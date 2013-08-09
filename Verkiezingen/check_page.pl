=head1 NAME

check_page.pl - Get a web page, check it is available and response time

=head1 VERSION HISTORY

version 1.0 3 October 2006 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application expects an URL and will get the page contents. It will calculate the response time and verify a string. If successful, then response time will be added to chart. If unsuccessful, then response Unicenter Event Message will be displayed.

=head1 SYNOPSIS

 check_page.pl [-t] [-l log_dir] -a URL_Address [-g Group] [-n Name] [-f chart_file] [-s CheckString]

 check_page -h	    Usage
 check_page -h 1    Usage and description of the options
 check_page -h 2    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-a URL_Address>

The address of the page to collect.

=item B<-g Group>

The Group Name of the URL to measure.

=item B<-n Name>

The Identifier name of the URL to measure.

=item B<-c Chart Title>

Title for the Chart

=item B<-f Chart file>

Full file specifications for the chart file.

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# variables
###########

my $uatimeout = 360;
#my $proxyserver = "internetemea.eds.com";
my $trace = 0;				# 0: do not trace, 1: trace
my $log = 1;				# 0: do not log, 1: logging
my ($url, $logdir, @avgresps, @msmtime);
my $group = "GPRS";
my $name = "hoofdbureau";
my $chart_file = "c:/temp/gprs_hoofdbureau.png";
my $msm_temp_file = "c:/temp/measurements_check_page.txt";
my $checkstring;
my $minvalue = -1;
my $number_of_measurements = 120;


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
use GD::Graph::lines;

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

=head2 Read Measurements

This procedure will read measurement file. First line is timestamp of measurement. Second line is measurement. Each value is separated by semicolon.

=cut

sub read_measurements() {
    if (-r $msm_temp_file) {
	my $openres = open(Msm, $msm_temp_file);
	if (not(defined $openres)) {
	    error("Could not open Measurement file $msm_temp_file for reading, exiting...");
	    exit_application(1);
	}
	# First line is time stamps
	my $line = <Msm>;
	chomp $line;
	@msmtime = split /;/,$line;
	# Second line is measurements
	$line = <Msm>;
	chomp $line;
	@avgresps = split /;/,$line;
	close Msm;
	my $msmtime_length = @msmtime;
	my $avgresps_length = @avgresps;
	while ($msmtime_length > $number_of_measurements) {
	    shift @msmtime;
	    $msmtime_length = @msmtime;
	}
	while ($avgresps_length > $number_of_measurements) {
	    shift @avgresps;
	    $avgresps_length = @avgresps;
	}
	# More measurements then timestamps, should never happen
	while ($avgresps_length > $msmtime_length) {
	    error("$avgresps_length avg responses, $msmtime_length time stamps...");
	    shift @avgresps;
	    $avgresps_length = @avgresps;
	}
	# More time stamps then measurements, should never happen
	while ($msmtime_length > $avgresps_length) {
	    error("$msmtime_length time stamps, $avgresps_length avg responses...");
	    shift @msmtime;
	    $msmtime_length = @msmtime;
	}
    }
}

=pod

=head2 Save Measurements

This procedure will print all time stamps and measurements to the temporary file.

=cut

sub save_measurements() {
    my $openres = open(Msm, ">$msm_temp_file");
    if (not defined $openres) {
	error("Could not open measurement file $msm_temp_file for writing, exiting...");
	exit_application(1);
    }
    print Msm join(";",@msmtime), "\n";
    print Msm join(";",@avgresps), "\n";
    close Msm;
}

=pod

=head2 Create Chart

Create Chart using GD modules.

=cut

sub create_chart() {
    my $xlength = @msmtime;
    my $ylength = @avgresps;
    if (not ($xlength == $ylength)) {
	error ("X-array and Y-array not same length, cannot make graph.");
    } else {
	my @data = (\@msmtime,\@avgresps);
	my $mygraph = GD::Graph::lines->new(600, 400);
	my $fromtime = $msmtime[0];
	my $totime = $msmtime[$xlength-1];
	my $graphsetres = $mygraph->set(
				x_label     => 'Measurement (Note: negative Response Time values indicate error or timeout in response)',
				y_label     => 'Response Time (ms)',
				title       => "Response $group for $name from $fromtime to $totime",
				x_label_skip => 8,
				x_all_ticks => 1,
				x_tick_offset => 3,
				zero_axis_only => 1);
	if (not defined $graphsetres) {
	    error("Could not set Graph for Device $group instance $name");
	} else {
	    my $myimage = $mygraph->plot(\@data) or die $mygraph->error;
	    # Open Output file
	    # my $outfile = $outdir."/$group"."_$name.png";
	    my $openres = open(OutFile, ">$chart_file");
	    if (not defined $openres) {
		error("Cannot open $chart_file for writing, exiting...");
	    } else {
		binmode OutFile;
		print OutFile $myimage->png;
		close OutFile;
	    }
	}
    }
}


######
# Main
######

# Handle input values
my %options;
getopts("tl:a:h:f:s:g:n:", \%options) or pod2usage(-verbose => 0);
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
# Find Group Name
if ($options{"g"}) {
    $group = $options{"g"};
}
# Find Identifier Name
if ($options{"n"}) {
    $name = $options{"n"};
}
# Find Chart Output Directory
if ($options{"f"}) {
    $chart_file = $options{"f"};
}
# Find CheckString
if ($options{"s"}) {
    $checkstring = $options{"s"};
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

read_measurements();
#my $proxy = gethost($proxyserver);
my $ua = LWP::UserAgent->new;
$ua->agent("DVagent");
$ua->timeout($uatimeout);
#if (defined $proxy) {
#    logging("using proxy");
#    $ua->proxy('http', "http://". $proxyserver . ":81");
#}
my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my $meas_time = sprintf "%02d:%02d", $hour,$min;
push @msmtime, $meas_time;
my $req = new HTTP::Request 'GET' => $url;
#if (defined $proxy) {
#    $req->proxy_authorization_basic("dz09s6", "krdjue07");
#}
logging ("Requesting $url");
my $timestart = time;
my $res = $ua->request($req);
my $timeend = time;
my $resp_time = $timeend - $timestart;
logging("$url: ".$res->status_line.", Resp time: $resp_time");
if ($res->is_success) {
    if (defined $checkstring) {
	if (index($res->content,$checkstring) > -1) {
	    # File found, checkstring found, all OK
	    push @avgresps, $resp_time;
	} else {
	    # Page found but checkstring not found
	    error("Page $url found, content $checkstring not found");
	    push @avgresps, $minvalue;
	}
    } else {
	# No checkstring, success!
        push @avgresps, $resp_time;
	print $res->content;
    }
} else {
    # Page not found
    error("Page $url not found ".$res->status_line);
    push @avgresps, $minvalue;
}

create_chart();
save_measurements();

exit_application(0);

=pod

=head1 TO DO

=over 4

=item *

Download only once per day: verify the date for the output file.

=item *

Check on existence output directory, create if it does not exist

=item *

Read proxy, username and password from file

=back

=head1 AUTHOR

Any remarks or bug reports, please contact E<lt>dirk.vermeylen@skynet.beE<gt>
