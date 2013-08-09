=head1 NAME

Continuo - Collects the "Continuo" playlist for the next week and converts them into a format that Plucker likes.

=head1 VERSION HISTORY

version 1.1 7 June 2005 DV

=over 4

=item *

Added pointers to each hour ...

=back

version 1.0 6 June 2005 DV

=over 4

=item * 

Initial version based on klara.pl

=back

=head1 DESCRIPTION

This application collects the radio programs for "Continuo" for the next week. The programs per day are available on one html page, not much formatting is done.

Also the data is collected in a user-friendly way: the data will not be thrown away before starting a new collection. Thus if no internet connection was possible, all data previously collected is still available.

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.8.0, build 804 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my $outputdir="d:/temp/continuo";
my ($program,$url,$proxy,$html,$hdate,$urldate,@date,$datestring,$href,$res);
my $urlbase="http://www.klara.be/html/continuo/html/";
my $uatimeout=180;
my $proxyserver="internetemea.eds.com";
my $pluckfile = "$outputdir/continuo.html";
my $ua;
my $hour = 0;
my $indexcnt = 0;

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Log;			    # Application and error logging
use OpexAccess;
use LWP::UserAgent;
use Net::hostent;		    # to determine whether to use the Proxy server
use Date::Calc qw(Day_of_Week Day_of_Week_to_Text Month_to_Text Today Language Decode_Language Add_Delta_Days);

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
    close PLUCK;
    logging("Exit application with return code: $return_code\n");
    close_log();
    exit $return_code;
}

sub trim {
    my @out = @_;
    for (@out) {
        s/^\s+//;
        s/\s+$//;
    }
    return wantarray ? @out : $out[0];
}

=pod

=head2 Print Program

This procedures handles the output to the program file and the index file.

=cut

sub print_pgmline($$$) {
    my ($pgmline, $hour, $urltitle) = @_;
    # Make Date Subdirectory 
    my $subdir = "$outputdir/$urltitle";
    if (not(-d "$subdir")) {
	if (mkdir("$subdir",0)) {
	    logging("$subdir has been created");
	} else {
	    error("Could not create directory $subdir.");
	    exit_application(1);
	}
    }
    # Print pgmline
    my $pgmfilename = "$outputdir/$urltitle/$hour.html";
    my $openres = open(PGM, ">$pgmfilename");
    if (not(defined $openres)) {
	error ("Could not open $pgmfilename for writing, exiting ...");
	exit_application(1);
    }
    print PGM "<html><head><title>Continuo overzicht voor $hdate - $hour uur</title></head><body>\n";
    print PGM "<h1>Continuo $hdate - $hour uur</h1>\n";
    print PGM $pgmline;
    print PGM "</body></html>\n";
    close PGM;
    # Add hour index line to index file
    my $indexline = "<a href=file://$pgmfilename>$hour.00</a> * ";
    print INDEX $indexline;
    $indexcnt++;
    if ($indexcnt >= 4) {
	print INDEX "<br>\n";
	$indexcnt = 0;
    }
    return;
}

=pod

=head2 Handle Program

Collect the program and save it in the appropriate file (if it can be retrieved).

=cut

