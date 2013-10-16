#! /usr/bin/python3
# -*- coding:utf-8 -*-

version = '0.9'

from gi.repository import Gtk, Gdk
from gi.repository.GdkPixbuf import Pixbuf
import pyalpm
import dbus
from time import strftime, localtime

from pamac import config, common, transaction

# i18n
import gettext
import locale
locale.bindtextdomain('pamac', '/usr/share/locale')
gettext.bindtextdomain('pamac', '/usr/share/locale')
gettext.textdomain('pamac')
_ = gettext.gettext

interface = transaction.interface

interface.add_from_file('/usr/share/pamac/gui/manager.ui')
ManagerWindow = interface.get_object("ManagerWindow")
details_list = interface.get_object('details_list')
deps_list = interface.get_object('deps_list')
files_textview = interface.get_object('files_textview')
files_scrolledwindow = interface.get_object('files_scrolledwindow')
name_label = interface.get_object('name_label')
desc_label = interface.get_object('desc_label')
link_label = interface.get_object('link_label')
licenses_label = interface.get_object('licenses_label')
search_entry = interface.get_object('search_entry')
search_list = interface.get_object('search_list')
search_selection = interface.get_object('search_treeview_selection')
packages_list_treeview = interface.get_object('packages_list_treeview')
state_column = interface.get_object('state_column')
name_column = interface.get_object('name_column')
version_column = interface.get_object('version_column')
size_column = interface.get_object('size_column')
state_rendererpixbuf = interface.get_object('state_rendererpixbuf')
name_renderertext = interface.get_object('name_renderertext')
version_renderertext = interface.get_object('version_renderertext')
size_renderertext = interface.get_object('size_renderertext')
list_selection = interface.get_object('list_treeview_selection')
groups_list = interface.get_object('groups_list')
groups_selection = interface.get_object('groups_treeview_selection')
states_list = interface.get_object('states_list')
states_selection = interface.get_object('states_treeview_selection')
repos_list = interface.get_object('repos_list')
repos_selection = interface.get_object('repos_treeview_selection')
AboutDialog = interface.get_object('AboutDialog')
PackagesChooserDialog = interface.get_object('PackagesChooserDialog')

files_buffer = files_textview.get_buffer()
AboutDialog.set_version(version)

search_dict = {}
groups_dict = {}
states_dict = {}
repos_dict = {}
current_filter = (None, None)
right_click_menu = Gtk.Menu()

installed_icon = Pixbuf.new_from_file('/usr/share/pamac/icons/16x16/actions/package-installed-updated.png')
uninstalled_icon = Pixbuf.new_from_file('/usr/share/pamac/icons/16x16/actions/package-available.png')
to_install_icon = Pixbuf.new_from_file('/usr/share/pamac/icons/16x16/actions/package-install.png')
to_reinstall_icon = Pixbuf.new_from_file('/usr/share/pamac/icons/16x16/actions/package-reinstall.png')
to_remove_icon = Pixbuf.new_from_file('/usr/share/pamac/icons/16x16/actions/package-remove.png')
locked_icon = Pixbuf.new_from_file('/usr/share/pamac/icons/16x16/actions/package-installed-locked.png')

def state_column_display_func(column, cell, treemodel, treeiter, data):
	if treemodel[treeiter][0] == _('No package found'):
		pixbuf = None
	elif treemodel[treeiter][0].name in config.holdpkg:
		pixbuf = locked_icon
	elif treemodel[treeiter][0].db.name == 'local':
		if treemodel[treeiter][0].name in transaction.to_add:
			pixbuf = to_reinstall_icon
		elif treemodel[treeiter][0].name in transaction.to_remove:
			pixbuf = to_remove_icon
		else:
			pixbuf = installed_icon
	elif treemodel[treeiter][0].name in transaction.to_add:
		pixbuf = to_install_icon
	else:
		pixbuf = uninstalled_icon
	cell.set_property("pixbuf", pixbuf)

def state_column_sort_func(treemodel, treeiter1, treeiter2, data):
	if treemodel[treeiter1][0].db.name == 'local':
		num1 = 1
	else:
		num1 = 0
	if treemodel[treeiter2][0].db.name == 'local':
		num2 = 1
	else:
		num2 = 0
	return num2 - num1

