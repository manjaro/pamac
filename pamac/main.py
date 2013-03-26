#! /usr/bin/python
# -*-coding:utf-8 -*-

from gi.repository import Gtk
from gi.repository.GdkPixbuf import Pixbuf
import pyalpm
import dbus
from collections import OrderedDict
from time import strftime, localtime

from pamac import config, common, transaction

interface = Gtk.Builder()

#interface.add_from_file('/usr/share/pamac/gui/dialogs.glade')
#ErrorDialog = interface.get_object('ErrorDialog')
#WarningDialog = interface.get_object('WarningDialog')
#InfoDialog = interface.get_object('InfoDialog')
#QuestionDialog = interface.get_object('QuestionDialog')

interface.add_from_file('/usr/share/pamac/gui/manager.glade')
ManagerWindow = interface.get_object("ManagerWindow")
package_desc = interface.get_object('package_desc')
#select_toggle = interface.get_object('cellrenderertoggle1')
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
	if ('Installing' in action) or ('Removing' in action) or ('Updating' in action):
		ProgressCancelButton.set_visible(False)
	else:
		ProgressCancelButton.set_visible(True)

def icon_signal_handler(icon):
	action_icon.set_from_file(icon)

def target_signal_handler(target):
	progress_bar.set_text(target)

def percent_signal_handler(percent):
	if float(percent) > 1:
		progress_bar.pulse()
	else:
		progress_bar.set_fraction(float(percent))

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
 
pkg_name_list = []
pkg_object_dict = {}
pkg_installed_dict = {}
current_filter = (None, None)
transaction_type = None
transaction_dict = {}
mode = None
states = ['Installed', 'Uninstalled', 'Orphans', 'To install', 'To remove']
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
	repos_list.append(['local'])

def set_list_dict_search(*patterns):
	global pkg_name_list
	global pkg_object_dict
	global pkg_installed_dict
	pkg_name_list = []
	pkg_object_dict = {}
	pkg_installed_dict = {}
	for db in transaction.handle.get_syncdbs():
		for pkg_object in db.search(*patterns):
			if not pkg_object.name in pkg_name_list:
				pkg_name_list.append(pkg_object.name)
				pkg_object_dict[pkg_object.name] = pkg_object
				pkg_installed_dict[pkg_object.name] = False
	for pkg_object in transaction.handle.get_localdb().search(*patterns):
		if not pkg_object.name in pkg_name_list:
			pkg_name_list.append(pkg_object.name)
		pkg_installed_dict[pkg_object.name] = True
		pkg_object_dict[pkg_object.name] = pkg_object
	pkg_name_list = sorted(pkg_name_list)
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
	global pkg_object_dict
	global pkg_installed_dict
	pkg_name_list = []
	pkg_object_dict = {}
	pkg_installed_dict = {}
	for db in transaction.handle.get_syncdbs():
		grp = db.read_grp(group)
		if grp is not None:
			name, pkg_list = grp
			for pkg_object in pkg_list:
				if not pkg_object.name in pkg_name_list:
					pkg_name_list.append(pkg_object.name)
				pkg_object_dict[pkg_object.name] = pkg_object
				pkg_installed_dict[pkg_object.name] = False
	db = config.pacman_conf.initialize_alpm().get_localdb()
	grp = db.read_grp(group)
	if grp is not None:
		name, pkg_list = grp
		for pkg_object in pkg_list:
			if not pkg_object.name in pkg_name_list:
				pkg_name_list.append(pkg_object.name)
			pkg_installed_dict[pkg_object.name] = True
			pkg_object_dict[pkg_object.name] = pkg_object
	pkg_name_list = sorted(pkg_name_list)

def set_list_dict_installed():
	global pkg_name_list
	global pkg_object_dict
	global pkg_installed_dict
	pkg_name_list = []
	pkg_object_dict = {}
	pkg_installed_dict = {}
	for pkg_object in transaction.localpkgs.values():
		if not pkg_object.name in pkg_name_list:
			pkg_name_list.append(pkg_object.name)
			pkg_installed_dict[pkg_object.name] = True
			pkg_object_dict[pkg_object.name] = pkg_object

