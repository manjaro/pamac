#! /usr/bin/python3
# -*- coding:utf-8 -*-

from gi.repository import Gtk, Gdk
from gi.repository.GdkPixbuf import Pixbuf
import pyalpm
import dbus
from collections import OrderedDict
from time import strftime, localtime

from pamac import config, common, transaction

# i18n
import gettext
import locale
locale.bindtextdomain('pamac', '/usr/share/locale')
gettext.bindtextdomain('pamac', '/usr/share/locale')
gettext.textdomain('pamac')
_ = gettext.gettext

interface = Gtk.Builder()
interface.set_translation_domain('pamac')

interface.add_from_file('/usr/share/pamac/gui/dialogs.glade')
ErrorDialog = interface.get_object('ErrorDialog')
WarningDialog = interface.get_object('WarningDialog')
InfoDialog = interface.get_object('InfoDialog')
#QuestionDialog = interface.get_object('QuestionDialog')

interface.add_from_file('/usr/share/pamac/gui/manager.glade')
ManagerWindow = interface.get_object("ManagerWindow")
details_list = interface.get_object('details_list')
deps_list = interface.get_object('deps_list')
files_list = interface.get_object('files_list')
files_scrolledwindow = interface.get_object('files_scrolledwindow')
name_label = interface.get_object('name_label')
desc_label = interface.get_object('desc_label')
link_label = interface.get_object('link_label')
licenses_label = interface.get_object('licenses_label')
search_entry = interface.get_object('search_entry')
search_list = interface.get_object('search_list')
search_selection = interface.get_object('search_treeview_selection')
packages_list = interface.get_object('packages_list')
list_selection = interface.get_object('list_treeview_selection')
installed_column = interface.get_object('installed_column')
name_column = interface.get_object('name_column')
groups_list = interface.get_object('groups_list')
groups_selection = interface.get_object('groups_treeview_selection')
state_list = interface.get_object('state_list')
state_selection = interface.get_object('state_treeview_selection')
repos_list = interface.get_object('repos_list')
repos_selection = interface.get_object('repos_treeview_selection')
ConfDialog = interface.get_object('ConfDialog')
transaction_sum = interface.get_object('transaction_sum')
sum_top_label = interface.get_object('sum_top_label')
sum_bottom_label = interface.get_object('sum_bottom_label')
ChooseDialog = interface.get_object('ChooseDialog')
choose_list = interface.get_object('choose_list')
choose_label = interface.get_object('choose_label')
ProgressWindow = interface.get_object('ProgressWindow')
progress_bar = interface.get_object('progressbar2')
progress_label = interface.get_object('progresslabel2')
action_icon = interface.get_object('action_icon')
ProgressCancelButton = interface.get_object('ProgressCancelButton')

interface.add_from_file('/usr/share/pamac/gui/updater.glade')
UpdaterWindow = interface.get_object("UpdaterWindow")
update_listore = interface.get_object('update_list')
update_top_label = interface.get_object('update_top_label')
update_bottom_label = interface.get_object('update_bottom_label')

def action_signal_handler(action):
	if action:
		progress_label.set_text(action)
	if (_('Installing') in action) or (_('Reinstalling') in action) or (_('Downgrading') in action) or (_('Removing') in action) or (_('Upgrading') in action) or (_('Configuring') in action):
		ProgressCancelButton.set_visible(False)
	else:
		ProgressCancelButton.set_visible(True)

def icon_signal_handler(icon):
	action_icon.set_from_file(icon)

def target_signal_handler(target):
	progress_bar.set_text(target)

def percent_signal_handler(percent):
	if percent > 1:
		progress_bar.pulse()
	else:
		progress_bar.set_fraction(percent)

