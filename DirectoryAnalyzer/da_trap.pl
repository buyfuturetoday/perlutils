=head1 NAME

da_trap - Handle DirectoryAnalyzer traps from the Unicenter Event Management console.

=head1 VERSION HISTORY

version 1.1 24 July 2002 DV

=over 4

=item *

Use status_no to set the object status in stead of severity. As a result, the severity and propagated severity are updated automatically.

=item *

Create objects and include them into parent objects before setting the status_no. Otherwise the status/severity is set while the object is still in the "Unplaced Objects". At that time severity propagation does not make sense.

=back

version 1.0 20 July 2002 DV

=over 4

=item *

Initial Release.

=back

=head1 DESCRIPTION

The Active Directory environment exists of sites and domain controllers per site. DirectoryAnalyzer will monitor for and report events that indicate abnormal conditions. The goal is to present alerts per domain controller and per site. This allows a visual representation of the current state of the Active Directory environment as detected by DirectoryAnalyzer. The drill down possibilities allow to quickly understand where the problems are situated.

This script is launched as a message action from the Unicenter Event Management console. It reflects the trap into the WorldView Business Process View for Active Directory. Each trap has three different severities, that will result in corresponding WorldView actions:

=over 4

=item 1 Clear

This severity indicates that the alert is cleared, the corresponding issue is solved or disappeared. The script will search for the corresponding object in WorldView and remove the object.

=item 2 Warning

This severity indicates that the alert represents a "Warning" condition. The script will search for the corresponding object in WorldView. If not found the object will be created and linked to its server or site object. The WorldView severity will be set to Warning. 

=item 3 Critical

This severity indicates that the alert represents a "Critical" condition. The script will search for the corresponding object in WorldView. If not found the object will be created and linked to its server or site object. The WorldView severity will be set to Critical.

=back

The goal is to provide additional information specifically related to visualisation. Any information that can be obtained from working with the DirectoryAnalyzer database should be collected there, not from this script.

The script handles all traps. Traps that should not result in updates in the WorldView should not trigger this script. Proper message actions need to be implemented for this. Traps that are not handled are:

=over 4

=item X, Y

License related traps. A specific Event Console message needs to be setup.

=item suspicious alerts

Since these traps relate to false alerts, we do not want to show them in the WorldView. 

=back

=head1 SYNOPSIS

 da_trap trapname severity [object_1 [object_2]]

    da_trap -h		Usage
    da_trap -h 1	Usage and description of the options
    da_trap -h 2	All documentation

=head1 OPTIONS

=over 4

=item B<trapname>

Name of the DirectoryAnalyzer trap.

=item B<severity>

Severity of the DirectoryAnalyzer trap.

=item B<object_1>

The name of the object in the trap. For some alerts object_2 needs to be specified as well.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.6.1, build 631 provided by ActiveState.

The script should run on UNIX platforms as well.

=head1 ADDITIONAL DOCUMENTATION

=head2 Naming Conventions

The sites and the servers (domain controllers) are using the same name as defined in the DirectoryAnalyzer database. Currently the label is the same as the name. Depending on the need, translation may be set-up to have a more meaningful label.

New objects generated as a result of the trap will have the name site_trapname or server_trapname. The label of the object is the trapname and the time and date of the last status change.

=cut

###########
# Variables
########### 

my $development = 1;		    # enable warnings and use strict only during development, set $development = 0 during production.
my $trace = 0;			    # 0: no tracing, 1: tracing
my $logdir = "c:/temp";		    # Log file directory
my $log = 1;			    # 0: no logging, 1: logging
my $scriptname;			    # Scriptname as used in error() and open_log()
my ($object1, $object2, $trap, $severity);
my ($object1_name, $object2_name);
my $instance_class = "White_Office_Park";
my $server_class = "Large_Factory"; # WorldView Server class
my $site_class = "LargeCity";	    # WorldView Site class
my $instance_class = "Application";
my $server_class = "Application"; # WorldView Server class
my $site_class = "Application";	    # WorldView Site class
my $parent_class;
my $status_no_warning = 2;	    # Status No Warning
my $status_no_critical = 5;	    # Status No Critical

