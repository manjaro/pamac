#! /usr/bin/python3
# -*- coding:utf-8 -*-

import pyalpm
from gi.repository import Gtk

from pamac import config, common

# i18n
import gettext
import locale
locale.bindtextdomain('pamac', '/usr/share/locale')
gettext.bindtextdomain('pamac', '/usr/share/locale')
gettext.textdomain('pamac')
_ = gettext.gettext

interface = Gtk.Builder()
interface.set_translation_domain('pamac')

interface.add_from_file('/usr/share/pamac/gui/dialogs.ui')
ErrorDialog = interface.get_object('ErrorDialog')
WarningDialog = interface.get_object('WarningDialog')
InfoDialog = interface.get_object('InfoDialog')
#QuestionDialog = interface.get_object('QuestionDialog')
ConfDialog = interface.get_object('ConfDialog')
transaction_sum = interface.get_object('transaction_sum')
sum_top_label = interface.get_object('sum_top_label')
sum_bottom_label = interface.get_object('sum_bottom_label')
ChooseDialog = interface.get_object('ChooseDialog')
choose_list = interface.get_object('choose_list')
choose_label = interface.get_object('choose_label')
choose_renderertoggle = interface.get_object('choose_renderertoggle')
ProgressWindow = interface.get_object('ProgressWindow')
progress_bar = interface.get_object('progressbar2')
progress_label = interface.get_object('progresslabel2')
action_icon = interface.get_object('action_icon')
ProgressCancelButton = interface.get_object('ProgressCancelButton')
ProgressCloseButton = interface.get_object('ProgressCloseButton')
progress_textview = interface.get_object('progress_textview')
progress_expander = interface.get_object('progress_expander')

progress_buffer = progress_textview.get_buffer()
choose_only_one = False

def choose_provides(data):
	global choose_only_one
	choose_only_one = True
	providers = data[0]
	dep_to_provide = data[1]
	choose_label.set_markup(_('<b>{pkgname} is provided by {number} packages.\nPlease choose the one you want to install:</b>').format(pkgname = dep_to_provide, number = str(len(providers))))
	choose_list.clear()
	choose_renderertoggle.set_radio(True)
	for pkg in providers:
		choose_list.append([False, pkg.name])
	ChooseDialog.run()
	index = 0
	if to_provide:
		for pkg in providers:
			if to_provide[0] == pkg.name:
				index = providers.index(pkg)
	return index

def on_choose_renderertoggle_toggled(widget, line):
	global choose_only_one
	choose_list[line][0] = not choose_list[line][0]
	if choose_only_one:
		for row in choose_list:
			if not row[1] == choose_list[line][1]:
				row[0] = False

def on_ChooseButton_clicked(*arg):
	ChooseDialog.hide()
	line = 0
	to_provide.clear()
	while line <  len(choose_list):
		if choose_list[line][0] is True:
			to_provide.append(choose_list[line][1])
		line += 1

def on_progress_textview_size_allocate(*arg):
	#auto-scrolling method
	adj = progress_textview.get_vadjustment()
	adj.set_value(adj.get_upper() - adj.get_page_size())

#~ def policykit_test(sender, connexion, action):
	#~ bus = dbus.SystemBus()
	#~ proxy_dbus = connexion.get_object('org.freedesktop.DBus','/org/freedesktop/DBus/Bus', False)
	#~ dbus_info = dbus.Interface(proxy_dbus,'org.freedesktop.DBus')
	#~ sender_pid = dbus_info.GetConnectionUnixProcessID(sender)
	#~ proxy_policykit = bus.get_object('org.freedesktop.PolicyKit1','/org/freedesktop/PolicyKit1/Authority',False)
	#~ policykit_authority = dbus.Interface(proxy_policykit,'org.freedesktop.PolicyKit1.Authority')
