How to use check_controller.py
------------------------------

The script queries the storage arrays management via http, and parse the XML response to identify unhealthy components.
Configuration is read from file. Look at yaml_conf file in this directory for an example on how to build a configuration file.


How XML response is made
------------------------

The controller replies to http get with an XML document, like the following:

::

	#  <OBJECT basetype="port" name="ports" oid="27" format="rows">
	#    <PROPERTY name="durable-id" type="string" size="20" draw="false" sort="string" display-name="Durable ID">hostport_B1</PROPERTY>
	#    <PROPERTY name="controller" key="true" type="string" size="4" draw="false" sort="string" display-name="Controller">B</PROPERTY>
	#	[...snip...]
	#    <PROPERTY name="configured-speed-numeric" type="uint32" size="8" draw="true" sort="string" display-name="Configured Speed">3</PROPERTY>
	#    <PROPERTY name="health" type="string" size="10" draw="true" sort="string" display-name="Health">N/A</PROPERTY>
	#    <PROPERTY name="health-numeric" type="uint32" size="10" draw="true" sort="string" display-name="Health">4</PROPERTY>
	#    <PROPERTY name="health-reason" type="string" size="80" draw="true" sort="string" display-name="Health Reason">There is no host connection to this host port.</PROPERTY>
	#  </OBJECT>
  
How the script works
--------------------

The XML response is made of different objects, each one with different child (PROPERTY).
check_controllers.py script will check, for some specified univocally defined attributes, the value of "health" attribute in the same object.
The above case is an example of non-significant object, since hostport_B1 is not connected.

This YAML configuration file allows to specify these univocally defined attributes:

::

	objects:
	 controllers:
	 # on this object, look for this attribute
	  durable-id:
	   # this attribute could have the following texts
	   - controller_a
	   - controller_b    

	
Means: looking at the "PROPERTY" xml child, look for attribute name="durable-id"
and verify its text is "controller_a". If so, in the same object look for attribute name="health", and check if it's 'OK'.


for additional checks, should be enough to identify a key that  univocally identify the object you want to check,
and then identify the values that the key can assume.
