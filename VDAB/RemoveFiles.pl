=head1 NAME

RemoveFiles - This script will remove all files in a directory that are older than a specific number of days and have known extension.

=head1 VERSION HISTORY

version 1.0 25 August 2009 DV

=over 4

=item *

Initial release, based on Del_Logfiles

=back

=head1 DESCRIPTION

The specified directory is scanned for all files with a known extension (in the suffix list). Each file is evaluated and if modification date is older than 7 days (parameter) then the file is removed.

The C<-r> remove flag must be specified for the files to be removed. Otherwise the application will only list the number of deletions per subdirectory.

=head1 SYNOPSIS

RemoveFiles.pl [-t] [-l log_dir] -d parent_directory [-n number_of_days] [-r]

    RemoveFiles -h		    Usage
    RemoveFiles -h 1	    Usage and description of the options
    RemoveFiles -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: see Log.pm

=item B<-d parent_directory>

Mandatory. The parent directory to find all files to be removed.

=item B<-n number_of_days>

The number of days to retain the logfile. Default: 7 (Keep last week's logfiles).

=item B<-r>

If specified, then the files are actually deleted. Otherwise, the number of files that are eligible for deletion are listed only.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.8.0, build 804 provided by ActiveState.

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $parent_dir, $nr_of_days, $delete_flag, $keep_seconds);
my @suffixlist = (".log", ".png");
my $delcounter = 0;

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use Log;					# Application and error logging
use File::Basename;			# Extract file details

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	logging("$delcounter files deleted from $parent_dir");
    logging("Exit application with return code: $return_code\n");
    close_log();
    exit $return_code;
}

=pod

=head2 Handle File

Check if the file has a modified timestamp older than threshold. Remove file if so.

=cut

sub handle_file($) {
    my ($filename) = @_;
	my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks)=stat($filename);
	if ($mtime < $keep_seconds) {
		if ($delete_flag eq "YES") {
		    my $delfiles = unlink "$filename";
		    if ($delfiles == 1) {
				$delcounter++;
		    } else {
				error("$filename could not be deleted");
		    }
		} else {
		    print "To be deleted: $filename\n";
		    $delcounter++;
		}
	}
}
		

=pod

=head2 Scan Dir

The Scan Dir function scans the directory and evaluates each file in the directory. If the file has a known extension, then the handle_file subdirectory will check to delete the file.

=cut

sub scan_dir($) {
    my ($directory) = @_;
    my (@dirlist);
    if (!(opendir (DIRHANDLE, $directory))) {
		error("Open directory $directory failed!");
    } else {
		@dirlist = readdir(DIRHANDLE);
		closedir(DIRHANDLE);
		foreach my $entry (@dirlist) {
			my $checkentry = $directory . "/$entry";
			my ($checkfile,$checkdir,$checksuffix) = fileparse($checkentry, @suffixlist);
			if (length($checksuffix) > 0) {
				# known extension, so delete file if allowed
				handle_file($checkentry);
			}
		}
    }
}

######
# Main
######

# Handle input values
my %options;
getopts("tl:d:n:r", \%options) or pod2usage(-verbose => 0);
my $arglength = scalar keys %options;  
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
    trace_flag(1);
    trace("Trace enabled");
}
# Find log file directory
if ($options{"l"}) {
    $logdir = logdir($options{"l"});
} else {
    $logdir = logdir();
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
# Find parent directory
if ($options{"d"}) {
    $parent_dir = $options{"d"};
    if (-d $parent_dir) {
	trace("Parent directory: $parent_dir");
    } else {
	error("Invalid parent directory $parent_dir, exiting...");
	exit_application(1);
    }
} else {
    error("Parent directory not specified, exiting...");
    exit_application(1);
}
# Find number of days
if (defined $options{"n"}) {
    $nr_of_days = $options{"n"};
    # Verify if the value is a positive integer
    if (not($nr_of_days =~ /^\d+$/)) {
	error("Number of days is not a positive integer: $nr_of_days, exiting...");
	exit_application(1);
    }
} else {
    $nr_of_days = 7;
}
# Check delete flag
if (defined $options{"r"}) {
    $delete_flag = "YES";
} else {
    $delete_flag = "NO";
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

fileparse_set_fstype("MSWin32");

# Initialize cut-off time to delete files
$keep_seconds = time - ($nr_of_days * 86400);

# Evaluate the directory tree
scan_dir($parent_dir);
	    
exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Nothing so far...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
