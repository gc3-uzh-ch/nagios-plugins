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
our $VERSION = '1.1';


=pod

=head1 NAME

check_diagnose_j - Nagios plugin for monitoring MAUI's "diagnose -j" output


=head1 SYNOPSIS

check_diagnose_j [OPTIONS]

Nagios plugin to check MAUI's "diagnose -j" output.

Run 'check_diagnose_j --verbose --help' to print the full man page.

=head2 Options

=over 4

=item --timeout, -t I<SECONDS>

Exit with critical status if the required information couldn't be retrieved
within the given time.

=item --tolerance, -l I<PERCENT>

Ignore MAUI warnings about jobs that are exceeding the allocated
resources, if within the specified allowance (specified as a percent
of the allocated resource).

The default tolerance is 5%, which is necessary to avoid complaints
about processes using tiny excess fractions of allocated CPUs on Linux
SMP systems.

=item --help

Print usage message and exit.  Together with C<--verbose>, print full
man page.

=back


=head1 DESCRIPTION

Run "diagnose -j" and report about any warnings or error messages.

I<Note:> in order to run "diagnose -j", the Nagios user must be
granted ADMIN3 privileges in the MAUI configuration file.


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
use Pod::Usage;

use Nagios::Plugin::Functions;


## parse command-line

my $timeout = 10;
my $tolerance = 5;
my $verbose = 0;

Getopt::Long::Configure ('gnu_getopt', 'no_ignore_case');
GetOptions (
    'timeout|t=i' => \$timeout,
    'tolerance|l=s' => \$tolerance,
    'verbose|v:+' => \$verbose,
    'help|h'      => sub { pod2usage(-exitval => 0, -verbose => 1+$verbose); },
    'version|V'   => sub { print Nagios::Plugin::Functions::get_shortname() 
                               . " $VERSION\n"; exit 3; }
    );

$tolerance =~ s/%//;
$tolerance /= 100;


## main

my @critical;
my @warning;
my @ok; 


eval {
    local $SIG{ALRM} = sub { die "timeout\n" }; # NB: \n required
    alarm $timeout;
    
    open MAUI_DIAGNOSE_J, 'diagnose -j |'
        or nagios_die(UNKNOWN, 'Could not run "diagnose -j"');

    while(<MAUI_DIAGNOSE_J>) {
        if (m/^([A-Z]+):/) {
            my $kind = $1;
            chomp;
            
            # tolerate some excess in processor usage reporting - this
            # is not very precise on Linux SMP systems.
            next
                if (m/job '\d+' utilizes more procs than dedicated \(([\d\.]+) > ([\d\.])+\)/
                    and ((1.0 * $1 / $2) < 1+$tolerance));

            # tolerate some excess in memory usage if within the $tolerance limits
            next
                if (m/job '\d+' utilizes more memory than dedicated \((\d+) > (\d+)\)/
                    and ((1.0 * $1 / $2) < 1+$tolerance));

            # viceversa, upgrade to 'WARNING' any message about excess resource usage
            $kind = 'WARNING'
                if (m/exceeds requested [a-z]+ limit \(([\d\.]+) > ([\d\.])+\)/
                    and ((1.0 * $1 / $2) > 1+$tolerance));
            
            if ($kind eq 'INFO' or $kind eq 'HINFO' or $kind eq 'SUM' or $kind eq 'STATS') {
                push @ok, $_;
            }
            elsif ($kind eq 'WARNING' or $kind eq 'ALERT' or $kind eq 'NOTE') {
                push @warning, $_;
            }
            else { # ERROR, FAILURE, RMFAILURE
                push @critical, $_;
            };
        };
    };

    close MAUI_DIAGNOSE_J;
};
if ($@) {
    nagios_die (CRITICAL, "Timeout while running 'diagnose -j'") if ($@ eq "timeout\n");
    nagios_die (UNKNOWN, "Got error while running 'diagnose -j': $@");
};

# default OK message
@ok = "No warnings in 'diagnose -j' output"
    if (scalar @ok) == 0;

nagios_exit(
    check_messages(
        critical => \@critical, 
        warning => \@warning,
        ok => \@ok,
        join => '; '
    )
);

