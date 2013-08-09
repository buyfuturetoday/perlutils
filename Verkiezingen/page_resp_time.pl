=head1 NAME

page_resp_time.pl - Get the age of a web page to verify frequent update.

=head1 VERSION HISTORY

version 1.0 29 September 2006 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will get a web page and verify the Response time of the page. The URL list must be available in an ini file.

All Response times are written to a file in a page;responsetime structure.

This application will not forward events in case of failure or for any other reason.

=head1 SYNOPSIS

 page_resp_time.pl [-t] [-l log_dir] -f URL_list

 page_resp_time.pl -h	  Usage
 page_resp_time.pl -h 1   Usage and description of the options
 page_resp_time.pl -h 2   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-f URL_list>

The URL List is the list of all (fully qualified) URL names for which response times need to be calculated. This file will be overwritten with the URL;measured response times pairs.

The initial file can have URL;measured response time pairs, but these response times will not be kept.

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# variables
###########

my $uatimeout = 60;
my $trace = 0;				# 0: do not trace, 1: trace
my $log = 1;				# 0: do not log, 1: logging
my ($url_file, $logdir, %urls, $ua);
my $cnt = 0;

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
use Time::HiRes qw(gettimeofday tv_interval);

#############
# subroutines
#############

sub exit_application($) {
    my($return_code) = @_;
    logging("Exit application with return code $return_code.\n");
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

=head2 Read ini file Procedure

This procedure will read all lines in the file. All key/value pairs will be stored in a hash. Duplicate keys in a section are allowed but not recommended, since only the last value will remain.

=cut

sub read_ini_file() {
    my $openres = open(Urls, $url_file);
    if (not defined $openres) {
	error("Cannot open URL_Last_Modified file $url_file for reading, exiting...");
	exit_application(1);
    }
    while (my $line = <Urls>) {
	chomp $line;
	# Ignore any line that does not start with character
	if ($line =~ /^[A-Za-z]/) {
	    $line = trim($line);	# Make sure no more trailing blanks
	    my ($url, undef) = split (/;/, $line);
	    $url = trim($url);
	    $urls{$url} = -1;
	}
    }
    close Urls;
}

=pod

=head2 Write Current Status

This procedure will keep track of the current status: url and last modified pairs in alphabetical order.

=cut

sub write_curr_stat() {
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my $datetime=sprintf("%04d%02d%02d%02d%02d%02d", $year+1900, $mon+1, $mday, $hour,$min,$sec);
   my $openres =  open(Status, ">$url_file"."_$datetime");
   if (defined $openres) {
	foreach my $key (sort keys %urls) {
	    print Status "$key;$urls{$key}\n";
	}
	close Status;
    } else {
	error("Could not open $url_file for writing");
    }
}


=pod

=head2 Verify URLs

For each URL the time required to extract the page will be measured. If the page could not be retrieved, then the response time will be set to -1. The reason for the failure will be written to the log file.

=cut

sub verify_urls($) {
    my ($url) = @_;
    my $req = new HTTP::Request 'GET' => $url;
    my $timestart = [gettimeofday];
    my $res = $ua->request($req);
    my $timeend = [gettimeofday];
    my $resp_time = tv_interval $timestart, $timeend;
#    logging("$url: ".$res->status_line);
    if ($res->is_success) {
	$urls{$url} = $resp_time;
    } else {
	my $status = $res->status_line;
	error("Page ***$url*** not available, reason: $status");
    }
}

######
# Main
######

# Handle input values
my %options;getopts("tl:f:h:", \%options) or pod2usage(-verbose => 0);
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
# Find url_last_modified file
if ($options{"f"}) {
    $url_file = $options{"f"};
    if (not (-r $url_file)) {
	error("URL_List file $url_file not readable, exiting...");
	exit_application(1);
    }
} else {
    error("URL_List file is not defined, exiting...");
    exit_application(1);
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Initialize Agent
$ua = LWP::UserAgent->new;
$ua->agent("DVagent");
#$ua->max_redirect(0);
$ua->timeout($uatimeout);

# Read URL file and last_modified times
read_ini_file();


my $scriptstart = [gettimeofday];
# Handle all URLs
while (my ($url, undef) = each %urls) {
    verify_urls($url);
    $cnt++;
}
my $scriptend = [gettimeofday];
my $script_time = tv_interval $scriptstart, $scriptend;
my $msg = "Verifying $cnt URLs in $script_time seconds";
logging($msg);
print "Verifying $cnt URLs in $script_time seconds\n";

write_curr_stat();

exit_application(0);

=pod

=head1 TO DO

=over 4

=item *

Nothing for now....

=back

=head1 AUTHOR

Any remarks or bug reports, please contact E<lt>dirk.vermeylen@skynet.beE<gt>
