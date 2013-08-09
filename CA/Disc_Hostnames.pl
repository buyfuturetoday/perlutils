=head1 NAME

Disc_Hostnames - Verify Discovery starting from a hostnames file.

=head1 VERSION HISTORY

version 1.0 - 3 April 2004 DV

=over 4

=item *

Initial Release

=back

=head1 DESCRIPTION

This application checks the possibility for Unicenter Discovery, starting from a hostnames file. For each entry in the hostnames file, the hostname is read and check for "Discovery readiness".

A number of checks are performed:

=over 4

=item
Verify if the name can be resolved to an IP address.

=item
Verify if the IP address resolves to the same name.

=item
Verify ICMP connectivity (ping) to the name.

=item
Check sysobjectID, SNMP call on 161 to be able to classify the host.

=item
Check Unicenter Log Agent version, to check SNMP call on 6665.

=item
Check appropriate OS agent.

=back

The result are available in a csv file for further processing.

=head1 SYNOPSIS

 Disc_Hostnames.pl [-t] [-l logfile_directory]  -f hostnames_file [-o output_dir] [-c SNMP_Community_String]

 Disc_Hostnames.pl -h	Usage Information
 Disc_Hostnames.pl -h 1	Usage Information and Options description
 Disc_Hostnames.pl -h 2	Full documentation

=head1 OPTIONS

=over 4

=item B<-t>

if set, then trace messages will be displayed. 

=item B<-l logfile_directory>

default: c:\temp

=item B<-f hostnames_file>

If specified, then a file with only hostnames is available. This is mutually exclusive with the hosts file.

=item B<-o output_dir>

Directory to put the resulting files, by default c:\temp.

=item B<-c SNMP_Community_String>

SNMP Community string. Default EDS_mgt_read. There is only one SNMP community string possible for OS SNMP and Unicenter SNMP.

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
###########

my $output_dir = "c:/temp";	# Default output directory
my ($logdir, $ip, $hostname, $res_host, $res_ip);
my ($ping_obj);
my $hostnames_file = "";
my $community = "EDS_mgt_read";	# Default community string
my $timeout = 10;		# REMARK - the used timeout seems to be ($timeout * 2) !!!

#####
# use
#####

use warnings;			    # show warnings
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Net::DNS;
use Net::Ping;
use Net::SNMP;
use Getopt::Std;		    # Input parameter handling
use Pod::Usage;			    # Usage printing
use File::Basename;		    # For logfilename translation
use Log;

#############
# subroutines
#############

