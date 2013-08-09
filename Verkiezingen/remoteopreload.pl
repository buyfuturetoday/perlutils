=head1 NAME

remoteopreload.pl - This script allows to run a remote opreload on a number of event agents.

=head1 VERSION HISTORY

version 1.0 - 5 September 2006 DV

=over 4

=item *

Initial Release.

=back

=head1 DESCRIPTION

The purpose of the application is to send a remote opreload command to one or more event agents. One host can be specified as a parameter, or a file containing one or more hosts can be specified. For each host name a look-up is done if the name exist. If the host does not exist in the reference table, then the opreload is ignored.

=head2 Procedure

The idea is that updates are made to the *.cau files. These files are then reloaded using the B<cautil -f filename.cau> command, or load all *.cau files at once with B<foreach . *.cau cautil -f>. 

The OPERA database needs to be reloaded I<only> on the hosts that need the change.

=head1 SYNOPSIS

 remoteopreload.pl [-t] [-l logfile_directory]  -s hosts-file | -i host

 remoteopreload.pl -h	Usage Information
 remoteopreload.pl -h 1	Usage Information and Options description
 remoteopreload.pl -h 2	Full documentation

=head1 OPTIONS

=over 4

=item B<-t>

if set, then trace messages will be displayed. 

=item B<-l logfile_directory>

default: c:\temp

=item B<-s hosts-file>

File containing hostnames to check. Each hostname must be on a single line. Empty lines or lines starting with # are ignored.

=item B<-i host>

Single host where to send opreload command to.

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
###########

my ($logdir, $hostfile, $hostname, %hosts);
my @hosts_array = ("s110229",
		   "s110230",
		   "s110231",
		   "s110232",
		   "s110233",
	           "s110234",
		   "s117780",
		   "s117781",
		   "s117791",
		   "s117796",
		   "s060606",
		   "s041441.vlaanderen.be",
		   "s117778.vlaanderen.be",
		   "lv-rev-prox-1",
		   "lv-rev-prox-2",
		   "bebswmvgbv94",
		   "behawmvgvv94",
		   "bebssmvgbv90",
		   "behasmvgvv90");


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
	logging("Command $command - Return code 0");
    } else {
	my $ErrorString = "Could not execute command $command";
	error($ErrorString);
#	exit_application(1);
#	display_error($ErrorString);
    }
}

sub handle_host($) {
    my ($host) = @_;
    if (exists $hosts{$host}) {
	my $cmd = "cawto -n $host Reload OPR cache";
	execute_command($cmd);
    } else {
	error("Cannot find $host in lookup table, ignoring this host.");
    }
}

######
# Main
######

# Handle input values
my %options;
getopts("l:th:s:i:", \%options) or pod2usage(-verbose => 0);
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
    if (not(-r $hostfile)) {
	error("Serverfile $hostfile not readable, exiting...");
	exit_application(1);
    }
}
if ($options{"i"}) {
    $hostname = $options{"i"};
}
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Now verify that one and only one option is selected.
if ((not defined $hostname) and (not defined $hostfile)) {
    error("Hostname or hostfile not specified, exiting...");
    exit_application(1);
}
if ((defined $hostname) and (defined $hostfile)) {
    error("Hostname $hostname and hostfile $hostfile both defined, please select only one of both.");
    exit_application(1);
}

# Then convert hosts array to lookup table
foreach my $value (@hosts_array) {
    $hosts{$value} = 1;
}

# Now handle host or file
if (defined $hostfile) {
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
	    handle_host($host);
	}
    }
} else {
    handle_host($hostname);
}

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Nothing so far.....

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>

