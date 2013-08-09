=head1 NAME

ExtractMailReport - Extract data for the Mail reporting

=head1 VERSION HISTORY

version 1.0 01 July 2009 DV

=over 4

=item *

Initial release.

=back

=head1 DESCRIPTION

This application will create the mail report, that allows to assign storage costs from mail to the entiteiten.

The report currently uses the tables stg_f_mail_performanties and stg_d_entiteiten.

=head1 SYNOPSIS

 ExtractMailReport.pl [-t] [-l log_dir]

 ExtractMailReport -h	   Usage
 ExtractMailReport -h 1	   Usage and description of the options
 ExtractMailReport -h 2	   All documentation

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

my ($logdir,$dbh, $dbh2);
my $username = "root";
my $password = "Monitor1";
my $server = "localhost";
my $databasename = "storage";
my $printerror = 0;
my $outfile = "D:/Projects/Vo/Storage Rapportage/reports/mailreport.csv";

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
		$dbh2->disconnect;
	}
	close RES;
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

=head2 Get Entiteit

This procedure will get entiteit data. For any entiteit number, it will collect entiteit type and entiteit naam.

=cut

sub get_entiteit($) {
	my ($d_entiteit_id) = @_;
	my $entiteit_tp = "unknown";
	my $entiteit_nm = "unknown";
	my $niveau_1_cd = "unknown";
	my $niveau_2_cd = "";
	my $niveau_3_cd = "";
	my $niveau_4_cd = "";
	my $niveau_5_cd = "";
	my $niveau_6_cd = "";
	my $niveau_7_cd = "";
	my $query = "SELECT entiteit_tp, entiteit_nm, niveau_1_cd, niveau_2_cd, niveau_3_cd, niveau_4_cd, niveau_5_cd, niveau_6_cd, niveau_7_cd from stg_d_entiteiten where d_entiteit_id = $d_entiteit_id";
	my $sth = $dbh2->prepare($query);
	if (not(defined $sth->execute())) {
		error("Error with query $query, ".$sth->errstr);
		exit_application(1);
	}
	# Add Entiteit info to disk space usage
	if (my $ref = $sth->fetchrow_hashref()) {
		$entiteit_tp = $ref->{entiteit_tp} || "unknown";
		$entiteit_nm = $ref->{entiteit_nm} || "unknown";
		$niveau_1_cd = $ref->{niveau_1_cd} || "unknown";
		$niveau_2_cd = $ref->{niveau_2_cd} || "";
		$niveau_3_cd = $ref->{niveau_3_cd} || "";
		$niveau_4_cd = $ref->{niveau_4_cd} || "";
		$niveau_5_cd = $ref->{niveau_5_cd} || "";
		$niveau_6_cd = $ref->{niveau_6_cd} || "";
		$niveau_7_cd = $ref->{niveau_7_cd} || "";
	}
	return ($entiteit_tp, $entiteit_nm, $niveau_1_cd, $niveau_2_cd, $niveau_3_cd, $niveau_4_cd, $niveau_5_cd, $niveau_6_cd, $niveau_7_cd, );
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

# Make database connection to database Information_Schema database
my $connectionstring = "DBI:mysql:database=$databasename;host=$server";
$dbh = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh) {
   	error("Could not open $databasename, exiting...");
   	exit_application(1);
}

# Make second database connection, since 2 queries are required concurrently
$dbh2 = DBI->connect($connectionstring, $username, $password,
		   {'PrintError' => $printerror,    # Set to 1 for debug info
		    'RaiseError' => 0});	    	# Do not die on error
if (not defined $dbh2) {
   	error("Could not open second connection to $databasename, exiting...");
   	exit_application(1);
}

# Open outputfile for writing
my $openres = open(RES, ">$outfile");
if (not defined $openres) {
	error("Could not open $outfile for writing, exiting...");
	exit_application(1);
}
# Print title line
print RES "d_entiteit_id; Entiteit type; Entiteit naam; Niveau 1; Niveau 2; Niveau 3; Niveau 4; Niveau 5; Niveau 6; Niveau 7; mailsize; trashsize; archiefsize\n";

# Query for disk space usage grouped by entity
my $query = "SELECT d_entiteit_id, sum( grootte_mtrk ) AS mailsize, sum( trashsize_mtrk ) AS trashsize, 
					sum( gebruikte_archief_mtrk ) AS archiefsize 
			 FROM stg_f_mail_performanties
			 GROUP BY d_entiteit_id"; 
my $sth = $dbh->prepare($query);
if (not(defined $sth->execute())) {
	error("Error with query $query, ".$sth->errstr);
	exit_application(1);
}
# Add Entiteit info to disk space usage
while (my $ref = $sth->fetchrow_hashref()) {
	my $d_entiteit_id = $ref->{d_entiteit_id};
	my $mailsize = $ref->{mailsize} || 0;
	my $trashsize = $ref->{trashsize} || 0;
	my $archiefsize = $ref->{archiefsize} || 0;
	my ($entiteit_tp, $entiteit_nm, $niveau_1_cd, $niveau_2_cd, $niveau_3_cd, $niveau_4_cd, $niveau_5_cd, $niveau_6_cd, $niveau_7_cd) = get_entiteit($d_entiteit_id);
	print RES "$d_entiteit_id; $entiteit_tp; $entiteit_nm; $niveau_1_cd; $niveau_2_cd; $niveau_3_cd; $niveau_4_cd; $niveau_5_cd; $niveau_6_cd; $niveau_7_cd; $mailsize; $trashsize; $archiefsize\n";
}

exit_application(0);

=head1 To Do
i Here a lot of documentation should be added.



=over 4

=item *

Allow to specify database name and table name as input variables.

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
