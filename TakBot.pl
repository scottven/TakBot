#!/usr/bin/perl
use warnings FATAL => qw(all);
use strict;

# Longer-term FIXME: handle waiting and reconnecting to the
#                    playtak server if it goes down
use IO::Select;
use Getopt::Long;
use LWP::Simple;
use URI::Escape;
use JSON;
use Carp::Always;
use IPC::Open2;
use threads;
use PTNUtils qw(ptn_to_playtak playtak_to_ptn);
use TakBotSocket;

# FIXME: get this from the command line
#        but the password from a file.
my $playtak_passwd = "";
my $playtak_user   = "TakBot";
my $playtak_host   = "playtak.com";
my $playtak_port   = 10000;
my $user_re = '[a-zA-Z][a-zA-Z0-9_]{3,15}';
my $owner_name = 'scottven';

my @known_ais = ('rtak', 'george', 'flatimir');
my $default_ai = 'rtak';
my $rtak_ai_base_url = 'http://192.168.100.154:8084/TakService/TakMoveService.svc/GetMove?';
my $torch_ai_path = '/home/takbot/tak-ai';
my $color_enabled = 0;

sub open_connection($;$$);
sub dispatch_control($$);
sub dispatch_game($$);
sub parse_control_shout($$$);
sub parse_game_shout($$$);
sub get_move_from_ai($);
sub handle_move_from_ai($$);
sub undo_move($);
sub add_move($$);

# global object for doing non-blocking network IO
my $selector = IO::Select->new();

# map of users to their outstanding "Seeks"
my %seek_table;

my @orig_command_line = ($0, @ARGV);
my $debug;
my $fork = 1; #not sure it will work w/o forking anymore
GetOptions('debug=s' => \$debug,
           'password=s' => \$playtak_passwd,
	   'fork!' => \$fork,
	  );
if(!defined $playtak_passwd) {
	die 'password is required';
}
our $debug_wire;
our $debug_ptn;
our $debug_ai;
our $debug_torch;
our $debug_rtak;
our $debug_undo;
if(defined $debug && ($debug =~ m/wire/ || $debug eq 'all' || $debug eq '1')) {
	$debug_wire = 1;
}
if(defined $debug && ($debug =~ m/ptn/  || $debug eq 'all' || $debug eq '1')) {
	$debug_ptn = 1;
	$debug_undo = 1;
}
if(defined $debug && ($debug =~ m/undo/)) {
	$debug_undo = 1;
}
if(defined $debug && ($debug =~ m/ai/  || $debug eq 'all' || $debug eq '1')) {
	$debug_ai = 1;
	$debug_torch = 1;
	$debug_rtak = 1;
}
if(defined $debug && ($debug =~ m/torch/)) {
	$debug_torch = 1;
}
if(defined $debug && ($debug =~ m/rtak/)) {
	$debug_torch = 1;
}
open_connection('control');

my $ai_name_re = join('|', @known_ais);

# don't want to leave zombies
if($fork) {
	$SIG{CHLD} = 'IGNORE';
}

#wait loop
while(1) {
	my($readers, $writers, $errors) = IO::Select::select($selector, undef, $selector, 30);
	foreach my $sock (@$errors) {
		#do something sensible
	}
	foreach my $sock (@$readers) {
		my $command = $sock->get_line();
		next if !defined $command;
		my $name = $sock->name();
		if($name eq 'control') {
			dispatch_control($command, $sock);
		} elsif($name =~ m/ai_/) {
			handle_move_from_ai($command, $sock);
		} else {
			dispatch_game($command, $sock);
		}
	}
	my $now = time();
	foreach my $sock ($selector->handles()) {
		next if $sock->name() =~ m/ai_/; #don't ping the AI socket
		if($now - $sock->last_time() >= 30) {
			$sock->send_line("PING\n");
		}
	}
}