#####
# use
#####

if ($development == 1) {
    use warnings;			    # show warning messages
    use strict 'vars';
    use strict 'refs';
    use strict 'subs';
}
use Pod::Usage;			    # Allow Usage information
use File::Basename;		    # logfilename translation

#############
# subroutines
#############

sub error($) {
    my($txt) = @_;
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
    my $command = "cawto -c red -a reverse -k Error in $scriptname: $txt";
    system("$command");
    logging("Error: $txt");
}

sub trace($) {
    if ($trace) {
	my($txt) = @_;
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
	logging("$datetime - Trace: $txt\n");
    }
}

# SUB - Open LogFile
sub open_log() {
    if ($log == 1) {
	($scriptname, undef) = split(/\./, basename($0));
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $logfilename=sprintf(">>$logdir/$scriptname%04d%02d%02d.log", $year+1900, $mon+1, $mday);
	open (LOGFILE, $logfilename);
	# open (STDERR, ">&LOGFILE");	    # STDERR messages into logfile
	# Ensure Autoflush for Log file...
	my $old_fh = select(LOGFILE);
	$| = 1;
	select($old_fh);
    }
}

# SUB - Handle Logging
sub logging($) {
    if ($log == 1) {
	my($txt) = @_;
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
	print LOGFILE $datetime." * $txt"."\n";
    }
}

# SUB - Close log file
sub close_log() {
    if ($log == 1) {
	close LOGFILE;
    }
}

sub exit_application($) {
    my($return_code) = @_;
    logging("Exit application with return code $return_code\n");
    close_log();
    exit $return_code;
}

=head2 Handle Clear

This trap occurs when an event is cleared. The script will try to find the corresponding object. If found then the object will be removed from the WorldView. Otherwise an error message will be displayed (since I assume that we should not have duplicate clear messages?).

=cut

sub handle_clear() {
    trace("Handle Clear Parent: $object1 Object1_Name: $object1_name");
    my $command = "chkobj $instance_class $object1_name";
    my $retcode = system ("repclnt $command /q");
    if ($retcode == 0) {
	my $command = "delobj $instance_class $object1_name";
	$retcode = system ("repclnt $command /q");
	if ($retcode == 0) {
	    trace("Successfully deleted trap $trap for $object1");
	} else {
	    error("Could not delete trap $trap for $object1");
	}
    } else {
	trace("Could not find trap $trap for $object1");
    }
}

=pod

=head2 Handle Warning

Find if the trap object exists. If so, check for the severity. If severity is critical, change to warning. If severity is warning, print an error message. If the object does not exist, create the trap object, link with the corresponding site or server object and set the object serverity to warning.

=cut

sub handle_warning() {
    trace("Handle Warning Parent: $object1 Object1_Name: $object1_name");
    my $command = "chkobj $instance_class $object1_name";
    my $retcode = system ("repclnt $command /q");
    if ($retcode == 256) {
	error("Unicenter Repository Service not active, trying to start ...");
	# start_repository_server;
    }
    if ($retcode == 65280) {	    # Object does not exist, create it ...
	my $command = "creaobj $instance_class $object1_name label $trap";
	$retcode = system ("repclnt $command /q");
	if ($retcode == 0) {
	    trace("Successfully created trap $trap for $object1 severity warning");
	    my $command = "creaincl $instance_class $object1_name $parent_class $object1";
	    my $retcode = system ("repclnt $command /q");
	    if ($retcode == 0) {
		trace("Successfully linked $trap to object $object1.");
	    } else {
		error("Could not link $trap to object $object1 ($command - retcode: $retcode)");
	    }
	} else {
	    error("Could not create trap $trap for $object1");
	}
    } elsif (not($retcode == 0)) {
	error("Unexpected returncode $retcode from $command.");
    }
    # Object found or created - Check for status (should be critical)
    # This needs to be implemented
    # my $command = "getilp $instance_class $object1_name severity";
    # my $retcode = system ("repclnt $command /q"); # Return code availble in STDOUT
    # Object found - set severity to Warning
    my $command = "setilp $instance_class $object1_name status_no $status_no_warning";
    my $retcode = system ("repclnt $command /q");
    if ($retcode == 0) {
        trace("Set severity for $trap at $object1 to warning.");
    } else {
        error("Could not set severity for $trap at $object1 to warning.");
    }
}

