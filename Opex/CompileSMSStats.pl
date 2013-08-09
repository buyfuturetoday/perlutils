=head1 NAME

CompileSMSStats - Compile sms.txt (bemon001) and sms_receive file into SMS Statistics information

=head1 VERSION HISTORY

version 1.0 4 June 2003 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application reads the file sms.txt that is created on bemon001 and that contains the information on time and content of each SMS Send. All values are stored in a hash and the file is deleted.

Then the received messages as available from the application ExtractSMS.pl are read one by one. If the message has been sent, then delivery statistics are calculated and the message is appended to the file sms_stats.csv. Else the message is appended to the file sms_receive_orphan.csv. The sms_receive.csv file is deleted after processing.

When a message is found, then it is removed from the hash. When all received messages are handled, then the remainder of the hash is written to the file sms_not_yet_received.txt. On the next run, this file should be I<pre-pended> to the file sms.txt that is moved from the C<bemon001\\d:\opex\log> directory.

=head1 SYNOPSIS

CompileSMSStats.pl [-t] [-l log_dir]

    CompileSMSStats -h	    Usage
    CompileSMSStats -h 1    Usage and description of the options
    CompileSMSStats -h 2    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: B<d:\opex\log>

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.8.0, build 804 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my $logdir;
my $sms_send_file = "c:/opex/sms/sms.txt";
my $sms_statistics_file = "c:/opex/sms/sms_statistics.csv";
my $sms_ny_received_file = "c:/opex/sms/sms_ny_received.csv";
my $sms_receive_file = "c:/opex/sms/sms_receive.csv";
my $sms_receive_orphan_file = "c:/opex/sms/sms_receive_orphan.csv";
my %sms = ();

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

######
# Main
######

# Handle input values
my %options;
getopts("tl:d:h:", \%options) or pod2usage(-verbose => 0);
# my $arglength = scalar keys %options;  
# if ($arglength == 0) {			# If no options specified,
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
    Log::trace_flag(1);
    Log::display_flag(1);
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
    $logdir = logdir("d:\\opex\\log");
    if (not(defined $logdir)) {
	print "Could not set d:\\opex\\log as Log directory, exiting...";
	exit 1;
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

# Open the sms send file
my $openres = open(SEND, $sms_send_file);
if (not(defined $openres)) {
    error("Could not open $sms_send_file for reading, exiting...");
    exit_application(1);
}

# Read all lines and fill up the hash
while (my $line = <SEND>) {
    chomp $line;
    my ($date,$time,$message) = split (/;/,$line);
    $message = trim $message;
    my ($hour,$min,$sec) = split(/:/,$time);
    my ($mday,$mon,$year) = split(/\//,$date);
    $mon = $mon - 1;		# Months since January
    $sms{$message} = timelocal($sec,$min,$hour,$mday,$mon,$year);
}
close SEND;

# Now also open the "Not yet received" lines and add to the hash
$openres = open(SEND, $sms_ny_received_file);
# This file may not be available
if (not(defined $openres)) {
    error("Could not open $sms_ny_received_file for reading.");
} else {
# Read all lines and fill up the hash
    while (my $line = <SEND>) {
	chomp $line;
	my ($date,$time,$message) = split (/;/,$line);
	$message = trim $message;
	my ($hour,$min,$sec) = split(/:/,$time);
	my ($mday,$mon,$year) = split(/\//,$date);
	$mon = $mon - 1;		# Months since January
	$sms{$message} = timelocal($sec,$min,$hour,$mday,$mon,$year);
    }
    close SEND;
}

# Open Statistics file for append
$openres = open(STATS, ">>$sms_statistics_file");
if (not(defined $openres)) {
    error("Could not open $sms_statistics_file for appending, exiting...");
    exit_application(1);
}

# Open Receive file for reading
$openres = open(RECEIVE, "$sms_receive_file");
if (not(defined $openres)) {
    error("Could not open $sms_receive_file for reading, exiting...");
    exit_application(1);
}

# Open Orphan file for appending
$openres = open(ORPHAN, ">$sms_receive_orphan_file");
if (not(defined $openres)) {
    error("Could not open $sms_receive_orphan_file for appending, exiting...");
    exit_application(1);
}

# Read through Receive file
while (my $line = <RECEIVE>) {
    chomp $line;
    my ($message,$date,$time) = split(/;/,$line);
    my ($hour,$min,$sec) = split(/:/,$time);
    my ($mday,$mon,$year) = split(/\//,$date);
    $mon = $mon - 1;		# Months since January
    # Receive time is UK time => Add 1 hour to be able to compare!
    my $rec_time = timelocal($sec,$min,$hour,$mday,$mon,$year) + 3600;
    if (exists($sms{$message})) {
	# Send - Receive pair found for message
	# Calculate time between send and receive in minutes
	my $tx_time = int (($rec_time - $sms{$message}) / 60);
	# Restore Date/Time message sent
	($sec,$min,$hour,$mday,$mon,$year,undef,undef,undef) = localtime($sms{$message});
	my $outputline = sprintf("%02d/%02d/%4d;%02d:%02d", $mday,$mon+1,$year+1900,$hour,$min);
	# Calculate Continental time message received
	($sec,$min,$hour,$mday,$mon,$year,undef,undef,undef) = localtime($rec_time);
	$time = sprintf("%02d:%02d",$hour,$min);
	# Compile output line
	$outputline = $outputline.";$message;;$time;$tx_time\n";
	# Write to the Statistics file
	print STATS $outputline;
	# Delete $message from hash: all info was received
	delete ($sms{$message});
    } else {
	# Message received but no matching send found => orphan
	print ORPHAN "$line\n";
    }
}
    

# Close Statistics file
close STATS;
# Close Receive file (unlink as well?)
close RECEIVE;
# Close Orphan file
close ORPHAN;

# Last Action: all remaining entries in %sms hash are saved in a file
# Open the sms_ny_received file
$openres = open(NYRECEIVED, ">$sms_ny_received_file");
if (not(defined $openres)) {
    error("Could not open $sms_ny_received_file for appending, exiting...");
    exit_application(1);
}
# Find all remaining data, convert to original output string
while (my ($message, $timeval) = each %sms) {
    my ($sec,$min,$hour,$mday,$mon,$year,undef,undef,undef) = localtime($timeval);
    my $outputline = sprintf("%02d/%02d/%4d;%02d:%02d:%02d", $mday,$mon+1,$year+1900,$hour,$min,$sec);
    print NYRECEIVED "$outputline;$message\n";
}
close NYRECEIVED;

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Allow to specify an input file location.

=item *

Allow to specify an output file location.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
