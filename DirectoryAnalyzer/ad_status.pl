=head1 NAME

ad_status - This script finds the status of the Active Directory network at a specific point in time.

=head1 VERSION HISTORY

version 1.1 8 August 2002 DV

=over 4

=item *

Accept date/time to retrieve the status of the Active Directory network.

=back

version 1.0 23 July 2002 DV

=over 4

=item *

Initial Release.

=back

=head1 DESCRIPTION

This script collects the status of the Active Directory monitoring at a specific time. The status is sent to the WorldView BPV by creating and linking trap objects.

This allows to simulate alerts available in the active directory database as of a specific date/time, without the need to process all events prior the the date/time.

The script assumes a clean Business Process View, containing only the sites and the servers. It will not synchronize the business process view by removing previously existing traps.

=head1 SYNOPSIS

ad_status [-t] [-l log_dir] [-d datasource] [-e event_management_server] [-s status_date_time]

    ad_status -h	    Usage
    ad_status -h 1	    Usage and description of the options
    ad_status -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: c:\temp

=item B<-d datasource>

The data source name pointing to the DirectoryAnalyzer database. Default: DA. 

=item B<-e event_management_server>

The server where the Unicenter Event Management server is running. This server will receive the SNMP traps. Default: bemew2064231.

The server name must be a name, not a dotted IP address. The translation from name to IP address is done in the application. (The application fails if the translation cannot be done).

=item B<-s status_date_time>

The date (and time) for which to determine the status of the Active Directory network. Default is to handle all available alerts in the database (Real time situation). For other values, the application will test if the given date/time is between the start and the end of the reporting. If not, the value will not be accepted. Valid input values are MM/DD/YYYY or "MM/DD/YYYY H:MM:SS AM" I<or PM>.

B<Be careful> to add a valid date and time. The program will fail if no valid date is added.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.6.1, build 631 provided by ActiveState.

Due to the nature of the problem, the script should only be used on Windows platforms.

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my $trace = 0;			    # 0: no tracing, 1: tracing
my $logdir = "c:/temp";		    # Log file directory
my $log = 1;			    # 0: no logging, 1: logging
my $dsource = "DA";		    # Data source name
my $dadb;			    # Pointer to the DirectoryAnalyzer Database
my $site_class = "LargeCity";		# Site Class name
my $server_class = "Large_Factory";	# Server Class name
my $site_class = "Application";		# Site Class name
my $server_class = "Application";	# Server Class name
my @alerts;			    # Array of different alert types
my %site = ();			    # Site Table hash
my %server = ();		    # Server Table hash
my $session;			    # SNMP Session object
my $snmp_error;			    # Error pointer in SNMP object
my $start_dt;			    # Date/time to calculate current status
my $sql_datetime = "";
my $da_enterprise = "1.3.6.1.4.1.1593.3.3.2.2";
my $da_severity = "1.3.6.1.4.1.1593.3.3.2.3.1";
my $da_server   = "1.3.6.1.4.1.1593.3.3.2.3.2";
my $da_site     = "1.3.6.1.4.1.1593.3.3.2.3.3";
my $da_nc       = "1.3.6.1.4.1.1593.3.3.2.3.4";
my $generic = 6;
my $host = "bemew2064231";
my $host_IP = "150.251.92.241";	    # NetPro DA Enterprise Agent console

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use File::Basename;		    # logfilename translation
use Win32::ODBC;		    # Win32 ODBC module
use Net::SNMP;			    # SNMP session management

#############
# subroutines
#############

sub error($) {
    my($txt) = @_;
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
    print "$datetime - Error: $txt\n";
    logging($txt);
}

sub trace($) {
    if ($trace) {
	my($txt) = @_;
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
	print "$datetime - Trace: $txt\n";
	logging($txt);
    }
}

# SUB - Open LogFile
sub open_log() {
    if ($log == 1) {
	my($scriptname, undef) = split(/\./, basename($0));
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $logfilename=sprintf(">>$logdir/$scriptname%04d%02d%02d.log", $year+1900, $mon+1, $mday);
	open (LOGFILE, $logfilename);
	# open (STDERR, ">&LOGFILE");	    # STDERR messages into logfile
	# Ensure Autoflush for Log file...
	my $old_fh = select(LOGFILE);
	$| = 1;
	select($old_fh);
    }
}

