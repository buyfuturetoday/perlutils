=head1 NAME

md5_check.pl - Calculate the checksum of files from directory and subdirectories.

=head1 VERSION HISTORY

version 1.1 1 May 2002 DV

=over 4

=item *

Standardize script: convert documentation to pod format, add usage information, ...

=back

version 1.0 2 May 2000 DV

=over 4

=item *

Initial release

=back

=head1 DESCRIPTION

This application is used to calculate the MD5 checksum of files, starting from a directory and including all subdirectories. The files are sorted, the checksums are written into a file in the output directory (default: c:\temp). 

Its primary purpose is to check the validity of CD's by comparing the resulting MD5 files as created from the hard disk and from the CD drive.

=head1 SYNOPSIS

 md5_check.pl [-t] [-l log_dir] -s source_dir [-d target_dir] [-n md5_filename]

 md5_check.pl -h	    Usage information
 md5_check.pl -h 1	    Usage information and a description of the options
 md5_check.pl -h 2	    Full documentation

=head1 OPTIONS

=over 4

=item B<-t>

enable trace messages if set

=item B<-l log_dir>

Logfile directory, by default: c:\temp

=item B<-s source_dir>

Source directory containing the files and the subdirectories that need verification. This must be specified, there is no default.

If the source directory is a file, then the MD5 checksum for the file is calculated and printed on STDOUT.

=item B<-d target_dir>

Target directory where the summary file will be placed, by default: c:\temp

=item B<-n md5_filename>

Name of the file containing all filenames and checksums. This is mandatory in case a directory has been specified. It is ignored if the source is a file. The filename will be preceded with "md5_" and ".txt" is appended. Typically the source directory is called "original" and the CD directory is called "backup" or "cd".

=back

=head1 ADDITIONAL INFORMATION

=cut

###########
# Variables
###########

$targetdir = "c:/temp";			    # MD5 results output directory
$sourcefile = "SRCFILE";		    # Placeholder name
$targetfile = "MD5FILE";		    # Placeholder name
$trace = 0;				    # 0: do not trace, 1: trace
$log = 1;				    # 0: do not log, 1: logging
$logfile = "LOGFILE";			    # Placeholder name
$logdir = "c:/temp";			    # Logdirectory
$md5_count = 0;				    # number of files evaluated

#####
# use
#####

use Getopt::Std;	    # for input parameter handling
use Pod::Usage;		    # Usage printing
use File::Basename;	    # $0 to basename conversion
use Digest::MD5;	    # use md5 conversion function

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
    close $sourcefile;
    close $targetfile;
    logging("Exit application with return code $return_code\n");
    close_log();
    exit $return_code;
}

=pod

=head2 calc_checksum procedure

The procedure opens the file in variable $checkfile and puts the filehandle in binmode. If the file to be investigated cannot be opened,the application halts with a "die" message.

The MD5 checksum is calculated using the Digest module. The checksum and the filename are appended to the output file (which is STDOUT in case the checksum of only one file was required).

=cut

sub calc_checksum() {
  open(FILE, $checkfile) or die "Can't open '$checkfile': $!";
  binmode(FILE);
  $checksum = Digest::MD5->new->addfile(*FILE)->hexdigest;
  print MD5_Result "$checksum, $filename\n";
  print ".";
  close FILE;
}

=pod

=head2 read_dir procedure

Start from directoryname. Read the directory and sort the entries. 

If the entry is a subdirectory, then the read_dir procedure is called again, if the directory name is not '.' or '..'.

If the entry is a filename then the checksum of the file is calculated.

If the entry is not a directory or a filename, then an error message "Unknown file type" is displayed in the error log.

=cut

sub read_dir($) {
  my ($directory) = @_;
  my (@dirlist);
  if (!(opendir ("$directory", $directory))) {
    error "Opendir failed!";
  }
  @dirlist = sort readdir("$directory");
  trace "Directory list for $directory:\n";
  foreach $filename (@dirlist) {
    $checkfile = $directory."\\$filename";
    if (-d $checkfile) {
      if (("$filename" ne ".") && ("$filename" ne "..")) {
        trace "Directory: $filename\n";
        read_dir($checkfile);
      }
    } elsif (-f $checkfile) {
      trace $checkfile."\n";
      calc_checksum();
    } else {
      error "Don't know $checkfile\n";
    }
  }
  trace "End of filelist.\n";
  closedir $directory;
}

######
# Main
######

# Handle input values
getopts("tl:s:d:n:h:", \%options) or pod2usage(-verbose => 0);
$arglength = scalar keys %options;  
if ($arglength == 0) {			# If no options specified,
    $options{"h"} = 0;			# display usage.
}
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
    $sourcedirectory = $options{"s"};
}
if (-d $sourcedirectory) {
    trace("Source Directory: $sourcedirectory");
} elsif (-f $sourcedirectory) {
    trace("Source File $sourcedirectory");
} else {
    error("Cannot find source directory $sourcedirectory");
    exit_application(1);
}
# Find target directory
if ($options{"d"}) {
    $targetdir = $options{"d"};
} else {
    $targetdir = "c:\\temp";
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
if ($options{"n"}) {
    $source = $options{"n"};
} elsif (-d $sourcedirectory) {
    error("md5_filename is not defined!");
    exit_application(1);
}
while (($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values
#$$$$$$ Output directory is not yet defined
#$$$$$$ Continue to work from here...
if (-d $sourcedirectory) {
  $outputfile = ">$targetdir\\md5_$source.txt";
  open (MD5_Result, $outputfile);
  read_dir($sourcedirectory);
  close MD5_Result;
} elsif (-f $sourcedirectory) {
  $outputfile = ">&STDOUT";
  open (MD5_Result, $outputfile);
  $checkfile = $sourcedirectory;
  $filename = $sourcedirectory;
  calc_checksum;
  close MD5_Result;
} else {
  error ("The file or directory input parameter is no longer...");
}
 
=pod

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
