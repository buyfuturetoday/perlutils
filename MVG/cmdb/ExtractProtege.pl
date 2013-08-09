=head1 NAME

ExtractProtege - Extract information from a Protege Database table. 

=head1 VERSION HISTORY

version 1.0 16 May 2008 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

Note that this script requires Protege version 3.3.1. Later versions of Protege have a more elaborated field structure and cannot be used with this script.

This application will read the table dump from Protege database table. It will convert classes and attributes into a generic metadata format, comparable with the database table-attribute structure. 

The application is build to connect to a MySQL database server. DBI modules have been used, so conversion to another type of database server shouldn't be difficult.

This script and the ExplodeProtege script need 3 tables in the database cmdbmeta. SQL below can be used to generate the tables.

 -- phpMyAdmin SQL Dump
 -- version 3.2.0.1
 -- http://www.phpmyadmin.net
 --
 -- Host: localhost
 -- Generation Time: Nov 17, 2009 at 11:21 AM
 -- Server version: 5.1.36
 -- PHP Version: 5.3.0
 
 SET SQL_MODE="NO_AUTO_VALUE_ON_ZERO";
 
 --
 -- Database: `cmdbmeta`
 --
 
 -- -------------------------------------------------------- 
 
 --
 -- Table structure for table `protegetableattributes`
 --
 
 CREATE TABLE IF NOT EXISTS `protegetableattributes` (
  `tablename` varchar(255) DEFAULT NULL,
  `attribute` varchar(255) DEFAULT NULL,
  `documentation` mediumtext,
  `destination` varchar(255) DEFAULT NULL
 ) ENGINE=MyISAM DEFAULT CHARSET=latin1;
 
 -- --------------------------------------------------------
 
 --
 -- Table structure for table `protegetableinfo`
 --
 
 CREATE TABLE IF NOT EXISTS `protegetableinfo` (
  `parent` varchar(255) NOT NULL,
  `tablename` varchar(255) DEFAULT NULL,
  `role` varchar(255) DEFAULT NULL,
  `documentation` mediumtext
 ) ENGINE=MyISAM DEFAULT CHARSET=latin1;
 
 -- --------------------------------------------------------
 
 --
 -- Table structure for table `protexplodedattributes`
 --
 
 CREATE TABLE IF NOT EXISTS `protexplodedattributes` (
  `tablename` varchar(255) DEFAULT NULL,
  `attribute` varchar(255) DEFAULT NULL,
  `documentation` mediumtext,
  `destination` varchar(255) DEFAULT NULL
 ) ENGINE=MyISAM DEFAULT CHARSET=latin1;
 


=head1 SYNOPSIS

 ExtractProtege.pl [-t] [-l log_dir]

 ExtractProtege -h	 	   Usage
 ExtractProtege -h 1	   Usage and description of the options
 ExtractProtege -h 2	   All documentation

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: d:\temp\log

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.8.0, build 804 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir,$dbh, $dbh2, $dbh3, $dbmeta);
my $server="localhost";
my $username="root";
my $password="Monitor1";
my $databasename="protegeDB";
my $table="protegetable";
my $printerror=0;
my $cmdbmetaDB = "cmdbmeta";
my $table_count = 0;
my $attribute_count = 0;

# Value type values
my $value_type_string = 3;
my $value_type_class = 6;
my $value_type_slot = 7;

# Slot values
my $slot_documentation = 2000;
my $slot_name = 2002;
my $slot_role = 2003;
my $slot_subclass = 2005;
my $slot_template_slot = 2008;
my $slot_value_type = 2014;
my $slot_facet_documentation = 3001;

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

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if (defined $dbh) {
		$dbh->disconnect;
	}
	if (defined $dbh2) {
		$dbh->disconnect;
	}
	if (defined $dbh3) {
		$dbh->disconnect;
	}
	if (defined $dbmeta) {
		$dbmeta->disconnect;
	}
	my $status_msg = "$table_count table records, $attribute_count attribute records";
	print $status_msg."\n";
	logging($status_msg);
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

=head2 Frame Name

This procedure will return the frame name for a frame ID

=cut

sub frame_name($) {
	my ($frame_id) = @_;
	my $name = "";
	my $query = "SELECT short_value, long_value FROM $table WHERE frame=$frame_id AND slot=$slot_name";
	my $sth = $dbh->prepare($query);
	$sth->execute();
	if (my $ref = $sth->fetchrow_hashref()) {
		my $short = $ref->{short_value};
		my $long = $ref->{long_value};
		if (defined $short) {
			$name = $short;
		} elsif (defined $long) {
			$name = $long;
		} else {
			error("Record found, but no name defined for frame $frame_id");
		}
	} else {
		error("No name record found for frame $frame_id");
	}
	return $name;
}

=pod 

=head2 Class Comment

This procedure will return the class documentation for a frame ID

=cut

