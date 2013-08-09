=head1 NAME

Create_Pages - This program creates a page for each picture to be displayed.

=head1 VERSION HISTORY

version 2.1 - 21 January 2007 DV

=over 4

=item *

Include Index Page, to allow easy print for picture selection.

=back

version 2.0 - 6 March 2006 DV

=over 4

=item *

Upgrade to include Javascript that will resize pictures as the browser resizes.

=back

version 1.1 - 3 July 2004 DV

=over 4

=item *

Add comments

=item *

Remove "Vorige" link for the first picture and "Volgende" for the last picture.

=back

version 1.0 - 30 May 2004 DV

=over 4

=item *

Initial Release

=back

=head1 DESCRIPTION

This program reads through the Images directory and creates a html page for each picture to be displayed. Each picture has a link to the Previous and to the Next picture. The first picture links to the last, the last picture links to the first picture.

The Album Directory must have following subdirectories: Pages, Images and Thumbnails. The Images directory contains the "full sized" pictures, the Thumbnails directory contains the thumbnail pictures and the Pages directory contains the html pages as created with this application. It is important that the Images directory and the Thumbnails directory are in sync. Both directories are required to allow the user to create images and thumbnails of the request size and accuracy.

As a rule of the thumb, images are displayed on size 530*350 pixels (28 % of Original size), while thumbnails are on 100*60 pixels (4% of original size). JPEG reduction for both is 80% and the "Keep original EXIF/IPTC data or JPEG comment" is B<not> set. Of course since the extension with Javascript it is now possible to have images in larger sizes.

Picture from a photo CD are reduced to 33% for the Images and to 6% for the Thumbnails. However the Create_Images.pl should reformat the pictures to suitable sizes.

The Pages directory can have a file I<Album_directory.txt>. If this file exists, then the Title, Comment, Date and City for each picture can be stored in this file. If available, then they will be displayed on the html page.

=head1 SYNOPSIS

 Create_Pages.pl [-t] [-l logfile_directory]  -d Album_directory

 Create_Pages.pl -h		Usage Information
 Create_Pages.pl -h 1	Usage Information and Options description
 Create_Pages.pl -h 2	Full documentation

=head1 OPTIONS

=over 4

=item B<-t>

if set, then trace messages will be displayed. 

=item B<-l logfile_directory>

default: c:\temp

=item B<-d Album_directory>

Points to the Album directory. In the Album directory, the pictures are stored in the Images subdirectory, while the pages are created in the Pages subdirectory.

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
###########

my @suffixlist=(".jpg");    # contains a list of all image extensions that can be handled
my $maxcols = 6;		    # Number of thumbnail pictures per row
my $maxrows = 6;		# Number of rows per index page
my $pagecount = 1;
my ($logdir, $albumdir, $indexpage, $albumname);
my (%title, %comment, %place, %date);
my (@indexpages, @dirlist);

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

#############
# subroutines
#############

sub exit_application($) {
    my($return_code) = @_;
    logging("Exit application with return code $return_code\n");
    close_log();
    exit $return_code;
}

=pod

=head2 Create Frame

This procedure will create the frame html for each picture page. This is the main page for each picture.

=cut

sub create_frame($) {
    my ($curr) = @_;
    my $openres=open(Frame,">$albumdir/Pages/frame$curr.html");
    if (not(defined $openres)) {
	error ("Could not open $albumdir/Pages/frame$curr.html for writing");
    } else {
	print Frame "<html>\n";
	print Frame "<head>\n";
	print Frame "<title>$albumname</title>\n";
	print Frame "</head>\n";
	print Frame "<frameset rows=\"50,*,70\">\n";
	print Frame "<frame src=\"title$curr.html\" scrolling=\"no\">\n";
	print Frame "<frame src=\"picture$curr.html\">\n";
	print Frame "    <frameset cols=\"50%,*\">\n";
	print Frame "        <frame src=\"nav$curr.html\">\n";
	print Frame "        <frame src=\"info$curr.html\">\n";
	print Frame "    </frameset>\n";
	print Frame "</frameset>\n";
	print Frame "</html>";
	close Frame;
    }
}

=pod

=head2 Create Title

This procedure will create the title frame for each picture.

=cut

sub create_title($) {
    my ($curr) = @_;
    my $openres=open(Title,">$albumdir/Pages/title$curr.html");
    if (not(defined $openres)) {
	error ("Could not open $albumdir/Pages/title$curr.html for writing");
    } else {
	print Title "<html>\n";
	print Title "<body bgcolor=\"yellow\">\n";
	print Title "<center>\n";
	my $local_title;
	if (defined $title{$curr}) {
	    $local_title = $title{$curr};
	} else {
	    $local_title = $curr;
	}
	print Title "<h2 id=\"title\">$local_title</h2>\n";
	print Title "</center>\n";
	print Title "</body>\n";
	print Title "</html>\n";
	close Title;
    }
}

