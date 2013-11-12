nagios-plugins
==============

Icinga/Nagios plugins we use or have used or would like to use :-)

This repository currently contains code for the following checks:

`check_cfengine_last_run.pl`
  Check when cfengine was last run, and raise a warning if this happened too much time back in the past.
`check_daemon.pl`
  Check that a process is running and report measurements about it.
`check_zpool_status/check_zpool_status.pl`
  Check the status of ZFS pools.
`dcache/check_dcache_movers.pl`
  Check for "No Mover found" errors in dCache
`dcache/check_dcache_cells.pl`
  Check availability of d-Cache cells.
`pbs/check_maui_diagnose_j.pl`
  Check MAUI's "diagnose -j" output.
`pbs/check_job_slots.pl`
  Monitor PBS/MAUI job slots usage.

In addition, two template files are provided, to be used as a starting
point for writing new plugins in Python or sh/bash.

Consider all code to be GPLv2+ licensed, unless specified otherwise.
