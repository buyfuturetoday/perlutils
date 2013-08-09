=head1 NAME

loadShareData2Table - Load File Share data to table

=head1 VERSION HISTORY

version 1.1  4 April 2009 DV

=over 4

=item *

Update to handle files with object name server, drive and directory

=item *

Add to table if it exists already, don't refuse to upload

=back

version 1.0 25 March 2009 DV

=over 4

=item *

Initial release, based on loadFileData

=back

=head1 DESCRIPTION

This application will read file data from a storage management application file and load the data into a mysql database table. This will allow to query the file data for analyzing file types, file age, last access, ... This will help the business case for HSM and archiving.

The application will create a separate table per fileserver share. The advantage is that table sizes remain manageable and file share data can be added as it comes available, the disadvantage is that queries need to concatenate the data from different tables.

=head1 SYNOPSIS

 loadShareData2Table.pl [-t] [-l log_dir] -f filedata.txt

 loadShareData2Table -h	 	   Usage
 loadShareData2Table -h 1	   Usage and description of the options
 loadShareData2Table -h 2	   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-f filedata.txt>

File containing all filedata in predefined format: separator is tab, fields are FileName,Path,SizeUsedMB,AllocatedMB,Created,Modified,Accessed,CreatedDays,ModifiedDays,AccessedDays,FileType. Some parametrization may be done in a later version of the application.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.8.0, build 804 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir,$dbh, $dbm, $filedata,$fieldstring,$reccnt,$printcnt, $multicnt, $nr_of_fields, $fileserver, $drive, $tablename);
my $masterdatabase="information_schema";
my $expectedfieldstring = "FileName,Path,SizeUsedMB,AllocatedMB,Created,Modified,Accessed,CreatedDays,ModifiedDays,AccessedDays,FileType";
my $unicode = "UCS-2BE";
my $multimax = 1000;
my $emptynumberflag = 0;

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
use Encode qw(encode decode);	# Convert from Unicode
use MySQLModules;

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if ($emptynumberflag == 1) {
		error("Empty numbers replaced by 999999 for $tablename");
	}
	if (defined $dbh) {
		$dbh->disconnect;
	}
	if (defined $dbm) {
		$dbm->disconnect;
	}
	close Filedata;
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
getopts("tl:h:f:", \%options) or pod2usage(-verbose => 0);
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
# Find Filedata to get
if ($options{"f"}) {
	$filedata = $options{"f"};
} else {
	error("No filedata file defined, exiting...");
	exit_application(1);
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Make database connection for filedata database
my $connectionstring = "DBI:mysql:database=$databasename;host=$server;port=$port";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

# Make database connection for MySQL master database
$connectionstring = "DBI:mysql:database=$masterdatabase;host=$server;port=$port";
$dbm = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbm) {
   	error("Could not open $masterdatabase, exiting...");
   	exit_application(1);
}

# Check if filedata file is readable
if (not(-r $filedata)) {
	error("Cannot access filedata file $filedata for reading, exiting...");
	exit_application(1);
}

# Open filedata file for reading
my $openres = open(Filedata, $filedata);
if (not(defined $openres)) {
	error("Couldn't open $filedata for reading, exiting...");
	exit_application(1);
}

# First find Object Name (Server and Drive)
my $delim = "\"Object Name:\"";
my $delim1 = "\"Objecting ..\"";
while (my $line = decode($unicode, <Filedata>)) {
	chomp $line;
	# Try to find line delimiter
	if ((substr($line,0,length($delim)) eq $delim) ||
		(substr($line,0,length($delim1)) eq $delim1)) {
		print "OK, found the Object name $line\n";
		my(undef,$serverdrive) = split /\t/,$line;
		$serverdrive=trim($serverdrive);
		# Now remove "'\\ at start and '" at and of label
		$serverdrive=substr($serverdrive,4,-2);
		($fileserver,$drive) = split /\\/,$serverdrive;
		# Make sure Drive is one character only
		$drive = substr($drive,0,1);
		last;
	}
}

# Define tablename
$tablename = "$fileserver"."_$drive";