def set_list_dict_uninstalled():
	global pkg_name_list
	global pkg_object_dict
	global pkg_installed_dict
	pkg_name_list = []
	pkg_object_dict = {}
	pkg_installed_dict = {}
	for pkg_object in transaction.syncpkgs.values():
		if not pkg_object.name in transaction.localpkgs.keys():
			if not pkg_object.name in pkg_name_list:
				pkg_name_list.append(pkg_object.name)
				pkg_installed_dict[pkg_object.name] = False
				pkg_object_dict[pkg_object.name] = pkg_object

def set_list_dict_local():
	global pkg_name_list
	global pkg_object_dict
	global pkg_installed_dict
	pkg_name_list = []
	pkg_object_dict = {}
	pkg_installed_dict = {}
	for pkg_object in transaction.localpkgs.values():
		if (not pkg_object.name in pkg_name_list) and (not pkg_object.name in transaction.syncpkgs.keys()):
			pkg_name_list.append(pkg_object.name)
			pkg_installed_dict[pkg_object.name] = True
			pkg_object_dict[pkg_object.name] = pkg_object

def set_list_dict_orphans():
	global pkg_name_list
	global pkg_object_dict
	global pkg_installed_dict
	pkg_name_list = []
	pkg_object_dict = {}
	pkg_installed_dict = {}
	for pkg_object in transaction.localpkgs.values():
		if (pkg_object.reason == 1) and (not pkg_object.compute_requiredby()):
			pkg_name_list.append(pkg_object.name)
			pkg_installed_dict[pkg_object.name] = True
			pkg_object_dict[pkg_object.name] = pkg_object

def set_list_dict_to_install():
	global pkg_name_list
	global pkg_object_dict
	global pkg_installed_dict
	pkg_name_list = []
	pkg_object_dict = {}
	pkg_installed_dict = {}
	if transaction_type == "install":
		for pkg_object in transaction_dict.values():
			if not pkg_object.name in pkg_name_list:
				pkg_name_list.append(pkg_object.name)
				pkg_installed_dict[pkg_object.name] = False
				pkg_object_dict[pkg_object.name] = pkg_object

def set_list_dict_to_remove():
	global pkg_name_list
	global pkg_object_dict
	global pkg_installed_dict
	pkg_name_list = []
	pkg_object_dict = {}
	pkg_installed_dict = {}
	if transaction_type == "remove":
		for pkg_object in transaction_dict.values():
			if not pkg_object.name in pkg_name_list:
				pkg_name_list.append(pkg_object.name)
				pkg_installed_dict[pkg_object.name] = True
				pkg_object_dict[pkg_object.name] = pkg_object

def set_list_dict_repos(repo):
	global pkg_name_list
	global pkg_object_dict
	global pkg_installed_dict
	pkg_name_list = []
	pkg_object_dict = {}
	pkg_installed_dict = {}
	for db in  transaction.handle.get_syncdbs():
		if db.name == repo:
			for pkg_object in db.pkgcache:
				if not pkg_object.name in pkg_name_list:
					pkg_name_list.append(pkg_object.name)
				if pkg_object.name in transaction.localpkgs.keys():
					pkg_installed_dict[pkg_object.name] = True
					pkg_object_dict[pkg_object.name] = transaction.localpkgs[pkg_object.name]
				else:
					pkg_installed_dict[pkg_object.name] = False
					pkg_object_dict[pkg_object.name] = pkg_object

