#! /usr/bin/python
# -*-coding:utf-8-*-

from gi.repository import Gtk, GObject

import pyalpm
import traceback
import dbus
from dbus.mainloop.glib import DBusGMainLoop

from pamac import config

interface = Gtk.Builder()
interface.add_from_file('/usr/share/pamac/gui/dialogs.glade')

ErrorDialog = interface.get_object('ErrorDialog')
WarningDialog = interface.get_object('WarningDialog')
ProgressWindow = interface.get_object('ProgressWindow')
progress_bar = interface.get_object('progressbar2')
progress_label = interface.get_object('progresslabel2')
action_icon = interface.get_object('action_icon')

t_lock = False
do_syncfirst = False
list_first = []
to_remove = []
to_add = []
to_update = []

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

def action_signal_handler(action):
	progress_label.set_text(action)

def icon_signal_handler(icon):
	action_icon.set_from_file(icon)

def target_signal_handler(target):
	progress_bar.set_text(target)

def percent_signal_handler(percent):
	progress_bar.set_fraction(float(percent))

bus.add_signal_receiver(action_signal_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitAction")
bus.add_signal_receiver(icon_signal_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitIcon")
bus.add_signal_receiver(target_signal_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitTarget")
bus.add_signal_receiver(percent_signal_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitPercent")

def init_transaction(**options):
	"Transaction initialization"
	global t_lock
	error = Init(options)
	if not error:
		t_lock = True
		return True
	else:
		ErrorDialog.format_secondary_text(error)
		response = ErrorDialog.run()
		if response:
			ErrorDialog.hide()
		return False

def check_conflicts():
	global to_add
	global to_remove
	to_check = []
	warning = ''
	for pkgname in to_add:
		for repo in config.pacman_conf.initialize_alpm().get_syncdbs():
			pkg = repo.get_pkg(pkgname)
			if pkg:
				to_check.append(pkg)
				break
	for target in to_check:
		if target.replaces:
			for name in target.replaces:
				pkg = config.pacman_conf.initialize_alpm().get_localdb().get_pkg(name)
				if pkg:
					if not pkg.name in to_remove:
						to_remove.append(pkg.name)
						if warning:
							warning = warning+'\n'
						warning = warning+pkg.name+' will be replaced by '+target.name
		if target.conflicts:
			for name in target.conflicts:
				pkg = config.pacman_conf.initialize_alpm().get_localdb().get_pkg(name)
				if pkg:
					if not pkg.name in to_remove:
						to_remove.append(pkg.name)
		for installed_pkg in config.pacman_conf.initialize_alpm().get_localdb().pkgcache:
			if installed_pkg.conflicts:
				for name in installed_pkg.conflicts:
					if name == target.name:
						if not name in to_remove:
							to_remove.append(installed_pkg.name)
	if warning:
		WarningDialog.format_secondary_text(warning)
		response = WarningDialog.run()
		if response:
			WarningDialog.hide()

def get_to_remove():
	global to_remove
	to_remove = To_Remove()

def get_to_add():
	global to_add
	to_add = To_Add()

def finalize():
	global t_lock
	error = Prepare()
	if error:
		ErrorDialog.format_secondary_text(error)
		response = ErrorDialog.run()
		if response:
			ErrorDialog.hide()
		Release()
		t_lock = False
	else:
		ProgressWindow.show_all()
		while Gtk.events_pending():
			Gtk.main_iteration()
		Commit(reply_handler = handle_reply, error_handler = handle_error, timeout = 2000*1000)

def handle_error(error):
	global t_lock
	global to_add
	global to_remove
	if not 'DBus.Error.NoReply' in str(error):
		ErrorDialog.format_secondary_text('Commit Error:\n'+str(error))
		response = ErrorDialog.run()
		if response:
			ErrorDialog.hide()
	t_lock = False
	Release()
	ProgressWindow.hide()
	to_add = []
	to_remove = []

def handle_reply(reply):
	global t_lock
	global to_add
	global to_remove
	print('reply',reply)
	t_lock = False
	Release()
	ProgressWindow.hide()
	to_add = []
	to_remove = []

def do_refresh():
	"""Sync databases like pacman -Sy"""
	global t
	global t_lock
	if t_lock is False:
		progress_label.set_text('Refreshing...')
		progress_bar.pulse()
		action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/refresh-cache.png')
		ProgressWindow.show_all()
		t_lock = True
		Refresh(reply_handler = handle_reply, error_handler = handle_error, timeout = 2000*1000)

def get_updates():
	"""Return a list of package objects in local db which can be updated"""
	global do_syncfirst
	global list_first
	if config.syncfirst:
		for name in config.syncfirst:
			pkg = config.pacman_conf.initialize_alpm().get_localdb().get_pkg(name)
			candidate = pyalpm.sync_newversion(pkg, config.pacman_conf.initialize_alpm().get_syncdbs())
			if candidate:
				list_first.append(candidate)
		if list_first:
			do_syncfirst = True
			return list_first
	result = []
	installed_pkglist = config.pacman_conf.initialize_alpm().get_localdb().pkgcache
	for pkg in installed_pkglist:
		candidate = pyalpm.sync_newversion(pkg, config.pacman_conf.initialize_alpm().get_syncdbs())
		if candidate:
			result.append(candidate)
	return result

def get_new_version_available(pkgname):
	for repo in config.pacman_conf.initialize_alpm().get_syncdbs():
		pkg = repo.get_pkg(pkgname)
		if pkg is not None:
			return pkg.version
			break
