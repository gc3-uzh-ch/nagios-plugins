#!/usr/bin/perl
#
# Author: Riccardo Murri <riccardo.murri@cscs.ch>
# Date: 2009-08-18
# Licence: GPL
#
our $VERSION = '3.3';

=pod

=head1 NAME

check_daemon - Nagios plugin for checking that a daemon is running


=head1 SYNOPSIS

check_daemon [OPTIONS] [-p PORT] [-l LOGFILE] CMD
check_daemon [OPTIONS] [-p PORT] [-l LOGFILE] -f FILE

Check that a process whose command-line matches (PERL-style) regexp
I<CMD> is running. With the C<-f> option, check that the process whose
PID is stored in I<FILE> is running.

Report measurements about the selected process: e.g., number of
running instances, number of open file descriptors, etc.  Optionally,
ensure that is listening on specified TCP/UDP ports, and that it is
writing to a log file.

Run 'check_daemon --verbose --help' to see the full manual page.

=head2 Options

=over 4

=item --critical, -c I<LIMITS>

Set critical range for any of the metrics gathered by this script: if
a metric falls within the specified range, report it and exit with
I<CRITICAL> status.  The I<LIMITS> argument is a comma-separated list;
each item in the list has the form I<METRIC=RANGE>, where I<METRIC> is
any of the I<perfdata> labels returned by the script, and I<RANGE> is
any standard Nagios range spec.


=item --freshness, -F I<SECONDS>

Require that a log file has been updated (mtime changed) within the
last I<SECONDS> seconds.  Only used in conjunction with option
C<--log>; ignored otherwise.


=item --host, -H I<HOST>

Require that sockets are bound to hostname/IP address
I<HOST>. Only used in conjunction with option C<--port>.


=item --instances, -n I<RANGE>

Check that the number of process instances matching the given command
line regexp falls in the specified I<RANGE>.  

The I<RANGE> specification deviates from the Nagios standard threshold
notation: a I<RANGE> can be:

=over 8

=item 

a single integer I<N> - in this case the test fails if the number of
instances is not exactly equal to I<N>;

=item

a Nagios range in the form I<N1:N2> - the test fails if the number of
instances does not fall within the specified range;

=item

a triplet of the form I<N1:N2:N3> - then the test passes if the number
of instances falls within I<N1> and I<N2>, fails with I<WARNING> state
if the number of instances falls between I<N2> and I<N3>, and fails
with I<CRITICAL> state if the number of instances exceeds I<N3>.

=back


=item --ipv4, -4

Restrict check to sockets bound to IPv4 addresses.  By default,
I<both> IPv4 and IPv6 sockets are checked.  Only used in conjunction
with option C<--port>; ignored otherwise.


=item --ipv6, -6

Restrict check to sockets bound to IPv6 addresses.  By default,
I<both> IPv4 and IPv6 sockets are checked.  Only used in conjunction
with option C<--port>; ignored otherwise.


=item --label I<WORD>

Use I<WORD> (alphanumeric characters only, no spaces, no punctuation
characters) as a prefix for the labels of Nagios I<perfdata>.  By
default, the process regexp is used, after changing all
non-alphanumeric characters to C<_>.


=item --log, -l I<PATH>

Require that the mtime on the log file pointed to by I<PATH> changed
recently; use option C<--freshness> to control how recently the log
file should have been updated.  If I<PATH> points to a directory, then
the check is successful if I<at least> one file in the directory has
been updated within the specified timeframe.


=item --pidfile, -f I<FILE>

Select process whose PID is stored in I<FILE>.


=item --port, -p I<PORTS>

Require that the selected process listens on TCP/UDP sockets bound to
I<PORTS>. (See section L<DESCRIPTION> for the full syntax of port
specification.)


=item --timeout, -t I<SECS>

Timeout to call external helper applications (e.g., B<lsof>).  If the
command does not complete within I<SECS> seconds time, then the check
is aborted and the plugin exists with I<UNKNOWN> state.


=item --warning, -w

