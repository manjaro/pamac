#! /usr/bin/python
# -*-coding:utf-8-*-

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GObject, Gtk

import pyalpm
import traceback
from pamac import config, common

loop = GObject.MainLoop()

t = None
error = ''

interface = Gtk.Builder()
interface.add_from_file('/usr/share/pamac/gui/dialogs.glade')

ProgressWindow = interface.get_object('ProgressWindow')
progress_bar = interface.get_object('progressbar2')
progress_label = interface.get_object('progresslabel2')
action_icon = interface.get_object('action_icon')

def cb_event(ID, event, tupel):
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
		common.ErrorDialog.format_secondary_text("ERROR: "+line)
		response = common.ErrorDialog.run()
		if response:
			common.ErrorDialog.hide()
			#t.release()
	elif level & pyalpm.LOG_WARNING:
		common.WarningDialog.format_secondary_text("WARNING: "+line)
		response = common.WarningDialog.run()
		if response:
			common.WarningDialog.hide()
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
	if (t.to_remove or t.to_add):
		for pkg in t.to_remove+t.to_add:
			if pkg.name+'-'+pkg.version in _target:
				size = pkg.size
		if _transferred == size:
			already_transferred += size
		progress_label.set_text('Downloading '+common.format_size(total_size))
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


class PamacDBusService(dbus.service.Object):
	def __init__(self):
		bus=dbus.SystemBus()
		bus_name = dbus.service.BusName('org.manjaro.pamac', bus)
		dbus.service.Object.__init__(self, bus_name, '/org/manjaro/pamac')

	def policykit_test(self,sender,connexion,action):
		bus = dbus.SystemBus()
		proxy_dbus = connexion.get_object('org.freedesktop.DBus','/org/freedesktop/DBus/Bus', False)
		dbus_info = dbus.Interface(proxy_dbus,'org.freedesktop.DBus')
		sender_pid = dbus_info.GetConnectionUnixProcessID(sender)
		proxy_policykit = bus.get_object('org.freedesktop.PolicyKit1','/org/freedesktop/PolicyKit1/Authority',False)
		policykit_authority = dbus.Interface(proxy_policykit,'org.freedesktop.PolicyKit1.Authority')

		Subject = ('unix-process', {'pid': dbus.UInt32(sender_pid, variant_level=1),
						'start-time': dbus.UInt64(0, variant_level=1)})
		(is_authorized,is_challenge,details) = policykit_authority.CheckAuthorization(Subject, action, {'': ''}, dbus.UInt32(1), '')
		return is_authorized

	@dbus.service.method('org.manjaro.pamac', 'a{sb}', 's', sender_keyword='sender', connection_keyword='connexion')
	def Init(self, options, sender=None, connexion=None):
		global t
		global error
		if self.policykit_test(sender,connexion,'org.manjaro.pamac.init_release'):
			error = ''
			config.handle.dlcb = cb_dl
			config.handle.totaldlcb = totaldlcb
			config.handle.eventcb = cb_event
			config.handle.questioncb = cb_conv
			config.handle.progresscb = cb_progress
			config.handle.logcb = cb_log
			try:
				t = config.handle.init_transaction(**options)
				print('Init:',t.flags)
			except pyalpm.error:
				error = traceback.format_exc()
			finally:
				return error 
		else :
			return 'You are not authorized'

	@dbus.service.method('org.manjaro.pamac', 's', 's')
	def Remove(self, pkgname):
		global t
		global error
		error = ''
		try:
			pkg = config.handle.get_localdb().get_pkg(pkgname)
			if pkg is not None:
				t.remove_pkg(pkg)
		except pyalpm.error:
			error = traceback.format_exc()
		finally:
			return error

	@dbus.service.method('org.manjaro.pamac', 's', 's')
	def Add(self, pkgname):
		global t
		global error
		error = ''
		try:
			for repo in config.handle.get_syncdbs():
				pkg = repo.get_pkg(pkgname)
				if pkg:
					t.add_pkg(pkg)
					break
		except pyalpm.error:
			error = traceback.format_exc()
		finally:
			return error

	@dbus.service.method('org.manjaro.pamac', '', 's')
	def Prepare(self):
		global t
		global error
		error = ''
		try:
			t.prepare()
			print('to_add:',t.to_add)
			print('to_remove:',t.to_remove)
		except pyalpm.error:
			error = traceback.format_exc()
		finally:
			return error 

	@dbus.service.method('org.manjaro.pamac', '', 'as')
	def To_Remove(self):
		global t
		liste = []
		for pkg in t.to_remove:
			liste.append(pkg.name)
		return liste 

	@dbus.service.method('org.manjaro.pamac', '', 'as')
	def To_Add(self):
		global t
		liste = []
		for pkg in t.to_add:
			liste.append(pkg.name)
		return liste 

	@dbus.service.method('org.manjaro.pamac', '', 's',sender_keyword='sender', connection_keyword='connexion')
	def Commit(self, sender=None, connexion=None):
		global t
		global error
		if self.policykit_test(sender,connexion,'org.manjaro.pamac.commit'): 
			ProgressWindow.show_all()
			while Gtk.events_pending():
				Gtk.main_iteration()
			try:
				t.commit()
			except pyalpm.error:
				error = traceback.format_exc() 
			finally:
				return error
		else :
			return 'You are not authorized'

	@dbus.service.method('org.manjaro.pamac', '', 's', sender_keyword='sender', connection_keyword='connexion')
	def Release(self, sender=None, connexion=None):
		global t
		global error
		if self.policykit_test(sender,connexion,'org.manjaro.pamac.init_release'):
			error = ''
			ProgressWindow.hide()
			try:
				t.release()
			except pyalpm.error:
				error = traceback.format_exc()
			finally:
				return error 
		else :
			return 'You are not authorized'

	@dbus.service.method('org.manjaro.pamac')
	def StopDaemon(self):
		loop.quit()


DBusGMainLoop(set_as_default=True)
myservice = PamacDBusService()
loop.run()
