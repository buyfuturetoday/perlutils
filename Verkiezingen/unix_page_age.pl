=head1 NAME

unix_page_age.pl - Get the age of a unix page to verify frequent rsync update.

=head1 VERSION HISTORY

version 1.0 29 September 2006 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will get a unix page and verify the date stamp in the page. The date stamp must be different then previous date stame. This can be used to verify that rsync is doing regular updates.

The last modified time of the URL must be more recent then the previous read last modified time. No local processing of the last modified time is done, since there is no control on the time synchronisation of the remote system.

=head1 SYNOPSIS

 unix_page_age.pl [-t] [-l log_dir] -f system-page_file [-m event-manager]

 unix_page_age.pl -h	    Usage
 unix_page_age.pl -h 1   Usage and description of the options
 unix_page_age.pl -h 2   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-f system-page_file>

This file has system/page file and timestamp pairs. If an item needs to be added to the list, then the B<system,file-location> can be added to the file. The application will recognize the new item and will not trigger an initial alarm. Items that no longer need to be verified can be removed from the file.

Note that the application will rewrite the file on each run, so no comments should be added to the file. Also items should be added / removed only when the application is not running.

For now the system and the page must be unique.

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# variables
###########

my $trace = 0;				# 0: do not trace, 1: trace
my $log = 1;				# 0: do not log, 1: logging
my ($page_file, $eventmgr, $logdir, %pages, %new_pages);
my $tempdir = "c:/temp";


#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use Log;
use OpexAccess;
use File::Basename;

#############
# subroutines
#############

sub exit_application($) {
    my($return_code) = @_;
    logging("Exit application with return code $return_code.\n");
    close_log();
    exit $return_code;
}

=pod

=head2 Trim

This section is used to get rid of leading or trailing blanks. It has been
copied from the Perl Cookbook.

=cut

sub trim {
    my @out = @_;
    for (@out) {
        s/^\s+//;
        s/\s+$//;
    }
    return wantarray ? @out : $out[0];
}

=pod

=head2 Execute Command

This procedure accepts a system command, executes the command and checks on a 0 return code. If no 0 return code, then an error occured and control is transferred to the Display Error procedure.

=cut

sub execute_command($) {
    my ($command) = @_;
    if (system($command) == 0) {
#	logging("Command $command - Return code 0");
    } else {
	my $ErrorString = "Could not execute command $command";
	error($ErrorString);
#	exit_application(1);
#	display_error($ErrorString);
    }
}

=pod

=head2 Read ini file Procedure

This procedure will read all lines in the file. All key/value pairs will be stored in a hash. Duplicate keys in a section are allowed but not recommended, since only the last value will remain.

=cut

sub read_ini_file() {
    my $openres = open(Urls, $page_file);
    if (not defined $openres) {
	error("Cannot open URL_Last_Modified file $page_file for reading, exiting...");
	exit_application(1);
    }
    while (my $line = <Urls>) {
	chomp $line;
	# Ignore any line that does not start with character
	if ($line =~ /^[A-Za-z]/) {
	    $line = trim($line);	# Make sure no more trailing blanks
	    my ($sys_page, $last_modified) = split (/=/, $line);
	    $sys_page = lc(trim($sys_page));
	    if (defined $last_modified) {
		$last_modified = trim($last_modified);
		$pages{$sys_page} = $last_modified;
	    } else {
		$pages{$sys_page} = -1;
	    }
	}
    }
    close Urls;
}

=pod

=head2 Write Current Status

This procedure will keep track of the current status: url and last modified pairs in alphabetical order.

=cut

sub write_curr_stat() {
   my $openres =  open(Status, ">$page_file");
   if (defined $openres) {
	foreach my $key (sort keys %new_pages) {
	    print Status "$key=$new_pages{$key}\n";
	}
	close Status;
    } else {
	error("Could not open $page_file for writing");
    }
}


=pod

=head2 Verify URLs

For each URL the procedure will get the page and read the last_modified time. If the last modified time is available and bigger then the previous last modified time, then only a log message will be written. In other cases an error will be send to the Unicenter event console.

=cut

sub verify_pages($$$) {
    my ($sys, $page, $last_modified) = @_;
    $new_pages{"$sys,$page"} = -1; # Initialize to invalid value
    # Copy page to local system, temp directory
    my $filename = basename($page);
    my $copied_file = $tempdir."/$filename";
    my $copy_cmd = "pscp -pw $atechKey $atechUser"."@"."$sys:$page $copied_file";
    execute_command($copy_cmd);
    # Open file for reading
    my $openres = open (Page, $copied_file);
    if (not defined $openres) {
	my $msg = "STATE_CRITICAL | rsyncPage rsync $filename notFound Page not found";
	my $cmd = "logforward -n$eventmgr -f$sys -vE -t\"$msg\"";
	execute_command($cmd);
	error("Could not open $copied_file for reading");
    } else {
	# Compare with previous read, must be different.
	my $new_last_modified = <Page>;
	chomp $new_last_modified;
	$new_pages{"$sys,$page"} = $new_last_modified;
	if ($new_last_modified ne $last_modified) {
	    logging("OK $page: $new_last_modified");
	} else {
	    my $msg = "STATE_CRITICAL | rsyncPage rsync $filename notUpdated Page not updated";
	    my $cmd = "logforward -n$eventmgr -f$sys -vE -t\"$msg\"";
	    execute_command($cmd);
	    error("System $sys Page $page not updated: $new_last_modified");
	}
    }
    unlink $copied_file;
}

######
# Main
######

# Handle input values
my %options;getopts("tl:f:m:h:", \%options) or pod2usage(-verbose => 0);
# The URL Address must be specified
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
    Log::trace_flag(1);
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
    if (not(defined $logdir)) {
	error("Could not find default Log directory, exiting...");
	exit_application(1);
    }
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
# Find url_last_modified file
if ($options{"f"}) {
    $page_file = $options{"f"};
    if (not (-r $page_file)) {
	error("System-Page file $page_file not readable, exiting...");
	exit_application(1);
    }
} else {
    error("System-Page file is not defined, exiting...");
    exit_application(1);
}
if ($options{"m"}) {
    $eventmgr = $options{"m"};
} else {
    $eventmgr = $ENV{COMPUTERNAME};
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Read URL file and last_modified times
read_ini_file();

# Handle all system-pages
while (my ($sys_page, $last_modified) = each %pages) {
    my ($sys,$page) = split /,/,$sys_page;
    $sys = trim $sys;
    $page = trim $page;
    verify_pages($sys, $page, $last_modified);
}

write_curr_stat();

exit_application(0);

=pod

=head1 TO DO

=over 4

=item *

Nothing for now....

=back

=head1 AUTHOR

Any remarks or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>

