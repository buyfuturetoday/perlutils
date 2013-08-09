=head1 NAME

DB_connection - This script tests connectivity to various databases.

=head1 VERSION HISTORY

version 2.4 5 March 2007 DV

=over 4

=item *

Connectivity problems in PrintError are now also printed to the logfile by default.

=back

version 2.3 9 February 2007 DV

=over 4

=item *

Add processing for Oracle and Microsoft SQL databases.

=back

version 2.2 9 August 2006 DV

=over 4

=item *

Change smcpcopy file processing to create one file per hour.

=item *

Add input parameter to specify IP part of the SMCpcopy filename.

=back

version 2.1 26 April 2006 DV

=over 4

=item *

Replace cawto with logforward so that the originating hostname can be specified.

=back

version 2.0 20 March 2006 DV

=over 4

=item *

Add reporting into SMCpcopy file

=item *

Add status file to allow to send only status change.

=back

version 1.1 01 January 2006 DV

=over 4

=item *

Verify if the path contains statements to Sybase. If not, add c:\SYBASE\DLL;C:\SYBASE\BIN to the path. (Note: or you install Sybase in the default directory, or you make sure that the path is correct...)

=item *

Add printerror as a command line parameter. Note that the printerror will dump error messages on STDOUT, not to the Log file. This should be OK since printerror should only be used in debug sessions and never in normal running mode.

=back

version 1.0 29 November 2005 DV

=over 4

=item *

Initial release, based on the MySQL_Connection script. This script has been extended for more database types. Currently Sybase and MySQL are supported. Other database types will be added as requested.

=back

=head1 DESCRIPTION

This script tests the connectivity to a number of Database servers. A connection attempt is made to the default database. If the connection is not successful, then a cawto-logforward alert is sent to an event console.

The script must run at regular intervals. All database servers are checked at each interval. No logic is available currently to test connectivity at different intervals for different servers. Scheduling must be done from an external application, for example the scheduling mechanism that is available on the OS.

The CA log agent cailoga2 should be configured to watch for 'ERROR' strings in the log file, and to watch for file size changes on every run (typically every 5 minutes). If there is no file size change, then the script did not run.

=head2 Debugging Failing Connections

Failing database server connections are in many cases due to two reasons. The most important reason is because the database server itself is failing, and the purpose of this application is to spot this condition. (Of course the connectivity information including username, password, servername, database name, port number, etc ... have been verified and are not the reason for the failing connection.)

However and especially during initial installation and configuration, it may be that the database connection fails due to invalid configuration of the database client driver on the monitoring server. To trap this kind of errors, the value of the variable B<PrintError> in DBI->connect can be set to 1 and the script needs to be started in interactive mode. The value RaiseError should remain 0. If RaiseError is set to 1 it will cause the script to die in case of errors, which prevents the exit_application procedure to do the clean-up - or subsequent connectivity tests to be performed.

=head1 SYNOPSIS

DB_Connection.pl [-t] [-l log_dir] [-n] [-i db_servers.ini] [-s sybase_interface_file] [-e Event_Server] [-d] [-c current_status_dir] [-p SMCpcopy_dir] [-a SMCpcopy_IPAddress]

    DB_Connection -h	 Usage
    DB_Connection -h 1   Usage and description of the options
    DB_Connection -h 2   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: c:\temp. Logging is enabled by default. 

=item B<-n>

Disable logging if set.

=item B<-i db_servers.ini>

(Path and) filename of the ini file containing all database server information. Default 'db_servers.ini' in the same directory as the script. The format of the ini file is 

    [Servername]
    user = username
    pwd = password
    db_type = I<DatabaseType>
    ip = I<IPAddress>
    hostname = I<hostname>

The servername is the database server name, that will be used in the database connectivity string. The servername is enclosed by block brackets, next line must be for user, followed by a line for password. The password value may be blank or omitted.

The db_type (Database type) is mandatory on each servername. Currently the database type is limited to 

 MySQL
 Sybase
 Oracle
 MSSQL

Supported database servers will be extended as required.

The ip address is required as field in the SMCPcopy file.

The hostname is required to add into the event field. If the hostname is not available, then the [Servername] will be used. This may work for MySQL servers, but not for Sybase servers as the Servername is a database server name and not a host system name.

For Oracle databases, two additional parameters may be specified:

 port=I<port-number> (default 1521)
 SID=I<SID-Identifier> (default ORCL)

