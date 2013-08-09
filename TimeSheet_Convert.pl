=head1 NAME

TimeSheet_Convert - Script to convert TimeSheets

=head1 DESCRIPTION

This script will read a memo dump of the timesheet extract and convert it into a nice csv format. The output will be sent to the c:\temp\ts_formatted.csv.

Read WBS numbers and project names from a project file. This approach allows to add comments to WBS entries. Also WBS maintenance is separated from the application itself, which makes WBS maintenance less critical for errors.

This application will convert timesheets that are generated with the application B<Timesheet>, version 1.2.3, available from http://www.jsankey.com. Timesheet information is exported by selecting Data / Export. Export settings are 'New Memo' for Destination, 'Timesheet Export' for Filename and 'Durations', check Note, Previous 2 weeks for Data. The result file is available as a memo and must be copied into a Notepad file after synchronization. This Notepad file is the input for this application.

=head1 SYNOPSIS

TimeSheet_Convert.pl [-t] [-l log_dir] -s timesheet_file [-q]

    TimeSheet_Convert.pl -h	 Usage
    TimeSheet_Convert.pl -h 1   Usage and description of the options
    TimeSheet_Convert.pl -h 2   All documentation

=head1 VERSION HISTORY

version 1.4 3 September 2007 DV

=over 4

=item *

Show output file in excel format, unless -q (quiet option) is specified.

=back

version 1.3 16 July 2007 DV

=over 4

=item *

Add Day (Text) to Date field, reformat to reflect SAP style of fromatting dates.

=back

version 1.2 22 March 2007 DV

=over 4

=item *

Reformat output to reflect SAP style row/column approach.

=back

version 1.1 26 February 2007 DV

=over 4

=item *

Convert time calculation from h:mm to minutes in decimal fraction.

=back

version 1.0 12 February 2007 DV

=over 4

=item *

Initial Version

=back

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: c:\temp. Logging is enabled by default. 

=item B<-s>

Timesheet_file extracted from Palm Memo.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP Professional, Perl v5.8.8 build 820 provided by ActiveState.

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, @dates, %total, %labels, $timesheet_file, %wbs, $quiet);
my $ts_outfile = "c:/temp/ts_formatted.csv";
my $wbs_file = "D:/Documents and Settings/dz09s6/My Documents/wbs-project.txt";

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
# use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use Log;			    # Application and error logging
use Date::Calc qw(Day_of_Week_Abbreviation Day_of_Week);

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
    logging("Exit application with return code: $return_code\n");
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

=head2 Read ini file Procedure

This procedure will read all lines from a ini file. All keys will be converted to lowercase, values will remain untouched. All key/value pairs will be stored in a hash. Duplicate keys in the file are allowed but not recommended. The last value will have precedence.

Keys are the Project descriptions, values are the WBS numbers required for SAP. A key must start with an alphabetic character. A line starting with another character (including blank) will be ignored (threated as a comment).

=cut

sub read_ini_file() {
	my $openres = open(WBS_List, $wbs_file);
	if (not defined $openres) {
		error ("Could not open $wbs_file for reading, exiting...");
		exit_application(1);
	}
    while (my $line = <WBS_List>) {
		chomp $line;
		if ($line =~ /^[A-Za-z]/) {
			my ($key, $value) = split (/=/, $line);
			$key = lc(trim($key));
			$value = trim($value);
			$wbs{$key} = $value;
		}
	}
	close WBS_List;
}

=pod

=head2 Handle Line

Each Line from the Timesheet export file is read. Each usable line has date as the first field, the label "Total" as the second field, total work time as third field and then pairs of work-item, work-time as next fields, for as many as there were work items.

Each work-item is added to the labels hash. A hash is also created with this work-item as name, the date as key and the duration as value.

=cut

