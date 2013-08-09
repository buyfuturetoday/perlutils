=head1 NAME

CheckSysUpTime - Verification and clean-up of the SysUpTime file.

=head1 VERSION HISTORY

version 1.2 31 october 2002 DV

=over 4

=item *

Allow for "T" test indicator in smc and config_id code. The "T" Test indicator is removed for now.

=back

version 1.1 22 october 2002 DV

=over 4

=item *

Resolved an issue with the Log module settings.

=back

version 1.0 16 october 2002 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This script wants to verify and clean-up the SysUpTime file per SMC. Following items are verified:

=over 4

=item B<application type>

The application type must be consistent. For now, only application type B<NET> is accepted. Can SysUpTime be associated with other application types?

=item B<instance type>

The instance type must be consistent. For  now, only instance type B<DEVICE> is accepted. Can SysUpTime be associated with other instance types?

=item B<SysUpTime>

The SysUpTime from subsequent records must point to the same start time (within a specified small accuracy) or it must point to a start time in the interval between subsequent measurements. It cannot point to any other start time.

However it happens that a one measurement has a discrepancy of minutes. Therefore an attempt is made to remove this measurement and keep all others. The number of invalid measurements is counted and compared to total number of measurements for a configuration ID. The number of errors must be less than 10% of the total number of measurements to maintain a reliable SysUpTime.

=item B<Configuration ID>

Configuration IDs must be sorted in ascending order. Configuration IDs cannot have negative numbers.

=back

Invalid records will be ignored.

The script will handle all files spi_*_sysuptime.dat that are available in the directory.

The information must be combined with the service window information: SysUpTime records not within the service windows have a bigger chance to be unreliable.

=head1 SYNOPSIS

CheckSysUpTime [-t] [-l log_dir] [-d source_dir]

    CheckSysUpTime -h	    Usage
    CheckSysUpTime -h 1	    Usage and description of the options
    CheckSysUpTime -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: c:\temp

=item B<-d source_directory>

The source directory where to start looking for files to upload to the remote server. Default: c:\projects\reporting\spi\testdata

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.6.1, build 631 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that the proper directories are mentioned.

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my $logdir;		    # Log file directory
my $srcdir = "c:/projects/reporting/spi/testdata/NL";	# Source directory for SysUpTime files
my $cnt;			    # Value used during tests, may need to be removed.
my $sysup_record="";		    # Maintain relevant sysup records for the CHECK file.
my $accuracy = 30000;		    # Accuracy to indicate the limits to define sysUpTime
my $valid_values = 0;
my $invalid_values = 0;
my $remember_record = "no";	    # Boolean (yes/no), indicates if the previous record is one to remember or not.
my ($smc, $verify_record, $invalid_config);
my ($errors, $skipped);
my ($start_time, $prv_time, $current_time);
my ($raw_spi,$raw_config,$raw_appl,$raw_instance,$raw_param);
my ($raw_date_time,$raw_interval,$raw_min,$raw_avg,$raw_max,$raw_nbrmeas);
my ($prv_spi,$prv_config,$prv_appl,$prv_instance,$prv_param);
my ($prv_date_time,$prv_interval,$prv_min,$prv_avg,$prv_max,$prv_nbrmeas);

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use Time::Local;		    # Convert time to epoch
use Log;

#############
# subroutines
#############

sub exit_application($) {
    my($return_code) = @_;
    logging("Exit application with return code $return_code\n");
    close_log();
    exit $return_code;
}

=pod

=head2 Trim

This section is used to get rid of leading or trailing blanks. It has been copied from the Perl Cookbook.

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

=head2 Copy to Previous record

This subroutine copies the current raw SPI data into the previous SPI data record, used to calculate differences.

=cut

sub copy2prv() {
    $prv_spi = $raw_spi;
    $prv_config = $raw_config;
    $prv_appl = $raw_appl;
    $prv_instance = $raw_instance;
    $prv_param = $raw_param;
    $prv_date_time = $raw_date_time;
    $prv_interval = $raw_interval;
    $prv_min = $raw_min;
    $prv_avg = $raw_avg;
    $prv_max = $raw_max;
    $prv_nbrmeas = $raw_nbrmeas;
    $prv_time = $current_time;
}

