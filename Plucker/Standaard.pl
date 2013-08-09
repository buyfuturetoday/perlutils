=head1 NAME

Standaard.pl - Collects the daily opinion from the Standaard web site.

=head1 DESCRIPTION

The "Commentaar" section is available on http://wwww.standaard.be/Meningen. The page is collected and the Commentaar section is extracted.

=head1 VERSION HISTORY

version 1.3 - 10 April 2007 DV

=over 4

=item *

Rework to collect data as it is and convert utf to latin1 as good as possible.

=back

version 1.2 - 24 March 2007 DV

=over 4

=item *

Replaced "$commentaar=$res->content;" with "$commentaar=$res->decoded_content(default_charset => "utf8");" to guarantee nice display of special characters.

=item *

Added Image processing.

=item *

Added collect_url procedure.

=back

version 1.1 - Rework, after new website from De Standaard 21 March 2007 DV

version 1.0 - Initial Release 8 November 2003 DV

=head1 SYNOPSIS

 standaard.pl

=head1 OPTIONS

Currently no options are defined

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# variables
###########

my $uatimeout=180;
my $storydir="d:/temp/news/";		# Opinie Location
my $imagesdir = "images/";
my $homepage = "http://www.standaard.be/";
my $commentaar_url="Meningen/";
my $commentaarfile="d:/temp/news/story1.html";
my ($proxy, $ua, $res);

#####
# use
#####

use warnings;
use strict 'vars';
use strict 'refs';
use strict 'subs';
use LWP::UserAgent;
use Net::hostent;	    # to determine whether to use the Proxy server
# use HTML::TreeBuilder;	    # to parse the html page
use Log;
use OpexAccess;
use dirkode;

#############
# subroutines
#############

sub exit_application($) {
    my($return_code) = @_;
    close COMMENTAAR;
    logging("Exit application with return code $return_code.\n");
    close_log();
 	exit $return_code;
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
		$req->proxy_authorization_basic($fwName, $fwKey);
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
		#$return_page=$res->decoded_content(default_charset => "utf8");
		#$return_page=$res->decoded_content();
		$return_page=$res->content();
		if (not defined $return_page) {
			error("Could not decode page...");
			$return_page = "Decoding issue";
		} else {
			print "Content collected for $url\n";
		}
    } else {
		error("Could not collect content for $url");
    }
    return $return_page;
}

=pod

=head2 Remove href

This procedure will remove <a href...> values that appear with the images.

=cut

sub remove_href($) {
	my ($commentaar) = @_;
	my $searchstring = "<a href=";
	while (index($commentaar, $searchstring) > -1) {
		my $searchpos = index($commentaar, $searchstring);
		my $leftstring = substr($commentaar,0,$searchpos);
		my $rightpos = index ($commentaar, ">", $searchpos);
		my $rightstring = substr($commentaar,$rightpos + 1);
		$commentaar = $leftstring . $rightstring;
		# Normally there should be a </a> as well
		my $delimstr = "</a>";
		$searchpos = index($commentaar, $delimstr, $searchpos);
		if ($searchpos > -1) {
			my $leftstring = substr($commentaar,0,$searchpos);
			my $rightstring = substr($commentaar,$searchpos + length($searchstring)+1);
			$commentaar = $leftstring . $rightstring;
		}
	}
	return $commentaar;
}

=pod

=head2 Collect URL

This procedure checks if the picture is available off-line. If not, the picture is downloaded. The URL is converted to point to the local copy of the picture.

=cut

sub collect_picture($) {
	my ($picture_url) = @_;
	# Need to find the last occurence of /
	my $startpos = rindex($picture_url,"/");
	my $locpic_url = substr($picture_url,$startpos+1);
	my $locpic_file = $storydir.$imagesdir."/".$locpic_url;
	if (not (-r $locpic_file)) {
		$picture_url = $homepage.$picture_url;
		my $picture = collect_url($picture_url);
		if (defined $picture) {
			my $openres = open (PICT, ">$locpic_file");
			if (not(defined $openres)) {
				error("Could not open $locpic_file for writing.");
			} else {
				binmode(PICT);
				print PICT $picture;
				close PICT;
			}
		}
	}
	return "<img src=\"$imagesdir"."$locpic_url\">";
}

=pod

=head2 Find Picture URL

