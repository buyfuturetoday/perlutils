=head1 NAME

Mail - Provides mailing facilities in your application.

=head1 VERSION HISTORY

version 2.0 - 6 february 2003

=over 4

=item *

Convert from Net::SMTP to MIME::Lite to allow for attachments. The module using Net::SMTP will be stored as Mail_Simple.pm.

=item *

IMPORTANT: the Recipients delimiter is now a comma - , -. The semicolon - ; - cannot be used.

=item *

The "/n" delimiter to format messages has been removed...

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

 use Mail;

 mail_address(Addressees);
 sender(Adress);
 subject("Subject Line");
 message("Message text");
 attachment(pointer_to_file);
 smtp_server(SMTP_Forwarder);
 smtp_debug(value);
 send_mail;

=head1 DESCRIPTION

This module allows to send mails from your Perl script. 

=cut

########
# Module
########

package Mail;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(mail_address smtp_server sender message attachment send_mail subject smtp_debug);

###########
# Variables
###########

my $smtp_server = "forwarder.eds.com";	    # Default SMTP forwarder
my $subject = "";			    # Mail subject
#my $smtp_debug = 0;			    # 0: no smtp debug info, 1: smtp debug info
my ($mail_address, $message, $attachment, $res);
my ($smtp, $recipient, $sender);


#####
# use
#####

use warnings;
use strict;
use MIME::Lite;
use File::Basename;

#############
# subroutines
#############

# The MIME::Lite module does not have a method to remove the object.
sub exit_module() {
#    if (defined($smtp)) {
#	$smtp->quit;
#    }
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
    if (defined $attachment) {
	if (not(-f $attachment)) {
	    return undef;
	}
    } elsif (not(defined $message)) {
	return undef;
    }
}

=pod

=head2 mail_address

mail_address allows to set or get the mail address(es). Enter the mail addresses as argument to the function. Use "," to separate recipients. All mail addresses are threated as a single parameter to the subroutine.

Returns the mail_address or "undefined" in case of an error.

If more than one parameter is passed to the function, then the function returns the previous mail address (if any). (Why passing more than one parameter to the function?...)

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

message allows to set or get the mail message. Returns undefined in case no message is yet defined, or in case of an error.

It is mandatory to define a message if there is no attachment defined.

=cut

sub message {
    my ($tmp_message) = @_;
    if (defined $tmp_message) {
	$message = $tmp_message;
    }
    return $message;
}

=pod

=head2 attachment

attachment allows to set or get the current setting for the attachment. Returns undefined in case no attachment has been specified or in case an invalid attachment (i.e. a file that (no longer) exists) has been specified.

=cut

sub attachment {
    my ($tmp_attachment) = @_;
    if (defined $tmp_attachment) {
	if (-r $tmp_attachment) {
	    $attachment = $tmp_attachment;
	}
    }
    return $attachment;
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

=head2 send_mail

The send_mail function collects all information and sends a message to an SMTP forwarder. The function does not accept any input values. All settings must be done prior to calling the function. 

A successful send will return 0, an unsuccessful send returns the "undefined" value.

=cut

sub send_mail {
    # Validate mail params. If not OK,then validate_params function will 
    # return to the calling program with "undefined".
    validate_params;
    # All parameters are OK, so...
    # Create object for SMTP server
    # First try to suppress error conditions, 
    # handle them in the application instead.

    if (defined $attachment) {
	my $filename=basename($attachment);
	$smtp=MIME::Lite->new(
	    FROM    => $sender,
	    To	    => $mail_address,
	    Subject => $subject,
	    Type    => 'multipart/mixed');
	if (defined $message) {
	    $smtp->attach(TYPE	    => 'TEXT',
			  Data	    => $message);
	}
	$smtp->attach(TYPE	    => 'application/octet-stream',
		      Path	    => $attachment,
		      Filename	    => $filename,
		      Disposition   => 'attachment');
    } else {
	$smtp=MIME::Lite->new(
	    FROM    => $sender,
	    To	    => $mail_address,
	    Subject => $subject,
	    Type    => 'TEXT',
	    Data    => $message);
    }

    if ($smtp->send_by_smtp($smtp_server)) {
print "Message successfully send...\n";
	return 0;
    } else {
print "Could not send message...\n";
	return undef;
    }
}

1;

=pod

=head1 TO DO

=over 4

=item *

Allow for more than one file as attachment per mail.

=item *

Allow to specify the filename as displayed in the mail.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
