=head1 NAME

scheduler - Scans for and launches agent scripts.

=head1 VERSION HISTORY

Version 1.2 23 February 2010 DV

=over 4

=item *

Extend to handle pre- and post processing.

=item *

Neoload changes have been done in a previous version.

=back

version 1.0 28 July 2009 DV

=over 4

=item *

Initial release

=back

=head1 DESCRIPTION

This application is responsible for the scheduling of agent scripts that run probes. The script will launch all agent scripts in sequence and then pause until the next script launch time. The script should run continuously (24X7) so a mechanism needs to be in place to check correct functioning of this script.

There must be one directory with all probe files. A probe file must have the (application) identifier name and the associated directory. Currently only Badboy files are handled. 

For each probe file there can be an .ini file with specific configuration settings for this probe. The ini file must have the identifier name and .ini extension. If no .ini file is present, then the default values will be used.

The ini file should have a section [Main]. Parameter 'timeout' specifies a timeout value (in seconds) after which the agent will kill the probe.

Parameters not yet implemented include earliestscan (HHMM - do not scan befor this time), latestscan (HHMM - do not scan after this time), daysnoscan (SAT, SUN - do not scan on these days).

This script will launch agent scripts sequentially and wait for completion to start next agent script. Multi-tasking may require heavier monitoring equipment and the next level in programming. It may be wiser to switch to a COTS tool when this is required.

The scheduler script has a mandatory ini file, that will be re-read at each monitoring cycle. This allows to change parameters between cycles and to stop the script by changing the command status from 'RUN' to 'STOP'.

=head1 SYNOPSIS

scheduler.pl [-t] [-l log_dir] -i scheduler.ini

    scheduler -h	    Usage
    scheduler -h 1	    Usage and description of the options
    scheduler -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-i scheduler.ini>

Scheduler ini file, containing all parameters for the scheduler script. This is an example of the scheduler.ini file:

 [Main]
 ; Scheduling interval in minutes. Before launching any agent script, 
 ; next interval time will be calculated. 
 ; When all scripts have finished, application will sleep till 
 ; next interval. If interval has expired in the mean time,
 ; then monitoring cycle will start immediately.
 interval = 15
 ; probe directory. Should contain all probe files (and probe .ini files
 ; if required)
 probedir = E:/ApplMon/probes
 ; Action, should be 'RUN'. To stop scheduler from launching another cycle,
 ; change Action (to 'STOP', but any value other than 'RUN' will be seen
 ; as a STOP sign).
 action = RUN
 ; PRE RUN Directory. Perl script files that are available in this directory will be launched before
 ; an application scheduling run is started.
 ; This variable is optional, uncomment it if required.
 pre-run = E:/ApplMon/before
 ; POST RUN Directory. Perl script files that are available in this directory will be launched after
 ; an application scheduling run is started.
 ; This variable is optional, uncomment it if required.
 post-run = E:/ApplMon/after
 
 ; Variables in the system section should never be changed, once configured 
 ; properly on a system
 [System]
 ; Perl points to the perl executable (including full path)
 perl = e:/perl510/bin/perl.exe
 ; bbagent points to the perl script that will launch badboy command line
 bbagent = E:/ApplMon/scheduler/badboyAgent.pl
 ; jmxagent points to the perl script that will launch jmeterAgent command line
 jmxagent = E:/ApplMon/scheduler/jmeterAgent.pl

 #####Nick###
 ; nlpagent points to the perl script that will launch neoloadrAgent command line
 nlpagent = E:/ApplMon/scheduler/neoloadAgent.pl


=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP SP2, Perl v5.10.0, build 1005 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

#####Nick####
my ($logdir, $application, $inifile, $schedule_ini, $neoload_ini, $prerun_dir, $postrun_dir);
####Nick#
my ($interval, $probedir, $action, $perl, $bbagent, $jmxagent, $nlpagent, $nlpappl);
###### To be removed after test
my ($dummyval);

