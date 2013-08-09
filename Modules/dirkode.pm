=head1 NAME

dirkode - Encoding module solely to fit my own purpose.

=head1 VERSION HISTORY

version 1.0 - 7 April 2007 DV

=over 4

=item *

Initial Release

=back

=head1 SYNOPSIS

 use dirkode;

=head1 DESCRIPTION

This module accepts a string, reads all characters and tries to convert from UTF-8 to Latin1, mainly to serve Dutch language and Plucker viewer.

=cut

########
# Module
########

package dirkode;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(showChar extractWord tx2latin);

###########
# Variables
###########

my %utf2latin = (
	"\xc2\xa1" => "\xa1",	# inverted exclamation mark 
	"\xc2\xab" => "\xab",	# « 
	"\xc2\xb2" => "\xb2",	# ² 
	"\xc2\xbb" => "\xbb",	# » 
	"\xc3\xa0" => "\xe0",	# à 
	"\xc3\xa1" => "\xe1",	# á 
	"\xc3\xa2" => "\xe2",	# â 
	"\xc3\xa4" => "\xe4",	# ä 
	"\xc3\xa7" => "\xe7",	# ç 
	"\xc3\xa8" => "\xe8",	# è 
	"\xc3\xa9" => "\xe9",	# é 
	"\xc3\xaa" => "\xea",	# ê 
	"\xc3\xab" => "\xeb",	# ë
	"\xc3\xad" => "\xed",	# í
	"\xc3\xaf" => "\xef",	# ï 
	"\xc3\xb2" => "\xf2",	# ò
	"\xc3\xb3" => "\xf3",	# ó 
	"\xc3\xb4" => "\xf4",	# ô 
	"\xc3\xb6" => "\xf6",	# ö 
	"\xc3\xb9" => "\xf9",	# ù 
	"\xc3\xba" => "\xfa",	# ú 
	"\xc3\xbc" => "\xfc",	# ü 
	"\xe2\x80\x93" => "\x2e", # Dash
	"\xe2\x80\x98" => "\x27", # Left angle quotes
	"\xe2\x80\x99" => "\x60", # Right angle quotes
	"\xe2\x80\x9c" => "\x22", # Double quotes
	"\xe2\x80\x9d" => "\x22", # Double quotes
);
my $noTx = "False";
my (@newarr, @wordarr, @specarr);

#####
# use
#####

use warnings;
use strict;
use Log;

#############
# subroutines
#############

=pod

=head2 showChar("string")

This procedure accepts a string, walks to all byte values of the string and tries to find characters that will be displayed ugly. Currently all characters with 8th bit on are suspicious characters. When a character is found, the word values will be displayed together with the high-bit character. This should help to set-up a conversion table.

=cut

sub showChar($) {
	my ($string) = @_;
	my @bytarr = unpack("C*", $string);
	while (my ($key, $value) = each %utf2latin) {
		print "$key: $value\n";
	}
	foreach my $charval (@bytarr) {
		if ($charval > 127) {
			print "Wide character: ".hex($charval)."\n";
		} else {
			print $charval;
		}
	}
}

sub handle_word {
	my $wordarr_length = @wordarr;
	if ($wordarr_length > 0) {
		my $word = pack ("C*", @wordarr);
		if ($noTx eq "True") {
			error("Word: ***$word*** contains unknown character.\n");
		}
	}
	undef @wordarr;
	$noTx = "False";
}


=pod

=head2 extractWord("string")

This procedure walks through a string and find all word boundaries, currently all spaces (Dec: 32), carriage returns and line feeds (Dec: 10 and 13). Each word - delimited by spaces - is presented as an entity for further processing.

=cut

sub extractWord($) {
	my ($string) = @_;
	my (@wordarr, @comparr);
	my @bytarr = unpack("C*", $string);
	while (my $charval = shift @bytarr) {
		if (($charval == 32) or ($charval == 10) or ($charval == 13)) {
			handle_word(@wordarr);
		} else {
			if ($charval > 127) {
				push @comparr, $charval;
				# Now handle for as long as there are special characters
				$charval = shift @bytarr;
				push @comparr, $charval;
				my $compstring = pack("C*",@comparr);
				if (defined $utf2latin{$compstring}) {
					my $replchar = unpack("C*",$utf2latin{$compstring});
					push @wordarr, $replchar;
				} else {
					$noTx = "True";
					# Unknown character, make sure original array is still availalbe (unpack $compstring)
					push @wordarr,@comparr;
				}
				undef @comparr;
			} else {
				push @wordarr, $charval;
			}
		}
	}
	# Handle last word
	handle_word(@wordarr);
}

=pod

=head2 Handle Translation

Translation found for special string. The translation will be added to the word and to the new string array. The special string will be cleared.

=cut

sub handle_tx($) {
	my ($specstr) = @_;
	# Translate character
	my $replchar = unpack("C*",$utf2latin{$specstr});
	# Add translated character to new string
	push @newarr, $replchar;
	# Add translation to word
	push @wordarr, $replchar;
	# Clear special string
	undef @specarr;
}

=pod

=head2 Handle Special string array

This procedure will handle the special string, by checking if a translation is available. If so, the translated character will be added to the new string array and to the word. Otherwise, the no translation flag will be set. The special string array will be cleared.

=cut

sub handle_specarr {
	# Special Array exists, handle it
	my $specstr = pack ("C*", @specarr);
	if (defined $utf2latin{$specstr}) {
		# This should never be the case, this situation must be handled
		# on the special character already.
		handle_tx($specstr);
	} else {
		# Byte array of special character found, no translation available.
		$noTx = "True";
		# Add array to new string
		push @newarr, @specarr;
		# Add array to word
		push @wordarr, @specarr;
		# Clear special string
		undef @specarr;
	}
}
=pod

=head2 Translate to Latin

This procedure tries to translate the string from some form of UTF-8 to Latin1 (iso-8859-1), for usage on the Palm Plucker application. A string is converted to its byte array. Each byte that has 7 bits or less is added to a new byte array. If a byte with bit 8 is encountered, then this is handled as a special character and added to the special character string. If there is a translation available for the special character string, then it is added to the replacement string. Otherwise the next character is handled. If the next character is not a special character, then there is no translation for this character and the word will be displayed as an error for further research.

=cut

sub tx2latin($) {
	my ($str2conv) = @_;
	undef @newarr;
	undef @wordarr;
	undef @specarr;
	my @arr2conv = unpack("C*", $str2conv);
	while (my $charval = shift @arr2conv) {
		if ($charval < 128) {
			if (@specarr) {
				handle_specarr;
			}
			# Add byte to new string
			push @newarr, $charval;
			push @wordarr, $charval;
			if (($charval == 32) or ($charval == 10) or ($charval == 13)) {
				handle_word(@wordarr);
			}
		} else {
			# Special character found
			push @specarr, $charval;
			my $specstr = pack ("C*", @specarr);
			if (defined $utf2latin{$specstr}) {
				handle_tx($specstr);
			}
		}
	}
	if (@specarr) {
		handle_specarr;
	}
	handle_word(@wordarr);
	# translate new array back to string
	my $txtstring = pack("C*", @newarr);
	return $txtstring;
}

1;

=pod

=head1 TO DO

=over 4

=item *

to be continued

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
