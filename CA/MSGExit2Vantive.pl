=head1 NAME

MSGExit2Vantive - Convert the emlog1 csv file to a plain text format.

=head1 VERSION HISTORY

version 1.0 2 April 2003 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application reads a *.csv file as generated from the emlog1 utility and converts it into a plain text file as required by the Vantive interface. Note that this should be used as a test only. For real production usage, it may be much better to change the emlog1 code.

The *.csv file is created as the result of a user action. The user action is defined by using the environment setting "CAI_MSG_EXIT".

The output files will be created wherever the Vantive interface expects its data. If more than one event is stored in the input file, then multiple output files will be created - one output file per event.

=head1 SYNOPSIS

MSGExit2Vantive.pl [-t] [-l log_dir] -f csv_file

    MSGExit2Vantive -h	    Usage
    MSGExit2Vantive -h 1	    Usage and description of the options
    MSGExit2Vantive -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: c:\temp

=item B<-f csv_file>

Full path to the csv file to be translated. The output will be available in a file with the same path, the same filename and extension *.txt.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.6.1, build 631 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my $logdir;
my $csv_file;
my $txt_file;
my $csv = "CSVFILE";		    # Placeholder
my $txt = "TXTFILE";		    # Placeholder
# my $outputdir;
my %eeib=();			    
my %eeib_fixed=();
my %user_action=();
my @vantivefields=();

=pod

=head2 Translate Unicenter User Action output to Vantive field requirements.

Note that since this logic has been copied from the MSGExit2EEIB application, the EEIB naming has been maintained as an intermediate array.

A hash %eeib is used for the translation. The key is the value as required for the EEIB file. The value is the column name from the Unicenter action file, after converting to *.csv using the emlog1 utility.

Some values are fixed for all events. These values are listed in the %eeib_fixed hash.

Some day this translation section could be done in a more user friendly way, instead of hardcoding everything...

=cut

$eeib{"event_handle"}="RecId";
$eeib{"hostname"}="Node";
$eeib{"msg"}="Text";
$eeib{"server_handle"}="RecId";
$eeib{"severity"}="Severity";
$eeib{"source"}="Pinfo";
$eeib{"administrator"}="User";

# Fixed values...

$eeib_fixed{"class_name"}="Unicenter";
$eeib_fixed{"date_reception"}="To be calculated";
$eeib_fixed{"origin"}="Unicenter Event Console";
$eeib_fixed{"status"}="Open";
$eeib_fixed{"sub_source"}="";
$eeib_fixed{"trouble_ticket"}="no";
$eeib_fixed{"date"}="To be calculated";
$eeib_fixed{"domain"}="";
$eeib_fixed{"reason"}="";
$eeib_fixed{"server"}="";
$eeib_fixed{"sub_origin"}="";
$eeib_fixed{"adapter_host"}="Unicenter Event Console";
$eeib_fixed{"last_update"}="To be calculated";
$eeib_fixed{"repeat_count"}="To be defined";
$eeib_fixed{"TECTOKEN"}="EOF";


=pod

=head2 VERIFY

A vantivefields array is used to guarantee the order in which the fields are printed on the report. The Vantive interface expects the values in a fixed order. 

Currently the order of the fields is hard-coded in the application in the array @vantivefields. Changing the array will change the order of the fields in the output.

=cut

@vantivefields=("class_name",
	        "date_reception",
		"event_handle",
		"hostname",
		"msg",
		"origin",
		"server_handle",
		"severity",
		"source",
		"status",
		"sub_source",
		"trouble_ticket",
		"date",
		"domain",
		"reason",
		"server",
		"sub_origin",
		"adapter_host",
		"last_update",
		"repeat_count",
		"administrator",
		"TECTOKEN");

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
#use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use Log;			    # Application and error logging
use File::Basename;		    # Extract filename from fully qualified name
use Time::Local;

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
    if (defined $csv) {
	close $csv;
    }
    logging("Exit application with return code: $return_code\n");
    close_log();
    exit $return_code;
}

=pod

=head2 Calc Special Fields

A number of fields are not available as is, they need to be calculated. The fields are the "date reception" (epoch time) "date" (local date and time of the event) and "last_update" (local date and time of the event).

=cut

