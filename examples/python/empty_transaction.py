#!/usr/bin/python

import gi
gi.require_version('Pamac', '1.0')
from gi.repository import GLib, Pamac

def on_emit_action (transaction, action, data):
	print(action)

def on_emit_action_progress (transaction, action, status, progress, data):
	print("{} {}".format(action, status))

def on_emit_warning (transaction, message, data):
	print(message)

def on_emit_error (transaction, message, details, details_length, data):
	if details_length > 0:
		print("{}:".format(message))
		for detail in details:
			print(detail)
	else:
		print(message)

def start_transaction():
	# /!\ the transaction will run without confirmation /!\
	# you need to override Transaction.ask_confirmation() method
	# in order to implement your own confirmation step
	to_install = []
	to_remove = []
	to_load = []
	to_build = []
	overwrite_files = []
	if transaction.get_lock():
		transaction.start (to_install, to_remove, to_load, to_build, overwrite_files)
		# launch a loop to wait for finished signal to be emitted
		loop.run()

def on_trans_finished (transaction, success, data):
	transaction.unlock()
	loop.quit()

if __name__ == "__main__":
	loop = GLib.MainLoop()
	config = Pamac.Config(conf_path="/etc/pamac.conf")
	db = Pamac.Database(config=config)
	transaction = Pamac.Transaction(database=db)
	data = None
	transaction.connect ("emit-action", on_emit_action, data)
	transaction.connect ("emit-action-progress", on_emit_action_progress, data)
	transaction.connect ("emit-error", on_emit_error, data)
	transaction.connect ("emit-warning", on_emit_warning, data)
	transaction.connect ("finished", on_trans_finished, data)
	start_transaction()
