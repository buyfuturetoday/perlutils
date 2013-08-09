=head1 NAME

get_page.pl - Get a web page

=head1 VERSION HISTORY

version 1.0 30 July 2006 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application expects an URL and will get the page contents. It can be used to obtain pages including javascripts to understand the contents. The page will be displayed on the output device.

=head1 SYNOPSIS

 get_page.pl [-t] [-l log_dir] -a URL_Address

 get_page -h	    Usage
 get_page -h 1	    Usage and description of the options
 get_page -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-a URL_Address>

The address of the page to collect.

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# variables
###########

my $uatimeout = 360;
my $proxyserver = "internetemea.eds.com";
my $trace = 0;				# 0: do not trace, 1: trace
my $log = 1;				# 0: do not log, 1: logging
my ($url, $logdir);


#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use LWP::UserAgent;
use Net::hostent;	    # to determine whether to use the Proxy server
use Log;
use OpexAccess;

#############
# subroutines
#############

sub exit_application($) {
    my($return_code) = @_;
    logging("Exit application with return code $return_code.\n");
    close_log();
    exit $return_code;
}

######
# Main
######

# Handle input values
my %options;
getopts("tl:a:h:", \%options) or pod2usage(-verbose => 0);
# The URL Address must be specified
my $arglength = scalar keys %options;  
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
# Find log file directory
if ($options{"l"}) {
    $logdir = logdir($options{"l"});
    if (not(defined $logdir)) {
		error("Could not set $logdir as Log directory, exiting...");
		exit_application(1);
    }
} else {
    $logdir = logdir();
    if (not(defined $logdir)) {
		error("Could not find default Log directory, exiting...");
		exit_application(1);
    }
}
if (-d $logdir) {
    trace("Logdir: $logdir");
} else {
    pod2usage(-msg     => "Cannot find log directory $logdir",
	      -verbose => 0);
}
# Logdir found, start logging
open_log();
logging("Start application");
# Find URL to get
if ($options{"a"}) {
    $url = $options{"a"};
} else {
    error("No URL defined, exiting...");
    exit_application(1);
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

my $proxy = gethost($proxyserver);
my $ua = LWP::UserAgent->new;
$ua->agent("DVagent");
$ua->timeout($uatimeout);
if (defined $proxy) {
    logging("using proxy");
    $ua->proxy('http', "http://". $proxyserver . ":81");
}

my $req = new HTTP::Request 'GET' => $url;
if (defined $proxy) {
    $req->proxy_authorization_basic($fwName, $fwKey);
}
logging ("Requesting $url");
# my $res = $ua->request($req);
my $res = $ua->simple_request($req);
logging("$url: ".$res->status_line);
if ($res->is_success) {
#    print $res->last_modified;
	#print $res->content;
	print $res->as_string;
} else {
    print "Page not downloaded: ".$res->status_line."\n";
}
exit_application(0);

=pod

=head1 TO DO

=over 4

=item *

Check on existence output directory, create if it does not exist

=back

=head1 AUTHOR

Any remarks or bug reports, please contact E<lt>dirk.vermeylen@skynet.beE<gt>
