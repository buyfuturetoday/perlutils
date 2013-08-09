=head1 NAME

ParentRow - Add full parent hierarchy per class

=head1 VERSION HISTORY

version 1.0 04 January 2011 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This script will calculate the parent hierarchy for all classes. It will start from the root class (parentid=0), find all children and add parentrow to the children. Then handle each child as parent and restart, until full hierarchy has been handled.

For now the script can handle only one root class (it_world). This script may require changes when links classes are added to these classes.

=head1 SYNOPSIS

 ParentRow.pl [-t] [-l log_dir]

 ParentRow -h	Usage
 ParentRow -h 1  Usage and description of the options
 ParentRow -h 2  All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-c class>

Parent Class

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP, Perl v5.10.0, build 1005 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $dbh, @parents, @nextgen, %parentrows);
my $printerror = 0;
my $init_parentid = 199;		# Initial Parent ID
my $delim = ";";
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
use dbParamsuCMDB;

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if (defined $dbh) {
		$dbh->disconnect;
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

sub updaterow($$$) {
	my ($dbh, $classid, $parentrow) = @_;
	my $query = "UPDATE classes
					SET parentrow = '$parentrow'
					WHERE classid = $classid";
	my $rv = $dbh->do($query);
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$rv->errstr);
		exit_application(1);
	}
}

sub handlechildren($) {
	my ($parentid) = @_;
	my $query = "SELECT classid
					FROM classes
					WHERE parentid = $parentid";
	my $sth = $dbh->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	while (my $ref = $sth->fetchrow_hashref) {
		my $classid = $ref->{classid};
		# Remember Parentrow for this child
		$parentrows{$classid} = $parentrows{$parentid} . $delim . $classid;
		# Remember child as new parent to handle
		push @nextgen, $classid;
		# Update parentrow for this class id
		updaterow($dbh, $classid, $parentrows{$parentid});
	}
	$sth->finish();
}
	

######
# Main
######

# Handle input values
my %options;
getopts("tl:h:", \%options) or pod2usage(-verbose => 0);
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

# Make database connection 
my $connectionstring = "DBI:mysql:database=$dbsource;host=$server;port=$port";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $dbsource, exiting...");
   	exit_application(1);
}

# Initialize parents array to handle
push @parents, $init_parentid;
# Initialize parentrows
$parentrows{$init_parentid} = "$init_parentid";
# Update parentrow for parentid
updaterow($dbh, $init_parentid, $parentrows{$init_parentid});


# Handle all parents in parent array
# First check if there
while (@parents) {
	while (my $parentid = shift @parents) {
		handlechildren($parentid);
	}
	# Move new parents to parents
	@parents = @nextgen;
	# And start from an empty array of nextgen
	@nextgen = ();
}

exit_application(0);

=head1 To Do

=over 4

=item *

Nothing documented for now...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@hp.comE<gt>
