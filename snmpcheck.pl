=head1 NAME

snmpcheck - Tests the connectivity to a snmp identifier

=head1 VERSION HISTORY

version 1.2 7 July 2002 DV

=over 4

=item *

Add debug flag during snmp checking

=back

version 1.1 29 March 2002 DV

=over 4

=item *

Add standard documentation and log file processing

=item *

Remove Unicenter specific items

=back

version 1.0 29 December 2000 DV

=over 4

=item *

Initial Release

=back

=head1 DESCRIPTION

snmpcheck verifies connectivity to a snmp identifier. It returns the value of the identifier on the (remote) host or an error message.

This script requires the Net::SNMP module.

=head1 SYNOPSIS

snmpcheck.pl [-t] [-l log_dir] [-r remote_host] [-p port] [-c community_string] [-o OID_identifier] [-d debug_mode]

 snmpcheck.pl -h	Usage information
 snmpcheck.pl -h 1	Usage information and a description of the options
 snmpcheck.pl -h 2	Full documentation

=head1 OPTIONS

=over 4

=item B<-t>

enable trace messages, if set

=item B<-l log_dir>

Logfile directory, default: c:\temp

=item B<-r remote_host>

hostname, default: localhost

=item B<-p port>

portnumber, default: 161

=item B<-c community_string>

READ community string, default: public

=item B<-o OID_identifier>

OID identifier, default: 1.3.6.1.2.1.1.3.0 (sysUpTime)

=item B<-d debug_mode>

Debug mode, default: 0. Debugging can be enabled on a per component level as defined by a bit mask. The bit mask is broken up as follows:

=over 8

=item B<2> - Message or PDU encoding and decoding

=item B<4> - Transport Layer 

=item B<8> - Dispatcher 

=item B<16> - Message Processing 

=item B<32> - Security

=back

Enter (-d 255) to catch all debug messages.

=back

=head1 ADDITIONAL INFORMATION

=cut

###########
# Variables
###########

$timeout = 5;	    # REMARK - the used timeout seems to be ($timeout * 2) !!!
$trace = 0;				    # 0: do not trace, 1: trace
$log = 1;				    # 0: do not log, 1: logging
$logfile = "LOGFILE";			    # Placeholder name
$logdir = "c:/temp";			    # Logdirectory

#####
# use
#####

use Net::SNMP;			# SNMP processing
use Getopt::Std;		# input parameter handling
use Pod::Usage;			# Usage printing
use File::Basename;		# $0 to basename conversion

#############
# subroutines
#############

sub error($) {
    my($txt) = @_;
    logging("Error in $inpfile: $txt");
}

sub trace($) {
    if ($trace) {
	my($txt) = @_;
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
	print "$datetime - Trace in $0: $txt\n";
    }
}

# SUB - Open LogFile
sub open_log() {
    if ($log == 1) {
	my ($logname, undef) = split (/\./, basename($0));
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$logfilename=sprintf(">>$logdir/$logname%04d%02d%02d.log", $year+1900, $mon+1, $mday);
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

# SUB - Handle exit application routines: logout if required, close log + issue return code
sub exit_application($) {
    my($return_code) = @_;
    if (defined $session) {
	$session->close;
    }
    logging("Exit application with return code $return_code\n");
    close_log();
    exit $return_code;
}

######
# Main
######

# Handle input values
getopts("tl:r:c:p:o:d:h:", \%options) or pod2usage(-verbose => 0);
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
# Host name or IP
if ($options{"r"}) {
    $host = $options{"r"};
} else {
    $host = "localhost";
}
# Community name
if ($options{"c"}) {
    $community = $options{"c"};
} else {
    $community = "public";
}
# Port
if ($options{"p"}) {
    $port = $options{"p"};
} else {
    $port = 161;
}
# OID Identifier
if ($options{"o"}) {
    $oid = $options{"o"};
} else {
    $oid = "1.3.6.1.2.1.1.3.0";	    # sysUpTime
}
# Debug
if ($options{"d"}) {
    $debug = $options{"d"};
} else {
    $debug = 0;
}
while (($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Create SNMP Object
($session, $error) = Net::SNMP->session(
		Hostname => $host,
		Community => $community,
		Port => $port,
		Debug => $debug,
		Timeout => $timeout);
if (defined $session) {
    logging("SNMP Session created");
    trace("SNMP Session created");
} else {
    logging("SNMP Session could not be created: $error");
    trace("SNMP Session could not be created: $error");
    exit_application(1);
}

# Request remote OID value
$response = $session->get_request($oid);
if (defined $response) {
    logging("Return value: ".$response->{$oid});
    print $response->{$oid};
} else {
    logging("No Response: ".$session->error());
    trace("No Response: ".$session->error());
    exit_application(1);
}

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Add "use strict, use warnings"

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>

