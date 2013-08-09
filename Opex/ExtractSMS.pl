=head1 NAME

ExtractSMS - Extract SMS messages from Print report.

=head1 VERSION HISTORY

version 1.0 4 June 2003 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application extracts SMS Messages from a print report and add all messages to a csv file. The format of the message line is B<Date;Time;From;Message>.

For a Nokia 6210 the input file creation requires a few steps. Setup the PC Suite 4, select C<Nokia Phone Editor>, select C<Messages> and select all required messages. The messages can be printed to a C<FILE:> printer.

Currently the input file must be C<C:\TEMP\SMSTXT.TXT>, all messages are appended to the output file C<C:\TEMP\SMS_RECEIVE.CSV>.

=head1 SYNOPSIS

ExtractSMS.pl [-t] [-l log_dir]

    ExtractSMS -h	    Usage
    ExtractSMS -h 1	    Usage and description of the options
    ExtractSMS -h 2	    All documentation

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
my $inputfile = "c:/temp/smstxt.txt";		# Inputfile
my $outputfile = "c:/opex/sms/sms_receive.csv";		# Outputfile
my $line;
my $startstring = "Date & Time:";

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

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
    close INPUT;
    close OUTPUT;
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

=head2 Handle Message Procedure

A message block starts with "Date & Time:". The Date and Time are extracted into separate fields. Next line is "From:" field, telephone number is extracted, the "To:" field is ignored, then there is an empty line and the next line is the message.

=cut

sub handle_message {
    # Extract Date and Time
    $line =  trim $line;	# Remove leading spaces
    my $datetime = trim substr($line, length($startstring));
    my ($date,$time) = split(/ /, $datetime);
    
    # Extract Sender phone number
    # This should never change, but you know only by verification!
    my $searchstring = "From:";
    $line = <INPUT>;
    if (index($line, $searchstring) == -1) {
	error("$searchstring not found when expected, exiting...");
	exit_application(1);
    }
    $line = trim $line;
    my $sender = trim substr($line, length($searchstring));
    
    # Now find Message
    # First line is "To: "
    $line = <INPUT>;
    # Next line is empty line
    $line = <INPUT>;
    # Now the message
    $line = <INPUT>;
    my $message = trim $line;

    # Print all to the output file
    print OUTPUT "$message;$date;$time;$sender\n";
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

my $openres = open(INPUT, $inputfile);
if (not(defined $openres)) {
    error("Could not open $inputfile for reading, exiting...");
    exit_application(1);
}

$openres = open(OUTPUT, ">$outputfile");
if (not(defined $openres)) {
    error("Could not open $outputfile for appending, exiting...");
    exit_application(1);
}

while ($line = <INPUT>) {
    chomp $line;
    if (index($line,$startstring) > -1) {
	handle_message();
    }
}

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
