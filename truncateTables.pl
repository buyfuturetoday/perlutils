=head1 NAME

truncateTables - This script will truncate tables

=head1 VERSION HISTORY

version 1.0 9 June 2007 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will truncate listed tables from MySQL database.

=head1 SYNOPSIS

truncateTables.pl [-t] [-l log_dir]

    truncateTables.pl -h	 Usage
    truncateTables.pl -h 1   Usage and description of the options
    truncateTables.pl -h 2   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: c:\temp. Logging is enabled by default. 

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.8.0, build 804 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $dbh);
my $databasename="Events";
my $server="localhost";
my $username="root";
my $password="Monitor1";
my $printerror=0;
my @table_array = ("strevents",
	               "openevents");

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use Log;
use DBI();

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if (defined $dbh) {
		$dbh->disconnect;
	}
    logging("Exit application with return code: $return_code\n");
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
getopts("h:tl:", \%options) or pod2usage(-verbose => 0);
# my $arglength = scalar keys %options;  
# print "Arglength: $arglength\n";
# if ($arglength == 0) {			# If no options specified,
#     $options{"h"} = 0;			# display usage.
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
# Log required?
if (defined $options{"n"}) {
    log_flag(0);
} else {
    log_flag(1);
    # Log required, so verify logdir available.
    if ($options{"l"}) {
		$logdir = logdir($options{"l"});
    } else {
		$logdir = logdir();
    }
    if (-d $logdir) {
		trace("Logdir: $logdir");
    } else {
		pod2usage(-msg     => "Cannot find log directory ".logdir,
		 		  -verbose => 0);
    }
}
# Logdir found, start logging
open_log();
logging("Start application");
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input value

# Make database connection
my $connectionstring = "DBI:mysql:database=$databasename;host=$server";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

foreach my $tablename (@table_array) {
	my $sql = "truncate $tablename";
	my $trunc_result = $dbh->do($sql);
	if (defined $trunc_result) {
		logging("$tablename truncated");
	 } else {
		error("Failed to truncate table $tablename");
	}
}

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Accept parameter to specify output file (and directory).

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
