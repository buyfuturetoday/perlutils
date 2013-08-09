# use pod2html scv_ctrl.pl > ServiceCtrl.html
# to have documentation in *html format

=head1 NAME

ServiceCtrl - Stop, start or status of services on all hosts in the list.

=head1 VERSION HISTORY

version 1.1 19 March 20002 DV

=over 4

=item *

Introduce use File::Basename to resolve an issue with logfile names.

=back

version 1.0 08/03/2002 - Initial Release

=head1 DESCRIPTION

This utility allows to control a service on a set of remote hosts.

=head1 USAGE

=over 4

=item *

-s "Service Name", default: Messenger

=item *

-a "status/stop/start", default: status

=item *

-h "hosts_file", default: c:\temp\hosts.txt
The hosts.txt file contains one host name per line, no blank lines and no comments.

=item *

-l "logfile_directory", default: c:\temp

=item *

-t: if set, then trace messages will be displayed

=back

=head1 ADDITIONAL INFORMATION

=cut

###########
# Variables
###########

$service = "Messenger";		    # Use short service name
$hostfile = "c:\\temp\\hosts.txt";  # hostlist
$host = "Xbeahw1076162";
$action = "status";		    # action to perform with the service
$trace = 0;			    # 0: no tracing, 1: tracing
$logdir = "c:\\temp";
$log = 1;			    # 0: no logging, 1: logging
$logfile = "LOGFILE";		    # Placeholder
$hostlist = "HOSTLIST";		    # Placeholder
$svc_stop = 1;			    # CurrentState Service is stopped
$svc_running = 4;		    # CurrentState Service is running

#####
# use
#####

use Win32::Service;
use Getopt::Std;
use File::Basename;		    # logfile name issue

#############
# subroutines
#############

sub error($) {
    my($txt) = @_;
    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
    print "$datetime - Error: $txt\n";
    logging("Error: $txt");
}

sub trace($) {
    if ($trace) {
	my($txt) = @_;
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
	print "$datetime - Trace: $txt\n";
    }
}

# SUB - Open LogFile
sub open_log() {
    if ($log == 1) {
	my($scriptname, undef) = split(/\./, basename($0));
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$logfilename=sprintf(">>$logdir\\"."$scriptname%04d%02d%02d.log", $year+1900, $mon+1, $mday);
	open ($logfile, $logfilename);
	# Ensure Autoflush for Log file...
	$old_fh = select($logfile);
	$| = 1;
	select($old_fh);
    }
}

# SUB - Handle Logging
sub logging($) {
    if ($log == 1) {
	my($txt) = @_;
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
	print $logfile $datetime." * $txt"."\n";
    }
}

# SUB - Close log file
sub close_log() {
    if ($log == 1) {
	close $logfile;
    }
}

sub exit_application($) {
    my($return_code) = @_;
    logging("Exit application with return code $return_code\n");
    close_log();
    exit $return_code;
}

=pod

=head2 Status Service handling

 Verify if the service status.
 If the status is known, then it will be displayed. 
 Currently known states:
    4: service is running
    1: service is stopped

=cut

sub status_service($$) {
    my($host, $service) = @_;
    # Verify service status
    my($ret) = Win32::Service::GetStatus($host, $service,\%statref);
    if (not($ret)) {
	logging("Can't connect to $host or $service does not exist.");
	trace("Can't connect to $host or $service does not exist.");
    } elsif ($statref{CurrentState} == $svc_running) {
	logging("$service is running on $host.");
	trace("$service is running on $host.");
    } elsif ($statref{CurrentState} eq $svc_stop) {
	logging("$service is stopped on $host.");
	trace("$service is stopped on $host.");
    } else {
	logging("$service in status $statref{CurrentState} on $host.");
	trace("$service in status $statref{CurrentState} on $host.");
    }
}

=pod

=head2 Start Service handling

 Verify if the service is running.
 If running: OK for this host
 If not running:
    Try to start service
    Wait for some time
    Verify that service is runnning
    If success: OK for this host
    If not running: print error message

=cut

