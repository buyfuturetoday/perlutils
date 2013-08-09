=head1 NAME

WRSSimpleCharts.pl - Script to extract data from the CAUM4WS table and convert it into charts. 

=head1 VERSION HISTORY

version 1.0 17 September 2006 DV

=over 4

=item *

Initial Release based on the WRSExtractData script.

=back

=head1 DESCRIPTION

The script will connect to the CAUM4WS database and extract data. The data will be converted into Charts, one chart per group / identifier combination.


=head1 SYNOPSIS

 WRS2Chart.pl [-t] [-l log_dir] [-d datasource]

    WRS2Chart.pl -h	    Usage
    WRS2Chart.pl -h 1	    Usage and description of the options
    WRS2Chart.pl -h 2	    All documentation

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

my ($logdir, $cawrmdb, @xvals, @yvals, @identifierID, $group, $name, $invalid_resp_time, $starttime, $endtime);
my $dsource = "CAUM4WS";	    # Data source name
# my $starttime = "9/14/06 16:00";  # Start Time, format MMDDYY HH:MM
# my $endtime   = "9/14/06 20:00";  # End Time, format MMDDYY HH:MM
my $interval = 4;		    # Interval (hours)
my $cnt = 0;
my $outdir = "d:/em/data/reps/adhoc";
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
use GD::Graph::lines;		    # Produce Line charts

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

sub create_chart() {
    my $xpoints = 16;
    my $xlength = @xvals;
    my $xskip = int($xlength/$xpoints); 
    my $ylength = @yvals;
    my $fromtime = substr($starttime,11);
    my $totime = substr($endtime,11);
    if (not ($xlength == $ylength)) {
	error ("X-array and Y-array not same length, cannot make graph.");
    } else {
	my @data = (\@xvals,\@yvals);
	my $mygraph = GD::Graph::lines->new(600, 400);
	my $graphsetres = $mygraph->set(
				x_label     => 'Measurement (Note: negative Response Time values indicate error or timeout in response)',
				y_label     => 'Response Time (ms)',
				title       => "Response $group for $name from $fromtime to $totime",
				x_label_skip => $xskip,
				x_all_ticks => 1,
				zero_axis_only => 1);
	if (not defined $graphsetres) {
	    error("Could not set Graph for Device $group instance $name");
	} else {
	    my $myimage = $mygraph->plot(\@data) or die $mygraph->error;
	    # Open Output file
	    my $outfile = $outdir."/$group"."_$name.png";
	    my $openres = open(OutFile, ">$outfile");
	    if (not defined $openres) {
		error("Cannot open $outfile for writing, exiting...");
	    } else {
		binmode OutFile;
		print OutFile $myimage->png;
		close OutFile;
	    }
	}
    }
}

sub prepare_arrays($) {
    my ($recordref) = @_;
    my %record = %$recordref;
    push @xvals, substr($record{TimeStart},11,5);
    if (($record{NewSumStatID} ==2) or ($record{NewSumStatID} ==3)){
	push @yvals, $record{'Response (ms)'};
    } else {
	push @yvals, $invalid_resp_time;
    }
}

=pod

=head2 Extract Data

Extract data and output all data in csv format.

=cut

sub extract_data($) {
    my ($identifier) = @_;
    # Determine max Response Time to have nice graph in negative values
    # Find max from all successful response times
    # 15% from max value is negative value
    my $sql = "SELECT MAX(RespTime) AS RespTime FROM WRM
	       WHERE (WRM.IdentifierID = $identifier) and 
		     (WRM.TimeStart > '$starttime') and 
		     (WRM.TimeStart < '$endtime') and
		     ((WRM.NewSumStatID = 2) or (WRM.NewSumStatID = 3))";
    SQLquery($cawrmdb, $sql);
    if ($cawrmdb->FetchRow()) {
	my %record = $cawrmdb->DataHash();
	my $max_resp_time = $record{RespTime};
	$invalid_resp_time = - int($max_resp_time * 0.15);
    }
    # Now select all data for this identifier
    $sql = "SELECT WRMGroup.Name AS 'Group', WRMIdentifier.Name AS Identifier, WRM.TimeStart, 
		      WRM.RespTime AS 'Response (ms)', WRM.NewAccuracyStatID as 'String Check', 
                      WRM.StatusCode, WRMStatusMessage.Message,WRM.NewSumStatID
	       FROM WRM
		    INNER JOIN WRMIdentifier ON WRM.IdentifierID = WRMIdentifier.IdentifierID 
		    INNER JOIN WRMGroup ON WRM.GroupID = WRMGroup.GroupID 
		    INNER JOIN WRMStatusMessage ON WRM.StatusMessageID = WRMStatusMessage.StatusMessageID
	       WHERE (WRM.IdentifierID = $identifier) and 
		     (WRM.TimeStart > '$starttime') and 
		     (WRM.TimeStart < '$endtime')
	       ORDER BY WRM.TimeStart";
    SQLquery($cawrmdb, $sql);
    while ($cawrmdb->FetchRow()) {
	my %record = $cawrmdb->DataHash();
	$group = $record{Group};
	$name  = $record{Identifier};
	prepare_arrays(\%record);
    }
}

=pod

=head2 Select Distinct Identifiers

An array will be created that lists all different identifiers in the required time interval. Each Identifier will be used to create a separate chart.

=cut

sub select_distinct_identifiers() {
    my $sql = "SELECT distinct(IdentifierID) FROM WRM 
	       WHERE (WRM.TimeStart > '$starttime') and 
		     (WRM.TimeStart < '$endtime')";
    SQLquery($cawrmdb, $sql);
    # Extract all identifier IDs
    while ($cawrmdb->FetchRow()) {
	my %record = $cawrmdb->DataHash();
	push @identifierID, $record{IdentifierID}
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

# Calculate Interval
my $endtimesecs = time;
my $starttimesecs = $endtimesecs - ($interval * 3600);
my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($endtimesecs);
$endtime = sprintf "%02d/%02d/%04d %02d:%02d", $mon+1, $mday, $year+1900, $hour,$min;
($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($starttimesecs);
$starttime = sprintf "%02d/%02d/%04d %02d:%02d", $mon+1, $mday, $year+1900, $hour,$min;
logging("Working from $starttime to $endtime");


# Open Handle to read database
if (!($cawrmdb = new Win32::ODBC($dsource))) {
    error("Data Source $dsource (CAUM4WS) Open failed: ".Win32::ODBC::Error());
    exit_application(1);
}

select_distinct_identifiers();

foreach my $identifier (@identifierID) {
    extract_data($identifier);
    create_chart();
    # Clean Arrays for next run
    @xvals = ();
    @yvals = ();
}

exit_application(0);

=pod

=head1 TO DO

=over 4

=item *

Calculate Start and end time for the last four hours.

=item *

Clear display of Invalid times. 

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>


