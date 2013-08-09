=head1 NAME

EscalationReport - Prints a report with the current escalation configuration.

=head1 VERSION HISTORY

version 1.0 27 May 2003 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application prints the current escalation configuration to a report. It starts from the different groupids defined in the groups table. Per group a list of the members, including contact details is printed. Then all objects for which escalation actions are required are printed. 

=head1 SYNOPSIS

EscalationReport.pl [-t] [-l log_dir]

    EscalationReport -h		    Usage
    EscalationReport -h 1	    Usage and description of the options
    EscalationReport -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\opex\log

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
my $dbase = "DSN=OPEX;UID=sa;PWD=";			    # ODBC Connection name to OPEX database
my ($dbgroups,$dbnames,$dbname);

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
    if (defined($dbgroups)) {
	$dbgroups->Close();
	trace("Close database connection");
    }
    if (defined($dbnames)) {
	$dbnames->Close();
	trace("Close database connection");
    }
    if (defined($dbname)) {
	$dbname->Close();
	trace("Close database connection");
    }
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
getopts("tl:h:", \%options) or pod2usage(-verbose => 0);
# my $arglength = scalar keys %options;  
# if ($arglength == 0) {			# If no options specified,
#    $options{"h"} = 0;			# display usage.
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
    Log::display_flag(1);
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
    $logdir = logdir("d:\\opex\\log");
    if (not(defined $logdir)) {
	error("Could not set d:\\opex\\log as Log directory, exiting...");
	exit_application(1);
    }
}
if (-d $logdir) {
    trace("Logdir: $logdir");
} else {
    pod2usage(-msg     => "Cannot find log directory $logdir",
	      -verbose => 0);
}
# Logdir found, start logging
open_log();
logging("Start application");
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Create Database Connection for Groups
undef $dbgroups;
if (not($dbgroups = new Win32::ODBC($dbase))) {
    error("Open failed: ".Win32::ODBC::Error());
    exit_application(1);
}

undef $dbnames;
if (not($dbnames = new Win32::ODBC($dbase))) {
    error("Open failed: ".Win32::ODBC::Error());
    exit_application(1);
}

undef $dbname;
if (not($dbname = new Win32::ODBC($dbase))) {
    error("Open failed: ".Win32::ODBC::Error());
    exit_application(1);
}

# Find the different Group ids
my $sqlquery = "SELECT distinct(groupid) FROM groups";
SQLquery($dbgroups, $sqlquery);
while ($dbgroups->FetchRow()) {
    my %Groupids =$dbgroups->DataHash();
    my $groupid = $Groupids{groupid};
    print "\nGroup: $groupid\n";
    print "******\n";
    $sqlquery = "SELECT name FROM groups WHERE groupid = \'$groupid\'";
    SQLquery($dbnames,$sqlquery);
    while($dbnames->FetchRow()) {
	my %Groups = $dbnames->DataHash();
	my $name = $Groups{name};
	$sqlquery = "SELECT telnum FROM names WHERE name = \'$name\'";
	SQLquery($dbname,$sqlquery);
	if ($dbname->FetchRow()) {  # Extract 1st occurrence of name only
	    my %Telnum = $dbname->DataHash();
	    my $telnum = $Telnum{telnum};
	    if ((defined $telnum) and (length($telnum) > 0)) {
		print "$name (GSM: $telnum)\n";
	# } else {
	        # print "$name\n";
	    }
	} else {
	    error("$name no contact info in Names table");
	}
    }
    print "\nEscalate for objects:\n";
    $sqlquery = "SELECT applid, action FROM decision WHERE groupid = \'$groupid\'";
    SQLquery($dbnames,$sqlquery);
    while($dbnames->FetchRow()) {
	my %Apps = $dbnames->DataHash();
	my $applid = $Apps{applid};
	my $action = $Apps{action};
	# Test if the SendSMS is defined for this applid
	if (($action & 1) == 1) {
	    print "$applid\n";
	}
    }
}

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Obtain database connection information from a file.

=item *

Print objects with an invalid groupid.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