sub exit_application($) {
    my($return_code) = @_;
    close DNS;
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

=head2 Open Output files

This section opens the  outputfile YYYYMMDD_DiscCheck.csv in the specified output directory. Existing files will be overwritten.

=cut

sub open_output_files() {
    
    # Today's date
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my $today = sprintf ("%04d%02d%02d", $year+1900, $mon+1, $mday);

    my $DNS = "$output_dir/$today"."_DiscCheck.csv";
    my $openres = open(DNS, ">$DNS");
    if (not(defined $openres)) {
	error("Could not open $DNS for writing.");
	exit_application(1);
    }
    
    print DNS "Hostname;IP;Discovered Name;ICMP;Ident.;Win2k;WinNT\n";
}


=pod

=head2 Open hosts file

Open the hosts file for reading. If a hostnames file is specified, then this file will be opened. Otherwise, the hosts file is used. Exit if the file cannot be opened.

=cut

sub open_hosts_file($) {
    my($file2open) = @_;
    my $openres = open(HOSTS, $file2open);
    if (not(defined $openres)) {
	error ("Could not open $file2open for reading.");
	exit_application(1);
    }
}

=pod

=head2 Handle Hostnames_File

The hostnames file contains a list of host names. Each line has a hostname and only a hostname.

=cut

sub handle_hostnames_file {
    while (my $line = <HOSTS>) {
	chomp $line;
	# Ignore empty lines
	if (length ($line) > 0) {
	    $hostname = trim($line);
	    # Hostname found, try to find an IP Address
	    find_ip();
	    my $result_string = "$hostname;$ip";
	    #if ($ip eq "UNDEFINED") {
	    #	print DNS "$result_string\n";
	    #} else {
		verify_name();
		$result_string = "$result_string;$res_host";
		my $ping_res = pingcheck($hostname);
		$result_string = "$result_string;$ping_res";
		# Continue checking even if ping was not successful
		# ICMP may be disabled while SNMP is available (portal).
		my $identification_oid = "1.3.6.1.2.1.1.2.0";
		my $identification_res=find_oid($hostname, 161, $identification_oid);
		# To do: if identification_oid successful,
		# then discover only expected objects.
		# Try to discover all objects only if identification_oid
		# coult not be found.
		my $win2k_oid="1.3.6.1.4.1.791.2.10.2.43.1.1.1.0";
		my $win2k_res=find_oid($hostname, 6665, $win2k_oid);
		my $winnt_oid="1.3.6.1.4.1.791.2.10.2.52.1.1.1.0";
		my $winnt_res=find_oid($hostname, 6665, $winnt_oid);
		print DNS "$result_string;$identification_res;$win2k_res;$winnt_res\n";
		#}
	}
    }
}

# Lookup hostname for the IP address, compare with defined hostname
# If match, write to DNS_OK
# If no match, write to DNS_Name_NOK
# Lookup IP address for hostname, compare with defined IP address
# If match, write to DNS_OK
# If no match, write to DNS_IP_NOK

=pod

=head2 Verify Name

Lookup the IP address in the resolver. The IP address should resolve to the hostname. Add the result to the csv output file.

=cut

sub verify_name() {
    my $resolver = new Net::DNS::Resolver;
    my $query = $resolver->search("$ip");
    if ($query) {
	foreach my $rr ($query->answer) {
	    # next unless $rr->type eq "A";
	    trace($rr->string);
	    my $host_string=$rr->string;
	    my (undef,undef,undef,undef,$host)=split /\t/,$rr->string;
	    # hostname tends to have a . in the end -> remove
	    if (substr($host,length($host)-1) eq ".") {
		$host = substr($host,0,length($host)-1);
	    }
	    if ($host ne $hostname) {
		$res_host = $host;
		logging("Another host found for $hostname");
	    } else {
		$res_host = "";
		logging("Host $host ok for $ip");
	    }
	}
    } else {
	$res_host = "UNDEFINED";
	error ("Trying to find hostname for IP $ip (expect: $hostname).");
	error ("query failed: ".$resolver->errorstring);
    }
}

=pod

=head2 Find IP Address

Lookup the hostname in the resolver. The hostname should resolve to the IP address. This is the IP address that will be assigned to the hostname.

=cut

sub find_ip() {
    my $resolver = new Net::DNS::Resolver;
    my $query = $resolver->search("$hostname");
    if ($query) {
	foreach my $rr ($query->answer) {
	    next unless $rr->type eq "A";
	    trace($rr->string);
	    $ip = $rr->address;
	}
    } else {
	$ip = "UNDEFINED";
	error ("Trying to find IP for hostname $hostname.");
	error ("query failed: ".$resolver->errorstring);
    }
}

=pod

=head2 Ping Check

Check ICMP connectivity on hostname or on IP address, return "SUCCESS" or "FAILED".

=cut

sub pingcheck($) {
    my ($hostid) = @_;
    my $ping_res = $ping_obj->ping($hostid);
    if ($ping_res) {
        return "SUCCESS";
    } else {
        return "FAILED";
    }
}

=pod

=head2 Find OID

Call the procedure with parameters host, port and OID string. Create a session, if successful, then request OID. 

=cut

sub find_oid($$$) {
    my ($host,$port,$oid) = @_;
    # Create SNMP Object
    my ($session, $error) = Net::SNMP->session(
			    Hostname => $host,
			    Community => $community,
			    Port => $port,
			    Timeout => $timeout);
    if (defined $session) {
	# Request remote OID value
	my $response = $session->get_request($oid);
	if (defined $response) {
	    return "SUCCESS";
	} else {
	    return "FAILED";
	}
    } else {
	error("SNMP Session could not be created for host $host on port $port looking for $oid");
	error("$error");
	return "NO Session";
    }
}


######
# Main
######

# Handle input values
my %options;
getopts("tl:f:o:c:h:", \%options) or pod2usage(-verbose => 0);
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
# Find output directory
if ($options{"o"}) {
    $output_dir = $options{"o"};
}
if (-d $output_dir) {
    trace("Output Directory: $output_dir");
} else {
    error("Cannot find output directory $output_dir.\n");
    exit_application(1);
}
# Check for hostnames file
if ($options{"f"}) {
    $hostnames_file=$options{"f"};
    if (not(-r $hostnames_file)) {
	error("Cannot access hostnames file $hostnames_file, exiting...");
	exit_application(1);
    }
} else {
    error("No hostnames file defined, exiting...");
    exit_application(1);
}
# Check for community string
if ($options{"c"}) {
    $community = $options{"c"};
}
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Create ping object
$ping_obj=Net::Ping->new("icmp");

# Open Output file for writing
open_output_files();

# Open hostnames file for reading
open_hosts_file($hostnames_file);

# Handle all entries in the hostnames file
handle_hostnames_file();

exit_application(0);

=pod

=head1 To Do

=over 4

=item * 

verify_name() subroutine has "# next". Don't understand why it is a "#" before...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