def refresh_packages_list():
	packages_list.clear()
	if not pkg_name_list:
		packages_list.append(["No package found", False, False, False, search_icon, '', 0])
	else:
		for name in pkg_name_list:
			if name in config.holdpkg:
				packages_list.append([name, True, False, True, locked_icon, '', 0])
			elif transaction_type is "install":
				if transaction.localpkgs.__contains__(name):
					packages_list.append([name, True, False, True, installed_icon, common.format_size(transaction.localpkgs[name].isize), transaction.localpkgs[name].isize])
				elif name in transaction_dict.keys():
					packages_list.append([name, False, True, True, to_install_icon, common.format_size(transaction.syncpkgs[name].isize), transaction.syncpkgs[name].isize])
				else:
					packages_list.append([name, False, True, False, uninstalled_icon, common.format_size(transaction.syncpkgs[name].isize), transaction.syncpkgs[name].isize])
			elif transaction_type is "remove":
				if not transaction.localpkgs.__contains__(name):
					packages_list.append([name, False, False, False, uninstalled_icon, common.format_size(transaction.syncpkgs[name].isize), transaction.syncpkgs[name].isize])
				elif name in transaction_dict.keys():
					packages_list.append([name, True, True, False, to_remove_icon, common.format_size(transaction.localpkgs[name].isize), transaction.localpkgs[name].isize])
				else:
					packages_list.append([name, True, True, True, installed_icon, common.format_size(transaction.localpkgs[name].isize), transaction.localpkgs[name].isize])
			elif transaction.localpkgs.__contains__(name):
				packages_list.append([name, True, True, True, installed_icon, common.format_size(transaction.localpkgs[name].isize), transaction.localpkgs[name].isize])
			else:
				packages_list.append([name, False, True, False, uninstalled_icon, common.format_size(transaction.syncpkgs[name].isize), transaction.syncpkgs[name].isize])

def set_packages_list():
	if current_filter[0] == 'search':
		set_list_dict_search(*current_filter[1])
	if current_filter[0] == 'group':
		set_list_dict_group(current_filter[1])
	if current_filter[0] == 'installed':
		set_list_dict_installed()
	if current_filter[0] == 'uninstalled':
		set_list_dict_uninstalled()
	if current_filter[0] == 'orphans':
		set_list_dict_orphans()
	if current_filter[0] == 'local':
		set_list_dict_local()
	if current_filter[0] == 'to_install':
		set_list_dict_to_install()
	if current_filter[0] == 'to_remove':
		set_list_dict_to_remove()
	if current_filter[0] == 'repo':
		set_list_dict_repos(current_filter[1])
	refresh_packages_list()

def set_desc(pkg, style):
	"""
	Args :
	  pkg_object -- the package to display
	  style -- 'local' or 'sync'
	"""

	if style not in ['local', 'sync', 'file']:
		raise ValueError('Invalid style for package info formatting')

	package_desc.clear()

	if style == 'sync':
		package_desc.append(['Repository:', pkg.db.name])
	package_desc.append(['Name:', pkg.name])
	package_desc.append(['Version:', pkg.version])
	package_desc.append(['Description:', pkg.desc])
	package_desc.append(['URL:', pkg.url])
	package_desc.append(['Licenses:', ' '.join(pkg.licenses)])
	package_desc.append(['Groups:', ' '.join(pkg.groups)])
	package_desc.append(['Provides:', ' '.join(pkg.provides)])
	package_desc.append(['Depends On:', ' '.join(pkg.depends)])
	package_desc.append(['Optional Deps:', '\n'.join(pkg.optdepends)])
	if style == 'local':
		package_desc.append(['Required By:', ' '.join(pkg.compute_requiredby())])
	package_desc.append(['Conflicts With:', ' '.join(pkg.conflicts)])
	package_desc.append(['Replaces:', ' '.join(pkg.replaces)])
	if style == 'sync':
		package_desc.append(['Compressed Size:', common.format_size(pkg.size)])
		package_desc.append(['Download Size:', common.format_size(pkg.download_size)])
	if style == 'local':
		package_desc.append(['Installed Size:', common.format_size(pkg.isize)])
	package_desc.append(['Packager:', pkg.packager])
	package_desc.append(['Architecture:', pkg.arch])
	#package_desc.append(['Build Date:', strftime("%a %d %b %Y %X %Z", localtime(pkg.builddate))])
	if style == 'local':
		#package_desc.append(['Install Date:', strftime("%a %d %b %Y %X %Z", localtime(pkg.installdate))])
		if pkg.reason == pyalpm.PKG_REASON_EXPLICIT:
			reason = 'Explicitly installed'
		elif pkg.reason == pyalpm.PKG_REASON_DEPEND:
			reason = 'Installed as a dependency for another package'
		else:
			reason = 'N/A'
		package_desc.append(['Install Reason:', reason])
	if style == 'sync':
		#package_desc.append(['Install Script:', 'Yes' if pkg.has_scriptlet else 'No'])
		#package_desc.append(['MD5 Sum:', pkg.md5sum])
		#package_desc.append(['SHA256 Sum:', pkg.sha256sum])
		package_desc.append(['Signatures:', 'Yes' if pkg.base64_sig else 'No'])
	if style == 'local':
		if len(pkg.backup) == 0:
			package_desc.append(['Backup files:', ''])
		else:
			#package_desc.append(['Backup files:', '\n'.join(["%s %s" % (md5, file) for (file, md5) in pkg.backup])])
			package_desc.append(['Backup files:', '\n'.join(["%s" % (file) for (file, md5) in pkg.backup])])