Set warning range for any of the metrics gathered by this script: if a
metric falls within the specified range, report it and exit with
I<WARNING> status (unless overridden by a critical event, see C<-c>).
The I<LIMITS> argument is a comma-separated list; each item in the
list has the form I<METRIC=RANGE>, where I<METRIC> is any of the
I<perfdata> labels returned by the script, and I<RANGE> is any
standard Nagios range spec.


=item --help

Print usage message and exit.

=back


=head1 DESCRIPTION

Check that a process whose command-line matches (PERL-style) regexp
I<CMD> is running. With the C<-f> option, check that the process whose
PID is stored in I<FILE> is running.

Report measurements about the selected process as Nagios I<perfdata>:
e.g., number of running instances, number of open file descriptors,
etc.  

According to the given options, will raise a WARNING or CRITICAL alert
if the selected process(es) do not listen on specified TCP/UDP ports,
or did not modify a log file recently enough.


=head2 Checking activity by log files

If option C<--log>/C<-l> is specified, it should be followed by a
single argument I<PATH>: an additional check is done on the file
pointed to by I<PATH>.  The check succeeds iff the file has been
modified (according to mtime) more recently than the threshold
specified by the C<--freshness> option.  If I<PATH> points to a
directory, then the test succeeds if I<any> of the files in the
directory have been modified more recently than the specified
threshold.


=head2 Checking for bound ports

If option C<--port>/C<-p> is specified, the popular UNIX tool
L<lsof(1)> is run to determine that the specified ports are open by
the selected process and the socket is in I<LISTENING> state.

The argument to option C<--port> is a comma-separated list of
C<PORT/PROTO>, where:

=over 4

=item 

C<PORT> is an integer port (e.g., C<80>), or a dash-separated range of
ports (e.g., C<9000-9002>).  Symbolic port names (e.g., C<smtp>) are
not supported.

=item 

C<PROTO> is either C<tcp> or C<udp>; no check is done on the protocol
if not specified (default).

=back

Checking socket status is faster than trying to open a connection to
the ports, and also does not affect processes which barf at improper
connection termination (i.e., won't clutter the system logs with
"connection dropped" messages).  On the other hand, it is less
reliable, as the socket may be in the I<LISTENING> state according to
the OS, but the bound process may be unresponsive.


=head2 Metrics and Nagios I<perfdata>

Some measurements are made on the process(es) matching the given
regexp, and reported as Nagios I<perfdata>.  Any of these metrics can
be tested against a limit range, and a I<WARNING>/I<CRITICAL> alert
will be raised if the metric value falls in the specified range (see
the C<-c> and C<-w> options).

=over 4

=item C<instances>

Number of processes matching the given command-line regexp.

=item C<open_files>

Number of I<file descriptors> in use; note that this includes also the
number of network sockets, not just the on-disk files.

=item C<rss>

Total amount of main memory occupied.

=item C<vmem>

Total amount of virtual memory occupied.

=item C<cputime>

Total CPU time consumed by the process.

=item C<open_sockets>

Number of open network sockets (all protocols).

=item C<connections_in>

Number of I<incoming> established TCP connections.

=item C<connections_out>

Number of I<outgoing> established TCP connections.

=back

I<Note:> if several process instance match the given command-line
regexp, then each of the above metrics will be the I<sum> of the
measurements made on each matching process.


=head1 EXAMPLES

Check for a running B<cfexecd>; at least one instance should be
running, but allow two for the times when the child agent is spawned:

  # check_daemon.pl cfexecd -n 1:2
  DAEMON OK - Found 1 running instance of process 'cfexecd' | cfexecd_instances=1;; cfexecd_time=2250000s;; cfexecd_open_files=23;; cfexecd_sockets=0;; cfexecd_rss=1273856kB;; cfexecd_vmem=8482816kB;;

Check for a running B<maui>, listening on port 15004/tcp (PBS
scheduler service) and writing to log file F</var/log/naui.log>.
There must be one and only one instance of the scheduler process:

  # check_daemon.pl maui -p 15004/tcp -n 1 -l /var/log/maui.log
  DAEMON OK - Found 1 running instance of process 'maui' listening on port 15004/tcp | maui_instances=1;; maui_open_files=19;; maui_sockets=2;; maui_cputime=134324790000s;; maui_rss=204165120kB;; maui_vmem=218042368kB;;

