package dbParams;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw($server $port $username $password $databasename $resultdb $resultdir);

###########
# Variables
###########

$port = 3306;
# $port = 8009;
$databasename="filedata";
$resultdb="vo_results";
$server="localhost";
$username="root";
$password="Monitor1";
$resultdir="d:/temp/vo_results";

1;
