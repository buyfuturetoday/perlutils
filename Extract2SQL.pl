=head1 NAME

Extract2SQL - Extract data from tables and create SQL statements for insertion into another database

=head1 VERSION HISTORY

version 1.0 28 May 2003 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application reads all data in a specified table in a database and convert the data into SQL insert statements. This allows to convert tables from one SQL database to another SQL database.

The SQL statements that are created are from the form C<INSERT INTO TABLE (columnX, columnY, ...) VALUES (valueX, valueY, ...)>. The column names are added because the order of the value fields is not determined. Also for I<NULL> values, no column/value pair is created.

The insert statements are grouped per 100. This means that a "GO" statement is issued per 100 insert records. This should give a good balance between speed and reliability.

The application will only convert the data, it will not (yet?) attempt to provide the SQL commands to create the table.

=head1 SYNOPSIS

Extract2SQL.pl [-t] [-l log_dir] [-d DSN_string] -T table [-o outputfile.sql] [-D Database]

    Extract2SQL -h	    Usage
    Extract2SQL -h 1	    Usage and description of the options
    Extract2SQL -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\opex\log

=item B<-d DSN_string>

DSN string that allows the ODBC connection to the database. Default B<DSN=OPEX;UID=sa;PWD=>

=item B<-T table>

Table name for which the data must be extracted.

=item B<-o outputfile>

Outputfile, containing all the SQL statements to insert the data. Default B<c:\temp\I<table>.sql>

=item B<-D Database>

If provided, then the "use Database\Go" statements are included as the first lines in the outputfile. This is for user convenience only.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.8.0, build 804 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my $logdir;
my $dbase = "DSN=OPEX;UID=sa;PWD="; # ODBC Connection name to OPEX database
my ($dbconn, $table, $sqlfile, $database);
my $cnt=0;

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use Log;			    # Application and error logging
use Win32::ODBC;		    # Allow ODBC Connection to database

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
    if (defined($dbconn)) {
	$dbconn->Close();
	trace("Close database connection");
    }
    close SQLFILE;
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

=head2 SQL query

Accepts a database handle and a query, executes the request and make the data available for processing.

=cut

sub SQLquery($$) {
  my($db, $query) = @_;
  trace("$db, $query");
  if ($db->Sql($query)) {
    my ($errnum, $errtext, $errconn) = $db->Error();
    error("SQL Error: $errnum $errtext $errconn");
    exit_application(1);
  }
}

######
# Main
######

# Handle input values
my %options;
getopts("tl:d:T:o:D:h:", \%options) or pod2usage(-verbose => 0);
# At least the table name must be specified.
my $arglength = scalar keys %options;  
if ($arglength == 0) {			# If no options specified,
   $options{"h"} = 0;			# display usage.
}
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
    $logdir = logdir("d:\\opex\\log");
    if (not(defined $logdir)) {
	error("Could not set d:\\opex\\log as Log directory, exiting...");
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
# Find DSN Connection string
if ($options{"d"}) {
    $dbase = $options{"d"};
}
# Find table name
if ($options{"T"}) {
    $table = $options{"T"};
} else {
    error("Table name not specified, exiting...");
    exit_application(1);
}
# Find output file name
if ($options{"o"}) {
    $sqlfile = $options{"o"};
} else {
    $sqlfile = "c:/temp/$table.sql";
}
# Find Database name
if ($options{"D"}) {
    $database = $options{"D"};
} else {
    undef $database;
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Create Database Connection
undef $dbconn;		    # Undef $dbconn for proper exit_application
if (not($dbconn = new Win32::ODBC($dbase))) {
    error("DSN string: $dbase");
    error("Open failed: ".Win32::ODBC::Error());
    exit_application(1);
}

# Open the sql file for output
my $open_res = open(SQLFILE, ">$sqlfile");
if (not(defined $open_res)) {
    error("Could not open $sqlfile for output, exiting...");
    exit_application(1);
}
# Add use statement if required
if (defined $database) {
    print SQLFILE "use $database\nGO\n";
}

# Process all data in the table
my $sqlquery = "SELECT * FROM $table";
SQLquery($dbconn, $sqlquery);
while ($dbconn->FetchRow()) {
    my %record =$dbconn->DataHash();
    my $columnstring = "";
    my $valuestring = "";
    while (my($column, $value) = each %record) {
	if (defined $value) {
	    if (length($columnstring) == 0) {
		$columnstring = $column;
		$valuestring  = "\'$value\'";
	    } else {
		$columnstring = $columnstring . ", $column";
		$valuestring  = $valuestring  . ", \'$value\'";
	    }
	}
    }
    print SQLFILE "INSERT INTO $table ($columnstring)\n       VALUES ($valuestring)\n";
    $cnt++;
    if ($cnt > 100) {
	print SQLFILE "GO\n";
	$cnt = 0;
    }
}
print SQLFILE "GO\n";

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Nothing for the moment...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
