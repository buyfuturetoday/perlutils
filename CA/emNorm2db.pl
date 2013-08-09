=head1 NAME

Norm2db - Load normalized events into MySQL database.

=head1 VERSION HISTORY

version 1.1 27 July 2007 DV

=over 4

=item *

Add accepted delims array. This is an array of words that start with the delimiter, but should be read as normal words, not as database field identifiers. This array is the reserved words, elements of this array can never be used as field identifiers. The array needs to be maintained manually in the Variables section.

=back

version 1.0 9 June 2007 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will be called by an MRA to simulate forwarding of events. Events must be normalized. The events will be stored in a MySQL table. 

This can be used to analyze forwarded events, for testing and review purposes.

=head1 SYNOPSIS

Norm2db {-name value}

=head1 OPTIONS

=over 4

=item B<-name value>

name - value pairs. The name must be preceded by a dash "-" and the parameter name. There is no space between the dash and the parameter name.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.8.0, build 804 provided by ActiveState.

The script should run unchanged on UNIX platforms as well, on condition that all directory settings are provided as input parameters (-l, -p, -c, -d options).

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir,$value,$valuestring,%normfields,%accepted_delims,$dbh);
my $databasename="Events";
my $server="localhost";
my $username="root";
my $password="Monitor1";
my $printerror=0;
my $identifier = "-";		    # Unique identifier for Parameter names
my @accepted_delims_array = ($identifier,   # - occurs sometimes as stand-alone
							 "-c");			# -c is used in %CATD_I_060, SNMPTRAP field

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use DBI();
use UNINSM::Event qw(cawto);
use Log;

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
	if (defined $dbh) {
		$dbh->disconnect;
	}
#	logging("Exit application with return code $return_code.\n");
#    close_log();
    return $return_code;
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

=head2 Substitute Quotes

This procedure will substitute all double-quotes with single-quotes in all values. This will change values, but only during upload into the MySQL database. 

=cut

sub subst_quotes($) {
    my ($string) = @_;
    while (index($string,"\"") > -1) {
		substr($string,index($string,"\""),1,"'");
    }
	$string = subst_slash($string);
    return $string;
}

=pod

=head2 Substitute Slashes

This procedure will substitute all backward slashes with forward slashes in all values. This will change values, but only during upload into the MySQL database. 

=cut

sub subst_slash($) {
    my ($string) = @_;
    while (index($string,"\\") > -1) {
		substr($string,index($string,"\\"),1,"/");
    }
    return $string;
}



=pod

=head2 Handle Userdata procedure

Check if this is a AEC normalized events. If so extract source, subsource and instance value. Otherwise, ignore the data.

=cut

sub handle_name($$) {
	my ($name,$valuestring) = @_;
	if ($name eq "userdata") {
		my ($subsource,$instance) = split /\|/,$valuestring;
		if (defined $subsource) {
			$normfields{subsource} = $subsource;
		}
		if (defined $instance) {
			$normfields{instance} = $instance;
		}
	} elsif ($name eq "category") {
		my ($source,$newstate,$oldstate) = split /\|/,$valuestring;
		if (defined $source) {
			$normfields{source} = $source;
		}
		if (defined $oldstate) {
			$normfields{oldstate} = $oldstate;
		}
		if (defined $newstate) {
			$normfields{newstate} = $newstate;
		}
	} else {
		$normfields{$name} = subst_quotes($valuestring);
	}
}

=pod

=head2 Load Data procedure

Insert the record into the events database.

=cut

sub loadData($) {
	my ($table) = @_;
	my $insertstring;
    while (my($key, $value) = each %normfields) {
		$insertstring .= "$key=\"$value\",";
    }
	# Now remove last comma
	$insertstring = substr($insertstring,0,length($insertstring)-1);
	
	# Make database connection
	my $connectionstring = "DBI:mysql:database=$databasename;host=$server";
	my $dbh = DBI->connect($connectionstring, $username, $password,
			   {'PrintError' => $printerror,    # Set to 1 for debug info
			    'RaiseError' => 0});	    	# Do not die on error
	if (not defined $dbh) {
    	cawto "Perl loadData - Could not open $databasename, exiting...","k";
    	exit_application(1);
	}

	# Insert string into database table strevents
	my $query = "insert into $table set $insertstring";
    my $rows_affected = $dbh->do($query);
    if (not defined $rows_affected) {
		cawto "Perl loadData - Something strange when inserting ($query)","k";
#		error("PID: $$ - SQL Error with *** $query");
		exit_application(1);
    }
}

sub handle_record($$) {
	my($table,$argstring) = @_;
	undef %normfields;
	# Make accepted delims hash for easier usage
	foreach my $value (@accepted_delims_array) {
		$accepted_delims{$value} = 1;
	}

	my @argList = split / /,$argstring;

	# First argument must be a parameter name
	my $name = shift @argList;
	if (not($identifier eq substr($name,0,length($identifier)))) {
    	cawto "Perl handle_record $table - First value in arg list must be a parameter name as identified with $identifier","k";
    	exit_application(1);
	} else {
    	# Remove identifier from name
    	$name = substr($name,length($identifier));
	}

	$valuestring = "";
	$value = shift @argList;
	while (defined $value) {
		if ((not defined $accepted_delims{$value}) and 
		 	($identifier eq substr($value,0,length($identifier)))) {
			# Next parameter name found - Evaluate current name / value pair
			# Ignore if value is empty,
			# Initialize new name / value pair
			$valuestring = trim $valuestring;
			if (length($valuestring) > 0) {
				handle_name($name,$valuestring);
			}
			# Initialize new pair
			$name = $value;
			# Remove identifier from name
			$name = substr($name,length($identifier));
			$valuestring = "";
    	} else {
			$valuestring = $valuestring.$value." ";
    	}
   		$value = shift @argList;
	}
	# Now also handle the last value
	$valuestring = trim $valuestring;
	if (length($valuestring) > 0) {
		handle_name($name,$valuestring);
	}

	# End of argument list reached.
	# Verify data and write to MySQL database if OK.
	# only verify if host name exist.
	if (exists($normfields{host})) {
		loadData($table);
	} else {
		cawto "Perl handle_record $table - Found event without host, ignored...","k";
		exit_application(1);
	}
}

	


######
# Main
######

=pod

=head2 Handle Argument list

The parameter value can be 3 cases: no parameter value OR parameter value of one word OR parameter value of more than one word.

Read @ARGV until end of string or until new parameter name, add name/value pairs to a hash. The MRA calling this application must be synchronized with the database since no error checking will be done. The MRA must specify exact field names as key values. No field verification will be done, except check on the host name. The host name must exist.

=cut

sub Norm2db {
	my ($argstring) = @_;
	my $table="strevents";
	handle_record($table,$argstring);
	exit_application(0);
}

=pod

=head2 Open2DB

This module is triggered by ___OPEN3_ messages. These messages will be loaded into the openEvent table on the Events database. This should allow to analyze OPEN3 messages and compare them to the HANDLE messages, thus comparing legacy MRA behaviour and the newly proposed AEC approach. Goal is that all escalation messages from OPEN3 are available as HANDLE messages as well, except where there are agreed deviations.

Argument names must be the field names of the openevents table. Argument values should be relevant information.

=cut

sub Open2db {
	my ($argstring) = @_;
	my $table = "openevents";
	handle_record($table,$argstring);
	exit_application(0);
}


=pod

=head1 To Do

=over 4

=item *

Include error reporting to back to the event console using cawto (or display error messages on the console using a popup window.

=item *

Verify if timeticks need to be added to the temporary filename, to make them unique across days.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
