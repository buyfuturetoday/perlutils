=head1 NAME

S3_ComponentenPerSite - Find the number of Components per site

=head1 VERSION HISTORY

version 1.1 19 September 2003 DV

=over 4

=item *

Limit the number of Components per site to Server only

=back

version 1.0 18 September 2003 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application extracts the unique site code, then find all the locations per site and then find all the components per location. The number of components is accumulated per site and provided in an csv file.

=head1 SYNOPSIS

S3_ComponentenPerSite.pl [-t] [-l log_dir] [-d DSN_string] [-o outputfile.csv]

    S3_ComponentenPerSite -h	    Usage
    S3_ComponentenPerSite -h 1	    Usage and description of the options
    S3_ComponentenPerSite -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\opex\log

=item B<-d DSN_string>

DSN string that allows the ODBC connection to the database. Example B<DSN=OPEX;UID=sa;PWD=>

=item B<-o outputfile>

Outputfile, containing all the SQL statements to insert the data. Default B<c:\temp\I<sites.csv>>

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.8.0, build 804 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my $logdir;
my $dbase = "S3"; # ODBC Connection name to OPEX database
my ($dbconn_site,$dbconn_loc,$dbconn_gencomp,$dbconn_gc_ls);
my ($omschrijving,$gc_count);
my (%componenten,$site_code,$gemeente,$naam,%lsid_hash,$cluster);
my ($gcid,$gctypeid,$locid,$lsid,$ls_naam,$sla_level_id,$pf_naam,$specification);
my $outputfile = "c:/temp/Master.csv";
my $site_table="informix_tp_site";
my $loc_table="informix_td_location";
my $gencomp_table="informix_td_gencomp";
my $gctype_table="informix_tp_gctype";
my $gc_ls_table="informix_tr_gc_ls";
my $logserv_table="informix_td_logserv";
my $platform_table="informix_td_platform";

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use Log;			    # Application and error logging
use Win32::ODBC;		    # Allow ODBC Connection to database

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
    if (defined($dbconn_site)) {
	$dbconn_site->Close();
	trace("Close site database connection");
    }
    if (defined($dbconn_loc)) {
	$dbconn_loc->Close();
	trace("Close location database connection");
    }
    if (defined($dbconn_gencomp)) {
	$dbconn_gencomp->Close();
	trace("Close gencomp database connection");
    }
    if (defined($dbconn_gc_ls)) {
	$dbconn_gc_ls->Close();
	trace("Close gc_ls database connection");
    }
    close OUTPUTFILE;
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

=head2 SQL query

Accepts a database handle and a query, executes the request and make the data available for processing.

=cut

sub SQLquery($$) {
  my($db, $query) = @_;
  trace("$db, $query");
  if ($db->Sql($query)) {
    my ($errnum, $errtext, $errconn) = $db->Error();
    error("SQL Error: $errnum $errtext $errconn");
    error($query);
    exit_application(1);
  }
}

=pod

=head2 Initialise Components

Load the gctype table into a hash for quick, easy and convenient access. Limit the number of components to investigate to "server" only.

=cut

sub init_componenten {
    my $sqlquery="SELECT * FROM $gctype_table";
    SQLquery($dbconn_site,$sqlquery);
    while($dbconn_site->FetchRow()) {
	my %gctype_record=$dbconn_site->DataHash();
	my $gctypeid=$gctype_record{gctypeid};
	my $omschrijving=$gctype_record{omschrijving};
	my $naam=$gctype_record{naam};
	if ($naam eq 'server') {
	    $componenten{$gctypeid}=$omschrijving;
	}
    }
}

=pod

=head2 Handle Logical Server

Generic components build up a logical server. Find the logical server for this generic component, find the SLA level associated with this logical server, find the platform name and the version number (OS and version number). Also keep track if this logical component has been selected before, in which case this is part of a cluster.

=cut

sub handle_logical_server {
    # initialize field names...
    $lsid="unknown";
    $cluster="";
    $sla_level_id="unknown";
    $ls_naam="unknown";
    $pf_naam="unknown";
    $specification="unknown";
    my $sqlquery="SELECT lsid FROM $gc_ls_table WHERE gcid=$gcid";
    SQLquery($dbconn_gc_ls,$sqlquery);
    # There should be only one ls for multiple gc
    if ($dbconn_gc_ls->FetchRow()) {
	my %gc_ls_record=$dbconn_gc_ls->DataHash();
	$lsid=$gc_ls_record{lsid};
	if (exists($lsid_hash{$lsid})) {
	    $cluster="cluster";
	} else {
	    $lsid_hash{$lsid}=1;
	}
	# Find the SLA level and logical name for this device
	$sqlquery="SELECT sla_level_id, naam FROM $logserv_table WHERE lsid=$lsid";
	SQLquery($dbconn_gc_ls,$sqlquery);
	if ($dbconn_gc_ls->FetchRow()) {
	    my %gc_ls_record=$dbconn_gc_ls->DataHash();
	    $sla_level_id=$gc_ls_record{sla_level_id};
	    $ls_naam=$gc_ls_record{naam};
	    # Find Platform name and specification for the device
	    # Look for platformtype_id=1 as this is the Operating System
	    $sqlquery="SELECT pf_naam,specification FROM $platform_table WHERE lsid=$lsid AND platformtype_id=1";
	    SQLquery($dbconn_gc_ls,$sqlquery);
	    if ($dbconn_gc_ls->FetchRow()) {
		my %gc_ls_record=$dbconn_gc_ls->DataHash();
		$pf_naam=$gc_ls_record{pf_naam};
		$specification=$gc_ls_record{specification};
	    } else {
		error("No Platform naam - Specificatie gevonden voor lsid $lsid");
	    }
	} else {
	    error ("No SLA-Naam record for lsid $lsid");
	}
    } else {
	error("No lsid for gcid $gcid");
    }
    print OUTPUTFILE "$site_code;$gemeente;$naam;$componenten{$gctypeid};$lsid;$cluster;$sla_level_id;$ls_naam;$pf_naam;$specification\n";
}

