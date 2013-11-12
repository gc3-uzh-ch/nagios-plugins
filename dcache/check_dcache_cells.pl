#!/usr/bin/perl

our $VERSION = '1.0';

=pod

=head1 NAME

check_dcache_cells - Nagios plugin for monitoring d-Cache cell status


=head1 SYNOPSIS

check_dcache_cells [OPTIONS]

Nagios plugin to check availability of d-Cache cells.

=head2 Options

=over 4

=item --ignore, -I I<CELLS>

Ignore the availability status of I<CELLS> (comma-separated list).

=item --input, -i I<FILE>

Read I<FILE> and process its contents instead of downloading
the cell status from the d-Cache web interface.

=item --timeout, -t I<SECONDS>

Exit with critical status if the d-Cache web interface doesn't respond
within the given time.

=item --url, -u I<URL>

Download d-Cache cell info from I<URL>.  
By default, use L<http://localhost:2288/cellinfo>

=item --help

Print usage message and exit.

=back


=head1 DESCRIPTION

Nagios plugin to check availability of d-Cache cells.
Exits with I<CRITICAL> status if any configured cell 
is I<OFFLINE>.


=head1 AUTHOR

Riccardo Murri, <riccardo.murri@cscs.ch>.


=head1 COPYRIGHT AND LICENCE

Copyright (c) 2008-2009 ETH Zuerich / L<CSCS | http://cscs.ch>.

Released under the GNU Public License.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

=cut


use English;
use strict;
use warnings;

use Getopt::Long;
use LWP::UserAgent;
use Pod::Usage;


## parse command-line

my $ignore = '';
my $input = undef;
my $timeout = 10;
my $verbose = 0;
my $url = 'http://localhost:2288/cellInfo';

Getopt::Long::Configure ('gnu_getopt', 'no_ignore_case');
GetOptions (
    'ignore|I=s'  => \$ignore,
    'input|i=s'   => \$input,
    'timeout|t=i' => \$timeout,
    'verbose|v:+' => \$verbose,
    'url|u=s'     => \$url,
    'help|h'      => sub { pod2usage(-exitval => 0, -verbose => 1+$verbose); },
    'version|V'   => sub { print "$PROGRAM_NAME $VERSION\n"; exit; }
    );

my %ignored;
foreach (split(qr/[,\s]/, $ignore)) { $ignored{lc($_)} = 1 };


## communication with Nagios

my %EXITCODE=('DEPENDENT'=>4,'UNKNOWN'=>3,'OK'=>0,'WARNING'=>1,'CRITICAL'=>2);

# exit_to_nagios STATUS MSG [...]
#
sub exit_to_nagios ($@) {
    my $status = shift;
    print "DCACHE-CELLS $status: @_\n";
    exit $EXITCODE{$status};
}


## main

my $cellinfo;
if ($input) {
    local $INPUT_RECORD_SEPARATOR; # enable local slurp-mode
    open INPUT, $input
        or exit_to_nagios ('UNKNOWN', "Cannot open file '$input'" . ($@? "$@" : ''));
    $cellinfo = <INPUT>;
} 
else{
    my $ua = LWP::UserAgent->new;
    $ua->timeout($timeout);
    $ua->env_proxy;
    
    my $response = $ua->get($url);
    exit_to_nagios ('UNKNOWN', "Cannot read '$url'" . ($@? "$@" : ''))
        unless ($response->is_success);

    $cellinfo = $response->decoded_content();
    exit_to_nagios ('UNKNOWN', "Fetched empty content from '$url'")
        if not $cellinfo;
}



## parse cellinfo file

my $cell = undef;
my $status = undef;
my @offline = ();

foreach (split qr{\n}, $cellinfo) {
    # XXX: the parsing here depends on the HTML produced
    # having a rather simple structure, namely, that 
    # "<td>" and "</tr>" tags are one per line...
    ($cell) = m'<td class="cell">([^<\s]+)</td>'i if m'<td class="cell">'i;
    $status = 'OK' if m'<td class="version">production'i;
    $status = 'OFFLINE' if m'<td class="offline"'i;

    push @offline, $cell if (m'</tr>'i and $status 
                             and $status eq 'OFFLINE' and not $ignored{lc($cell)});
}


## now make report to user

if ($#offline >= 0) {
    exit_to_nagios ('CRITICAL', "OFFLINE cells: @offline");
}
else {
    exit_to_nagios ('OK', "All cells currently online.",
        ($verbose? "(Ignoring: ".join(',', keys %ignored).")" : ''));
}    
