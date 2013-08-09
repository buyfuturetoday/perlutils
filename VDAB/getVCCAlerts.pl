=head1 NAME

getVCCAlerts - This script will get the alerts that are forwarded to VCC and alerts that are not forwarded to VCC

=head1 VERSION HISTORY

version 1.0 08 April 2010 DV

=over 4

=item *

Initial Release.

=back

=head1 DESCRIPTION

This script will get alerts that are catched by TEC and forwarded to VCC. The script will also get alerts that are catched but not forwarded to VCC because they are filtered.

 [Main]
 ; ftp Connection information
 ruser = appmon
 rpwd = appmon
 rhost = pw18
 rdir = /em/bin/Agile
 ldir = e:\temp

=head1 SYNOPSIS

getVCCAlerts.pl [-t] [-l log_dir]

 getVCCAlerts -h	    Usage
 getVCCAlerts -h 1	    Usage and description of the options
 getVCCAlerts -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP SP2, Perl v5.8.8, build 820 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $dbh, $ftph, $ruser, $rpwd, $rhost, $rdir, $ldir);
my (@files2handle);
my $printerror = 0;

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
use DBI();
use amParams;
use Config::IniFiles;		# Handle ini file
use File::Basename;			# Get Current Directory
use Net::FTP;				# FTP File handling

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if (defined $dbh) {
		$dbh->disconnect;
	}
	if (defined $ftph) {
		$ftph->quit;
	}
    logging("Exit application with return code: $return_code\n");
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

=head2 Handle Ini File

appAlert agent ini file is used to specify application alert specific settings.

=cut

sub handle_ini_file($) {
	my ($inifile) = @_;
	my $schedule_ini = new Config::IniFiles(-file	=> $inifile);
	if (not defined $schedule_ini) {
		my $errline = "Could not process $inifile, errors: ".join("",@Config::IniFiles::errors);
		exit_application(1);
	}
	$ruser = $schedule_ini->val("Main","ruser");
	$rpwd = $schedule_ini->val("Main","rpwd");
	$rhost = $schedule_ini->val("Main","rhost");
	$rdir = $schedule_ini->val("Main", "rdir");
	$ldir = $schedule_ini->val("Main", "ldir");
}

=pod

=head2 Get Stored Modification time

This module will get the last processed modification time for the file. If the file has never been processed, the modification time will be set to a random value in the past.

=cut

sub getstoredmodtime {
	my ($filename) = @_;
	my ($lastmodtime);
	my $query = "SELECT pvalue FROM params WHERE pkey = ?";
	my $sth = $dbh->prepare($query);
	$sth->bind_param(1, $filename);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref()) {
		$lastmodtime = $ref->{pvalue};
	} else {
		# No time found, assign time in past
		$lastmodtime = 0;
	}
	return $lastmodtime;
}

=pod

=head2 Get File

Copy file to local directory and update last modification time

=cut

sub getfile {
	my ($filename, $lastmodtime, $storedmodtime) = @_;
	my ($query);
	# First get file
	my $localfile = "$ldir/$filename";
	my $rv = $ftph->get($filename, $localfile);
	if (not defined $rv) {
		error("Could not copy $filename to $localfile, ".$ftph->message);
		exit_application(1);
	}
	# Then update last modification time
	if ($storedmodtime == 0) {
		$query = "INSERT INTO params (pkey, pvalue)
						 VALUES ('$filename', '$lastmodtime')";
	} else {
		$query = "UPDATE params SET pvalue = '$lastmodtime'
						 WHERE pkey = '$filename'";
	}
	$rv = $dbh->do($query);
	if (not defined $rv) {
		error("Error executing query $query, ".$dbh->errstr);
		exit_application(1);
	}
}

=pod

=head2 Get Remote Files

Collect all filenames to handle and return them in an array. The file senttovcc.log and notsenttovcc.log and their previous versions will be checked. For each file the last modification date will be read. If the last modification date is younger than the last modification date stored in the database, the file will be copied to the local system and the local file name will be added to the array of files to handle.

=cut

sub get_remote_files {
	my $filename = "senttovcc.log";
	my $storedmodtime = getstoredmodtime($filename);
	my $lastmodtime = $ftph->mdtm($filename);
	if ($lastmodtime > $storedmodtime) {
		push @files2handle, $filename;
		getfile($filename, $lastmodtime, $storedmodtime);
	}
	return @files2handle;
}

=pod

=head2 Event Stored

This procedure will check if the event is stored already in the database. If this is the case then this event and all earlier events in the log file have been handled already and this application can stop processing.

=cut

sub event_stored {
	my ($fdtstamp, $host, $message) = @_;
	my $query = "SELECT dtstamp FROM events 
					WHERE dtstamp = ? AND host = ? AND message = ?";
	my $sth = $dbh->prepare($query);
	$sth->bind_param(1, $fdtstamp);
	$sth->bind_param(2, $host);
	$sth->bind_param(3, $message);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Error executing query $query, ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref){
		# OK, record found, stop processing
		$sth->finish;
		return "Yes";
	} else {
		# Record not found, continue processing
		$sth->finish;
		return "No";
	}
}

