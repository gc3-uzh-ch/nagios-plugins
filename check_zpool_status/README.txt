check_zpool_status
==================

Copyright (c) 2008-2009 ETHZ Zuerich / CSCS

To install, just copy "check_zpool_status.pl" in a directory where
your Nagios will be able to execute it.  The PERL module IPC::Run is
needed.  "check_zpool_status.pl" will run "zpool status" and parse its
output.

To see usage instructions, run:

  check_zpool_status.pl --help

To see the complete manual, run:

  check_zpool_status.pl --verbose --help

The "t/" directory contains some example "zpool status" outputs, that
you can test with the "--input" option.  If you find an output which
check_zpool_status cannot parse or parses incorrectly, please send me
a copy.

You may copy, distribute and modify check_zpool_status.pl according to
the terms of the GNU GPL v3 or (at your option) any later version.

-- Riccardo Murri <riccardo.murri@gmail.com>
