=head1 NAME

gva.pl - Collects the daily opinion from the Gazet van Antwerpen web site.

=head1 DESCRIPTION

The Opinion Page and the Regional Opinion page is available for a number of days. All available pages will be collected, downloaded if required or refered to otherwise.

The Opinion Page and the Regional Opinion Page will both be downloaded, using a switch to define which Page to download.

=head1 VERSION HISTORY

version 1.2 - 10 April 2007 DV

=over 4

=item *

Added conversion from UTF to Latin1, to cope with Palm Plucker.

=back

version 1.1 - 25 March 2007 DV

=over 4

=item *

Update to cover for new layout at GVA Website.

=back


version 0.1 - Initial Release 19 September 2002 DV

=head1 SYNOPSIS

gva.pl [-t] [-l log_dir] [-r]

    gva.pl -h	  Usage
    gva.pl -h 1   Usage and description of the options
    gva.pl -h 2   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: c:\temp. Logging is enabled by default. 

=item B<-r>

If specified, then the regional information will be collected. Otherwise it is the standpunten for the country.

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# variables
###########

my $uatimeout = 180;
my $indexfile = "Commentaar_index.html";
my ($proxy, $ua, $res, %urls, $storydir, $homepage, $logdir);


#####
# use
#####

use warnings;
use strict 'vars';
use strict 'refs';
use strict 'subs';
use LWP::UserAgent;
use Net::hostent;	    # to determine whether to use the Proxy server
use Log;
use OpexAccess;
use Getopt::Std;
use Pod::Usage;
use dirkode;

#############
# subroutines
#############

sub exit_application($) {
    my($return_code) = @_;
	close Comm_Index;
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
			error("Could not decode page for $url");
		} else {
			print "Content collected for $url\n";
		}
    } else {
		error("Could not collect content for $url");
    }
    return $return_page;
}

=pod

=head2 Format Comment Page

This procedure will format the Comment page to strip off all unnecessary information.
The title is available after between <h3 class="entry-header"> and </h3>. The text is available between <div class="entry-body"> and <!-- technorati tags -->.

=cut

sub format_comment($) {
	my ($comment_page) = @_;
#	my ($title);
#	my $title_startstr = "<h3 class=\"entry-header\">";
#	my $title_startpos = index($comment_page,$title_startstr);
#	if ($title_startpos == -1) {
#		$title = "Geen titel gevonden";
#	} else {
#		$title_startpos = $title_startpos + length($title_startstr);
#		my $title_endstr = "</h3>";
#		my $title_endpos = index($comment_page,$title_endstr,$title_startpos);
#		$title = substr($comment_page, $title_startpos, $title_endpos-$title_startpos);
#		$comment_page = substr($comment_page,$title_endpos);
#	}
	my $comm_startstr = "<div class=\"entry-body\">";
	my $comm_startpos = index($comment_page, $comm_startstr);
	if ($comm_startpos == -1) {
		error("Unrecognized format of Commentaar page");
	} else {
		$comment_page = substr($comment_page, $comm_startpos + length($comm_startstr));
		my $comm_endstr = "<!-- technorati tags -->";
		my $comm_endpos = index($comment_page,$comm_endstr);
		if ($comm_endpos == -1) {
			error("Could not find Comment end string $comm_endstr");
		} else {
			$comment_page = substr($comment_page,0, $comm_endpos);
		}
	}
	return $comment_page;
}

=pod

=head2 Handle Commentaar URL

This procedure will check if the Commentaar has been downloaded for this URL. If not, then the page will be downloaded. Then another check will be done to see if the Commentaar page exists locally. If so, the Commentaar URL will be added to the Commentaar Index page.

=cut

sub handle_commentaar_url($$) {
	my ($commentaar_url, $title) = @_;
	my $comment_ref = substr($commentaar_url, rindex($commentaar_url,"/")+1);
	my $comment_file = "$storydir/$comment_ref";
	if (not (-r $comment_file)) {
		# File does not exist locally, try to get it from the website
		my $comment_page = collect_url($commentaar_url);

		if (defined $comment_page) {
			$comment_page = format_comment($comment_page);
			$comment_page = tx2latin($comment_page);
			my $openres = open(Comm, ">$comment_file");
			if (not defined $openres) {
				error("Could not open $comment_file for writing.");
			} else {
				print Comm "<html>\n";
				print Comm "<head>\n";
				# print Comm "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\" />\n";
				print Comm "<title>$title</title>\n";
				print Comm "</head>\n";
				print Comm "<body>\n";
				print Comm "<h3>$title</h3>\n";
				print Comm $comment_page;
				print Comm "</body>\n";
				print Comm "</html>";
				close Comm;
			}
		}
	}
	# Check again if comment file exists. If so, add it to the Index page
	if (-r $comment_file) {
		print Comm_Index "<a href=\"$comment_ref\">$title</a><br>\n";
	}
}

