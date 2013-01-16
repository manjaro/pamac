#! /usr/bin/python
# -*-coding:utf-8-*-

from gi.repository import Gtk

import pyalpm
import traceback
import dbus

from pamac import config, common

t_lock = False
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
	error = Init(options)
	if not error:
		t_lock = True
		return True
	else:
		common.ErrorDialog.format_secondary_text(error)
		response = common.ErrorDialog.run()
		if response:
			common.ErrorDialog.hide()
		return False

def check_conflicts():
	to_check = []
	warning = ''
	for pkgname in common.to_add:
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
					if not pkg.name in common.to_remove:
						common.to_remove.append(pkg.name)
						if warning:
							warning = warning+'\n'
						warning = warning+pkg.name+' will be replaced by '+target.name
		if target.conflicts:
			for name in target.conflicts:
				pkg = config.pacman_conf.initialize_alpm().get_localdb().get_pkg(name)
				if pkg:
					if not pkg.name in common.to_remove:
						common.to_remove.append(pkg.name)
		for installed_pkg in config.pacman_conf.initialize_alpm().get_localdb().pkgcache:
			if installed_pkg.conflicts:
				for name in installed_pkg.conflicts:
					if name == target.name:
						if not name in common.to_remove:
							common.to_remove.append(installed_pkg.name)
	if warning:
		common.WarningDialog.format_secondary_text(warning)
		response = common.WarningDialog.run()
		if response:
			common.WarningDialog.hide()

def get_to_remove():
	common.to_remove = To_Remove()

def get_to_add():
	common.to_add = To_Add()

def finalize():
	global t_lock
	while Gtk.events_pending():
		Gtk.main_iteration()
	error = Prepare()
	if error:
		common.ErrorDialog.format_secondary_text(error)
		response = common.ErrorDialog.run()
		if response:
			common.ErrorDialog.hide()
	error = Commit()
	if error:
		common.ErrorDialog.format_secondary_text(error)
		response = common.ErrorDialog.run()
		if response:
			common.ErrorDialog.hide()
	t_lock = False
	Release()
	common.to_add = []
	common.to_remove = []

def do_refresh():
	"""Sync databases like pacman -Sy"""
	global t
	global t_lock
	for db in config.pacman_conf.initialize_alpm().get_syncdbs():
		if t_lock is False:
			t = init_transaction()
			try:
				db.update(force=False)
				t.release()
				t_lock = False
			except pyalpm.error:
				common.ErrorDialog.format_secondary_text(traceback.format_exc())
				response = common.ErrorDialog.run()
				if response:
					common.ErrorDialog.hide()
				t_lock = False
				break
	t_lock = False

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
