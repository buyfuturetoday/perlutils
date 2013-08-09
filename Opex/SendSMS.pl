=head1 NAME

SendSMS - Sends XML string to MobileSys application for distributing SMS messages.

=head1 VERSION HISTORY

version 1.1 5 June 2003 DV

=over 4

Replace function to delete processed messages into the exit_application subroutine to guarantee all processed messages are deleted in case of problems.

=back

version 1.0 26 May 2003 DV

=over 4

=item *

Initial release, based on the MobileSys_SMS application and the old SendSMS application.

=back

=head1 DESCRIPTION

This application is triggered by an event message "SENDSMS" to indicate that new messages are available in the smsbuf table for sending. The text message is read together with all corresponding phone numbers, the information is converted in to an XML message and transmitted to a mailbox address for processing.

Only one instance of this application can be active at any time. Therefore the application must have access to a lock file. When the access to the lock file is not granted, then the application silently waits until it has access to the lockfile.

=head1 SYNOPSIS

SendSMS.pl [-t] [-l log_dir] [-p]

    SendSMS -h		    Usage
    SendSMS -h 1	    Usage and description of the options
    SendSMS -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\opex\log

=item B<-p>

If set, display SMTP Debug information. Default: no SMTP Debug information.

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
my $smtp_server = "forwarder.eds.com";	    # EDS Forwarder server
my $sender = 'peter.desmit@eds.com';	    # Sender of the message
my $application = "OPEX-MON";		    # Application name for this...
my $lockfile = "d:/opex/lock/smslock.txt";  # SendSMS lockfile to guarantee exclusive usage
# my $lockfile = "c:/temp/smslock.txt";  # SendSMS lockfile to guarantee exclusive usage
my $dbase = "DSN=OPEX;UID=sa;PWD=";			    # ODBC Connection name to OPEX database
my ($message, $billing_info, $banner, $res);
my ($smtp, $recipient, $smtp_debug, $dbsmsbuf, $dbsmsupd);
my @recipients = ();	    # Recipient phone list array
my @delete = ();	    # Messages to be deleted array

#####
# use
#####

# use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use Log;			    # Application and error logging
use Net::SMTP;
use Win32::ODBC;		    # Allow ODBC Connection to database

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
    

    if (defined($dbsmsbuf)) {
        # Remove all messages that have been sent. The SQLquery statement
	# has been updated to B<exit> immediately in case of problems
	# instead of calling the exit_application subroutine
	foreach my $msg (@delete) {
	    my $sqlquery = "DELETE FROM smsbuf where msg=\'$msg\'";
	    SQLquery($dbsmsbuf, $sqlquery);
	    trace("$msg has been deleted");
	}
	$dbsmsbuf->Close();
	trace("Close database connection");
    }
    if (defined($dbsmsupd)) {
	$dbsmsupd->Close();
	trace("Close database connection for phone numbers");
    }
    if (defined($smtp)) {
	$smtp->quit;
	trace("Quit SMTP connection");
    }
    flock(LOCK,8);
    trace("Release lock on file");
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

=head2 SQL query

Accepts a database handle and a query, executes the request and make the data available for processing.

The I<exit_application> string has been replaced by an I<exit> statement to avoid loop conditions since the "Remove all messages that have been sent" block is added to the exit_application subroutine. And this was required to make sure that messages get deleted in case of a first message processed successfully and a second message fails (Mail server not reachable or so). In this case the first message will be transmitted twice. (Of course, if the error for the second message is in the SQL statement, then this will not work, but most probably the delete will also not work so we better have a straight exit...)

=cut

sub SQLquery($$) {
    my($db, $query) = @_;
    trace("$db, $query");
    if ($db->Sql($query)) {
	my ($errnum, $errtext, $errconn) = $db->Error();
	error("SQL Error: $errnum $errtext $errconn");
	exit 1;
    }
}

=pod

=head2 Send Message to MobileSys Application

Create the smtp object, connect to the mail server, configure the sender address, configure the mail address, format the message.

If the connection to the mail server fails, then the application is terminated. The messages remain in the smsbuf table until this application is triggered next time. So messages will not get lost, but it is unpredictable when they will be transferred.

=cut

