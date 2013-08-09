package MySQLModules;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw($printerror $triggerint get_all_tables get_new_tables check_results_db connect2masterdb);

###########
# Variables
###########

$printerror=0;
$triggerint=999999;		# Value used as trigger for invalid numbers

#####
# use
#####

use Log;
use dbParams;

=pod

=head2 Connect to Master Database

This procedure will connect to the MySQL Master database.

=cut

sub connect2masterdb () {
	my $masterdatabase = "information_schema";
	# Make database connection for MySQL master database
	my $connectionstring = "DBI:mysql:database=$masterdatabase;host=$server;port=$port";
	my $dbm = DBI->connect($connectionstring, $username, $password,
							{'PrintError' => $printerror,    # Set to 1 for debug info
				   			 'RaiseError' => 0});	    	# Do not die on error
	if (defined $dbm) {
		return $dbm;
	} else {
   		error("Could not open $masterdatabase, exiting...");
		return undef;
	}

}

=pod

=head2 Get All Tables

Get all tables from the filedata database. Each table corresponds with a drive on a fileserver. 

=cut

sub get_all_tables() {
	# Empty array table_arr
	my @table_arr=();
	my $dbm = connect2masterdb() or return undef;
	# Get all tablenames for database filedata
	my $query = "SELECT table_name FROM tables WHERE table_schema = '$databasename'";
	my $sth = $dbm->prepare($query);
	my $rv = $sth->execute();
	if (not(defined $rv)) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		return undef;
	}
	while (my $ref = $sth->fetchrow_hashref) {
		my $table_name = $ref->{table_name};
		push @table_arr,$table_name;
	}
	$dbm->disconnect;
	return @table_arr;
}

=pod

=head2 Get New Tables

Get new tables from the filedata database. Each table corresponds with a drive on a fileserver. Only tables that are created after date YYYY-MM-DD will be listed (create_time > 'YYYY-MM-DD').

=cut

sub get_new_tables($) {
	my ($newtablesdate) = @_;
	# Empty array table_arr
	my @table_arr=();
	my $dbm = connect2masterdb() or return undef;
	# Get all tablenames for database filedata
	my $query = "SELECT table_name FROM tables 
				 WHERE table_schema = '$databasename' AND create_time > '$newtablesdate'";
	my $sth = $dbm->prepare($query);
	my $rv = $sth->execute();
	if (not(defined $rv)) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		return undef;
	}
	while (my $ref = $sth->fetchrow_hashref) {
		my $table_name = $ref->{table_name};
		push @table_arr,$table_name;
	}
	$dbm->disconnect;
	return @table_arr;
}

=pod

=head2 Check Results DB

This procedure will check if the Results DB exists. It will be created if it does not exist already.

=cut

sub check_results_db($) {
	my ($resultdbname) = @_;
	my $dbm = connect2masterdb() or return undef;	
	my $query = "SELECT count(*) as rescount FROM schemata WHERE schema_name='$resultdbname'";
	my $sth = $dbm->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, Error: ".$sth->errstr);
		return undef;
	}
	my $rescount = 0;
	if (my $ref = $sth->fetchrow_hashref) {
		$rescount = $ref->{rescount};
	}
	$sth->finish();
	if ($rescount == 0) {
		# Create database if it does not exists already
		$query = "CREATE DATABASE `$resultdbname`";
		$rv = $dbm->do($query);
		if (defined $rv) {
			logging("Database $resultdbname created");
			return 1;
		} else {
			error("Could not create Result Database $resultdbname. Query: $query - Error ".$dbm->errstr);
			return undef;
		}
	} else {
		# Results Database exists, return success
		return 1;
	}
}

1;
