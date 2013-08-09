=head1 NAME

drupalFuncs - Drupal specific functions

=head1 VERSION HISTORY

version 1.0 - 07 March 2010

=over 4

=item *

Initial release

=back

=head1 SYNOPSIS

 use drupalFuncs;

 addbook(BookTitle, BookContent);

=head1 DESCRIPTION

This module provides all kind of Drupal functions.

=cut

########
# Module
########

package drupalFuncs;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(addbook getnode);

###########
# Variables
###########


#####
# use
#####

use warnings;
use strict;
use Log;
use DBI();

#############
# subroutines
#############

=pod

=head2 Get Node(dbHandle, nodeId)

This procedure will get the node title and the node content for a given node id. This procedure assumes for now that node revisions are not used. There is only one revision version per node.

=cut

sub getnode {
	my ($dbh, $nid) = @_;
	my $query = "SELECT title, body
						FROM node_revisions
						WHERE nid=$nid";
	my $sth = $dbh->prepare($query);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Error executing query $query, ".$sth->errstr);
		return undef;
	}
	my $ref = $sth->fetchrow_hashref();
	my $title = $ref->{title};
	my $body = $ref->{body};
	$sth->finish;
	return ($title, $body);
}

=pod

=head2 addbook(dbHandle, BookTitle, BookContent)

This procedure will create a book record. The book title and the book content are input parameters. A node page and a menu entry will be created. The node ID and the menu link id are returned.

=cut

sub addbook {
	my ($dbh, $booktitle, $bookcontent, $plid) = @_;
	my ($nid, $mlid);
	if (not defined $booktitle) {
		$booktitle = "Undefined Book Title";
	}
	if (not defined $bookcontent) {
		$bookcontent = "";
	}
	$nid = addnode($dbh, $booktitle, $bookcontent);
	if (not defined $nid) {
		return undef;
	}
	if (defined $plid) {
		$mlid = addbookrecord($dbh, $nid, $booktitle, $plid);
	} else {
		$mlid = addbookrecord($dbh, $nid, $booktitle);
	}
	if (not defined $mlid) {
		return undef;
	}
	return ($nid, $mlid);
}

=pod

=head2 addnode(dbHandle, nodeTitle, nodeContent)

This procedure will create a node. The node title and the node content are input, the node id is returned to the calling application.

=cut

sub addnode {
	my ($dbh, $title, $content) = @_;
	my ($nid, $vid);
# Import title into node table
	my $query = "INSERT INTO node (nid, vid, type, language, title, uid, status, created, changed, comment, promote, moderate, sticky, tnid, translate)
						VALUES (0, 0, 'page', '', ?,1,1,?,?,0,0,0,0,0,0)";
	my $sth = $dbh->prepare($query);
	my $now = time();
	$sth->bind_param(1, $title);
	$sth->bind_param(2, $now);
	$sth->bind_param(3, $now);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Error while inserting article $title, ". $sth->errstr);
		return undef;
	} elsif (not ($rv == 1)) {
		error("$rv rows inserted for $title, 1 expected");
	}
	
	# Get last insert id
	$nid = $dbh->{insertid};
	
	# Import article into node revisions table
	$query = "INSERT INTO node_revisions (nid, vid, uid, title, body, teaser, log, timestamp, format)
					VALUES (?,0,1,?,?,?,'',?,2);";
	$sth = $dbh->prepare($query);
	$sth->bind_param(1, $nid);
	$sth->bind_param(2, $title);
	$sth->bind_param(3, $content);
	$sth->bind_param(4, $content);
	$sth->bind_param(5, $now);
	$rv = $sth->execute();
	if (not defined $rv) {
		error("Error while inserting article $title in node_revision, ". $sth->errstr);
		return undef;
	} elsif (not ($rv == 1)) {
		error("$rv rows inserted for $title in node_revision, 1 expected");
	}
	
	# Get vid to update node table
	$vid = $dbh->{insertid};
	$query = "UPDATE node SET vid=? WHERE nid=?";
	$sth = $dbh->prepare($query);
	$sth->bind_param(1, $vid);
	$sth->bind_param(2, $nid);
	$rv = $sth->execute();
	if (not defined $rv) {
		error("Error while inserting vid $vid in node table for node $nid, ". $sth->errstr);
		return undef;
	} elsif (not ($rv == 1)) {
		error("$rv rows inserted for node $nid in node table, 1 expected");
	}
	
	# Apparantly there should be a comment record for each node id
	# or should it?
	$query = "INSERT INTO node_comment_statistics (nid, last_comment_timestamp, last_comment_uid, comment_count)
					VALUES (?, ?, 1, 0)";
	$sth = $dbh->prepare($query);
	$sth->bind_param(1, $nid);
	$sth->bind_param(2, $now);
	$rv = $sth->execute();
	if (not defined $rv) {
		error("Error while inserting vid $vid in node table for node $nid, ". $sth->errstr);
	} elsif (not ($rv == 1)) {
		error("$rv rows inserted for node $nid in node table, 1 expected");
	}
	return $nid;
}

