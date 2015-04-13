/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2015 Guillaume Benoit <guillaume@manjaro.org>
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

	[GtkTemplate (ui = "/org/manjaro/pamac/updater/updater_window.ui")]
	public class UpdaterWindow : Gtk.ApplicationWindow {

		[GtkChild]
		public Gtk.Label top_label;
		[GtkChild]
		public Gtk.TreeView updates_treeview;
		[GtkChild]
		public Gtk.CellRendererToggle select_update;
		[GtkChild]
		public Gtk.Label bottom_label;
		[GtkChild]
		public Gtk.Button apply_button;

		public Gtk.ListStore updates_list;

		public Pamac.Transaction transaction;

		public UpdaterWindow (Gtk.Application application) {
			Object (application: application);

			updates_list = new Gtk.ListStore (3, typeof (bool), typeof (string), typeof (string));
			updates_treeview.set_model (updates_list);

			transaction = new Transaction (this as Gtk.ApplicationWindow);
			transaction.mode = Mode.UPDATER;
			transaction.finished.connect (on_transaction_finished);

			bottom_label.set_visible (false);
			apply_button.set_sensitive (false);

			on_refresh_button_clicked ();
		}

		[GtkCallback]
		public void on_select_update_toggled (string path) {
			Gtk.TreePath treepath = new Gtk.TreePath.from_string (path);
			Gtk.TreeIter iter;
			updates_list.get_iter (out iter, treepath);
			updates_list.set (iter, 0, !select_update.active);
			updates_list.foreach ((model, path, iter) => {
				GLib.Value val;
				updates_list.get_value (iter, 0, out val);
				bool selected = val.get_boolean ();
				if (selected) {
					apply_button.set_sensitive (true);
					return true;
				}
				apply_button.set_sensitive (false);
				return false;
			});
		}

		[GtkCallback]
		public void on_preferences_button_clicked () {
			transaction.run_preferences_dialog.begin (() => {
				set_updates_list.begin ();
			});
		}

		[GtkCallback]
		public void on_apply_button_clicked () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
			updates_list.foreach ((model, path, iter) => {
				GLib.Value val;
				updates_list.get_value (iter, 0, out val);
				bool selected = val.get_boolean ();
				if (selected) {
					updates_list.get_value (iter, 1, out val);
					// string has the form "pkgname pkgversion"
					string pkgname = val.get_string ().split (" ", 2)[0];
					transaction.special_ignorepkgs.remove (pkgname);
				} else {
					updates_list.get_value (iter, 1, out val);
					// string has the form "pkgname pkgversion"
					string pkgname = val.get_string ().split (" ", 2)[0];
					transaction.special_ignorepkgs.add ((owned) pkgname);
				}
				return false;
			});
			transaction.sysupgrade (0);
		}

		[GtkCallback]
		public void on_refresh_button_clicked () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
			transaction.start_refresh (0);
		}

		[GtkCallback]
		public void on_close_button_clicked () {
			this.application.quit ();
		}

		public void on_transaction_finished (bool error) {
			set_updates_list.begin ();
		}

		public async void set_updates_list () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
			top_label.set_markup ("");
			updates_list.clear ();
			bottom_label.set_visible (false);
			Gtk.TreeIter iter;
			string name;
			string size;
			uint64 dsize = 0;
			uint updates_nb = 0;
			Updates updates = yield transaction.get_updates ();
			foreach (UpdateInfos infos in updates.repos_updates) {
				name = infos.name + " " + infos.version;
				if (infos.download_size != 0) {
					size = format_size (infos.download_size);
				} else {
					size = "";
				}
				dsize += infos.download_size;
				updates_nb++;
				if (infos.name in transaction.special_ignorepkgs) {
					updates_list.insert_with_values (out iter, -1, 0, false, 1, name, 2, size);
				} else {
					updates_list.insert_with_values (out iter, -1, 0, true, 1, name, 2, size);
				}
			}
			foreach (UpdateInfos infos in updates.aur_updates) {
				name = infos.name + " " + infos.version;
				size = "";
				updates_nb++;
				updates_list.insert_with_values (out iter, -1, 0, true, 1, name, 2, size);
			}
			if (updates_nb == 0) {
				top_label.set_markup("<b>%s</b>".printf (dgettext (null, "Your system is up-to-date")));
				apply_button.set_sensitive (false);
			} else {
				top_label.set_markup("<b>%s</b>".printf (dngettext (null, "%u available update", "%u available updates", updates_nb).printf (updates_nb)));
				apply_button.set_sensitive (true);
			}
			if (dsize != 0) {
				bottom_label.set_markup("<b>%s: %s</b>".printf (dgettext (null, "Total download size"), format_size(dsize)));
				bottom_label.set_visible (true);
			} else {
				bottom_label.set_visible (false);
			}
			this.get_window ().set_cursor (null);
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
		}
	}
}
