#! /usr/bin/python3
# -*- coding:utf-8 -*-

from gi.repository import Gtk, GObject
from subprocess import call
from time import sleep
import threading
from pamac import common, transaction

GObject.threads_init()

# i18n
import gettext
gettext.bindtextdomain('pamac', '/usr/share/locale')
gettext.textdomain('pamac')
_ = gettext.gettext

update_icon = '/usr/share/pamac/icons/24x24/status/pamac-update.png'
update_info = _('{number} available updates')
one_update_info = _('1 available update')
noupdate_icon = '/usr/share/pamac/icons/24x24/status/pamac-tray.png'
noupdate_info = _('Your system is up-to-date')
icon = noupdate_icon
info = noupdate_info

class Tray:
	def __init__(self):
		self.statusIcon = Gtk.StatusIcon()
		self.statusIcon.set_visible(True)

		self.menu = Gtk.Menu()
		self.menuItem = Gtk.ImageMenuItem(_('Update Manager'))
		self.menuItem.set_image(Gtk.Image.new_from_file('/usr/share/pamac/icons/16x16/apps/pamac-updater.png'))
		self.menuItem.connect('activate', self.execute_update, self.statusIcon)
		self.menu.append(self.menuItem)
		self.menuItem = Gtk.ImageMenuItem(_('Package Manager'))
		self.menuItem.set_image(Gtk.Image.new_from_file('/usr/share/pamac/icons/16x16/apps/pamac.png'))
		self.menuItem.connect('activate', self.execute_manager, self.statusIcon)
		self.menu.append(self.menuItem)
		self.menuItem = Gtk.ImageMenuItem(_('Quit'))
		self.menuItem.set_image(Gtk.Image.new_from_file('/usr/share/pamac/icons/16x16/apps/exit.png'))
		self.menuItem.connect('activate', self.quit_tray, self.statusIcon)
		self.menu.append(self.menuItem)

		self.statusIcon.connect('popup-menu', self.popup_menu_cb, self.menu)
		self.statusIcon.connect('activate', self.activate_cb)

	def execute_update(self, widget, event, data = None):
		call(['/usr/bin/pamac-updater'])

	def execute_manager(self, widget, event, data = None):
		call(['/usr/bin/pamac-manager'])

	def quit_tray(self, widget, data = None):
		t1.shutdown()
		t2.shutdown()
		Gtk.main_quit()

	def popup_menu_cb(self, widget, button, time, data = None):
		if button == 3:
			if data:
				data.show_all()
				data.popup(None, None, Gtk.StatusIcon.position_menu, self.statusIcon, 3, time)

	def activate_cb(self, widget, data = None):
		if icon == update_icon:
			call(['/usr/bin/pamac-updater'])

	def update_icon(self, icon, info):
		GObject.idle_add(self.statusIcon.set_from_file, icon)
		GObject.idle_add(self.statusIcon.set_tooltip_markup, info)

	def set_visible(self, boolean):
		self.statusIcon.set_visible(boolean)

class PeriodicRefresh(threading.Thread):
	"""Thread that executes a task every N seconds"""
	def __init__(self):
		threading.Thread.__init__(self)
		self._finished = threading.Event()
		self._interval = 3600*3

	def setInterval(self, interval):
		"""Set the number of seconds we sleep between executing our task"""
		self._interval = interval

	def shutdown(self):
		"""Stop this thread"""
		self._finished.set()

	def run(self):
		while True:
			if self._finished.isSet():
				return
			call(['/usr/bin/pamac-refresh'])
			self._finished.wait(self._interval)

class PeriodicCheck(threading.Thread):
	"""Thread that executes a task every N seconds"""
	def __init__(self):
		threading.Thread.__init__(self)
		self._finished = threading.Event()
		self._interval = 1
		self.trans = transaction.Transaction()

	def setInterval(self, interval):
		"""Set the number of seconds we sleep between executing our task"""
		self._interval = interval

	def shutdown(self):
		"""Stop this thread"""
		self._finished.set()

	def run(self):
		pid_file = True
		while True:
			if self._finished.isSet():
				return
			if common.pid_file_exists():
				pid_file = True
			elif pid_file:
				self.trans.update_dbs()
				set_icon(len(self.trans.get_updates()[1]))
				pid_file = False
			else:
				self._finished.wait(self._interval)

def set_icon(updates):
	global icon
	global info
	if updates:
		icon = update_icon
		if int(updates) == 1:
			info = one_update_info
		else:
			info = update_info.format(number = updates)
		if not common.pid_file_exists():
			call(['notify-send', '-i', '/usr/share/pamac/icons/32x32/apps/pamac-updater.png', '-u', 'normal', _('Update Manager'), info])
	else:
		icon = noupdate_icon
		info = noupdate_info
	print(info)
	tray.update_icon(icon, info)
	return False

tray = Tray()
t1 = PeriodicRefresh()
t1.start()
t2 = PeriodicCheck()
t2.start()
Gtk.main()
