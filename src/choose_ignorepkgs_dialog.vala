/*
 *  pamac-vala
 *
 *  Copyright (C) 2015-2018 Guillaume Benoit <guillaume@manjaro.org>
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

	[GtkTemplate (ui = "/org/manjaro/pamac/preferences/choose_ignorepkgs_dialog.ui")]
	class ChooseIgnorepkgsDialog : Gtk.Dialog {

		[GtkChild]
		public Gtk.TreeView treeview;

		public Gtk.ListStore pkgs_list;

		public ChooseIgnorepkgsDialog (Gtk.Window window) {
			int use_header_bar;
			Gtk.Settings.get_default ().get ("gtk-dialogs-use-header", out use_header_bar);
			Object (transient_for: window, use_header_bar: use_header_bar);

			pkgs_list = new Gtk.ListStore (2, typeof (bool), typeof (string));
			treeview.set_model (pkgs_list);
		}

		[GtkCallback]
		void on_renderertoggle_toggled (string path) {
			Gtk.TreeIter iter;
			bool selected;
			if (pkgs_list.get_iter_from_string (out iter, path)) {
				pkgs_list.get (iter, 0, out selected);
				pkgs_list.set (iter, 0, !selected);
			}
		}
	}
}
