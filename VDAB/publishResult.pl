=head1 NAME

publishResult - This application will extract performance data from the database and publish the results on a shared drive.

=head1 VERSION HISTORY

version 1.0 4 September 2009 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will extract the performance data from the database and make it available in a text file for further processing. There will be one result file per day. Files will be copied on a local drive and on a shared drive.

The oldest date from the database will be collected. Then a file will be created for every day that does not exist on the local drive. If a map is available, then the file will be copied to the shared drive as well.

=head1 SYNOPSIS

publishResult.pl [-t] [-l log_dir]

    publishResult -h	    Usage
    publishResult -h 1	    Usage and description of the options
    publishResult -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP SP2, Perl v5.8.8, build 820 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $dbh, $dbh2,$netwobj);
my $printerror = 0;
my $timeout = 60;
my $shareddrive = "\\\\10.40.2.100\\grpict";
my $shareavailable = "No";
my $map = "N:";
my $persistant = 0;
my $perfdir = "e:/Application Monitoring Report";
my $publishdir = "GRPDATA/Application Monitoring Report";

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use Log;					# Application and error logging
use DBI();
use amParams;
use Win32::OLE;				# Shared drive handling
use File::Copy;				# For copying files

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	disconnectShare();
	if (defined $dbh) {
		$dbh->disconnect;
	}
    logging("Exit application with return code: $return_code\n");
    close_log();
    exit $return_code;
}

=pod

=head2 Trim

This section is used to get rid of leading or trailing blanks. It has been
copied from the Perl Cookbook.

=cut

sub trim {
    my @out = @_;
    for (@out) {
        s/^\s+//;
        s/\s+$//;
    }
    return wantarray ? @out : $out[0];
}

=pod

=head2 Connect2Share

This procedure will try to connect to the remote share. If successful, published data will be copied to the share. Otherwise published data will be available locally only.

=cut

sub connect2Share() {
	my(%allshares);
	# Find Network drive
	$netwobj = Win32::OLE->new('WScript.Network');
	my $nrshares = $netwobj->EnumNetworkDrives->Count;
	for (my $cnt=0; $cnt<$nrshares; $cnt+=2) {
		my $mapchr = $netwobj->EnumNetworkDrives->{$cnt};
		my $share = $netwobj->EnumNetworkDrives->{$cnt+1};
		$allshares{$share} = $mapchr;
	}
	# Check if required share is available and accessible
	if ($allshares{$shareddrive}) {
		$map = $allshares{$shareddrive};
		# Drive letter found, check if readable
		if (-d $map) {
			$shareavailable = "Yes";
			logging("Share $shareddrive available on $map");
		} else {
			# Share exist but not readable.
			# Remove share and reconnect (in a next step)
			logging("Share $shareddrive available but not readable on $map, trying to remove");
			$netwobj->RemoveNetworkDrive($map);
		}
	}
	# Connect to share if not yet available
	if (not($shareavailable eq "Yes")) {
		$netwobj->MapNetworkDrive($map, $shareddrive, $persistant, $sharename, $sharekey);
		# Test if drive is readable 
		# (there seems to be no other test available?)
		if (-d $map) {
			$shareavailable = "Yes";
			logging("Share $shareddrive available on $map");
		} else {
			error("Could not map $shareddrive to $map");
		}
	}
}

=pod

=head2 Disconnect Share

This procedure will disconnect from the share if it is available. No checking on a successful disconnect will be done.

=cut

sub disconnectShare() {
	if ($shareavailable eq "Yes") {
		$netwobj->RemoveNetworkDrive("$map", 1);
		logging("Disconnect from network share");
	}
}

=pod

=head2 Handle table Date procedure

A check will be done if the local file for the table and date is available. If so, then procedure will stop. If not, then this procedure will extract all records from a specific date and table. The records will be written to a local file. If a share is available, then the local file will be copied to the network share.

=cut

sub handle_table_date($$) {
	my ($table, $date) = @_;
	my $outfilename = "$perfdir/$table"."_$date.csv";
	if (-r $outfilename) {
		logging("$outfilename exists already, no extract required");
		return;
	}
	logging("Now creating $outfilename");
	my $resfile = open(PERF, ">$outfilename");
	if (not defined $resfile) {
		error("Could not open $outfilename for writing");
		return;
	}
	my $query = "SELECT * FROM $table WHERE date(msdatetime)='$date'";
	my $sth = $dbh->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	# fetchrow_array could be more efficient than fetchall_arrayref
	while (my @ref = $sth->fetchrow_array) {
		print PERF join(";",@ref),"\n";
	}
	close PERF;
	# Copy file if share is available
	if ($shareavailable eq "Yes") {
		my $publishedfile = "$map/$publishdir/$table"."_$date.csv";
		my $copyres = copy($outfilename, $publishedfile);
		if (defined $copyres) {
			logging("$outfilename copied to $publishedfile");
		} else {
			error("Could not copy $outfilename to $publishedfile");
		}
	}
}

######
# Main
######

# Handle input values
my %options;
getopts("tl:h:", \%options) or pod2usage(-verbose => 0);
# At least the table name must be specified.
# my $arglength = scalar keys %options;  
# if ($arglength == 0) {			# If no options specified,
#    $options{"h"} = 0;			# display usage. jmeter plan is mandatory
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
		error("Could not set d:/temp/log as Log directory, exiting...");
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

# Set-up database connection
my $connectionstring = "DBI:mysql:database=$databasename;host=$server;port=$port";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

# Set-up second database connection
$dbh2 = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh2) {
   	error("Could not open second connection to $databasename, exiting...");
   	exit_application(1);
}

connect2Share();

# Handle all tables
foreach my $table ("monstat","bbperf") {
	# Get all distinct dates
	my $query = "SELECT distinct(date(msdatetime)) as date FROM $table WHERE NOT date(msdatetime)=curdate()";
	my $sth = $dbh->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	while (my $ref = $sth->fetchrow_hashref) {
		my $date = $ref->{date};
		handle_table_date($table, $date);
	}
}


exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Run tests for some time, then compare with response time too long. (Do we want to do this in jmeterAgent.pl, or in a separate script?

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
