=head1 NAME

ftp - FTP of selected files to a directory on a remote server

=head1 VERSION HISTORY

version 2.4 2 August 2002 DV

=over 4

=item *

Add the sleep time as a variable for restoring ftp connections.

=item *

Add a switch (-R) to prevent restoring broken ftp connections.

=back

version 2.3 11 July 2002 DV

=over 4

=item *

Implement the loop. When the ftp transfer session fails for some reason before all files are copied, then attempt to restore the session and continue to upload the files.

=item *

Update the log procedure to redirect STDERR to the logfile

=back

version 2.2 9 July 2002 DV

=over 4

=item *

add use warnings and use strict for better error checking

=item *

add comment on supported platforms

=back

version 2.1 19 March 2002 DV

=over 4

=item *

Include -C to clean up successfully transferred files.

=item *

Add counters for number of files transferred, number of files deleted and number of failed transfers.

=item *

Introduce use File::Basename to solve an issue with logfile names when script does not start from its own directory.

=back

version 2.0 14/03/2002 DV

=over 4

=item *

Convert ftp script to work for more type of files.

=item *

Add Synopis and Usage information, add pod2usage

=back

version 1.0 16/12/2000 DV

=over 4

=item *

Initial release, copy Dealer Performance data to the hdi1 server.

=back

=head1 DESCRIPTION

This script finds and picks up files to be transferred to a remote system. The files can be specified using a specific string in the filename, and/or a specific date in the filename, and/or a specific extension. Only "ascii" mode file transfer is possible.

All selected files will be copied to one directory on a remote server.

=head1 SYNOPSIS

ftp [-t] [-l log_dir] [-d source_dir] [-s string] [-n number_of_days] [-e ext] [-w] -r remote_host [-u username] [-p password] [-L load_dir] [-C] [-D] [-R] [-S sleeptime]

    ftp -h	    Usage
    ftp -h 1	    Usage and description of the options
    ftp -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: c:\temp

=item B<-d source_directory>

The source directory where to start looking for files to upload to the remote server. Default: c:\temp\dmp. 

=item B<-s string>

if specified, search string that must occur in the file name.

=item B<-n number>

number of days to go back, '-n 1': go back one day, '-n -1': tomorrow, '-n 0' is for today. Date is always in the format YYYYMMDD.

=item B<-e ext>

if specified, extension required on the filename. The extension in this application is defined as anything that comes after the first period in the filename (in other words: it assumes only one dot in the filename).

=item B<-w>

If specified, walk through the subdirectories to find more files. Note: on the remote host all files are copied into the load directory. The subdirectory structure is not (yet?) maintained on the remote host.

=item B<-r remote_host>

Remote host

=item B<-u Username>

FTP Username to log on to the remote host. If not specified, then logon with anonymous. 

=item B<-p Password>

FTP Password required to log on to the remote host. No password encryption is done. It is possible to specify only a password and no username (to use with user: "anonymous").

=item B<-L load_directory>

target directory on the remote host to load the files. If not specified, then the FTP user's home directory will be used.

=item B<-C>

When set, then files that are successfully transferred are deleted from the source.

=item B<-D>

enable FTP debugging

=item B<-R>

Restore ftp session. By default, when an ftp session is broken, the application will try to restore the ftp session until all files are transferred. If this option is set, then the application will B<not> try to restore the ftp session. This reduces the risk of running in an endless loop.

=item B<-S sleeptime>

