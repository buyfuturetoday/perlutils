=head1 NAME

Fwd_Event.pl - This script walks through the directory that was created from the EM_MSGAction_Report.pl script and forwards the events to the requested destination.

=head1 VERSION HISTORY

version 2.0 8 June 2005 DV

=over 4

=item * 
Forward events using logforward instead of cawto.

=item * 
Allow for blanks and special characters in all fields

=back

version 1.0 19 April 2005 DV

=over 4

=item *
Initial release.

=back

=head1 DESCRIPTION

This script reads the directory with all events that could not yet be forwarded. Each file contains one event. The file is read and a logforward message is created. When the logforward was successful then the file is deleted. Each event file exists of key/value pairs. Acceptable keys are the key values for the 'logforward' command: FromNode, Severity, Userid, Station, Device, Category, Userdata, Tag, Source, Text.

The messages start with identifier "DELAYED".

This script must be run once as part of the site failover actions.

=head1 SYNOPSIS

Fwd_Event.pl EventServer

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

my $identifier = "-";		    # Unique identifier for Parameter names
my ($value,$valuestring, $logdir);
# my $outputdir = "%AGENTWORKS_DIR%/Temp";  # Output directory for EEIB interface
# my $inputdir = "d:/em/data/cawtotemp";	    # Output directory for cawto utility
my $inputdir = "c:/temp/cawtotemp";	    # Output directory for cawto utility
my $arglist;
my $targetserver;
my %logforward_args = (FromNode => "f",
		       Severity => "v",
		       Userid   => "u",
		       Station  => "x",
		       Device   => "q",
		       Category => "g",
		       Userdata => "d",
		       Tag	=> "p",
		       Source   => "s",
		       Text     => "t");

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Log;

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

=head2 Send Event

The Send Event procedure will forward the event to the requested event console. Each forward event must return a success. If not successful, then this script will be interrupted and the current event server will not be considered active.

=cut

sub send_event() {
    my $cmd = "logforward $arglist";
    my @cmd_output = `$cmd`;
    my $cmd_lines = @cmd_output;
    if ($cmd_lines == 0) {
	logging("Successfully send record $targetserver\n$cmd");
	return 0;
    } else {
	error("Error while sending record to $targetserver\nCommand: $cmd\n@cmd_output");
	exit_application(1);
    }
}

=pod

=head2 Handle File

Each file in the directory is handled separately. Each line in the file is read and split up in an key / value pair. The key is the option name for the cawto command, value is the string that goes with this option. The text key does not have an option name.

Option names for empty values are omitted since they do not add information to the cawto command.

It is mandatory that the EM_MSGAction_Report.pl command in the MRA has a valid cawto syntax as this script will copy the input without additional processing.

=cut

sub handle_file($) {
    my ($evtfile) = @_;
    my ($text, $node);
    my $openres = open (EVTFILE, $evtfile);
    if (not(defined $openres)) {
	error ("Could not open $evtfile for reading!");
	return;
    }
    # Initialize events with target node
    $arglist = "-n$targetserver";
    while (my $line = <EVTFILE>) {
	chomp $line;
	# Format is "name:valuestring", so find first semicolon
	# Do not use "split", since this will split on each semicolon
	my $keylength = index($line,":");
	if ($keylength == -1) {
	    error ("No key / value pair found on line $line, file $evtfile, ignoring line.");
	} else {
	    # Only add to list if value is specified, 
	    # do not add empty key / value pairs
	    if (($keylength+3) < length($line)) {	# :"" are there for empty values!
		my $key = substr($line,0,$keylength);
		my $value = substr($line,$keylength+1);
		# All values have additional blank => get rid of it!
		$value = trim $value;
		# Add "DELAYED" to text string from delayed events
		if ($key eq "Text") {
		    $value = "DELAYED $value";
		}
		# and enclose value with double quotes
		$value = "\"".$value."\"";
		# Recreate all key / value pairs as input for logforward
		# Translate key to character
		if (defined($logforward_args{$key})) {
		    $arglist = $arglist . " -$logforward_args{$key}"."$value";
		} else {
		    error("No valid key found on line $line, file $evtfile, ignoring line");
		}
	    }
	}
    }
    close EVTFILE;
    my $sendres = send_event();
    if ($sendres == 0) {
	print "Now deleting file $evtfile\n";
        unlink $evtfile;
    }
}

=pod

head2 Check Connectivity 

This procedure checks the connectivity to the remote event server. If successful then all files will be processed. Otherwise an error message is printed and no files are processed.

=cut

sub check_connectivity($) {
    my ($nr_of_files) = @_;
    $nr_of_files = $nr_of_files - 2;
    my $textline = "Start sending $nr_of_files delayed events.";
    $arglist = "-n$targetserver -t\"$textline\" -cblue -areverse";
    send_event();
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

# Find the input directory.
# If the directory cannot be found, script will stop.
if (not(-d $inputdir)) {
    error("Directory $inputdir for temporary storage does not exist, exiting ....");
    exit_application(1);
}

# Define target event server
$targetserver = shift @ARGV;

# Read files in directory and handle each file
if (not(opendir(EVENTDIR, $inputdir))) {
    error ("Collect directory list for $inputdir failed, exiting ...");
    exit_application(1);
}

my @dirlist = readdir(EVENTDIR);
# sort directory list to guarantee delivery in order of events received.
@dirlist = sort @dirlist;
my $nr_files = @dirlist;
closedir(EVENTDIR);

check_connectivity($nr_files);

foreach my $filename (@dirlist) {
    if (("$filename" ne ".") && ("$filename" ne "..")) {
	my $evtfile = $inputdir."/$filename";
	if (-f $evtfile) {
	    handle_file($evtfile);
	}
    }
}

my $textline = "End of delayed events";
$arglist = "-n$targetserver -t\"$textline\" -cblue -areverse";
send_event();

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
