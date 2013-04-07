#! /usr/bin/python3
# -*- coding:utf-8 -*-

from gi.repository import GObject
from sys import argv
import dbus
from pamac import common, transaction, main

def error(error):
	transaction.StopDaemon()
	common.rm_pid_file()
	print('exiting')
	loop.quit()

def reply(reply):
	transaction.StopDaemon()
	common.rm_pid_file()
	print('exiting')
	loop.quit()

def install(pkgnames):
	transaction.to_add = []
	transaction.to_remove = []
	pkg_to_install = []
	for pkgname in pkgnames:
		if not pkgname in transaction.localpkgs.keys():
			transaction.to_add.append(pkgname)
			pkg_to_install.append(transaction.syncpkgs[pkgname])
	main.check_conflicts('normal', pkg_to_install)
	if transaction.to_add:
		if transaction.init_transaction(noconflicts = True, needed =True):
			for pkgname in transaction.to_add:
				transaction.Add(pkgname)
			for pkgname in transaction.to_remove:
				transaction.Remove(pkgname)
			_error = transaction.Prepare()
			if _error:
				main.handle_error(_error)
				error(_error)
			else:
				main.finalize()
				loop.run()
	else:
		transaction.WarningDialog.format_secondary_text('Nothing to do')
		response = transaction.WarningDialog.run()
		if response:
			transaction.WarningDialog.hide()
		reply('')

bus = dbus.SystemBus()
bus.add_signal_receiver(reply, dbus_interface = "org.manjaro.pamac", signal_name = "EmitTransactionDone")
bus.add_signal_receiver(error, dbus_interface = "org.manjaro.pamac", signal_name = "EmitTransactionError")

loop = GObject.MainLoop()

transaction.get_handle()
transaction.update_db()
do_syncfirst, updates = transaction.get_updates()

if common.pid_file_exists():
	transaction.ErrorDialog.format_secondary_text('Another instance of Pamac is running')
	response = transaction.ErrorDialog.run()
	if response:
		transaction.ErrorDialog.hide()
	transaction.StopDaemon()
elif updates:
		transaction.ErrorDialog.format_secondary_text('Some updates are available.\nPlease update your system first')
		response = transaction.ErrorDialog.run()
		if response:
			transaction.ErrorDialog.hide()
		transaction.StopDaemon()
else:
	common.write_pid_file()
	pkgname_to_install = argv[1:]
	install(pkgname_to_install)
