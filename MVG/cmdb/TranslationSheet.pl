=head1 NAME

TranslationSheet - Loads the data from the translation sheet

=head1 VERSION HISTORY

version 1.0 25 May 2008 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will load the information from the translation sheet. The workbook Translations.xls is the master source for all translation information for now. MySQL allows to work with the data in an efficient way. In a later version, when the 'combination interface' is ready, MySQL should become the master.

The application is build to connect to a MySQL database server. DBI modules have been used, so conversion to another type of database server shouldn't be difficult.

=head1 SYNOPSIS

 TranslationSheet.pl [-t] [-l log_dir]

 TranslationSheet -h	   Usage
 TranslationSheet -h 1	   Usage and description of the options
 TranslationSheet -h 2	   All documentation

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

my ($logdir, $dbmeta, $report, $reportbook);
my $username = "root";
my $password = "Monitor1";
my $server = "localhost";
my $cmdbmetaDB = "cmdbmeta";
my $printerror = 0;
my $reportname = "d:/Projects/MVG/CMDB/Translations.xls";	# Your Excel Workbook

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

my $cmw_table = "translations";
# Create table if not exists
my $create_query = "CREATE TABLE IF NOT EXISTS $cmw_table (
  					`prottable` varchar(255),
  					`protattr` varchar(255),
  					`cmwtable` varchar(255),
  					`cmwattr` varchar(255),
  					`logtable` varchar(255),
  					`remark` text
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
my $insquery = "INSERT INTO $cmw_table (cmwtable, logtable) values (?, ?)";
$stmeta = $dbmeta->prepare($insquery);

# Walk through tab "LogFysTableName"
# Read from row 1 until empty space
# First column is the logical table name
# Second column is the physical table name

my $sheet = $reportbook->Worksheets("LogFysTableName");		# Worksheet name
my $row = 1;
while (defined $sheet->Cells($row, 1)->{'Value'}) {
	my $logtable = $sheet->Cells($row, 1)->{'Value'};
	# No error checking is done on empty values for physical table name.
	my $cmwtable = $sheet->Cells($row, 2)->{'Value'};
	# Add tablename and documentation to cmw_log_table_info
	# ToDo: add quote for documentation!
	if (not(defined $stmeta->execute($cmwtable, $logtable))) {
		error("Could not add $cmwtable - $logtable to $cmw_table, $stmeta->errstr");
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