Check for B<tomcat> instances: they are detected by presence of the
Java class C<catalina> on the command-line; however, use C<tomcat> as
a prefix for I<perfdata> labels:

  # check_daemon.pl org.apache.catalina.startup.Bootstrap --label tomcat

Ditto, but require at least one instance and turn critical if there
are more than 200:

  # check_daemon.pl org.apache.catalina.startup.Bootstrap --label tomcat -n 1:200

Ditto, and additionally warn if there are more than 50000 open
files/sockets:

  # check_daemon.pl org.apache.catalina.startup.Bootstrap --label tomcat -n 1:200 -w open_files=50000


=head1 BUGS AND TO-DO

Ports I<must> be specified as a positive integer; service names
(e.g., C<smtp> for C<25/tcp>) are not accepted.

No error is printed if a port number is out of range (e.g., negative
integer or greater than 65535); invalid ports are silently ignored.

Should be able to use host IP instead of hostname, to avoid B<lsof>
doing the reverse lookup of hostnames.


=head1 AUTHOR

L<Riccardo Murri|riccardo.murri@cscs.ch>


=head1 COPYRIGHT AND LICENCE

Copyright (c) 2008-2009, ETH Zuerich / L<CSCS | http://cscs.ch>.

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
use POSIX qw(strftime);
use Sys::Hostname;

use Nagios::Plugin;
use Proc::ProcessTable;
use Unix::Lsof;


## metric descriptions (for readable error messages)

my %description = (
    'instances'=>"number of processes matching the given command-line regexp",
    'open_files'=>"number of file descriptors in use",
    'rss'=>"total amount of main memory occupied",
    'vmem'=>"total amount of virtual memory occupied",
    'cputime'=>"total CPU time consumed by the process",
    'sockets'=>"number of open network sockets",
    'connections_in'=>"number of incoming established TCP connections",
    'connections_out'=>"Number of outgoing established TCP connections"
);

my %units = (
    'rss'=>"kB",
    'vmem'=>"kB",
    'cputime'=>"s",
);


## parse command-line

pod2usage(-exitval => 1, -verbose => 0) unless $ARGV[0];

my @critical;
my $freshness = 300; # 5 minutes
my $instances = 1;
my $ipv4 = undef;
my $ipv6 = undef;
my $host = undef;
my $label = undef;
my $log = undef;
my $pidfile = undef;
my $portlist = undef;
my $timeout = 10;
my $verbose = 0;
my @warning;

my $np = Nagios::Plugin->new;    
Getopt::Long::Configure ('gnu_getopt', 'no_ignore_case');
GetOptions (
    'critical|c=s'   => \@critical,
    'freshness|F=i'  => \$freshness,
    'instances|n=s'  => \$instances,
    'ipv4|4!'        => \$ipv4,
    'ipv6|6!'        => \$ipv6,
    'host|H=s'       => \$host,
    'label=s'        => \$label,
    'log|l=s'        => \$log,
    'pidfile|f=s'    => \$pidfile,
    'port|ports|p=s' => \$portlist,
    'verbose|v:+'    => \$verbose,
    'warnings|w=s'   => \@warning,
    'help|h'         => sub { pod2usage(-exitval => 0, -verbose => ($verbose? 1+$verbose : 0)); },
    'version|V'      => sub { print Nagios::Plugin::Functions::get_shortname() 
                                  . " $VERSION\n"; 
                              exit 3; }
    );

my $process = $ARGV[0];

# by default, scan both IPv4 and IPv6 addresses
($ipv4, $ipv6) = (1, 1) if (not $ipv4 and not $ipv6);

# by default, use canonical system hostname
$host = hostname unless defined($host);

# extract limits out of the -w and -c options
my %warning;
foreach (split /,/, (join (',', @warning))) {
    my ($metric, $range) = split /=/;
    $warning{$metric} = $range;
}

