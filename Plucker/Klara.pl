=head1 NAME

klara - Collects the "Klara" radio programs for the next week and converts them into a format that Plucker likes.

=head1 VERSION HISTORY

version 2.1 8 May 2004 DV

=over 4

=item * 

Add the pictures to the pictures repository.

=back

version 2.0 1 May 2004 DV

=over 4

=item *

As Klara has reviewed their website, the program required rework...

=back

version 1.0 7 April 2003 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application collects the radio programs for "Klara" for the next week. It will split-up the programs per day on block-per-block base. This guarantees a mucher quicker display of the programs blocks and a nice display as well.

Also the data is collected in a more user-friendly way: the data will not be thrown away before starting a new collection. Thus if no internet connection was possible, all data previously collected is still available.

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.8.0, build 804 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my $outputdir="d:/temp/klara";
my $title="";
my ($program,$url,$proxy,$html,$hdate,$urldate,@date,$datestring,$href,$res);
my $urlbase="http://www.klara.be/html/";
my $uatimeout=180;
my $proxyserver="internetemea.eds.com";
my $pluckfile = "$outputdir/klara.html";
my $ua;

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
#use strict 'subs';
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
    close TITEL;
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

=head2 Replace Special Character

For some reason, the </span> is replaced every now and then by a "»" character, resulting in a missing </b> and too much bold indicators.

Therefore a search is done for the occurence of the funny character "»" and all occurrences are replaced by </span>. This means that also legal occurences of the funny character will get replaced.

=cut

sub replace_special_character {
    my $searchstring="»";
    my $replacestring="</span>";
    my $searchpos=index($program,$searchstring);
    while ($searchpos > -1) {
	# Replace » with </span>
	substr($program,$searchpos,length($searchstring),$replacestring);
	logging("Replaced $searchstring by $replacestring for $title on $hdate");
	$searchpos=index($program,$searchstring);
    }
}

=pod

=head2 Handle Printb

This subroutine looks for all label pairs <span class="printb"> and </span>. The pairs will be replaced with <b> and </b>. Be careful to replace </span> only after a preceding <span class="printb"> (however this is not tested...)

=cut

sub handle_printb {
    replace_special_character;
    my $searchstring="<span class=\"printb\">";
    my $replacestring="<b>";
    my $searchstring2="</span>";
    my $replacestring2="</b>";
    my $searchpos=index($program,$searchstring);
    while ($searchpos > -1) {
	# Replace <span class="printb"> by <b>	    
	substr($program,$searchpos,length($searchstring),$replacestring);
	# Look for the occurence of </span> that goes with replaced label
	# We assume they come in pairs!
	my $searchpos2=index($program,$searchstring2,$searchpos);
	if ($searchpos2 > -1) {
	    substr($program,$searchpos2,length($searchstring2),$replacestring2);
	} else {
	    error("$searchstring and $searchstring2 did not come in pairs for $title on $hdate");
	}
	$searchpos=index($program,$searchstring);
    }
}

=pod

=head2 Strip Tags

The array @accept contains a list of tags that should not be removed. A search in a while loop tries to find all tags, verifies if they do appear in the @accept array and if not, removes the tags from the $program string. 

Note that this does not work well for the last tag. For some reason the last invalid tag </tr> is not removed. Also note that multiple instances of <br> and spaces are also not touched, since Plucker does not display them.

=cut

sub strip_tags {
    my @accept=("<b>","</b>","<br>");
    my $ptr=index($program,"<");
    while ($ptr > -1) {
	my $endtag=index($program,">",$ptr);
	# Extract the string
	my $tag=substr($program,$ptr,index($program,">",$ptr)-$ptr+1);
	# Check if the tag should be removed
	my $removetag = "Yes";
	foreach my $allowtag (@accept) {
	    if ($allowtag eq $tag) {
		$removetag = "No";
		last;
	    }
	}
	if ($removetag eq "Yes") {
	    substr($program,$ptr,index($program,">",$ptr)-$ptr+1,"");
	}
	# Now look for the next tag
	$ptr=index($program,"<",$ptr+1);
    }
}

=pod

=head2 Remove Metriweb

On each program page there appears to be a metriweb counter. We want to get rid of the counter to be able to handle all remaining images in a uniform way. Metriweb starts with B<<!--//metriweb> and ends with B<-->>. 

