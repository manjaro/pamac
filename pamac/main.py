#! /usr/bin/python
# -*-coding:utf-8 -*-

from gi.repository import Gtk

import pyalpm
import dbus
from collections import OrderedDict
from time import strftime, localtime

from pamac import config, common, transaction

interface = Gtk.Builder()

interface.add_from_file('/usr/share/pamac/gui/dialogs.glade')
ErrorDialog = interface.get_object('ErrorDialog')
WarningDialog = interface.get_object('WarningDialog')
QuestionDialog = interface.get_object('QuestionDialog')

interface.add_from_file('/usr/share/pamac/gui/manager.glade')
ManagerWindow = interface.get_object("ManagerWindow")
packages_list = interface.get_object('packages_list')
groups_list = interface.get_object('groups_list')
package_desc = interface.get_object('package_desc')
toggle = interface.get_object('cellrenderertoggle1')
search_entry = interface.get_object('search_entry')
tree2 = interface.get_object('treeview2_selection')
tree1 = interface.get_object('treeview1_selection')
installed_column = interface.get_object('installed_column')
name_column = interface.get_object('name_column')
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
update_label = interface.get_object('update_label')

def action_signal_handler(action):
	progress_label.set_text(action)
	#if 'Downloading' in action:
	#	print('cancel enabled')
	#	ProgressCancelButton.set_visible(True)
	#else:
	ProgressCancelButton.set_visible(False)
	#print('cancel disabled')

def icon_signal_handler(icon):
	action_icon.set_from_file(icon)

def target_signal_handler(target):
	progress_bar.set_text(target)

def percent_signal_handler(percent):
	if percent == '0':
		progress_bar.pulse()
	else:
		progress_bar.set_fraction(float(percent))

