=head1 NAME

siteconfig - Extract the Site / Server configuration from the DirectoryAnalyzer database.

=head1 VERSION HISTORY

version 1.2 26 July 2002 DV

=over 4

=item *

Resolve issue with master bpv: the top level business process view must have the ManagedObjectRoot (class ManagedObject) as parent. If not then the severity propagation will behave unpredictable.

=back

version 1.1 22 July 2002 DV

=over 4

=item *

Use the Site / Server configuration to create the BPV in WorldView

=back

version 1.0 18 July 2002 DV

=over 4

=item *

Initial Release.

=back

=head1 DESCRIPTION

Active Directory networks are build up of sites. Each site has a number of Domain Controller servers. This script extracts the different sites and the corresponding domain controller servers from the DirectoryAnalyzer database. The output of the script can be used to create the corresponding business process views in the Unicenter WorldView map.

When objects with the same name exist already in the database, then an error message is printed and the object is left unchanged. 

=head1 SYNOPSIS

 siteconfig [-t] [-l log_dir] [-d datasource] [-c BPV_container]

    siteconfig -h	    Usage
    siteconfig -h 1	    Usage and description of the options
    siteconfig -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: c:\temp

=item B<-d datasource>

The data source name pointing to the DirectoryAnalyzer database. Default: DA. 

=item B<-c BPV_container>

The name of the Business Process View that contains the Active Directory container. Default: ActiveDirectory.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.6.1, build 631 provided by ActiveState.

Due to the nature of the problem, the script should only be used on Windows platforms.

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my $trace = 0;			    # 0: no tracing, 1: tracing
my $logdir = "c:/temp";		    # Log file directory
my $log = 1;			    # 0: no logging, 1: logging
my $dsource = "DA";		    # Data source name
my $dadb;			    # Pointer to the DirectoryAnalyzer Database
my %site = ();			    # Site Table hash
my $bpv_master = "ActiveDirectory"; # BPV Master name
my $bpv_master_class = "BusinessView";	# BPV Master class name
my $site_class = "LargeCity";		# Site Class name
my $server_class = "Large_Factory";	# Server Class name
my $site_class = "Application";		# Site Class name
my $server_class = "Application";	# Server Class name

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use File::Basename;		    # logfilename translation
use Win32::ODBC;		    # Win32 ODBC module

#############
# subroutines
#############

sub error($) {
    my($txt) = @_;
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
    print "$datetime - Error: $txt\n";
    logging($txt);
}

sub trace($) {
    if ($trace) {
	my($txt) = @_;
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
	print "$datetime - Trace: $txt\n";
	logging($txt);
    }
}

# SUB - Open LogFile
sub open_log() {
    if ($log == 1) {
	my($scriptname, undef) = split(/\./, basename($0));
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $logfilename=sprintf(">>$logdir/$scriptname%04d%02d%02d.log", $year+1900, $mon+1, $mday);
	open (LOGFILE, $logfilename);
	# open (STDERR, ">&LOGFILE");	    # STDERR messages into logfile
	# Ensure Autoflush for Log file...
	my $old_fh = select(LOGFILE);
	$| = 1;
	select($old_fh);
    }
}

# SUB - Handle Logging
sub logging($) {
    if ($log == 1) {
	my($txt) = @_;
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
	print LOGFILE $datetime." * $txt"."\n";
    }
}

# SUB - Close log file
sub close_log() {
    if ($log == 1) {
	close LOGFILE;
    }
}

sub exit_application($) {
    my($return_code) = @_;
    if (defined $dadb) {
	$dadb->Close();
	logging("Close Database connection.");
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
    $db->Close();
    exit_application(1);
  }
}

=pod

=head2 Create Master BPV

Request to the WorldView repository server for the master bpv object. If the repository server is not running, or the master bpv exists, then exit the application. Otherwise create the master bpv. Include the master bpv into the ManagedObjectRoot object, class ManagedObjectRoot.

=cut

sub create_master_bpv() {
    my $command = "creaobj $bpv_master_class $bpv_master label $bpv_master";
    my $retcode = system ("repclnt $command /q");
    if ($retcode == 0) {
	logging("Master BPV $bpv_master successfully created.");
	my $command = "creaincl $bpv_master_class $bpv_master ManagedObject ManagedObjectRoot";
	my $retcode = system ("repclnt $command /q");
	if (not($retcode == 0)) {
	    error("Could not link $bpv_master into ManagedObjectRoot, Errorcode: $retcode.");
	    exit_application(1);
	}
    } elsif ($retcode == 256) {
	error ("Unicenter Repository Service not active, exiting for now ...");
	exit_application(1);
	# Change to start repserver automatically
    } elsif ($retcode == 65280) {
	error ("Master BPV $bpv_master exists already, exiting ...");
	exit_application(1);
    } else {
	error ("Could not create master BPV $bpv_master, error code: $retcode, exiting ...");
        exit_application(1);
    }
}

=pod

=head2 Collect Sites

In the DirectoryAnalyzer database, the Site table has the site GlobalUID as unique index. The procedure selects all the unique site global uids with the corresponding site names and stores the information into the site hash, with the globalUID as key and the site name as value.

=cut

sub collect_sites() {
    my $nr_sites = 0;
    SQLquery($dadb, "SELECT GlobalUID, Name from Site");
    while ($dadb->FetchRow()) {
	my %recordhash = $dadb->DataHash();
	my $key = $recordhash{"GlobalUID"};
	my $value = $recordhash{"Name"};
	$site{$key} = $value;
	$nr_sites++;
	add_site($value);
    }
    logging("$nr_sites sites have been added");
}

