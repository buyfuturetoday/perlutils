=head1 NAME

ExtractCmwSheet - Extract information from CMW (Logical) Datamodel spreadsheet.

=head1 VERSION HISTORY

version 1.0 25 May 2008 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will read different tabs from the master spreadsheet "CMDB Mapping Table v0.09" and import the data into MySQL cmdbmetaDB for merging with other sources of information.

The application is build to connect to a MySQL database server. DBI modules have been used, so conversion to another type of database server shouldn't be difficult.

=head1 SYNOPSIS

 ExtractCmwSheet.pl [-t] [-l log_dir]

 ExtractCmwSheet -h	   Usage
 ExtractCmwSheet -h 1	   Usage and description of the options
 ExtractCmwSheet -h 2	   All documentation

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

my ($logdir, $dbmeta, $report, $reportbook, $table_count, $attribute_count);
my $username = "root";
my $password = "Monitor1";
my $server = "localhost";
my $cmdbmetaDB = "cmdbmeta";
my $printerror = 0;
my $reportname = "d:/Projects/MVG/CMDB/CMDB mapping tabel v0.09.xls";	# Your Excel Workbook

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
use Win32::OLE;				# Connect to Excel workbook
use Log;

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if (defined $dbmeta) {
		$dbmeta->disconnect;
	}
	if (defined $reportbook) {
		$reportbook->Close;
		undef $reportbook;
	}
	if (defined $report) {
		$report->Quit;
		undef $report;
	}
	my $status_msg = "$table_count table records";
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

# Make database connection to cmdbMetaData database
my $connectionstring = "DBI:mysql:database=$cmdbmetaDB;host=$server";
$dbmeta = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbmeta) {
   	error("Could not open $cmdbmetaDB, exiting...");
   	exit_application(1);
}

# Make connection to excel workbook
if (not ($report = new Win32::OLE 'Excel.Application')) {
	error("Excel Application open failed: ".Win32::OLE->LastError);
	exit_application(1);
}
$report->{WindowState} = "xlNormal";
# Open your workbook
if (!(-e $reportname)) {
	error("Excel $reportname not found, exiting...");
	exit_application(1);
}
$reportbook = $report->Workbooks->Open($reportname);

my $cmw_table = "cmw_log_table_info";
# Create cmw_log_table_info if not exists
my $create_query = "CREATE TABLE IF NOT EXISTS $cmw_table (
  					`tablename` varchar(255) NOT NULL,
  					`documentation` text
					) ENGINE=InnoDB DEFAULT CHARSET=latin1";
my $stmeta = $dbmeta->prepare($create_query);
if (not(defined $stmeta->execute())) {
	error("Table $cmw_table doesn't exist and could not be created, " . $stmeta->errstr);
	exit_application(1);
}

# Empty table (in case it did exist already)
my $empty_query = "TRUNCATE TABLE $cmw_table";
$stmeta = $dbmeta->prepare($empty_query);
if (not (defined $stmeta->execute())) {
	error("Could not truncate table $cmw_table, " . $stmeta->errstr);
}

# Prepare insert statement for cmdbmeta table
my $insquery = "INSERT INTO $cmw_table (tablename, documentation) values (?, ?)";
$stmeta = $dbmeta->prepare($insquery);

# Walk through tab "Tabel beschrijving"
# Read from row 3 until empty space
# Entiteitnaam is logical database name
# Add Entiteitbeschrijving (1) and entiteitbeschrijving (2) into one string
# Logical database name and entiteitbeschrijving will be added to table

my $sheet = $reportbook->Worksheets("Tabel beschrijving");		# Worksheet name
my $row = 3;
while (defined $sheet->Cells($row, 1)->{'Value'}) {
	my $table_name = $sheet->Cells($row, 1)->{'Value'};
	my $documentation = "";
	if (defined $sheet->Cells($row, 2)->{'Value'}) {
		$documentation = $sheet->Cells($row, 2)->{'Value'};
	}
	if (defined $sheet->Cells($row, 3)->{'Value'}) {
		$documentation = $documentation."\n".$sheet->Cells($row, 3)->{'Value'};
	}
	# Add tablename and documentation to cmw_log_table_info
	# ToDo: add quote for documentation!
	if (not(defined $stmeta->execute($table_name, $documentation))) {
		error("Could not add $table_name to cmw_fys_table_info, $stmeta->errstr");
	}
	$table_count++;
	$row++;
}

# Handle tab "Inhoud tabellen"
# The contents of this tab will be added to the table cmw_fys_table_info, 
# fields ETL and Remark.
# Read from row 3 until empty space.
# Each entry in the sheet must have a corresponding line in the table cmw_fys_table_info.

# Prepare SQL
$cmw_table = "cmw_fys_table_info";
$insquery = "UPDATE $cmw_table set description = ? , etl= ? , remark = ?
			 WHERE tablename = ?";
$stmeta = $dbmeta->prepare($insquery);

# Walk through sheet
$sheet = $reportbook->Worksheets("Inhoud tabellen");		# Worksheet name
$row = 2;
while (defined $sheet->Cells($row, 1)->{'Value'}) {
	my $table_name = $sheet->Cells($row, 1)->{'Value'};
	my $description = "";
	if (defined $sheet->Cells($row, 2)->{'Value'}) {
		$description = $sheet->Cells($row, 2)->{'Value'};
	}
	my $etl = "";
	if (defined $sheet->Cells($row, 3)->{'Value'}) {
		$etl = $sheet->Cells($row, 3)->{'Value'};
	}
	my $remark = "";
	if (defined $sheet->Cells($row, 4)->{'Value'}) {
		$remark = $sheet->Cells($row, 4)->{'Value'};
	}
	# Add info to table
	# ToDo: add quote for documentation (Cannot be done for placeholders!)
	my $queryres = $stmeta->execute($description, $etl, $remark, $table_name);
	if (not(defined $queryres)) {
		error("Could not add $etl and $remark to entry $table_name in $cmw_table, $stmeta->errstr");
	} elsif (not($queryres == 1)) {
		error("Update to $table_name in $cmw_table on $queryres lines!");
	}
	$row++;
}

exit_application(0);

=head1 To Do

=over 4

=item *

Allow to specify database name and table name as input variables.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
