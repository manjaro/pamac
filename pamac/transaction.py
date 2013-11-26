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

import pyalpm
from gi.repository import Gtk, GObject
from time import sleep
import subprocess
import os
import fnmatch
#import requests
#from ftplib import FTP
#from urllib.parse import urlparse
import dbus
from dbus.mainloop.glib import DBusGMainLoop

from pamac import config, common, aur

to_remove = set()
to_add = set()
to_mark_as_dep = set()
to_update = set()
to_load = set()
available_updates = (False, [])
to_build = []
cancel_download = False
build_proc = None
make_depends = set()
base_devel = ('autoconf', 'automake', 'binutils', 'bison', 'fakeroot', 
				'file', 'findutils', 'flex', 'gawk', 'gcc', 'gettext', 
				'grep', 'groff', 'gzip', 'libtool', 'm4', 'make', 'patch', 
				'pkg-config', 'sed', 'sudo', 'texinfo', 'util-linux', 'which')
build_depends = set()
handle = None
syncdbs = None
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
progress_expander = interface.get_object('progress_expander')
progress_textview = interface.get_object('progress_textview')

progress_buffer = progress_textview.get_buffer()

DBusGMainLoop(set_as_default = True)
bus = dbus.SystemBus()

def get_dbus_methods():
	proxy = bus.get_object('org.manjaro.pamac','/org/manjaro/pamac', introspect = False)
	global Refresh
	global CheckUpdates
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
	global SetPkgReason
	SetPkgReason = proxy.get_dbus_method('SetPkgReason','org.manjaro.pamac')
	Refresh = proxy.get_dbus_method('Refresh','org.manjaro.pamac')
	CheckUpdates = proxy.get_dbus_method('CheckUpdates','org.manjaro.pamac')
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

def write_to_buffer(fd, condition):
	if condition == GObject.IO_IN: # if there's something interesting to read
		line = fd.readline().decode(encoding='UTF-8')
		#print(line.rstrip('\n'))
		progress_buffer.insert_at_cursor(line)
		progress_bar.pulse()
		while Gtk.events_pending():
			Gtk.main_iteration()
		return True # FUNDAMENTAL, otherwise the callback isn't recalled
	else:
		return False # Raised an error: exit

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
	choose_label.set_markup('<b>{}</b>'.format(_('{pkgname} is provided by {number} packages.\nPlease choose those you would like to install:').format(pkgname = virtual_dep, number = str(len(providers)))))
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

def refresh(force_update = False):
	while Gtk.events_pending():
		Gtk.main_iteration()
	action_handler(_('Refreshing')+'...')
	icon_handler('/usr/share/pamac/icons/24x24/status/refresh-cache.png')
	target_handler('')
	percent_handler(0)
	ProgressCancelButton.set_visible(True)
	ProgressCloseButton.set_visible(False)
	progress_expander.set_visible(True)
	ProgressWindow.show()
	while Gtk.events_pending():
		Gtk.main_iteration()
	Refresh(force_update)

def init_transaction(**options):
	return Init(dbus.Dictionary(options, signature='sb'))

