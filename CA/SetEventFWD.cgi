#!e:\em\apps\Perl\bin\perl.exe

=head1 NAME

SetEventFWD.pl - This cgi script configures the Event Forward destination and variables.

=head1 VERSION HISTORY

version 1.0 1 May 2005 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

The script runs as a cgi and allows to configure the Event Forwarding for infrastructure servers. Event forwarding configuration is required to implement the Tier-1 site failover mechanisms.

=head1 SYNOPSIS

SetEventFWD.cgi

=head1 OPTIONS

=over 4

=item B<process>

Process or Cancel request, to allow the user to exit from the configuration screen without applying any changes.

=item B<EventServer>

Target server to forward events to. A connection verification to this server is done before the FORWARD destination is changed.

=item B<Secondary Framework Server>

Status secondary framework server. UP => filter on the duplicate events from secondary monitored sites. DOWN => do not filter, the current framework server is currently the only Tier-1 Framework server.

=item B<Status Event Server>

Status of the current target Event Server. Allows to manually set the value of the Event Server to DOWN. The 'Forward Events to' setting is ignored in this case. Also required to allow for the situation when the target Event Server is DOWN, and the status of the Secondary Framework Server changes from 'UP' to 'DOWN'. Events from the secondary monitored sites must be moved to the temporary space at this time.

=item B<Active Event Server>

If the Active Event Server is the primary event server, then alerts are sent to the Secondary event server in case of forward failure. If the Active Event Server is the secondary event server, it does not make sense to forward events to the primary event server ...

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.8.3, build 809 provided by ActiveState.

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
###########

my ($return_code, $EventServer, $query, $ErrorString, $SecondaryEvent);
my ($EventStatus, $ActiveEventSrv, $command);
my $log = 1;		    # 1: logging - 0: no logging
my $logdir = "c:/temp";
my $appdir = "e:/em/apps/failover";

#####
# use
#####

use warnings;			    # show warnings
use strict 'vars';
use strict 'refs';
use strict 'subs';
use CGI;

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
    logging("Exit Application, return code $return_code\n");
    close_log();
    exit $return_code;
}

=pod

=head2 Display Success

In case all settings have been applied successfully, a success message is shown to the user with an overview of the current settings.

=cut

sub display_success() {
    # For some reason the print CGI results in a <?xml ... statement
    # that is added to the output. The web browser on the framework servers
    # fails on the <?xml ... statement
    print <<END_OF_HTML;
Content-type: text/html

<html>
<head>
<title>Results ...</title>
</head>
<body bgcolor='#AFFFCC'>
<h1>Request has been processed successfully</h1>
<ul>
<li>EventServer: $EventServer
<li>Status Secondary Event Server: $SecondaryEvent
<li>Status Event Status: $EventStatus
<li>Active Event Server: $ActiveEventSrv
</ul>
</body>
</html>
END_OF_HTML
#    print $query->header;
#    print $query->start_html(-title	=> "Results ...",
#			     -bgcolor	=> '#AFFFCC');
#    print "<h1>Request has been processed successfully</h1>\n";
#    print "<ul>\n";
#    print "<li>EventServer: $EventServer\n";
#    print "<li>Status Secondary Event Server: $SecondaryEvent\n";
#    print "<li>Status Event Status: $EventStatus\n";
#    print "<li>Active Event Server: $ActiveEventSrv\n";
#    print "</ul>\n";
#    print $query->end_html;
    exit_application(0);
}

=pod

=head2 Display Error

In case an error is encountered, the Display Error procedure shows the error, logs the error in the log file and terminates further execution of the application.

=cut

sub display_error($) {
    my ($ErrorString) = @_;
    # For some reason the print CGI results in a <?xml ... statement
    # that is added to the output. The web browser on the framework servers
    # fails on the <?xml ... statement
    print <<END_OF_HTML;
Content-type: text/html

<html>
<head>
<title>Results ...</title>
</head>
<body bgcolor='#FFAFCC'>
<h1>Request has not been processed</h1>
$ErrorString
</body>
</html>
END_OF_HTML
#    print $query->header;
#    print $query->start_html(-title	=> "Results ...",
#			     -bgcolor	=> '#FFAFCC');
#    print "<h1>Request has not been processed</h1>\n";
#    print "$ErrorString\n";
#    print $query->end_html;
    exit_application(1);
}

=pod

=head2 Execute Command

This procedure accepts a system command, executes the command and checks on a 0 return code. If no 0 return code, then an error occured and control is transferred to the Display Error procedure.

=cut

sub execute_command($) {
    my ($command) = @_;
    if (system($command) == 0) {
	logging("Command $command - Return code 0");
    } else {
	$ErrorString = "Could not execute command $command";
	error($ErrorString);
	display_error($ErrorString);
    }
}

