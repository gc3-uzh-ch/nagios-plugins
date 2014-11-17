#!/usr/bin/env python
#

"""
A script to check some properties on DotHill controllers. Developed targeting the
Dot Hill AssuredSAN 4730 controller, Version: CF100R038-02.
The script accepts in input a configuration file where
	- a user/password pair is needed to authenticate on the controller
	- a list of management IP of controllers is given
	- a list of property to check is given

"""

import sys
import os
import requests
from lxml import etree
from optparse import OptionParser
import yaml


yaml_document = """
## YAML conf for check_controller.py script
## refer to README in the same directory for a quickstart

# to authenticate on the controllers' management (using 'manage' account)
authentication:
 md5_hex_hash: 539e12f63b693a9970a97b885e857f8b

# on those hosts, query the status of the following objects
objects:
 controllers:
 # on this object, look for this attribute
  durable-id:
   # this attribute could have the following texts
   - controller_a
   - controller_b
#   - expport_out1_a0
#   - expport_out1_b0
   - mgmtport_a
   - mgmtport_b
   - hostport_A0   
   - hostport_A2   
   - hostport_B0   
   - hostport_B2
   - Ctlr B CF
   - Ctlr A CF

 
 volumes:
 # on this object, look for this attribute
  volume-name:
  # this attribute may have the following texts
   - ost01
   - ost02
   - ost03
   - ost04       
   - ost05
   - ost06
   - ost07
   - ost08       
   - ost09
   - ost10
   - ost11
   - ost12       
   - ost13
   - ost14
   - ost15
   - ost16       
   - ost17
   - ost18
   - ost19
   - ost20       
   - ost21
   - ost22
   - ost23
   - ost24       
   - ost25
   - ost26
   - ost27
   - ost28       
   - ost29
   - ost30
   - ost31
   - ost32


# define some hosts
hosts:
 # this is not a name on the dns or /etc/hosts
 sclustre-ctrl-oss1-oss2:
  # controller A and B, with IPs
  - sclustre-ctrl-oss1-oss2-a.es: 10.128.93.16
  - sclustre-ctrl-oss1-oss2-b.es: 10.128.93.17
 sclustre-ctrl-oss3-oss4:
  - sclustre-ctrl-oss3-oss4-a.es: 10.128.93.20
  - sclustre-ctrl-oss3-oss4-b.es: 10.128.93.21 
 sclustre-ctrl-oss5-oss6:
  - sclustre-ctrl-oss5-oss6-a.es: 10.128.93.24
  - sclustre-ctrl-oss5-oss6-b.es: 10.128.93.25 
 sclustre-ctrl-oss7-oss8:
  - sclustre-ctrl-oss7-oss8-a.es: 10.128.93.28
  - sclustre-ctrl-oss7-oss8-b.es: 10.128.93.29 
 sclustre-ctrl-mds1-mds2:
  - sclustre-ctrl-mds1-mds2-a.es: 10.128.93.12
  - sclustre-ctrl-mds1-mds2-b.es: 10.128.93.13  
"""


## print a list of string in a nice way
def get_nice_string(list_or_iterator):
    return ", ".join( str(x) for x in list_or_iterator)
####


class Manage_HTTP_Connection:
	""" Manage HTTP connections: create session and run requests """
	
	connection_per_controller = dict()
	
	## authentication and get a session from controllers management
	def __authenticate_and_get_session(self, ctrl_ip):

		# check if already exists a session for that ip
		if ctrl_ip in self.connection_per_controller:
			return self.connection_per_controller[ctrl_ip]
		# if not, create one
		## get the hash from conf
		md5_hex_hash = doc['authentication']['md5_hex_hash']	
		### LOGIN: run the HTTP GET and get response in xml
		try:
			self.r = requests.get('http://'+ctrl_ip+'/api/login/'+md5_hex_hash, stream=True, timeout=5)			
		except (requests.ConnectionError, requests.Timeout):
			return None
		## get the document root and the session key
		XML_response = etree.parse(self.r.raw)
		
		session_key = XML_response.xpath("/RESPONSE/OBJECT/PROPERTY[@name='response']/text()")[0]
		# map the session key to controller's ip, in order to reuse it next time
		self.connection_per_controller[ctrl_ip] = session_key
		return session_key

	def http_get(self, ip, obj):
		# get a session
		session_key = self.__authenticate_and_get_session(ip)
		if not session_key:
			return None
		# return the requests
		return requests.get('http://'+ip+'/api/show/'+obj, 
			headers={"sessionKey":session_key, "dataType":"api"}, 
			stream=True, timeout=5)
	

	
