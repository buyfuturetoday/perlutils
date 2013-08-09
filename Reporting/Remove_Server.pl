=head1 NAME

Remove_Server.pl - This script allows to remove specific servers from the SysUpTime file so that they do no longer show up in the Availability report.

=head1 VERSION HISTORY

version 1.1 28 November 2002 DV

=over 4

=item *

Display the number of records deleted.

=back

version 1.0 27 November 2002 DV

=over 4

=item *

Initial Release.

=back

=head1 DESCRIPTION

This script is a temporary solution that allows to delete specific servers from the SysUpTime file. As a result, this servers will no longer show up in the Availability SPI reporting. This script should be replaced by a function in the SPI Review processing.

Deleting servers from the SysUpTime table is one of the actions that can help to restore thrust in the automatic SPI collection.

=head1 SYNOPSIS

Remove_Server [-t] [-l log_dir] -s smc_location_id -d device_name

    Remove_Server -h	    Usage
    Remove_Server -h 1    Usage and description of the options
    Remove_Server -h 2    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: c:\temp

=item B<-s smc_location_id>

Number, specifying the SMC Location ID. (2: Netherlands, 3: UK, 4: France, 5: Germany, 7: Switzerland, 8: Nordic)

=item B<-d device_name>

Device name that must be removed from the SYSUPTIME table.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.6.1, build 631 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that the proper directories are mentioned.

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
###########

my $logdir;			# Log file directory
my $dsource="SXEMEA";		# ODBC Database source
my ($smc, $hostname, $customer_code, $spidb, $query, $connection);

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
use Win32::ODBC;

#############
# subroutines
#############

sub exit_application($) {
    my($return_code) = @_;
    if (defined $spidb) {
	$spidb->Close;
	logging("Close database connection spidb");
    }
    logging("Exit application with return code $return_code\n");
    close_log();
    exit $return_code;
}

sub SQLquery($$) {
  my($db, $query) = @_;
  if ($db->Sql($query)) {
    my ($errnum, $errtext, $errconn) = $db->Error();
    error("$errnum.$errtext.$errconn\n$query\n$db");
    exit_application(1);
  }
}

######
# Main
######

# Handle input values

my %options;
getopts("tl:s:d:h:", \%options) or pod2usage(-verbose => 0);
my $arglength = scalar keys %options;  
if ($arglength == 0) {			# If no options specified,
    $options{"h"} = 0;			# display usage.
}
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
    trace_flag(1);
    trace("Trace enabled");
}
# Find log file directory
if ($options{"l"}) {
    $logdir = logdir($options{"l"});
}
$logdir = logdir();
if (-d $logdir) {
    trace("Logdir: $logdir");
} else {
    pod2usage(-msg     => "Cannot find log directory ".logdir,
	      -verbose => 0);
}
# Logdir found, start logging
open_log();
logging("Start application");
# Find SMC Location ID
if ($options{"s"}) {
    $smc = $options{"s"};
} else {
    error("No SMC Location ID defined...");
    exit_application(1);
}
# Find hostname
if ($options{"d"}) {
    $hostname = $options{"d"};
} else {
    error("No hostname defined...");
    exit_application(1);
}
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Create database connections
if (!($spidb = new Win32::ODBC("DSN=$dsource;UID=sa;PWD="))) {
    error("Cannot open database spidb (Data Source: $dsource)");
    exit_application(1);
} else {
    $connection = $spidb->Connection();
    logging("Connected to $dsource on connection number $connection");
}

=pod

=head2 Remove Server from the SysUpTime file

Look up the configuration_id for the specified server in the CONFIGURATION table.

If found then log the records to be deleted and then delete this smc_location_id/configuration_id from the SYSUPTIME table. 

Delete the records also from the MEASUREMENTS table, since this table is used for UP/DOWN events calculations.

=cut

$query = "SELECT configuration_id, customer_code
	  FROM CONFIGURATION 
	  WHERE hostname=\'$hostname\' 
		and smc_location_id=$smc";
SQLquery($spidb, $query);
if ($spidb->FetchRow()) {
    my %recordhash = $spidb->DataHash();
    my $configuration_id = $recordhash{"configuration_id"};
    my $customer_code = $recordhash{"customer_code"};
    $query = "SELECT *
		FROM SYSUPTIME
		WHERE smc_location_id = $smc and
		      configuration_id = $configuration_id";
    SQLquery($spidb,$query);
    while ($spidb->FetchRow()) {
	my %recordhash = $spidb->DataHash();
	my $datum = $recordhash{"datum"};
	my $uptime = $recordhash{"uptime"};
	my $downtime = $recordhash{"downtime"};
	logging "$datum - $uptime - $downtime - $customer_code\n";
    }
    $query = "DELETE
		FROM SYSUPTIME
		WHERE smc_location_id = $smc and
		      configuration_id = $configuration_id";
    SQLquery($spidb,$query);
    my $nr_deleted = $spidb->RowCount($connection);
    logging("$nr_deleted records deleted from the SYSUPTIME table");
    print "$nr_deleted records deleted from the SYSUPTIME table\n";
    $query = "DELETE
		FROM MEASUREMENTS
		WHERE smc_location_id = $smc and
		      configuration_id = $configuration_id";
    SQLquery($spidb,$query);
    $nr_deleted = $spidb->RowCount($connection);
    logging("$nr_deleted records deleted from the MEASUREMENTS table");
    print "$nr_deleted records deleted from the MEASUREMENTS table\n";
}

exit_application(0);

=pod

=head1 TO DO

=over 4

=item * 

Nothing for the moment...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
