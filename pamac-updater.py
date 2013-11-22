#! /usr/bin/python3
# -*- coding:utf-8 -*-

from gi.repository import Gtk, Gdk
import pyalpm
import dbus

from pamac import config, common, transaction, aur

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
UpdaterApplyButton = interface.get_object('UpdaterApplyButton')

update_top_label.set_markup('<big><b>{}</b></big>'.format(_('Your system is up-to-date')))
update_bottom_label.set_markup('')
UpdaterApplyButton.set_sensitive(False)

def have_updates():
	while Gtk.events_pending():
		Gtk.main_iteration()
	UpdaterWindow.get_window().set_cursor(Gdk.Cursor(Gdk.CursorType.WATCH))
	while Gtk.events_pending():
		Gtk.main_iteration()
	update_listore.clear()
	update_top_label.set_justify(Gtk.Justification.CENTER)
	updates = transaction.available_updates[1]
	if not updates:
		update_bottom_label.set_markup('')
		update_top_label.set_markup('<big><b>{}</b></big>'.format(_('Your system is up-to-date')))
		UpdaterApplyButton.set_sensitive(False)
	else:
		UpdaterApplyButton.set_sensitive(True)
		dsize = 0
		for name, version, db, tarpath, size in updates:
			dsize += size
			if size:
				size_str = common.format_size(size)
			else:
				size_str = ''
			update_listore.append([name+' '+version, size_str])
		if dsize == 0:
			update_bottom_label.set_markup('')
		else:
			update_bottom_label.set_markup('<b>{} {}</b>'.format(_('Total download size:'), common.format_size(dsize)))
		if len(updates) == 1:
			update_top_label.set_markup('<big><b>{}</b></big>'.format(_('1 available update')))
		else:
			update_top_label.set_markup('<big><b>{}</b></big>'.format(_('{number} available updates').format(number = len(updates))))
	UpdaterWindow.get_window().set_cursor(None)

def handle_error(error):
	UpdaterWindow.get_window().set_cursor(None)
	transaction.ProgressWindow.hide()
	while Gtk.events_pending():
		Gtk.main_iteration()
	if error:
		if not 'DBus.Error.NoReply' in str(error):
			print(error)
			transaction.ErrorDialog.format_secondary_text(error)
			response = transaction.ErrorDialog.run()
			if response:
				transaction.ErrorDialog.hide()
	transaction.get_handle()
	transaction.update_dbs()

def handle_reply(reply):
	while Gtk.events_pending():
		Gtk.main_iteration()
	if transaction.to_build:
		transaction.build_next() 
	elif reply:
		transaction.Release()
		transaction.ProgressCloseButton.set_visible(True)
		transaction.action_icon.set_from_icon_name('dialog-information', Gtk.IconSize.BUTTON)
		transaction.progress_label.set_text(str(reply))
		transaction.progress_bar.set_text('')
		end_iter = transaction.progress_buffer.get_end_iter()
		transaction.progress_buffer.insert(end_iter, str(reply))
		transaction.get_handle()
		transaction.update_dbs()
	else:
		#~ transaction.ProgressWindow.hide()
		#~ while Gtk.events_pending():
			#~ Gtk.main_iteration()
		UpdaterWindow.get_window().set_cursor(None)
		transaction.get_handle()
		transaction.update_dbs()
		transaction.get_updates()

def handle_updates(updates):
	transaction.ProgressWindow.hide()
	transaction.available_updates = updates
	have_updates()

def on_UpdaterWindow_delete_event(*args):
	transaction.StopDaemon()
	common.rm_pid_file()
	Gtk.main_quit()

def on_TransValidButton_clicked(*args):
	UpdaterWindow.get_window().set_cursor(None)
	transaction.ConfDialog.hide()
	while Gtk.events_pending():
		Gtk.main_iteration()
	transaction.finalize()

def on_TransCancelButton_clicked(*args):
	UpdaterWindow.get_window().set_cursor(None)
	transaction.progress_buffer.delete(transaction.progress_buffer.get_start_iter(),transaction.progress_buffer.get_end_iter())
	transaction.ConfDialog.hide()
	while Gtk.events_pending():
		Gtk.main_iteration()
	transaction.Release()
	transaction.to_add.clear()
	transaction.to_add_as_dep.clear()
	transaction.to_update.clear()
	transaction.to_build.clear()

def on_ProgressCloseButton_clicked(*args):
	UpdaterWindow.get_window().set_cursor(None)
	#~ transaction.ProgressWindow.hide()
	#~ while Gtk.events_pending():
		#~ Gtk.main_iteration()
	transaction.progress_buffer.delete(transaction.progress_buffer.get_start_iter(),transaction.progress_buffer.get_end_iter())
	transaction.need_details_handler(False)
	transaction.get_updates()

def on_ProgressCancelButton_clicked(*args):
	transaction.to_add.clear()
	transaction.to_update.clear()
	transaction.to_build.clear()
	transaction.Interrupt()
	UpdaterWindow.get_window().set_cursor(None)
	transaction.ProgressWindow.hide()
	while Gtk.events_pending():
		Gtk.main_iteration()

def on_Updater_ApplyButton_clicked(*args):
	UpdaterWindow.get_window().set_cursor(Gdk.Cursor(Gdk.CursorType.WATCH))
	while Gtk.events_pending():
		Gtk.main_iteration()
	transaction.sysupgrade(show_updates = False)

def on_Updater_RefreshButton_clicked(*args):
	UpdaterWindow.get_window().set_cursor(Gdk.Cursor(Gdk.CursorType.WATCH))
	while Gtk.events_pending():
		Gtk.main_iteration()
	transaction.refresh()

def on_Updater_CloseButton_clicked(*args):
	transaction.StopDaemon()
	common.rm_pid_file()
	Gtk.main_quit()

signals = {'on_ChooseButton_clicked' : transaction.on_ChooseButton_clicked,
		'on_progress_textview_size_allocate' : transaction.on_progress_textview_size_allocate,
		'on_choose_renderertoggle_toggled' : transaction.on_choose_renderertoggle_toggled,
		'on_TransValidButton_clicked' :on_TransValidButton_clicked,
		'on_TransCancelButton_clicked' :on_TransCancelButton_clicked,
		'on_ProgressCloseButton_clicked' : on_ProgressCloseButton_clicked,
		'on_ProgressCancelButton_clicked' : on_ProgressCancelButton_clicked,
		'on_UpdaterWindow_delete_event' : on_UpdaterWindow_delete_event,
		'on_Updater_ApplyButton_clicked' : on_Updater_ApplyButton_clicked,
		'on_Updater_RefreshButton_clicked' : on_Updater_RefreshButton_clicked,
		'on_Updater_CloseButton_clicked' : on_Updater_CloseButton_clicked}

def config_dbus_signals():
	bus = dbus.SystemBus()
	bus.add_signal_receiver(handle_reply, dbus_interface = "org.manjaro.pamac", signal_name = "EmitTransactionDone")
	bus.add_signal_receiver(handle_error, dbus_interface = "org.manjaro.pamac", signal_name = "EmitTransactionError")
	bus.add_signal_receiver(handle_updates, dbus_interface = "org.manjaro.pamac", signal_name = "EmitAvailableUpdates")

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
	UpdaterWindow.show_all()
	UpdaterWindow.get_window().set_cursor(Gdk.Cursor(Gdk.CursorType.WATCH))
	while Gtk.events_pending():
		Gtk.main_iteration()
	transaction.refresh()
	Gtk.main()
