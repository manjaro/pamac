#! /usr/bin/python3
# -*- coding:utf-8 -*-

from gi.repository import Gtk, GObject
from subprocess import Popen
import dbus
import threading
from pamac import common
from time import sleep

# i18n
import gettext
gettext.bindtextdomain('pamac', '/usr/share/locale')
gettext.textdomain('pamac')
_ = gettext.gettext

GObject.threads_init()

update_icon = 'software-update-urgent'
update_info = _('{number} available updates')
one_update_info = _('1 available update')
noupdate_icon = 'software-update-available'
noupdate_info = _('Your system is up-to-date')
icon = noupdate_icon
info = noupdate_info

class Tray:
	def __init__(self):
		self.statusIcon = Gtk.StatusIcon()

		self.menu = Gtk.Menu()
		self.menuItem = Gtk.ImageMenuItem(_('Update Manager'))
		self.menuItem.set_image(Gtk.Image.new_from_pixbuf(Gtk.IconTheme.get_default().load_icon('system-software-update', 16, 0)))
		self.menuItem.connect('activate', self.execute_update, self.statusIcon)
		self.menu.append(self.menuItem)
		self.menuItem = Gtk.ImageMenuItem(_('Package Manager'))
		self.menuItem.set_image(Gtk.Image.new_from_pixbuf(Gtk.IconTheme.get_default().load_icon('system-software-install', 16, 0)))
		self.menuItem.connect('activate', self.execute_manager, self.statusIcon)
		self.menu.append(self.menuItem)
		self.menuItem = Gtk.ImageMenuItem(_('Quit'))
		self.menuItem.set_image(Gtk.Image.new_from_stock('gtk-quit', Gtk.IconSize.MENU))
		self.menuItem.connect('activate', self.quit_tray, self.statusIcon)
		self.menu.append(self.menuItem)

		self.statusIcon.connect('popup-menu', self.popup_menu_cb, self.menu)
		self.statusIcon.connect('activate', self.activate_cb)

	def execute_update(self, widget, event, data = None):
		Popen(['/usr/bin/pamac-updater'])

	def execute_manager(self, widget, event, data = None):
		Popen(['/usr/bin/pamac-manager'])

	def quit_tray(self, widget, data = None):
		t.shutdown()
		Gtk.main_quit()

	def popup_menu_cb(self, widget, button, time, data = None):
		if button == 3:
			if data:
				data.show_all()
				data.popup(None, None, Gtk.StatusIcon.position_menu, self.statusIcon, 3, time)

	def activate_cb(self, widget, data = None):
		if icon == update_icon:
			Popen(['/usr/bin/pamac-updater'])

	def update_icon(self, icon, info):
		self.statusIcon.set_from_icon_name(icon)
		self.statusIcon.set_tooltip_markup(info)

	def set_visible(self, boolean):
		self.statusIcon.set_visible(boolean)

class PeriodicTask(threading.Thread):
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
		while 1:
			if self._finished.isSet():
				return
			self.task()
			# sleep for interval or until shutdown
			self._finished.wait(self._interval)

	def task(self):
		Popen(['/usr/bin/pamac-refresh'])

def set_icon(updates):
	global icon
	global info
	if updates:
		icon = update_icon
		if int(updates) == 1:
			info = one_update_info
		else:
			info = update_info.format(number = updates)
		tray.set_visible(True)
		sleep(2)
		if not common.pid_file_exists():
			Popen(['notify-send', '-i', 'system-software-update', '-u', 'normal', _('Update Manager'), info])
	else:
		icon = noupdate_icon
		info = noupdate_info
		tray.set_visible(True)
	print(info)
	tray.update_icon(icon, info)

from pamac import transaction
bus = dbus.SystemBus()
bus.add_signal_receiver(set_icon, dbus_interface = "org.manjaro.pamac", signal_name = "EmitAvailableUpdates")
transaction.StopDaemon()

tray = Tray()
t = PeriodicTask()
t.start()
Gtk.main()
