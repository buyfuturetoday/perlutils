=head1 NAME

Create_Images - This program creates the environment and Images for the Create_Pages application.

=head1 VERSION HISTORY

version 1.0 - 25 January 2007 DV

=over 4

=item *

Initial Release.

=back

=head1 DESCRIPTION

This application will create the environment (directory structure) and images for the Create_Pages Application. The Pages, Images and Thumbnails directory will be created if it does not exist. The picture_funcs.js will be created. All Images will be copied to the Images directory and to the Thumbnails directory on the appropriate size. The size of the Thumbnails directory should allow to print the index page on on paper page.

This application requires the ImageMagick application and the PerlMagick procedure.

=head1 SYNOPSIS

 Create_Images.pl [-t] [-l logfile_directory]  -s Source_directory -a Album_directory [-o]
 
 Create_Images.pl -h		Usage Information
 Create_Images.pl -h 1		Usage Information and Options description
 Create_Images.pl -h 2		Full documentation

=head1 OPTIONS

=over 4

=item B<-t>

if set, then trace messages will be displayed. 

=item B<-l logfile_directory>

default: c:\temp

=item B<-s Source_directory>

Points to the Source directory. This directory contains all originals of the pictures.

=item B<-a Album_directory>

Points to the Album directory. Following directories will be created if they don't exist: album_directory, album_directory\Images, album_directory\Pages, album_directory\Thumbnails. Also the function picture_funcs.js will be created if it doesn't exist.

=item B<-o>

Overwrite existing images and thumbnail files. Default: do not overwrite. If specified, then all images will be overwritten.

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
###########

my ($logdir, $albumdir, $sourcedir, $keep);
my $image_size = 1024;		# Max size of the image in pixels
my $thumbnail_size = 128;	# Will 128 fit on a page, or should it be 92?

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
use Image::Magick;

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

=head2 Create Dir Procedure

This procedure will create the directory specified. If it is not possible to create the directory, an error message will be shown and the program will exit.

=cut

sub create_dir($) {
	my ($dir) = @_;
	my $dir_retcode = mkdir $dir;
	if ($dir_retcode) {
		logging("$dir created.");
	} else {
		error("Could not create $dir: ".$!.", exiting...");
		exit_application(1);
	}
}

=pod

=head2 Create js Procedure

This procedure will create the picture_funcs.js function in the Pages directory. Note that - in case a code change is required - it must be done in the code between the B<EndJsfile> markers.

=cut

sub create_js($) {
	my ($js_file) = @_;
	my $openres = open (Jsfile, ">$js_file");
	if (not(defined $openres)) {
		error("Couldn't open $js_file for writing, exiting...");
		exit_application(1);
	}
	print Jsfile << "EndJsfile";
function parent_to_url(url) {
    if (url == "frameEERSTE.html") {
        parent.location.href = "overzicht.html";
    } else if (url == "frameLAATSTE.html") {
        parent.location.href = "overzicht.html";
    } else {
        parent.location.href = url;
    }
}
// The capture_size function will execute onload of the page
// and will capture the original size of the picture. 
// This will then be used to ensure that the picture will never needs
// to get bigger than the original size.
var orig_width, orig_height;
function capture_size(picture) {
    orig_width = picture.width;
    orig_height = picture.height;
    resize(picture);
}
function resize(picture) {
    // Verify if resizing is required
    if (navigator.appName == "Netscape") {
        var margin = 16;        // Margin required around the picture. 
        var window_width = window.innerWidth - margin;
        var window_height = window.innerHeight - margin;
    } else if (navigator.appName == "Microsoft Internet Explorer") {
        var margin = 38;        // Margin required around the picture. 
        var window_width = document.body.offsetWidth - margin;
        var window_height = document.body.offsetHeight - margin;
    }
    if ((window_width >= orig_width) && (window_height >= orig_height)) {
        // No resizing required, set picture to original size
        picture.height = orig_height;
        picture.width  = orig_width;
    } else {
        // Resizing required
        width_scale = window_width / orig_width;
        height_scale = window_height / orig_height;
        if (width_scale < height_scale) {
            picture.width = window_width;
            picture.height = orig_height * (window_width / orig_width);
        } else {
            picture.width = orig_width * (window_height / orig_height);
            picture.height = window_height;
        }
    }
}
EndJsfile
	close Jsfile;
	logging("$js_file written");
}

######
# Main
######

# Handle input values
my %options;
getopts("l:th:s:a:o", \%options) or pod2usage(-verbose => 0);
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
# Find Source directory
if ($options{"s"}) {
    $sourcedir = $options{"s"};
} else {
    error("No Source Directory specified, exiting...");
    exit_application(1);
}
if (-d $sourcedir) {
    trace("Source Directory: $sourcedir");
} else {
    error("Cannot find Source directory $sourcedir");
    exit_application(1);
}
# Find Album directory
if ($options{"a"}) {
    $albumdir = $options{"a"};
} else {
    error("No Album Directory specified, exiting...");
    exit_application(1);
}
# Check to keep or overwrite existing pictures
if (defined $options{"o"}) {
	$keep = "No";
} else {
	$keep = "Yes";
}
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Create album directory and subdirectories
if (not(-d $albumdir)) {
	create_dir($albumdir);
}
if (not(-d "$albumdir/Pages")) {
	create_dir("$albumdir/Pages");
}
if (not(-d "$albumdir/Images")) {
	create_dir("$albumdir/Images");
}
if (not(-d "$albumdir/Thumbnails")) {
	create_dir("$albumdir/Thumbnails");
}
if (not(-r "$albumdir/Pages/picture_funcs.js")) {
	create_js("$albumdir/Pages/picture_funcs.js");
}

# Read Source directory
my $openres=opendir(ImageFiles,"$sourcedir");
if (not $openres) {
    error "Could not open Images directory $sourcedir for reading, exiting...";
    exit_application(1);
}
my @dirlist=readdir(ImageFiles);
close ImageFiles;

my $nr_files = @dirlist;
$nr_files = $nr_files - 2;
my $filecnt = 0;
foreach my $filename (@dirlist) {
    if (("$filename" ne ".") and ("$filename" ne "..")) {
		$filecnt++;
		print "Handling file $filename ($filecnt / $nr_files)\n";
		# Handle only jpg files (for now)
		my $ext = substr($filename,length($filename)-3);
		$ext = lc($ext);
		if ($ext eq "jpg") {
			my $imagefile = "$sourcedir/$filename";
			my $albumfile = "$albumdir/Images/$filename";
			my $tn_file = "$albumdir/Thumbnails/$filename";
			if (not(($keep eq "Yes") and (-r $albumfile) and (-r $tn_file))) {
				my $image = Image::Magick->new;
				$image->Read($imagefile);
				# Write Albumfile if required
				if (not(($keep eq "Yes") and (-r $albumfile))) {
					my ($width,$height) = $image->Get('width', 'height');
					# Reduce to Image size first (never enlarge!)
					if (($width > $image_size) or ($height > $image_size)) {
						# Resizing required
						$image->Resize(geometry=>"$image_size x $image_size");
					}
					$image->Write(filename=>$albumfile);
				}
				# Write Thumbnail file if required
				if (not(($keep eq "Yes") and (-r $tn_file))) {
					my ($width,$height) = $image->Get('width', 'height');
					if (($width > $thumbnail_size) or ($height > $thumbnail_size)) {
						# Resizing required
						$image->Resize(geometry=>"$thumbnail_size x $thumbnail_size");
					}
					$image->Write(filename=>$tn_file);
				}
				undef $image;
			}
		}
    }
}

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Nothing for now....

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@skynet.beE<gt>