=pod

=head2 Create Picture

This procedure will read the picture and display it in the picture section of the frame. Resizing will be done to guarantee that the picture fits nicely in the frame.

=cut

sub create_picture($) {
    my ($curr) = @_;
    my $openres=open(Pic ,">$albumdir/Pages/picture$curr.html");
    if (not(defined $openres)) {
	error ("Could not open $albumdir/Pages/picture$curr.html for writing");
    } else {
	print Pic "<html>\n";
	print Pic "<head>\n";
	print Pic "<script type=\"text/javascript\" src=\"picture_funcs.js\">\n";
	print Pic "</script>\n";
	print Pic "</head>\n";
	print Pic "<body bgcolor=\"lightblue\" onresize=\"resize(document.picture)\">\n";
	print Pic "<center>\n";
	print Pic "<img src=\"../images/$curr.jpg\" name=\"picture\" onload=\"capture_size(document.picture)\">\n";
	print Pic "</center>\n";
	print Pic "</body>\n";
	print Pic "</html>\n";
	close Pic;
    }
}

=pod

=head2 Create Navigation

This subroutine will create the Navigation page that goes with each picture. It will point the previous page, the next page and the home page.

=cut

sub create_nav($$$) {
    my ($prev, $curr, $next) = @_;
    my $openres=open(Nav ,">$albumdir/Pages/nav$curr.html");
    if (not(defined $openres)) {
	error ("Could not open $albumdir/Pages/nav$curr.html for writing");
    } else {
	print Nav "<html>\n";
	print Nav "<script type=\"text/javascript\" src=\"picture_funcs.js\">\n";
	print Nav "</script>\n";
	print Nav "<body bgcolor=\"yellow\">\n";
	print Nav "<form>\n";
	print Nav "<input type=\"button\" value=\"vorige\" name=\"vorige\" onclick=\"parent_to_url('frame$prev.html')\">\n";
	print Nav "<input type=\"button\" value=\"home\" name=\"home\" onclick=\"parent_to_url('overzicht.html')\">\n";
	print Nav "<input type=\"button\" value=\"volgende\" name=\"volgende\" onclick=\"parent_to_url('frame$next.html')\">\n";
	print Nav "</form>\n";
	print Nav "</body>\n";
	print Nav "</html>\n";
	close Nav;
    }
}

=pod

=head2 Create Info

This procedure will add the Information to each picture.

=cut

sub create_info($) {
    my ($curr) = @_;
    my $openres=open(Info ,">$albumdir/Pages/info$curr.html");
    if (not(defined $openres)) {
	error ("Could not open $albumdir/Pages/info$curr.html for writing");
    } else {
	print Info "<html>\n";
	print Info "<body bgcolor=\"lightblue\">\n";
	my $line;
        if (defined ($place{$curr})) {
	    $line = $place{$curr};
	}
	if (defined ($date{$curr})) {
	    if (defined $line) {
		$line = "$line - $date{$curr}\n";
	    } else {
		$line = "$date{$curr}\n";
	    }
	}
	if (defined ($comment{$curr})) {
	    if (defined $line) {
		$line = "$line<br>\n$comment{$curr}\n";
	    } else {
		$line = "$comment{$curr}\n";
	    }
	}
	if (defined $line) {
	    print Info $line;
	}
	print Info "</body>\n";
	print Info "</html>\n";
	close Info;
    }
}

=pod

=head2 Create Page Procedure

For each image a number of files need to be created:

=over 4

=item frames

This is the main frameset page that calls all other pages.

=item title

This page contains the title of the picture.

=item picture

This page contains the picture and references to the Javascript resize functions.

=item navigation

This page contains the buttons to the previous, next and overview page.

=item info

This page contains additional information about the picture, including place, time and comment, if available.

=back

=cut

sub create_pages {
    my($prevfile,$currfile,$nextfile)=@_;
    my($prev,$curr,$next);
    if ($prevfile ne "NONE") {
	$prev=basename($prevfile,@suffixlist);
    }
    $curr=basename($currfile,@suffixlist);
    if ($nextfile ne "NONE") {
        $next=basename($nextfile,@suffixlist);
    }
    create_frame($curr);
    create_title($curr);
    create_picture($curr);
    create_nav($prev,$curr,$next);
    create_info($curr);
}

=pod

=head2 Create Overzicht Procedure

This procedure creates the overview page per folder. Therefore it reads the Thumbnails directory and add all filenames that are not equal to B<.> or B<..> to the Overview page. It is important that the Thumbnails page is in sync with the Images page. No further checking on the file contents is done.

=cut

