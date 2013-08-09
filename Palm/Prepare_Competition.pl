=head1 NAME

Prepare_Competition - Prepares a competition for input to Bundesliga

=head1 VERSION HISTORY

version 1.0 - 23 Aug 2005 DV

=over 4

=item *

Initial Release

=back

=head1 DESCRIPTION

This application converts a football competition text file into a file that can be converted into a palm database. The football competition is available at http://www.kvbv.be. The conversion program is at http://www.pundt.de.

The input file should be a copy from what is available on the kvbv website today.

=head1 SYNOPSIS

 Prepare_Competition.pl [-t] [-l logfile_directory]  -f input_text_file

 Prepare_Competition.pl -h	Usage Information
 Prepare_Competition.pl -h 1	Usage Information and Options description
 Prepare_Competition.pl -h 2	Full documentation

=head1 OPTIONS

=over 4

=item B<-t>

if set, then trace messages will be displayed. 

=item B<-l logfile_directory>

default: c:\temp\log

=item B<-f input_text_file>

Full path to the file to convert. The output file will be the same filename, with the extension _converted appended to it. This parameter is mandatory.

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
###########

my ($logdir, $orig_file);
my $extension = "_Converted";

my %ploeg;
$ploeg{"A.FC.TUBIZE"} = "Tubeke";
$ploeg{"K.AS.EUPEN"} = "Eupen";
$ploeg{"K.BERINGEN-HEUSDEN-ZOLDER"} = "B-Heusden-Z";
$ploeg{"K.FC.DESSEL SPORT"} = "Dessel";
$ploeg{"K.FC.VERBR.GEEL"} = "Geel";
$ploeg{"K.FC.VIGOR WUITENS HAMME"} = "Hamme";
$ploeg{"K.MSK.DEINZE"} = "Deinze";
$ploeg{"K.SK.RONSE"} = "Ronse";
$ploeg{"K.UNITED OVERPELT-LOMMEL"} = "KVSK United";
$ploeg{"KV.KORTRIJK"} = "Kortrijk";
$ploeg{"KV.OOSTENDE"} = "KV. Oostende";
$ploeg{"KV.RED STAR WAASLAND"} = "Waasland";
$ploeg{"OUD-HEVERLEE LEUVEN"} = "OH Leuven";
$ploeg{"R.AEC.MONS"} = "Bergen";
$ploeg{"R.ANTWERP FC."} = "Antwerp";
$ploeg{"R.EXCELSIOR VIRTON"} = "Virton";
$ploeg{"R.UNION ST.-GILLOISE"} = "Union";
$ploeg{"YELLOW-RED KV.MECHELEN"} = "KV. Mechelen";

#####
# use
#####

use warnings;			    # show warnings
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Input parameter handling
use Pod::Usage;			    # Usage printing
use Log;

#############
# subroutines
#############

sub exit_application($) {
    my($return_code) = @_;
    close ORIG;
    close CONVERT;
    logging("Exit application with return code $return_code\n");
    close_log();
    exit $return_code;	
}

=pod

=head2 Trim

This section is used to get rid of leading or trailing blanks. It has been
copied from the Perl Cookbook.

=cut

sub trim {
    my @out = @_;
    for (@out) {
        s/^\s+//;
        s/\s+$//;
    }
    return wantarray ? @out : $out[0];
}

=pod

=head2 Handle TeamList

The file for conversion must start with a list of teams. Each team is on a separate line, with only the name of the team. Each name should be no longer than 20 characters. A translation table will be defined to maintain short names.

In the original file, this block must be terminated with a blank line. Each line consists of numbers, with the team name as a character string (including possible spaces) and terminated with a tab.

=cut

sub handle_teamlist() {
    while (my $line = <ORIG>) {
	chomp ($line);
	$line = trim($line); # No more leading or trailing blanks
	if (length($line) == 0) {
	    # Empty line is a block separator
	    last;
	} else {
	    # Line starts with number, then characters and then many blanks
	    # and much more numbers
	    # Separated with tabs
	    my @members = split /\t/,$line;
	    foreach my $member (@members) {
		$member = trim ($member);
		if (not($member =~ /^\d+$/)) {
		    print "$ploeg{$member}\n";
		}
	    }
	}
    }
    print "\n";
}

sub handle_competition() {
    # Read until non-empty line, this is the start of the "day"
    while (my $line = <ORIG>) {
	chomp ($line);
	$line = trim($line);
	if (length($line) == 0) {
	    print "\n";		# Keep empty line
	} elsif (length($line) > 1) {
	    handle_day($line);	# Ignore "-"
	}
    }
}

sub handle_day($) {
    my ($line) = @_;
    my @members = split /\t/,$line;
    # First word is date
    $members[0] = trim ($members[0]);
    my $year  = substr($members[0],6,4);
    my $month = substr($members[0],3,2);
    my $day   = substr($members[0],0,2);
    # Second word is time
    $members[1] = trim ($members[1]);
    my $hour  = substr($members[1],0,2);
    my $min   = substr($members[1],3,2);
    $members[2] = trim ($members[2]);
    $members[3] = trim ($members[3]);
    print "$year$month$day$hour$min:$ploeg{$members[2]}:$ploeg{$members[3]}:\n";
    # print "$year$month$day$hour$min:$ploeg{$members[2]}:$ploeg{$members[3]}:\n";
    # Third word is home team
    # Fourth word is visitors team
}
	
######
# Main
######

# Handle input values
my %options;
getopts("tl:f:h:", \%options) or pod2usage(-verbose => 0);
# Print Usage
if (defined $options{"h"}) {
    if ($options{"h"} == 0) {
        pod2usage(-verbose => 0);
    } elsif ($options{"h"} == 1) {
        pod2usage(-verbose => 1);
    } else {
	pod2usage(-verbose => 2);
    }
}
# Trace required?
if (defined $options{"t"}) {
    Log::trace_flag(1);
    trace("Trace enabled");
}
# Find log file directory
if ($options{"l"}) {
    $logdir = logdir($options{"l"});
} else {
    $logdir=logdir();
}
if (-d $logdir) {
    trace("Logdir: $logdir");
} else {
    pod2usage(-msg     => "Cannot find log directory ".logdir,
	      -verbose => 0);
}
# Logdir found, start logging
open_log();
logging("Start application");
# Find hosts file
if ($options{"f"}) {
    $orig_file = $options{"f"};
} else {
    error("Input file must be defined, exiting ....");
    exit_application(1);
}
if (-r $orig_file) {
    trace("Original file: $orig_file");
} else {
    error("Cannot find input file $orig_file for conversion");
    exit_application(1);
}
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Open input file for reading
my $openres = open(ORIG, $orig_file);
if (not(defined $openres)) {
    error("Cannot open $orig_file for reading, exiting...");
    exit_application(1);
}

# Open output file for writing
my $output_file = $orig_file . $extension;
$openres = open(CONVERT, ">$output_file");
if (not(defined $openres)) {
    error("Cannot open $output_file for writing, exiting...");
    exit_application(1);
}

# First section is the list of teams.
handle_teamlist();

# Then handle the competition
handle_competition();

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Verify if it works with some results appended to the file, without specifying the up-to-date table.

=item *

Verify if it is possible to specify a translation table official names to common names. This should be used for regular table updates then.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@skynet.beE<gt>
