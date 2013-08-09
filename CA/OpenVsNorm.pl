=head1 NAME

OpenVsNorm - This script compares OPEN vs HANDLE escalation events.

=head1 VERSION HISTORY

version 1.1 24 July 2007 DV

=over 4

=item *

Add check on agent names in OPEN events, to make a note on all unexpected events.

=back

version 1.0 20 July 2007 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application compares OPEN vs HANDLE escalation events. Input is the *.csv file for the LogPlayer.pl application. Make sure that the strevents table and the openevents table are empty before running LogPlayer.pl to ensure that the results are correct. Also verify that the Event Console log is empty, to make error control easier.

Output is a report with statistics on the different escalation reports, and a summary of deviations.

The output will have yyyymmdd_hhmmss in the filename, to guarantee that files are not overwritten.

=head1 SYNOPSIS

OpenVsNorm.pl [-t] [-l log_dir] [-i conlog.csv] [-d outputdirectory]

    OpenVsNorm.pl -h	 Usage
    OpenVsNorm.pl -h 1   Usage and description of the options
    OpenVsNorm.pl -h 2   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: c:\temp. Logging is enabled by default. 

=item B<-i conlog.csv>

Console log in flat file format. The filename is extracted and added as first part of the output file name. This method allows to create unique output file names per conlog.csv test file. 

=item B<-d outputdirectory>

Output directory for the report file.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.8.0, build 804 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $dbh, $class, $handleval, $openval, %known_agents, $prepend, $title, $mySql);
my $databasename="Events";
my $server="localhost";
my $username="root";
my $password="Monitor1";
my $printerror=0;
my $report_file = "OpenVsNorm.txt";
my $report_directory = "c:/temp/mra";
my @known_agents_array = ("WebResponse",
						  "CaiUxOs",
						  "caiLogA2",
						  "Agent",
						  "EventManagement",
						  "caiW2kOs",
						  "Informix",
						  "Oracle",
						  "Ping",
						  "MSEXCHANGE",
						  "caiNt4Os",
					  	  "AgentVerification");

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
use File::Basename;

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if (defined $dbh) {
		$dbh->disconnect;
	}
	close Report;
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

=pod

=head2 Handle SQLQuery

This procedure handles the SQL query in two different ways. If a title has been specified, then the result set of the SQL query is printed to a report. 
Otherwise, the SQL query returns the first value from the first record (as a counter) that can be used for further processing. 

=cut

sub handle_sqlquery {
	my ($mySql,$title) = @_;
	my $retvalue;
	my $mySth = $dbh->prepare($mySql);
	if (not defined $mySth) {
		error("Cannot prepare statement $mySql");
		exit_application(1);
	}
	$mySth->execute;
	if (defined $mySth->err) {
		error("Error while executing $mySql:\n".$mySth->errstr);
		exit_application(1);
	}
	if (defined $title) {
		# Print result to Report
		print Report $title."\n\n";
		while (my @returndata = $mySth->fetchrow()) {
			print Report join(" * ",@returndata),"\n";
		}
		print Report "\n\n";
	} else {
		if (my @returndata = $mySth->fetchrow()) {
			$retvalue = shift @returndata;
			if (not defined $retvalue) {
				error("No valid result for $mySql");
			} elsif (not($retvalue =~ /^\d+$/)) {
				error("No numeric value returned from $mySql");
			}
		} else {
			error("No result line from $mySql");
		}
	}
	$mySth->finish;
	return $retvalue;
}

=pod

=head2 Handle OpenQuery

This procedure handles the SQL query for the OPEN table. Each agent value is checked to understand if it is known already. If not, then an error message is displayed and printed in the report to notify about the new agent that requires verification.

=cut

sub handle_openquery {
	my ($mySql,$title) = @_;
	my $retvalue;
	my $mySth = $dbh->prepare($mySql);
	if (not defined $mySth) {
		error("Cannot prepare statement $mySql");
		exit_application(1);
	}
	$mySth->execute;
	if (defined $mySth->err) {
		error("Error while executing $mySql:\n".$mySth->errstr);
		exit_application(1);
	}
	if (defined $title) {
		# Print result to Report
		print Report $title."\n\n";
		while (my @returndata = $mySth->fetchrow()) {
			print Report join(" * ",@returndata),"\n";
			my $agent_val = $returndata[0];
			if (not defined $known_agents{$agent_val}) {
				my $repmsg = "Unexpected agent value $agent_val found, please investigate!";
				error($repmsg);
				print Report $repmsg."\n";
			}
		}
		print Report "\n\n";
	}
	$mySth->finish;
	return $retvalue;
}

