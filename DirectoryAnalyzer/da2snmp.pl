=head1 NAME

da2snmp - Translate the alerts in the DirectoryAnalyzer database into SNMP traps

=head1 VERSION HISTORY

version 1.3 6 August 2002 DV

=over 4

=item *

Add date/time of alert in the print to STDOUT message for better understanding.

=item *

Add sleep 2 after firing trap to avoid workstation overload. Currently the ODBC drivers are used to read the alerts from the Access database and during Unicenter processing for accepting the alerts. This sleep should be removed for performance testing and when trying to find out the performance limits.

=back

version 1.2 5 August 2002 DV

=over 4

=item *

Accept date/time to start generating SNMP traps from alerts.

=back

version 1.1 23 July 2002 DV

=over 4

=item *

Add the sleeptime or interactive control switch. 

=item *

Display the alert before firing, not after.

Sleeptime is the number of seconds to wait between firing the alerts. Sleeptime of 0 or negative means interactive mode: the script waits for user input before firing the next alert.

=back

version 1.0 16 July 2002 DV

=over 4

=item *

Initial Release.

=back

=head1 DESCRIPTION

This script reads all alerts in the DA database, converts each alert into the corresponding SNMP trap and sends the SNMP trap to a Unicenter console.

=head1 SYNOPSIS

 da2snmp [-t] [-l log_dir] [-d datasource] [-e event_management_server] [-s sleeptime] [-a alert_date_time]

    da2snmp -h		    Usage
    da2snmp -h 1	    Usage and description of the options
    da2snmp -h 2	    All documentation

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

=item B<-s sleeptime>

Sleeptime is the number of seconds to wait between firing the alerts. Sleeptime of 0 or negative means interactive mode: the script waits for user input before firing the next alert. Default: sleeptime = 10 (seconds).

=item B<-a alert_date_time>

The date (and time) to start generating SNMP traps from alerts. This should be the same value as specified with the B<-s> parameter for the ad_status.pl application. Default value is to handle all alerts in the database. For other values, the application will test if the given date/time is between the start and the end of the alerts in the database. If not, the value will not be accepted. Valid input values are MM/DD/YYYY or "MM/DD/YYYY H:MM:SS AM" I<or PM>.

B<Be careful> to add a valid date and time. The program will fail if no valid value is added.


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
my $host = "bemew2064231";	    # Unicenter Event Management server
my $host_IP = "150.251.92.241";	    # NetPro DA Enterprise Agent console
my $dadb;			    # Pointer to the DirectoryAnalyzer Database
my %object = ();		    # Object Table hash
my %site = ();			    # Site Table hash
my %server = ();		    # Server Table hash
my %nc = ();			    # Naming Context hash
my %replica_server = ();	    # Replica Server table hash
my %replica_nc = ();		    # Replica NC table hash
my $sleeptime = 5;		    # Time to sleep between firing alerts
my $nr_alerts = 0;
my $site = 1;
my $server = 2;
my $nc = 4;
my $replica = 8;
my $sql_datetime = "";
my $start_dt;

my $session;			    # SNMP session object
my $snmp_error;			    # Error pointer in SNMP object
my $da_enterprise = "1.3.6.1.4.1.1593.3.3.2.2";
my $da_severity = "1.3.6.1.4.1.1593.3.3.2.3.1";
my $da_server   = "1.3.6.1.4.1.1593.3.3.2.3.2";
my $da_site     = "1.3.6.1.4.1.1593.3.3.2.3.3";
my $da_nc       = "1.3.6.1.4.1.1593.3.3.2.3.4";
my $generic = 6;

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
use Net::SNMP;			    # To build SNMP connections

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
    logging("$nr_alerts alerts have been handled.");
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

=head2 Handle Alerts

The procedure handle selects all alerts from  the DA database and calls the procedure to translate the alert data into SNMP.

=cut

sub handle_alerts() {
    my $query = "SELECT ObjectID, AlertType, AlertTime, AlertState 
		    FROM Alert $sql_datetime
		    ORDER BY AlertTime";
    SQLquery($dadb, $query);
    while ($dadb->FetchRow()) {
	my %recordhash = $dadb->DataHash();
	my $objectid = $recordhash{"ObjectID"};
	my $alerttype = $recordhash{"AlertType"};
	my $alertstate = $recordhash{"AlertState"};
	my $alerttime = $recordhash{"AlertTime"};
	$nr_alerts++;
	convert2trap($objectid, $alerttype, $alertstate, $alerttime);
    }
}

=pod

=head2 Convert to trap

The convert to trap procedure gets the relevant alert data (objectid, alerttype and alertstate) as input and formats an SNMP trap with this data. The alerttype translates to the SNMP specific trap, the alertstate is the value1, which is the severity (1: clear, 2: warning, 3: critical) of the alert, from the SNMP trap. The remaining part of the SNMP string translates depending on the alerttype.