=pod

=head2 Handle Critical

The expected situation is that a critical alert will occur only after a warning trap has been received. In this case it is sufficient to update the status from the trap object from warning to critical only.

However if the trap object cannot be found, it is created and linked to the corresponding server or site object. An error message is printed (will be printed in a future version of the script...).

=cut

sub handle_critical() {
    trace("Handle Critical: Parent: $object1 Class: $parent_class Object1_Name: $object1_name");
    my $command = "chkobj $instance_class $object1_name";
    my $retcode = system ("repclnt $command /q");
    if ($retcode == 256) {
	error("Unicenter Repository Service not active, trying to start ...");
	# start_repository_server;
    }
    if ($retcode == 65280) {	    # Object does not exist, create it ...
	my $command = "creaobj $instance_class $object1_name label $trap";
	$retcode = system ("repclnt $command /q");
	if ($retcode == 0) {
	    trace("Successfully created trap $trap for $object1 severity critical");
	    my $command = "creaincl $instance_class $object1_name $parent_class $object1";
	    my $retcode = system ("repclnt $command /q");
	    if ($retcode == 0) {
		trace("Successfully linked $trap to object $object1.");
	    } else {
		error("Could not link $trap to object $object1 ($command returncode: $retcode)");
	    }
	} else {
	    error("Could not create trap $trap for $object1");
	}
    } elsif (not($retcode == 0)) {
	error("Unexpected returncode $retcode from $command.");
    }
    # Object found - Check for status (should be critical)
    # This needs to be implemented
    # my $command = "getilp $instance_class $object1_name severity";
    # my $retcode = system ("repclnt $command /q"); # Return code availble in STDOUT
    # Object found - set severity to Warning
    my $command = "setilp $instance_class $object1_name status_no $status_no_critical";
    my $retcode = system ("repclnt $command /q");
    if ($retcode == 0) {
        trace("Set severity for $trap at $object1 to warning.");
    } else {
        error("Could not set severity for $trap at $object1 to warning.");
    }
}

#########
# M A I N
#########

open_log();
my $nr_args = @ARGV;
my $args = "@ARGV";
logging("Starting application with arguments <$args>.");
($trap, $severity, $object1_class, $object1, $object2) = split " ", $args;
if ($nr_args < 2) {
    pod2usage(verbose => 0);
} elsif ($trap eq "-h") {
    if    ($severity == 2) { pod2usage (verbose => 2); }
    elsif ($severity == 1) { pod2usage (verbose => 1); }
    else { pod2usage (verbose => 0); }
}

if (defined $object1_class) {
    if ($object1_class eq "daVarServerName:") {
	$parent_class = "$server_class";
    } elsif ($object1_class eq "daVarSiteName:") {
	$parent_class = "$site_class";
    } else {
	$parent_class = "$server_class";
	error("Investigate NC class?");
    }
}


# Remove semicolon from trap, semicolon is the last character from the trap.
if (index($trap, ":") > -1) {
    $trap = substr($trap, 0, length($trap)-1);
}

# Remove semicolon from severity, semicolon is the last character.
if (index($severity, ":") > -1) {
    $severity = substr($severity, 0, length($severity)-1);
}

if (defined $object1) {
    $object1_name = $object1 . "_" . $trap;
}

if (defined $object2) {
    $object2_name = $object2 . "_" . $trap;
}

if ($severity == 1) {
    handle_clear();
} elsif ($severity == 2) {
    handle_warning();
} elsif ($severity == 3) {
    handle_critical();
} else {
    error("Don't know how to handle severity $severity");
    exit_application(1);
}

exit_application(0);

=pod

=head1 TO DO

=over 4

=item *

Start the repserver automatically if not running.

=item *

Correct the parent object for naming context events. Add DCs into different naming contexts, allow alerts to be associated with the naming contexts.

=item *

Verify the returncode for getilp for severity. Check if this is the expected return code.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