sub compare_vals($$$) {
	my ($comp_class,$handleval,$openval) = @_;
	# better make sure both variables are numeric
	if ($handleval == $openval) {
		print Report "Class: $comp_class Test OK ($handleval records)\n";
	} else {
		print Report "Class: $comp_class Test Failed, HANDLE: $handleval; OPEN: $openval\n";
		error("Class: $comp_class Test Failed, HANDLE: $handleval; OPEN: $openval");
	}
}

######
# Main
######

# Handle input values
my %options;
getopts("h:tl:i:d:", \%options) or pod2usage(-verbose => 0);
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
# Conlog Filename used to create output filename
if (defined $options{"i"}) {
	($prepend, undef) = split(/\./, basename($options{"i"}));
} else {
	$prepend = "";
}
# Output directory
if (defined $options{"d"}) {
	$report_directory = $options{"d"};
}
if (not (-d $report_directory)) {
	error("Report output directory $report_directory does not exist, exiting...");
	exit_application(1);
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input value

# Convert array to hash for easier reference
foreach my $value (@known_agents_array) {
	$known_agents{$value} = 1;
}

# Make database connection
my $connectionstring = "DBI:mysql:database=$databasename;host=$server";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my $currentDateTime = sprintf("%02d-%02d-%04d %02d:%02d:%02d", $mday, $mon+1, $year+1900, $hour, $min, $sec);
my $report_dt = sprintf("%04d%02d%02d%02d%02d%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec);
$report_file = $prepend . "_" . $report_dt . "_" . $report_file;

# Open output file for report
my $report_filename = "$report_directory/$report_file";
my $openres = open(Report, ">$report_filename");
if (not defined $openres) {
	error("Couldn't open $report_filename for writing, exiting...");
	exit_application(1);
}


print Report "Report generated at $currentDateTime\n\n";

# HANDLE Escalation Events - Total
$title = "HANDLE Escalation Events - Total";
$mySql = "SELECT count( * ) FROM strevents";
$handleval = handle_sqlquery($mySql);
print Report "$title: $handleval\n\n";

# HANDLE Escalation Events per agent
$title = "HANDLE Escalation Events per agent";
$mySql = "SELECT source, count( * ) FROM strevents 
				GROUP BY source 
				ORDER BY count( * ) DESC";
handle_sqlquery($mySql,$title);

# OPEN Escalation Events - Total
$title = "OPEN Escalation Events - Total";
$mySql = "SELECT count( * ) FROM openevents";
$openval = handle_sqlquery($mySql);
print Report "$title: $openval\n\n";

# OPEN Escalation Events per agent
$title = "OPEN Escalation Events per agent";
$mySql = "SELECT agent, count( * ) FROM openevents 
				GROUP BY agent 
				ORDER BY count( * ) DESC";
handle_openquery($mySql,$title);

# caiW2kOs Events 
$class = "caiW2kOs";
# from HANDLE
$mySql = "SELECT count(*) from strevents
				WHERE source='$class'
				AND (NOT (newstate = 'LINK-DOWN'))";
$handleval = handle_sqlquery($mySql);
# from OPEN
$mySql = "SELECT count(*) from openevents
				WHERE agent = '$class'";
$openval = handle_sqlquery($mySql);
compare_vals($class,$handleval,$openval);

# caiUxOs Events 
$class = "caiUxOs";
# from HANDLE
$mySql = "SELECT count(*) from strevents
				WHERE source='$class'
				AND (NOT (newstate = 'LINK-DOWN'))";
$handleval = handle_sqlquery($mySql);
# from OPEN
$mySql = "SELECT count(*) from openevents
				WHERE agent = '$class'";
$openval = handle_sqlquery($mySql);
compare_vals("$class, Test 1/2",$handleval,$openval);

# caiUxOs Events, excluding oldstate
$mySql = "SELECT count(*) from openevents
				WHERE agent = '$class'
				AND Text LIKE '%/tmp'";
my $spec_openval = handle_sqlquery($mySql);
compare_vals("caiUxOs, without messages about /tmp (Test 2/2)",$handleval,$openval-$spec_openval);

# caiNt4Os Events 
$class = "caiNt4Os";
# from HANDLE
$mySql = "SELECT count(*) from strevents
				WHERE source='$class'
				AND (NOT (newstate = 'LINK-DOWN'))";
$handleval = handle_sqlquery($mySql);
# from OPEN
$mySql = "SELECT count(*) from openevents
				WHERE agent = '$class'";
$openval = handle_sqlquery($mySql);
compare_vals($class,$handleval,$openval);

# exchagent Events 
$class = "exchagnt";
# from HANDLE
$mySql = "SELECT count(*) from strevents
				WHERE source='$class'
				AND (NOT (newstate = 'LINK-DOWN'))";
$handleval = handle_sqlquery($mySql);
# from OPEN
$mySql = "SELECT count(*) from openevents
				WHERE agent = 'MSEXCHANGE'";
$openval = handle_sqlquery($mySql);
compare_vals($class,$handleval,$openval);

# caiLogA2 Events 
$class = "caiLogA2";
# from HANDLE
$mySql = "SELECT count(*) from strevents
				WHERE source='$class'
				AND (NOT (newstate = 'LINK-DOWN'))";
$handleval = handle_sqlquery($mySql);
# from OPEN
$mySql = "SELECT count(*) from openevents
				WHERE agent = '$class'";
$openval = handle_sqlquery($mySql);
compare_vals($class,$handleval,$openval);

# caiOraA2 Events 
$class = "caiOraA2";
# from HANDLE
$mySql = "SELECT count(*) from strevents
				WHERE source='$class'
				AND (NOT (newstate = 'LINK-DOWN'))";
$handleval = handle_sqlquery($mySql);
# from OPEN
$mySql = "SELECT count(*) from openevents
				WHERE agent = 'Oracle'";
$openval = handle_sqlquery($mySql);
compare_vals($class,$handleval,$openval);

# ImxAgent Events 
$class = "ImxAgent";
# from HANDLE
$mySql = "SELECT count(*) from strevents
				WHERE source='$class'
				AND (NOT (newstate = 'LINK-DOWN'))";
$handleval = handle_sqlquery($mySql);
# from OPEN
$mySql = "SELECT count(*) from openevents
				WHERE agent = 'Informix'";
$openval = handle_sqlquery($mySql);
compare_vals($class,$handleval,$openval);

# wrm5Agent Events 
$class = "wrm5Agent";
# from HANDLE
$mySql = "SELECT count(*) from strevents
				WHERE source like '$class%'
				AND (NOT (newstate = 'LINK-DOWN'))";
$handleval = handle_sqlquery($mySql);
# from OPEN
$mySql = "SELECT count(*) from openevents
				WHERE agent = 'WebResponse'";
$openval = handle_sqlquery($mySql);
compare_vals($class,$handleval,$openval);

# AgentAbsent Events 
$class = "AgentAbsent";
# from HANDLE
$mySql = "SELECT count(*) from strevents
				WHERE source='$class'";
$handleval = handle_sqlquery($mySql);
# from OPEN
$mySql = "SELECT count(*) from openevents
				WHERE agent = 'EventManagement'";
$openval = handle_sqlquery($mySql);
compare_vals("$class Test 1/2",$handleval,$openval);

# AgentAbsent Events, excluding HTTPScripterrorCount
$mySql = "SELECT count(*) from openevents
				WHERE agent = 'EventManagement'
				AND Text like '%HTTPScripterrorCount%'";
$spec_openval = handle_sqlquery($mySql);
compare_vals("AgentAbsent, without HTTPScripterrorCount (Test 2/2)",$handleval,$openval-$spec_openval);

# Mib-II Events 
$class = "Mib-II";
# from HANDLE
$mySql = "SELECT count(*) from strevents
				WHERE source='$class'";
$handleval = handle_sqlquery($mySql);
# from OPEN
$mySql = "SELECT count(*) from openevents
				WHERE agent = 'Ping'";
$openval = handle_sqlquery($mySql);
compare_vals($class,$handleval,$openval);

# LINK-DOWN Events 
$class = "LINK-DOWN";
# from HANDLE
$mySql = "SELECT count(*) from strevents
				WHERE newstate='$class'";
$handleval = handle_sqlquery($mySql);
# from OPEN
$mySql = "SELECT count(*) from openevents
				WHERE agent = 'Agent'";
$openval = handle_sqlquery($mySql);
compare_vals($class,$handleval,$openval);

# AgentVerification Events 
$class = "AgentVerification";
# from HANDLE
$mySql = "SELECT count(*) from strevents
				WHERE subsource='$class'";
$handleval = handle_sqlquery($mySql);
# from OPEN
$mySql = "SELECT count(*) from openevents
				WHERE agent = '$class'";
$openval = handle_sqlquery($mySql);
compare_vals($class,$handleval,$openval);

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Accept parameter to specify output file (and directory).

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