def name_column_display_func(column, cell, treemodel, treeiter, data):
	if treemodel[treeiter][0] == _('No package found'):
		cell.set_property("text", _('No package found'))
	else:
		cell.set_property("text", treemodel[treeiter][0].name)

def name_column_sort_func(treemodel, treeiter1, treeiter2, data):
	str1 = treemodel[treeiter1][0].name
	str2 = treemodel[treeiter2][0].name
	if str1 < str2:
		return -1
	elif str1 > str2:
		return 1
	else:
		return 0

def version_column_display_func(column, cell, treemodel, treeiter, data):
	if treemodel[treeiter][0] == _('No package found'):
		cell.set_property("text", '')
	else:
		cell.set_property("text", treemodel[treeiter][0].version)

def version_column_sort_func(treemodel, treeiter1, treeiter2, data):
	return pyalpm.vercmp(treemodel[treeiter1][0].version, treemodel[treeiter2][0].version)

def size_column_display_func(column, cell, treemodel, treeiter, data):
	if treemodel[treeiter][0] == _('No package found'):
		cell.set_property("text", '')
	else:
		cell.set_property("text", common.format_size(treemodel[treeiter][0].isize))

def size_column_sort_func(treemodel, treeiter1, treeiter2, data):
	num1 = treemodel[treeiter1][0].isize
	num2 = treemodel[treeiter2][0].isize
	return num1 - num2

def update_lists():
	for db in transaction.syncdbs:
		repos_list.append([db.name])
		for name, pkgs in db.grpcache:
			groups_list.append([name])
	repos_list.append([_('local')])
	groups_list.set_sort_column_id(0, Gtk.SortType.ASCENDING)
	states = [_('Installed'), _('Uninstalled'), _('Orphans'), _('To install'), _('To remove')]
	for state in states:
		states_list.append([state])

def get_group_list(group):
	global groups_dict
	if group in groups_dict.keys():
		return groups_dict[group]
	else:
		groups_dict[group] = Gtk.ListStore(object)
		dbs_list = [transaction.localdb]
		dbs_list.extend(transaction.syncdbs.copy())
		pkgs = pyalpm.find_grp_pkgs(dbs_list, group)
		for pkg in pkgs:
			groups_dict[group].append([pkg])
		return groups_dict[group]

def get_state_list(state):
	global states_dict
	if state == _('To install'):
		liststore = Gtk.ListStore(object)
		for pkg in transaction.to_add:
			liststore.append([pkg])
		return liststore
	elif state == _('To remove'):
		liststore = Gtk.ListStore(object)
		for pkg in transaction.to_remove:
			liststore.append([pkg])
		return liststore
	elif state in states_dict.keys():
		return states_dict[state]
	else:
		states_dict[state] = Gtk.ListStore(object)
		if state == _('Installed'):
			for pkg in transaction.localdb.pkgcache:
				states_dict[state].append([pkg])
		elif state == _('Uninstalled'):
			for pkg in get_uninstalled_pkgs():
				states_dict[state].append([pkg])
		elif state == _('Orphans'):
			for pkg in get_orphan_pkgs():
				states_dict[state].append([pkg])
		return states_dict[state]

def get_repo_list(repo):
	global repos_dict
	if repo in repos_dict.keys():
		return repos_dict[repo]
	else:
		repos_dict[repo] = Gtk.ListStore(object)
		if repo == _('local'):
			for pkg in transaction.localdb.pkgcache:
				if not transaction.get_syncpkg(pkg.name):
					repos_dict[repo].append([pkg])
		else:
			for db in transaction.syncdbs:
				if db.name ==repo:
					for pkg in db.pkgcache:
						local_pkg = transaction.get_localpkg(pkg.name)
						if local_pkg:
							repos_dict[repo].append([local_pkg])
						else:
							repos_dict[repo].append([pkg])
		return repos_dict[repo]

def search_pkgs(search_string):
	global search_dict
	if search_string in search_dict.keys():
		return search_dict[search_string]
	else:
		search_dict[search_string] = Gtk.ListStore(object)
		names_list = []
		for pkg in transaction.localdb.search(*search_string.split()):
			if not pkg.name in names_list:
				names_list.append(pkg.name)
				search_dict[search_string].append([pkg])
		for db in transaction.syncdbs:
			for pkg in db.search(*search_string.split()):
				if not pkg.name in names_list:
					names_list.append(pkg.name)
					search_dict[search_string].append([pkg])
		if not names_list:
			search_dict[search_string].append([_('No package found')])
		else:
			if not search_string in [row[0] for row in search_list]:
				search_list.append([search_string])
		return search_dict[search_string] 

