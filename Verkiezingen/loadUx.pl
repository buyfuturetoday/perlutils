=head1 NAME

loadUx.pl - This script will load Unix agent template file on agent systems.

=head1 VERSION HISTORY

version 1.1 - 7 September 2006 DV

=over 4

=item *

Added Template Directory

=item *

Allow comments and empty lines in host file

=back

version 1.0 - 3 September 2006 DV

=over 4

=item *

Initial Release.

=back

=head1 DESCRIPTION

The purpose of this application is to load a Unix file on Unicenter Agents. The application needs the list of hosts to be executed. The template is copied to each host, then the commands to reload the template are executed. Finally the log file is copied to the central system and renamed for further reference.

=head2 Command File

Contents of the loadUx.txt command file

    # This script will stop the caiUxOs agent, load the template and
    # restart the caiUxOs agent.
    . /etc/profile
    echo load caiUxOs template at `date` > log.txt
    echo awservices status >> log.txt
    awservices status >> log.txt 2>&1
    echo caiUxOs stop >> log.txt
    caiUxOs stop >> log.txt 2>&1
    echo ldconfig caiUxOs.config >> log.txt
    ldconfig caiUxOs.config >> log.txt 2>&1
    echo caiUxOs start >> log.txt
    caiUxOs start >> log.txt 2>&1

=head2 Agent Template

The agent template is the (modified) caiUxOs.config file that was created with the saveconfigs.pl script or the mkconfig script.

=head1 SYNOPSIS

 loadUx.pl [-t] [-l logfile_directory]  [-u username] [-p password] [-s hosts-file | -i host] [-c command-file] -a agent-template

 loadUx.pl -h	Usage Information
 loadUx.pl -h 1	Usage Information and Options description
 loadUx.pl -h 2	Full documentation

=head1 OPTIONS

=over 4

=item B<-t>

if set, then trace messages will be displayed. 

=item B<-l logfile_directory>

default: c:\temp

=item B<-u username>

Username that can execute commands.

=item B<-p password>

Password associated with username.

=item B<-s hosts-file>

File containing hostnames to check. Each hostname must be on a single line. Empty lines or lines starting with # are ignored.

=item B<-i host>

Single host where to send opreload command to.

=item B<-c command-line>

File containing all commands to be executed. Each command must log output to the file log.txt in the default directory. Default: loadUx.txt

=item B<-a agent-template>

Agent template file that will be copied to the remote system containing the new configuration.

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
###########

my ($logdir, $username, $pwd, $hostfile, $hostname, $cmds, $template, $scriptname);
my $cfg_dir = "D:/dirk/NSM.config/atech/configsets";

#####
# use
#####

use warnings;			    # show warnings
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Input parameter handling
use Pod::Usage;			    # Usage printing
use File::Basename;		    # For logfilename translation
use Log;
use OpexAccess;

#############
# subroutines
#############

sub exit_application($) {
    my($return_code) = @_;
    close HOSTS;
    logging("Exit application with return code $return_code\n");
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

=head2 Execute Command

This procedure accepts a system command, executes the command and checks on a 0 return code. If no 0 return code, then an error occured and control is transferred to the Display Error procedure.

=cut

sub execute_command($) {
    my ($command) = @_;
    if (system($command) == 0) {
	logging("Command $command - Return code 0");
    } else {
	my $ErrorString = "Could not execute command $command";
	error($ErrorString);
	exit_application(1);
#	display_error($ErrorString);
    }
}

sub handle_host($) {
    my ($host) = @_;
    # Verify if $host exist
    # Copy template file to $host
    my $cmd = "pscp -pw $pwd $template $username"."@"."$host:";
    execute_command($cmd);
    # Execute commands on $host
    $cmd = "putty -ssh -pw $pwd -m $cmds $username"."@"."$host";
    execute_command($cmd);
    # Copy logfile to local system, rename
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my $datetime = sprintf("%04d%02d%02d%02d%02d%02d", $year+1900, $mon+1, $mday,$hour,$min,$sec);
    $cmd = "pscp -pw $pwd $username"."@"."$host:log.txt $logdir/".$host."_".$scriptname."_".$datetime."_log.txt";
    execute_command($cmd);
}

######
# Main
######

# Handle input values
my %options;
getopts("l:th:u:p:s:c:a:i:", \%options) or pod2usage(-verbose => 0);
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
} else {
    $logdir=logdir();
}
if (-d $logdir) {
    trace("Logdir: $logdir");
} else {
    pod2usage(-msg     => "Cannot find log directory ".logdir,
	      -verbose => 0);
}
# Logdir found, start logging
open_log();
logging("Start application");
# Find source directory
if ($options{"u"}) {
    $username = $options{"u"};
} else {
    $username = $atechUser;
}
if ($options{"p"}) {
    $pwd = $options{"p"};
} else {
    $pwd = $atechKey;
}
if ($options{"s"}) {
    $hostfile = $options{"s"};
    if (not(-r $hostfile)) {
	error("Serverfile $hostfile not readable, exiting...");
	exit_application(1);
    }
}
if ($options{"i"}) {
    $hostname = $options{"i"};
}
if ($options{"c"}) {
    $cmds = $options{"c"};
} else {
    $cmds = $cfg_dir."/loadUx.txt";
}
if (not(-r $cmds)) {
    error("Commandfile $cmds not readable, exiting...");
    exit_application(1);
}
if ($options{"a"}) {
    $template = $options{"a"};
    if (not(-r $template)) {
	error("Agenttemplate $template not readable, exiting...");
	exit_application(1);
    }
}
if ($options{"d"}) {
    if (defined $template) {
	my $errmsg = "Template file $template already specified, cannot specify directory " . $options{"d"} . " as well, exiting...";
	error($errmsg);
	exit_application(1);
    }
    $template = $options{"d"};
    if (-d $template) {
	$template .= "/*.config";
    } else {
	error("Template directory $template not a directory, exiting...");
	exit_application(1);
    }
}
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Verify that Template has been defined
if (not defined $template) {
    error("Template file or directory not defined, exiting...");
    exit_application(1);
}

# Now verify that one and only one option is selected (hostname or hostfile)
if ((not defined $hostname) and (not defined $hostfile)) {
    error("Hostname or hostfile not specified, exiting...");
    exit_application(1);
}
if ((defined $hostname) and (defined $hostfile)) {
    error("Hostname $hostname and hostfile $hostfile both defined, please select only one of both.");
    exit_application(1);
}

# Find scriptname to store in host logfile
($scriptname, undef) = split(/\./, basename($0));

if (defined $hostfile) {
    # Read hosts file, handle hosts one by one
    my $openres = open(HOSTS, $hostfile);
    if (not(defined $openres)) {
	error("Could not open serverfile $hostfile for reading, exiting...");
	exit_application(1);
    }
    while (my $host = <HOSTS>) {
	chomp $host;
	# Ignore any line that does not start with character
	if ($host =~ /^[A-Za-z]/) {
	    $host = trim($host);
	    handle_host($host);
	}
    }
} else {
    handle_host($hostname);
}

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Add possibility to specify one host only.

=item *

Implement host verification

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
