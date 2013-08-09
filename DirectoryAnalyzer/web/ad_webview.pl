=head1 NAME

ad_webview - Collects information from the Active Directory Business Process View to present the status of sites and servers.

=head1 VERSION HISTORY

version 1.1 24 July 2002 DV

=over 4

=item *

Initial release, based on the web.pl script (Peter Bellen, CA) as developed for the OPEX project.

=back

=head1 DESCRIPTION

The script displays the Active Directory Business Process View, including all sites and servers. For all sites and servers all the associated traps are displayed. The script runs as a CGI script in a Web Server.

This is a temporary solution that must be replaced by the Unicenter Portal solution.

=head1 SYNOPSIS

ad_webview req_position

=head1 OPTIONS

=over 4

=item *

req_position: String containing which entries to expand or collapse. By default all sites are shown collapsed. To expand the 4th site in the list, the req_position string is "0.;0.4.". To expand the 2nd server in the 4th site, the req_position string is "0.;0.4.;0.4.2.". A child tree can be expanded only if the parent tree is in the req_position string before the child tree. 

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows 2000, Perl v5.6.1, build 631 provided by ActiveState.

Due to the nature of the problem, the script should only be used on Windows platforms as CGI within IIS.

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my $trace = 0;			    # 0: no tracing, 1: tracing
my $logdir = "c:/temp";		    # Log file directory
my $log = 1;			    # 0: no logging, 1: logging
my $scriptname;
my $dsource = "TNGDB";		    # Data source name for TNG Database
my $tngdb;			    # Pointer to the DirectoryAnalyzer Database
my $bpv_master = "ActiveDirectory"; # BPV Master name
my $bpv_master_class = "BusinessView";	# BPV Master class name
#my $bpv_master = "TestBPV"; # BPV Master name
my $bpv_master_class = "BusinessView";	# BPV Master class name
my $refresh = 60;		    # Webview refresh interval (in seconds)
my ($iniclass, $ininame);

# my $site_class = "LargeCity";		# Site Class name
# my $server_class = "Large_Factory";	# Server Class name

#####
# use
#####

#use warnings;			    # show warning messages
#use strict 'vars';
#use strict 'refs';
#use strict 'subs';
use File::Basename;		    # logfilename translation
use Win32::ODBC;		    # Win32 ODBC module

#############
# subroutines
#############

sub error($) {
    my($txt) = @_;
    my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
    print "$datetime - Error: $txt\n";
    logging($txt);
}

sub trace($) {
    if ($trace) {
	my($txt) = @_;
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
	print "$datetime - Trace: $txt\n";
    }
}

# SUB - Open LogFile
sub open_log() {
    if ($log == 1) {
	($scriptname, undef) = split(/\./, basename($0));
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $logfilename=sprintf(">>$logdir/$scriptname%04d%02d%02d.log", $year+1900, $mon+1, $mday);
	open (LOGFILE, $logfilename);
	# open (STDERR, ">&LOGFILE");	    # STDERR messages into logfile
	# Ensure Autoflush for Log file...
	my $old_fh = select(LOGFILE);
	$| = 1;
	select($old_fh);
    }
}

# SUB - Handle Logging
sub logging($) {
    if ($log == 1) {
	my($txt) = @_;
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $datetime = sprintf "%02d/%02d/%04d %02d:%02d:%02d",$mday, $mon+1, $year+1900, $hour,$min,$sec;
	print LOGFILE $datetime." * $txt"."\n";
    }
}

# SUB - Close log file
sub close_log() {
    if ($log == 1) {
	close LOGFILE;
    }
}

sub exit_application($) {
    my($return_code) = @_;
    if (defined $tngdb) {
	$tngdb->Close();
	logging("Close Database connection.");
    }
    logging("Exit application with return code $return_code\n");
    close_log();
    exit $return_code;
}

