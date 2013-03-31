#! /usr/bin/python
# -*- coding:utf-8 -*-

from gi.repository import GObject
from pamac import common, transaction
import dbus

def reply(reply):
	transaction.StopDaemon()
	common.rm_pid_file()
	print('check updates done')
	loop.quit()

def error(error):
	transaction.StopDaemon()
	common.rm_pid_file()
	print('check updates failed')
	loop.quit()

bus = dbus.SystemBus()
bus.add_signal_receiver(reply, dbus_interface = "org.manjaro.pamac", signal_name = "EmitTransactionDone")
bus.add_signal_receiver(error, dbus_interface = "org.manjaro.pamac", signal_name = "EmitTransactionError")

loop = GObject.MainLoop()

if not common.pid_file_exists():
	print('checking updates')
	common.write_pid_file()
	transaction.Refresh()
	loop.run()
