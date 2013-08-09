=head1 NAME

getFileSystem - Collect File System information.

=head1 VERSION HISTORY

version 1.0 16 October 2009 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will get the Filesystems that are created on Logical Disks. Note that there are also filesystems created from a Logical Pool. Another application needs to collect the filesystems from the Logical Pools.

Take all known logical disks for the customer and find the subg identifier in t_part. If subg is NULL, then the logical disk has no Filesystem assigned. Otherwise the subg field is the parent identifier for the t_subg table that has all filesystem information.

=head1 SYNOPSIS

 getFileSystemFromDisk.pl [-t] [-l log_dir] 

 getFileSystemFromDisk -h	   Usage
 getFileSystemFromDisk -h 1	   Usage and description of the options
 getFileSystemFromDisk -h 2	   All documentation

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

my ($logdir, $dbhsource, $dbhtarget, $dbhtarget2);
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
	if (defined $dbhtarget2) {
		$dbhtarget2->disconnect;
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

=head2 Add to Filesystem

This procedure will add the Filesystem information to the File System table.

=cut

sub add2Filesystem {
	my($name,$kb_log,$pct,$status,$filesystem,$description,$server,$vserver,$logicaldisk,$servergroup) = @_;
	my $kb_used = sprintf("%u",($kb_log * $pct) / 100);
	my $query = "INSERT INTO filesystem (name,kb_log,pct,kb_used,status,filesystem,description,server,vserver,logicaldisk,servergroup) 
				 VALUES ('$name','$kb_log','$pct','$kb_used','$status','$filesystem','$description','$server','$vserver','$logicaldisk','$servergroup')";
	my $rows_affected = $dbhtarget2->do($query);
	if (not defined $rows_affected) {
		error("Insert failed, query $query. Error: ".$dbhtarget2->errstr);
	} elsif (not $rows_affected == 1) {
		error("$rows_affected rows updated ($query), 1 expected");
	}
}

=pod

=head2 Get Filesystems

A Logical disk with one or more filesystems assigned to it has a 'subg' identifier. This is the 'parent' field in the table t_subg.

Unique identifier for filesystems in t_subg is serverg|subg combination. All filesystem information is available there. 

=cut

sub getfilesys {
	my ($serverg, $parent) = @_;
	my $query = "SELECT subg,kb_log,pct,sts,fs,zdscr,server,vserver FROM t_subg WHERE serverg='$serverg' and parent='$parent'";
	my $sth = $dbhsource->prepare($query);
	my $rv = $sth->execute();
	if (not(defined $rv)) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	while (my $ref = $sth->fetchrow_hashref) {
		my $subg = $ref->{subg};
		my $kb_log = $ref->{kb_log};
		my $pct = $ref->{pct};
		my $sts = $ref->{sts};
		my $fs = $ref->{fs} || "";
		my $zdscr = $ref->{zdscr} || "";
		my $server = $ref->{server} || "";
		my $vserver = $ref->{vserver} || "";
		add2Filesystem($subg,$kb_log,$pct,$sts,$fs,$zdscr,$server,$vserver,$parent,$serverg);
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

# Get second database connection
$dbhtarget2 = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbhtarget2) {
   	error("Could not open $dbtarget, exiting...");
   	exit_application(1);
}


# Get all Logical Disks
my $query = "SELECT logicaldisk,servergroup FROM logicaldisk";
my $sth = $dbhtarget->prepare($query);
my $rv = $sth->execute();
if (not(defined $rv)) {
	error("Could not execute query $query, Error: ".$sth->errstr);
	exit_application(1);
}
while (my $ref = $sth->fetchrow_hashref) {
	my $logicaldisk = $ref->{logicaldisk};
	my $servergroup = $ref->{servergroup};
	getfilesys($servergroup,$logicaldisk);
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
