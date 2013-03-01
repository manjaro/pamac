#! /usr/bin/python
# -*-coding:utf-8-*-

from gi.repository import Gtk

import pyalpm
from collections import OrderedDict
import dbus
from dbus.mainloop.glib import DBusGMainLoop

from pamac import config, common

t_lock = False
to_remove = []
to_add = []
to_provide = []
to_update = []
handle = None
syncpkgs = OrderedDict()
localpkgs = OrderedDict()

interface = Gtk.Builder()

interface.add_from_file('/usr/share/pamac/gui/dialogs.glade')
ErrorDialog = interface.get_object('ErrorDialog')
WarningDialog = interface.get_object('WarningDialog')
QuestionDialog = interface.get_object('QuestionDialog')

def get_handle():
	global handle
	handle = config.pacman_conf.initialize_alpm()
	print('get handle')

def update_db():
	get_handle()
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
Prepare = proxy.get_dbus_method('Prepare','org.manjaro.pamac')
To_Remove = proxy.get_dbus_method('To_Remove','org.manjaro.pamac')
To_Add = proxy.get_dbus_method('To_Add','org.manjaro.pamac')
Commit = proxy.get_dbus_method('Commit','org.manjaro.pamac')
Release = proxy.get_dbus_method('Release','org.manjaro.pamac')
StopDaemon = proxy.get_dbus_method('StopDaemon','org.manjaro.pamac')

def init_transaction(**options):
	"Transaction initialization"
	global t_lock
	error = Init(dbus.Dictionary(options, signature='sb'))
	if not error:
		t_lock = True
		return True
	else:
		ErrorDialog.format_secondary_text('Init Error:\n'+str(error))
		response = ErrorDialog.run()
		if response:
			ErrorDialog.hide()
		return False

def get_to_remove():
	global to_remove
	to_remove = To_Remove()

def get_to_add():
	global to_add
	to_add = To_Add()

def get_updates():
	"""Return a list of package objects in local db which can be updated"""
	do_syncfirst = False
	list_first = []
	#update_db()
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
			result.append(candidate)
	return do_syncfirst, result
