package TakBotSocket;
use warnings;
use strict;
use parent 'IO::Socket::INET';

my %name_map;
my %last_lines;
my %last_times;
my %ptn_map;
my %ai_map;
my %connection_map;

sub send_line($$) {
	my $self = shift;
	my $line = shift;
	if($self->syswrite($line) != length($line)) {
		my $msg = "failed to send $line to ";
		$msg .= $self->name();
		$msg .= ": $!";
	}
	print "SENT: $line" if $main::debug_wire;
	$self->last_line($line);
	$self->last_time(time());
}

sub get_line($) {
	my $self = shift;
	my $line;
	my $buf;
	my $rv;
	while($rv = $self->sysread($buf, 1)) {
		$line .= $buf;
		if($buf eq "\n") {
			last;
		}
	}
	if(!defined $rv) {
		my $msg = "tried to read from a closed socket: ";
		$msg .= $self->name();
		$msg .= ": $!";
		die $msg;
	}
	if($rv == 0) {
		print "dropping $self\n" if $main::debug_wire;
		$self->drop_connection();
		return undef;
	}
	print "GOT: $line" if $main::debug_wire;
	return $line;
}

sub drop_connection($$) {
	my $self = shift;
	my $selector = shift;
	if($self->name() eq 'control') {
		die "uh oh, dropping the control conneciton";
	}
	$self->send_line("quit\n");
	$selector->remove($self);
	$self->close();
	if($main::fork) {
		exit 0;
	}
}

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

sub last_time($;$) {
	my $self = shift;
	my $time = shift;
	if(defined $time) {
		$last_times{$self} = $time;
	}
	return $last_times{$self};
}

sub ptn($;$) {
	my $self = shift;
	my $ptn = shift;
	if(defined $ptn) {
		$ptn_map{$self} = $ptn;
	}
	return $ptn_map{$self};
}

sub connection($;$) {
	my $self = shift;
	my $connection = shift;
	if(defined $connection) {
		$connection_map{$self} = $connection;
	}
	return $connection_map{$self};
}

sub ai($$) {
	my $self = shift;
	my $ai = shift;
	if(defined $ai) {
		my $new_ai = lc $ai;
		if($new_ai eq 'rtak') {
			&main::send_line($self, "Shout RTak by Shlkt\n") if $main::color_enabled;
		} elsif($new_ai eq 'george') {
			&main::send_line($self, "Shout George TakAI by alphatak\n") if $main::color_enabled;
		} elsif($new_ai eq 'flatimir') {
			&main::send_line($self, "Shout Flatimir by alphatak\n") if $main::color_enabled;
		} else {
			&main::send_line($self, "Shout I don't know about the $new_ai AI.\n");
			return undef;
		}
		$ai_map{$self} = $new_ai;
	}
	return $ai_map{$self};
}

1;
