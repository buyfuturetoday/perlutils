=head1 NAME

WRSExtractData.pl - Script to extract data from the CAUM4WS table.

=head1 VERSION HISTORY

version 1.0 16 September 2006 DV

=over 4

=item *

Initial Release based on the CATrapModification script.

=back

=head1 DESCRIPTION

The script will connect to the CAUM4WS database and extract data. The data will be made available in a csv file on the c:\temp directory. 

For now the script does not accept any relevant input parameters (until it becomes more clear what we want to do with it).

=head1 SYNOPSIS

 WRSExtractData.pl [-t] [-l log_dir] [-d datasource]

    WRSExtractData.pl -h	    Usage
    WRSExtractData.pl -h 1	    Usage and description of the options
    WRSExtractData.pl -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: c:\temp\log

=item B<-d datasource>

The data source name pointing to the CA Trap database. Default: CAITRPDB, the data source name requested for the Unicenter Trap Editor. 

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $cawrmdb);
my $dsource = "CAUM4WS";	    # Data source name
my $starttime = "9/14/06 08:00";    # Start Time, format MMDDYY HH:MM
my $endtime   = "9/15/06 0:00";	    # End Time, format MMDDYY HH:MM

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

Extract data and output all data in csv format.

=cut

sub extract_data() {
    my $sql = "SELECT WRMGroup.Name AS 'Group', WRMIdentifier.Name AS Identifier, WRM.TimeStart, 
		      WRM.RespTime AS 'Response (ms)', WRM.NewAccuracyStatID as 'String Check', 
                      WRM.StatusCode, WRMStatusMessage.Message
	       FROM WRM
		    INNER JOIN WRMIdentifier ON WRM.IdentifierID = WRMIdentifier.IdentifierID 
		    INNER JOIN WRMGroup ON WRM.GroupID = WRMGroup.GroupID 
		    INNER JOIN WRMStatusMessage ON WRM.StatusMessageID = WRMStatusMessage.StatusMessageID
	       WHERE (WRM.SourceID = 9) and 
		     (WRM.TimeStart > '$starttime') and 
		     (WRM.TimeStart < '$endtime')";
    SQLquery($cawrmdb, $sql);
    # Print Header information
    # and first row
    if ($cawrmdb->FetchRow()) {
	my %record = $cawrmdb->DataHash();
	foreach my $key (keys %record) {
	    print OutFile $key.";";
	}
	print OutFile "\n";
	foreach my $key (keys %record) {
	    print OutFile $record{$key}.";";
	}
	print OutFile "\n";
    } else {
	error("Query did not return any rows! Query : ********\n$sql\n**********");
	exit_application(1);
    }
    # Print all following records
    while ($cawrmdb->FetchRow()) {
	my %record = $cawrmdb->DataHash();
	foreach my $key (keys %record) {
	    print OutFile $record{$key}.";";
	}
	print OutFile "\n";
    }
}

######
# Main
######

# Handle input values

my %options;
getopts("tl:d:h:", \%options) or pod2usage(-verbose => 0);
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
my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my $datetime = sprintf "%04d%02d%02d%02d%02d", $year+1900, $mon+1, $mday, $hour,$min;
my $outfile = "c:/temp/wrmstat_$datetime.csv";
my $openres = open(OutFile, ">$outfile");
if (not defined $openres) {
    error("Cannot open $outfile for writing, exiting...");
    exit_application(1);
}

extract_data();

exit_application(0);

=pod

=head1 TO DO

=over 4

=item *

Ensure that all fields in each row are printed in the same sequence.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