=over 4

=item AlertType 28, 29

These are DirectoryAnalyzer License related alerts. The objectID for these alerts is ignored. (note that these alerts are not yet in use.)

=item AlertType 15, 41, 43, 44, 54

These alerts are replication specific. The ObjectID translates to a replica object. The SNMP trap requires the corresponding Server name as value 2 and NC name as value 3.

=item Other Alerts

For all other alerts, the ObjectID must be translated into its object class. The corresponding name is used for value 2 in the SNMP trap.

=back

B<Note> that virtually no back-checking is done at the moment. It is assumed that the DA database is consistent.

=cut

sub convert2trap($$$$) {
    my ($objectid, $specific, $severity, $alerttime) = @_;
    my ($value2_class, $value2_val, $value3_val);
    if (($specific == 28) or 
        ($specific == 29)) {
	    $value2_class = "";
	    $value2_val = "";
	    $value3_val = "";
    } elsif 
       (($specific == 15) or
        ($specific == 41) or
	($specific == 43) or
	($specific == 44) or 
	($specific == 54)) {
	    $value2_class = "server";
	    $value2_val = $replica_server{$objectid};
	    $value3_val = $replica_nc{$objectid};
    } else {
	    $value2_class = $object{$objectid};
	    $value3_val = "";
	    if ($value2_class eq "server") {
		$value2_val = $server{$objectid};
	    } elsif ($value2_class eq "site") {
		$value2_val = $site{$objectid};
	    } else {
		$value2_val = $nc{$objectid};
	    }
    }
    print "Next: Trap $specific for object $value2_val, severity $severity at $alerttime\n";
    if ($sleeptime > 0) {
        print "Sleeping for $sleeptime seconds ...\n";
        sleep $sleeptime;
    } else {
        print "Press <Return> to fire alert.";
        my $inp_value = <STDIN>;
    }
    sendtrap($specific, $severity, $value2_class, $value2_val, $value3_val);
}

=pod

=head2 Send Trap

This procedure assembles all available information into a proper SNMP Trap string and sends the trap to the destination host.

=cut

sub sendtrap($$$$$) {
    my ($specific, $severity, $value2_class, $value2_val, $value3_val) = @_;
    my @oidvalue = ($da_severity, INTEGER, $severity);
    my @addvalue;
    if (not ($value2_class eq "")) {
	if ($value2_class eq "server") {
	    @addvalue = ($da_server, OCTET_STRING, $value2_val);
	} elsif ($value2_class eq "site") {
	    @addvalue = ($da_site, OCTET_STRING, $value2_val);
	} else {
	    @addvalue = ($da_nc, OCTET_STRING, $value2_val);
	}
	push @oidvalue, @addvalue;
	if (not ($value3_val eq "")) {
	    @addvalue = ($da_nc, OCTET_STRING, $value3_val);
	    push @oidvalue, @addvalue;
	}
    }
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
    sleep 2;	# Additional sleep time to avoid workstation overload
}

=pod

=head2 Initialize Tables

The Directory Analyzer configuration information is extracted from the database into hashes for performance reasons. This will avoid a number of SQL queries per alert, since ObjectID to servername, to site, ... information is available in the script

=cut

sub initialize_tables() {
    initialize_object();
    initialize_server();
    initialize_site();
    initialize_nc();
    initialize_replica();
}

=pod

=head2 Initialize Object

The Object_ table knows for each ObjectID the corresponding Object class. Currently there are 4 different object classes in use:

=over 4

=item 1 site

=item 2 server

=item 4 nc (naming context)

=item 8 replica

=back

With an object ID, find the object class. In the corresponding table, find the name for the object.

=cut

sub initialize_object() {
    my $nr_objects = 0;
    SQLquery($dadb, "SELECT ObjectID, ObjectClass from Object_");
    while ($dadb->FetchRow()) {
	my %recordhash = $dadb->DataHash();
	my $key = $recordhash{"ObjectID"};
	my $value = $recordhash{"ObjectClass"};
	if ($value == 1) {
	    $object{$key} = "site";
	} elsif ($value == 2) {
	    $object{$key} = "server";
	} elsif ($value == 4) {
	    $object{$key} = "nc";
	} elsif ($value == 8) {
	    $object{$key} = "replica";
	} else {
	    error("Don't know class for objectclass $value assigned to ObjectID $key.");
	}
	$nr_objects++;
    }
    logging("$nr_objects objects have been added.");
}

=pod

=head2 Initialize Server

The Server table knows for every Server ObjectID the corresponding server name.

=cut