def set_transaction_sum():
	transaction_sum.clear()
	if transaction.to_remove:
		transaction.to_remove = sorted(transaction.to_remove)
		transaction_sum.append(['To remove:', transaction.to_remove[0]])
		i = 1
		while i < len(transaction.to_remove):
			transaction_sum.append([' ', transaction.to_remove[i]])
			i += 1
		sum_bottom_label.set_markup('')
	if transaction.to_add:
		transaction.to_add = sorted(transaction.to_add)
		installed = []
		for pkg_object in config.pacman_conf.initialize_alpm().get_localdb().pkgcache:
			installed.append(pkg_object.name)
		transaction.to_update = sorted(set(installed).intersection(transaction.to_add))
		to_remove_from_add = sorted(set(transaction.to_update).intersection(transaction.to_add))
		for name in to_remove_from_add:
			transaction.to_add.remove(name)
		if transaction.to_add:
			transaction_sum.append(['To install:', transaction.to_add[0]])
			i = 1
			while i < len(transaction.to_add):
				transaction_sum.append([' ', transaction.to_add[i]])
				i += 1
		if mode == 'manager':
			if transaction.to_update:
				transaction_sum.append(['To update:', transaction.to_update[0]])
				i = 1
				while i < len(transaction.to_update):
					transaction_sum.append([' ', transaction.to_update[i]])
					i += 1
		dsize = 0
		for name in transaction.to_add:
			dsize += transaction.syncpkgs[name].download_size
		sum_bottom_label.set_markup('<b>Total Download size: </b>'+common.format_size(dsize))
	sum_top_label.set_markup('<big><b>Transaction Summary</b></big>')

def handle_error(error):
	global transaction_type
	global transaction_dict
	ProgressWindow.hide()
	#while Gtk.events_pending():
	#	Gtk.main_iteration()
	if error:
		if not 'DBus.Error.NoReply' in str(error):
			print('error:', error)
			transaction.ErrorDialog.format_secondary_text(error)
			response = transaction.ErrorDialog.run()
			if response:
				transaction.ErrorDialog.hide()
	transaction.t_lock = False
	transaction.Release()
	if mode == 'manager':
		transaction.to_add = []
		transaction.to_remove = []
		transaction_dict.clear()
		transaction_type = None
		transaction.get_handle()
		transaction.update_db()
		refresh_packages_list()
	if mode == 'updater':
		have_updates()

def handle_reply(reply):
	global transaction_type
	global transaction_dict
	ProgressWindow.hide()
	#while Gtk.events_pending():
	#	Gtk.main_iteration()
	if reply:
		transaction.InfoDialog.format_secondary_text(reply)
		response = transaction.InfoDialog.run()
		if response:
			transaction.InfoDialog.hide()
	transaction.t_lock = False
	try:
		transaction.Release()
	except:
		pass
	transaction.to_add = []
	transaction.to_remove = []
	transaction_dict.clear()
	transaction.get_handle()
	transaction.update_db()
	if (transaction_type == "install") or (transaction_type == "remove"):
		transaction_type = None
		refresh_packages_list()
	else:
		transaction_type = None
	if have_updates():
		if mode == 'manager':
			do_sysupgrade()

