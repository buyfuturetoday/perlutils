=head1 NAME

jmeterAgent - This agent script will launch a jmeter probe and act on the results.

=head1 VERSION HISTORY

version 2.0  9 October 2009 DV

=over 4

=item *

Converted to jmeterAgentThin.pl. Data is appended to csv file instead of SQL database. This is for the first release of the ThinApp appliance.

=item * 

Read config values from jmeter agent ini file. (note that there can be an agent specific ini file as well, which is discovered automatically if it exists in the agent directory).

=back

version 1.2 27 August 2009 DV

=over 4

=item *

Add switch to keep result file, used for debugging.

=item *

Add logic to try to cope with CR/LF in results. Check if bytes is defined on the line. This is expected on each result. If not defined read next line and concatenate. (Alternative solution: check number of fields in array returned by split.)

=back

version 1.1 18 August 2009 DV

=over 4

=item *

Added .ini file handling.

=item *

Get firewall settings.

=back

version 1.0 24 July 2009 DV

=over 4

=item *

Initial release, based on the Nagios JMeter plugin (see www.monitoringexchange.org, jmeter invocation plugin).

=back

=head1 DESCRIPTION

This application invokes a JMeter test plan for application monitoring. 

=head1 SYNOPSIS

jmeterAgent.pl [-t] [-l log_dir] -p jmx_test_plan [-k timeout] [-r] -i jmeter.ini

    jmeterAgent -h		    Usage
    jmeterAgent -h 1	    Usage and description of the options
    jmeterAgent -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-p jmx_testplan>

The jmeter test plan to run.

=item B<-k timeout>

Timeout value in seconds for the test plan. jmeter application will be killed if still active after this amount of time. 

=item B<-r>

If set then the result file will not be deleted. This value should be used for debugging reasons only.

Default: 60 seconds.

=item B<-i jmeter.ini>

The ini file containing the host-specific settings. This is an example of an jmeter.ini file:

 [Main]
 ; Java executable name
 java = java.exe
 ; Java directory
 javadir = C:/jre6/bin
 ; jmeter jar path and name
 jmeter = c:/jmeter/bin/ApacheJMeter.jar
 ; resultdir
 resultdir = c:/applmon/Results


=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP SP2, Perl v5.8.8, build 820 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $jmxplan, $jmobj, $dirname, $suffix);
my ($msdatetime, $applname, $resfile, $jmeterinifile, $agentinifile);
my ($java, $javadir, $jmeter, $resultdir);
my $timeout = 60;
my $exitcode = 927;
my $status = "ok";				# Initial status
my $resptime = "999999";		# Initial response time
my $errstring = "";
my $delimiter = ";";			# Delimiter for error string
my @suffixlist = (".jmx");		# Specifies suffices to extract
my $cmdext = "";				# Add extensions from ini file to jmeter launch command 
my $removeresult = "Yes";		# Input variable allows to keep result file

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use Log;					# Application and error logging
use Win32::Process;			# Win32 Process module
use File::Basename;			# Used to extract application name from a badboy testplan
use Config::IniFiles;		# Handle ini file
use Win32 qw(CSIDL_PERSONAL);

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

sub get_jmeter_ini_file() {
	# Initialize jmeteragent configuration file
	my $jmeter_ini = new Config::IniFiles(-file => $jmeterinifile);
	if (not defined $jmeter_ini) {
		error("Could not process $jmeterinifile, errors: ".join("",@Config::IniFiles::errors));
		exit_application(1);
	}
	$java      = $jmeter_ini->val("Main","java");
	$javadir   = $jmeter_ini->val("Main","javadir");
	$jmeter    = $jmeter_ini->val("Main","jmeter");
}

=pod

=head2 Add to errorstring

This procedure will add the message to the errorstring. This guarantees that the error string has the expected format.

=cut

sub add2errormsg($) {
	my ($errormsg) = @_;
	if (length($errstring) > 0) {
		# Add delimiter to errstring
		$errstring .= $delimiter;
	}
	$errstring .= $errormsg;
}


=pod

=head2 Handle Statistics

This procedure will process the result file for the probe. A result file line has the fields: timeStamp elapsed label responseCode responseMessage threadName dataType success failureMessage bytes Latency

elapsed time will be summarized, responseCodes should all be valid. Currently code 200 is valid. Other codes may be added later, if applicable. For now response codes must be valid for all probes. When probe-specific response codes are required, a .ini file can be created for the response code. If response code not OK, status is set to error and errorstring attached. 

The success status combines responseCode and (possible) assertion. When success status is not 'TRUE' and failureMessage exist, then status is set to Error and failuremessage is added to errstring.

Assertion failures are identified with the text "Test failed: text expected to contain /xxx/". In this case a more userfriendly errormessage will be added to the errstring. 

For each step a line is added to the bbperf table. The summary line is added to the database table monstat at the end of the application. Therefore care must be taken to guarantee that application is properly ended.

=cut

