#!/usr/bin/perl
#
# Copyright (c) 2008, 2009, ETH Zurich / CSCS.
#
# This module is free software; you can redistribute it and/or modify it
# under the terms of GNU general public license (gpl) version 3.
# See the LICENSE file for details.
#
# Authors: riccardo.murri@gmail.com
#
our $VERSION = '1.5';


=pod

=head1 NAME

check_job_slots - Nagios plugin for monitoring PBS/MAUI job slots usage


=head1 SYNOPSIS

check_job_slots [OPTIONS]

Nagios plugin for monitoring PBS/MAUI job slots usage; reports on
usage figures for job slots and raises a warning if it detects an
inconsistency.

=head2 Options

=over 4

=item --timeout, -t I<SECONDS>

Exit with critical status if the required information couldn't be
retrieved within the given time.  (For instance, because of timeout in
getting output from the PBS or MAUI commands.)

=item --tolerance, -a I<NUM>

When comparing job count gotten from Torque and the one gotten from
MAUI, consider them equal if they differ by less than I<NUM>, to avoid
false positives.  (Default: 0)

You should probably set the tolerance approximately equal to the
number of jobs that your local TORQUE/MAUI install can start within
the running time of an instance of this script.

=item --help

Print usage message and exit.

=back


=head1 DESCRIPTION

Nagios plugin for monitoring PBS/MAUI job slots usage; reports on
usage figures for job slots and raises a warning if there is any
inconsistency.

I<Note:> this script assumes that each job consumes 1 CPU/core only!

In details, the plugin works as follows:

=over 4

=item

Total number of available CPUs and running jobs is gathered by parsing
the output of C<pbsnodes -a>.

=item 

Total number of reserved CPUs and running jobs (again) is gathered by
parsing the output of MAUI's C<showres>.

=item

The number of running and queued jobs (according to Torque) are
gathered by parsing the output of C<qstat -q>.

=back

A warning is raised if the computed values do not match: for instance,
if the number of running jobs according to Torque and according to
MAUI do not coincide.


=head1 BUGS AND LIMITATIONS

It is assumed that each job consumes 1 CPU/core only; dropping this
assumption would require writing a more sophisticated parser.


=head1 AUTHOR

Riccardo Murri, riccardo.murri@cscs.ch


=head1 COPYRIGHT AND LICENCE

Copyright (c) 2008--2009, ETH Zuerich / L<CSCS | http://cscs.ch>

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

use Nagios::Plugin;
my $np = Nagios::Plugin->new;


## parse command-line

my $critical = undef;
my $timeout = 10;
my $tolerance = 0;
my $verbose = 0;
my $warning = undef;

Getopt::Long::Configure ('gnu_getopt', 'no_ignore_case');
GetOptions (
    'critical|c=i'  => \$critical,
    'timeout|t=i'   => \$timeout,
    'tolerance|a=s' => \$tolerance,
    'verbose|v:+'   => \$verbose,
    'warning|w=i'   => \$warning,
    'help|h'        => sub { pod2usage(-exitval => 0, -verbose => 1+$verbose); },
    'version|V'     => sub { print Nagios::Plugin::Functions::get_shortname() 
                               . " $VERSION\n"; exit 3; }
    );


## main


## read "pbsnodes" output, and collect total number of CPUs.

my $available_cpus = 0;
my $used_cpus = 0;

eval {
    local $SIG{ALRM} = sub { die "timeout\n" }; # NB: \n required
    alarm $timeout;
    
    open PBSNODES, "pbsnodes -a |"
        or $np->nagios_die("Cannot run 'pbsnodes -a'");
    my $state;
    while (<PBSNODES>) {
        chomp;
        $state = $1 if (m/state = (.+)/);
        $available_cpus += $1 if ((m/np = (\d+)/) and ($state !~ m/(down|off)/));
        # XXX: the following assumes that each job session uses only 1 core!
        if (m/jobs = /) {
            my @words = split;
            $used_cpus += scalar(@words) - 2;  # job = 0/..., 1/..., 
        };
    };
    close PBSNODES;

    alarm 0;
};
if ($@) {
    $np->nagios_die (CRITICAL, "Timeout while running 'pbsnodes -a'") if ($@ eq "timeout\n");
    $np->nagios_die (UNKNOWN, "Got error while running 'pbsnodes -a': $@");
}

## read "qstat -q" and determine number of running vs queued jobs

my $running;
my $queued;

eval {
    local $SIG{ALRM} = sub { die "timeout\n" }; # NB: \n required
    alarm $timeout;
    
    (undef, $running, $queued) = split /\s+/, `qstat -q | tail -n 1`
    or $np->nagios_die("Cannot run 'qstat -q'");

    alarm 0;
};
if ($@) {
    $np->nagios_die (CRITICAL, "Timeout while running 'qstat -q'") if ($@ eq "timeout\n");
    $np->nagios_die (UNKNOWN, "Got error while running 'qstat -q': $@");
}


