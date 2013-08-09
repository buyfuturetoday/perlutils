=head1 NAME

generateAlert - This script gets application alert information from the appAlert script and generates all required alerts.

=head1 VERSION HISTORY

version 1.2 12 March 2010 DV

=over 4

=item *

Include logfile monitoring to the OS Eventlog, required for Tivoli agent monitoring

=back

version 1.1 02 March 2010 DV

=over 4

=item *

Update to allow logfile monitoring and to allow to disable SMS forwarding

=back

version 1.0 19 February 2010 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This script will scan the appstates table for applications with alert status 'NEW'. For such application lines the alert information will be generated.

The ini file generateAlert.ini will be picked up automatically in the directory where the perl script is stored. The ini file must be available. This is an example of the ini file:

 [Main]
 ; ssh Connection information
 ruser = appmon
 rpwd = appmon
 rhost = pw18
 ; Putty path
 puttydir = c:/putty
 ; Alertscript that is triggered on rhost server
 alertscript = /usr/local/bin/alert_via_sms.sh
 ; Timeout in seconds for the SMS Alert
 timeout = 60
 ; sms flag - indicates whether SMS forwarding is enabled
 ; 'ON' is required for sms messages (case sensitive)
 smsflag = Off
 ; Log file monitoring
 logmonflag = ON
 logfile = d:/temp/appmon.log
 ; EventLog monitoring
 eventlogflag = ON
 eventlogSource = ApplMon
 eventlogID = 1

 [Users]
 ; The user section has a list of all users that need to receive 
 ; an alert message.
 ; Users are defined with parameter value userX, where X is the number of
 ; the user, e.g. user1, user2, ...
 ; The numbers must start at 1 and must be consecutive
 ; The user names must be known on the phonebook on pw18
 ; user1=UnixPager
 user1=DirkV


=head1 SYNOPSIS

generateAlert.pl [-t] [-l log_dir]

    generateAlert -h		    Usage
    generateAlert -h 1	    Usage and description of the options
    generateAlert -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP SP2, Perl v5.8.8, build 820 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $dbh, $plobj, $timeout, $logmonflag, $logfile, $smsflag);
my ($eventlogflag, $eventlogsource, $eventlogID);
my ($puttypath, $ruser, $rpwd, $rhost, @users, $alertscript);
my $printerror = 0;
my $exitcode = 927;

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
use DBI();
use amParams;
use Config::IniFiles;		# Handle ini file
use Win32::Process;
use File::Basename;			# Get Current Directory

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if (defined $dbh) {
		$dbh->disconnect;
	}
	close TIVLOG;
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

=head2 Handle Ini File

appAlert agent ini file is used to specify application alert specific settings.

=cut

sub handle_ini_file($) {
	my ($inifile) = @_;
	my $schedule_ini = new Config::IniFiles(-file	=> $inifile);
	if (not defined $schedule_ini) {
		my $errline = "Could not process $inifile, errors: ".join("",@Config::IniFiles::errors);
		exit_application(1);
	}
	$smsflag = $schedule_ini->val("Main", "smsflag");
	if ($smsflag eq "ON") {
		$puttypath = $schedule_ini->val("Main","puttydir");
		$ruser = $schedule_ini->val("Main","ruser");
		$rpwd = $schedule_ini->val("Main","rpwd");
		$rhost = $schedule_ini->val("Main","rhost");
		$alertscript = $schedule_ini->val("Main", "alertscript");
		if (not defined $alertscript) {
			error("Alertscript is not defined, exiting...");
			exit_application(1);
		}
		$timeout = $schedule_ini->val("Main", "timeout");
		# Get user names
		my $cnt = 1;
		while (1) {
			my $label = "user" . $cnt;
			my $user = $schedule_ini->val("Users", $label);
			if (defined $user) {
				push @users, $user;
				$cnt++;
			} else {
				# all users found
				last;
			}
		}
		if (not defined $users[0]) {
			error("No SMS recipients defined, exiting...");
			exit_application(1);
		}
	}
	$logmonflag = $schedule_ini->val("Main", "logmonflag");
	if ($logmonflag eq "ON") {
		$logfile = $schedule_ini->val("Main", "logfile");
	}
	$eventlogflag = $schedule_ini->val("Main", "eventlogflag");
	if ($eventlogflag eq "ON") {
		$eventlogsource = $schedule_ini->val("Main", "eventlogsource");
		$eventlogID = $schedule_ini->val("Main", "eventlogID");
	}
}

