#! /usr/bin/python
# -*-coding:utf-8 -*

from gi.repository import Gtk

import pyalpm
import traceback
import config

interface = Gtk.Builder()
interface.add_from_file('gui/dialogs.glade')

ProgressWindow = interface.get_object('ProgressWindow')
progress_bar = interface.get_object('progressbar2')
progress_label = interface.get_object('progresslabel2')
ErrorDialog = interface.get_object('ErrorDialog')
ConfDialog = interface.get_object('ConfDialog')
transaction_desc = interface.get_object('transaction_desc')
down_label = interface.get_object('down_label')

to_remove = None
to_add = None
to_update = None
do_syncfirst = False
list_first = []

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
	global to_remove
	global to_add
	global to_update
	t = init_transaction(config.handle)
	if do_syncfirst is True:
		for pkg in list_first:
			t.add_pkg(pkg)
	else:
		try:
			t.sysupgrade(downgrade=False)
		except pyalpm.error:
			ErrorDialog.format_secondary_text(traceback.format_exc())
			response = ErrorDialog.run()
			if response:
				ErrorDialog.hide()
			t.release()
	try:
		t.prepare()
	except pyalpm.error:
		ErrorDialog.format_secondary_text(traceback.format_exc())
		response = ErrorDialog.run()
		if response:
			ErrorDialog.hide()
		t.release()
	to_remove = t.to_remove
	to_add = t.to_add
	if len(to_add) + len(to_remove) == 0:
		t.release()
	else:
		set_transaction_desc('update')
		if len(transaction_desc) != 0:
			response = ConfDialog.run()
			if response == Gtk.ResponseType.OK:
				t_finalize(t)
			if response == Gtk.ResponseType.CANCEL or Gtk.ResponseType.CLOSE or Gtk.ResponseType.DELETE_EVENT:
				ProgressWindow.hide()
				ConfDialog.hide()
				t.release()
		else:
			t_finalize(t)
			t.release()

def t_finalize(t):
	ConfDialog.hide() 
	try:
		t.commit()
	except pyalpm.error:
		ErrorDialog.format_secondary_text(traceback.format_exc())
		response = ErrorDialog.run()
		if response:
			ErrorDialog.hide()
	ProgressWindow.hide()

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

def set_transaction_desc(mode):
	global transaction_desc
	global down_label
	global to_add
	global to_remove
	global to_update
	transaction_desc.clear()
	if to_remove:
		transaction_desc.append(['To remove:', to_remove[0].name])
		i = 1
		while i < len(to_remove):
			transaction_desc.append([' ', to_remove[i].name])
			i += 1
		down_label.set_markup('')
	if to_add:
		if mode == 'update':
			installed_name = []
			for pkg_object in config.handle.get_localdb().pkgcache:
				installed_name.append(pkg_object.name)
			to_add_name = []
			for pkg_object in to_add:
				to_add_name.append(pkg_object.name)
			to_update = sorted(set(installed_name).intersection(to_add_name))
			to_remove_from_add_name = sorted(set(to_update).intersection(to_add_name))
			for name in to_remove_from_add_name:
					to_add_name.remove(name)
		if to_add_name:
			transaction_desc.append(['To install:', to_add_name[0]])
			i = 1
			while i < len(to_add_name):
				transaction_desc.append([' ', to_add_name[i]])
				i += 1
		if mode == 'normal':
			if to_update:
				transaction_desc.append(['To update:', to_update[0]])
				i = 1
				while i < len(to_update):
					transaction_desc.append([' ', to_update[i]])
					i += 1
		down_label.set_markup('')
		#down_label.set_markup('<b>Total Download size: </b>'+format_size(total_size))

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
		progress_label.set_text('Refreshing...')
		progress_bar.set_text(_target)
		progress_bar.pulse()

def cb_progress(_target, _percent, n, i):
	while Gtk.events_pending():
		Gtk.main_iteration()
	target = _target+' ('+str(i)+'/'+str(n)+')'
	progress_bar.set_fraction(_percent/100)
	progress_bar.set_text(target) 


if __name__ == "__main__":
	True
