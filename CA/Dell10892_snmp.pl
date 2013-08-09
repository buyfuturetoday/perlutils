=head1 NAME

Dell10892_snmp - Simulate Traps for the Dell 10892.mib

=head1 VERSION HISTORY

version 1.1 1 June 2005 DV

=over 4

=item *

Add input variable to accept host IP and SNMP Community string. The host IP address must be resolvable on the receiving event agent.

=back

version 1.0 26 May 2005 DV

=over 4

=item *

Initial release, based on the da2snmp.pl script

=back

=head1 DESCRIPTION

This script simulates a trap for every specific 'Trap' number.

=head1 SYNOPSIS

 Dell10892_snmp [-t] [-l log_dir] [-e event_management_server] [-s sleeptime] [-a] [-i host_ip] [-c SNMP Community String]

    Dell10892_snmp -h	    Usage
    Dell10892_snmp -h 1	    Usage and description of the options
    Dell10892_snmp -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: c:\temp

=item B<-e event_management_server>

The server where the Unicenter Event Management server is running. This server will receive the SNMP traps. Default: bemew2064231.

The server name must be a name, not a dotted IP address. The translation from name to IP address is done in the application. (The application fails if the translation cannot be done).

=item B<-i host IP>

Host IP address, must be resolvable on the receiving event agent.

=item B<-c community>

SNMP Trap community string, default: public.

=item B<-a>

If specified then handle all events in the table, otherwise handle only one event.

=item B<-s sleeptime>

Sleeptime is the number of seconds to wait between firing the alerts. Sleeptime of 0 or negative means interactive mode: the script waits for user input before firing the next alert. Default: no sleeptime. 

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.6.1, build 631 provided by ActiveState.

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir);			    # Log file directory
my $dsource = "DA";		    # Data source name
my $host = "bemew2064231";	    # Unicenter Event Management server
my $host_IP = "145.16.19.37";	    # Agent sending the trap
my $community = "public";	    # SNMP Community string
my $handle_all = "NO";		    # Handle all events?
my $sleeptime = 1;		    # Time to sleep between firing alerts
my $nr_alerts = 0;
my $session;			    # SNMP session object
my $snmp_error;			    # Error pointer in SNMP object
my $dell_enterprise = "1.3.6.1.4.1.674.10892.1";
my $dell_name     = "1.3.6.1.4.1.674.10892.1.5000.10.1.0";
my $dell_tableoid = "1.3.6.1.4.1.674.10892.1.5000.10.2.0";
my $dell_message  = "1.3.6.1.4.1.674.10892.1.5000.10.3.0";
my $dell_currstat = "1.3.6.1.4.1.674.10892.1.5000.10.4.0";
my $dell_prevstat = "1.3.6.1.4.1.674.10892.1.5000.10.5.0";
my $dell_data     = "1.3.6.1.4.1.674.10892.1.5000.10.6.0";
my $generic = 6;
# List of all specific traps
my @specifics = (1001,
		 1004,
		 1006,
		 1007,
		 1052,
		 1053,
		 1054,
		 1055,
		 1102,
		 1103,
		 1104,
		 1105,
		 1152,
		 1153,
		 1154,
		 1155,
		 1202,
		 1203,
		 1204,
		 1205,
		 1252,
		 1254,
		 1304,
		 1305,
		 1306,
		 1352,
		 1353,
		 1354,
		 1403,
		 1404,
		 1405,
		 1452,
		 1453,
		 1454,
		 1501,
		 1502,
		 1504,
		 1552,
		 1553,
		 1554,
		 1602,
		 1603,
		 1604);

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use File::Basename;		    # logfilename translation
use Win32::ODBC;		    # Win32 ODBC module
use Net::SNMP;			    # To build SNMP connections
use Log;

#############
# subroutines
#############

sub exit_application($) {
    my($return_code) = @_;
    if (defined $session) {
	$session->close;
	logging("Close SNMP session.");
    }
    logging("$nr_alerts traps have been handled.");
    logging("Exit application with return code $return_code\n");
    close_log();
    exit $return_code;
}

