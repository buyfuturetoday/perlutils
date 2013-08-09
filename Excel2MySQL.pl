=head1 NAME

Excel2MySQL - Excel Worksheet to MySQL conversion

=head1 VERSION HISTORY

version 1.0 20 October 2010 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will convert an excel worksheet into a MySQL table. 

It will drop the table and create a table using first row elements as fields. All other rows will be added to the table.

The excel data must be in a continuous area (row_min-row_max, col_min-col_max).
When the table is loaded, then another command will ensure that all duplicate records are removed from the table.

Note that this application requires .xls files, not the newer .xlsx format!

=head1 SYNOPSIS

 Excel2MySQL.pl [-t] [-l log_dir] -m tablename [-w worksheet] -e excelfile [-d]

 Excel2MySQL -h		Usage
 Excel2MySQL -h 1   Usage and description of the options
 Excel2MySQL -h 2   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-m tablename>

MySQL Table name to be created. The table will be dropped if it exists already.

=item B<-w worksheet>

MySQL Worksheet name. If omitted then the first worksheet will be used (index 0).

=item B<-e excelfile>

MySQL Excel Workbook, needs to be readable.

=item B<-d>

If specified, then duplicates will not be removed from the table.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP, Perl v5.10.0, build 1005 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $dbh, $table, $excel, $sheetname, $worksheet, $temp_table, $duplicates);
my $rowcnt = 0;
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
use dbParamsALU;
use Spreadsheet::ParseExcel;

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if (defined $dbh) {
		$dbh->disconnect;
	}
	my $msg = "$rowcnt records inserted into table $table";
	print $msg."\n";
	logging($msg);
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

=head2 Create Table Procedure

This procedure will read the first line of the excel sheet. It will 

=cut

sub create_table($$$$$) {
	my ($dbh, $worksheet, $row_min, $col_min, $col_max) = @_;

	my $createstring = "CREATE TEMPORARY TABLE IF NOT EXISTS $temp_table (";
	# Read the fields
	for my $col ($col_min .. $col_max) {
		my $cell = $worksheet->get_cell($row_min, $col);
		my $unformatted = trim($cell->unformatted());
		# Remove spaces from label names
		# so working with the database doesn't require ` delimiters
		$unformatted =~ s/ //g;
		my $addfield = "\n  `$unformatted` varchar(50) default NULL,";
		# Add field to current create string
		$createstring .= $addfield;
	}
	# Remove last character (comma) from create string
	$createstring = substr($createstring, 0, -1);
	# Add closing lines
	$createstring .= "\n) ENGINE=MyISAM DEFAULT CHARSET=latin1;";
	# And create table
	my $rv = $dbh->do($createstring);
	if (not defined $rv) {
		error("Could not create temporary table $temp_table\n$createstring\n".$dbh->errstr);
		exit_application(1);
	}
}

######
# Main
######

# Handle input values
my %options;
getopts("tl:h:adn:m:w:e:", \%options) or pod2usage(-verbose => 0);
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
# Get tablename
if ($options{"m"}) {
	$table = $options{"m"};
} else {
	error("Table name not defined, exiting...");
	exit_application(1);
}
# Get excel file
if ($options{"e"}) {
	$excel = $options{"e"};
	if (not -r $excel) {
		error("Excel file $excel not readable, exiting...");
		exit_application(1);
	}
} else {
	error("Excel file not defined, exiting...");
	exit_application(1);
}
# Get worksheet name
if ($options{"w"}) {
	$sheetname = $options{"w"};
}
# Check if duplicates should not be removed
if (defined $options{"d"}) {
	$duplicates = "";
} else {
	$duplicates = "DISTINCT";
}
logging("Start application");
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Make database connection 
my $connectionstring = "DBI:mysql:database=$dbsource;host=$server;port=$port";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $dbsource, exiting...");
   	exit_application(1);
}

# Drop table if exists
my $query = "DROP TABLE IF EXISTS $table";
my $rv = $dbh->do($query);
if (not defined $rv) {
	error("Could not drop table ".$dbh->errstr);
	exit_application(1);
}

# Open Excel File
my $parser = Spreadsheet::ParseExcel->new();
my $workbook = $parser->parse($excel);
if (not defined $workbook) {
	error("Could not open $excel for reading, ".$parser->error());
	exit_application(1);
}

# Open Workbook
if (defined $sheetname) {
	$worksheet = $workbook->worksheet("$sheetname");
} else {
	$worksheet = $workbook->worksheet(0);
}
if (not defined $worksheet) {
	error("Could not access worksheet, exiting...");
	exit_application(1);
}

my ($row_min, $row_max) = $worksheet->row_range();
my ($col_min, $col_max) = $worksheet->col_range();

# Create table
$temp_table = "TEMP_$table";
create_table($dbh, $worksheet, $row_min, $col_min, $col_max);
$row_min++;

# Now handle all rows
for my $row ($row_min .. $row_max) { 
	my $insertstring = "INSERT INTO $temp_table VALUES (";
	for my $col ($col_min .. $col_max) {
		my $unformatted;
		my $cell = $worksheet->get_cell($row, $col);
		if (defined $cell) {
			$unformatted = $cell->unformatted();
		} else {
			$unformatted = "";
		}
		my $fieldvalue = $dbh->quote($unformatted);
		$insertstring .= $fieldvalue .",";
	}
	# Remove last character (comma) from insert string
	$insertstring = substr($insertstring, 0, -1);
	# Add closing characters
	$insertstring .= ");";
	# And insert line
	my $rv = $dbh->do($insertstring);
	if (not defined $rv) {
		error("Could not add record to temp table \n$insertstring\n".$dbh->errstr);
		exit_application(1);
	}
	$rowcnt++;
}

$query = "CREATE TABLE $table AS SELECT $duplicates * FROM $temp_table";
$rv = $dbh->do($query);
if (not defined $rv) {
	error("Could not create table with uniqe strings".$dbh->errstr);
	exit_application(1);
}

exit_application(0);

=head1 To Do

=over 4

=item *

Nothing documented for now...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@hp.comE<gt>