sub handle_statistics() {
	# Open resfile
	my $openres = open(RES, $resfile);
	if (not defined $openres) {
		error("Could not open $resfile for reading!");
		add2errormsg("Could not open $resfile");
		$status = "critical";
		return;
	}
	# resfile open, now read result lines
	my $asserterror = "Test failed: text expected to contain";
	# Reset total response time
	$resptime = 0;
	while (my $line = <RES>) {
		chomp $line;
		my($timestamp,$elapse,$label,$responsecode,$responsemsg,$threadname,$datatype,$success,$failuremsg,$bytes,$latency) = split /\|/,$line;
		# Check if $bytes if defined. If not, then there is probably 
		# an unexpected CR/LF in the response line.
		# Read next line and concatenate.
		while (not defined $bytes) {
			my $restline = <RES>;
			if (not defined $restline) {
				# EOF reached
				my $errmsg = "Result file in unexpected format";
				add2errormsg("$errmsg");
				$elapse = 999999;
				$status = "critical";
			} else {
				# Concatenate both lines
				chomp $restline;
				$line .= $restline;
				($timestamp,$elapse,$label,$responsecode,$responsemsg,$threadname,$datatype,$success,$failuremsg,$bytes,$latency) = split /\|/,$line;
			}
		}
		# If elapse time equals 'elapsed', then jmeter.properties
		# has setting jmeter. (...) . print_field_names=true
		if ($elapse eq "elapsed") {
			logging("jmeter.properties setting print_field_names should be false");
			next;
		}
		# Check if elapse time is  numeric
		if (not($elapse =~ /^[0-9][0-9]*$/)) {
			my $errmsg = "Elapse time $elapse not numeric";
			error($errmsg);
			add2errormsg("$errmsg");
			$elapse = 999999;
			$status = "critical";
		}
		$resptime += $elapse;
		# Check if response code is numeric
		if (not($responsecode =~ /^[0-9][0-9]*$/)) {
			my $errmsg = "Elapse time $elapse not numeric";
			error($errmsg);
			add2errormsg("$errmsg");
			$elapse = 999999;
			$status = "critical";
		} else {
			# OK: response code equals 200 AND no failuremessage
			if (($responsecode == 200) && (length($failuremsg) == 0)) {
				$failuremsg = "";
			# NOK: read failuremsg, if empty read responsemsg
			} else {
				# Set status to error from ok only.
				if ($status eq "ok") {
					$status = "error";
				}
				# Try to find message
				if (length($failuremsg) > 0) {
					if (index($failuremsg, $asserterror) > -1) {
						# Assertion error, get text between forward slashes
						my $startpos = index($failuremsg, "/");
						my $assertstring = substr($failuremsg,$startpos+1,-1);
						add2errormsg("Assertion failed: $assertstring");
						$failuremsg = "Assertion failed: $assertstring";
					} else {
						# Other error message
						add2errormsg("$failuremsg");
					}
				} else {
					# No failure message, so use responsemsg as error
					# This is the case for FTP file not found
					add2errormsg("$responsemsg");
					# Set failuremsg for load in database
					$failuremsg = $responsemsg;
				}
			}
		}
		# Write detail performance information
		add2bbperform($label,$elapse,$responsecode,$failuremsg);
	}
	close RES;
	if (not($removeresult eq "No")) {
		unlink $resfile;
	}
}

=pod

=head2 Add to bbperform

Add URL response time info to bbperf table.

=cut

sub add2bbperform($$$$) {
	my($url,$elapse,$response,$errors) = @_;
	my $openres = open (BBPERF, ">>$resultdir/bbperf.csv");
	if (not defined $openres) {
		error("Could not open $resultdir/bbperf.csv for appending...");
	} else {
		print BBPERF "$msdatetime;$applname;$url;$elapse;$response;$errors\n";
		close BBPERF;
	}
}

=pod

=head2 Add Monitoring Status

Add total monitoring status for this application.

=cut

sub add2monstatus() {
	my $openres = open (MONSTAT, ">>$resultdir/monstat.csv");
	if (not defined $openres) {
		error("Could not open $resultdir/monstat.csv for appending...");
	} else {
		print MONSTAT "$msdatetime;$applname;$status;$resptime;$errstring\n";
		close MONSTAT;
	}
}

=pod

=head2 Handle Ini File

jmeter agent ini file is used to specify probe specific settings. If default settings are used, then no .ini file is needed. The .ini file must have the same name as the jmeter probe and must reside in the same directory. It must have the .ini extension.

Section [Main], firewall points to the firewall, port points to the firewall port.

=cut

sub handle_ini_file() {
	my $agent_ini = new Config::IniFiles(-file	=> $agentinifile);
	if (not defined $agent_ini) {
		my $errline = "Could not process $agentinifile, errors: ".join("",@Config::IniFiles::errors);
		add2errormsg($errline);
		$status = "critical";
		error($errline);
		# Don't process any further. Ini file was required and could not be read,
		# so exit application here.
		add2monstatus();
		exit_application(1);
	}
	my $firewall_host = $agent_ini->val("Main","firewall");
	my $firewall_port = $agent_ini->val("Main","port");
	if (defined $firewall_host) {
		$cmdext .= "-H $firewall_host ";			# Trailing space required!
		# Don't handle port without firewall
		if (defined $firewall_port) {
			$cmdext .= "-P $firewall_port ";		# Trailing space required!
		}
	}
}


