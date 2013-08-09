=head1 NAME

BMC_Monitor - This application reads a BMC Patrol report and extracts the monitoring data.

=head1 VERSION HISTORY

version 1.0 9 September 2005 DV

=over 4

=item * 

Initial version.

=back

=head1 DESCRIPTION

This script reads a Patrol Report file and extracts the monitoring settings for the device.

A Patrol report has a standard output format. First line of each block is the Class name, with an indication of the number of instances in the class ('Zero' or any number > 0). Next is the instance blocks. Each instance has a number of parameters. The parameter must be of 'Type: CONSUMER' for monitoring tresholds (Type: COLLECTOR is used for reporting). 

The CONSUMER parameters have "Active" as second line. Only parameters with "Active: ACTIVE" will be considered. 

Next line contains the "Thresholds". If "Thresholds: None" then this parameter is not monitored. Else the next lines (BORDER, ALARM1, ALARM2) contain the threshold values. Only the parameters with threshold settings are important to keep, as these are the only ones that are configured for monitoring and that may generate alarms. None of the other parameters will generate alarms.

For these parameters, the output will be:
Class;Instance;Parameter;Threshold1;Threshold2 ....

=head1 SYNOPSIS

 BMC_Monitor.pl [-t] [-l log_dir] -r Report_File [-o Output_file]

    BMC_Monitor.pl -h	    Usage
    BMC_Monitor.pl -h 1	    Usage and description of the options
    BMC_Monitor.pl -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: c:\temp\log

=item B<-r Report_File>

Report File containing the configuration for the Patrol agent on the server. This file is mandatory.

=item B<-o Output_file>

The output file contains the result of the processing. If not specified, then the file is I<Report_File>.csv

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.6.1, build 631 provided by ActiveState.

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $report_file, $output_file, $line, %ignore_class, $line_type);
my ($class, $inst_count, $instance, $parameter, $attribute, $value);
my $thresholds = "";	    # if $thresholds not empty during EOF processing,
			    # then additional line needs to be printed.
# The ignore_classes array contains all classes that are known to have no
# usable threshold settings.
my @ignore_classes = ("COLLECTORS",
		      "PATROLAGENT",
		      "SMC_REPORT_RU",
		      "SMC_REPORT_RU_CONT",
		      "SMC_TRANSFER_AGENT");

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
# use File::Basename;		    # logfilename translation
use Log;

#############
# subroutines
#############

sub print_thresholds();