=pod

=head2 Add Site

This procedure will add the site to the Active Directory Business Process View, and link the site into the master Business Process View. The name of the object is the site name as used in the DirectoryAnalyzer database. Currently the label is the same as the name. This may change in the future. 

=cut

sub add_site($) {
    my ($site) = @_;
    my $command = "creaobj $site_class $site label $site";
    my $retcode = system ("repclnt $command /q");
    if ($retcode == 0) {
	logging("Site object $site successfully created.");
	# Link into master bpv
	my $command = "creaincl $site_class $site $bpv_master_class $bpv_master";
	my $retcode = system("repclnt $command /q");
	if ($retcode == 0) {
	    logging("Site object $site successfully linked into $bpv_master.");
	} else {
	    error("Could not link site object $site into $bpv_master.");
	}
    } elsif ($retcode == 256) {
	error ("Unicenter Repository Service not active, exiting for now ...");
	exit_application(1);
	# Change to start repserver automatically
    } elsif ($retcode == 65280) {
	error ("Site object $site exists already, skipping ...");
    } else {
	error ("Could not create site object $site, error code: $retcode, skipping ...");
    }
}

=pod

=head2 Servers in Site

In the DirectoryAnalyzer database, all the domain controller servers are listed with a reference to the site using the SiteGlobalUID field. 

The site hash as constructed in the procedures Collect Sites is scanned for all possible Site Global UIDs. For every site all the corresponding domain controller servers are extracted and printed.

=cut

sub servers_in_site() {
    my $nr_servers = 0;
    foreach my $SiteGlobalUID (keys %site) {
	my $site = $site{$SiteGlobalUID};
	print "\nSite $site: ";
        SQLquery($dadb, "SELECT Name from Server where SiteGlobalUID = \'$SiteGlobalUID\'");
        while ($dadb->FetchRow()) {
	    my %recordhash = $dadb->DataHash();
	    my $server = $recordhash{"Name"};
	    print "$server ";
	    $nr_servers++;
	    add_server($server, $site);
	}
    }
    logging("$nr_servers servers have been added");
}
=pod

=head2 Add Server

This procedure will add the server in the WorldView and link the server into the site in the Active Directory Business Process View. The name of the object is the server name as used in the DirectoryAnalyzer database. Currently the label is the same as the name. This may change in the future. 

=cut

sub add_server($$) {
    my ($server, $site) = @_;
    my $command = "creaobj $server_class $server label $server";
    my $retcode = system ("repclnt $command /q");
    if ($retcode == 0) {
	logging("Server object $server successfully created.");
	# Link into site bpv
	my $command = "creaincl $server_class $server $site_class $site";
	my $retcode = system("repclnt $command /q");
	if ($retcode == 0) {
	    logging("Server object $server successfully linked into $site.");
	} else {
	    error("Could not link server object $server into $site.");
	}
    } elsif ($retcode == 256) {
	error ("Unicenter Repository Service not active, exiting for now ...");
	exit_application(1);
	# Change to start repserver automatically
    } elsif ($retcode == 65280) {
	error ("Server object $server exists already, skipping ...");
    } else {
	error ("Could not create site object $site, error code: $retcode, skipping ...");
    }
}

######
# Main
######

# Handle input values

my %options;
getopts("tl:d:c:h:", \%options) or pod2usage(-verbose => 0);
# my $arglength = scalar keys %options;  
# if ($arglength == 0) {		# If no options specified,
#    $options{"h"} = 0;			# display usage.
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
    $trace = 1;
    trace("Trace enabled");
}
# Find log file directory
if ($options{"l"}) {
    $logdir = $options{"l"};
}
if (-d $logdir) {
    trace("Logdir: $logdir");
} else {
    pod2usage(-msg     => "Cannot find log directory $logdir.",
	      -verbose => 0);
}
# Logdir found, start logging
open_log();
logging("Start application");
# Find data source
if ($options{"d"}) {
    $dsource = $options{"d"};
}
# Find Master BPV
if ($options{"c"}) {
    $bpv_master = $options{"d"};
}
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Open Handle to DirectoryAnalyzer database
if (!($dadb = new Win32::ODBC($dsource))) {
    error("Data Source $dsource (Alert) Open failed: ".Win32::ODBC::Error());
    exit_application(1);
}

# Create Master BPV
create_master_bpv();

# Collect Site information
collect_sites();

# Find the servers per site
servers_in_site();

exit_application(0);

=pod

=head1 TO DO

=over 4

=item *

Add an autoarrange option when creating the BPV master, site and server containers. This will take care of a better looking layout in the WorldView 2D map.

=item *

Add the "list" option to only list the site and server configuration as found in the directoryanalyzer database.

=item *

Add the "test" option to compare the site and server configuration as found in the directoryanalyzer database with the configuration as found in the WorldView Business Process View. List the differences, but do not  update the WorldView.

=item *

Currently only the create of the BPV is done. Add the "synchronize" option, to find out if the site configuration in the WorldView BPV is still in sync with the site configuration in the DA database.

=item *

Currently the configuration is set-up for one domain and one naming context. More advanced configurations, including trees in the domain naming structure will be added as the need and test sites become available.

=item *

Start the repserver service automatically if not running.

=item *

This script will create a business process view with new objects. Site objects will always be new objects. However servers may already be monitored with Unicenter agents. This servers can be linked into the Active Directory Business Process View. This will be done if there is a test site with this need available.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
