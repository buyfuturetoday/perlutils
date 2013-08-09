=head1 NAME

DNS_Check - Verify Name Resolution

=head1 VERSION HISTORY

version 1.1 - 30 March 2004 DV

=over 4

=item *

Add Ping Connectivity Test

=back

version 1.0 - 10 March 2004 DV

=over 4

=item *

Initial Release

=back

=head1 DESCRIPTION

This application allows to verify DNS name resolution. 

In cases where name resolution is not the most reliable thing, a etc\hosts file is used to identify the hosts. The goal of the application is to highlight the hosts for which DNS name resolution is not OK. When name resolution is working fine for all hosts, then the etc\hosts file can be eliminated.

Verification is done by walking through the etc\hosts file, read the IP address and the primary name for the server. Then do a lookup to translate IP address in name and verify if this matches with the name in the etc/hosts file. Lookup the name and check if this matches with the IP address. All mismatches must be reported. Full matches mean that the name resolution is working fine and the name can be removed from the etc\hosts file.

Three csv_reports are created: 1. translation in both directions works fine (YYYYMMDD_DNS_OK) - 2. IP translates to another hosts name (YYYYMMDD_DNS_Name_NOK.csv) - 3. host name translates to another IP address (YYYYMMDD_DNS_IP_NOK.csv). There will be one file per day. Subsequent runs on the same day may result in file overwrites.

=head1 SYNOPSIS

 DNS_Check.pl [-t] [-l logfile_directory]  [-f hosts_file] [-o output_dir] [-C]

 DNS_Check.pl -h	Usage Information
 DNS_Check.pl -h 1	Usage Information and Options description
 DNS_Check.pl -h 2	Full documentation

=head1 OPTIONS

=over 4

=item B<-t>

if set, then trace messages will be displayed. 

=item B<-l logfile_directory>

default: c:\temp

=item B<-f hosts_file>

Full path and file name to the hosts file. By default c:\winnt\system32\drivers\etc\hosts.

=item B<-o output_dir>

Directory to put the resulting files, by default c:\temp.

=item B<-C>

If specified, then test ICMP connectivity. Default: do not specify ICMP connectivity.

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
###########

my $output_dir = "c:/temp";	# Default output directory
my $hostfile = "c:/winnt/system32/drivers/etc/hosts";	# hosts file default directory
my ($logdir, $ip, $hostname, $res_host, $res_ip);
my ($ip_conn, $host_conn, $ping_obj, $connectivity);

#####
# use
#####

use warnings;			    # show warnings
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Net::DNS;
use Net::Ping;
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

This section opens the three outputfiles YYYYMMDD_DNS_OK.csv, YYYYMMDD_DNS_Name_NOK.csv and YYYYMMDD_DNS_IP_NOK.csv in the specified output directory. Existing files will be overwritten.

=cut

sub open_output_files() {
    
    # Today's date
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my $today = sprintf ("%04d%02d%02d", $year+1900, $mon+1, $mday);

    my $DNS = "$output_dir/$today"."_DNS.csv";
    my $openres = open(DNS, ">$DNS");
    if (not(defined $openres)) {
	error("Could not open $DNS for writing.");
	exit_application(1);
    }
    
    print DNS "IP;Discovered IP;Hostname;Discovered Hostname";
    if (defined($connectivity)) {
	print DNS ";IP Conn.;Host Conn.\n";
    } else {
	print DNS "\n";
    }
}


=pod

=head2 Open hosts file

Open the hosts file for reading. Exit if the file cannot be opened.

=cut

sub open_hosts_file() {
    my $openres = open(HOSTS, $hostfile);
    if (not(defined $openres)) {
	error ("Could not open $hostfile for reading.");
	exit_application(1);
    }
}

=pod

=head2 Handle Hosts file

For each line in the host file: Read line to determine if it contains IP address / hostname information. An IP address must start on position 1 and must end with space or tab. If not, read next line. Otherwise, extract IP address and call procedure to extract hostname.

=cut

