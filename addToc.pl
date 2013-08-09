=head1 NAME

addToc - Add Table of Contents to kb-style document.

=head1 DESCRIPTION

This script will add a table of contents to a kb-style document. It will find headers as of layer 4, extract them and list them in a table of contents at the start of the document. It will add name references in the document allowing to jump directly from the TOC item to the item in the text.

Note that the original file will be overwritten. Therefore a safe copy will be made in the c:\temp\kbsave directory. This directory must exist before the application can run.

=head1 SYNOPSIS

addToc.pl [-t] [-l log_dir] -s kbItem-file [-c]

    addToc.pl -h	 Usage
    addToc.pl -h 1   Usage and description of the options
    addToc.pl -h 2   All documentation

=head1 VERSION HISTORY

version 1.0 4 October 2007 DV

=over

=item *

Initial Version

=back

=head1 OPTIONS

=over 4

=item B<-t>

Tracing enabled, default: no tracing

=item B<-l logfile_directory>

default: c:\temp. Logging is enabled by default. 

=item B<-s kbItem-file>

Text file where a TOC needs to be added.

=item B<-c>

Clean only, remove formatting elements to restore file in own format. This may be helpful for a text file that is not yet complete.

=back

=head1 SUPPORTED PLATFORMS

The script has been developed and tested on Windows XP Professional, Perl v5.8.8 build 820 provided by ActiveState.

=head1 ADDITIONAL DOCUMENTATION

=cut

###########
# Variables
########### 

my ($logdir, $kbtext_bn, $kbtext_file, @kbtext, @toc, $clean_only);
my $savedir = "c:/temp/kbSave";

#####
# use
#####

use warnings;			    # show warning messages
use strict 'vars';
use strict 'refs';
use strict 'subs';
use Getopt::Std;		    # Handle input params
use Pod::Usage;			    # Allow Usage information
use Log;			    	# Application and error logging
use File::Basename;			# Understand file basename
use File::Copy;
use Tie::File;

#############
# subroutines
#############

sub exit_application($) {
    my ($return_code) = @_;
    logging("Exit application with return code: $return_code\n");
    close_log();
    exit $return_code;
}

=pod

=head2 Trim

This section is used to get rid of leading or trailing blanks. It has been
copied from the Perl Cookbook.

=cut

sub trim {
    my @out = @_;
    for (@out) {
        s/^\s+//;
        s/\s+$//;
    }
    return wantarray ? @out : $out[0];
}

sub clean_file() {
	my $nr_lines = @kbtext;
	for (my $cnt = 1; $cnt < $nr_lines; $cnt++) {
		if ($kbtext[$cnt] =~ /^<!--- TOC Section Start -->/) {
			# Start TOC found, now search for end TOC
			my $myStartToc = $cnt;
			while (not($kbtext[$cnt] =~ /^<!--- TOC Section END -->/)) {
				$cnt++;
				if ($cnt >= $nr_lines) {
					error("Could not find End of TOC...");
					exit_application(1);
				}
			}
			my $myEndToc = $cnt;
			splice @kbtext, $myStartToc, $myEndToc-$myStartToc+1;
			# Reset line counter and number of lines
			$cnt = 1;
			$nr_lines = @kbtext;
		} elsif ($kbtext[$cnt] =~ /^<a name=LBL/) {
			# Name tag line found, should be removed
			splice @kbtext, $cnt, 1;
			# Update counters
			$cnt--;
			$nr_lines = @kbtext;
		} elsif ($kbtext[$cnt] =~ /^<hr>$/) {
			# hr tag line found, should be removed
			splice @kbtext, $cnt, 1;
			# Update counters
			$cnt--;
			$nr_lines = @kbtext;
		}
	}
}