sub SQLquery($$) {
  my($db, $query) = @_;
  if ($db->Sql($query)) {
    my ($errnum, $errtext, $errconn) = $db->Error();
    error("$errnum.$errtext.$errconn\n$query\n$db");
    $db->Close();
    exit();
  }
}

############################################################################
# The Originals
############################################################################

sub htmlout {
	my $line = "@_";
	print $line . "\n";
}

sub uuid2str ($) {
	my ($uuid) = @_ ;
	@unp_uuid = unpack "N1n1n1H4H12", $uuid;
	@unp_uuid[0] = unpack "H8",(pack "l",@unp_uuid[0]);
	@unp_uuid[1] = unpack "H4",(pack "l",@unp_uuid[1]);
	@unp_uuid[2] = unpack "H4",(pack "l",@unp_uuid[2]);
	return (join "-", @unp_uuid);
}

sub uuid2hexstr ($) {
	my ($uuid) = @_ ;
	@unp_uuid = unpack "H32", $uuid;
	return ("0x".join "",@unp_uuid);
}

sub SQLquery ($$) {
    my($database,$query) = @_;
    trace("DB: $database, Query: $query");
    if ($database->Sql($query)) {
	my($errnum, $errtext, $errcon) = $database->Error();
	error("SQL query failed: $query");
	error("$errnum $errtext $errcon");
	exit_application(1);
    }
}

=pod

=head2 Children procedure

Find all children for an object

=cut

sub Children($$$$$$) {
    my ($db,$parentuuid,$action,$oldpos,$oldlast,$open) = @_;
    my %Children;
    my $count = 0;
    my $NumChild = 0;
    my $found = 0;
	
    $hexuuid = uuid2hexstr($parentuuid);
    SQLquery($db, "SELECT child_uuid,child_class FROM tng_inclusion WHERE parent_uuid = $hexuuid");
    while ($db->FetchRow()) {
    	%Data = $db->DataHash;
	$childuuid = $Data{child_uuid};
	$Children{$childuuid} = 1;
    }
    $NumChild = keys %Children;

    if ($action ne "ProcessObject") { error("Action: $action"); }
    &$action($db,$parentuuid,$oldpos,$NumChild,$oldlast,$open);

    # This finds out if the folder is open or closed
    foreach (split /;/, $open) {
	($_ eq $oldpos) && ($found = 1);
    }
    if ($found) {
	foreach $uuid (keys %Children) {
	    $newpos = $oldpos . ++$count . ".";
	    $newlast = $oldlast . "." . ($NumChild == $count ? "1" : "0" );
	    Children($db,$uuid,$action,$newpos,$newlast,$open);
	}
    }
}

=pod

=head2 Process Object

Process the object ...

=cut

