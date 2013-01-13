#! /usr/bin/python
# -*-coding:utf-8-*-

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GObject, Gtk

import pyalpm
import traceback
from pamac import config, callbacks

loop = GObject.MainLoop()

t = None
error = ''

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
			try:
				callbacks.handle.dlcb = callbacks.cb_dl
				callbacks.handle.totaldlcb = callbacks.totaldlcb
				callbacks.handle.eventcb = callbacks.cb_event
				callbacks.handle.questioncb = callbacks.cb_conv
				callbacks.handle.progresscb = callbacks.cb_progress
				callbacks.handle.logcb = callbacks.cb_log
				t = callbacks.handle.init_transaction(**options)
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
			pkg = callbacks.handle.get_localdb().get_pkg(pkgname)
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
			for repo in callbacks.handle.get_syncdbs():
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
		except pyalpm.error:
			error = traceback.format_exc()
		finally:
			print('to_add:',t.to_add)
			print('to_remove:',t.to_remove)
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
			try:
				callbacks.ProgressWindow.show_all()
				while Gtk.events_pending():
					Gtk.main_iteration()
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
			try:
				callbacks.ProgressWindow.hide()
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
