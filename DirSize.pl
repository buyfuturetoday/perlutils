=head1 NAME

DirSize.pl - Calculate the size of directories, including all subdirectories

=head1 VERSION HISTORY

version 1.3 - 19 March 2002 DV

=over 4

=item *

Introduce use File::Basename to resolve logfilename resolution when script is not running from its own directory

=back

version 1.2 - 18 March 2002 DV

=over 4

=item *

Work on a bug for size calculation.

=item *

Include Usage information

=back

version 1.1 - 12 March 2002 DV

=over 4

=item *

Include POD

=item *

Use the standard input variables.

=item *

Change \\ to / in filenames to have compatibility with UNIX systems.

=back

version 1.0 - 13 August 2001 DV

=over 4

=item *

Initial Release

=back

=head1 DESCRIPTION

In case of a lack of disk space, this application allows to quickly find which directory is using most of the disk space. This helps to understand which directories to clean up. 

The disk size is printed in reverse numerical order. This means that the biggest file or sub-directory is printed last. This helps if too many entries scroll too fast over the screen: you only want to  know about the biggest one.

This application can also be used as an example of hash lists and recursive subroutine calls.

=head1 SYNOPSIS

 DirSize.pl [-t] [-d Source_directory] [-l logfile_directory]
 
 DirSize.pl -h		Usage Information
 DirSize.pl -h 1	Usage Information and Options description
 DirSize.pl -h 2	Full documentation

=head1 OPTIONS

=over 4

=item B<-d Source_directory>

Directory to calculate the disk space per subdirectory or file, default: c:\temp

=item B<-l logfile_directory>

default: c:\temp

=item B<-t>

if set, then trace messages will be displayed. 

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
###########

$sourcedirectory = "c:/temp";	    # Directory to scan
$trace = 0;			    # 0: no tracing, 1: tracing
$logdir = "c:/temp";		    # Log file directory
$log = 1;			    # 0: no logging, 1: logging
$logfile = "LOGFILE";		    # Placeholder

#####
# use
#####

use File::stat;			    # File properties
use Getopt::Std;		    # Input parameter handling
use Pod::Usage;			    # Usage printing
use File::Basename;		    # For logfilename translation

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

=head2 Walk through procedure

This procedure walks through a subdirectory. It adds up the file size of each file. In case there are subdirectories of the subdirectory, then the "walk_through" procedure is called recursively.

The end result is the total size of the subdirectory.

=cut

sub walk_through($) {
    my ($directory) = @_;
    my (@dirlist);
    if (!(opendir ("$directory", $directory))) {
	error "Opendir $direcory failed!";
    } else {
	@dirlist = readdir("$directory");
	foreach $filename (@dirlist) {
	    my $checkfile = $directory."/$filename";
	    if (-d $checkfile) {
		if (("$filename" ne ".") && ("$filename" ne "..")) {
		    walk_through($checkfile);
		}
	    } elsif (-f $checkfile) {
		$sb = stat($checkfile);
		$size = $sb->size + $size;
		print ".";
	    } else {
		error "walk_through Don't know $checkfile\n";
	    }
	}
    }
}

=pod

=head2 Read Dir procedure

The read_dir subdirectory reads the contents of the directory to scan. For each entry verify the file type. We are interested in file types 'directory' and 'file' only, other file types are ignored for now.

If the file type is a 'file', then the file size is extracted.

If the file type is a directory, then the walk_through subdirectory is called to calculate the size of the sub-directory. 

The size is the key in a hash table. If the key does not exist, then it is added with the filename or subdirectory name as value. If the key exists, then the filename or subdirectory name is appended to the existing value.

=cut

sub read_dir($) {
    my ($directory) = @_;
    my (@dirlist);
    if (!(opendir ("$directory", $directory))) {
	error "Opendir $direcory failed!";
    } else {
	@dirlist = readdir("$directory");
	foreach $filename (@dirlist) {
	    my $checkfile = $directory."/$filename";
	    if (-d $checkfile) {
		if (("$filename" ne ".") && ("$filename" ne "..")) {
		    $size = 0;
		    print "\n".$checkfile;
		    walk_through($checkfile);
		    if (defined $hashlist{$size}) {
			$hashlist{$size} = $hashlist{$size} . " * " . $checkfile;
		    } else {
			$hashlist{$size} = $checkfile;
		    }
		}
	    } elsif (-f $checkfile) {
		print "\n".$checkfile;
		$sb = stat($checkfile);
		$size = $sb->size;
		if (defined $hashlist{$size}) {
		    $hashlist{$size} = $hashlist{$size} . " * " . $checkfile;
		} else {
		    $hashlist{$size} = $checkfile;
		}
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
while (($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

read_dir($sourcedirectory);
@sortkeys = sort {$a <=> $b} keys %hashlist;	    # Sort numerically
foreach $kdir (@sortkeys) {
    logging("$kdir - $hashlist{\"$kdir\"}");
    trace("$kdir - $hashlist{\"$kdir\"}");
}
exit_application(0);

=pod

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
