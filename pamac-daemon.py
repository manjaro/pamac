#! /usr/bin/python3
# -*- coding:utf-8 -*-

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GObject

import pyalpm
from multiprocessing import Process
from pamac import config, common

# i18n
import gettext
gettext.bindtextdomain('pamac', '/usr/share/locale')
gettext.textdomain('pamac')
_ = gettext.gettext
 
class PamacDBusService(dbus.service.Object):
	def __init__(self):
		bus=dbus.SystemBus()
		bus_name = dbus.service.BusName('org.manjaro.pamac', bus)
		dbus.service.Object.__init__(self, bus_name, '/org/manjaro/pamac')
		self.t = None
		self.task = None
		self.error = ''
		self.warning = ''
		self.previous_action = ''
		self.action = _('Preparing')+'...'
		self.previous_icon = ''
		self.icon = '/usr/share/pamac/icons/24x24/status/setup.png'
		self.previous_target = ''
		self.target = ''
		self.previous_percent = 0
		self.percent = 0
		self.total_size = 0
		self.already_transferred = 0
		self.handle = config.handle()

	def get_handle(self):
		print('daemon get handle')
		self.handle = config.handle()
		self.handle.dlcb = self.cb_dl
		self.handle.totaldlcb = self.totaldlcb
		self.handle.eventcb = self.cb_event
		self.handle.questioncb = self.cb_conv
		self.handle.progresscb = self.cb_progress
		self.handle.logcb = self.cb_log

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
			self.action = _('Checking dependencies')+'...'
			self.icon = '/usr/share/pamac/icons/24x24/status/package-search.png'
		elif ID is 3:
			self.action = _('Checking file conflicts')+'...'
			self.icon = '/usr/share/pamac/icons/24x24/status/package-search.png'
		elif ID is 5:
			self.action = _('Resolving dependencies')+'...'
			self.icon = '/usr/share/pamac/icons/24x24/status/setup.png'
		elif ID is 7:
			self.action = _('Checking inter conflicts')+'...'
			self.icon = '/usr/share/pamac/icons/24x24/status/package-search.png'
		elif ID is 9:
			self.action = _('Installing')+'...'
			self.icon = '/usr/share/pamac/icons/24x24/status/package-add.png'
		elif ID is 10:
			formatted_event = 'Installed {pkgname} ({pkgversion})'.format(pkgname = tupel[0].name, pkgversion = tupel[0].version)
			common.write_log_file(formatted_event)
			print(formatted_event)
		elif ID is 11:
			self.action = _('Removing')+'...'
			self.icon = '/usr/share/pamac/icons/24x24/status/package-delete.png'
		elif ID is 12:
			formatted_event = 'Removed {pkgname} ({pkgversion})'.format(pkgname = tupel[0].name, pkgversion = tupel[0].version)
			common.write_log_file(formatted_event)
			print(formatted_event)
		elif ID is 13:
			self.action = _('Upgrading')+'...'
			self.icon = '/usr/share/pamac/icons/24x24/status/package-update.png'
		elif ID is 14:
			formatted_event = 'Upgraded {pkgname} ({oldversion} -> {newversion})'.format(pkgname = tupel[1].name, oldversion = tupel[1].version, newversion = tupel[0].version)
			common.write_log_file(formatted_event)
			print(formatted_event)
		elif ID is 15:
			self.action = _('Downgrading')+'...'
			self.icon = '/usr/share/pamac/icons/24x24/status/rollback.png'
			print('Downgrading a package')
		#elif ID is 16:
			#formatted_event = 'Downgraded {pkgname} ({oldversion} -> {newversion})'.format(pkgname = tupel[1].name, oldversion = tupel[1].version, newversion = tupel[0].version)
			#common.write_log_file(formatted_event)
			#print(formatted_event)
		elif ID is 17:
			self.action = _('Reinstalling')+'...'
			self.icon = '/usr/share/pamac/icons/24x24/status/package-add.png'
			print('Reinstalling a package')
		#elif ID is 18:
			#formatted_event = 'Reinstalled {pkgname} ({pkgversion})'.format(pkgname = tupel[0].name, pkgversion = tupel[0].version)
			#common.write_log_file(formatted_event)
			#print(formatted_event)
		elif ID is 19:
			self.action = _('Checking integrity')+'...'
			self.icon = '/usr/share/pamac/icons/24x24/status/package-search.png'
			self.already_transferred = 0
		elif ID is 21:
			self.action = _('Loading packages files')+'...'
			self.icon = '/usr/share/pamac/icons/24x24/status/package-search.png'
			print('Loading packages files')
		elif ID is 30:
			self.action = _('Configuring')+'...'
			self.icon = '/usr/share/pamac/icons/24x24/status/setup.png'
			self.EmitPercent(2)
			print('Configuring a package')
		elif ID is 31:
			print('Downloading a file')
		elif ID is 36:
			self.action = _('Checking keys in keyring')+'...'
			self.icon = '/usr/share/pamac/icons/24x24/status/package-search.png'
			print('Checking keys in keyring')
		else :
			self.action = ''
		#self.EmitTarget('')
		#self.EmitPercent(0)
		if self.action != self.previous_action:
			self.previous_action = self.action
			self.EmitAction(self.action)
		if self.icon != self.previous_icon:
			self.previous_icon = self.icon
			self.EmitIcon(self.icon)
		print(ID,event)

	def cb_conv(self, *args):
		print("conversation", args)

	def cb_log(self, level, line):
		_logmask = pyalpm.LOG_ERROR | pyalpm.LOG_WARNING
		if not (level & _logmask):
			return
		if level & pyalpm.LOG_ERROR:
			#self.error += "ERROR: "+line
			self.EmitLogError(line)
			#print(self.error)
			#self.t.release()
		elif level & pyalpm.LOG_WARNING:
			#self.warning += "WARNING: "+line
			self.EmitLogWarning(line)
		elif level & pyalpm.LOG_DEBUG:
			line = "DEBUG: " + line
			print(line)
		elif level & pyalpm.LOG_FUNCTION:
			line = "FUNC: " + line
			print(line)

	@dbus.service.signal('org.manjaro.pamac')
	def EmitLogError(self, message):
		pass

	@dbus.service.signal('org.manjaro.pamac')
	def EmitLogWarning(self, message):
		pass

	def totaldlcb(self, _total_size):
		self.total_size = _total_size

	def cb_dl(self, _target, _transferred, total):
		if self.total_size > 0:
			fraction = (_transferred+self.already_transferred)/self.total_size
		size = 0
		try:
			if (self.t.to_remove or self.t.to_add):
				for pkg in self.t.to_remove+self.t.to_add:
					if pkg.filename == _target:
						size = pkg.size
				if _transferred == size:
					self.already_transferred += size
				self.action = _('Downloading {size}').format(size = common.format_size(self.total_size))
				self.target = _target
				self.percent = round(fraction, 2)
				self.icon = '/usr/share/pamac/icons/24x24/status/package-download.png'
			else:
				self.action = _('Refreshing')+'...'
				self.target = _target
				self.percent = 2
				self.icon = '/usr/share/pamac/icons/24x24/status/refresh-cache.png'
			if self.action != self.previous_action:
				self.previous_action = self.action
				self.EmitAction(self.action)
			if self.icon != self.previous_icon:
				self.previous_icon = self.icon
				self.EmitIcon(self.icon)
			if self.target != self.previous_target:
				self.previous_target = self.target
				self.EmitTarget(self.target)
			if self.percent != self.previous_percent:
				self.previous_percent = self.percent
				self.EmitPercent(self.percent)
		except pyalpm.error:
			pass

	def cb_progress(self, _target, _percent, n, i):
		self.target = _target+' ('+str(i)+'/'+str(n)+')'
		#self.percent = round(_percent/100, 2)
		self.percent = round(i/n, 2)
		if self.target != self.previous_target:
			self.previous_target = self.target
			self.EmitTarget(self.target)
		if self.percent != self.previous_percent:
			self.previous_percent = self.percent
			self.EmitPercent(self.percent)

	def policykit_test(self, sender, connexion, action):
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

	@dbus.service.signal('org.manjaro.pamac')
	def EmitAvailableUpdates(self, updates_nb):
		pass

	def CheckUpdates(self):
		updates = 0
		_ignorepkgs = []
		for group in self.handle.ignoregrps:
			db = self.handle.get_localdb()
			grp = db.read_grp(group)
			if grp:
				name, pkg_list = grp
				for pkg in pkg_list:
					if not pkg.name in _ignorepkgs:
						_ignorepkgs.append(pkg.name)
		for name in self.handle.ignorepkgs:
			pkg = self.handle.get_localdb().get_pkg(name)
			if pkg:
				if not pkg.name in _ignorepkgs:
					_ignorepkgs.append(pkg.name)
		if config.syncfirst:
			for name in config.syncfirst:
				pkg = self.handle.get_localdb().get_pkg(name)
				if pkg:
					candidate = pyalpm.sync_newversion(pkg, self.handle.get_syncdbs())
					if candidate:
						updates += 1
		if not updates:
			for pkg in self.handle.get_localdb().pkgcache:
				candidate = pyalpm.sync_newversion(pkg, self.handle.get_syncdbs())
				if candidate:
					if not candidate.name in _ignorepkgs:
						updates += 1
		self.EmitAvailableUpdates(updates)

	@dbus.service.method('org.manjaro.pamac', '', 's', async_callbacks=('success', 'nosuccess'))
	def Refresh(self, success, nosuccess):
		def refresh():
			self.target = ''
			self.percent = 0
			self.error = ''
			self.get_handle()
			for db in self.handle.get_syncdbs():
				try:
					self.t = self.handle.init_transaction()
					db.update(force = False)
				except pyalpm.error as e:
					self.error += ' --> '+str(e)+'\n'
					break
				finally:
					try:
						self.t.release()
					except:
						pass
			if self.error:
				self.EmitTransactionError(self.error)
			else:
				self.EmitTransactionDone('')
				self.CheckUpdates()
		self.task = Process(target=refresh)
		self.task.start()
		success('')

	@dbus.service.method('org.manjaro.pamac', 'a{sb}', 's')#, sender_keyword='sender', connection_keyword='connexion')
	def Init(self, options):#, sender=None, connexion=None):
		self.error = ''
		#if self.policykit_test(sender,connexion,'org.manjaro.pamac.init_release'):
		try:
			self.get_handle()
			self.t = self.handle.init_transaction(**options)
			print('Init:',self.t.flags)
		except pyalpm.error as e:
			self.error += ' --> '+str(e)+'\n'
		finally:
			if self.error:
				self.EmitTransactionError(self.error)
			return self.error
		#else:
		#	return _('Authentication failed')

	@dbus.service.method('org.manjaro.pamac', '', 's')
	def Sysupgrade(self):
		self.error = ''
		try:
			self.t.sysupgrade(downgrade=False)
			print('to_upgrade:',self.t.to_add)
		except pyalpm.error as e:
			self.error += ' --> '+str(e)+'\n'
		finally:
			return self.error

	@dbus.service.method('org.manjaro.pamac', 's', 's')
	def Remove(self, pkgname):
		self.error = ''
		try:
			pkg = self.handle.get_localdb().get_pkg(pkgname)
			if pkg is not None:
				self.t.remove_pkg(pkg)
		except pyalpm.error as e:
			self.error += ' --> '+str(e)+'\n'
		finally:
			return self.error

	@dbus.service.method('org.manjaro.pamac', 's', 's')
	def Add(self, pkgname):
		self.error = ''
		try:
			for repo in self.handle.get_syncdbs():
				pkg = repo.get_pkg(pkgname)
				if pkg:
					self.t.add_pkg(pkg)
					break
		except pyalpm.error as e:
			self.error += ' --> '+str(e)+'\n'
		finally:
			return self.error

	@dbus.service.method('org.manjaro.pamac', 's', 's')
	def Load(self, tarball_path):
		self.error = ''
		try:
			pkg = self.handle.load_pkg(tarball_path)
			if pkg:
				self.t.add_pkg(pkg)
		except pyalpm.error:
			self.error += _('{pkgname} is not a valid path or package name').format(pkgname = tarball_path)
		finally:
			return self.error

	@dbus.service.method('org.manjaro.pamac', '', 's')
	def Prepare(self):
		self.error = ''
		try:
			self.t.prepare()
		except pyalpm.error as e:
			print(e)
			self.error += ' --> '+str(e)+'\n'
		finally:
			return self.error

	@dbus.service.method('org.manjaro.pamac', '', 'a(ss)')
	def To_Remove(self):
		liste = []
		for pkg in self.t.to_remove:
			liste.append((pkg.name, pkg.version))
		return liste

	@dbus.service.method('org.manjaro.pamac', '', 'a(ssi)')
	def To_Add(self):
		liste = []
		for pkg in self.t.to_add:
			liste.append((pkg.name, pkg.version, pkg.download_size))
		return liste

	@dbus.service.method('org.manjaro.pamac', '', 's', async_callbacks=('success', 'nosuccess'))
	def Interrupt(self, success, nosuccess):
		def interrupt():
			self.error = ''
			#try:
			#	self.t.interrupt()
			#except pyalpm.error as e:
			#	self.error += ' --> '+str(e)+'\n'
			try:
				self.t.release()
			#except pyalpm.error as e:
				#self.error += ' --> '+str(e)+'\n'
			except:
				pass
			#finally:
				#if self.error:
					#self.EmitTransactionError(self.error)
		self.task.terminate()
		interrupt()
		success('')

	@dbus.service.method('org.manjaro.pamac', '', 's', sender_keyword='sender', connection_keyword='connexion', async_callbacks=('success', 'nosuccess'))
	def Commit(self, success, nosuccess, sender=None, connexion=None):
		def commit():
			self.error = ''
			try:
				self.t.commit()
			except pyalpm.error as e:
				#error = traceback.format_exc()
				self.error += ' --> '+str(e)+'\n'
			#except dbus.exceptions.DBusException:
				#pass
			finally:
				self.CheckUpdates()
				if self.error:
					self.EmitTransactionError(self.error)
				else:
					self.EmitTransactionDone(_('Transaction successfully finished'))
		try:
			authorized = self.policykit_test(sender,connexion,'org.manjaro.pamac.commit')
		except dbus.exceptions.DBusException as e:
			self.EmitTransactionError(_('Authentication failed'))
			success('')
		else:
			if authorized:
				self.task = Process(target=commit)
				self.task.start()
			else :
				self.t.release()
				self.EmitTransactionError(_('Authentication failed'))
			success('')

	@dbus.service.signal('org.manjaro.pamac')
	def EmitTransactionDone(self, message):
		pass

	@dbus.service.signal('org.manjaro.pamac')
	def EmitTransactionError(self, message):
		pass

	@dbus.service.method('org.manjaro.pamac', '', 's')#, sender_keyword='sender', connection_keyword='connexion')
	def Release(self):#, sender=None, connexion=None):
		self.error = ''
		#if self.policykit_test(sender,connexion,'org.manjaro.pamac.init_release'):
		try:
			self.t.release()
		except pyalpm.error as e:
			self.error += ' --> '+str(e)+'\n'
		finally:
			return self.error
		#else :
		#	return _('Authentication failed')

	@dbus.service.method('org.manjaro.pamac')
	def StopDaemon(self):
		try:
			self.t.release()
		except:
			pass
		mainloop.quit()

GObject.threads_init()
DBusGMainLoop(set_as_default=True)
myservice = PamacDBusService()
mainloop = GObject.MainLoop()
mainloop.run()
