=head1 NAME

getRaidgroup - Collect RaidGroup information for Customer

=head1 VERSION HISTORY

version 1.0 14 October 2009 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will get the RaidGroup Information for all boxes in the customer environment. Therefore the boxes for the customer will be collected first. For each box all RaidGroup information will then be collected.

=head1 SYNOPSIS

 getRaidGroup.pl [-t] [-l log_dir] 

 getRaidGroup -h	   Usage
 getRaidGroup -h 1	   Usage and description of the options
 getRaidGroup -h 2	   All documentation

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

my ($logdir, $dbhsource, $dbhtarget, @boxes);
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

=head2 Add to RaidGroup

This procedure will add the Raidgroup information to the DWH Raidgroup table.

Check if kb_raw=kb_free. If so, set type to Unbound if type was r5 or r1_0. It can occur that the type has been defined already, but the configuration has not yet been done.

=cut

sub add2raidgroup {
	my($rg,$diskcount,$diskpool,$kb_cont,$kb_free,$kb_log,$kb_os,$kb_raw,$rgtype,$box) = @_;
	if (($rgtype eq 'r5') or ($rgtype eq 'r1_0')) {
		if ($kb_raw == $kb_free) {
			$rgtype = "Unbound";
		}
	}
	my $query = "INSERT INTO raidgroup (rg,diskcount,diskpool,kb_cont,kb_free,kb_log,kb_os,kb_raw,rgtype,box) 
				 VALUES ('$rg','$diskcount','$diskpool','$kb_cont','$kb_free','$kb_log','$kb_os','$kb_raw','$rgtype','$box')";
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

# Now collect Raidgroup information per box
foreach my $box (@boxes) {
	my $query = "SELECT rg, diskcount, diskpool, kb_cont, kb_free, kb_log, kb_os, kb_raw, tp 
			     FROM t_rg WHERE box='$box'";
	my $sth = $dbhsource->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query. Error: ".$sth->errstr);
		exit_application(1);
	}
	while (my $ref = $sth->fetchrow_hashref) {
		my $rg = $ref->{rg};
		my $diskcount = $ref->{diskcount};
		my $diskpool = $ref->{diskpool};
		my $kb_cont = $ref->{kb_cont};
		my $kb_free = $ref->{kb_free};
		my $kb_log = $ref->{kb_log};
		my $kb_os = $ref->{kb_os};
		my $kb_raw = $ref->{kb_raw};
		my $tp = $ref->{tp};
		add2raidgroup($rg,$diskcount,$diskpool,$kb_cont,$kb_free,$kb_log,$kb_os,$kb_raw,$tp,$box);
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
