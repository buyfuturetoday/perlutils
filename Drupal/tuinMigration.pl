=head1 NAME

tuinMigration - Migrate tuin Database

=head1 VERSION HISTORY

version 1.0 07 March 2010 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will convert the tuin database.

=head1 SYNOPSIS

 tuinMigration.pl [-t] [-l log_dir] 

 tuinMigration -h	   Usage
 tuinMigration -h 1   Usage and description of the options
 tuinMigration -h 2   All documentation

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

my ($logdir, $dbhsource, $dbhtarget);
my $printerror = 1;
# my ($nid, $vid, $bid, $mid, $mlid, $plid, $blid, $menu_name);

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
use File::Basename;
use tuinParams;				# DB Connection parameters
use drupalFuncs;			# Drupal Functions

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if (defined $dbhsource) {
		$dbhsource->disconnect;
	}
	if (defined $dbhtarget) {
		$dbhtarget->disconnect;
	}
	close TxTable;
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

sub stripContent {
	my ($content) = @_;
	my ($intro, $rest);
	my $txtl = index($content, "<h3>");
	if ($txtl > -1) {
		$intro = substr($content, 0, $txtl);
		$rest = substr($content, $txtl);
	} else {
		$intro = $content;
		$rest = "";
	}
	return ($intro, $rest);
}

sub getTitle {
	my ($content) = @_;
	my ($title, $rest);
	my $titlelength = index($content, "</h3>");
	if ($titlelength == -1) {
		error("Title not properly closed for $content");
		exit_application(1);
	}
	$title = substr($content, length("<h3>"), $titlelength - length("<h3>"));
	$rest = substr($content, $titlelength + length("</h3>"));
	return ($title, $rest);
}

sub handle_nodes {
	my ($plid_top, $topmlid) = @_;
	my $query = "SELECT b.nid as nid
					FROM menu_links ml, book b
					WHERE plid = $plid_top AND ml.mlid = b.mlid";
	my $sth = $dbhsource->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Error executing query $query, " . $sth->errstr);
		exit_application(1);
	}
	while (my $ref = $sth->fetchrow_hashref()) {
		my $nid = $ref->{nid};
		my ($title, $restoftext) = getnode($dbhsource, $nid);
		my ($textpart, $content) = stripContent($restoftext);
		# Menu link id from planten node is parent for description pages
		my ($newnid, $plid) = addbook($dbhtarget, $title, $textpart, $topmlid);
		print TxTable "$title;$nid;$newnid\n";
		while ($content) {
			# Get title from content
			($title, $content) = getTitle($content);
			# Get text till next title
			($textpart, $content) = stripContent($content);
			# Add as page under this plant
			my ($newnid, undef) = addbook($dbhtarget, $title, $textpart, $plid);
		}
	}
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
my $connectionstring = "DBI:mysql:database=$dbsource;host=$server;port=$port";
$dbhsource = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbhsource) {
   	error("Could not open $dbsource, exiting...");
   	exit_application(1);
}

# Make database connection to target database
$connectionstring = "DBI:mysql:database=$dbtarget;host=$server;port=$port";
$dbhtarget = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbhtarget) {
   	error("Could not open $dbtarget, exiting...");
   	exit_application(1);
}

my $txtablefile = "d:/temp/tuintx.csv";
my $openres = open(TxTable, ">$txtablefile");
if (not defined $openres) {
	error("Could not open $txtablefile for writing, exiting...");
	exit_application(1);
}
print TxTable "Title;Old nid;New nid\n";
# Create Top Book Page
my $bookTitle = "Tuinplanten";
my $bookContent = "Dit is een collectie van tuinplanten.";
my ($top_nid, $topmlid) = addbook($dbhtarget, $bookTitle, $bookContent);

# Handle all Tuinplanten from Tuin
handle_nodes(259,$topmlid);
# vijver
handle_nodes(405,$topmlid);
# and voortuin
handle_nodes(310,$topmlid);

# Create Boek Snoeitechnieken
$bookTitle = "Snoeitechnieken";
$bookContent = "Dit is een collectie van snoeitechnieken.";
($top_nid, $topmlid) = addbook($dbhtarget, $bookTitle, $bookContent);
handle_nodes(396, $topmlid);

# Create Boek Vissen
$bookTitle = "Vissen";
$bookContent = "Dit is een collectie van vissen.";
($top_nid, $topmlid) = addbook($dbhtarget, $bookTitle, $bookContent);
handle_nodes(406, $topmlid);

exit_application(0);

=head1 To Do

=over 4

=item *

Nothing documented for now...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
