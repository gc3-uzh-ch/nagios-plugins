#!/usr/bin/python
#

"""
A script to check some properties on DotHill controllers. Developed targeting the
Dot Hill AssuredSAN 4730 controller, Version: CF100R038-02.
The script accepts in input a configuration file where
	- a user/password pair is needed to authenticate on the controller
	- a list of management IP of controllers is given
	- a list of property to check is given

"""


########### how the xml response is made

# some property inside an object:


#  <OBJECT basetype="port" name="ports" oid="27" format="rows">
#    <PROPERTY name="durable-id" type="string" size="20" draw="false" sort="string" display-name="Durable ID">hostport_B1</PROPERTY>
#    <PROPERTY name="controller" key="true" type="string" size="4" draw="false" sort="string" display-name="Controller">B</PROPERTY>
#    <PROPERTY name="controller-numeric" key="true" type="uint32" size="4" draw="false" sort="string" display-name="Controller">0</PROPERTY>
#    <PROPERTY name="port" key="true" type="string" size="5" draw="true" sort="string" display-name="Ports">B1</PROPERTY>
#    <PROPERTY name="port-type" type="string" size="8" draw="false" sort="string" display-name="Port Type">FC</PROPERTY>
#    <PROPERTY name="port-type-numeric" type="uint32" size="8" draw="false" sort="string" display-name="Port Type">6</PROPERTY>
#    <PROPERTY name="media" type="string" size="8" draw="true" sort="string" display-name="Media">FC(-)</PROPERTY>
#    <PROPERTY name="target-id" type="string" size="224" draw="true" sort="string" display-name="Target ID">257000c0ff1a60ee</PROPERTY>
#    <PROPERTY name="status" type="string" size="13" draw="true" sort="string" display-name="Status">Disconnected</PROPERTY>
#    <PROPERTY name="status-numeric" type="uint32" size="13" draw="true" sort="string" display-name="Status">6</PROPERTY>
#    <PROPERTY name="actual-speed" type="string" size="8" draw="true" sort="string" display-name="Actual Speed"></PROPERTY>
#    <PROPERTY name="actual-speed-numeric" type="uint32" size="8" draw="true" sort="string" display-name="Actual Speed">255</PROPERTY>
#    <PROPERTY name="configured-speed" type="string" size="8" draw="true" sort="string" display-name="Configured Speed">Auto</PROPERTY>
#    <PROPERTY name="configured-speed-numeric" type="uint32" size="8" draw="true" sort="string" display-name="Configured Speed">3</PROPERTY>
#    <PROPERTY name="health" type="string" size="10" draw="true" sort="string" display-name="Health">N/A</PROPERTY>
#    <PROPERTY name="health-numeric" type="uint32" size="10" draw="true" sort="string" display-name="Health">4</PROPERTY>
#    <PROPERTY name="health-reason" type="string" size="80" draw="true" sort="string" display-name="Health Reason">There is no host connection to this host port.</PROPERTY>
#    <PROPERTY name="health-recommendation" type="string" size="900" draw="true" sort="string" display-name="Health Recommendation">- If this host port is intentionally unused, no action is required.
#  - Otherwise, use an appropriate interface cable to connect this host port to a switch or host.
#  - If a cable is connected, check the cable and the switch or host for problems.</PROPERTY>
#  </OBJECT>
  
# I need to check, for some durable-id like 'controller_a' or 'hostport_A0', the value of 'health'.
# The above case is an example of non-significant object, since hostport_B1 is not connected.

# So I defined a check_dict where
# - the `key` is something I need to identify an attribute I must check
# - the `value` is a list of values that the key can have in the different objects
# e.g. : Looking at the "PROPERTY" xml child, look for attribute name="durable-id"
# and verify its text is "hostport_A0". If so, look for attribute name="health",
# and check if it's 'OK'

# by default I will check if the health property of the object has a 'OK' value, and report CRITICAL state if not

# for additional checks, should be enough to identify a key that univocally identify the object you want to check,
# and then identify the values that the key can assume.


import sys
import hashlib
import urllib2
import os
import exceptions
import requests
import xml.dom.minidom
from lxml import etree
from optparse import OptionParser
from pprint import pprint
import yaml
import StringIO


## prettify XML
def pretty_xml(xml_string):
	"This will prettify xml strings"
	xml = xml.dom.minidom.parseString(xml_string)
	pretty_xml = xml.toprettyxml()
	print pretty_xml
	return
####	

## print a list of string in a nice way
def get_nice_string(list_or_iterator):
    return ", ".join( str(x) for x in list_or_iterator)
####

## authentication on controllers management
def authenticate_and_get_session(url_login):
	## get the hash from conf
	md5_hex_hash = doc['authentication']['md5_hex_hash']	
	### LOGIN: run the HTTP GET and get response in xml
	r = requests.get('http://'+url_login+'/api/login/'+md5_hex_hash, stream=True)
	XMLdoc = etree.parse(r.raw)
	## get the document root and the session key
	session_key = XMLdoc.xpath("/RESPONSE/OBJECT/PROPERTY[@name='response']/text()")[0]
	return session_key


	
