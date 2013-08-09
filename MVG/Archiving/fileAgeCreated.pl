=head1 NAME

fileAgeCreated - File Age by Created Date

=head1 VERSION HISTORY

version 1.0 25 March 2009 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will create a report with the file age by Created Date.

=head1 SYNOPSIS

 fileAgeCreated.pl [-t] [-l log_dir] [-a]

 fileAgeCreated -h	 	   Usage
 fileAgeCreated -h 1	   Usage and description of the options
 fileAgeCreated -h 2	   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-a>

If set, then run script over all tables. Otherwise, use defined tablearray.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP, Perl v5.8.8, build 804 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir,$dbh,%outline, %htmltable, %tot_files, %size_used, %alloc_size, @labels, $subtitle,$nf, $outline_totals);
my $resultdir = "d:/temp/vo_archief";
my $htmldir = "d:/temp/vo_archief/html";
my @daysint_arr = (3,7,90,180,365);
my @label_names = ('0 - 3 days',
				   '3 days - 1 week',
				   '8 - 90 days',
				   '3 to 6 months',
				   '6 months - 1 year',
				   'Over 1 Year');
my @selectvariables = ('totalfiles',
					   'sizeused',
					   'allocsize');
my @wherevariables = ('createddays',
					  'modifieddays',
					  'accesseddays');
my ($dayslow, $daysupp);
# my @table_arr=('bru000center44m_o','bru000center84m_k','nos030mercur19m_m');
my @table_arr=('bru000center84m_k');
my $alltablesflag = "No";
my $bgcolor = "lightyellow";

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
# Disable strict 'refs' for @$tablename variables
# use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use DBI();
use Log;
use GD::Graph::pie;
# use GD::Text;
use Number::Format;
use MySQLModules;

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if (defined $dbh) {
		$dbh->disconnect;
	}
	close RES;
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

=head2 Handle Query

Run the query for every table in the database or for a single table (to do). Summarize results in hash.

=cut

sub handle_query($$$$) {
	my ($tablename,$whereclause,$printlabel,$wherevariable) = @_;
	my ($server, $drive) = split/_/,$tablename;
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
	print "$datetime - Handling query $printlabel ($wherevariable) for $server, drive $drive\n";
	my $query = "SELECT count(*) as totalfiles, sum(sizeusedmb) as sizeused, sum(allocatedmb) as allocsize from $tablename where $whereclause";
	logging($query);
	my $sth = $dbh->prepare($query);
	my $rv = $sth->execute();
	if (not(defined $rv)) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		my $totalfiles = $ref->{totalfiles} || 0;
		my $sizeused = $ref->{sizeused} || 0;
		my $allocsize = $ref->{allocsize} || 0;
		# Send output to csv outputfile
		$outline{$tablename} .= sprintf (";$totalfiles;%.2f;%.2f",$sizeused,$allocsize);
		# Format numbers
		my $totalfiles_f = $nf->format_number($totalfiles,0,0);
		my $sizeused_f = $nf->format_number($sizeused,2,2);
		my $allocsize_f = $nf->format_number($allocsize,2,2);
		$htmltable{$tablename} .= "<td align='right'>$totalfiles_f<td align='right'>$sizeused_f<td align='right'>$allocsize_f";
		# Add to array for pie chart
		foreach my $varname (@selectvariables) {
			# For Server / Shares
			my $arrayname = $tablename . "-" . $wherevariable . "-" . $varname;
			my $value = "\$".$varname;
			push @$arrayname, eval($value);
			# Summarize Totals per selectperiod (printlabel), selectvariable (totalfiles, sizeused, allocsize)
			# and wherevariable (createddays, modifieddays, accesseddays).
			my $tothashname = "totals-$wherevariable-$varname-hash";
			$$tothashname{$printlabel} += eval($value);
		}
	} else {
		error("Query $query did not return any rows!");
	}
	$sth->finish();
}

=pod

=head2 Create Result

This procedure will create a result file per table name (server and drive). A html page will be created with a table overview of the results, and pie charts as available.

=cut

sub create_html($) {
	my ($tablename) = @_;
	my $resfile = "$htmldir/$tablename.html";
	my $openres = open(HTML, ">$resfile");
	if (not defined $openres) {
		error("Could not open $resfile for writing!");
		return;
	}
	if ($tablename eq "totals") {
		print HTML "<h1>Overview Totals</h1>\n";
	} else {
		my ($server,$drive) = split /_/,$tablename;
		print HTML "<h1>Server ".uc($server)." Drive ".uc($drive)."</h1>\n";
	}
	print HTML $htmltable{$tablename};
	foreach my $wherevariable (@wherevariables) {
		print HTML "<h2>$wherevariable</h2>\n";
		foreach my $varname (@selectvariables) {
			my $imgname = $tablename . "-" . $wherevariable . "-" . $varname . ".png";
			print HTML "<img src=$resultdir/$imgname>\n";
		}
	}
	close HTML;
}

