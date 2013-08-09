=head1 NAME

resFileAge - Results of File Age Analysis

=head1 VERSION HISTORY

version 1.0 05 May 2009 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will create the results from the File Age analysis.

=head1 SYNOPSIS

 resFileAge.pl [-t] [-l log_dir]

 resFileAge -h			Usage
 resFileAge -h 1		Usage and description of the options
 resFileAge -h 2		All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP, Perl v5.8.8, build 804 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $dbres, $tabledir, $imgdir, $nf, @val_array, @table_arr);
my @label_names = ('-1 - 3',
				   '3 - 7',
				   '7 - 90',
				   '90 - 180',
				   '180 - 365',
				   '> 365');
my @wherevariables = ('createddays',
					  'modifieddays',
					  'accesseddays');
my $resulttable = "FileAge";
my $bgcolor = "lightyellow";

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
use Number::Format;
use GD::Graph::pie;

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if (defined $dbres) {
		$dbres->disconnect;
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

sub create_chart {
	my ($category, $tablename, $wherevariable) = @_;
	my @data = (\@label_names,\@val_array);
	my $mygraph = GD::Graph::pie->new(300,300);
	my $graphsetres = $mygraph->set(title       => "$category",
#									label		=> "Server: $server - Drive: $drive",
									start_angle => 180,
									'3d'		=> 1);
	if (not defined $graphsetres) {
	    error("Could not set Graph for $category $tablename $wherevariable");
	} else {
		$mygraph->set_title_font('arial',12) or error("Could not set font for title");
		$mygraph->set_value_font('arial',10) or error("Could not set font for values");
	    my $myimage = $mygraph->plot(\@data);
		if (not defined $myimage) {
			error("Could not create image for $tablename $category ($wherevariable)");
			error($mygraph->error);
		}
	    # Open Output file
		my $imgfilename = "$category"."_$tablename"."_$wherevariable"."_$category.png";
   		my $outfile = "$imgdir/$imgfilename";
    	my $openres = open(OutFile, ">$outfile");
    	if (not defined $openres) {
			error("Cannot open $outfile for writing, exiting...");
    	} else {
			binmode OutFile;
			print OutFile $myimage->png;
			close OutFile;
    	}
		print HTML "<img src=img/$imgfilename>\n";
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
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Define Number format
$nf = new Number::Format(THOUSANDS_SEP => '.',
						 DECIMAL_POINT => ',');

# Set Font Path for GD
GD::Text->font_path("c:/windows/fonts");

# Make database connection to results database
my $connectionstring = "DBI:mysql:database=$resultdb;host=$server;port=$port";
$dbres = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbres) {
   	error("Could not open database $resultdb, exiting...");
   	exit_application(1);
}

# Create Result Directories if they don't exist already
# Customer Directory
if (not(-d $resultdir)) {
	my $mkdirres = mkdir($resultdir);
	if (not $mkdirres) {
		error("Could not create subdirectory $resultdir, errorno: $!");
		exit_application(1);
	}
}
# Result table Main Directory
$tabledir = "$resultdir/$resulttable";
if (not(-d $tabledir)) {
	my $mkdirres = mkdir($tabledir);
	if (not $mkdirres) {
		error("Could not create subdirectory $tabledir, errorno: $!");
		exit_application(1);
	}
}
# Result table Images Directory
$imgdir = "$resultdir/$resulttable/img";
if (not(-d $imgdir)) {
	my $mkdirres = mkdir($imgdir);
	if (not $mkdirres) {
		error("Could not create subdirectory $imgdir, errorno: $!");
		exit_application(1);
	}
}

# Create csv file from result table
# Open csv result file
my $openres = open(XL, ">$tabledir/$resulttable.csv");
if (not defined $openres) {
	error("Could not open csv file $tabledir/$resulttable.csv for writing, exiting...");
	exit_application(1);
}
print XL "ReportDate;Server;Drive;Period;Lifecycle;Files;Size Used (MB);Size Alloc (MB)\n";
my $query = "SELECT dateid, server, drive, period, lifecycle, files, sizeused, sizealloc FROM $resulttable";
logging($query);
my $sth = $dbres->prepare($query);
my $rv = $sth->execute();
if (not(defined $rv)) {
	error("Could not execute query $query, Error: ".$sth->errstr);
	exit_application(1);
}
while (my $ref = $sth->fetchrow_hashref) {
	my $dateid = $ref->{dateid} || 0;
	my $server = $ref->{server} || "UnknownServer";
	my $drive = $ref->{drive} || "UnknownDrive";
	my $period = $ref->{period} || 0;
	my $lifecycle = $ref->{lifecycle} || "UnknownLifecycle";
	my $files = $ref->{files};
	my $sizeused = $ref->{sizeused};
	my $sizealloc = $ref->{sizealloc};
	print XL "'$dateid;$server;$drive;'$period;$lifecycle;$files;$sizeused;$sizealloc\n";
}
$sth->finish();
# Close csv result file
close XL;

# Calculate Totals for the different lifecycles
# Open html totals file
$openres = open(HTML, ">$tabledir/totals.html");
if (not defined $openres) {
	error("Could not open totals file $tabledir/totals.html for writing, exiting...");
	exit_application(1);
}
print HTML "<h1>$resulttable Totals</h1>\n";
foreach my $wherevariable (@wherevariables) {
	my (@files_array, @sizeused_array, @sizealloc_array);
	print HTML "<h2>$wherevariable</h2>\n";
	print HTML "<table bgcolor='$bgcolor' border cellpadding=2>\n";
	print HTML "<tr><th>Interval<th>Total Files<th>Size Used (MB)<th>Size Allocated (MB)</tr>\n";
	foreach my $period (@label_names) {
		$query = "SELECT sum(files) as totalfiles, sum(sizeused) as totalsizeused, sum(sizealloc) as totalsizealloc FROM $resulttable WHERE lifecycle = '$wherevariable' AND period = '$period' GROUP BY period ASC";
	logging($query);
	my $sth = $dbres->prepare($query);
	my $rv = $sth->execute();
	if (not(defined $rv)) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		my $totalfiles = $ref->{totalfiles};
		my $totalsizeused = $ref->{totalsizeused};
		my $totalsizealloc = $ref->{totalsizealloc};
		# Format numbers
		my $totalfiles_f = $nf->format_number($totalfiles,0,0);
		my $totalsizeused_f = $nf->format_number($totalsizeused,2,2);
		my $totalsizealloc_f = $nf->format_number($totalsizealloc,2,2);
		print HTML "<tr><td align='right'>$period<td align='right'>$totalfiles_f<td align='right'>$totalsizeused_f<td align='right'>$totalsizealloc_f</tr>\n";
		# Add to array for charts
		push @files_array, $totalfiles;
		push @sizeused_array, $totalsizeused;
		push @sizealloc_array, $totalsizealloc;
	} else {
		error("No totals record for period $period, investigate!");
	}
	}
	print HTML "</table><p>\n";
	@val_array = @files_array;
	create_chart("Total_Files", "Totals", $wherevariable);
	@val_array = @sizeused_array;
	create_chart("Size_Used", "Totals", $wherevariable);
	@val_array = @sizealloc_array;
	create_chart("Size_Allocated", "Totals", $wherevariable);
}

$sth->finish();
close HTML;

# Calculate per server and drive for the different lifecycles
@table_arr = get_all_tables();
foreach my $tablename (@table_arr) {
	my ($server, $drive) = split /_/,$tablename;

	# Open html file
	$openres = open(HTML, ">$tabledir/$tablename.html");
	if (not defined $openres) {
		error("Could not open  file $tabledir/$tablename.html for writing, exiting...");
		exit_application(1);
	}
	print HTML "<h1>$resulttable Server $server Drive $drive</h1>\n";
	foreach my $wherevariable (@wherevariables) {
		my (@files_array, @sizeused_array, @sizealloc_array);
		print HTML "<h2>$wherevariable</h2>\n";
		print HTML "<table bgcolor='$bgcolor' border cellpadding=2>\n";
		print HTML "<tr><th>Interval<th>Total Files<th>Size Used (MB)<th>Size Allocated (MB)</tr>\n";
		foreach my $period (@label_names) {
		$query = "SELECT period, files, sizeused, sizealloc FROM $resulttable WHERE lifecycle = '$wherevariable' AND period = '$period' AND server = '$server' AND drive = '$drive'";
		logging($query);
		my $sth = $dbres->prepare($query);
		my $rv = $sth->execute();
		if (not(defined $rv)) {
			error("Could not execute query $query, Error: ".$sth->errstr);
			exit_application(1);
		}
		if (my $ref = $sth->fetchrow_hashref) {
			my $files = $ref->{files};
			my $sizeused = $ref->{sizeused};
			my $sizealloc = $ref->{sizealloc};
			# Format numbers
			my $files_f = $nf->format_number($files,0,0);
			my $sizeused_f = $nf->format_number($sizeused,2,2);
			my $sizealloc_f = $nf->format_number($sizealloc,2,2);
			print HTML "<tr><td align='right'>$period<td align='right'>$files_f<td align='right'>$sizeused_f<td align='right'>$sizealloc_f</tr>\n";
			# Add to array for charts
			push @files_array, $files;
			push @sizeused_array, $sizeused;
			push @sizealloc_array, $sizealloc;
		} else {
			error("No record for table $tablename and period $period, investigate!");
		}
		}
		print HTML "</table><p>\n";
		@val_array = @files_array;
		create_chart("Total_Files", $tablename, $wherevariable);
		@val_array = @sizeused_array;
		create_chart("Size_Used", $tablename, $wherevariable);
		@val_array = @sizealloc_array;
		create_chart("Size_Allocated", $tablename, $wherevariable);
	}
	$sth->finish();
	close HTML;
}

# Now print index page
$openres = open(IND, ">$tabledir/index.html");
if (not defined $openres) {
	error("Could not open $tabledir/index.html for writing, exiting...");
	exit_application(1);
}
print IND "<h1>File Age</h1>\n";
print IND "<a href=$resulttable.csv>Download Result file (csv Format)</a>\n";
print IND "<ul>\n";
print IND "<li><a href=totals.html>Totals</a>\n";
@table_arr = sort @table_arr;
foreach my $tablename (@table_arr) {
	my ($server, $drive) = split /_/, $tablename;
	print IND "<li><a href=$tablename.html>$server - $drive</a>\n";
}
print IND "</ul>\n";
close IND;

exit_application(0);

=head1 To Do

=over 4

=item *

Nothing documented for now...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