=pod

=head2 Remember Check Record

This procedure adds the previous record to the sysup records since it is a record that contains useful information.

=cut

sub remember_sysup_record() {
    $sysup_record = $sysup_record . " $prv_spi,$prv_config,$prv_appl,$prv_instance,$prv_param,$prv_date_time,$prv_interval,$prv_min,$prv_avg,$prv_max,$prv_nbrmeas\n";
}

=pod

=head2 Convert Time

This procedure converts the time (in date_time field) to the epoch time. The epoch time is returned.

=cut

sub convert_time() {
    my($date,$time) = split(" ",$raw_date_time);
    my($year,$month,$day) = split("-",$date);
    my($hour,$min,$sec) = split(":",$time);
    $year = $year-1900;
    $month = $month-1;
    return timelocal($sec,$min,$hour,$day,$month,$year);
}

=pod

=head2 New Configuration

In case we are handling a new configuration ID, do following actions: 

=over 4

=item *

If there are records from a previous configuration ID, write the records to the CHECK file.

=item *

Verify if the new configuration ID is bigger than the previous configuration ID. Configuration IDs must be ordered in ascending order for the current implementation of the input verification.

=item *

Calculate the Server start time (epoch time).

=item *

Remember the start record.

=back

=cut

sub new_config() {
    if ($remember_record eq "yes") {
	remember_sysup_record();
	$remember_record = "no";
    }
    if (($prv_config > 0) and not($prv_config == $invalid_config)) {
	logging("Config ID: $prv_config, $valid_values valid records, $invalid_values invalid records");
    }
    if (length($sysup_record) > 0) {
	print CHECK_SYSUPTIME $sysup_record;
	$sysup_record = "";
    }
    if ($raw_config <= $prv_config) {
	$invalid_config = $raw_config;
	error ("Config ID lower than previous config: $verify_record");
	$errors++;
    } else {
	# Calculate Start Time in epoch
	$current_time=convert_time();
	$start_time = $current_time*100 - $raw_avg;
	# Store as previous record, but do not yet remember previous record
	copy2prv();
	# Remember record for the CHECK file
	remember_sysup_record();
	# Initialize valid and invalid measurement counters
	$valid_values = 1;
	$invalid_values = 0;
    }
}

=pod

=head2 Same Configuration

=over 4

=item *

First verify if the application and the instance are the same as from the previous config ID. If not, do not trust this measurement.

=item *

Check if the SysUpTime equals max_SysUpTime (2**31-1). This means that the device has not been restarted since the previous measurement. Forget about the previous record and continue with the current record.

=item *

Else calculate if the sysUpTime is in the interval since the previous measurement. If so, the server has been down and restarted between the two measurements. Save the previous record and start a new cycle including a new start time with the new record.

=item *

Else calculate if the sysUpTime points to the previously calculated start time (within the allowed accuracy). If so, forget about the previous record and continue with the current record.

=item *

Else report the measurement as "invalid". Calculate the number of invalid records. Ignore the record as long as the total number of invalid records is less than 10% of all measurements in since the last server restart for this configuration ID. Also accept a 'false' start, on condition that all is OK as of the second record.

=back

=cut

