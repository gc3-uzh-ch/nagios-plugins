#!/usr/bin/perl
#
# Copyright (c) 2008, 2009, ETH Zurich.
#
# This module is free software; you can redistribute it and/or modify it
# under the terms of GNU general public license (gpl) version 3.
# See the LICENSE file for details.
#
# Authors: riccardo.murri@cscs.ch
#
our $VERSION = '1.0';


=pod

=head1 NAME

check_dcache_movers - Check for "No Mover found" errors in dCache


=head1 SYNOPSIS

check_dcache_movers [OPTIONS]

Nagios plugin to check for "No Mover found" errors in dCache.

Run 'check_dcache_movers --verbose --help' to print the full man page.

=head2 Options

=over 4

=item --age, -a I<MINUTES>

Only consider entries older than I<MINUTES>: every dCache task starts
with no associated mover.  (Default: 10 minutes.)

=item --critical, -c I<THRESHOLD>

Exit with I<CRITICAL> status if there are more than I<THRESHOLD> tasks
with no associated mover. (Default: 5)

=item --timeout, -t I<SECONDS>

Exit with critical status if the required information couldn't be retrieved
within the given time.

=item --url, -u I<URL>

URL of local dCache admin web page to examine.
(Default: http://localhost:2288/context/transfers.html)

=item --warnings, -w I<THRESHOLD>

Exit with I<CRITICAL> status if there are more than I<THRESHOLD> tasks
with no associated mover.  (Default: 0)


=item --help

Print usage message and exit.

=back


=head1 DESCRIPTION

Check if there are any "No movers found" messages in dCache admin
interface transfers table.  By default, outputs a warning message if
there is any instance of that message in the table, and a critical
error message if there are more than 5 instances of the "No movers
found" alert.  (These thresholds can be adjusted with the '-w' and
'-c' command-line options.)


=head1 KNOWN BUGS AND LIMITATIONS

Parsing the HTML report by dCache is very dependend on content being
properly marked with C<class="..."> attributes.  This might change in
future releases of dCache.


=head1 AUTHOR

Riccardo Murri, riccardo.murri@cscs.ch


=head1 COPYRIGHT AND LICENCE

Copyright (c) 2008, ETH Zuerich / L<CSCS | http://cscs.ch>.

Released under the GNU General Public License.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT
WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER
PARTIES PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND,
EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE. THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE
SOFTWARE IS WITH YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME
THE COST OF ALL NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE LIABLE
TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE THE
SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH
DAMAGES.

=cut


use English;
use strict;
use warnings;

use Getopt::Long;
use LWP::UserAgent;
use Pod::Usage;
use Sys::Hostname;

use Nagios::Plugin::Functions;


## parse command-line

my $age = 10; 
my $critical = 5;
my $timeout = 10;
my $url = undef;
my $verbose = 0;
my $warnings = 0;

Getopt::Long::Configure ('gnu_getopt', 'no_ignore_case');
GetOptions (
    'age|a=i'     => \$age,
    'critical|c=i'=> \$critical,
    'timeout|t=i' => \$timeout,
    'url|u=s'     => \$url,
    'verbose|v:+' => \$verbose,
    'warnings|w=i'=> \$warnings,
    'help|h'      => sub { pod2usage(-exitval => 0, -verbose => 1+$verbose); },
    'version|V'   => sub { print Nagios::Plugin::Functions::get_shortname() 
                               . " $VERSION\n"; exit 3; }
    );


## main

$age *= 60; # convert from minutes to seconds

$url = 'http://'.hostname.':2288/context/transfers.html'
    unless defined($url);

my $ua = LWP::UserAgent->new;
$ua->timeout($timeout);
$ua->env_proxy;

my $response = $ua->get($url);
nagios_die("Cannot fetch '$url'")
    unless $response->is_success;

my $no_movers_found_count = 0;
my $waited = 0;
foreach (split (qr{\n}, $response->decoded_content)) {
    # rely on the "wait" line to be outputted *before*
    # the "No Mover found" one is...
    $waited =  3600*$1 + 60*$2 + $3 
        if (m/td class="wait">(\d+):(\d\d):(\d+)</i);
    $no_movers_found_count++
        if ($waited > $age and m/class="missing".+>No +Mover +found</i);
}

nagios_die(CRITICAL, "$no_movers_found_count transfers pending with 'No Mover Found'")
    if $no_movers_found_count > $critical;
nagios_die(WARNING, "$no_movers_found_count transfers pending with 'No Mover Found'")
    if $no_movers_found_count > $warnings;
nagios_die(OK, "No transfers waiting for a mover.");
