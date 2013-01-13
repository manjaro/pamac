#! /usr/bin/python
# -*-coding:utf-8-*-

from gi.repository import Gtk
import pyalpm
from pamac import config

handle = config.handle

# Callbacks
interface = Gtk.Builder()
interface.add_from_file('/usr/share/pamac/gui/dialogs.glade')

ProgressWindow = interface.get_object('ProgressWindow')
progress_bar = interface.get_object('progressbar2')
progress_label = interface.get_object('progresslabel2')
action_icon = interface.get_object('action_icon')

event_text = ' '
def cb_event(ID, event, tupel):
	global event_text
	while Gtk.events_pending():
		Gtk.main_iteration()
	if ID is 1:
		progress_label.set_text('Checking dependencies')
		action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/package-search.png')
	elif ID is 3:
		progress_label.set_text('Checking file conflicts')
		action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/package-search.png')
	elif ID is 5:
		progress_label.set_text('Resolving dependencies')
		action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/setup.png')
	elif ID is 7:
		progress_label.set_text('Checking inter conflicts')
		action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/package-search.png')
	elif ID is 9:
		progress_label.set_text('Installing packages')
		action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/package-add.png')
	elif ID is 11:
		progress_label.set_text('Removing packages')
		action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/package-delete.png')
	elif ID is 13:
		progress_label.set_text('Upgrading packages')
		action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/package-update.png')
	elif ID is 15:
		progress_label.set_text('Checking integrity')
		action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/package-search.png')
	elif ID is 17:
		progress_label.set_text('Checking signatures')
		action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/package-search.png')
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
		action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/package-download.png')
	else:
		progress_label.set_text('Refreshing...')
		progress_bar.set_text(_target)
		progress_bar.pulse()
		action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/refresh-cache.png')

def cb_progress(_target, _percent, n, i):
	while Gtk.events_pending():
		Gtk.main_iteration()
	target = _target+' ('+str(i)+'/'+str(n)+')'
	progress_bar.set_fraction(_percent/100)
	progress_bar.set_text(target) 
