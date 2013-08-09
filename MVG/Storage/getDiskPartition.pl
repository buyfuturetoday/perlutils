=head1 NAME

getDiskPartition - Collect Disk Partition information associated with all Storage Volumes

=head1 VERSION HISTORY

version 1.0 27 October 2009 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will collect all Disk Partition information for the known Storage Volumes.

=head1 SYNOPSIS

 getDiskPartition.pl [-t] [-l log_dir] 

 getDiskPartition -h	   Usage
 getDiskPartition -h 1	   Usage and description of the options
 getDiskPartition -h 2	   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP, Perl v5.8.8, build 820 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $dbhsource, $dbhsource2, $dbhtarget, @volumes);
my $username = "root";
my $password = "Monitor1";
my $server = "localhost";
my $dbsource = "san";
my $dbtarget = "dwh_storage";
my $port = 3306;
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

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if (defined $dbhsource) {
		$dbhsource->disconnect;
	}
	if (defined $dbhtarget) {
		$dbhtarget->disconnect;
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

=pod

=head2 Add to LogicalDisk

This procedure will add the logical disk information to the DWH Logical Disk table.

The assumption is that the disk partition name is unique. However it may happen that in the process of migrating servers, the storage is temporarily available on more than one servergroup. It is obvious that in this case only one servergroup can control the storage. 

The volume (disk) and the disk partition (part) will then occur more than once in the t_part table. Check in the t_disk table which servergroup has control (disk is key in the t_disk table). Keep only the servergroup from t_disk for reporting purposes.

=cut

sub add2diskpartition {
	my($part,$kb_log,$servergroup,$logicaldisk,$vol) = @_;
	my $query = "INSERT INTO diskpartition (part,kb_log,servergroup,logicaldisk,vol) 
				 VALUES ('$part','$kb_log','$servergroup','$logicaldisk','$vol')";
	my $rows_affected = $dbhtarget->do($query);
	if (not defined $rows_affected) {
		# Check if duplicate entry, might be storage migration issue
		if ($dbhtarget->err == 1062) {
			checkServergroup($part,$kb_log,$servergroup,$logicaldisk,$vol);
		} else {
			error("Insert failed, query $query. Error: (".$dbhtarget->err.") ".$dbhtarget->errstr);
		}
	} elsif (not $rows_affected == 1) {
		error("$rows_affected rows updated ($query), 1 expected");
	}
}

=pod

=head2 Check Servergroup Procedure

This procedure is called when a duplicate partition is found in the diskpartition table. The t_disk table is checked to verify which should be the master servergroup for the partition and the volume.

=cut

sub checkServergroup {
	my($part,$kb_log,$servergroup,$logicaldisk,$vol) = @_;
	my $reccnt = 0;
	my $query = "SELECT count(*) as reccnt FROM t_disk
				 WHERE disk='$vol' AND serverg='$servergroup'";
	my $sth = $dbhsource2->prepare($query);
	my $rv = $sth->execute();
	if (not(defined $rv)) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		$reccnt = $ref->{reccnt};
	}
	if ($reccnt > 0) {
		logging("$servergroup - $vol - $part found in t_disk, updating table diskpartition");
		$query = "UPDATE diskpartition SET kb_log='$kb_log',servergroup='$servergroup',
				                           logicaldisk='$logicaldisk',vol='$vol' 
				  WHERE part='$part'";
		my $rows_affected = $dbhtarget->do($query);
		if (not defined $rows_affected) {
			error("Insert failed, query $query. Error: (".$dbhtarget->err.") ".$dbhtarget->errstr);
		} elsif (not $rows_affected == 1) {
			error("$rows_affected rows updated ($query), 1 expected");
		}
	} else {
		logging("$servergroup - $vol - $part not found in t_disk, keep data in diskpartition");
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

# Make database connection to source database
my $connectionstring = "DBI:mysql:database=$dbsource;host=$server;port=$port";
$dbhsource = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbhsource) {
   	error("Could not open $dbsource, exiting...");
   	exit_application(1);
}

# Make second database connection to source database
$dbhsource2 = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbhsource2) {
   	error("Could not open $dbsource, exiting...");
   	exit_application(1);
}

# Make database connection to target database
$connectionstring = "DBI:mysql:database=$dbtarget;host=$server;port=$port";
$dbhtarget = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbhtarget) {
   	error("Could not open $dbtarget, exiting...");
   	exit_application(1);
}

# Get all StorageVolumes (vol is primary key, so distinct() is not required).
my $query = "SELECT vol FROM storagevolume";
my $sth = $dbhtarget->prepare($query);
my $rv = $sth->execute();
if (not(defined $rv)) {
	error("Could not execute query $query, Error: ".$sth->errstr);
	exit_application(1);
}
while (my $ref = $sth->fetchrow_hashref) {
	my $vol = $ref->{vol};
	push @volumes, $vol;
}
$sth->finish();

# For each Storage Volume, get the partition information in table t_part
foreach my $vol (@volumes) {
	my $query = "SELECT part, subg, kb, serverg FROM t_part WHERE disk='$vol'";
	my $sth = $dbhsource->prepare($query);
	my $rv = $sth->execute();
	if (not(defined $rv)) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	while (my $ref = $sth->fetchrow_hashref) {
		my $part = $ref->{part};
		my $kb = $ref->{kb};
		my $subg = $ref->{subg} || "";
		my $serverg = $ref->{serverg};
		add2diskpartition($part,$kb,$serverg,$subg,$vol);
	}
	$sth->finish();
}

exit_application(0);

=head1 To Do

=over 4

=item *

Nothing documented for now...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
