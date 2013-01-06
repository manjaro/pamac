#! /usr/bin/python
# -*-coding:utf-8 -*-

from gi.repository import Gtk, GdkPixbuf, Gdk, GObject

import pyalpm
import math
import sys
from time import strftime, localtime
from os import geteuid
import traceback

from pamac import transaction, config, callbacks

interface = Gtk.Builder()
interface.add_from_file('/usr/share/pamac/gui/manager.glade')
interface.add_from_file('/usr/share/pamac/gui/dialogs.glade')

MainWindow = interface.get_object("MainWindow")

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
top_label = interface.get_object('top_label')
bottom_label = interface.get_object('bottom_label')

installed_column.set_sort_column_id(1)
name_column.set_sort_column_id(0)

tmp_list = []
for repo in config.handle.get_syncdbs():
	for name, pkgs in repo.grpcache:
		if not name in tmp_list:
			tmp_list.append(name)
tmp_list = sorted(tmp_list)
for name in tmp_list:
	groups_list.append([name])

pkg_name_list = []
pkg_object_dict = {}
pkg_installed_dict = {}
list_dict = None
current_group = None
transaction_type = None
transaction_dict = {}

def set_list_dict_search(*patterns):
	global pkg_name_list
	global pkg_object_dict
	global pkg_installed_dict
	pkg_name_list = []
	pkg_object_dict = {}
	pkg_installed_dict = {}
	for db in config.handle.get_syncdbs():
		for pkg_object in db.search(*patterns):
			if not pkg_object.name in pkg_name_list:
				pkg_name_list.append(pkg_object.name)
				pkg_object_dict[pkg_object.name] = pkg_object
				pkg_installed_dict[pkg_object.name] = False
	for pkg_object in config.handle.get_localdb().search(*patterns):
		print(pkg_object)
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
	for db in config.handle.get_syncdbs():
		grp = db.read_grp(group)
		if grp is not None:
			name, pkg_list = grp
			for pkg_object in pkg_list:
				if not pkg_object.name in pkg_name_list:
					pkg_name_list.append(pkg_object.name)
				pkg_object_dict[pkg_object.name] = pkg_object
				pkg_installed_dict[pkg_object.name] = False
	db = config.handle.get_localdb()
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
		packages_list.append([" ", False, False])
	else:
		for name in pkg_name_list:
			if name in config.holdpkg:
				packages_list.append([name, pkg_installed_dict[name], False])
				break
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
				print(name,pkg_installed_dict[name])

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
		package_desc.append(['Download Size:', transaction.format_size(pkg.size)])
	if style == 'file':
		package_desc.append(['Compressed Size:', transaction.format_size(pkg.size)])
	package_desc.append(['Installed Size:', transaction.format_size(pkg.isize)])
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
		transaction_sum.append(['To remove:', transaction.to_remove[0]])
		i = 1
		while i < len(transaction.to_remove):
			transaction_sum.append([' ', transaction.to_remove[i]])
			i += 1
		bottom_label.set_markup('')
	if transaction.to_add:
		installed = []
		for pkg_object in config.handle.get_localdb().pkgcache:
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
		if transaction.to_update:
			transaction_sum.append(['To update:', transaction.to_update[0]])
			i = 1
			while i < len(transaction.to_update):
				transaction_sum.append([' ', transaction.to_update[i]])
				i += 1
		bottom_label.set_markup('')
		#bottom_label.set_markup('<b>Total Download size: </b>'+format_size(totaldlcb))
	top_label.set_markup('<big><b>Transaction Summary</b></big>')

class Handler:
	def on_MainWindow_delete_event(self, *arg):
		if __name__ == "__main__":
			Gtk.main_quit()
		else:
			MainWindow.hide()

	def on_QuitButton_clicked(self, *arg):
		if __name__ == "__main__":
			Gtk.main_quit()
		else:
			MainWindow.hide()

	def on_ValidButton_clicked(self, *arg):
		global t
		global transaction_type
		global transaction_dict
		#if not geteuid() == 0:
			#transaction.ErrorDialog.format_secondary_text("You need to be root to run packages transactions")
			#response = transaction.ErrorDialog.run()
			#if response:
				#transaction.ErrorDialog.hide()
		#el
		if not transaction_dict:
			transaction.ErrorDialog.format_secondary_text("No package is selected")
			response = transaction.ErrorDialog.run()
			if response:
				transaction.ErrorDialog.hide()
		else:
			if transaction.t_lock is True:
				print('Transaction locked')
			else:
				if transaction_type is "remove":
					transaction.init_transaction(cascade = True)
					for pkgname in transaction_dict.keys():
						transaction.Remove(pkgname)
					error = transaction.Prepare()
					if error:
						transaction.ErrorDialog.format_secondary_text(error)
						response = transaction.ErrorDialog.run()
						if response:
							transaction.ErrorDialog.hide()
						transaction.Release()
						transaction.t_lock = False
					transaction.get_to_remove()
					#transaction.get_to_add()
					set_transaction_sum()
					ConfDialog.show_all()
				if transaction_type is "install":
					transaction.init_transaction(noconflicts = True)
					for pkgname in transaction_dict.keys():
						transaction.Add(pkgname)
					error = transaction.Prepare()
					if error:
						transaction.ErrorDialog.format_secondary_text(error)
						response = transaction.ErrorDialog.run()
						if response:
							transaction.ErrorDialog.hide()
						transaction.Release()
						transaction.t_lock = False
					transaction.get_to_remove()
					transaction.get_to_add()
					transaction.check_conflicts()
					transaction.Release()
					set_transaction_sum()
					ConfDialog.show_all()

	def on_EraseButton_clicked(self, *arg):
		global transaction_type
		global transaction_dict
		transaction_dict.clear()
		transaction_type = None
		refresh_packages_list()

	def on_RefreshButton_clicked(self, *arg):
		transaction.do_refresh()
		refresh_packages_list()

	def on_TransCancelButton_clicked(self, *arg):
		ConfDialog.hide()
		transaction.t_lock = False
		transaction.Release()

	def on_TransValidButton_clicked(self, *arg):
		global transaction_type
		ConfDialog.hide()
		while Gtk.events_pending():
			Gtk.main_iteration()
		if transaction_type is "remove":
			error = transaction.Commit()
			if error:
				transaction.ErrorDialog.format_secondary_text(error)
				response = transaction.ErrorDialog.run()
				if response:
					transaction.ErrorDialog.hide()
			transaction.Release()
		if transaction_type is "install":
			transaction.init_transaction(noconflicts = True, nodeps = True)
			for pkgname in transaction.to_add:
				transaction.Add(pkgname)
			for pkgname in transaction.to_remove:
				transaction.Remove(pkgname)
			transaction.finalize()
		transaction_dict.clear()
		transaction_type = None
		set_packages_list()
		transaction.t_lock = False

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

def main():
	interface.connect_signals(Handler())
	MainWindow.show_all()

if __name__ == "__main__":
	if geteuid() == 0:
		transaction.progress_label.set_text('Refreshing...')
		transaction.progress_bar.pulse()
		transaction.action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/refresh-cache.png')
		transaction.do_refresh()
	main()
	Gtk.main()

