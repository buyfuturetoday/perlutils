=head1 NAME

DATrapModification - Script to modify the NetPro DirectoryAnalyzer Trap messages.

=head1 VERSION HISTORY

version 1.0 19 July 2002 DV

=over 4

=item *

Initial Release.

=back

=head1 DESCRIPTION

Using the standard NetPro DirectoryAnalyzer mib file and the Unicenter Trap Editor, the NetPro DirectoryAnalyzer traps translations have two shortcomings.

=over 4

=item 1 Product Identification

All messages in the event management console have the format "%CATD_I_066, trapname: values. The only unique string is B<%CATD_I_066> which is not sufficient to distinguish between NetPro DirectoryAnalyzer traps and traps that originate from other sources. Therefore the trap names will be preceded with "NetProDA".

=item 2 Comma for readability

Although the traps are translated into nice readable messages where values are separated with commas, the Unicenter Event Messages mechanism treats the comma as part of the object name. In stead of removing the comma during the each event message processing, the commas are removed from the message format field.

=back

=head1 SYNOPSIS

 DATrapModification [-t] [-l log_dir] [-d datasource]

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

The data source name pointing to the DirectoryAnalyzer database. Default: TRAPDB, the data source name requested for the Unicenter Trap Editor. 

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
my $dsource = "TRAPDB";		    # Data source name
my $trapdb;			    # Pointer to the CAITRAPDB Database
my $trapdb_upd;			    # Pointer to the CAITRAPDB Database for update
my %site = ();			    # Site Table hash
my $company = "NetProDA";	    # Company trap identifier
my $netproda_eid = "1.3.6.1.4.1.1593.3.3.2.2";	# NetPro DirectoryAnalyzer Enterprise ID

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
    if (defined $trapdb) {
	$trapdb->Close();
	logging("Close Database connection.");
    }
    if (defined $trapdb_upd) {
	$trapdb_upd->Close();
	logging("Close Database connection for update.");
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
    exit();
  }
}

=pod

=head2 Handle Records

Read all records for the Enterprise OID for NetPro DirectoryAnalyzer 1.3.6.1.4.1.1593.3.3.2.2. Check if "NetProDA" is part of the alarmname. If so, then the record in the Trap DB has been updated already. If not, then add NetProDA before the AlarmName and remove commas from the format. Update the record for the Enterprise ID and the specific trap.

=cut

sub handle_records() {
    my $nr_records = 0;
    SQLquery($trapdb, "SELECT Specific, AlarmName, Format 
			 FROM cadb.TRAP 
			 WHERE Eid = \'$netproda_eid\'");
    while ($trapdb->FetchRow()) {
	my %recordhash = $trapdb->DataHash();
	my $specific  = $recordhash{"Specific"};
	my $alarmname = $recordhash{"AlarmName"};
	my $format    = $recordhash{"Format"};
	print "$specific - $alarmname - $format\n";
	if (index($alarmname, $company) == -1) {
	    $alarmname = $company . " " . $alarmname;
	    while (index($format, ",") > -1) {
		my $pos = index($format, ",");
		my $format_first = substr($format, 0, $pos);
		my $format_last  = substr($format, $pos+1, length($format));
		$format = $format_first . $format_last;
	    }
	    logging("Updating Eid=$netproda_eid and specific $specific with $alarmname and $format.");
	    SQLquery($trapdb_upd, "UPDATE cadb.TRAP
				    SET AlarmName = \'$alarmname\', 
				        Format = \'$format\'
				    WHERE Eid = \'$netproda_eid\' and
				          Specific = $specific");
	}    
	$nr_records++;
    }
    logging("$nr_records have been handled.");
}

######
# Main
######

# Handle input values

my %options;
getopts("tl:d:h:", \%options) or pod2usage(-verbose => 0);
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
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Open Handle to read CAITRPDB database
if (!($trapdb = new Win32::ODBC($dsource))) {
    error("Data Source $dsource (CAITRPDB) Open failed: ".Win32::ODBC::Error());
    exit_application(1);
}

# Open Handle to update CAITRPDB database
if (!($trapdb_upd = new Win32::ODBC($dsource))) {
    error("Data Source $dsource (CAITRPDB) Open failed for update: ".Win32::ODBC::Error());
    exit_application(1);
}

handle_records();

exit_application(0);

=pod

=head1 TO DO

=over 4

=item *

Nothing for the moment ...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