#~ 
	#~ Subject = ('unix-process', {'pid': dbus.UInt32(sender_pid, variant_level=1),
					#~ 'start-time': dbus.UInt64(0, variant_level=1)})
	#~ (is_authorized,is_challenge,details) = policykit_authority.CheckAuthorization(Subject, action, {'': ''}, dbus.UInt32(1), '')
	#~ return is_authorized

#~ def sort_pkgs_list(self, pkgs_list):
	#~ result = []
	#~ names_list = sorted([pkg.name for pkg in pkgs_list])
	#~ for name in names_list:
		#~ for pkg in pkgs_list:
			#~ if name == pkg.name:
				#~ result.append(pkg)
	#~ return result

def remove_pkg_from_list(pkg, pkgs_list):
	if pkgs_list:
		for _pkg in pkgs_list:
			if (pkg.name == _pkg.name and pkg.version == _pkg.version and pkg.arch == _pkg.arch):
				target = _pkg
		pkgs_list.remove(_pkg)

def pkg_in_list(pkg, pkgs_list):
	result = False
	if pkgs_list:
		for _pkg in pkgs_list:
			if (pkg.name == _pkg.name and pkg.version == _pkg.version and pkg.arch == _pkg.arch):
				result = True
	return result

class Transaction():
	def __init__(self):
		self.t = None
		self.to_remove = []
		self.to_add = []
		self.to_load = []
		self.to_provide = []
		self.error = ''
		self.warning = ''
		self.previous_action = ''
		self.previous_action_long = ''
		self.previous_icon = ''
		self.previous_target = ''
		self.previous_percent = 0
		self.total_size = 0
		self.already_transferred = 0
		self.handle = config.handle()
		self.syncdbs = self.handle.get_syncdbs()
		self.localdb = self.handle.get_localdb()
		self.handle.dlcb = self.cb_dl
		self.handle.totaldlcb = self.totaldlcb
		self.handle.eventcb = self.cb_event
		self.handle.questioncb = self.cb_question
		self.handle.progresscb = self.cb_progress
		self.handle.logcb = self.cb_log

	def update_dbs(self):
		self.handle = config.handle()
		self.syncdbs = self.handle.get_syncdbs()
		self.localdb = self.handle.get_localdb()
		self.handle.dlcb = self.cb_dl
		self.handle.totaldlcb = self.totaldlcb
		self.handle.eventcb = self.cb_event
		self.handle.questioncb = self.cb_question
		self.handle.progresscb = self.cb_progress
		self.handle.logcb = self.cb_log

	def get_localpkg(self, name):
		return self.localdb.get_pkg(name)

	def get_syncpkg(self, name):
		for repo in self.syncdbs:
			pkg = repo.get_pkg(name)
			if pkg:
				return pkg

	def cb_event(self, event, tupel):
		global progress_buffer
		action = self.previous_action
		action_long = self.previous_action_long
		icon = self.previous_icon
		if event == 'ALPM_EVENT_CHECKDEPS_START':
			action = _('Checking dependencies')+'...'
			action_long = action+'\n'
			icon = '/usr/share/pamac/icons/24x24/status/package-search.png'
		elif event == 'ALPM_EVENT_CHECKDEPS_DONE':
			if self.warning:
				self.handle_warning(self.warning)
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
			pass
		elif event == 'ALPM_EVENT_INTERCONFLICTS_START':
			action = _('Checking inter conflicts')+'...'
			action_long = action+'\n'
			icon = '/usr/share/pamac/icons/24x24/status/package-search.png'
		elif event == 'ALPM_EVENT_INTERCONFLICTS_DONE':
			if self.warning:
				self.handle_warning(self.warning)
				self.warning = ''
		elif event == 'ALPM_EVENT_ADD_START':
			string = _('Installing {pkgname}').format(pkgname = tupel[0].name)
			action = string+'...'
			action_long = '{} ({})\n'.format(string, tupel[0].version)
			icon = '/usr/share/pamac/icons/24x24/status/package-add.png'
			ProgressCancelButton.set_visible(False)
		elif event == 'ALPM_EVENT_ADD_DONE':
			formatted_event = 'Installed {pkgname} ({pkgversion})'.format(pkgname = tupel[0].name, pkgversion = tupel[0].version)
			common.write_log_file(formatted_event)
		elif event == 'ALPM_EVENT_REMOVE_START':
			string = _('Removing {pkgname}').format(pkgname = tupel[0].name)
			action = string+'...'
			action_long = '{} ({})\n'.format(string, tupel[0].version)
			icon = '/usr/share/pamac/icons/24x24/status/package-delete.png'
			ProgressCancelButton.set_visible(False)
		elif event == 'ALPM_EVENT_REMOVE_DONE':
			formatted_event = 'Removed {pkgname} ({pkgversion})'.format(pkgname = tupel[0].name, pkgversion = tupel[0].version)
			common.write_log_file(formatted_event)
		elif event == 'ALPM_EVENT_UPGRADE_START':
			string = _('Upgrading {pkgname}').format(pkgname = tupel[1].name)
			action = string+'...'
			action_long = '{} ({} -> {})\n'.format(string, tupel[1].version, tupel[0].version)
			icon = '/usr/share/pamac/icons/24x24/status/package-update.png'
			ProgressCancelButton.set_visible(False)
		elif event == 'ALPM_EVENT_UPGRADE_DONE':
			formatted_event = 'Upgraded {pkgname} ({oldversion} -> {newversion})'.format(pkgname = tupel[1].name, oldversion = tupel[1].version, newversion = tupel[0].version)
			common.write_log_file(formatted_event)
		elif event == 'ALPM_EVENT_DOWNGRADE_START':
			string = _('Downgrading {pkgname}').format(pkgname = tupel[1].name)
			action = string+'...'
			action_long = '{} ({} -> {})'.format(string, tupel[1].version, tupel[0].version)
			icon = '/usr/share/pamac/icons/24x24/status/package-add.png'
			ProgressCancelButton.set_visible(False)
		elif event == 'ALPM_EVENT_DOWNGRADE_DONE':
			formatted_event = 'Downgraded {pkgname} ({oldversion} -> {newversion})'.format(pkgname = tupel[1].name, oldversion = tupel[1].version, newversion = tupel[0].version)
			common.write_log_file(formatted_event)
		elif event == 'ALPM_EVENT_REINSTALL_START':
			string = _('Reinstalling {pkgname}').format(pkgname = tupel[0].name)
			action = string+'...'
			action_long = '{} ({})'.format(string, tupel[0].version)
			icon = '/usr/share/pamac/icons/24x24/status/package-add.png'
			ProgressCancelButton.set_visible(False)
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
			progress_bar.pulse()
			progress_expander.set_expanded(True)
		elif event == 'ALPM_EVENT_RETRIEVE_START':
			# handled by download callback
			ProgressCancelButton.set_visible(True)
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
			ProgressCancelButton.set_visible(True)
		elif event == 'ALPM_EVENT_KEYRING_DONE':
			pass
		elif event == 'ALPM_EVENT_KEY_DOWNLOAD_START':
			action = _('Downloading required keys')+'...'
			action_long = action+'\n'
		elif event == 'ALPM_EVENT_KEY_DOWNLOAD_DONE':
			pass
		if action != self.previous_action:
			self.previous_action = action
			progress_label.set_text(action)
		if action_long != self.previous_action_long:
			self.previous_action_long != action_long
			end_iter = progress_buffer.get_end_iter()
			progress_buffer.insert(end_iter, action_long)
		if icon != self.previous_icon:
			self.previous_icon = icon
			action_icon.set_from_file(icon)
		while Gtk.events_pending():
			Gtk.main_iteration()
		print(event)

	def cb_question(self, event, data_tupel, extra_data):
		print('question', event, data_tupel, extra_data)
		if event == 'ALPM_QUESTION_INSTALL_IGNOREPKG':
			return 0 #Do not install package in IgnorePkg/IgnoreGroup
		if event == 'ALPM_QUESTION_REPLACE_PKG':
			self.warning += _('{pkgname1} will replace by {pkgname2}\n').format(pkgname1 = data_tupel[0].name, pkgname2 = data_tupel[1].name)
			return 1 #Auto-remove conflicts in case of replaces
		if event == 'ALPM_QUESTION_CONFLICT_PKG':
			self.warning += _('{pkgname1} conflicts with {pkgname2}\n').format(pkgname1 = data_tupel[0], pkgname2 = data_tupel[1])
			return 1 #Auto-remove conflicts
		if event == 'ALPM_QUESTION_CORRUPTED_PKG':
			return 1 #Auto-remove corrupted pkgs in cache
		if event == 'ALPM_QUESTION_REMOVE_PKGS':
			return 1 #Do not upgrade packages which have unresolvable dependencies
		if event == 'ALPM_QUESTION_SELECT_PROVIDER':
			return choose_provides(data_tupel)
		if event == 'ALPM_QUESTION_IMPORT_KEY':
			# data_tupel = (revoked(int), length(int), pubkey_algo(string), fingerprint(string), uid(string), created_time(int))
			if data_tupel[0] is 0: # not revoked
				return 1 #Auto import not revoked key
			if data_tupel[0] is 1: # revoked
				return 0 #Do not import revoked key

	def cb_log(self, level, line):
		global progress_buffer
		_logmask = pyalpm.LOG_ERROR | pyalpm.LOG_WARNING
		if not (level & _logmask):
			return
		if level & pyalpm.LOG_ERROR:
			self.error += line
			_error = "ERROR: "+line
			end_iter = progress_buffer.get_end_iter()
			progress_buffer.insert(end_iter, _error)
			progress_expander.set_expanded(True)
			while Gtk.events_pending():
				Gtk.main_iteration()
			print(line)
		elif level & pyalpm.LOG_WARNING:
			self.warning += line
			_warning = "WARNING: "+line
			end_iter = progress_buffer.get_end_iter()
			progress_buffer.insert(end_iter, _warning)
			while Gtk.events_pending():
				Gtk.main_iteration()
		elif level & pyalpm.LOG_DEBUG:
			line = "DEBUG: " + line
			print(line)
		elif level & pyalpm.LOG_FUNCTION:
			line = "FUNC: " + line
			print(line)

	def totaldlcb(self, _total_size):
		self.total_size = _total_size

	def cb_dl(self, _target, _transferred, _total):
		global progress_buffer
		if _target.endswith('.db'):
			action = _('Refreshing {repo}').format(repo = _target.rstrip('.db'))+'...'
			action_long = ''
			icon = '/usr/share/pamac/icons/24x24/status/refresh-cache.png'
		else:
			action = _('Downloading {pkgname}').format(pkgname = _target.rstrip('.pkg.tar.xz'))+'...'
			action_long = action+'\n'
			icon = '/usr/share/pamac/icons/24x24/status/package-download.png'
		if self.total_size > 0:
			percent = round((_transferred+self.already_transferred)/self.total_size, 2)
			#~ target = '{transferred}/{size}'.format(transferred = common.format_size(_transferred+self.already_transferred), size = common.format_size(self.total_size))
		else:
			percent = round(_transferred/_total, 2)
			#~ percent = 2.0
			#~ target = ''
		if action != self.previous_action:
			self.previous_action = action
			progress_label.set_text(action)
		if action_long != self.previous_action_long:
			self.previous_action_long = action_long
			end_iter = progress_buffer.get_end_iter()
			progress_buffer.insert(end_iter, action_long)
		if icon != self.previous_icon:
			self.previous_icon = icon
			action_icon.set_from_file(icon)
		#~ if target != self.previous_target:
			#~ self.previous_target = target
			#~ progress_bar.set_text(target)
		#~ if percent == 2.0:
			#~ progress_bar.pulse()
		elif percent != self.previous_percent:
			self.previous_percent = percent
			if 0 <= percent <= 1:
				progress_bar.set_fraction(percent)
			else:
				progress_bar.pulse()
		elif _transferred == _total:
			self.already_transferred += _total
		#~ if self.already_transferred == self.total_size:
			#~ progress_bar.set_text('')
		while Gtk.events_pending():
			Gtk.main_iteration()

	def cb_progress(self, event, target, _percent, n, i):
		if event in ('ALPM_PROGRESS_ADD_START', 'ALPM_PROGRESS_UPGRADE_START', 'ALPM_PROGRESS_DOWNGRADE_START', 'ALPM_PROGRESS_REINSTALL_START', 'ALPM_PROGRESS_REMOVE_START'):
			percent = round(((i-1)/n)+(_percent/(100*n)), 2)
		else:
			percent = round(_percent/100, 2)
		if target != self.previous_target:
			self.previous_target = target.format()
		if percent != self.previous_percent:
			progress_bar.set_text('{}/{}'.format(str(i), str(n)))
			self.previous_percent = percent
			if 0 <= percent <= 1:
				progress_bar.set_fraction(percent)
			else:
				progress_bar.pulse()
		while Gtk.events_pending():
			Gtk.main_iteration()

	def refresh(self, force_update):
		progress_label.set_text(_('Refreshing')+'...')
		action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/refresh-cache.png')
		progress_bar.set_text('')
		progress_bar.set_fraction(0)
		ProgressCloseButton.set_visible(False)
		ProgressCancelButton.set_visible(True)
		ProgressWindow.show()
		while Gtk.events_pending():
			Gtk.main_iteration()
		self.error = ''
		for db in self.syncdbs:
			try:
				self.t = self.handle.init_transaction()
				db.update(force = force_update)
				self.t.release()
			except pyalpm.error as e:
				self.release()
				self.error += str(e)+'\n'
				break
		self.update_dbs()
		ProgressWindow.hide()
		if self.error:
			self.handle_error(self.error)

	def get_updates(self):
		do_syncfirst = False
		list_first = set()
		_ignorepkgs = set()
		if self.handle:
			for group in self.handle.ignoregrps:
				db = self.handle.get_localdb()
				grp = db.read_grp(group)
				if grp:
					name, pkg_list = grp
					for pkg in pkg_list:
						_ignorepkgs.add(pkg.name)
			for name in self.handle.ignorepkgs:
				if self.get_localpkg(name):
					_ignorepkgs.add(name)
		if config.syncfirst:
			for name in config.syncfirst:
				if self.get_localpkg(name):
					candidate = pyalpm.sync_newversion(self.get_localpkg(name), self.syncdbs)
					if candidate:
						list_first.add(candidate)
			if list_first:
				do_syncfirst = True
				return do_syncfirst, list_first
		result = set()
		for pkg in self.localdb.pkgcache:
			candidate = pyalpm.sync_newversion(pkg, self.syncdbs)
			if candidate:
				if not candidate.name in _ignorepkgs:
					result.add(candidate)
		return do_syncfirst, result

	def init(self, **options):
		self.error = ''
		try:
			self.t = self.handle.init_transaction(**options)
		except pyalpm.error as e:
			self.error += str(e)+'\n'
		finally:
			if self.error:
				self.handle_error(self.error)
				return False
			else:
				return True

	def sysupgrade(self, force_downgrade):
		try:
			self.t.sysupgrade(downgrade = force_downgrade)
		except pyalpm.error as e:
			self.error += str(e)+'\n'
			self.t.release()
		finally:
			if self.error:
				self.handle_error(self.error)
				return False
			else:
				return True

	def remove(self, pkg):
		try:
			self.t.remove_pkg(pkg)
		except pyalpm.error as e:
			self.error += str(e)+'\n'
			self.t.release()
		finally:
			if self.error:
				self.handle_error(self.error)
				return False
			else:
				return True

	def add(self, pkg):
		try:
			self.t.add_pkg(pkg)
		except pyalpm.error as e:
			# skip duplicate target error
			if not 'pm_errno 25' in str(e):
				self.error += str(e)+'\n'
				self.t.release()
		finally:
			if self.error:
				self.handle_error(self.error)
				return False
			else:
				return True

	def load(self, tarball_path):
		try:
			pkg = self.handle.load_pkg(tarball_path)
			if pkg:
				self.t.add_pkg(pkg)
			else:
				self.error += _('{pkgname} is not a valid path or package name').format(pkgname = tarball_path)
		except pyalpm.error as e:
			# skip duplicate target error
			if not 'pm_errno 25' in str(e):
				self.error += str(e)+'\n'
				self.t.release()
		finally:
			if self.error:
				self.handle_error(self.error)
				return False
			else:
				return True

	def prepare(self):
		try:
			self.t.prepare()
		except pyalpm.error as e:
			self.error += str(e)+'\n'
			self.t.release()
		else:
			for pkg in self.t.to_remove:
				if pkg.name in config.holdpkg:
					self.error += _('The transaction cannot be performed because it needs to remove {pkgname1} which is a locked package').format(pkgname1 = pkg.name)
					self.t.release()
					break
		finally:
			if self.error:
				self.handle_error(self.error)
				return False
			else:
				return True

	def commit(self):
		try:
			self.t.commit()
		except pyalpm.error as e:
			self.error += str(e)+'\n'
		else:
			global progress_buffer
			ProgressCloseButton.set_visible(True)
			action_icon.set_from_icon_name('dialog-information', Gtk.IconSize.BUTTON)
			progress_label.set_text(_('Transaction successfully finished'))
			progress_bar.set_text('')
			end_iter = progress_buffer.get_end_iter()
			progress_buffer.insert(end_iter, _('Transaction successfully finished'))
		finally:
			self.release()
			if self.warning:
				self.handle_warning(self.warning)
				self.warning = ''
			if self.error:
				self.handle_error(self.error)

	def interrupt(self):
		try:
			self.t.interrupt()
		except:
			pass
		try:
			self.t.release()
		except:
			pass
		# Fix me, pyalpm don't stop so we inform and force quit to really interrupt the transaction
		InfoDialog.format_secondary_text(_('The transaction was interrupted.\nNow Pamac will quit.'))
		response = InfoDialog.run()
		if response:
			InfoDialog.hide()
		common.rm_pid_file()
		print('interrupted')
		exit(0)

	def set_transaction_sum(self, show_updates):
		transaction_sum.clear()
		sum_top_label.set_markup(_('<big><b>Transaction Summary</b></big>'))
		_to_remove = self.t.to_remove
		_to_install = []
		_to_reinstall = []
		_to_downgrade = []
		_to_update = []
		dsize = 0
		for pkg in self.t.to_add:
			dsize += pkg.download_size
			installed = self.get_localpkg(pkg.name)
			if not installed:
				_to_install.append(pkg)
			else:
				comp = pyalpm.vercmp(pkg.version, installed.version)
				if comp == 0:
					_to_reinstall.append(pkg)
				elif comp == -1:
					_to_downgrade.append(pkg)
				elif comp == 1:
					_to_update.append(pkg)
		if dsize == 0:
			sum_bottom_label.set_markup('')
		else:
			sum_bottom_label.set_markup(_('<b>Total download size: </b>')+common.format_size(dsize))
		i = 0
		while i < len(_to_remove):
			pkg = _to_remove[i]
			if i == 0:
				transaction_sum.append([_('To remove')+':', pkg.name+' '+pkg.version])
			else:
				transaction_sum.append(['', pkg.name+' '+pkg.version])
			i += 1
		i = 0
		while i < len(_to_install):
			pkg = _to_install[i]
			if i == 0:
				transaction_sum.append([_('To install')+':', pkg.name+' '+pkg.version])
			else:
				transaction_sum.append(['', pkg.name+' '+pkg.version])
			i += 1
		i = 0
		while i < len(_to_reinstall):
			pkg = _to_reinstall[i]
			if i == 0:
				transaction_sum.append([_('To reinstall')+':', pkg.name+' '+pkg.version])
			else:
				transaction_sum.append(['', pkg.name+' '+pkg.version])
			i += 1
		i = 0
		while i < len(_to_downgrade):
			pkg = _to_downgrade[i]
			if i == 0:
				transaction_sum.append([_('To downgrade')+':', pkg.name+' '+pkg.version])
			else:
				transaction_sum.append(['', pkg.name+' '+pkg.version])
			i += 1
		if show_updates:
			i = 0
			while i < len(_to_update):
				pkg = _to_update[i]
				if i == 0:
					transaction_sum.append([_('To update')+':', pkg.name+' '+pkg.version])
				else:
					transaction_sum.append(['', pkg.name+' '+pkg.version])
				i += 1

	def handle_error(self, error):
		ProgressWindow.hide()
		print(error)
		ErrorDialog.format_secondary_text(error)
		response = ErrorDialog.run()
		if response:
			ErrorDialog.hide()

	def handle_warning(self, warning):
		WarningDialog.format_secondary_text(warning)
		response = WarningDialog.run()
		if response:
			WarningDialog.hide()

	def do_sysupgrade(self, show_updates):
		do_syncfirst, to_update = self.get_updates()
		if to_update:
			self.to_add.clear()
			self.to_remove.clear()
			self.error = ''
			if do_syncfirst:
				if self.init(recurse = True):
					for pkg in to_update:
						self.add(pkg)
					if self.prepare():
						self.set_transaction_sum(show_updates)
						if show_updates:
							ConfDialog.show_all()
							while Gtk.events_pending():
								Gtk.main_iteration()
						else:
							if len(transaction_sum) != 0:
								ConfDialog.show_all()
								while Gtk.events_pending():
									Gtk.main_iteration()
							else:
								self.finalize()
			else:
				if self.init():
					if self.sysupgrade(False):
						if self.prepare():
							self.set_transaction_sum(show_updates)
							if show_updates:
								ConfDialog.show_all()
								while Gtk.events_pending():
									Gtk.main_iteration()
							else:
								if len(transaction_sum) != 0:
									ConfDialog.show_all()
									while Gtk.events_pending():
										Gtk.main_iteration()
								else:
									self.finalize()

	def finalize(self):
		global progress_buffer
		progress_label.set_text(_('Preparing')+'...')
		action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/package-setup.png')
		progress_bar.set_text('')
		progress_bar.set_fraction(0)
		progress_buffer.delete(progress_buffer.get_start_iter(),progress_buffer.get_end_iter())
		ProgressCloseButton.set_visible(False)
		ProgressWindow.show()
		while Gtk.events_pending():
			Gtk.main_iteration()
		self.commit()
		self.to_add.clear()
		self.to_remove.clear()

	def run(self):
		if self.to_add or self.to_remove or self.to_load:
			if self.init(cascade = True):
				for pkg in self.to_add:
					self.add(pkg)
				for pkg in self.to_remove:
					self.remove(pkg)
				for path in self.to_load:
					self.load(path)
				if self.prepare():
					self.set_transaction_sum(True)
					ConfDialog.show()
					while Gtk.events_pending():
						Gtk.main_iteration()
		else:
			self.handle_warning(_('Nothing to do'))

	def release(self):
		try:
			self.t.release()
		except:
			pass
