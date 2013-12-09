#!/usr/bin/env python
#
# Adapted from the original code at
# http://skipperkongen.dk/2011/12/06/hello-world-plugin-for-nagios-in-python/
#
"""
A simple "hello world" Nagios/Icinga check, to be used as a
template for writing other and more complex ones.
"""

# optparse is Python 2.3 - 2.6, deprecated in 2.7, but we need to stay
# compatible with Python 2.4 until we get rid of the last RHEL5.x
# machine, so stick with `optparse` for the moment.
from optparse import OptionParser
import os
import sys

# exit statuses recognized by Nagios
OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

# template for reading parameters from commandline
# a `--help` option is automatically added by `optparse`
parser = OptionParser()
parser.add_option("-m", "--message", dest="message",
   default='Hello world', help="A message to print after OK - ")
(options, args) = parser.parse_args()

# RETURN OUTPUT TO NAGIOS
# using the example `-m` parameter parsed from commandline
print ("OK - %s" % (options.message))
sys.exit(OK)
