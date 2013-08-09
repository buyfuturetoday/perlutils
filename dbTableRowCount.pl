=head1 NAME

dbTableRowCount - List table names and row counts for any given database.

=head1 VERSION HISTORY

version 1.0 1 March 2010 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application gets a database name and will list all table names and row counts for the database. The tablenames and row counts can be used to detect changes in databases while using applications, when the application is run before and  after an application update.

The script is for MySQL only since all table names are collected from the information_schema database, table 'tables'.

=head1 SYNOPSIS

 dbTableRowCount.pl [-t] [-l log_dir] -d databasename

 dbTableRowCount -h	   Usage
 dbTableRowCount -h 1   Usage and description of the options
 dbTableRowCount -h 2   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-d database>

Database name

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP, Perl v5.8.8, build 820 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $dbh, $dbc, $databasename);
my $printerror = 1;
my $outdir = "c:/temp";

# Database connection information
my $username = "admin";
my $password = "H2X9hgZP_iKa";
my $server = "ex-std-node77.prod.rhcloud.com";
my $port = 3306;


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
	if (defined $dbc) {
		$dbc->disconnect;
	}
	close DBRES;
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

sub get_reccnt($) {
	my ($table) = @_;
	my ($reccnt);
	# Prepare query
	my $query = "SELECT count(*) as reccnt FROM $table";
	my $sth = $dbc->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Error executing query, " . $sth->errstr);
		return -1;
	}
	if (my $ref = $sth->fetchrow_hashref) {
		$reccnt = $ref->{reccnt};
	}
	return $reccnt;
}

######
# Main
######

# Handle input values
my %options;
getopts("tl:h:d:", \%options) or pod2usage(-verbose => 0);
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
if ($options{"d"}) {
	$databasename = $options{"d"};
} else {
	error("Databasename not defined, exiting...");
	exit_application(1);
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Open Result file
my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my $datetime = sprintf "%04d%02d%02d%02d%02d%02d",$year+1900, $mon+1, $mday, $hour,$min,$sec;
my $resfile = "$outdir/$databasename"."_$datetime.csv";
my $openres = open(DBRES, ">$resfile");
if (not defined $openres) {
	error("Could not open $resfile for writing, exiting....");
	exit_application(1);
}
print DBRES "Table;Records\n";

# Make database connection to information schema database
my $connectionstring = "DBI:mysql:database=information_schema;host=$server;port=$port";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open database information_schema, exiting...");
   	exit_application(1);
}

# Make database connection to database
$connectionstring = "DBI:mysql:database=$databasename;host=$server;port=$port";
$dbc = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

# Get all tablenames for this database
my $query = "SELECT table_name FROM tables
					WHERE table_schema = ?
					ORDER BY table_name ASC";
my $sth = $dbh->prepare($query);
$sth->bind_param(1, $databasename);
my $rv = $sth->execute();
if (not defined $rv) {
	error("Error executing query, " . $sth->errstr);
	exit_application(1);
}

# Handle all tables
while (my $ref = $sth->fetchrow_hashref) {
	my $table = $ref->{table_name};
	my $reccnt = get_reccnt($table);
	print DBRES "$table;$reccnt\n";
}

exit_application(0);

=head1 To Do

=over 4

=item *

Nothing documented for now...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