sub dispatch_control($$) {
	my $line = shift;
	my $sock = shift;
	chomp $line;
	if($line =~ m/^Welcome!/) {
		$sock->send_line("Client TakBot control alpha test\n");
	} elsif($line =~ m/^Login or Register/) {
		$sock->send_line("Login $playtak_user $playtak_passwd\n");
	} elsif($line =~ m/^Welcome $playtak_user!/o) {
		#nop for control
	} elsif($line =~ m/^Online/) {
		#nop for control
	} elsif($line =~ m/^Seek new (\d+) ($user_re)/o) {
		# map user to seek number
		$seek_table{$2} = $1;
	} elsif($line =~ m/^Seek remove (\d+) ($user_re)/o) {
		delete $seek_table{$2}
	} elsif($line =~ m/^Game/) {
		#nop for control
	} elsif($line =~ m/^Shout(?: <IRC>)? <($user_re)> (.*)/o) {
		parse_control_shout($sock, $1, $2);
	} elsif($line =~ m/^OK/) {
		#nop for control
	} elsif($line =~ m/^NOK/) {
		warn "NOK from " . $sock->last_line();
	} elsif($line =~ m/^Message /) {
		warn $line;
	} elsif($line =~ m/^Error /) {
		warn "Error from " . $sock->last_line();
	} else {
		warn "unsupported control message: $line";
	}
}

sub dispatch_game($$) {
	my $line = shift;
	my $sock = shift;
	my $game_no = $sock->name();
	chomp $line;
	if($line =~ m/^Welcome!/) {
		$sock->send_line("Client TakBot game alpha test\n");
	} elsif($line =~ m/^Login or Register/) {
		$sock->send_line("Login Guest\n");
	} elsif($line =~ m/^Welcome Guest[0-9]+!/o) {
		$sock->send_line("Accept $game_no\n");
	} elsif($line =~ m/^Game#$game_no Time/) {
		#nop for bots, at least for now
	} elsif($line =~ m/^Game#$game_no ([PM] .*)/) {
		my $ptn = playtak_to_ptn($1);
		add_move($sock, $ptn);
		get_move_from_ai($sock);
	} elsif($line =~ m/^Game#$game_no (Over|Abandoned)/) {
		$sock->drop_connection($selector);
	} elsif($line =~ m/^Game#$game_no RequestUndo/) {
		#send_line($sock, "Game#$game_no RequestUndo\n");
	} elsif($line =~ m/^Game#$game_no Undo/) {
		#undo_move($sock);
		#send_line($sock, "Game#$game_no RequestUndo\n");
	} elsif($line =~ m/^Game#$game_no OfferDraw/) {
		#accept all offers for draws
		$sock->send_line("Game#$game_no OfferDraw\n");
		if($color_enabled && $sock->ai() eq 'george') {
			$sock->send_line("Shout A tied game... Oh myyyy.\n");
		}
	} elsif($line =~ m/^Online/) {
		#nop for game
	} elsif($line =~ m/^Seek new (\d+) ($user_re)/o) {
		#nop for game
	} elsif($line =~ m/^Seek remove (\d+) ($user_re)/o) {
		#nop for game
	} elsif($line =~ m/^GameList/) {
		#nop for game
	} elsif($line =~ m/^Game Start ([0-9]+) ([0-9]+) $user_re vs $user_re (white|black)/) {
		$sock->name($1);
		$sock->ptn("[Size \"$2\"]\n");
		if($3 eq 'white') {
			get_move_from_ai($sock);
		}
	} elsif($line =~ m/^Shout(?: <IRC>)? <($user_re)> (.*)/o) {
		# use this to change AI settings
		parse_game_shout($sock, $1, $2);
	} elsif($line =~ m/^OK/) {
		#nop for game
	} elsif($line =~ m/^NOK/) {
		warn "NOK from " . $sock->last_line();
	} elsif($line =~ m/^Message /) {
		warn $line;
	} elsif($line =~ m/^Error /) {
		warn "Error from " . $sock->last_line();
	} else {
		warn "unsupported game message: $line";
	}
}

sub parse_game_shout($$$) {
	my $sock = shift;
	my $user = shift;
	my $line = shift;

	# FIXME: limit this to the opponent
	if($line =~ m/^takbot:\s*ai\s*($ai_name_re)/oi) {
		$sock->ai($1);
	}
}

