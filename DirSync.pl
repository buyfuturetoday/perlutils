=head1 NAME

DirSync - Directory Synchronization

=head1 VERSION HISTORY

version 1.3 - 19 January 2008 DV

=over 4

=item *

Update walkthrough procedure to cope with symbolic links in Vista. As a consequence failures to open directories will be logged only, no longer result in an error message.

=back

version 1.2 - 08 Augustus 2007 DV

=over 4

=item *

Add flag to prevent report display. This allows to run program for a number of directories and only display report on the last run.

=back

version 1.1 - 28 Augustus 2006 DV

=over 4

=item *

Added Modification time check. Note that the File size check should not be used for now, as this function has not been tested and may be removed in a later release.

=back

version 1.0 - 18 October 2003 DV

=over 4

=item *

Initial Release

=back

=head1 DESCRIPTION

This application allows to synchronize directories. It reads all files (including subdirectories) from a source directory and verifies if the file exist on the target directory. 

If the file does not exist, then it is copied to the target directory.

If the file exists, then it is copied if the file on the source is younger than the file on the target and if the size of the source file is bigger than the target file size. Otherwise the file is listed to an exception report.

The application walks through all subdirectories from the source directory. If there is a source directory, then it will be created on the target system.

A report is created with the files eligible for copying. The report is a *.html file that points to the eligible files. The pointer is to the target directory (for a production run) or to the source directory otherwise. There will be one report per day, with the date in the report's file name.

=head1 SYNOPSIS

 DirSync.pl [-t] [-l logfile_directory]  [-d Source_directory] [-T Target_directory] [-P] [-W] [-S] [-A] [-r]

 DirSync.pl -h		Usage Information
 DirSync.pl -h 1	Usage Information and Options description
 DirSync.pl -h 2	Full documentation

=head1 OPTIONS

=over 4

=item B<-t>

if set, then trace messages will be displayed. 

=item B<-l logfile_directory>

default: c:\temp

=item B<-d Source_directory>

Source Directory, containing the master files.

=item B<-T Target_directory>

Target Directory, should be a copy of the source.

=item B<-P>

Production run. Must be specified for the files to be copied. Otherwise only a report is generated indicating which files would have been copied. Should not be specified on a first run.

=item B<-W>

Walkthrough. If set, then subdirectories are scanned as well. If omitted, then the subdirectories are ignored. Should be specified on a first run.

=item B<-S>

Check Size. If set, then files are compared on filesize. Bigger files on the source are copied to the target. Smaller files are notified. Equal file sizes are ignored.

=item B<-A>

Check access time. If set, then files are compared on last access time. More recent access times on the source are copied to the target. Equal file access times are ignored.

=item B<-r>

If specified, then end-report will not be displayed.

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
###########

my $sourcedirectory = "c:/temp/source";	# Directory to scan
my $targetdirectory = "c:/temp/target";	# Target Directory
my ($logdir,$htmlfilename,$display_report);
my ($production,$walkthrough,$bigsize,$tagname,$bgcolor,$accesstime);	
my $size=0;
my $copycount=0;
my $filecount=0;
my $browser_exe="c:/program files/internet explorer/iexplore.exe"; # Browser Executable

#####
# use
#####

use warnings;			    # show warnings
use strict 'vars';
use strict 'refs';
use strict 'subs';
use File::stat;			    # File properties
use File::Copy;			    # File copy command
use Getopt::Std;		    # Input parameter handling
use Pod::Usage;			    # Usage printing
use File::Basename;		    # For logfilename translation
use Log;

#############
# subroutines
#############

sub exit_application($) {
    my($return_code) = @_;
    if ($return_code == 0) {
	if (defined $production) {
	    # print "$copycount files copied, $size bytes in total";
	    logging ("$copycount files copied, $size bytes in total");
	} else {
	    # print "$copycount files will be copied, $size bytes in total";
	    logging("$copycount files will be copied, $size bytes in total");
	}
    }
    logging("Exit application with return code $return_code\n");
    close_log();
    if ($return_code == 0) {
	display_report();	    # Special function to format and print display report
    }
    exit $return_code;	    # This code will never be reached due to the exec in the display report.
}

