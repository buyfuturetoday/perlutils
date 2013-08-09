=head1 NAME

Log - Provides Error messages, trace messages and logging messages

=head1 VERSION HISTORY

version 1.8 - 05 January 2010

=over 4

=item *

Modified hostname function to make it platform-independent. ($ENV{COMPUTERNAME} is windowx only.)

=back

version 1.7 - 13 April 2009

=over 4

=item * 

Modified Trace function so that it will print both to STDOUT and to Logfile.

=back

version 1.6 - 14 April 2006

=over 4

=item *

Calculate path to perl executable (to call wperl) and to tk_popup module. No more need to hardcode tk_popup reference.

=back

version 1.5 - 21 February 2005

=over 4

=item *

Add computername to the logfile name

=back

version 1.4 - 26 April 2004

=over 4

=item *

Changed wperl directory to (default)/c:\perl\bin

=back

version 1.3 - 16 September 2003

=over 4

=item *

Changed default log directory to \temp\log

=back

version 1.2 - 18 April 2003

=over 4

=item *

Use wperl instead of perl for the system call to the tk_popup script, to avoid the console flickering on the screen.

=back

version 1.1 - 14 April 2003

=over 4

=item *

Added the tk_popup module to allow to print error messages in popup boxes.

=back

version 1.0 - 7 August 2002

=over 4

=item *

Initial release

=back

=head1 SYNOPSIS

 use Log;

 error("Error message");
 trace("Trace message");
 open_log();
 logging("Log message");
 close_log();
 logdir("logdirectory");
 log_flag;
 trace_flag;
 stderr_flag;
 display_flag;

=head1 DESCRIPTION

The module provides error messages, trace messages and logging messages.

=cut

########
# Module
########

package Log;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(error trace open_log logging close_log logdir trace_flag log_flag);

###########
# Variables
###########

my $trace = 0;		    # 0: no tracing (default), 1: tracing
my $log = 1;		    # 0: no logging, 1: logging (default)
my $logdir = "d:\\temp\\log";    # Log file directory
my $stderr = 0;		    # 0: no STDERR redirection, 1: STDERR in logfile
my $display = 0;	    # 0: do not show error on screen, 1: show error (using tk_popup.pl application).
my $scriptname = "Perl Script";
my ($perldir, $perllibdir);

#####
# use
#####

use warnings;
use strict;
use File::Basename;	    # Logfilename translation
use Sys::Hostname;	    # Get Hostname

#############
# subroutines
#############

=pod

=head2 error("Error String")

The procedure accepts any valid string, calculates the current date and time and prints the string on STDOUT and in the logfile. The format of the error message is:

DD/MM/YYYY HH:MM:SS - Error: I<Error String>

=cut

sub error($) {
    my($txt) = @_;
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
    print "$datetime - Error: $txt\n";
    logging("ERROR: " . $txt);
    if ($display == 1) {
		if ($^O eq "MSWin32") {
	    	my $command="$perllibdir/tk_popup.pl -application $scriptname -severity error -message $txt";
	    	system("start $perldir/wperl $command");
		}
    }
}

=pod

=head2 trace("Trace String")

If the trace flag is set to 1, then the procedure accepts any valid string, calculates the current date and time and prints the string on STDOUT. The format of the trace message is: 

DD/MM/YYYY HH:MM:SS - Trace: I<Error String>

=cut

sub trace($) {
    if ($trace) {
	my($txt) = @_;
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
	print "$datetime * $txt\n";
	print LOGFILE "$datetime * $txt\n";
    }
}

=pod

=head2 open_log