sub parse_control_shout($$$) {
	my $sock = shift;
	my $user = shift;
	my $line = shift;

	my $owner_cmd = $user eq $owner_name;

	if($owner_cmd && $line =~ m/^TakBot: fight ($user_re)\s*($ai_name_re)?/o) {
		if(exists $seek_table{$1}) {
			$sock->send_line("Shout $user: OK, joining $1's game.\n");
			open_connection($seek_table{$1}, $sock, $2);
		} else {
			$sock->send_line("Shout $user: Sorry, I don't see a game from $1.\n");
		}
	} elsif($owner_cmd && $line =~ m/^TakBot: reboot$/) {
		$sock->send_line("Shout $user: Aye, aye.  Brb!\n");
		exec { $orig_command_line[0] }  @orig_command_line;
	} elsif($owner_cmd && $line =~ m/^TakBot: (no )?talk$/) {
		if(defined $1 && $1 eq 'no ') {
			$color_enabled = 0;
		} else {
			$color_enabled = 1;
		}
	} elsif($owner_cmd && $line =~ m/^TakBot: shutdown$/) {
		$sock->send_line("Shout Goodbye.\n");
		$sock->send_line("quit\n");
		exit(0);
	} elsif($line =~ m/^TakBot:?\s*play\s*($ai_name_re)?/oi) {
		#$sock->send_line("Shout Hi, $user!  I'm looking for your game now\n");
		if(exists $seek_table{$user}) {
			$sock->send_line("Shout $user: OK, joining your game.\n");
			open_connection($seek_table{$user}, $sock, $1);
		} else {
			$sock->send_line("Shout $user: Sorry, I don't see a game to join from you.  Please create a game first.\n");
		}
	} elsif($line =~ m/^TakBot:\s*help/i) {
		$sock->send_line("Shout $user: For instructions see https://github.com/scottven/TakBot/blob/master/README.md\n");
	} elsif($line =~m/^TakBot:\s*list/i) {
		$sock->send_line("Shout The AIs that I currently can use are: " . join(", ", @known_ais) . "\n");
	}
}


sub open_connection($;$$) {
	my $name = shift;
	my $control_sock = shift;
	my $ai_selection = shift;

	if($fork && $name ne 'control') {
		my $pid = fork();
		if(!defined $pid) {
			die "fork failed: $!";
		} elsif($pid == 0) {
			$control_sock->close();
		} else {
			#parent
			return;
		}
	}

	my $sock = new TakBotSocket(PeerHost => $playtak_host,
	                              PeerPort => $playtak_port,
				      Proto    => 'tcp');
	$sock->name($name);
	$sock->last_time(time());
	$sock->blocking(undef);
	if(defined $ai_selection) {
		$sock->ai($ai_selection);
	} else {
		$sock->ai($default_ai);
	}
	$selector->add($sock);
	return $sock;
}

sub get_move_from_rtak($$) {
	my $ptn = shift;
	my $writer = shift;
	my $query = $rtak_ai_base_url . "code=" . uri_escape($ptn);
	print "Query: $query\n" if $debug_rtak;
	my $ret = get($query);
	if(!defined $ret) {
		return undef;
	}
	print "Returned $ret\n" if $debug_rtak;
	my $move = decode_json($ret)->{d};
	print "Move is $move\n" if $debug_rtak;
	$writer->send_line("$move\n");
	$writer->close();
}

sub get_move_from_torch_ai($$$) {
	my $ai_name = shift;
	my $ptn = shift;
	my $writer = shift;
	chdir $torch_ai_path;
	my $script = $torch_ai_path . "/takbot_${ai_name}.lua";
	print "calling $script with th\n" if $debug_torch;
	my ($ai_reader, $ai_writer);
	my $ai_pid = open2($ai_reader, $ai_writer, "th $script");
	print $ai_writer $ptn;
	close $ai_writer;
	my @ai_return = <$ai_reader>;
	print "AI returned: @ai_return" if $debug_torch;
	my $move = $ai_return[-2];
	print "move line is $move" if $debug_torch;
	chomp $move;
	$move =~ s/.*move: ([^,]+),.*$/$1/;
	$move = ucfirst $move;
	print "Move finally is $move\n" if $debug_torch;
	$writer->send_line("$move\n");
	$writer->close();
}

