=head1 NAME

LogPlayer - Event Logplayer script

=head1 VERSION HISTORY

version 1.1 17 July 2007 DV

=over 4

=item *

Do not send %CATD_I_060, SNMPTRAP messages

=back

version 1.0 5 July 2007 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application is a Perl script version of the Unicenter Event Log Player. It allows to add some more user control on which events to send and how fast to send them. This should allow for stress testing and other specific tests.

=head1 SYNOPSIS

LogPlayer.pl [-t] [-l log_dir] -c console_file

    LogPlayer.pl -h	 Usage
    LogPlayer.pl -h 1   Usage and description of the options
    LogPlayer.pl -h 2   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: c:\temp. Logging is enabled by default. 

=item B<-c console_file>

Console log in flat file format. This flat file is created with the command I<cautil select conlog list conlog out=conlog.csv>.

Note that cautil select conlog does not seem to work for event logs that are copied from another server. Therefore make sure that there are not MRAs defined and no AEC rules, clean the current event log and run the event log through the event log player to make it a file created on the local system. Now it should be possible to dump the new log file into a flat text file.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.8.0, build 804 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $conlog_file, $cnt_events, $cnt_loop);
# Do send SNMPTrap for ABN (AgentVerification is required)
my $snmpid = "XXX CATD_I_060, SNMPTRAP";
my $sleepsec = 1;		# Seconds to sleep after handling number of records
my $handled_recs = 1000000;	# Records handled before sleeping

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use Log;

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	logging("$cnt_events sent to Event Manager.");
	logging("Exit application with return code: $return_code\n");
    close_log();
    exit $return_code;
}

sub trim {
    my @out = @_;
    for (@out) {
        s/^\s+//;
        s/\s+$//;
    }
    return wantarray ? @out : $out[0];
}


######
# Main
######

# Handle input values
my %options;
getopts("h:tl:c:", \%options) or pod2usage(-verbose => 0);
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
# Find Event file
if ($options{"c"}) {
	$conlog_file = $options{"c"};
	# Verify that the console log file is readable.
	if (not(-r $conlog_file)) {
    	error("Cannot access Console logfile $conlog_file for reading, exiting...");
    	exit_application(1);
	}
} else {
	error("Console log file not defined, exiting...");
	exit_application(1);
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input value

# Open Console Log file for reading
my $openres = open (Conlog, $conlog_file);
if (not defined $openres) {
	error("Couldn't open $conlog_file for reading, exiting...");
	exit_application(1);
}

# Read and ignore title line from conlog.csv
<Conlog>;

# Handle all lines in Console Event Log
while (my $line = <Conlog>) {
	chomp $line;
	my ($Date,$Time,$RecId,$Node,$User,$Station,$Color,$Attrib,$Type,$Flags,$Timegen,$Msgnum,$Severity,$Exit,$Workload,$Pinfo,$Tag,$Category,$Bindata,$Device,$Udata,$Source,$Text,$Annotation) = split /\",\"/,$line;
	# Do not sent %CATD_I_060, SNMPTRAP messages for now
	if (index($Text,$snmpid) == -1) {
		my $arglist = "-nlocalhost";	# Change this value for event forwarding to another event manager.
		$arglist .= " -f"."\"".$Node."\"";			# Node field
		$arglist .= " -v"."\"".$Severity."\"";		# Severity
		$arglist .= " -u"."\"".$User."\"";			# User
		$arglist .= " -x"."\"".$Station."\"";		# Station
		$arglist .= " -s"."\"".$Source."\"";		# Source
		$arglist .= " -t"."\"".$Text."\"";			# Text
		my $cmd = "logforward $arglist";
    	my @cmd_output = `$cmd`;
    	my $cmd_lines = @cmd_output;
    	if ($cmd_lines == 0) {
			#	logging("Successfully send record $targetserver\n$cmd");
			$cnt_events++;
			#return 0;
		} else {
			error("Error while sending record to event console\nCommand: $cmd\n@cmd_output");
			exit_application(1);
    	}
		# Implement wait after each 100 records
		$cnt_loop++;
		if ($cnt_loop >= $handled_recs) {
			$cnt_loop = 0;
			print "Sleep $sleepsec secs, $cnt_events events handled\n";
			sleep $sleepsec;
		}
	}
}

print "Sleep 2 minutes, to allow Oprdaemon to finalize\n";
sleep 120;

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Allow to send events to event console on another server (-n parameter).

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
