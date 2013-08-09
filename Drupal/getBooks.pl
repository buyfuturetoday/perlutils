=head1 NAME

getBooks - Get Book Information from a Drupal database

=head1 VERSION HISTORY

version 1.0 03 March 2010 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will get information on Books from a Drupal database.

The goal is to allow to understand (and possibly extract the data) from a Drupal database backup, where the drupal environment itself is not available.

=head1 SYNOPSIS

 getBooks.pl [-t] [-l log_dir] [-d databasename]

 getBooks -h	   Usage
 getBooks -h 1   Usage and description of the options
 getBooks -h 2   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-d databasename>

Optional, specifies the database name. Otherwise the database name is taken from the kbparams module.

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
my ($nid, $vid, $bid, $mid, $mlid, $plid, $blid, $menu_name);

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
use File::Basename;

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
getopts("tl:h:d:", \%options) or pod2usage(-verbose => 0);
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
# Check if database name is specified
if ($options{"d"}) {
	$databasename = $options{"d"};
}
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

# Get Book Starter pages
my $query = "SELECT menu_name, mlid, link_path, link_title
					FROM menu_links
					WHERE module = 'book'
						AND depth = 1";
my $sth = $dbh->prepare($query);
my $rv = $sth->execute();
if (not defined $rv) {
	error("Error executing query $query, " . $sth->errstr);
	exit_application(1);
}
my $nodepath = 'node/';
while (my $ref = $sth->fetchrow_hashref) {
	my $menu_name = $ref->{menu_name};
	my $mlid = $ref->{mlid};
	my $link_path = $ref->{link_path};
	my $link_title = $ref->{link_title};
	my $nid = substr($link_path,length($nodepath));
	my $resline = "Book: $link_title * nid: $nid * mlid: $mlid * menu: $menu_name * node: $link_path";
	print $resline."\n";
	logging($resline);
}

exit_application(0);

=head1 To Do

=over 4

=item *

Nothing documented for now...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
