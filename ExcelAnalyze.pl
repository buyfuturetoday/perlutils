=head1 NAME

ExcelAnalyze - Excel Workbook analyzer

=head1 VERSION HISTORY

version 1.0 26 October 2010 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will analyze excel workbooks as need arises. This is to help understand those workbooks that are not handled properly.

=head1 SYNOPSIS

 ExcelAnalyze.pl [-t] [-l log_dir] -e excelfile [-o] [-s sheet]

 ExcelAnalyze -h		Usage
 ExcelAnalyze -h 1   Usage and description of the options
 ExcelAnalyze -h 2   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-e excelfile>

MySQL Excel Workbook, needs to be readable.

=item B<-o>

Worksheet count and worksheet names will be displayed.

=item B<-s sheet>

sheet name. If specified then the range (row_min to row_max, col_min to col_max) of the sheet will be specified.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP, Perl v5.10.0, build 1005 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $excel, $listsheets, $sheet);
my $rowcnt = 0;
my $printerror = 0;

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use Log;
use Spreadsheet::ParseExcel;

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	logging("Exit application with return code $return_code.\n");
    close_log();
    exit $return_code;
}

sub trim {
    my @out = @_;
    for (@out) {
        s/^\s+//;
        s/\s+$//;
    }
    return wantarray ? @out : $out[0];
}

######
# Main
######

# Handle input values
my %options;
getopts("tl:h:e:os:", \%options) or pod2usage(-verbose => 0);
# my $arglength = scalar keys %options;  
# if ($arglength == 0) {			# If no options specified,
#   $options{"h"} = 0;			# display usage.
# }
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
    if (not(defined $logdir)) {
		error("Could not set $logdir as Log directory, exiting...");
		exit_application(1);
    }
} else {
    $logdir = logdir();
    if (not(defined $logdir)) {
		error("Could not find default Log directory, exiting...");
		exit_application(1);
    }
}
if (-d $logdir) {
    trace("Logdir: $logdir");
} else {
    pod2usage(-msg     => "Cannot find log directory $logdir",
	      -verbose => 0);
}
# Logdir found, start logging
open_log();
logging("Start application");
# Get excel file
if ($options{"e"}) {
	$excel = $options{"e"};
	if (not -r $excel) {
		error("Excel file $excel not readable, exiting...");
		exit_application(1);
	}
} else {
	error("Excel file not defined, exiting...");
	exit_application(1);
}
if (defined $options{"o"}) {
	$listsheets = "Yes";
}
if ($options{"s"}) {
	$sheet = $options{"s"};
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Open Excel File
my $parser = Spreadsheet::ParseExcel->new();
my $workbook = $parser->parse($excel);
if (not defined $workbook) {
	error("Could not open $excel for reading, ".$parser->error());
	exit_application(1);
}

if (defined $listsheets) {
	# Count of worksheets
	my $count = $workbook->worksheet_count();
	print "$count worksheets defined in workbook $excel\n";

	# Get Workbooks
	for my $worksheet ($workbook->worksheets()) {
		my $sheetname = $worksheet->get_name();
		print "Worksheet: *$sheetname*\n";
	}

}

if (defined $sheet) {
	my $worksheet = $workbook->worksheet("$sheet");
	if (not defined $worksheet) {
		error("Could not access worksheet *$sheet*, exiting...");
		exit_application(1);
	}
	my ($row_min, $row_max) = $worksheet->row_range();
	my ($col_min, $col_max) = $worksheet->col_range();
	print "$sheet Range from row $row_min to $row_max\n";
	print "$sheet Range from col $col_min to $col_max\n";
}



exit_application(0);

=head1 To Do

=over 4

=item *

Nothing documented for now...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@hp.comE<gt>