sub create_overzicht {
    my $openres=open(Overview,">$albumdir/Pages/overzicht.html");
    if (not (defined $openres)) {
	error ("Could not open $albumdir/Pages/overzicht.html for writing.");
	return;
    }
    print Overview "<html>\n";
    print Overview "<head>\n";
	print Overview "<script type=\"text/javascript\" src=\"picture_funcs.js\">\n";
	print Overview "</script>\n";
    print Overview "<title>$albumname</title>\n";
    print Overview "</head>\n";
    print Overview "<body bgcolor=lightyellow><center>\n";
    print Overview "<table bgcolor=lightgreen border=0>\n";
    print Overview "<tr>\n";
    print Overview "<td><h1>$albumname</h1></td>\n";
    print Overview "</table>\n";
	print Overview "<form>\n";
	print Overview "<input type=\"button\" value=\"index\" name=\"index\" onclick=\"parent_to_url('index_1.html')\">\n";
	print Overview "</form>\n";
    # print Overview "<table bgcolor=lightgreen align=center border=2 cellspacing=10>\n";
    print Overview "<table bgcolor=lightgreen align=center cellspacing=10>\n";
    my $columncount=0;
    foreach my $filename (@dirlist) {
	if (("$filename" ne ".") and ("$filename" ne "..")) {
	    my $file=basename($filename,@suffixlist);
	    if ($columncount==0) {
		print Overview "<tr>\n";
	    }
	    print Overview "<td align=center><a href=frame$file.html><img src=\"../Thumbnails/$filename\"></a></td>\n";
	    $columncount++;
	    if ($columncount==$maxcols) {
		print Overview "</tr>\n";
		$columncount=0;
	    }
	}
    }
    if ($columncount > 0) {
	print Overview "</tr>\n";
    }
    print Overview "</table>\n";
    print Overview "</body>\n";
    print Overview "</html>\n";
    close Overview;
}

=pod

=head2 Create Index Page Procedure

This procedure creates the index page per folder. Therefore it reads the Thumbnails directory and add all filenames that are not equal to B<.> or B<..> to the index page, so that the index page can be printed (page by page). The goal is that the index pages are printed nicely on one single page.

Each Indexpage is stored in a separate row of the indexpages table, to allow easy printing, including referencing to previous and next pages.

=cut

sub create_index {
    my $columncount = 0;
	my $rowcount = 0;
    foreach my $filename (@dirlist) {
	if (("$filename" ne ".") and ("$filename" ne "..")) {
		if (($rowcount == 0) and ($columncount == 0)) {
		}
	    my $file=basename($filename,@suffixlist);
		# A filelabel should be no longer than 12 characters -
		# so that page formatting is not destroyed.
		my $filelabel = substr($file,0,12);
	    if ($columncount==0) {
			$indexpages[$pagecount] .= "<tr>\n";
	    }
		# Test $filename - should not be longer than x chars
		# truncate to x chars.
	    $indexpages[$pagecount] .= "<td align=center><a href=frame$file.html><img src=\"../Thumbnails/$filename\"></a>\n";
		$indexpages[$pagecount] .= "<br>$filelabel</td>";
	    $columncount++;
	    if ($columncount==$maxcols) {
			$indexpages[$pagecount] .= "</tr>\n";
			$columncount=0;
			$rowcount++;
			if ($rowcount >= $maxrows) {
				$rowcount = 0;
				$pagecount++;
			}
	    }
	}
    }
	if ($columncount > 0) {
		$indexpages[$pagecount] .=  "</tr>\n";
    }
	if ($rowcount > 0) {
    }
}

=pod

=head2 Handle Comment Procedure

This procedure checks if the comment file exists. The filename must be I<albumname.csv>.

Each line in the file must start with the filename of the picture. All other fields are optional.

=cut

sub handle_comment() {
    $albumname=basename($albumdir);
    my $commentfile="$albumdir/Pages/$albumname.csv";
    trace("Looking for $commentfile");
    if (-r $commentfile) {
	trace ("Comment file $commentfile found!");
	my $openres=open(COMMENT, $commentfile);
	if (not(defined $openres)) {
	    error("Could not open $commentfile for reading!");
	} else {
	    while (my $inputline=<COMMENT>) {
		chomp $inputline;
		my($full_filename,undef,$datum,$stad,$titel,$commentaar)=split /;/,$inputline;
		my ($filename,undef) = split /\./,$full_filename;
		if (defined $datum) {
		    $date{$filename}=$datum;
		}
		if (defined $stad) {
		    $place{$filename}=$stad;
		}
		if (defined $titel) {
		    $title{$filename}=$titel;
		}
		if (defined $commentaar) {
		    $comment{$filename}=$commentaar;
		}
	    }
	    close COMMENT;
	}
    }
}

=pod