sub same_config() {
    if (not(($raw_appl eq $prv_appl) and
	    ($raw_instance eq $prv_instance))) {
	# Different application or instance => invalid config id.
	error("Change in application and/or instance - $verify_record");
	$errors++;
	$invalid_config = $raw_config;
	$sysup_record = "";
	$remember_record = "no";
    } elsif ($raw_avg == 2147483647) {
	# Max SysUpTime reached (2**31 - 1) => Accept last record
	    $valid_values++;
	    copy2prv();
	    $remember_record = "yes";
    } else {
	# Verify sysUpTime has expected value.
	$current_time = convert_time();
	my $delta_time = $current_time - $prv_time;
	if ($raw_avg < (($delta_time*100)+$accuracy)) {
	    # sysUpTime indicates that the server has been rebooted since the last measurement
	    # Previous record indicates "System Down" message -> remember
	    if ($remember_record eq "yes") {
		remember_sysup_record();
	    }
	    logging("Config ID: $prv_config, $valid_values valid records, $invalid_values invalid records for start time $start_time");
	    $start_time = $current_time*100 - $raw_avg;
	    copy2prv();
	    $remember_record = "yes";
	    # Re-initialize valid and invalid measurement counters for the config ID.
	    $valid_values = 1;
	    $invalid_values = 0;
	} elsif (((($current_time*100)-$raw_avg) > ($start_time-$accuracy)) and
		 ((($current_time*100)-$raw_avg) < ($start_time+$accuracy))) {
	    # Estimated server start time within the calculated accuracy
	    # Forget previous record (no new information)
	    # remember current record.
	    $valid_values++;
	    copy2prv();
	    $remember_record = "yes";
	} else {
	    # Estimated server start time not within the calculated accuracy
	    # Something wrong happened with the measurements.
	    # This configuration ID has not been measured correctly.
	    #error("Invalid measurement for configID $raw_config at $raw_date_time (avg: $raw_avg)");
	    $invalid_values++;
	    if ($valid_values == 1) {
		# False starts have been notified, forget about first record and remember second record only
		# However do not reset valid values counter to avoid looping when next record is also not in synch.
		copy2prv();
		$invalid_values--;
	    } elsif (($invalid_values*10) > $valid_values) {
		error("Number of invalid measurements for configID $raw_config too high ($valid_values valid, $invalid_values invalid), skipping config ID");
		$invalid_values--;
		logging("Investigated $valid_values valid records and $invalid_values invalid records.");
		$errors++;
		$invalid_config = $raw_config;
		$sysup_record = "";
		$remember_record = "no";
	    }
	}
    }
}

=pod

=head2 Handle Record

The record is verified for validity:

=over 4

=item *

Test for sufficient number of fields

=item *

Test if config ID is still valid. When an error is found, the config ID is invalid and other records for this config ID are no longer handled.

=item *

Test for SysUpTime > 0. Average SysUpTime=0 or lower is not possible.

=item *

Check for Application=DEVICE, Instance=Net. Other values are not yet accepted.

=back

=cut

sub handle_record() {
    if ($raw_config == $invalid_config) {
	$skipped++;
    } elsif (not(defined($raw_nbrmeas))) {
	$errors++;
	$sysup_record = "";
	$remember_record = "no";
	$invalid_config = $raw_config;
	error("Insufficient fields: $verify_record");
    } elsif ($raw_param ne "sysUpTime") {
	error("Invalid parameter $raw_param for config id $raw_config");
	$errors++;
	$sysup_record = "";
	$remember_record = "no";
	$invalid_config = $raw_config;
    } elsif ($raw_appl ne "NET") {
	error("Invalid application $raw_appl for config id $raw_config");
	$errors++;
	$sysup_record = "";
	$remember_record = "no";
	$invalid_config = $raw_config;
    } elsif ($raw_instance ne "Device") {
	error("Invalid instance $raw_instance for config id $raw_config");
	$errors++;
	$sysup_record = "";
	$remember_record = "no";
	$invalid_config = $raw_config;
    } elsif ($raw_avg <= 0 ) {
	error("Invalid SysUptime $raw_avg for config id $raw_config");
	$errors++;
	$sysup_record = "";
	$remember_record = "no";
	$invalid_config = $raw_config;
    } else {
	if ($raw_config == $prv_config) {
	    same_config();
	} else {
	    new_config();
	}
    }
}

=pod

=head2 Handle File

This subroutine opens the file for input, creates a file for output and reads through the records.

=cut

