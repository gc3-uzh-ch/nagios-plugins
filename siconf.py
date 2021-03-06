#!/usr/bin/python
#
# draft for siconf script
# link to task: adminwiki/tasks/Icinga_simplified_checks_table/
# target:frequency:options:command
# syntax of generic service with mandatory fields
#	define service {
#    service_description	nscd check
#  	 use             		generic-service
#  	 register              	1
#  	 hostgroup_name        	gc3-hosts
#  	 check_command         	check_nscd
#	}

# frequency in api 
# print to stdout or to file
# check if /etc/icinga/icinga.cfg exists

import sys
import os
import exceptions
from optparse import OptionParser
from pynag import Model

# to store the service definitions
service_array = []

'''
function to parse input file, where a line is as follows
target:frequency:option:command:service_description
'''
def split_line(text):
	# skip the comment lines
	if text[0] == "#":
		return	
	# explode it		
	explode_list=text.strip().split('|')
#	print len(explode_list)
	# try to identify each field
	# raise an exception if, on each line, we don't have at least 5 fields
	try:		
		# get the frequency
		frequency=explode_list[1]
		# get the options
		options=explode_list[2]
		# get the command
		command=explode_list[3]		
		# get the service description
		service=explode_list[4]			
	except IndexError as idx_e:
		sys.stderr.write("A field is missing in the configuration file, on the following line:\n")
		sys.stderr.write(text)
		sys.exit(1)
	# we accept empty values only for option field
	if command == "" or service == "":
		sys.stderr.write("An empty field is now allowed on command, service.\n")
		sys.exit(1)		
	# target is in comma separated list, explode it
	host_list=explode_list[0].strip().split(',')

	# set icinga configuration file
	Model.cfg_file = icinga_conf
	# for each host or host_group in this configuration line	
	for idx, host in enumerate(host_list):
		# create a new service object
		s = Model.Service()
		# Set some attributes for the service
		s.service_description = service
		s.use = 'generic-service'
#		s.register = 'register'
		if frequency != '':
			s.check_interval = frequency
		s.check_command = command
#		s.notification_options = 'y'
		if host[0] == "@":
			s.hostgroup_name = host[1:]
		else:
			s.host_name = host
		if options == "passive":
			s.passive_checks_enabled = '1'
		# put it into an array
		service_array.append(s)

'''
start main
configure optionparser
read arguments from command line
'''
parser = OptionParser("Usage: %prog -i input_file [options]")
parser.add_option("-i", "--input", dest="input_filename",
	default='', help="Path to Icinga service definition short-format file. Example syntax: \n \
	target:frequency:options:command:description \n \
	Use \"-\" to read from STDIN")
parser.add_option("-o", "--output", dest="output_filename",
	default='', help="Write Icinga service definitions to this file.\n \
	Default is pynag dir in $ICINGA_HOME/pynag")
parser.add_option("-c", "--icinga-conf", dest="icinga_conf", default="/etc/icinga/icinga.cfg",
	help="Path to icinga configuration file. Default is %default")
#parser.add_option("-p", "--print", action="store_true", dest="stdout",
#	default=False, help="Write Icinga service definitions to standard output.\n")		

(options, args) = parser.parse_args()

# check usage: accept one argument (name of the table file)
if not options.input_filename:
	parser.print_help()
#	parser.error("Please specify a configuration file.")
#	sys.stderr.write("Usage:  %s [path to configuration file] \n" % (sys.argv[0]))
	sys.exit(2)

input_filename = options.input_filename
output_filename = options.output_filename
icinga_conf = options.icinga_conf
stdout = False
if not output_filename:
	stdout = True
else:
	print "Writing service definitions to {0}".format(output_filename)

# open input file, exit if IO error
if input_filename == '-':
	input_file = sys.stdin
else:
	try:
		input_file = open(input_filename,'r')
	except (IOError, exceptions.NameError) as e:
		# print file path here
		print "I/O error({1}) on {0}: {2}".format(e.filename, e.errno, e.strerror) 
		sys.exit(1)

# open icinga configuration file, exit if IO error	
try:
	open(icinga_conf,'r')
except (IOError, exceptions.NameError) as e:
	# print file path here
	print "I/O error({1}) on {0}: {2}".format(e.filename, e.errno, e.strerror) 
	sys.exit(1)	

# parse each line of the configuration file
for line in input_file:
	# for each line explode strings on colon delimiter ":"
	split_line(line)

# once you have an array of services, iterate over it 
for idx, service in enumerate(service_array):
	if stdout:
		print service
	else:
		# it will write by default to /etc/icinga/pynag (it creates dir if not existing)
		service.set_filename(output_filename)
		service.save()		
sys.exit(0)