Cluster support can be implemented by specifying additional cluster parameters:

 cluster = I<clustername>
 cluster_ip = I<cluster_ip>

If the same clustername appears in two nodesections, then these two nodes are threated as belonging to the same cluster. For a cluster a special 'cluster line' will be printed in the reporting file with the maximum availability over both nodes. B<Note:> do not use this function, as cluster reporting is an eSLR functionality!

=item B<-s sybase_interface_file>

Path and filename of the sybase interface file. If specified, then it is checked if the file is readable. If not specified, then there is no check if the default file is readable since this may not be available if there are no sybase databases. Default: c:/sybase/ini/sql.ini.

The sybase interface file need to be created as described in the Sybase Documentation.

=item B<-e Event_Server>

The Event Management Server to send the alerts to using cawto. Note that connectivity is only checked when there is an alert, so be sure run the application with 'Informational Events' at least once to verify Event Connectivity. Default: none. This means that no event record will be send to the event console.

=item B<-d>

If specified, then the PrintError variable in the Connect Statement will be set to 1. This may help to see more debug information during connectivity testing. By default, the PrintError value is set to 0, so that there is no debug information.

=item B<-c current_status_dir>

Directory where the Current Status file will be stored. By default, this is the directory where the script is stored. If the file does not exist, then any current status will be 'Unkown' and the time interval will be 10. File existance is not required, only helpful. Therefore the script will not check if the directory exists and is accessible. 

The status file status.txt consists of key=value pairs. One key has the timestamp of the last measurements, other keys are database names, values are up/down.

=item B<-p SMCpcopy_dir>

Directory where the SMCpcopy file is stored. By default, this is the directory where the script is stored.

=item B<-a SMCpcopy_IPAddress>

If specified, then the value is used as the IP address to insert into the SMCpcopy filename. By preference, the IP address is extracted automatically from the system.

Please make sure that the format (IP Address with underscores instead of dots) required for the eSLR import is used.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP Professional, Perl v5.8.8 build 820 provided by ActiveState. This is the minimum version due to a bug in the Perl Oracle implementation!

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my $logdir;
my $db_servers_file = "DB_Servers.ini";
my ($server, $username, $password, %status, %curr_status, %ini);
my ($curr_time, $hostIP);
my @supported_databases = ("Sybase", "MySQL", "Oracle", "MSSQL");
my (%supported_db_hash, $smcpcopy_file, $status_dir, $statusfile, $time_int);
my $smcpcopy_dir = "d:/em/data/reporting";		# smcpcopy file directory
my $db_type = "MySQL";
my $syb_interface_file = "c:/sybase/ini/cwt_sql.ini";
my $path_ext = "c:\\sybase\\dll;c:\\sybase\\bin";
my $printerror = 0;
my $eventserver = "none";
my $timeout = 30;

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
use DBI();			    # Database Connection
use File::Basename;		    # Script installation directory
use Net::hostent;		    # hostname - IP translation
use Socket;			    # hostname - IP translation

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
    close DB_Servers;
    close SMCPcopy;
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

This procedure will read all lines in a section from a ini file. All keys will be converted to lowercase, values will remain untouched. All key/value pairs will be stored in a hash. When the section has been read completely (terminated by a new section or by end of file) the section will be handled as a whole. This reduces the need for advanced error checking during the initial file read. Duplicate keys in a section are allowed but not recommended. The last value will have precedence.

The ini file cannot use the reserved keyword I<header>.

=cut

sub read_ini_file() {
    while (my $line = <DB_Servers>) {
		chomp $line;
		# Ignore empty lines
		if (length($line) > 0) {
	    	if (substr($line,0,1) eq "[") {
				if (exists($ini{header})) {
					# All data from previous section collected,
					# now act upon it.
		    		review_params();
				}
				# Start a new section
				undef %ini;
				$line = trim($line);	# Make sure no more trailing blanks
				if (substr($line,length($line)-1,1) eq "]") {
		    		my $header = substr($line, 1, length($line)-2);	# Remove leading and trailing brackets []
		    		$ini{header} = $header;
				} else {
		    		logging("Header line not well formed $line, ignoring section");
				}
	    	} elsif (substr($line,0,1) ne "#") {
				# Ignore comment lines
				# key/value pairs for invalid headers will be added to the hash
				# but removed automatically in the next valid header
				my ($key, $value) = split (/=/, $line);
				$key = lc(trim($key));
				$value = trim($value);
				$ini{$key} = $value;
	    	}
		}
    }
    # Handle last section if available
    if (exists($ini{header})) {
		review_params();
    }
}