## ExitStatement class: gather all the status from all the components of every host,
## and exit with CRITICAL if a single component is unhealthy
class ExitStatement:
	""" Prepare Nagios exit statement """

	string_list = []

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
			string = component.get_component_status()
			self.string_list.append("on " + component.host + ": " + string)
		return self.final_status + " -- " + get_nice_string(self.string_list)	
		
	def exit_code(self):
		return self.exit_status[self.final_status]

## Component class: a component is for instance a volume, or a controller
class Component:
	""" A component is to be intended a 'volume' or 'controller' """
	
	def __init__(self, component_name, check_dict, host):
		self.name = component_name
		self.dict = check_dict
		self.element_list = dict()
		self.host = host
		self.status_message = []
		self.__status = 'OK'
		
	### CHECK element in component is ok, parse XML and get the health of each element
	def check_element(self, XMLdoc):
		for child in XMLdoc.xpath('/RESPONSE/OBJECT'):
			for key_name in self.dict.keys():
				for element in child:
					if element.get('name') == key_name:
						name = element.text						
					if element.get('name') == 'health' and name in self.dict[key_name]:
						self.addStatus(name, element.text)
					else:
						continue
				
	def addStatus(self, element_name, element_status):
		self.element_list[element_name] = element_status
		if element_status != 'OK':
			self.set_status('CRITICAL')
			self.status_message.append(element_name + " health is " + element_status)

	def add_custom_status(self, custom_message):
		self.set_status('UNKNOWN')
		self.status_message.append(custom_message)
		
	def get_component_status(self):
		if len(self.status_message) > 0:
			return get_nice_string(self.status_message)		
		else:
			return "all " + self.name + " are healthy"
		
	def printStatus(self):
		for element in self.elementList:
			print element
				
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
parser = OptionParser("Usage: %prog -c conf_filename")
parser.add_option("-c", "--config", dest="conf_filename",
	default='', help="Configuration file")

(options, args) = parser.parse_args()

# check usage: accept one argument (name of the table file)
if not options.conf_filename:
	parser.print_help()
	sys.exit(2)

# parse confFile
# - read an hash of user_password
# - read a list of hosts
# - read a list of object and, for each object, a dictionary
	
## all the controllers IP
url_login = ['localhost:9999']
## get the hash from user and pass
md5_data="manage_!manage"
md5_hex_hash=hashlib.md5(md5_data).hexdigest()
#
### LOGIN: run the HTTP GET and get response in xml
url = 'http://'+url_login[0]+'/api/login'
r = requests.get('http://'+url_login[0]+'/api/login/'+md5_hex_hash, stream=True)
XMLdoc = etree.parse(r.raw)
## get the document root and the session key
session_key = XMLdoc.xpath("/RESPONSE/OBJECT/PROPERTY[@name='response']/text()")[0]

#check_volumes(ET.fromstring(r.text))
#check_element(ET.parse('vol_test'), 'volume-name', 'volumes')

### yaml test

with open('yaml_conf', 'r') as f:
    doc = yaml.load(f)

exit_stm = ExitStatement()


for obj in doc['objects']:
	check_dict =  doc['objects'][obj]

	for host in doc['hosts']:
		skip = False	
		for ctrl_name in doc['hosts'][host]:
			if skip:
				break
			for ip in ctrl_name:
				component = Component(obj, check_dict, host)
				try:
				
					session_key = authenticate_and_get_session(ctrl_name[ip])
				
					r = requests.get('http://'+ctrl_name[ip]+'/api/show/'+obj, 
						headers={"sessionKey":session_key, "dataType":"api"}, 
						stream=True)
				except requests.ConnectionError as e:
					component.add_custom_status("Unable to contact " + ip + " (" + ctrl_name[ip] + ")")
					exit_stm.add_component_status(component)			
					continue
				XMLdoc = etree.parse(r.raw)
				component.check_element(XMLdoc)
				exit_stm.add_component_status(component)
				skip = True
		

				

##########

#exit_stm = ExitStatement()
#parser = etree.XMLParser(ns_clean=True, recover=True, encoding='utf-8')

#check_dict = { 'durable-id':['controller_a', 'controller_b', 'hostport_A0', 'hostport_A0', 'hostport_A2', 'hostport_B0', 'hostport_B2', 'mgmtport_a', 'mgmtport_b']}
#controller = Component('controllers', check_dict, 'localhost')
#r = requests.get('http://'+url_login[0]+'/api/show/controllers', headers={"sessionKey":session_key, "dataType":"api"}, stream=True)
#XMLdoc = etree.parse(r.raw)

#controller.check_element(XMLdoc)
#exit_stm.add_component_status(controller)



#check_dict = { 'volume-name':['ost01', 'ost05']}
#volumes = Component('volumes', check_dict, 'localhost')
#XMLdoc = etree.parse('vol_test')
#check_element(volumes, XMLdoc, exit_stm)
#exit_stm.add_component(volumes)
				
print exit_stm.exit_statement()

sys.exit(exit_stm.exit_code())
		


#r = requests.get('http://'+url_login[0]+'/api/show/controllers', headers={"sessionKey":session_key, "dataType":"api"})
#print r.text

#check_elements(ET.parse('ctrl_test'), 'durable-id', check_dict, 'controllers')

#for object in tree.findall('OBJECT'):
#	for child in object.findall('PROPERTY'):
#		if child.get('name') == 'health':
#			print child.text			

#print r.text
