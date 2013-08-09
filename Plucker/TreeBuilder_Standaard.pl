=head1 NAME

Standaard.pl - Collects the daily opinion from the Standaard web site.

=head1 DESCRIPTION

The "Commentaar" section is available on http://wwww.standaard.be/standpunt/commentaar. The page is collected and parsed for the element "class=mdl_txt". This contains the title (class=mdl_ttl) and the text.

=head1 VERSION HISTORY

version 1.0 - Initial Release 8 November 2003 DV

=head1 SYNOPSIS

 standaard.pl

=head1 OPTIONS

Currently no options are defined

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# variables
###########

my $uatimeout=180;
my $proxyserver="internetabh.eds.com";
my $storydir="c:/temp/news";		# Opinie Location
my $commentaar_url="http://www.standaard.be/standpunt/commentaar";
my $commentaarfile="c:/temp/news/story1.html";

#####
# use
#####

use warnings;
use strict 'vars';
use strict 'refs';
use strict 'subs';
use LWP::UserAgent;
use Net::hostent;	    # to determine whether to use the Proxy server
use HTML::TreeBuilder;	    # to parse the html page
use Log;

#############
# subroutines
#############

sub exit_application($) {
    my($return_code) = @_;
    close COMMENTAAR;
    logging("Exit application with return code $return_code.\n");
    close_log();
    exit $return_code;
}

=pod

=head2 Examine Title

The title is part of the element "Commentaar" and it is indicated by the class Mdl_ttl.

=cut

sub examine_title($) {
    my ($commentaar)=@_;
    my $attr_name="class";
    my $attr_value="Mdl_ttl";
    my $title=$commentaar->look_down($attr_name,$attr_value);
    if (defined $title) {    # Scalar context => look for first occurence
	print COMMENTAAR "<html>\n";
	print COMMENTAAR "<head>\n";
	print COMMENTAAR "<title>", $title->as_text,"</title>\n";
	print COMMENTAAR "</head>\n";
	print COMMENTAAR "<body>\n";
	print COMMENTAAR "<b>",$title->as_text,"</b>\n";
    } else {
	print "Error: Could not find an elements for $attr_name $attr_value\n";
    }
}

=pod

=head2 Examine Text

The "Commentaar" element is indicated by the first occurence of the class "Mdl_txt". Apparantly on this web pages, there are no occurences of "Aansluitende dossiers" or pictures anymore, so they do not need to be removed.

The "Commentaar" element contains sub-elements, that can be line breaks <br>. One sub-element is the title that is to be found separatly in the section examine_title.

=cut

sub examine_text($) {
    my ($element)=@_;
    # Commentaar Text is the first block of text from the class
    # "Mdl_txt". Another text block explains how to react.
    my $attr_name="class";
    my $attr_value="Mdl_txt";
    my $commentaar_block=$element->look_down($attr_name,$attr_value);
    if (not(defined $commentaar_block)) {
	error("Error: Could not find commentaar block with $attr_name $attr_value");
    }
    examine_title($commentaar_block);
    my @commentaar_elements=$commentaar_block->content_list;
    foreach my $commentaar_element (@commentaar_elements) {
	my $commentaar_tag;
	my $res_eval=eval { $commentaar_tag=$commentaar_element->tag };
	if (defined ($res_eval)) {
	    if ($commentaar_tag eq "br") {
		print COMMENTAAR "<br> \n";
	    }
	} else {
	    print COMMENTAAR "$commentaar_element\n";
	}
    }
}

######
# Main
######

open_log();
logging("Start application");
Log::display_flag(1);
my $proxy=gethost($proxyserver);
my $ua=LWP::UserAgent->new;
$ua->agent("DVagent");
$ua->timeout($uatimeout);
if (defined $proxy) {
    logging("using proxy");
    $ua->proxy('http', "http://". $proxyserver . ":80");
}

my $req = new HTTP::Request 'GET' => $commentaar_url;
if (defined $proxy) {
    $req->proxy_authorization_basic("dz09s6", "pietje03");
}
my $res = $ua->request($req);
logging("$commentaar_url: ".$res->status_line);
if (not($res->is_success)) {
    error("Could not collect commentaar page.");
    exit_application(1);
}

my $commentaar=$res->content;

my $openres=open(COMMENTAAR, ">$commentaarfile");
if (not $openres) {
    error("Could not open $commentaarfile for writing!");
    exit_application(1);
}

my $tree=HTML::TreeBuilder->new;
$tree->parse($commentaar);
my @content=$tree->content_list;
while (my $element=pop(@content)) {
    my $tag;
    my $res_eval=eval { $tag=$element->tag };
    if (defined ($res_eval)) {
        if ($tag eq "body") {
	    examine_text($element);
	}
    }
}

print COMMENTAAR "</body>\n";
print COMMENTAAR "</html>\n";

exit_application(0);

=pod

=head1 TO DO

=over 4

=item *

Check on existence output directory, create if it does not exist

=item *

Read proxy, username and password from file

=item *

Accept options for tracing, log file location, output file location, ...

=back

=head1 AUTHOR

Any remarks or bug reports, please contact E<lt>dirk.vermeylen@skynet.beE<gt>
