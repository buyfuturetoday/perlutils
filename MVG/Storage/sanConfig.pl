=head1 NAME

sanConfig - Calculates the used and available capacity on SAN Clariion boxes

=head1 VERSION HISTORY

version 1.0 2 July 2009 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will calculate the storage capacity in use and the storage capacity available for the SAN storage devices at Vo.

=head1 SYNOPSIS

 sanConfig.pl [-t] [-l log_dir] 

 sanConfig -h	 	   Usage
 sanConfig -h 1	   Usage and description of the options
 sanConfig -h 2	   All documentation

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

my ($logdir, $dbh, @boxes);
my $username = "root";
my $password = "Monitor1";
my $server = "localhost";
my $databasename = "san";
my $port = 3306;
my $printerror = 0;
my $outfile = "D:/Projects/Vo/Storage Rapportage/reports/sanConfig.csv";

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

print RES "box;rg;rgn;pool;diskpool;tp;diskcount;kb_raw;kb_log;kb_free;kb_cont;kb_os\n";
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
		print RES "$box;$rg;$rgn;$pool;$diskpool;$tp;$diskcount;$kb_raw;$kb_log;$kb_free;$kb_cont;$kb_os\n";
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