=pod

=head2 Add Event

This procedure will add the event to the event table.

=cut

sub add_event {
	my ($fdtstamp, $severity, $source, $class, $host, $subsource, $message) = @_;
	my $query = "INSERT INTO events (dtstamp, severity, source, class, host, subsource, message)
					         VALUES (?, ?, ?, ?, ?, ?, ?)";
	my $sth = $dbh->prepare($query);
	$sth->bind_param(1, $fdtstamp);
	$sth->bind_param(2, $severity);
	$sth->bind_param(3, $source);
	$sth->bind_param(4, $class);
	$sth->bind_param(5, $host);
	$sth->bind_param(6, $subsource);
	$sth->bind_param(7, $message);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Error executing query $query, ".$sth->errstr);
		exit_application(1);
	}
}

=pod

=head2 Format Date Time Stamp

This procedure will convert the Tivoli date/time stamp to the MySQL date/time stamp.

Source nvserverd (Netview) provides date in YY format, sourcd ITM provides date in YYYY format. In first case add 2000 to the date. (mind Y3k issue).

=cut

sub format_dt {
	my ($dtstamp, $source) = @_;
	my $offset = 0;
	if ($source eq "nvserverd") {
		$offset = 2000;
	}
	$dtstamp = trim($dtstamp);
	my ($date, $time) = split / /, $dtstamp;
	my ($mnt, $day, $yr) = split /\//, $date;
	if (index($time, ".") > -1) {
		# Timestring has subseconds, strip this...
		($time, undef) = split /\./, $time;
	}
	my $fdate = sprintf("%04d-%02d-%02d", $yr+$offset, $mnt, $day);
	return "$fdate $time";
}

=pod

=head2 Handle File

This procedure will read the file and add all additional records to the alerts database. The assumption is that event de-duplication has been done. It means that an alert is uniquely defined by date/time stamp and the 

=cut

sub handle_file {
	my ($filename) = @_;
	my $cnt = 0;
	my $localfile = "$ldir/$filename";
	my $openres = open(Events, $localfile);
	if (not defined $openres) {
		error("Could not open $localfile for reading, exiting...");
		exit_application(1);
	}
	# Get all events in an array
	my @events = <Events>;
	close Events;
	# Handle the array backwards until already handled records are found
	while (my $eventline = pop @events) {
		chomp $eventline;
		my ($identifier, $dtstamp, $severity, $source, $class, $host, $subsource, @msgarr) = split /,/,$eventline; 
		# Trim all values
		$dtstamp = trim($dtstamp);
		$severity = trim($severity);
		$source = trim($source);
		$class = trim($class);
		$host = trim($host);
		$subsource = trim($subsource);
		# Check if dtstamp has only date, then legacy record and stop processing
		if (index($dtstamp, " ") == -1) {
			logging("Stop processing - legacy event line: $eventline");
			last;
		}
		# Remove commas from msgarr, replace by " "
		my $message = join (" ", @msgarr);
		# Format date/time stamps
		my $fdtstamp = format_dt($dtstamp,$source);
		if (event_stored($fdtstamp, $host, $message) eq "Yes") {
			last;
		} else {
			add_event($fdtstamp, $severity, $source, $class, $host, $subsource, $message);
			$cnt++;
		}
	}
	logging("$cnt events added from $filename");
}

######
# Main
######

# Handle input values
my %options;
getopts("tl:h:", \%options) or pod2usage(-verbose => 0);
# my $arglength = scalar keys %options;  
# if ($arglength == 0) {			# If no options specified,
#    $options{"h"} = 0;			# display usage. jmeter plan is mandatory
# }
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
		error("Could not set d:/temp/log as Log directory, exiting...");
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
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Get ini values
fileparse_set_fstype("MSWin32");
my ($applname,$dirname,$suffix) = fileparse($0, ".pl");
my $inifile = "$dirname/$applname.ini";
if (-r $inifile) {
	handle_ini_file($inifile);
} else {
	error("Inifile $inifile not readable, exiting...");
	exit_application(1);
}

# Set-up database connection
my $connectionstring = "DBI:mysql:database=$databasename;host=$server;port=$port";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

# Set-up ftp handle
$ftph = Net::FTP->new($rhost, 
					  Debug => 0);
if (not defined $ftph) {
	error("Could not create ftp handle, ".$@);
	exit_application(1);
}
my $rv = $ftph->login($ruser, $rpwd);
if (not defined $rv) {
	error("Cannot login: ".$ftph->message);
	exit_application(1);
}
# Ensure Ascii mode
$ftph->ascii;
$rv = $ftph->cwd($rdir);
if (not defined $rv) {
	error("Cannot change to remote directory $rdir ".$ftph->message);
	exit_application(1);
}

get_remote_files();

push @files2handle, "senttovcc.log";

# Now handle all files
foreach my $filename (@files2handle) {
	handle_file($filename);
}

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Allow to send to multiple SMS numbers

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@hp.comE<gt>
