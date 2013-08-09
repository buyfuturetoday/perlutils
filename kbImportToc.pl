=head1 NAME

kbImportToc - Import kb TOC directory in MySQL

=head1 VERSION HISTORY

version 1.0 26 February 2010 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will import kb Table of Contents into MySQL. This is required as a first step for migration into Drupal.

=head1 SYNOPSIS

 kbImportToc.pl [-t] [-l log_dir] 

 kbImportToc -h	   Usage
 kbImportToc -h 1   Usage and description of the options
 kbImportToc -h 2   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP, Perl v5.8.8, build 820 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $dbh);
my $printerror = 0;
my $kbdir = "d:/web/kb/library";

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use DBI();
use Log;
use kbParams;			# DB Connection parameters

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if (defined $dbh) {
		$dbh->disconnect;
	}
	logging("Exit application with return code $return_code.\n");
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

######
# Main
######

# Handle input values
my %options;
getopts("tl:h:an:", \%options) or pod2usage(-verbose => 0);
# my $arglength = scalar keys %options;  
# if ($arglength == 0) {			# If no options specified,
#   $options{"h"} = 0;			# display usage.
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
		error("Could not find default Log directory, exiting...");
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

# Make database connection to source database
my $connectionstring = "DBI:mysql:database=$databasename;host=$server;port=$port";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

# Create table if not exists
my $query = "CREATE TABLE IF NOT EXISTS `kb_toc` (
				`toc_id` int(11) NOT NULL AUTO_INCREMENT,
				`kb_category` varchar(255) NOT NULL,
				PRIMARY KEY (`toc_id`)
				) ENGINE=MyISAM  DEFAULT CHARSET=latin1 AUTO_INCREMENT=45 ;";
my $rv = $dbh->do($query);
if (not(defined $rv)) {
	error("Could not execute query $query, Error: ".$dbh->errstr);
	exit_application(1);
}


# Truncate table kb_toc
$query = "TRUNCATE TABLE kb_toc";
$rv = $dbh->do($query);
if (not(defined $rv)) {
	error("Could not execute query $query, Error: ".$dbh->errstr);
	exit_application(1);
}

# Open kb directory
my $openres = opendir(KBDIR, $kbdir);
if (not defined $openres) {
	error("Could not open $kbdir for reading, exiting...");
	exit_application(1);
}
my @dirlist = readdir(KBDIR);
closedir (KBDIR);

# Prepare SQL statement for insert
$query = "INSERT INTO kb_toc (toc_id, kb_category)
				VALUES (0,?)";
my $sth = $dbh->prepare($query);

# Find kb directories
foreach my $dirname (@dirlist) {
	if (($dirname ne "images") and ($dirname ne ".") and ($dirname ne "..")) {
		my $fullname = "$kbdir/$dirname";
		if (-d $fullname) {
			# Found a category, add it to the table
			$sth->bind_param(1,$dirname);
			my $rv = $sth->execute();
			if (not defined $rv) {
				error("Error while inserting $dirname, ". $sth->errstr);
				exit_application(1);
			} elsif (not ($rv == 1)) {
				error("$rv rows inserted for $dirname, 1 expected");
			}
		}
	}
}

exit_application(0);

=head1 To Do

=over 4

=item *

Nothing documented for now...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