def get_uninstalled_pkgs():
	pkgs_list = []
	names_list = []
	for repo in transaction.syncdbs:
		for pkg in repo.pkgcache:
			if not pkg.name in names_list:
				names_list.append(pkg.name)
				if not transaction.get_localpkg(pkg.name):
					pkgs_list.append(pkg)
	return pkgs_list

def get_orphan_pkgs():
	pkgs_list = []
	for pkg in transaction.localdb.pkgcache:
		if pkg.reason == pyalpm.PKG_REASON_DEPEND:
			if not pkg.compute_requiredby():
				pkgs_list.append(pkg)
	return pkgs_list

def refresh_packages_list(liststore):
	packages_list_treeview.freeze_child_notify()
	packages_list_treeview.set_model(None)
	liststore.set_sort_func(0, name_column_sort_func, None)
	liststore.set_sort_column_id(0, Gtk.SortType.ASCENDING)
	packages_list_treeview.set_model(liststore)
	state_column.set_sort_indicator(False)
	name_column.set_sort_indicator(True)
	version_column.set_sort_indicator(False)
	size_column.set_sort_indicator(False)
	packages_list_treeview.thaw_child_notify()
	ManagerWindow.get_window().set_cursor(None)

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
		optdeps = []
		for optdep in pkg.optdepends:
			if transaction.get_localpkg(optdep.split(':')[0]):
				optdeps.append(optdep+' ['+_('Installed')+']')
			else:
				optdeps.append(optdep)
		deps_list.append([_('Optional Deps')+':', '\n'.join(optdeps)])
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
	files_buffer.delete(files_buffer.get_start_iter(), files_buffer.get_end_iter())
	if len(pkg.files) != 0:
		for file in pkg.files:
			end_iter = files_buffer.get_end_iter()
			files_buffer.insert(end_iter, '/'+file[0]+'\n')

def handle_error(error):
	ManagerWindow.get_window().set_cursor(None)
	transaction.ProgressWindow.hide()
	while Gtk.events_pending():
		Gtk.main_iteration()
	if error:
		if not 'DBus.Error.NoReply' in str(error):
			print(error)
			transaction.ErrorDialog.format_secondary_text(str(error))
			response = transaction.ErrorDialog.run()
			if response:
				transaction.ErrorDialog.hide()
	transaction.progress_buffer.delete(transaction.progress_buffer.get_start_iter(),transaction.progress_buffer.get_end_iter())
	transaction.get_handle()
	transaction.update_dbs()
	transaction.to_add.clear()
	transaction.to_remove.clear()
	transaction.to_load.clear()

def handle_reply(reply):
	if reply:
		transaction.ProgressCloseButton.set_visible(True)
		transaction.action_icon.set_from_icon_name('dialog-information', Gtk.IconSize.BUTTON)
		transaction.progress_label.set_text(str(reply))
		transaction.progress_bar.set_text('')
		end_iter = transaction.progress_buffer.get_end_iter()
		transaction.progress_buffer.insert(end_iter, str(reply))
	else:
		transaction.ProgressWindow.hide()
		while Gtk.events_pending():
			Gtk.main_iteration()
		error = transaction.sysupgrade(True)
		ManagerWindow.get_window().set_cursor(None)
		if error:
			handle_error(error)
			return
	transaction.get_handle()
	transaction.update_dbs()
	transaction.to_add.clear()
	transaction.to_remove.clear()
	global search_dict
	global groups_dict
	global states_dict 
	global repos_dict
	search_dict = {}
	groups_dict = {}
	states_dict = {}
	repos_dict = {}
	if current_filter[0]:
		refresh_packages_list(current_filter[0](current_filter[1]))

def on_ManagerWindow_delete_event(*args):
	transaction.StopDaemon()
	common.rm_pid_file()
	Gtk.main_quit()

def on_TransValidButton_clicked(*args):
	transaction.ConfDialog.hide()
	while Gtk.events_pending():
		Gtk.main_iteration()
	transaction.finalize()

