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

# FIXME: get this from the command line
#        but the password from a file.
my $playtak_passwd = "";
my $playtak_user   = "TakBot";
my $playtak_host   = "playtak.com";
my $playtak_port   = 10000;
my $user_re = '[a-zA-Z][a-zA-Z0-9_]{3,15}';

my $ai_base_url = 'http://takservice.azurewebsites.net/TakMoveService.svc/GetMove?';

sub open_connection($$;$);
sub drop_connection($);
sub get_line($);
sub send_line($$);
sub dispatch_control($$);
sub dispatch_game($$);
sub parse_shout($$$);
sub ptn_to_playtak($);
sub playtak_to_ptn($);
sub get_move_from_ai($);
sub add_move($$);

# global object for doing non-blocking network IO
my $selector = IO::Select->new();

# map of users to their outstanding "Seeks"
my %seek_table;

my $debug;
my $fork;
GetOptions('debug=s' => \$debug,
           'password=s' => \$playtak_passwd,
	   'fork' => \$fork,
	  );
if(!defined $playtak_passwd) {
	die 'password is required';
}
my $debug_wire;
my $debug_ptn;
my $debug_ai;
if(defined $debug && ($debug =~ m/wire/ || $debug eq 'all' || $debug eq '1')) {
	$debug_wire = 1;
}
if(defined $debug && ($debug =~ m/ptn/  || $debug eq 'all' || $debug eq '1')) {
	$debug_ptn = 1;
}
if(defined $debug && ($debug =~ m/ai/  || $debug eq 'all' || $debug eq '1')) {
	$debug_ai = 1;
}
open_connection($selector, 'control');

my %letter_values = ( a => 1, b => 2, c => 3, d => 4,
               e => 5, f => 6, g => 7, h => 8 );