sub calc_specialfields {
    $eeib_fixed{"date"}=$user_action{"Date"}." ".$user_action{"Timegen"};
    $eeib_fixed{"last_update"}=$user_action{"Date"}." ".$user_action{"Timegen"};
    my($year,$month,$day)=split(/\//,$user_action{"Date"});
    my($hour,$min,$sec)=split(/:/,$user_action{"Timegen"});
    $year=$year-1900;
    $month=$month-1;
    $eeib_fixed{"date_reception"}=timelocal($sec,$min,$hour,$day,$month,$year);
}


=pod

=head2 Handle file

Read the title line. The title line should be there always, even if no translation could be done. The values of the title line are stored in the key array.

Then read all consecutive lines. Each line corresponds with one event. The event values are stored in the values array. All keys and values are printed into a nice format and then the next line is handled.

Remark: the field values are separated by commas, there may be problems if a comma appears within one of the field values.

=cut

sub handle_file {
    my $inputline = <$csv>;
    chomp $inputline;
    # The title line does not contain quotes, 
    # so easy input into the @keys array.
    my @keys = split /,/, $inputline;
    my $nbr_keys = @keys;
    my $recno = 0;		    # Event record counter to handle multiple events in one file.
    while ($inputline = <$csv>) {
	$recno++;
	chomp $inputline;
	# Use "," to get rid of the quotes around the value fields in one go, but ...
	my @values = split /\",\"/, $inputline;		    
	# ... the first quote, around the date field, is still there ...
	$values[0] = substr($values[0],1,length($values[0])-1);
	# ... as is the last quote!
	# However if the last field is empty, there is only a quote in it.
	# Remark: the annotation field seems to be always empty!!!
	if (length($values[$nbr_keys-1]) == 1) {
	    $values[$nbr_keys-1] = "";
	} else {
	    $values[$nbr_keys-1] = substr($values[$nbr_keys-1],0,length($values[$nbr_keys-1]-1));
	}
	# Convert @keys and @values arrays into a hash
	for (my $cnt=0; $cnt < $nbr_keys; $cnt++) {
	    $user_action{$keys[$cnt]}=$values[$cnt];
	}
	calc_specialfields;
	# Write the hash to a file
	my $openres = open($txt,">$txt_file"."_$recno");
	if (not(defined $openres)) {
	    error("Could not create $txt_file"."_$recno for writing, exiting...");
	    exit_application(1);
	}
	foreach my $key (@vantivefields) {
	    if (defined($eeib{$key})) {
		print $txt "$key:$user_action{$eeib{$key}}\n";
	    } elsif (defined($eeib_fixed{$key})) {
		print $txt "$key:$eeib_fixed{$key}\n";
	    } else {
		error("No value found for $key");
	    }
	}
	close $txt;
    }
}

######
# Main
######

# Log::stderr_flag(1);
# Handle input values
my %options;
getopts("tl:f:h:", \%options) or pod2usage(-verbose => 0);
#my $arglength = scalar keys %options;  
#if ($arglength == 0) {			# If no options specified,
#    $options{"h"} = 0;			# display usage.
#}
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
    pod2usage(-msg     => "Cannot find log directory ".logdir,
	      -verbose => 0);
}
# Logdir found, start logging
open_log();
logging("Start application");
# Find csv file to convert
if ($options{"f"}) {
    $csv_file = $options{"f"};
    if (not(-r $csv_file)) {
	error("csv file $csv_file not found, exiting...");
	exit_application(1);
    }
} else {
    error("csv file not defined, exiting...");
    exit_application(1);
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# open csv file for reading
my $openres = open($csv,$csv_file);
if (not(defined $openres)) {
    error("Could not open $csv_file, exiting...");
    exit_application(1);
}

# Find the %AGENTWORKS_DIR%\TEMP Directory, because this is where bo2fotng.pl
# tries to find the file.
my $agentworks_dir = $ENV{'AGENTWORKS_DIR'};
if (not(defined $agentworks_dir)) {
    error("Environment Variable AGENTWORKS_DIR not defined");
    exit_application(1);
} elsif (not(-d "$agentworks_dir/temp")) {
    error("Directory $agentworks_dir/temp does not exist");
    exit_application(1);
}

# Now strip the path name from the input file
# because the outputfile needs to go to the %AGENTWORKS_DIR%\TEMP directory
my ($txt_file_name,undef) = split (/\./,basename($csv_file));
logging("$txt_file_name *** $csv_file");
$txt_file = "$agentworks_dir/temp/$txt_file_name";


handle_file;

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Include error reporting to back to the event console using cawto (or display error messages on the console using a popup window.

=item *

Change the output file format to be flexible and compliant with the Unicenter EEIB flat file contents.

=item *

Call the bo2fotng.pl application, since this is an easy way to communicate the new file name.

=item *

One user action can trigger the file for several event messages in one go. bo2fotng.pl requires one event per file, so split up the input file into one output file per event.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