=pod

=head2 Process Locations

Find all locations for a site. For each location, find the different components and count the different components if the component is a server. Add the calculated number to the total number for this site. Print the result when all locations for the site are handled.

=cut

sub process_locations {
    my %comps_total;
    # Find any location per site
    my $sqlquery = "SELECT locid FROM $loc_table WHERE site_code=\'$site_code\'";
    SQLquery($dbconn_loc, $sqlquery);
    while ($dbconn_loc->FetchRow()) {
        my %loc_record = $dbconn_loc->DataHash();
	$locid = $loc_record{locid};
	# For each location, find all components
	$sqlquery="SELECT gcid,gctypeid FROM $gencomp_table WHERE locid=$locid";
	SQLquery($dbconn_gencomp, $sqlquery);
	while ($dbconn_gencomp->FetchRow()) {
	    my %gencomp_record=$dbconn_gencomp->DataHash();
	    $gcid=$gencomp_record{gcid};
	    $gctypeid=$gencomp_record{gctypeid};
	    if (exists($componenten{$gctypeid})) {
		handle_logical_server;
	    }
	}
    }
}


=pod

=head2 Process Sites

Select all site codes from the table tp_site. For each site, check if there is a "gemeente" and a "naam" available. If so, call the procedure to process all locations at this site. Otherwise, print an error message.

=cut

sub process_sites {
    my $sqlquery = "SELECT site_code, gemeente, naam FROM $site_table";
    SQLquery($dbconn_site, $sqlquery);
    while ($dbconn_site->FetchRow()) {
	my %record =$dbconn_site->DataHash();
	$site_code = $record{site_code};
	$gemeente  = $record{gemeente};
	$naam      = $record{naam};
	if (not(defined $gemeente)) {
	    error("$site_code - gemeente niet gedefinieerd");
	} elsif (not(defined $naam)) {
	    error("$site_code - naam niet gedefinieerd");
	} else {
	    process_locations;
	}
    }
}


######
# Main
######

# Handle input values
my %options;
getopts("tl:d:o:", \%options) or pod2usage(-verbose => 0);
# No arguments are required
#my $arglength = scalar keys %options;  
#if ($arglength == 0) {			# If no options specified,
#   $options{"h"} = 0;			# display usage.
#}
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
}
if (-d $logdir) {
    trace("Logdir: $logdir");
} else {
    pod2usage(-msg     => "Cannot find log directory $logdir",
	      -verbose => 0);
}
# Logdir found, start logging
open_log();
# Find output file name
if ($options{"o"}) {
    $outputfile = $options{"o"};
}
logging("Start application");
# Find DSN Connection string
if ($options{"d"}) {
    $dbase = $options{"d"};
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Create Site Database Connection
undef $dbconn_site;		    # Undef $dbconn for proper exit_application
if (not($dbconn_site = new Win32::ODBC($dbase))) {
    error("DSN string: $dbase");
    error("Open failed: ".Win32::ODBC::Error());
    exit_application(1);
}

# Create Location Database Connection
undef $dbconn_loc;		    # Undef $dbconn for proper exit_application
if (not($dbconn_loc = new Win32::ODBC($dbase))) {
    error("DSN string: $dbase");
    error("Open failed: ".Win32::ODBC::Error());
    exit_application(1);
}

# Create Gencomp Database Connection
undef $dbconn_gencomp;		    # Undef $dbconn for proper exit_application
if (not($dbconn_gencomp=new Win32::ODBC($dbase))) {
    error("DSN string: $dbase");
    error("Open failed: ".Win32::ODBC::Error());
    exit_application(1);
}

# Create gc_ls Database Connection
undef $dbconn_gc_ls;		    # Undef $dbconn for proper exit_application
if (not($dbconn_gc_ls=new Win32::ODBC($dbase))) {
    error("DSN string: $dbase");
    error("Open failed: ".Win32::ODBC::Error());
    exit_application(1);
}

# Open the *.csv file for output
my $open_res=open(OUTPUTFILE, ">$outputfile");
if (not(defined $open_res)) {
    error("Could not open $outputfile for output, exiting...");
    exit_application(1);
}

# Initialise Components hash for quicker and easier access
init_componenten;

# Process all sites
process_sites;

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Split-up the different queries in different subroutines.

=item *

Add a title line to the csv file, change the order of the columns?

=item *

Add all master data into a master table instead of a spreadsheet - This allows easier processing.

=item *

From the master table: read line by line and find the different HW/SW combinations. Result: file with all the different possibilities.

=item *

Read the different HW/SW combinations, add to a hash and determine how many occurences per site from the master table.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