=pod

=head2 Send SMS

This procedure will prepare the commands to send an SMS, open an ssh connection to the remote server and launch the commands.

=cut

sub send_sms($$$) {
	my ($application, $msdatetime, $status) = @_;
	my $smsmsg = "VDAB Alert: $application $status $msdatetime";
	foreach my $smsname (@users) {
		my $cmd = "plink -ssh -l $ruser -pw $rpwd $rhost $alertscript -p $smsname \\\"$smsmsg\\\"";
		logging("Alert Command $cmd");
		# Build the SMS Alert process
		my $retcode = Win32::Process::Create($plobj,
							"$puttypath/plink.exe",
							"$cmd",
							1,
							NORMAL_PRIORITY_CLASS,
							".");
		if (not defined $retcode) {
			error("Error in Process Create: " . Win32::FormatMessage(Win32::GetLastError()));
			exit_application(1);
		}
	
		my $pid = $plobj->GetProcessID();
		logging("Process $pid created.");
		my $wait_in_msec = $timeout * 1000;
		$plobj->Wait($wait_in_msec);
		# Kill process if still there
		my $killcode = $plobj->Kill($exitcode);
		if (not($killcode == 0)) {
			error("SMS Alert Process has been killed after $timeout seconds");
			exit_application(1);
		}
	}
}

=pod

=head2 Clear Alert

This script will clear the alert flag when an SMS has been sent.

=cut

sub clear_alert($$) {
	my ($application, $msdatetime) = @_;
	my $query = "UPDATE appstates SET alert = ''
						WHERE application = ? AND msdatetime = ?";
	my $sth = $dbh->prepare($query);
	$sth->bind_param(1, $application);
	$sth->bind_param(2, $msdatetime);
	my $rv = $sth->execute();
	if (not(defined $rv)) {
		error("Could not execute query $query, Error: ".$dbh->errstr);
		exit_application(1);
	} elsif (not($rv == 1)) {
		error("$rv rows updated, expected only 1 for application $application at $msdatetime");
	}
}

######
# Main
######

# Handle input values
my %options;
getopts("tl:h:", \%options) or pod2usage(-verbose => 0);
# my $arglength = scalar keys %options;  
# if ($arglength == 0) {			# If no options specified,
#    $options{"h"} = 0;			# display usage. jmeter plan is mandatory
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
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Get ini values
fileparse_set_fstype("MSWin32");
my ($applname,$dirname,$suffix) = fileparse($0, ".pl");
my $inifile = "$dirname/$applname.ini";
if (-r $inifile) {
	handle_ini_file($inifile);
} else {
	error("Inifile $inifile not readable, exiting...");
	exit_application(1);
}
$ENV{PATH} = $puttypath.";".$ENV{PATH};

# Open logfile if required
if ($logmonflag eq "ON") {
	my $openres = open(TIVLOG, ">>$logfile");
	if (not defined $openres) {
		error("Could not open $logfile for appending, exiting...");
		exit_application(1);
	}
}


# Set-up database connection
my $connectionstring = "DBI:mysql:database=$databasename;host=$server;port=$port";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

# Get all applications that require alert
my $query = "SELECT application, msdatetime, status FROM appstates
					WHERE alert = 'NEW'";
my $sth = $dbh->prepare($query);
my $rv = $sth->execute;
if (not(defined $rv)) {
	error("Could not execute query $query, Error: ".$sth->errstr);
	exit_application(1);
}
while (my $ref = $sth->fetchrow_hashref) {
	my $application = $ref->{application};
	my $msdatetime = $ref->{msdatetime};
	my $status = $ref->{status};
	if ($logmonflag eq "ON") {
		print TIVLOG "$msdatetime $application $status\n";
	}
	if ($eventlogflag eq "ON") {
		my $eventmsg = "Application $application Status $status At $msdatetime";
		my $eventcmd = "eventcreate /id $eventlogID /so $eventlogsource /l Application /t ERROR /d \"$eventmsg\"";
		system $eventcmd;
	}
	if ($smsflag eq "ON") {
		send_sms($application, $msdatetime, $status);
	}
	clear_alert($application, $msdatetime);
}

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Allow to send to multiple SMS numbers

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@hp.comE<gt>