# Check if the table exists already
my $query = "SELECT table_name FROM tables WHERE table_schema = '$databasename' AND table_name = '$tablename'";
my $sth = $dbm->prepare($query);
my $rv = $sth->execute();
if (not(defined $rv)) {
	error("Could not execute query $query, Error: ".$sth->errstr);
	exit_application(1);
}
if (my $ref = $sth->fetchrow_hashref) {
	$sth->finish;
	logging("Table $tablename exists already, rows will be added.");
} else {
	logging("Table $tablename will be created.");
	# Create Table
	$query = "CREATE TABLE $tablename 
			( `FileName` varchar(1024) default NULL,
			  `Path` varchar(1024) default NULL,
			  `SizeUsedMB` float default NULL,
			  `AllocatedMB` float default NULL,
			  `Created` datetime default NULL,
			  `Modified` datetime default NULL,
			  `Accessed` datetime default NULL,
			  `CreatedDays` int(11) default NULL,
			  `ModifiedDays` int(11) default NULL,
			  `AccessedDays` int(11) default NULL,
			  `FileType` varchar(256) default NULL,
			  `Server` varchar(256) default NULL,
			  `Drive` varchar(256) default NULL
			) ENGINE=MyISAM DEFAULT CHARSET=latin1;";
	$rv = $dbh->do($query);
	if (defined $rv) {
	    logging("Table $tablename created");
	} else {
	    error("Could not create table $tablename. Error: ".$dbh->errstr."\nQuery: $query");
    	exit_application(1);
    }
}

$delim = "\"FileName\"";
my $cnt;
# Scan through file until Field title line is found
while (my $line = decode($unicode, <Filedata>)) {
	chomp $line;
	# Try to find line delimiter
	if (substr($line,0,length($delim)) eq $delim) {
		print "OK, found the delimiter $delim\n";
		# Check if expected fieldnames show up
		print "\n$line\n";
		my @fields = split /\t/,$line;
		$nr_of_fields = @fields;
		foreach my $field (@fields) {
			# Remove blanks and strip quotes
			$field = substr(trim($field),1,-1);
			$fieldstring .= "$field,";
		}
		# Now remove last ,
		$fieldstring = substr($fieldstring,0,-1);
		if ($fieldstring eq $expectedfieldstring) {
			# Jump out of while loop
			print "OK, start line found!\n";
			last;
			} else {
			# Not the expected field string
			error("Not the expected field string ***$fieldstring*** (expected ***$expectedfieldstring***), exiting...");
			exit_application(1);
			}
	}
}

# Read one line before reading actual file content
my $line = decode($unicode,<Filedata>);

# Now handle each record
$reccnt = 0;
$printcnt = 0;
my $multivalue = "";
my $columncount = -1;
while (my $line = decode($unicode, <Filedata>)) {
	if ($printcnt > 999) {
		my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
		my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;		
		print "$datetime - $tablename * Handling record $reccnt\n";
		$printcnt = 0;
	}
	chomp $line;
	my @fields = split /\t/,$line;
	my $fieldcount = @fields;
	if (not($fieldcount == $nr_of_fields)) {
		error("$tablename - Invalid columncount for $line");
		# Jump out of this loop, take next record
		next;
	}
	$reccnt++;
	$printcnt++;
	$multicnt++;
	my $fieldvalues = "";
	foreach my $field (@fields) {
		# Remove blanks
		$field = trim($field);
		# Remove quote if available
		if (substr($field,0,1) eq "\"") {
			$field = substr($field,1,-1);
			# Check if field has date value
			# and change format to MySQL format
			if (index($field,"/") > 0) {
				my($datefield,$timefield) = split / /,$field;
				my($dd,$mm,$yy) = split /\//,$datefield;
				$field=sprintf("%04d-%02d-%02d %s",$yy,$mm,$dd,$timefield);
			}
		} else {
			# Field is number, so remove . (thousand separator) if available,
			$field=~s/\.//g;
			# then replace decimal symbol , with dot.
			$field=~s/,/./;
			# If no value available, then add 999999 and print error message
			if (length($field) == 0) {
				$field = 999999;
				$emptynumberflag = 1;
			}
		}
		# Now quote special characters
		$field = $dbh->quote($field);
		$fieldvalues .= "$field,";
	}
	# Now add server and drive
	$fieldvalues = "$fieldvalues'$fileserver','$drive'";
	# Create multivalue string
	$multivalue .= "($fieldvalues),";
	# Create SQL insert string only if multimax is reached
	if ($multicnt > $multimax) {
		# Remove last comma
		$multivalue = substr($multivalue,0,-1);
		my $sql = "INSERT INTO $tablename values $multivalue";
    	my $rows_affected = $dbh->do($sql);
    	if (not defined $rows_affected) {
			error("PID: $$ - SQL Error with *** $sql, error: ".$dbh->errstr);
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
my $resultstring = "$reccnt records loaded in $tablename";
print "$resultstring\n";
logging($resultstring);

exit_application(0);

=head1 To Do

=over 4

=item *

Split up server name and path

=item *

Add fielddata labels as variables.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
