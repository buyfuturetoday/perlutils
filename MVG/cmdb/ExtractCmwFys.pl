=head1 NAME

ExtractCmwFys - Extract information from CMW Physical Datamodel.

=head1 VERSION HISTORY

version 1.0 24 May 2008 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will read CMW Physical database information as available in the MySQL Information Schema database, and make the information available in the cmdbmeta database. 

The application is build to connect to a MySQL database server. DBI modules have been used, so conversion to another type of database server shouldn't be difficult.

=head1 SYNOPSIS

 ExtractCmwFys.pl [-t] [-l log_dir]

 ExtractCmwFys -h	 	   Usage
 ExtractCmwFys -h 1	   Usage and description of the options
 ExtractCmwFys -h 2	   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.8.0, build 804 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir,$dbh, $dbmeta, $table_count, $attribute_count);
my $username = "root";
my $password = "Monitor1";
my $server = "localhost";
my $databasename = "information_schema";
my $cmdbmetaDB = "cmdbmeta";
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

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if (defined $dbh) {
		$dbh->disconnect;
	}
	if (defined $dbmeta) {
		$dbmeta->disconnect;
	}
	my $status_msg = "$table_count table records, $attribute_count attribute records";
	print $status_msg."\n";
	logging($status_msg);
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
getopts("tl:h:", \%options) or pod2usage(-verbose => 0);
# This application does not require arguments
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
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Make database connection to database Information_Schema database
my $connectionstring = "DBI:mysql:database=$databasename;host=$server";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

# Make database connection to cmdbMetaData database
$connectionstring = "DBI:mysql:database=$cmdbmetaDB;host=$server";
$dbmeta = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbmeta) {
   	error("Could not open $cmdbmetaDB, exiting...");
   	exit_application(1);
}

my $cmw_table = "cmw_fys_table_info";
# Create cmw_fys_table_info if not exists
my $create_query = "CREATE TABLE IF NOT EXISTS $cmw_table (
  					`tablename` varchar(255) NOT NULL,
  					`documentation` text,
					`description` text,
				    `etl` text,
				    `remark` text,
					`cmw_observation` text
					) ENGINE=InnoDB DEFAULT CHARSET=latin1";
my $stmeta = $dbmeta->prepare($create_query);
if (not(defined $stmeta->execute())) {
	error("Table $cmw_table doesn't exist and could not be created, " . $stmeta->errstr);
	exit_application(1);
}

# Empty table cmw_fys_table_info
my $empty_query = "TRUNCATE TABLE $cmw_table";
$stmeta = $dbmeta->prepare($empty_query);
if (not (defined $stmeta->execute())) {
	error("Could not truncate table $cmw_table, " . $stmeta->errstr);
}

# Prepare insert statement for cmdbmeta table
my $insquery = "INSERT INTO $cmw_table (tablename) values (?)";
$stmeta = $dbmeta->prepare($insquery);
# Select all CMW Table names
my $query = "SELECT table_name FROM tables WHERE table_schema = 'cmdb'";
my $sth = $dbh->prepare($query);
if (not(defined $sth->execute())) {
	error($sth->errstr);
	exit_application(1);
}
# Add tablenames to cmw_fys_table_info
while (my $ref = $sth->fetchrow_hashref()) {
	my $table_name = $ref->{table_name};
	if (not(defined $stmeta->execute($table_name))) {
		error("Could not add $table_name to cmw_fys_table_info");
	}
	$table_count++;
}

$cmw_table = "cmw_fys_table_attr";
# Create table if it does not exists
$create_query = "CREATE TABLE IF NOT EXISTS `cmw_fys_table_attr` (
				  `tablename` varchar(255) NOT NULL,
				  `attribute` varchar(255) NOT NULL,
				  `documentation` text,
				  `destination` varchar(1024)
				) ENGINE=InnoDB DEFAULT CHARSET=latin1";
$stmeta = $dbmeta->prepare($create_query);
if (not(defined $stmeta->execute())) {
	error("Table $cmw_table doesn't exist and could not be created, " . $stmeta->errstr);
	exit_application(1);
}

# Empty table cmw_fys_table_attr
$empty_query = "TRUNCATE TABLE $cmw_table";
$stmeta = $dbmeta->prepare($empty_query);
if (not (defined $stmeta->execute())) {
	error("Could not truncate table $cmw_table, " . $stmeta->errstr);
}

# Prepare insert statement for cmdbmeta table
$insquery = "INSERT INTO $cmw_table (tablename, attribute) values (?, ?)";
$stmeta = $dbmeta->prepare($insquery);
# Select all CMW Table attributes 
$query = "SELECT table_name, column_name FROM columns WHERE table_schema = 'cmdb'";
$sth = $dbh->prepare($query);
if (not(defined $sth->execute())) {
	error($sth->errstr);
	exit_application(1);
}
# Add tablenames to cmw_fys_table_info
while (my $ref = $sth->fetchrow_hashref()) {
	my $table_name = $ref->{table_name};
	my $column_name = $ref->{column_name};
	if (not(defined $stmeta->execute($table_name, $column_name))) {
		error("Could not add $table_name, $column_name to $cmw_table");
	}
	$attribute_count++;
}

exit_application(0);

=head1 To Do

=over 4

=item *

Allow to specify database name and table name as input variables.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
