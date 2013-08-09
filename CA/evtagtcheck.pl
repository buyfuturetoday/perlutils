=head1 NAME

evtagtcheck.pl - This script will verify availability of Event Agents using oprping.

=head1 VERSION HISTORY

version 1.0 - 4 September 2006 DV

=over 4

=item *

Initial Release.

=back

=head1 DESCRIPTION

The purpose of the application is to test availability of Unicenter event agents or event managers. Therefore a oprping command is issued to each event agent. Upon failure, an alert is written to the event console. Upon success, the reply time is extracted. If the reply time is above the threshold, then a warning message is issued.

=head1 SYNOPSIS

 evtagtcheck.pl [-t] [-l logfile_directory]  -s hosts-file [-m event-manager]

 evtagtcheck.pl -h	Usage Information
 evtagtcheck.pl -h 1	Usage Information and Options description
 evtagtcheck.pl -h 2	Full documentation

=head1 OPTIONS

=over 4

=item B<-t>

if set, then trace messages will be displayed. 

=item B<-l logfile_directory>

default: c:\temp

=item B<-s hosts-file>

File containing hostnames to check. Each hostname must be on a single line. Empty lines or lines starting with # are ignored.

=item B<-m event-manager>

Event manager where alerts need to be send. Optional, default value is localhost.

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
###########

my ($logdir, $hostfile, $eventmgr);
my $timeout = 50000;	# oprping warning if wait time > 50 sec

#####
# use
#####

use warnings;			    # show warnings
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Input parameter handling
use Pod::Usage;			    # Usage printing
# use File::Basename;		    # For logfilename translation
use Log;

#############
# subroutines
#############

sub exit_application($) {
    my($return_code) = @_;
    close HOSTS;
    logging("Exit application with return code $return_code\n");
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

=head2 Execute Command

This procedure accepts a system command, executes the command and checks on a 0 return code. If no 0 return code, then an error occured and control is transferred to the Display Error procedure.

=cut

sub execute_command($) {
    my ($command) = @_;
    if (system($command) == 0) {
#	logging("Command $command - Return code 0");
    } else {
	my $ErrorString = "Could not execute command $command";
	error($ErrorString);
#	exit_application(1);
#	display_error($ErrorString);
    }
}

sub verify_host($) {
    my ($host) = @_;
    my $cmd = "oprping $host 1 koekoek";
    my @outlist = `$cmd`;
    # There should one line on success, no lines on failure
    my $resline = shift @outlist;
    if (defined $resline) {
	my $searchstring = "oprping: node='$host' bytes=";
	if (index($resline, $searchstring) == 0) {
	    # Successful return, extract time
	    my $searchstart = "time=";
	    my $searchend = "ms";
	    my $startpos = index($resline, $searchstart);
	    if ($startpos == -1) {
		# Unrecognized format, issue error
		$cmd = "logforward -n$eventmgr -f$host -vE -t\"STATE_CRITICAL | oprping eventagent connectivity critical unrecognized format $resline";
		execute_command($cmd);
		error("oprping $host unexpected response: $resline");
	    } else {
		$startpos = $startpos + length($searchstart);
		my $endpos = index($resline, $searchend, $startpos);
		if ($endpos == -1) {
		    # Unrecognized format, issue error
		    $cmd = "logforward -n$eventmgr -f$host -vE -t\"STATE_CRITICAL | oprping eventagent connectivity critical unrecognized format $resline";
		    execute_command($cmd);
		    error("oprping $host unexpected response: $resline");
		} else {
		    my $resptime = substr($resline, $startpos, $endpos-$startpos);
		    if ($resptime > $timeout) {
			$cmd = "logforward -n$eventmgr -f$host -vE -t\"STATE_WARNING | oprping eventagent connectivity warning response time $resptime ms threshold $timeout ms";
			execute_command($cmd);
			logging("WARNING: oprping host replied in $resptime ms");
		    } else {
			logging("$host replied in $resptime ms");
		    }
		}
	    }
	} else {
	    # Don't recognize return, issue error
	    $cmd = "logforward -n$eventmgr -f$host -vE -t\"STATE_CRITICAL | oprping eventagent connectivity critical unrecognized format $resline";
	    execute_command($cmd);
	    error("oprping $host unexpected response: $resline");
	}
    } else {
	# No connection, issue error
	$cmd = "logforward -n$eventmgr -f$host -vE -t\"STATE_CRITICAL | oprping eventagent connectivity critical no response from agent";
	execute_command($cmd);
	error("Event Agent on $host not responding");
    }
}

######
# Main
######

# Handle input values
my %options;
getopts("l:th:u:p:s:c:a:", \%options) or pod2usage(-verbose => 0);
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
} else {
    $logdir=logdir();
}
if (-d $logdir) {
    trace("Logdir: $logdir");
} else {
    pod2usage(-msg     => "Cannot find log directory ".logdir,
	      -verbose => 0);
}
# Logdir found, start logging
open_log();
logging("Start application");
if ($options{"s"}) {
    $hostfile = $options{"s"};
} else {
    error("Hostfile not defined, exiting...");
    exit_application(1);
}
if (not(-r $hostfile)) {
    error("Serverfile $hostfile not readable, exiting...");
    exit_application(1);
}
if ($options{"m"}) {
    $eventmgr = $options{"m"};
} else {
    $eventmgr = $ENV{COMPUTERNAME};
}
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Read hosts file, handle hosts one by one
my $openres = open(HOSTS, $hostfile);
if (not(defined $openres)) {
    error("Could not open serverfile $hostfile for reading, exiting...");
    exit_application(1);
}
while (my $host = <HOSTS>) {
    chomp $host;
    # Ignore any line that does not start with character
    if ($host =~ /^[A-Za-z]/) {
	$host = trim($host);
	verify_host($host);
    }
}

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Verify return codes from the commands

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
