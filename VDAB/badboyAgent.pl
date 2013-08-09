=head1 NAME

badboyAgent - This agent script will launch a badboy probe and act on the results.

=head1 VERSION HISTORY

version 1.0 27 July 2009 DV

=over 4

=item *

Initial release

=back

=head1 DESCRIPTION

This application invokes a Badboy Software test plan for application monitoring (http://www.badboy.com.au/).

The results are captured in the script and evaluated. Performance results are added into a database table. The status is written to the monitoring table.

Monitored data is identified by an application name. The application name is the filename of the Badboy plan. The monitoring instance is identified by date and time of monitoring.

Badboy scripts will use engine "MSHTML" and not the RAW engine. My impression is that assertions are not handled well on RAW engine, they do require 'real' internet engine.

Note that you must review the Internet Properties. Check the "Disable Script Debugging (Other)" Option to prevent Script error messages from MSHTML. Also review Page checks and cache settings (to be further documented!).

=head1 SYNOPSIS

badboyAgent.pl [-t] [-l log_dir] [-d] -p badboy_test_plan.bb [-k timeout]

    badboyAgent -h		    Usage
    badboyAgent -h 1	    Usage and description of the options
    badboyAgent -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-d>

If specified then additional debug information will be printed in the logfile.

=item B<-p badboy_test_plan.bb>

The Badboy Software test plan to run in native bb format.

=item B<-k timeout>

Timeout value in seconds for the test plan. jmeter application will be killed if still active after this amount of time. 

Default: 60 seconds.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP SP2, Perl v5.8.8, build 820 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $bbplan, $debugflag, $application, $dbh, @reslines);
my ($msdate, $mstime, $applname);
my $printerror = 0;
my $timeout = 240;
my $bbdir = "e:/Program files/Badboy";
my $status = "OK";
my $errstring = "";

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use File::Basename;			# Used to extract application name from a badboy testplan
use DBI();
use Log;					# Application and error logging
use amParams;

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if (defined $dbh) {
		$dbh->disconnect;
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

=head2 Handle Statistics

Resultlines have been read up to Summary Statistics. Next lines contain valid information for upload.

If command was successful, then exit_application will be called from this procedure. If command was not successful (this means: statistics area not found) then exit_application wil be called from main routine.

=cut

sub handle_statistics() {
	my $assertion = "Check for text \"";
	while (my $line = shift @reslines) {
		# Get rid of \n (CR) on end of line
		chomp($line);
		# Now separate arguments
		# Use ' ' as argument, to remove all whitespaces and tabs between arguments
		my @args = split ' ', $line;
		my $nr_args = @args;
		if (index($line, $assertion) > -1) {
			# This is a line about assertion failed
			# Remove everything from line until first quote
			my $strnotfound = substr($line, length($assertion));
			# Find second quote
			my $endpos = index($strnotfound, "\"");
			# Now remove everything from second quote
			$strnotfound = substr($strnotfound, 0, $endpos);
			add2bbassert($strnotfound);
			$status = "Error";
			$errstring .= "A: $strnotfound;";
		} else {
			# URL statistics line
			# Get URL
			# Last 3 arguments are Response time, Responses and Errors
			# The rest (often only 1 argument) is the URL (and label).
			my $url = "";
			for (my $cnt=0; $cnt < ($nr_args-3); $cnt++) {
				$url .= $args[$cnt]." ";
			}
			# Remove trailing space
			$url = trim($url);
			add2bbperform($url,$args[-3],$args[-1]);
		}
	}
	# Statistics session handled, collect monitoring status
	add2monstatus();
	exit_application(0);
}

=pod

=head2 Add to bbassert

Add string to bbassert table. This string was not found during check for specific application. Unfortunately Badboy does not allow to link the string with URL (at least, I didn't know how to handle).

=cut

sub add2bbassert($) {
	my ($assertstring) = @_;
	my $query = "INSERT INTO bbasserts (msdate,mstime,application,assertstring)
							 values ('$msdate','$mstime','$applname','$assertstring')";
	my $rows_affected = $dbh->do($query);
	if (not defined $rows_affected) {
		error("Insert failed, query $query. Error: ".$dbh->errstr);
	} elsif (not $rows_affected == 1) {
		error("$rows_affected rows inserted ($query), 1 expected");
	}
}

=pod

=head2 Add to bbperform

Add URL response time info to bbperf table.

=cut

sub add2bbperform($$$) {
	my($url,$response,$errors) = @_;
	my $query = "INSERT INTO bbperf (msdate,mstime,application,url,response,status)
							 values ('$msdate','$mstime','$applname','$url',$response,$errors)";
	my $rows_affected = $dbh->do($query);
	if (not defined $rows_affected) {
		error("Insert failed, query $query. Error: ".$dbh->errstr);
	} elsif (not $rows_affected == 1) {
		error("$rows_affected rows inserted ($query), 1 expected");
	}
}

=pod

=head2 Add Monitoring Status

Add total monitoring status for this application.

=cut

sub add2monstatus() {
	my $query = "INSERT INTO monstat (msdate,mstime,application,status,errors)
							 values ('$msdate','$mstime','$applname','$status','$errstring')";
	my $rows_affected = $dbh->do($query);
	if (not defined $rows_affected) {
		error("Insert failed, query $query. Error: ".$dbh->errstr);
	} elsif (not $rows_affected == 1) {
		error("$rows_affected rows inserted ($query), 1 expected");
	}
}



######
# Main
######

# Handle input values
my %options;
getopts("tl:dp:k:h:", \%options) or pod2usage(-verbose => 0);
# At least the table name must be specified.
my $arglength = scalar keys %options;  
if ($arglength == 0) {			# If no options specified,
   $options{"h"} = 0;			# display usage. jmeter plan is mandatory
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
    if (not(defined $logdir)) {
		error("Could not set d:/temp/log as Log directory, exiting...");
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
# Check for debug flag
if (defined $options{"d"}) {
	$debugflag = "Yes";
} else {
	$debugflag = "No";
}
# Find badboy test plan
if ($options{"p"}) {
    $bbplan = $options{"p"};
	if (not -r $bbplan) {
		error("Cannot access test plan $bbplan for reading, exiting...");
		exit_application(1);
	}
} else {
	error("jmeter test plan has not been defined, exiting...");
	exit_application(1);
}
# Find timeout
if ($options{"k"}) {
    $timeout = $options{"k"};
	# Check timeout value is integer
	if (not($timeout =~ /^[1-9][0-9]*$/)) {
		error("Timeout $timeout is not a valid integer number, exiting...");
		exit_application(1);
	}
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Set-up database connection
my $connectionstring = "DBI:mysql:database=$databasename;host=$server;port=$port";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

# Get application name and date/time
($applname,undef) = split(/\./, basename($bbplan));
my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$msdate = sprintf("%04d-%02d-%02d",$year+1900, $mon+1, $mday);
$mstime = sprintf("%02d:%02d:%02d",$hour,$min,$sec);

# Set-up command line
my $cmdline = "\"$bbdir/bbcmd\" -i 1 -c -d $timeout -e MSHTML $bbplan";
@reslines = `$cmdline`;

# Now scan result lines for 'Summary Statistics' or 'Set duration expired'
my $statline = "----------------------------------------------------------------------------------";
my $expired = "Duration expired";

# print command output for debug purposes
if ($debugflag eq "Yes") {
	logging(join("",@reslines));
}

while (my $line = shift @reslines) {
	chomp ($line);
	# Check if duration expired
	if (index($line,$expired) > -1) {
	   $status = "Error";
	   $errstring .= "Timeout;";
	}
	# Check if Summary statistics report starts
	if (index($line, $statline) > -1) {
		handle_statistics();
		last;
	}
}
# Now keep track of current monitoring status
# Statistics session not found, something wron with Badboy SW
$errstring .= "Stat section not found in BB report;";
$status = "Error";
add2monstatus();

exit_application(1);

=pod

=head1 To Do

=over 4

=item *

Nothing for the moment...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