=pod

=head2 addBookRecord(dbHandle, nodeID, linkTitle, parent) 

This procedure will add a book record to the menu_links table and to the Book table.

If a menu linkt to parent is defined, then read the parent menu information. IF parent doesn't have children yet, update parent to indicate that there are children. Read parent information to get menu_name, depth and path structure (list of parents).

=cut

sub addbookrecord() {
	my ($dbh, $nid, $link_title, $plid) = @_;
	my ($menu_name, $has_children, $depth);
	my $parentfields = "";
	my $parentvalues = "";
	my $menu_string = "book-toc-";
	if (not defined $link_title) {
		$link_title = "Undefined Link Title";
	}
	if (defined $plid) {
		# Get parent record
		my $query = "SELECT menu_name, has_children, depth,
					        p1, p2, p3, p4, p5, p6, p7, p8
					 FROM menu_links
					 WHERE mlid = ?";
		my $sth = $dbh->prepare($query);
		$sth->bind_param(1, $plid);
		my $rv = $sth->execute();
		if (not defined $rv) {
			error("Error executing query $query, ".$sth->errstr);
			return undef;
		}
		# Now handle parent record
		if (my $ref = $sth->fetchrow_hashref()) {
			$menu_name = $ref->{menu_name};
			$has_children = $ref->{has_children};
			$depth = $ref->{depth};
			if ($has_children == 0) {
				# First child for this parent
				setChild($dbh, $plid);
			}
			for (my $cnt = 1; $cnt <= $depth; $cnt++) {
				my $refvalue = "p".$cnt;
				my $parent = $ref->{$refvalue};
				$parentfields .= ", $refvalue";
				$parentvalues .= ", $parent";
				# Parent link for this node is last entry from parent tree
				# Update entry on each iteration
				$plid = $parent;
			}
			# Make sure depth is incremented for new record
			$depth++;
			$sth->finish;
		} else {
			error("No parent record $plid found for node $nid");
			$sth->finish;
			return undef;
		}
	} else {
		# New Book
		$menu_name = $menu_string . $nid;
		$has_children = 0;
		$depth = 1;
		$plid = 0;
	}
	# Complete book information
	my $link_path = "node/" . $nid;
	my $router_path = "node/%";
	my $options = "a:0:{}";

	my $query = "INSERT INTO menu_links
					(menu_name, plid, link_path, router_path, link_title, options, 
					 module, has_children, depth $parentfields)
				 VALUES (?,?,?,?,?,?,'book',?,? $parentvalues)";
	my $sth = $dbh->prepare($query);
	$sth->bind_param(1, $menu_name);
	$sth->bind_param(2, $plid);
	$sth->bind_param(3, $link_path);
	$sth->bind_param(4, $router_path);
	$sth->bind_param(5, $link_title);
	$sth->bind_param(6, $options);
	$sth->bind_param(7, $has_children);
	$sth->bind_param(8, $depth);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Error with query $query, " . $sth->errstr);
		return undef;
	}
	# Get menu link id to update menu link record
	my $mlid = $dbh->{insertid};
	my $pfield = "p" . $depth;
	my $pvalue = $mlid;
	$query = "UPDATE menu_links SET $pfield = $pvalue
				WHERE mlid = $mlid";
	$rv = $dbh->do($query);
	if (not defined $rv) {
		error("Error executing query $query, ".$dbh->errstr);
		return undef;
	}
	# Update book table
	my $bid = substr($menu_name, length($menu_string));
	$query = "INSERT INTO book (mlid, nid, bid)
				VALUES ($mlid, $nid, $bid)";
	$rv = $dbh->do($query);
	if (not defined $rv) {
		error("Error executing query $query, " . $dbh->errstr);
		return undef;
	}
	return $mlid;
}
			
=pod

=head2 setChild(dbHandle, mlid)

mlid points to a book page entry that will get a child page. Update has_child to 1 for this menu link. There are no return values. In case something went wrong, there will be an error message in the log file.

=cut

sub setChild {
	my ($dbh, $mlid) = @_;
	my $query = "UPDATE menu_links SET has_children=1 WHERE mlid=?";
	my $sth = $dbh->prepare($query);
	$sth->bind_param(1, $mlid);
	my $rv = $sth->execute();
	if (not defined $rv) {
		error("Could not execute query $query, ".$sth->errstr);
	}
	$sth->finish;
	return;
}
		
1;

=pod

=head1 TO DO

=over 4

=item *

Nothing documentef for now...

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@skynet.beE<gt>