sub send_to_MobileSys {
    
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
    
    # Configure the sender
    $res=$smtp->mail($sender);
    if ($res == 0) {
	error("Mail method not successful!");
	exit_application(1);
    }
    
    # Configure the mail address
    $res=$smtp->to($mail_address);
    #$res=$smtp->to($mail_address,'dirk.vermeylen@eds.com');
    if ($res==0) {
	error("To: $mail_address not successful!");
	exit_application(1);
    }
    
    # Format the message
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
    # $smtp->datasend("   <message>$send_message\n");
    $smtp->datasend("   </message>\n");
    # if (defined($billing_info)) {
    #	$smtp->datasend("   <applicationinformation>\n");
    #	$smtp->datasend("	$billing_info");
    #	$smtp->datasend("   </applicationinformation>\n");
    #}
    # Send the message
    $smtp->datasend("</smsmessage>\n");
    $smtp->dataend();
    logging("$message - transferred to MCS SMS");

    # Temporary procedure to print messages to special file
    # for performance verification from the MCS SMS system
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my $datetime = sprintf "%02d/%02d/%04d;%02d:%02d:%02d",$mday, $mon+1, $year+1900,$hour,$min,$sec;
    my $cmdstring = "$datetime;$message";
    system("echo $cmdstring >> d:/opex/log/sms.txt");
}

=pod

=head2 Check Phone Number

The phone number should be from the form +CC PPP NNNNNNN. This is the Country code (numeric, 1 to 3 digits), mobile phone operator prefix (numeric, 3 digits) and number (numeric).

These rules are based on the current knowledge, no guarantee it will work forever.

=cut

sub check_phonenumber($) {
    my ($phonenumber) = @_;
    my ($country, $provider, $suffix) = split (/ /, $phonenumber);
    if (not($country =~ /^\+[1-9]\d{0,2}$/)) {
	error("$phonenumber invalid country code $country");
    } elsif (not($provider =~ /^\d{3}$/)) {
	error("$phonenumber invalid provider code $provider");
    } elsif (not($suffix =~ /^\d+$/)) {
	error("$phonenumber invalid suffix code $suffix");
    } else {
	# All checks were successful, number looks possible
	return 0;
    }
    # One of the checks failed
    return 1;
}
	
    

######
# Main
######

# Handle input values
my %options;
getopts("tl:ph:", \%options) or pod2usage(-verbose => 0);
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
	error("Could not set d:\\opex\\log as Log directory, exiting...");
	exit_application(1);
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

# Obtain Lock on file
open(LOCK, "$lockfile");
if (not(flock(LOCK,2))) {
    # When lock not granted, then application should wait 
    # until lock is granted. The error condition below should never
    # be executed.
    error("Cannot obtain queue lock on $lockfile, exiting...");
    exit_application(1);
}

# Create Database Connection for Messages
undef $dbsmsbuf;
if (not($dbsmsbuf = new Win32::ODBC($dbase))) {
    error("Open failed: ".Win32::ODBC::Error());
    exit_application(1);
}

# Create Database Connection for Phone numbers
undef $dbsmsupd;
if (not($dbsmsupd = new Win32::ODBC($dbase))) {
    error("Open failed: ".Win32::ODBC::Error());
    exit_application(1);
}

# Collect text message into $message, check that message does not exceed 150 characters
my $sqlquery = "SELECT distinct(msg) FROM smsbuf";
SQLquery($dbsmsbuf, $sqlquery);
while ($dbsmsbuf->FetchRow()) {
    my %MsgTable = $dbsmsbuf->DataHash();
    $message = $MsgTable{msg};
    # Collect recipients into @recipients
    $sqlquery = "SELECT distinct(telnum) FROM smsbuf WHERE msg=\'$message\'";
    SQLquery($dbsmsupd, $sqlquery);
    @recipients = ();
    while ($dbsmsupd->FetchRow()) {
	my %recipient_record = $dbsmsupd->DataHash();
	my $recipient=$recipient_record{telnum};
	my $check_return = check_phonenumber($recipient);
	if ($check_return == 0) {
	    push @recipients, $recipient;
	}
    }
    my $nr_phones = @recipients;
    if ($nr_phones > 0) {
	# Verify message length < 150
	my $save_message;
	undef $save_message;
	if (length($message) > 150) {
	    $save_message = $message;
	    $message = substr($message, 0, 150);
	}
	send_to_MobileSys;
	if (defined($save_message)) {
	    $message = $save_message;
	}
    } else {
	error("No valid phone numbers for Message $message");
    }
    push @delete, $message;
}


exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Obtain database connection information from a file.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
