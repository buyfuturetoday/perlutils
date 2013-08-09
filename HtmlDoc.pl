=head1 NAME

HtmlDoc.pl - HTML Doc Generator

=head1 VERSION HISTORY

version 1.4 19 October 2003 DV

=over 4

=item *

Include usage of the Log module, to be able to display error messages on screen in case of invalid POD structure.

=back

version 1.3 29 March 2002 DV

=over 4

=item *

Reverse the "-w" Walk through subdirectories logic. Default behaviour is to walk through subdirectories. Specify B<-w> if you do not want to walk through subdirectories.

=back

version 1.3 10 May 2005 DV

=over 4

Add *.cgi as a valid filename to convert

=back

version 1.2 25 March 2002 DV

=over 4

=item *

Add *.pm as a valid filename to convert

=item *

Address an issue with the target path name

=back

version 1.1 19 March 2002 DV

=over 4

=item *

Implement use File::Basename to correct logfilename issue

=back

version 1.0 17 March 2002 DV

=over 4

=item *

Initial Release

=back

=head1 DESCRIPTION

The application generates html files from all *.pl scripts found. It starts from a directory name and walks through all subdirectories. The resulting html files are placed in a specified directory and using the same subdirectory structure as the originating file structure.

If required, the target directory will be created on condition that the target's parent directory exists.

This script is based on the FindFile.pl script.

=head1 SYNOPSIS

 HtmlDoc.pl [-t] [-l log_dir] [-s source_dir] [-d target_dir] [-w]

 HtmlDoc.pl -h		Usage information
 HtmlDoc.pl -h 1	Usage information and a description of the options
 HtmlDoc.pl -h 2	Full documentation

=head1 OPTIONS

=over 4

=item B<-t>

enable trace messages if set

=item B<-l log_dir>

Logfile directory, by default: c:\temp

=item B<-s source_dir>

Source directory, by default: c:\perlutils\lib

=item B<-d target_dir>

Target directory to put the resulting html files, by default: c:\perlutils\html

=item B<-w>

if set, then do not look into subdirectories from the source directory (i.e.: Do not Walk through the directory tree)

=back

=head1 ADDITIONAL INFORMATION

=cut

###########
# Variables
###########

$sourcedir = "d:/perlutils/lib";	    # source directory
$targetdir = "d:/perlutils/html";	    # html target directory
$sourcefile = "SRCFILE";		    # Placeholder name
$targetfile = "ERAFILE";		    # Placeholder name
$logdir;
$converted = 0;				    # number of files converted

#####
# use
#####

use Getopt::Std;	    # for input parameter handling
use Pod::Usage;		    # Usage printing
use Pod::Html;		    # for html generation
use Pod::Checker;	    # for pod checking
use File::Basename;	    # $0 to basename conversion
use Log;		    # Application and error logging

#############
# subroutines
#############

sub exit_application($) {
    my($return_code) = @_;
    close $sourcefile;
    close $targetfile;
    logging("Exit application with return code $return_code\n");
    close_log();
    exit $return_code;
}

=pod

=head2 Handle File Procedure

The file is checked to see if it fulfills the requirements: the file extension must be equal to "pl" or "pm" or "cgi". If so, then:

=over 4

=item *

podchecker module to verify if POD is OK. If POD is not OK for a module, no *.html is generated. Verify the log file on error messages and run I<podchecker> for the *.pl file that fails. 

=item *

calculate targetdirectory

=item *

verify if targetdirectory exists, if not: create targetdirectory. This may require some steps to create the target directory tree. 

=item *

run pod2html from source file to target file.

=back

The number of files found is counted.

=cut