my %critical;
foreach (split /,/, (join (',', @critical))) {
    my ($metric, $range) = split /=/;
    $critical{$metric} = $range;
}


## subroutines

sub threshold_ok ($$) {
    my $num = shift;
    my $range = shift;
    # if $range is a single numeric value, then check for equality
    return ($num == $range) if ($range =~ m'^\d+$');
    # if range is a pair `num1:num2` or `num1:`, then raise an alert 
    # when $num falls outside the range
    return (OK == $np->check_threshold(check=>$num, warning=>$range))
        if ($range =~ m/\@?(\d*:\d+|\d+:\d*)/); # std Nagios range/threshold
    # if range is a triple `num1:num2:num3`, then return WARNING state
    # when $num falls in the range num1:num2, 
    return (OK == $np->check_threshold(check=>$num, 
                                       warning=>"$2:$3",
                                       critical=>"$3:"))
        if ($range =~ m/(\d*):(\d+):(\d*)/);
};


## main

$np->nagios_exit(UNKNOWN, "Cannot parse command-line '@ARGV':"
            ." need 1 argument, the process name regexp.")
    if (scalar(@ARGV) != 1) and not $pidfile;

# build process table
my $pt_factory = new Proc::ProcessTable( enable_ttys => 0 );
my $pt = $pt_factory->table;

my @instances;
if ($pidfile) {
# read pidfile
    open PIDFILE, "< $pidfile"
        or $np->nagios_die("Cannot read file '$pidfile': $!");
    local $/ = undef; # enable slurp mode locally
    my $pidfile_contents = <PIDFILE>;
    my $pid = (split /\s/, $pidfile_contents)[0];
    $np->nagios_die("Cannot read any PID from file '$pidfile'")
        unless $pid;
    @instances = grep { $_->pid == $pid } @$pt;

    $process = $instances[0]->fname;
}
else {
    my $PPID = getppid();
    # grep for processes matching the given command-line regexp (and exclude this one and its parent!)
    @instances = grep { $_->cmndline =~ qr{$process} and $_->pid != $PID and $_->pid != $PPID } @$pt;
}

my $num_instances = scalar @instances;
$np->nagios_exit(CRITICAL, 
                 "Found ".$num_instances
                 ." process instances matching command-line regexp '$process',"
                 ." expected $instances")
    if not threshold_ok($num_instances, $instances);

# try to re-use process regexp as label
$label = $process unless defined($label);
$label =~ s/\W/_/g;

# build list of (numeric) ports
my @ports;
if ($portlist) {
    foreach (split(/,/, $portlist)) {
        my ($portspec, $proto) = split qr{/};
        $proto = 'any' if not defined($proto);
        $proto = lc($proto);
        
        if ($portspec =~ m/(\d+)-(\d+)/) {
            push @ports, [$_, $proto] foreach ($1..$2);
        }
        else {
            push @ports, [$portspec, $proto];
        }
    } 
}

# cumulative data we are going to gather
my %listen;
my %established;

my %metrics;
$metrics{'open_files'} = 0;
$metrics{'rss'} = 0;
$metrics{'sockets'} = 0;
$metrics{'vmem'} = 0;
$metrics{'cputime'} = 0;

# flags to determine if a file is a socket
my %is_socket = (
    'IPv4'=> $ipv4,
    'IPv6'=> $ipv6
);