sub handle_hosts_file() {
  
    while (my $line = <HOSTS>) {
	chomp $line;
	# Ignore empty lines
	if (length ($line) > 0) {
	    # First part must be IP Address => first char must be a digit
	    my $char=substr($line,0,1);
	    if ($char =~ /[0-9]/) {
		# Find IP delimiter space or tab, whatever comes first
		my $space=index($line," ");
		if ($space == -1) {$space = length($line);}
		my $tab=index($line,"\t");
		if ($tab == -1) {$tab = length($line);}
		if ($space < $tab) {
		    $ip=substr($line,0,$space);
		    $hostname=substr($line,$space);
		} else {
		    $ip=substr($line,0,$tab);
		    $hostname=substr($line,$tab);
		}
		$hostname=strip($hostname);
		trace("Now investigating IP $ip, host $hostname");
		$res_host = "";
		$res_ip = "";
		verify_name();
		verify_ip();
		print DNS "$ip;$res_ip;$hostname;$res_host";
		if (defined($connectivity)) {
		    print DNS ";$ip_conn;$host_conn\n";
		} else {
		    print DNS "\n";
		}
	    }
	}
    }
}

=pod

=head2 strip

Strip hostname from inputline. Hostname can be preceded by spaces and/or tabs. Remove all of them to find the start of the hostname. Terminator is space, tab or end-of-line.

=cut

sub strip($) {
    my($hostname)=@_;
    $hostname=trim($hostname);
    # hostname can be preceded by tab '\t' or space
    while (substr($hostname,0,1) eq "\t") {
	$hostname=substr($hostname,1);
	$hostname=trim($hostname);
    }
    # hostname delimiter can be tab '\t'or space.
    # Find IP delimiter space or tab, whatever comes first
    my $space=index($hostname," ");
    if ($space == -1) {$space = length($hostname);}
    my $tab=index($hostname,"\t");
    if ($tab == -1) {$tab = length($hostname);}
    if ($space < $tab) {
        $hostname=substr($hostname,0,$space);
    } else {
        $hostname=substr($hostname,0,$tab);
    }
    return ($hostname);
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
		logging("Host $host ok for $ip");
	    }
	}
    } else {
	$res_host = "UNDEFINED";
	error ("Trying to find hostname for IP $ip (expect: $hostname).");
	error ("query failed: ".$resolver->errorstring);
    }
    if (defined($connectivity)) {
	my $ping_res = $ping_obj->ping($ip);
	if ($ping_res) {
	    $ip_conn="Yes";
	} else {
	    $ip_conn="No";
	}
    }
}

=pod

=head2 Verify IP Address

Lookup the hostname in the resolver. The hostname should resolve to the IP address. Add the result to the csv output file.

=cut

sub verify_ip() {
    my $resolver = new Net::DNS::Resolver;
    my $query = $resolver->search("$hostname");
    if ($query) {
	foreach my $rr ($query->answer) {
	    next unless $rr->type eq "A";
	    trace($rr->string);
	    my $det_ip = $rr->address;
	    if ($det_ip ne $ip) {
		$res_ip = $det_ip;
		logging("Another IP Address found for $hostname");
	    } else {
		logging("IP $ip ok for $hostname");
	    }
	}
    } else {
	$res_ip = "UNDEFINED";
	error ("Trying to find IP for hostname $hostname (expect: $ip).");
	error ("query failed: ".$resolver->errorstring);
    }
    if (defined($connectivity)) {
	my $ping_res = $ping_obj->ping($hostname);
	if ($ping_res) {
	    $host_conn="Yes";
	} else {
	    $host_conn="No";
	}
    }
}


######
# Main
######

# Handle input values
my %options;
getopts("tl:f:o:Ch:", \%options) or pod2usage(-verbose => 0);
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
# Find hosts file
if ($options{"f"}) {
    $hostfile = $options{"f"};
}
if (-r $hostfile) {
    trace("Host file: $hostfile");
} else {
    error("Cannot find host file $hostfile");
    exit_application(1);
}
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
# Verify connectivity
if ($options{"C"}) {
    $connectivity="Yes";
}
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Create ping object if required
if (defined($connectivity)) {
    $ping_obj=Net::Ping->new("icmp");
}

open_output_files();
open_hosts_file();
handle_hosts_file();

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Read the Windows directory from an environment variable (on windows only - if on UNIX, then read from /etc/hosts).

=item *

Combine all output into one output file instead of three today.

=item * 

verify_name() subroutine has "# next". Don't understand why it is a "#" before...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
