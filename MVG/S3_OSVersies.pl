=head1 NAME

S3_OSVersies - Find the different Operating Systems with version info and number of systems.

=head1 VERSION HISTORY

version 1.0 19 September 2003 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application finds the different Operating Systems, find for each Operating System the different versions and the number of logical systems where the operating system / version is installed.

=head1 SYNOPSIS

S3_OSVersies.pl [-t] [-l log_dir] [-d DSN_string] [-o outputfile.csv]

    S3_OSVersies -h	    Usage
    S3_OSVersies -h 1	    Usage and description of the options
    S3_OSVersies -h 2	    All documentation

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
my ($dbconn_os,$dbconn_versie,$dbconn_sla,@os);
my $outputfile = "c:/temp/OSVersies.csv";
my $platform_table="informix_td_platform";
my $logserv_table="informix_td_logserv";

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
    if (defined($dbconn_os)) {
	$dbconn_os->Close();
	trace("Close OS database connection");
    }
    if (defined($dbconn_versie)) {
	$dbconn_versie->Close();
	trace("Close versie database connection");
    }
    if (defined($dbconn_sla)) {
	$dbconn_sla->Close();
	trace("Close versie database connection");
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

=head2 Find OS

This procedure find the different Operating Systems. Each Operating System is added to an array.

=cut

sub find_os {
    my $sqlquery="SELECT distinct(pf_naam) FROM $platform_table WHERE platformtype_id=1";
    SQLquery($dbconn_os,$sqlquery);
    while($dbconn_os->FetchRow()) {
	my %os_record=$dbconn_os->DataHash();
	my $pf_naam=$os_record{pf_naam};
	push @os, $pf_naam;
    }
}

=pod

=head2 Versions

This procedure finds for all the Operating Systems the different versions and the number of occurences per version.

=cut

sub versions {
    while (my $pf_naam = pop @os) {
	my $sqlquery="SELECT distinct(specification) FROM $platform_table WHERE pf_naam=\'$pf_naam\'";
	SQLquery($dbconn_os,$sqlquery);
	while ($dbconn_os->FetchRow()) {
	    my %sla_count;
	    my %version_record=$dbconn_os->DataHash();
	    my $version=$version_record{specification};
	    # Count number of occurences for this OS / Version
	    my $sqlquery="SELECT lsid FROM $platform_table WHERE pf_naam=\'$pf_naam\' AND specification=\'$version\'";
	    SQLquery($dbconn_versie,$sqlquery);
	    while ($dbconn_versie->FetchRow()) {
		my %lsid_record=$dbconn_versie->DataHash();
		my $lsid=$lsid_record{lsid};
		my $sqlquery="SELECT sla_level_id FROM $logserv_table WHERE lsid=$lsid";
		SQLquery($dbconn_sla,$sqlquery);
		if ($dbconn_sla->FetchRow()) {
		    my %sla_record=$dbconn_sla->DataHash();
		    my $sla=$sla_record{sla_level_id};
		    if (exists($sla_count{$sla})) {
			$sla_count{$sla}++;
		    } else {
			$sla_count{$sla}=1;
		    }
		} else {
		    error ("Could not find sla for lsid $lsid");
		}
	    }
	    while (my($sla,$count)=each %sla_count) {
		print OUTPUTFILE "$pf_naam;$version;$sla;$count\n";
	    }
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

# Create OS Database Connection
undef $dbconn_os;		    # Undef $dbconn for proper exit_application
if (not($dbconn_os = new Win32::ODBC($dbase))) {
    error("DSN string: $dbase");
    error("Open failed: ".Win32::ODBC::Error());
    exit_application(1);
}

# Create Versie Database Connection
undef $dbconn_versie;		    # Undef $dbconn for proper exit_application
if (not($dbconn_versie = new Win32::ODBC($dbase))) {
    error("DSN string: $dbase");
    error("Open failed: ".Win32::ODBC::Error());
    exit_application(1);
}

# Create SLA Database Connection
undef $dbconn_sla;		    # Undef $dbconn for proper exit_application
if (not($dbconn_sla = new Win32::ODBC($dbase))) {
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
# Print title line for the output file
print OUTPUTFILE "OS;versie;sla;aantal\n";

# Find all Operating Systems, add Operating Systems to an array
find_os;

# For each Operating System, find the version and count the number of occurences
versions;

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Nothing for the moment...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