=pod

=head2 Send Trap

This procedure assembles all available information into a proper SNMP Trap string and sends the trap to the destination host.

=cut

sub sendtrap($) {
    my ($specific) = @_;
    my @oidvalue = ();
    my @addvalue;
    @addvalue = ($dell_name, OCTET_STRING, 'ukdxsp2mn001');
    push @oidvalue, @addvalue;
    @addvalue = ($dell_tableoid, OCTET_STRING, '1.3.6.1.4.1.674.10892.1.700.10.1.2.1.1');
    push @oidvalue, @addvalue;
    # my $message = "Redundancy lost Redundancy unit: System Cooling Unit Chassis location: Main System Chassis Previous redundancy state was: Normal Number of devices required for full redundancy: 7";
    my $message = "Additional text as available in Dell-10892 trap";
    @addvalue = ($dell_message, OCTET_STRING, $message);
    push @oidvalue, @addvalue;
    @addvalue = ($dell_currstat, INTEGER, '4');
    push @oidvalue, @addvalue;
    @addvalue = ($dell_prevstat, INTEGER, '3');
    push @oidvalue, @addvalue;
    @addvalue = ($dell_data, OCTET_STRING, '');
    push @oidvalue, @addvalue;

    my $timeticks = time();
    my $response = $session->trap(-enterprise      => $dell_enterprise,
                           -agentaddr       => $host_IP,
    			   -generictrap     => $generic,
                           -specifictrap    => $specific,
                           -timestamp       => $timeticks,
    			   -varbindlist	    => \@oidvalue,
    );
    if (defined $response) {
	trace("Trap $specific send.");
    } else {
	error("Could not send trap $specific. ");
    }
    $nr_alerts++;
}

=pod

=head2 Create SNMP Session

This procedure will create an SNMP session to the Event Management Host

=cut

sub create_snmp() {
    ($session, $snmp_error) = Net::SNMP->session(
					-hostname => $host,
					-community => $community,
					-port => 162);	# No default value for port is accepted!
    if (defined $session) {
	logging("SNMP Session created");
	trace("SNMP Session created");
    } else {
	logging("SNMP Session could not be created: $snmp_error");
	trace("SNMP Session could not be created: $snmp_error");
	exit_application(1);
    }
}

######
# Main
######

# Handle input values

my %options;
getopts("tl:d:e:s:ac:i:h:", \%options) or pod2usage(-verbose => 0);
# my $arglength = scalar keys %options;  
# if ($arglength == 0) {		# If no options specified,
#    $options{"h"} = 0;			# display usage.
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
    trace_flag(1);
    trace("Trace enabled");
}
# Find log file directory
if ($options{"l"}) {
    $logdir = logdir($options{"l"});
} else {
    $logdir = logdir();
}
if (-d $logdir) {
    trace("Logdir: $logdir");
} else {
    pod2usage(-msg     => "Cannot find log directory $logdir.",
	      -verbose => 0);
}
# Logdir found, start logging
open_log();
logging("Start application");
# Find data source
if ($options{"d"}) {
    $dsource = $options{"d"};
}
# Event Management Server
if ($options{"e"}) {
    $host = $options{"e"};
}
# Host IP
if ($options{"i"}) {
    $host_IP = $options{"i"};
}
# SNMP Community String
if ($options{"c"}) {
    $community = $options{"c"};
}
if (defined $options{"a"}) {
    $handle_all = "YES";
}
# Sleeptime
if (defined $options{"s"}) {
    $sleeptime = $options{"s"};
}
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Open snmp session
create_snmp();

# Handle alerts
if ($handle_all eq "YES") {
    foreach my $specific (@specifics) {
	sendtrap($specific);
	sleep $sleeptime;
    }
} else {
    my $specific = 1306;
    sendtrap($specific);
}

exit_application(0);

=pod

=head1 TO DO

=over 4

=item *

Specify a start date/time and an end date/time for the alerts to be processed/

=item *

Handle the time ticks per alert. time = 0: time of the first alert. Use timeticks to identify alerts.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