Time to sleep (in seconds) before restoring any broken ftp connection. Default: 360 (5 minutes). Use -S 0 for no sleeping (during tests).

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.6.1, build 631 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my $walk = 0;			    # 0: don't walk through subdirs, 1: walkthrough
my $trace = 0;			    # 0: no tracing, 1: tracing
my $logdir = "c:/temp";		    # Log file directory
my $log = 1;			    # 0: no logging, 1: logging
my $srcdir = "c:/temp/dmp";	    # Search directory on source
my ($ftpobject, $ftpdir, $ftpdebug);    # Declare ftpobject
my ($incstr, $incdate, $incext);    
my ($host, $username, $password);
my ($delsource, $restore_session);			    # Flag
my $sleeptime;
my $found = 0;			    # Counts the number of files found
my $total_delfiles = 0;		    # Counts the number of files deleted
my $total_ftp = 0;		    # Counts the number of files transferred
my $total_failed_ftp = 0;	    # Counts the number of failed transfers

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Net::FTP;
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use File::Basename;		    # logfilename translation

#############
# subroutines
#############

sub error($) {
    my($txt) = @_;
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
    print "$datetime - Error: $txt\n";
    logging($txt);
}

sub trace($) {
    if ($trace) {
	my($txt) = @_;
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
	print "$datetime - Trace: $txt\n";
    }
}

# SUB - Open LogFile
sub open_log() {
    if ($log == 1) {
	my($scriptname, undef) = split(/\./, basename($0));
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $logfilename=sprintf(">>$logdir/$scriptname%04d%02d%02d.log", $year+1900, $mon+1, $mday);
	open (LOGFILE, $logfilename);
	open (STDERR, ">&LOGFILE");	    # STDERR messages into logfile
	# Ensure Autoflush for Log file...
	my $old_fh = select(LOGFILE);
	$| = 1;
	select($old_fh);
    }
}

# SUB - Handle Logging
sub logging($) {
    if ($log == 1) {
	my($txt) = @_;
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
	print LOGFILE $datetime." * $txt"."\n";
    }
}

# SUB - Close log file
sub close_log() {
    if ($log == 1) {
	close LOGFILE;
    }
}

sub exit_application($) {
    my($return_code) = @_;
    if (defined $ftpobject) {
	$ftpobject->quit();
    }
    logging("Total files found:       $found");
    logging("Total files transferred: $total_ftp");
    logging("Total files deleted:     $total_delfiles");
    logging("File transferred failed for $total_failed_ftp files");
    logging("Exit application with return code $return_code\n");
    close_log();
    exit $return_code;
}


=pod

=head2 Handle File Procedure

The file is checked to see if it fulfills the requirements. If so, the file is transferred to the remote server.

In case that the ftp session is closed before the file transfer is finished, then a new session is set-up and the file is transferred again. 

B<Be careful>: this construction may introduce the script to enter into an endless loop. Therefore a C<sleep> of 5 minutes is done before attempting to restore the connection.

The number of files transferred is counted.

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
    my $putfullname = "$directory/$file";
    my $ftp_result = $ftpobject->put($putfullname);
    while (not defined($ftp_result)) {
        my $msg = "$directory/$file has not been transferred successfully";
        $total_failed_ftp++;
	error($msg);
	if ($restore_session == 1) {
	    sleep $sleeptime;
	    setup_session();	# Be careful: this may cause the script to loop
	    $ftp_result = $ftpobject->put($putfullname);
	} else {
	    my $msg = "FTP session is broken.";
	    error($msg);
	    exit_application(1);
	}
    }
    if ($ftp_result eq $file) {
	$total_ftp++;      
	logging("$directory/$file has been transferred");
	trace("$directory/$file has been transferred");
	if (defined $delsource) {
	    my $delfiles = unlink "$directory/$file";
	    if ($delfiles == 1) {
		$total_delfiles++;
	    } else {
		error("$directory/$file could not be deleted");
	    }
	}
    } else {
        my $msg = "$directory/$file has not been transferred successfully";
        $total_failed_ftp++;
        error($msg);
    }
    $found++;
}

=pod

=head2 Walk through procedure

This procedure walks through a subdirectory, if required. It checks each filename. In case there are subdirectories of the subdirectory, then the "walk_through" procedure is called recursively.

=cut

sub walk_through($);	    # early prototype declaration to avoid warning message

