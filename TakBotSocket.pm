package TakBotSocket;
use warnings;
use strict;
use parent 'IO::Socket::INET';

my %name_map;
my %last_lines;
my %last_times;
my %ptn_map;
my %ai_map;

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
