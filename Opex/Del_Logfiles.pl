=head1 NAME

Del_Logfiles - Find all LOG subdirectories and remove the logfiles older than a specific number of days.

=head1 VERSION HISTORY

version 1.0 16 May 2003 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application accepts a parent directory and find all the B<LOG> subdirectories. In each log subdirectory, all logfiles older than a specific number of days are deleted. Logfile names must use the format I<nameYYYYMMDD.log>. The decision to delete the files is based on the filename, not on the file creation or modification time stamps.

Note that LOG subdirectories are not further investigated. However the B<LOG> directory itself must be a subdirectory, it cannot be the parent directory.

The C<-r> remove flag must be specified for the files to be removed. Otherwise the application will only list the number of deletions per subdirectory.

=head1 SYNOPSIS

Del_Logfiles.pl [-t] [-l log_dir] -d parent_directory [-n number_of_days] [-r]

    Del_Logfiles -h	    Usage
    Del_Logfiles -h 1	    Usage and description of the options
    Del_Logfiles -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: c:\temp

=item B<-d parent_directory>

Mandatory. The parent directory to find all LOG subdirectories.

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

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use Log;			    # Application and error logging
use Time::Local;

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
    logging("Exit application with return code: $return_code\n");
    close_log();
    exit $return_code;
}

=pod

=head2 Handle Log Directory

Scan through the log directory. Check if the entry is a file. If so, then check if the file extension is B<.log>. If so, check if the date field before the extension indicates that the file is older than the required number of days. If so, delete the file. Otherwise, look at the next entry.

=cut

sub handle_log_dir($) {
    my ($directory) = @_;
    my (@dirlist);
    my $ext = ".log";
    if (!(opendir (DIRHANDLE, $directory))) {
	error("Open directory $directory failed!");
    } else {
	@dirlist = readdir(DIRHANDLE);
	closedir(DIRHANDLE);
	my $delcounter=0;
	my $nbr_of_files = @dirlist;
	$nbr_of_files = $nbr_of_files - 2;	# . and .. should not be counted as files
	foreach my $entry (@dirlist) {
	    # Extension must be .log
	    if (substr($entry,length($entry)-length($ext),length($ext)) eq $ext) {
		# Extract date from filename
		my $date = substr($entry,length($entry)-length($ext)-length("YYYYMMDD"),length("YYYYMMDD"));
		# Date must be numeric
		if ($date =~ /^\d+$/) {
		    my $year  = substr($date,0,4);
		    my $month = substr($date,4,2) - 1;
		    my $day   = substr($date,6,2);
		    my $date_seconds = timelocal(0,0,0,$day,$month,$year);
		    if ($date_seconds < $keep_seconds) {
			if ($delete_flag eq "YES") {
			    my $delfiles = unlink "$directory/$entry";
			    if ($delfiles == 1) {
				$delcounter++;
			    } else {
				error("$directory/$entry could not be deleted");
			    }
			} else {
			    print "To be deleted: $directory/$entry\n";
			    $delcounter++;
			}
		    }
		}
	    }
	}
	logging("$directory - $delcounter files deleted out of $nbr_of_files files in total");
    }
}
		

=pod

=head2 Scan Dir

The Scan Dir function scans the directory and evaluates each entry. If a LOG subdirectory is found, then the handle_log_dir procedure is executed. If the entry is another subdirectory, then this is searched as well for LOG subdirectories (unless it is the . or .. subdirectory.

Any other entry is ignored.

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
	    if (-d $checkentry) {
		if (uc($entry) eq "LOG") {	    # Log entry is case insensitive
		    handle_log_dir($checkentry);
		} else {
		    if (("$entry" ne ".") and ("$entry" ne "..")) {
			# Call function with & to avoid early prototype declaration
			&scan_dir($checkentry);
		    }
		}
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