# SUB - Handle Logging
sub logging($) {
    if ($log == 1) {
	my($txt) = @_;
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
	print LOGFILE $datetime." * $txt"."\n";
    }
}

# SUB - Close log file
sub close_log() {
    if ($log == 1) {
	close LOGFILE;
    }
}

sub exit_application($) {
    my($return_code) = @_;
    if (defined $dadb) {
	$dadb->Close();
	logging("Close Database connection.");
    }
    if (defined $session) {
	$session->close;
	logging("Close SNMP session.");
    }
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

=head2 Collect Alerts

This procedure will collect the different alert types that are available in the Alerts table in the DirectoryAnalyzer database.

=cut

sub collect_alerts($) {
    my ($objectid) = @_;
    my $nr_alerts = 0;
    @alerts = ();
    my $query = "SELECT distinct(AlertType) from Alert where ObjectID = $objectid";
    SQLquery($dadb, $query);
    while ($dadb->FetchRow()) {
        my %recordhash = $dadb->DataHash();
        push @alerts, ($recordhash{"AlertType"});
        $nr_alerts++;
    }
    logging("$nr_alerts different alert types detected for ObjectId $objectid.");
}

=pod

=head2 Collect Sites

This procedure collects the different site ObjectIDs and Names that are available in the DirectoryAnalyzer database.

=cut

sub collect_sites() {
    my $nr_sites = 0;
    my $query = "SELECT ObjectID, Name from Site";
    SQLquery($dadb, $query);
    while ($dadb->FetchRow()) {
        my %recordhash = $dadb->DataHash();
	my $key = $recordhash{"ObjectID"};
	my $value = $recordhash{"Name"};
	$site{$key} = $value;
	$nr_sites++;
    }
    logging("$nr_sites different sites detected.");
}

=pod

=head2 Alerts per Site

For each site the number of different alert types is collected. For each alert type the most recent status is requested. If the status is warning or critical, a corresponding trap is fired.

=cut

sub alerts_per_site() {
    my $nr_sitealerts = 0;
    foreach my $objectid (keys %site) {
	my $sitename = $site{$objectid};
	collect_alerts($objectid);
	foreach my $alerttype (@alerts) {
	    print "Investigate $sitename - $alerttype\n";
	    my $query = "SELECT AlertState, AlertTime 
			 FROM Alert 
			 WHERE AlertTime = 
			    (SELECT max(AlertTime) 
			     FROM Alert 
			     WHERE ObjectID=$objectid AND
				   AlertType=$alerttype 
				   $sql_datetime)";
logging($query);
	    SQLquery($dadb, $query);
	    if ($dadb->FetchRow()) {
		my %recordhash = $dadb->DataHash();
		my $alertstate = $recordhash{"AlertState"};
		my $alerttime = $recordhash{"AlertTime"};
		logging "$sitename - $alerttype - $alertstate - $alerttime";
		if ($alertstate > 1) {
		    sendtrap($alerttype, $alertstate, "site", $sitename);
		}
	    }
	    $nr_sitealerts++;
	}
    }
    logging("$nr_sitealerts alerts for all sites have been investigated.");
}	    

=pod

=head2 Collect Servers

For each server the number of different alert types is collected. For each alert type the most recent status is requested. If the status is warning or critical, a corresponding trap is fired.

=cut

sub collect_servers() {
    my $nr_servers = 0;
    my $query = "SELECT ObjectID, Name from Server";
    SQLquery($dadb, $query);
    while ($dadb->FetchRow()) {
        my %recordhash = $dadb->DataHash();
	my $key = $recordhash{"ObjectID"};
	my $value = $recordhash{"Name"};
	$server{$key} = $value;
	$nr_servers++;
    }
    logging("$nr_servers different servers detected.");
}
=pod

=head2 Alerts per Server

For each server every alert is tested on the most recent occurence before the date given. If the corresponding alert state is 2, a warning trap is sent. If the state is 3, a critical trap is sent.

=cut

sub alerts_per_server() {
    my $nr_serveralerts = 0;
    foreach my $objectid (keys %server) {
	my $servername = $server{$objectid};
	collect_alerts($objectid);
	foreach my $alerttype (@alerts) {
	    print "Investigate $servername - $alerttype\n";
	    my $query = "SELECT AlertState, AlertTime 
			 FROM Alert 
			 WHERE AlertTime = 
			    (SELECT max(AlertTime) 
			     FROM Alert 
			     WHERE ObjectID=$objectid AND
				   AlertType=$alerttype 
				   $sql_datetime)";
logging($query);
	    SQLquery($dadb, $query);
	    if ($dadb->FetchRow()) {
		my %recordhash = $dadb->DataHash();
		my $alertstate = $recordhash{"AlertState"};
		my $alerttime = $recordhash{"AlertTime"};
		logging "$servername - $alerttype - $alertstate - $alerttime";
		if ($alertstate > 1) {
		    sendtrap($alerttype, $alertstate, "server", $servername);
		}
	    } else {
		logging "$servername - $alerttype - no info found";
	    }
	    $nr_serveralerts++;
	}
    }
    logging("$nr_serveralerts alerts for all servers have been investigated.");
}	    

=pod

=head2 Send Trap

This procedure assembles all available information into a proper SNMP Trap string and sends the trap to the destination host.

=cut

sub sendtrap($$$$) {
    my ($specific, $severity, $value2_class, $value2_val) = @_;
    my @oidvalue = ($da_severity, INTEGER, $severity);
    my @addvalue;
    if ($value2_class eq "server") {
        @addvalue = ($da_server, OCTET_STRING, $value2_val);
    } else {
        @addvalue = ($da_site, OCTET_STRING, $value2_val);
    }
    push @oidvalue, @addvalue;
    my $timeticks = 1052648777;
    my $response = $session->trap(-enterprise      => $da_enterprise,
                           -agentaddr       => $host_IP,
			   -generictrap     => $generic,
                           -specifictrap    => $specific,
                           -timestamp       => $timeticks,
			   -varbindlist	    => \@oidvalue,
    );
    if (defined $response) {
	trace("Trap $specific send. Severity $severity, Name $value2_val");
    } else {
	error("Could not send trap $specific. Severity $severity, Name $value2_val");
    }
}

=pod

=head2 Create SNMP Session

This procedure will create an SNMP session to the Event Management Host

=cut

sub create_snmp() {
    ($session, $snmp_error) = Net::SNMP->session(
					Hostname => $host,
					Port => 162);	# No default value for port is accepted!
    if (defined $session) {
	logging("SNMP Session created");
	trace("SNMP Session created");
    } else {
	logging("SNMP Session could not be created: $snmp_error");
	trace("SNMP Session could not be created: $snmp_error");
	exit_application(1);
    }
}

######
# Main
######

# Handle input values

my %options;
getopts("tl:d:e:s:h:", \%options) or pod2usage(-verbose => 0);
# my $arglength = scalar keys %options;  
# if ($arglength == 0) {		# If no options specified,
#    $options{"h"} = 0;			# display usage.
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
    $trace = 1;
    trace("Trace enabled");
}
# Find log file directory
if ($options{"l"}) {
    $logdir = $options{"l"};
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
# Event Management Server
if ($options{"e"}) {
    $host = $options{"e"};
}
# Start date/time
if (defined $options{"s"}) {
    $start_dt = "#" . $options{"s"} . "#";
}
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Open Handle to DirectoryAnalyzer database
if (!($dadb = new Win32::ODBC($dsource))) {
    error("Data Source $dsource (Alert) Open failed: ".Win32::ODBC::Error());
    exit_application(1);
}

# Verify if start date/time is valid
if (defined $start_dt) {
    my $query = "SELECT count(*) FROM Alert WHERE AlertTime < $start_dt"; 
    SQLquery($dadb, $query);
    if ($dadb->FetchRow()) {
	my %recordhash = $dadb->DataHash();
	my(undef,$count) = %recordhash;
	if ($count == 0) {
	    error("No alerts before start date $start_dt");
	    exit_application(1);
	} else {
	    $sql_datetime = "AND AlertTime < $start_dt";
	}
    }
}

# Create SNMP session
create_snmp();

# Collect sites
collect_sites();

# Collect Information for all sites
alerts_per_site();

# Collect all servers
collect_servers();

# Collect information for all servers
alerts_per_server();

exit_application(0);

=pod

=head1 TO DO

=over 4

=item *

Add date and time as input parameters

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
