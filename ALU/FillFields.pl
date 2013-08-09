=head1 NAME

FillFields - Fill Empty Fields with fieldvalue from previous field.

=head1 VERSION HISTORY

version 1.0 22 December 2010 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will fill NULL fields with fieldvalue from previous field. This application can be used for tables imported from excel. For importing (vertically) merged fields, the field value will be added to the first record and all other fields from this merged field will be NULL. 

Empty fields remain empty.

=head1 SYNOPSIS

 FillFields.pl [-t] [-l log_dir] -m tablename 

 FillFields -h		Usage
 FillFields -h 1   Usage and description of the options
 FillFields -h 2   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-m tablename>

MySQL Table name to handle. For uCMDB database, the attributes and the links table have NULL values in first (nonID) field.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP, Perl v5.10.0, build 1005 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $dbh, $dbh2, $table, $field);
my $printerror = 0;
my $prev_value = "Impossible Value";

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
	if (defined $dbh2) {
		$dbh2->disconnect;
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

sub update_record($$) {
	my ($id, $value) = @_;
	my $query = "UPDATE $table SET $field = '$value' WHERE ID = $id";
	my $rv = $dbh2->do($query);
	if (not defined $rv) {
		error("Could not update record ID $id in table $table ". $dbh->errstr);
		exit_application(1);
	}
}
	

######
# Main
######

# Handle input values
my %options;
getopts("tl:h:m:", \%options) or pod2usage(-verbose => 0);
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
# Get tablename
if ($options{"m"}) {
	$table = $options{"m"};
} else {
	error("Table name not defined, exiting...");
	exit_application(1);
}
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

$dbh2 = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh2) {
   	error("Could not open $dbsource, exiting...");
   	exit_application(1);
}

if ($table eq 'attributes') {
	$field = 'class';
} elsif ($table eq 'links') {
	$field = 'FromCIclass';
} elsif ($table eq 'aluucmdb') {
	$field = 'CITechName';
} else {
	error("Don't know how to handle table $table, exiting...");
	exit_application(1);
}

my $query = "SELECT ID, $field FROM $table ORDER BY ID ASC";
my $sth = $dbh->prepare($query);
my $rv = $sth->execute();
if (not defined $rv) {
	error("Could not execute query $query, Error: ".$sth->errstr);
	exit_application(1);
}
while (my $ref = $sth->fetchrow_hashref) {
	my $id = $ref->{ID};
	my $value = $ref->{$field};
	if (defined $value) {
		$prev_value = $value;
	} else {
		update_record($id, $prev_value);
	}
}
$sth->finish();

exit_application(0);

=head1 To Do

=over 4

=item *

Nothing documented for now...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@hp.comE<gt>
