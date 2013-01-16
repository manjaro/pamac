#! /usr/bin/python
# -*-coding:utf-8-*-

from gi.repository import Gtk

interface = Gtk.Builder()
interface.add_from_file('/usr/share/pamac/gui/dialogs.glade')

ErrorDialog = interface.get_object('ErrorDialog')
WarningDialog = interface.get_object('WarningDialog')

to_remove = []
to_add = []
to_update = []

def format_size(size):
	KiB_size = size / 1024
	if KiB_size < 1000:
		size_string = '%.1f KiB' % (KiB_size)
		return size_string
	else:
		size_string = '%.2f MiB' % (KiB_size / 1024)
		return size_string
