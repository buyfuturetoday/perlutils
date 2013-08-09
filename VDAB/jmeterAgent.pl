=head1 NAME

jmeterAgent - This agent script will launch a jmeter probe and act on the results.

=head1 VERSION HISTORY

version 1.0 24 July 2009 DV

=over 4

=item *

Initial release, based on the Nagios JMeter plugin (see www.monitoringexchange.org, jmeter invocation plugin).

=back

=head1 DESCRIPTION

This application invokes a JMeter test plan for application monitoring. 

=head1 SYNOPSIS

jmeterAgent.pl [-t] [-l log_dir] -p jmx_test_plan [-k timeout]

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

Default: 60 seconds.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP SP2, Perl v5.8.8, build 820 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $jmxplan, $jmobj, $dbh);
my ($msdate, $mstime, $applname, $resfile);
my $printerror = 0;
my $timeout = 60;
# my $jmeter = "c:/jmeter/bin/ApacheJMeter.jar";
my $jmeter = "e:/jmeter/bin/ApacheJMeter.jar";
# my $javadir = "C:/Program Files/Java/jre1.6.0_07/bin";
my $javadir = "C:/Program Files/Java/jre6/bin";
my $java = "java.exe";
my $resultdir = "e:/applmon/Results";
my $exitcode = 927;
my $status = "ok";				# Initial status
my $resptime = "999999";		# Initial response time
my $errstring = "";
my $delimiter = ";";			# Delimiter for error string

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
use DBI();
use amParams;

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if (defined $dbh) {
		$dbh->disconnect;
	}
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
	my $openres = open(RES, "$resfile");
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
		# If elapse time equals 'elapsed', then jmeter.properties
		# has setting jmeter. (...) . print_field_names=true
		if ($elapse eq "elapsed") {
			logging("jmeter.properties setting print_field_names should be false");
			next;
		}
		# Check if elapse time is  numeric
		if (not($elapse =~ /^[1-9][0-9]*$/)) {
			my $errmsg = "Elapse time $elapse not numeric";
			error($errmsg);
			add2errormsg("$errmsg");
			$elapse = 999999;
			$status = "critical";
		}
		$resptime += $elapse;
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
			# Set status to error from ok only.
			if ($status eq "ok") {
				$status = "error";
			}
		} else {
			$failuremsg = "";
		}
		# Write detail performance information
		add2bbperform($label,$elapse,$responsecode,$failuremsg);
	}
	close RES;
	unlink $resfile;
}

=pod

=head2 Add to bbperform

Add URL response time info to bbperf table.

=cut

sub add2bbperform($$$$) {
	my($url,$elapse,$response,$errors) = @_;
	my $query = "INSERT INTO bbperf (msdate,mstime,application,url,elapse,response,status)
							 values ('$msdate','$mstime','$applname','$url',$elapse,'$response','$errors')";
	my $rows_affected = $dbh->do($query);
	if (not defined $rows_affected) {
		error("Insert failed, query $query. Error: ".$dbh->errstr);
	} elsif (not $rows_affected == 1) {
		error("$rows_affected rows inserted ($query), 1 expected");
	}
}

=pod

=head2 Add Monitoring Status

Add total monitoring status for this application.

=cut

sub add2monstatus() {
	my $query = "INSERT INTO monstat (msdate,mstime,application,status,resptime,errors)
							 values ('$msdate','$mstime','$applname','$status',$resptime,'$errstring')";
	my $rows_affected = $dbh->do($query);
	if (not defined $rows_affected) {
		error("Insert failed, query $query. Error: ".$dbh->errstr);
	} elsif (not $rows_affected == 1) {
		error("$rows_affected rows inserted ($query), 1 expected");
	}
}

######
# Main
######

# Handle input values
my %options;
getopts("tl:p:k:h:", \%options) or pod2usage(-verbose => 0);
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
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Set-up database connection
my $connectionstring = "DBI:mysql:database=$databasename;host=$server;port=$port";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

# Get application name and date/time
($applname,undef) = split(/\./, basename($jmxplan));
my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$msdate = sprintf("%04d-%02d-%02d",$year+1900, $mon+1, $mday);
$mstime = sprintf("%02d:%02d:%02d",$hour,$min,$sec);

# Get Test result file
$resfile = "$resultdir/$applname.csv";

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

my $cmd = "$java $args -jar $jmeter -t $jmxplan -l $resfile -n";
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
} elsif (not(-r $resfile)) {
	error("Cannot access $resfile for reading");
	add2errormsg("Result file not readable");
	$status = "critical";
} else {
	handle_statistics();
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
