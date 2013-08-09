=head1 NAME

fileAge - File Age by Created, Modified, Accessed Date

=head1 VERSION HISTORY

version 1.0 05 May 2009 DV

=over 4

=item *

Initial release, based on fileAgeCreated.

=back

=head1 DESCRIPTION

This application will fill the table with file age information.

=head1 SYNOPSIS

 fileAge.pl [-t] [-l log_dir] [-a | -n YYYY-MM-DD]

 fileAge -h	 	   Usage
 fileAge -h 1	   Usage and description of the options
 fileAge -h 2	   All documentation

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

my ($logdir,$dbh, $dbres, $dbm, $dateid, $newtabledate, @labels);
my @daysint_arr = (3,7,90,180,365);
my @label_names = ('0 - 3 days',
				   '3 days - 1 week',
				   '8 - 90 days',
				   '3 to 6 months',
				   '6 months - 1 year',
				   'Over 1 Year');
my @wherevariables = ('createddays',
					  'modifieddays',
					  'accesseddays');
my ($dayslow, $daysupp);
# my @table_arr=('bru000center44m_o','bru000center84m_k','nos030mercur19m_m');
my @table_arr=('bru000center84m_k');
my $alltablesflag = "No";
my $resulttable = "FileAge";

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

sub handle_query($$$$) {
	my ($tablename,$whereclause,$printlabel,$wherevariable) = @_;
	my ($server, $drive) = split/_/,$tablename;
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
	print "$datetime - Handling query $printlabel ($wherevariable) for $server, drive $drive\n";
	my $query = "SELECT count(*) as totalfiles, sum(sizeusedmb) as sizeused, sum(allocatedmb) as allocsize from $tablename where $whereclause";
	logging($query);
	my $sth = $dbh->prepare($query);
	my $rv = $sth->execute();
	if (not(defined $rv)) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		my $totalfiles = $ref->{totalfiles} || 0;
		my $sizeused = $ref->{sizeused} || 0;
		my $allocsize = $ref->{allocsize} || 0;
		add2resulttable($server,$drive,$printlabel,$wherevariable,$totalfiles,$sizeused,$allocsize);

	} else {
		error("Query $query did not return any rows!");
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
#    $options{"h"} = 0;			# display usage.
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

# Check for Result Table FileAge, create table if required
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
	# Handle each interval per table
	$dayslow = -1;
	foreach $daysupp (@daysint_arr) {
		my $label = "$dayslow - $daysupp";
		foreach my $wherevariable (@wherevariables) {
			my $whereclause = "$wherevariable > $dayslow and $wherevariable <= $daysupp";
			handle_query($tablename,$whereclause,$label,$wherevariable);
		}
		# Prepare dayslow for next foreach run
		$dayslow = $daysupp;
	}
	# Final query for upperlimit only
	my $label = "> $dayslow";
	foreach my $wherevariable (@wherevariables) {
		my $whereclause = "$wherevariable > $dayslow";
		handle_query($tablename,$whereclause,$label,$wherevariable);
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