###change Nick
my @suffixlist = ("jmx","nlpi","pl");	# Specifies suffices that are handled (jmeter & neoload initiator files)
my @nlpsuffixlist = ("nlp");	# Specifies suffices for neoload

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use File::Basename;			# Used to extract application name from a badboy testplan
use Log;					# Application and error logging
use Config::IniFiles;		# Handle ini file

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

=pod

=head2 Get Scheduler Ini File

Read the scheduler ini file on each run. Validate values, exit application if required or on invalid values. Run application with current values otherwise.

This approach allows to control the scheduler on remote PCs with file actions only.

=cut

sub get_scheduler_ini_file() {
	if (not $schedule_ini->ReadConfig) {
		error("Could not reload $inifile, errors: ".join("",@Config::IniFiles::errors));
		exit_application(1);
	}
	$interval = $schedule_ini->val("Main","interval");
	$probedir = $schedule_ini->val("Main","probedir");
	$action   = $schedule_ini->val("Main","action");
	$perl	  = $schedule_ini->val("System","perl");
	$bbagent  = $schedule_ini->val("System","bbagent");
	$jmxagent  = $schedule_ini->val("System","jmxagent");
	$prerun_dir = $schedule_ini->val("Main","pre-run");
	$postrun_dir = $schedule_ini->val("Main", "post-run");
	####Nick###
	$nlpagent  = $schedule_ini->val("System","nlpagent");
	$dummyval = $schedule_ini->val("System","dummyval");
	# Check for action RUN
	$action = trim($action);
	if (not ( uc($action) eq "RUN")) {
		error("Action $action (not RUN), exiting...");
		exit_application(1);
	}
	# Check for valid interval
	if (not($interval =~ /^[1-9][0-9]*$/)) {
		error("Interval $interval is not a valid integer number, exiting...");
		exit_application(1);
	}
	# Check for valid probedir
	if (not(-d $probedir)) {
		error("$probedir is not a valid directory, exiting...");
		exit_application(1);
	}
}

sub handle_badboy($) {
	my ($applpath) = @_;
	my ($applname, $appldir, $suffix) = fileparse("$applpath",@suffixlist);
	# Check for application ini file must be done in bbagent.pl
	if (not -x $perl) {
		error("Cannot find executable $perl to launch $applname");
		return;
	}
	if (not -r $bbagent) {
		error("Cannot read badboy agent $bbagent to launch $applname");
		return;
	}
	my $cmdline = "$perl $bbagent -p $applpath";
	logging("Launching $cmdline");
	system($cmdline);
}

sub handle_jmeter($) {
	my ($applpath) = @_;
	my ($applname, $appldir, $suffix) = fileparse("$applpath",@suffixlist);
	# Check for application ini file must be done in bbagent.pl
	if (not -x $perl) {
		error("Cannot find executable $perl to launch $applname");
		return;
	}
	if (not -r $jmxagent) {
		error("Cannot read jmeter agent $jmxagent to launch $applname");
		return;
	}
	my $cmdline = "$perl $jmxagent -p $applpath";
	logging("Launching $cmdline");
	system($cmdline);
}

#####Nick###
sub handle_neoload($) {
	my ($applpath) = @_;
	my ($applname, $appldir, $suffix) = fileparse("$applpath",@nlpsuffixlist);
	# Check for application ini file must be done in bbagent.pl
	if (not -x $perl) {
		error("Cannot find executable $perl to launch $applname");
		return;
	}
	if (not -r $nlpagent) {
		error("Cannot read Neoload agent $nlpagent to launch $applname");
		return;
	}
	
	my $cmdline = "$perl $nlpagent -p $applpath";
	logging("Launching $cmdline");
	system($cmdline);

}
####Nick####
sub neoload_ini($) {
    # Initialize neoload configuration file
	# opgelet!!! nlpi file wordt hier doorgestuurd met het path erbij, moet dit???
  
       	$neoload_ini = new Config::IniFiles(-file	=> @_);
    if (not defined $neoload_ini) {
    	error("Could not process @_, errors: ".join("",@Config::IniFiles::errors));
	}
	$nlpappl = $neoload_ini->val("Main","neoloadappl");
 
    handle_neoload("$nlpappl");
	   
}