######
# Main
######

# Handle input values
my %options;
getopts("tl:p:k:i:rh:", \%options) or pod2usage(-verbose => 0);
# At least the table name must be specified.
my $arglength = scalar keys %options;  
if ($arglength == 0) {			# If no options specified,
   $options{"h"} = 0;			# display usage. jmeter plan is mandatory
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
		error("Could not set d:/temp/log as Log directory, exiting...");
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
# Find jmeter test plan
if ($options{"p"}) {
    $jmxplan = $options{"p"};
	if (not -r $jmxplan) {
		error("Cannot access test plan $jmxplan for reading, exiting...");
		exit_application(1);
	} elsif (index($jmxplan, " ") > -1) {
		error("Test plan name $jmxplan should not have spaces, exiting...");
		exit_application(1);
	}
} else {
	error("jmeter test plan has not been defined, exiting...");
	exit_application(1);
}
# Find timeout
if ($options{"k"}) {
    $timeout = $options{"k"};
	# Check timeout value is integer
	if (not($timeout =~ /^[1-9][0-9]*$/)) {
		error("Timeout $timeout is not a valid integer number, exiting...");
		exit_application(1);
	}
}
# Check for jmeter ini file
if ($options{"i"}) {
	$jmeterinifile = $options{"i"};
	# Check inifile is readable
	if (not -r $jmeterinifile) {
		error("Could not open $jmeterinifile for reading, exiting...");
		exit_application(1);
	}
} else {
	error("jmeter ini file has not been defined, exiting...");
	exit_application(1);
}
# Find Remove Results flag
if (defined $options{"r"}) {
	$removeresult = "No";
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Get application settings
get_jmeter_ini_file();

# Get application name and date/time
fileparse_set_fstype("MSWin32");
($applname,$dirname,$suffix) = fileparse($jmxplan, @suffixlist);
my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$msdatetime = sprintf("%04d-%02d-%02d %02d:%02d:%02d",$year+1900, $mon+1, $mday,$hour,$min,$sec);

# Calculate result directory
$resultdir = Win32::GetFolderPath(CSIDL_PERSONAL);
$resultdir = Win32::GetShortPathName($resultdir);
# Get Test result file
$resfile = "$resultdir/$applname.csv";

# Check for ini file
$agentinifile = "$dirname/$applname.ini";
if (-r $agentinifile) {
	handle_ini_file();
}

# jmeter recommended startup values are documented in the Unix startup file jmeter\bin\jmeter.
# If specific settings should be required for some test scripts, consider using an .ini file.
my $heap     = "-Xms512m -Xmx512m";
my $new      = "-XX:NewSize=128m -XX:MaxNewSize=128m";
my $tenuring = "-XX:MaxTenuringThreshold=2";
my $rmigc    = "-Dsun.rmi.dgc.client.gcInterval=600000 -Dsun.rmi.dgc.server.gcInterval=600000";
my $perm     = "-XX:PermSize=64m -XX:MaxPermSize=64m";
my $dump     = "-XX:+HeapDumpOnOutOfMemoryError";
# Note that JVM server is not installed on VMserver
# my $server   = "-server";
my $args     = "$dump $heap $new $tenuring $rmigc $perm";

my $cmd = "$java $args -jar $jmeter -t $jmxplan -l $resfile -n $cmdext";
logging($cmd);

# Build the invocation
my $retcode = Win32::Process::Create($jmobj,
				"$javadir/$java",
				"$cmd",
				1,
				NORMAL_PRIORITY_CLASS,
#				NORMAL_PRIORITY_CLASS && CREATE_NO_WINDOW,
				".");
if (not defined $retcode) {
	error("Error in Process Create: " . Win32::FormatMessage(Win32::GetLastError()));
	exit_application(1);
}

my $pid = $jmobj->GetProcessID();
logging("Process $pid created.");
my $wait_in_msec = $timeout * 1000;
$jmobj->Wait($wait_in_msec);
# Kill process if still there
my $killcode = $jmobj->Kill($exitcode);
if (not($killcode == 0)) {
	error("Process has been killed after $timeout seconds");
	add2errormsg("Timeout");
	$status = "critical";
}
# Note that there can be a partial result file if there was a timeout. 
# Handle this partial file then.
if (-r "$resfile") {
	handle_statistics();
} else {
	error("Cannot access $resfile for reading");
	add2errormsg("Result file not readable");
	$status = "critical";
}

add2monstatus();
exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Run tests for some time, then compare with response time too long. (Do we want to do this in jmeterAgent.pl, or in a separate script?

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