def check_to_build():
	global to_build
	global to_add
	global to_mark_as_dep
	global make_depends
	global build_depends
	make_depends = set()
	builds_depends = set()
	# check if base_devel packages are installed
	for name in base_devel:
		if not pyalpm.find_satisfier(localdb.pkgcache, name):
			make_depends.add(name)
	already_checked = set()
	build_order = []
	i = 0
	error = ''
	while i < len(to_build):
		while Gtk.events_pending():
			Gtk.main_iteration()
		pkg = to_build[i]
		# if current pkg is not in build_order add it at the end of the list
		if not pkg.name in build_order:
			build_order.append(pkg.name)
		# download end extract tarball from AUR
		srcdir = aur.get_extract_tarball(pkg)
		if srcdir:
			# get PKGBUILD and parse it to create a new pkg object with makedeps and deps 
			new_pkgs = aur.get_pkgs(srcdir + '/PKGBUILD')
			for new_pkg in new_pkgs:
				while Gtk.events_pending():
					Gtk.main_iteration()
				print('checking', new_pkg.name)
				# check if some makedeps must be installed
				for makedepend in new_pkg.makedepends:
					while Gtk.events_pending():
						Gtk.main_iteration()
					if not makedepend in already_checked:
						if not pyalpm.find_satisfier(localdb.pkgcache, makedepend):
							print('found make dep:',makedepend)
							for db in syncdbs:
								provider = pyalpm.find_satisfier(db.pkgcache, makedepend)
								if provider:
									break
							if provider:
								make_depends.add(provider.name)
								already_checked.add(makedepend)
							else:
								# current makedep need to be built
								raw_makedepend = common.format_pkg_name(makedepend)
								if raw_makedepend in build_order:
									# add it in build_order before pkg
									build_order.remove(raw_makedepend)
									index = build_order.index(pkg.name)
									build_order.insert(index, raw_makedepend)
								else:
									# get infos about it
									makedep_pkg = aur.info(raw_makedepend)
									if makedep_pkg:
										# add it in to_build so it will be checked 
										to_build.append(makedep_pkg)
										# add it in build_order before pkg
										index = build_order.index(pkg.name)
										build_order.insert(index, raw_makedepend)
										# add it in already_checked and to_add_as_as_dep 
										already_checked.add(raw_makedepend)
										to_mark_as_dep.add(raw_makedepend)
									else:
										if error:
											error += '\n'
										error += _('{pkgname} depends on {dependname} but it is not installable').format(pkgname = pkg.name, dependname = makedepend)
				# check if some deps must be installed or built
				for depend in new_pkg.depends:
					while Gtk.events_pending():
						Gtk.main_iteration()
					if not depend in already_checked:
						if not pyalpm.find_satisfier(localdb.pkgcache, depend):
							print('found dep:',depend)
							for db in syncdbs:
								provider = pyalpm.find_satisfier(db.pkgcache, depend)
								if provider:
									break
							if provider:
								# current dep need to be installed
								build_depends.add(provider.name)
								already_checked.add(depend)
							else:
								# current dep need to be built
								raw_depend = common.format_pkg_name(depend)
								if raw_depend in build_order:
									# add it in build_order before pkg
									build_order.remove(raw_depend)
									index = build_order.index(pkg.name)
									build_order.insert(index, raw_depend)
								else:
									# get infos about it
									dep_pkg = aur.info(raw_depend)
									if dep_pkg:
										# add it in to_build so it will be checked 
										to_build.append(dep_pkg)
										# add it in build_order before pkg
										index = build_order.index(pkg.name)
										build_order.insert(index, raw_depend)
										# add it in already_checked and to_add_as_as_dep 
										already_checked.add(raw_depend)
										to_mark_as_dep.add(raw_depend)
									else:
										if error:
											error += '\n'
										error += _('{pkgname} depends on {dependname} but it is not installable').format(pkgname = pkg.name, dependname = depend)
		else:
			if error:
				error += '\n'
			error += _('Failed to get {pkgname} archive from AUR').format(pkgname = pkg.name)
		i += 1
	if error:
		return error
	# add pkgname in make_depends and build_depends in to_add and to_mark_as_dep
	for name in make_depends:
		to_add.add(name)
		to_mark_as_dep.add(name)
	for name in build_depends:
		to_add.add(name)
		to_mark_as_dep.add(name)
	# reorder to_build following build_order
	to_build.sort(key = lambda pkg: build_order.index(pkg.name))
	print('order:', build_order)
	print('to build:',to_build)
	print('makedeps:',make_depends)
	print('builddeps:',build_depends)
	return error

def run():
	if to_add or to_remove or to_load or to_build:
		global progress_buffer
		action_handler(_('Preparing')+'...')
		icon_handler('/usr/share/pamac/icons/24x24/status/package-setup.png')
		target_handler('')
		percent_handler(0)
		progress_buffer.delete(progress_buffer.get_start_iter(), progress_buffer.get_end_iter())
		ProgressCancelButton.set_visible(False)
		ProgressCloseButton.set_visible(False)
		progress_expander.set_visible(False)
		ProgressWindow.show()
		while Gtk.events_pending():
			Gtk.main_iteration()
		# we need to give some time a the window to refresh
		sleep(0.1)
		error = ''
		if to_build:
			# check if packages in to_build have deps or makedeps which need to be install first 
			error += check_to_build()
		if not error:
			if to_add or to_remove or to_load:
				while Gtk.events_pending():
					Gtk.main_iteration()
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
						error += prepare(**trans_flags)
			if not error:
				set_transaction_sum()
				ProgressWindow.hide()
				ConfDialog.show_all()
				while Gtk.events_pending():
					Gtk.main_iteration()
		if error:
			ProgressWindow.hide()
			Release()
			return(error)
	else:
		return (_('Nothing to do'))

