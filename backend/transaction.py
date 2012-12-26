#! /usr/bin/python
# -*-coding:utf-8-*-

from gi.repository import Gtk

import pyalpm
import traceback
import sys
from backend import config

interface = Gtk.Builder()
interface.add_from_file('/usr/share/pamac/dialogs.glade')

ProgressWindow = interface.get_object('ProgressWindow')
progress_bar = interface.get_object('progressbar2')
progress_label = interface.get_object('progresslabel2')
ErrorDialog = interface.get_object('ErrorDialog')
WarningDialog = interface.get_object('WarningDialog')
QuestionDialog = interface.get_object('QuestionDialog')
ConfDialog = interface.get_object('ConfDialog')
transaction_desc = interface.get_object('transaction_desc')
down_label = interface.get_object('down_label')

t = None
t_lock = False
conflict_to_remove = None
to_remove = None
to_add = None
to_update = None
do_syncfirst = False
list_first = []

def init_transaction(handle, **options):
	"Transaction initialization"
	global t_lock
	handle.dlcb = cb_dl
	handle.totaldlcb = totaldlcb
	handle.eventcb = cb_event
	handle.questioncb = cb_conv
	handle.progresscb = cb_progress
	handle.logcb = cb_log
	try:
		_t = handle.init_transaction(**options)
		print(_t.flags)
		t_lock = True
		return _t
	except pyalpm.error:
		ErrorDialog.format_secondary_text(traceback.format_exc())
		response = ErrorDialog.run()
		if response:
			ErrorDialog.hide()
		return False

def check_conflicts():
	global conflict_to_remove
	conflict_to_remove = {}
	installed_conflicts = {}
	for pkg in config.handle.get_localdb().pkgcache:
		if pkg.conflicts:
			installed_conflicts[pkg.name] = pkg.conflicts
	targets_conflicts = {}
	targets_replaces = {}
	for pkg in t.to_add:
		if pkg.replaces:
			targets_replaces[pkg.name] = pkg.replaces
		if pkg.conflicts:
			targets_conflicts[pkg.name] = pkg.conflicts
	warning = ''
	if targets_replaces:
		for key, value in targets_replaces.items():
			for name in value:
				pkg = config.handle.get_localdb().get_pkg(name)
				if pkg:
					if not pkg.name in conflict_to_remove.keys():
						conflict_to_remove[pkg.name] = pkg
						if warning:
							warning = warning+'\n'
						warning = warning+pkg.name+' will be replaced by '+key 
	if targets_conflicts:
		for key, value in targets_conflicts.items():
			for name in value:
				pkg = config.handle.get_localdb().get_pkg(name)
				if pkg:
					if not pkg.name in conflict_to_remove.keys():
						conflict_to_remove[pkg.name] = pkg
	if installed_conflicts:
		for key, value in installed_conflicts.items():
			for name in value:
				for pkg in t.to_add:
					if pkg.name == name:
						if not pkg.name in conflict_to_remove.keys():
							conflict_to_remove[pkg.name] = pkg
	if conflict_to_remove:
		WarningDialog.format_secondary_text(warning)
		response = WarningDialog.run()
		if response:
			WarningDialog.hide()

def do_refresh():
	"""Sync databases like pacman -Sy"""
	global t
	global t_lock
	ProgressWindow.show_all()
	for db in config.handle.get_syncdbs():
		if t_lock is False:
			t = init_transaction(config.handle)
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
	ProgressWindow.hide()
	progress_label.set_text('')
	progress_bar.set_text('')

def do_sysupgrade():
	"""Upgrade a system like pacman -Su"""
	global t
	global t_lock
	global to_remove
	global to_add
	global to_update
	if t_lock is False:
		if do_syncfirst is True:
			t = init_transaction(config.handle, recurse = True)
			for pkg in list_first:
				t.add_pkg(pkg)
			to_remove = t.to_remove
			to_add = t.to_add
			set_transaction_desc('update')
			response = ConfDialog.run()
			if response == Gtk.ResponseType.OK:
				t_finalize(t)
			if response == Gtk.ResponseType.CANCEL or Gtk.ResponseType.CLOSE or Gtk.ResponseType.DELETE_EVENT:
				ProgressWindow.hide()
				ConfDialog.hide()
				t.release()
				t_lock = False
		else:
			try:
				t = init_transaction(config.handle)
				t.sysupgrade(downgrade=False)
			except pyalpm.error:
				ErrorDialog.format_secondary_text(traceback.format_exc())
				response = ErrorDialog.run()
				if response:
					ErrorDialog.hide()
				t.release()
				t_lock = False
			check_conflicts()
			to_add = t.to_add
			to_remove = []
			for pkg in conflict_to_remove.values():
				to_remove.append(pkg)
			if len(to_add) + len(to_remove) == 0:
				t.release()
				print("Nothing to update")
			else:
				t.release()
				t = init_transaction(config.handle, noconflicts = True, nodeps = True, nodepversion = True)
				for pkg in to_add:
					t.add_pkg(pkg)
				for pkg in conflict_to_remove.values():
					t.remove_pkg(pkg)
				to_remove = t.to_remove
				to_add = t.to_add
				set_transaction_desc('update')
				if len(transaction_desc) != 0:
					response = ConfDialog.run()
					if response == Gtk.ResponseType.OK:
								t_finalize(t)
					if response == Gtk.ResponseType.CANCEL or Gtk.ResponseType.CLOSE or Gtk.ResponseType.DELETE_EVENT:
						ProgressWindow.hide()
						ConfDialog.hide()
						t.release()
						t_lock = False
				else:
					t_finalize(t)
					t.release()
					t_lock = False

def t_finalize(t):
	ConfDialog.hide()
	try:
		t.prepare()
	except pyalpm.error:
		ErrorDialog.format_secondary_text(traceback.format_exc())
		response = ErrorDialog.run()
		if response:
			ErrorDialog.hide()
		t.release()
		t_lock = False
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
	#	down_label.set_markup('<b>Total Download size: </b>'+format_size(totaldlcb))

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
			break
		else :
			progress_label.set_text(' ')
	if ID is 27:
		progress_label.set_text('Downloading '+format_size(total_size))
		print('Downloading a file')
	if ID is 17:
		progress_label.set_text('Checking signatures')
		print('Checking signatures')
	progress_bar.set_fraction(0.0)
	progress_bar.set_text('')
	print(ID,event)

def cb_conv(*args):
	print("conversation", args)

_logmask = pyalpm.LOG_ERROR | pyalpm.LOG_WARNING

def cb_log(level, line):
	#global t
	#try:
	#	_line = str(_line, encoding='utf-8').strip("\n")
	#except:
	#	_line = str(_line, encoding='latin-1').strip("\n")
	if not (level & _logmask):
		return
	if level & pyalpm.LOG_ERROR:
		ErrorDialog.format_secondary_text("ERROR: "+line)
		response = ErrorDialog.run()
		if response:
			ErrorDialog.hide()
			#t.release()
	elif level & pyalpm.LOG_WARNING:
		WarningDialog.format_secondary_text("WARNING: "+line)
		response = WarningDialog.run()
		if response:
			WarningDialog.hide()
	elif level & pyalpm.LOG_DEBUG:
		line = "DEBUG: " + line
		print(line)
	elif level & pyalpm.LOG_FUNCTION:
		line = "FUNC: " + line
		print(line)
	#sys.stderr.write(line)

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