=pod

=head2 open_log

The procedure opens the logfile for the script and associates a filehandle to the logfile.

The current date (YYYYMMDD) is appended to the scriptname. 

The autoflush is on for the logfile. This means that no messages are buffered. In case of system crashes more messages should be in the log file.

If the logfile directory does not exist or if the logfile could not be opened, then the return value of the subroutine is undefined. Otherwise the return value is 0.

=cut

sub open_log() {
    if ($log == 1) {
	if (not(-d $logdir)) {
	    print "$logdir does not exist, cannot open logfile\n";
	    exit;
	}
	my $scriptname = "SetEventFWD";
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $computername = $ENV{HTTP_HOST};
	my $logfilename=sprintf(">>$logdir/$scriptname"."_$ENV{COMPUTERNAME}_%04d%02d%02d.log", $year+1900, $mon+1, $mday);
	my $openres = open (LOGFILE, $logfilename);
	if (not(defined $openres)) {
	    print "Could not open $logfilename\n";
	}
	# Ensure Autoflush for Log file...
	my $old_fh = select(LOGFILE);
	$| = 1;
	select($old_fh);
    }
    return 0;
}

=pod

=head2 handle_logging("Log message")

This procedure will add log messages to the log file, if the log flag is set. The current date and time is calculated, prepended to the log message and the log message is appended to the logfile. A "Carriage Return/Linefeed" is appended to the log message.

=cut

sub logging($) {
    if ($log == 1) {
	my($txt) = @_;
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
	print LOGFILE $datetime." * $txt"."\n";
    }
}

=pod

=head2 error_logging("Error Message")

For now this procedure will call the logging procedure. The idea is that for error messages a line is written to the event log.

=cut

sub error($) {
    my ($errorline) = @_;
    print "Error: $errorline\n";
    logging($errorline);
}

=pod

=head2 close_log

If the logfile is opened, then this procedure will close the logfile.

=cut

sub close_log() {
    if ($log == 1) {
	close LOGFILE;
    }
}

######
# Main
######

open_log();
logging ("Start Application");

$query = new CGI;

# Review input parameters
# Process or Cancel request?
if (not(defined($query->param("process")))) {
    $ErrorString = "Processing canceled upon user's request!";
    display_error($ErrorString);
}
    
# 1. EventServer
if (defined($query->param("EventServer"))) {
    $EventServer = $query->param("EventServer");
    logging ("EventServer: $EventServer");
} else {
    $ErrorString = "EventServer parameter not defined";
    error($ErrorString);
    display_error($ErrorString);
}
# 2. Secondary Event Server
if (defined($query->param("secev"))) {
    $SecondaryEvent = $query->param("secev");
    logging("Secondary Event: $SecondaryEvent");
} else {
    $ErrorString = "Secondary Event Status not defined";
    error($ErrorString);
    display_error($ErrorString);
}
# 3. Status Event Server
if (defined($query->param("evserv"))) {
    $EventStatus = $query->param("evserv");
    logging("Event Server: $EventStatus");
} else {
    $ErrorString = "Status Event Server is not defined";
    error($ErrorString);
    display_error($ErrorString);
}
# 4. Active Event Server
if (defined($query->param("actserv"))) {
    $ActiveEventSrv = $query->param("actserv");
    logging("Active Event Server: $ActiveEventSrv");
} else  {
    $ErrorString = "Active Event Server is not defined";
    error($ErrorString);
    display_error($ErrorString);
}

# Verify if the defined event server can accept events. 
# If so, then all delayed events are sent as part of the Perl script.
#
# Send events only if event server is supposed to accept events.
if ($EventStatus eq "UP") {
    my $command = "perl $appdir/Fwd_Event.pl $EventServer";
    if (not(system ($command) == 0)) {
	$ErrorString = "Could not send events to event server $EventServer ($command)";
	error($ErrorString);
	display_error($ErrorString);
    }
    # Update FORWARD destination
    $command = "cautil select msgaction action=\"FORWARD\" alter msgaction node=$EventServer";
    if (not(system($command) == 0)) {
	$ErrorString = "Could not configure FORWARD Destination ($command)";
	error($ErrorString);
	display_error($ErrorString);
    }
}

# set the status variables for the event
$command = "cawto MRA_setenvsh SECONDARY FW $SecondaryEvent";
execute_command($command);
$command = "cawto MRA_setenvsh STATUS EV $EventStatus";
execute_command($command);
$command = "cawto MRA_setenvsh ACTIVE EV $ActiveEventSrv";
execute_command($command);
$command = "oprcmd opreload";
execute_command($command);

display_success();