sub collect_headers() {
	my $nr_lines = @kbtext;
	undef @toc;
	push @toc,"<!--- TOC Section Start -->";
	push @toc,"<a name=top></a><h4>Table of Contents</h4>";
	push @toc,"<menu>";
	my $hl = 4;				# Header level for menu
	my $current_hl = 4;
	my $labelcnt = 0;
	my ($label, $return_to_top, $hr_tag);
	# Read through file, but skip first line
	for (my $cnt = 1; $cnt < $nr_lines; $cnt++) {
		if ($kbtext[$cnt] =~ /^<(H|h).*/) {
			# Verify header level is numeric
			$current_hl = substr($kbtext[$cnt], 2, 1);
			if (not($current_hl =~ /[4-9]/)) {
				my $disp_cnt = $cnt+1;
				error("Line $disp_cnt invalid label $kbtext[$cnt]");
			} else {
				# Insert name tag in html document
				# 1. Format name tag
				$labelcnt++;
				$label = "LBL_$labelcnt";
				if ($current_hl < $hl) {
					$return_to_top = "href=#top>Back to Top";
				} else {
					# No return to top required
					$return_to_top = ">";
				}
				# 1.5 Add <hr> in case of new <h4>
				if ($current_hl == 4) {
					$hr_tag = "<br><hr>";
				} else {
					$hr_tag = "";
				}
				my $nametag = "<a name=LBL_$labelcnt $return_to_top</a>$hr_tag";
				# 2. Add name tag to text
				splice @kbtext, $cnt, 0, $nametag;
				# 3. Sync counters with text update
				$cnt++;
				$nr_lines = @kbtext;
				# Update TOC
				if ($current_hl > $hl) {
					while ($current_hl > $hl) {
						push @toc,"<menu>";
						$hl++;
					}
				} elsif ($current_hl < $hl) {
					while ($current_hl < $hl) {
						push @toc,"</menu>";
						$hl--;
					}
				}
				# Reformat TOC line
				my $tocline = trim $kbtext[$cnt];
				# Now strip of <hx> and </hx>
				$tocline = substr($tocline,4, length($tocline)-9);
				push @toc,"<li><a href=\"#LBL_$labelcnt\">$tocline</a>";
			}
		}
	}
	# End of file, now add closing </menu>
	$current_hl = 3;
	while ($current_hl < $hl) {
		push @toc,"</menu>";
		$hl--;
	}
	push @toc,"<!--- TOC Section END -->";
	# And add a closing 'Back to Top' line
	my $nametag = "<a name=LBL_END href=#top>Back to Top</a>";
	push @kbtext, $nametag;
}

sub add_toc() {
	splice @kbtext, 1, 0, @toc;
}


######
# Main
######

# Handle input values
my %options;
getopts("h:tl:s:c", \%options) or pod2usage(-verbose => 0);
my $arglength = scalar keys %options;  
# print "Arglength: $arglength\n";
if ($arglength == 0) {			# If no options specified,
    $options{"h"} = 0;			# display usage.
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
    Log::trace_flag(1);
    trace("Trace enabled");
}
# Log required?
if (defined $options{"n"}) {
    log_flag(0);
} else {
    log_flag(1);
    # Log required, so verify logdir available.
    if ($options{"l"}) {
		$logdir = logdir($options{"l"});
    } else {
		$logdir = logdir();
    }
    if (-d $logdir) {
		trace("Logdir: $logdir");
    } else {
		pod2usage(-msg     => "Cannot find log directory ".logdir,
		 		  -verbose => 0);
    }
}
# Logdir found, start logging
open_log();
logging("Start application");
# Find Input Text File
if ($options{"s"}) {
	$kbtext_file = $options{"s"};
	# Verify that the timesheet file is readable.
	if (not(-r $kbtext_file)) {
    	error("Cannot access kb text file $kbtext_file for reading, exiting...");
    	exit_application(1);
	}
} else {
	error("Kb text file not defined, exiting...");
	exit_application(1);
}
if (defined $options{"c"}) {
	$clean_only = "Yes";
}
# Show input parameters
while (my($key, $value) = each %options) {
    logging("$key: $value");
    trace("$key: $value");
}
# End handle input value

# Find file basename
$kbtext_bn = basename($kbtext_file);

# First copy text file to save dir
my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my $datetime = sprintf "%04d%02d%02d%02d%02d%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec;
if (not(-d $savedir)) {
	error("Save directory $savedir is not a directory, exiting...");
	exit_application(1);
}
# Copy file to save location
my $copyres = copy($kbtext_file, "$savedir/$kbtext_bn"."_$datetime");
if (defined $copyres) {
	logging("Save copy created $savedir/$kbtext_bn");
} else {
	error("Could not copy $kbtext_file to $savedir/$kbtext_bn, exiting...");
	exit_application(1);
}

# Slurp text file into array.
my $tieres = tie @kbtext, 'Tie::File', $kbtext_file;
if (not defined $tieres) {
	error("Couldn't tie $kbtext_file into array, exiting...");
	exit_application(1);
}

# Clean current file if required
clean_file();

if (not defined $clean_only) {
	# Collect all headers from text file
	collect_headers();
	# Add TOC
	add_toc();
}

exit_application(0);

=pod

=head1 To Do

=over 4

=item *

Nothing for now.....

=back

=head1 AUTHOR

Any suggestions or bug reports, please contact E<lt>dirk.vermeylen@eds.comE<gt>