=pod

=head2 Create Piechart

This procedure will get a tablename (server - drive) and plot a pie chart for each variable in the select variable array. First the subtitle will be set, then the length of the data array is checked and then the pie chart is plotted.

=cut

sub create_piechart($) {
	my ($tablename) = @_;
	# my ($server, $drive) = split /_/, $tablename;
	foreach my $wherevariable (@wherevariables) {
		foreach my $varname (@selectvariables)  {
			# Set Subtitle
			if ($varname eq "totalfiles") {
				$subtitle = "Total Files";
			} else {
				if ($varname eq "sizeused") {
					$subtitle = "Size Used";
				} else {
					if ($varname eq "allocsize") {
						$subtitle = "Size Allocated";
					}
				}
			}
			# Check for correct length array
			my $xlength = @label_names;
			my $arrayname = $tablename . "-" . $wherevariable . "-" . $varname;
			my $ylength = @$arrayname;
    		if (not ($xlength == $ylength)) {
				error ("X-array and Y-array not same length, cannot make piechart for $tablename.");
		    } else {
				# Plot pie chart
				my @data = (\@label_names,\@$arrayname);
				my $mygraph = GD::Graph::pie->new(300, 300);
				my $graphsetres = $mygraph->set(title       => "File Age - $subtitle",
#												label		=> "Server: $server - Drive: $drive",
												start_angle => 180,
												'3d'		=> 1);
				if (not defined $graphsetres) {
				    error("Could not set Graph for $tablename");
				} else {
					$mygraph->set_title_font('arial',12) or error("Could not set font for title");
					$mygraph->set_value_font('arial',10) or error("Could not set font for values");
#					$mygraph->set_label_font('arial',18) or error("Could not set font for label");
				    my $myimage = $mygraph->plot(\@data);
					if (not defined $myimage) {
						error("Could not create image for $tablename, $varname");
						error($mygraph->error);
					}
				    # Open Output file
		    		my $outfile = $resultdir."/$arrayname.png";
			    	my $openres = open(OutFile, ">$outfile");
			    	if (not defined $openres) {
						error("Cannot open $outfile for writing, exiting...");
			    	} else {
						binmode OutFile;
						print OutFile $myimage->png;
						close OutFile;
			    	}	
				}
    		}
		}
	}
}

=pod

=head2 Convert Totals Data

This procedure will convert the totals that are available in a hash to arrays that can be handled by the pie chart procedure. A csv output line will be generated.

=cut

sub convert_totals_data() {
	my $tablename = "totals";
	# Prepare html table line
	$htmltable{$tablename} = "<table bgcolor='$bgcolor' border cellpadding=2>\n";
	$htmltable{$tablename} .= "<tr><th><th colspan=3>Created<th colspan=3>Modified<th colspan=3>Accessed</tr>\n";
	$htmltable{$tablename} .= "<tr><th>Interval<th>Total Files<th>Size Used (MB)<th>Size Allocated (MB)<th>Total Files<th>Size Used (MB)<th>Size Allocated (MB)<th>Total Files<th>Size Used (MB)<th>Size Allocated (MB)</tr>\n";
	# Handle interval data first
	$dayslow = -1;
	foreach $daysupp (@daysint_arr) {
		my $label = "$dayslow - $daysupp";
		format_totals($tablename,$label);
		$dayslow = $daysupp;
	}
	# Final query for upperlimit only
	my $label = "> $dayslow";
	format_totals($tablename,$label);
	# Close html table
	$htmltable{$tablename} .= "</table>\n";
	create_html($tablename);
	create_piechart($tablename);
}

=pod

=head2 Format Totals

This procedure is called from the Convert Totals Data subroutine, and will convert a single line of data.

=cut

sub format_totals($$) {
	my ($tablename, $label) = @_;
	# Prepare html output file
	$htmltable{$tablename} .= "<tr><td>$label";
	# Prepare csv output line for totals
	$outline_totals .= ";;'$label'";
	foreach my $wherevariable (@wherevariables) {
		foreach my $varname (@selectvariables) {
			my $arrayname = $tablename . "-" . $wherevariable . "-" . $varname;
			my $hashname = "$arrayname-hash";
			# Add values to array for pie chart
			push @$arrayname, $$hashname{$label};
			# html report - nice number format
			my ($value_f, $value_csv);
			if ($varname eq "totalfiles") {
				$value_f = $nf->format_number($$hashname{$label},0,0);
				$value_csv = $$hashname{$label};
			} else {
				$value_f = $nf->format_number($$hashname{$label},2,2);
				$value_csv = sprintf("%.2f",$$hashname{$label});
			}
			$htmltable{$tablename} .= "<td align='right'>".$value_f;
			$outline_totals .= ";$value_csv";
		}
	}
	# Close html line
	$htmltable{$tablename} .= "</tr>\n";
	# Close csv output line
	$outline_totals .= "\n";
}

