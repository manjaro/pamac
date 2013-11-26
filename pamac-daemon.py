#! /usr/bin/python3
# -*- coding:utf-8 -*-

# pamac - A Python implementation of alpm
# Copyright (C) 2013 Guillaume Benoit <guillaume@manjaro.org>
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GObject
import re

import pyalpm
from multiprocessing import Process
from pamac import config, common, aur

# i18n
import gettext
gettext.bindtextdomain('pamac', '/usr/share/locale')
gettext.textdomain('pamac')
_ = gettext.gettext

class PamacDBusService(dbus.service.Object):
	def __init__(self):
		bus = dbus.SystemBus()
		bus_name = dbus.service.BusName('org.manjaro.pamac', bus)
		dbus.service.Object.__init__(self, bus_name, '/org/manjaro/pamac')
		self.t = None
		self.task = None
		self.error = ''
		self.warning = ''
		self.providers = []
		self.previous_action = ''
		self.previous_action_long = ''
		self.previous_icon = ''
		self.previous_target = ''
		self.previous_percent = 0
		self.total_size = 0
		self.already_transferred = 0
		self.handle = config.handle()
		self.local_packages = set()
		self.localdb = None
		self.syncdbs = None
		self.get_handle()

	def get_handle(self):
		print('daemon get handle')
		self.handle = config.handle()
		self.localdb = self.handle.get_localdb()
		self.syncdbs = self.handle.get_syncdbs()
		self.handle.dlcb = self.cb_dl
		self.handle.totaldlcb = self.totaldlcb
		self.handle.eventcb = self.cb_event
		self.handle.questioncb = self.cb_question
		self.handle.progresscb = self.cb_progress
		self.handle.logcb = self.cb_log

	def get_local_packages(self):
		self.local_packages = set()
		sync_pkg = None
		for pkg in self.localdb.pkgcache:
			for db in self.syncdbs:
				sync_pkg = db.get_pkg(pkg.name)
				if sync_pkg:
					break
			if not sync_pkg:
				self.local_packages.add(pkg.name)

	def check_finished_commit(self):
		if self.task.is_alive():
			return True
		else:
			self.get_handle()
			return False

	@dbus.service.signal('org.manjaro.pamac')
	def EmitAction(self, action):
		pass

	@dbus.service.signal('org.manjaro.pamac')
	def EmitActionLong(self, action):
		pass

	@dbus.service.signal('org.manjaro.pamac')
	def EmitNeedDetails(self, need):
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

	@dbus.service.signal('org.manjaro.pamac')
	def EmitLogError(self, message):
		pass

	@dbus.service.signal('org.manjaro.pamac')
	def EmitLogWarning(self, message):
		pass

	@dbus.service.signal('org.manjaro.pamac', signature = '(ba(ssssu))')
	def EmitAvailableUpdates(self, updates):
		pass

	@dbus.service.signal('org.manjaro.pamac')
	def EmitDownloadStart(self, message):
		pass

	@dbus.service.signal('org.manjaro.pamac')
	def EmitTransactionStart(self, message):
		pass

	@dbus.service.signal('org.manjaro.pamac')
	def EmitTransactionDone(self, message):
		pass

	@dbus.service.signal('org.manjaro.pamac')
	def EmitTransactionError(self, message):
		pass

	def cb_event(self, event, tupel):
		action = self.previous_action
		action_long = self.previous_action_long
		icon = self.previous_icon
		if event == 'ALPM_EVENT_CHECKDEPS_START':
			action = _('Checking dependencies')+'...'
			action_long = action+'\n'
			icon = '/usr/share/pamac/icons/24x24/status/package-search.png'
		elif event == 'ALPM_EVENT_CHECKDEPS_DONE':
			if self.warning:
				self.EmitLogWarning(self.warning)
				self.warning = ''
		elif event == 'ALPM_EVENT_FILECONFLICTS_START':
			action = _('Checking file conflicts')+'...'
			action_long = action+'\n'
			icon = '/usr/share/pamac/icons/24x24/status/package-search.png'
		elif event == 'ALPM_EVENT_FILECONFLICTS_DONE':
			pass
		elif event == 'ALPM_EVENT_RESOLVEDEPS_START':
			action = _('Resolving dependencies')+'...'
			action_long = action+'\n'
			icon = '/usr/share/pamac/icons/24x24/status/package-setup.png'
		elif event == 'ALPM_EVENT_RESOLVEDEPS_DONE':
			if self.warning:
				self.EmitLogWarning(self.warning)
				self.warning = ''
		elif event == 'ALPM_EVENT_INTERCONFLICTS_START':
			action = _('Checking inter conflicts')+'...'
			action_long = action+'\n'
			icon = '/usr/share/pamac/icons/24x24/status/package-search.png'
		elif event == 'ALPM_EVENT_INTERCONFLICTS_DONE':
			if self.warning:
				self.EmitLogWarning(self.warning)
				self.warning = ''
		elif event == 'ALPM_EVENT_ADD_START':
			string = _('Installing {pkgname}').format(pkgname = tupel[0].name)
			action = string+'...'
			action_long = '{} ({})...\n'.format(string, tupel[0].version)
			icon = '/usr/share/pamac/icons/24x24/status/package-add.png'
		elif event == 'ALPM_EVENT_ADD_DONE':
			formatted_event = 'Installed {pkgname} ({pkgversion})'.format(pkgname = tupel[0].name, pkgversion = tupel[0].version)
			common.write_log_file(formatted_event)
		elif event == 'ALPM_EVENT_REMOVE_START':
			string = _('Removing {pkgname}').format(pkgname = tupel[0].name)
			action = string+'...'
			action_long = '{} ({})...\n'.format(string, tupel[0].version)
			icon = '/usr/share/pamac/icons/24x24/status/package-delete.png'
		elif event == 'ALPM_EVENT_REMOVE_DONE':
			formatted_event = 'Removed {pkgname} ({pkgversion})'.format(pkgname = tupel[0].name, pkgversion = tupel[0].version)
			common.write_log_file(formatted_event)
		elif event == 'ALPM_EVENT_UPGRADE_START':
			string = _('Upgrading {pkgname}').format(pkgname = tupel[1].name)
			action = string+'...'
			action_long = '{} ({} => {})...\n'.format(string, tupel[1].version, tupel[0].version)
			icon = '/usr/share/pamac/icons/24x24/status/package-update.png'
		elif event == 'ALPM_EVENT_UPGRADE_DONE':
			formatted_event = 'Upgraded {pkgname} ({oldversion} -> {newversion})'.format(pkgname = tupel[1].name, oldversion = tupel[1].version, newversion = tupel[0].version)
			common.write_log_file(formatted_event)
		elif event == 'ALPM_EVENT_DOWNGRADE_START':
			string = _('Downgrading {pkgname}').format(pkgname = tupel[1].name)
			action = string+'...'
			action_long = '{} ({} => {})...\n'.format(string, tupel[1].version, tupel[0].version)
			icon = '/usr/share/pamac/icons/24x24/status/package-add.png'
		elif event == 'ALPM_EVENT_DOWNGRADE_DONE':
			formatted_event = 'Downgraded {pkgname} ({oldversion} -> {newversion})'.format(pkgname = tupel[1].name, oldversion = tupel[1].version, newversion = tupel[0].version)
			common.write_log_file(formatted_event)
		elif event == 'ALPM_EVENT_REINSTALL_START':
			string = _('Reinstalling {pkgname}').format(pkgname = tupel[0].name)
			action = string+'...'
			action_long = '{} ({})...\n'.format(string, tupel[0].version)
			icon = '/usr/share/pamac/icons/24x24/status/package-add.png'
		elif event == 'ALPM_EVENT_REINSTALL_DONE':
			formatted_event = 'Reinstalled {pkgname} ({pkgversion})'.format(pkgname = tupel[0].name, pkgversion = tupel[0].version)
			common.write_log_file(formatted_event)
		elif event == 'ALPM_EVENT_INTEGRITY_START':
			action = _('Checking integrity')+'...'
			action_long = action+'\n'
			icon = '/usr/share/pamac/icons/24x24/status/package-search.png'
			self.already_transferred = 0
		elif event == 'ALPM_EVENT_INTEGRITY_DONE':
			pass
		elif event == 'ALPM_EVENT_LOAD_START':
			action = _('Loading packages files')+'...'
			action_long = action+'\n'
			icon = '/usr/share/pamac/icons/24x24/status/package-search.png'
		elif event == 'ALPM_EVENT_LOAD_DONE':
			pass
		elif event == 'ALPM_EVENT_DELTA_INTEGRITY_START':
			action = _('Checking delta integrity')+'...'
			action_long = action+'\n'
			icon = '/usr/share/pamac/icons/24x24/status/package-search.png'
		elif event == 'ALPM_EVENT_DELTA_INTEGRITY_DONE':
			pass
		elif event == 'ALPM_EVENT_DELTA_PATCHES_START':
			action = _('Applying deltas')+'...'
			action_long = action+'\n'
			icon = '/usr/share/pamac/icons/24x24/status/package-setup.png'
		elif event == 'ALPM_EVENT_DELTA_PATCHES_DONE':
			pass
		elif event == 'ALPM_EVENT_DELTA_PATCH_START':
			action = _('Generating {} with {}').format(tupel[0], tupel[1])+'...'
			action_long = action+'\n'
			icon = '/usr/share/pamac/icons/24x24/status/package-setup.png'
		elif event == 'ALPM_EVENT_DELTA_PATCH_DONE':
			action = _('Generation succeeded!')
			action_long = action+'\n'
		elif event == 'ALPM_EVENT_DELTA_PATCH_FAILED':
			action = _('Generation failed.')
			action_long = action+'\n'
		elif event == 'ALPM_EVENT_SCRIPTLET_INFO':
			action =_('Configuring {pkgname}').format(pkgname = self.previous_target)+'...'
			action_long = tupel[0]
			icon = '/usr/share/pamac/icons/24x24/status/package-setup.png'
			self.EmitNeedDetails(True)
		elif event == 'ALPM_EVENT_RETRIEVE_START':
			action = _('Downloading')+'...'
			action_long = action+'\n'
			icon = '/usr/share/pamac/icons/24x24/status/package-download.png'
			self.EmitDownloadStart('')
		elif event == 'ALPM_EVENT_DISKSPACE_START':
			action = _('Checking available disk space')+'...'
			action_long = action+'\n'
			icon = '/usr/share/pamac/icons/24x24/status/package-search.png'
		elif event == 'ALPM_EVENT_OPTDEP_REQUIRED':
			print('Optionnal deps exist')
		elif event == 'ALPM_EVENT_DATABASE_MISSING':
			#action =_('Database file for {} does not exist').format(tupel[0])+'...'
			#action_long = action
			pass
		elif event == 'ALPM_EVENT_KEYRING_START':
			action = _('Checking keyring')+'...'
			action_long = action+'\n'
			icon = '/usr/share/pamac/icons/24x24/status/package-search.png'
		elif event == 'ALPM_EVENT_KEYRING_DONE':
			pass
		elif event == 'ALPM_EVENT_KEY_DOWNLOAD_START':
			action = _('Downloading required keys')+'...'
			action_long = action+'\n'
		elif event == 'ALPM_EVENT_KEY_DOWNLOAD_DONE':
			pass
		if action != self.previous_action:
			self.previous_action = action
			self.EmitAction(action)
		if action_long != self.previous_action_long:
			self.previous_action_long != action_long
			self.EmitActionLong(action_long)
		if icon != self.previous_icon:
			self.previous_icon = icon
			self.EmitIcon(icon)
		print(event)

	def cb_question(self, event, data_tupel, extra_data):
		if event == 'ALPM_QUESTION_INSTALL_IGNOREPKG':
			return 0 # Do not install package in IgnorePkg/IgnoreGroup
		if event == 'ALPM_QUESTION_REPLACE_PKG':
			self.warning += _('{pkgname1} will be replaced by {pkgname2}').format(pkgname1 = data_tupel[0].name, pkgname2 = data_tupel[1].name)+'\n'
			return 1 # Auto-remove conflicts in case of replaces
		if event == 'ALPM_QUESTION_CONFLICT_PKG':
			self.warning += _('{pkgname1} conflicts with {pkgname2}').format(pkgname1 = data_tupel[0], pkgname2 = data_tupel[1])+'\n'
			return 1 # Auto-remove conflicts
		if event == 'ALPM_QUESTION_CORRUPTED_PKG':
			return 1 # Auto-remove corrupted pkgs in cache
		if event == 'ALPM_QUESTION_REMOVE_PKGS':
			return 1 # Do not upgrade packages which have unresolvable dependencies
		if event == 'ALPM_QUESTION_SELECT_PROVIDER':
			## In this case we populate providers with different choices
			## the client will have to release transaction and re-init one 
			## with the chosen package added to it
			self.providers.append(([pkg.name for pkg in data_tupel[0]], data_tupel[1]))
			return 0 # return the first choice, this is not important because the transaction will be released
		if event == 'ALPM_QUESTION_IMPORT_KEY':
			## data_tupel = (revoked(int), length(int), pubkey_algo(string), fingerprint(string), uid(string), created_time(int))
			if data_tupel[0] is 0: # not revoked
				return 1 # Auto get not revoked key
			if data_tupel[0] is 1: # revoked
				return 0 # Do not get revoked key

	def cb_log(self, level, line):
		_logmask = pyalpm.LOG_ERROR | pyalpm.LOG_WARNING
		if not (level & _logmask):
			return
		if level & pyalpm.LOG_ERROR:
			_error = "ERROR: "+line
			self.EmitActionLong(_error)
			self.EmitNeedDetails(True)
			print(line)
		elif level & pyalpm.LOG_WARNING:
			self.warning += line
			_warning = "WARNING: "+line
			self.EmitActionLong(_warning)
		elif level & pyalpm.LOG_DEBUG:
			line = "DEBUG: " + line
			print(line)
		elif level & pyalpm.LOG_FUNCTION:
			line = "FUNC: " + line
			print(line)

	def totaldlcb(self, _total_size):
		self.total_size = _total_size

	def cb_dl(self, _target, _transferred, _total):
		if _target.endswith('.db'):
			action = _('Refreshing {repo}').format(repo = _target.replace('.db', ''))+'...'
			action_long = ''
			icon = '/usr/share/pamac/icons/24x24/status/refresh-cache.png'
		else:
			action = _('Downloading {pkgname}').format(pkgname = _target.replace('.pkg.tar.xz', ''))+'...'
			action_long = action+'\n'
			icon = '/usr/share/pamac/icons/24x24/status/package-download.png'
		if self.total_size > 0:
			percent = round((_transferred+self.already_transferred)/self.total_size, 2)
			if _transferred+self.already_transferred <= self.total_size:
				target = '{transferred}/{size}'.format(transferred = common.format_size(_transferred+self.already_transferred), size = common.format_size(self.total_size))
			else:
				target = ''
		else:
			percent = round(_transferred/_total, 2)
			target = ''
		if action != self.previous_action:
			self.previous_action = action
			self.EmitAction(action)
		if action_long != self.previous_action_long:
			self.previous_action_long = action_long
			self.EmitActionLong(action_long)
		if icon != self.previous_icon:
			self.previous_icon = icon
			self.EmitIcon(icon)
		if target != self.previous_target:
			self.previous_target = target
			self.EmitTarget(target)
		if percent != self.previous_percent:
			self.previous_percent = percent
			self.EmitPercent(percent)
		elif _transferred == _total:
			self.already_transferred += _total

	def cb_progress(self, event, target, _percent, n, i):
		if event in ('ALPM_PROGRESS_ADD_START', 'ALPM_PROGRESS_UPGRADE_START', 'ALPM_PROGRESS_DOWNGRADE_START', 'ALPM_PROGRESS_REINSTALL_START', 'ALPM_PROGRESS_REMOVE_START'):
			percent = round(((i-1)/n)+(_percent/(100*n)), 2)
			self.EmitTransactionStart('')
		else:
			percent = round(_percent/100, 2)
		if target != self.previous_target:
			self.previous_target = target
		if percent != self.previous_percent:
			self.EmitTarget('{}/{}'.format(str(i), str(n)))
			self.previous_percent = percent
			self.EmitPercent(percent)

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

	@dbus.service.method('org.manjaro.pamac', 'si', 's')
	def SetPkgReason(self, pkgname, reason):
		error = ''
		try:
			pkg = self.localdb.get_pkg(pkgname)
			if pkg:
				self.handle.set_pkgreason(pkg, reason)
		except Exception as e:
			error = str(e)
		return error

	@dbus.service.method('org.manjaro.pamac', '', 's', async_callbacks=('success', 'nosuccess'))
	def CheckUpdates(self, success, nosuccess):
		success('')
		syncfirst = False
		updates = []
		_ignorepkgs = set()
		self.get_handle()
		self.get_local_packages()
		for group in self.handle.ignoregrps:
			db = self.localdb
			grp = db.read_grp(group)
			if grp:
				name, pkg_list = grp
				for pkg in pkg_list:
					_ignorepkgs.add(pkg.name)
		for name in self.handle.ignorepkgs:
			pkg = self.localdb.get_pkg(name)
			if pkg:
				_ignorepkgs.add(pkg.name)
		if config.syncfirst:
			for name in config.syncfirst:
				pkg = self.localdb.get_pkg(name)
				if pkg:
					candidate = pyalpm.sync_newversion(pkg, self.syncdbs)
					if candidate:
						syncfirst = True
						updates.append((candidate.name, candidate.version, candidate.db.name, '', candidate.download_size))
		if not updates:
			for pkg in self.localdb.pkgcache:
				if not pkg.name in _ignorepkgs:
					candidate = pyalpm.sync_newversion(pkg, self.syncdbs)
					if candidate:
						updates.append((candidate.name, candidate.version, candidate.db.name, '', candidate.download_size))
						self.local_packages.discard(pkg.name)
			if self.local_packages:
				aur_pkgs = aur.multiinfo(self.local_packages)
				for aur_pkg in aur_pkgs:
					comp = pyalpm.vercmp(aur_pkg.version, self.localdb.get_pkg(aur_pkg.name).version)
					if comp == 1:
						updates.append((aur_pkg.name, aur_pkg.version, aur_pkg.db.name, aur_pkg.tarpath, aur_pkg.download_size))
		self.EmitAvailableUpdates((syncfirst, updates))

	@dbus.service.method('org.manjaro.pamac', 'b', 's', async_callbacks=('success', 'nosuccess'))
	def Refresh(self, force_update, success, nosuccess):
		def refresh():
			self.target = ''
			self.percent = 0
			error = ''
			for db in self.syncdbs:
				try:
					self.t = self.handle.init_transaction()
					db.update(force = bool(force_update))
					self.t.release()
				except pyalpm.error as e:
					error += str(e)
					break
			if error:
				self.EmitTransactionError(error)
			else:
				self.EmitTransactionDone('')
		self.task = Process(target=refresh)
		self.task.start()
		GObject.timeout_add(100, self.check_finished_commit)
		success('')

	@dbus.service.method('org.manjaro.pamac', 'a{sb}', 's')
	def Init(self, options):
		error = ''
		try:
			self.t = self.handle.init_transaction(**options)
			print('Init:',self.t.flags)
		except pyalpm.error as e:
			error = str(e)
		finally:
			return error

	@dbus.service.method('org.manjaro.pamac', '', 's')
	def Sysupgrade(self):
		error = ''
		try:
			self.t.sysupgrade(downgrade=False)
		except pyalpm.error as e:
			error = ' --> '+str(e)+'\n'
			self.t.release()
		finally:
			return error

	@dbus.service.method('org.manjaro.pamac', 's', 's')
	def Remove(self, pkgname):
		error = ''
		try:
			pkg = self.localdb.get_pkg(pkgname)
			if pkg is not None:
				self.t.remove_pkg(pkg)
		except pyalpm.error as e:
			error = ' --> '+str(e)+'\n'
		finally:
			return error

	@dbus.service.method('org.manjaro.pamac', 's', 's')
	def Add(self, pkgname):
		error = ''
		try:
			for db in self.syncdbs:
				pkg = db.get_pkg(pkgname)
				if pkg:
					self.t.add_pkg(pkg)
					break
		except pyalpm.error as e:
			error += ' --> '+str(e)+'\n'
		finally:
			return error

	@dbus.service.method('org.manjaro.pamac', 's', 's')
	def Load(self, tarball_path):
		error = ''
		try:
			pkg = self.handle.load_pkg(tarball_path)
			if pkg:
				self.t.add_pkg(pkg)
		except pyalpm.error:
			error = _('{pkgname} is not a valid path or package name').format(pkgname = tarball_path)
		finally:
			return error

	def check_extra_modules(self):
		to_add = set(pkg.name for pkg in self.t.to_add)
		to_remove = set(pkg.name for pkg in self.t.to_remove)
		to_check = [pkg for pkg in self.t.to_add]
		already_checked = set(pkg.name for pkg in to_check)
		depends = [to_check]
		# get installed kernels and modules
		pkgs = self.localdb.search('linux')
		installed_kernels = set()
		installed_modules =  set()
		for pkg in pkgs:
			match = re.match("(linux[0-9]{2,3})(.*)", pkg.name)
			if match:
				installed_kernels.add(match.group(1))
				if match.group(2):
					installed_modules.add(match.group(2))
		for pkg in self.t.to_add:
			match = re.match("(linux[0-9]{2,3})(.*)", pkg.name)
			if match:
				installed_kernels.add(match.group(1))
				if match.group(2):
					installed_modules.add(match.group(2))
		# check in to_remove if there is a kernel and if so, auto-remove the corresponding modules 
		for pkg in self.t.to_remove:
			match = re.match("(linux[0-9]{2,3})(.*)", pkg.name)
			if match:
				if not match.group(2):
					installed_kernels.discard(match.group(1))
					for module in installed_modules:
						pkgname = match.group(1)+module
						if not pkgname in to_remove:
							to_remove.add(pkgname)
							_pkg = self.localdb.get_pkg(pkgname)
							if _pkg:
								self.t.remove_pkg(_pkg)
		# start loops to check pkgs
		i = 0
		while depends[i]:
			# add a empty list for new pkgs to check next loop
			depends.append([])
			# start to check one pkg
			for pkg in depends[i]:
				# check if the current pkg is a kernel and if so, check if a module is required to install
				match = re.match("(linux[0-9]{2,3})(.*)", pkg.name)
				if match:
					if not match.group(2): # match pkg is a kernel
						for module in installed_modules:
							pkgname = match.group(1) + module
							if not self.localdb.get_pkg(pkgname):
								for db in self.syncdbs:
									_pkg = db.get_pkg(pkgname)
									if _pkg:
										if not _pkg.name in already_checked:
											depends[i+1].append(_pkg)
											already_checked.add(_pkg.name)
										if not _pkg.name in to_add | to_remove:
											to_add.add(_pkg.name)
											self.t.add_pkg(_pkg)
										break
				# check if the current pkg is a kernel module and if so, install it for all installed kernels
				match = re.match("(linux[0-9]{2,3})(.*-modules)", pkg.name)
				if match:
					for kernel in installed_kernels:
						pkgname = kernel + match.group(2)
						if not self.localdb.get_pkg(pkgname):
							for db in self.syncdbs:
								_pkg = db.get_pkg(pkgname)
								if _pkg:
									if not _pkg.name in already_checked:
										depends[i+1].append(_pkg)
										already_checked.add(_pkg.name)
									if not _pkg.name in to_add | to_remove:
											to_add.add(_pkg.name)
											self.t.add_pkg(_pkg)
									break
				for depend in pkg.depends:
					found_depend = pyalpm.find_satisfier(self.localdb.pkgcache, depend)
					if not found_depend:
						for db in self.syncdbs:
							found_depend = pyalpm.find_satisfier(db.pkgcache, depend)
							if found_depend:
								break
					if found_depend:
						# add the dep in list to check its deps in next loop 
						if not found_depend.name in already_checked:
							depends[i+1].append(found_depend)
							already_checked.add(found_depend.name)
			i += 1
			# end of the loop

	@dbus.service.method('org.manjaro.pamac', '', 'a(ass)')
	def Prepare(self):
		error = ''
		self.providers.clear()
		self.check_extra_modules()
		try:
			self.t.prepare()
		except pyalpm.error as e:
			error = str(e)
			self.t.release()
		else:
			for pkg in self.t.to_remove:
				if pkg.name in config.holdpkg:
					error = _('The transaction cannot be performed because it needs to remove {pkgname1} which is a locked package').format(pkgname1 = pkg.name)
					self.t.release()
					break
		finally:
			try:
				summ = len(self.t.to_add) + len(self.t.to_remove)
			except pyalpm.error:
				return [((), '')]
			if summ == 0:
				self.t.release()
				return [((), _('Nothing to do'))]
			elif error:
				return [((), error)]
			elif self.providers:
				return self.providers
			else:
				return [((), '')]

	@dbus.service.method('org.manjaro.pamac', '', 'a(ss)')
	def To_Remove(self):
		_list = []
		try:
			for pkg in self.t.to_remove:
				_list.append((pkg.name, pkg.version))
		except:
			pass
		return _list

	@dbus.service.method('org.manjaro.pamac', '', 'a(ssi)')
	def To_Add(self):
		_list = []
		try:
			for pkg in self.t.to_add:
				_list.append((pkg.name, pkg.version, pkg.download_size))
		except:
			pass
		return _list

	@dbus.service.method('org.manjaro.pamac', '', 's', async_callbacks=('success', 'nosuccess'))
	def Interrupt(self, success, nosuccess):
		def interrupt():
			try:
				self.t.interrupt()
			except:
				pass
			try:
				self.t.release()
			except:
				pass
			finally:
				common.rm_lock_file()
		self.task.terminate()
		interrupt()
		success('')

	@dbus.service.method('org.manjaro.pamac', '', 's', sender_keyword='sender', connection_keyword='connexion', async_callbacks=('success', 'nosuccess'))
	def Commit(self, success, nosuccess, sender=None, connexion=None):
		def commit():
			error = ''
			try:
				self.t.commit()
			except pyalpm.error as e:
				error = str(e)
			#except dbus.exceptions.DBusException:
				#pass
			finally:
				self.t.release()
				if self.warning:
					self.EmitLogWarning(self.warning)
					self.warning = ''
				if error:
					self.EmitTransactionError(error)
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
				GObject.timeout_add(100, self.check_finished_commit)
			else :
				self.t.release()
				self.EmitTransactionError(_('Authentication failed'))
			success('')

	@dbus.service.method('org.manjaro.pamac', '', '')
	def Release(self):
		try:
			self.t.release()
		except:
			pass

	@dbus.service.method('org.manjaro.pamac')
	def StopDaemon(self):
		try:
			self.t.release()
		except:
			pass
		common.rm_pid_file()
		mainloop.quit()

GObject.threads_init()
DBusGMainLoop(set_as_default = True)
myservice = PamacDBusService()
mainloop = GObject.MainLoop()
mainloop.run()