bus.add_signal_receiver(handle_reply, dbus_interface = "org.manjaro.pamac", signal_name = "EmitTransactionDone")
bus.add_signal_receiver(handle_error, dbus_interface = "org.manjaro.pamac", signal_name = "EmitTransactionError")

def do_refresh():
	"""Sync databases like pacman -Sy"""
	if transaction.t_lock is False:
		transaction.t_lock = True
		progress_label.set_text('Refreshing...')
		action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/refresh-cache.png')
		progress_bar.set_text('')
		progress_bar.set_fraction(0)
		ProgressWindow.show_all()
		while Gtk.events_pending():
			Gtk.main_iteration()
		transaction.Refresh()#reply_handler = handle_reply, error_handler = handle_error, timeout = 2000*1000)

def have_updates():
	do_syncfirst, updates = transaction.get_updates()
	update_listore.clear()
	update_top_label.set_justify(Gtk.Justification.CENTER)
	if not updates:
		update_listore.append(['', ''])
		update_bottom_label.set_markup('')
		update_top_label.set_markup('<big><b>No update available</b></big>')
		return False
	else:
		dsize = 0
		for pkg in updates:
			pkgname = pkg.name+" "+pkg.version
			update_listore.append([pkgname, common.format_size(pkg.size)])
			dsize += pkg.download_size
		update_bottom_label.set_markup('<b>Total Download size: </b>'+common.format_size(dsize))
		update_top_label.set_markup('<big><b>Available updates</b></big>')
		return True

def do_sysupgrade():
	global transaction_type
	"""Upgrade a system like pacman -Su"""
	if transaction.t_lock is False:
		transaction_type = "update"
		do_syncfirst, updates = transaction.get_updates()
		if updates:
			transaction.to_add = []
			transaction.to_remove = []
			if do_syncfirst:
				check_conflicts('normal', updates)
				for pkg in updates:
					transaction.to_add.append(pkg.name)
				if transaction.init_transaction(recurse = True, needed = True):
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
						set_transaction_sum()
						if mode == 'updater':
							if len(transaction.to_add) + len(transaction.to_remove) != 0:
								ConfDialog.show_all()
							else:
								finalize()
						if mode == 'manager':
							ConfDialog.show_all()
			else:
				check_conflicts('updating', updates)
				if transaction.init_transaction(noconflicts = True):
					error = transaction.Sysupgrade()
					if error:
						handle_error(error)
					else:
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
							set_transaction_sum()
							if mode == 'updater':
								if len(transaction.to_add) + len(transaction.to_remove) != 0:
									ConfDialog.show_all()
								else:
									finalize()
							if mode == 'manager':
								ConfDialog.show_all()

def finalize():
		progress_label.set_text('Preparing...')
		action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/setup.png')
		progress_bar.set_text('')
		progress_bar.set_fraction(0)
		ProgressWindow.show_all()
		while Gtk.events_pending():
			Gtk.main_iteration()
		transaction.Commit()#reply_handler = handle_reply, error_handler = handle_error, timeout = 2000*1000)

