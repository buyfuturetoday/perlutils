=head1 NAME

getStorageVolumes - Collect Storage Volume information for Customer

=head1 VERSION HISTORY

version 1.0 14 October 2009 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will get the StorageVolume Information. First search for all boxes for the customer, then find raid groups on these boxes. For the configured raid groups find the raid group fragments. Then search for the volume associated with raid group. 

For each volume, the relevant information is extracted from the volume and disk tables. For some volumes there is no corresponding record in t_disk. The assumption is that these volumes are no longer assigned to a system, and are available for other usages.

=head1 SYNOPSIS

 getStorageVolume.pl [-t] [-l log_dir] 

 getStorageVolume -h	   Usage
 getStorageVolume -h 1	   Usage and description of the options
 getStorageVolume -h 2	   All documentation

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

my ($logdir, $dbhsource, $dbhtarget, @boxes, @raidgroups, %volumes);
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

=head2 Add to StorageVolume

This procedure will add the storage volume information to the DWH StorageVolume table.

=cut

sub add2storagevolume {
	my($vol,$kb_free,$kb_log,$kb_ovh,$kb_raw,$wwlunid,$servergroup,$box,$rgtype) = @_;
	my ($kb_free_string,$kb_ovh_string);
	if ($kb_free == -1) {
		$kb_free_string = "NULL";
	} else {
		$kb_free_string = "'$kb_free'";
	}
	if ($kb_ovh == -1) {
		$kb_ovh_string = "NULL";
	} else {
		$kb_ovh_string = "'$kb_ovh'";
	}
	my $query = "INSERT INTO storagevolume (vol,kb_free,kb_log,kb_ovh,kb_raw,wwlunid,servergroup,box,rgtype) 
				 VALUES ('$vol',$kb_free_string,'$kb_log',$kb_ovh_string,'$kb_raw','$wwlunid','$servergroup','$box','$rgtype')";
	my $rows_affected = $dbhtarget->do($query);
	if (not defined $rows_affected) {
		error("Insert failed, query $query. Error: ".$dbhtarget->errstr);
	} elsif (not $rows_affected == 1) {
		error("$rows_affected rows updated ($query), 1 expected");
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

# Make database connection to target database
$connectionstring = "DBI:mysql:database=$dbtarget;host=$server;port=$port";
$dbhtarget = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbhtarget) {
   	error("Could not open $dbtarget, exiting...");
   	exit_application(1);
}

# Get all Clariion SAN boxes at Vo
# Do not collect info for other box types (Centera, VLT, ...) since they require
# a different logical (UML) model
my $query = "SELECT box FROM t_box WHERE sts='prod' AND scope='eib' AND boxtype='clariion'";
my $sth = $dbhsource->prepare($query);
my $rv = $sth->execute();
if (not(defined $rv)) {
	error("Could not execute query $query, Error: ".$sth->errstr);
	exit_application(1);
}
while (my $ref = $sth->fetchrow_hashref) {
	my $box = $ref->{box};
	push @boxes, $box;
}
$sth->finish();

# Now collect all Raidgroups per box that are from type r5 or r1_0
# Types hot_spare or unbound are not raidgroup fragments that are availalbe
# for Storage Volumes.
foreach my $box (@boxes) {
	my $query = "SELECT rg 
			     FROM t_rg WHERE box='$box' and (tp = 'r1_0' OR tp = 'r5')";
	my $sth = $dbhsource->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query. Error: ".$sth->errstr);
		exit_application(1);
	}
	while (my $ref = $sth->fetchrow_hashref) {
		my $rg = $ref->{rg};
		push @raidgroups, $rg;
	}
}
$sth->finish();

# Now collect volume identifier for all Raidgroup fragments per Raid Group
foreach my $rg (@raidgroups) {
	my $query = "SELECT vol
				 FROM t_rgfrag WHERE rg='$rg'";	
	my $sth = $dbhsource->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query. Error: ".$sth->errstr);
		exit_application(1);
	}
	while (my $ref = $sth->fetchrow_hashref) {
		my $vol = $ref->{vol};
		$volumes{$vol} = 1;
	}
}
$sth->finish();

# Now for each identified volume collect the volume information
while (my ($vol,undef) = each %volumes) {
	my($kb_log,$kb_raw,$wwlunid,$kb_free,$kb_ovh,$box,$tp);
	my $subg = "";
	my $serverg = "";
	# Get info from volume table
	my $query = "SELECT vol.kb_log AS kb_log, vol.kb_raw AS kb_raw, vol.wwlunid AS wwlunid, rgfrag.box AS box, rg.tp AS tp
				 FROM t_vol AS vol, t_rgfrag AS rgfrag, t_rg AS rg
				 WHERE vol.vol = '$vol'
				 AND rgfrag.vol = vol.vol
				 AND rgfrag.rg = rg.rg";
	my $sth = $dbhsource->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query. Error: ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		$kb_log = $ref->{kb_log};
		$kb_raw = $ref->{kb_raw};
		$wwlunid = $ref->{wwlunid};
		$box = $ref->{box};
		$tp = $ref->{tp};
	} else {
		error("No volume info found for $vol in t_vol");
		next;
	}
	$sth->finish();
	# Get some more info from disk table
	$query = "SELECT kb_free, kb_ovh, serverg FROM t_disk
				 WHERE disk='$vol'";
	$sth = $dbhsource->prepare($query);
	$rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query. Error: ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		$kb_free = $ref->{kb_free};
		$kb_ovh = $ref->{kb_ovh};
		$serverg = $ref->{serverg};
	} else {
		error("No volume info found for $vol in t_disk");
		$kb_free = -1;
		$kb_ovh = -1;
	}
	$sth->finish();
	add2storagevolume($vol,$kb_free,$kb_log,$kb_ovh,$kb_raw,$wwlunid,$serverg,$box,$tp);
}

exit_application(0);

=head1 To Do

=over 4

=item *

Nothing documented for now...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
