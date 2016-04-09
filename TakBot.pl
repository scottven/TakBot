#!/usr/bin/perl
use warnings FATAL => qw(all);
use strict;

# Longer-term FIXME: handle waiting and reconnecting to the
#                    playtak server if it goes down
use IO::Select;
use IO::Socket::INET;
use Getopt::Long;

# FIXME: get this from the command line
#        but the password from a file.
my $playtak_passwd = "";
my $playtak_user   = "TakBot";
my $playtak_host   = "playtak.com";
my $playtak_port   = 10000;
my $user_re = '[a-zA-Z][a-zA-Z0-9_]{3,15}';

sub open_connection($);
sub get_line($);
sub send_line($$);
sub dispatch_control($$);
sub parse_shout($$$);

# global object for doing non-blocking network IO
my $selector = IO::Select->new();

# map of IO::Socket objects to their purpose
my %fd_map;
# map of IO::Socket objects to the last line we sent into them
# useful for debugging NOKs
my %last_line; 

# map of users to their outstanding "Seeks"
my %seek_table;

my $debug;
GetOptions("debug" => \$debug,
           "password=s" => \$playtak_passwd,
	  );

my $control_channel = open_connection($selector);
$fd_map{$control_channel} = 'control';

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
		warn "NOK from $last_line{$sock}";
	} elsif($line =~ m/^Message /) {
		warn $line;
	} elsif($line =~ m/^Error /) {
		warn "Error from $last_line{$sock}";
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

sub open_connection($) {
	my $selector = shift;

	my $sock = new IO::Socket::INET(PeerHost => $playtak_host,
	                                PeerPort => $playtak_port,
					Proto    => 'tcp');
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
		die "tried to read from a closed socket: $fd_map{$sock}: $!";
	}
	print "GOT: $line" if $debug;
	return $line;
}

sub send_line($$) {
	my $sock = shift;
	my $line = shift;
	if($sock->syswrite($line) != length($line)) {
		die "failed to send $line to $fd_map{$sock}: $!";
	}
	print "SENT: $line" if $debug;
	$last_line{$sock} = $line;
}