def on_TransCancelButton_clicked(*args):
	transaction.progress_buffer.delete(transaction.progress_buffer.get_start_iter(),transaction.progress_buffer.get_end_iter())
	transaction.ConfDialog.hide()
	while Gtk.events_pending():
		Gtk.main_iteration()
	transaction.Release()
	if current_filter[0]:
		refresh_packages_list(current_filter[0](current_filter[1]))

def on_ProgressCloseButton_clicked(*args):
	transaction.ProgressWindow.hide()
	while Gtk.events_pending():
		Gtk.main_iteration()
	transaction.progress_buffer.delete(transaction.progress_buffer.get_start_iter(),transaction.progress_buffer.get_end_iter())
	ManagerWindow.get_window().set_cursor(Gdk.Cursor(Gdk.CursorType.WATCH))
	error = transaction.sysupgrade(True)
	ManagerWindow.get_window().set_cursor(None)
	if error:
		handle_error(error)

def on_ProgressCancelButton_clicked(*args):
	transaction.Interrupt()
	ManagerWindow.get_window().set_cursor(None)
	transaction.ProgressWindow.hide()
	while Gtk.events_pending():
		Gtk.main_iteration()

def on_search_entry_icon_press(*args):
	on_search_entry_activate(None)

def on_search_entry_activate(widget):
	global current_filter
	ManagerWindow.get_window().set_cursor(Gdk.Cursor(Gdk.CursorType.WATCH))
	while Gtk.events_pending():
		Gtk.main_iteration()
	current_filter = (search_pkgs, search_entry.get_text())
	refresh_packages_list(search_pkgs(search_entry.get_text()))

def mark_to_install(widget, pkg):
	transaction.to_add.add(pkg.name)

def mark_to_reinstall(widget, pkg):
	transaction.to_add.add(pkg.name)

def mark_to_remove(widget, pkg):
	transaction.to_remove.add(pkg.name)

def mark_to_unselect(widget, pkg):
	transaction.to_remove.discard(pkg.name)
	transaction.to_add.discard(pkg.name)

def select_optdeps(widget, pkg, optdeps):
	transaction.choose_label.set_markup(_('<b>{pkgname} has {number} uninstalled optional deps.\nPlease choose the one(s) you want to install:</b>').format(pkgname = pkg.name, number = str(len(optdeps))))
	transaction.choose_list.clear()
	for long_string in optdeps:
		transaction.choose_list.append([False, long_string])
	transaction.ChooseDialog.run()

def install_with_optdeps(widget, pkg, optdeps):
	select_optdeps(widget, pkg, optdeps)
	transaction.to_add.add(pkg.name)

