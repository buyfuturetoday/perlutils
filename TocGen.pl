=head1 NAME

TocGen.pl - Table of Contents Generator

=head1 VERSION HISTORY

version 1.1 29 March 2002 DV

=over 4

=item *

Correct bug, add missing use Pod::Usage statement

=back

version 1.0 19 March 2002 DV - Initial Release

=head1 DESCRIPTION

The application generates a table of contents from a set of *.html files. It starts from a directory name and walks through all subdirectories. All html files found are placed in a "Table of Contents" like structure, with some indentation per subdirectory. This allows to organize the documentation structure similar to the file structure.

The script will not include the index.html page and the images subdirectory from the root directory, if they are available. This allows for proper formatting.

Make sure you have an images subdirectory with:

=over 4

=item *

greysmallbullet.gif: the symbol to be used as bullet

=back

=head1 DEPENDENCIES

TocGen.pl assumes to work after HtmlDoc.pl. HtmlDoc.pl attempts to create the *.html files in a new subdirectory. The subdirectory will be created only if ther are *.html files to be put into the subdirectory.

As a consequence TocGen.pl assumes that each subdirectory will finally end-up in a *.html file. For each encountered subdirectory, a new entry will be created in the toc.html file. Therefore when mixing up the source directory and the documentation directory, you may end-up with subdirectory trees not ending in any useful documentation. This behaviour is on purpose...

=head1 SYNOPSIS

 TocGen.pl [-t] [-l log_dir] [-s source_dir]

 TocGen.pl -h		Usage information
 TocGen.pl -h 1		Usage information and a description of the options
 TocGen.pl -h 2		Full documentation

=head1 OPTIONS

=over 4

=item B<-t>

enable trace messages if set

=item B<-l log_dir>

Logfile directory, by default: c:\temp

=item B<-s source_dir>

Source directory, by default: c:\perlutils\html

=back

=head1 ADDITIONAL INFORMATION

=cut

###########
# Variables
###########

$sourcedir = "d:/perlutils/html";	    # source directory
$toc = "TOCFILE";			    # Placeholder name
$trace = 0;				    # 0: do not trace, 1: trace
$log = 1;				    # 0: do not log, 1: logging
$logfile = "LOGFILE";			    # Placeholder name
$logdir = "c:/temp/log";			    # Logdirectory
$total_included = 0;			    # number of files included in TOC
$total_dirs = 0;			    # number of directories added to the TOC

# HTML specific settings
$bullet = "<img src=\"images/greysmallbullet.gif\" width=\"5\" height=\"5\" alt=\"*\"> ";
$indent = "&nbsp;&nbsp;&nbsp;&nbsp;";
$target = "target=\"docs\"";
$currind = "";

#####
# use
#####

use Getopt::Std;	    # for input parameter handling
use File::Basename;	    # $0 to basename conversion
use Pod::Usage;		    # Usage printing

#############
# subroutines
#############

sub error($) {
    my($txt) = @_;
    logging("Error in $inpfile: $txt");
}

sub trace($) {
    if ($trace) {
	my($txt) = @_;
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
	print "$datetime - Trace in $0: $txt\n";
    }
}

# SUB - Open LogFile
sub open_log() {
    if ($log == 1) {
	my ($scriptname, undef) = split (/\./, basename($0));
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$logfilename=sprintf(">>$logdir/$scriptname%04d%02d%02d.log", $year+1900, $mon+1, $mday);
	my $openres = open ($logfile, $logfilename);
	if (not($openres)) {
	    error("Could not open logfile $logfilename");
	    exit_application(1);
	}
	# Ensure Autoflush for Log file...
	$old_fh = select($logfile);
	$| = 1;
	select($old_fh);
    }
}

# SUB - Handle Logging
sub logging($) {
    if ($log == 1) {
	my($txt) = @_;
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
	print $logfile $datetime." * $txt"."\n";
    }
}

# SUB - Close log file
sub close_log() {
    if ($log == 1) {
	close $logfile;
    }
}

sub exit_application($) {
    my($return_code) = @_;
    print $toc "</html>";
    close $toc;
    logging("Number of references added to toc: $total_included");
    logging("Number of directories added to toc: $total_dirs");
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

Indent the TOC, because we're in a subdirectory

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

sub walk_through($) {
    my ($directory) = @_;
    my (@dirlist,@filelist);
    my ($entry) = basename($directory);
    print $toc "$currind$entry<br>\n";
    #print $toc "$currind$bullet$entry<br>\n";
    $total_dirs++;
    # New directory, so indent the entries in the toc
    $currind = $currind . $indent;
    if (!(opendir ("$directory", $directory))) {
	error "Opendir $direcory failed!";
    } else {
	@entrylist = readdir("$directory");
	foreach $filename (@entrylist) {
	    my $checkfile = $directory."/$filename";
	    if (-f $checkfile) {
		push @filelist, $filename;
	    } elsif (-d $checkfile) {
		if (("$filename" ne ".") && ("$filename" ne "..")) {
		    push @dirlist, $filename;
		}
	    } else {
		error "Don't know $checkfile\n";
	    }
	}
	closedir $directory;
	my(@sorted_filelist) = sort { lc($a) cmp lc($b) } @filelist;
	my(@sorted_dirlist)  = sort { lc($a) cmp lc($b) } @dirlist;
	foreach $filename (@sorted_filelist) {
	    handle_file("$directory/",$filename);
	}
	foreach $filename (@sorted_dirlist) {
	    walk_through("$directory/$filename");
	}
    }
    # remove the indent that was added in the beginning of this loop.
    $currind = substr($currind, 0, length($currind)-length($indent));
}

=pod

=head2 Scan Dir procedure

The Scan Dir procedure reads all file(types) in the directory. Files and directories are separated. Then Files are ordered (case sensitive) and then submitted one by one to the handle_file procedure.

After this, directories are submitted one by one to the walk_through procedure.

=cut

sub scan_dir($) {
    my ($directory) = @_;
    my (@dirlist, @filelist, @entrylist);
    if (!(opendir ("$directory", $directory))) {
	error "Opendir $direcory failed!";
    } else {
	@entrylist = readdir("$directory");
	foreach $filename (@entrylist) {
	    my $checkfile = $directory."/$filename";
	    if (-f $checkfile) {
		push @filelist, $filename;
	    } elsif (-d $checkfile) {
		if (("$filename" ne ".") && ("$filename" ne "..")) {
		    push @dirlist, $filename;
		}
	    } else {
		error "Don't know $checkfile\n";
	    }
	}
	closedir $directory;
	trace "End of filelist.";
	@sorted_filelist = sort { lc($a) cmp lc($b) } @filelist;
	@sorted_dirlist  = sort { lc($a) cmp lc($b) } @dirlist;
	foreach $filename (@sorted_filelist) {
	    if (($filename ne "toc.html") and ($filename ne "index.html")) {
		handle_file("$directory/",$filename);
	    }
	}
	foreach $filename (@sorted_dirlist) {
	    if ($filename ne "images") {
		walk_through("$directory/$filename");
	    }
	}
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
    $trace = 1;
    trace("Trace enabled");
}
# Find log file directory
if ($options{"l"}) {
    $logdir = $options{"l"};
}
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
    error("Cannot find source directory $pcmdir");
    exit_application(1);
}
while (($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Open new toc.html for writing
$openres = open ($toc, ">$sourcedir/toc.html");
if (not $openres) {
    error("Cannot open $sourcedir/toc.html for writing");
    exit_application(1);
}
# Initialize toc.html
print $toc "<html>\n<div nowrap>\n";

scan_dir($sourcedir);

exit_application(0);

=pod

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
