=head1 NAME

resFileGrowth - Results of File Growth Analysis

=head1 VERSION HISTORY

version 1.0 05 May 2009 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will create the results from the File Growth analysis.

=head1 SYNOPSIS

 resFileGrowth.pl [-t] [-l log_dir]

 resFileGrowth -h		Usage
 resFileGrowth -h 1		Usage and description of the options
 resFileGrowth -h 2		All documentation

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

my ($logdir, $dbres, $tabledir, $imgdir, $nf, @label_array, @val1_array, @val2_array, @table_arr);
my @wherevariables = ('created',
					  'modified',
					  'accessed');
my $resulttable = "FileGrowth";
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
use GD::Graph::lines;

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
	my @data = (\@label_array,\@val1_array,\@val2_array);
	my $mygraph = GD::Graph::lines->new(300,300);
	my $graphsetres = $mygraph->set(title       => "$category");
#									label		=> "Server: $server - Drive: $drive");
	if (not defined $graphsetres) {
	    error("Could not set Graph for $category");
	} else {
		$mygraph->set_title_font('arial',12) or error("Could not set font for title");
#		$mygraph->set_x_axis_font('arial',10) or error("Could not set font for title");
#		$mygraph->set_y_axis_font('arial',10) or error("Could not set font for title");
	    my $myimage = $mygraph->plot(\@data);
		if (not defined $myimage) {
			error("Could not create image for $tablename $category ($wherevariable)");
			error($mygraph->error);
		}
	    # Open Output file
		my $imgfilename = "$tablename"."_$wherevariable"."_$category.png";
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
	print XL "'$dateid;$server;$drive;$period;$lifecycle;$files;$sizeused;$sizealloc\n";
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
	my (@labels, @filesperyear, @sizeperyear, @arr_cumfiles, @arr_cumsize, $cumfiles, $cumsize);
	print HTML "<h2>$wherevariable</h2>\n";
	print HTML "<table bgcolor='$bgcolor' border cellpadding=2>\n";
	print HTML "<tr><th>Interval<th>Total Files<th>Size Used (MB)<th>Size Allocated (MB)</tr>\n";
	$query = "SELECT period, sum(files) as totalfiles, sum(sizeused) as totalsizeused, sum(sizealloc) as totalsizealloc FROM $resulttable WHERE lifecycle = '$wherevariable' AND period < 2009 GROUP BY period ASC";
	logging($query);
	my $sth = $dbres->prepare($query);
	my $rv = $sth->execute();
	if (not(defined $rv)) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	while (my $ref = $sth->fetchrow_hashref) {
		my $period = $ref->{period} || $triggerint;
		my $totalfiles = $ref->{totalfiles} || $triggerint;
		my $totalsizeused = $ref->{totalsizeused} || $triggerint;
		my $totalsizealloc = $ref->{totalsizealloc} || $triggerint;
		# Format numbers
		my $totalfiles_f = $nf->format_number($totalfiles,0,0);
		my $totalsizeused_f = $nf->format_number($totalsizeused,2,2);
		my $totalsizealloc_f = $nf->format_number($totalsizealloc,2,2);
		print HTML "<tr><td align='right'>$period<td align='right'>$totalfiles_f<td align='right'>$totalsizeused_f<td align='right'>$totalsizealloc_f</tr>\n";
		# Add to array for charts
		push @labels, $period;
		push @filesperyear, $totalfiles;
		push @sizeperyear, $totalsizeused;
		$cumfiles += $totalfiles;
		push @arr_cumfiles, $cumfiles;
		$cumsize += $totalsizeused;
		push @arr_cumsize,$cumsize;
	}
	print HTML "</table><p>\n";
	@label_array = @labels;
	@val1_array = @filesperyear;
	@val2_array = @arr_cumfiles;
	create_chart("Total_Files", "Totals", $wherevariable);
	@val1_array = @sizeperyear;
	@val2_array = @arr_cumsize;
	create_chart("Size_Used", "Totals", $wherevariable);
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
		my (@labels, @filesperyear, @sizeperyear, @arr_cumfiles, @arr_cumsize, $cumfiles, $cumsize);
		print HTML "<h2>$wherevariable</h2>\n";
		print HTML "<table bgcolor='$bgcolor' border cellpadding=2>\n";
		print HTML "<tr><th>Interval<th>Total Files<th>Size Used (MB)<th>Size Allocated (MB)</tr>\n";
		$query = "SELECT period, files, sizeused, sizealloc FROM $resulttable WHERE lifecycle = '$wherevariable' AND period < 2009 AND server = '$server' AND drive = '$drive' GROUP BY period ASC";
		logging($query);
		my $sth = $dbres->prepare($query);
		my $rv = $sth->execute();
		if (not(defined $rv)) {
			error("Could not execute query $query, Error: ".$sth->errstr);
			exit_application(1);
		}
		while (my $ref = $sth->fetchrow_hashref) {
			my $period = $ref->{period};
			my $files = $ref->{files};
			my $sizeused = $ref->{sizeused};
			my $sizealloc = $ref->{sizealloc};
			# Format numbers
			my $files_f = $nf->format_number($files,0,0);
			my $sizeused_f = $nf->format_number($sizeused,2,2);
			my $sizealloc_f = $nf->format_number($sizealloc,2,2);
			print HTML "<tr><td align='right'>$period<td align='right'>$files_f<td align='right'>$sizeused_f<td align='right'>$sizealloc_f</tr>\n";
			# Add to array for charts
			push @labels, $period;
			push @filesperyear, $files;
			push @sizeperyear, $sizeused;
			$cumfiles += $files;
			push @arr_cumfiles, $cumfiles;
			$cumsize += $sizeused;
			push @arr_cumsize,$cumsize;
		}
		print HTML "</table><p>\n";
		my $linecnt = @labels;
		# Only produce graphs when there is real output
		if ($linecnt > 0) {
			@label_array = @labels;
			@val1_array = @filesperyear;
			@val2_array = @arr_cumfiles;
			create_chart("Total_Files", $tablename, $wherevariable);
			@val1_array = @sizeperyear;
			@val2_array = @arr_cumsize;
			create_chart("Size_Used", $tablename, $wherevariable);
		}
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
print IND "<h1>File Growth</h1>\n";
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
