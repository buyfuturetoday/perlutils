=head1 NAME

Controles - Collects the information from the Verkeersinformatie and converts them into a format that Plucker likes.

=head1 VERSION HISTORY

version 1.1 25 May 2003 DV

=over 4

=item *

Add verification check on date, see if the date is valid.

=back

version 1.0 18 April 2003 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application collects the information regarding the Verkeerscontroles from the Federale Politie.

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.8.0, build 804 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my $outputdir="c:/temp/fedpol";
my $title="";
my ($program,$url,$proxy,$html,$hdate,$urldate,@date,$datestring,$href,$res);
my $url="http://www.fedpol.be/fedpol/verkeer/radar.htm";
# my $url="http://www.fedpol.be/fedpolNew/Nederlands/verkeer/controles.htm";
my $uatimeout=180;
my $proxyserver="internetabh.eds.com";
my $pluckfile = "$outputdir/dagen.html";
my $ua;
my $imagestring = '<img src="../../impol/roodpijl.gif" width="7" height="5">';


#####
# use
#####

#use warnings;			    # show warning messages
#use strict 'vars';
#use strict 'refs';
#use strict 'subs';
use Log;			    # Application and error logging
use LWP::UserAgent;
use Net::hostent;		    # to determine whether to use the Proxy server
use Date::Calc qw(Day_of_Week Day_of_Week_to_Text Decode_Month Language Decode_Language check_date);

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

=head2 Create Controles home page

If information could be retrieved successfully from Internet, then try to create the home page on the local machine.

=cut

sub controles_home_page {
    my $openres=open(PLUCK, ">$pluckfile");
    if (not $openres) {
	error("Could not open $pluckfile.");
	exit_application(1);
    }
    print PLUCK "<Title>Federale Politie</Title>\n\n";
    print PLUCK "<h1>Geplande Controles</h1>\n\n";
}

=pod

=head2 Find day of Week

Convert the date to be able to add the day of week to the overview. Verification if the day and year are numeric, the month is converted using a special Date::Calc function.

=cut

sub find_day_of_week {
    $dagvdweek = "";
    my ($dag,$maand,$jaar) = split (/ /, $prev_date);
    # Check for valid date
    # Dag numeric
    if (not($dag =~ /^\d+$/)) {
	error("Date $prev_date invalid dag $dag, exiting...");
	exit_application(1);
    }
    my $maand_nr = Decode_Month($maand);
    # Maand_nr 1 .. 12, 0 in case of error
    if ($maand_nr == 0) {
	error("Date $prev_date invalid maand, exiting...");
	exit_application(1);
    }
    # If Year not defined, assume this year...
    if (length($jaar) ==0) {
	(undef,undef,undef,undef,undef,$jaar,undef,undef,undef) = localtime(time);
	$jaar = $jaar + 1900;
    } elsif (not($jaar =~ /^\d+$/)) {		# Year numeric
	error("Date $prev_date invalid year $jaar, exiting...");
	exit_application(1);
    }
    # Check date
    if (check_date($jaar, $maand_nr, $dag)) {
	my $dow = Day_of_Week($jaar,$maand_nr,$dag);
	$dagvdweek = Day_of_Week_to_Text($dow);
	$dagvdweek = $dagvdweek . " ";
    } else {
	error("Date $prev_date invalid, ($dag-$maand_nr-$jaar) exiting...");
	exit_application(1);
    }
}

=pod

=head2 Print Info

The prev_date field is investigated to find the Day of the Week. 

The rest of the information is then printed to a file.

=cut

sub print_info {
    find_day_of_week;
    print PLUCK "<a href=\"$prev_date.html\">$dagvdweek$prev_date</a><br>\n";
    open (CONTROLE,">$outputdir/$prev_date.html");
    print CONTROLE "<title>Geplande controles voor $dagvdweek$prev_date</title>\n";
    print CONTROLE "<h2>$dagvdweek$prev_date</h2>\n";
    $length_array = @locations;
    for (my $cnt=0;$cnt<$length_array;$cnt++) {
        print CONTROLE "<b>$locations[$cnt]</b><br>\n";
	print CONTROLE "<font color=blue>$snelheid[$cnt]</font><br>\n";
	if ($alcohol[$cnt] ne "Niet aangekondigd") {
	    print CONTROLE "<font color=red>Alcohol: $alcohol[$cnt]</font><br>\n";
	}
    }
    close CONTROLE;
}
=pod

=head2 Extract Dates

The dates seem to be hidden after the string with a specific color <font color="#F2EBB9">. Dates are always duplicated: first for Flanders, then for Wallonie.

The dates for Flanders also contain the tag name <a name=...></a> that needs to be removed before extracting the date.

=cut

