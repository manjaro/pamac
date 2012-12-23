#! /usr/bin/python
# -*-coding:utf-8 -*-

from gi.repository import Gtk, GdkPixbuf, Gdk

import pyalpm
from time import strftime, localtime
from os import geteuid
import config
import transaction

interface = Gtk.Builder()
interface.add_from_file('gui/pamac_update.glade')
interface.add_from_file('gui/dialogs.glade')

update_listore = interface.get_object('update_list')
top_label = interface.get_object('top_label')

def have_updates():
	available_updates = transaction.get_updates()
	update_listore.clear()
	if not available_updates:
		update_listore.append(["", ""])
		return False
	else:
		for pkg in available_updates:
			pkgname = pkg.name
			newversion = transaction.get_new_version_available(pkgname)
			pkgname = pkg.name+" "+newversion
			update_listore.append([pkgname, transaction.format_size(pkg.size)])
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

	def on_ProgressWindow_delete_event(self, *arg):
		pass

def main():
	update = have_updates()
	top_label.set_justify(Gtk.Justification.CENTER)
	if update is False:
		top_label.set_markup("<big><b>No update available</b></big>")
	else:
		top_label.set_markup("<big><b>Available updates</b></big>")
	interface.connect_signals(Handler())
	UpdateWindow = interface.get_object("UpdateWindow")
	UpdateWindow.show_all()
	Gtk.main()

if __name__ == "__main__":
	if geteuid() == 0:
		transaction.do_refresh()
	main()
