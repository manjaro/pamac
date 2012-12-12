#! /usr/bin/python
# -*-coding:utf-8 -*

from gi.repository import Gtk, GdkPixbuf, Gdk, GObject

import pyalpm
import math
import sys
from time import strftime, localtime
from os import geteuid
import config
import transaction
import traceback

interface = Gtk.Builder()
interface.add_from_file('gui/pamac.glade')
interface.add_from_file('gui/dialogs.glade')

packages_list = interface.get_object('packages_list')
groups_list = interface.get_object('groups_list')
transaction_desc = interface.get_object('transaction_desc')
package_desc = interface.get_object('package_desc')
conf_label = interface.get_object('conf_label')
toggle = interface.get_object('cellrenderertoggle1')
search_entry = interface.get_object('search_entry')
tree2 = interface.get_object('treeview2_selection')
tree1 = interface.get_object('treeview1_selection')
installed_column = interface.get_object('installed_column')
name_column = interface.get_object('name_column')
ConfDialog = interface.get_object('ConfDialog')
ErrorDialog = interface.get_object('ErrorDialog')
down_label = interface.get_object('down_label')

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
t = None

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

class Handler:
	def on_MainWindow_delete_event(self, *arg):
		Gtk.main_quit()

	def on_QuitButton_clicked(self, *arg):
		Gtk.main_quit()

	def on_ValidButton_clicked(self, *arg):
		global t
		global transaction_type
		global transaction_dict
		global transaction_desc
		if not geteuid() == 0:
			ErrorDialog.format_secondary_text("You need to be root to run packages transactions")
			response = ErrorDialog.run()
			if response:
				ErrorDialog.hide()
		elif not transaction_dict:
			ErrorDialog.format_secondary_text("No package is selected")
			response = ErrorDialog.run()
			if response:
				ErrorDialog.hide()
		else: 
			transaction_desc.clear()
			t = transaction.init_transaction(config.handle)
			if transaction_type is "install":
				for pkg in transaction_dict.values():
					t.add_pkg(pkg)
			if transaction_type is "remove":
				for pkg in transaction_dict.values():
					t.remove_pkg(pkg)
			try:
				t.prepare()
			except pyalpm.error:
				ErrorDialog.format_secondary_text(traceback.format_exc())
				response = ErrorDialog.run()
				if response:
					ErrorDialog.hide()
				t.release()
			transaction.to_remove = t.to_remove
			transaction.to_add = t.to_add
			if transaction.to_remove:
				transaction_desc.append(['To remove:', transaction.to_remove[0].name])
				i = 1
				while i <  len(transaction.to_remove):
					transaction_desc.append([' ', transaction.to_remove[i].name])
					i += 1
				down_label.set_markup('')
			if transaction.to_add:
				transaction_desc.append(['To install:', transaction.to_add[0].name])
				i = 1
				dsize = transaction.to_add[0].size
				while i <  len(transaction.to_add):
					transaction_desc.append([' ', transaction.to_add[i].name])
					dsize += transaction.to_add[i].download_size
					i += 1
				down_label.set_markup('<b>Total Download size: </b>'+transaction.format_size(dsize))
			response = ConfDialog.run()
			if response == Gtk.ResponseType.OK:
				ConfDialog.hide()
				try:
					t.commit()
				except pyalpm.error:
					ErrorDialog.format_secondary_text(traceback.format_exc())
					response = ErrorDialog.run()
					if response:
						ErrorDialog.hide()
						t.release()
				transaction_dict.clear()
				transaction_type = None
				set_packages_list()
				transaction.ProgressWindow.hide()
			if response == Gtk.ResponseType.CANCEL or Gtk.ResponseType.CLOSE or Gtk.ResponseType.DELETE_EVENT:
				transaction.ProgressWindow.hide()
				ConfDialog.hide()
				t.release()

	def on_EraseButton_clicked(self, *arg):
		global transaction_type
		global transaction_dict
		transaction_dict.clear()
		transaction_type = None
		refresh_packages_list()

	def on_RefreshButton_clicked(self, *arg):
		transaction.do_refresh()
		refresh_packages_list()

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

#if __name__ == "__main__":
transaction.do_refresh()
interface.connect_signals(Handler())
MainWindow = interface.get_object("MainWindow")
MainWindow.show_all()
Gtk.main()