## read "showres" output and collect total number of running jobs +
## reserved job slots

my $jobres_cpus = 0;
my $running_maui = 0;
my $used_cpus_maui = 0;

eval {
    local $SIG{ALRM} = sub { die "timeout\n" }; # NB: \n required
    alarm $timeout;
    
    open SHOWRES, "showres |"
        or $np->nagios_die("Cannot run 'showres'");
    while (<SHOWRES>) {
        my ($resid, $type, $state, $start, $end, $duration, $nodes_and_procs, $starttime) = split;
        # MAUI defines states 'S' (starting), 'I' (idle), and 'R' (running) for Jobs,
        # but I cannot find documentation anywhere on how they relate to Torque/PBS
        # job states... I presume that any job listed in "showres" output is "running"
        # by Torque/PBS point of view.
        if (defined($type) and ($type eq 'Job')) {
            $running_maui += 1;
            $used_cpus_maui += $2 if ($nodes_and_procs =~ m{(\d+)/(\d+)});
        }
        # MAUI resource usage has the form "nodes/processors", so "1/4" means "4 procs used on 1 node"
        $jobres_cpus += $2 
            if defined($nodes_and_procs) and ($nodes_and_procs =~ m{(\d+)/(\d+)});
    }
    close SHOWRES;

    alarm 0;
};
if ($@) {
    $np->nagios_die (CRITICAL, "Timeout while running 'showres'") if ($@ eq "timeout\n");
    $np->nagios_die (UNKNOWN, "Got error while running 'showres': $@");
}


## summarize

my $free_cpus = $available_cpus - $used_cpus;
my $reserved_cpus = $jobres_cpus - $used_cpus;

my @criticals;
my @warnings;

push @warnings, 
    "Multi-core jobs detected: $running jobs running over $used_cpus CPUs"
    if $used_cpus - $running > $tolerance;

# "showres" does not tell us how much of the reserved CPUs are in use
# by a job, so the only case we can reliably tell that a job should
# *not* be queued is when there are more free CPUs than reserved
# ones...
#
push @criticals,
    "Queued jobs ($queued) while there are "
    .($free_cpus - $reserved_cpus)
    ." free CPUs certainly available"
    if ($queued > 0) and ($free_cpus > $reserved_cpus);
#push @warnings,
#    "Queued jobs ($queued) while there are $free_cpus free CPUs available"
#    if ($queued > 0) and ($free_cpus > 0);  # XXX: likely to be inaccurate

push @warnings,
    "Torque reports $used_cpus used CPUs, while MAUI reports $used_cpus_maui"
    if abs($used_cpus - $used_cpus_maui) > $tolerance;

push @warnings,
    "Torque reports $running running jobs, while MAUI reports $running_maui"
    if abs($running - $running_maui) > $tolerance;

# XXX: likely never to be triggered
push @warnings,
    "Torque reports more used CPUs ($used_cpus)"
    ." than MAUI has available ($jobres_cpus, summing running jobs and reservations)"
    if $used_cpus > $jobres_cpus;

#push @warnings,
#    "Overcommittment: MAUI shows more reserved CPUs ($jobres_cpus)"
#    ." than Torque reports as available ($available_cpus)"
#    if $jobres_cpus - $available_cpus > $tolerance;

push @warnings,
    "MAUI and TORQUE report different number of running jobs:"
    ." $running_maui vs $running"
    if abs($running - $running_maui) > $tolerance;

#push @warnings,
#    "Running + Free + Reserved = ".($running+$free_cpus+$reserved_cpus)." < ".$available_cpus." = Total CPUs: "
#    ."Running Jobs: $running, "
#    ."Free CPUs: $free_cpus, "
#    ."Reserved CPUs: $reserved_cpus, "
#    ."Total CPUs: $available_cpus"
#    if ($running + $free_cpus + $reserved_cpus < $available_cpus);

$np->add_perfdata(label=>'running_jobs', value=>$running);
$np->add_perfdata(label=>'queued_jobs', value=>$queued);

$np->add_perfdata(label=>'total_cpus', value=>$available_cpus);
$np->add_perfdata(label=>'used_cpus', value=>$used_cpus);
$np->add_perfdata(label=>'free_cpus', value=>$free_cpus);
$np->add_perfdata(label=>'reserved_cpus', value=>$reserved_cpus);

$np->nagios_die ($np->check_messages(
                     critical => \@criticals,
                     warning  => \@warnings,
                     ok => "Running Jobs: $running, Free CPUs: $free_cpus, Reserved CPUs: $reserved_cpus, Total CPUs: $available_cpus",
                     join => '; '
            ));
