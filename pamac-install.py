#! /usr/bin/pkexec /usr/bin/python3
# -*- coding:utf-8 -*-

from gi.repository import Gtk
from sys import argv
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
	print('exiting')
	loop.quit()

def on_ProgressCloseButton_clicked(*args):
	transaction.ProgressWindow.hide()
	transaction.progress_buffer.delete(transaction.progress_buffer.get_start_iter(),transaction.progress_buffer.get_end_iter())
	common.rm_pid_file()
	Gtk.main_quit()

def on_ProgressCancelButton_clicked(*args):
	trans.interrupt()

def on_TransCancelButton_clicked(self, *arg):
	transaction.ConfDialog.hide()
	trans.release()
	common.rm_pid_file()
	Gtk.main_quit()

def on_TransValidButton_clicked(self, *arg):
	transaction.ConfDialog.hide()
	trans.finalize()
	common.rm_pid_file()
	Gtk.main_quit()

def get_pkgs(pkgstr_list):
	get_error = ''
	for pkgstr in pkgstr_list:
		if '.pkg.tar.' in pkgstr:
			full_path = abspath(pkgstr)
			trans.to_load.append(full_path)
		else:
			pkg = trans.get_syncpkg(pkgstr)
			if pkg:
				trans.to_add.append(pkg)
			else:
				if get_error:
					get_error += '\n'
				get_error += _('{pkgname} is not a valid path or package name').format(pkgname = pkgstr)
	if get_error:
		trans.handle_error(get_error)
		return False
	else:
		return True

signals = {'on_TransValidButton_clicked' : on_TransValidButton_clicked,
		'on_TransCancelButton_clicked' : on_TransCancelButton_clicked,
		'on_ChooseButton_clicked' : transaction.on_ChooseButton_clicked,
		'on_progress_textview_size_allocate' : transaction.on_progress_textview_size_allocate,
		'on_choose_renderertoggle_toggled' : transaction.on_choose_renderertoggle_toggled,
		'on_ProgressCancelButton_clicked' : on_ProgressCancelButton_clicked,
		'on_ProgressCloseButton_clicked' : on_ProgressCloseButton_clicked}

if common.pid_file_exists():
	transaction.ErrorDialog.format_secondary_text(_('Pamac is already running'))
	response = transaction.ErrorDialog.run()
	if response:
		transaction.ErrorDialog.hide()
else:
	trans = transaction.Transaction()
	do_syncfirst, updates = trans.get_updates()
	if updates:
		transaction.ErrorDialog.format_secondary_text(_('Some updates are available.\nPlease update your system first'))
		response = transaction.ErrorDialog.run()
		if response:
			transaction.ErrorDialog.hide()
	else:
		transaction.interface.connect_signals(signals)
		args_str = argv[1:]
		if get_pkgs(args_str):
			if trans.to_add or trans.to_load:
				if trans.check_extra_modules():
					if trans.init(cascade = True):
						for pkg in trans.to_add:
							trans.add(pkg)
						for path in trans.to_load:
							trans.load(path)
						if trans.prepare():
							common.write_pid_file()
							trans.set_transaction_sum(True)
							transaction.ConfDialog.show()
							Gtk.main()
	
