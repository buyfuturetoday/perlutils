=head1 NAME

S3_SiteGemeenteNaam - Extract the site - Gemeente - Naam information from the S3 database

=head1 VERSION HISTORY

version 1.1 22 September 2003 DV

=over 4

=item *

Extend the output with additional information like straat, nummer, ...

=back

version 1.0 16 September 2003 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application extracts the unique sitecode - gemeente - naam information from the tp_site database, and provides the information to a *.csv file.

=head1 SYNOPSIS

S3_SiteGemeenteNaam.pl [-t] [-l log_dir] [-d DSN_string] [-o outputfile.csv]

    S3_SiteGemeenteNaam -h	    Usage
    S3_SiteGemeenteNaam -h 1	    Usage and description of the options
    S3_SiteGemeenteNaam -h 2	    All documentation

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
my ($dbconn,$outputfile);
my $table="informix_tp_site";

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
    if (defined($dbconn)) {
	$dbconn->Close();
	trace("Close database connection");
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
    exit_application(1);
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
} else {
    $outputfile = "c:/temp/sites.csv";
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

# Create Database Connection
undef $dbconn;		    # Undef $dbconn for proper exit_application
if (not($dbconn = new Win32::ODBC($dbase))) {
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

# Process all data in the table
my $sqlquery = "SELECT site_code, gemeente, naam, straat, huisnr, postcode FROM $table";
SQLquery($dbconn, $sqlquery);
while ($dbconn->FetchRow()) {
    my %record =$dbconn->DataHash();
    my $site_code = $record{site_code};
    my $gemeente  = $record{gemeente};
    my $naam      = $record{naam};
    my $straat	  = $record{straat};
    my $huisnr    = $record{huisnr};
    my $postcode  = $record{postcode};
    if (not(defined $gemeente)) {
	error("$site_code - gemeente niet gedefinieerd");
    } elsif (not(defined $naam)) {
	error("$site_code - naam niet gedefinieerd");
    } else {
	print OUTPUTFILE "$site_code;$naam;$straat;$huisnr;$postcode;$gemeente\n";
    }
}

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Nothing for the moment...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