sub handle_line($) {
	my ($line) = @_;
	my ($date,undef,$total_label,$total_time, @rest) = split /,/, $line;
	if ($total_label eq "\"Total\"") {
		push @dates, $date;
		# Convert total_time to h.f format.
		my ($hour,$min) = split /:/,$total_time;
		$min = ($min / 60) * 100;
		$total_time = sprintf "%2d.%02d",$hour,$min;
		$total{$date} = $total_time;
		my $length = @rest;
		my ($label, $duration);
		while ($length > 0) {
			$label = shift @rest;
			$label = substr($label, 1, length($label)-2);
			$duration = shift @rest;
			# Convert duration from h:mm to h.f
			($hour,$min) = split /:/,$duration;
			$min = ($min / 60) * 100;
			$duration = sprintf "%2d.%02d",$hour,$min;
			$labels{$label} = 1;
			$$label{$date} = $duration;
			$length = @rest;
		}
	} else {
		error("Something unusual on format timesheet file");
	}
}
	

######
# Main
######

# Handle input values
my %options;
getopts("h:tl:s:q", \%options) or pod2usage(-verbose => 0);
my $arglength = scalar keys %options;  
# print "Arglength: $arglength\n";
if ($arglength == 0) {			# If no options specified,
    $options{"h"} = 0;			# display usage.
}
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
# Log required?
if (defined $options{"n"}) {
    log_flag(0);
} else {
    log_flag(1);
    # Log required, so verify logdir available.
    if ($options{"l"}) {
		$logdir = logdir($options{"l"});
    } else {
		$logdir = logdir();
    }
    if (-d $logdir) {
		trace("Logdir: $logdir");
    } else {
		pod2usage(-msg     => "Cannot find log directory ".logdir,
		 		  -verbose => 0);
    }
}
# Logdir found, start logging
open_log();
logging("Start application");
# Find TimeSheet_file
if ($options{"s"}) {
	$timesheet_file = $options{"s"};
	# Verify that the timesheet file is readable.
	if (not(-r $timesheet_file)) {
    	error("Cannot access Timesheet file $timesheet_file for reading, exiting...");
    	exit_application(1);
	}
} else {
	error("Timesheet file not defined, exiting...");
	exit_application(1);
}
if (defined ($options{"q"})) {
	$quiet = "Yes";
} else {
	undef $quiet;
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input value

# Initialize WBS hash
read_ini_file();

# Open Timesheet file for reading
my $openres = open(Ts, $timesheet_file);
if (not(defined $openres)) {
	error("Couldn't open $timesheet_file for reading, exiting...");
	exit_application(1);
}

# Handle all lines in timesheet file
while (my $line = <Ts>) {
	chomp $line;
	$line = trim ($line);
	# Make sure that first character is numeric
	if ($line =~ /^[0-9]/) {
		handle_line($line);
	}
}
close Ts;

# Now print nicely formatted output file
$openres = open (TsRes, ">$ts_outfile");
if (not(defined $openres)) {
	error("Could not open $ts_outfile for writing, exiting...");
	exit_application(1);
}

# Print Headerline with all dates
print TsRes ";;";
foreach my $dateval (@dates) {
	# Extract Day of Week (text)
	my ($year, $mon, $day) = split /\//,$dateval;
	my $dow_abbrev = Day_of_Week_Abbreviation(Day_of_Week($year, $mon, $day));
	# and reformat, print into the SAP date format
	print TsRes substr($dow_abbrev,0,2)." $day.$mon;";
}
print TsRes "\n";

# Next line is the Totals
print TsRes "Total;;";
foreach my $dateval (@dates) {
	print TsRes "$total{$dateval};";
}
print TsRes "\n";

# and then print one line per work-item
while (my($key, $value) = each %labels) {
	print TsRes "$key;";
	my $wbs_code = $wbs{lc($key)};
	if (not defined $wbs_code) {
		$wbs_code = 1000;
	}
	if (length($wbs_code) == 4) {
		# WBS Code length 4 -> 1000-range
		print TsRes "$wbs_code;";
	} else {
		print TsRes "2000;";
	}
	foreach my $dateval (@dates) {
		if (exists $$key{$dateval}) {
			print TsRes "$$key{$dateval};";
		} else {
			print TsRes ";";
		}
	}
	if (length($wbs_code) == 4) {
		# WBS Code length 4 -> 1000-range
		print TsRes "\n";
	} else {
		print TsRes "$wbs_code\n";
	}
}

close TsRes;

if (not(defined $quiet)) {
	system("$ts_outfile");
}

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Nothing for now.....

=back
