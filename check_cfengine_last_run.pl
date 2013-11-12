#!/usr/bin/perl

our $VERSION = '1.2';

=pod

=head1 NAME

check_cfengine_last_run - Nagios plugin for checking when B<cfengine> was last run.


=head1 SYNOPSIS

check_cfengine_last_run [OPTIONS]

Nagios plugin to check when B<cfengine> was last run, and raise a
warning if this happened too much time back in the past.
Also exits with WARNING level if the last run logfile is empty.

=head2 Options

=over 4

=item --cfengine-dir, -d I<PATH>

Set the path to the directory where B<cfexecd> stores its log files.
Default is F</var/cfengine/outputs>

=item --critical, -c I<THRESHOLD>

Exit with B<CRITICAL> status if B<cfagent> has not been run for the
last I<THRESHOLDS> minutes.  (Default: 360 minutes, i.e., 6 hours)

=item --warning, -w I<THRESHOLD>

Exit with B<WARNING> status if B<cfagent> has not been run for the
last I<THRESHOLDS> minutes. (Default: 65 minutes)

=item --help

Print usage message and exit.

=back


=head1 DESCRIPTION

Nagios plugin to check when B<cfengine> was last run, and raise a
warning if this happened too much time back in the past.


=head1 AUTHOR

Riccardo Murri, riccardo.murri@gmail.com


=head1 COPYRIGHT AND LICENCE

Copyright (c) 2008, 2009 ETH Zurich / L<CSCS | http://cscs.ch>.

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

use File::stat;
use Getopt::Long;
use Pod::Usage;
use POSIX qw(strftime);


## parse command-line

my $cfengine_log_dir = '/var/cfengine/outputs';
my $critical = 360;
my $verbose = undef;
my $warning = 65;

Getopt::Long::Configure ('gnu_getopt', 'no_ignore_case');
GetOptions (
    'critical|c=i'=> \$critical,
    'cfengine-dir|d=s' => \$cfengine_log_dir,
    'verbose|v:+' => \$verbose,
    'warnings|w=i'=> \$warning,
    'help|h'      => sub { pod2usage(-exitval => 0, -verbose => 1+$verbose); },
    'version|V'   => sub { print "$PROGRAM_NAME $VERSION\n"; exit; }
    );


## communication with Nagios

my %EXITCODE=('DEPENDENT'=>4,'UNKNOWN'=>3,'OK'=>0,'WARNING'=>1,'CRITICAL'=>2);

# exit_to_nagios STATUS MSG [...]
#
sub exit_to_nagios ($@) {
    my $status = shift;
    print "CFENGINE_LAST_RUN $status: @_\n";
    exit $EXITCODE{$status};
}


## main

my $st = stat($cfengine_log_dir . '/previous')
    or exit_to_nagios('WARNING', "Cannot stat logfile '$cfengine_log_dir/previous'");

exit_to_nagios ('WARNING', "cfengine logfile '$cfengine_log_dir/previous' is empty")
    if $st->size == 0;

my $delta = (time() - $st->mtime) / 60;

# human readable timestamp
my $lastrun = strftime('%H:%M on %A, %B %d, %Y', localtime($st->mtime));

exit_to_nagios ('CRITICAL', "cfengine was last run more than $critical minutes ago, at " . $lastrun)
    if ($delta > $critical);
exit_to_nagios ('WARNING', "cfengine was last run more than $critical minutes ago, at " . $lastrun)
    if ($delta > $warning);
exit_to_nagios ('OK', "cfengine was last run at " . $lastrun)