sub get_move_from_ai($) {
	my $sock = shift;
	my $game_no = $sock->name();
	my $ptn = $sock->ptn();
	my ($reader, $writer) = TakBotSocket->socketpair(AF_UNIX, SOCK_STREAM, PF_UNSPEC);
	print "sockets are $sock, $reader, and $writer\n" if $debug_ai;
	$reader->name("ai_$game_no");
	$reader->blocking(undef);
	$reader->connection($sock);
	my $thr;
	if($sock->ai() eq 'rtak') {
		$thr = threads->create(\&get_move_from_rtak, $ptn, $writer);
	} elsif($sock->ai() eq 'george') {
		$thr = threads->create(\&get_move_from_torch_ai, 'george', $ptn, $writer);
	} elsif($sock->ai() eq 'flatimir') {
		$thr = threads->create(\&get_move_from_torch_ai, 'flatimir', $ptn, $writer);
	}
	$thr->detach();
	$selector->add($reader);
	print "$game_no AI request queued.\n" if $debug_ai;
}

sub handle_move_from_ai($$) {
	my $move = shift;
	my $reader = shift;
	print "handling reply for " . $reader->name() . "\n" if $debug_ai;
	my $sock = $reader->connection();
	my $game_no = $sock->name();
	chomp $move;
	print "read $move from $reader for $sock\n" if $debug_ai;
	if(!defined $move || $move eq '') {
		$sock->send_line("Shout Sorry, the AI encountered an error.  I surrender.\n");
		$sock->send_line("Game#$game_no Resign\n");
		return;
	}
	print "got $move for $game_no from ai\n" if $debug_ai;
	add_move($sock, $move);
	$move = ptn_to_playtak($move);
	$sock->send_line("Game#$game_no $move\n");
	$selector->remove($reader);
	$reader->close();
}

sub undo_move($) {
	my $sock = shift;
	my $old_ptn = $sock->ptn();
	print "undoing $old_ptn\n" if $debug_undo;
	my @ptn_lines = split(/\n/, $old_ptn);
	if($ptn_lines[-1] =~ m/^\s*([0-9]+)\.\s+([SFC1-8a-h<>+-]+)\s([FSC1-8a-h><+-]+)?/) {
		my $turn = $1;
		my $white_move = $2;
		my $black_move = $3;
		if(!defined $black_move) {
			$sock->ptn(join("\n", @ptn_lines[0 ... $#ptn_lines-1]));
		} else {
			$ptn_lines[-1] = $turn . ".\t$white_move\t";
			$sock->ptn(join("\n", @ptn_lines));
		}
	} else {
		#no moves, so nothing to undo
	}
	print "ended up with " . $sock->ptn() . "\n" if $debug_undo;
}


sub add_move($$) {
	my $sock = shift;
	my $new_move = shift;
	my $old_ptn = $sock->ptn();
	#we only need the last line
	my $last_line = $old_ptn;
	chomp $last_line;
	$last_line =~ s/.*\n//s;
	print "last line: $last_line\n" if $debug_ptn;
	if($last_line =~ m/^\s*([0-9]+)\.\s+([FSC1-8a-h<>+-]+)\s([FSC1-8a-h><+-]+)?/) {
		my $turn = $1;
		my $white_move = $2;
		my $black_move = $3;
		if(!defined $black_move) {
			$sock->ptn($old_ptn . $new_move . "\n");
		} else {
			print "turn is $turn\n" if $debug_ptn;
			$sock->ptn($old_ptn . ($turn+1) . ".\t$new_move\t");
		}
	} else {
		#first turn
		$sock->ptn($old_ptn . "1.\t$new_move\t");
	}
}


