=head1 NAME

getStorageVolumeMirrors - Get Storage Volume Mirrors

=head1 VERSION HISTORY

version 1.0 14 October 2009 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will add the mirror link to a Storage volume. Therefore the table t_mirrorview is scanned. The wwlunid / wwlunid2 is translated to the volume couples. If the volumes are identified as volumes for the customer, then the volumes are added to each others link.

=head1 SYNOPSIS

 getStorageVolumeMirrors.pl [-t] [-l log_dir] 

 getStorageVolumeMirrors -h	   Usage
 getStorageVolumeMirrors -h 1  Usage and description of the options
 getStorageVolumeMirrors -h 2  All documentation

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

my ($logdir, $dbhsource, $dbhtarget, %couples);
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

=head2 Update Mirror

The volumes for the mirror have been found. Now check if both volumes are defined as StorageVolumes. If so, add mirror link to both. Ignore couple if no Storage Volumes are defined. Error message if only 1 part of the mirror exist.

=cut

sub updatemirror {
	my ($vol, $vol2) = @_;
	# Add first volume
	my $query = "UPDATE storagevolume SET mirror = '$vol2' 
				 WHERE vol='$vol'";	
	my $rows_affected = $dbhtarget->do($query);
	if (not defined $rows_affected) {
		error("Update failed, query $query. Error: ".$dbhtarget->errstr);
	} elsif ($rows_affected > 1) {
		error("$rows_affected rows updated ($query), 0 or 1 expected");
	}
	# Add second volume
	$query = "UPDATE storagevolume SET mirror = '$vol' 
				 WHERE vol='$vol2'";	
	my $rows_affected2 = $dbhtarget->do($query);
	if (not defined $rows_affected2) {
		error("Update failed, query $query. Error: ".$dbhtarget->errstr);
	} elsif ($rows_affected2 > 1) {
		error("$rows_affected2 rows updated ($query), 0 or 1 expected");
	}
	if (not $rows_affected == $rows_affected2) {
		error("Only 1 volume of the pair $vol - $vol2 found!");
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

# Get all wwlunid couples
my $query = "SELECT wwlunid,wwlunid2 FROM t_mirrorview";
my $sth = $dbhsource->prepare($query);
my $rv = $sth->execute();
if (not(defined $rv)) {
	error("Could not execute query $query, Error: ".$sth->errstr);
	exit_application(1);
}
while (my $ref = $sth->fetchrow_hashref) {
	my $wwlunid = $ref->{wwlunid};
	my $wwlunid2 = $ref->{wwlunid2};
	$couples{$wwlunid} = $wwlunid2;
}
$sth->finish();

# Now get the storage volumes for each couples
while (my ($wwlunid, $wwlunid2) = each %couples) {
	my ($vol, $vol2);
	# Get first storage volume
	my $query = "SELECT vol FROM t_vol WHERE wwlunid='$wwlunid'";
	my $sth = $dbhsource->prepare($query);
	my $rv = $sth->execute();
	if (not(defined $rv)) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		$vol = $ref->{vol};
	} else {
		error("Could not find wwlunid $wwlunid in t_vol!");
		next;
	}
	# and get second storage volume
	$query = "SELECT vol FROM t_vol WHERE wwlunid='$wwlunid2'";
	$sth = $dbhsource->prepare($query);
	$rv = $sth->execute();
	if (not(defined $rv)) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		$vol2 = $ref->{vol};
	} else {
		error("Could not find wwlunid2 $wwlunid2 in t_vol!");
		next;
	}
	updatemirror($vol,$vol2);
}

exit_application(0);

=head1 To Do

=over 4

=item *

Nothing documented for now...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
