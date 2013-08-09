=head1 NAME

changeFieldValues - Change Field Values 999999 to best guesses.

=head1 VERSION HISTORY

version 1.0 13 April 2009 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will change field values 999999 for best guesses for the field.

=head1 SYNOPSIS

 changeFieldValues.pl [-t] [-l log_dir] [-a]

 changeFieldValues -h 	   Usage
 changeFieldValues -h 1	   Usage and description of the options
 changeFieldValues -h 2	   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Disable tracing, default: tracing. Remark: reverse logic!

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-a>

If set, then run script over all tables. Otherwise, use defined tablearray.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP, Perl v5.8.8, build 804 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir,$dbh, $reportdate, $reportdays);
# my @table_arr=('bru000center83m_s','bru000center83m_l','bru000center83m_p','bru000center83m_n');
my @table_arr=('bru000center41m_i');
my $alltablesflag = "No";

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
use MySQLModules;
use dbParams;

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

######
# Main
######

# Handle input values
my %options;
getopts("tl:h:a", \%options) or pod2usage(-verbose => 0);
# The Filename must be specified
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
	Log::trace_flag(0);
} else {
    Log::trace_flag(1);
}
# Find log file directory
if ($options{"l"}) {
    $logdir = logdir($options{"l"});
    if (not(defined $logdir)) {
		print "Could not set $logdir as Log directory, exiting...\n";
		exit_application(1);
    }
} else {
    $logdir = logdir();
    if (not(defined $logdir)) {
		print "Could not find default Log directory, exiting...\n";
		exit_application(1);
    }
}
if (-d $logdir) {
	# trace("Logdir: $logdir");
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
if (defined $options{"a"}) {
	$alltablesflag = "Yes";
}
# End handle input values

if ($alltablesflag eq "Yes") {
	@table_arr = get_all_tables();
}

# Make database connection
my $connectionstring = "DBI:mysql:database=$databasename;host=$server;port=$port";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

# Handle all tables in array
foreach my $tablename (@table_arr) {
	trace("Table $tablename");
	# Investigate SizeUsedMB and AllocsizeMB
	# Both 999999 -> change to 0
	# One 999999, change to the other one
	#
	# Check both 999999 First
	my $sql = "UPDATE $tablename 
						SET SizeUsedMB=0, AllocatedMB=0 
						WHERE SizeUsedMB=$triggerint and AllocatedMB=$triggerint";
	my $rows_affected = $dbh->do($sql);
	if (defined $rows_affected) {
		trace("$rows_affected rows with both SizeUsedMB and AllocatedMB invalid, reset to 0");
	} else {
		error("SQL Error with $sql, ".$dbh->errstr);
		exit_application(1);
	}
	# Now check for SizeUsedMB invalid
	$sql = "UPDATE $tablename 
				   SET SizeUsedMB=AllocatedMB
				   WHERE SizeUsedMB=$triggerint";
	$rows_affected = $dbh->do($sql);
	if (defined $rows_affected) {
		trace("$rows_affected rows with invalid SizeUsedMB, set to AllocatedMB");
	} else {
		error("SQL Error with $sql, ".$dbh->errstr);
		exit_application(1);
	}
	# and check for AllocatedMB invalid
	$sql = "UPDATE $tablename 
				   SET AllocatedMB=SizeUsedMB
				   WHERE AllocatedMB=$triggerint";
	$rows_affected = $dbh->do($sql);
	if (defined $rows_affected) {
		trace("$rows_affected rows with invalid AllocatedMB, set to SizeUsedMB");
	} else {
		error("SQL Error with $sql, ".$dbh->errstr);
		exit_application(1);
	}
	# Now verify dates
	# First calculate report date
	my $query = "SELECT FROM_DAYS(TO_DAYS(Created)+CreatedDays) as reportdate, 
						(TO_DAYS(Created)+CreatedDays) as reportdays 
					    FROM $tablename WHERE NOT CreatedDays = $triggerint LIMIT 1";
	my $sth = $dbh->prepare($query);
	my $rv = $sth->execute();
	if (not(defined $rv)) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		$reportdate = $ref->{reportdate};
		$reportdays = $ref->{reportdays};
		trace("Report Date is $reportdate ($reportdays)");
	} else {
		error("Query $query did not return any results, skip rest of table handling");
		next;
	}
	# Update CreatedDays where required
	$sql = "UPDATE $tablename
				   SET CreatedDays = ($reportdays - TO_DAYS(Created))
				   WHERE CreatedDays = 999999";
	$rows_affected = $dbh->do($sql);
	if (defined $rows_affected) {
		trace("$rows_affected rows with invalid CreatedDays, value calculated from Created");
	} else {
		error("SQL Error with $sql, ".$dbh->errstr);
		exit_application(1);
	}
	# Update ModifiedDays where required
	$sql = "UPDATE $tablename
				   SET ModifiedDays = ($reportdays - TO_DAYS(Modified))
				   WHERE ModifiedDays = 999999";
	$rows_affected = $dbh->do($sql);
	if (defined $rows_affected) {
		trace("$rows_affected rows with invalid ModifiedDays, value calculated from Modified");
	} else {
		error("SQL Error with $sql, ".$dbh->errstr);
		exit_application(1);
	}
	# Update AccessedDays where required
	$sql = "UPDATE $tablename
				   SET AccessedDays = ($reportdays - TO_DAYS(Accessed))
				   WHERE AccessedDays = 999999";
	$rows_affected = $dbh->do($sql);
	if (defined $rows_affected) {
		trace("$rows_affected rows with invalid AccessedDays, value calculated from Accessed");
	} else {
		error("SQL Error with $sql, ".$dbh->errstr);
		exit_application(1);
	}
	# Now calculate number of records with dates in the future
	$query = "SELECT count(*) as count FROM $tablename WHERE CreatedDays < 0";
	$sth = $dbh->prepare($query);
	$rv = $sth->execute();
	if (not(defined $rv)) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		my $count = $ref->{count};
		trace("$count records with Created date in the future");
	} else {
		error("Query $query did not return any results.");
	}
	$query = "SELECT count(*) as count FROM $tablename WHERE ModifiedDays < 0";
	$sth = $dbh->prepare($query);
	$rv = $sth->execute();
	if (not(defined $rv)) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		my $count = $ref->{count};
		trace("$count records with Modified date in the future");
	} else {
		error("Query $query did not return any results.");
	}
	$query = "SELECT count(*) as count FROM $tablename WHERE AccessedDays < 0";
	$sth = $dbh->prepare($query);
	$rv = $sth->execute();
	if (not(defined $rv)) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		my $count = $ref->{count};
		trace("$count records with Accessed date in the future");
	} else {
		error("Query $query did not return any results.");
	}
}

exit_application(0);

=head1 To Do

=over 4

=item *

Nothing for now...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