This procedure will extract the src information from the img string. (Note that TreeBuilder may be a more elegant way of obtaining this information.)

=cut

sub find_picture($) {
	my ($picture_url) = @_;
	my $startstr = "src=\"";
	my $endstr = ".jpg";
	my $startpos = index($picture_url,$startstr);
	if ($startpos == -1) {
		# src not found, return empty picture url
		$picture_url = "";
	} else {
		$startpos = $startpos + length($startstr);
		my $endpos = index($picture_url,$endstr);
		if ($endpos == -1) {
			error("Couldn't find $endstr in $picture_url.");
			$picture_url = "";
		} else {
			$endpos = $endpos + length($endstr);
			my $rem_pic = substr($picture_url,$startpos,$endpos-$startpos);
			$picture_url = collect_picture($rem_pic);
		}
	}
	return $picture_url;
}

=pod

=head2 Investigate Picture

This procedure will check the page for pictures (img tagname). If there is a picture, the collect picture procedure will be called to download it (if required) and the source will be updated to make it available for Plucker.

=cut

sub investigate_picture {
    my ($page)=@_;
    my $image_end=0;
    my $image_delim="<img";
	# the alt string is kb<br> for whatever reason,
	# the url is terminated by />.
	my $end_delim = "/>";
    my $image_start=index($page,$image_delim,$image_end);
    while ($image_start > -1) {
		# the alt string is kb<br> for whatever reason,
		# the url is terminated by />.
		$image_end = index($page,$end_delim,$image_start) + length($end_delim);
		my $leftstring = substr($page,0,$image_start);
		my $rightstring = substr($page,$image_end+1);
		my $picture_url = substr($page,$image_start,$image_end - $image_start);
		$picture_url = find_picture($picture_url);
		$page = $leftstring . $picture_url . $rightstring;
		$image_start=index($page,$image_delim,length($leftstring . $picture_url));
    }
    return $page;
}

=pod

=head2 Handle Commentaar

Commentaar is extracted from the page, depending on the current start and end string.

=cut

sub handle_commentaar($) {
	my ($commentaar) = @_;
	# Find Start
	my $searchstring = "Commentaar</a></h3>";
	my $searchpos = index($commentaar,$searchstring);
	if ($searchpos == -1) {
		error("Couldn't find Commentaar Start String $searchstring");
	} else {
		$commentaar = substr($commentaar, $searchpos + length($searchstring));
		# Find End string
		$searchstring = "</div>";
		$searchpos = index($commentaar,$searchstring);
		if ($searchpos > -1) {
			$commentaar = substr($commentaar, 0,$searchpos);
			$commentaar = remove_href($commentaar);
			$commentaar = investigate_picture($commentaar);
		}
		$commentaar = tx2latin($commentaar);
		print COMMENTAAR "<html>\n";
		print COMMENTAAR "<head>\n";
#		print COMMENTAAR "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\" />\n";
		print COMMENTAAR "</head>\n";
		print COMMENTAAR "<body>\n";
		print COMMENTAAR $commentaar;
		print COMMENTAAR "</body>\n"; 
		print COMMENTAAR "</html>";
	}
}
		

######
# Main
######

open_log();
logging("Start application");
Log::display_flag(1);
$proxy=gethost($proxyserver);
$ua=LWP::UserAgent->new;
$ua->agent("DVagent");
$ua->timeout($uatimeout);
if (defined $proxy) {
    logging("using proxy");
    $ua->proxy('http', "http://". $proxyserver . ":$proxyport");
}

my $commentaar=collect_url($homepage.$commentaar_url);

if (defined $commentaar) {
	my $openres=open(COMMENTAAR, ">$commentaarfile");
	if (not $openres) {
    	error("Could not open $commentaarfile for writing!");
    	exit_application(1);
	}
	handle_commentaar($commentaar);
	exit_application(0);
} else {
	error("Could not collect Commentaar page, exiting...");
	exit_application(1);
}

=pod

=head1 TO DO

=over 4

=item *

Check on existence output directory, create if it does not exist

=item *

Read proxy, username and password from file

=item *

Accept options for tracing, log file location, output file location, ...

=back

=head1 AUTHOR

Any remarks or bug reports, please contact E<lt>dirk.vermeylen@skynet.beE<gt>
