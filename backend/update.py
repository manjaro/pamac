#! /usr/bin/python
# -*-coding:utf-8 -*-

from gi.repository import Gtk

import pyalpm
from os import geteuid

from backend import transaction

interface = Gtk.Builder()
interface.add_from_file('/usr/share/pamac/pamac_update.glade')
interface.add_from_file('/usr/share/pamac/dialogs.glade')

update_listore = interface.get_object('update_list')
top_label = interface.get_object('top_label')

def have_updates():
	available_updates = transaction.get_updates()
	update_listore.clear()
	top_label.set_justify(Gtk.Justification.CENTER)
	if not available_updates:
		update_listore.append(["", ""])
		top_label.set_markup("<big><b>No update available</b></big>")
		return False
	else:
		for pkg in available_updates:
			pkgname = pkg.name
			newversion = transaction.get_new_version_available(pkgname)
			pkgname = pkg.name+" "+newversion
			update_listore.append([pkgname, transaction.format_size(pkg.size)])
		top_label.set_markup("<big><b>Available updates</b></big>")
		return True

class Handler:
	def on_UpdateWindow_delete_event(self, *arg):
		Gtk.main_quit()

	def on_QuitButton_clicked(self, *arg):
		Gtk.main_quit()

	def on_ApplyButton_clicked(self, *arg):
		transaction.do_sysupgrade()
		have_updates()

	def on_RefreshButton_clicked(self, *arg):
		transaction.do_refresh()
		have_updates()

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