bus = dbus.SystemBus()
bus.add_signal_receiver(action_signal_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitAction")
bus.add_signal_receiver(icon_signal_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitIcon")
bus.add_signal_receiver(target_signal_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitTarget")
bus.add_signal_receiver(percent_signal_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitPercent")

installed_icon = Pixbuf.new_from_file('/usr/share/pamac/icons/22x22/status/package-installed.png')
uninstalled_icon = Pixbuf.new_from_file('/usr/share/pamac/icons/22x22/status/package-available.png')
to_install_icon = Pixbuf.new_from_file('/usr/share/pamac/icons/22x22/status/package-add.png')
to_remove_icon = Pixbuf.new_from_file('/usr/share/pamac/icons/22x22/status/package-delete.png')
locked_icon = Pixbuf.new_from_file('/usr/share/pamac/icons/22x22/status/package-blocked.png')
search_icon = Pixbuf.new_from_file('/usr/share/pamac/icons/22x22/status/package-search.png')
 
pkg_name_list = set()
current_filter = (None, None)
mode = None
states = [_('Installed'), _('Uninstalled'), _('Orphans'), _('To install'), _('To remove')]
for state in states:
	state_list.append([state])

def get_groups():
	groups_list.clear()
	tmp_list = []
	for repo in transaction.handle.get_syncdbs():
		for name, pkgs in repo.grpcache:
			if not name in tmp_list:
				tmp_list.append(name)
	tmp_list = sorted(tmp_list)
	for name in tmp_list:
		groups_list.append([name])

def get_repos():
	repos_list.clear()
	for repo in transaction.handle.get_syncdbs():
		repos_list.append([repo.name])
	repos_list.append([_('local')])

def set_list_dict_search(*patterns):
	global pkg_name_list
	pkg_name_list.clear()
	for db in transaction.handle.get_syncdbs():
		for pkg in db.search(*patterns):
			pkg_name_list.add(pkg.name)
	for pkg in transaction.handle.get_localdb().search(*patterns):
		pkg_name_list.add(pkg.name)
	if pkg_name_list:
		joined = ''
		for term in patterns:
			joined += term
		already_in_list = False
		if len(search_list) != 0:
			for line in search_list:
				if joined == line[0]:
					already_in_list = True
		if not already_in_list:
			search_list.append([joined])

def set_list_dict_group(group):
	global pkg_name_list
	pkg_name_list.clear()
	for db in transaction.handle.get_syncdbs():
		grp = db.read_grp(group)
		if grp is not None:
			name, pkg_list = grp
			for pkg in pkg_list:
				pkg_name_list.add(pkg.name)
	db = transaction.handle.get_localdb()
	grp = db.read_grp(group)
	if grp is not None:
		name, pkg_list = grp
		for pkg in pkg_list:
			pkg_name_list.add(pkg.name)

def set_list_dict_installed():
	global pkg_name_list
	pkg_name_list.clear()
	pkg_name_list = set(transaction.localpkgs.keys())

def set_list_dict_uninstalled():
	global pkg_name_list
	pkg_name_list.clear()
	pkg_name_list = set(transaction.syncpkgs.keys()).difference(set(transaction.localpkgs.keys()))

def set_list_dict_local():
	global pkg_name_list
	pkg_name_list.clear()
	pkg_name_list = set(transaction.localpkgs.keys()).difference(set(transaction.syncpkgs.keys()))

def set_list_dict_orphans():
	global pkg_name_list
	pkg_name_list.clear()
	for pkg in transaction.localpkgs.values():
		if pkg.reason == 1:
			required = set(pkg.compute_requiredby())
			required &= set(transaction.localpkgs.keys())
			if not required:
				pkg_name_list.add(pkg.name)

def set_list_dict_to_install():
	global pkg_name_list
	pkg_name_list.clear()
	pkg_name_list = transaction.to_add.copy()

def set_list_dict_to_remove():
	global pkg_name_list
	pkg_name_list.clear()
	pkg_name_list = transaction.to_remove.copy()

def set_list_dict_repos(repo):
	global pkg_name_list
	pkg_name_list.clear()
	for db in  transaction.handle.get_syncdbs():
		if db.name == repo:
			for pkg in db.pkgcache:
				pkg_name_list.add(pkg.name)

def refresh_packages_list():
	if current_filter[0]:
		ManagerWindow.get_root_window().set_cursor(Gdk.Cursor(Gdk.CursorType.WATCH))
		while Gtk.events_pending():
			Gtk.main_iteration()
		packages_list.clear()
		if not pkg_name_list:
			packages_list.append([_('No package found'), False, False, False, search_icon, '', 0, ''])
		else:
			#installed = set(transaction.localpkgs.keys()) - transaction.to_remove
			#uninstalled = (set(transaction.syncpkgs.keys()) - installed) - transaction.to_add
			#to_lock = installed & set(config.holdpkg)
			name_list = sorted(pkg_name_list)
			for name in name_list:
				if name in config.holdpkg:
					packages_list.append([name, True, False, True, locked_icon, common.format_size(transaction.localpkgs[name].isize), transaction.localpkgs[name].isize, transaction.localpkgs[name].version])
				elif name in transaction.to_add:
					packages_list.append([name, False, True, True, to_install_icon, common.format_size(transaction.syncpkgs[name].isize), transaction.syncpkgs[name].isize, transaction.syncpkgs[name].version])
				elif name in transaction.to_remove:
					packages_list.append([name, True, True, False, to_remove_icon, common.format_size(transaction.localpkgs[name].isize), transaction.localpkgs[name].isize, transaction.localpkgs[name].version])
				elif name in transaction.localpkgs.keys():
					packages_list.append([name, True, True, True, installed_icon, common.format_size(transaction.localpkgs[name].isize), transaction.localpkgs[name].isize, transaction.localpkgs[name].version])
				#elif name in uninstalled:
				else:
					packages_list.append([name, False, True, False, uninstalled_icon, common.format_size(transaction.syncpkgs[name].isize), transaction.syncpkgs[name].isize, transaction.syncpkgs[name].version])
		ManagerWindow.get_root_window().set_cursor(Gdk.Cursor(Gdk.CursorType.ARROW))

def set_packages_list():
	if current_filter[0] == 'search':
		set_list_dict_search(*current_filter[1])
	elif current_filter[0] == 'group':
		set_list_dict_group(current_filter[1])
	elif current_filter[0] == 'installed':
		set_list_dict_installed()
	elif current_filter[0] == 'uninstalled':
		set_list_dict_uninstalled()
	elif current_filter[0] == 'orphans':
		set_list_dict_orphans()
	elif current_filter[0] == 'local':
		set_list_dict_local()
	elif current_filter[0] == 'to_install':
		set_list_dict_to_install()
	elif current_filter[0] == 'to_remove':
		set_list_dict_to_remove()
	elif current_filter[0] == 'repo':
		set_list_dict_repos(current_filter[1])
	if current_filter[0]:
		refresh_packages_list()

def set_infos_list(pkg):
	name_label.set_markup('<big><b>{}  {}</b></big>'.format(pkg.name, pkg.version))
	# fix &,-,>,< in desc
	desc = pkg.desc.replace('&', '&amp;')
	desc = desc.replace('<->', '/')
	desc_label.set_markup(desc)
	# fix & in url
	url = pkg.url.replace('&', '&amp;')
	link_label.set_markup('<a href=\"{_url}\">{_url}</a>'.format(_url = url))
	licenses_label.set_markup(_('Licenses')+': {}'.format(' '.join(pkg.licenses)))

def set_deps_list(pkg, style):
	deps_list.clear()
	if pkg.depends:
		deps_list.append([_('Depends On')+':', '\n'.join(pkg.depends)])
	if pkg.optdepends:
		deps_list.append([_('Optional Deps')+':', '\n'.join(pkg.optdepends)])
	if style == 'local':
		if pkg.compute_requiredby():
			deps_list.append([_('Required By')+':', '\n'.join(pkg.compute_requiredby())])
	if pkg.provides:
		deps_list.append([_('Provides')+':', '\n'.join(pkg.provides)])
	if pkg.replaces:
		deps_list.append([_('Replaces')+':', '\n'.join(pkg.replaces)])
	if pkg.conflicts:
		deps_list.append([_('Conflicts With')+':', '\n'.join(pkg.conflicts)])

def set_details_list(pkg, style):
	details_list.clear()
	if style == 'sync':
		details_list.append([_('Repository')+':', pkg.db.name])
	if pkg.groups:
		details_list.append([_('Groups')+':', ' '.join(pkg.groups)])
	if style == 'sync':
		details_list.append([_('Compressed Size')+':', common.format_size(pkg.size)])
		details_list.append([_('Download Size')+':', common.format_size(pkg.download_size)])
	if style == 'local':
		details_list.append([_('Installed Size')+':', common.format_size(pkg.isize)])
	details_list.append([_('Packager')+':', pkg.packager])
	details_list.append([_('Architecture')+':', pkg.arch])
	#details_list.append([_('Build Date')+':', strftime("%a %d %b %Y %X %Z", localtime(pkg.builddate))])
	if style == 'local':
		details_list.append([_('Install Date')+':', strftime("%a %d %b %Y %X %Z", localtime(pkg.installdate))])
		if pkg.reason == pyalpm.PKG_REASON_EXPLICIT:
			reason = _('Explicitly installed')
		elif pkg.reason == pyalpm.PKG_REASON_DEPEND:
			reason = _('Installed as a dependency for another package')
		else:
			reason = _('Unknown')
		details_list.append([_('Install Reason')+':', reason])
	if style == 'sync':
		#details_list.append([_('Install Script')':', 'Yes' if pkg.has_scriptlet else 'No'])
		#details_list.append(['MD5 Sum:', pkg.md5sum])
		#details_list.append(['SHA256 Sum:', pkg.sha256sum])
		details_list.append([_('Signatures')+':', 'Yes' if pkg.base64_sig else 'No'])
	if style == 'local':
		if len(pkg.backup) != 0:
			#details_list.append(['_(Backup files)+':', '\n'.join(["%s %s" % (md5, file) for (file, md5) in pkg.backup])])
			details_list.append([_('Backup files')+':', '\n'.join(["%s" % (file) for (file, md5) in pkg.backup])])

def set_files_list(pkg):
	files_list.clear()
	if len(pkg.files) != 0:
		for file in pkg.files:
			files_list.append(['/'+file[0]])

def set_transaction_sum():
	transaction_sum.clear()
	sum_top_label.set_markup(_('<big><b>Transaction Summary</b></big>'))
	if mode == 'manager':
		if transaction.to_update:
			to_update = sorted(transaction.to_update)
			transaction_sum.append([_('To update')+':', to_update[0]])
			i = 1
			while i < len(to_update):
				transaction_sum.append([' ', to_update[i]])
				i += 1
	if transaction.to_add:
		transaction.to_add -= transaction.to_update
		to_add = sorted(transaction.to_add)
		if to_add:
			transaction_sum.append([_('To install')+':', to_add[0]])
			i = 1
			while i < len(to_add):
				transaction_sum.append([' ', to_add[i]])
				i += 1
	if transaction.to_add or transaction.to_update:
		dsize = 0
		for name in transaction.to_add | transaction.to_update:
			if name in transaction.syncpkgs.keys():
				dsize += transaction.syncpkgs[name].download_size
		sum_bottom_label.set_markup(_('<b>Total download size: </b>')+common.format_size(dsize))
	if transaction.to_remove:
		to_remove = sorted(transaction.to_remove)
		transaction_sum.append([_('To remove')+':', to_remove[0]])
		i = 1
		while i < len(to_remove):
			transaction_sum.append([' ', to_remove[i]])
			i += 1
		sum_bottom_label.set_markup('')

def handle_error(error):
	ProgressWindow.hide()
	#while Gtk.events_pending():
	#	Gtk.main_iteration()
	if error:
		if not 'DBus.Error.NoReply' in str(error):
			print('error:', error)
			ErrorDialog.format_secondary_text(error)
			response = ErrorDialog.run()
			if response:
				ErrorDialog.hide()
	try:
		transaction.Release()
	except:
		pass
	if mode == 'manager':
		transaction.get_handle()
		transaction.update_db()
		transaction.to_add.clear()
		transaction.to_remove.clear()
		transaction.to_update.clear()
		set_packages_list()
	if mode == 'updater':
		have_updates()

def handle_reply(reply):
	ProgressWindow.hide()
	#while Gtk.events_pending():
	#	Gtk.main_iteration()
	if reply:
		InfoDialog.format_secondary_text(reply)
		response = InfoDialog.run()
		if response:
			InfoDialog.hide()
	try:
		transaction.Release()
	except:
		pass
	transaction.get_handle()
	transaction.update_db()
	if mode == 'manager':
		transaction.to_add.clear()
		transaction.to_remove.clear()
		transaction.to_update.clear()
		set_packages_list()
	if have_updates():
		if mode == 'manager':
			do_sysupgrade()

bus.add_signal_receiver(handle_reply, dbus_interface = "org.manjaro.pamac", signal_name = "EmitTransactionDone")
bus.add_signal_receiver(handle_error, dbus_interface = "org.manjaro.pamac", signal_name = "EmitTransactionError")

def do_refresh():
	"""Sync databases like pacman -Sy"""
	progress_label.set_text(_('Refreshing')+'...')
	action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/refresh-cache.png')
	progress_bar.set_text('')
	progress_bar.set_fraction(0)
	ProgressWindow.show_all()
	while Gtk.events_pending():
		Gtk.main_iteration()
	transaction.Refresh()

def have_updates():
	do_syncfirst, updates = transaction.get_updates()
	update_listore.clear()
	update_top_label.set_justify(Gtk.Justification.CENTER)
	if not updates:
		update_listore.append(['', ''])
		update_bottom_label.set_markup('')
		update_top_label.set_markup(_('<big><b>Your system is up-to-date</b></big>'))
		return False
	else:
		dsize = 0
		for pkg in updates:
			pkgname = pkg.name+" "+pkg.version
			update_listore.append([pkgname, common.format_size(pkg.size)])
			dsize += pkg.download_size
		update_bottom_label.set_markup(_('<b>Total download size: </b>')+common.format_size(dsize))
		if len(updates) == 1:
			update_top_label.set_markup(_('<big><b>1 available update</b></big>'))
		else:
			update_top_label.set_markup(_('<big><b>{number} available updates</b></big>').format(number = len(updates)))
		return True

def do_sysupgrade():
	"""Upgrade a system like pacman -Su"""
	do_syncfirst, updates = transaction.get_updates()
	if updates:
		transaction.to_add.clear()
		transaction.to_remove.clear()
		transaction.to_update = set([pkg.name for pkg in updates])
		check_conflicts()
		init = False
		error = ''
		if do_syncfirst:
			init = transaction.init_transaction(noconflicts = True, recurse = True)
		else:
			init = transaction.init_transaction(noconflicts = True)
			if init:
				error = transaction.Sysupgrade()
				if error:
					handle_error(error)
		if init:
			if not error:
				for name in transaction.to_add | transaction.to_update:
					transaction.Add(name)
				for name in transaction.to_remove:
					transaction.Remove(name)
				error = transaction.Prepare()
				if error:
					handle_error(error)
				else:
					transaction.get_to_remove()
					transaction.get_to_add()
					transaction.to_add -= transaction.to_update
					set_transaction_sum()
					if mode == 'updater':
						if len(transaction.to_add) + len(transaction.to_remove) != 0:
							ConfDialog.show_all()
						else:
							finalize()
					if mode == 'manager':
						ConfDialog.show_all()

def finalize():
	progress_label.set_text(_('Preparing')+'...')
	action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/setup.png')
	progress_bar.set_text('')
	progress_bar.set_fraction(0)
	ProgressWindow.show_all()
	while Gtk.events_pending():
		Gtk.main_iteration()
	try:
		transaction.Commit()
	except dbus.exceptions.DBusException as e:
		handle_error(str(e))

def check_conflicts():
	print('checking...')
	ManagerWindow.get_root_window().set_cursor(Gdk.Cursor(Gdk.CursorType.WATCH))
	while Gtk.events_pending():
		Gtk.main_iteration()
	to_check = [transaction.syncpkgs[name] for name in transaction.to_add | transaction.to_update]
	if transaction.to_load:
		for path in transaction.to_load:
			pkg = transaction.handle.load_pkg(path)
			if pkg:
				to_check.append(pkg)
	already_checked = set(pkg.name for pkg in to_check)
	depends = [to_check]
	warning = ''
	error = ''
	pkgs = transaction.handle.get_localdb().search('linux3')
	installed_linux = []
	# get packages to remove
	check_for_removal = transaction.to_remove.copy()
	to_add_to_remove = set()
	hold_requirement = {}
	while check_for_removal:
		for name in check_for_removal:
			required = transaction.localpkgs[name].compute_requiredby()
			for requirement in required:
				if requirement in config.holdpkg:
					for hold in config.holdpkg:
						if requirement == hold:
							if error:
								error += '\n'
							error += _('The transaction cannot be performed because it needs to remove {pkgname1} which is a locked package').format(pkgname1 = hold)
							print(_('The transaction cannot be performed because it needs to remove {pkgname1} which is a locked package').format(pkgname1 = hold))
				else:
					to_add_to_remove.add(requirement)
		to_add_to_remove &= set(transaction.localpkgs.keys())
		check_for_removal = to_add_to_remove.copy()
		transaction.to_remove |= to_add_to_remove
		to_add_to_remove.clear()
		if error:
			break
	# get installed kernels
	for item in pkgs:
		if len(item.name) == 7:
			installed_linux.append(item.name)
	for to_install in transaction.to_add:
		if 'linux3' in to_install:
			if len(to_install) == 7:
				installed_linux.append(to_install)
	# check if new pkgs will replace installed ones
	if transaction.to_update:
		for pkg in transaction.syncpkgs.values():
			for replace in pkg.replaces:
				found_replace = pyalpm.find_satisfier(transaction.localpkgs.values(), replace)
				if found_replace:
					if not common.format_pkg_name(replace) in transaction.syncpkgs.keys():
						if found_replace.name != pkg.name:
							if not pkg.name in transaction.localpkgs.keys():
								if common.format_pkg_name(replace) in transaction.localpkgs.keys():
									if not found_replace.name in transaction.to_remove:
										transaction.to_remove.add(found_replace.name)
										if warning:
											warning += '\n'
										warning += _('{pkgname1} will be replaced by {pkgname2}').format(pkgname1 = found_replace.name, pkgname2 = pkg.name)
										print(_('{pkgname1} will be replaced by {pkgname2}').format(pkgname1 = found_replace.name, pkgname2 = pkg.name))
									if not pkg.name in already_checked:
										depends[0].append(pkg)
										already_checked.add(pkg.name)
									transaction.to_add.add(pkg.name)
	# start loops to check pkgs
	i = 0
	while depends[i]:
		# add a empty list for new pkgs to check next loop
		depends.append([])
		# start to check one pkg
		for pkg in depends[i]:
			# check if the current pkg is a kernel and if so, check if a module is required to install
			if 'linux3' in pkg.name:
				for _pkg in transaction.localpkgs.values():
					for depend in _pkg.depends:
						if '-modules' in depend:
							for __pkg in transaction.syncpkgs.values():
								if not __pkg.name in transaction.localpkgs.keys():
									for provide in __pkg.provides:
										for linux in installed_linux:
											if linux in __pkg.name:
												if common.format_pkg_name(depend) == common.format_pkg_name(provide):
													if not __pkg.name in transaction.to_add:
														if not __pkg.name in already_checked:
															depends[i+1].append(__pkg)
															already_checked.add(__pkg.name)
														transaction.to_add.add(__pkg.name)
			# check pkg deps
			for depend in pkg.depends:
				# check if dep is already installed
				found_depend = pyalpm.find_satisfier(transaction.localpkgs.values(), depend)
				if found_depend:
					# check if the dep is a kernel module to provide and if so, auto-select it
					if found_depend.name != common.format_pkg_name(depend):
						if ('-modules' in depend) or ('linux' in depend):
							for _pkg in transaction.syncpkgs.values():
								if not _pkg.name in transaction.localpkgs.keys():
									for name in _pkg.provides:
										for linux in installed_linux:
											if linux in _pkg.name:
												if common.format_pkg_name(depend) == common.format_pkg_name(name):
													if not _pkg.name in transaction.to_add:
														if not _pkg.name in already_checked:
															depends[i+1].append(_pkg)
															already_checked.add(_pkg.name)
														transaction.to_add.add(_pkg.name)
					else:
						# add the dep in list to check its deps in next loop 
						if not found_depend.name in already_checked:
							depends[i+1].append(found_depend)
							already_checked.add(found_depend.name)
				else:
					# found the dep in uninstalled pkgs
					found_depend = pyalpm.find_satisfier(transaction.syncpkgs.values(), depend)
					if found_depend:
						# check if the dep is a kernel module to provide and if so, auto-select it
						if found_depend.name != common.format_pkg_name(depend):
							if ('-modules' in depend) or ('linux' in depend):
								for _pkg in transaction.syncpkgs.values():
									if not _pkg.name in transaction.localpkgs.keys():
										for name in _pkg.provides:
											for linux in installed_linux:
												if linux in _pkg.name:
													if common.format_pkg_name(depend) == common.format_pkg_name(name):
														if not _pkg.name in transaction.to_add:
															if not _pkg.name in already_checked:
																depends[i+1].append(_pkg)
																already_checked.add(_pkg.name)
															transaction.to_add.add(_pkg.name)
							else:
								# so the dep is a virtual dep: check if it's already provides
								already_provided = False
								for pkgname in transaction.to_add:
									_pkg = transaction.syncpkgs[pkgname]
									found_depend = pyalpm.find_satisfier([_pkg], depend)
									if found_depend:
										already_provided = True
								# if not already provided, run ChooseDialog (via choose_provides)
								if not already_provided:
									to_add_to_depends = choose_provides(depend)
									for _pkg in to_add_to_depends:
										if not _pkg.name in transaction.to_add:
											if not _pkg.name in already_checked:
												depends[i+1].append(_pkg)
												already_checked.add(_pkg.name)
											transaction.to_add.add(_pkg.name)
						else:
							# so the dep is not yet installed, add it in list to check its deps in next loop
							if not found_depend.name in already_checked:
								depends[i+1].append(found_depend)
								already_checked.add(found_depend.name)
			# check if the pkg replaces installed ones
			if transaction.to_update:
				for replace in pkg.replaces:
					found_replace = pyalpm.find_satisfier(transaction.localpkgs.values(), replace)
					if found_replace:
						if found_replace.name != pkg.name:
							if not found_replace.name in transaction.to_remove:
								transaction.to_remove.add(found_replace.name)
								if warning:
									warning += '\n'
								warning += _('{pkgname1} will be replaced by {pkgname2}').format(pkgname1 = found_replace.name, pkgname2 = pkg.name)
								print(_('{pkgname1} will be replaced by {pkgname2}').format(pkgname1 = found_replace.name, pkgname2 = pkg.name))
			# check pkg conflicts
			for conflict in pkg.conflicts:
				# check if the pkg conflicts with installed ones
				found_conflict = pyalpm.find_satisfier(transaction.localpkgs.values(), conflict)
				if found_conflict:
					if found_conflict.name != pkg.name:
						# if pkg provides the conflict no need to check if it can be safely removed
						will_provide_conflict = pyalpm.find_satisfier([pkg], conflict)
						if will_provide_conflict:
							if not found_conflict.name in transaction.to_remove:
								transaction.to_remove.add(found_conflict.name)
								if warning:
									warning += '\n'
								warning += _('{pkgname1} conflicts with {pkgname2}').format(pkgname1 = pkg.name, pkgname2 = found_conflict.name)
								print(_('{pkgname1} conflicts with {pkgname2}').format(pkgname1 = pkg.name, pkgname2 = found_conflict.name))
						else:
							# if the conflict will be updated, check the conflicts of the new one
							if found_conflict.name in transaction.to_update:
								new_found_conflict = pyalpm.find_satisfier([transaction.syncpkgs[found_conflict.name]], conflict)
								if new_found_conflict:
									# check if the conflict can be safely removed
									required = set(pkg.compute_requiredby())
									required &= set(transaction.localpkgs.keys())
									if required:
										str_required = ''
										for item in required:
											if str_required:
												str_required += ', '
											str_required += item
										if error:
											error += '\n'
										error += _('{pkgname1} conflicts with {pkgname2} but cannot be removed because it is needed by {pkgname3}').format(pkgname1 = found_conflict.name, pkgname2 = pkg.name, pkgname3 = str_required)
										print(_('{pkgname1} conflicts with {pkgname2} but cannot be removed because it is needed by {pkgname3}').format(pkgname1 = found_conflict.name, pkgname2 = pkg.name, pkgname3 = str_required))
									elif not found_conflict.name in transaction.to_remove:
										transaction.to_remove.add(found_conflict.name)
										if warning:
											warning += '\n'
										warning += _('{pkgname1} conflicts with {pkgname2}').format(pkgname1 = pkg.name, pkgname2 = found_conflict.name)
										print(_('{pkgname1} conflicts with {pkgname2}').format(pkgname1 = pkg.name, pkgname2 = found_conflict.name))
							else:
								# check if the conflict can be safely removed
								required = set(pkg.compute_requiredby())
								required &= set(transaction.localpkgs.keys())
								if required:
									str_required = ''
									for item in required:
										if str_required:
											str_required += ', '
										str_required += item
									if error:
										error += '\n'
									error += _('{pkgname1} conflicts with {pkgname2} but cannot be removed because it is needed by {pkgname3}').format(pkgname1 = found_conflict.name, pkgname2 = pkg.name, pkgname3 = str_required)
									print(_('{pkgname1} conflicts with {pkgname2} but cannot be removed because it is needed by {pkgname3}').format(pkgname1 = found_conflict.name, pkgname2 = pkg.name, pkgname3 = str_required))
								elif not found_conflict.name in transaction.to_remove:
									transaction.to_remove.add(found_conflict.name)
									if warning:
										warning += '\n'
									warning += _('{pkgname1} conflicts with {pkgname2}').format(pkgname1 = pkg.name, pkgname2 = found_conflict.name)
									print(_('{pkgname1} conflicts with {pkgname2}').format(pkgname1 = pkg.name, pkgname2 = found_conflict.name))
				# check if the pkg conflicts with the other ones to install
				found_conflict = pyalpm.find_satisfier(depends[0], conflict)
				if found_conflict:
					if not common.format_pkg_name(conflict) == pkg.name:
						if not common.format_pkg_name(conflict) in transaction.to_remove:
							if pkg.name in transaction.to_add and common.format_pkg_name(conflict) in transaction.to_add:
								transaction.to_add.discard(common.format_pkg_name(conflict))
								transaction.to_add.discard(pkg.name)
								if warning:
									warning += '\n'
								warning += _('{pkgname1} conflicts with {pkgname2}\nNone of them will be installed').format(pkgname1 = pkg.name, pkgname2 = common.format_pkg_name(conflict))
								print(_('{pkgname1} conflicts with {pkgname2}\nNone of them will be installed').format(pkgname1 = pkg.name, pkgname2 = common.format_pkg_name(conflict)))
		i += 1
		# end of the loop

	# check if installed pkgs conflicts with the ones to install
	to_check = [transaction.syncpkgs[name] for name in transaction.to_add | transaction.to_update]
	for pkg in transaction.localpkgs.values():
		for conflict in pkg.conflicts:
			found_conflict = pyalpm.find_satisfier(to_check, conflict)
			if found_conflict:
				if found_conflict.name != pkg.name:
					# if pkg provides the conflict no need to check if it can be safely removed
					will_provide_conflict = pyalpm.find_satisfier([pkg], conflict)
					if will_provide_conflict:
						if not pkg.name in transaction.to_remove:
							transaction.to_remove.add(pkg.name)
							if warning:
								warning += '\n'
							warning += _('{pkgname1} conflicts with {pkgname2}').format(pkgname1 = found_conflict.name, pkgname2 = pkg.name)
							print(_('{pkgname1} conflicts with {pkgname2}').format(pkgname1 = found_conflict.name, pkgname2 = pkg.name))
					else:
						# if pkg will be updated, check the conflicts of this new one
						if pkg.name in transaction.to_update:
							for new_conflict in transaction.syncpkgs[pkg.name].conflicts:
								if new_conflict == conflict:
									# check if the conflict can be safely removed
									required = set(pkg.compute_requiredby())
									required &= set(transaction.localpkgs.keys())
									if required:
										str_required = ''
										for item in required:
											if str_required:
												str_required += ', '
											str_required += item
										if error:
											error += '\n'
										error += _('{pkgname1} conflicts with {pkgname2} but cannot be removed because it is needed by {pkgname3}').format(pkgname1 = pkg.name, pkgname2 = found_conflict.name, pkgname3 = str_required)
										print(_('{pkgname1} conflicts with {pkgname2} but cannot be removed because it is needed by {pkgname3}').format(pkgname1 = pkg.name, pkgname2 = found_conflict.name, pkgname3 = str_required))
									elif not pkg.name in transaction.to_remove:
										transaction.to_remove.add(pkg.name)
										if warning:
											warning += '\n'
										warning += _('{pkgname1} conflicts with {pkgname2}').format(pkgname1= found_conflict.name, pkgname2 = pkg.name)
										print(_('{pkgname1} conflicts with {pkgname2}').format(pkgname1 = found_conflict.name, pkgname2 = pkg.name))
						else:
							# check if the conflict can be safely removed
							required = set(pkg.compute_requiredby())
							required &= set(transaction.localpkgs.keys())
							if required:
								str_required = ''
								for item in required:
									if str_required:
										str_required += ', '
									str_required += item
								if error:
									error += '\n'
								error += _('{pkgname1} conflicts with {pkgname2} but cannot be removed because it is needed by {pkgname3}').format(pkgname1 = pkg.name, pkgname2 = found_conflict.name, pkgname3 = str_required)
								print(_('{pkgname1} conflicts with {pkgname2} but cannot be removed because it is needed by {pkgname3}').format(pkgname1 = pkg.name, pkgname2 = found_conflict.name, pkgname3 = str_required))
							elif not pkg.name in transaction.to_remove:
								transaction.to_remove.add(pkg.name)
								if warning:
									warning += '\n'
								warning += _('{pkgname1} conflicts with {pkgname2}').format(pkgname1= found_conflict.name, pkgname2 = pkg.name)
								print(_('{pkgname1} conflicts with {pkgname2}').format(pkgname1 = found_conflict.name, pkgname2 = pkg.name))

	# remove in to_remove the packages which are needed by the names in to_add to avoid conflicts:
	wont_be_removed = set()
	for pkg_list in depends:
		for pkg in pkg_list:
			wont_be_removed.add(pkg.name)

	ManagerWindow.get_root_window().set_cursor(Gdk.Cursor(Gdk.CursorType.ARROW))
	print('check result:')
	print('    to add:', transaction.to_add if transaction.to_add else 'None')
	if transaction.to_load:
		print('    to load:', transaction.to_load)
	print('    will not be removed:', transaction.to_remove & wont_be_removed if transaction.to_remove & wont_be_removed else 'None')
	transaction.to_remove -= wont_be_removed
	print('    to remove:', transaction.to_remove if transaction.to_remove else 'None')
	print('    to update:', transaction.to_update if transaction.to_update else 'None')
	if warning:
		WarningDialog.format_secondary_text(warning)
		response = WarningDialog.run()
		if response:
			WarningDialog.hide()
	if error:
		handle_error(error)

def choose_provides(name):
	provides = OrderedDict()
	already_add = []
	for pkg in transaction.syncpkgs.values():
		for provide in pkg.provides:
			if common.format_pkg_name(name) == common.format_pkg_name(provide):
				if not pkg.name in provides.keys():
					provides[pkg.name] = pkg
	if provides:
		choose_label.set_markup(_('<b>{pkgname} is provided by {number} packages.\nPlease choose the one(s) you want to install:</b>').format(pkgname = name, number = str(len(provides.keys()))))
		choose_list.clear()
		for name in provides.keys():
			if transaction.handle.get_localdb().get_pkg(name):
				choose_list.append([True, name])
			else:
				choose_list.append([False, name])
		ChooseDialog.run()
		return [provides[pkgname] for pkgname in transaction.to_provide]
	else:
		return []

class Handler:
	#Manager Handlers
	def on_ManagerWindow_delete_event(self, *arg):
		transaction.StopDaemon()
		common.rm_pid_file()
		Gtk.main_quit()

	def on_Manager_QuitButton_clicked(self, *arg):
		transaction.StopDaemon()
		common.rm_pid_file()
		Gtk.main_quit()

	def on_Manager_ValidButton_clicked(self, *arg):
		transaction.to_update.clear()
		if transaction.to_add | transaction.to_remove:
			check_conflicts()
		if transaction.to_add | transaction.to_remove:
			if transaction.init_transaction(noconflicts = True):
				for pkgname in transaction.to_add:
					transaction.Add(pkgname)
				for pkgname in transaction.to_remove:
					transaction.Remove(pkgname)
				error = transaction.Prepare()
				if error:
					handle_error(error)
				else:
					transaction.get_to_remove()
					transaction.get_to_add()
					do_syncfirst, updates = transaction.get_updates()
					transaction.to_update = set([pkg.name for pkg in updates])
					transaction.to_add -= transaction.to_update
					set_transaction_sum()
					ConfDialog.show_all()
		else:
			WarningDialog.format_secondary_text(_('Nothing to do'))
			response = WarningDialog.run()
			if response:
				WarningDialog.hide()
			refresh_packages_list()

	def on_Manager_EraseButton_clicked(self, *arg):
		transaction.to_add.clear()
		transaction.to_remove.clear()
		transaction.to_update.clear()
		refresh_packages_list()

	def on_Manager_RefreshButton_clicked(self, *arg):
		do_refresh()

	def on_TransCancelButton_clicked(self, *arg):
		ProgressWindow.hide()
		ConfDialog.hide()
		transaction.Release()
		refresh_packages_list()

	def on_TransValidButton_clicked(self, *arg):
		ConfDialog.hide()
		finalize()

	def on_search_entry_icon_press(self, *arg):
		global current_filter
		current_filter = ('search', search_entry.get_text().split())
		set_packages_list()

	def on_search_entry_activate(self, widget):
		global current_filter
		current_filter = ('search', search_entry.get_text().split())
		set_packages_list()

	def on_list_treeview_selection_changed(self, widget):
		liste, line = list_selection.get_selected()
		if line:
			if packages_list[line][0] != _('No package found'):
				if transaction.localpkgs.__contains__(packages_list[line][0]):
					set_infos_list(transaction.localpkgs[packages_list[line][0]])
					set_deps_list(transaction.localpkgs[packages_list[line][0]], "local")
					set_details_list(transaction.localpkgs[packages_list[line][0]], "local")
					set_files_list(transaction.localpkgs[packages_list[line][0]])
					files_scrolledwindow.set_visible(True)
				else:
					set_infos_list(transaction.syncpkgs[packages_list[line][0]])
					set_deps_list(transaction.syncpkgs[packages_list[line][0]], "sync")
					set_details_list(transaction.syncpkgs[packages_list[line][0]], "sync")
					files_scrolledwindow.set_visible(False)

	def on_search_treeview_selection_changed(self, widget):
		global current_filter
		liste, line = search_selection.get_selected()
		if line:
			current_filter = ('search', search_list[line][0].split())
			set_packages_list()

	def on_groups_treeview_selection_changed(self, widget):
		global current_filter
		liste, line = groups_selection.get_selected()
		if line:
			current_filter = ('group', groups_list[line][0])
			set_packages_list()

	def on_state_treeview_selection_changed(self, widget):
		global current_filter
		liste, line = state_selection.get_selected()
		if line:
			if state_list[line][0] == _('Installed'):
				current_filter = ('installed', None)
			if state_list[line][0] == _('Uninstalled'):
				current_filter = ('uninstalled', None)
			if state_list[line][0] == _('Orphans'):
				current_filter = ('orphans', None)
			if state_list[line][0] == _('To install'):
				current_filter = ('to_install', None)
			if state_list[line][0] == _('To remove'):
				current_filter = ('to_remove', None)
			set_packages_list()

	def on_repos_treeview_selection_changed(self, widget):
		global current_filter
		liste, line = repos_selection.get_selected()
		if line:
			if repos_list[line][0] == _('local'):
				current_filter = ('local', None)
			else:
				current_filter = ('repo', repos_list[line][0])
			set_packages_list()

	def on_cellrenderertoggle1_toggled(self, widget, line):
		if packages_list[line][1] is True:
			if packages_list[line][0] in transaction.to_remove:
				packages_list[line][3] =True
				packages_list[line][4] = installed_icon
				transaction.to_remove.discard(packages_list[line][0])
			else:
				packages_list[line][3] = False
				packages_list[line][4] = to_remove_icon
				transaction.to_remove.add(packages_list[line][0])
		if packages_list[line][1] is False:
			if packages_list[line][0] in transaction.to_add:
				packages_list[line][3] = False
				packages_list[line][4] = uninstalled_icon
				transaction.to_add.discard(packages_list[line][0])
			else:
				packages_list[line][3] = True
				packages_list[line][4] = to_install_icon
				transaction.to_add.add(packages_list[line][0])

	def on_cellrenderertoggle2_toggled(self, widget, line):
		choose_list[line][0] = not choose_list[line][0]

	def on_ChooseButton_clicked(self, *arg):
		ChooseDialog.hide()
		line = 0
		transaction.to_provide.clear()
		while line <  len(choose_list):
			if choose_list[line][0] is True:
				if not choose_list[line][1] in transaction.localpkgs.keys():
						transaction.to_provide.add(choose_list[line][1])
			if choose_list[line][0] is False:
				transaction.to_provide.discard(choose_list[line][1])
			line += 1

	def on_ProgressCancelButton_clicked(self, *arg):
		print('cancelled')
		if not _('Refreshing') in progress_label.get_text(): 
			error = transaction.Interrupt()
			if error:
				handle_error(error)
			else:
				handle_reply('')

	#Updater Handlers
	def on_UpdaterWindow_delete_event(self, *arg):
		transaction.StopDaemon()
		common.rm_pid_file()
		Gtk.main_quit()

	def on_Updater_QuitButton_clicked(self, *arg):
		transaction.StopDaemon()
		common.rm_pid_file()
		Gtk.main_quit()

	def on_Updater_ApplyButton_clicked(self, *arg):
		do_sysupgrade()

	def on_Updater_RefreshButton_clicked(self, *arg):
		do_refresh()

def main(_mode):
	if common.pid_file_exists():
		ErrorDialog.format_secondary_text(_('Pamac is already running'))
		response = ErrorDialog.run()
		if response:
			ErrorDialog.hide()
	else:
		common.write_pid_file()
		global mode
		mode = _mode
		interface.connect_signals(Handler())
		do_refresh()
		transaction.get_handle()
		get_groups()
		get_repos()
		if mode == 'manager':
			ManagerWindow.show_all()
		if mode == 'updater':
			update_top_label.set_markup(_('<big><b>Your system is up-to-date</b></big>'))
			update_bottom_label.set_markup('')
			UpdaterWindow.show_all()
		while Gtk.events_pending():
			Gtk.main_iteration()
		Gtk.main()