sub extract_dates {
    my $searchstring = "<font color=\"#F2EBB9\">";
    my $endstring = "</font>";
    my $endpos = 0;
    my $tag_id = "<a name";
    my $tag_end = "</a>";
    $startpos = index($html,$searchstring,$endpos);
    undef $prev_date;
    while ($startpos > -1) {
	$startpos = $startpos + length($searchstring);
	$endpos = index($html,$endstring,$startpos);
	if ($endpos == -1) {
	    error("$endpos string not found after position $startpos, exiting...");
	    exit_application(1);
	}
	# Look if there is a name tag that should be removed.
	# The name tag comes where the date is expected.
	if (substr($html,$startpos,length($tag_id)) eq $tag_id) {
	    $startpos = index($html,$tag_end,$startpos) + length($tag_end);
	}
	$date = substr($html,$startpos,$endpos-$startpos);
	# Date comes with record separator and a lot of spaces
	my ($day,$rest) = split (/$\//,$date);
	$day = trim $day;
	$rest = trim $rest;
	$date = "$day $rest";
	if ($date ne $prev_date) {
	    if (defined $prev_date) {
		print_info;
	    }
	    $prev_date = $date;
	    @locations = ();
	    @snelheid = ();
	    @alcohol = ();
	}
	locations_for_day($endpos);
	$startpos = index($html,$searchstring,$endpos);
    }
    print_info;
}

=pod

=head2 Locations for Day

The next table row contains the places. A table row is all information between the <tr> and </tr> delimiters.

=cut

sub locations_for_day($) {
    my ($endpos) = @_;
    # Next row after the date - start looking as of previous endpos
    my $rowstart = index($html,"<tr",$endpos);
    my $rowend   = index($html,"</tr>",$rowstart);
    my $rowinfo  = substr($html,$rowstart,$rowend-$rowstart);
    my $fieldstart = "<font color=\"#990033\">";
    my $fieldend   = "</font>";
    my $fieldendpos = 0;
    my $fieldstartpos = index($rowinfo,$fieldstart,$fieldendpos);
    while ($fieldstartpos > -1) {
	$fieldstartpos = $fieldstartpos + length($fieldstart);
	$fieldendpos = index($rowinfo,$fieldend,$fieldstartpos);
	$location = substr($rowinfo,$fieldstartpos,$fieldendpos-$fieldstartpos);
	push @locations,"$location";
	$fieldstartpos = index($rowinfo,$fieldstart,$fieldendpos);
    }
    snelheid_for_day($rowend);
}

=pod

=head2 Snelheid for Day

The next table row contains the snelheidscontroles. A table row is all information between the <tr> and </tr> delimiters.

=cut

sub snelheid_for_day($) {
    my ($endpos) = @_;
    # Next row after the date - start looking as of previous endpos
    my $rowstart = index($html,"<tr",$endpos);
    my $rowend   = index($html,"</tr>",$rowstart);
    my $rowinfo  = substr($html,$rowstart,$rowend-$rowstart);
    my $fieldstart = "<div align=\"left\">";
    my $fieldend   = "</div>";
    my $fieldendpos = 0;
    my $fieldstartpos = index($rowinfo,$fieldstart,$fieldendpos);
    # First entry is row header "Snelheid", so look for next.
    $fieldendpos = index($rowinfo,$fieldend,$fieldstartpos);
    $fieldstartpos = index($rowinfo,$fieldstart,$fieldendpos);
    while ($fieldstartpos > -1) {
	$fieldstartpos = $fieldstartpos + length($fieldstart);
	$fieldendpos = index($rowinfo,$fieldend,$fieldstartpos);
	$snelheid_controle = substr($rowinfo,$fieldstartpos,$fieldendpos-$fieldstartpos);
	# There are a couple of "Rode pijlen" used on the web site that should be removed
	$img = index($snelheid_controle,$imagestring);
	while ($img > -1) {
	    substr($snelheid_controle,$img,length($imagestring),"");
	    $img = index($snelheid_controle,$imagestring);
	}
	push @snelheid,"$snelheid_controle";
	$fieldstartpos = index($rowinfo,$fieldstart,$fieldendpos);
    }
    alcohol_for_day($rowend);
}

=pod

=head2 Alcoholcontrole for Day

The next table row contains the alcoholcontroles. A table row is all information between the <tr> and </tr> delimiters.

=cut

sub alcohol_for_day($) {
    my ($endpos) = @_;
    # Next row after the date - start looking as of previous endpos
    my $rowstart = index($html,"<tr",$endpos);
    my $rowend   = index($html,"</tr>",$rowstart);
    my $rowinfo  = substr($html,$rowstart,$rowend-$rowstart);
    my $fieldstart = "<div align=\"left\">";
    my $fieldend   = "</div>";
    my $fieldendpos = 0;
    my $fieldstartpos = index($rowinfo,$fieldstart,$fieldendpos);
    # First entry is row header "Alcohol", so look for next.
    $fieldendpos = index($rowinfo,$fieldend,$fieldstartpos);
    $fieldstartpos = index($rowinfo,$fieldstart,$fieldendpos);
    while ($fieldstartpos > -1) {
	$fieldstartpos = $fieldstartpos + length($fieldstart);
	$fieldendpos = index($rowinfo,$fieldend,$fieldstartpos);
	$alcohol_controle = substr($rowinfo,$fieldstartpos,$fieldendpos-$fieldstartpos);
	$alcohol_controle = trim $alcohol_controle;
	# There are a couple of "Rode pijlen" used on the web site that should be removed
	my $img = index($alcohol_controle,$imagestring);
	while ($img > -1) {
	    substr($alcohol_controle,$img,length($imagestring),"");
	    $img = index($snelheid_controle,$imagestring);
	}
	if ((length($alcohol_controle) == 0) or 
	    ($alcohol_controle eq "&nbsp;")  or 
	    ($alcohol_controle eq "/")) {
	    $alcohol_controle = "Niet aangekondigd";
	}
	push @alcohol,"$alcohol_controle";
	$fieldstartpos = index($rowinfo,$fieldstart,$fieldendpos);
    }
}

######
# Main
######

open_log();
logging("Start application");
Log::display_flag(1);
Log::trace_flag(1);

# Initialization

# Language for Date Functions
Language(Decode_Language("Nederlands"));

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

# Collect the information on the site of the Federale Politie
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
    trace($res->as_string);
} else {
    error("Could not collect information, exiting ...");
    exit_application(1);
}

controles_home_page;
extract_dates;

exit_application(0);

=pod

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@skynet.beE<gt>
