#!/usr/bin/perl

our $VERSION = '1.1';

=pod

=head1 NAME

check_zpool_status - Nagios plugin for monitoring Sun ZFS zpools


=head1 SYNOPSIS

check_zpool_status [OPTIONS] POOL

Nagios plugin to check the status of ZFS pools.

=head2 Options

=over 4

=item --critical, -c I<CONDITIONS>

If any of the conditions (comma-separated list) is deemed not-OK, then
report on it and exit with CRITICAL status.

=item --input, -i I<FILE>

Do not call B<zpool status>, instead, read I<FILE> and process it as
if it was B<zpool status> output.

=item --report, -r LIST

Report on the listed events in the Nagios the status line.

=item --timeout, -t I<SECONDS>

Exit with critical status if B<zpool status> doesn't report within the
given maximum time.

=item --verbose, -v

By default, B<check_zpool_status> only reports the number of vdev's in
each status; with C<--verbose>, it explicitly lists vdev's in each
status.

=item --warning, -w I<LIST>

If any of the conditions (comma-separated list) is deemed not-OK, then
report on it and exit with WARNING status.

=item --help

Print usage message and exit.

=back


=head1 DESCRIPTION

Run B<zpool status> on the given pool and report on its
status. Emphasis in reports is given to vdev status, rather than
filesystem usage.

B<check_zpool_status> reports on the availability of the given zpool,
and summarizes the number of I<ONLINE> and I<AVAIL> vdev's.  

By default:

=over 4

=item 

If any of the following conditions are met:

=over 4

=item scrubbing in progress (or finished with errors), 

=item any I<action> suggested by B<zpool status>, 

=item or vdev's in any of the following states: I<DEGRADED>, I<INUSE>, I<OFFLINE>, I<UNAVAIL>.

=back

then exit status is set to I<WARNING> and the report line contains a
summary of all the failing conditions.

=item 

If any of the following conditions are met:

=over 4

=item B<zpool> reports data I<errors>;

=item any vdev's is in I<FAULTED> state;

=back

then exit status is set to I<CRITICAL> and the report line contains a
summary of all the failing conditions.

=back


=head2 Altering severity conditions and reporting

The C<--report>, C<--warning> and C<--critical> command-line options
all accept a comma-separated list of the following conditions. If a
condition is given as argument to the C<-w> (resp. C<-c>) option, it
will cause B<check_zpool_status> to exit with WARNING (resp. CRITICAL)
status, and report on the triggered condition on the Nagios status
line.  If a condition is given as argument to the C<-r> option, it
will not influence B<check_zpool_status> exit code, and will be
reported upon in any event.

=over 4

=item action 

C<zpool status> outputs any C<action:> line.

=item avail 

A vdev is in the I<AVAIL> state.

=item degraded 

A vdev is in the I<DEGRADED> state.

=item errors 

There were data errors reported by C<zpool status>.

=item faulted 

A vdev is in the I<FAULTED> state.

=item inuse 

A vdev is in the I<INUSE> state.

=item offline 

A vdev is in the I<OFFLINE> state.

=item online 

A vdev is in the I<ONLINE> state.

=item replacing 

Replacing of some vdev's is in progress.

=item scrub 

Scrubbing is in progress, or has ended with errors.

=item unavail

A vdev is in the I<UNAVAIL> state.

=item unknown

A vdev is in the I<UNKNOWN> state.

=back


=head1 COPYRIGHT AND LICENCE

Copyright (c) 2008 ETH Zuerich / L<CSCS | http://cscs.ch> 

This code was initially based on L<check_zfs | http://www.geocities.com/ntb4real/proj/zfs.htm>, 
which is copyright (c) 2007 Nathan Butcher, later extensively rewritten by 
L<Riccardo Murri|rmurri@cscs.ch>.

Released under the GNU Public License

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
use IPC::Run qw(run timer timeout);
use Pod::Usage;


## defaults

my $default_report = 'online,avail';
my $default_warnings = 'action,degraded,inuse,offline,unavail,replacing,scrub';
my $default_critical = 'errors,faulted';


## parse command-line

my $input = undef;
my $timeout = 10;
my $report = undef;
my $verbose = 0;
my $warnings = undef;
my $critical = undef;

Getopt::Long::Configure ('gnu_getopt', 'no_ignore_case');
GetOptions (
    'input|i=s'   => \$input,
    'timeout|t=i' => \$timeout,
    'report|r=s'  => \$report,
    'verbose|v:+' => \$verbose,
    'warning|w=s' => \$warnings,
    'critical|c=s'=> \$critical,
    'help|h'      => sub { pod2usage(-exitval => 0, -verbose => 1+$verbose); },
    'version|V'   => sub { print "$PROGRAM_NAME $VERSION\n"; exit; }
    );


