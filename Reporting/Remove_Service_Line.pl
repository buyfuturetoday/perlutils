=head1 NAME

Remove_Service_Line.pl - This script allows to remove specific service lines from the SysUpTime file so that they do no longer show up in the Availability report.

=head1 VERSION HISTORY

version 1.1 28 November 2002 DV

=over 4

=item *

Add the number of records deleted

=back

version 1.0 27 November 2002 DV

=over 4

=item *

Initial Release.

=back

=head1 DESCRIPTION

This script is a temporary solution that allows to delete specific service lines from the SysUpTime file. As a result, this servers will no longer show up in the Availability SPI reporting. This script should be replaced by a function in the SPI Review processing.

Deleting servers from the SysUpTime table is one of the actions that can help to restore thrust in the automatic SPI collection.

=head1 SYNOPSIS

Remove_Service_Line [-t] [-l log_dir] -s smc_location_id -c sx_client -d service_line -g

    Remove_Service_Line -h	Usage
    Remove_Service_Line -h 1    Usage and description of the options
    Remove_Service_Line -h 2    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: c:\temp

=item B<-s smc_location_id>

Number, specifying the SMC Location ID. (2: Netherlands, 3: UK, 4: France, 5: Germany, 7: Switzerland, 8: Nordic)

=item B<-c sx_client>

Client name as it appears on the dashboard.

=item B<-d service_line>

Number, specifying the service line to be deleted. (687: DSS/Managed WorkPlace, 1772: Hosting/Mainframe, 1773: Hosting/Midrange, 1774: Hosting/WebHosting, 2682: Hosting/Application Hosting)

=item B<-g>

Go-flag! If specified, then the servers will be deleted from the tables, otherwise the servers will be displayed only (for verification).

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
my ($smc, $client, $client_id, $serviceline, $customer_code);
my ($spidb, $spi2db, $spi3db, $query, $connection);
my ($delete_flag, $hostname, $configuration_id);
my $count_devices=0;

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
    if (defined $spi2db) {
	$spidb->Close;
	logging("Close database connection spi2db");
    }
    if (defined $spi3db) {
	$spidb->Close;
	logging("Close database connection spi2db");
    }
    logging("$count_devices devices investigated");
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
getopts("tl:s:c:d:gh:", \%options) or pod2usage(-verbose => 0);
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
# Find client name
if ($options{"c"}) {
    $client = $options{"c"};
} else {
    error("No client defined...");
    exit_application(1);
}
# Find Service Line
if ($options{"d"}) {
    $serviceline = $options{"d"};
} else {
    error("No service line defined...");
    exit_application(1);
}
# Find Delete Flag
if (defined $options{"g"}) {
    $delete_flag="YES";
} else {
    $delete_flag="NO";
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
}
if (!($spi2db = new Win32::ODBC("DSN=$dsource;UID=sa;PWD="))) {
    error("Cannot open database spi2db (Data Source: $dsource)");
    exit_application(1);
}
if (!($spi3db = new Win32::ODBC("DSN=$dsource;UID=sa;PWD="))) {
    error("Cannot open database spi3db (Data Source: $dsource)");
    exit_application(1);
} else {
    $connection = $spi3db->Connection();
    logging("Connected to $dsource on connection $connection");
}

=pod

=head2 Remove Servers from the SysUpTime file for a service line and a specific customer.

Find the client id for a specific client name. Look up all the customer codes for a specific client id.

For each customer code, find all the configuration ids for the specified service line.

If found then delete this smc_location_id/configuration_id from the SYSUPTIME table. 

Delete the records also from the MEASUREMENTS table, since this table is used for UP/DOWN events calculations.

=cut

$query = "SELECT client_id 
	    FROM vw_spi_inquire_client_definition
	    WHERE client_name=\'$client\'";
SQLquery($spidb,$query);
if ($spidb->FetchRow()) {
    my %recordhash = $spidb->DataHash();
    $client_id = $recordhash{"client_id"};
    logging("$client has code $client_id");
} else {
    error("No client id for $client");
    exit_application(1);
}

$query = "SELECT customer_code
	  FROM CUSTOMER_CODE_2_CLIENT_ID
	  WHERE sx_client_id = $client_id";
SQLquery($spidb, $query);
while ($spidb->FetchRow()) {
    my %recordhash = $spidb->DataHash();
    $customer_code = $recordhash{"customer_code"};
    logging("Now handling customer code $customer_code for client $client");
    $query = "SELECT configuration_id, hostname
		FROM CONFIGURATION
		WHERE smc_location_id = $smc and
		    customer_code = \'$customer_code\' and
		    type = $serviceline";
    SQLquery($spi2db,$query);
    while ($spi2db->FetchRow()) {
	my %recordhash = $spi2db->DataHash();
	$configuration_id = $recordhash{"configuration_id"};
	$hostname = $recordhash{"hostname"};
	print "Investigating $hostname ($configuration_id)...\n";
	logging("investigating $hostname ($configuration_id) for removal");
	$count_devices++;
	if ($delete_flag eq "YES") {
	    logging("deleting $hostname ($configuration_id) from SYSUPTIME and MEASUREMENTS");
	    print "deleting $hostname ($configuration_id) from SYSUPTIME and MEASUREMENTS\n";
	    $query = "DELETE
			FROM SYSUPTIME
			WHERE smc_location_id = $smc and
			  configuration_id = $configuration_id";
	    SQLquery($spi3db,$query);
	    my $nr_deleted = $spi3db->RowCount($connection);
	    logging("$nr_deleted records deleted from SYSUPTIME table");
	    print "$nr_deleted records deleted from SYSUPTIME table\n";
	    $query = "DELETE
			FROM MEASUREMENTS
			WHERE smc_location_id = $smc and
			      configuration_id = $configuration_id";
	    SQLquery($spi3db,$query);
	    $nr_deleted = $spi3db->RowCount($connection);
	    print "$nr_deleted records deleted from MEASUREMENTS table\n";
	}
    }
}

print "$count_devices devices investigated\n";
exit_application(0);

=pod

=head1 TO DO

=over 4

=item *

Refuse invalid Service Line types.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
