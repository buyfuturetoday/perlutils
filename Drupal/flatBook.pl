=head1 NAME

flatBook - Dump a specified Drupal Book into flat files for data backup and dummy browser export.

=head1 VERSION HISTORY

version 1.0 03 March 2010 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will dump the contents of a Drupal Book into flat file directory. This provides a backup for the data or it alllows to transfer the content to lightweight internet environments, such as an IPAQ mobile.

=head1 SYNOPSIS

 flatBook.pl [-t] [-l log_dir] [-d databasename] -b bookTitle -s dumpdirectorystore -Y

 flatBook -h	   Usage
 flatBook -h 1   Usage and description of the options
 flatBook -h 2   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-d databasename>

Databasename if specified. Otherwise database name is read from the kbparams module.

=item B<-b bookTitle>

The title of the Book to be stored.

=item B<-s dumpdirectorystore>

The directory where the Book information will be stored. The book will be stored in directory dumpdirectorystore/bookTitle. This directory should not exist.

=item B<-Y>

If the directory dumpdirectorystore/bookTitle exists, remove it including all subdirectories. If the directory exists but this flag is not set, then exit application.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP, Perl v5.8.8, build 820 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $dbh, $book, $bookdir, $deleteflag);
my $printerror = 0;
# my ($nid, $vid, $bid, $mid, $mlid, $plid, $blid);

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
# use File::Basename;
use File::Path;			# mkdir and removedir

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

=pod

=head2 Handle PathError

This procedure will evaluate error messages returned from the rmtree or mkpath statements. The result of these functions is a reference to an array of error hashes.
If the array is empty, then there are no error messages. Otherwise all hashes need to be evaluated to get the full message.

If there is a message, the application will exit.

=cut


sub handle_patherror($$) {
	my ($location, $err) = @_;
	if (defined @$err[0]) {
		# Something wrong, collect message
		my $errmsg = "";
		foreach my $diag (@$err) {
			my ($file, $msg) = each %$diag;
			$errmsg .= "$file: $msg\n";
		}
		error("Error while $location: $errmsg");
		exit_application(1);
	}
 }

=pod

=head2 Add Chapter

This procedure will add a chapter to the book. It will get the node title and the node content. The node title is used as the chapter title, which will be the subdirectory name for the chapter. In the subdirectory a content page with the node information will be created.

=cut

sub addchapter($$$) {
	my ($bookdir, $mlid, $nid) = @_;
	my ($title, $content) = getnode($nid);
	# Create directory for this chapter
	my $chapterdir = "$bookdir/$title";
	mkpath($chapterdir, {error => \my $err});
	handle_patherror("create $bookdir", $err);
	# create content page for this chapter
	createpage($chapterdir, $title, $content);
	handlechapter($chapterdir,$mlid,$nid);
}

=pod

=head2 Handle Chapter

This procedure will walk through a chapter of the book. It will get all nodes that are direct children of the node. In case the child is a parent itself, then the addchapter procedure will be called. Otherwise the createpage procedure is called, to create a page for this node.

=cut

sub handlechapter($$$) {
	my ($chapterdir, $plid, $bid) = @_;
	# Get all direct children for this parent
	my $query = "SELECT nid, ml.mlid as mlid, has_children
						FROM menu_links ml, book b
						WHERE plid = $plid
							AND ml.mlid = b.mlid";
	my $sth = $dbh->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, " . $sth->errstr);
		exit_application(1);
	}
	while (my $ref = $sth->fetchrow_hashref()) {
		my $nid = $ref->{nid};
		my $mlid = $ref->{mlid};
		my $haschildren = $ref->{has_children};
		if ($haschildren == 1) {
			addchapter($chapterdir, $mlid, $nid);
		} else {
			addnode($chapterdir, $nid);
		}
	}
}

=pod

=head2 Add Node

This procedure adds a node to the book chapter. First it will get the node information, then it will write the information to the node page.

