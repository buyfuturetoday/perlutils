=head1 NAME

MobileSys_sms - Sends XML string to MobileSys application for distributing SMS messages.

=head1 VERSION HISTORY

version 1.2 22 October 2002 DV

=over 4

=item *

Resolved an issue with the settings towards the Log module.

=back

version 1.1 16 October 2002 DV

=over 4

=item *

Removed leading and trailing blanks from recipient list

=back

version 1.0 27 September 2002 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application accepts a string for formatting and sending as an SMS message.
The application can be used as a front-end for the MobileSYS application.

=head1 SYNOPSIS

MobileSys_sms.pl [-t] [-l log_dir] [-d mcs_sms_mail_address] -s smtp_server -o sender -r recipient_list -m message -a application_name [-b Billing_information] [-p]

    MobileSys_sms -h	    Usage
    MobileSys_sms -h 1	    Usage and description of the options
    MobileSys_sms -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: c:\temp

=item B<-d mcs_sms_mail_address>

The mail address where the MCS MobileSys application listens for your messages. Default: SMS@europe.eds.com

=item B<-s smtp_server>

Mandatory. The smtp server used to transfer your mail message.

=item B<-o sender>

Mandatory. The original sender of the mail.

=item B<-r recipient_list>

Mandatory. The list of the mobile destination numbers, in the format specified by the MCS SMS service description. Enclose the message in quotes, separate messages with a comma.

Format : +countrycode provider mobilenumber (including the spaces !)

=item B<-m message>

Mandatory. The message to be send as an SMS. Enclose the message in quotes.

=item B<-a application_name>

Mandatory. Name of the application as defined in the MSC SMS connection document.

=item B<-b Billing_info>

Optional. Information that will appear on the EIT billing.

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
my $mail_address = 'sms@europe.eds.com';    # Destination for SMS messages
my ($smtp_server, $message, $application, $billing_info, $banner, $res);
my ($smtp, $recipient, $sender, $smtp_debug);
my @recipients = ();

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
use Net::SMTP;

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
    if (defined($smtp)) {
	$smtp->quit;
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

######
# Main
######

# Handle input values
my %options;
getopts("tl:d:s:o:r:m:a:b:ph:", \%options) or pod2usage(-verbose => 0);
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
    $mail_address = $options{"d"};
}
# Find SMTP Server
if ($options{"s"}) {
    $smtp_server = $options{"s"};
} else {
    error("SMTP Server not defined, exiting ...");
    exit_application(1);
}
# Find sender of the mail
if ($options{"o"}) {
    $sender = $options{"o"};
} else {
    error("No sender defined, exiting ...");
    exit_application(1);
}
# Collect Recipient List
if ($options{"r"}) {
    @recipients = split(",",$options{"r"});
#    recipients_validation;
} else {
    error("No recipients defined, exiting ...");
    exit_application(1);
}
# Find message to send
if ($options{"m"}) {
    $message = $options{"m"};
    if (length($message) > 150) {
	$message = substr($message,0,150);
	error("Message should not exceed 150 characters, truncated to: \n$message");
    }
} else {
    error("No message found, exiting ...");
    exit_application(1);
}
# Find Application name
if ($options{"a"}) {
    $application = $options{"a"};
} else {
    error("Application name not found, existing ...");
    exit_application(1);
}
# Find Billing Information
if ($options{"b"}) {
    $billing_info = $options{"b"};
}
# Check for smtp debug information
if (defined $options{"p"}) {
    $smtp_debug = 1;
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Create object for SMTP server
$smtp=Net::SMTP->new($smtp_server,
		      Debug => $smtp_debug);
if (defined $smtp) {
    $banner = $smtp->banner();
    if (defined $banner) {
    logging("Banner from $smtp_server: $banner");
    } else {
	error("Couldn't get banner from $smtp_server.");
    }
} else {
    error("Could not get to mailhost $smtp_server, exiting ...");
    exit_application(1);
}

$res=$smtp->mail($sender);
if ($res == 0) {
    error("Mail method not successful!");
    exit_application(1);
}

$res=$smtp->to($mail_address,'dirk.vermeylen@eds.com');
#$res=$smtp->to($mail_address);
if ($res==0) {
    error("To: $mail_address not successful!");
    exit_application(1);
}

$smtp->data();
$smtp->datasend("To: " . $mail_address);
$smtp->datasend("\n");
$smtp->datasend("Subject: XML");
$smtp->datasend("\n");
$smtp->datasend("<smsmessage>\n");
$smtp->datasend("   <applicationname>$application</applicationname>\n");
$smtp->datasend("   <recipientslist>\n");
foreach $recipient (@recipients) {
    $recipient = trim($recipient);
    $smtp->datasend("	<recipient>$recipient</recipient>\n");
}
$smtp->datasend("   </recipientslist>\n");
$smtp->datasend("   <message>$message\n");
$smtp->datasend("   </message>\n");
if (defined($billing_info)) {
    $smtp->datasend("   <applicationinformation>\n");
    $smtp->datasend("	$billing_info");
    $smtp->datasend("   </applicationinformation>\n");
}
$smtp->datasend("</smsmessage>\n");
$smtp->dataend();

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Improved formatting and error checking of the recipient numbers.

=item *

Accept input values from a file or from input (input overrides file).

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