=cut

sub remove_metriweb($) {
    my($page)=@_;
    my $metristart=index($page,"<!--//metriweb");
    if ($metristart > -1) {
	my $metriend=index($page,"-->",$metristart);
	if ($metriend == -1) {
	    error ("Metriweb start found, but no end!");
	} else {
	    substr($page,$metristart,$metriend-$metristart+length("-->"),"");
	    return $page;
	}
    }
}

=pod

=head2 Investigate Pictures procedure

The Klara Programs do have occasionally pictures with them. Pictures are indicated with the B<images/> starter. If pictures are found, then the I<Collect Picture> procedure is called. The link to the pictures is changed from B<images/> to B<../images/> because all pictures to have the correct links on the local system.

The procedure expects the contents of the program as input and returns the contents after updating the images links.

=cut

sub investigate_pictures {
    my($page,$bios)=@_;
    my $image_end=0;
    my $image_delim="images/";
    my $image_start=index($page,$image_delim,$image_end);
    while ($image_start > -1) {
		$image_end=index($page,"\"",$image_start);
		my $filename_start=$image_start+length($image_delim);
		my $filename=substr($page,$filename_start,$image_end-$filename_start);
		collect_picture($filename,$bios);
		# Replace image with ../image
		substr($page,$image_start,length($image_delim),"../$image_delim");
		$image_start=index($page,$image_delim,$image_end);
    }
    return $page;
}

=pod

=head2 Collect Picture procedure

The Collect Picture procedure gets as input the picture name. If the picture exists already in the repository, then no further action is required. If the picture is not already available in the repository, then the picture is downloaded from the Klara website and stored in the picture repository (write in binmode).

=cut

sub collect_picture {
    my($picture_file,$bios)=@_;
    # Verify if the file exist already
    my $picture_filename="d:/temp/klara/images/$picture_file";
    my ($picture_url);
    if (-r $picture_filename) {
	print "$picture_file exists already, no need to collect again...\n";
    } else {
	if (defined $bios) {
	    $picture_url="http://www.klara.be/html/bios/images/$picture_file";
	} else {
	    $picture_url="http://www.klara.be/html/images/$picture_file";
	}
	my $picture=collect_url($picture_url);
	if (defined $picture) {
	    my $openres=open(PICT,">$picture_filename");
	    if (not (defined $openres)) {
			error ("Could not open $picture_filename for writing");
	    } else {
			binmode(PICT);
			print PICT $picture;
			close PICT;
	    }
	}
    }
}

=pod

=head2 Collect bios procedure

This procedure will scan the program item to find links to the bios from the presenters. If found, then the bios will be made available (if not yet available) and the URL will be updated to reflect the settings on the local system.

As with the pictures, the bios will be downloaded once and then live on the system for as long as required. This means that updates from the bios on the web site will not automatically be reflected on the local system. Advice is to clear the bios subdirectory every now and then to update all bios.

=cut

sub collect_bios($) {
    my($page)=@_;
    my $bios_delim="<a href=\"javascript:stemmen('";
    my $bios_start=index($page,$bios_delim);
    while ($bios_start > -1) {
	my $bios_url_start=$bios_start+length($bios_delim);
	my $bios_url_end=index($page,"'",$bios_url_start);
	my $bios_url=substr($page,$bios_url_start,$bios_url_end-$bios_url_start);
	# 1. verify if bios page is there
	my $bios_page_file="$outputdir/$bios_url";
	# if not, collect page
	if (not (-r $bios_page_file)) {
	    my $bios_page=collect_url($urlbase.$bios_url);
	    if (defined $bios_page) {
		my $openres=open(BIOS,">$outputdir/$bios_url");
		if (defined $openres) {
		    # metriweb for bios is different...
		    # $bios_page=remove_metriweb($bios_page);
		    # pictures are under bios/images...
		    $bios_page=investigate_pictures($bios_page,"bios");
		    print BIOS $bios_page;
		    close BIOS;
		} else {
		    error "Could not open $outputdir/$bios_page for writing";
		}
	    } else {
		error "Could not collect bios on $urlbase.$bios_url";
	    }
	}
	# 2. Replace URL
	my $bios_end=index($page,">",$bios_start);
	substr($page,$bios_start,$bios_end-$bios_start+1,"<a href=\"../$bios_url\">");
	$bios_start=index($page,$bios_delim,$bios_url_end);
    }
    # ... and be sure to return the updated page to the calling procedure.
    return $page;
}