=cut

sub addnode($$) {
	my ($chapterdir, $nid) = @_;
	my ($title, $content) = getnode($nid);
	createpage($chapterdir, $title, $content);
}

=pod

=head2 Get Node

This procedure will get the node title and the node content for a given node id. This procedure assumes for now that node revisions are not used. There is only one revision version per node.

=cut

sub getnode($) {
	my ($nid) = @_;
	my $query = "SELECT title, body
						FROM node_revisions
						WHERE nid=$nid";
	my $sth = $dbh->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Error executing query $query, ".$sth->errstr);
		exit_application(1);
	}
	my $ref = $sth->fetchrow_hashref();
	my $title = $ref->{title};
	my $body = $ref->{body};
	$sth->finish;
	return ($title, $body);
}

=pod

=head2 Create Page

This procedure will create a page with the node information.

=cut

sub createpage($$$) {
	my ($pagedir, $title, $content) = @_;
	my $openres = open(PAGE, ">$pagedir/$title.html");
	if (not defined $openres) {
		error("Could not open $pagedir/$title for writing!");
	} else {
		print PAGE "<h3>$title</h3>\n";
		print PAGE $content;
		close PAGE;
	}
	return;
}

######
# Main
######

# Handle input values
my %options;
getopts("tl:h:d:b:s:Y", \%options) or pod2usage(-verbose => 0);
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
# Get database name
if ($options{"d"}) {
	$databasename = $options{"d"};
}
# Get Book title
if ($options{"b"}) {
	$book = $options{"b"};
} else {
	error("Book Title is not defined, exiting...");
	exit_application(1);
}
# Get dump directory
if ($options{"s"}) {
	$bookdir = $options{"s"};
} else {
	error("Book dump directory not defined, exiting...");
	exit_application(1);
}
# Get delete directory flag
if (defined $options{"Y"}) {
	$deleteflag = "Yes";
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Check if directory exists
if (-d "$bookdir/$book") {
	# Directory exist, can I delete it?
	if ($deleteflag eq "Yes") {
		rmtree("$bookdir/$book", {error => \my $err});
		handle_patherror("delete $bookdir", $err);
	} else {
		error("Book directory $bookdir/$book still exists, specify delete flag -Y!");
		exit_application(1);
	}
}

# Make database connection to source database
my $connectionstring = "DBI:mysql:database=$databasename;host=$server;port=$port";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

# Find Book Node
# First make sure that only 1 record is returned for the query
my $query = "SELECT count(*) as reccnt
					FROM menu_links ml, book b
					WHERE link_title = ? and module='book' and depth=1
						AND ml.mlid = b.mlid";
my $sth = $dbh->prepare($query);
$sth->bind_param(1, $book);
my $rv = $sth->execute();
if (not defined $rv) {
	error("Error executing query $query: ".$sth->errstr);
	exit_application(1);
}
if (my $ref = $sth->fetchrow_hashref()) {
	my $reccnt = $ref->{reccnt};
	if (not ($reccnt == 1)) {
		error("$reccnt found, 1 record expected for book $book in query $query");
		exit_application(1);
	}
}
$sth->finish;
# OK, now work on this record
$query = "SELECT nid, ml.mlid as mlid
				FROM menu_links ml, book b
				WHERE link_title = ? and module='book' and depth=1
					AND ml.mlid = b.mlid";
$sth = $dbh->prepare($query);
$sth->bind_param(1, $book);
$rv = $sth->execute();
if (not defined $rv) {
	error("Error executing query $query: ".$sth->errstr);
	exit_application(1);
}
if (my $ref = $sth->fetchrow_hashref()) {
	my $mlid = $ref->{mlid};
	my $nid = $ref->{nid};
	$sth->finish();
	addchapter($bookdir, $mlid, $nid);
}

exit_application(0);

=head1 To Do

=over 4

=item *

Nothing documented for now...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
