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
my %waiting_map;
my %moves_map;

sub send_line($$) {
	my $self = shift;
	my $line = shift;
	if($self->syswrite($line) != length($line)) {
		my $msg = "failed to send $line to ";
		$msg .= $self->name();
		$msg .= ": $!";
	}
	print "SENT: $line" if $main::debug{wire};
	$self->last_line($line);
	$self->last_time(time());
}

sub get_line($) {
	my $self = shift;
	my $no_drop = shift;
	my $line;
	my $buf;
	my $rv;
	while($rv = $self->sysread($buf, 1)) {
		$line .= $buf;
		if($buf eq "\n") {
			last;
		}
	}
	if(!$no_drop && !defined $rv) {
		my $msg = "tried to read from a closed socket: ";
		$msg .= $self->name();
		$msg .= ": $!";
		die $msg;
	}
	if(!$no_drop && $rv == 0) {
		print "dropping " . $self->name() . "\n" if $main::debug{wire};
		$self->drop_connection();
		return undef;
	}
	print "GOT: $line" if $main::debug{wire} && defined $line;
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
		print "quitting " . $self->name() . "\n" if $main::debug{ai};
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

sub waiting($;$) {
	my $self = shift;
	my $waiting = shift;
	if(defined $waiting) {
		$waiting_map{$self} = $waiting;
	}
	return $waiting_map{$self};
}

sub moves($;$) {
	my $self = shift;
	my $moves = shift;
	if(defined $moves) {
		$moves_map{$self} = $moves;
	}
	return $moves_map{$self};
}

sub ai($$) {
	my $self = shift;
	my $ai = shift;
	if(defined $ai) {
		my $new_ai = lc $ai;
		if($new_ai eq 'rtak') {
			$self->send_line("Shout RTak by Shlkt\n") if $main::color_enabled;
		} elsif($new_ai eq 'george') {
			$self->send_line("Shout George TakAI by alphatak\n") if $main::color_enabled;
		} elsif($new_ai eq 'flatimir') {
			$self->send_line("Shout Flatimir by alphatak\n") if $main::color_enabled;
		} elsif($new_ai eq 'joe') {
			$self->send_line("Shout Average Joe by alphatak, Shlkt, and scottven\n") if $main::color_enabled;
		} else {
			$self->send_line("Shout I don't know about the $new_ai AI.\n");
			return undef;
		}
		$ai_map{$self} = $new_ai;
	}
	return $ai_map{$self};
}

1;
