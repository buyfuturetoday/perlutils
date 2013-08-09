=head1 NAME

Update_FWD - Updates the FORWARD destination in the "FORWARD" Message Record

=head1 VERSION HISTORY

version 1.0 10 May 2005 DV

=over 4

Initial release.

=back

=head1 DESCRIPTION

This script accepts a servername and updates the "FORWARD" destination in the FORWARD Message record. Therefore the FORWARD Message record token number must be obtained, to know which message actions to update.

=head1 SYNOPSIS

Update_FWD.pl EventServer

=head1 OPTIONS

=over 4

=item B<EventServer>

The Event Server where the messages need to be send to.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.8.3, build 809 provided by ActiveState.

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my $log = 1;			    # Log flag. 1 for logging, 0 for not logging
my $logdir = "c:/temp";
my @evtargs;
my ($targetserver, $command, $res_command, $token, $msgrec_file);
my $msgid = "FORWARD|*";
my $cautil_tmp = "c:/temp/cautil_tmp.txt";  # Temporary output file

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

=head2 Find Output file

The cautil -csv writes the output in a file. The file location is specified as an error string.

=cut

sub find_output_file() {
    my $openres = open(OUTFILE, $cautil_tmp);
    if (not(defined $openres)) {
	error("Could not open $cautil_tmp for reading, exiting ....");
	exit_application(1);
    }
    my $line = <OUTFILE>;
    close OUTFILE;
    chomp $line;
    my $startpos = length("%CARTC_I_006, Output report file name is '");
    my $endpos = index($line, "'", $startpos+1);
    $msgrec_file = substr($line,$startpos, $endpos - $startpos);
    print "*** $msgrec_file ***";
}

=pod

=head2 Find Token

The Token appears to be the first item on the second line ...

=cut

sub find_token() {
    my $openres = open(OUTFILE, $msgrec_file);
    if (not(defined $openres)) {
	error("Could not open $msgrec_file for reading, exiting ....");
	exit_application(1);
    }
    my $line = <OUTFILE>;
    # My info is on the second line
    $line = <OUTFILE>;
    chomp $line;
    my @fields = split /,/, $line;
    $token = $fields[0];
    print " *** Token: $token ***";
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
	my $scriptname = "Update_Fwd";
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
    print "Error: $errorline\n";
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

# Define target event server
$targetserver = shift @ARGV;

# Find Message Token for Message ID
$command = "cautil -csv select msgrec msgid=\"$msgid\" list msgrec 2>$cautil_tmp";
$res_command = system($command);
if (not($res_command == 0)) {
    error("Could not execute command $command");
    exit_application(1);
}

find_output_file();
find_token();

$command = "cautil select msgaction name=($token,*) action=\"FORWARD\" alter msgaction node=$targetserver";
$res_command = system($command);
if (not($res_command == 0)) {
    error("Could not execute command $command");
    exit_application(1);
}

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Include error reporting to back to the event console using cawto (or display error messages on the console using a popup window.

=item *

Test connectivity to the Event Server before trying to send all events.

=item *

Test successful cawto on each transmission

=item *

Add a label to TEXT messages to inform remote system on delays.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
