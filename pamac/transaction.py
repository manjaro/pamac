#! /usr/bin/python3
# -*- coding:utf-8 -*-

import pyalpm
import dbus
from gi.repository import Gtk
from dbus.mainloop.glib import DBusGMainLoop

from pamac import config, common

to_remove = set()
to_add = set()
to_update = set()
to_load = set()
handle = None
syncdbs =None
localdb = None

# i18n
import gettext
import locale
locale.bindtextdomain('pamac', '/usr/share/locale')
gettext.bindtextdomain('pamac', '/usr/share/locale')
gettext.textdomain('pamac')
_ = gettext.gettext

interface = Gtk.Builder()
interface.set_translation_domain('pamac')

interface.add_from_file('/usr/share/pamac/gui/dialogs.ui')
ErrorDialog = interface.get_object('ErrorDialog')
WarningDialog = interface.get_object('WarningDialog')
#InfoDialog = interface.get_object('InfoDialog')
#QuestionDialog = interface.get_object('QuestionDialog')
ConfDialog = interface.get_object('ConfDialog')
transaction_sum = interface.get_object('transaction_sum')
sum_top_label = interface.get_object('sum_top_label')
sum_bottom_label = interface.get_object('sum_bottom_label')
ChooseDialog = interface.get_object('ChooseDialog')
choose_list = interface.get_object('choose_list')
choose_label = interface.get_object('choose_label')
choose_renderertoggle = interface.get_object('choose_renderertoggle')
ProgressWindow = interface.get_object('ProgressWindow')
progress_bar = interface.get_object('progressbar2')
progress_label = interface.get_object('progresslabel2')
action_icon = interface.get_object('action_icon')
ProgressCancelButton = interface.get_object('ProgressCancelButton')
ProgressCloseButton = interface.get_object('ProgressCloseButton')
progress_textview = interface.get_object('progress_textview')
progress_expander = interface.get_object('progress_expander')

progress_buffer = progress_textview.get_buffer()

DBusGMainLoop(set_as_default = True)
bus = dbus.SystemBus()

def get_dbus_methods():
	proxy = bus.get_object('org.manjaro.pamac','/org/manjaro/pamac', introspect = False)
	global Refresh
	global Init
	global Sysupgrade
	global Remove
	global Add
	global Load
	global Prepare
	global To_Remove
	global To_Add
	global Commit
	global Interrupt
	global Release
	global StopDaemon
	Refresh = proxy.get_dbus_method('Refresh','org.manjaro.pamac')
	Init = proxy.get_dbus_method('Init','org.manjaro.pamac')
	Sysupgrade = proxy.get_dbus_method('Sysupgrade','org.manjaro.pamac')
	Remove = proxy.get_dbus_method('Remove','org.manjaro.pamac')
	Add = proxy.get_dbus_method('Add','org.manjaro.pamac')
	Load = proxy.get_dbus_method('Load','org.manjaro.pamac')
	Prepare = proxy.get_dbus_method('Prepare','org.manjaro.pamac')
	To_Remove = proxy.get_dbus_method('To_Remove','org.manjaro.pamac')
	To_Add = proxy.get_dbus_method('To_Add','org.manjaro.pamac')
	Commit = proxy.get_dbus_method('Commit','org.manjaro.pamac')
	Interrupt = proxy.get_dbus_method('Interrupt','org.manjaro.pamac')
	Release = proxy.get_dbus_method('Release','org.manjaro.pamac')
	StopDaemon = proxy.get_dbus_method('StopDaemon','org.manjaro.pamac')