def on_list_treeview_button_press_event(treeview, event):
	global right_click_menu
	liststore = packages_list_treeview.get_model()
	# Check if right mouse button was clicked
	if event.type == Gdk.EventType.BUTTON_PRESS and event.button == 3:
		while Gtk.events_pending():
			Gtk.main_iteration()
		treepath, viewcolumn, x, y = treeview.get_path_at_pos(int(event.x), int(event.y))
		treeiter = liststore.get_iter(treepath)
		if treeiter:
			if liststore[treeiter][0] != _('No package found') and not liststore[treeiter][0].name in config.holdpkg:
				right_click_menu = Gtk.Menu()
				if liststore[treeiter][0].name in transaction.to_add | transaction.to_remove:
					item = Gtk.ImageMenuItem(_('Unselect'))
					item.set_image(Gtk.Image.new_from_stock('gtk-undo', Gtk.IconSize.MENU))
					item.set_always_show_image(True)
					item.connect('activate', mark_to_unselect, liststore[treeiter][0])
					right_click_menu.append(item)
				elif liststore[treeiter][0].db.name == 'local':
					item = Gtk.ImageMenuItem(_('Remove'))
					item.set_image(Gtk.Image.new_from_pixbuf(to_remove_icon))
					item.set_always_show_image(True)
					item.connect('activate', mark_to_remove, liststore[treeiter][0])
					right_click_menu.append(item)
					if transaction.get_syncpkg(liststore[treeiter][0].name):
						item = Gtk.ImageMenuItem(_('Reinstall'))
						item.set_image(Gtk.Image.new_from_pixbuf(to_reinstall_icon))
						item.set_always_show_image(True)
						item.connect('activate', mark_to_reinstall, liststore[treeiter][0])
						right_click_menu.append(item)
					optdeps_strings = liststore[treeiter][0].optdepends
					if optdeps_strings:
						available_optdeps = []
						for optdep_string in optdeps_strings:
							optdep = optdep_string.split(':')[0]
							if not transaction.get_localpkg(optdep):
								available_optdeps.append(optdep_string)
						if available_optdeps:
							item = Gtk.ImageMenuItem(_('Install optional deps'))
							item.set_image(Gtk.Image.new_from_pixbuf(to_install_icon))
							item.set_always_show_image(True)
							item.connect('activate', select_optdeps, liststore[treeiter][0], available_optdeps)
							right_click_menu.append(item)
				else:
					item = Gtk.ImageMenuItem(_('Install'))
					item.set_image(Gtk.Image.new_from_pixbuf(to_install_icon))
					item.set_always_show_image(True)
					item.connect('activate', mark_to_install, liststore[treeiter][0])
					right_click_menu.append(item)
					optdeps_strings = liststore[treeiter][0].optdepends
					if optdeps_strings:
						available_optdeps = []
						for optdep_string in optdeps_strings:
							optdep = optdep_string.split(':')[0]
							if not transaction.get_localpkg(optdep):
								available_optdeps.append(optdep_string)
						if available_optdeps:
							item = Gtk.ImageMenuItem(_('Install with optional deps'))
							item.set_image(Gtk.Image.new_from_pixbuf(to_install_icon))
							item.set_always_show_image(True)
							item.connect('activate', install_with_optdeps, liststore[treeiter][0], available_optdeps)
							right_click_menu.append(item)
				treeview.grab_focus()
				treeview.set_cursor(treepath, viewcolumn, 0)
				right_click_menu.show_all()
				right_click_menu.popup(None, None, None, None, event.button, event.time)
				return True

def on_list_treeview_selection_changed(treeview):
	liststore, treeiter = list_selection.get_selected()
	if treeiter:
		if liststore[treeiter][0] != _('No package found'):
			set_infos_list(liststore[treeiter][0])
			if liststore[treeiter][0].db.name == 'local':
				set_deps_list(liststore[treeiter][0], "local")
				set_details_list(liststore[treeiter][0], "local")
				set_files_list(liststore[treeiter][0])
				files_scrolledwindow.set_visible(True)
			else:
				set_deps_list(liststore[treeiter][0], "sync")
				set_details_list(liststore[treeiter][0], "sync")
				files_scrolledwindow.set_visible(False)

def on_search_treeview_selection_changed(widget):
	global current_filter
	while Gtk.events_pending():
		Gtk.main_iteration()
	liste, line = search_selection.get_selected()
	if line:
		ManagerWindow.get_window().set_cursor(Gdk.Cursor(Gdk.CursorType.WATCH))
		while Gtk.events_pending():
			Gtk.main_iteration()
		current_filter = (search_pkgs, search_list[line][0])
		refresh_packages_list(search_pkgs(search_list[line][0]))

def on_groups_treeview_selection_changed(widget):
	global current_filter
	while Gtk.events_pending():
		Gtk.main_iteration()
	liste, line = groups_selection.get_selected()
	if line:
		ManagerWindow.get_window().set_cursor(Gdk.Cursor(Gdk.CursorType.WATCH))
		while Gtk.events_pending():
			Gtk.main_iteration()
		current_filter = (get_group_list, groups_list[line][0])
		refresh_packages_list(get_group_list(groups_list[line][0]))

def on_states_treeview_selection_changed(widget):
	global current_filter
	while Gtk.events_pending():
		Gtk.main_iteration()
	liste, line = states_selection.get_selected()
	if line:
		ManagerWindow.get_window().set_cursor(Gdk.Cursor(Gdk.CursorType.WATCH))
		while Gtk.events_pending():
			Gtk.main_iteration()
		current_filter = (get_state_list, states_list[line][0])
		refresh_packages_list(get_state_list(states_list[line][0]))

def on_repos_treeview_selection_changed(widget):
	global current_filter
	while Gtk.events_pending():
		Gtk.main_iteration()
	liste, line = repos_selection.get_selected()
	if line:
		ManagerWindow.get_window().set_cursor(Gdk.Cursor(Gdk.CursorType.WATCH))
		while Gtk.events_pending():
			Gtk.main_iteration()
		current_filter = (get_repo_list, repos_list[line][0])
		refresh_packages_list(get_repo_list(repos_list[line][0]))