=pod

=head2 Handle Program

Collect the program and save it in the appropriate file (if it can be retrieved).

=cut

sub handle_program($) {
    # Collect program
    my($urltitle)=@_;
    my $urlprogram=$urlbase.$urltitle;
    my $program=collect_url($urlprogram);
    if (defined $program) {
	my $openres=open(PGM,">$outputdir/$datestring/$title.html");
	$program=remove_metriweb($program);
	$program=investigate_pictures($program);
	$program=collect_bios($program);
	print PGM $program;
	close PGM;
    } else {
	error("Could not collect program on $urlprogram");
    }
}

=pod

=head2 Handle Day

Investigate if the directory for the day exists. If not, create it. The idea is to collect information for the next week, so pre-views can be updated with newer information later on while preventing that the data is overwritten with useless data if no information can be found.

Per day a page is created with the program titles for that day. The program titles link to the actual program description.

=cut

sub handle_day {
    # Now start working
    if (not(-d "$outputdir/$datestring")) {
	if (mkdir("$outputdir/$datestring",0)) {
	    logging("$outputdir/$datestring has been created");
	} else {
	    error("Could not create $outputdir/$datestring.");
	    exit_application(1);
	}
    }
    open(TITEL,">$outputdir/$datestring/titel.html");
    print TITEL "<h2>$hdate</h2>\n\n";
    # Scan through day overview to find Program URLs and Program titles
    my $urldelim="<a HREF=\"";
    my $titledelim="Gegevens\">";
    my $titleenddelim="</a>";
    my $currpos=0;
    my $newitem=index($html,$urldelim,$currpos);
    while ($newitem > -1) {
	# New URL and title available
	# Try to find them
	# But first initialize $currpos
	$currpos=$newitem+length($urldelim);
	# URL has a fixed length: YYMMDDSSSSS.html
	my $urltitle=substr($html,$currpos,16);
	my $titlestart=index($html,$titledelim,$currpos)+length($titledelim);
	my $titleend=index($html,$titleenddelim,$titlestart);
	$title=substr($html,$titlestart,$titleend-$titlestart);
	print TITEL "<a href=\"$title.html\">$title</a><br>\n";
	trace("$urltitle: $title***");
	# Now do some magic with the URL and the title
	handle_program($urltitle);
	# and re-initialize
	$newitem=index($html,$urldelim,$currpos);
    }
}
	
=pod

=head2 Collect Program

This subroutine collects the full program for a particular day. If successful, then the contents of the program will be analyzed and written to files. If not successful, then the files that might exist from the previous runs are kept.

Also program changes in the course of the week are taken into account with this approach.

=cut

sub collect_program {
    # Find the URL
    $url=$urlbase.$urldate;
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
	$html=$res->content;
	trace("Content collected for $datestring");
	handle_day;
    } else {
	error("Could not collect program overview for $hdate");
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

# Create Klara home page
my $openres=open(PLUCK, ">$pluckfile");
if (not $openres) {
    error("Could not open $pluckfile.");
    exit_application(1);
}
print PLUCK "<Title>Klara</Title>\n\n";
print PLUCK "<h1>Klara Programmaschema</h1>\n\n";

# Loop through all dates for the week starting today
for (my $cnt=0; $cnt<7; $cnt++) {
    $hdate= Day_of_Week_to_Text(Day_of_Week(@date)).", ".$date[2]." ".
			           Month_to_Text($date[1])." ".$date[0];
    $datestring=sprintf("%02d%02d%02d",substr($date[0],2,2),$date[1],$date[2]);
    $urldate=$datestring."ME.html";
    $href="$datestring/titel.html";
    print PLUCK "<a href=\"$href\">$hdate</a><br>\n";
    collect_program;
    @date=Add_Delta_Days(@date,1);
}


exit_application(0);

=pod

=head1 TO DO

=over 4

=item *

Clean up procedures from previous version, add appropriate comments, ...

=item *

Investigate to link the presentators in ...

=item *

Replace "Collect Program" with "Collect URL".

=item *

Implement 'age check' on the bios and the pictures to be notified if newer versions are available.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@skynet.beE<gt>