=pod

=head2 Review Parameters

This procedure will review available parameters. A server (header) must exists to arrive here. A username (user) is mandatory. If no password (pwd) has been specified, then a blank password will be used. The database type must be specified (db_type).

=cut

sub review_params() {
    my ($server,$user,$pwd);
    $server = $ini{header};
    if (exists($ini{db_type})) {
		$db_type = lc($ini{db_type});
    } else {
		error("No database type specified for $server");
    }
    if (exists($ini{user})) {
		$user = $ini{user};
    } else {
		error("No user defined for $server");
		return;
    }
    if (exists($ini{pwd})) {
		$pwd = $ini{pwd};
    } else {
		$pwd = "";
    }
    verify_connectivity($server,$user,$pwd);
}

=pod

=head2 Verify Connectivity

This procedure will verify the connectivity to the Database server. The connection string is build for the specific database type. Successful connections will be written to the log file and send as informational to the event manager if requested. Unsuccessful connections will be printed as an error and are always sent to the event manager.

Note that unsuccessful connection to the database is not flagged as an ERROR in the application log file. From an application point, this can be an expected condition. Unsuccessful connections are always sent to the Event Console and should be handled there. The application log file should have ERROR only on unexpected application conditions. A Log Watcher should watch for these conditions and raise an alert when they occur.

=cut

sub verify_connectivity($$$) {
    my ($server, $username, $password) = @_;
    my ($connectionstring, $dbconn_res);
    if ($db_type eq "mysql") {
		my $databasename = "mysql";
		$connectionstring = "DBI:mysql:database=$databasename;host=$server;mysql_connect_timeout=$timeout";
    } elsif ($db_type eq "sybase") {
#		my $databasename = "master";
		my $interface = $syb_interface_file;	
		$connectionstring = "DBI:Sybase:server=$server;interfaces=$interface";
    } elsif ($db_type eq "oracle") {
		# Review Oracle specific values
		my ($sid, $port);
		if (exists($ini{sid})) {
			$sid = $ini{sid};
		} else {
			$sid = "ORCL";
		}
		if (exists($ini{port})) {
			$port = $ini{port};
		} else {
			$port = "1526";
		}
		$connectionstring = "DBI:Oracle:host=$server;sid=$sid;port=$port";
    } elsif ($db_type eq "mssql") {
		my $dsn = "";
		$connectionstring = "DBI:ODBC:driver={SQL Server};Server=$server;";
    } else {
		error("Database type $db_type not yet supported");
		return;
    }
    # Connect to the database.
    my $dbh = DBI->connect($connectionstring, $username, $password,
			   {'PrintError' => $printerror,    # Set to 1 for debug info
			    'RaiseError' => 0});	    # Do not die on error
    if (defined $dbh) {
		$dbconn_res = "SUCCESS";
		# Successful connection, so disconnect as well
		my $rc = $dbh->disconnect;
		if (not defined $rc) {
    		error("Could not disconnect from $db_type server $server after successful connection.");
		}
   	} else {
		if (defined $DBI::errstr) {
			logging("$connectionstring, $username, $password - $DBI::errstr");
		}
		$dbconn_res = "FAILED";
   	}
	send_event($server,$dbconn_res);
	if (exists($ini{cluster})) {
		handle_cluster($server,$dbconn_res,$ini{cluster});
	}
}

=pod

=head2 Send Event

The Send Event procedure will forward the event to the requested event console. Each forward event must return a success. If not successful, then an error will be printed  to the log file.

This procedure will also set the current status of the measurement in the status file.

=cut

