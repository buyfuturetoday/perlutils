=head1 NAME

serverreboot.pl - Periodically checks possible server reboots by comparing sysUpTime.

=head1 VERSION HISTORY

version 1.0 15 September 2006 DV

=over 4

=item *

Initial version, based on snmpcheck.pl and DB_Connection.pl

=back

=head1 DESCRIPTION

The application reads a host-systuptime file. For each host the current sysuptime is requested and compared with the value stored in the host-sysuptime file. In case the new value is lower than the stored value, then a system reboot is assumed and a message is sent to the Unicenter Event Console. The application runs on a regular base (e.g. every 10 minutes).


This script requires the Net::SNMP module (which is depending on the Crypt::DES module).

=head1 SYNOPSIS

serverreboot.pl [-t] [-l log_dir] [-c community_string] [-d debug_mode] -f host-sysuptime_file [-m event-manager

 serverreboot.pl -h	Usage information
 serverreboot.pl -h 1	Usage information and a description of the options
 serverreboot.pl -h 2	Full documentation

=head1 OPTIONS

=over 4

=item B<-t>

enable trace messages, if set

=item B<-l log_dir>

Logfile directory, default: c:\temp\log

=item B<-c community_string>

READ community string, default: public

=item B<-d debug_mode>

Debug mode, default: 0. Debugging can be enabled on a per component level as defined by a bit mask. The bit mask is broken up as follows:

=over 8

=item B<2> - Message or PDU encoding and decoding

=item B<4> - Transport Layer 

=item B<8> - Dispatcher 

=item B<16> - Message Processing 

=item B<32> - Security

=item B<255> - Enter (-d 255) to catch all debug messages.

=back

=item B<-f host-sysuptime_file>

The host-sysuptime file has host, sysuptime pairs. If a host needs to be added to the list, then the I<hostname=> must be added to the file. The application will recognize the empty sysuptime and will not trigger an initial alarm. Hosts that no longer need to be verified can be removed from the host-sysuptime file.

Note that the application will rewrite the file on each run, so no comments should be added to the file. Also hosts should be added / removed only when the application is not running. All hostnames will be lowercase.

=item B<-m event-manager>

Event manager where alerts need to be send. Optional, default value is localhost.

=back

=head1 ADDITIONAL INFORMATION

=cut

###########
# Variables
###########

my $timeout = 5;		    # REMARK - the used timeout seems to be ($timeout * 2) !!!
my ($logdir, %hosts, %new_values, $community, $debug, $hosts_file, $eventmgr);
my $port = 161;			    # Default SNMP port
my $oid = "1.3.6.1.2.1.1.3.0";	    # sysUpTime


#####
# use
#####

use warnings;
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Net::SNMP;			# SNMP processing
use Getopt::Std;		# input parameter handling
use Pod::Usage;			# Usage printing
use File::Basename;		# $0 to basename conversion
use Log;

#############
# subroutines
#############

sub exit_application($) {
    my($return_code) = @_;
    close Hosts;
    close Status;
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

=pod

=head2 Read ini file Procedure

This procedure will read all lines in a section from a ini file. All keys will be converted to lowercase, values will remain untouched. All key/value pairs will be stored in a hash. Duplicate keys in a section are allowed but not recommended. The last value will have precedence.

=cut

sub read_ini_file() {
    my $openres = open(Hosts, $hosts_file);
    if (not defined $openres) {
	error("Cannot open Hosts-sysuptime file $hosts_file for reading, exiting...");
	exit_application(1);
    }
    while (my $line = <Hosts>) {
	chomp $line;
	# Ignore any line that does not start with character
	if ($line =~ /^[A-Za-z]/) {
	    $line = trim($line);	# Make sure no more trailing blanks
	    my ($host, $uptime) = split (/=/, $line);
	    $host = lc(trim($host));
	    if (defined $uptime) {
		$uptime = trim($uptime);
		if ($uptime =~ /^[+-]?\d+$/) {
		    $hosts{$host} = $uptime;
		} else {
		    $hosts{$host} = -1;
		}
	    } else {
		$hosts{$host} = -1;
	    }
	}
    }
    close Hosts;
}

=pod

=head2 Write Current Status

This procedure will keep track of the current status: hostname and sysuptime pairs in alphabetical order.

=cut

sub write_curr_stat() {
   my $openres =  open(Status, ">$hosts_file");
   if (defined $openres) {
	foreach my $key (sort keys %new_values) {
	    print Status "$key=$new_values{$key}\n";
	}
	close Status;
    } else {
	error("Could not open $hosts_file for writing");
    }
}

=pod

=head2 Verify Host

For each host this procedure will build an SNMP connection to the host and request the sysuptime. If sysuptime is available and bigger then previous sysuptime, then only a log message will be written. In other cases (sysuptime smaller so assumed system reboot or sysuptime could not be read) an error will be send to the Unicenter Event console.

=cut

sub verify_host($$) {
    my ($host, $sysuptime) = @_;
    # Create SNMP Object
    my ($session, $error) = Net::SNMP->session(
		Hostname => $host,
		Community => $community,
		Port => $port,
		Debug => $debug,
		Timeout => $timeout,
		Translate => 0);
    if (not defined $session) {
	logging("SNMP Session to host $host could not be created: $error");
    } else {
	# Request remote OID value
	my $response = $session->get_request($oid);
	if (defined $response) {
	    my $new_sysuptime = $response->{$oid};
	    if ($new_sysuptime < $sysuptime) {
		# New sysuptime less then previous sysuptime, possible reboot
		my $msg = "STATE_CRITICAL | rebootCheck reboot $host Restarted new time $new_sysuptime old time $sysuptime";
		my $cmd = "logforward -n$eventmgr -f$host -vE -t\"$msg\"";
		execute_command($cmd);
		error("Possible reboot for $host, old time: $sysuptime, new time: $new_sysuptime");
	    }
	    $new_values{$host} = $new_sysuptime;
	    logging("$host: $new_sysuptime");
	} else {
	    my $msg = "STATE_CRITICAL | rebootCheck reboot $host noSNMP could not get sysuptime for $host";
	    my $cmd = "logforward -n$eventmgr -f$host -vE -t\"$msg\"";
	    execute_command($cmd);
	    error("No Response from host $host: ".$session->error());
	    $new_values{$host} = -1;
	}
	$session->close();
    }
}

######
# Main
######

# Handle input values
my %options;
getopts("tl:c:d:f:h:", \%options) or pod2usage(-verbose => 0);
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
# Community name
if ($options{"c"}) {
    $community = $options{"c"};
} else {
    $community = "EDS_mgt_read";
}
if ($options{"d"}) {
    $debug = $options{"d"};
} else {
    $debug = 0;
}
# Find hosts-sysuptime file
if ($options{"f"}) {
    $hosts_file = $options{"f"};
    if (not (-r $hosts_file)) {
	error("Hosts-sysuptime file $hosts_file not readable, exiting...");
	exit_application(1);
    }
} else {
    error("Hosts-sysuptime file is not defined, exiting...");
    exit_application(1);
}
if ($options{"m"}) {
    $eventmgr = $options{"m"};
} else {
    $eventmgr = $ENV{COMPUTERNAME};
}
while (my ($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Read Hosts file and sysuptimes
read_ini_file();

# Handle all hosts
while (my ($host,$sysuptime) = each %hosts) {
    verify_host($host,$sysuptime);

}

write_curr_stat();


exit_application(0);

=pod

=head1 To Do

=over 4

=item *

please let me know....

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>