bus = dbus.SystemBus()
bus.add_signal_receiver(action_signal_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitAction")
bus.add_signal_receiver(icon_signal_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitIcon")
bus.add_signal_receiver(target_signal_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitTarget")
bus.add_signal_receiver(percent_signal_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitPercent")

installed_column.set_sort_column_id(1)
name_column.set_sort_column_id(0)

pkg_name_list = []
pkg_object_dict = {}
pkg_installed_dict = {}
list_dict = None
current_group = None
transaction_type = None
transaction_dict = {}
mode = None

def get_groups():
	tmp_list = []
	for repo in transaction.handle.get_syncdbs():
		for name, pkgs in repo.grpcache:
			if not name in tmp_list:
				tmp_list.append(name)
	tmp_list = sorted(tmp_list)
	for name in tmp_list:
		groups_list.append([name])

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

def refresh_packages_list():
	global packages_list
	packages_list.clear()
	if not pkg_name_list:
		packages_list.append(["No package found", False, False])
	else:
		for name in pkg_name_list:
			if name in config.holdpkg:
				packages_list.append([name, pkg_installed_dict[name], False])
			elif transaction_type is "install":
				if pkg_installed_dict[name] is True:
					packages_list.append([name, pkg_installed_dict[name], False])
				elif name in transaction_dict.keys():
					packages_list.append([name, True, True])
				else:
					packages_list.append([name, pkg_installed_dict[name], True])
			elif transaction_type is "remove":
				if pkg_installed_dict[name] is False:
					packages_list.append([name, pkg_installed_dict[name], False])
				elif name in transaction_dict.keys():
					packages_list.append([name, False, True])
				else:
					packages_list.append([name, pkg_installed_dict[name], True])
			else:
				packages_list.append([name, pkg_installed_dict[name], True])

def set_packages_list():
	global list_dict
	if list_dict == "search":
		search_strings_list = search_entry.get_text().split()
		set_list_dict_search(*search_strings_list)
	if list_dict == "group":
		set_list_dict_group(current_group)
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
		package_desc.append(['Download Size:', common.format_size(pkg.size)])
	if style == 'file':
		package_desc.append(['Compressed Size:', common.format_size(pkg.size)])
	package_desc.append(['Installed Size:', common.format_size(pkg.isize)])
	package_desc.append(['Packager:', pkg.packager])
	package_desc.append(['Architecture:', pkg.arch])
	package_desc.append(['Build Date:', strftime("%a %d %b %Y %X %Z", localtime(pkg.builddate))])

	if style == 'local':
		package_desc.append(['Install Date:', strftime("%a %d %b %Y %X %Z", localtime(pkg.installdate))])
		if pkg.reason == pyalpm.PKG_REASON_EXPLICIT:
			reason = 'Explicitly installed'
		elif pkg.reason == pyalpm.PKG_REASON_DEPEND:
			reason = 'Installed as a dependency for another package'
		else:
			reason = 'N/A'
		package_desc.append(['Install Reason:', reason])
	if style != 'sync':
		package_desc.append(['Install Script:', 'Yes' if pkg.has_scriptlet else 'No'])
	if style == 'sync':
		package_desc.append(['MD5 Sum:', pkg.md5sum])
		package_desc.append(['SHA256 Sum:', pkg.sha256sum])
		package_desc.append(['Signatures:', 'Yes' if pkg.base64_sig else 'No'])

	if style == 'local':
		if len(pkg.backup) == 0:
			package_desc.append(['Backup files:', ''])
		else:
			package_desc.append(['Backup files:', '\n'.join(["%s %s" % (md5, file) for (file, md5) in pkg.backup])])

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
		sum_bottom_label.set_markup('')
		#sum_bottom_label.set_markup('<b>Total Download size: </b>'+common.format_size(totaldlcb))
	sum_top_label.set_markup('<big><b>Transaction Summary</b></big>')

def handle_error(error):
	global transaction_type
	global transaction_dict
	if error:
		if not 'DBus.Error.NoReply' in error:
			print('error',error)
			transaction.ErrorDialog.format_secondary_text(error)
			response = transaction.ErrorDialog.run()
			if response:
				transaction.ErrorDialog.hide()
	transaction.t_lock = False
	transaction.Release()
	ProgressWindow.hide()
	if mode == 'manager':
		transaction.to_add = []
		transaction.to_remove = []
		transaction_dict.clear()
		transaction_type = None
		transaction.update_db()
		get_groups()
		set_packages_list()
	if mode == 'updater':
		have_updates()
	print('error',error)

def handle_reply(reply):
	global transaction_type
	global transaction_dict
	if reply:
		transaction.ErrorDialog.format_secondary_text(reply)
		response = transaction.ErrorDialog.run()
		if response:
			transaction.ErrorDialog.hide()
	transaction.t_lock = False
	transaction.Release()
	ProgressWindow.hide()
	transaction.to_add = []
	transaction.to_remove = []
	transaction_dict.clear()
	transaction.update_db()
	get_groups()
	if (transaction_type == "install") or (transaction_type == "remove"):
		transaction_type = None
		set_packages_list()
	else:
		transaction_type = None
	if have_updates():
		if mode == 'manager':
			do_sysupgrade()

def do_refresh():
	"""Sync databases like pacman -Sy"""
	if transaction.t_lock is False:
		transaction.t_lock = True
		progress_label.set_text('Refreshing...')
		action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/refresh-cache.png')
		ProgressWindow.show_all()
		while Gtk.events_pending():
			Gtk.main_iteration()
		transaction.Refresh(reply_handler = handle_reply, error_handler = handle_error, timeout = 2000*1000)

def have_updates():
	do_syncfirst, updates = transaction.get_updates()
	update_listore.clear()
	update_label.set_justify(Gtk.Justification.CENTER)
	if not updates:
		update_listore.append(["", ""])
		update_label.set_markup("<big><b>No update available</b></big>")
		return False
	else:
		for pkg in updates:
			pkgname = pkg.name+" "+pkg.version
			update_listore.append([pkgname, common.format_size(pkg.size)])
		update_label.set_markup("<big><b>Available updates</b></big>")
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
			check_conflicts(updates)
			if do_syncfirst:
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
		ProgressWindow.show_all()
		while Gtk.events_pending():
			Gtk.main_iteration()
		transaction.Commit(reply_handler = handle_reply, error_handler = handle_error, timeout = 2000*1000)

def check_conflicts(pkg_list):
	depends = [pkg_list]
	warning = ''
	error = ''
	pkgs = transaction.handle.get_localdb().search('linux3')
	installed_linux = []
	for i in pkgs:
		if len(i.name) == 7:
			installed_linux.append(i.name)
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
									print('test',transaction.to_add)
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
			for replace in pkg.replaces:
				provide = pyalpm.find_satisfier(transaction.localpkgs.values(), replace)
				if provide:
					if provide.name != pkg.name:
						if not provide.name in transaction.to_remove:
							transaction.to_remove.append(provide.name)
							if warning:
								warning = warning+'\n'
							warning = warning+provide.name+' will be replaced by '+pkg.name
			for conflict in pkg.conflicts:
				provide = pyalpm.find_satisfier(transaction.localpkgs.values(), conflict)
				if provide:
					if provide.name != pkg.name:
						if not provide.name in transaction.to_remove:
							transaction.to_remove.append(provide.name)
							if warning:
								warning = warning+'\n'
							warning = warning+pkg.name+' conflicts with '+provide.name
				provide = pyalpm.find_satisfier(depends[0], conflict)
				if provide:
					if not common.format_pkg_name(conflict) == pkg.name:
						if not common.format_pkg_name(conflict) in transaction.to_remove:
							if pkg.name in transaction.to_add and common.format_pkg_name(conflict) in transaction.to_add:
								transaction.to_add.remove(common.format_pkg_name(conflict))
								transaction.to_add.remove(pkg.name)
								if warning:
									warning = warning+'\n'
								warning = warning+pkg.name+' conflicts with '+common.format_pkg_name(conflict)+'\nNone of them will be installed'
		i += 1
	for pkg in transaction.localpkgs.values():
		for conflict in pkg.conflicts:
			provide = pyalpm.find_satisfier(depends[0], conflict)
			if provide:
				if provide.name != pkg.name:
					if not provide.name in transaction.to_remove:
						transaction.to_remove.append(pkg.name)
						if warning:
							warning = warning+'\n'
						warning = warning+provide.name+' conflicts with '+pkg.name
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
										warning = warning+'\n'
									warning = warning+provide.name+' will be replaced by '+pkg.name
								if not pkg.name in transaction.to_add:
									transaction.to_add.append(pkg.name)
	print(transaction.to_add,transaction.to_remove)
	if warning:
		transaction.WarningDialog.format_secondary_text(warning)
		response = transaction.WarningDialog.run()
		if response:
			transaction.WarningDialog.hide()
	pkg_list = {}
	for pkgname in transaction.to_remove:
		pkg_list[pkgname] = transaction.localpkgs[pkgname]
	for pkgname in transaction.to_add:
		pkg = transaction.syncpkgs[pkgname]
		for replace in pkg.replaces:
			provide = pyalpm.find_satisfier(pkg_list.values(), replace)
			if provide:
				pkg_list.pop(provide.name)
	for pkg in pkg_list.values():
		required = pkg.compute_requiredby()
		if required:
			str_required = ''
			for i in required:
				if str_required:
					str_required += ', '
				str_required += i
			if error:
				error = error+'\n'
			error += 'Cannot remove {} because it is needed by {}'.format(pkgname, str_required)
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
					check_conflicts(transaction_dict.values())
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
		set_packages_list()

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

	def on_search_button_clicked(self, widget):
		global list_dict
		list_dict = "search"
		set_packages_list()

	def on_search_entry_icon_press(self, *arg):
		global list_dict
		list_dict = "search"
		set_packages_list()

	def on_search_entry_activate(self, widget):
		global list_dict
		list_dict = "search"
		set_packages_list()

	def on_treeview2_selection_changed(self, widget):
		liste, line = tree2.get_selected()
		if line is not None:
			if packages_list[line][0] in pkg_object_dict.keys():
				pkg_object = pkg_object_dict[packages_list[line][0]]
				if pkg_installed_dict[packages_list[line][0]] is True:
					style = "local"
				else:
					style = "sync"
				set_desc(pkg_object, style)

	def on_treeview1_selection_changed(self, widget):
		global list_dict
		global current_group
		liste, line = tree1.get_selected()
		if line is not None:
			list_dict = "group"
			current_group = groups_list[line][0]
			set_packages_list()

	def on_installed_column_clicked(self, widget):
		installed_column.set_sort_column_id(1)

	def on_name_column_clicked(self, widget):
		name_column.set_sort_column_id(0)

	def on_cellrenderertoggle1_toggled(self, widget, line):
		global transaction_type
		global transaction_dict
		global pkg_object_dict
		if packages_list[line][0] in transaction_dict.keys():
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
			pass
		else:
			if packages_list[line][1] is True:
				transaction_type = "remove"
				transaction_dict[packages_list[line][0]] = pkg_object_dict[packages_list[line][0]]
				lin = 0
				while lin <  len(packages_list):
					if not packages_list[lin][0] in transaction_dict.keys():
						if packages_list[lin][1] is False:
							packages_list[lin][2] = False
					lin += 1
			if packages_list[line][1] is False:
				transaction_type = "install"
				transaction_dict[packages_list[line][0]] = pkg_object_dict[packages_list[line][0]]
				lin = 0
				while lin <  len(packages_list):
					if not packages_list[lin][0] in transaction_dict.keys():
						if packages_list[lin][1] is True:
							packages_list[lin][2] = False
					lin += 1
		packages_list[line][1] = not packages_list[line][1]
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
		#handle_reply('')

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
		if mode == 'manager':
			ManagerWindow.show_all()
		if mode == 'updater':
			update_label.set_markup("<big><b>Available updates</b></big>")
			UpdaterWindow.show_all()
		while Gtk.events_pending():
			Gtk.main_iteration()
		Gtk.main()
