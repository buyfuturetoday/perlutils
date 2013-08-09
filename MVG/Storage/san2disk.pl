=head1 NAME

san2disk - Relates SAN box to logical disk or filesystem.

=head1 VERSION HISTORY

version 1.0 2 July 2009 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will list the relation between the SAN, Raid Groups, Fragments, volumes, logical pools and filesystems.

Except for NAS, a logical pool is the filesystem. 

A NAS will further split up the logical pool in filesystems.

=head1 SYNOPSIS

 san2disk.pl [-t] [-l log_dir] 

 san2disk -h	 	   Usage
 san2disk -h 1	   Usage and description of the options
 san2disk -h 2	   All documentation

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

my ($logdir, $dbh, $dbh2, $dbh3, @boxes);
my $username = "root";
my $password = "Monitor1";
my $server = "localhost";
my $databasename = "san";
my $port = 3306;
my $printerror = 0;
my $outfile = "D:/Projects/Vo/Storage Rapportage/reports/san2disk.csv";

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
use Switch;

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if (defined $dbh) {
		$dbh->disconnect;
	}
	if (defined $dbh2) {
		$dbh2->disconnect;
	}
	if (defined $dbh3) {
		$dbh3->disconnect;
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

=head2 Get Volume

This procedure will relate the raid group fragments to volumes.

=cut

sub get_volume($$$) {
	my ($box, $rgn,$startline) = @_;
	my $query = "SELECT rgfrag, vol, capa, kb_raw, kb_log
				 FROM t_rgfrag
				 WHERE box='$box' AND rgn='$rgn'";
	my $sth = $dbh2->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	while (my $ref = $sth->fetchrow_hashref) {
		my $rgfrag = $ref->{rgfrag};
		my $vol = $ref->{vol};
		my $capa = $ref->{capa};
		my $kb_raw = $ref->{kb_raw};
		my $kb_log = $ref->{kb_log};
		my $resline = "$startline;$rgfrag;$vol;$capa;$kb_raw;$kb_log";
		get_diskinfo($vol,$resline);
	}
	$sth->finish();
}

=pod

=head2 Get DiskInfo

This procedure will link the SAN volume information to the Server Disk.

The assumption is that each SAN volume will be associated with not more than 1 server disk. An error will be reported if the SAN volume is associated with more than 1 server disk. Further investigation is then required.

Some SAN volumes have been defined, but are no longer assigned to a server disk. In theory they are available for new assignements, but available contiguous disk space may limit their usage.

=cut

sub get_diskinfo($) {
	my ($vol, $startline) = @_;
	my ($serverg, $diskg, $drv, $kb, $kb_free, $kb_ovh);
	my $resline = "";
	# First check count. The expectation is that each volume
	# will have exact 1 record in t_disk, except if the volume is
	# no longer associated with a server / logical partition.
	my $query = "SELECT count(*) as cnt FROM t_disk WHERE disk='$vol'";
	my $sth = $dbh3->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		my $cnt = $ref->{cnt};
		if ($cnt > 1) {
			# I haven't seen this error message already...
			error("Disk volume $vol has more than one logical pool record in t_disk, investigate!");
			return $resline;
		}
	}
	$sth->finish();
	$query = "SELECT serverg, diskg, drv, kb, kb_free, kb_ovh
				 FROM t_disk
				 WHERE disk='$vol'";
	$sth = $dbh3->prepare($query);
	$rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		$serverg = $ref->{serverg} || "unknown";
		$diskg = $ref->{diskg} || "unknown";
		$drv = $ref->{drv} || "unknown";
		$kb = $ref->{kb} || "unknown";
		$kb_free = $ref->{kb_free} || "unknown";
		$kb_ovh = $ref->{kb_ovh} || "unknown";
		$sth->finish();
		$resline = "$startline;$serverg;$diskg;$drv;$kb;$kb_free;$kb_ovh";
		get_partinfo($vol,$resline);
	} else {
		$serverg = "unassigend";
		$diskg   = "unassigned";
		$drv	 = "";
		$kb      = "";
		$kb_free = "";
		$kb_ovh  = "";
		$sth->finish();
		$resline = "$startline;$serverg;$diskg;$drv;$kb;$kb_free;$kb_ovh";
		print RES $resline."\n";
	}
	return;
}

