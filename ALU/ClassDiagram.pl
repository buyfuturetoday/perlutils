=head1 NAME

ClassDiagram - Creates a class diagram starting from the selected class.

=head1 VERSION HISTORY

version 2.0 30 December 2010 DV

=over 4

=item *

Extended to print all attributes with a class

=back

version 1.0 28 December 2010 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This script will create a class diagram starting from the specified class. For now this works only on classes, not on links.

=head1 SYNOPSIS

 ClassHierarchy.pl [-t] [-l log_dir] [-c class] [-d depth] [-a] [-m table]

 ClassHierarchy -h	Usage
 ClassHierarchy -h 1  Usage and description of the options
 ClassHierarchy -h 2  All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=item B<-c class>

Parent Class, default it_world.

=item B<-d depth>

Optional, specifies the number of generations in the diagram.

=item B<-a>

Optional, if specified then do not add attributes to the diagram.

=item B<-m table>

Optional, table to handle. By default: classes table.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP, Perl v5.10.0, build 1005 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $dbh, %checkloop, @parents, @newparents, $parent, $parentid);
my ($depth, $showattribs);
my $classtable = "classes";
my $gencnt = 1;		# Generation Counter, to be used with depth.
my $printerror = 0;
# @opt all prints method for class creation. This is not required.
# Update when opt for attributes is known.
my $printheader = "/**\n * \@opt all\n */\n";

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
use dbParamsfmo_cmdb;

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if (defined $dbh) {
		$dbh->disconnect;
	}
	close ClassFile;
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

sub getattributes($) {
	my ($classid) = @_;
	my $attributes = "";
	# Query modified to show attributes only first time they
	# are used. Child classes will no longer list attributes.
	# This works only for starting from root class
	my $query = "SELECT a.attributename as name, a.type as type
					FROM attributes a, attrperclass p
					WHERE p.classid = $classid
					AND p.attributeid = a.attributeid
					AND p.classid = p.attrrow";
	my $sth = $dbh->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	while (my $ref = $sth->fetchrow_hashref) {
		my $name = $ref->{name};
		my $type = $ref->{type};
		my ($typedef, undef) = split /\[/, $type;
		$attributes .= "\n\t$typedef $name;";
	}
	if (length($attributes) > 0) {
		$attributes .= "\n";
	}
	return $attributes;
}

sub getchildren($) {
	my ($parent) = @_;
	my $parentid = $checkloop{$parent};
	my $query = "SELECT classid, classname
					FROM $classtable
					WHERE parentid = $parentid";
	my $sth = $dbh->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		exit_application(1);
	}
	while (my $ref = $sth->fetchrow_hashref) {
		my $classid = $ref->{classid};
		my $classname = $ref->{classname};
		if (exists $checkloop{$classname}) {
			error("$classname found in different branches, exiting...");
			$sth->finish();
			exit_application(1);
		}
		my $attributes = "";
		if (not defined $showattribs) {
			$attributes = getattributes($classid);
			print ClassFile $printheader;
		}
		print ClassFile "class $classname extends $parent {$attributes}\n";
		$checkloop{$classname} = $classid;
		push @newparents, $classname;
	}
	$sth->finish();
}
	

######
# Main
######

# Handle input values
my %options;
getopts("tl:h:c:d:am:", \%options) or pod2usage(-verbose => 0);
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
# Get parent
if ($options{"c"}) {
	$parent = $options{"c"};
} else {
	$parent = "it_world";
}
# Get Depth
if ($options{"d"}) {
	$depth = $options{"d"};
	if (not $depth =~ /^[0-9][0-9]*$/) {
		error("Depth $depth not integer, exiting...");
		exit_application(1);
	}
}
# Hide attributes from diagram?
if (defined ($options{"a"})) {
	$showattribs = "No";
}
# Classtable to handle?
if ($options{"m"}) {
	$classtable = $options{"m"};
}
logging("Start application");
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Open java file for writing
my $openres = open(ClassFile, ">d:/temp/class.java");
if (not defined $openres) {
	error("Could not open classfile for writing, exiting...");
	exit_application(1);
}

# Make database connection 
my $connectionstring = "DBI:mysql:database=$dbsource;host=$server;port=$port";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $dbsource, exiting...");
   	exit_application(1);
}

my $query = "SELECT classid FROM $classtable WHERE classname = '$parent'";
my $sth = $dbh->prepare($query);
my $rv = $sth->execute();
if (not defined $rv) {
	error("Could not execute query $query, Error: ".$sth->errstr);
	exit_application(1);
}
if (my $ref = $sth->fetchrow_hashref) {
	$parentid = $ref->{classid};
} else {
	error("Could not find class $parent in classes table, exiting...");
	$sth->finish();
	exit_application(1);
}
$sth->finish();

# Handle initial class
my $attributes = "";
if (not defined $showattribs) {
	$attributes = getattributes($parentid);
	print ClassFile $printheader;
}
print ClassFile "class $parent {$attributes}\n";
$checkloop{$parent} = $parentid;
push @parents, $parent;

while (@parents) {
	while (my $parent = shift @parents) {
		getchildren($parent);
	}
	# Move new parents to parents
	@parents = @newparents;
	# And start from an empty array of newparents
	@newparents = ();
	# Count Generations
	$gencnt++;
	if ((defined $depth) and $gencnt > $depth) {
		last;
	}
}

exit_application(0);

=head1 To Do

=over 4

=item *

Nothing documented for now...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@hp.comE<gt>