sub handle_program($) {
    my ($urltitle) = @_;
    my $startstring = "<td align=\"right\" valign=\"top\"><span class=\"vetblauw\">";
    my $compstring = "<td align=\"left\" valign=\"top\"><span class=\"vetblauw\">";
    my $titlestring = "<span class=\"schuinblauw\">";
    my $perfstring = "<span class=\"blauw\">";
    my $cdstring = "<span class=\"kleinblauw\">";
    my $termstring = "</span>";
    my $firstline = "";
    my $pgmline = "";

    # Find Start String for program item
    my $startpos = index($program, $startstring);
    if ($startpos == -1) {
	error("Program layout not available or changed, could not handle program for $urltitle");
	return;
    }
    # Start string for program item found, open index file
    my $openres=open(INDEX,">$outputdir/$urltitle");
    print INDEX "<html><head><title>Continuo overzicht voor $hdate</title></head><body>\n";
    print INDEX "<h1>Continuo $hdate</h1>\n";
    while ($startpos > -1) {
	# Find Time
	my $time_ind = substr($program,$startpos+length($startstring),5);
	# Find Componist
	my $comp_start = index($program,$compstring,$startpos+length($startstring)) + length($compstring);
	my $comp_end = index($program,$termstring,$comp_start);
	my $componist = substr($program,$comp_start,$comp_end-$comp_start);
	# Find Title
	my $title_start = index($program,$titlestring,$comp_end) + length($titlestring);
	my $title_end = index($program,$termstring,$title_start);
	my $title = substr($program,$title_start,$title_end-$title_start);
	# Find Performer(s)
	my $perf_start = index($program,$perfstring,$title_end) + length($perfstring);
	my $perf_end = index($program, $termstring, $perf_start);
	my $performer = substr($program, $perf_start, $perf_end-$perf_start);
	# Find CD Details
	my $cd_start = index($program, $cdstring, $perf_end) + length($cdstring);
	my $cd_end = index($program, $termstring, $cd_start);
	my $cd = substr($program, $cd_start, $cd_end - $cd_start);
	# Check to see if hour change
	# Hour is first two characters of the time_ind variable (for now).
	my $hr_time = substr($time_ind,0,2);
	if (not($hr_time == $hour)) {
	    # Check if $pgmline if available
	    if (length($pgmline) > 0) {
		# If so: print $pgmline and print entry in index file
		print_pgmline($pgmline, $hour, $datestring);
	    }
	    # Start new $pgmline
	    $pgmline = "<b><font color=red>$time_ind </font></b>$componist<font color=blue>$title</font>$performer<font color=blue>$cd</font><br>\n";
	    $hour = $hr_time;
	} else {
	    # Add to $pgmline
	    $pgmline = $pgmline . "<b><font color=red>$time_ind </font></b>$componist<font color=blue>$title</font>$performer<font color=blue>$cd</font><br>\n";
	}
	# Check for next entry
	$startpos = index($program,$startstring,$cd_end);
    }
    if (length($pgmline) > 0) {
	print_pgmline($pgmline, $hour, $datestring);
    }
    print INDEX "</body></html>\n";
    close INDEX;
    return;
}

=pod

=head2 Handle Day

All info for the day is in one single file. The file needs to be reformatted for Plucker output.

=cut

sub handle_day($) {
    my($urltitle)=@_;
    my $urlprogram=$urlbase.$urltitle;
    $program=collect_url($urlprogram);
    if (defined $program) {
	handle_program($urltitle);
    } else {
	error("Could not collect program on $urlprogram");
    }
}    

=pod

=head2 Collect URL

This procedure accepts an URL and tries to collect the information from the web. It expects the URL to be retrieved. Return value is the content of the page or B<UNDEFINED> in case of no return page.

The procedure knows if it is connected directly to the web, or behind the EDS firewall. In the latter case, proper proxy authentication is done. 
In case of working on the EDS intranet, the proxy may cause temporary problems. Therefore if the information could not be connected due to proxy errors, another attempt is made to collect the information, up to maximum three attempts.

=cut

sub collect_url($) {
    # Find the URL
    my($url)=@_;
    my($return_page);
    undef $return_page;		# to be sure...
    my $req=new HTTP::Request 'GET' => $url;
    if (defined $proxy) {
	$req->proxy_authorization_basic($fwName,$fwKey);
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
	$return_page=$res->content;
	print "Content collected for $url\n";
    } else {
	error("Could not collect content for $url");
    }
    return $return_page;
}

######
# Main
######

open_log();
logging("Start application");
Log::display_flag(1);

# Initialization

# Language for Date Functions
Language(Decode_Language("Nederlands"));

# Initialize date
@date=Today();

# Determine to use a proxy
$proxy=gethost($proxyserver);

# Create a User Agent
$ua = LWP::UserAgent->new;
$ua->agent("DVagent");
$ua->timeout($uatimeout);
if (defined $proxy) {
    logging("using proxy");
    $ua->proxy('http', "http://". $proxyserver . ":81");
}

# Create Continuo home page
my $openres=open(PLUCK, ">$pluckfile");
if (not $openres) {
    error("Could not open $pluckfile.");
    exit_application(1);
}
print PLUCK "<Title>Continuo</Title>\n\n";
print PLUCK "<h1>Continuo Programmaschema</h1>\n\n";

# Loop through all dates for the week starting today
for (my $cnt=0; $cnt<7; $cnt++) {
    # Initialize Date
    $hdate= Day_of_Week_to_Text(Day_of_Week(@date)).", ".$date[2]." ".
			           Month_to_Text($date[1])." ".$date[0];
    $datestring=sprintf("%02d%02d%02d",substr($date[0],2,2),$date[1],$date[2]);
    # Initialize URLs
    $urldate="$datestring.html";
    $href="$datestring.html";
    # Reset Counter
    $indexcnt = 0;
    print PLUCK "<a href=\"$href\">$hdate</a><br>\n";
    handle_day($urldate);
    @date=Add_Delta_Days(@date,1);
}


exit_application(0);

=pod

=head1 TO DO

=over 4

=item *

Nothing for now ....

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@skynet.beE<gt>
