=head1 NAME

FindFile.pl - Finds all occurences of files that fulfill a search pattern.

=head1 VERSION HISTORY

=over 4

=item *

Implement use File::Basename for log file name processing

=back

version 1.0 - 13 March 2002 DV

=over 4

=item *

Initial Release

=back

=head1 DESCRIPTION

This application allows to find all occurences of files that fulfill the search pattern. The search can be limited to the current directory or it can walk through all subdirectories.

The search pattern must include a string and it can include a date. Regular Expressions (such as: Look for file names starting with "azerty") are not included. The search string can appear anywhere in the file name. 

It is also possible to specify an extension, in which case the filenames must have the extension as specified.


=head1 USAGE

=over 4

=item *

-d "directory": Directory to start looking for files, default: c:\temp

=item *

-w: Walk through the subdirectories, default: no

=item *

-s "String": search string that must occur in the filename

=item *

-n I<number>: number of days to go back, '-n 1': go back one day, '-n -1': tomorrow. Date is always in the format YYYYMMDD. '-n 0' is not possible, use '-T' instead.

=item *

-T: Today's date must be part of the file name.

=item *

-e "Extension": if specified, then the file must have the extension as specified.

=item *

-l "log_file_directory", default: c:\temp

=item *

-t: if set, then trace messages will be displayed. 

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
###########

$srcdir = "c:/temp";		    # Start Directory for the search
$found = 0;			    # Counts the number of files found
$walk = 0;			    # 0: don't walk through subdirs, 1: walkthrough
$trace = 0;			    # 0: no tracing, 1: tracing
$logdir = "c:/temp";		    # Log file directory
$log = 1;			    # 0: no logging, 1: logging
$logfile = "LOGFILE";		    # Placeholder

#####
# use
#####

use Getopt::Std;
use File::Basename;		    # For logfile name processing

#############
# subroutines
#############

sub error($) {
    my($txt) = @_;
    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
    print "$datetime - Error: $txt\n";
    logging("Error: $txt");
}

sub trace($) {
    if ($trace) {
	my($txt) = @_;
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
	print "$datetime - Trace: $txt\n";
    }
}

# SUB - Open LogFile
sub open_log() {
    if ($log == 1) {
	my($scriptname, undef) = split(/\./, basename($0));
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$logfilename=sprintf(">>$logdir/$scriptname%04d%02d%02d.log", $year+1900, $mon+1, $mday);
	open ($logfile, $logfilename);
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
    logging("Exit application with return code $return_code\n");
    close_log();
    exit $return_code;
}

=pod

=head2 Handle File Procedure

The file is checked to see if it fulfills the requirements. If so, the filename, including the path, is printed to the log file.

The number of files found is counted.

=cut

sub handle_file($$) {
    my($directory, $file) = @_;
    my($filename, $fileext) = split(/\./, $file);
    if (defined $incstr) {
	if (index($filename,$incstr) == -1) {
	    return;	    # File name not OK - stop searching
	}
    }
    if (defined $incdate) {
	if (index($filename,$incdate) == -1) {
	    return;	    # Date not OK - stop searching
	}
    }
    if (defined $incext) {
	if ($fileext ne $incext) {
	    return;	    # Extension not OK - stop searching
	}
    }
    $found++;
    logging("$directory/$file is OK!");
    trace("$directory/$file is OK!");
}

=pod

=head2 Walk through procedure

This procedure walks through a subdirectory, if required. It checks each filename. In case there are subdirectories of the subdirectory, then the "walk_through" procedure is called recursively.

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
	    if ((-d $checkfile) and ($walk == 1)) {	    # interested in subdirs?
		if (("$filename" ne ".") && ("$filename" ne "..")) {
		    trace "Directory: $filename";
		    walk_through($checkfile);
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
getopts("d:ws:Tn:e:l:t", \%options) or die "getopts failed - $!";
# Trace required?
if ($options{"t"}) {
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
# Find search directory
if ($options{"d"}) {
    $srcdir = $options{"d"};
}
if (-d $srcdir) {
    trace("Search Directory: $srcdir");
} else {
    error("Cannot find directory to scan $srcdir");
    exit_application(1);
}
# Walk through subdirs
if ($options{"w"}) {
    $walk = 1;
}
# Search string
if ($options{"s"}) {
    $incstr = $options{"s"};
}
# Dates
if ($options{"n"}) {
    $searchtime = time - ($options{"n"} * 86400);
    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($searchtime);
    $incdate = sprintf ("%04d%02d%02d",$year+1900, $mon+1, $mday);
}
if ($options{"T"}) {
    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    $incdate = sprintf ("%04d%02d%02d",$year+1900, $mon+1, $mday);
} 
# Extension
if ($options{"e"}) {
    $incext = $options{"e"}
}
if ((not(defined $incstr)) and 
    (not(defined $incdate)) and 
    (not(defined $incext))) {
    error("A search string (-s) or number of days (-n) or extension (-e) must be specified!");
    exit_application(1);
}
logging("Investigating $srcdir for $incstr - $incdate - $incext - walk: $walk");
trace("Investigating $srcdir for $incstr - $incdate - $incext - walk: $walk");
# End handle input values

scan_dir($srcdir);
logging("$found files found!");
trace("$found files found!");
exit_application(0);

=pod

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
