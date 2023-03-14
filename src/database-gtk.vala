/*
 *  pamac-vala
 *
 *  Copyright (C) 2018-2023 Guillaume Benoit <guillaume@manjaro.org>
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
	public class DatabaseGtk: Database {
		// parent window
		public Gtk.Window? window { get; set; }

		public DatabaseGtk (Config config) {
			Object (config: config);
			// window is set in manager.vala
		}

		construct {
			// connect to signals
			emit_warning.connect ((message) => {
				if (message.length == 0) {
					return;
				}
				var flags = Gtk.DialogFlags.MODAL;
				int use_header_bar;
				Gtk.Settings.get_default ().get ("gtk-dialogs-use-header", out use_header_bar);
				if (use_header_bar == 1) {
					flags |= Gtk.DialogFlags.USE_HEADER_BAR;
				}
				var dialog = new Gtk.Dialog.with_buttons (dgettext (null, "Error"),
														window,
														flags);
				dialog.margin_top = 3;
				dialog.margin_bottom = 3;
				dialog.margin_start = 3;
				dialog.margin_end = 3;
				dialog.icon_name = "system-software-install";
				dialog.deletable = false;
				unowned Gtk.Widget widget = dialog.add_button (dgettext (null, "_Close"), Gtk.ResponseType.CLOSE);
				dialog.focus_widget = widget;
				var scrolledwindow = new Gtk.ScrolledWindow ();
				var label = new Gtk.Label (message);
				label.selectable = true;
				label.margin_top = 12;
				label.margin_bottom = 12;
				label.margin_start = 12;
				label.margin_end = 12;
				scrolledwindow.set_child (label);
				scrolledwindow.hexpand = true;
				scrolledwindow.vexpand = true;
				unowned Gtk.Box box = dialog.get_content_area ();
				box.append (scrolledwindow);
				box.spacing = 6;
				dialog.default_width = 600;
				dialog.default_height = 300;
				dialog.response.connect (() => {
					dialog.destroy ();
				});
				dialog.show ();
			});
		}
	}
}
