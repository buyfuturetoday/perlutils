=head1 NAME

saveconfigs.pl - Save agent configurations for specified hosts.

=head1 VERSION HISTORY

version 1.0 - 3 September 2006 DV

=over 4

=item *

Initial Release.

=back

=head1 DESCRIPTION

The purpose of this application is to save the configuration file of any Unicenter Agent on the specified hosts. The application needs the list of hosts and the commandfile to be executed. The save config shell script is copied to each host, then the commands to run the save config script are executed. Finally the log file and any configuration file is copied to the central system and renamed for further reference.

=head2 Copy agent configuration from one particular host

 perl saveconfigs.pl -u username -p password -i hostname -c saveConfigs.txt -a atech_save.sh

=head2 Copy agent configuration from all hosts

 perl saveconfigs.pl -u username -p password -s UxHosts.txt -c saveConfigs.txt -a atech_save.sh

=head2 Command File

Contents of the saveConfigs.txt file:

    # This script will set +x permissions on atech_save.sh
    # and run the shell script.
    . /etc/profile
    echo saveConfigs.sh at `date` > log.txt
    echo ls *.config >> log.txt
    ls *.config >> log.txt
    echo rm *.config
    rm *.config >> log.txt 2>&1
    echo chmod +x atech_save.sh >> log.txt
    chmod +x atech_save.sh >> log.txt 2>&1
    echo ./atech_save.sh >> log.txt
    ./atech_save.sh >> log.txt 2>&1

=head2 Remote Unix Shell Script

Contents of the atech_save.sh file:

    #! /usr/bin/ksh

    name_node=`uname -n`
    agent_list=`orbctrl |awk 'NR>1{print $2}' |grep -v aws_ |grep -v orbctrl`

    for i in $agent_list
    do
	# sort out if it is mibmuxed agent with instances
	echo $i |grep '@' > /dev/null
	if [ $? -eq 0 ]; then
	    # mibmuxed agent with instances
	    name_agent=`echo $i |awk '{FS = "@"}{print $2}'`
	    name_inst=`echo $i |awk '{FS = "@"}{print $1}'`
	    name_tmp=$name_agent"_"$name_inst".tmp"
	    name_file=$name_agent"_"$name_inst".config"
	    echo "Saving $name_node:$name_inst config to $name_file ..."
	    mkconfig $name_agent -i $name_inst -u $name_tmp > /dev/null
	    sed s/$name_agent:bootstrap/$name_agent:$name_inst/ $name_tmp > $name_file
	    rm $name_tmp
	else
	    # standard agent
	    if [ "$i" != "hpaAgent" -a "$i" != "prfAgent" ]; then
		# not either of the performance agents
		name_file=$i".config"
		echo "Saving $name_node:$i config to $name_file ..."
		mkconfig $i -u $name_file > /dev/null
	    fi
	fi
    done

=head1 SYNOPSIS

 saveconfigs.pl [-t] [-l logfile_directory]  [-u username] [-p password] [-s hosts-file | -i host] [-c command-file] [-a remote-unix-shell-script]

 saveconfigs.pl -h	Usage Information
 saveconfigs.pl -h 1	Usage Information and Options description
 saveconfigs.pl -h 2	Full documentation

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

File containing all commands to be executed. Each command must log output to the file log.txt in the default directory. Default: saveConfigs.txt

=item B<-a remote-unix-shell-script>

Shell script that will run remotely to extract all agent configuration settings. Default: atech_save.sh.

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
###########

my ($logdir, $username, $pwd, $hostfile, $cmds);
my ($template, $scriptname, $mkdirres, $hostname);
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

sub copy_cfgs($) {
    my ($host) = @_;
    # Verify if $hostdir exists
    if (not(-d "$cfg_dir/$host")) {
	$mkdirres = mkdir ("$cfg_dir/$host");
	if (not $mkdirres) {
	    error("Could not create subdirectory $cfg_dir/$host, errorno: $!. Exiting...");
	    exit_application(1);
	}
    }
    # Create DateTime Directory
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my $datetime = sprintf("%04d%02d%02d%02d%02d%02d", $year+1900, $mon+1, $mday,$hour,$min,$sec);
    $mkdirres = mkdir("$cfg_dir/$host/$datetime");
    if (not $mkdirres) {
	error("Could not create subdirectory $cfg_dir/$host/$datetime, errorno: $!. Exiting...");
	exit_application(1);
    }
    my $save_dir = "$cfg_dir/$host/$datetime";
    my $cmd = "pscp -pw $pwd $username@".$host.":*.config $save_dir";
    execute_command($cmd);
#    $cmd = "pscp -pw $pwd $username@".$host.":/em/smc/NSM/atech/agents/config/aws_baseline/*.cfg $save_dir";
#    execute_command($cmd);
}

sub handle_host($) {
    my ($host) = @_;
    # Verify if $host exist
    # Copy shell script to $host
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
    # Copy all configuration files on local system
    copy_cfgs($host);
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
    $cmds = $cfg_dir."/saveconfigs.txt";
}
if (not(-r $cmds)) {
    error("Commandfile $cmds not readable, exiting...");
    exit_application(1);
}
if ($options{"a"}) {
    $template = $options{"a"};
} else {
    $template = $cfg_dir."/atech_save.sh";
}
if (not(-r $template)) {
    error("Agenttemplate $template not readable, exiting...");
    exit_application(1);
}
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Now verify that one and only one option is selected. (hostname or hostfile)
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

Verify return codes from the commands

=back