sub start_service($$) {
    my($host, $service) = @_;
    # Verify if service is running
    my($ret) = Win32::Service::GetStatus($host, $service,\%statref);
    if (not($ret)) {
	error("Can't connect to $host or $service does not exist.");
    } elsif ($statref{CurrentState} == $svc_running) {
	logging("$service already running on $host.");
	trace("$service already running on $host.");
    } else {
	# Service exists, but is not running, try to start it
	trace("Trying to start $service on $host...");
	my($ret) = Win32::Service::StartService($host, $service);
	if (not($ret)) {
	    error("Lost connection to $host to start $service.");
	} else {
	    sleep 5;
	    my($ret) = Win32::Service::GetStatus($host, $service,\%statref);
	    if (not($ret)) {
	        error("Lost connection to $host to verify status after starting $service");
	    } else {
                my ($cnt) = 0;
	        while ((not($statref{CurrentState} == $svc_running) and ($cnt++ < 3))) {
	            logging("Waiting for $service on $host to start...");
	            trace("Waiting for $service on $host to start...");
	            sleep 5;
	            my($ret) = Win32::Service::GetStatus($host, $service,\%statref);
		    if (not($ret)) {
		        error("Lost connection to $host to verify status after starting $service");
			last;
		    }
	        }
	        # Evaluate Status
	        if ($statref{CurrentState} == $svc_running) {
	            logging("$service is running on $host.");
	            trace("$service is running on $host.");
	        } else {
	            error("$service could not be started on $host.");
	        }
	    }
	}
    }
}

=pod

=head2 Stop Service handling

 Verify if the service is running.
 If not: OK for this host (service is already stopped)
 If running:
    Try to stop service
    Wait for some time
    Verify that service is stopped
    If success: OK for this host
    If not stopped: print error message

=cut

sub stop_service($$) {
    my($host, $service) = @_;
    # Verify if the service is running
    my($ret) = Win32::Service::GetStatus($host, $service,\%statref);
    if (not($ret)) {
	error("Can't connect to $host or $service does not exist.");
    } elsif ($statref{CurrentState} == $svc_stop) {
	logging("$service already stopped on $host.");
	trace("$service already stopped on $host.");
    } else {
	# Service is running, try to stop it
	trace("Trying to stop $service on $host...");
        my($ret) = Win32::Service::StopService($host, $service);
	if (not($ret)) {
	    error("Lost connection to $host to stop $service.");
	} else {
	    sleep 5;
	    my($ret) = Win32::Service::GetStatus($host, $service,\%statref);
	    if (not($ret)) {
	        error("Lost connection to $host to verify stopping of $service");
	    } else {
                my ($cnt) = 0;
	        while ((not($statref{CurrentState} == $svc_stop) and ($cnt++ < 3))) {
	            logging("Waiting for $service on $host to stop...");
	            trace("Waiting for $service on $host to stop...");
	            sleep 5;
	            my($ret) = Win32::Service::GetStatus($host, $service,\%statref);
		    if (not($ret)) {
		        error("Lost connection to $host to verify stopping of $service");
			last;
		    }
	        }
	        # Evaluate Status
	        if ($statref{CurrentState} == $svc_stop) {
	            logging("$service stopped on $host.");
	            trace("$service stopped on $host.");
	        } else {
	            error("$service could not be stopped on $host.");
	        }
	    }
        }
    }
}

######
# MAIN
######

# Handle input values
getopts("s:a:h:l:t", \%options) or die "getopts failed - $!";
# Trace required?
if ($options{"t"}) {
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
    die "Cannot find log directory $logdir.\n";
}
# Logdir found, start logging
open_log();
logging("Start application");

# Service name
if ($options{"s"}) {
    $service = $options{"s"};
}
# Required action
if ($options{"a"}) {
    $action = $options{"a"};
    if (not (($action eq "status") or
             ($action eq "stop")   or
	     ($action eq "start"))) {
	error("-a not in (status, stop, start), don't know what to do.");
	exit_application(1);
    }
}
# Hosts list
if ($options{"h"}) {
    $hostfile = $options{"h"};
}
if (not(-e $hostfile)) {
    error("Cannot find the file with the hosts $hostfile.");
    exit_application(1);
}
logging("Hostfile: $hostfile, Service: $service, Action: $action");
trace("Hostfile: $hostfile, Service: $service, Action: $action");
# End handle input values

$openres = open($hostlist, $hostfile);
if (not($openres)) {
    error("Could not open $hostfile");
    exit_application(1);
}

while ($host = <$hostlist>) {
    chomp $host;
    if ($action eq "status") {
	status_service($host, $service);
    } elsif ($action eq "start") {
	start_service($host, $service);
    } elsif ($action eq "stop") {
	stop_service($host, $service);
    } else {
	error("Unknown action: $action");
	exit_application(1);
    }
}

exit_application(0);

=pod

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
