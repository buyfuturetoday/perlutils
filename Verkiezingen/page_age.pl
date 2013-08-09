=head1 NAME

page_age.pl - Get the age of a web page to verify frequent update.

=head1 VERSION HISTORY

version 1.0 29 September 2006 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will get a web page and verify the last modified time of the page. This can be used to verify websites that need regular updates. The URL list must be available in an ini file.

The last modified time of the URL must be more recent then the previous read last modified time. No local processing of the last modified time is done, since there is no control on the time synchronisation of the remote system.

=head1 SYNOPSIS

 page_age.pl [-t] [-l log_dir] -f URL_last_modified_time [-m event-manager] [-s scriptID]

 page_age.pl -h	    Usage
 page_age.pl -h 1   Usage and description of the options
 page_age.pl -h 2   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-f URL_last_modified_time>

The URL_last_modified_time has URL, last_modified_time pairs. If an URL needs to be added to the list, then the URL can be added to the file. The application will recognize the new URL and will not trigger an initial alarm. URLs that no longer need to be verified can be removed from the URL_last_modified_time file.

Note that the application will rewrite the file on each run, so no comments should be added to the file. Also URLs should be added / removed only when the application is not running.

=item B<-s scriptID>

Script Identifier name that will show up on the event console.

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# variables
###########

my $uatimeout = 60;
my $proxyserver = "internetemea.eds.com";
my $trace = 0;				# 0: do not trace, 1: trace
my $log = 1;				# 0: do not log, 1: logging
my ($url_file, $eventmgr, $logdir, %urls, %new_urls, $proxy, $ua, $host, $scriptID);


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
# use OpexAccess;

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
	    my ($url, $last_modified) = split (/=/, $line);
	    $url = lc(trim($url));
	    if (defined $last_modified) {
		$last_modified = trim($last_modified);
		if ($last_modified =~ /^[+-]?\d+$/) {
		    $urls{$url} = $last_modified;
		} else {
		    $urls{$url} = -1;
		}
	    } else {
		$urls{$url} = -1;
	    }
	}
    }
    close Urls;
}

=pod

=head2 Write Current Status

This procedure will keep track of the current status: url and last modified pairs in alphabetical order.

=cut

sub write_curr_stat() {
   my $openres =  open(Status, ">$url_file");
   if (defined $openres) {
	foreach my $key (sort keys %new_urls) {
	    print Status "$key=$new_urls{$key}\n";
	}
	close Status;
    } else {
	error("Could not open $url_file for writing");
    }
}


=pod

=head2 Verify URLs

For each URL the procedure will get the page and read the last_modified time. If the last modified time is available and bigger then the previous last modified time, then only a log message will be written. In other cases an error will be send to the Unicenter event console.

=cut

sub verify_urls($$) {
    my ($url, $last_modified) = @_;
    # Initialize to false value
    $new_urls{$url} = -1;
    my $req = new HTTP::Request 'GET' => $url;
    if (defined $proxy) {
#	$req->proxy_authorization_basic($fwName, $fwKey);
    }
    my $res = $ua->request($req);
    logging("$url: ".$res->status_line);
    if ($res->is_success) {
	my $new_last_modified = $res->last_modified;
	$new_urls{$url} = $new_last_modified;
	if ($new_last_modified > $last_modified) {
	    logging("$url: $new_last_modified");
	} else {
	    my $msg = "STATE_CRITICAL | $scriptID rsync $url notUpdated Page not updated";
	    my $cmd = "logforward -n$eventmgr -f$host -vE -t\"$msg\"";
	    execute_command($cmd);
	    error("Page $url not updated ($new_last_modified)");
	}
    } else {
	my $status = $res->status_line;
	my $msg = "STATE_CRITICAL | $scriptID rsync $url notAvailable Could not get page $status";
	    my $cmd = "logforward -n$eventmgr -f$host -vE -t\"$msg\"";
	execute_command($cmd);
	error("Page $url not available, reason: $status");
    }
}

######
# Main
######

# Handle input values
my %options;getopts("tl:f:m:s:h:", \%options) or pod2usage(-verbose => 0);
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
	error("URL_Last_Modified file $url_file not readable, exiting...");
	exit_application(1);
    }
} else {
    error("URL_Last_Modified file is not defined, exiting...");
    exit_application(1);
}
if ($options{"m"}) {
    $eventmgr = $options{"m"};
} else {
    $eventmgr = $ENV{COMPUTERNAME};
}
# Find Script Identifier
if ($options{"s"}) {
    $scriptID = $options{"s"};
} else {
    $scriptID = "rsyncPage";
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Initialize originating host
$host = $ENV{COMPUTERNAME};

# Initialize Agent
# $proxy = gethost($proxyserver);
undef $proxy;
$ua = LWP::UserAgent->new;
$ua->agent("DVagent");
$ua->max_redirect(0);
$ua->timeout($uatimeout);
if (defined $proxy) {
    logging("using proxy");
    $ua->proxy('http', "http://". $proxyserver . ":81");
}

# Read URL file and last_modified times
read_ini_file();

# Handle all URLs
while (my ($url, $last_modified) = each %urls) {
    verify_urls($url, $last_modified);
}

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
