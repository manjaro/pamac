#! /usr/bin/python3
# -*- coding:utf-8 -*-

from gi.repository import GObject
from pamac import common, transaction
import dbus


def handle_reply(reply):
	print('check updates done')
	transaction.CheckUpdates()

def handle_error(error):
	transaction.StopDaemon()
	print('check updates failed')
	loop.quit()

def handle_updates(updates):
	transaction.StopDaemon()
	loop.quit()

loop = GObject.MainLoop()

if not common.pid_file_exists():
	print('checking updates')
	bus = dbus.SystemBus()
	bus.add_signal_receiver(handle_reply, dbus_interface = "org.manjaro.pamac", signal_name = "EmitTransactionDone")
	bus.add_signal_receiver(handle_error, dbus_interface = "org.manjaro.pamac", signal_name = "EmitTransactionError")
	bus.add_signal_receiver(handle_updates, dbus_interface = "org.manjaro.pamac", signal_name = "EmitAvailableUpdates")
	transaction.get_dbus_methods()
	try:
		transaction.Refresh(False)
	except:
		pass
	else:
		loop.run()