=pod

=head2 Handle Ref Page

This subroutine will read through the Commentaar Main Page, find all URLs for the different Commentaar articles and handle upon each Commentaar URL.

=cut

sub handle_ref_page($) {
	my ($ref_page) = @_;
	my ($title);
	# Open Index Page
	my $indexpage = "$storydir/$indexfile";
	my $openres = open(Comm_Index, ">$indexpage");
	if (not defined $openres) {
		error("Could not open $indexpage for writing, exiting...");
		exit_application(1);
	}
	print Comm_Index "<html>\n";
	print Comm_Index "<head>\n";
#	print Comm_Index "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\" />\n";
	print Comm_Index "<title>Commentaar GvA</title>\n";
	print Comm_Index "</head>\n";
	print Comm_Index "<body>\n";
	print Comm_Index "<h3>Commentaar GvA</h3>\n";
	my $searchstring = "<h3 class=\"entry-header\">";
	while (index($ref_page, $searchstring) > -1) {
		# Extract URL
		my $startstr = "href=";
		my $startpos = index($ref_page,$startstr,index($ref_page, $searchstring));
		$startpos = $startpos + length($startstr);
		my $endstr = ">";
		my $endpos = index($ref_page,$endstr,$startpos);
		my $comm_url = substr($ref_page,$startpos+1,$endpos-$startpos-2);
		# Find Title
		my $end_title_str = "</a>";
		my $end_title_pos = index($ref_page,$end_title_str,$endpos);
		if ($end_title_pos == -1) {
			$title = "Commentaar (geen titel gevonden)";
		} else {
			$title = substr($ref_page, $endpos+1, $end_title_pos - ($endpos+1));
			if ((length($title) > 80) || (length($title) == 0)) {
				$title = "Commentaar (geen titel gevonden)";
			} else {
				$title = tx2latin($title);
			}
		}
		if (not exists $urls{$comm_url}) {
			handle_commentaar_url($comm_url,$title);
			$urls{$comm_url} = 1;	# to ensure that each URL is handled only once
		}
		$ref_page = substr($ref_page,$endpos);
	}
	print Comm_Index "</body>\n";
	print Comm_Index "</html>\n";
	return;
}

######
# Main
######

# Handle input values
my %options;
getopts("h:tl:r", \%options) or pod2usage(-verbose => 0);
my $arglength = scalar keys %options;  
# print "Arglength: $arglength\n";
#if ($arglength == 0) {			# If no options specified,
#    $options{"h"} = 0;			# display usage.
#}
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
# Log required?
if (defined $options{"n"}) {
    log_flag(0);
} else {
    log_flag(1);
    # Log required, so verify logdir available.
    if ($options{"l"}) {
		$logdir = logdir($options{"l"});
    } else {
		$logdir = logdir();
    }
    if (-d $logdir) {
		trace("Logdir: $logdir");
    } else {
		pod2usage(-msg     => "Cannot find log directory ".logdir,
		 		  -verbose => 0);
    }
}
# Logdir found, start logging
open_log();
logging("Start application");
# Check for Algemeen or Regionaal
if (defined ($options{"r"})) {
	$storydir = "d:/temp/news/GVA_Regio";		# Opinie Location
	$homepage = "http://gva.typepad.com/standpuntantwerpen/";
} else {
	$storydir = "d:/temp/news/gva";		# Opinie Location
	$homepage = "http://gva.typepad.com/standpunt/";
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input value

Log::display_flag(1);
$proxy = gethost($proxyserver);
$ua = LWP::UserAgent->new;
$ua->agent("DVagent");
$ua->timeout($uatimeout);
if (defined $proxy) {
    logging("using proxy");
    $ua->proxy('http', "http://". $proxyserver . ":$proxyport");
}

# Collect the main page with reference to all Comment pages
my $ref_page = collect_url($homepage);
if (not defined $ref_page) {
	error("Could not collect Commentaar Reference Page, exiting...");
	exit_application(1);
}

handle_ref_page($ref_page);

exit_application(0);

=pod

=head1 TO DO

=over 4

=item *

... everything

=back

=head1 AUTHOR

Any remarks or bug reports, please contact E<lt>dirk.vermeylen@skynet.beE<gt>
