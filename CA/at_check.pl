=head1 NAME

at_check.pl - This script will verify availability of Agent Technologies services using servicectrl.

=head1 VERSION HISTORY

version 1.0 - 2 October 2006 DV

=over 4

=item *

Initial Release.

=back

=head1 DESCRIPTION

The purpose of this script is to test Agent Technologies services on a number of servers. Therefore the servicectrl command is issued and each output line is verified on RUNNING for all services.

=head1 SYNOPSIS

 at_check.pl [-t] [-l logfile_directory]  -s hosts-file [-m event-manager]

 at_check.pl -h		Usage Information
 at_check.pl -h 1	Usage Information and Options description
 at_check.pl -h 2	Full documentation

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
    logging("Verifying $host");
    my $cmd = "servicectrl status --remote=$host";
    my @outlist = `$cmd`;
    # The first word must be running, anything else is an 
    # error that needs to be escalated
    foreach my $line (@outlist) {
	chomp $line;
	if (substr($line,0,7) ne "RUNNING") {
	    $cmd = "logforward -n$eventmgr -f$host -vE -t\"STATE_CRITICAL | at_check agent technologies critical $line";
	    execute_command($cmd);
	    error("$host - $line");
	}
    }
}

######
# Main
######

# Handle input values
my %options;
getopts("l:th:s:m:", \%options) or pod2usage(-verbose => 0);
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