## ExitStatement class: gather all the status from all the components of every host,
## and exit with CRITICAL if just a single component is unhealthy
class ExitStatement:
	""" Prepare Icinga final exit statement """

	string_list = []
	how_many_status = dict()

	def __init__(self):
		ExitStatement.exit_status={ 'OK':0, 'WARNING':1, 'CRITICAL':2, 'UNKNOWN':3 }
		self.component_list = []		
		self.final_status = 'OK'
		
	def add_component_status(self, component):
		if component.get_status() != 'OK':
			self.final_status = 'CRITICAL'
		self.component_list.append(component)
		
	def exit_statement(self):
		for component in self.component_list:
			string = component.get_component_exit()
			self.string_list.append("on " + component.ctrl + ": " + string)
		return self.final_status + " -- " + get_nice_string(self.string_list)	
		
	def exit_code(self):
		return self.exit_status[self.final_status]

## Component class: a component is for instance a volume, or a controller
class Component:
	""" A component is to be intended a 'volume' or 'controller' """
	
	def __init__(self, component_name, check_dict, host, requested_ctrl):
		self.name = component_name
		self.dict = check_dict
		self.element_list = dict()
		self.host = host
		self.status_message = []
		self.ctrl = requested_ctrl
		self.__status = 'OK'
		
	### CHECK element in component is ok, parse XML and get the health of each element
	def check_element(self, XMLdoc):
		for child in XMLdoc.xpath('/RESPONSE/OBJECT'):
			for key_name in self.dict.keys():
				for element in child:
					if element.get('name') == key_name:
						name = element.text						
					if element.get('name') == 'health' and name in self.dict[key_name]:
						self.add_status(name, element.text)
					else:
						continue
				
	def add_status(self, element_name, element_status):
		self.element_list[element_name] = element_status
		if element_status != 'OK':
			self.set_status('CRITICAL')
			self.status_message.append(element_name + " health is " + element_status)

	def add_custom_status(self, custom_message):
		self.set_status('UNKNOWN')
		self.status_message.append(custom_message)
		
	def get_component_exit(self):
		if len(self.status_message) > 0:
			return get_nice_string(self.status_message)		
		else:
			return "all " + self.name + " are healthy"
						
	def set_status(self,status):
		self.__status=status
		
	def get_status(self):
		return self.__status

#	


'''
start main
configure optionparser
read arguments from command line
'''
parser = OptionParser("Usage: %prog -c conf_filename -H dothill_ctrl")
parser.add_option("-H", "--host", dest="dothill_ctrl",
	default='', help="IP address of DotHill storage controller management")	

(options, args) = parser.parse_args()

# input sanit
if not options.dothill_ctrl:
	parser.print_help()
	sys.exit(2)	

# load the inline yaml configuration
doc = yaml.load(yaml_document)
# this is the controller we want to check
requested_ctrl = options.dothill_ctrl

# create an exit statement, to be filled at the end of the job
exit_stm = ExitStatement()

# create http connection instance
http_connection = Manage_HTTP_Connection()

# iterate over objects specified in configuration file (controllers, volumes, ...)
for obj in doc['objects']:
	check_dict =  doc['objects'][obj]
	# for every object, iterate over hosts
	for host in doc['hosts']:
		skip = False
			
		for ctrl_name in doc['hosts'][host]:
			if skip:
				break
				
			# iterate over different way to reach the same storage array (break loop if success)
			for ctrl in ctrl_name:
				# if not the ctrl we want, please break to the next
				if ctrl != requested_ctrl:
					break
				component = Component(obj, check_dict, host, requested_ctrl)
				r = http_connection.http_get(ctrl_name[ctrl], obj)
				if not r:
					component.add_custom_status("Unable to contact " + ctrl + " (" + ctrl_name[ctrl] + ")")
					exit_stm.add_component_status(component)			
					continue
				XMLdoc = etree.parse(r.raw)
				component.check_element(XMLdoc)
				exit_stm.add_component_status(component)
				# break loop if success
				skip = True
					

##########

				
print exit_stm.exit_statement()

sys.exit(exit_stm.exit_code())
		