def prepare(**trans_flags):
	error = ''
	ret = Prepare()
	# ret type is a(ass) so [([''], '')]
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
	return(error)

def check_finished_build(data):
	global to_build
	global build_proc
	path = data[0]
	pkg = data[1]
	if build_proc.poll() is None:
		print('pulse')
		progress_bar.pulse()
		while Gtk.events_pending():
			Gtk.main_iteration()
		return True
	elif build_proc.poll() == 0:
		built = []
		# parse again PKGBUILD to have new pkg objects in case of a pkgver() function
		# was used so pkgver was changed during build process
		new_pkgs = aur.get_pkgs(path + '/PKGBUILD')
		# find built packages
		for new_pkg in new_pkgs:
			for item in os.listdir(path):
				if os.path.isfile(os.path.join(path, item)):
					# add a * before pkgver if there an epoch variable
					if fnmatch.fnmatch(item, '{}-*{}-*.pkg.tar.?z'.format(new_pkg.name, new_pkg.version)):
						built.append(os.path.join(path, item))
						break
		if built:
			print('successfully built:', built)
			build_proc = None
			if pkg in to_build:
				to_build.remove(pkg)
			# install built packages
			error = ''
			error += init_transaction()
			if not error:
				for pkg_path in built:
					error += Load(pkg_path)
				if not error:
					error += prepare()
					if not error:
						if To_Remove():
							set_transaction_sum()
							ConfDialog.show_all()
							while Gtk.events_pending():
								Gtk.main_iteration()
						else:
							finalize()
				if error:
					Release()
					ProgressCancelButton.set_visible(False)
					ProgressCloseButton.set_visible(True)
					ErrorDialog.format_secondary_text(error)
					response = ErrorDialog.run()
					if response:
						ErrorDialog.hide()
		else:
			ProgressCancelButton.set_visible(False)
			ProgressCloseButton.set_visible(True)
			action_long_handler(_('Build process failed.'))
		return False
	elif build_proc.poll() == 1:
		ProgressCancelButton.set_visible(False)
		ProgressCloseButton.set_visible(True)
		action_long_handler(_('Build process failed.'))
		return False

def download(url_list, path):
	def write_file(chunk):
		nonlocal transferred
		nonlocal f
		if cancel_download:
			if ftp:
				ftp.quit()
			raise Exception('Download cancelled')
			return
		f.write(chunk)
		transferred += len(chunk)
		if total_size > 0:
			percent = round(transferred/total_size, 2)
			percent_handler(percent)
			if transferred <= total_size:
				target = '{transferred}/{size}'.format(transferred = common.format_size(transferred), size = common.format_size(total_size))
			else:
				target = ''
			target_handler(target)
		while Gtk.events_pending():
			Gtk.main_iteration()
	
	global cancel_download
	cancel_download = False
	ftp = None
	total_size = 0
	transferred = 0
	icon_handler('/usr/share/pamac/icons/24x24/status/package-download.png')
	ProgressCancelButton.set_visible(True)
	ProgressCloseButton.set_visible(False)
	parsed_urls = []
	for url in url_list:
		url_components = urlparse(url)
		if url_components.scheme:
			parsed_urls.append(url_components)
	print(parsed_urls)
	for url_components in parsed_urls:
		if url_components.scheme == 'http':
			total_size += int(requests.get(url).headers['Content-Length'])
		elif url_components.scheme == 'ftp':
			ftp = FTP(url_components.netloc)
			ftp.login('anonymous', '')
			total_size += int(ftp.size(url_components.path))
	print(total_size)
	for url_components in parsed_urls:
		filename = url_components.path.split('/')[-1]
		print(filename)
		action = _('Downloading {pkgname}').format(pkgname = filename)+'...'
		action_long = action+'\n'
		action_handler(action)
		action_long_handler(action_long)
		ProgressWindow.show()
		while Gtk.events_pending():
			Gtk.main_iteration()
		with open(os.path.join(path, filename), 'wb') as f:
			if url_components.scheme == 'http':
				try:
					r = requests.get(url, stream = True)
					for chunk in r.iter_content(1024):
						if cancel_download:
							raise Exception('Download cancelled')
							break
						else:
							write_file(chunk)
				except Exception as e:
					print(e)
					cancel_download = False
			elif url_components.scheme == 'ftp':
				try:
					ftp = FTP(url_components.netloc)
					ftp.login('anonymous', '') 
					ftp.retrbinary('RETR '+url_components.path, write_file, blocksize=1024)
				except Exception as e:
					print(e)
					cancel_download = False

