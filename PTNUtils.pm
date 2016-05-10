package PTNUtils;
use Exporter 'import';
use warnings;
use strict;
our @EXPORT_OK = qw(ptn_to_playtak playtak_to_ptn);

my %letter_values = ( a => 1, b => 2, c => 3, d => 4,
               e => 5, f => 6, g => 7, h => 8 );
my @letters = ( '', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h');

sub letter_add($$) {
	my $letter = shift;
	my $count = shift;
	print "letter_add($letter, $count): $letter_values{$letter}, $letters[$count]\n" if $main::debug{ptn};
	return $letters[$letter_values{$letter}+$count];
}

sub letter_sub($$) {
	my $letter = shift;
	my $count = shift;
	print "letter_sub($letter, $count): $letter_values{$letter}, $letters[$count]\n" if $main::debug{ptn};
	return $letters[$letter_values{$letter}-$count];
}

sub ptn_to_playtak($) {
	my $ptn = shift;
	if($ptn =~ m/^([FCS]?)([a-h][1-8])$/i) {
		#It's a place
		my $ret = 'P ' . uc $2;
		if($1 eq 'C') {
			$ret .= ' C';
		} elsif($1 eq 'S') {
			$ret .= ' W';
		}
		print "ptn_to_playtak($ptn) -> $ret\n" if $main::debug{ptn};
		return $ret;
	} elsif($ptn =~ m/^([1-8]?)([a-h])([1-8])([-+<>])([1-8]*)$/) {
		#It's a move
		my $num_lifted = $1;
		my $file = $2;
		my $row = $3;
		my $direction = $4;
		my @drops = split(//, $5);
		if($num_lifted eq '') {
			$num_lifted = 1;
		}
		if(scalar(@drops) == 0) {
			$drops[0] = $num_lifted;
		}
		print "drops is :" . join(", ", @drops) . ":\n" if $main::debug{ptn};
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
		print "ptn_to_playtak($ptn) -> $ret\n" if $main::debug{ptn};
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
			$ret = 'F' . $ret; #Alphatak's torch AI requires the F
		}
		print "playtak_to_ptn($playtak) -> $ret\n" if $main::debug{ptn};
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
		print "playtak_to_ptn($playtak) -> $ptn\n" if $main::debug{ptn};
		return $ptn;
	} else {
		die "unknown playtak opcode in $playtak";
	}
}

1;
