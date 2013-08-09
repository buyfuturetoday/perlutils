=head1 NAME

Get_Stream.pl - This application accepts an Internet address and collects the stream on this address.

=head1 VERSION HISTORY

version 1.0 - 30 May 2004 DV

=over 4

=item *

Initial Release

=back

=head1 DESCRIPTION

This application gets an internet address as input and collects a stream. The purpose is to download music or radio programs from the internet, but any internet page (pictures, ...) can do.

Note that there is no re-direct, the internet data must be readily available.

=head1 SYNOPSIS

 Get_Stream.pl [-t] [-l logfile_directory]  -a http_address -n filename [-d filedirectory]

 Get_Stream.pl -h	Usage Information
 Get_Stream.pl -h 1	Usage Information and Options description
 Get_Stream.pl -h 2	Full documentation

=head1 OPTIONS

=over 4

=item B<-t>

if set, then trace messages will be displayed. 

=item B<-l logfile_directory>

default: c:\temp\log

=item B<-a http_address>

Internet address where to stream can be found. This must be the full internet address, including http:// etc.

=item B<-n filename>

This is the filename where to store the target file. Be sure to pick the correct file extenstion.

=item B<-d directory>

This is the directory where the output file will be stored. By default this is B<d:\My Music>

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
###########

my ($url, $filename, $proxy, $ua, $html, $logdir, $res);
my $directory="d:/My Music";	
my $proxyserver="internetabh.eds.com";
my $uatimeout=180;

#####
# use
#####

use warnings;			    # show warnings
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Input parameter handling
use Pod::Usage;			    # Usage printing
use File::Basename;		    # For logfilename translation
use Log;
use LWP::UserAgent;
use Net::hostent;		    # to determine whether to use the Proxy server

#############
# subroutines
#############

sub exit_application($) {
    my($return_code) = @_;
    logging("Exit application with return code $return_code\n");
    close_log();
    exit $return_code;
}

######
# Main
######

# Handle input values
my %options;
getopts("l:th:a:n:d:", \%options) or pod2usage(-verbose => 0);
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
# Find URL
if ($options{"a"}) {
    $url = $options{"a"};
} else {
    error("No URL found, exiting...");
    exit_application(1);
}
# Find name for target file
if ($options{"n"}) {
    $filename=$options{"n"};
} else {
    error("No name for target file found, exiting...");
    exit_application(1);
}
# Find directory for target file
if ($options{"d"}) {
    $directory=$options{"d"};
}
if (-d $directory) {
    trace("Target Directory: $directory");
} else {
    error("Cannot find target directory $directory.\n");
    exit_application(1);
}
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Determine to use a proxy
$proxy=gethost($proxyserver);

# Create a User Agent
$ua = LWP::UserAgent->new;
$ua->agent("DVagent");
$ua->timeout($uatimeout);
if (defined $proxy) {
    logging("using proxy");
    $ua->proxy('http', "http://". $proxyserver . ":80");
}

# Collect the web info
my $req=new HTTP::Request 'GET' => $url;
if (defined $proxy) {
    $req->proxy_authorization_basic("dz09s6","pietje03");
}
# Ofthen there seem to be problems with the proxyserver. 
# The assumption is that this is due to specific proxy problems, so
# retrying may solve the problem.
# Currently 3 attempts are made to get through the proxy server.
my $cnt=0;
while ($cnt < 3) {
    $cnt++;
    $res=$ua->request($req);
    logging("$url: ".$res->status_line);
    if (index($res->status_line,$proxyserver) > -1) {
        error("Issue with $proxyserver on attempt $cnt for $url");
    } else {
        last;
    }
}
if ($res->is_success) {
    $html=$res->content;
    trace("Content collected for $url");
} else {
    error("Could not collect program overview for $url");
    exit_application(1);
}

if (defined $html) {
    my $openres=open(STREAM,">$directory/$filename");
    if (not (defined $openres)) {
	error ("Could not open $directory/$filename for writing");
    } else {
	binmode(STREAM);
	print STREAM $html;
	close STREAM;
    }
}

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Nothing for the moment...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@skynet.beE<gt>