The procedure opens the logfile for the script and associates a filehandle to the logfile. (Make sure that the calling program's exit handling will close the logfile as well!).

The logfile name is retrieved from the calling perl script name. The basename of the calling script is determined. Then the scriptname is the part of the basename before the first . (dot) in the filename. This assumes that a . (dot) is only used to split up the filename from the extension.

The current date (YYYYMMDD) is appended to the scriptname. 

Logfiles have the extension .log. The logfiles are stored on the logfile directory. The logfile directory can be set or examined with the subroutine logdir.

If the stderr flag is set, then messages from STDERR are included in the logfile. This may be helpful for batch processing. Control the stderr flag with the stderr_flag subroutine.

The autoflush is on for the logfile. This means that no messages are buffered. In case of system crashes more messages should be in the log file.

If the logfile directory does not exist or if the logfile could not be opened, then the return value of the subroutine is undefined. Otherwise the return value is 0.

=cut

sub open_log() {
    if ($log == 1) {
	if (not(-d $logdir)) {
	    print "Error in Log.pm - $logdir does not exist, cannot open logfile\n";
	    return undef;
	}
	($scriptname, undef) = split(/\./, basename($0));
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $computername = hostname;
	if (not(defined $computername)) {
		$computername = "undefinedComputer";
	}
	my $logfilename=sprintf(">>$logdir/$scriptname"."_$computername"."_%04d%02d%02d.log", $year+1900, $mon+1, $mday);
	my $openres = open (LOGFILE, $logfilename);
	if (not(defined $openres)) {
	    print "Error in Log.pm - Could not open $logfilename\n";
	}
	if ($stderr == 1) {
	    open (STDERR, ">&LOGFILE");	    # STDERR messages into logfile
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

This procedure will add log messages to the log file, if the log flag is set. (Control the log flag with the log_flag procedure). The current date and time is calculated, prepended to the log message and the log message is appended to the logfile. A "Carriage Return/Linefeed" is appended to the log message.

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

=head2 close_log

If the logfile is opened, then this procedure will close the logfile.

=cut

sub close_log() {
    if ($log == 1) {
	close LOGFILE;
    }
}

=pod

=head2 logdir

This procedure allows to set or get the current logfile directory.

When called without parameters, then the procedure checks if the current  setting is a directory. If so, then the current setting is returned. Otherwise, the return value is undefined.

When called with a parameter, then it is assumed that the parameter is the required logfile directory. The procedure checks if the parameter is a directory. If so, the logfile directory is set to this value. Otherwise the return value of the subroutine is undefined. The value of logdir is not changed in this case.

=cut

sub logdir {
    my ($tmpdir) = @_;
    if (defined $tmpdir) {
	if (-d $tmpdir) {
	    $logdir = $tmpdir;
	    return $logdir;
	} else {
	    return undef;
	}
    } elsif (-d $logdir) {
	return $logdir;
    } else {
	return undef;
    }
}

=pod

=head2 log_flag (value)

The log_flag procedure allows to set or get the value of the log flag. A value of 0 means no logging, a value of 1 (default) means logging. The subroutine returns the value of the log flag. If an invalid value is specified then the subroutine return value is undefined.

=cut

sub log_flag {
    my ($log_flag) = @_;
    if (defined $log_flag) {
	if ($log_flag == 0) {
	   $log = 0;
	   return $log;
	} elsif ($log_flag == 1) {
	    $log = 1;
	    return $log;
	} else {
	    return undef;
	}
    } else {
	return $log;
    }
}

=pod

=head2 trace_flag (value)

The trace_flag procedure allows to set or get the value of the trace flag. A value of 0 (default) means no tracing, a value of 1 means tracing. The subroutine returns the value of the trace flag. If an invalid value is specified then the subroutine return value is undefined.

=cut

sub trace_flag {
    my ($trace_flag) = @_;
    if (defined $trace_flag) {
	if ($trace_flag == 0) {
	   $trace = 0;
	   return $trace;
	} elsif ($trace_flag == 1) {
	    $trace = 1;
	    return $trace;
	} else {
	    return undef;
	}
    } else {
	return $trace;
    }
}

=pod

=head2 stderr_flag (value)

The stderr_flag procedure allows to set or get the value of the stderr flag. A value of 0 (default) means no STDERR redirection, a value of 1 means redirecting STDERR to the logfile. The subroutine returns the value of the stderr flag. If an invalid value is specified then the subroutine return value is undefined.

=cut

sub stderr_flag {
    my ($stderr_flag) = @_;
    if (defined $stderr_flag) {
	if ($stderr_flag == 0) {
	   $stderr = 0;
	   return $stderr;
	} elsif ($stderr_flag == 1) {
	    $stderr = 1;
	    return $stderr;
	} else {
	    return undef;
	}
    } else {
	return $stderr;
    }
}

=pod

=head2 display_flag (value)

The display_flag procedure allows to set or get the value of the display flag. A value of 0 (default) means no display of the error message on a popup window, a value of 1 means displayint the error message on the popup window. The subroutine returns the value of the display flag. If an invalid value is specified then the subroutine return value is undefined.

If display_flag is (set to) 1, then the perldir and perllibdir directory values are calculated. This allows to call the tk_popup application asynchronously in the error module.

=cut

sub display_flag {
    my ($display_flag) = @_;
    if (defined $display_flag) {
		if ($display_flag == 0) {
	   		$display = 0;
	   		return $display;
		} elsif ($display_flag == 1) {
	    	$display = 1;
			# In this case I need to know the Perl directory path to call 
			# the wperl executable and the tk_popup.pl script.
			$perldir = dirname($^X);
			# perllibdir points to the site specific modules
			# Therefore remove /bin directory from the path
			$perllibdir = substr($perldir,0,-length("/bin"));
			$perllibdir .= "/site/lib";
	    	return $display;
		} else {
	    	return undef;
		}
    } else {
		return $display;
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

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
