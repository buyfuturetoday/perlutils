=head1 NAME

getStateChanges - Get State Changes from monstat table.

=head1 VERSION HISTORY

version 1.0 25 February 2010 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will get state changes from monstat table. Any state change to OK or from OK will be listed in the statechange table.

=head1 SYNOPSIS

 getStateChanges.pl [-t] [-l log_dir] 

 getStateChanges -h	   Usage
 getStateChanges -h 1	   Usage and description of the options
 getStateChanges -h 2	   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP, Perl v5.8.8, build 820 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $dbh);
my $printerror = 0;

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use DBI();
use Log;
use amParams;

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if (defined $dbh) {
		$dbh->disconnect;
	}
	logging("Exit application with return code $return_code.\n");
    close_log();
    exit $return_code;
}

sub trim {
    my @out = @_;
    for (@out) {
        s/^\s+//;
        s/\s+$//;
    }
    return wantarray ? @out : $out[0];
}

sub handle_change_status($$$$) {
	my ($sth, $application, $msdatetime, $status) = @_;
	my ($msdate, $mstime) = split / /, $msdatetime;
	my ($mshour, $msmin) = split /:/, $mstime;
	$sth->bind_param(1, $application);
	$sth->bind_param(2, $msdatetime);
	$sth->bind_param(3, $status);
	$sth->bind_param(4, $msdate);
	$sth->bind_param(5, $mstime);
	$sth->bind_param(6, $mshour);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Query to insert into table for $application, $msdatetime, $status not successful " . $sth->errstr);
	} elsif (not ($rv == 1)) {
		error("$rv rows inserted for $application, $msdatetime, $status. 1 expected.");
	}
}

######
# Main
######

# Handle input values
my %options;
getopts("tl:h:an:", \%options) or pod2usage(-verbose => 0);
# my $arglength = scalar keys %options;  
# if ($arglength == 0) {			# If no options specified,
#   $options{"h"} = 0;			# display usage.
# }
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
    if (not(defined $logdir)) {
		error("Could not set $logdir as Log directory, exiting...");
		exit_application(1);
    }
} else {
    $logdir = logdir();
    if (not(defined $logdir)) {
		error("Could not find default Log directory, exiting...");
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
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Make database connection to source database
my $connectionstring = "DBI:mysql:database=$databasename;host=$server;port=$port";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

# Drop table first
my $query = "TRUNCATE TABLE statechanges";
my $rv = $dbh->do($query);
if (not(defined  $rv)) {
	error("Could not truncate table statechanges. ".$dbh->errstr);
	exit_application(1);
}

# Now scan through applications for state changes.
$query = "SELECT application, msdatetime, status FROM monstat
				ORDER BY application, msdatetime ASC";
my $sth = $dbh->prepare($query);
$rv = $sth->execute();
if (not(defined $rv)) {
	error("Could not execute query $query, Error: ".$sth->errstr);
	exit_application(1);
}
my $currappl = "Start van de cyclus";
my ($currstatus);
# Prepare SQL to update statechanges table
my $updquery = "INSERT INTO statechanges (application, msdatetime, status, msdate, mstime, mshour)
							VALUES (?,?,?,?,?,?);";
my $sthupd = $dbh->prepare($updquery);
# Walk through all event messages
while (my $ref = $sth->fetchrow_hashref) {
	my $application = $ref->{application};
	my $msdatetime = $ref->{msdatetime};
	my $status = $ref->{status};
	if ($status ne "ok") {
		$status = "nok";		# change critical and error status to nok
	}
	if ($currappl ne $application) {
		$currappl = $application;
		$currstatus = $status;
		# Make a note of the start status of the application
		handle_change_status($sthupd, $application, $msdatetime, $status);
	} elsif ($currstatus ne $status) {
		$currstatus = $status;
		handle_change_status($sthupd, $application, $msdatetime, $status);
	}
}

$sth->finish();

exit_application(0);

=head1 To Do

=over 4

=item *

Nothing documented for now...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