sub handle_file($) {
    my($filename) = @_;
    my $openres = open(RAW_SYSUPTIME, "$srcdir/$filename");
    if (not(defined($openres))) {
	error("Could not open $srcdir/$filename for reading.");
	exit_application(1);
    }
    $openres = open(CHECK_SYSUPTIME, ">$srcdir/CHECK_$filename");
    if (not(defined($openres))) {
	error("Could not open $srcdir/CHECK_$filename for writing.");
	exit_application(1);
    }
    $cnt=0;
    $errors=0;
    $skipped=0;
    # Find SMC number
    $smc=substr($filename,length("spi_"),length($filename)-length("spi_")-length("_sysuptime.dat"));
    $invalid_config=-1;
    $prv_config=-1;
    while ($verify_record = <RAW_SYSUPTIME>) {
	chomp $verify_record;
	$cnt++;
	($raw_spi,$raw_config,$raw_appl,$raw_instance,$raw_param,$raw_date_time,$raw_interval,$raw_min,$raw_avg,$raw_max,$raw_nbrmeas) = split(",",$verify_record);
	# Get rid of leading and trailing spaces
	$raw_spi	= trim($raw_spi);
	$raw_config	= trim($raw_config);
	$raw_appl	= trim($raw_appl);
	$raw_instance	= trim($raw_instance);
	$raw_param	= trim($raw_param);
	$raw_date_time	= trim($raw_date_time);
	$raw_interval	= trim($raw_interval);
	$raw_min	= trim($raw_min);
	$raw_avg	= trim($raw_avg);
	$raw_max	= trim($raw_avg);
	$raw_nbrmeas	= trim($raw_nbrmeas);
	# Get rid of "T" test indicator on smc (spi) and config_id
	if (substr($raw_spi,0,1) eq "T") {
	    $raw_spi = substr($raw_spi,1);
	}
	if (substr($raw_config,0,1) eq "T") {
	    $raw_config = substr($raw_config,1);
	}
	handle_record();
    }
    if ($remember_record eq "yes") {
	remember_sysup_record();
	$remember_record = "no";
    }
    if (length($sysup_record) > 0) {
	print CHECK_SYSUPTIME $sysup_record;
	$sysup_record = "";
    }
    if (($prv_config > 0) and not($prv_config == $invalid_config)) {
	logging("Config ID: $prv_config, $valid_values valid records, $invalid_values invalid records");
    }
    close RAW_SYSUPTIME;
    close CHECK_SYSUPTIME;
    logging("Summary for $filename:");
    logging("$cnt records handled");
    logging("$errors error records");
    logging("$skipped records skipped");
}

######
# Main
######

# Handle input values

my %options;
getopts("tl:d:h:", \%options) or pod2usage(-verbose => 0);
#my $arglength = scalar keys %options;  
#if ($arglength == 0) {			# If no options specified,
#    $options{"h"} = 0;			# display usage.
#}
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
}
$logdir = logdir();
if (-d $logdir) {
    trace("Logdir: $logdir");
} else {
    pod2usage(-msg     => "Cannot find log directory ".logdir,
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
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

=pod

=head2 Find all files to investigate

This section scans through the directory and checks for each file name if it fulfills the requirements. If so, then the Handle File procedure is called.

=cut

my (@dirlist);
if (!(opendir (DIR, $srcdir))) {
    error "Opendir $srcdir failed!";
    exit_application(1);
} else {
    my @dirlist = readdir(DIR);
    closedir DIR;
    foreach my $filename (@dirlist) {
        if ((substr($filename,0,length("spi_")) eq "spi_") and
            (substr($filename,-length("_sysuptime.dat")) eq "_sysuptime.dat")) {
		logging("Now handling file $filename");
		handle_file("$filename");
	}
    }
}

exit_application(0);

=pod

=head1 Testplan

=over 4

=item *

Check on invalid SMC number

=item *

Check in invalid record: missing field, additional field

=item *

Check for parameter not equal "sysUpTime"

=back

=head1 To Do

=over 4

=item *

Add input parameter option for accuracy

=item *

Check for subsequent and equal times.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
