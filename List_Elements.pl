=head1 NAME

List_Elements.pl - This script will dump all elements from a HTML Treebuilder object.

=head1 DESCRIPTION

This application will accept a URL or a filename. In case of an URL, the application reads the page on the web. In case of a filename, the file is slurped into a variable.

=head1 VERSION HISTORY

version 1.0 - Initial Release 16 September 2005 DV

=head1 SYNOPSIS

 List_Elements.pl [-t] [-l log_dir] [-f filename] [-u url] [-d]

 List_Elements.pl -h	Usage information
 List_Elements.pl -h 1	Usage information and a description of the options
 List_Elements.pl -h 2	Full documentation

=head1 OPTIONS

=over 4

=item B<-t>

enable trace messages if set

=item B<-l log_dir>

Logfile directory, by default: c:\temp

=item B<-f filename>

Filename that contains the contents of a html page.

=item B<-u url>

URL that requires analysing. The URL must start with http:// . -u or -f is required and mutual exclusive.

=item B<-d>

If this option is specified, then the body of the html is dumped instead of an element tree display.

=back

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# variables
###########

my $uatimeout=180;
my ($filename, $url, $html_page, $action);
my ($proxy, $res, $ua,$logdir);
my $proxyserver="internetabh.eds.com";

#####
# use
#####

use warnings;
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;	    # For input parameter handling
use Pod::Usage;		    # Usage printing
use LWP::UserAgent;
use Net::hostent;	    # to determine whether to use the Proxy server
use HTML::TreeBuilder;	    # to parse the html page
use Log;

#############
# subroutines
#############

sub exit_application($) {
    my($return_code) = @_;
    close FILE;
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

=head2 Handle Page procedure

This procedure will convert the html page into a tree and extract the body element of the tree. Then the dump page procedure or the show elements procedure will be called to show the contents of the page.

=cut

sub handle_page($) {
    
    my ($page) = @_;
    
    # Create Tree
    my $tree = HTML::TreeBuilder->new;
    $tree->parse($page);
    # Extract Elements
    my (@content) = $tree->content_list;
    while (my $element = pop (@content)) {
	my $tag;
	my $res_eval = eval {$tag = $element->tag};
	if (defined ($res_eval)) {
	    if ($tag eq "body") {
		$page = $element;
	    }
	}
    }
    
    if ($action eq "dump") {
	dump_page($page);
    } else {
	show_elements($page);
    }
}

=pod

=head2 Show Elements Procedure

This procedure will accept a html body tree and extract all the elements from the tree. An attempt is made to print sufficient information with each element so that the element can be identified in the tree.

The _parent and _content values are not printed, since these are hashes or arrays that are not in a readable format.

=cut

sub show_elements($) {
    my ($page) = @_;
    my @elements = $page->descendants();
    my $nr_elements = @elements;

    print "Found $nr_elements elements\n";
    foreach my $element (@elements) {
	my $tag;
	my $res_eval = eval{$tag = $element->tag};
	if (defined $res_eval) {
	    print "\n\n$tag\n=======\n";
	    print "Depth: ".$element->depth()."\n";
	    my %el_hash = $element->all_attr();
	    while (my($key, $value) = each %el_hash) {
	        if (not(($key eq "_parent") or ($key eq "_content"))) {
		    print "$key: $value\n";
		}
	    }
	} else {
	    print "No tag defined for this element\n";
	}
    }
}

=pod

=head2 Dump Page Procedure

This procedure will accept a html body tree and dumps the page on the screen. The output can be captured in a file using standard file redirection techniques.

=cut

sub dump_page($) {
    my ($page) = @_;
    $page->dump;
}

=pod

=head2 Collect URL

This procedure accepts an URL and tries to collect the information from the web. It expects the URL to be retrieved. Return value is the content of the page or B<UNDEFINED> in case of no return page.

The procedure knows if it is connected directly to the web, or behind the EDS firewall. In the latter case, proper proxy authentication is done. 
In case of working on the EDS intranet, the proxy may cause temporary problems. Therefore if the information could not be connected due to proxy errors, another attempt is made to collect the information, up to maximum three attempts.

=cut

sub collect_url($) {
    # Find the URL
    my($url)=@_;
    my($return_page);
    undef $return_page;		# to be sure...
    my $req=new HTTP::Request 'GET' => $url;
    if (defined $proxy) {
	$req->proxy_authorization_basic("dz09s6","pietje03");
    }
    # Ofthen there seem to be problems with the proxyserver. 
    # The assumption is that this is due to specific proxy problems, so
    # retrying may solve the problem.
    # Currently 3 attempts are made to get through the proxy server.
    my $cnt=0;
    while ($cnt < 3) {
	$cnt++;
	$res=$ua->request($req);
	logging("$url: ".$res->status_line);
	if (index($res->status_line,$proxyserver) > -1) {
	    error("Issue with $proxyserver on attempt $cnt for $url");
	} else {
	    last;
	}
    }
    if ($res->is_success) {
	$return_page=$res->content;
	print "Content collected for $url\n";
    } else {
	error("Could not collect content for $url");
    }
    return $return_page;
}

######
# Main
######

my %options;
getopts("tdl:f:u:", \%options) or pod2usage(-verbose => 0);
my $arglength = scalar keys %options;  
if ($arglength == 0) {		    # If no options specified,
    $options{"h"} = 0;		    # display usage.
}
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
    trace_flag(1);
    trace("Trace enabled");
}
# Find log file directory
if ($options{"l"}) {
    $logdir = logdir($options{"l"});
} else {
    $logdir = logdir();
}
if (-d $logdir) {
    trace("Logdir: $logdir");
} else {
    pod2usage(-msg     => "Cannot find log directory $logdir.",
	      -verbose => 0);
}
# Check if dump is required, or an elements list
if (defined $options{"d"}) {
    $action = "dump";
} else {
    $action = "elements";
}
# Logdir found, start logging
open_log();
logging("Start application");
# Find filename if specified
if ($options{"f"}) {
    $filename = $options{"f"};
    if (not(-r $filename)) {
	error("Cannot access $filename for reading");
	exit_application(1);
    }
}
# Find url if specified
if ($options{"u"}) {
    $url = $options{"u"};
}
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input values

# Filename or url must be specified, otherwise exit.
if ((not(defined $filename)) and (not(defined $url))) {
    error("Filename and URL undefined, at least one must be specified");
    exit_application(1);
}
# Only one of them can be specified, the application
# is not supposed to choose if the user cannot.
if ((defined $filename) and (defined $url)) {
    error("Filename $filename and URL $url cannot both be defined, choose one of them");
    exit_application(1);
}

# Check to handle file
if (defined $filename) {
    my $openres = open (FILE, $filename);
    if (not(defined $openres)) {
	error("Could not open $filename for reading, exiting...");
	exit_application(1);
    }
    undef $/;
    $html_page = <FILE>;
    close FILE;
} elsif (defined $url) {
    # Initialize user agent
    $proxy=gethost($proxyserver);
    $ua=LWP::UserAgent->new;
    $ua->agent("DVagent");
    $ua->timeout($uatimeout);
    if (defined $proxy) {
	logging("using proxy");
	$ua->proxy('http', "http://". $proxyserver . ":80");
    }
    $html_page = collect_url($url);
}
if (defined $html_page) {
    handle_page($html_page);
} else {
    error("html_page not available for evaluation");
    exit_application(1);
}

exit_application(0);

=pod

=head1 TO DO

=over 4

=item *

Read proxy, username and password from file

=back

=head1 AUTHOR

Any remarks or bug reports, please contact E<lt>dirk.vermeylen@skynet.beE<gt>