my %alert;
$alert{$_} = -1 foreach (qw(ACTION AVAIL DEGRADED ERRORS FAULTED 
                            INUSE OFFLINE ONLINE REPLACING SCRUB 
                            UNAVAIL UNKNOWN));
$alert{uc($_)} = 0 foreach (split /[,\s]+/, $default_report);
$alert{uc($_)} = 1 foreach (split /[,\s]+/, $default_warnings);
$alert{uc($_)} = 2 foreach (split /[,\s]+/, $default_critical);
if ($report) { $alert{uc($_)} = 0 foreach (split /[,\s]+/, $report); }
if ($warnings) { $alert{uc($_)} = 1 foreach (split /[,\s]+/, $warnings); }
if ($critical) { $alert{uc($_)} = 2 foreach (split /[,\s]+/, $critical); }


## communication with Nagios

my %EXITCODE=('DEPENDENT'=>4,'UNKNOWN'=>3,'OK'=>0,'WARNING'=>1,'CRITICAL'=>2);

# exit_to_nagios STATUS MSG [...]
#
sub exit_to_nagios ($@) {
    my $status = shift;
    print "ZPOOL $status: @_\n";
    exit $EXITCODE{$status};
}


## sanity check

exit_to_nagios('UNKNOWN', "This plugin currently only works on Solaris 10, OpenSolaris distributions, and FreeBSD 7 and later.")
    if ($^O ne 'solaris' and $^O ne 'freebsd' and not $input);

my $pool=$ARGV[0];
exit_to_nagios('UNKNOWN', "No ZPOOL given on command-line - type '$0 --help' for usage.")
    unless $pool;


## main

my @zpool_status = ('zpool', 'status', $pool);

# pre-allocate 10k into $zpool_cmd_stdout and _stderr
my $zpool_cmd_stdout = '\n' x 10_000;
my $zpool_cmd_stderr = '\n' x 10_000;

if ($input) {
    local $INPUT_RECORD_SEPARATOR; # enable local slurp-mode
    open INPUT, $input
        or exit_to_nagios ('UNKNOWN', "Cannot open file '$input'");
    $zpool_cmd_stdout = <INPUT>;
} 
else{
    my $timer = timeout($timeout);
    eval {
        $zpool_cmd_stdout = '';
        $zpool_cmd_stderr = '';
        #   COMMAND      STDIN   STDOUT              STDERR 
        run (\@zpool_status, \undef, \$zpool_cmd_stdout, \$zpool_cmd_stderr, $timer);
    };
    if ($@) { # an exception occurred
        exit_to_nagios ('CRITICAL', "'@zpool_status' did not respond in $timeout seconds")
            if ($timer->is_expired);
        
        exit_to_nagios ('UNKNOWN', "$@");
    }
    if (0 < length $zpool_cmd_stderr) {
        exit_to_nagios ('WARNING', "Error running '@zpool_status':", 
                        (split qr{\n}, $zpool_cmd_stderr)[0]);
    }
}

## parse 'zfs status' output to find zpool fses and devices
my $in_device_table;
my $in_replacing_section;
my $in_spares_section;

my $health;

my %report;
$report{$_} = [] foreach (qw(AVAIL DEGRADED FAULTED INUSE OFFLINE 
                             ONLINE REPLACING UNAVAIL UNKNOWN));

foreach (split qr{\n}, $zpool_cmd_stdout) {
    if (/^ state: /) {
        ($health) = /^ state: (\S+)/;
        next; 
    }

    # this appears only if the pool is not in OK state
    if (/^ action: /) {
        $report{ACTION} = /^ action: ([^\.]+)/;
    }

    # header line that marks beginning of device table
    if (/^\s+NAME\s+STATE\s+READ\s+WRITE\s+CKSUM/) {
        $in_device_table=1;
        next;
    }
    
    if ($in_device_table) {
        
        # end of device table is marked by an empty line
        if ( /^\s*$/ ) {
            $in_device_table=0;
            next;
        }
        
        # first line of dev table reports on pool summary
        if (/^\s+${pool}\s+/) {
            next;
        } 

        # enter 'spares' section
        if (/^\tspares/) {
            $in_spares_section = 1;
        }

        # skip aggregate devices report
        if (/^\s+(disk|file|mirror|raidz|spare)/) {
            next;
        }

        # enter replacing section, continued on next lines
        if (/^\s+replacing\s/) {
            ($in_replacing_section) = /^(\s+)replacing/;
            $in_replacing_section .= '\s\s';
            my $perc;
            if (/%/) {
                ($perc) = /([0-9]+%)/;  
            } else {
                $perc = 'in progress';
            }
            unshift @{$report{REPLACING}}, [$perc];
            next;
        }

        # device description line 
        my ($dev, $state, $notes) = /^\s+(\S+)\s+(\S+)[\s\dKMG]+(\D*)/;
        push @{$report{$state}}, $dev;
        $report{$dev} = [$state, ($notes or '')];
        push @{$report{SPARES}}, $dev if $in_spares_section;

        # 'replacing' section marked by indentation
        if ($in_replacing_section) {
            if (m/^$in_replacing_section/) {
                push @{@{$report{REPLACING}}[0]}, $dev;
            }
            else {
                $in_replacing_section = undef;
            }
        }

        next;
    }

    # e.g.: " scrub: scrub completed with 0 errors on Tue Jun 24 14:29:42 2008"
    if ( /^ scrub: / ) {
        ($report{SCRUB}) = /^ scrub: (.+)/;
        next;
    }
    
    # e.g.: "errors: No known data errors"
    if ( /^errors:/ ) {
        ($report{ERRORS}) = /^errors: (.+)/;
        next;
    }
}