def build_next():
	global build_proc
	pkg = to_build[0]
	path = os.path.join(aur.srcpkgdir, pkg.name)
	new_pkgs = aur.get_pkgs(path + '/PKGBUILD')
	# sources are identicals for splitted packages
	# (not complete) download(new_pkgs[0].source, path)
	action = _('Building {pkgname}').format(pkgname = pkg.name)+'...'
	action_handler(action)
	action_long_handler(action+'\n')
	icon_handler('/usr/share/pamac/icons/24x24/status/package-setup.png')
	target_handler('')
	percent_handler(0)
	ProgressCancelButton.set_visible(True)
	ProgressCloseButton.set_visible(False)
	progress_expander.set_visible(True)
	progress_expander.set_expanded(True)
	ProgressWindow.show()
	build_proc = subprocess.Popen(["makepkg", "-cf"], cwd = path, stdout = subprocess.PIPE, stderr=subprocess.STDOUT)
	#GObject.io_add_watch(build_proc.stdout, GObject.IO_IN, write_to_buffer)
	while Gtk.events_pending():
		Gtk.main_iteration()
	GObject.timeout_add(500, check_finished_build, (path, pkg))

def finalize():
	if To_Add() or To_Remove():
		global progress_buffer
		action_handler(_('Preparing')+'...')
		icon_handler('/usr/share/pamac/icons/24x24/status/package-setup.png')
		target_handler('')
		percent_handler(0)
		progress_buffer.delete(progress_buffer.get_start_iter(), progress_buffer.get_end_iter())
		ProgressCancelButton.set_visible(True)
		ProgressCloseButton.set_visible(False)
		progress_expander.set_visible(True)
		try:
			Commit()
		except dbus.exceptions.DBusException as e:
			Release()
	elif to_build:
		# packages in to_build have no deps or makedeps 
		# so we build and install the first one
		# the next ones will be built by the caller
		build_next()

def mark_needed_pkgs_as_dep():
	global to_mark_as_dep
	for name in to_mark_as_dep.copy():
		if get_localpkg(name):
			error = SetPkgReason(name, pyalpm.PKG_REASON_DEPEND)
			if error:
				print(error)
			else:
				to_mark_as_dep.discard(name)

def get_updates():
	while Gtk.events_pending():
		Gtk.main_iteration()
	action_handler(_('Checking for updates')+'...')
	icon_handler('/usr/share/pamac/icons/24x24/status/package-search.png')
	target_handler('')
	percent_handler(0)
	ProgressCancelButton.set_visible(False)
	ProgressCloseButton.set_visible(False)
	progress_expander.set_visible(False)
	ProgressWindow.show()
	while Gtk.events_pending():
		Gtk.main_iteration()
	CheckUpdates()

def get_transaction_sum():
	transaction_dict = {'to_remove': [], 'to_build': [], 'to_install': [], 'to_update': [], 'to_reinstall': [], 'to_downgrade': []}
	for pkg in to_build:
		transaction_dict['to_build'].append(pkg.name+' '+pkg.version)
	_to_remove = sorted(To_Remove())
	for name, version in _to_remove:
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
	#~ if transaction_dict['to_build']:
		#~ print('To build:', [name for name in transaction_dict['to_build']])
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

