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

	[GtkTemplate (ui = "/org/manjaro/pamac/updater/updater_window.ui")]
	class UpdaterWindow : Gtk.ApplicationWindow {

		[GtkChild]
		Gtk.Label top_label;
		[GtkChild]
		Gtk.StackSwitcher stackswitcher;
		[GtkChild]
		Gtk.ScrolledWindow repos_scrolledwindow;
		[GtkChild]
		Gtk.ScrolledWindow aur_scrolledwindow;
		[GtkChild]
		Gtk.TreeView repos_updates_treeview;
		[GtkChild]
		Gtk.CellRendererToggle repos_select_update;
		[GtkChild]
		Gtk.TreeView aur_updates_treeview;
		[GtkChild]
		Gtk.CellRendererToggle aur_select_update;
		[GtkChild]
		Gtk.Label bottom_label;
		[GtkChild]
		Gtk.Button apply_button;

		Gtk.ListStore repos_updates_list;
		Gtk.ListStore aur_updates_list;

		public Pamac.Transaction transaction;

		public UpdaterWindow (Gtk.Application application) {
			Object (application: application);

			bottom_label.visible  = false;
			apply_button.sensitive = false;
			stackswitcher.visible = false;
			aur_scrolledwindow.visible = false;

			Timeout.add (100, populate_window);
		}

		bool populate_window () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));

			repos_updates_list = new Gtk.ListStore (6, typeof (bool), typeof (string), typeof (string), typeof (string),typeof (string), typeof (string));
			repos_updates_treeview.set_model (repos_updates_list);
			aur_updates_list = new Gtk.ListStore (3, typeof (bool), typeof (string), typeof (string));
			aur_updates_treeview.set_model (aur_updates_list);

			transaction = new Transaction (this as Gtk.ApplicationWindow);
			transaction.mode = Mode.UPDATER;
			transaction.finished.connect (populate_updates_list);
			transaction.get_updates_finished.connect (on_get_updates_finished);

			on_refresh_button_clicked ();

			return false;
		}

		void set_apply_button_sensitive () {
			bool sensitive = false;
			repos_updates_list.foreach ((model, path, iter) => {
				bool selected;
				repos_updates_list.get (iter, 0, out selected);
				sensitive = selected;
				return sensitive;
			});
			if (!sensitive) {
				aur_updates_list.foreach ((model, path, iter) => {
					bool selected;
					aur_updates_list.get (iter, 0, out selected);
					sensitive = selected;
					return sensitive;
				});
			}
			apply_button.sensitive = sensitive;
		}

		[GtkCallback]
		void on_repos_select_update_toggled (string path) {
			Gtk.TreePath treepath = new Gtk.TreePath.from_string (path);
			Gtk.TreeIter iter;
			string pkgname;
			repos_updates_list.get_iter (out iter, treepath);
			repos_updates_list.get (iter, 1, out pkgname);
			if (repos_select_update.active) {
				repos_updates_list.set (iter, 0, false);
				transaction.temporary_ignorepkgs.add (pkgname);
			} else {
				repos_updates_list.set (iter, 0, true);
				transaction.temporary_ignorepkgs.remove (pkgname);
			}
			set_apply_button_sensitive ();
		}

		[GtkCallback]
		void on_aur_select_update_toggled  (string path) {
			Gtk.TreePath treepath = new Gtk.TreePath.from_string (path);
			Gtk.TreeIter iter;
			string pkgname;
			aur_updates_list.get_iter (out iter, treepath);
			aur_updates_list.get (iter, 1, out pkgname);
			if (aur_select_update.active) {
				aur_updates_list.set (iter, 0, false);
				transaction.temporary_ignorepkgs.add (pkgname);
			} else {
				aur_updates_list.set (iter, 0, true);
				transaction.temporary_ignorepkgs.remove (pkgname);
			}
			set_apply_button_sensitive ();
		}

		[GtkCallback]
		void on_preferences_button_clicked () {
			transaction.run_preferences_dialog.begin (() => {
				populate_updates_list ();
			});
		}

		[GtkCallback]
		void on_apply_button_clicked () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			transaction.sysupgrade (false);
		}

		[GtkCallback]
		void on_refresh_button_clicked () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			transaction.start_refresh (false);
		}

		[GtkCallback]
		void on_close_button_clicked () {
			this.application.quit ();
		}

		void populate_updates_list () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			transaction.start_get_updates ();
		}

		void on_get_updates_finished (Updates updates) {
			top_label.set_markup ("");
			repos_updates_list.clear ();
			stackswitcher.visible = false;
			repos_scrolledwindow.visible = true;
			aur_updates_list.clear ();
			aur_scrolledwindow.visible = false;
			bottom_label.visible = false;
			uint64 dsize = 0;
			uint repos_updates_nb = 0;
			uint aur_updates_nb = 0;
			foreach (unowned UpdateInfos infos in updates.repos_updates) {
				string size = infos.download_size != 0 ? format_size (infos.download_size) : "";
				dsize += infos.download_size;
				repos_updates_nb++;
				repos_updates_list.insert_with_values (null, -1,
														0, !transaction.temporary_ignorepkgs.contains (infos.name),
														1, infos.name,
														2, infos.new_version,
														3, "(%s)".printf (infos.old_version),
														4, infos.repo,
														5, size);
			}
			foreach (unowned UpdateInfos infos in updates.aur_updates) {
				aur_updates_nb++;
				aur_updates_list.insert_with_values (null, -1,
														0, !transaction.temporary_ignorepkgs.contains (infos.name),
														1, infos.name,
														2, "%s\t (%s)".printf (infos.new_version, infos.old_version));
			}
			uint updates_nb = repos_updates_nb + aur_updates_nb;
			if (updates_nb == 0) {
				top_label.set_markup("<b>%s</b>".printf (dgettext (null, "Your system is up-to-date")));
			} else {
				top_label.set_markup("<b>%s</b>".printf (dngettext (null, "%u available update", "%u available updates", updates_nb).printf (updates_nb)));
			}
			set_apply_button_sensitive ();
			if (dsize != 0) {
				bottom_label.set_markup("<b>%s: %s</b>".printf (dgettext (null, "Total download size"), format_size(dsize)));
				bottom_label.visible = true;
			} else {
				bottom_label.visible = false;
			}
			if (aur_updates_nb != 0) {
				aur_scrolledwindow.visible = true;
				if (repos_updates_nb == 0) {
					repos_scrolledwindow.visible = false;
				}
				stackswitcher.visible = true;
			}
			this.get_window ().set_cursor (null);
		}
	}
}
