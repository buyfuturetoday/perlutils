=head1 NAME

dump2mysql - Load Database dump file into MySQL database.

=head1 VERSION HISTORY

version 1.1 1 July 2009 DV

=over 4

=item *

NULL text expected for NULL values. Change 'null' field values into null (without quotes) values, to guarantee that no string is inserted into the table.

=item *

Remove subst_quotes procedure since in-line procedure is in place now.

=back

version 1.0 2 April 2008 DV

=over 4

=item *

Initial release, based on cmw2db(2).pl.

=back

=head1 DESCRIPTION

This application will read a database dumpfile, like the ones created from Oracle DWH table and import each row into the corresponding MySQL table. The MySQL table must exist already. The file will be handled in batches of 50 records (variable in the script) to speed up processing.

The pipe symbol is used as field delimiter. Quotes and double quotes will be removed from the lines. The "Include NULL text" option must be enabled while downloading the data.

=head1 SYNOPSIS

 dump2mysql.pl [-t] [-l log_dir] -f dumpfile.txt [-n tablename]

 dump2mysql -h	 	   Usage
 dump2mysql -h 1	   Usage and description of the options
 dump2mysql -h 2	   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-f dumpfile.txt>

The (path to and) filename containing the dump information.

=item B<-n tablename>

Not yet implemented. If specified, then this is the tablename. Otherwise, the filename of the dumpfile will be used as tablename.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.8.0, build 804 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir,$dbh,$filepath,$tablename,$printcnt, $multicnt);
my $databasename="storage";
my $server="localhost";
my $username="root";
my $password="Monitor1";
my $printerror=0;
my $multimax=100;
my $reccnt=0;

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
use File::Basename;

#############
# subroutines
#############

sub exit_application($) {
	logging("$reccnt records loaded in $tablename");
    my ($return_code) = @_;
	if (defined $dbh) {
		$dbh->disconnect;
	}
	close Dump;
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
getopts("tl:f:n:h:", \%options) or pod2usage(-verbose => 0);
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
# Find URL to get
if ($options{"f"}) {
    $filepath = $options{"f"};
	# Verify that the dump file is readable.
	if (not(-r $filepath)) {
    	error("Cannot access Dump file $filepath for reading, exiting...");
    	exit_application(1);
	}
} else {
    error("Dumpfile not defined, exiting...");
    exit_application(1);
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Extract filename to use as tablename
($tablename, undef) = split(/\./, basename($filepath));

# Open Dump file for reading
my $openres = open(Dump, $filepath);
if (not(defined $openres)) {
	error("Couldn't open $filepath for reading, exiting...");
	exit_application(1);
}

# Make database connection
my $connectionstring = "DBI:mysql:database=$databasename;host=$server";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

# Now handle each record
$reccnt = 0;
$printcnt = 0;
my $multivalue = "";
my $columncount = -1;
while (my $line = <Dump>) {
	$reccnt++;
	$printcnt++;
	$multicnt++;
	if ($printcnt > 999) {
		my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
		my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;		
		print "$datetime - $tablename * Handling record $reccnt\n";
		$printcnt = 0;
	}
	chomp $line;
	# Add end-of-line identifier, to force empty fields up to the end
	$line .= "END";
	# Substitute backward slash with forward slash
	my $slashpos = index($line,"\\");
	while ($slashpos > -1) {
		substr($line, $slashpos, 1, "/");
		$slashpos = index($line,"\\");
	}
	# Substitute comma with dot
	my $commapos = index($line,",");
	while ($commapos > -1) {
		substr($line, $commapos, 1, ".");
		$commapos = index($line, ",");
	}
	# Remove double quotes from line
	my $quotpos = index($line, "\"");
	while ($quotpos > -1) {
		substr($line,$quotpos,1,"");
		$quotpos = index($line, "\"");
	}
	# Also remove single quotes from line
	$quotpos = index($line, "'");
	while ($quotpos > -1) {
		substr($line,$quotpos,1,"");
		$quotpos = index($line, "'");
	}
	my(@fields) = split /\|/,$line;
	if ($columncount < 0) {
		# On first pass, set column count equal to number of fields
		$columncount = @fields;
	} else {
		my $currentcolumns = @fields;
		if (not($currentcolumns == $columncount)) {
			error("$tablename - Invalid columncount for $line");
			# Jump out of this loop, take next record
			next;
		}
	}
	my $valuestring = join("','",@fields);
	# Remove END identifier from end of line
	$valuestring = substr($valuestring,0,length($valuestring)-3);
	# Add start and stop single quotes
	$valuestring = "'".$valuestring."'";
	# Remove quotes from null
	my $nullstring = "'null'";
	my $nullpos = index($valuestring, $nullstring);
	while ($nullpos > -1) {
		substr($valuestring,$nullpos,length($nullstring),"null");
		$nullpos = index($valuestring, $nullstring);
	}
	# Create $multivalue string
	$multivalue .= "($valuestring),";
	# Create SQL insert string only if multimax is reached
	if ($multicnt > $multimax) {
		# Remove last comma
		$multivalue = substr($multivalue,0,-1);
		my $sql = "INSERT INTO $tablename values $multivalue";
    	my $rows_affected = $dbh->do($sql);
    	if (not defined $rows_affected) {
			error("PID: $$ - SQL Error with *** $sql");
			exit_application(1);
		}
		$multivalue = "";
		$multicnt = 0;
    }
}
# Load last bunch of records
if (length($multivalue) > 0) {
	# Remove last comma
	$multivalue = substr($multivalue,0,-1);
	my $sql = "INSERT INTO $tablename values $multivalue";
    my $rows_affected = $dbh->do($sql);
    if (not defined $rows_affected) {
		error("PID: $$ - SQL Error with *** $sql");
		exit_application(1);
	}
}
print "$reccnt records loaded in $tablename\n";
		
exit_application(0);

=head1 To Do

=over 4

=item *

Implement functionality to accept tablename.

=item *

Allow to have other delimiter instead of pipe symbol.

=item *

Use database->quote instead of current formatting options

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
