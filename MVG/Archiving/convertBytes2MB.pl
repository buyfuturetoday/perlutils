=head1 NAME

convertBytes2MB - Convert Bytes to MB

=head1 VERSION HISTORY

version 1.0 04 May 2009 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will convert size in bytes to size in MB.

=head1 SYNOPSIS

 convertBytes2MB.pl [-t] [-l log_dir] [-a | -n YYYY-MM-DD]

 convertBytes2MB -h 	   Usage
 convertBytes2MB -h 1	   Usage and description of the options
 convertBytes2MB -h 2	   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Disable tracing, default: tracing. Remark: reverse logic!

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-a>

If set, then run script over all tables. Otherwise, use defined tablearray.

=item B<-n>

If set, then run script only over tables that are created I<after> YYYY-MM-DD.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP, Perl v5.8.8, build 804 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir,$dbh, $reportdate, $reportdays, $newtabledate);
# my @table_arr=('bru000center83m_s','bru000center83m_l','bru000center83m_p','bru000center83m_n');
my @table_arr=('bru000center85m_o');
my $alltablesflag = "No";

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
use MySQLModules;
use dbParams;

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

######
# Main
######

# Handle input values
my %options;
getopts("tl:h:an:", \%options) or pod2usage(-verbose => 0);
# The Filename must be specified
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
	Log::trace_flag(0);
} else {
    Log::trace_flag(1);
}
# Find log file directory
if ($options{"l"}) {
    $logdir = logdir($options{"l"});
    if (not(defined $logdir)) {
		print "Could not set $logdir as Log directory, exiting...\n";
		exit_application(1);
    }
} else {
    $logdir = logdir();
    if (not(defined $logdir)) {
		print "Could not find default Log directory, exiting...\n";
		exit_application(1);
    }
}
if (-d $logdir) {
	# trace("Logdir: $logdir");
} else {
    pod2usage(-msg     => "Cannot find log directory $logdir",
	      -verbose => 0);
}
# Logdir found, start logging
open_log();
logging("Start application");
# Check if result needs to run over all tables
if (defined $options{"a"}) {
	$alltablesflag = "Yes";
}
# Check if result needs to run only over new tables
if (defined $options{"n"}) {
	$newtabledate = $options{"n"};
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

if ($alltablesflag eq "Yes") {
	@table_arr = get_all_tables();
	if (scalar @table_arr == 1) {
		exit_application(1);
	}
}

if (defined $newtabledate) {
	@table_arr = get_new_tables($newtabledate);
	if (scalar @table_arr == 1) {
		exit_application(1);
	}
}

# Make database connection
my $connectionstring = "DBI:mysql:database=$databasename;host=$server;port=$port";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

# Handle all tables in array
foreach my $tablename (@table_arr) {
	trace("Table $tablename");
	my $sql = "UPDATE $tablename 
						SET SizeUsedMB=CAST(SizeUsedMB/1048576 AS DECIMAL(11,2)), 
						    AllocatedMB=CAST(AllocatedMB/1048576 AS DECIMAL(11,2))";
	my $rows_affected = $dbh->do($sql);
	if (defined $rows_affected) {
		trace("$rows_affected rows updated");
	} else {
		error("SQL Error with $sql, ".$dbh->errstr);
		exit_application(1);
	}
}

exit_application(0);

=head1 To Do

=over 4

=item *

Nothing for now...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