=pod

=head2 Display Report

The Display Report procedure add the "Close-of-table" formatting and adds an end-of-report formatting. If the browser executable is found, then the browser is started to display the report in a browser window.

=cut

sub display_report() {
    # End-format html report
    print HTMLFILE "</table>\n";
    print HTMLFILE "<p><b>Summary:</b><br>\n";
    print HTMLFILE "<ul>\n";
    print HTMLFILE "<li><b>$filecount</b> files have been investigated\n";
    print HTMLFILE "<li><b>$copycount</b> files eligible\n";
    print HTMLFILE "<li><b>$size</b> bytes in total\n";
    print HTMLFILE "</ul>\n";
    close HTMLFILE;
    # Display report
    if (not defined $display_report) {
	if (-x $browser_exe) {
	   exec("\"$browser_exe\" $htmlfilename#$tagname");
	}
    }
}

=pod

=head2 Copy File

In case the $production flag is set, then the file is copied to the target directory. Otherwise only some reporting is done. This will allow to set-up proper reporting (including html files?).

=cut

sub copy_file($$$$) {
    my ($sourcefile,$targetfile,$filesize,$reason)=@_;
    logging "Copying $sourcefile";
    $size=$size+$filesize;
    $copycount++;
    my $htmllink=$sourcefile;
    if (defined($production)) {
        my $copyres=copy("$sourcefile","$targetfile");
        if ($copyres == 0) {
	    error "Could not copy $sourcefile into $targetfile";
	} else {
	    $htmllink=$targetfile;	
	}
    }	
    print HTMLFILE "<tr><td><a href=\"$htmllink\">$sourcefile</a><td align='right'>$filesize<td align='center'>$reason</tr>\n";
}

=pod

=head2 Scan Source procedure

The Scan Source procedure scans through the source directory and reads all files. For every file, it checks if the file exist on the target. If not, the file is copied to the target. 

If the file exists on the target, then the file is copied from the source to the target only if the source file is newer and the source file is bigger than the target. 

The test and error message on 'opendir' failure has been removed and replaced by a 'simple' logging. This is to cope with an Vista setting, where "Mijn Afbeeldingen", "Mijn muziek" en "Mijn Video's" still exists as a hidden symbolic link (for compatibility reasons), but is no longer available as a directory. 

=cut

sub scan_source($$) {
    my ($sourcedir,$targetdir)=@_;
    my (@dirlist);
    if (not(opendir (SOURCEDIR, $sourcedir))) {
	logging "Opendir $sourcedir failed!";
    } else {
	@dirlist=readdir(SOURCEDIR);
	foreach my $filename (@dirlist) {
	    if (("$filename" ne ".") and ("$filename" ne "..")) {
		my $sourcefile="$sourcedir/$filename";
		my $targetfile="$targetdir/$filename";
		if (-d $sourcefile) {
		    if (defined $walkthrough) {
			# Investigate Subdirectory
			walk_through($sourcefile,$targetfile);
		    }
		} elsif (-f $targetfile) {	# $sourcefile not a directory, must be a file
		    $filecount++;
		    if (defined $bigsize) {
		    # File exists, additional checks will be implemented later
			my $sb=stat($sourcefile);
			my $tb=stat($targetfile);
			my $source_size=$sb->size;
			my $target_size=$tb->size;
			if ($target_size > $source_size) {
			    error("Investigate $sourcefile - file modified but size smaller than $targetfile");
			} elsif ($target_size < $source_size) {
			    copy_file($sourcefile,$targetfile,$source_size,"File Size Increased");
			}
		    }
		    if (defined $accesstime) {
			my $sb=stat($sourcefile);
			my $tb=stat($targetfile);
			my $source_size=$sb->size;
			if ($sb->mtime > $tb->mtime) {
			    copy_file($sourcefile,$targetfile,$source_size,"Source File updated");
			}
		    }
		} else {
		    # File does not exist, must be copied
		    $filecount++;
		    my $sb=stat($sourcefile);
		    copy_file($sourcefile,$targetfile,$sb->size,"New File");
		}
	    }
        }
    }
}

