=head1 NAME

KBTocGen.pl - Table of Contents Generator for the Knowledge Base

=head1 VERSION HISTORY

version 1.1 - 25 October 2004 DV

=over 4

=item * 

Add script to clear the description window

=back

version 1.0 - 9 November 2002 DV

=over 4

=item *

Initial release, based on the tocgen.pl script

=back

=head1 DESCRIPTION

The application generates a table of contents from a set of *.html files. It starts from a directory and creates references for all folders in the directory. Then it investigates all subdirectories to create a table of Contents on the subdirectories level.

kbtocgen investigates only the directories, it will not walk through any available subdirectories. In every directory a toc.html is created with the "Table of Contents" for this directory.

By using the default index.html file, the contents of each subdirectory is shown on the upper half of the right frame. Information itself is displayed on the lower half of the right frame.

The goal is to provide an index for knowledge based type of articles. Every topic remains in its own file, resulting in excellent performances for the Palm (but also in exaggerated disk space usage on the PC).

=head1 SYNOPSIS

 KBTocGen.pl [-t] [-l log_dir] [-s source_dir]

 kbTocGen.pl -h		Usage information
 kbTocGen.pl -h 1		Usage information and a description of the options
 kbTocGen.pl -h 2		Full documentation

=head1 OPTIONS

=over 4

=item B<-t>

enable trace messages if set

=item B<-l log_dir>

Logfile directory, by default: c:\temp

=item B<-s source_dir>

Source directory, by default: c:\web\kb\library

=back

=head1 ADDITIONAL INFORMATION

=cut

###########
# Variables
###########

my $sourcedir = "d:/web/kb/library";	    # source directory
my $maintoc = "MAINTOCFILE";		    # Placeholder name
my $subjecttoc = "SUBJECTTOCFILE";	    # Placeholder name
my $logdir;				    # Logdirectory
my $total_categories = 0;		    # number of categories included in TOC
my $total_descriptions = 0;		    # number of descriptions added to the TOC

# HTML specific settings
$topictarget = "target=\"topics\"";
$descriptiontarget = "target=\"description\"";
$currind = "";

#####
# use
#####

#use warnings;
#use strict 'vars';
#use strict 'refs';
#use strict 'subs';
use Getopt::Std;	    # for input parameter handling
use File::Basename;	    # $0 to basename conversion
use Pod::Usage;		    # Usage printing
use Log;

#############
# subroutines
#############

sub exit_application($) {
    my($return_code) = @_;
    logging("$total_categories categories added");
    logging("$total_descriptions descriptions added");
    logging("Exit application with return code $return_code\n");
    close_log();
    exit $return_code;
}

=pod

=head2 Handle File Procedure

=over 4

=item *

Verify if the file is of type *.html, this is verified on the extension only.

=item *

If so, calculate the relative directory to the file starting from the source directory.

=item *

Create an entry in the TOC with the filename (without extension) and a relative I<href> to the file itself.

=back

=cut

sub handle_file($$) {
    my($abs_dir, $file) = @_;
    # Calculate the relative directory to the html file, 
    # including / before the file name.
    my($rel_dir) = substr($abs_dir, length($sourcedir)+1);
    my($filename) = basename($file, ".html");
    # I'm only interested in html files, $fileext is empty for other files.
    my($fileext) = substr($file,length($filename)+1);
    if ($fileext eq "html") {
	print $toc "$currind$bullet<a href=\"$rel_dir$file\" $target>$filename</a><br>\n";
	$total_included++;
    }
}

=pod

=head2 Walk through procedure

This procedure walks through a subdirectory.

=over 4

=item *

Add the subdirectory name to the TOC

=item *

Read all entries in the subdirectory, separate files and directories. Order (case-insensitive) the file list and the directory list.

=item *

Submit all files to the Handle File procedure

=item *

Submit all directories to the Walk Through procedure

=item *

End of this subdirectory handling, so remove the indent to the TOC.

=back

=cut

