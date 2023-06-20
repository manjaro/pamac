/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2023 Guillaume Benoit <guillaume@manjaro.org>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a get of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

namespace Pamac {

	class GtkTrayIcon: TrayIcon {
		Gtk3.StatusIcon status_icon;

		public override void init_status_icon () {
			status_icon = new Gtk3.StatusIcon ();
			status_icon.visible = false;
			status_icon.activate.connect (left_clicked);
			status_icon.popup_menu.connect (menu_popup);
		}

		// Show popup menu on right button
		void menu_popup () {
			var menu = create_menu ();
			menu.popup_at_pointer (null);
		}

		public override void set_tooltip (string info) {
			status_icon.set_tooltip_markup (info);
		}

		public override void set_icon (string icon) {
			status_icon.set_from_icon_name (icon);
		}

		public override void set_icon_visible (bool visible) {
			status_icon.visible = visible;
		}
	}
}

int main (string[] args) {
	var tray_icon = new Pamac.GtkTrayIcon();
	return tray_icon.run (args);
}