my @letters = ( '', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h');

# don't want to leave zombies
if($fork) {
	$SIG{CHLD} = 'IGNORE';
}

#wait loop
#FIXME: This doesn't handle sending Pings.
while(1) {
	my($readers, $writers, $errors) = IO::Select::select($selector, undef, $selector);
	foreach my $sock (@$errors) {
		#do something sensible
	}
	foreach my $sock (@$readers) {
		my $command = get_line($sock);
		if($sock->name() eq 'control') {
			dispatch_control($command, $sock);
		} else {
			dispatch_game($command, $sock);
		}
	}
}

sub dispatch_control($$) {
	my $line = shift;
	my $sock = shift;
	chomp $line;
	if($line =~ m/^Welcome!/) {
		send_line($sock, "Client TakBot control alpha test\n");
	} elsif($line =~ m/^Login or Register/) {
		send_line($sock, "Login $playtak_user $playtak_passwd\n");
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
		parse_shout($sock, $1, $2);
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
		send_line($sock, "Client TakBot game alpha test\n");
	} elsif($line =~ m/^Login or Register/) {
		send_line($sock, "Login Guest\n");
	} elsif($line =~ m/^Welcome Guest[0-9]+!/o) {
		send_line($sock, "Accept $game_no\n");
	} elsif($line =~ m/^Game#$game_no Time/) {
		#nop for bots, at least for now
	} elsif($line =~ m/^Game#$game_no ([PM] .*)/) {
		my $ptn = playtak_to_ptn($1);
		add_move($sock, $ptn);
		get_move_from_ai($sock);
	} elsif($line =~ m/^Game#$game_no (Over|Abandoned)/) {
		drop_connection($sock);
	} elsif($line =~ m/^Game#$game_no OfferDraw/) {
		#accept all offers for draws
		send_line($sock, "Game#$game_no OfferDraw\n");
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
		$sock->ptn("[Size \"$2x$2\"]\n");
		if($3 eq 'white') {
			get_move_from_ai($sock);
		}
	} elsif($line =~ m/^Shout(?: <IRC>)? <($user_re)> (.*)/o) {
		#I think this is nop for game too...
		#parse_shout($sock, $1, $2);
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

sub parse_shout($$$) {
	my $sock = shift;
	my $user = shift;
	my $line = shift;

	if($line =~ m/^TakBot: play/) {
		#send_line($sock, "Shout Hi, $user!  I'm looking for your game now\n");
		if(exists $seek_table{$user}) {
			send_line($sock, "Shout $user: OK, joining your game.\n");
			open_connection($selector, $seek_table{$user}, $sock);
		} else {
			send_line($sock, "Shout $user: Sorry, I don't see a game to join from you.  Please create a game first.\n");
		}
	}
	#fall through
}


sub open_connection($$;$) {
	my $selector = shift;
	my $name = shift;
	my $control_sock = shift;

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

	my $sock = new TakBot::Socket(PeerHost => $playtak_host,
	                              PeerPort => $playtak_port,
				      Proto    => 'tcp');
	$sock->name($name);
	$sock->blocking(undef);
	$selector->add($sock);
	return $sock;
}

sub drop_connection($) {
	my $sock = shift;
	$selector->remove($sock);
	$sock->close();
	if($fork) {
		exit 0;
	}
}

sub get_line($) {
	my $sock = shift;
	my $line;
	my $buf;
	my $rv;
	while($rv = $sock->sysread($buf, 1)) {
		$line .= $buf;
		if($buf eq "\n") {
			last;
		}
	}
	if(!defined $rv) {
		my $msg = "tried to read from a closed socket: ";
		$msg .= $sock->name();
		$msg .= ": $!";
		die $msg;
	}
	print "GOT: $line" if $debug_wire;
	return $line;
}

sub send_line($$) {
	my $sock = shift;
	my $line = shift;
	if($sock->syswrite($line) != length($line)) {
		my $msg = "failed to send $line to ";
		$msg .= $sock->name();
		$msg .= ": $!";
	}
	print "SENT: $line" if $debug_wire;
	$sock->last_line($line);
}

sub letter_add($$) {
	my $letter = shift;
	my $count = shift;
	print "letter_add($letter, $count): $letter_values{$letter}, $letters[$count]\n" if $debug_ptn;
	return $letters[$letter_values{$letter}+$count];
}
sub letter_sub($$) {
	my $letter = shift;
	my $count = shift;
	print "letter_sub($letter, $count): $letter_values{$letter}, $letters[$count]\n" if $debug_ptn;
	return $letters[$letter_values{$letter}-$count];
}

sub ptn_to_playtak($) {
	my $ptn = shift;
	if($ptn =~ m/^([FCS]?)([a-h][1-8])$/) {
		#It's a place
		my $ret = 'P ' . uc $2;
		if($1 eq 'C') {
			$ret .= ' C';
		} elsif($1 eq 'S') {
			$ret .= ' W';
		}
		print "ptn_to_playtak($ptn) -> $ret\n" if $debug_ptn;
		return $ret;
	} elsif($ptn =~ m/^([1-8]?)([a-h])([1-8])([-+<>])([1-8]*)$/) {
		#It's a move
		my $num_lifted = $1;
		my $file = $2;
		my $row = $3;
		my $direction = $4;
		my @drops = split(//, $5);
		if(scalar(@drops) == 0) {
			$drops[0] = 1;
		}
		print "drops is :" . join(", ", @drops) . ":\n" if $debug_ptn;
		my $ret = 'M '. uc($file) . $row . ' ';
		if($direction eq '+') {
			$ret .= uc($file) . ($row + scalar(@drops));
		} elsif($direction eq '-') {
			$ret .= uc($file) . ($row - scalar(@drops));
		} elsif($direction eq '>') {
			$ret .= uc(letter_add($file, scalar(@drops))) . $row;
		} elsif($direction eq '<') {
			$ret .= uc(letter_sub($file, scalar(@drops))) . $row;
		} else {
			die "unexpected direction $direction in PTN $ptn";
		}
		foreach my $drop (@drops) {
			$ret .= " $drop";
		}
		print "ptn_to_playtak($ptn) -> $ret\n" if $debug_ptn;
		return $ret;
	} else {
		die "unmatched PTN $ptn";
	}
}

sub playtak_to_ptn($) {
	my $playtak = shift;
	my @words = split(/ /, $playtak);
	if($words[0] eq 'P') {
		# It's a place
		my $ret = lc $words[1];
		if(defined $words[2] && $words[2] eq 'W') {
			$ret = 'S' . $ret;
		} elsif(defined $words[2] && $words[2] eq 'C') {
			$ret = 'C' . $ret;
		}
		print "playtak_to_ptn($playtak) -> $ret\n" if $debug_ptn;
		return $ret;
	} elsif($words[0] eq 'M') {
		# It's a move
		shift @words; #dump to M
		my $start = shift @words;
		my $end = shift @words;
		my $direction;
		#all remaining words are drop counts
		my ($start_file, $start_row) = split(//, $start);
		my ($end_file, $end_row) = split(//, $end);
		if($start_file eq $end_file && $start_row == $end_row) {
			die "can't start and end in the same place: $playtak";
		}
		if($start_file ne $end_file && $start_row != $end_row) {
			die "can't move diagonally: $playtak";
		}
		my $cmp;
		if($cmp = $start_row <=> $end_row) {
			if($cmp > 0) {
				$direction = '-';
			} else {
				$direction = '+';
			}
		} elsif($cmp = $start_file cmp $end_file) {
			if($cmp > 0) {
				$direction = '<';
			} else {
				$direction = '>';
			}
		}
		my $liftsize = 0;
		my $drop_string = '';
		foreach my $drop(@words) {
			$liftsize += $drop;
			$drop_string .= $drop;
		}
		my $ptn = $liftsize . lc($start) . $direction . $drop_string;
		print "playtak_to_ptn($playtak) -> $ptn\n" if $debug_ptn;
		return $ptn;
	} else {
		die "unknown playtak opcode in $playtak";
	}
}

sub get_move_from_ai($) {
	my $sock = shift;
	my $query = $ai_base_url . "code=" . uri_escape($sock->ptn());
	print "Query: $query\n" if $debug_ai;
	my $ret = get($query);
	print "Returned $ret\n" if $debug_ai;
	my $move = decode_json($ret)->{d};
	print "Move is $move\n" if $debug_ai;
	add_move($sock, $move);
	$move = ptn_to_playtak($move);
	my $game_no = $sock->name();
	send_line($sock, "Game#$game_no $move\n");
}

sub add_move($$) {
	my $sock = shift;
	my $new_move = shift;
	my $old_ptn = $sock->ptn();
	#we only need the last line
	my $last_line = $old_ptn;
	chomp $last_line;
	$last_line =~ s/.*\n//s;
	print "last line: $last_line" if $debug_ptn;
	if($last_line =~ m/^\s*([0-9]+)\.\s+([1-8a-h<>+-]+)\s([1-8a-h><+-]+)?/) {
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

package TakBot::Socket;
use parent 'IO::Socket::INET';

my %name_map;
my %last_lines;
my %ptn_map;
#my %move_count;

sub name($;$) {
	my $self = shift;
	my $name = shift;
	if(defined $name) {
		$name_map{$self} = $name;
	}
	return $name_map{$self};
}

sub last_line($;$) {
	my $self = shift;
	my $line = shift;
	if(defined $line) {
		$last_lines{$self} = $line;
	}
	return $last_lines{$self};
}

sub ptn($;$) {
	my $self = shift;
	my $ptn = shift;
	if(defined $ptn) {
		$ptn_map{$self} = $ptn;
	}
	return $ptn_map{$self};
}

#sub move_count($;$) {
#	my $self = shift;
#	my $incr = shift;
#	if(!exists $move_count{$self}) {
#		$move_count{$self} = 0;
#	}
#	if(defined $incr) {
#		$move_count{$self}++;
#	}
#	return $move_count{$self};
#}
1;
