=head1 NAME

ErrCnt - Count the number of errors, report failure only in case of X consecutive problems.

=head1 VERSION HISTORY

version 1.0 - 3 July 2003

=over 4

=item *

Initial release

=back

=head1 SYNOPSIS

 use ErrCnt;

 name("Object_Name");
 directory("Countfile directory");
 max_errors(number);

=head1 DESCRIPTION

This module allows to calculate the number of consecutive errors before escalating. For this each application uses a counter file to store the number of errors.

Returncode = 0 indicates successful termination, Returncode = 1 indicates an error. In case of success, the counter file is deleted if it exists. In case of an error and the error file exists and the value in the file is numeric, the value is read from the file. Otherwise the value is initialized to 0.

Then the error counter is incremented by 1 and written to the error file. If the write is not successful, an error is returned. If the counter is equel to or greater than the maximum number of errors, then an escalation is returned to the calling program. Otherwise, success is returned to the calling program.

=cut

########
# Module
########

package ErrCnt;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(errcnt name directory max_errors errcnt_file);

###########
# Variables
###########

my ($dir,$name,$errcnt_file, $openres);
my $max_errors = 3;

#####
# use
#####

use warnings;
use strict;
# use File::Basename;	    # Logfilename translation
use Log;

#############
# subroutines
#############

=pod

=head2 name

This procedure allows to set or get the current object name.

When called without parameters, then the procedure returns the object name or undefined when no object name has been defined so far.

When called with a parameter, then it is assumed that this is the object name.No verification is done if the object name can be used as a file name, this is assumed.

=cut

sub name {
    my ($tmpdir) = @_;
    if (defined $tmpdir) {
	if (length($tmpdir) > 0) {
	    $name = $tmpdir;
	    return $name;
	} else {
	    return undef;
	}
    } elsif (defined $name) {
	return $name;
    } else {
	return undef;
    }
}

=pod

=head2 max_errors

This procedure allows to set or get the maximum number of errors (3 by default).

When called without parameters, then the procedure returns the maximum number of errors.

When called with a parameter, then it is verified if the parameter is a positive integer. If so, this is set as the new value for max_errors. Otherwise an undefined is returned.

=cut

sub max_errors {
    my ($tmpdir) = @_;
    if (defined $tmpdir) {
    # Verify if the value is a positive integer
	if ($tmpdir =~ /^\d+$/) {
	    $max_errors = $tmpdir;
	    return $max_errors;
	} else {
	    error("ErrCnt.pm - max_errors not numeric");
	    return undef;
	}
    } elsif (defined $max_errors) {
	return $max_errors;
    } else {
	# I should never arrive here ...
	return undef;
    }
}

=pod

=head2 directory

This procedure allows to set or get the current count file directory.

When called without parameters, then the procedure checks if the current  setting is a directory. If so, then the current setting is returned. Otherwise, the return value is undefined.

When called with a parameter, then it is assumed that the parameter is the required logfile directory. The procedure checks if the parameter is a directory. If so, the count file directory is set to this value. Otherwise the return value of the subroutine is undefined. The value of directory is not changed in this case.

=cut

sub directory {
    my ($tmpdir) = @_;
    if (defined $tmpdir) {
	if (-d $tmpdir) {
	    $dir = $tmpdir;
	    return $dir;
	} else {
	    return undef;
	}
    } elsif ((defined $dir) and (-d $dir)) {
	return $dir;
    } else {
	return undef;
    }
}

=pod

head2 errcnt_file

This procedure checks if the name and the directory are defined. If so, the errcnt_file is set.

=cut

sub errcnt_file {
    if ((defined($name)) and
        (defined($dir))  and
	(-d $dir)) {
	$errcnt_file = "$dir/$name.cnt";
    } else {
	undef $errcnt_file;
    }
}

sub errcnt($) {
    my ($returncode) = @_;
    if (not(defined($errcnt_file))) {
	error("Error count file not defined, no counting of consecutive errors.");
	return $returncode;
    }
    my $errcnt = 0;
    my ($errcnt_value);
    if ($returncode == 0) {
	# OK -> remove file if it exists
	if (-e $errcnt_file) {
	    unlink $errcnt_file;
	    logging("$errcnt_file deleted");
	}
	return 0;
    } else {
	# Not OK
	undef $errcnt_value;
	# Try to obtain a value for the error counter
	if (-e $errcnt_file) {
	    $openres = open (ERRCNT, $errcnt_file);
	    if (not(defined $openres)) {
		# Cannot open Error count file => Return Error
		logging("Cannot open $errcnt_file");
		return 1;
	    }
	    if (defined($errcnt_value = <ERRCNT>)) {
		# If there is something in the file, then it must be numeric
		# If there is nothing in the file, then $errcnt_value is undef
		chomp $errcnt_value;
		if (not($errcnt_value =~ /^\d+$/)) {
		    # No numeric value - Remove errcnt_value
		    undef $errcnt_value;
		}
	    }
	    close ERRCNT;
	}
	if (defined $errcnt_value) {
	    $errcnt = $errcnt_value;
	}
	$errcnt++;
	# Write Err_counter value to file
	$openres = open (ERRCNT, ">$errcnt_file");
	if (not(defined $openres)) {
	    logging("Cannot open $errcnt_file for writing");
	    return 1;
	}
	print ERRCNT $errcnt;
	close ERRCNT;
	# Evaluate if threshold has been reached
	if ($errcnt < $max_errors) {
	    logging("$errcnt consecutive error(s), max $max_errors. No escalation");
	    return 0;
	} else {
	    logging("$errcnt consecutive errors, max nr errors ($max_errors) reached, escalate!");
	    return 1;
	}
    }
}

1;


=pod

=head1 TO DO

=over 4

=item *

Investigate the CPAN module Log::Log4perl to replace this module.

=item *

Implement pop-up display messages for other operating systems.

=item *

Allow to specify the pathname for the tk_popup application.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>

=head1 To be removed ...

use Log;
open_log();
$errcnt_file = "c:/temp/errcnt.txt";
errcnt(1);
logging("Exit Application\n");
close_log();
