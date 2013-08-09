=head1 NAME

tk_popup - Generates a popup dialog box.

=head1 VERSION HISTORY

version 1.0 14 April 2003 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application generates a popup dialog box. When any Perl script needs to display a popup message, then this application can be invoked with a command like system("start perl tk_popup.pl arguments") on Windows systems or system("perl tk_popup.pl arguments &") on UNIX systems. This way the calling application will dump a message for the user's convenience without waiting for any user feedback.

Due to the asynchronous requirements to launch this application, it cannot be transferred into a Perl module (to my current knowledge). However it is still threated as a module and it must be stored in the %PerlPath%/site/lib directory (as any other site specific module). This way it can be launched without the need to hardcode paths in the log.pm script.

=head1 SYNOPSIS

tk_popup [-application application_name] [-severity severity] [-message message]

Note: keywords are case-sensitive.

=head1 OPTIONS

=over 4

=item B<-application>

The application name that will appear in the title of the popup window.

=item B<-severity>

Severity of the message. Severity must be one of the values: error, info, question or warning.

=item B<-message>

The message to be displayed in the popup box.

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
my $application="Perl Script";
my $message="Error in Perl Script";
my $severity="error";
my ($name,$mw);
my %param_hash;
$param_hash{"application"}="Perl Script";
$param_hash{"message"}="Issue in Perl Script";
$param_hash{"severity"}="error";

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Tk;
use Tk::Dialog;

#############
# subroutines
#############

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

=pod

=head2 Handle Argument list

The parameter value can be 3 cases: no parameter value OR parameter value of one word OR parameter value of more than one word.

Read @ARGV until end of string or until new parameter name, print name/value pair from what was read so far.

=cut

undef $name;
$valuestring = "";
$value = shift @ARGV;
while (defined $value) {
    if ($identifier eq substr($value,0,length($identifier))) {
	# Parameter name found - print previous name / value pair - if any ...
	if (defined $name) {
	    $valuestring=trim($valuestring);
	    $param_hash{$name}=$valuestring;
	}
	# ... and initialize new name / value pair
	$name = $value;
	# Remove identifier from name
	$name = substr($name,length($identifier));
	$valuestring = "";
    } else {
	$valuestring = $valuestring.$value." ";
    }
    $value = shift @ARGV;
}
# End of argument list reached, print last name / value pair.
if (defined $name) {
    $valuestring=trim($valuestring);
    $param_hash{$name}=$valuestring;
}

# Display the pop-up window
$mw=MainWindow->new();
$mw->withdraw();		# Do not show the main window
$mw->messageBox(-icon=>$param_hash{"severity"},
		-message=>$param_hash{"message"},
		-title=>$param_hash{"application"},
		-type=>"ok");
