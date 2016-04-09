#!/usr/bin/perl
use warnings FATAL => qw(all);
use strict;

# Longer-term FIXME: handle waiting and reconnecting to the
#                    playtak server if it goes down
use IO::Select;
use Getopt::Long;

# FIXME: get this from the command line
#        but the password from a file.
my $playtak_passwd = "";
my $playtak_user   = "TakBot";
my $playtak_host   = "playtak.com";
my $playtak_port   = 10000;
my $user_re = '[a-zA-Z][a-zA-Z0-9_]{3,15}';

sub open_connection($$);
sub get_line($);
sub send_line($$);
sub dispatch_control($$);
sub parse_shout($$$);
sub ptn_to_playtak($);
sub playtak_to_ptn($);

# global object for doing non-blocking network IO
my $selector = IO::Select->new();

# map of users to their outstanding "Seeks"
my %seek_table;

my $debug;
GetOptions('debug=s' => \$debug,
           'password=s' => \$playtak_passwd,
	  );
if(!defined $playtak_passwd) {
	die 'password is required';
}
my $debug_wire;
my $debug_ptn;
if(defined $debug && ($debug =~ m/wire/ || $debug eq 'all' || $debug == 1)) {
	$debug_wire = 1;
}
if(defined $debug && ($debug =~ m/ptn/  || $debug eq 'all' || $debug == 1)) {
	$debug_ptn = 1;
}

my $control_channel = open_connection($selector, 'control');

#wait loop
while(1) {
	my($readers, $writers, $errors) = IO::Select::select($selector, undef, $selector);
	foreach my $sock (@$errors) {
		#do something sensible
	}
	foreach my $sock (@$readers) {
		my $command = get_line($sock);
		if($sock == $control_channel) {
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
		send_line($sock, "Client TakBot alpha test\n");
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

sub parse_shout($$$) {
	my $sock = shift;
	my $user = shift;
	my $line = shift;

	if($line =~ m/^TakBot: ([^ ]+)/) {
		send_line($sock, "Shout Hi, $user!  I can't do anything useful yet, but just wait!\n");
	}
	#fall through
}

sub open_connection($$) {
	my $selector = shift;
	my $name = shift;

	my $sock = new TakBot::Socket(PeerHost => $playtak_host,
	                              PeerPort => $playtak_port,
				      Proto    => 'tcp');
	$sock->name($name);
	$sock->blocking(undef);
	$selector->add($sock);
	return $sock;
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

my %file_values = ( a => 1, b => 2, c => 3, d => 4,
               e => 5, f => 6, g => 7, h => 8 );
my @file_letters = ( '', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h');
sub letter_add($$) {
	my $letter = shift;
	my $count = shift;
	return $file_letters[$file_values{$letter}+$count];
}
sub letter_sub($$) {
	my $letter = shift;
	my $count = shift;
	return $file_letters[$file_values{$letter}-$count];
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
		my @drops = split(/./, $5);
		if(scalar(@drops) == 0) {
			$drops[0] = 1;
		}
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
		} else {
			die "invalid stone type $words[2] in $playtak";
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


package TakBot::Socket;
use parent 'IO::Socket::INET';

my %name_map;
my %last_lines;
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

1;
