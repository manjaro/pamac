#! /usr/bin/python
# -*-coding:utf-8-*-

from gi.repository import Gtk

import pyalpm
import traceback
import dbus

from pamac import config

interface = Gtk.Builder()
interface.add_from_file('/usr/share/pamac/gui/dialogs.glade')

ErrorDialog = interface.get_object('ErrorDialog')
WarningDialog = interface.get_object('WarningDialog')

t = None
t_lock = False
conflict_to_remove = None
to_remove = None
to_add = None
to_update = None
do_syncfirst = False
list_first = []

proxy = dbus.SystemBus().get_object('org.manjaro.pamac','/org/manjaro/pamac')
Init = proxy.get_dbus_method('Init','org.manjaro.pamac')
Remove = proxy.get_dbus_method('Remove','org.manjaro.pamac')
Add = proxy.get_dbus_method('Add','org.manjaro.pamac')
Prepare = proxy.get_dbus_method('Prepare','org.manjaro.pamac')
To_Remove = proxy.get_dbus_method('To_Remove','org.manjaro.pamac')
To_Add = proxy.get_dbus_method('To_Add','org.manjaro.pamac')
Commit = proxy.get_dbus_method('Commit','org.manjaro.pamac')
Release = proxy.get_dbus_method('Release','org.manjaro.pamac')

def init_transaction(**options):
	"Transaction initialization"
	global t_lock
	global proxy
	error = Init(options)
	print(error)
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
	global conflict_to_remove
	global to_add
	global to_remove
	conflict_to_remove = {}
	to_check = []
	warning = ''
	for pkgname in to_add:
		for repo in config.handle.get_syncdbs():
			pkg = repo.get_pkg(pkgname)
			if pkg:
				to_check.append(pkg)
				break
	for target in to_check:
		if target.replaces:
			for name in target.replaces:
				pkg = config.handle.get_localdb().get_pkg(name)
				if pkg:
					if not pkg.name in to_remove:
						to_remove.append(pkg.name)
						if warning:
							warning = warning+'\n'
						warning = warning+pkg.name+' will be replaced by '+target.name
		if target.conflicts:
			for name in target.conflicts:
				pkg = config.handle.get_localdb().get_pkg(name)
				if pkg:
					if not pkg.name in to_remove:
						to_remove.append(pkg.name)
		for installed_pkg in config.handle.get_localdb().pkgcache:
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
	while Gtk.events_pending():
		Gtk.main_iteration()
	error = Prepare()
	if error:
		ErrorDialog.format_secondary_text(error)
		response = ErrorDialog.run()
		if response:
			transaction.ErrorDialog.hide()
	error = Commit()
	if error:
		ErrorDialog.format_secondary_text(error)
		response = ErrorDialog.run()
		if response:
			transaction.ErrorDialog.hide()
	t_lock = False
	Release()

def do_refresh():
	"""Sync databases like pacman -Sy"""
	global t
	global t_lock
	for db in config.handle.get_syncdbs():
		if t_lock is False:
			t = init_transaction()
			try:
				db.update(force=False)
				t.release()
				t_lock = False
			except pyalpm.error:
				ErrorDialog.format_secondary_text(traceback.format_exc())
				response = ErrorDialog.run()
				if response:
					ErrorDialog.hide()
				t_lock = False
				break
	t_lock = False
	progress_label.set_text('')
	progress_bar.set_text('')

def get_updates():
	"""Return a list of package objects in local db which can be updated"""
	global do_syncfirst
	global list_first
	if config.syncfirst:
		for name in config.syncfirst:
			pkg = config.handle.get_localdb().get_pkg(name)
			candidate = pyalpm.sync_newversion(pkg, config.handle.get_syncdbs())
			if candidate:
				list_first.append(candidate)
		if list_first:
			do_syncfirst = True
			return list_first
	result = []
	installed_pkglist = config.handle.get_localdb().pkgcache
	for pkg in installed_pkglist:
		candidate = pyalpm.sync_newversion(pkg, config.handle.get_syncdbs())
		if candidate:
			result.append(candidate)
	return result

def get_new_version_available(pkgname):
	for repo in config.handle.get_syncdbs():
		pkg = repo.get_pkg(pkgname)
		if pkg is not None:
			return pkg.version
			break

def format_size(size):
	KiB_size = size / 1024
	if KiB_size < 1000:
		size_string = '%.1f KiB' % (KiB_size)
		return size_string
	else:
		size_string = '%.2f MiB' % (KiB_size / 1024)
		return size_string
