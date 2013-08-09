# Documentation:
#   use: pod2html pcm2dmp.pl > pcm2dmp.html 
#   to obtain the documentation in *.html format

=head1 NAME

pcm2dmp - Converts pcm files as available from historical performance collection to dmp format as required for upload into ERA2.

=head1 VERSION HISTORY

version: 0.7 - 4 July 2002 DV

=over 4

=item *

Add strict and warnings pragmas for additional error checking.

=item *

Rework documentation where required ...

=back

version: 0.6 - 19 March 2002 DV

=over 4

=item *

Allow fully qualified hostnames (including dots)

=item *

Add -C flag to clean-up *.csv files that are successfully transferred to *.dmp files. Also delete all "Subset" files, even though they are not converted to *.dmp files.

=item *

Add counters to display number of files transferred.

=item *

Resolve an issue with logfile creation when the script does not run from its home directory

=back

version: 0.5 - 15 March 2002 DV

=over 4

=item *

Handles "FullDaily" files only, the "SubsetDaily" files are ignored.

=item *

Allow for hostnames with underscores in the name.

=item *

SMCcopy file names must have IP addresses with _ in stead of . (like: 198_132_114_90)

=item *

SMCcopy file names must end on *.dat in stead of *.dmp

=back

version: 0.4 - 13 March 2002 DV

=over 4

=item *

Add pcmtocsv processing

=item *

Add processing for specific day only

=item *

Introduce proper SMCpcopy file names

=back

version: 0.3 - 7 March 2002 DV

=over 4 

=item *

Add POD to allow easy documentation

=item * 

Change instances from "0;C:" to "C:"

=item * 

Change instances from "_Total;_Total" to "Total"

=item *

Translate "System - System Up Time" to "NET - Device - sysUpTime"

=back

version: 0.2 - 6 March 2002 DV

=over 4

=item *

Add "Hostname to IP Address" translation

=back

version: 0.1 - 4 March 2002 DV

=over 4

=item *

Initial Release

=back

=head1 DESCRIPTION 

    0. Convert pcm files to csv files
    1. Read input file until string (Time (HH:MM) ->) is found
       Calculate Interval
       Read Start time
       2. Read until empty line or end-of-file
	Fill in IP Address (currently: hostname)
	Fill in Application
	Fill in Instance
	Fill in Parameter
	Calculate Start Date/Time
	Read value for min, avg, max, nr - no consolidation is done 
	Write result line

=head1 SYNOPSIS

 pcm2dmp [-t] [-l log_dir] [-p pcm_dir] [-c csv_dir] [-d dmp_dir] [-n days_back] [-C]

 pcm2dmp -h		Usage
 pcm2dmp -h 1		Usage and description of the options
 pcm2dmp -h 2		Full documentation

=head1 OPTIONS

=over 4

=item B<-t>

tracing enabled if set, default: no tracing

=item B<-l logfile_directory>

default: c:\temp

=item B<-p pcm_directory>

default: c:\tnd\perfdata\performance_cubes

=item B<-c csv_directory>

default: c:\temp\csv. The directory will be created if it does not exists.

=item B<-d dmp_directory>

default: c:\temp\dmp. The directory will be created if it does not exists.

=item B<-n days_back>

number of days to go back, '-n 1': go back one day, '-n -1': tomorrow, '-n 0' is for today. Date is always in the format YYYYMMDD. If not specified, then all available files are handled.

=item B<-C>

If set, then the converted csv files are deleted after conversion. Also corresponding "SubsetDaily" files are deleted. The option is to delete only the handled files. If files are not handled due to whatever reason, they remain in the csv directory. This can be used as an error check.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.6.1, build 631 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
###########

my $csvdir = "c:/temp/csv";			    # csv source directory
my $dmpdir = "c:/temp/dmp";			    # dmp target directory
my $pcmdir = "c:/tnd/perfdata/performance_cubes";   # pcm source directory
my $sectionstring = "\"Time (HH:MM) ->\"";	    # Section separator
my $delsource = 0;					    # 0: do not del source, 1: delete
my $trace = 0;					    # 0: do not trace, 1: trace
my $log = 1;					    # 0: do not log, 1: logging
my $logdir = "c:/temp";				    # Logdirectory
my $total_cvt = 0;				    # Counts converted files
my $total_delfiles = 0;				    # Counts deleted FullDaily files (have been converted)
my $total_delsubset = 0;			    # Counts Subset Daily files
my @timelist;					    # Timelist array
my $interval;	    
my ($filename, $inpfile);
my $procdate;					    # Handle files for one day only
my %hosttable = ();		  # Hash table to collect hostname - IP information

