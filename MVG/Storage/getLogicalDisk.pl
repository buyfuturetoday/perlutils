=head1 NAME

getLogicalDisk - Collect Logical Disks.

=head1 VERSION HISTORY

version 1.0 15 October 2009 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will collect all logical Disk information. Logical Disks are made up of one or more disk partitions.

=head1 SYNOPSIS

 getLogicalDisk.pl [-t] [-l log_dir] 

 getLogicalDisk -h	   Usage
 getLogicalDisk -h 1	   Usage and description of the options
 getLogicalDisk -h 2	   All documentation

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

my ($logdir, $dbhtarget, $dbhtarget2, @volumes);
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
	if (defined $dbhtarget) {
		$dbhtarget->disconnect;
	}
	if (defined $dbhtarget2) {
		$dbhtarget2->disconnect;
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

=cut

sub add2logicaldisk {
	my($logicaldisk,$kb_log,$servergroup) = @_;
	my $query = "INSERT INTO logicaldisk (logicaldisk,kb_log,servergroup) 
				 VALUES ('$logicaldisk','$kb_log','$servergroup')";
	my $rows_affected = $dbhtarget2->do($query);
	if (not defined $rows_affected) {
		error("Insert failed, query $query. Error: ".$dbhtarget2->errstr);
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

# Make database connection to target database
my $connectionstring = "DBI:mysql:database=$dbtarget;host=$server;port=$port";
$dbhtarget = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbhtarget) {
   	error("Could not open $dbtarget, exiting...");
   	exit_application(1);
}

# Make second database connection to target database
$dbhtarget2 = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbhtarget2) {
   	error("Could not open $dbhtarget2, exiting...");
   	exit_application(1);
}

# Get all LogicalDisk Identifiers (servergroup,logicaldisk combination)
my $query = "SELECT servergroup, logicaldisk, sum(kb_log) AS kb_log
			 FROM diskpartition
			 WHERE NOT logicaldisk = ''
			 GROUP BY servergroup, logicaldisk";
my $sth = $dbhtarget->prepare($query);
my $rv = $sth->execute();
if (not(defined $rv)) {
	error("Could not execute query $query, Error: ".$sth->errstr);
	exit_application(1);
}
while (my $ref = $sth->fetchrow_hashref) {
	my $servergroup = $ref->{servergroup};
	my $logicaldisk = $ref->{logicaldisk};
	my $kb_log = $ref->{kb_log};
	add2logicaldisk($logicaldisk,$kb_log,$servergroup);
}
$sth->finish();

exit_application(0);

=head1 To Do

=over 4

=item *

Nothing documented for now...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
