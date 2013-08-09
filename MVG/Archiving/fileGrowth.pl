=head1 NAME

fileGrowth - Growth of Number of Files

=head1 VERSION HISTORY

version 1.1 28 April 2009 DV

=over 4

=item *

Rework to collect results in database.

=back

version 1.0 21 April 2009 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will create a report with the file growth, number of files, size used and size allocated.

=head1 SYNOPSIS

 fileGrowth.pl [-t] [-l log_dir] [-a | -n YYYY-MM-DD]

 fileGrowth -h	 	   Usage
 fileGrowth -h 1	   Usage and description of the options
 fileGrowth -h 2	   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-a>

If set, then run script over all tables. Otherwise, use defined tablearray.

=item B<-n>

If set, then run script only over tables that are created I<after> YYYY-MM-DD.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP, Perl v5.8.8, build 804 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $dbh, $dbres, $dbm, $dateid, $newtabledate);
my @wherevariables = ('created',
					  'modified',
					  'accessed');
# my @table_arr=('bru000center44m_o','bru000center84m_k','nos030mercur19m_m');
my @table_arr=('bru000center84m_k');
my $alltablesflag = "No";
my $resulttable = "FileGrowth";

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
	if (defined $dbres) {
		$dbres->disconnect;
	}
	if (defined $dbm) {
		$dbm->disconnect;
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

=pod

=head2 Handle Query

Run the query for every table in the database or for a single table (to do). Summarize results in hash.

=cut

sub handle_query($$) {
	my ($tablename,$wherevariable) = @_;
	my ($server, $drive) = split/_/,$tablename;
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
	print "$datetime - Handling query $wherevariable for $server, drive $drive\n";
	my $query = "SELECT count(*) as totalfiles, sum(sizeusedmb) as sizeused, sum(allocatedmb) as allocsize, year($wherevariable) as year FROM $tablename WHERE year($wherevariable) > 1999 AND year ($wherevariable) < 2010 GROUP BY year";
	logging($query);
	my $sth = $dbh->prepare($query);
	my $rv = $sth->execute();
	if (not(defined $rv)) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	while (my $ref = $sth->fetchrow_hashref) {
		my $totalfiles = $ref->{totalfiles} || 0;
		my $sizeused = $ref->{sizeused} || 0;
		my $allocsize = $ref->{allocsize} || 0;
		my $interval = $ref->{year} || 0;
		add2resulttable($server,$drive,$interval,$wherevariable,$totalfiles,$sizeused,$allocsize);
	}
	$sth->finish();
}

=pod

=head2 Add to Result Table

Add the result query to the result table.

=cut

sub add2resulttable() {
	my($server,$drive,$interval,$lifecycle,$files,$sizeused,$sizealloc) = @_;
	my $query = "INSERT INTO $resulttable 
				 (DateID,Server,Drive,Period,Lifecycle,Files,SizeUsed,SizeAlloc) VALUES
				 ('$dateid','$server','$drive','$interval','$lifecycle','$files','$sizeused','$sizealloc')";
	my $rows_affected = $dbres->do($query);
    if (not defined $rows_affected) {
		error("PID: $$ - SQL Error with *** $query, error: ".$dbres->errstr);
		exit_application(1);
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
# Check if result needs to run over all tables
if (defined $options{"a"}) {
	$alltablesflag = "Yes";
}
# Check if result needs to run only over new tables
if (defined $options{"n"}) {
	$newtabledate = $options{"n"};
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Check for ResultDB, Create DB if required
check_results_db($resultdb) or exit_application(1);

# Get All tables if required
if ($alltablesflag eq "Yes") {
	@table_arr = get_all_tables();
	if (scalar @table_arr == 1) {
		exit_application(1);
	}
}

# Get only recent tables.
# This will overwrite 'all tables' flag if both are specified
if (defined $newtabledate) {
	@table_arr = get_new_tables($newtabledate);
	if (scalar @table_arr == 1) {
		exit_application(1);
	}
}

# Calculate DateID
my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$dateid = sprintf "%04d%02d%02d%02d%02d%02d", $year+1900, $mon+1, $mday, $hour,$min,$sec;

# Make database connection to filedata database
my $connectionstring = "DBI:mysql:database=$databasename;host=$server;port=$port";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

# Make database connection to results database
$connectionstring = "DBI:mysql:database=$resultdb;host=$server;port=$port";
$dbres = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbres) {
   	error("Could not open $resultdb, exiting...");
   	exit_application(1);
}

# Check for Result Table FileGrowth, create table if required
$dbm = connect2masterdb() or exit_application(1);
my $query = "SELECT table_name FROM tables WHERE table_schema = '$resultdb' AND table_name = '$resulttable'";
my $sth = $dbm->prepare($query);
my $rv = $sth->execute();
if (not(defined $rv)) {
	error("Could not execute query $query, Error: ".$sth->errstr);
	exit_application(1);
}
my $disc_name = "NotDefined";
if (my $ref = $sth->fetchrow_hashref) {
	my $disc_name = $ref->{table_name} || "NotDefined";
}
$sth->finish;
if ($disc_name eq $resulttable) {
	logging("Table $resulttable exists already, rows will be added.");
} else {
	logging("Table $resulttable will be created.");
	# Create Table
	$query = "CREATE TABLE $resulttable 
			( `DateID` varchar(256) default NULL,
			  `Server` varchar(256) default NULL,
			  `Drive` varchar(256) default NULL,
			  `Period` varchar(256) default NULL,
			  `Lifecycle` varchar(256) default NULL,
			  `Files` int(11) default NULL,
			  `SizeUsed` float default NULL,
			  `SizeAlloc` float default NULL
			) ENGINE=MyISAM DEFAULT CHARSET=latin1;";
	$rv = $dbres->do($query);
	if (defined $rv) {
	    logging("Table $resulttable created");
	} else {
	    error("Could not create table $resulttable. Error: ".$dbh->errstr."\nQuery: $query");
    	exit_application(1);
    }
}

# Handle all tables
foreach my $tablename (@table_arr) {
	# Handle each File Lifecycle category
	foreach my $wherevariable (@wherevariables) {
		handle_query($tablename,$wherevariable);
	}
}

exit_application(0);

=head1 To Do

=over 4

=item *

Nothing documented for now...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
