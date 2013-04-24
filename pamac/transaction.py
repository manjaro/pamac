#! /usr/bin/python3
# -*- coding:utf-8 -*-

import pyalpm
from collections import OrderedDict
import dbus
from dbus.mainloop.glib import DBusGMainLoop

from pamac import config, common

to_remove = set()
to_add = set()
to_load = set()
to_update = set()
to_provide = set()
handle = None
syncpkgs = OrderedDict()
localpkgs = OrderedDict()

def get_handle():
	global handle
	handle = config.handle()
	print('get handle')

def update_db():
	#get_handle()
	global syncpkgs
	global localpkgs
	syncpkgs = OrderedDict()
	localpkgs = OrderedDict()
	for repo in handle.get_syncdbs():
		for pkg in repo.pkgcache:
			if not pkg.name in syncpkgs.keys():
				syncpkgs[pkg.name] = pkg
	for pkg in handle.get_localdb().pkgcache:
		if not pkg.name in localpkgs.keys():
			localpkgs[pkg.name] = pkg

DBusGMainLoop(set_as_default=True)
bus = dbus.SystemBus()
proxy = bus.get_object('org.manjaro.pamac','/org/manjaro/pamac', introspect=False)
Refresh = proxy.get_dbus_method('Refresh','org.manjaro.pamac')
Init = proxy.get_dbus_method('Init','org.manjaro.pamac')
Sysupgrade = proxy.get_dbus_method('Sysupgrade','org.manjaro.pamac')
Remove = proxy.get_dbus_method('Remove','org.manjaro.pamac')
Add = proxy.get_dbus_method('Add','org.manjaro.pamac')
Load = proxy.get_dbus_method('Load','org.manjaro.pamac')
Prepare = proxy.get_dbus_method('Prepare','org.manjaro.pamac')
To_Remove = proxy.get_dbus_method('To_Remove','org.manjaro.pamac')
To_Add = proxy.get_dbus_method('To_Add','org.manjaro.pamac')
Commit = proxy.get_dbus_method('Commit','org.manjaro.pamac')
Interrupt = proxy.get_dbus_method('Interrupt','org.manjaro.pamac')
Release = proxy.get_dbus_method('Release','org.manjaro.pamac')
StopDaemon = proxy.get_dbus_method('StopDaemon','org.manjaro.pamac')

def init_transaction(**options):
	error = Init(dbus.Dictionary(options, signature='sb'))
	if not error:
		return True
	else:
		return False

def get_updates():
	"""Return a list of package objects in local db which can be updated"""
	do_syncfirst = False
	list_first = []
	_ignorepkgs = []
	update_db()
	for group in handle.ignoregrps:
		db = handle.get_localdb()
		grp = db.read_grp(group)
		if grp:
			name, pkg_list = grp
			for pkg in pkg_list:
				if not pkg.name in _ignorepkgs:
					_ignorepkgs.append(pkg.name)
	for pkgname in handle.ignorepkgs:
		if pkgname in localpkgs.keys():
			if not pkgname in _ignorepkgs:
				_ignorepkgs.append(pkgname)
	if config.syncfirst:
		for name in config.syncfirst:
			if name in localpkgs.keys():
				candidate = pyalpm.sync_newversion(localpkgs[name], handle.get_syncdbs())
				if candidate:
					list_first.append(candidate)
		if list_first:
			do_syncfirst = True
			return do_syncfirst, list_first
	result = []
	for pkg in localpkgs.values():
		candidate = pyalpm.sync_newversion(pkg, handle.get_syncdbs())
		if candidate:
			if not candidate.name in _ignorepkgs:
				result.append(candidate)
	return do_syncfirst, result