=pod

=head2 Handle Appls

This procedure will launch all perl scripts in a specific directory. It can be configured by the pre_run or post_run variable in the ini file.

Post-run processing will guarantee that all alerts will be filtered from the event table and forwarded to an SMS server. 

=cut

sub handle_apps($) {
	my ($fromdir) = @_;
	# Scan directory
	if (not(opendir(PROBEDIR, $fromdir))) {
		error("Could not open directory $fromdir for reading, exiting...");
		exit_application(1);
	}
	my @filelist = readdir(PROBEDIR);
	# Sort the files
	closedir(PROBEDIR);
	my @sortedlist = sort @filelist;
	foreach my $filename (@sortedlist) {
		my ($applname,$dirname,$suffix) = fileparse("$fromdir/$filename", @suffixlist);
		# Check for Perl script, launch script if so
		if (lc($suffix) eq "pl") {
			my $cmdline = "$perl $fromdir/$filename";
			system($cmdline);
	   }
	}
} 

######
# Main
######

# Handle input values
#
my %options;
getopts("tl:d:i:h:", \%options) or pod2usage(-verbose => 0);
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
# Check for scheduling ini file
if ($options{"i"}) {
	$inifile = $options{"i"};
	# Check inifile is readable
	if (not -r $inifile) {
		error("Could not open $inifile for reading, exiting...");
		exit_application(1);
	}
} else {
	error("Scheduler ini file has not been defined, exiting...");
	exit_application(1);
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Make sure File parsing is done using Microsoft Windows conventions
fileparse_set_fstype("MSWin32");

# Initialize scheduler configuration file
$schedule_ini = new Config::IniFiles(
							-file	=> $inifile);
if (not defined $schedule_ini) {
	error("Could not process $inifile, errors: ".join("",@Config::IniFiles::errors));
	exit_application(1);
}



# Enter infinite scheduling loop
while (1) {
	get_scheduler_ini_file();
	# Calculate next start time
	my $nextrun = time() + ($interval * 60);
	# Get PRE-RUN applications
	if (defined $prerun_dir) {
		handle_apps($prerun_dir);
	}
	# Scan directory
	if (not(opendir(PROBEDIR, $probedir))) {
		error("Could not open directory $probedir for reading, exiting...");
		exit_application(1);
	}
	my @filelist = readdir(PROBEDIR);
	closedir(PROBEDIR);
	foreach my $filename (@filelist) {
		my ($applname,$dirname,$suffix) = fileparse("$probedir/$filename", @suffixlist);
		# Check for Badboy script, launch agent script if so
		# Note that this is no longer in suffix list
		# so it should be ignored
		if (lc($suffix) eq "bb") {
		   handle_badboy("$probedir/$filename");
	   }
	   # Check for jmeter script, launch agent script if so
	   if (lc($suffix) eq "jmx") {
		   handle_jmeter("$probedir/$filename");
	   }
	   #####Nick###
	   # Check for neoload script, launch neoload initiator
	   if (lc($suffix) eq "nlpi") {
		   neoload_ini("$probedir/$filename");
	   }
	}
	# Get POST-RUN applications
	if (defined $postrun_dir) {
		handle_apps($postrun_dir);
	}
	# Calculate next run
	my $now = time();
	my $sleep = $nextrun - $now;
	if ($sleep > 0) {
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($nextrun);
		my $nextdatetime = sprintf("%02d-%02d-%04d %02d:%02d:%02d", $mday, $mon+1, $year+1900, $hour, $min,$sec);
		logging("Next run on $nextdatetime (sleeping for $sleep seconds)");
		close_log();
		sleep $sleep;
		# Force logfile per day
		open_log();
	} else {
		logging("No sleep required...");
		# Force logfile per day
		close_log();
		open_log();
	}
}

logging("Application managed to get out of loop...");
exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Process ini files for specific probes.

=back

=head1 AUTHOR