sub handle_file($$) {
    my($directory, $file) = @_;
    my($filename, $fileext) = split(/\./, $file);
    if (($fileext eq "pl") or ($fileext eq "pm") or ($fileext eq "cgi")) {
	# podchecker module to verify if POD is OK
	$syntax_okay = podchecker("$directory/$file", $poderrors, %pod_options);
	if ($syntax_okay > 0) {
	    error("$directory/$file has invalid POD structure");
	    print "$directory/$file has invalid POD structure\n";
	} else {
	    # calculate targetdirectory
	    $rel_source = substr($directory, length($sourcedir));
	    $dest_dir = "$targetdir$rel_source";
	    # verify if targetdirectory exists, if not: create targetdirectory
	    if (not(-d $dest_dir)) {
		$currtree = $targetdir;
		trace("$dest_dir does not exists");
		$subtree_end = index($dest_dir, "/", length($currtree)+1);
		while ($subtree_end > -1) {
		    $currtree = substr($dest_dir,0,$subtree_end);
		    trace("Creating subdir: $currtree");
		    if (not(-d $currtree)) {
			if (mkdir ($currtree, 0)) {
			    logging("$currtree has been created");
			} else {
			    error("$currtree could not be created");
			    exit_application(1);
			}
		    }
		    $subtree_end = index($dest_dir, "/", length($currtree)+1);
		}
		trace("Creating subdir: $dest_dir");
		if (not(-d $dest_dir)) {
		    if (mkdir ($dest_dir, 0)) {
			logging("$dest_dir has been created");
		    } else {
			error("$dest_dir could not be created");
			exit_application(1);
		    }
		}
	    }
	    # run pod2html from source file to target file.
	    pod2html("--backlink=Back to Top",
		     "--header",
		     "--infile=$directory/$file",
		     "--outfile=$dest_dir/$filename.html");
	    $converted++;
	    logging("$directory/$file is converted to $dest_dir/$filename.html");
	}
    }
}

=pod

=head2 Walk through procedure

This procedure walks through a subdirectory, if required (if the -w flag was not specified). It checks each filename. In case there are subdirectories of the subdirectory, then the "walk_through" procedure is called recursively.

=cut

sub walk_through($) {
    my ($directory) = @_;
    my (@dirlist);
    my ($size) = 0;
    if (!(opendir ("$directory", $directory))) {
	error "Opendir $direcory failed!";
    } else {
	@dirlist = readdir("$directory");
	trace "walk_through Directory list for $directory:";
	foreach $filename (@dirlist) {
	    my $checkfile = $directory."/$filename";
	    if (-d $checkfile) {	# if here: always interested in subdirs
		if (("$filename" ne ".") && ("$filename" ne "..")) {
		    trace "walk_through Directory: $filename";
		    walk_through($checkfile);
		}
	    } elsif (-f $checkfile) {
		handle_file($directory, $filename);
	    } else {
		error "walk_through Don't know $checkfile\n";
	    }
	}
    }
}

=pod

=head2 Scan Dir procedure

The Scan Dir procedure scans through the directory and checks for each file name if it fulfills the requirements. If so, then the Handle File procedure is called.

If the directory has subdirectories, then these are investigated as well if requested during startup.

=cut

sub scan_dir($) {
    my ($directory) = @_;
    my (@dirlist);
    if (!(opendir ("$directory", $directory))) {
	error "Opendir $direcory failed!";
    } else {
	@dirlist = readdir("$directory");
	foreach $filename (@dirlist) {
	    my $checkfile = $directory."/$filename";
	    if (-d $checkfile) {
		if ($walk == 1) {	    # interested in subdirs?
		    if (("$filename" ne ".") && ("$filename" ne "..")) {
			trace "Directory: $filename";
			walk_through($checkfile);
		    }
		}
	    } elsif (-f $checkfile) {
		handle_file($directory, $filename);
	    } else {
		error "Don't know $checkfile\n";
	    }
	}
	trace "End of filelist.";
	closedir $directory;
    }
}


######
# Main
######

# Handle input values
getopts("tl:s:d:wh:", \%options) or pod2usage(-verbose => 0);
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
    $logdir = logdir($options{"l"});
    if (not(defined $logdir)) {
	error("Could not set $logdir as Log directory, exiting...");
	exit_application(1);
    }
} else {
    $logdir = logdir();
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
# Find target directory
if ($options{"d"}) {
    $targetdir = $options{"d"};
}
if (-d $targetdir) {
    trace("Target Directory: $targetdir");
} else {
    if (mkdir ($targetdir, 0)) {
	logging("$targetdir has been created");
    } else {
	error("$targetdir could not be created");
	exit_application(1);
    }
}
# Walk through subdirectories
if (defined $options{"w"}) {
    $walk = 0;
} else {
    $walk = 1;
}
while (($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Display POD errors in pop-up window.
Log::display_flag(1);

$poderrors = "/dev/null";

scan_dir($sourcedir);

exit_application(0);

=pod

=head1 TO DO

=over 4

=item *

Verify if there is any documentation at all. Currently if there is no documentation, a *.html file is created consisting of a header and a footer only. 

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