=pod

=head2 Get PartInfo

This procedure will link the SAN volume information to the Logical Partition information.

The assumption is that each SAN volume will be associated with not more than 1 server disk partition. An error will be reported if the SAN volume is associated with more than 1 server disk partition. Further investigation is then required.

Some SAN volumes have been defined, but are no longer available as a logical partition. In theory they are available for new assignements, but available contiguous disk space may limit their usage.

=cut

sub get_partinfo($$) {
	my ($vol, $startline) = @_;
	my ($serverg, $part, $subg, $kb);
	my $resline = "";
	my $query = "SELECT count(*) as cnt FROM t_part WHERE disk='$vol'";
	my $sth = $dbh3->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		my $cnt = $ref->{cnt};
		if ($cnt == 0) {
			# Could this be part of a mirrorview?
			$sth->finish();
			get_mirror($vol,$startline);
			return;
		}
	}
	$sth->finish();
	$query = "SELECT serverg, part, subg, kb
				 FROM t_part
				 WHERE disk='$vol'";
	$sth = $dbh3->prepare($query);
	$rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	while (my $ref = $sth->fetchrow_hashref) {
		$serverg = $ref->{serverg} || "unknown";
		$part = $ref->{part} || "unknown";
		$subg = $ref->{subg} || "unknown";
		$kb = $ref->{kb} || "unknown";
		$sth->finish();
		$resline = "$startline;$serverg;$part;$subg;$kb";
		if ($subg eq "unknown") {
			print RES $resline."\n";
		} else {
			get_subginfo($subg,$resline);
		}
	}
	return;
}

=pod

=head2 Get SubgroupInfo

This procedure will collect the subgroup information that is related to a partition.

There can be multiple subgroups related to a partition. Each partition should have a subgroup.

=cut

sub get_subginfo($$) {
	my ($parent, $startline) = @_;
	my $resline = "";
	my $query = "SELECT count(*) as cnt FROM t_subg WHERE parent='$parent'";
	my $sth = $dbh3->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		my $cnt = $ref->{cnt};
		if ($cnt == 0) {
			$resline = "$startline;No Subgroup\n";
			print RES $resline;
			return;
		}
	}
	$sth->finish();
	$query = "SELECT serverg, subg, sts, pct, kb_log, pool, fs, server, vserver, zdscr
				 FROM t_subg
				 WHERE parent='$parent'";
	$sth = $dbh3->prepare($query);
	$rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	while (my $ref = $sth->fetchrow_hashref) {
		my $serverg = $ref->{serverg} || "unknown";
		my $subg = $ref->{subg} || "unknown";
		my $sts = $ref->{sts} || "";
		my $pct = $ref->{pct} || "";
		my $kb_log = $ref->{kb_log} || "";
		my $pool = $ref->{pool} || "";
		my $fs = $ref->{fs} || "unknown";
		my $server = $ref->{server} || "unknown";
		my $vserver = $ref->{vserver} || "unknown";
		my $zdscr = $ref->{zdscr} || "";
		$resline = "$startline;$serverg;$parent;$subg;$sts;$pct;$kb_log;$pool;$fs;$server;$vserver;$zdscr\n";
		print RES $resline;
	}
	$sth->finish();
	return;
}

=pod

=head2 Get Mirror

This procedure will check for a mirror configuration. If the disk volume is not in the t_part partition table, it may be the passive side of a mirror configuration.

Therefore the wwlunid is collected from the volume table. This lun id should be value wwlunid2 in the mirrorview, where disk is then the volume for the active drive.

=cut