sub send_event($$) {
    my ($server,$result) = @_;
    my ($ip, $hostname, $smc_result);
    $curr_status{$server} = $result;
    # Write record to SMCPcopy file.
    if (exists($ini{ip})) {
		$ip = $ini{ip};
    } else {
		$ip = "101.101.101.101";
    }
    if (exists($ini{hostname})) {
		$hostname = $ini{hostname};
    } else {
		$hostname = $ini{header};
    }
    if ($result eq "SUCCESS") {
		$smc_result = 1;
    } else {
		$smc_result = 0;
    }
    my $smcp_record = "$ip,$db_type,$server,DBAvailability,$curr_time,$time_int,$smc_result,$smc_result,$smc_result,1\n";
    print SMCPcopy $smcp_record;
    # Check if previous status exist, and if it is equal to new status
    if (exists($status{$server}) and ($status{$server} eq $result)) {
		# Yes: only logging, no send message to console
		logging("Connection to $db_type server $server $result");
    } else {
		# No: message to console required (if console defined)
		if (not(exists($status{$server}))) {
	    	$status{$server} = "UNKOWN";
		}
		logging("Connection to $db_type server $server new status $result prev status $status{$server}");
		if ($eventserver ne "none") {
	    	my $uc_db_type = uc($db_type);
	    	my $arglist = "-n$eventserver -f$hostname -t\"$uc_db_type Connection $result to $server\"";
	    	my $cmd = "logforward $arglist";
	    	my @cmd_output = `$cmd 2>&1`;
	    	my $cmd_lines = @cmd_output;
	    	if ($cmd_lines == 0) {
#	    	logging("Successfully send record to $eventserver\n$cmd");
	    	} else {
				error("Error while sending record to $eventserver\nCommand: $cmd\n@cmd_output");
	    	}
		}
    }
    return;
}

=pod

=head2 Verify Path

This procedure will check if C:\SYBASE\DLL;C;\SYBASE\BIN is part of the path statement. If not, it will be appended to the PATH.

=cut

sub verify_path() {
    my $curr_path = $ENV{PATH};
    # Convert to lowercase to ensure that find is successful,
    # but keep original path.
    my $curr_path_lc = lc($curr_path);
    my $searchstring = "sybase";
    if (index($curr_path_lc, $searchstring) == -1) {
		$curr_path = $curr_path . ";$path_ext";
		$ENV{PATH} = $curr_path;
    }
}

=pod

=head2 Collect Previous Status

This procedure tries to find the status file from the previous check. If the file exists, then all key/value pairs are read. One key is the timestamp of the previous measurement, to be used as interval in the smcpcopy file. All other keys are the database names for which availability has been checked Up/Down.

=cut

sub collect_prev_stat() {
    $statusfile = "$status_dir/status.txt";
    if (-r $statusfile) {
		my $openres = open(Status, $statusfile);
		if (defined $openres) {
	    	while (my $line = <Status>) {
				chomp $line;
				my ($key, $value) = split(/=/,$line);
				$key = trim($key);
				$value = trim($value);
				$status{$key} = $value;
	    	}
	    	close Status;
	    	my $delfiles = unlink $statusfile;
	    	if (not($delfiles == 1)) {
				error("Statusfile $statusfile could not be deleted.");
	    	}
		} else {
	    	error("Statusfile $statusfile is readable, but could not be opened for read.");
		}
    }
}

=pod

=head2 Write Current Status

This procedure will keep track of the current status: time of the measurement (in timeticks) and status per database server.

=cut

sub write_curr_stat() {
	my $openres =  open(Status, ">$statusfile");
	if (defined $openres) {
		while (my ($key, $value) = each %curr_status) {
	    	print Status "$key=$value\n";
		}
		close Status;
    } else {
		error("Could not open $statusfile for writing");
    }
}

=pod

=head2 Open SMCPcopy file

This procedure will attempt to create a valid SMCPcopy filename and open the file. If the file cannot be opened, an error will be logged and the program will continue. The SMCPcopy filename must be: B<SMCpcopy_IPAddress_datetime.dmp>.

=cut

sub open_smcpcopy() {
    # Open smcpcopy file for status collection
    # Find local IP address
    if (not(defined $hostIP)) {
		$hostIP = "";
		if (not(my $host = gethost($ENV{COMPUTERNAME}))) {
	    	error("Cannot find IP address for localhost, use default");
	    	$hostIP = "127.0.0.1";
		} else {
	    	$hostIP = inet_ntoa($host->addr);
		}
		$hostIP =~ s/\./_/g;	    # Replace . with _ to make era folks happy
    }
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my $timeid = sprintf("%04d%02d%02d%02d",$year+1900,$mon+1,$mday,$hour);
    my $smcpcopy_file = "SMCpcopy_$hostIP"."_$timeid"."00.dmp";
    my $openres = open(SMCPcopy, ">>$smcpcopy_dir/$smcpcopy_file");
    if (not(defined $openres)) {
		error("Could not open $smcpcopy_dir/$smcpcopy_file for appending");
    }
    $curr_time = sprintf("%04d-%02d-%02d %02d:%02d:%02d",$year+1900,$mon+1,$mday, $hour, $min, $sec);
}