my %monthnum = (		  # using Date::Calc is better
    January	=> 1,		  # but the Date::Calc module is not in 
    February	=> 2,		  # the standard Activestate Perl release...
    March       => 3,
    April       => 4,
    May	        => 5,
    June        => 6,
    July        => 7,
    August	=> 8,
    September	=> 9,
    October	=> 10,
    November	=> 11,
    December	=> 12
);

#####
# use
#####

use warnings;		    # impose warning message generation
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Socket;		    # for IP address translation
use Net::hostent;	    # for hostname to IP translation
use Getopt::Std;	    # for input parameter handling
use Pod::Usage;		    # Usage printing
use File::Basename;	    # logfile name extraction

#############
# subroutines
#############

sub error($) {
    my($txt) = @_;
    logging("Error in $inpfile: $txt");
}

sub trace($) {
    if ($trace) {
	my ($txt) = @_;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
	print "$datetime - Trace in $0: $txt\n";
    }
}

# SUB - Open LogFile
sub open_log() {
    if ($log == 1) {
	my ($logname, undef) = split (/\./, basename($0));
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $logfilename=sprintf(">>$logdir/$logname%04d%02d%02d.log", $year+1900, $mon+1, $mday);
	open (LOGFILE, $logfilename);
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
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
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
    my($ret) = @_;
    close CSVFILE;
    close ERAFILE;
    logging("Total number of files converted:           $total_cvt");
    logging("Total number of FullDaily files deleted:   $total_delfiles");
    logging("Total number of SubsetDaily files deleted: $total_delsubset");
    logging("Exit application with return code $ret\n");
    close_log();
    exit $ret;
}
 
=pod

=head2 Hostname - IP Address translation

For each hostname one attempt is made to find the IP address. If successful, the (hostname, IP) pair is added to the hosttable hash. If not successful, (hostname, hostname) is added to the hosttable hash. The idea is that hostname - IP translations work immediately. If not, the translation must be recovered on ERA level. 

Processing of the local files should not be delayed due to slow hostname - IP Address translation.

=cut 

sub findIP($) {
    my $hostIP;
    my($hostname) = @_;
    if (!(my $host = gethost($hostname))) {
	logging("Cannot find IP for $hostname");
	$hostIP = $hostname;
    } elsif (@{$host->addr_list} > 1) {
	logging("More than one IP address for $hostname, using first one.");
	$hostIP = inet_ntoa($host->addr);
    } else {
	$hostIP = inet_ntoa($host->addr);
    }
    $hosttable{$hostname} = $hostIP;
    return $hostIP;
}

=pod

=head2 Handle Section procedure

=over 4

=item * Convert csv line to dmp line

Each csv line contains all measurements during the period for this data section.
SMCpcopy needs one line per measurement.
Therefore C<avg = min = max = measured value>, and C<nr of measurements = 1>

The csv file sometimes contain "instance" values from the form: C<0;C:>
This occurs for example for the application "LogicalDisk", 
parameter "% Disk Read Time". 
The "instance" values will be scanned on semi-colons, and only the second
item will be kept.

Also some instances are written as _Total;_Total. Therefore underscores as 
first characters will be removed.

Note: application, parameter and instances are defined in the document
"ESMC Reporting Project - Definition of Interface Files"

=item * sysUpTime

PCM cubes from CA define C<System - System Up Time>, while ERA is looking for 
C<NET - Device - sysUpTime>, so this translation is done.

However as soon as more names should be translated from PCM to ERA format,
a translation table must be created

=back

=cut

# SUB - Consolidate measurements per line
sub handle_section() {
    while (my $csvline = <CSVFILE>) {
	if (length($csvline) > 1) {
	    chomp $csvline;
	    my ($hostname, $application, $parameter, $instance, $date, undef, @vallist) = split(/,/, $csvline);
	    # Remove quotes
	    $hostname = substr($hostname, 1, length($hostname)-2);
	    $application = substr($application, 1, length($application)-2);
	    $instance = substr($instance, 1, length($instance)-2);
	    $parameter = substr($parameter, 1, length($parameter)-2);
	    $date = substr($date, 1, length($date)-2);
	    # End Remove quotes
	    # Find IP Address
	    my $hostIP;
	    if (defined $hosttable{$hostname}) {
		$hostIP = $hosttable{$hostname};
	    } else {
		$hostIP = findIP($hostname);
	    }
	    # Handle sysUpTime
	    if ($parameter eq "System Up Time") {
		$application = "NET";
		$instance = "Device";
		$parameter = "sysUpTime";
	    }
	    # Handle $instance values
	    if (index($instance,";") > 0) {
		(undef, $instance) = split(/;/, $instance);
	    }
	    if (substr($instance,0,1) eq "_") {
		$instance = substr($instance, 1);
	    }
	    if ($instance eq "") { $instance = $application; }
	    # Format Date
	    my ($dd, $month, $yyyy) = split(/ /, $date);
	    my $era2date = sprintf("%04d-%02d-%02d", $yyyy, $monthnum{$month}, $dd);
	    my $cnt = 0;
	    my ($value, $era2time, $min, $avg, $max, $nbr);
	    foreach $value (@vallist) {
		$era2time = $era2date . " " . $timelist[$cnt] . ":00";
		$cnt++;
		$min = $value;
		$avg = $value;
		$max = $value;
		$nbr = 1;
		print ERAFILE "$hostIP,$application,$instance,$parameter,$era2time,$interval,$min,$avg,$max,$nbr\n";
	    }
	} else {
	    last;
	}
    }
}

=pod

=head2 Handle File Procedure

The csv files as delivered from the CA Unicenter pcmtocsv utility consist of:

=over 4

=item *

The header section, that can be ignored

=item *

some blank lines

=item *

One or more data sections. Each data section starts with "Time (HH:MM) ->" as the first string on the line. This line also contains the time stamps for each measurement.

=item *

Each data section contains a number of data lines with measurements, as handled in the "handle section" procedure

=item *

Each data section (apart from the last section) is terminated with a blank line.

=back

=cut

sub handle_file() {
    my $csvline;
    while ($csvline = <CSVFILE>) {
	chomp $csvline;
	if (substr($csvline, 0, length($sectionstring)) eq $sectionstring) {
	    (undef, undef, undef, undef, undef, undef, @timelist) = split(/,/, $csvline);
	    # Calculate interval ...
	    my $starttime = $timelist[0];
	    my $nexttime  = $timelist[1];
	    my ($starthour, $startmin) = split(/:/, $starttime);
	    my $starttick = ($starthour * 60) + $startmin;	  # Handle start at 8:55, next 9:15
	    my ($nexthour, $nextmin) = split(/:/, $nexttime);
	    my $nexttick = ($nexthour * 60) + $nextmin;
	    $interval = $nexttick - $starttick;
	    if ($interval <= 0) { error("Invalid interval time for $csvline"); }
	    handle_section();
	}
    }
}

=pod

=head2 Convert File procedure

A file is found that fulfills the requirements for conversion. Following actions are taken:

=over 4

=item *

Open the file

=item *

Extract the hostname from the filename. The hostname is anything in the filename before "_FullDaily".

=item *

Convert the hostname to the IP address. Replace all dots in the IP address with underscores

=item *

Now the output file name is known. Open the file for output and perform the conversion in the Handle File procedure.

=item *

If required, delete the original file.

=back

=cut

sub convert_file($$) {
    my($inpfile,$filename) = @_;
    my $openres = open(CSVFILE, "$csvdir/$inpfile");
    if (not $openres) {
	error("Could not open $csvdir/$inpfile for reading.");
	exit_application(1);
    }
    # host names can have _, TNG names use _ as separator
    # look for the last _ in the file name.
    my $undpos = index($filename,"_FullDaily");
    my $hostname = substr($filename,0,$undpos);
    # Find IP Address
    my ($hostIP,$filedate);
    if (defined $hosttable{$hostname}) {
	$hostIP = $hosttable{$hostname};
    } else {
	$hostIP = findIP($hostname);
    }
    if (defined $procdate) {
	$filedate = $procdate;
    } else {
	$filedate = substr($filename, length($filename)-8);
    }
    my $hcopy_IP = $hostIP;
    $hcopy_IP =~ s/\./_/g;   # Using regexps is a bad idea, always!
    my $outfile = "$dmpdir/SMChcopy_" . $hcopy_IP ."_$filedate.dat";
    $openres = open(ERAFILE, ">$outfile");
    if (not $openres) {
	error("Could not open $outfile for writing.");
	exit_application(1);
    }
    logging("Now working on $csvdir/$inpfile");
    handle_file();
    close CSVFILE;
    close ERAFILE;
    $total_cvt++;
    if ($delsource == 1) {
	my $delfiles = unlink "$csvdir/$inpfile";
	if ($delfiles == 1) {
	    $total_delfiles++;
	} else {
	    error("$csvdir/$inpfile could not be deleted");
	}
    }
}

=pod

=head2 pcm2csv Procedure

This procedure runs the utility "pcmtocsv" to convert the *.pcm files into *.csv files. The utility runs recursively through all performance cubes subdirectories, the result files are stored in one directory. The host name is pre-pended to each result file. If a date is specified, then all daily cubes for this date are handled. Otherwise all cubes are handled.

If the utility fails, then the application is terminated with exit code 1.

=cut

sub pcm2csv() {
    my $dayswitch;
    if (defined $procdate) {
	$dayswitch = "-x $procdate";
    } else {
	$dayswitch = "";
    }
    my $command = "pcmtocsv $pcmdir $csvdir -r -f $dayswitch -t daily";
    logging("Starting with $command");
    my $sysres = system($command);
    if ($sysres == 0) {
	logging("pcmtocsv successfully finished.");
    } else {
	error("Something wrong in $command");
	exit_application(1);
    }
}

######
# Main
######

# Handle input values
my %options;
getopts("tl:p:c:d:n:Ch:", \%options) or pod2usage(-verbose => 0);
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
# Find pcm directory
if ($options{"p"}) {
    $pcmdir = $options{"p"};
}
if (-d $pcmdir) {
    trace("pcm Directory: $pcmdir");
} else {
    error("Cannot find pcm directory $pcmdir");
    exit_application(1);
}
# Find csv directory
if ($options{"c"}) {
    $csvdir = $options{"c"};
}
if (-d $csvdir) {
    trace("csv Directory: $csvdir");
} else {
    if (mkdir ($csvdir, 0)) {
	logging("$csvdir has been created");
    } else {
	error("$csvdir could not be created");
	exit_application(1);
    }
}
# Find dmp directory
if ($options{"d"}) {
    $dmpdir = $options{"d"};
}
if (-d $dmpdir) {
    trace("dmp Directory: $dmpdir");
} else {
    if (mkdir ($dmpdir, 0)) {
	logging("$dmpdir has been created");
    } else {
	error("$dmpdir could not be created");
	exit_application(1);
    }
}
# Dates
if (defined $options{"n"}) {
    my $searchtime = time - ($options{"n"} * 86400);
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($searchtime);
    $procdate = sprintf ("%04d%02d%02d",$year+1900, $mon+1, $mday);
}
# Delete files after successful conversion
if (defined $options{"C"}) {
    $delsource = 1;
}
while (my ($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Convert pcm to csv files
pcm2csv();

# Find IP Address of the machine where I'm running,
# as required in the SMCpcopy filename.
my $host;
if (!($host = gethost(""))) {
    logging("Can't find hostname for this machine...");
    exit_application(1);
}
my $my_host = $host->name;
logging("Host: $my_host");
if (@{$host->addr_list} > 1) { 
    logging("More than one IP address defined for $my_host, using first one.");
}
my $my_IP = inet_ntoa($host->addr);
logging("IP Address: $my_IP");
$my_IP =~ s/\./_/g;   # Using regexps is a bad idea, always!

# Collect all *.csv files
opendir(DIR, $csvdir);
my @dirlist = readdir(DIR);
closedir(DIR);

# Process all *.csv files
foreach $inpfile (@dirlist) {
    my $ext;
    ($filename, $ext) = split(/\./, $inpfile);
    $filename = basename($inpfile, ".csv");
    if (length($inpfile) <= length($filename)) {
	$ext = "";
    } else {
	$ext = substr($inpfile, length($filename)+1);
    }
    trace("Filename: $filename - Ext: $ext");
    if ($ext eq "csv") {
	if ((not(defined $procdate)) or (index($inpfile, $procdate) > -1)) {
	    if (index($filename,"FullDaily") > -1) {
		# Handle file to convert
		convert_file($inpfile,$filename);
	    } elsif (index($filename, "SubsetDaily") > -1) {
		if ($delsource == 1) {
		    my $delfiles = unlink "$csvdir/$inpfile";
		    if ($delfiles == 1) {
			$total_delsubset++;
		    } else {
			error("$csvdir/$inpfile could not be deleted");
		    }
		}
	    }
	}
    }
}

trace("Hostname - IP address table");
while (my($hostname, $hostIP) = each %hosttable) {
    trace("$hostname - $hostIP");
}

exit_application(0);

=pod

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>

EMEA Tools and Automation
