=head1 NAME

kbImportContent - Import kb TOC directory in MySQL

=head1 VERSION HISTORY

version 1.0 27 February 2010 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will import kb Content into MySQL. This is required as a first step for migration into Drupal.

=head1 SYNOPSIS

 kbImportContent.pl [-t] [-l log_dir] 

 kbImportContent -h	   Usage
 kbImportContent -h 1   Usage and description of the options
 kbImportContent -h 2   All documentation

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

sub get_toc_id($$) {
	my ($sth, $dirname) = @_;
	my ($toc_id);
	$sth->bind_param(1,$dirname);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Error w ". $sth->errstr);
		exit_application(1);
	}
	if (my $ref = $sth->fetchrow_hashref) {
		$toc_id = $ref->{toc_id};
	} else {
		$toc_id = -1;
	}
	$sth->finish;
	return $toc_id;
}

sub handle_category($$) {
	my ($dirname, $toc_id) = @_;

	# Open category directory
	my $cat_dir = "$kbdir/$dirname";
	my $openres = opendir(KBDIR, $cat_dir);
	if (not defined $openres) {
		error("Could not open $cat_dir for reading, exiting...");
		exit_application(1);
	}
	my @dirlist = readdir(KBDIR);
	closedir (KBDIR);

	#
	# Find category articles
	foreach my $artfile (@dirlist) {
		my ($article, undef, $suffix) = fileparse("$cat_dir/$artfile", ".html");
		if ((lc($suffix) eq ".html") and (lc($article) ne "toc")) {
			# Found article, handle it
			handle_article($cat_dir, $artfile, $toc_id);
		}
	}
}

sub handle_article ($$$) {
	my ($cat_dir, $artfile, $toc_id) = @_;
	my ($title, $article);
	# Open article
	my $openres = open(Article, "$cat_dir/$artfile");
	if (not defined $openres) {
		error("Could not open $cat_dir/$artfile for reading!");
		return;
	}
	# Get title line
	my $line = <Article>;
	chomp $line;
	my $titstart = "<h3>";
	my $titend = "</h3>";
	# Check title starts with <h3>
	if ((substr($line, 0, length($titstart)) ne $titstart) or (substr($line, length($line)-length($titend), length($titend)) ne $titend)) {
		error "Invalid title $cat_dir/$artfile \t $line\n";
		$title = "Invalid title";
	} else {
		$title = substr($line, length($titstart), length($line) - length($titstart) - length($titend));
	}
	
	# Now read all lines to get article
	while ($line = <Article>) {
		$article .= $line;
	}
	
	# Import into kb_article table
	my $query = "INSERT INTO kb_article (kb_id, toc_id, title, article) VALUES (0, ?, ?, ?)";
	my $sth = $dbh->prepare($query);
	$sth->bind_param(1, $toc_id);
	$sth->bind_param(2, $title);
	$sth->bind_param(3, $article);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Error while inserting article $cat_dir/$artfile, ". $sth->errstr);
		exit_application(1);
	} elsif (not ($rv == 1)) {
		error("$rv rows inserted for $cat_dir/$artfile, 1 expected");
	}
	close Article;
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

# Create Table if not exists
my $query = "CREATE TABLE IF NOT EXISTS `kb_article` (
				  `kb_id` int(11) NOT NULL AUTO_INCREMENT,
				  `toc_id` int(11) NOT NULL,
				  `title` varchar(255) NOT NULL,
				  `article` text NOT NULL,
				  PRIMARY KEY (`kb_id`)
					) ENGINE=MyISAM  DEFAULT CHARSET=latin1 AUTO_INCREMENT=432 ;";
my $rv = $dbh->do($query);
if (not(defined $rv)) {
	error("Could not execute query $query, Error: ".$dbh->errstr);
	exit_application(1);
}

# Truncate table kb_article
$query = "TRUNCATE TABLE kb_article";
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

# Prepare SQL to get toc id
$query = "SELECT toc_id FROM kb_toc
				WHERE kb_category = ?";
my $sth = $dbh->prepare($query);

# Find kb directories
foreach my $dirname (@dirlist) {
	if (($dirname ne ".") and ($dirname ne "..") and ($dirname ne "images")) {
		my $fullname = "$kbdir/$dirname";
		if (-d $fullname) {
			# Found a category, get the toc_id
			my $toc_id = get_toc_id($sth, $dirname);
			if ($toc_id > 0) {
				handle_category($dirname, $toc_id);
			} else {
				error("$fullname no index found.");
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