######
# Main
######

# Handle input values
my %options;
getopts("tl:h:a", \%options) or pod2usage(-verbose => 0);
# The Filename must be specified
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
if (defined $options{"a"}) {
	$alltablesflag = "Yes";
}
# End handle input values

# Define Number format
$nf = new Number::Format(THOUSANDS_SEP => '.',
						 DECIMAL_POINT => ',');
# Set Font Path for GD
GD::Text->font_path("c:/windows/fonts");

if ($alltablesflag eq "Yes") {
	@table_arr = get_all_tables();
	if (scalar @table_arr == 1) {
		exit_application(1);
	}
}

# Make database connection
my $connectionstring = "DBI:mysql:database=$databasename;host=$server;port=$port";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

# Handle all tables
foreach my $tablename (@table_arr) {
	my ($server, $drive) = split /_/, $tablename;
	# Prepare html table
	$htmltable{$tablename} = "<table bgcolor='$bgcolor' border cellpadding=2>\n";
	$htmltable{$tablename} .= "<tr><th><th colspan=3>Created<th colspan=3>Modified<th colspan=3>Accessed</tr>\n";
	$htmltable{$tablename} .= "<tr><th>Interval<th>Total Files<th>Size Used (MB)<th>Size Allocated (MB)<th>Total Files<th>Size Used (MB)<th>Size Allocated (MB)<th>Total Files<th>Size Used (MB)<th>Size Allocated (MB)</tr>\n";
	# Handle each interval per table
	$dayslow = -1;
	foreach $daysupp (@daysint_arr) {
		my $label = "$dayslow - $daysupp";
		# Prepare html table line
		$htmltable{$tablename} .= "<tr><td>$label";
		# Prepare csv output line for server and drive
		$outline{$tablename} .= "$server;$drive;'$label'";
		foreach my $wherevariable (@wherevariables) {
			my $whereclause = "$wherevariable > $dayslow and $wherevariable <= $daysupp";
			handle_query($tablename,$whereclause,$label,$wherevariable);
		}
		# Close html line
		$htmltable{$tablename} .= "</tr>\n";
		# Close csv output line
		$outline{$tablename} .= "\n";
		# Prepare dayslow for next foreach run
		$dayslow = $daysupp;
	}
	# Final query for upperlimit only
	my $label = "> $dayslow";
	$htmltable{$tablename} .= "<tr><td>$label";
	# Prepare csv output line for server and drive
	$outline{$tablename} .= "$server;$drive;'$label'";
	foreach my $wherevariable (@wherevariables) {
		my $whereclause = "$wherevariable > $dayslow";
		handle_query($tablename,$whereclause,$label,$wherevariable);
	}
	# Close csv output line
	$outline{$tablename} .= "\n";
	# Close html line
	$htmltable{$tablename} .= "</tr>\n";
	# Close html table
	$htmltable{$tablename} .= "</table>\n";
	create_html($tablename);
	create_piechart($tablename);
}

# Create html and piechart for totals
convert_totals_data();


# Write data to file
my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my $filename = sprintf "fileAgeCreated.csv", $year+1900, $mon+1, $mday, $hour,$min,$sec;
my $openres = open(RES, ">$resultdir/$filename");
if (not defined $openres) {
	error("Could not open $resultdir/$filename for writing, exiting...");
	exit_application(1);
}

print RES ";;;Created;;;Modified;;;Accessed\n";
print RES "Server;Drive;Interval;# Files;Size Used(MB);Size Allocated (MB);# Files;Size Used(MB);Size Allocated (MB);# Files;Size Used(MB);Size Allocated (MB)\n";
# Server based output
while (my($table,$res) = each %outline) {
	print RES $res;
}

print RES ";;;Created;;;Modified;;;Accessed\n";
print RES "Server;Drive;Interval;# Files;Size Used(MB);Size Allocated (MB);# Files;Size Used(MB);Size Allocated (MB);# Files;Size Used(MB);Size Allocated (MB)\n";
# Totals output
print RES $outline_totals;

exit_application(0);

=head1 To Do

=over 4

=item *

Split up server name and path

=item *

Allow for output file directory and file name flexibility.

=item *

Allow to read timeint_arr from configuration file.

=item *

Allow to run query for every table in database or for single table (parametername).

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
