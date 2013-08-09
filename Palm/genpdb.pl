#!/usr/bin/perl -w

=head1 NAME

genpbd.pl - Script to generate a "Bundesliga" PDB file from a textual
list of teams, matches and results.

=head1 SYNOPSIS

genpdb.pl <text file> [database name]

=head1 DESCRIPTION

You can use this script to generate a PDB file suitable to be used with
Bundesliga. This script takes a textual list of all teams, matches and
results of the following form:

 TEAMBLOCK
 MATCHBLOCK
 ...
 MATCHBLOCK

The TEAMBLOCK builds the list of teams, each team in one line,
each line not longer than 20 chars. The last line must be an empty
line.

Each of the maximum 90 MATCHBLOCKs lists the matches of one match
day. It can optionally start with a date line of the form YYYYMMDD
(this is the old format).  Each line following is of one of the
following forms:

 Team 1:Team 2:
 Team 1:Team 2:e1:e2
 YYYYMMDDhhmm:Team 1:Team 2:
 YYYYMMDDhhmm:Team 1:Team 2:e1:e2
 :=ph:Team 1:val
 :=gh:Team 1:val

The B<Team 1:Team 2:> form simply tells the script who's going to
play against whom; B<Team 1> and B<Team 2> must have been listed in
the TEAMBLOCK.

The B<Team 1:Team 2:e1:e2> form includes a result for the match. B<e1> and
B<e2> should be 0 or positive integers less than 255.

The B<YYYYMMDDhhmm:Team 1:Team 2:> and B<YYYYMMDDhhmm:Team 1:Team 2:e1:e2> 
form include a match date.

The remaining two forms B<:=ph:Team 1:val> and B<:=gh:Team 1:val>
define either a point (B<=ph:>) or a goal (B<=gh:>) handicap for the
team listed next, with value B<val>. For example, the line

 :=ph:Basel:17

gives the team Basel a credit of 17 points, valid with the match day
this line is included in. Handicaps can also be negative values.

Each MATCHBLOCK (except the very last one) must end with an
empty line to separate it from the next one.

=head1 EXAMPLE

The following snippet is a valid text file; it lists the first
two match days with results from the Swiss Masters Round 2001.

 Basel
 FC Sion
 Genf
 FC Zürich
 Grasshopper
 Lausanne
 Lugano
 St. Gallen
 
 :=ph:Basel:17
 :=ph:FC Sion:16
 :=ph:Genf:17
 :=ph:FC Zürich:15
 :=ph:Grasshopper:18
 :=ph:Lausanne:17
 :=ph:Lugano:21
 :=ph:St. Gallen:20
 200102241530:Grasshopper:St. Gallen:2:1
 200102241530:Lausanne:FC Zürich:1:1
 200102241530:Lugano:FC Sion:1:1
 200102241800:Genf:Basel:3:0
 
 20010304
 St. Gallen:Lugano:3:2
 FC Zürich:Genf:1:0
 FC Sion:Grasshopper:2:0
 Basel:Lausanne:0:0

=head1 COPYRIGHT

genpdb.pl (c) Thomas Pundt 2001

Permission to use, copy, modify, and distribute this software for any
purpose, without fee, and without a written agreement is hereby granted,
provided that the above copyright notice and this paragraph and the
following two paragraphs appear in all copies.

IN NO EVENT SHALL THE AUTHOR BE LIABLE TO ANY PARTY FOR DIRECT, INDIRECT,
SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING LOST PROFITS,
ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF
THE AUTHOR HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

THE AUTHOR SPECIFICALLY DISCLAIMS ANY WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
PARTICULAR PURPOSE. THE SOFTWARE PROVIDED HEREUNDER IS ON AN "AS IS"
BASIS, AND THE AUTHOR HAS NO OBLIGATIONS TO PROVIDE MAINTENANCE, SUPPORT,
UPDATES, ENHANCEMENTS, OR MODIFICATIONS.

=cut


use PDA::Pilot; # from the pilot-link package.
use POSIX qw(mktime);

sub usage()
{
  print "Usage: genpdb.pl <Text-File> [Name]\n";
  exit;
}

