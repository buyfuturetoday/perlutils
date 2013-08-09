=head1 NAME

AttrRow - Add full attribute hierarchy per attribute

=head1 VERSION HISTORY

version 1.0 04 January 2011 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This script will add the attribute row per attribute for the class. This should allow to draw attributes in classes independent of the start point.

=head1 SYNOPSIS

 AttrRow.pl [-t] [-l log_dir]

 AttrRow -h	   Usage
 AttrRow -h 1  Usage and description of the options
 AttrRow -h 2  All documentation

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

sub updateattr($$$$) {
	my ($dbh, $classid, $attributeid, $attrrow) = @_;
	my $query = "UPDATE attrperclass
					SET attrrow = '$attrrow'
					WHERE classid = $classid
					AND attributeid = $attributeid";
	my $rv = $dbh->do($query);
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$rv->errstr);
		exit_application(1);
	}
}

sub handleattribute($$$$) {
	my ($dbh, $attributeid, $classid, $parentrow) = @_;
	my @parents = split /;/, $parentrow;
	my $query = "SELECT attrrow FROM attrperclass
					WHERE classid = ? AND attributeid = $attributeid";
	my $sth = $dbh->prepare($query);
	my $attrrow;		# Initialize attrrow variable
	while (my $parent = pop @parents) {
		$sth->bind_param(1, $parent);
		my $rv = $sth->execute();
		if (not defined $rv) {
			error("Could not execute query $query, Error: ".$sth->errstr);
			exit_application(1);
		}
		if (my $ref = $sth->fetchrow_hashref) {
			# Found attribute in parent class, so classid can be updated
			# and search stopped
			$attrrow = $ref->{attrrow};
			$attrrow .= $delim . $classid;
			updateattr($dbh, $classid, $attributeid, $attrrow);
			$sth->finish;
			last;
		} else {
			$sth->finish;
		}
	}
	if (not defined $attrrow) {
		# Attribute not found in one of the parent classes, 
		# initialize attrrow
		updateattr($dbh, $classid, $attributeid, $classid);
	}
}

sub handleclass($$$) {
	my ($dbh, $classid, $parentrow) = @_;
	my $query = "SELECT attributeid
					FROM attrperclass
					WHERE classid = $classid";
	my $sth = $dbh->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	while (my $ref = $sth->fetchrow_hashref) {
		my $attributeid = $ref->{attributeid};
		handleattribute($dbh, $attributeid, $classid, $parentrow);
	}
}

sub handlechildren($$) {
	my ($dbh, $parentid) = @_;
	my $query = "SELECT classid, parentrow
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
		my $parentrow = $ref->{parentrow};
		# Remember child as new parent to handle
		push @nextgen, $classid;
		handleclass($dbh, $classid, $parentrow);
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
# Update attrrow for parentid
handleclass($dbh, $init_parentid, "");

# Handle all parents in parent array
# First check if there
while (@parents) {
	while (my $parentid = shift @parents) {
		handlechildren($dbh, $parentid);
	}
	# Move next generation parents to parents
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
