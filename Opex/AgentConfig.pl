=head1 NAME

AgentConfig - Creates a report on the Agent Configuration.

=head1 VERSION HISTORY

version 1.1 3 July 2003 DV

=over 4

=item *

Add title line to the output file.

=back

version 1.0 3 June 2003 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application scans through the files ldconfig_BEMON001_GenAppI<AGENT>.txt. For each agent the name, the polling interval, the application monitors and other useful information is collected. The results are printed in an comma separated file c:/temp/genapp_config.csv.

It is the user's responsibility to make sure that only valid ldconfig files are available. In the current configuration these are the files that are created at 5 o'clock during the morning run. Files created at another time should not be considered.

=head1 SYNOPSIS

AgentConfig.pl [-t] [-l log_dir] [-d AgentDir]

    AgentConfig -h	    Usage
    AgentConfig -h 1	    Usage and description of the options
    AgentConfig -h 2	    All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: B<d:\opex\log>

=item B<-d>

Agent directory, default B<d:\tngbackup\agents>

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
my $agentdir = "d:/tngbackup/agents";		# Default agents directory
my $filestring = "ldconfig_BEMON001_GenApp_";	# File string for GenApp agent config files
my (%agent, %appl, $agentname);
my (@dirlist);

# Do NOT forget to update the PRINT line in the handle_application
# procedure when adding or changing the Agent Configuration or the 
# Application Configuration

# Agent Configuration
$agent{gaConfigCheckBasePoll} = "";	# Polling Interval

# Application Configuration
$appl{gaStatusCheckName} =  "";		# Name of the Application
$appl{gaStatusCheckCommand} = "";	# Command for the Application

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

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
    closedir AGENTDIR;
    close LDCONFIG;
    close CONFIG;
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

=head2 Handle Agent

This procedure handles the agent block. Verification is done that none of the values are filled in already, because this block should appear only once in each ldconfig file.

The keys are stored from position 1..40, the values are stored as of position 41.

The block is terminated by a blank line.

=cut

sub handle_agent {
    while (my $line = <LDCONFIG>) {
	chomp $line;
	if (length($line) == 0) {
	    # Empty line => quit the subroutine
	    last;
	}
	my ($parameter,@rest) = split / /,$line;
	$parameter = trim $parameter;
	if (exists($agent{$parameter})) {
	    if (not($agent{$parameter} eq "")) {
		error("$agentname duplicate value for $agent{$parameter}");
	    }
	    $agent{$parameter} = trim substr($line,length($parameter));
	}
    }
}

=pod

=head2 Handle Application

This procedure handles the application block. The application hash is cleared first, then all values are stored. At the end of the block all values are written to the output file. 

The block is terminated by a blank line.

=cut

sub handle_application {
    # Initialize application configuration
    foreach my $key (keys %appl) {
	$appl{$key} = "";
    }    
    while (my $line = <LDCONFIG>) {
	chomp $line;
	if (length($line) == 0) {
	    # Empty line => quit the subroutine
	    last;
	}
	my ($parameter,@rest) = split / /,$line;
	$parameter = trim $parameter;
	if (exists($appl{$parameter})) {
	    if (not($appl{$parameter} eq "")) {
		error("$agentname duplicate value for $appl{$parameter} in application configuration");
	    }
	    $appl{$parameter} = trim substr($line,length($parameter));
	}
    }
    print CONFIG "$agentname;$agent{gaConfigCheckBasePoll};$appl{gaStatusCheckName};$appl{gaStatusCheckCommand}\n";
}

=pod

head2 Handle ldconfig File

This procedure will walk through the ldconfig file.

It will find the agent name in the line I<#CONFIGSET GenApp:bootstrap@>. Then it will look for all 
the gaConfigCheckGroup to find all required agent configuration settings, and in the different groups gaStatusCheckTable to find the application monitoring settings.

It should find only one agent configuration group. 

=cut

sub handle_ldconfig_file($) {
    my ($filename) = @_;
    # Initialize agent configuration
    foreach my $key (keys %agent) {
	$agent{$key} = "";
    }
    my $openres = open(LDCONFIG, $filename);
    if (not(defined $openres)) {
	error("Could not open $filename for processing!");
    } else {
	# Find Agent name
	# The agentname must be the first usable line in the file.
	my $agentstring = "#CONFIGSET GenApp:bootstrap@";
	while (my $line = <LDCONFIG>) {
	    chomp $line;
	    if (index($line,$agentstring) == 0) {
		$agentname = substr($line,length($agentstring));
		last;
	    }
	}
	# Handle Group
	while (my $line = <LDCONFIG>) {
	    chomp $line;
	    if (index($line,"#SNMPGROUP gaConfigCheckGroup") == 0) {
		handle_agent();
	    } elsif (index($line, "#SNMPTABLE gaStatusCheckTable") == 0) {
		handle_application();
	    }
	}
    }
}

######
# Main
######

# Handle input values
my %options;
getopts("tl:d:h:", \%options) or pod2usage(-verbose => 0);
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
	print "Could not set d:\\opex\\log as Log directory, exiting...";
	exit 1;
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
if ($options{"d"}) {
    $agentdir = $options{"d"};
}
if (-d $agentdir) {
    trace("Agentdirectory: $agentdir");
} else {
    error("Cannot find Agentdirectory $agentdir, exiting...");
    exit_application(1);
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

my $openres = open(CONFIG, ">c:/temp/genapp_config.csv");
if (not(defined $openres)) {
    error("Could not open c:/temp/genapp_config.csv for writing, exiting...");
    exit_application(1);
}
print CONFIG "Agent;Poll;Object;Command\n";

if (not(opendir(AGENTDIR,$agentdir))) {
    error("Opendir $agentdir failed, exiting...");
    exit_application(1);
}
@dirlist = readdir(AGENTDIR);
foreach my $filename (@dirlist) {
    if (index($filename,$filestring) == 0) {
	# Valid file found
	handle_ldconfig_file("$agentdir/$filename");
    }
}
   
exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Nothing for the moment ...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
