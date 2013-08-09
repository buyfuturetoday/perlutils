=head1 NAME

AnalyzeTable - Script to analyze table field per field.

=head1 VERSION HISTORY

version 1.0 28 April 2011 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This script will analyze a table field by field. First it will calculate the number of records and the number of duplicate records. Then for each column the number of NULL values will be calculated, and the number of unique values for the column. 

Columns with a high percentage of NULL values are not (very) relevant. Columns with a high number of unique values (or all uniques) are key fields.

=head1 SYNOPSIS

 AnalyzeTable.pl [-t] [-l log_dir] -c tablename

 AnalyzeTable -h	Usage
 AnalyzeTable -h 1  Usage and description of the options
 AnalyzeTable -h 2  All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-c tablename>

Table name to verify.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP, Perl v5.10.0, build 1005 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $dbi, $dbh, $tablename, @columns, $cntrecs);
my $printerror = 0;
my $resdir = "d:/temp/";

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
# use dbParams_analyze;
use dbParams_aluCMDB;

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if (defined $dbh) {
		$dbh->disconnect;
	}
	if (defined $dbi) {
		$dbi->disconnect;
	}
	close RES;
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

sub gettotalrecords($$) {
	my ($dbh, $tablename) = @_;
	my $query = "SELECT COUNT(*) as cnt FROM $tablename";
	my $sth = $dbh->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		$cntrecs = $ref->{cnt};
	} else {
		error("Could not find total number of records, $query");
		exit_application(1);
	}
	$sth->finish;
	print RES "Total Records: $cntrecs\n";
}

sub getcolumns($$$) {
	my ($dbh, $tableschema, $tablename) = @_;
	my $query = "SELECT column_name FROM COLUMNS
			     WHERE table_Schema = '$tableschema' AND table_name = '$tablename'";
	my $sth = $dbh->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	while (my $ref = $sth->fetchrow_hashref) {
		my $col = $ref->{column_name};
		push @columns, $col;
	}
	$sth->finish;
}

sub handlecolumn($$$) {
	my ($dbh, $tablename, $column) = @_;
	my ($nullcnt, $distcnt);
	# First get all NULL values
	my $query = "SELECT count(*) as cnt FROM $tablename
				 WHERE `$column` is NULL";
	my $sth = $dbh->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		$nullcnt = $ref->{cnt};
	} else {
		error("Could not find total number of records, $query");
		exit_application(1);
	}
	$sth->finish;
	# Then get number of distinct values
	# First create table with distinct column values
	$query = "CREATE TEMPORARY TABLE dum SELECT distinct(`$column`)
			  FROM $tablename 
			  WHERE `$column` is not NULL";
	$rv = $dbh->do($query);
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	# Then count number of distinct values
	$query = "SELECT count(*) as cnt FROM dum";
	$sth = $dbh->prepare($query);
	$rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		$distcnt = $ref->{cnt};
	} else {
		error("Could not find total number of records, $query");
		exit_application(1);
	}
	$sth->finish;
	# and drop table, since database handle will be reused
	$query = "DROP TABLE dum";
	$rv = $dbh->do($query);
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	print RES "$column;$nullcnt;$distcnt\n";
}

######
# Main
######

# Handle input values
my %options;
getopts("tl:h:c:", \%options) or pod2usage(-verbose => 0);
my $arglength = scalar keys %options;  
if ($arglength == 0) {			# If no options specified,
	$options{"h"} = 0;			# display usage.
}
#Print Usage
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
# Find Tablename
if ($options{"c"}) {
	$tablename = $options{"c"};
} else {
	error("Tablename not defined, exiting...");
	exit_application(1);
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Create Result File
my $resfile = $resdir.$tablename."_".time.".txt";
my $openres = open(RES, ">$resfile");
if (not defined $openres) {
	error("Could not open $resfile for writing, exiting...");
	exit_application(1);
}

# Make database connection
my $connectionstring = "DBI:mysql:database=$dbsource;host=$server;port=$port";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $dbsource, exiting...");
   	exit_application(1);
}

# Also make a database connection to the information_schema
$connectionstring = "DBI:mysql:database=information_schema;host=$server;port=$port";
$dbi = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbi) {
   	error("Could not open information_schema, exiting...");
   	exit_application(1);
}

# Get column names
getcolumns($dbi, $dbsource, $tablename);

# Get total number of records
gettotalrecords($dbh, $tablename);

# Handle all columns in column array
# First check if there
while (@columns) {
	while (my $column = shift @columns) {
		handlecolumn($dbh, $tablename, $column);
	}
}

exit_application(0);

=head1 To Do

=over 4

=item *

Count number of distinct records. For now the assumption is that the table only has unique records.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@hp.comE<gt>
