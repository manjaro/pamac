#! /usr/bin/python3
# -*- coding:utf-8 -*-

from gi.repository import Gtk, GObject
from subprocess import Popen
from pamac import transaction, common
import dbus
import threading

# i18n
import gettext
gettext.bindtextdomain('pamac', '/usr/share/locale')
gettext.textdomain('pamac')
_ = gettext.gettext

GObject.threads_init()
bus = dbus.SystemBus()

icon = ''
info = ''
update_icon = '/usr/share/pamac/icons/scalable/status/update-normal.svg'
update_info = _('{number} available updates')
one_update_info = _('1 available update')
noupdate_icon = '/usr/share/pamac/icons/scalable/status/update-enhancement.svg'
noupdate_info = _('Your system is up-to-date')

class Tray:
	def __init__(self):
		self.statusIcon = Gtk.StatusIcon()
		self.statusIcon.set_visible(True)

		self.menu = Gtk.Menu()
		self.menuItem = Gtk.ImageMenuItem(_('Install/Check for updates'))
		self.menuItem.connect('activate', self.execute_update, self.statusIcon)
		self.menu.append(self.menuItem)
		self.menuItem = Gtk.ImageMenuItem(_('Run pamac-manager'))
		self.menuItem.connect('activate', self.execute_manager, self.statusIcon)
		self.menu.append(self.menuItem)
		self.menuItem = Gtk.ImageMenuItem(_('Quit'))
		self.menuItem.connect('activate', self.quit_tray, self.statusIcon)
		self.menu.append(self.menuItem)

		self.statusIcon.connect('popup-menu', self.popup_menu_cb, self.menu)
		self.statusIcon.connect('activate', self.activate_cb, self.menu)

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
		Popen(['notify-send', '-i', icon, '-u', 'normal', 'Pamac', info])

	def update_icon(self, icon, info):
		self.statusIcon.set_from_file(icon)
		self.statusIcon.set_tooltip_markup(info)

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
		Popen(['notify-send', '-i', icon, '-u', 'normal', 'Pamac', info])
	else:
		icon = noupdate_icon
		info = noupdate_info
	print(info)
	tray.update_icon(icon, info)

bus.add_signal_receiver(set_icon, dbus_interface = "org.manjaro.pamac", signal_name = "EmitAvailableUpdates")

tray = Tray()
#set_icon()
t = PeriodicTask()
t.start()
Gtk.main()
