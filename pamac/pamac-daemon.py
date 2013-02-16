#! /usr/bin/python
# -*-coding:utf-8-*-

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GObject

import pyalpm
import traceback
from pamac import config, common

class PamacDBusService(dbus.service.Object):
	def __init__(self):
		bus=dbus.SystemBus()
		bus_name = dbus.service.BusName('org.manjaro.pamac', bus)
		dbus.service.Object.__init__(self, bus_name, '/org/manjaro/pamac')
		self.t = None
		self.error = ''
		self.warning = ''
		self.action = 'Preparing...'
		self.icon = '/usr/share/pamac/icons/24x24/status/setup.png'
		self.target = ''
		self.percent = 0
		self.total_size = 0
		self.already_transferred = 0
		config.handle.dlcb = self.cb_dl
		config.handle.totaldlcb = self.totaldlcb
		config.handle.eventcb = self.cb_event
		config.handle.questioncb = self.cb_conv
		config.handle.progresscb = self.cb_progress
		config.handle.logcb = self.cb_log

	@dbus.service.signal('org.manjaro.pamac')
	def EmitAction(self, action):
		pass

	@dbus.service.signal('org.manjaro.pamac')
	def EmitIcon(self, icon):
		pass

	@dbus.service.signal('org.manjaro.pamac')
	def EmitTarget(self, target):
		pass

	@dbus.service.signal('org.manjaro.pamac')
	def EmitPercent(self, percent):
		pass

	def cb_event(self, ID, event, tupel):
		if ID is 1:
			self.action = 'Checking dependencies...'
			self.icon = '/usr/share/pamac/icons/24x24/status/package-search.png'
		elif ID is 3:
			self.action = 'Checking file conflicts...'
			self.icon = '/usr/share/pamac/icons/24x24/status/package-search.png'
		elif ID is 5:
			self.action = 'Resolving dependencies...'
			self.icon = '/usr/share/pamac/icons/24x24/status/setup.png'
		elif ID is 7:
			self.action = 'Checking inter conflicts...'
			self.icon = '/usr/share/pamac/icons/24x24/status/package-search.png'
		elif ID is 9:
			self.action = 'Installing...'
			self.icon = '/usr/share/pamac/icons/24x24/status/package-add.png'
		elif ID is 11:
			self.action = 'Removing...'
			self.icon = '/usr/share/pamac/icons/24x24/status/package-delete.png'
		elif ID is 13:
			self.action = 'Upgrading...'
			self.icon = '/usr/share/pamac/icons/24x24/status/package-update.png'
		elif ID is 15:
			self.action = 'Checking integrity...'
			self.icon = '/usr/share/pamac/icons/24x24/status/package-search.png'
			self.already_transferred = 0
		elif ID is 17:
			self.action = 'Loading packages files...'
			self.icon = '/usr/share/pamac/icons/24x24/status/package-search.png'
			print('Loading packages files')
		elif ID is 26:
			self.action = 'Configuring...'
			self.icon = '/usr/share/pamac/icons/24x24/status/setup.png'
			print('Configuring a package')
		elif ID is 27:
			print('Downloading a file')
		else :
			self.action = ''
		self.EmitTarget('')
		self.EmitPercent(str(0))
		self.EmitAction(self.action)
		self.EmitIcon(self.icon)
		print(ID,event)

	def cb_conv(self, *args):
		print("conversation", args)

	def cb_log(self, level, line):
		#global t
		_logmask = pyalpm.LOG_ERROR | pyalpm.LOG_WARNING
		if not (level & _logmask):
			return
		if level & pyalpm.LOG_ERROR:
			self.error = "ERROR: "+line
				#t.release()
		elif level & pyalpm.LOG_WARNING:
			self.warning = "WARNING: "+line
		elif level & pyalpm.LOG_DEBUG:
			line = "DEBUG: " + line
			print(line)
		elif level & pyalpm.LOG_FUNCTION:
			line = "FUNC: " + line
			print(line)

	def totaldlcb(self, _total_size):
		self.total_size = _total_size

	def cb_dl(self, _target, _transferred, total):
		if self.total_size > 0:
			fraction = (_transferred+self.already_transferred)/self.total_size
		size = 0
		if (t.to_remove or t.to_add):
			for pkg in t.to_remove+t.to_add:
				if pkg.name+'-'+pkg.version in _target:
					size = pkg.size
			if _transferred == size:
				self.already_transferred += size
			self.action = 'Downloading '+common.format_size(self.total_size)
			self.target = _target
			if fraction > 1:
				self.percent = 0
			else:
				self.percent = fraction
			self.icon = '/usr/share/pamac/icons/24x24/status/package-download.png'
		else:
			self.action = 'Refreshing...'
			self.target = _target
			self.percent = 0
			self.icon = '/usr/share/pamac/icons/24x24/status/refresh-cache.png'
		self.EmitAction(self.action)
		self.EmitIcon(self.icon)
		self.EmitTarget(self.target)
		self.EmitPercent(str(self.percent))

	def cb_progress(self, _target, _percent, n, i):
		self.target = _target+' ('+str(i)+'/'+str(n)+')'
		self.percent = _percent/100
		self.EmitTarget(self.target)
		self.EmitPercent(str(self.percent))

	def policykit_test(self, sender,connexion, action):
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

	@dbus.service.method('org.manjaro.pamac', '', 's')
	def Refresh(self):
		global t
		global error
		error = ''
		for db in config.handle.get_syncdbs():
			try:
				t = config.handle.init_transaction()
				db.update(force=False)
				t.release()
			except pyalpm.error:
				error = traceback.format_exc()
				break
		return error

	@dbus.service.signal('org.manjaro.pamac')
	def EmitAvailableUpdates(self, available_updates):
		pass

	@dbus.service.method('org.manjaro.pamac', '', '')
	def CheckUpdates(self):
		for pkg in config.handle.get_localdb().pkgcache:
			candidate = pyalpm.sync_newversion(pkg, config.handle.get_syncdbs())
			if candidate:
				self.EmitAvailableUpdates(True)
				return

	@dbus.service.method('org.manjaro.pamac', 'a{sb}', 's', sender_keyword='sender', connection_keyword='connexion')
	def Init(self, options, sender=None, connexion=None):
		global t
		global error
		if self.policykit_test(sender,connexion,'org.manjaro.pamac.init_release'):
			error = ''
			try:
				t = config.handle.init_transaction(**options)
				print('Init:',t.flags)
			except pyalpm.error:
				error = traceback.format_exc()
			finally:
				return error 
		else :
			return 'You are not authorized'

	@dbus.service.method('org.manjaro.pamac', '', 's')
	def Sysupgrade(self):
		global t
		global error
		error = ''
		try:
			t.sysupgrade(downgrade=False)
			print('to_upgrade:',t.to_add)
		except pyalpm.error:
			error = traceback.format_exc()
		finally:
			return error

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

	@dbus.service.method('org.manjaro.pamac', '', 's', sender_keyword='sender', connection_keyword='connexion')#, async_callbacks=('success', 'nosuccess'))
	def Commit(self, sender=None, connexion=None):#success, nosuccess, sender=None, connexion=None):
		global t
		global error
		error = ''
		if self.policykit_test(sender,connexion,'org.manjaro.pamac.commit'): 
			try:
				t.commit()
				#success('')
			except pyalpm.error:
				error = traceback.format_exc()
				#nosuccess(error)
			except dbus.exceptions.DBusException:
				pass
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
				t.release()
			except pyalpm.error:
				error = traceback.format_exc()
			finally:
				return error 
		else :
			return 'You are not authorized'

	@dbus.service.method('org.manjaro.pamac')
	def StopDaemon(self):
		global t
		try:
			t.release()
		except:
			pass
		mainloop.quit()

DBusGMainLoop(set_as_default=True)
myservice = PamacDBusService()
mainloop = GObject.MainLoop()
mainloop.run()