def set_transaction_sum(show_updates = True):
	dsize = 0
	transaction_sum.clear()
	transaction_dict = get_transaction_sum()
	sum_top_label.set_markup('<big><b>{}</b></big>'.format(_('Transaction Summary')))
	if transaction_dict['to_remove']:
		transaction_sum.append([_('To remove')+':', transaction_dict['to_remove'][0]])
		i = 1
		while i < len(transaction_dict['to_remove']):
			transaction_sum.append(['', transaction_dict['to_remove'][i]])
			i += 1
	if transaction_dict['to_downgrade']:
		transaction_sum.append([_('To downgrade')+':', transaction_dict['to_downgrade'][0][0]])
		i = 1
		while i < len(transaction_dict['to_downgrade']):
			transaction_sum.append(['', transaction_dict['to_downgrade'][i][0]])
			dsize += transaction_dict['to_downgrade'][i][1]
			i += 1
	if transaction_dict['to_build']:
		transaction_sum.append([_('To build')+':', transaction_dict['to_build'][0]])
		i = 1
		while i < len(transaction_dict['to_build']):
			transaction_sum.append(['', transaction_dict['to_build'][i]])
			i += 1
	if transaction_dict['to_install']:
		transaction_sum.append([_('To install')+':', transaction_dict['to_install'][0][0]])
		i = 1
		while i < len(transaction_dict['to_install']):
			transaction_sum.append(['', transaction_dict['to_install'][i][0]])
			dsize += transaction_dict['to_install'][i][1]
			i += 1
	if transaction_dict['to_reinstall']:
		transaction_sum.append([_('To reinstall')+':', transaction_dict['to_reinstall'][0][0]])
		i = 1
		while i < len(transaction_dict['to_reinstall']):
			transaction_sum.append(['', transaction_dict['to_reinstall'][i][0]])
			dsize += transaction_dict['to_reinstall'][i][1]
			i += 1
	if show_updates:
		if transaction_dict['to_update']:
			transaction_sum.append([_('To update')+':', transaction_dict['to_update'][0][0]])
			i = 1
			while i < len(transaction_dict['to_update']):
				transaction_sum.append(['', transaction_dict['to_update'][i][0]])
				dsize += transaction_dict['to_update'][i][1]
				i += 1
	if dsize == 0:
		sum_bottom_label.set_markup('')
	else:
		sum_bottom_label.set_markup('<b>{} {}</b>'.format(_('Total download size:'), common.format_size(dsize)))

def sysupgrade(show_updates = True):
	global to_update
	global to_add
	global to_remove
	syncfirst, updates = available_updates
	if updates:
		to_update.clear()
		to_add.clear()
		to_remove.clear()
		for name, version, db, tarpath, size in updates:
			if db == 'AUR':
				# call AURPkg constructor directly to avoid a request to AUR
				infos = {'name': name, 'version': version, 'Description': '', 'URLPath': tarpath}
				pkg = aur.AURPkg(infos)
				to_build.append(pkg)
			else:
				to_update.add(name)
		error = ''
		if syncfirst:
			error += init_transaction()
			if not error:
				for name in to_update:
					error += Add(name)
					if not error:
						error += prepare()
		else:
			if to_build:
				# check if packages in to_build have deps or makedeps which need to be install first 
				# grab errors differently here to not break regular updates
				_error = check_to_build()
			if to_update or to_add:
				error += init_transaction()
				if not error:
					if to_update:
						error += Sysupgrade()
					_error = ''
					for name in to_add:
						_error += Add(name)
					if _error:
						print(_error)
					if not error:
						error += prepare()
		if not error:
			set_transaction_sum(show_updates = show_updates)
			if show_updates:
				ProgressWindow.hide()
				ConfDialog.show_all()
				while Gtk.events_pending():
					Gtk.main_iteration()
			else:
				if len(transaction_sum) != 0:
					ProgressWindow.hide()
					ConfDialog.show_all()
					while Gtk.events_pending():
						Gtk.main_iteration()
				else:
					finalize()
		if error:
			ProgressWindow.hide()
			Release()
		return error
