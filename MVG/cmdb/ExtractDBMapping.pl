=head1 NAME

ExtractDBMapping - Extract DB Mapping information (tab CMDB DB Mapping)

=head1 VERSION HISTORY

version 1.0 25 May 2008 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will read tab "CMDB DB Mapping" from the workbook "CMDB mapping tabel v0.09.xls", extracts and translates all information. Translation to physical table names will be done at the same time, since there are a number of unknown or irrelevant table names in the sheet.

Last rows (676-682) are ignored thanks to the blank on row 675.

The application is build to connect to a MySQL database server. DBI modules have been used, so conversion to another type of database server shouldn't be difficult.

=head1 SYNOPSIS

 ExtractDBMapping.pl [-t] [-l log_dir]

 ExtractDBMapping -h	   Usage
 ExtractDBMapping -h 1	   Usage and description of the options
 ExtractDBMapping -h 2	   All documentation

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

my ($logdir, $dbmeta, $report, $reportbook, %translate, %not_found, %combine);
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

# Collect translation information first
my $query = "SELECT cmwtable, logtable FROM translations WHERE
			 cmwtable IS NOT NULL and logtable IS NOT NULL
			 AND prottable IS NULL AND protattr IS NULL and cmwattr IS NULL";
my $stmeta = $dbmeta->prepare($query);
if (not(defined $stmeta->execute())) {
	error("Could not query translations table, $stmeta->errstr");
	exit_application(1);
}
while (my $ref = $stmeta->fetchrow_hashref()) {
	my $cmwtable = $ref->{cmwtable};
	my $logtable = $ref->{logtable};
	$translate{$logtable} = $cmwtable;
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

# Now add info to existing cmw_fys_table_attr
my $cmw_table = "cmw_fys_table_attr";

# Walk through tab "Tabel beschrijving"
# Read from row 3 until empty space
# Column 2 is the logical data name
# Column 3 is the attribute
# Column 6 and 7 make up the documentation
my $sheet = $reportbook->Worksheets("CMDB DB Mapping");		# Worksheet name
my $row = 3;
while (defined $sheet->Cells($row, 2)->{'Value'}) {
	my $logtable = $sheet->Cells($row, 2)->{'Value'};
	# Manual check has been done, attribute names are always available in relevant situations
	my $attribute = $sheet->Cells($row, 3)->{'Value'};
	# Check if Logical table translates to physical table
	if (exists $translate{$logtable}) {
		# Check if combination is unique, or has it been handled before?
		if (defined $combine{"$logtable$attribute"}) {
			error ("Combination $logtable $attribute occurs more than once");
		} else {
			$combine{"$logtable$attribute"} = 1;
			my $cmwtable = $translate{$logtable};
			my $documentation = "";
			if (defined $sheet->Cells($row, 6)->{'Value'}) {
				$documentation = $sheet->Cells($row, 6)->{'Value'};
			}
			if (defined $sheet->Cells($row, 7)->{'Value'}) {
				$documentation = $documentation."\n".$sheet->Cells($row, 7)->{'Value'};
			}
			# Add documentation to cmw_fys_table_attr
			my $insquery = sprintf "UPDATE $cmw_table SET documentation = %s 
		    			            WHERE tablename = '$cmwtable' AND attribute = '$attribute'", $dbmeta->quote($documentation);
			$stmeta = $dbmeta->prepare($insquery);
			my $queryres = $stmeta->execute();
			if (not(defined $stmeta->execute())) {
				error ("Could not update table $cmwtable, attribute $attribute, ".$stmeta->errstr);
			} elsif (not $queryres == 1) {
				error("Table $cmwtable, attribute $attribute occurs $queryres times");
			}
		}
	} else {
		if (not exists $not_found{$logtable}) {
			error("No table name translation for $logtable");
			$not_found{$logtable} = 1;
		}
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