def config_dbus_signals():
	bus.add_signal_receiver(action_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitAction")
	bus.add_signal_receiver(action_long_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitActionLong")
	bus.add_signal_receiver(icon_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitIcon")
	bus.add_signal_receiver(target_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitTarget")
	bus.add_signal_receiver(percent_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitPercent")
	bus.add_signal_receiver(need_details_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitNeedDetails")
	bus.add_signal_receiver(download_start_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitDownloadStart")
	bus.add_signal_receiver(transaction_start_handler, dbus_interface = "org.manjaro.pamac", signal_name = "EmitTransactionStart")
	bus.add_signal_receiver(log_error, dbus_interface = "org.manjaro.pamac", signal_name = "EmitLogError")
	bus.add_signal_receiver(log_warning, dbus_interface = "org.manjaro.pamac", signal_name = "EmitLogWarning")

def action_handler(action):
	progress_label.set_text(action)

def action_long_handler(action_long):
	global progress_buffer
	end_iter = progress_buffer.get_end_iter()
	progress_buffer.insert(end_iter, action_long)

def need_details_handler(need):
	progress_expander.set_expanded(need)

def icon_handler(icon):
	action_icon.set_from_file(icon)

def target_handler(target):
	progress_bar.set_text(target)

def percent_handler(percent):
	if percent > 1:
		progress_bar.pulse()
	else:
		progress_bar.set_fraction(percent)

def transaction_start_handler(msg):
	ProgressCancelButton.set_visible(False)
	ProgressWindow.show()
	while Gtk.events_pending():
		Gtk.main_iteration()

def download_start_handler(msg):
	ProgressWindow.show()
	while Gtk.events_pending():
		Gtk.main_iteration()

def log_error(msg):
	ErrorDialog.format_secondary_text(msg)
	response = ErrorDialog.run()
	while Gtk.events_pending():
		Gtk.main_iteration()
	if response:
		ErrorDialog.hide()

def log_warning(msg):
	WarningDialog.format_secondary_text(msg)
	response = WarningDialog.run()
	while Gtk.events_pending():
		Gtk.main_iteration()
	if response:
		WarningDialog.hide()

def choose_provides(data):
	virtual_dep = str(data[1])
	providers = data[0]
	choose_label.set_markup(_('<b>{pkgname} is provided by {number} packages.\nPlease choose the one(s) you want to install:</b>').format(pkgname = virtual_dep, number = str(len(providers))))
	choose_list.clear()
	for name in providers:
		choose_list.append([False, str(name)])
	lenght = len(to_add)
	ChooseDialog.run()
	if len(to_add) == lenght: # no choice was done by the user
		to_add.add(choose_list.get(choose_list.get_iter_first(), 1)[0]) # add first provider

def on_choose_renderertoggle_toggled(widget, line):
	choose_list[line][0] = not choose_list[line][0]

def on_ChooseButton_clicked(*arg):
	ChooseDialog.hide()
	while Gtk.events_pending():
		Gtk.main_iteration()
	for row in choose_list:
		if row[0] is True:
			to_add.add(row[1].split(':')[0]) # split done in case of optdep choice

def on_progress_textview_size_allocate(*arg):
	#auto-scrolling method
	adj = progress_textview.get_vadjustment()
	adj.set_value(adj.get_upper() - adj.get_page_size())

def get_handle():
	global handle
	handle = config.handle()
	print('get handle')

def update_dbs():
	global handle
	global syncdbs
	global localdb
	handle = config.handle()
	syncdbs = handle.get_syncdbs()
	localdb = handle.get_localdb()

def get_localpkg(name):
	return localdb.get_pkg(name)

def get_syncpkg(name):
	for repo in syncdbs:
		pkg = repo.get_pkg(name)
		if pkg:
			return pkg

def refresh(force_update):
	progress_label.set_text(_('Refreshing')+'...')
	action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/refresh-cache.png')
	progress_bar.set_text('')
	progress_bar.set_fraction(0)
	ProgressCancelButton.set_visible(True)
	ProgressCloseButton.set_visible(False)
	while Gtk.events_pending():
		Gtk.main_iteration()
	Refresh(force_update)

def init_transaction(**options):
	return Init(dbus.Dictionary(options, signature='sb'))

def run():
	if to_add | to_remove | to_load:
		error = ''
		trans_flags = {'cascade' : True}
		error += init_transaction(**trans_flags)
		if not error:
			for name in to_add:
				error += Add(name)
			for name in to_remove:
				error += Remove(name)
			for path in to_load:
				error += Load(path)
			if not error:
				error += prepare(False, **trans_flags)
		if error:
			Release()
			return(error)
	else:
		return (_('Nothing to do'))

def prepare(show_updates, **trans_flags):
	global to_add
	error = ''
	ret = Prepare()
	if ret[0][0]: # providers are emitted
		Release()
		for item in ret:
			choose_provides(item)
		error += init_transaction(**trans_flags)
		if not error:
			for name in to_add:
				error += Add(name)
			for name in to_remove:
				error += Remove(name)
			for path in to_load:
				error += Load(path)
			if not error:
				ret = Prepare()
				if ret[0][1]:
					error = str(ret[0][1])
	elif ret[0][1]: # an error is emitted
		error = str(ret[0][1])
	if not error:
		set_transaction_sum(show_updates)
		if show_updates:
			ConfDialog.show_all()
			while Gtk.events_pending():
				Gtk.main_iteration()
		else:
			if len(transaction_sum) != 0:
				ConfDialog.show_all()
				while Gtk.events_pending():
					Gtk.main_iteration()
			else:
				finalize()
	return(error)

def finalize():
	global progress_buffer
	progress_label.set_text(_('Preparing')+'...')
	action_icon.set_from_file('/usr/share/pamac/icons/24x24/status/package-setup.png')
	progress_bar.set_text('')
	progress_bar.set_fraction(0)
	progress_buffer.delete(progress_buffer.get_start_iter(), progress_buffer.get_end_iter())
	ProgressCancelButton.set_visible(True)
	ProgressCloseButton.set_visible(False)
	#~ try:
	Commit()
	#~ except dbus.exceptions.DBusException as e:
		#~ handle_error(str(e))
	while Gtk.events_pending():
		Gtk.main_iteration()

def get_updates():
	do_syncfirst = False
	list_first = []
	_ignorepkgs = set()
	if handle:
		for group in handle.ignoregrps:
			db = localdb
			grp = db.read_grp(group)
			if grp:
				name, pkg_list = grp
				for pkg in pkg_list:
					_ignorepkgs.add(pkg.name)
		for name in handle.ignorepkgs:
			if get_localpkg(name):
				_ignorepkgs.add(name)
	if config.syncfirst:
		for name in config.syncfirst:
			pkg = get_localpkg(name)
			if pkg:
				candidate = pyalpm.sync_newversion(pkg, syncdbs)
				if candidate:
					list_first.append(candidate)
		if list_first:
			do_syncfirst = True
			return do_syncfirst, list_first
	result = []
	for pkg in localdb.pkgcache:
		candidate = pyalpm.sync_newversion(pkg, syncdbs)
		if candidate:
			if not candidate.name in _ignorepkgs:
				result.append(candidate)
	return do_syncfirst, result

def get_transaction_sum():
	transaction_dict = {'to_remove': [], 'to_install': [], 'to_update': [], 'to_reinstall': [], 'to_downgrade': []}
	to_remove = sorted(To_Remove())
	for name, version in to_remove:
		transaction_dict['to_remove'].append(name+' '+version)
	others = sorted(To_Add())
	for name, version, dsize in others:
		pkg = get_localpkg(name)
		if pkg:
			comp = pyalpm.vercmp(version, pkg.version)
			if comp == 1:
				transaction_dict['to_update'].append((name+' '+version, dsize))
			elif comp == 0:
				transaction_dict['to_reinstall'].append((name+' '+version, dsize))
			elif comp == -1:
				transaction_dict['to_downgrade'].append((name+' '+version, dsize))
		else:
			transaction_dict['to_install'].append((name+' '+version, dsize))
	#~ if transaction_dict['to_install']:
		#~ print('To install:', [name for name, size in transaction_dict['to_install']])
	#~ if transaction_dict['to_reinstall']:
		#~ print('To reinstall:', [name for name, size in transaction_dict['to_reinstall']])
	#~ if transaction_dict['to_downgrade']:
		#~ print('To downgrade:', [name for name, size in transaction_dict['to_downgrade']])
	#~ if transaction_dict['to_remove']:
		#~ print('To remove:', [name for name in transaction_dict['to_remove']])
	#~ if transaction_dict['to_update']:
		#~ print('To update:', [name for name, size in transaction_dict['to_update']])
	return transaction_dict

def set_transaction_sum(show_updates):
	transaction_sum.clear()
	transaction_dict = get_transaction_sum()
	sum_top_label.set_markup(_('<big><b>Transaction Summary</b></big>'))
	if transaction_dict['to_install']:
		transaction_sum.append([_('To install')+':', transaction_dict['to_install'][0][0]])
		i = 1
		while i < len(transaction_dict['to_install']):
			transaction_sum.append([' ', transaction_dict['to_install'][i][0]])
			i += 1
	if transaction_dict['to_reinstall']:
		transaction_sum.append([_('To reinstall')+':', transaction_dict['to_reinstall'][0][0]])
		i = 1
		while i < len(transaction_dict['to_reinstall']):
			transaction_sum.append([' ', transaction_dict['to_reinstall'][i][0]])
			i += 1
	if transaction_dict['to_downgrade']:
		transaction_sum.append([_('To downgrade')+':', transaction_dict['to_downgrade'][0][0]])
		i = 1
		while i < len(transaction_dict['to_downgrade']):
			transaction_sum.append([' ', transaction_dict['to_downgrade'][i][0]])
			i += 1
	if transaction_dict['to_remove']:
		transaction_sum.append([_('To remove')+':', transaction_dict['to_remove'][0]])
		i = 1
		while i < len(transaction_dict['to_remove']):
			transaction_sum.append([' ', transaction_dict['to_remove'][i]])
			i += 1
	if show_updates:
		if transaction_dict['to_update']:
			transaction_sum.append([_('To update')+':', transaction_dict['to_update'][0][0]])
			i = 1
			while i < len(transaction_dict['to_update']):
				transaction_sum.append([' ', transaction_dict['to_update'][i][0]])
				i += 1
	dsize = 0
	for nameversion, size in transaction_dict['to_install'] + transaction_dict['to_update'] + transaction_dict['to_reinstall'] + transaction_dict['to_downgrade']:
		dsize += size
	if dsize == 0:
		sum_bottom_label.set_markup('')
	else:
		sum_bottom_label.set_markup(_('<b>Total download size: </b>')+common.format_size(dsize))

def sysupgrade(show_updates):
	global to_update
	global to_add
	global to_remove
	do_syncfirst, updates = get_updates()
	if updates:
		to_update = set([pkg.name for pkg in updates])
		to_add.clear()
		to_remove.clear()
		error = ''
		if do_syncfirst:
			error += init_transaction()
			if not error:
				for name in to_update:
					error += Add(name)
		else:
			error += init_transaction()
			if not error:
				error += Sysupgrade()
		if not error:
			error += prepare(show_updates)
		if error:
			Release()
		return error