sub get_mirror($$) {
	my ($vol, $startline) = @_;
	my ($serverg, $part, $subg, $kb, $wwlunid);
	my $resline = "";
	# Get wwlunid from volume table
	my $query = "SELECT wwlunid FROM t_vol WHERE vol='$vol'";
	my $sth = $dbh3->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		$wwlunid = $ref->{wwlunid};
		$sth->finish();
	} else {
		$sth->finish();
		error ("Could not find $vol in t_vol volume table!");
		return;
	}
	# Now find active disk in the mirrorview
	$query = "SELECT wwlunid, wwlunid2 FROM t_mirrorview WHERE wwlunid = '$wwlunid' OR wwlunid2 = '$wwlunid'";
	$sth = $dbh3->prepare($query);
	$rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		my $wwlunid_first = $ref->{wwlunid};
		my $wwlunid_second = $ref->{wwlunid2};
		if ($wwlunid_first eq $wwlunid) {
			$wwlunid = $wwlunid_second;
		} else {
			$wwlunid = $wwlunid_first;
		}
		$sth->finish();
	} else {
		$sth->finish();
		error ("Could not find wwlunid for volume $vol in t_mirrorview mirror table!");
		return;
	}
	# and find disk volume for this wwlunid
	$query = "SELECT vol FROM t_vol WHERE wwlunid = '$wwlunid'";
	$sth = $dbh3->prepare($query);
	$rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		$vol = $ref->{vol};
		$sth->finish();
		$resline = "$startline;Active Mirror;$vol\n";
		print RES $resline;
	} else {
		$sth->finish();
		error ("Could not find $wwlunid (volume $vol) for active volume in t_mirrorview mirror table!");
		return;
	}
	return;
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

# Open outputfile for writing
my $openres = open(RES, ">$outfile");
if (not defined $openres) {
	error("Could not open $outfile for writing, exiting...");
	exit_application(1);
}

# Make database connection to filedata database
my $connectionstring = "DBI:mysql:database=$databasename;host=$server;port=$port";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

# And make a second connection to database
$dbh2 = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

# And make a third connection to database
$dbh3 = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

# Get all Clariion SAN boxes at Vo
my $query = "SELECT box FROM t_box WHERE sts='prod' AND scope='eib' AND boxtype='clariion'";
my $sth = $dbh->prepare($query);
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

print RES "box;rg;rgn;pool;diskpool;tp;kb_raw;kb_log;rgfrag;vol;capa;kb_raw;kb_log;serverg;diskg;drv;kb;kb_free;kb_ovh;serverg;part;subg;kb;serverg;parent;subg;sts;pct;kb_log;pool;fs;server;vserver;zdscr\n";
# Get Configuration for each box:
# All Raid Groups and hot-spare disks
foreach my $box (@boxes) {
	my $query = "SELECT rg, rgn, pool, diskpool, tp, diskcount, kb_raw, kb_log, kb_free, kb_cont, kb_os
				 FROM t_rg
				 WHERE box='$box' AND NOT tp='Unbound' AND NOT tp='hot_spare'";
	my $sth = $dbh->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	while (my $ref = $sth->fetchrow_hashref) {
		my $rg = $ref->{rg};
		my $rgn = $ref->{rgn};
		my $pool = $ref->{pool};
		my $diskpool = $ref->{diskpool};
		my $tp = $ref->{tp};
		my $diskcount = $ref->{diskcount};
		my $kb_raw = $ref->{kb_raw};
		my $kb_log = $ref->{kb_log};
		my $kb_free = $ref->{kb_free};
		my $kb_cont = $ref->{kb_cont};
		my $kb_os = $ref->{kb_os};
		my $rgline = "$box;$rg;$rgn;$pool;$diskpool;$tp;$kb_raw;$kb_log";
		# Now search for RAID group fragments for this Raid Group
		get_volume($box,$rgn,$rgline);
	}
}

exit_application(0);

=head1 To Do

=over 4

=item *

Nothing documented for now...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
