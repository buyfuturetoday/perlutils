=head1 NAME

MRA_Conf_Quiet.pl - Configure MRA quiet setting to enable/disable debugging on event console.

=head1 VERSION HISTORY

version 1.0 - 22 April 2005 DV

=over 4

=item *

Initial Release

=back

=head1 DESCRIPTION

This application configures the 'quiet' setting for all actions related to (a) message record(s). It accepts a message record identifier and updates the 'quiet' setting for all associated message actions. One or more message record can be specified.

The cautil utility does not allow to select a message record, read the token and perform an action on the associated message actions. Therefore this script...

It is possible to use cautil to update the quiet field in all msgactions over all message records, but this may not offer the requested level of granularity.

If valid message records are found, then an 'opreload' is done on the OPR database.

ISSUE: It is not possible to extract the Message Token automatically using cautil select statements. It is possible using "oprdb list db", but oprdb reloads the database at that time (and it is not an elegant way).

=head1 SYNOPSIS

 MRA_Conf_Quiet.pl [-t] [-l logfile_directory] -m msgid -q Y|N

 MRA_Conf_Quiet.pl -h	Usage Information
 MRA_Conf_Quiet.pl -h 1	Usage Information and Options description
 MRA_Conf_Quiet.pl -h 2	Full documentation

=head1 OPTIONS

=over 4

=item B<-t>

if set, then trace messages will be displayed. 

=item B<-l logfile_directory>

default: c:\temp\log

=item B<-m msgid>

Message ID that is used in the select statement 'cautil select msgrecord msgid="msgid"'. The message id must be specified. It will be passed to the cautil statement unchanged.

=item B<-q Y|N>

Parameter for 'quiet' mode. Must be 'Y'(es) or 'N'(o).

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
###########

my $outputdir = "c:/temp";	    # Temporary output directory
my ($msgid, $quiet, $msgfile, $errfile);
my ($logdir);

#####
# use
#####

use warnings;			    # show warnings
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Input parameter handling
use Pod::Usage;			    # Usage printing
use Log;

#############
# subroutines
#############

sub exit_application($) {
    my($return_code) = @_;
    if (-r $msgfile) {
    #	unlink $msgfile;
	logging ("Message file $msgfile deleted");
    }
    if (-r $errfile) {
    #	unlink $errfile;
	logging ("Message file $errfile deleted");
    }
    logging("Exit application with return code $return_code\n");
    close_log();
    exit $return_code;
}

######
# Main
######

# Handle input values
my %options;
getopts("tl:h:m:q:", \%options) or pod2usage(-verbose => 0);
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
} else {
    $logdir=logdir();
}
if (-d $logdir) {
    trace("Logdir: $logdir");
} else {
    pod2usage(-msg     => "Cannot find log directory ".logdir,
	      -verbose => 0);
}
# Logdir found, start logging
open_log();
logging("Start application");
# Find Message ID
if ($options{"m"}) {
    $msgid = $options{"m"};
} else {
    error("Message ID not specified, exiting ...");
    exit_application(1);
}
# Find quiet setting
if ($options{"q"}) {
    $quiet = $options{"q"};
    if (($quiet ne "Y") and ($quiet ne "N")) {
	error ("Quiet setting must be Y or N (uppercase!)");
	exit_application(1);
    }
} else {
    error("Quiet setting not specified, exiting ...");
    exit_application(1);
}
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Launch cautil command to find Message Tokens
if (not(-d $outputdir)) {
    error ("Cannot find temporary directory $outputdir, exiting ...");
    exit_application(1);
}
$msgfile = "$outputdir/cautil_msg_" . time . ".txt";
$errfile = "$outputdir/cautil_err_" . time . ".txt";
my $cmdline = "cautil select msgrecord msgid=\"$msgid\" save msgrecord file=$msgfile format=cautil > $errfile 2>&1";
system($cmdline);

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

This script could be extended to accept any Message Action parameter and value (e.g. to selectively configure the 'FORWARD' node for specified Message Records).

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
