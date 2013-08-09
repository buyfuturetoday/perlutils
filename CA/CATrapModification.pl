=head1 NAME

CATrapModification - Script to modify the CA Trap messages in the Trap Translation database.

=head1 VERSION HISTORY

version 1.0 27 May 2005 DV

=over 4

=item *

Initial Release based on the DirectoryAnalyzer DATrapModification.pl script.

=back

=head1 DESCRIPTION

Using the standard mib file and the Unicenter Trap Editor, there is a need to identify the Class of the Traps.

All messages in the event management console have the format "%CATD_I_066, trapname: values. The only unique string is B<%CATD_I_066> which is not sufficient to distinguish between the origin of the traps. This script allows to configure a class name as the first part in the trap message.

Note that no function is available to replace an existing Event class name with another event class name. In this case the original mib file (without the event class) needs to be loaded into the database and this script needs to run to implement the required event class name.

=head1 SYNOPSIS

 CATrapModification [-t] [-l log_dir] [-d datasource] -m mibname -c classname

    CATrapModification -h	    Usage
    CATrapModification -h 1	    Usage and description of the options
    CATrapModification -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: c:\temp

=item B<-d datasource>

The data source name pointing to the CA Trap database. Default: CAITRPDB, the data source name requested for the Unicenter Trap Editor. 

=item B<-m mibname>

Mandatory, the mibname for which the Event Class name must be added.

=item B<-c classname>

Mandatory, the Event Class name to add to the Alarmname.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.8.3, build 809 provided by ActiveState.

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $classname, $mibname, $trapdb, $trapdb_upd);
my $dsource = "CAITRPDB";		    # Data source name

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
use Log;			    # Log module

#############
# subroutines
#############

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

Read all records for the Enterprise OID for the specified MIB. Check if class name is part of the alarmname. If so, then the record in the Trap DB has been updated already. If not, then add the class name before the Trap message. Update the record for the Enterprise ID and the specific trap.

The assumption is that the MibName / Specific field combination is unique, as well as the Eid / Specific field combination.

=cut

sub handle_records() {
    my $nr_records = 0;
    SQLquery($trapdb, "SELECT Specific, AlarmName, Eid
			 FROM cadb.TRAP 
			 WHERE MibName = \'$mibname\'");
    while ($trapdb->FetchRow()) {
	my %recordhash = $trapdb->DataHash();
	my $specific  = $recordhash{"Specific"};
	my $alarmname = $recordhash{"AlarmName"};
	my $eid       = $recordhash{"Eid"};
	if (index($alarmname, $classname) == -1) {
	    $alarmname = $classname . " " . $alarmname;
	    logging("Updating $mibname, $eid, $specific new value: $alarmname.");
	    SQLquery($trapdb_upd, "UPDATE cadb.TRAP
				    SET AlarmName = \'$alarmname\' 
				    WHERE Eid = \'$eid\' and
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
getopts("tl:d:m:c:h:", \%options) or pod2usage(-verbose => 0);
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
} else {
    $logdir = logdir();
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
# Find mibname
if ($options{"m"}) {
    $mibname = $options{"m"};
} else {
    error("Mibname not defined, exiting ...");
    exit_application(1);
}
# Find classname
if ($options{"c"}) {
    $classname = $options{"c"};
} else {
    error("Classname not defined, exiting ...");
    exit_application(1);
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

Nothing for the now ...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
