=head1 NAME

resFileTypeNumber - Results of File Type Analysis (Number)

=head1 VERSION HISTORY

version 1.0 05 May 2009 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will create the results from the File Type analysis (size).

=head1 SYNOPSIS

 resFileTypeNumber.pl [-t] [-l log_dir]

 resFileTypeNumber -h			Usage
 resFileTypeNumber -h 1		Usage and description of the options
 resFileTypeNumber -h 2		All documentation

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

my ($logdir, $dbres, $tabledir, $imgdir, $nf, @table_arr);
my $resulttable = "FileTypeNumber";
my $bgcolor = "lightyellow";
my $limit = 20;

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

# Create csv file from result table
# Open csv result file
my $openres = open(XL, ">$tabledir/$resulttable.csv");
if (not defined $openres) {
	error("Could not open csv file $tabledir/$resulttable.csv for writing, exiting...");
	exit_application(1);
}
print XL "Date ID; Server; Drive; FileType; Files; Size Used (MB); Size Allocated (MB)\n";
my $query = "SELECT dateid, server, drive, filetype, files, sizeused, sizealloc FROM $resulttable";
logging($query);
my $sth = $dbres->prepare($query);
my $rv = $sth->execute();
if (not(defined $rv)) {
	error("Could not execute query $query, Error: ".$sth->errstr);
	exit_application(1);
}
while (my $ref = $sth->fetchrow_hashref) {
	my $dateid = $ref->{dateid};
	my $server = $ref->{server};
	my $drive = $ref->{drive};
	my $filetype = $ref->{filetype};
	my $files = $ref->{files};
	my $sizeused = $ref->{sizeused};
	my $sizealloc = $ref->{sizealloc};
	print XL "'$dateid, $server, $drive, $filetype, $files, $sizeused, $sizealloc\n";
}
$sth->finish();
# Close csv result file
close XL;

# Overall largest file type by size
# Open html totals file
$openres = open(HTML, ">$tabledir/totals.html");
if (not defined $openres) {
	error("Could not open totals file $tabledir/totals.html for writing, exiting...");
	exit_application(1);
}
print HTML "<h1>$resulttable Totals</h1>\n";
print HTML "<table bgcolor='$bgcolor' border cellpadding=2>\n";
print HTML "<tr><th>Filetype<th>Files<th>Size Used (MB)<th>Size Allocated (MB)</tr>\n";
$query = "SELECT filetype, sum(files) as totalfiles, sum(sizeused) as totalsizeused, sum(sizealloc) as totalsizealloc FROM $resulttable GROUP BY filetype ORDER BY totalfiles DESC LIMIT $limit";
logging($query);
$sth = $dbres->prepare($query);
$rv = $sth->execute();
if (not(defined $rv)) {
	error("Could not execute query $query, Error: ".$sth->errstr);
	exit_application(1);
}
while (my $ref = $sth->fetchrow_hashref) {
	my $filetype = $ref->{filetype};
	my $files = $ref->{totalfiles};
	my $sizeused = $ref->{totalsizeused};
	my $sizealloc = $ref->{totalsizealloc};
	# Format numbers
	my $files_f = $nf->format_number($files,0,0);
	my $sizeused_f = $nf->format_number($sizeused,2,2);
	my $sizealloc_f = $nf->format_number($sizealloc,2,2);
	print HTML "<tr><td align='right'>$filetype<td align='right'>$files_f<td align='right'>$sizeused_f<td align='right'>$sizealloc_f</tr>\n";
}
print HTML "</table><p>\n";
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
print HTML "<table bgcolor='$bgcolor' border cellpadding=2>\n";
print HTML "<tr><th>Filetype<th>Files<th>Size Used (MB)<th>Size Allocated (MB)</tr>\n";
$query = "SELECT filetype, sum(files) as totalfiles, sum(sizeused) as totalsizeused, sum(sizealloc) as totalsizealloc FROM $resulttable WHERE server = '$server' AND drive = '$drive' GROUP BY filetype ORDER BY totalfiles DESC LIMIT $limit";
logging($query);
$sth = $dbres->prepare($query);
$rv = $sth->execute();
if (not(defined $rv)) {
	error("Could not execute query $query, Error: ".$sth->errstr);
	exit_application(1);
}
while (my $ref = $sth->fetchrow_hashref) {
	my $filetype = $ref->{filetype};
	my $files = $ref->{totalfiles};
	my $sizeused = $ref->{totalsizeused};
	my $sizealloc = $ref->{totalsizealloc};
	# Format numbers
	my $files_f = $nf->format_number($files,0,0);
	my $sizeused_f = $nf->format_number($sizeused,2,2);
	my $sizealloc_f = $nf->format_number($sizealloc,2,2);
	print HTML "<tr><td align='right'>$filetype<td align='right'>$files_f<td align='right'>$sizeused_f<td align='right'>$sizealloc_f</tr>\n";
}
print HTML "</table><p>\n";
$sth->finish();
close HTML;
}

# Now print index page
$openres = open(IND, ">$tabledir/index.html");
if (not defined $openres) {
	error("Could not open $tabledir/index.html for writing, exiting...");
	exit_application(1);
}
print IND "<h1>$resulttable</h1>\n";
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