def check_conflicts(mode, pkg_list):
	depends = [pkg_list]
	warning = ''
	error = ''
	pkgs = transaction.handle.get_localdb().search('linux3')
	installed_linux = []
	for item in pkgs:
		if len(item.name) == 7:
			installed_linux.append(item.name)
	for to_install in transaction.to_add:
		if 'linux3' in to_install:
			if len(to_install) == 7:
				installed_linux.append(to_install)
	i = 0
	while depends[i]:
		depends.append([])
		for pkg in depends[i]:
			if 'linux3' in pkg.name:
				for _pkg in transaction.localpkgs.values():
					for depend in _pkg.depends:
						if '-modules' in depend:
							for __pkg in transaction.syncpkgs.values():
								if not __pkg.name in transaction.localpkgs.keys():
									for name in __pkg.provides:
										for linux in installed_linux:
											if linux in __pkg.name:
												if common.format_pkg_name(depend) == common.format_pkg_name(name):
													if not __pkg.name in transaction.to_add:
														print(i,'module',__pkg)
														depends[i+1].append(__pkg)
														transaction.to_add.append(__pkg.name)
			for depend in pkg.depends:
				provide = pyalpm.find_satisfier(transaction.localpkgs.values(), depend)
				if provide:
					print(i,'local',provide)
					if provide.name != common.format_pkg_name(depend):
						if ('-modules' in depend) or ('linux' in depend):
							for _pkg in transaction.syncpkgs.values():
								if not _pkg.name in transaction.localpkgs.keys():
									for name in _pkg.provides:
										for linux in installed_linux:
											if linux in _pkg.name:
												if common.format_pkg_name(depend) == common.format_pkg_name(name):
													if not _pkg.name in transaction.to_add:
														depends[i+1].append(_pkg)
														transaction.to_add.append(_pkg.name)
				else:
					provide = pyalpm.find_satisfier(transaction.syncpkgs.values(), depend)
					if provide:
						print(i,'sync',provide)
						if provide.name != common.format_pkg_name(depend):
							if ('-modules' in depend) or ('linux' in depend):
								for _pkg in transaction.syncpkgs.values():
									if not _pkg.name in transaction.localpkgs.keys():
										for name in _pkg.provides:
											for linux in installed_linux:
												if linux in _pkg.name:
													if common.format_pkg_name(depend) == common.format_pkg_name(name):
														if not _pkg.name in transaction.to_add:
															depends[i+1].append(_pkg)
															transaction.to_add.append(_pkg.name)
							else:
								already_provided = False
								for pkgname in transaction.to_add:
									_pkg = transaction.syncpkgs[pkgname]
									provide = pyalpm.find_satisfier([_pkg], depend)
									if provide:
										already_provided = True
								if not already_provided:
									to_add_to_depends = choose_provides(depend)
									for _pkg in to_add_to_depends:
										if not _pkg.name in transaction.to_add:
											depends[i+1].append(_pkg)
											transaction.to_add.append(_pkg.name)
						else:
							depends[i+1].append(provide)
			if mode == 'updating':
				for replace in pkg.replaces:
					provide = pyalpm.find_satisfier(transaction.localpkgs.values(), replace)
					if provide:
						if provide.name != pkg.name:
							if not provide.name in transaction.to_remove:
								transaction.to_remove.append(provide.name)
								if warning:
									warning += '\n'
								warning += provide.name+' will be replaced by '+pkg.name
			for conflict in pkg.conflicts:
				provide = pyalpm.find_satisfier(transaction.localpkgs.values(), conflict)
				if provide:
					if provide.name != pkg.name:
						if transaction.syncpkgs.__contains__(provide.name):
							new_provide = pyalpm.find_satisfier([transaction.syncpkgs[provide.name]], conflict)
							if new_provide:
								required = pkg.compute_requiredby()
								if required:
									str_required = ''
									for item in required:
										if str_required:
											str_required += ', '
										str_required += item
									if error:
										error += '\n'
									error += '{} conflicts with {} but cannot be removed because it is needed by {}'.format(provide.name, pkg.name, str_required)
								elif not provide.name in transaction.to_remove:
									transaction.to_remove.append(provide.name)
									if warning:
										warning += '\n'
									warning += pkg.name+' conflicts with '+provide.name
				provide = pyalpm.find_satisfier(depends[0], conflict)
				if provide:
					if not common.format_pkg_name(conflict) == pkg.name:
						if not common.format_pkg_name(conflict) in transaction.to_remove:
							if pkg.name in transaction.to_add and common.format_pkg_name(conflict) in transaction.to_add:
								transaction.to_add.remove(common.format_pkg_name(conflict))
								transaction.to_add.remove(pkg.name)
								if warning:
									warning += '\n'
								warning += pkg.name+' conflicts with '+common.format_pkg_name(conflict)+'\nNone of them will be installed'
		i += 1
	for pkg in transaction.localpkgs.values():
		for conflict in pkg.conflicts:
			provide = pyalpm.find_satisfier(depends[0], conflict)
			if provide:
				if provide.name != pkg.name:
					if transaction.syncpkgs.__contains__(pkg.name):
						new_provide = pyalpm.find_satisfier([transaction.syncpkgs[pkg.name]], conflict)
						if new_provide:
							required = pkg.compute_requiredby()
							if required:
								str_required = ''
								for item in required:
									if str_required:
										str_required += ', '
									str_required += item
								if error:
									error += '\n'
								error += '{} conflicts with {} but cannot be removed because it is needed by {}'.format(provide.name, pkg.name, str_required)
							elif not provide.name in transaction.to_remove:
								transaction.to_remove.append(pkg.name)
								if warning:
									warning += '\n'
								warning += provide.name+' conflicts with '+pkg.name
	if mode == 'updating':
		for pkg in transaction.syncpkgs.values():
			for replace in pkg.replaces:
				provide = pyalpm.find_satisfier(transaction.localpkgs.values(), replace)
				if provide:
					if not common.format_pkg_name(replace) in transaction.syncpkgs.keys():
						if provide.name != pkg.name:
							if not pkg.name in transaction.localpkgs.keys():
								if common.format_pkg_name(replace) in transaction.localpkgs.keys():
									if not provide.name in transaction.to_remove:
										transaction.to_remove.append(provide.name)
										if warning:
											warning += '\n'
										warning += provide.name+' will be replaced by '+pkg.name
									if not pkg.name in transaction.to_add:
										transaction.to_add.append(pkg.name)
	print('check result:', 'to add:', transaction.to_add, 'to remove:', transaction.to_remove)
	if warning:
		transaction.WarningDialog.format_secondary_text(warning)
		response = transaction.WarningDialog.run()
		if response:
			transaction.WarningDialog.hide()
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
		choose_label.set_markup('<b>{} is provided by {} packages.\nPlease choose the one(s) you want to install:</b>'.format(name,str(len(provides.keys()))))
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
		if not transaction_dict:
			transaction.ErrorDialog.format_secondary_text("No package is selected")
			response = 	transaction.ErrorDialog.run()
			if response:
				transaction.ErrorDialog.hide()
		else:
			if transaction.t_lock is True:
				print('Transaction locked')
			else:
				if transaction_type is "remove":
					if transaction.init_transaction(cascade = True, recurse = True):
						for pkgname in transaction_dict.keys():
							transaction.Remove(pkgname)
						error = transaction.Prepare()
						if error:
							handle_error(error)
						else:
							transaction.get_to_remove()
							transaction.get_to_add()
							set_transaction_sum()
							ConfDialog.show_all()
				if transaction_type is "install":
					transaction.to_add = []
					for pkgname in transaction_dict.keys():
						transaction.to_add.append(pkgname)
					transaction.to_remove = []
					check_conflicts('normal', transaction_dict.values())
					if transaction.to_add:
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
								set_transaction_sum()
								ConfDialog.show_all()
					else:
						transaction.WarningDialog.format_secondary_text('Nothing to do')
						response = transaction.WarningDialog.run()
						if response:
							transaction.WarningDialog.hide()
						transaction.t_lock = False

	def on_Manager_EraseButton_clicked(self, *arg):
		global transaction_type
		global transaction_dict
		transaction_dict.clear()
		if transaction_type:
			transaction_type = None
			refresh_packages_list()

	def on_Manager_RefreshButton_clicked(self, *arg):
		do_refresh()

	def on_TransCancelButton_clicked(self, *arg):
		global transaction_type
		ProgressWindow.hide()
		ConfDialog.hide()
		transaction.t_lock = False
		transaction.Release()
		if transaction_type == "update":
			transaction_type = None

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
		if line is not None:
			if packages_list[line][0] in pkg_object_dict.keys():
				pkg_object = pkg_object_dict[packages_list[line][0]]
				if pkg_installed_dict[packages_list[line][0]] is True:
					style = "local"
				else:
					style = "sync"
				set_desc(pkg_object, style)

	def on_search_treeview_selection_changed(self, widget):
		global current_filter
		liste, line = search_selection.get_selected()
		if line is not None:
			current_filter = ('search', search_list[line][0].split())
			set_packages_list()

	def on_groups_treeview_selection_changed(self, widget):
		global current_filter
		liste, line = groups_selection.get_selected()
		if line is not None:
			current_filter = ('group', groups_list[line][0])
			set_packages_list()

	def on_state_treeview_selection_changed(self, widget):
		global current_filter
		liste, line = state_selection.get_selected()
		if line is not None:
			if state_list[line][0] == 'Installed':
				current_filter = ('installed', None)
			if state_list[line][0] == 'Uninstalled':
				current_filter = ('uninstalled', None)
			if state_list[line][0] == 'Orphans':
				current_filter = ('orphans', None)
			if state_list[line][0] == 'To install':
				current_filter = ('to_install', None)
			if state_list[line][0] == 'To remove':
				current_filter = ('to_remove', None)
			set_packages_list()

	def on_repos_treeview_selection_changed(self, widget):
		global current_filter
		liste, line = repos_selection.get_selected()
		if line is not None:
			if repos_list[line][0] == 'local':
				current_filter = ('local', None)
			else:
				current_filter = ('repo', repos_list[line][0])
			set_packages_list()

	def on_cellrenderertoggle1_toggled(self, widget, line):
		global transaction_type
		global transaction_dict
		global pkg_object_dict
		if packages_list[line][0] in transaction_dict.keys():
			if transaction_type == "remove":
				packages_list[line][4] = installed_icon
			if transaction_type == "install":
				packages_list[line][4] = uninstalled_icon
			transaction_dict.pop(packages_list[line][0])
			if not transaction_dict:
				transaction_type = None
				lin = 0
				while lin <  len(packages_list):
					if packages_list[lin][0] in config.holdpkg:
						packages_list[lin][2] = False
					else:
						packages_list[lin][2] = True
					lin += 1
		else:
			if packages_list[line][1] is True:
				transaction_type = "remove"
				transaction_dict[packages_list[line][0]] = pkg_object_dict[packages_list[line][0]]
				packages_list[line][4] = to_remove_icon
				lin = 0
				while lin <  len(packages_list):
					if not packages_list[lin][0] in transaction_dict.keys():
						if packages_list[lin][1] is False:
							packages_list[lin][2] = False
					lin += 1
			if packages_list[line][1] is False:
				transaction_type = "install"
				transaction_dict[packages_list[line][0]] = pkg_object_dict[packages_list[line][0]]
				packages_list[line][4] = to_install_icon
				lin = 0
				while lin <  len(packages_list):
					if not packages_list[lin][0] in transaction_dict.keys():
						if packages_list[lin][1] is True:
							packages_list[lin][2] = False
					lin += 1
		packages_list[line][3] = not packages_list[line][3]
		packages_list[line][2] = True

	def on_cellrenderertoggle2_toggled(self, widget, line):
		choose_list[line][0] = not choose_list[line][0]

	def on_ChooseButton_clicked(self, *arg):
		ChooseDialog.hide()
		line = 0
		transaction.to_provide = []
		while line <  len(choose_list):
			if choose_list[line][0] is True:
				if not choose_list[line][1] in transaction.to_provide:
					if not choose_list[line][1] in transaction.localpkgs.keys():
						transaction.to_provide.append(choose_list[line][1])
			if choose_list[line][0] is False:
				if choose_list[line][1] in transaction.to_provide:
					transaction.to_provide.remove(choose_list[line][1])
			line += 1

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

	def on_ProgressCancelButton_clicked(self, *arg):
		print('cancelled')
		error = transaction.Interrupt()
		if error:
			handle_error(error)
		else:
			handle_reply('')

def main(_mode):
	if common.pid_file_exists():
		transaction.ErrorDialog.format_secondary_text('Another instance of Pamac is running')
		response = transaction.ErrorDialog.run()
		if response:
			transaction.ErrorDialog.hide()
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
			update_top_label.set_markup('<big><b>Available updates</b></big>')
			update_bottom_label.set_markup('')
			UpdaterWindow.show_all()
		while Gtk.events_pending():
			Gtk.main_iteration()
		Gtk.main()