=pod

=head2 Walk Through

If the subdirectory does not exist and the production flag is set, then create the subdirectory. Call scan_source to walk through subdirectory.

=cut

sub walk_through($$) {
    my ($sourcefile,$targetfile)=@_;
    if (defined $production) {
	if (not(-d $targetfile)) {
	    my $mkdirres=mkdir($targetfile);
	    if (not($mkdirres)) {
		error("Could not create subdirectory $targetfile, errorno: $!");
	    }
	}
    }
    scan_source($sourcefile,$targetfile);
}

######
# Main
######

# Handle input values
my %options;
getopts("d:l:th:T:PWSAr", \%options) or pod2usage(-verbose => 0);
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
Log::display_flag(1);
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
# Find source directory
if ($options{"d"}) {
    $sourcedirectory = $options{"d"};
}
if (-d $sourcedirectory) {
    trace("Source Directory: $sourcedirectory");
} else {
    error("Cannot find directory to scan $sourcedirectory.\n");
    exit_application(1);
}
# Find target directory
if ($options{"T"}) {
    $targetdirectory = $options{"T"};
}
if (-d $targetdirectory) {
    trace("Target Directory: $targetdirectory");
} else {
    error("Cannot find target directory $targetdirectory.\n");
    exit_application(1);
}
# Check for Production Run
if ($options{"P"}) {
    $production = "YES";
} else {
    undef $production;
}
# Check for Walkthrough
if ($options{"W"}) {
    $walkthrough="YES";
} else {
    undef $walkthrough;
}
# Check for File Size difference
if ($options{"S"}) {
    $bigsize="YES";
} else {
    undef $bigsize;
}
# Check for Access Time
if ($options{"A"}) {
    $accesstime = "YES";
} else {
    undef $accesstime;
}
# Check for Report display
if ($options{"r"}) {
    $display_report = "No";
} else {
    undef $display_report;
}
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

error("Backup applicatie is gestart, wacht nu op resultaat scherm! (Kan lang duren...)");

# Initialize copy report in html format
my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$htmlfilename=sprintf("$logdir/SyncReport%04d%02d%02d.html",$year+1900,$mon+1,$mday);
my $openres=open(HTMLFILE,">>$htmlfilename");
my $title=sprintf("New files (%02d:%02d:%02d)",$hour,$min,$sec);
$tagname=sprintf("%02d:%02d:%02d",$hour,$min,$sec);
if (defined $production) {
    $bgcolor="#AFFFCC";
} else {
    $bgcolor="#FFAFCC";
    $title=$title." - <i>Preview</i>";
}
my $filesizecheck="disabled";
if (defined $bigsize) {
    $filesizecheck="enabled";
}
my $fileagecheck="disabled";
if (defined $accesstime) {
    $fileagecheck="enabled";
}
my $walkthroughstatus="disabled";
if (defined $walkthrough) {
    $walkthroughstatus="enabled";
}
print HTMLFILE "<a name=\"$tagname\"></a><h3>$title</h3>\n\n";
print HTMLFILE "Filesize check is <b>$filesizecheck</b>.<br>\n";
print HTMLFILE "Scan Subdirectories is <b>$walkthroughstatus</b>.<br>\n";
print HTMLFILE "Access Time check is <b>$fileagecheck</b>.<p>\n";
print HTMLFILE "<table bgcolor='$bgcolor' border width='100%' cellpadding=2>\n";
print HTMLFILE "<tr><th width='74%'>Filename<th width='13%'>Size (bytes)<th width='13%'>Reason</tr >\n";

scan_source($sourcedirectory,$targetdirectory);

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Automatically open *.html report at the end of the application.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>

