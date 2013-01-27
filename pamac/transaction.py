#! /usr/bin/python
# -*-coding:utf-8-*-

from gi.repository import Gtk

import pyalpm
import dbus
from dbus.mainloop.glib import DBusGMainLoop

from pamac import config

interface = Gtk.Builder()
interface.add_from_file('/usr/share/pamac/gui/dialogs.glade')

ErrorDialog = interface.get_object('ErrorDialog')
WarningDialog = interface.get_object('WarningDialog')
QuestionDialog = interface.get_object('QuestionDialog')
ProgressWindow = interface.get_object('ProgressWindow')
progress_bar = interface.get_object('progressbar2')
progress_label = interface.get_object('progresslabel2')
action_icon = interface.get_object('action_icon')
ProgressCancelButton = interface.get_object('ProgressCancelButton')

t_lock = False
do_syncfirst = False
list_first = []
to_remove = []
to_add = []
to_update = []
handle = None

def get_handle():
	global handle
	handle = config.pacman_conf.initialize_alpm()

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

def action_signal_handler(action):
	progress_label.set_text(action)
	#~ if 'Downloading' in action:
		#~ print('cancel enabled')
		#~ ProgressCancelButton.set_visible(True)
	#~ else:
	ProgressCancelButton.set_visible(False)
		#~ print('cancel disabled')

def icon_signal_handler(icon):
	action_icon.set_from_file(icon)

def target_signal_handler(target):
	progress_bar.set_text(target)

def percent_signal_handler(percent):
	#~ if percent == '0':
		#~ progress_bar.pulse()
	#~ else:
	progress_bar.set_fraction(float(percent))

bus.add_signal_receiver(action_signal_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitAction")
bus.add_signal_receiver(icon_signal_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitIcon")
bus.add_signal_receiver(target_signal_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitTarget")
bus.add_signal_receiver(percent_signal_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitPercent")

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

def check_conflicts():
	global to_add
	global to_remove
	to_check = []
	installed_pkg_name = []
	syncdbs_pkg_name = []
	warning = ''
	for pkgname in to_add:
		for repo in handle.get_syncdbs():
			pkg = repo.get_pkg(pkgname)
			if pkg:
				to_check.append(pkg)
				break
	for installed_pkg in handle.get_localdb().pkgcache:
		installed_pkg_name.append(installed_pkg.name)
	for target in to_check:
		for name in target.replaces:
			if name in installed_pkg_name:
				if not name in to_remove:
					to_remove.append(name)
					if warning:
						warning = warning+'\n'
					warning = warning+name+' will be replaced by '+target.name
		for name in target.conflicts:
			if name in to_add:
				to_add.remove(name)
				to_add.remove(target.name)
				if warning:
					warning = warning+'\n'
				warning = warning+name+' conflicts with '+target.name+'\nNone of them will be installed'
			if name in installed_pkg_name:
				if not name in to_remove:
					to_remove.append(name)
					if warning:
						warning = warning+'\n'
					warning = warning+name+' conflicts with '+target.name
		for installed_pkg in handle.get_localdb().pkgcache:
			for name in installed_pkg.conflicts:
				if name == target.name:
					if not name in to_remove:
						to_remove.append(installed_pkg.name)
						if warning:
							warning = warning+'\n'
						warning = warning+installed_pkg.name+' conflicts with '+target.name
	for repo in handle.get_syncdbs():
		for pkg in repo.pkgcache:
			for name in pkg.replaces:
				if name in installed_pkg_name:
					if not name in to_remove:
						to_remove.append(name)
						if warning:
							warning = warning+'\n'
						warning = warning+name+' will be replaced by '+pkg.name
					if not pkg.name in to_add:
						to_add.append(pkg.name)
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

def do_refresh():
	"""Sync databases like pacman -Sy"""
	global t_lock
	get_handle()
	if t_lock is False:
		t_lock = True
		progress_label.set_text('Refreshing...')
		action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/refresh-cache.png')
		ProgressWindow.show_all()
		while Gtk.events_pending():
			Gtk.main_iteration()
		Refresh(reply_handler = handle_reply, error_handler = handle_error, timeout = 2000*1000)

def handle_error(error):
	global t_lock
	if not 'DBus.Error.NoReply' in str(error):
		transaction.ErrorDialog.format_secondary_text('Refresh Error:\n'+str(error))
		response = transaction.ErrorDialog.run()
		if response:
			transaction.ErrorDialog.hide()
	t_lock = False
	Release()
	ProgressWindow.hide()

def handle_reply(reply):
	global t_lock
	t_lock = False
	ProgressWindow.hide()

def get_updates():
	"""Return a list of package objects in local db which can be updated"""
	global do_syncfirst
	global list_first
	get_handle()
	if config.syncfirst:
		for name in config.syncfirst:
			pkg = handle.get_localdb().get_pkg(name)
			candidate = pyalpm.sync_newversion(pkg, handle.get_syncdbs())
			if candidate:
				list_first.append(candidate)
		if list_first:
			do_syncfirst = True
			return list_first
	result = []
	installed_pkglist = handle.get_localdb().pkgcache
	for pkg in installed_pkglist:
		candidate = pyalpm.sync_newversion(pkg, handle.get_syncdbs())
		if candidate:
			result.append(candidate)
	return result

def get_new_version_available(pkgname):
	for repo in handle.get_syncdbs():
		pkg = repo.get_pkg(pkgname)
		if pkg is not None:
			return pkg.version
			break
