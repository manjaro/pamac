#! /usr/bin/python
# -*-coding:utf-8 -*-

from gi.repository import Gtk

from pamac import config, common, transaction

interface = Gtk.Builder()
interface.add_from_file('/usr/share/pamac/gui/updater.glade')
#interface.add_from_file('/usr/share/pamac/gui/dialogs.glade')

UpdateWindow = interface.get_object("UpdateWindow")

ConfDialog = interface.get_object('ConfDialog')
transaction_add = interface.get_object('transaction_add')
top_label = interface.get_object('top_label')
bottom_label = interface.get_object('bottom_label')
update_listore = interface.get_object('update_list')
update_label = interface.get_object('update_label')

def do_refresh():
	"""Sync databases like pacman -Sy"""
	transaction.get_handle()
	if transaction.t_lock is False:
		transaction.t_lock = True
		transaction.progress_label.set_text('Refreshing...')
		transaction.action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/refresh-cache.png')
		transaction.ProgressWindow.show_all()
		while Gtk.events_pending():
			Gtk.main_iteration()
		transaction.Refresh(reply_handler = handle_reply, error_handler = handle_error, timeout = 2000*1000)

def have_updates():
	available_updates = transaction.get_updates()
	update_listore.clear()
	update_label.set_justify(Gtk.Justification.CENTER)
	if not available_updates:
		update_listore.append(["", ""])
		update_label.set_markup("<big><b>No update available</b></big>")
		return False
	else:
		for pkg in available_updates:
			pkgname = pkg.name
			newversion = transaction.get_new_version_available(pkgname)
			pkgname = pkg.name+" "+newversion
			update_listore.append([pkgname, common.format_size(pkg.size)])
		update_label.set_markup("<big><b>Available updates</b></big>")
		return True

def set_transaction_add():
	transaction_add.clear()
	if transaction.to_remove:
		transaction_add.append(['To remove:', transaction.to_remove[0]])
		i = 1
		while i < len(transaction.to_remove):
			transaction_add.append([' ', transaction.to_remove[i]])
			i += 1
		bottom_label.set_markup('')
	if transaction.to_add:
		installed_name = []
		for pkg_object in transaction.handle.get_localdb().pkgcache:
			installed_name.append(pkg_object.name)
		transaction.to_update = sorted(set(installed_name).intersection(transaction.to_add))
		to_remove_from_add_name = sorted(set(transaction.to_update).intersection(transaction.to_add))
		for name in to_remove_from_add_name:
			transaction.to_add.remove(name)
		if transaction.to_add:
			transaction_add.append(['To install:', transaction.to_add[0]])
			i = 1
			while i < len(transaction.to_add):
				transaction_add.append([' ', transaction.to_add[i]])
				i += 1
		bottom_label.set_markup('')
		#bottom_label.set_markup('<b>Total Download size: </b>'+format_size(totaldlcb))
	top_label.set_markup('<big><b>Additionnal Transaction(s)</b></big>')

def do_sysupgrade():
	"""Upgrade a system like pacman -Su"""
	if transaction.t_lock is False:
		if transaction.do_syncfirst is True:
			if transaction.init_transaction(recurse = True):
				for pkg in transaction.list_first:
					transaction.Add(pkg.name)
				transaction.get_to_remove()
				transaction.get_to_add()
				set_transaction_add()
				if len(transaction.to_add) + len(transaction.to_remove) != 0:
					ConfDialog.show_all()
				else:
					finalize()
		else:
			if transaction.init_transaction():
				error = transaction.Sysupgrade()
				if error:
					transaction.ErrorDialog.format_secondary_text(error)
					response = transaction.ErrorDialog.run()
					if response:
						transaction.ErrorDialog.hide()
					transaction.Release()
					transaction.t_lock = False
				transaction.get_to_remove()
				transaction.get_to_add()
				transaction.check_conflicts()
				transaction.Release()
				if len(transaction.to_add) == 0:
					transaction.t_lock = False
					print("Nothing to update")
				else:
					if transaction.init_transaction(noconflicts = True):
						for pkgname in transaction.to_update:
							transaction.Add(pkgname)
						for pkgname in transaction.to_add:
							transaction.Add(pkgname)
						for pkgname in transaction.to_remove:
							transaction.Remove(pkgname)
						set_transaction_add()
						if len(transaction.to_add) + len(transaction.to_remove) != 0:
							ConfDialog.show_all()
						else:
							finalize()

def finalize():
	error = transaction.Prepare()
	if error:
		transaction.ErrorDialog.format_secondary_text(error)
		response = transaction.ErrorDialog.run()
		if response:
			transaction.ErrorDialog.hide()
		transaction.Release()
		transaction.t_lock = False
	else:
		transaction.progress_label.set_text('Preparing...')
		transaction.action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/setup.png')
		transaction.ProgressWindow.show_all()
		while Gtk.events_pending():
			Gtk.main_iteration()
		transaction.Commit(reply_handler = handle_reply, error_handler = handle_error, timeout = 2000*1000)

def handle_error(error):
	if not 'DBus.Error.NoReply' in str(error):
		transaction.ErrorDialog.format_secondary_text('Commit Error:\n'+str(error))
		response = transaction.ErrorDialog.run()
		if response:
			transaction.ErrorDialog.hide()
	transaction.t_lock = False
	transaction.Release()
	transaction.ProgressWindow.hide()
	have_updates()

def handle_reply(reply):
	if str(reply):
		transaction.ErrorDialog.format_secondary_text('Commit Error:\n'+str(reply))
		response = transaction.ErrorDialog.run()
		if response:
			transaction.ErrorDialog.hide()
	if transaction.do_syncfirst is True:
		transaction.do_syncfirst = False
		transaction.list_first = []
	transaction.t_lock = False
	transaction.Release()
	transaction.ProgressWindow.hide()
	have_updates()

class Handler:
	def on_UpdateWindow_delete_event(self, *arg):
		transaction.StopDaemon()
		if __name__ == "__main__":
			Gtk.main_quit()
		else:
			UpdateWindow.hide()

	def on_QuitButton_clicked(self, *arg):
		transaction.StopDaemon()
		if __name__ == "__main__":
			Gtk.main_quit()
		else:
			UpdateWindow.hide()

	def on_ApplyButton_clicked(self, *arg):
		do_sysupgrade()

	def on_RefreshButton_clicked(self, *arg):
		transaction.do_refresh()
		#have_updates()

	def on_TransCancelButton_clicked(self, *arg):
		ConfDialog.hide()
		transaction.t_lock = False
		transaction.Release()

	def on_TransValidButton_clicked(self, *arg):
		ConfDialog.hide()
		finalize()

	def on_ProgressCancelButton_clicked(self, *arg):
		transaction.t_lock = False
		transaction.Release()
		transaction.ProgressWindow.hide()
		have_updates()

def main():
	do_refresh()
	#have_updates()
	update_label.set_markup("<big><b>Available updates</b></big>")
	interface.connect_signals(Handler())
	UpdateWindow.show_all()
	while Gtk.events_pending():
		Gtk.main_iteration()

if __name__ == "__main__":
	main()
	Gtk.main()
