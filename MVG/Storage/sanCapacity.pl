=head1 NAME

sanCapacity - Calculates the used and available capacity on SAN Clariion boxes

=head1 VERSION HISTORY

version 1.0 2 July 2009 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will calculate the storage capacity in use and the storage capacity available for the SAN storage devices at Vo.

There are two ways of learning about the available storage capacity. The easy way is to check for the fields kb_log and kb_cont in the table t_rg. This gives the logical free space and the contiguous free space for the raid group. Contiguous free space is less than or equal to logical free space. 

The second way, as done in this script, will find the fragments that are defined for each raid group and summarize assigned disk space. The sum is the assigned disk space, the available disk space can then be calculated.

There are also some volumes defined but no longer (or not yet?) assigned to a server and disk. These volumes can be found in the san2disk report, by selecting serverg and diskg unassigned.

Note that these volumes can be made up of fragments, and the total usable space may be smaller than the listed disk space.

=head1 SYNOPSIS

 sanCapacity.pl [-t] [-l log_dir] 

 sanCapacity -h	 	   Usage
 sanCapacity -h 1	   Usage and description of the options
 sanCapacity -h 2	   All documentation

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

my ($logdir, $dbh, $dbh2, @boxes);
my $username = "root";
my $password = "Monitor1";
my $server = "localhost";
my $databasename = "san";
my $port = 3306;
my $printerror = 0;
my $outfile = "D:/Projects/Vo/Storage Rapportage/reports/sanCapacity.csv";

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

=head2 Get Raid Group Fragments Space

This procedure will calculate all Raid Group Fragments for the Raid Group. The goal is to determine how much raw/log space is in use and how much is still available.

=cut

sub get_rg_fragments_space($$) {
	my ($box, $rgn) = @_;
	my ($tot_raw, $tot_log);
	my $query = "SELECT sum(kb_raw) as tot_raw, sum(kb_log) as tot_log
				 FROM t_rgfrag
				 WHERE box='$box' AND rgn='$rgn'";
	my $sth = $dbh2->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		$tot_raw = $ref->{tot_raw} || "bekijkt dat eens";
		$tot_log = $ref->{tot_log} || "bekijkt dat eens";
	} else {
		$tot_raw = "unknown";
		$tot_log = "unknown";
	}
	$sth->finish();
	return $tot_raw, $tot_log;
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

print RES "box;rg;rgn;pool;diskpool;tp;diskcount;kb_raw;kb_log;kb_free;kb_cont;kb_os (raw);Assigned (raw);Assigned (log);Available (raw);Available (log)\n";
# Get Configuration for each box:
# All Raid Groups and hot-spare disks
foreach my $box (@boxes) {
	my $query = "SELECT rg, rgn, pool, diskpool, tp, diskcount, kb_raw, kb_log, kb_free, kb_cont, kb_os
				 FROM t_rg
				 WHERE box='$box'";
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
		# Now search for RAID group fragments for this Raid Group if required
		my ($tot_raw, $tot_log, $avail_raw, $avail_log);
		switch ($tp) {
			case "Unbound" {
				$tot_raw = 0;
				$tot_log = 0;
				$avail_raw = $kb_raw;
				$avail_log = 0;
			}
			case "hot_spare" {
				$tot_raw = 0;
				$tot_log = 0;
				$avail_raw = 0;
				$avail_log = 0;
			}
			else {
				($tot_raw, $tot_log) = get_rg_fragments_space($box,$rgn);
				$avail_raw = $kb_raw - $kb_os - $tot_raw;
				$avail_log = $kb_log - $tot_log;
			}
		}
		print RES "$box;$rg;$rgn;$pool;$diskpool;$tp;$diskcount;$kb_raw;$kb_log;$kb_free;$kb_cont;$kb_os;$tot_raw;$tot_log;$avail_raw;$avail_log\n";
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