sub exit_application($) {
    my($return_code) = @_;
    # If $thresholds contains values, then threshold line must be printed before closing
    if (length($thresholds) > 0) {
	print_thresholds();
	# print RESULT "$class;$instance;$parameter;$thresholds\n";
    }
    close REPORT;
    close RESULT;
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

=head2 Determine Line Type

The line type can be determined using the number of tabs:

=over 4

=item No tabs

Class line or not relevant

=item "1 tab"

Instance line

=item "2 tabs"

Parameter line

=item "3 tabs"

Attribute line

=item "4 tabs"

Threshold line

=back

=cut

sub determine_line_type($) {
    my ($line) = @_;
    if (index($line, "\t\t\t\t") > -1) {
	return "threshold";
    } elsif (index($line, "\t\t\t") > -1) {
	return "attribute";
    } elsif (index($line, "\t\t") > -1) {
	return "parameter";
    } elsif (index($line, "\t") > -1) {
	return "instance";
    } else {
	return "none";
    }
}

=pod

=head2 Read Next Line Procedure

This procedure reads the next line in the BMC Report file, verifies and acts upon EOF processing and determines the line type. If EOF not reached, then $line has the contents of the line and $line_type contains the line type for this line.

=cut

sub read_next_line() {
    $line = <REPORT>;
    if (defined($line)) {
	chomp $line;
	$line_type = determine_line_type($line);
    } else {
	exit_application(0);
    }
}

=pod

=head2 Check Valid Class

This procedure checks if the current line is a valid class line. If so, the class name will be returned. Otherwise the class name will be set to 'undefined'. Setting to undefined will help to spot errors if the result print statement slips through unexpectedely.

A line with a valid class has the number of instances, which cannot be 'Zero'. If a valid class is found, then it is checked if the class should be ignored or not. Ignored classes do not add to the threshold configuration.

=cut

sub check_valid_class($) {
    my ($line) = @_;
    if ((index($line,"instance") > -1) and 
	(index($line, "Zero") == -1)) {
	($class, undef) = split " ",$line;
	if (not(defined($ignore_class{$class}))) {
	    return $class;
	}
    }
    return undef;
}

sub convert_threshold($) {
    my ($valueline) = @_;
    my $convertstring = "";
    $valueline = substr($valueline, 2);	    # Get rid of first :
    my (@value) = split / /,$valueline;
    my $length_array = @value;
    if (not($length_array == 9)) {
	$convertstring = "INVALID;INVALID;INVALID;INVALID;";
	error("Thresholdvalues invalid string $valueline");
	return $convertstring;
    }
    if ($value[0] eq "MIN:") {
	$convertstring = trim $value[1];
    } else {
	$convertstring = "INVALID";
    }
    if ($value[2] eq "MAX:") {
	$convertstring = $convertstring . ";" . trim $value[3];
    } else {
	$convertstring = $convertstring . ";INVALID";
    }
    if (($value[4] eq "RECOVERY") and ($value[5] eq "ACTIONS:")) {
	$convertstring = $convertstring . ";" . trim $value [6];
    } else {
	$convertstring = $convertstring . ";INVALID";
    }
    if ($value[7] eq "TRIGGERING:") {
	$convertstring = $convertstring . ";" . $value[8] . ";";
    } else {
	$convertstring = $convertstring . ";INVALID;";
    }
    if (index($convertstring, "INVALID") > -1) {
	error("Thresholdvalues invalid string $valueline - $convertstring");
    }
    return $convertstring;
}


=pod

=head2 Print Thresholds

This procedure will format and print the threshold values. Thresholds can have categories "BORDER", "ALARM1" and "ALARM2" in this order specified. Each category has the fields MIN, MAX, RECOVERY ACTIONS and TRIGGERING. The value for each field is read and added to the output line. If the category is not present, then empty fields will be put in the output line.

Note that threshold conversion is done in a less elegant way...

=cut

sub print_thresholds() {
    my $thresholdline = "";
    my $empty_fields = ";;;;";
    my ($startpos, $endpos);
    # Check if category BORDER is there
    if (index($thresholds, "BORDER") > -1) {
	$startpos = index($thresholds, "BORDER") +length ("BORDER");
	if (index($thresholds, "ALARM") > -1) {
	    # ALARM Category is there, extract string between Border and Alarm
	    $endpos = index($thresholds, "ALARM");
	} else {
	    $endpos = length($thresholds);
	}
	my $borderstring = substr($thresholds, $startpos, $endpos-$startpos);
	$thresholds = substr($thresholds, $endpos);
	$thresholdline = $thresholdline . convert_threshold($borderstring);
    } else {
	# Add empty fields for threshold line
	$thresholdline = $thresholdline . $empty_fields;
    }
    # Check if category ALARM1 is there
    $startpos = 0;
    if (index($thresholds, "ALARM1") > -1) {
	$startpos = index($thresholds, "ALARM1") + length("ALARM1");
	if (index($thresholds, "ALARM2") > -1) {
	    # ALARM2 Category is there, extract string between Border and Alarm
	    $endpos = index($thresholds, "ALARM2");
	} else {
	    $endpos = length($thresholds);
	}
	my $alarm1string = substr($thresholds, $startpos, $endpos-$startpos);
	$thresholds = substr($thresholds, $endpos);
	$thresholdline = $thresholdline . convert_threshold($alarm1string);
    } else {
	# Add empty fields for threshold line, as no ALARM1 category
	$thresholdline = $thresholdline . $empty_fields;
    }
    # Check if category ALARM2 is there
    if (index($thresholds, "ALARM2") > -1) {
	$startpos = index($thresholds, "ALARM2") + length("ALARM2");
	my $alarm2string = substr($thresholds, $startpos);
	$thresholdline = $thresholdline . convert_threshold($alarm2string);
    } else {
	$thresholdline = $thresholdline . $empty_fields;
    }
    print RESULT "$class;$instance;$parameter;$thresholdline\n";
}

######
# Main
######

# Handle input values

my %options;
getopts("tl:r:o:h:", \%options) or pod2usage(-verbose => 0);
my $arglength = scalar keys %options;  
if ($arglength == 0) {		    # If no options specified,
    $options{"h"} = 0;		    # display usage.
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
    trace_flag(1);
    trace("Trace enabled");
}
# Find log file directory
if ($options{"l"}) {
    $logdir = logdir($options{"l"});
} else {
    $logdir = logdir();
}
if (-d $logdir) {
    trace("Logdir: $logdir");
} else {
    pod2usage(-msg     => "Cannot find log directory $logdir.",
	      -verbose => 0);
}
# Logdir found, start logging
open_log();
logging("Start application");
# Find report file
if ($options{"r"}) {
    $report_file = $options{"r"};
    # Checking on valid file name and if accessible for reading will be done
    # while opening the file.
}
# Check if output file is specified
if ($options{"o"}) {
    $output_file = $options{"e"};
} else {
    $output_file = $report_file . ".csv";
}
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Convert @ignore_classes array to hash for easier reference
foreach my $key (@ignore_classes) {
    $ignore_class{$key} = 1;
}

# Open Report file for reading
my $openres = open(REPORT, $report_file);
if (not(defined $openres)) {
    error("Cannot open report file $report_file for reading, exiting...");
    exit_application(1);
}

# Open output file for writing
$openres = open(RESULT, ">$output_file");
if (not(defined $openres)) {
    error("Cannot open output result file $output_file for writing, exiting...");
    exit_application(1);
}

print RESULT ";;;Border;;;;Alarm1;;;;Alarm2\n";
print RESULT "Class;Instance;Parameter;Min;Max;Recovery;Triggering;Min;Max;Recovery;Triggering;Min;Max;Recovery;Triggering;\n";
# Initialize
read_next_line();

while (defined ($line)) {
    $class = check_valid_class($line);
    if (defined $class) {
	read_next_line();
	while ($line_type eq "instance") {
	    $instance = trim $line;
	    read_next_line();
	    while ($line_type eq "parameter") {
		$parameter = trim $line;
		read_next_line();
		while ($line_type eq "attribute") {
		    $line = trim $line;
		    ($attribute, $value) = split / /, $line;
		    if (($attribute eq "Type:") and ($value eq "CONSUMER")) {
			# don't need the "determine_line_type" from read_next_line here,
			# but it doesn't hurt, and I'll have EOF processing instead!
			read_next_line();
			$line = trim $line;
			($attribute, $value) = split / /, $line;
			if (($attribute eq "Active:") and ($value eq "ACTIVE")) {
			    # don't need the "determine_line_type" from read_next_line here,
			    # but it doesn't hurt, and I'll have EOF processing instead!
			    read_next_line();
			    $line = trim $line;
			    ($attribute, $value) = split / /, $line;
			    if ((not(defined $value)) and ($attribute eq "Thresholds:")) {
				read_next_line();
				while ($line_type eq "threshold") {
				    $line = trim $line;
				    $thresholds = $thresholds." ".$line;
				    read_next_line();
				}
				# All thresholds found, so print them
				# print RESULT "$class;$instance;$parameter;$thresholds\n";
				print_thresholds();
				$thresholds = "";
			    }
			} else {
			    while (($line_type eq "attribute") or ($line_type eq "threshold")) {
				read_next_line();
			    }
			}
		    } else {
			while (($line_type eq "attribute") or ($line_type eq "threshold")) {
			    read_next_line();
			}
		    }
		}
	    }
	}
    } else {
	read_next_line();
    }
}

exit_application(0);

=pod

=head1 TO DO

=over 4

=item *

Convert Threshold1, Threshold2 in better formats.

=item *

Include the exclusion of specific classes

=item *

Combine read next line, chomp and determine line type in a function. This function should keep track of EOF handling.

=item *

Make the application more readable, by adding functions and doc.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