=pod

=head2 Handle Cluster procedure

This procedure handles cluster availability. A cluster is defined by  a key 'cluster' and a key 'cluster_ip' in the database connectivity section from the ini file. If cluster_ip is not defined, then the ip of the host will be used.

A cluster is made up of two nodes, that will be verified independently. The best connectivity from both independent nodes is the cluster connectivity. This means if both nodes are down, then the cluster is down. If at least one node is up, then the cluster is up. The first node of the cluster that is found in the db connectivity file will be used to create a hash with the cluster name. The connectivity info will be stored in the hash. When the second node of the cluster is found, then the connectivity info is compared with connectivity from the first node. The best possible connectivity info is used to call the send_event procedure, to write the SMCPcopy file, an event and the status information.

=cut

sub handle_cluster($$) {
	my ($server, $dbconn_res, $cluster) = @_;
	if (exists($$cluster{conn})) {
		# Previous cluster node has been found
		# Use cluster_ip Address in the ip address
		if (exists($ini{cluster_ip})) {
			$ini{ip} = $ini{cluster_ip};
		} else {
			$ini{ip} = $$cluster{ip};
		}
		# Check best connectivity result
		if ($$cluster{conn} eq "SUCCESS") {
			$dbconn_res = "SUCCESS";
		}
		$ini{hostname} = $cluster;
		send_event($cluster,$dbconn_res);
	} else {
		# First cluster node, save results for later usage
		$$cluster{conn} = $dbconn_res;
		if (exists($ini{cluster_ip})) {
			$$cluster{ip} = $ini{cluster_ip};
		} else {
			$$cluster{ip} = $ini{ip};
		}
	}
}

######
# Main
######

# Handle input values
my %options;
getopts("tl:ni:e:h:s:dc:p:a:", \%options) or pod2usage(-verbose => 0);
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
# Find DB_servers.ini file
if ($options{"i"}) {
    $db_servers_file = $options{"i"};
}
# Verify that the DB_Servers.ini file is readable.
if (-r $db_servers_file) {
    logging("Using $db_servers_file for Database Server information");
} else {
    error("Cannot access Database Server information file $db_servers_file, exiting...");
    exit_application(1);
}
# Find Event Server
if ($options{"e"}) {
    $eventserver = $options{"e"};
}
# Find sql.ini file
if ($options{"s"}) {
    $syb_interface_file = $options{"s"};
    if (not (-r $syb_interface_file)) {
		error("Sybase interface file $syb_interface_file not accessible for read, exiting...");
		exit_application(1);
    }
}
# Debug Connection Errors?
if (defined($options{"d"})) {
    $printerror = 1;
}
# Check for Status file directory
if (defined($options{"c"})) {
    $status_dir = $options{"c"};
} else {
    $status_dir = dirname($0);	    # Current script directory
}
# Check for SMCpcopy file directory
if (defined($options{"p"})) {
    $smcpcopy_dir = $options{"p"};
}
# Investigate if SMCpcopy IP Address is required
if (defined($options{"a"})) {
    $hostIP = $options{"a"};
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}

# End handle input value
# Add sybase\bin and sybase\dll to path if not there
verify_path();

# Collect Previous Status Information
collect_prev_stat();

# Calculate interval between measurements
if (exists $status{timestamp}) {
    my $timesec = time() - $status{timestamp};
    $time_int = int($timesec / 60);	# 60 second in a minute, need an integer result
} else {
    $time_int = 30;	    # Preferred ERA default value
}
$curr_status{"timestamp"} = time();

open_smcpcopy();

# Convert Supported Databases array to Hash for easier lookup
foreach my $value (@supported_databases) {
    $supported_db_hash{$value} = 1;
}

# Open Database Servers ini file
my $openres = open(DB_Servers, $db_servers_file);
if (not defined $openres) {
    error("Could not open $db_servers_file for reading, exiting...");
    exit_application(1);
}

# Read Database Servers ini file and collect Connection information
read_ini_file();

write_curr_stat();

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Review logfile name, consider removing the date as part of the name to allow the CA log agent to more easily find back the file.

=item *

Remove cluster processing, as cluster reporting is implemented into eSLR reporting and should not be done in this script.

=back
