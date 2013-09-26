#! /usr/bin/pkexec /usr/bin/python3
# -*- coding:utf-8 -*-

from gi.repository import Gtk, Gdk
import pyalpm

from pamac import config, common, transaction

# i18n
import gettext
import locale
locale.bindtextdomain('pamac', '/usr/share/locale')
gettext.bindtextdomain('pamac', '/usr/share/locale')
gettext.textdomain('pamac')
_ = gettext.gettext

interface = transaction.interface

interface.add_from_file('/usr/share/pamac/gui/updater.ui')
UpdaterWindow = interface.get_object("UpdaterWindow")
update_listore = interface.get_object('update_list')
update_top_label = interface.get_object('update_top_label')
update_bottom_label = interface.get_object('update_bottom_label')

update_top_label.set_markup(_('<big><b>Your system is up-to-date</b></big>'))
update_bottom_label.set_markup('')

def have_updates():
	do_syncfirst, updates = trans.get_updates()
	update_listore.clear()
	update_top_label.set_justify(Gtk.Justification.CENTER)
	if not updates:
		update_bottom_label.set_markup('')
		update_top_label.set_markup(_('<big><b>Your system is up-to-date</b></big>'))
	else:
		dsize = 0
		for pkg in updates:
			pkgname = pkg.name+' '+pkg.version
			update_listore.append([pkgname, common.format_size(pkg.size)])
			dsize += pkg.download_size
		if dsize == 0:
			update_bottom_label.set_markup('')
		else:
			update_bottom_label.set_markup(_('<b>Total download size: </b>')+common.format_size(dsize))
		if len(updates) == 1:
			update_top_label.set_markup(_('<big><b>1 available update</b></big>'))
		else:
			update_top_label.set_markup(_('<big><b>{number} available updates</b></big>').format(number = len(updates)))

def on_TransValidButton_clicked(*arg):
	transaction.ConfDialog.hide()
	trans.finalize()

def on_TransCancelButton_clicked(*arg):
	transaction.progress_buffer.delete(transaction.progress_buffer.get_start_iter(),transaction.progress_buffer.get_end_iter())
	transaction.ConfDialog.hide()
	trans.release()

def on_ProgressCloseButton_clicked(*arg):
	transaction.ProgressWindow.hide()
	transaction.progress_buffer.delete(transaction.progress_buffer.get_start_iter(),transaction.progress_buffer.get_end_iter())
	have_updates()

def on_ProgressCancelButton_clicked(*args):
	trans.interrupt()

def on_UpdaterWindow_delete_event(*arg):
	Gtk.main_quit()
	common.rm_pid_file()

def on_Updater_ApplyButton_clicked(*arg):
	UpdaterWindow.get_window().set_cursor(Gdk.Cursor(Gdk.CursorType.WATCH))
	while Gtk.events_pending():
		Gtk.main_iteration()
	trans.do_sysupgrade(False)
	UpdaterWindow.get_window().set_cursor(None)

def on_Updater_RefreshButton_clicked(*arg):
	while Gtk.events_pending():
		Gtk.main_iteration()
	UpdaterWindow.get_window().set_cursor(Gdk.Cursor(Gdk.CursorType.WATCH))
	trans.refresh(False)
	UpdaterWindow.get_window().set_cursor(None)

signals = {'on_ChooseButton_clicked' : transaction.on_ChooseButton_clicked,
		'on_progress_textview_size_allocate' : transaction.on_progress_textview_size_allocate,
		'on_choose_renderertoggle_toggled' : transaction.on_choose_renderertoggle_toggled,
		'on_TransValidButton_clicked' :on_TransValidButton_clicked,
		'on_TransCancelButton_clicked' :on_TransCancelButton_clicked,
		'on_ProgressCloseButton_clicked' : on_ProgressCloseButton_clicked,
		'on_ProgressCancelButton_clicked' : on_ProgressCancelButton_clicked,
		'on_UpdaterWindow_delete_event' : on_UpdaterWindow_delete_event,
		'on_Updater_ApplyButton_clicked' : on_Updater_ApplyButton_clicked,
		'on_Updater_RefreshButton_clicked' : on_Updater_RefreshButton_clicked}

if common.pid_file_exists():
	transaction.ErrorDialog.format_secondary_text(_('Pamac is already running'))
	response = transaction.ErrorDialog.run()
	if response:
		transaction.ErrorDialog.hide()
else:
	common.write_pid_file()
	interface.connect_signals(signals)
	UpdaterWindow.show_all()
	trans = transaction.Transaction()
	UpdaterWindow.get_window().set_cursor(Gdk.Cursor(Gdk.CursorType.WATCH))
	while Gtk.events_pending():
		Gtk.main_iteration()
	trans.refresh(False)
	have_updates()
	UpdaterWindow.get_window().set_cursor(None)
	Gtk.main()
