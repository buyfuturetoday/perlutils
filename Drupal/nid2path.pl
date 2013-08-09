=head1 NAME

nid2path - Node ID to Path conversion

=head1 VERSION HISTORY

version 1.0 16 March 2010 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will convert node pointers to human-readable paths as created with Drupal Pathauto.

=head1 SYNOPSIS

 nid2path.pl [-t] [-l log_dir] [-p path_conversion_file]

 nid2path -h	 Usage
 nid2path -h 1   Usage and description of the options
 nid2path -h 2   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-p path_conversion_file>


=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP, Perl v5.8.8, build 820 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $dbh, %nodetx, %noderevtx);
my $printerror = 1;
my $pathconversionfile = "d:/temp/tuintx.csv";
my $searchstring = "http://localhost/drupal6/node/";
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

sub tuintx {
	my ($openfile) = @_;
	my $openres = open(TXTable, $openfile);
	if (not defined $openres) {
		error("Could not open $openfile for reading, exiting...");
		exit_application(1);
	}
	# Get TitleLine
	my $line = <TXTable>;
	while ($line = <TXTable>) {
		chomp $line;
		my ($title, $oldnid, $newnid) = split /;/, $line;
		if (exists $nodetx{$oldnid}) {
			error("Duplicate entry for $title (old nid: $oldnid, new nid: $newnid)");
		} else {
			$nodetx{$oldnid} = $newnid;
			$noderevtx{$newnid} = $oldnid;
		}
	}
	close TXTable;
}

sub convertURL {
	my ($nid, $body) = @_;
	my $startpos = index($body, $searchstring);
	while ($startpos > -1) {
		# Search for href delimiter > from searchstring
		my $endpos = index($body,">", $startpos);
		my $replstr = substr($body,$startpos,$endpos-$startpos);
		if (not ($replstr =~ /[0-9]$/)) {
			# Lastchar is ' or ", strip
			$replstr = substr($replstr, -1);
		}
		my $oldnode = substr($replstr,length($searchstring));
		if (defined $nodetx{$oldnode}) {
			my $newnid = $nodetx{$oldnode};
			# Get URL
			my $query = "SELECT dst FROM url_alias WHERE src = ?";
			my $sth = $dbh->prepare($query);
			$sth->bind_param(1, "node/$newnid");
			my $rv = $sth->execute();
			if (not defined $rv) {
				error("Error executing query $query, ".$sth->errstr);
				exit_application(1);
			}
			if (my $res = $sth->fetchrow_hashref()) {
				my $dst = "/" . $res->{dst};
				substr($body, $startpos, length("$searchstring"."$oldnode"), $dst);
				logging("$newnid: $searchstring/$oldnode to $dst");
				$sth->finish();
			} else {
				error("Could not find destination URL for node/$newnid (old nid: $nid)");
				exit_application(1);
			}
		} else {
			error("NID $nid invalid node reference $oldnode\n$body");
			exit_application(1);
		}
		$startpos = index($body, $searchstring);
	}
	# Now update body and teaser info
	my $query = "UPDATE node_revisions SET body = ?, teaser = ?
				WHERE nid = $nid";
	my $sth=$dbh->prepare($query);
	$sth->bind_param(1, $body);
	$sth->bind_param(2, $body);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, ".$sth->errstr);
		exit_application(1);
	}
	if (not ($rv == 1)) {
		error("$rv rows affected, 1 expected!");
		exit_application(1);
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

# Make database connection to target database
my $connectionstring = "DBI:mysql:database=$dbtarget;host=$server;port=$port";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $dbtarget, exiting...");
   	exit_application(1);
}

# Initialize translation table
tuintx($pathconversionfile);

# Get all nodes with node reference
my $query = "SELECT nid, body FROM node_revisions
				WHERE body LIKE ?";
my $sth = $dbh->prepare($query);
$sth->bind_param(1,"%$searchstring%");
my $rv = $sth->execute();
if (not defined $rv) {
	error("Could not execute query $query, ".$sth->errstr);
	exit_application(1);
}
while (my $res = $sth->fetchrow_hashref()) {
	my $nid = $res->{nid};
	my $body = $res->{body};
#	if (defined $noderevtx{$nid}) {
		convertURL($nid, $body);
#	}
}

exit_application(0);

=head1 To Do

=over 4

=item *

Nothing documented for now...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