sub handle_subdir($$) {
    my ($directory, $topic) = @_;
    my (@dirlist,@filelist);
    if (!(opendir ("$directory", $directory))) {
	error "Opendir $direcory failed!";
    } else {
	@entrylist = readdir("$directory");
	foreach $filename (@entrylist) {
	    my $checkfile = $directory."/$filename";
	    if (-f $checkfile) {
		push @filelist, $filename;
	    }
	}
	closedir $directory;
	my(@sorted_filelist) = sort { lc($a) cmp lc($b) } @filelist;
	my $openres = open($subjecttoc, ">$directory/toc.html");
	if (not $openres) {
	    error("Cannot open $directory/toc.html for writing");
	    exit_application(1);
	}
	# Initialize toc.html
	print $subjecttoc "<html>\n";
	print $subjecttoc "<script>\n";
	print $subjecttoc "function clear_description() {\n";
	print $subjecttoc "	window.open(\"about:blank\",\"description\");\n";
	print $subjecttoc "}\n";
	print $subjecttoc "</script>\n";
	print $subjecttoc "<h2>$topic</h2>\n";
	print $subjecttoc "<body onLoad=\"clear_description()\";>\n";
	print $subjecttoc "<menu>\n";
	foreach $filename (@sorted_filelist) {
	    my $title = basename($filename, ".html");
	    my $fileext = substr($filename, length($title)+1);
	    if (($fileext eq "html") and ($title ne "toc")) {
		print $subjecttoc "<li><a href=\"$filename\" $descriptiontarget>$title</a>\n";
		$total_descriptions++;
	    }
	}
	print $subjecttoc "</menu>\n";
	print $subjecttoc "</body>\n";
	print $subjecttoc "</html>";
	close $subjecttoc;
    }
}

=pod

=head2 Scan Dir procedure

The Scan Dir procedure reads all file(types) in the directory. Files and directories are separated. Then Files are ordered (case sensitive) and then submitted one by one to the handle_file procedure.

After this, directories are submitted one by one to the walk_through procedure.

=cut

sub handle_maindir($) {
    my ($directory) = @_;
    my (@dirlist, @entrylist);
    if (!(opendir ("$directory", $directory))) {
	error "Opendir $direcory failed!";
    } else {
	@entrylist = readdir("$directory");
	foreach my $filename (@entrylist) {
	    my $checkfile = $directory."/$filename";
	    if (-d $checkfile) {
		if (("$filename" ne ".") && ("$filename" ne "..")) {
		    push @dirlist, $filename;
		}
	    }
	}
	closedir $directory;
	trace "End of filelist.";
	@sorted_dirlist  = sort { lc($a) cmp lc($b) } @dirlist;
	# Open main toc.html for writing
	$openres = open ($maintoc, ">$sourcedir/toc.html");
	if (not $openres) {
	    error("Cannot open $sourcedir/toc.html for writing");
	    exit_application(1);
	}
	# Initialize toc.html
	#	print $maintoc "<html>\n<div nowrap>\n";
    	print $maintoc "<html>\n";
	print $maintoc "<menu>\n";
	foreach $filename (@sorted_dirlist) {
	    if ($filename ne "images") {
		print $maintoc "<li><a href=\"$filename/toc.html\" $topictarget>$filename</a>\n";
		$total_categories++;
		handle_subdir("$directory/$filename", $filename);
	    }
	}
	print $maintoc "</menu>\n";
	print $maintoc "</html>";
	close $maintoc;
    }
}


######
# Main
######

# Handle input values
getopts("tl:s:h:", \%options) or pod2usage(-verbose => 0);
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
    trace_flag(1);
    trace("Trace enabled");
}
# Find log file directory
if ($options{"l"}) {
    $logdir = logdir($options{"l"});
}
$logdir = logdir();
if (-d $logdir) {
    trace("Logdir: $logdir");
} else {
    die "Cannot find log directory $logdir.\n";
}
# Logdir found, start logging
open_log();
logging("Start application");
# Find source directory
if ($options{"s"}) {
    $sourcedir = $options{"s"};
}
if (-d $sourcedir) {
    trace("Source Directory: $sourcedir");
} else {
    error("Cannot find source directory $sourcedir");
    exit_application(1);
}
while (($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

handle_maindir($sourcedir);

exit_application(0);

=pod

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