sub class_documentation($) {
	my ($class_id) = @_;
	my $documentation = "";
	my $query = "SELECT short_value, long_value FROM $table WHERE frame=$class_id AND slot=$slot_documentation";
	my $sth = $dbh->prepare($query);
	$sth->execute();
	if (my $ref = $sth->fetchrow_hashref()) {
		my $short = $ref->{short_value};
		my $long = $ref->{long_value};
		if (defined $short) {
			$documentation = $short;
		} elsif (defined $long) {
			$documentation = $long;
		} else {
			error("Record found, but no documentation defined for class frame $class_id");
		}
	} else {
		logging("No documentation record found for class frame $class_id");
	}
	return $documentation;
}

=pod 

=head2 Class Role

This procedure will return the class role for a frame ID

=cut

sub class_role($) {
	my ($class_id) = @_;
	my $role = "None";
	my $query = "SELECT short_value, long_value FROM $table WHERE frame=$class_id AND slot=$slot_role";
	my $sth = $dbh->prepare($query);
	$sth->execute();
	if (my $ref = $sth->fetchrow_hashref()) {
		my $short = $ref->{short_value};
		my $long = $ref->{long_value};
		if (defined $short) {
			$role = $short;
		} elsif (defined $long) {
			$role = $long;
		} else {
			error("Record found, but no role defined for class frame $class_id");
		}
	} else {
		error("No role record found for class frame $class_id");
	}
	return $role;
}

=pod 

=head2 Class Subclasses

This procedure will return the subclasses for a given class

=cut

sub class_subclasses($) {
	my ($class_id) = @_;
	my @subclasses = ();
	my $query = "SELECT short_value FROM $table WHERE frame=$class_id AND slot=$slot_subclass";
	my $sth = $dbh->prepare($query);
	$sth->execute();
	while (my $ref = $sth->fetchrow_hashref()) {
		my $short = $ref->{short_value};
		push @subclasses, $short;
	}
	return @subclasses;
}

=pod 

=head2 Class Attributes

This procedure will return all attribute references for a specific class.

=cut

sub class_attributes($) {
	my ($class_id) = @_;
	my @attributes = ();
	my $query = "SELECT short_value FROM $table WHERE frame=$class_id AND slot=$slot_template_slot";
	my $sth = $dbh->prepare($query);
	$sth->execute();
	while (my $ref = $sth->fetchrow_hashref()) {
		my $short = $ref->{short_value};
		push @attributes, $short;
	}
	return @attributes;
}

=pod

=head2 Instance Destination

This procedure will investigate each attribute (direct or modified) to find out if the slot type is instance. If so, then the destination classes will be collected.

=cut

sub instance_destination($) {
	my ($frame_id) = @_;
	my $instance_dest = "";
	my $query = "SELECT short_value FROM $table 
				 WHERE frame=$frame_id AND slot=$slot_value_type and 
					   value_type=$value_type_string AND short_value = 'Instance'";
	# Be careful to use third database connection, 
	# first one will be called from frame_name procedure, 
	# second one from modified attributes.
	my $sth = $dbh3->prepare($query);
	$sth->execute();
	# If the string value Instance is found, then go on to search destination classes
	if ($sth->fetchrow_hashref()) {
		# OK, Instance string value found for the frame, 
		# continue to find destination classes
		$query = "SELECT short_value FROM $table 
				 WHERE frame=$frame_id AND slot=$slot_value_type and 
					   value_type=$value_type_class";
#print "$query\n";
#logging($query);
		$sth = $dbh3->prepare($query);
		$sth->execute();
		while (my $ref = $sth->fetchrow_hashref()) {
			my $frame_id = $ref->{short_value};
			# Get attribute name
			my $attribute_name = frame_name($frame_id);
			$instance_dest .= $attribute_name.";";
		}
		# Remove last semicolon from instance_dest variable
		if (length($instance_dest) > 0) {
			$instance_dest = substr($instance_dest,0,-1);
		} else {
			error("Frame $frame_id slot Instance, but no destination classes found!");
		}
	}
	return $instance_dest;
}

=pod 

=head2 Handle Attribute

This procedure will all aspects of an attribute. For each attribute it will be investigated if the type is an "Instance". If so, then the instance destination will be added as well.

=cut

sub handle_attribute($$) {
	my ($attribute_id, $table) = @_;
	my ($attribute_name, $documentation, $instance_dest);
	$attribute_name = frame_name($attribute_id);
	$instance_dest = instance_destination($attribute_id);
	$documentation = class_documentation($attribute_id);
	write_attribute_info($table,$attribute_name,$documentation,$instance_dest);
}

=pod

=head2 Modified Attributes procedure

This procedure will handle all attributes for which the documentation is modified. These attributes can be found by querying for all facet ids 3001 (documentation) and is_template (r). The short_value/long_value gives the modified documentation, the attribute id is the slot field, and needs to be queried separately.