sub walk_through($) {
    my ($directory) = @_;
    my (@dirlist);
    my ($size) = 0;
    if (!(opendir (DIR, $directory))) {
	error "Opendir $directory failed!";
    } else {
	my @dirlist = readdir(DIR);
	trace "walk_through Directory list for $directory:";
	foreach my $filename (@dirlist) {
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
	closedir DIR;
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
    if (!(opendir (DIR, $directory))) {
	error "Opendir $directory failed!";
    } else {
	my @dirlist = readdir(DIR);
	foreach my $filename (@dirlist) {
	    my $checkfile = $directory."/$filename";
	    if (-d $checkfile) {
		if ($walk == 1) {			# interested in subdirs?
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
	closedir DIR;
    }
}

=pod

=head2 Setup Session

Create an ftp object to the remote host, log in to the remote host and go to the required directory on the remote host.

=cut

sub setup_session() {

    # Create ftp object
    if (defined $ftpdebug) {
	$ftpobject = Net::FTP->new ($host, Debug => 1);
    } else {
	$ftpobject = Net::FTP->new ($host);
    }
    if (!($ftpobject)) {
	my $msg = "Create FTPObject to host $host not successful!";
	error ($msg);
	exit_application(1);
    }
    logging("Create FTPObject for $host successful");

    # Login to ftp session
    if (!($ftpobject->login($username, $password) == 1)) {
	my $msg = "Login to $host using $username, $password failed";
	error ($msg);
	exit_application(1);
    }
    logging("Login to $host successful");

    # Change directory on remote server
    if (defined $ftpdir) {
	if ($ftpobject->cwd($ftpdir) == 1) {
	    logging("Change to remote directory $ftpdir successful");
	} else {
	    my $msg = "Change to directory $ftpdir failed";
	    error($msg);
	    exit_application(1);
	}
    }
}

######
# Main
######

# Handle input values

my %options;
getopts("tl:d:s:n:e:wr:u:p:L:S:CDRh:", \%options) or pod2usage(-verbose => 0);
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
    pod2usage(-msg     => "Cannot find log directory $logdir.",
	      -verbose => 0);
}
# Logdir found, start logging
open_log();
logging("Start application");
# Find local search directory
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
if (defined $options{"w"}) {
    $walk = 1;
}
# Search string
if ($options{"s"}) {
    $incstr = $options{"s"};
}
# Dates
if (defined $options{"n"}) {
    my $searchtime = time - ($options{"n"} * 86400);
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($searchtime);
    $incdate = sprintf ("%04d%02d%02d",$year+1900, $mon+1, $mday);
    trace($incdate);
}
# Extension
if ($options{"e"}) {
    $incext = $options{"e"}
}
# Remote host
if ($options{"r"}) {
    $host = $options{"r"};
} else {
    error("No remote host (-r) specified");
    exit_application(1);
}
# Username
if ($options{"u"}) {
    $username = $options{"u"};
} else {
    $username = "anonymous";
    $password = "anonpassword";
}
# Password
if ($options{"p"}) {
    $password = $options{"p"};
}
# Load Directory
if ($options{"L"}) {
    $ftpdir = $options{"L"};
}
# Delete files after successful transfer
if (defined $options{"C"}) {
    $delsource = 1;
}
# Restore FTP Session if cancelled before all files are transferred
# Remark: restore session by default, set option to avoid restoring the session
if (defined $options{"R"}) {
    $restore_session = 0;
} else {
    $restore_session = 1;
}
# Sleep time before restoring connection
if (defined $options{"S"}) {
    $sleeptime = $options{"S"};
} else {
    $sleeptime = 360;
}
# FTP Debugging
if (defined $options{"D"}) {
    $ftpdebug = "D";
}
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

setup_session();

scan_dir($srcdir);

if (!($ftpobject->quit() == 1)) {
  my $msg = "FTP Quit not successfully";
  error($msg);
  exit_application(1);  
}

exit_application(0);

=pod

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
