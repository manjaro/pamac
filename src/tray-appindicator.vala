/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2016 Guillaume Benoit <guillaume@manjaro.org>
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

	class IndicatorTrayIcon: TrayIcon {
		AppIndicator.Indicator indicator_status_icon;

		public override void init_status_icon () {
			indicator_status_icon = new AppIndicator.Indicator ("Update Manager", noupdate_icon_name, AppIndicator.IndicatorCategory.APPLICATION_STATUS);
			indicator_status_icon.set_status (AppIndicator.IndicatorStatus.PASSIVE);
			// add a item without label to not show it in menu
			// this allow left click action
			var item = new Gtk.MenuItem ();
			item.visible = true;
			item.activate.connect (left_clicked);
			menu.append (item);
			indicator_status_icon.set_menu (menu);
			indicator_status_icon.set_secondary_activate_target (item);
		}

		public override void set_tooltip (string info) {
			indicator_status_icon.set_title (info);
		}

		public override void set_icon (string icon) {
			indicator_status_icon.set_icon_full (icon, icon);
		}

		public override string get_icon () {
			return indicator_status_icon.get_icon ();
		}

		public override void set_icon_visible (bool visible) {
			if (visible) {
				indicator_status_icon.set_status (AppIndicator.IndicatorStatus.ACTIVE);
			} else {
				indicator_status_icon.set_status (AppIndicator.IndicatorStatus.PASSIVE);
			}
		}
	}
}

int main (string[] args) {
	var tray_icon = new Pamac.IndicatorTrayIcon();
	return tray_icon.run (args);
}
