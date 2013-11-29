#! /usr/bin/python3
# -*- coding:utf-8 -*-

# pamac - A Python implementation of alpm
# Copyright (C) 2013 Guillaume Benoit <guillaume@manjaro.org>
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

from gi.repository import Gtk
from sys import argv
import dbus
from os.path import abspath
from pamac import common, transaction

# i18n
import gettext
import locale
locale.bindtextdomain('pamac', '/usr/share/locale')
gettext.bindtextdomain('pamac', '/usr/share/locale')
gettext.textdomain('pamac')
_ = gettext.gettext

def exiting(msg):
	transaction.StopDaemon()
	print(msg)
	print('exiting')
	Gtk.main_quit()

def handle_error(error):
	transaction.ProgressWindow.hide()
	while Gtk.events_pending():
		Gtk.main_iteration()
	if error:
		if not 'DBus.Error.NoReply' in str(error):
			transaction.ErrorDialog.format_secondary_text(error)
			response = transaction.ErrorDialog.run()
			if response:
				transaction.ErrorDialog.hide()
	exiting(error)

def handle_reply(reply):
	transaction.ProgressCloseButton.set_visible(True)
	transaction.action_icon.set_from_icon_name('dialog-information', Gtk.IconSize.BUTTON)
	transaction.progress_label.set_text(str(reply))
	transaction.progress_bar.set_text('')
	end_iter = transaction.progress_buffer.get_end_iter()
	transaction.progress_buffer.insert(end_iter, str(reply))

def handle_updates(update_data):
	syncfirst, updates = update_data
	transaction.ProgressWindow.hide()
	while Gtk.events_pending():
		Gtk.main_iteration()
	if transaction_done:
		exiting('')
	elif updates:
		transaction.ErrorDialog.format_secondary_text(_('Some updates are available.\nPlease update your system first'))
		response = transaction.ErrorDialog.run()
		if response:
			transaction.ErrorDialog.hide()
		exiting('')
	else:
		common.write_pid_file()
		transaction.interface.connect_signals(signals)
		transaction.config_dbus_signals()
		pkgs_to_install = argv[1:]
		install(pkgs_to_install)

def on_TransValidButton_clicked(*args):
	transaction.ConfDialog.hide()
	while Gtk.events_pending():
		Gtk.main_iteration()
	transaction.finalize()

def on_TransCancelButton_clicked(*args):
	transaction.ConfDialog.hide()
	while Gtk.events_pending():
		Gtk.main_iteration()
	transaction.Release()
	exiting('')

def on_ProgressCloseButton_clicked(*args):
	global transaction_done
	transaction.ProgressWindow.hide()
	while Gtk.events_pending():
		Gtk.main_iteration()
	transaction_done = True
	transaction.CheckUpdates()

def on_ProgressCancelButton_clicked(*args):
	transaction.Interrupt()
	transaction.ProgressWindow.hide()
	while Gtk.events_pending():
		Gtk.main_iteration()
	exiting('')

def get_pkgs(pkgs):
	error = ''
	for name in pkgs:
		if '.pkg.tar.' in name:
			full_path = abspath(name)
			transaction.to_load.add(full_path)
		elif transaction.get_syncpkg(name):
			transaction.to_add.add(name)
		else:
			if error:
				error += '\n'
			error += _('{pkgname} is not a valid path or package name').format(pkgname = name)
	if error:
		handle_error(error)
		return False
	else:
		return True

def install(pkgs):
	if get_pkgs(pkgs):
		error = transaction.run()
		while Gtk.events_pending():
			Gtk.main_iteration()
		if error:
			handle_error(error)

signals = {'on_ChooseButton_clicked' : transaction.on_ChooseButton_clicked,
		'on_progress_textview_size_allocate' : transaction.on_progress_textview_size_allocate,
		'on_choose_renderertoggle_toggled' : transaction.on_choose_renderertoggle_toggled,
		'on_TransValidButton_clicked' :on_TransValidButton_clicked,
		'on_TransCancelButton_clicked' :on_TransCancelButton_clicked,
		'on_ProgressCloseButton_clicked' : on_ProgressCloseButton_clicked,
		'on_ProgressCancelButton_clicked' : on_ProgressCancelButton_clicked}

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
	transaction_done = False
	transaction.get_handle()
	transaction.get_dbus_methods()
	config_dbus_signals()
	transaction.get_updates()
	Gtk.main()
