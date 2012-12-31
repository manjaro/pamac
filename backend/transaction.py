#! /usr/bin/python
# -*-coding:utf-8-*-

from gi.repository import Gtk

import pyalpm
import traceback

from backend import config

interface = Gtk.Builder()
interface.add_from_file('/usr/share/pamac/dialogs.glade')

ProgressWindow = interface.get_object('ProgressWindow')
progress_bar = interface.get_object('progressbar2')
progress_label = interface.get_object('progresslabel2')
action_icon = interface.get_object('action_icon')
ErrorDialog = interface.get_object('ErrorDialog')
WarningDialog = interface.get_object('WarningDialog')
QuestionDialog = interface.get_object('QuestionDialog')

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
	warning = ''
	for target in t.to_add:
		if target.replaces:
			for name in target.replaces:
				pkg = config.handle.get_localdb().get_pkg(name)
				if pkg:
					if not pkg.name in conflict_to_remove.keys():
						conflict_to_remove[pkg.name] = pkg
						if warning:
							warning = warning+'\n'
						warning = warning+pkg.name+' will be replaced by '+target.name
		if target.conflicts:
			for name in target.conflicts:
				pkg = config.handle.get_localdb().get_pkg(name)
				if pkg:
					if not pkg.name in conflict_to_remove.keys():
						conflict_to_remove[pkg.name] = pkg
		for installed_pkg in config.handle.get_localdb().pkgcache:
			if installed_pkg.conflicts:
				for name in installed_pkg.conflicts:
					if name == target.name:
						if not name in conflict_to_remove.keys():
							conflict_to_remove[installed_pkg.name] = installed_pkg
	if warning:
		WarningDialog.format_secondary_text(warning)
		response = WarningDialog.run()
		if response:
			WarningDialog.hide()

def do_refresh():
	"""Sync databases like pacman -Sy"""
	global t
	global t_lock
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
	progress_label.set_text('')
	progress_bar.set_text('')

def t_finalize(t):
	ProgressWindow.show_all()
	try:
		t.prepare()
	except pyalpm.error:
		ErrorDialog.format_secondary_text(traceback.format_exc())
		response = ErrorDialog.run()
		if response:
			ErrorDialog.hide()
	try:
		t.commit()
	except pyalpm.error:
		ErrorDialog.format_secondary_text(traceback.format_exc())
		response = ErrorDialog.run()
		if response:
			ErrorDialog.hide()
	t_lock = False
	ProgressWindow.hide()
	t.release()

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


# Callbacks
event_text = ' '
def cb_event(ID, event, tupel):
	global event_text
	while Gtk.events_pending():
		Gtk.main_iteration()
	if ID is 1:
		progress_label.set_text('Checking dependencies')
		action_icon.set_from_file('/usr/share/icons/hicolor/24x24/status/package-search.png')
	elif ID is 3:
		progress_label.set_text('Checking file conflicts')
		action_icon.set_from_file('/usr/share/icons/hicolor/24x24/status/package-search.png')
	elif ID is 5:
		progress_label.set_text('Resolving dependencies')
		action_icon.set_from_file('/usr/share/icons/hicolor/24x24/status/setup.png')
	elif ID is 7:
		progress_label.set_text('Checking inter conflicts')
		action_icon.set_from_file('/usr/share/icons/hicolor/24x24/status/package-search.png')
	elif ID is 9:
		progress_label.set_text('Installing packages')
		action_icon.set_from_file('/usr/share/icons/hicolor/24x24/status/package-add.png')
	elif ID is 11:
		progress_label.set_text('Removing packages')
		action_icon.set_from_file('/usr/share/icons/hicolor/24x24/status/package-delete.png')
	elif ID is 13:
		progress_label.set_text('Upgrading packages')
		action_icon.set_from_file('/usr/share/icons/hicolor/24x24/status/package-update.png')
	elif ID is 15:
		progress_label.set_text('Checking integrity')
		action_icon.set_from_file('/usr/share/icons/hicolor/24x24/status/package-search.png')
	elif ID is 17:
		progress_label.set_text('Checking signatures')
		action_icon.set_from_file('/usr/share/icons/hicolor/24x24/status/package-search.png')
		print('Checking signatures')
	elif ID is 27:
		print('Downloading a file')
	else :
		progress_label.set_text('')
	progress_bar.set_fraction(0.0)
	progress_bar.set_text('')
	print(ID,event)

def cb_conv(*args):
	print("conversation", args)

_logmask = pyalpm.LOG_ERROR | pyalpm.LOG_WARNING

def cb_log(level, line):
	#global t
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
		action_icon.set_from_file('/usr/share/icons/hicolor/24x24/status/package-download.png')
	else:
		progress_label.set_text('Refreshing...')
		progress_bar.set_text(_target)
		progress_bar.pulse()
		action_icon.set_from_file('/usr/share/icons/hicolor/24x24/status/refresh-cache.png')

def cb_progress(_target, _percent, n, i):
	while Gtk.events_pending():
		Gtk.main_iteration()
	target = _target+' ('+str(i)+'/'+str(n)+')'
	progress_bar.set_fraction(_percent/100)
	progress_bar.set_text(target) 


if __name__ == "__main__":
	True
