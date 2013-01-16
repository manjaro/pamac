#! /usr/bin/python
# -*-coding:utf-8-*-

from gi.repository import Gtk

from pamac import transaction, updater, manager

class Tray:
	def __init__(self, icon, info):
		self.icon = icon
		self.info = info
		self.statusIcon = Gtk.StatusIcon()
		self.statusIcon.set_from_file(icon)
		self.statusIcon.set_visible(True)
		self.statusIcon.set_tooltip_markup(info)

		self.menu = Gtk.Menu()
		self.menuItem = Gtk.ImageMenuItem('Check for updates')
		self.menuItem.connect('activate', self.execute_update, self.statusIcon)
		self.menu.append(self.menuItem)
		self.menuItem = Gtk.ImageMenuItem('Run pamac')
		self.menuItem.connect('activate', self.execute_manager, self.statusIcon)
		self.menu.append(self.menuItem)
		self.menuItem = Gtk.ImageMenuItem(Gtk.STOCK_QUIT)
		self.menuItem.connect('activate', self.quit_tray, self.statusIcon)
		self.menu.append(self.menuItem)

		self.statusIcon.connect('popup-menu', self.popup_menu_cb, self.menu)
		self.statusIcon.set_visible(1)

	def execute_update(self, widget, event, data = None):
		updater.main()

	def execute_manager(self, widget, event, data = None):
		manager.main()

	def quit_tray(self, widget, data = None):
		Gtk.main_quit()

	def popup_menu_cb(self, widget, button, time, data = None):
		if button == 3:
			if data:
				data.show_all()
				data.popup(None, None, Gtk.StatusIcon.position_menu, self.statusIcon, 3, time)

if __name__ == "__main__":
	updates = transaction.get_updates()
	if updates:
		icon = '/usr/share/pamac/icons/24x24/status/update-normal.png'
		info = str(len(updates))+' update(s) available'
	else:
		icon = '/usr/share/pamac/icons/24x24/status/update-enhancement.png'
		info = ' No update available'
	tray = Tray(icon, info)
	Gtk.main()