sub initialize_server() {
    my $nr_servers = 0;
    SQLquery($dadb, "SELECT ObjectID, Name from Server");
    while ($dadb->FetchRow()) {
	my %recordhash = $dadb->DataHash();
	my $key = $recordhash{"ObjectID"};
	my $value = $recordhash{"Name"};
	$server{$key} = $value;
	$nr_servers++;
    }
    logging("$nr_servers servers have been added");
}

=pod

=head2 Initialize Site

The Site table knows for every Site ObjectID the corresponding site name.

=cut

sub initialize_site() {
    my $nr_sites = 0;
    SQLquery($dadb, "SELECT ObjectID, Name from Site");
    while ($dadb->FetchRow()) {
	my %recordhash = $dadb->DataHash();
	my $key = $recordhash{"ObjectID"};
	my $value = $recordhash{"Name"};
	$site{$key} = $value;
	$nr_sites++;
    }
    logging("$nr_sites sites have been added");
}

=pod

=head2 Initialize nc (Naming Context)

The Naming context table knows for every nc ObjectID the corresponding naming context. Currently there are 3 different naming contexts defined:

=over 4

=item Schema

=item Configuration

=item Domain name (one additional NC per domain name?)

=back

=cut

sub initialize_nc() {
    my $nr_ncs = 0;
    SQLquery($dadb, "SELECT ObjectID, Name from NC");
    while ($dadb->FetchRow()) {
	my %recordhash = $dadb->DataHash();
	my $key = $recordhash{"ObjectID"};
	my $value = $recordhash{"Name"};
	$nc{$key} = $value;
	$nr_ncs++;
    }
    logging("$nr_ncs naming contexts have been added");
}

=pod

=head2 Initialize Replica

Every replica object is a relation between a naming context and a server name. This section collects the replica object / server name portion in the replica_server hash and the replica object / naming context portion in the replica_nc hash.

In the replica table, the server object and the nc object is referenced using their GlobalUID. This is added to the respective hashes first. When each hash is complete, then all the GlobalUIDs are replaced with the proper server names or NC names.

=cut

sub initialize_replica() {
    my $nr_replica = 0;
    SQLquery($dadb, "SELECT ObjectID, NCGlobalUID, ServerGlobalUID from Replica");
    while ($dadb->FetchRow()) {
	my %recordhash = $dadb->DataHash();
	my $key = $recordhash{"ObjectID"};
	my $value = $recordhash{"ServerGlobalUID"};
	my $nc_value = $recordhash{"NCGlobalUID"};
	$replica_server{$key} = $value;
	$replica_nc{$key} = $nc_value;
	$nr_replica++;
    }
    foreach my $key (keys %replica_server) {
    	my $globalUID = $replica_server{$key};
	SQLquery($dadb, "SELECT Name FROM Server WHERE GlobalUID = \'$globalUID\'");
	if ($dadb->FetchRow()) {
	    my %recordhash = $dadb->DataHash();
	    $replica_server{$key} = $recordhash{"Name"};
	} else {
	    error("Cannot find Name for ServerGlobalUID $replica_server{$key} in Server Table.");
	}
    }	
    foreach my $key (keys %replica_nc) {
    	my $globalUID = $replica_nc{$key};
	SQLquery($dadb, "SELECT Name FROM NC WHERE GlobalUID = \'$globalUID\'");
	if ($dadb->FetchRow()) {
	    my %recordhash = $dadb->DataHash();
	    $replica_nc{$key} = $recordhash{"Name"};
	} else {
	    error("Cannot find Name for NCGlobalUID $replica_nc{$key} in NC Table.");
	}
    }	
    logging("$nr_replica replica objects have been added");
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
getopts("tl:d:e:s:a:h:", \%options) or pod2usage(-verbose => 0);
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
# Sleeptime
if (defined $options{"s"}) {
    $sleeptime = $options{"s"};
}
# Start date/time
if (defined $options{"a"}) {
    $start_dt = "#" . $options{"a"} . "#";
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
    my $query = "SELECT count(*) FROM Alert WHERE AlertTime >= $start_dt"; 
    SQLquery($dadb, $query);
    if ($dadb->FetchRow()) {
	my %recordhash = $dadb->DataHash();
	my(undef,$count) = %recordhash;
	if ($count == 0) {
	    error("No alerts before start date $start_dt");
	    exit_application(1);
	} else {
	    $sql_datetime = "WHERE AlertTime >= $start_dt";
	}
    }
}

# Open snmp session
create_snmp();

# Initialize the tables
initialize_tables();

# Handle all alerts
handle_alerts();

exit_application(0);

=pod

=head1 TO DO

=over 4

=item *

Specify a start date/time and an end date/time for the alerts to be processed/

=item *

Handle the time ticks per alert. time = 0: time of the first alert. Use timeticks to identify alerts.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
