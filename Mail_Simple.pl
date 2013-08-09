=head1 NAME

Mail_Simple - Accepts all required parameters and sends a mail to list of recipients.

=head1 VERSION HISTORY

version 1.2 11 May 2005 DV

=over 4

=item *

Call module mail_simple, no need to send attachments and no need for mime module.

=back

version 1.1 22 October 2002 DV

=over 4

=item *

Rework script to use module Mail.pm.

=back

version 1.0 16 October 2002 DV

=over 4

=item *

Initial release, based on the script MobileSys_sms.pl

=back

=head1 DESCRIPTION

This application attempts to send mail messages to list of recipients. It is a wrapper for the Mail_Simple.pm module.

=head1 SYNOPSIS

Mail_Simple.pl [-t] [-l log_dir] -d recipients [-s smtp_server] -o sender -m message [-u subject] [-p]

    Mail -h	    Usage
    Mail -h 1	    Usage and description of the options
    Mail -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: c:\temp

=item B<-d recipients>

The mail addresses where the message must be send to. Use ";" to separate recipients.

=item B<-s smtp_server>

The smtp server used to transfer your mail message. Default: forwarder.eds.com

=item B<-o sender>

Mandatory. The original sender of the mail.

=item B<-m message>

Mandatory. The message to be send in the mail. Enclose the message in quotes.

=item B<-u subject>

Subject from the mail message.

=item B<-p>

If set, then smtp debug information is displayed on STDOUT.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.6.1, build 631 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my $logdir;
my $mail_address;			    # Destination for SMS messages
my $subject = "";
my $smtp_server = "forwarder.eds.com";	    # Default SMTP forwarder
my ($mail_address, $message, $banner, $res);
my ($smtp, $recipient, $sender, $smtp_debug);

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
use Mail_simple;

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
    logging("Exit application with return code: $return_code\n");
    close_log();
    exit $return_code;
}

######
# Main
######

# Handle input values
my %options;
getopts("tl:d:s:o:m:u:ph:", \%options) or pod2usage(-verbose => 0);
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
    trace_flag(1);
    trace("Trace enabled");
}
# Find log file directory
if ($options{"l"}) {
    $logdir = logdir($options{"l"});
} else {
    $logdir = logdir();
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
# Find SMS mail address destination
if ($options{"d"}) {
    $res = mail_address($options{"d"});
    if (not(defined $res)) {
	error("Could not set mail address, exiting...");
	exit_application(1);
    }
}
# Find SMTP Server
if ($options{"s"}) {
    $res = smtp_server($options{"s"});
}
# Find sender of the mail
if ($options{"o"}) {
    $res = sender($options{"o"});
} else {
    error("No sender defined, exiting ...");
    exit_application(1);
}
# Find message to send
if ($options{"m"}) {
    $res = message($options{"m"});
} else {
    error("No message found, exiting ...");
    exit_application(1);
}
# Find subject
if ($options{"u"}) {
    $res = subject($options{"u"});
}
# Check for smtp debug information
if (defined $options{"p"}) {
    $res = smtp_debug(1);
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values
my $msg = message();
$msg = $msg . "\nsecond line \n third line \n and so on ...";
message($msg);
$res = send_mail();

if (defined $res) {
    logging("Message has been sent");
} else {
    error("Could not send message");
    exit_application(1);
}

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Accept input values from a file or from input (input overrides file).

=item *

Allow for multiple smtp forwarder addresses, for compensation if one of the forwarders cannot be reached.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