Note that is_template field is a bit value, no idea how to query this (and no idea why this would be required).

=cut

sub mod_attributes($$) {
	my($class_id, $classname) = @_;
	my $documentation = "";
	my $query = "SELECT slot, short_value, long_value FROM $table 
				 WHERE frame=$class_id AND facet=$slot_facet_documentation";
	# Be careful to use second database connection,
	# first one will be called from frame_name procedure.
	my $sth = $dbh2->prepare($query);
	$sth->execute();
	while (my $ref = $sth->fetchrow_hashref()) {
		my $slot_id = $ref->{slot};
		# Get modified documentation
		my $short = $ref->{short_value};
		my $long = $ref->{long_value};
		if (defined $short) {
			$documentation = $short;
		} elsif (defined $long) {
			$documentation = $long;
		} else {
			error("Attribute modified documentation found, but no documentation defined for class frame $class_id and attribute $slot_id");
		}
		# Get attribute name
		my $attribute_name = frame_name($slot_id);
		my $instance_dest = instance_destination($slot_id);
		write_attribute_info($classname, $attribute_name, $documentation, $instance_dest);
	}
}

=pod

=head2 Write Table Info

This procedure will write Protege table information into the cmdb metadata database.

=cut

sub write_table_info {
	my ($parent, $classname, $role, $documentation) = @_;
	my $sql = sprintf "INSERT INTO protegeTableInfo (parent, tablename, role, documentation)
				values ('$parent', '$classname', '$role', %s)", $dbmeta->quote($documentation);
	my $rows_affected = $dbmeta->do($sql);
	if (not defined $rows_affected) {
		error("PID: $$ - SQL Error with *** $sql");
	}
	$table_count++;
}

=pod

=head2 Write Attribute Info

This procedure will write Protege attribute information into the cmdb metadata database.

=cut

sub write_attribute_info {
	my ($table, $attribute, $documentation, $instance_dest) = @_;
	my $sql = sprintf "INSERT INTO protegeTableAttributes (tablename, attribute, documentation, destination)
				values ('$table', '$attribute', %s, '$instance_dest')", $dbmeta->quote($documentation);
	my $rows_affected = $dbmeta->do($sql);
	if (not defined $rows_affected) {
		error("PID: $$ - SQL Error with *** $sql");
	}
	$attribute_count++;
}

=pod

=head2 Extract Class Procedure

This Extract Class procedure is used to extract name and documentation information from this class. This subroutine will be called recursively, be careful to finalize all database connections before calling the subroutine again.

=cut

# Dummy declaration of the subroutine to allow recursive calling. Avoid "Called too early to check prototype error".
sub extract_class($$);

sub extract_class($$) {
	my ($class_id, $parent) = @_;
	my ($classname, $documentation, $role, @subclass, @attributes);
	# Get class name
	if ($class_id < 10000) {
		if ($class_id == 1000) {
			$classname = "THING";
		} else {
			$classname = $class_id;
		}
		$documentation = "";
		$role = "Abstract";
	} else {
		$classname = frame_name($class_id);
		$documentation = class_documentation($class_id);
		$role = class_role($class_id);
	}
	write_table_info($parent,$classname,$role,$documentation);
	# Collect and handle all direct attributes for the class
	@attributes = class_attributes($class_id);
	foreach my $attr_id (@attributes) {
		handle_attribute($attr_id, $classname);
	}
	# Collect and handle all modified attributes for the class
	# For now only work on modified documentation
	mod_attributes($class_id, $classname);
	# Collect and handle all subclasses.
	# This is where the recursive stuff comes into place.
	@subclass = class_subclasses($class_id);
	$parent = $classname;
	foreach my $subclass_id (@subclass) {
		extract_class($subclass_id, $parent);
	}
}

######
# Main
######

# Handle input values
my %options;
getopts("tl:h:", \%options) or pod2usage(-verbose => 0);
# This application does not require arguments
# my $arglength = scalar keys %options;  
# if ($arglength == 0) {			# If no options specified,
#    $options{"h"} = 0;			# display usage.
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

# Make database connection to database protegeTable
my $connectionstring = "DBI:mysql:database=$databasename;host=$server";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

# Make second database connection to database protegeTable
# my $connectionstring = "DBI:mysql:database=$databasename;host=$server";
$dbh2 = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh2) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

# Make third database connection to database protegeTable.
# Second one to collect modified instances, third one to collect destinations for slots of type Instance.
$dbh3 = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh3) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}


# Make database connection to cmdbMetaData database
$connectionstring = "DBI:mysql:database=$cmdbmetaDB;host=$server";
$dbmeta = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbmeta) {
   	error("Could not open $cmdbmetaDB, exiting...");
   	exit_application(1);
}

# Call Recursive subroutine
extract_class(1000, "Thing");

exit_application(0);

=head1 To Do

=over 4

=item *

Allow to specify database name and table name as input variables.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
