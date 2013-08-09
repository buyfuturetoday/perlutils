=head1 NAME

appAlert - This script will find applications with state change from OK and prepare an SMS alert.

=head1 VERSION HISTORY

version 1.0 18 February 2010 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will find monitored applications with a state change from OK to ERROR or CRITICAL. When an application is found in the time interval, an SMS alert is prepared.

This application will be triggered by an external application on a regular base. For this the scheduler script will be extended to include triggering of this application.

The script will use a table appstates that keeps track of applications that are not in the state OK. When new applications are added to the table, alerts need to be generated. These alert messages will be written to the appstates table with the 'NEW' flag. Another application will do the actual alerting. The 'NEW' flag will be cleared after the alerting.

=head1 SYNOPSIS

appAlert.pl [-t] [-l log_dir]

    appAlert -h		    Usage
    appAlert -h 1	    Usage and description of the options
    appAlert -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP SP2, Perl v5.8.8, build 820 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $dbh);
# my ($msdatetime, $applname);
my $printerror = 0;
my $timeout = 60;
my $lateststatus = "appAlert_latest_status";

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use Log;					# Application and error logging
use DBI();
use amParams;

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if (defined $dbh) {
		$dbh->disconnect;
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

=pod

=head2 Check Alerts 

This procedure will check for alerts for which the status is changed from OK. Therefore all applications with last alert with status not OK and not already in appstates will be listed. For each alert an escalation will be generated. The alert wil be added to the appstates table.

=cut

sub check_alerts_in_interval() {
	# First create temporary table with per application last status
print "CREATE TEMP TABLE QUERY\n";
	my $query = "CREATE TEMPORARY TABLE laststatus
						SELECT application, max(msdatetime) as msdatetime, status
						FROM monstat
						GROUP BY application";
	my $rv = $dbh->do($query);
	if (not(defined $rv)) {
		error("Could not execute query $query, Error: ".$dbh->errstr);
		exit_application(1);
	}
	# Be careful, above query will have application / max(msdatetime) pairs
	# but you're not sure about the status value due to the GROUP BY application.
	# Therefore run a new query to update status values.
print "UPDATE QUERY\n";
	$query = "SELECT ms.status as status, ls.msdatetime as msdatetime, 
				ls.application as application
			  FROM monstat ms, laststatus ls
			  WHERE ls.application = ms.application
			  AND ls.msdatetime = ms.msdatetime";
	my $sth = $dbh->prepare($query);
	$rv = $sth->execute;
	if (not(defined $rv)) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	while (my $ref = $sth->fetchrow_hashref) {
		my $app = $ref->{application};
		my $msdatetime = $ref->{msdatetime};
		my $status = $ref->{status};
		updatelaststatus($app, $msdatetime, $status);
	}
	# Now get those applications with not status OK
	# and not in appstates. These are the applications for which an alert must be sent.
print "SELECT FOR STATUS NOK QUERY\n";
	$query = "SELECT application, msdatetime, status
					FROM laststatus
					WHERE NOT application IN (
						SELECT distinct(application) as application FROM appstates)
					AND NOT status = 'ok'";
	$sth = $dbh->prepare($query);
	$rv = $sth->execute;
	if (not(defined $rv)) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	while (my $ref = $sth->fetchrow_hashref) {
		my $app = $ref->{application};
		my $msdatetime = $ref->{msdatetime};
		my $status = $ref->{status};
		add2appstates($app, $msdatetime, $status);
	}
}

=pod

=head2 Add to Appstates table

This procedure will add the newly discovered alert to the appstates table.

=cut

sub add2appstates($$$) {
	my ($application, $msdatetime, $status) = @_;
	logging("Add alert for $application, status $status at $msdatetime to appstates table");
	my $query = "INSERT INTO appstates (application, msdatetime, status, alert)
						VALUES (?, ?, ?, 'NEW');";
	my $sth = $dbh->prepare($query);
	$sth->bind_param(1, $application);
	$sth->bind_param(2, $msdatetime);
	$sth->bind_param(3, $status);
	my $rv = $sth->execute();
	if (not(defined $rv)) {
		error("Could not execute query $query, Error: ".$dbh->errstr);
		exit_application(1);
	} elsif (not($rv == 1)) {
		error("$rv rows added to table appstates, 1 row expected");
	}
}

=pod

=head2 Update Last Status

This procedure will guarantee that for all applications the last status field is correct. This could be done in a single UPDATE statement, but with a very poor performance. Therefore this split-up in a SELECT and UPDATE statement.

=cut

sub updatelaststatus($$$) {
	my ($application, $msdatetime, $status) = @_;
	my $query = "UPDATE laststatus set status = ? 
				 WHERE application = ? AND msdatetime = ?";
	my $sth = $dbh->prepare($query);
	$sth->bind_param(2, $application);
	$sth->bind_param(3, $msdatetime);
	$sth->bind_param(1, $status);
	my $rv = $sth->execute();
	if (not(defined $rv)) {
		error("Could not execute query $query, Error: ".$dbh->errstr);
		exit_application(1);
	} elsif (not($rv == 1)) {
		error("$rv rows updated in table laststatus, 1 row expected");
	}
}
=pod

=head2 Remove Alerts

This procedure will remove alerts that have their status on OK from appstates table. 

=cut

sub remove_alerts() {
	my $query = "DELETE FROM appstates WHERE application in (
						SELECT application FROM laststatus WHERE status = 'ok');";
	my $rv = $dbh->do($query);
	if (not(defined $rv)) {
		error("Could not execute query $query, Error: ".$dbh->errstr);
		exit_application(1);
	} elsif ($rv > 0) {
		logging("$rv applications removed from table appstates");
	}
}

######
# Main
######

# Handle input values
my %options;
getopts("tl:h:", \%options) or pod2usage(-verbose => 0);
# No options are mandatory for this script
# my $arglength = scalar keys %options;  
# if ($arglength == 0) {			# If no options specified,
#    $options{"h"} = 0;			# display usage. jmeter plan is mandatory
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
		error("Could not set d:/temp/log as Log directory, exiting...");
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

# Set-up database connection
my $connectionstring = "DBI:mysql:database=$databasename;host=$server;port=$port";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

# OK, run is required
# Check for alerts in this interval and trigger alerts for status changes
check_alerts_in_interval();

# Remove alerts with status change to OK from table
remove_alerts();

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Nothing documented for now....

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@hp.comE<gt>
