=head1 NAME

WRSExtractSrcFailed.pl - Script to extract Source data from the CAUM4WS table for all transactions.

=head1 VERSION HISTORY

version 1.0 25 September 2006 DV

=over 4

=item *

Initial Release based on the WRSExtractIdentifier script.

=back

=head1 DESCRIPTION

The script will connect to the CAUM4WS database and extract data. The data will be made available in a html file on the reporting directory. The data from one identifier with the last 20 failed connections will be extracted.

=head1 SYNOPSIS

 WRSExtractSrcFailed.pl [-t] [-l log_dir] [-d datasource] -i instancenumber

    WRSExtractSrcFailed.pl -h	  Usage
    WRSExtractSrcFailed.pl -h 1    Usage and description of the options
    WRSExtractSrcFailed.pl -h 2    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: c:\temp\log

=item B<-d datasource>

The data source name pointing to the CA Trap database. Default: CAITRPDB, the data source name requested for the Unicenter Trap Editor. 

=item B<-i Source>

SourceID number from the CounterSource table.

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $cawrmdb, $identifier, $bgcolor);
my $dsource = "CAUM4WS";	    # Data source name
my $rep_dir = "d:/em/data/reps/extract";    # Directory to store HTML file
my $top_count = 40;

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
use Win32::ODBC;		    # Win32 ODBC module
use Log;			    # Log module

#############
# subroutines
#############

sub exit_application($) {
    my($return_code) = @_;
    if (defined $cawrmdb) {
	$cawrmdb->Close();
	logging("Close Database connection.");
    }
    close OutFile;
    logging("Exit application with return code $return_code\n");
    close_log();
    exit $return_code;
}

sub SQLquery($$) {
  my($db, $query) = @_;
  if ($db->Sql($query)) {
    my ($errnum, $errtext, $errconn) = $db->Error();
    error("$errnum.$errtext.$errconn\n$query\n$db");
    $db->Close();
    exit();
  }
}

=pod

=head2 Extract Data

Extract data and output all data in html format.

=cut

sub extract_data() {
    my $sql = "SELECT TOP $top_count WRMGroup.Name AS 'Group', WRMIdentifier.Name AS Identifier, WRM.TimeStart, 
		      WRMStat.Name as MonStatus, WRM.RespTime, WRM.NewAccuracyStatID, 
                      WRM.StatusCode, WRMStatusMessage.Message
	       FROM WRM
		    INNER JOIN WRMIdentifier ON WRM.IdentifierID = WRMIdentifier.IdentifierID 
		    INNER JOIN WRMGroup ON WRM.GroupID = WRMGroup.GroupID 
		    INNER JOIN WRMStatusMessage ON WRM.StatusMessageID = WRMStatusMessage.StatusMessageID
		    INNER JOIN WRMStat ON WRM.NewSumStatID = WRMStat.StatusID
	       WHERE (WRM.SourceID = $identifier) and 
		     (WRM.NewSumStatID <> 2)
	       ORDER BY WRM.TimeStart DESC";
    SQLquery($cawrmdb, $sql);
    # Print all records
    while ($cawrmdb->FetchRow()) {
	my %record = $cawrmdb->DataHash();
	# Check if status is OK or NOK
	if ($record{MonStatus} eq "OK") {
	    $bgcolor = "#AFFFCC";
	} else {
	    $bgcolor = "#FFAFCC";
	}
	my $outline = "<tr bgcolor='$bgcolor'><td>".$record{Group};
	$outline .= "<td>".$record{Identifier};
	my $yr = substr($record{TimeStart},0,4);
	my $mth = substr($record{TimeStart},5,2);
	my $day = substr($record{TimeStart},8,2);
	my $time = substr($record{TimeStart},11,8);
	$outline .= "<td>$day-$mth-$yr $time";
	$outline .= "<td>".$record{MonStatus};
	$outline .= "<td>".$record{RespTime};
	$outline .= "<td>".$record{NewAccuracyStatID};
	$outline .= "<td>".$record{StatusCode};
	$outline .= "<td>".$record{Message};
	$outline .= "</tr>\n";
	print OutFile $outline;
    }
}

######
# Main
######

# Handle input values

my %options;
getopts("tl:d:h:i:", \%options) or pod2usage(-verbose => 0);
# Mandatory Input Parameters? Enable section below:
#my $arglength = scalar keys %options;  
#if ($arglength == 0) {			# If no options specified,
#   $options{"h"} = 0;			# display usage.
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
    pod2usage(-msg     => "Cannot find log directory $logdir.",
	      -verbose => 0);
}
# Logdir found, start logging
open_log();
logging("Start application");
# Find data source
if ($options{"d"}) {
    $dsource = $options{"d"};
}
# Find Identifier
if (defined $options{"i"}) {
    $identifier = $options{"i"};
} else {
    error("No identifer number defined, exiting...");
    exit_application(1);
}
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Open Handle to read database
if (!($cawrmdb = new Win32::ODBC($dsource))) {
    error("Data Source $dsource (CAUM4WS) Open failed: ".Win32::ODBC::Error());
    exit_application(1);
}

# Open Output file
my $outfile = $rep_dir."/source_failed_$identifier.html";
my $openres = open(OutFile, ">$outfile");
if (not defined $openres) {
    error("Cannot open $outfile for writing, exiting...");
    exit_application(1);
}

# Define Extraction Time
my $currenttimesecs = time;
my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($currenttimesecs);
my $datetime = sprintf "%02d/%02d/%04d %02d:%02d", $mon+1, $mday, $year+1900, $hour,$min;
logging("Extraction done at $datetime");

# Initialize Report
print OutFile "<html><body>\n";
print OutFile "<h3>Last $top_count Connections (Extracted at $datetime)</h3>\n";
print OutFile "<table border width='100%' cellpadding=2>\n";
print OutFile "<tr bgcolor='yellow'><th>Device<th>Id.<th>Time<th>MonStatus<th>Resp.(ms)";
print OutFile "<th>Acc.<th>Status<th>Message</tr>\n";

extract_data();

# Finalize Report
print OutFile "</table></body></html>\n";

exit_application(0);

=pod

=head1 TO DO

=over 4

=item *

Ensure that all fields in each row are printed in the same sequence.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