=head2 Print Index Pages

This procedure will print all index pages, including all references to previous and next pages (wherever appropriate).

=cut

sub print_index_pages() {
	for (my $cnt=1;$cnt <= $pagecount; $cnt++) {
		$indexpage = "$albumdir/Pages/index_$cnt".".html";
    	my $openres=open(Index,">$indexpage");
    	if (not (defined $openres)) {
			error ("Could not open $indexpage for writing.");
			return;
    	}
    	print Index "<html>\n";
	    print Index "<head>\n";
    	print Index "<title>$albumname</title>\n";
		print Index "<head>\n";
		print Index "<script type=\"text/javascript\" src=\"picture_funcs.js\">\n";
		print Index "</script>\n";
		print Index "</head>\n";
	    print Index "</head>\n";
    	print Index "<body bgcolor=lightyellow><center>\n";
	    print Index "<table bgcolor=lightgreen border=0>\n";
    	print Index "<tr>\n";
	    print Index "<td><h1>$albumname - page $cnt</h1></td>\n";
    	print Index "</table>\n";
		print Index "<form>\n";
		# Print pointer to previous page if not first page
		if ($cnt > 1) {
			my $prev_page = $cnt - 1;
			my $prev_page_ref = "index_$prev_page".".html";
			print Index "<input type=\"button\" value=\"vorige\" name=\"vorige\" onclick=\"parent_to_url('$prev_page_ref')\">\n";
		}
		# Print pointer to home page
		print Index "<input type=\"button\" value=\"home\" name=\"home\" onclick=\"parent_to_url('overzicht.html')\">\n";
		# Print pointer to next page if not last page
		if ($cnt < $pagecount) {
			my $next_page = $cnt + 1;
			my $next_page_ref = "index_$next_page".".html";
			print Index "<input type=\"button\" value=\"volgende\" name=\"volgende\" onclick=\"parent_to_url('$next_page_ref')\">\n";
		}
		print Index "</form>\n";
	    # print Index "<table bgcolor=lightgreen align=center border=2 cellspacing=10>\n";
    	print Index "<table bgcolor=lightgreen align=center cellspacing=10>\n";
		print Index $indexpages[$cnt];
	    print Index "</table>\n";
    	print Index "</body>\n";
	    print Index "</html>\n";
    	close Index;
	}
}

######
# Main
######

# Handle input values
my %options;
getopts("d:l:th:", \%options) or pod2usage(-verbose => 0);
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
# Find Album directory
if ($options{"d"}) {
    $albumdir = $options{"d"};
} else {
    error("No Album Directory specified, exiting...");
    exit_application(1);
}
if (-d $albumdir) {
    trace("Album Directory: $albumdir");
} else {
    error("Cannot find Album directory $albumdir.\n");
    exit_application(1);
}
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Handle Title-Comment file
handle_comment();

# Read Images directory
my $openres=opendir(ImageFiles,"$albumdir/Images");
if (not $openres) {
    error "Could not open Images directory $albumdir/Images, exiting...";
    exit_application(1);
}
@dirlist=readdir(ImageFiles);
close ImageFiles;

# Each image displays itself and links to both the previous picture and the next picture
my ($firstpicture, $secondpicture, $prevpicture, $currpicture, $nextpicture);
foreach my $filename (@dirlist) {
    if (("$filename" ne ".") and ("$filename" ne "..")) {
	# First picture points to last picture on "Previous" button
	# Remember first picture and handle after last picture
	if (not (defined $firstpicture)) {
	    $firstpicture=$filename;
	    $prevpicture=$filename;
	} else {
	    # Remember also second picture as "Next" for first picture
	    if (not (defined $currpicture)) {
		$currpicture=$filename;
		$secondpicture=$filename;
	    } else {
		$nextpicture=$filename;
		create_pages($prevpicture,$currpicture,$nextpicture);
		# Shift pictures
		$prevpicture=$currpicture;
		$currpicture=$nextpicture;
	    }
	}
    }
}
# Now handle last picture
$nextpicture="LAATSTE";
create_pages($prevpicture,$currpicture,$nextpicture);
# ... and handle first picture
$prevpicture="EERSTE";
$currpicture=$firstpicture;
$nextpicture=$secondpicture;
create_pages($prevpicture,$currpicture,$nextpicture);

# Finally create "overzicht.html"
create_overzicht;

# ... and the index pages, for printing the overview:
create_index;
print_index_pages;

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Script to verify Images and Thumbnails directories are in sync. Both directories should contain only the pictures, nothing else.

=item *

Instead of reading from directory list, create an order - title - comment file for the images.

=item *

Remove processing of WS_FTP.LOG or any other unwanted file...

=item *

Review to reduce the number of pages and have picture references as XML data.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@skynet.beE<gt>