## now make report to user

sub max ($$) { my ($a, $b) = @_; return ($a > $b)? $a : $b; }

my $statuscode = 0; # OK

$statuscode = max($statuscode, $alert{DEGRADED}) if ($health eq 'DEGRADED');
$statuscode = max($statuscode, $alert{OFFLINE}) if ($health eq 'OFFLINE');
$statuscode = max($statuscode, $alert{ONLINE}) if ($health eq 'ONLINE');
$statuscode = max($statuscode, $alert{UNKNOWN}) if ($health eq 'UNKNOWN');

my @msgs;

# get rid of 'all is good' messages, unless explictly asked by user
$report{ERRORS} = undef 
    if ($report{ERRORS}
        and $report{ERRORS} =~ /No known data errors/ 
        and $alert{ERRORS} != 0);
$report{SCRUB} = undef
    if ($report{SCRUB}
        and $report{SCRUB} =~ /(scrub|resilver) completed with 0 error/
        and $alert{SCRUB} != 0);

# rewrite error message so that it makes sense on Nagios report
$report{ERRORS} = 'Permanent errors have been detected'
    if ($report{ERRORS} and 
        $report{ERRORS} =~ m'Permanent errors have been detected in the following files:');

# if there are any errors, these get upfront in the message
if ($report{ERRORS}) {
    $statuscode = max($statuscode, $alert{ERRORS});
    push @msgs, [$alert{ERRORS}, $report{ERRORS}];
}

# any of these conditions may trigger an alert, if count is > 0
foreach my $cond (qw(FAULTED INUSE UNAVAIL OFFLINE UNKNOWN DEGRADED ONLINE AVAIL)) {
    if (($#{$report{$cond}} >= 0) 
        or ($alert{$cond} == 0 and not $verbose)) {
        $statuscode = max($statuscode, $alert{$cond});
        # report just count, or full list if verbose
        push @msgs, [$alert{$cond},
                     $cond .':'. ($verbose?
                                  # verbose: if there are notes, output: "vdev(notes)"
                                  # else output: "vdev"
                                  join(',', 
                                       map($_ . ($report{$_}[1]? "($report{$_}[1])" : ''),
                                           @{$report{$cond}})) 
                                  # non-verbose: just output count of vdev for given state
                                  : 1+$#{$report{$cond}})];
    }
}

# report on replacing disks
if ($verbose) {
    foreach my $repl (@{$report{REPLACING}}) {
        my $progress = shift @{$repl};
        push @msgs, [$alert{REPLACING},
                     'replacing ' 
                     . join(' with ', @$repl)
                     . ' ' . $progress];
    }
}
else {
    if ($#{$report{REPLACING}} > 0) {
        $statuscode = max($statuscode, $alert{REPLACING});
        push @msgs, [$alert{REPLACING}, 
                     'replacing:' . $#{$report{REPLACING}}];
    }
}

# then comes any suggested action
if ($report{ACTION}) {
    $statuscode = max($statuscode, $alert{ACTION});
    push @msgs, [$alert{ACTION}, $report{ACTION}];
}

# finally scrub status
if ($report{SCRUB}) {
    $statuscode = max($statuscode, $alert{SCRUB});
    push @msgs, [$alert{SCRUB}, $report{SCRUB}];
}


## calling all goats!

my $state = 'UNKNOWN';
$state = 'OK' if $statuscode == 0;
$state = 'WARNING' if $statuscode == 1;
$state = 'CRITICAL' if $statuscode == 2;

# DEBUG:
#use Data::Dumper;
#print STDERR Dumper(\%report);

exit_to_nagios ($state, "$pool $health ", 
                join ('; ', map($$_[1], grep { $$_[0] <= $statuscode } @msgs)));