def on_list_treeview_row_activated(treeview, treeiter, column):
	liststore = treeview.get_model()
	if not liststore[treeiter][0] == _('No package found'):
		if not liststore[treeiter][0].name in config.holdpkg:
			if liststore[treeiter][0].db.name == 'local':
				if liststore[treeiter][0].name in transaction.to_add:
					transaction.to_add.discard(liststore[treeiter][0].name)
				elif liststore[treeiter][0].name in transaction.to_remove:
					transaction.to_remove.discard(liststore[treeiter][0].name)
				else:
					transaction.to_remove.add(liststore[treeiter][0].name)
			else:
				if liststore[treeiter][0].name in transaction.to_add:
					transaction.to_add.discard(liststore[treeiter][0].name)
				else:
					transaction.to_add.add(liststore[treeiter][0].name)
	while Gtk.events_pending():
		Gtk.main_iteration()

def on_notebook1_switch_page(notebook, page, page_num):
	ManagerWindow.get_window().set_cursor(Gdk.Cursor(Gdk.CursorType.WATCH))
	while Gtk.events_pending():
		Gtk.main_iteration()
	if page_num == 0:
		liste, line = search_selection.get_selected()
		if line:
			on_search_treeview_selection_changed(None)
		elif search_entry.get_text():
			on_search_entry_activate(None)
		else:
			ManagerWindow.get_window().set_cursor(None)
	elif page_num == 1:
		on_groups_treeview_selection_changed(None)
	elif page_num == 2:
		on_states_treeview_selection_changed(None)
	elif page_num == 3:
		on_repos_treeview_selection_changed(None)

def on_manager_valid_button_clicked(*args):
	ManagerWindow.get_window().set_cursor(Gdk.Cursor(Gdk.CursorType.WATCH))
	error = transaction.run()
	ManagerWindow.get_window().set_cursor(None)
	if error:
		handle_error(error)

def on_manager_cancel_button_clicked(*args):
	transaction.to_add.clear()
	transaction.to_remove.clear()
	if current_filter[0]:
		refresh_packages_list(current_filter[0](current_filter[1]))

def on_refresh_item_activate(*args):
	ManagerWindow.get_window().set_cursor(Gdk.Cursor(Gdk.CursorType.WATCH))
	transaction.refresh(False)


def on_local_item_activate(*args):
	response = PackagesChooserDialog.run()
	if response:
		PackagesChooserDialog.hide()
		while Gtk.events_pending():
			Gtk.main_iteration()

def on_about_item_activate(*args):
	response = AboutDialog.run()
	if response:
		AboutDialog.hide()
		while Gtk.events_pending():
			Gtk.main_iteration()

def on_package_open_button_clicked(*args):
	packages_paths = PackagesChooserDialog.get_filenames()
	if packages_paths:
		PackagesChooserDialog.hide()
		while Gtk.events_pending():
			Gtk.main_iteration()
		for path in packages_paths:
			transaction.to_load.add(path)
		ManagerWindow.get_window().set_cursor(Gdk.Cursor(Gdk.CursorType.WATCH))
		error = transaction.run()
		ManagerWindow.get_window().set_cursor(None)
		if error:
			handle_error(error)

def on_PackagesChooserDialog_file_activated(*args):
	on_package_open_button_clicked(*args)

def on_package_cancel_button_clicked(*args):
	PackagesChooserDialog.hide()
	while Gtk.events_pending():
		Gtk.main_iteration()

def on_state_column_clicked(column):
	liststore = packages_list_treeview.get_model()
	state_column.set_sort_indicator(True)
	name_column.set_sort_indicator(False)
	version_column.set_sort_indicator(False)
	size_column.set_sort_indicator(False)
	liststore.set_sort_func(0, state_column_sort_func, None)

def on_name_column_clicked(column):
	liststore = packages_list_treeview.get_model()
	state_column.set_sort_indicator(False)
	name_column.set_sort_indicator(True)
	version_column.set_sort_indicator(False)
	size_column.set_sort_indicator(False)
	liststore.set_sort_func(0, name_column_sort_func, None)

