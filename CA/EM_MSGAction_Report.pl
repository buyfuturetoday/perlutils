=head1 NAME

EM_MSGAction_Report - Create a report from a message action for usage by the EEIB interface or the cawto utility

=head1 VERSION HISTORY

version 1.1 19 April 2005 DV

=over 4

=item *

Modify script to generate files that can be used as input for cawto commands to allow more control on the message forward. 

=item *

Add logging into script instead of using dedicated Log.pm module. Logging is no longer mandatory and should be done only for debugging purposes.

=back

version 1.0 4 April 2003 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application is executed as a message action from the Unicenter Event Console. It accepts the event parameters from the message actions and puts them in a file for further processing by the EEIB application or the cawto application.

The parameters are identified using "-name value" combinations.

For EEIB the name is the variable name as specified required for the bo2fotng.pl script. The value can be empty or can contain data, depending on the event.

For cawto the names must be the command arguments that will be used as input for the cawto command. Files will be written to a directory that is only used for that purpose. Make sure the outputdir in the script points to the right directory.

It is mandatory to use the record number as the first parameter. The record number is the unique identifier for the filename.

=head1 SYNOPSIS

EM_MSGAction_Report.pl record_id {-name value}

=head1 OPTIONS

=over 4

=item B<record_id>

The unique record_id of the event (Event-related variable: &LOGRECID). This is used as the filename for the bo2fotng.pl application.

=item B<-name value>

name - value pairs. The name must be preceded by a dash "-" and the parameter name. There is no space between the dash and the parameter name.

The name - value pairs can be plain text, to allow fixed values appearing in the result file.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.8.0, build 804 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my $identifier = "-";		    # Unique identifier for Parameter names
my ($value,$valuestring);
my $log = 1;			    # Log flag. 1 for logging, 0 for not logging
# my $outputdir = "%AGENTWORKS_DIR%/Temp";  # Output directory for EEIB interface
# my $outputdir = "d:/em/data/cawtotemp";	    # Output directory for cawto utility
my $outputdir = "c:/temp/cawtotemp";	    # Output directory for cawto utility
my $logdir = "c:/temp";

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
    close EEIBFile;
    logging("Exit application with return code: $return_code\n");
    close_log();
    exit $return_code;
}

sub trim {
    my @out = @_;
    for (@out) {
        s/^\s+//;
        s/\s+$//;
    }
    return wantarray ? @out : $out[0];
}

=pod

=head2 open_log

The procedure opens the logfile for the script and associates a filehandle to the logfile.

The current date (YYYYMMDD) is appended to the scriptname. 

The autoflush is on for the logfile. This means that no messages are buffered. In case of system crashes more messages should be in the log file.

If the logfile directory does not exist or if the logfile could not be opened, then the return value of the subroutine is undefined. Otherwise the return value is 0.

=cut

sub open_log() {
    if ($log == 1) {
	if (not(-d $logdir)) {
	    print "$logdir does not exist, cannot open logfile\n";
	    exit;
	}
	my $scriptname = "EM_MSGAction_Report";
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $computername = $ENV{COMPUTERNAME};
	my $logfilename=sprintf(">>$logdir/$scriptname"."_$ENV{COMPUTERNAME}_%04d%02d%02d.log", $year+1900, $mon+1, $mday);
	my $openres = open (LOGFILE, $logfilename);
	if (not(defined $openres)) {
	    print "Could not open $logfilename\n";
	}
	# Ensure Autoflush for Log file...
	my $old_fh = select(LOGFILE);
	$| = 1;
	select($old_fh);
    }
    return 0;
}

=pod

=head2 handle_logging("Log message")

This procedure will add log messages to the log file, if the log flag is set. The current date and time is calculated, prepended to the log message and the log message is appended to the logfile. A "Carriage Return/Linefeed" is appended to the log message.

=cut

sub logging($) {
    if ($log == 1) {
	my($txt) = @_;
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
	print LOGFILE $datetime." * $txt"."\n";
    }
}

=pod

=head2 error_logging("Error Message")

For now this procedure will call the logging procedure. The idea is that for error messages a line is written to the event log.

=cut

sub error($) {
    my ($errorline) = @_;
    logging($errorline);
}

=pod

=head2 close_log

If the logfile is opened, then this procedure will close the logfile.

=cut

sub close_log() {
    if ($log == 1) {
	close LOGFILE;
    }
}

######
# Main
######

open_log();
logging("Start application");

my $nbr_args = @ARGV;
if ($nbr_args == 0) {
    error("No arguments specified");
    exit_application(1);
} else {
    logging("Argument list: @ARGV");
}

# Find the output directory.
# If the directory cannot be found, script will stop.
if (not(-d $outputdir)) {
    error("Directory $outputdir for temporary storage does not exist, exiting ....");
    exit_application(1);
}

# First value must be a unique identifier for the file name.
my $filename = shift @ARGV;
my $timeticks = time();
$filename = "$timeticks"."_$filename";
if (not(defined $filename)) {
    error("Unique filename identifier not defined.");
    exit_application(1);
} elsif (-r "$outputdir/$filename.txt") {
    error("Requested file $outputdir/$filename.txt already exists");
    exit_application(1);
}

# Filename is found and seems to be unique, so open file now.
my $openres = open (EEIBFile, ">$outputdir/$filename.txt");
if (not(defined $openres)) {
    error("Could not open $outputdir/$filename.txt for writing.");
    exit_application(1);
}

# Second argument must be a parameter name
my $name = shift @ARGV;
if (not($identifier eq substr($name,0,length($identifier)))) {
    error("Second value in arg list must be a parameter name as identified with $identifier");
    exit_application(1);
} else {
    # Remove identifier from name
    $name = substr($name,length($identifier));
}

=pod

=head2 Handle Argument list

The parameter value can be 3 cases: no parameter value OR parameter value of one word OR parameter value of more than one word.

Read @ARGV until end of string or until new parameter name, print name/value pair.

=cut

$valuestring = "";
$value = shift @ARGV;
while (defined $value) {
    if ($identifier eq substr($value,0,length($identifier))) {
	# Next parameter name found - print previous name / value pair
	# and initialize new name / value pair
	trim $valuestring;
	print EEIBFile "$name:$valuestring\n";
	$name = $value;
	# Remove identifier from name
	$name = substr($name,length($identifier));
	$valuestring = "";
    } else {
	$valuestring = $valuestring.$value." ";
    }
    $value = shift @ARGV;
}
# End of argument list reached.
trim $valuestring;
print EEIBFile "$name:$valuestring";

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Include error reporting to back to the event console using cawto (or display error messages on the console using a popup window.

=item *

Verify if timeticks need to be added to the temporary filename, to make them unique across days.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
