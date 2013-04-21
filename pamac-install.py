#! /usr/bin/python3
# -*- coding:utf-8 -*-

from gi.repository import GObject
from sys import argv
import dbus
from pamac import common, transaction, main

# i18n
import gettext
import locale
locale.bindtextdomain('pamac', '/usr/share/locale')
gettext.bindtextdomain('pamac', '/usr/share/locale')
gettext.textdomain('pamac')
_ = gettext.gettext

def exiting(msg):
	transaction.StopDaemon()
	common.rm_pid_file()
	print('exiting')
	loop.quit()

bus = dbus.SystemBus()
bus.add_signal_receiver(exiting, dbus_interface = "org.manjaro.pamac", signal_name = "EmitTransactionDone")
bus.add_signal_receiver(exiting, dbus_interface = "org.manjaro.pamac", signal_name = "EmitTransactionError")

def new_on_TransCancelButton_clicked(self, *arg):
	main.ProgressWindow.hide()
	main.ConfDialog.hide()
	transaction.Release()
	exiting('')

def new_on_TransValidButton_clicked(self, *arg):
	main.ConfDialog.hide()
	main.finalize()

main.Handler.on_TransCancelButton_clicked = new_on_TransCancelButton_clicked
main.Handler.on_TransValidButton_clicked = new_on_TransValidButton_clicked
main.interface.connect_signals(main.Handler())

def get_pkgs(pkgs):
	get_error = ''
	for pkg in pkgs:
		if '.pkg.tar.' in pkg:
			transaction.to_load.add(pkg)
		elif pkg in transaction.syncpkgs.keys():
			transaction.to_add.add(pkg)
		else:
			if get_error:
				get_error += '\n'
			get_error += _('{pkgname} is not a valid path or package name').format(pkgname = pkg)
	if get_error:
		main.handle_error(get_error)
		exiting(get_error)
		return False
	else:
		return True

def install(pkgs):
	if get_pkgs(pkgs):
		main.check_conflicts()
		if transaction.to_add | transaction.to_load:
			if transaction.init_transaction(noconflicts = True):
				for pkgname in transaction.to_add:
					transaction.Add(pkgname)
				for pkg_path in transaction.to_load:
					transaction.Load(pkg_path)
				for pkgname in transaction.to_remove:
					transaction.Remove(pkgname)
				_error = transaction.Prepare()
				if _error:
					main.handle_error(_error)
					exiting(_error)
				else:
					transaction.get_to_remove()
					transaction.get_to_add()
					do_syncfirst, updates = transaction.get_updates()
					transaction.to_update = set([pkg.name for pkg in updates])
					transaction.to_add -= transaction.to_update
					main.set_transaction_sum()
					main.ConfDialog.show_all()
					loop.run()
		else:
			main.WarningDialog.format_secondary_text(_('Nothing to do'))
			response = main.WarningDialog.run()
			if response:
				main.WarningDialog.hide()
			exiting('')

loop = GObject.MainLoop()

transaction.get_handle()
transaction.update_db()
do_syncfirst, updates = transaction.get_updates()

if common.pid_file_exists():
	main.ErrorDialog.format_secondary_text(_('Pamac is already running'))
	response = main.ErrorDialog.run()
	if response:
		main.ErrorDialog.hide()
#~ elif updates:
		#~ main.ErrorDialog.format_secondary_text(_('Some updates are available.\nPlease update your system first'))
		#~ response = main.ErrorDialog.run()
		#~ if response:
			#~ main.ErrorDialog.hide()
		#~ transaction.StopDaemon()
else:
	common.write_pid_file()
	pkgs_to_install = argv[1:]
	install(pkgs_to_install)
