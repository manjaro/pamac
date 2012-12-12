#! /usr/bin/python
# -*-coding:utf-8 -*

from gi.repository import Gtk

import pyalpm
import math
import sys
import config

interface = Gtk.Builder()
interface.add_from_file('gui/dialogs.glade')

ProgressWindow = interface.get_object('ProgressWindow')
progress_bar = interface.get_object('progressbar2')
progress_label = interface.get_object('progresslabel2')

to_remove = None
to_add = None

def init_transaction(handle):
	"Transaction initialization"
	handle.dlcb = cb_dl
	handle.totaldlcb = totaldlcb
	handle.eventcb = cb_event
	handle.questioncb = cb_conv
	handle.progresscb = cb_progress
	try:
		t = handle.init_transaction(cascade = True)
		return t
	except pyalpm.error:
		ErrorDialog.format_secondary_text(traceback.format_exc())
		response = ErrorDialog.run()
		if response:
			ErrorDialog.hide()
		return False

def do_refresh():
	"""Sync databases like pacman -Sy"""
	ProgressWindow.show_all()
	for db in config.handle.get_syncdbs():
		t = init_transaction(config.handle)
		try:
			db.update(force=False)
		except pyalpm.error:
			ErrorDialog.format_secondary_text(traceback.format_exc())
			response = ErrorDialog.run()
			if response:
				ErrorDialog.hide()
		t.release()
	ProgressWindow.hide()
	progress_label.set_text('')
	progress_bar.set_text('')

def do_sysupgrade():
	"""Upgrade a system like pacman -Su"""
	t = init_transaction(config.handle)
	t.sysupgrade(downgrade=False)
	if len(t.to_add) + len(t.to_remove) == 0:
		print("Nothing to do")
		t.release()
		return 0
	else:
		ok = finalize(t)
		return (0 if ok else 1)

def get_updates():
	"""Return a list of package objects in local db which can be updated"""
	installed_pkglist = config.handle.get_localdb().pkgcache
	result = []
	for pkg in installed_pkglist:
		candidate = pyalpm.sync_newversion(pkg, config.handle.get_syncdbs())
		if candidate is not None:
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

# Callbacks
event_text = ' '
def cb_event(ID, event, tupel):
	global event_text
	ProgressWindow.show_all()
	while Gtk.events_pending():
		Gtk.main_iteration()
	for i in [1,3,5,7,9,11,15]:
		if ID is i:
			progress_label.set_text(event)
			print(event)
			break
		else :
			progress_label.set_text(' ')
	if ID is 27:
		progress_label.set_text('Downloading '+format_size(total_size))
		print('Downloading a file')
	progress_bar.set_fraction(0.0)
	progress_bar.set_text('')

def cb_conv(*args):
	print("conversation", args)

total_size = 0
def totaldlcb(_total_size):
	global total_size
	total_size = _total_size

already_transferred = 0
def cb_dl(_target, _transferred, total):
	global already_transferred
	while Gtk.events_pending():
		Gtk.main_iteration()
	if total_size > 0:
		fraction = (_transferred+already_transferred)/total_size
	size = 0
	if (to_remove or to_add):
		for pkg in to_remove+to_add:
			if pkg.name+'-'+pkg.version in _target:
				size = pkg.size
		if _transferred == size:
			already_transferred += size
		progress_label.set_text('Downloading '+format_size(total_size))
		progress_bar.set_text(_target)
		progress_bar.set_fraction(fraction)
	else:
		progress_label.set_text('Downloading...')
		progress_bar.set_text(_target)
		progress_bar.pulse()


def cb_progress(_target, _percent, n, i):
	while Gtk.events_pending():
		Gtk.main_iteration()
	target = _target+' ('+str(i)+'/'+str(n)+')'
	progress_bar.set_fraction(_percent/100)
	progress_bar.set_text(target) 

if __name__ == "__main__":
	do_refresh()
	available_updates = get_updates()
	if not available_updates:
		print("\nNo update available")
	else:
		for pkg in available_updates:
			pkgname = pkg.name
			oldversion = pkg.version
			newversion = get_new_version_available(pkgname)
			print("\n{} {} can be updated to {}".format(pkgname, oldversion, newversion))