def on_version_column_clicked(column):
	liststore = packages_list_treeview.get_model()
	state_column.set_sort_indicator(False)
	name_column.set_sort_indicator(False)
	version_column.set_sort_indicator(True)
	size_column.set_sort_indicator(False)
	liststore.set_sort_func(0, version_column_sort_func, None)

def on_size_column_clicked(column):
	liststore = packages_list_treeview.get_model()
	state_column.set_sort_indicator(False)
	name_column.set_sort_indicator(False)
	version_column.set_sort_indicator(False)
	size_column.set_sort_indicator(True)
	liststore.set_sort_func(0, size_column_sort_func, None)

signals = {'on_ManagerWindow_delete_event' : on_ManagerWindow_delete_event,
		'on_TransValidButton_clicked' : on_TransValidButton_clicked,
		'on_TransCancelButton_clicked' : on_TransCancelButton_clicked,
		'on_ChooseButton_clicked' : transaction.on_ChooseButton_clicked,
		'on_progress_textview_size_allocate' : transaction.on_progress_textview_size_allocate,
		'on_choose_renderertoggle_toggled' : transaction.on_choose_renderertoggle_toggled,
		'on_ProgressCancelButton_clicked' : on_ProgressCancelButton_clicked,
		'on_ProgressCloseButton_clicked' : on_ProgressCloseButton_clicked,
		'on_search_entry_icon_press' : on_search_entry_icon_press,
		'on_search_entry_activate' : on_search_entry_activate,
		'on_list_treeview_button_press_event' : on_list_treeview_button_press_event,
		'on_list_treeview_selection_changed' : on_list_treeview_selection_changed,
		'on_search_treeview_selection_changed' : on_search_treeview_selection_changed,
		'on_groups_treeview_selection_changed' : on_groups_treeview_selection_changed,
		'on_states_treeview_selection_changed' : on_states_treeview_selection_changed,
		'on_repos_treeview_selection_changed' : on_repos_treeview_selection_changed,
		'on_list_treeview_row_activated' : on_list_treeview_row_activated,
		'on_notebook1_switch_page' : on_notebook1_switch_page,
		'on_manager_valid_button_clicked' : on_manager_valid_button_clicked,
		'on_manager_cancel_button_clicked' : on_manager_cancel_button_clicked,
		'on_refresh_item_activate' : on_refresh_item_activate,
		'on_local_item_activate' : on_local_item_activate,
		'on_about_item_activate' : on_about_item_activate,
		'on_package_open_button_clicked' : on_package_open_button_clicked,
		'on_package_cancel_button_clicked' : on_package_cancel_button_clicked,
		'on_PackagesChooserDialog_file_activated' : on_PackagesChooserDialog_file_activated,
		'on_state_column_clicked' : on_state_column_clicked,
		'on_name_column_clicked' : on_name_column_clicked,
		'on_version_column_clicked' : on_version_column_clicked,
		'on_size_column_clicked' : on_size_column_clicked}

def config_dbus_signals():
	bus = dbus.SystemBus()
	bus.add_signal_receiver(handle_reply, dbus_interface = "org.manjaro.pamac", signal_name = "EmitTransactionDone")
	bus.add_signal_receiver(handle_error, dbus_interface = "org.manjaro.pamac", signal_name = "EmitTransactionError")

if common.pid_file_exists():
	transaction.ErrorDialog.format_secondary_text(_('Pamac is already running'))
	response = transaction.ErrorDialog.run()
	if response:
		transaction.ErrorDialog.hide()
else:
	common.write_pid_file()
	interface.connect_signals(signals)
	transaction.get_dbus_methods()
	transaction.config_dbus_signals()
	config_dbus_signals()
	state_column.set_cell_data_func(state_rendererpixbuf, state_column_display_func)
	name_column.set_cell_data_func(name_renderertext, name_column_display_func)
	version_column.set_cell_data_func(version_renderertext, version_column_display_func)
	size_column.set_cell_data_func(size_renderertext, size_column_display_func)
	transaction.get_handle()
	transaction.update_dbs()
	update_lists()
	ManagerWindow.show_all()
	ManagerWindow.get_window().set_cursor(Gdk.Cursor(Gdk.CursorType.WATCH))
	transaction.refresh(False)
	while Gtk.events_pending():
		Gtk.main_iteration()
	Gtk.main()
