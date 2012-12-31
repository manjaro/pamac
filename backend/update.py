#! /usr/bin/python
# -*-coding:utf-8 -*-

from gi.repository import Gtk

import pyalpm
from os import geteuid

from backend import config, transaction

interface = Gtk.Builder()
interface.add_from_file('/usr/share/pamac/pamac_update.glade')
interface.add_from_file('/usr/share/pamac/dialogs.glade')

ConfDialog = interface.get_object('ConfDialog')
transaction_add = interface.get_object('transaction_add')
top_label = interface.get_object('top_label')
bottom_label = interface.get_object('bottom_label')
update_listore = interface.get_object('update_list')
update_label = interface.get_object('update_label')

def have_updates():
	available_updates = transaction.get_updates()
	update_listore.clear()
	update_label.set_justify(Gtk.Justification.CENTER)
	if not available_updates:
		update_listore.append(["", ""])
		update_label.set_markup("<big><b>No update available</b></big>")
		return False
	else:
		for pkg in available_updates:
			pkgname = pkg.name
			newversion = transaction.get_new_version_available(pkgname)
			pkgname = pkg.name+" "+newversion
			update_listore.append([pkgname, transaction.format_size(pkg.size)])
		update_label.set_markup("<big><b>Available updates</b></big>")
		return True

def set_transaction_add():
	transaction_add.clear()
	if transaction.to_remove:
		transaction_add.append(['To remove:', transaction.to_remove[0].name])
		i = 1
		while i < len(transaction.to_remove):
			transaction_add.append([' ', transaction.to_remove[i].name])
			i += 1
		bottom_label.set_markup('')
	if transaction.to_add:
		installed_name = []
		for pkg_object in config.handle.get_localdb().pkgcache:
			installed_name.append(pkg_object.name)
		to_add_name = []
		for pkg_object in transaction.to_add:
			to_add_name.append(pkg_object.name)
		transaction.to_update = sorted(set(installed_name).intersection(to_add_name))
		to_remove_from_add_name = sorted(set(transaction.to_update).intersection(to_add_name))
		for name in to_remove_from_add_name:
			to_add_name.remove(name)
		if to_add_name:
			transaction_add.append(['To install:', to_add_name[0]])
			i = 1
			while i < len(to_add_name):
				transaction_add.append([' ', to_add_name[i]])
				i += 1
		if transaction.to_update:
			transaction_add.append(['To update:', transaction.to_update[0]])
			i = 1
			while i < len(transaction.to_update):
				transaction_add.append([' ', transaction.to_update[i]])
				i += 1
		bottom_label.set_markup('')
		#bottom_label.set_markup('<b>Total Download size: </b>'+format_size(totaldlcb))
		top_label.set_markup('<big><b>Additionnal Transaction(s)</b></big>')

def do_sysupgrade():
	"""Upgrade a system like pacman -Su"""
	if transaction.t_lock is False:
		if transaction.do_syncfirst is True:
			transaction.t = transaction.init_transaction(config.handle, recurse = True)
			for pkg in list_first:
				transaction.t.add_pkg(pkg)
			transaction.to_remove = transaction.t.to_remove
			transaction.to_add = transaction.t.to_add
			set_transaction_add()
			ConfDialog.show_all()
		else:
			try:
				transaction.t = transaction.init_transaction(config.handle)
				transaction.t.sysupgrade(downgrade=False)
			except pyalpm.error:
				ErrorDialog.format_secondary_text(traceback.format_exc())
				response = ErrorDialog.run()
				if response:
					ErrorDialog.hide()
				transaction.t.release()
				transaction.t_lock = False
			transaction.check_conflicts()
			transaction.to_add = transaction.t.to_add
			transaction.to_remove = []
			for pkg in transaction.conflict_to_remove.values():
				transaction.to_remove.append(pkg)
			if len(transaction.to_add) + len(transaction.to_remove) == 0:
				transaction.t.release()
				transaction.t_lock = False
				print("Nothing to update")
			else:
				transaction.t.release()
				transaction.t = transaction.init_transaction(config.handle, noconflicts = True, nodeps = True)
				for pkg in transaction.to_add:
					transaction.t.add_pkg(pkg)
				for pkg in transaction.conflict_to_remove.values():
					transaction.t.remove_pkg(pkg)
				transaction.to_remove = transaction.t.to_remove
				transaction.to_add = transaction.t.to_add
				set_transaction_add()
				if len(transaction.to_update) + len(transaction.to_remove) != 0:
					ConfDialog.show_all()
				else:
					transaction.t_finalize(t)

class Handler:
	def on_UpdateWindow_delete_event(self, *arg):
		Gtk.main_quit()

	def on_QuitButton_clicked(self, *arg):
		Gtk.main_quit()

	def on_ApplyButton_clicked(self, *arg):
		do_sysupgrade()
		have_updates()

	def on_RefreshButton_clicked(self, *arg):
		transaction.do_refresh()
		have_updates()

	def on_TransCancelButton_clicked(self, *arg):
		ConfDialog.hide()
		transaction.t_lock = False
		transaction.t.release()

	def on_TransValidButton_clicked(self, *arg):
		ConfDialog.hide()
		transaction.t_finalize(t)

def main():
	have_updates()
	interface.connect_signals(Handler())
	UpdateWindow = interface.get_object("UpdateWindow")
	UpdateWindow.show_all()
	Gtk.main()

if __name__ == "__main__":
	if geteuid() == 0:
		transaction.do_refresh()
	main()