usage() if ($#ARGV == -1);

open FILE, $ARGV[0] or usage();

%htype = ( "=ph"=>0, "=gh"=>1);

$state = "<ReadTeamNames>";
$rec = "";
$secs_since_70 = 24107 * 86400 + 3600;
$lastWithResult = 1;

while(<FILE>) {
  chomp();

  if (/^\s*#\s*(name="(.*?)")?/) {
    $liga = $2 if ($2);
    next;
  }

  if ($state eq "<ReadTeamNames>") {
    if ($_ eq "") {
      $state = "<ReadMatchDays>";
      push @recs, $rec;
      $matches = $numHandicaps = $date = 0;
      $handicap = $rec = "";
      $recnum = 1;
      next;
    }

    $rec .= "$_\0";
    if (length($_)>20) {
      print "'$_' has more than 20 chars; team names\n".
	"longer than 20 chars will generate runtime errors. Please fix.\n";
      exit;

    }
    $team{$_} = ++$numTeams;
    if ($numTeams>24) {
      print "Bundesliga can't handle more than 24 teams per league\n";
      exit;
    }
    next;
  }

  if ($state eq "<ReadMatchDays>") {
    if ($_ eq "") {
      push @recs, sprintf("%c%c%s%s", 
			  $matches, $numHandicaps, $rec, $handicap);
      $matches = $numHandicaps = $date = 0;
      $handicap = $rec = "";
      $recnum++;
      next;
    }

    if (/^(\d{4})(\d{2})(\d{2})$/) {
      if ($1+$2+$3>0) {
	$date = mktime(0, 30, 15, $3, $2-1, $1-1900) + $secs_since_70;
      } else {
	print "Malformed date: $1$2$3 - ignored.\n";
	next;
      }
      next;
    }

    #
    # point or goal handicap
    #
    if ( /^:(=ph|=gh):(.*?):(-?\d+)$/ ) {
      if ($team{$2}>0) {
	$handicap .= sprintf "%c%c%c", $htype{$1}, $team{$2}, $3;
	$numHandicaps++;
      } else {
	print "'$2' listed in handicap is not in teams list - ignored\n";
	next;
      }
      next;
    }

    if (/^(\d+:)?(.*?):(.*?):((\d+):(\d+))?$/) {
      $m1 = $team{$2}; $m2 = $team{$3};
      if ($m1 && $m2 && $m1>0 && $m2>0) {
	if ($4) {
	  $e1 = $5; $e2 = $6;
	  $lastWithResult = $recnum;
	} else {
	  $e1 = $e2 = 255;
	}
      } else {
	print "$_ is not a valid match - ignored\n";
	next;
      }
      if ($1 && $1 =~ /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})/) {
	$date = mktime(0, $5, $4, $3, $2-1, $1-1900) + $secs_since_70;
      }
#     printf "%d %d %d %d %u\n", $m1, $m2, $e1, $e2, $date; 
      $rec .= sprintf("%c%c%c%c%c%c%c%c", $m1, $m2, $e1, $e2,
		      ($date & 0xff000000)>>24, 
		      ($date & 0xff0000)>>16, 
		      ($date & 0xff00)>>8, 
		      ($date & 0xff) );
      $matches++;
    }

  }

}
close FILE;

push @recs, sprintf("%c%c%s%s", 
		    $matches, $numHandicaps, $rec, $handicap)
  if ($rec ne "");

$recnum = $#recs;
$rec = sprintf("\0\7%c%c%c%c%c%c\0\0",
	       $lastWithResult/256, $lastWithResult%256,
	       $numTeams/256, $numTeams%256,
	       $recnum/256, $recnum%256);

$name = $ARGV[0];
$name = $1 if ($ARGV[0] =~ /(.*?)\.txt/);
$pdbname = $name;
$pdbname = $liga if ($liga);
$pdbname = $ARGV[1] if ($#ARGV>0);

%info = ("type"=>"Data","creator"=>"tpBL","name"=>"$pdbname");
$pdb = PDA::Pilot::File::create("$name.pdb", \%info ) 
  or die "something went wrong\n";

$i = 0;
$pdb->addRecordRaw($rec,$i++,0,0);
foreach (@recs) {
  $pdb->addRecordRaw($_,$i++,0,0);
}

# printf "$lastWithResult|$numTeams|$recnum:%d\n",$#recs;
