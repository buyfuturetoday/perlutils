=head1 NAME

Mail_simple - Provides mailing facilities in your application.

=head1 VERSION HISTORY

version 1.2 - 7 february 2003

=over 4

=item * 

Rename Mail.pm to Mail_simple.pm. A new Mail.pm module based on the MIME::Lite module has been developed. The new mail module allows to send attachments in mails.

=back

version 1.1 - 3 december 2002 

=over 4

=item *

Bug fix - "return" returns to the calling subroutine. The "exit_module" subroutine cannot exit the module, but only cleans up and returns to the calling module. The calling module needs to return to its caller...

=back

version 1.0 - 22 october 2002

=over 4

=item *

Initial release

=back

=head1 SYNOPSIS

 use Mail_simple;

 mail_address(Addressees);
 sender(Adress);
 subject("Subject Line");
 message("Message text");
 smtp_server(SMTP_Forwarder);
 smtp_debug(value);
 send_mail;

=head1 DESCRIPTION

This module allows to send mails from your Perl script. 

=cut

########
# Module
########

package Mail_simple;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(mail_address smtp_server sender message send_mail subject smtp_debug);

###########
# Variables
###########

my $smtp_server = "forwarder.eds.com";	    # Default SMTP forwarder
my $subject = "";			    # Mail subject
my $smtp_debug = 0;			    # 0: no smtp debug info, 1: smtp debug info
my ($mail_address, $message, $banner, $res);
my ($smtp, $recipient, $sender);


#####
# use
#####

use warnings;
use strict;
use Net::SMTP;

#############
# subroutines
#############

sub exit_module() {
    if (defined($smtp)) {
	$smtp->quit;
    }
    return;
}

sub trim {
    my @out = @_;
    for (@out) {
        s/^\s+//;
        s/\s+$//;
    }
    return wantarray ? @out : $out[0];
}

sub validate_params {
    if (not(defined $mail_address)) {
	return undef;
    }
    if (not(defined $sender)) {
	return undef;
    }
    if (not(defined $message)) {
	return undef;
    }
}

=pod

=head2 mail_address

mail_address allows to set or get the mail address(es). Enter the mail addresses as argument to the function. Use ";" to separate recipients. All mail addresses are threated as a single parameter to the subroutine.

Returns the mail_address or "undefined" in case of an error.

If more than one parameter is passed to the function, then the function returns the previous mail address (if any).

=cut

sub mail_address {
    my ($tmp_address,$rest) = @_;
    if (defined $rest) {
	return $mail_address;
    } elsif (defined $tmp_address) {
	$mail_address = $tmp_address;
    }
    return $mail_address;
}

=pod

=head2 sender

sender allows to set or get the mail address of the sender. Returns the sender address or undefined in case of an error. No verification is done on the sender address.

The user must supply a sender name.

=cut

sub sender {
    my ($tmp_address) = @_;
    if (defined $tmp_address) {
	$sender = $tmp_address;
    }
    return $sender;
}

=pod

=head2 subject

subject allows to set or get the subject of the mail. Returns an empty string (not undefined) in case no subject is yet defined.

=cut

sub subject {
    my ($tmp_subject) = @_;
    if (defined $tmp_subject) {
	$subject = $tmp_subject;
    }
    return $subject;
}

=pod 

=head2 message

message allows to set or get the mail message. Returns undefined in case no message is yet defined, or in case of an error. Use "\n" in the message to separate lines.

It is mandatory to define a message.

=cut

sub message {
    my ($tmp_message) = @_;
    if (defined $tmp_message) {
	$message = $tmp_message;
    }
    return $message;
}

=pod

=head2 smtp_server

smtp_server allows to set or get the SMTP forwarding server. Default value: "forwarder.eds.com". No checking is done if the name corresponds to an SMTP server, any value is accepted.

=cut

sub smtp_server {
    my ($tmp_smtp) = @_;
    if (defined $tmp_smtp) {
	$smtp_server = $tmp_smtp;
    }
    return $smtp_server;
}

=pod

=head2 smtp_debug

If set to 1, then SMTP debug information is displayed on STDOUT. If set to 0, then no SMTP debug information will be displayed on STDOUT. If called without parameters, then returns the current status of the flag.

=cut

sub smtp_debug {
    my ($tmp_debug) = @_;
    if (defined $tmp_debug) {
	if ($tmp_debug == 1) {
	    $smtp_debug =1;
	} else {
	    $smtp_debug = 0;
	}
    } else {
	$smtp_debug = 0;
    }
    return $smtp_debug;
}

=pod

=head2 send_mail

The send_mail function collects all information and sends a message to an SMTP forwarder. The function does not accept any input values. All settings must be done prior to calling the function. 

A successful send will return 0, an unsuccessful send returns the "undefined" value.

=cut

sub send_mail {
    validate_params;
    # Create object for SMTP server
    $smtp=Net::SMTP->new($smtp_server,
			 Debug => $smtp_debug);
    if (not(defined $smtp)) {
	exit_module();
	return undef;
    }

    $res=$smtp->mail($sender);
    if ($res == 0) {
	#error("Mail method not successful!");
	exit_module();
	return undef;
    }

    my @recipients = split(";",$mail_address);
    foreach $recipient (@recipients) {
	$recipient = trim($recipient);
	$res=$smtp->to($recipient);
	if ($res==0) {
	    #error("To: $mail_address not successful!");
	    exit_module();
	    return undef;
	}
    }

    $smtp->data();
    $smtp->datasend("To: " . $mail_address);
    $smtp->datasend("\n");
    $smtp->datasend("Subject: $subject");
    $smtp->datasend("\n");
    my @messagearray = split("\n", $message);
    foreach my $messageline (@messagearray) {
	$smtp->datasend("$messageline\n");
    }
    $smtp->dataend();

    exit_module();
    return 0;
}

1;

=pod

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