sub ProcessObject {
    my ($db,$uuid,$position,$NumChild,$Last,$open) = @_ ;
    my $newurl="";
    my $pos_found = 0;
    local $ChangeTime="";	
    # We only have to bother about calculating a new URL if we have children...
    if ($NumChild) {
	# If position is on our selection tree, we cut of one digit, this will
	# make the tree collapse on subsequent click ...
	foreach (split /;/,$open) {
	    if ( /^$position/ ) {
		$pos_found = 1;
	    } else {
		$newurl .= $_ . ";";
	    }
	}
    }
    $pos_found or ( $newurl .= $position ) ;
    $depth = ( @LastArr = split /\./,$Last ) -1;
    $hexuid = uuid2hexstr($uuid);
    SQLquery($db, "SELECT name,label,propagated_sev,class_name FROM tng_managedobject WHERE uuid = $hexuid");
    if ($db->FetchRow()) {
	%Data = $db->DataHash;
	$name = $Data{name};
	$label = $Data{label};
	$class = $Data{class_name};
	$sever = $Data{propagated_sev};
    }
    $window = "Open";
    if ($sever == 2 || $sever == 3 )  {$color = "Orange"; $icon="daemon1.gif" ; $text = "Warning"; }
    elsif ($sever == 0 ) { $color = "Green"; $icon="daemon0.gif" ;$text = "Normal";}
    elsif ($sever == 6 ) { $color = "Gray"; $icon="daemon3.gif" ;$text = "None"; $window = "Closed"}
    else {$color = "Red"; $icon="daemon2.gif";$text = "Critical"; }
    $name =~ s/ /%20/g;
    htmlout "<table border=0 cellspacing=0 cellpadding=0>";
    htmlout "<tr valign=middle>";
    if (@LastArr[$depth]) {
	$line = "Images/LineLast";
    } else {
	$line = "Images/LineNode";
    }
    if ($NumChild) {
	if ($pos_found) {
	    $line .= "Open";
	} else {
	    $line .= "Closed";
	}
    }
    $line .= ".gif";

    print "<td>";
    foreach $elem (@LastArr[0..$depth-1]) {
	if ($elem) {
	   print "<img border=noborder height=0 width=20>";
	} else {
	   print "<img border=noborder src=Images/Line.gif>";
	}
    }
    if ( $NumChild ) {
	print "<a href=$scriptname.pl?req_position=$newurl&req_appname=$req_appname style=\"color: $color\"><img src=$line border=noborder><img border=noborder src=Images/$window$color.gif></a>";
    } else {
	print "<img src=$line border=noborder><img border=noborder src=Images/$window$color.gif>";
    }
    htmlout "</td>";
    htmlout "<td><div class=item><FONT COLOR=$color>&nbsp;$label$ChangeTime</FONT></div></td>";
    htmlout "</tr>";
    htmlout "</table>";
}

########
# Main 
########

open_log();
logging("Start application");

$input="$ENV{QUERY_STRING}";
@params = split /&/, $input ;
foreach $par (@params) {
  printf("%s\n",$par);
  ($name,$value) = split /=/, $par;
  $$name = $value;
}

$iniclass = $bpv_master_class;
$ininame = $bpv_master;
$ininame =~ s/%20/ /g;

# Connect to TNG COR
if (!($tngdb = new Win32::ODBC("DSN=$dsource;UID=sa;PWD="))) {
	error("SQL open failed on $dsource: ".Win32::ODBC::Error());
	exit_application(1);
}

# Get uuid of the initial object
SQLquery($tngdb, "SELECT uuid FROM tng_managedobject WHERE name = \'$ininame\' and class_name = \'$iniclass\'");
if ($tngdb->FetchRow()) {
	my %Data = $tngdb->DataHash;
	$uuid = $Data{uuid};
#	printf "%s has uuid %s %s\n",$ininame,uuid2str($uuid),uuid2hexstr($uuid);
} else {
	error("Object ($ininame) not found in TNG CORE database");
	exit_application(1);
}

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$year+=1900;
my $month=("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec")[$mon];
my $datetime = sprintf "%02d %s %4d %02d:%02d:%02d",$mday,$month,$year,$hour,$min,$sec;

htmlout "Content-type: text/html\n";
htmlout "<HTML>";
htmlout "<meta http-equiv=Refresh content=$refresh>";
htmlout "<HEAD>";
htmlout "<STYLE>";
htmlout ".item{FONT-SIZE: .85em}";
htmlout "</STYLE>";
htmlout "<TITLE>Active Directory Status</TITLE></HEAD>";
htmlout "<BODY>";
htmlout "<table border=1 cellspacing=0 cellpadding=0>";
htmlout "<tr><th align=center bgcolor=Pink>Active Directory Status Overview<br>";
htmlout "Reported by $ENV{COMPUTERNAME} on $datetime</th><tr>";
htmlout "<tr><td>";
# Do ProcessObject for uuid and it's children.
Children($tngdb,$uuid,"ProcessObject","0.",1,$req_position);
htmlout "</td></tr>";
htmlout "</table>";

htmlout "</BODY>";
htmlout "</HTML>";

exit_application(0);

=pod

=head1 TO DO

=over 4

=item *

Develop the script

=back

=head1 AUTHOR

Original script: Peter Bellen (CA) - 2000.

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
