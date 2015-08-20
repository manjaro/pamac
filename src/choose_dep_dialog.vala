/*
 *  pamac-vala
 *
 *  Copyright (C) 2014 Guillaume Benoit <guillaume@manjaro.org>
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

	[GtkTemplate (ui = "/org/manjaro/pamac/manager/choose_dep_dialog.ui")]
	public class ChooseDependenciesDialog : Gtk.Dialog {

		[GtkChild]
		public Gtk.Label label;
		[GtkChild]
		public Gtk.TreeView treeview;
		[GtkChild]
		public Gtk.CellRendererToggle renderertoggle;

		public Gtk.ListStore deps_list;

		Transaction transaction;

		public ChooseDependenciesDialog (Transaction transaction, string pkgname, Gtk.ApplicationWindow? window) {
			Object (transient_for: window, use_header_bar: 0);

			this.transaction = transaction;

			string[] optdeps = transaction.get_pkg_uninstalled_optdeps (pkgname);
			label.set_markup ("<b>%s</b>".printf (
				dngettext (null, "%s has %u uninstalled optional dependency.\nChoose if you would like to install it",
						"%s has %u uninstalled optional dependencies.\nChoose those you would like to install", optdeps.length).printf (pkgname, optdeps.length)));
			deps_list = new Gtk.ListStore (3, typeof (bool), typeof (string), typeof (string));
			treeview.set_model (deps_list);
			Gtk.TreeIter iter;
			foreach (var optdep in optdeps) {
				string[] split = optdep.split (":", 2);
				deps_list.insert_with_values (out iter, -1,
										0, false,
										1, split[0],
										2, split[1]);
			}
		}

		[GtkCallback]
		void on_renderertoggle_toggled (string path) {
			Gtk.TreeIter iter;
			GLib.Value val;
			bool selected;
			if (deps_list.get_iter_from_string (out iter, path)) {;
				deps_list.get_value (iter, 0, out val);
				selected = val.get_boolean ();
				deps_list.set_value (iter, 0, !selected);
			}
		}
	}
}