foreach my $instance (@instances) {
    my $pid = $instance->pid;

    $metrics{'rss'} += $instance->rss;
    $metrics{'vmem'} += $instance->size;
    $metrics{'cputime'} += $instance->time;

    my $lsof;
    eval { 
        local $SIG{ALRM} = sub { die "Timeout reading 'lsof' output\n" }; # NB: \n required
        alarm $timeout;
        
        $lsof = lsof("-l", "-P", "-p", $pid, { suppress_errors => 0 }); 
        
        alarm 0;
    };
    $np->nagios_die("Error: $@") if $@;
    $np->nagios_die('Error running lsof: ' . $lsof->errors()) if $lsof->has_errors();

    foreach my $file (@{$lsof->{'output'}->{"$pid"}->{'files'}}) {
        $metrics{'open_files'}++;
        if (defined($file->{'file type'}) and $is_socket{$file->{'file type'}}) {
            my $proto = lc($file->{'protocol name'});
            my $state = lc($file->{'tcp/tpi info'}->{'connection state'});
            if ($state eq 'listen' or $proto eq 'udp') {
                $file->{'file name'} =~ m/:([0-9]+)/;
                $listen{$1.'_'.$proto}++;
            }
            elsif ($state eq 'established') {
                $established{$proto}++;
                if ($file->{'file name'} =~ m/$host:([0-9]+)->/) {
                    $established{'out'}++;
                    $established{'out_'.$1.'_'.$proto}++;
                }
                elsif ($file->{'file name'} =~ m/->$host:([0-9]+)/) {
                    $established{'in'}++;
                    $established{'in_'.$1.'_'.$proto}++;
                };
            }
            #$metrics{'sockets'}{$proto}++;
            $metrics{'sockets'}++;
        }
    }
}

$metrics{'instances'} = $num_instances;
$metrics{'_connections_in'} = $established{'in'};
$metrics{'connections_out'} = $established{'out'};

# output information as perfdata
foreach (keys %metrics) {
    $np->add_perfdata( 
        label=>($label.'_'.$_), 
        value=>$metrics{$_}, 
        uom=> (defined($units{$_})? $units{$_} : undef)
        )
        if defined($metrics{$_});
}
foreach (@ports) {
    my $portproto = 'in_'.join ('_', @$_);
    $np->add_perfdata( label=>$label.'_connections_'.$portproto, 
                       value=>$established{$portproto} )
        if defined($established{$portproto});
};

# check that metrics are within the specified limits
foreach (keys %critical) {
    $np->add_message(CRITICAL, 
                     "$description{$_} scored $metrics{$_}:"
                     ." out of limit range $critical{$_}")
        if $np->check_threshold(check=>$metrics{$_},
                                critical=>$critical{$_});
}

foreach (keys %warning) {
    $np->add_message(WARNING, 
                     "$description{$_} scored $metrics{$_}:"
                     ." out of limit range $warning{$_}")
        if $np->check_threshold(check=>$metrics{$_},
                                warning=>$warning{$_});
}


# check that all required ports are listening 
foreach my $pp (@ports) {
    my ($port, $proto) = @$pp;
    $np->add_message(CRITICAL,
                    "No process instance matching '$process' is listening on port $port/$proto.")
        unless defined($listen{$port.'_'.$proto}) and $listen{$port.'_'.$proto} > 0;
}

# check logfile freshness
if (defined($log)) {
    $np->nagios_die("Non-existent log file path '$log'") unless -e $log;

    if (-d $log) {
        # log path is a directory, scan for modified files
        opendir LOGDIR, $log
            or $np->nagios_die("Cannot open log directory '$log': $@");
        my $latest = 0;
        my @entries = grep { -f "$log/$_" and not m/^\./ } readdir(LOGDIR);
        foreach my $entry (@entries) {
            my $mtime = (stat("$log/$entry"))[9];
            $latest = $mtime if ($mtime > $latest);
        }
        closedir LOGDIR;
        
        $np->add_message(WARNING,
                         "No file in directory '$log' has been modified"
                         ." within the last $freshness seconds")
            if (time() - $latest) > $freshness;
    }
    else {
        # log path is a regular file
        my $mtime = (stat($log))[9]
            or $np->nagios_die("Cannot stat log file path '$log': $@");

        $np->add_message(WARNING, 
                         "Log file '$log' last updated at "
                         . strftime('%H:%M:%S of %a, %b %d', localtime($mtime)))
            if (time() - $mtime) > $freshness;
    }
}

# all tests passed!
$np->add_message(OK, 
                 "Found ".$num_instances." running instance".
                 ($num_instances>1? 's':'')
                 ." of process '$process'"
                 . ($portlist? " listening on port $portlist" : ''));
$np->nagios_exit($np->check_messages(join => ';'));
