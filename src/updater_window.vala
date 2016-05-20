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
		Gtk.HeaderBar headerbar;
		[GtkChild]
		Gtk.Button button_back;
		[GtkChild]
		Gtk.ModelButton preferences_button;
		[GtkChild]
		Gtk.Stack stack;
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
		Gtk.Box transaction_infobox;
		[GtkChild]
		Gtk.Button details_button;
		[GtkChild]
		Gtk.Button apply_button;
		[GtkChild]
		Gtk.Button cancel_button;

		Gtk.ListStore repos_updates_list;
		Gtk.ListStore aur_updates_list;

		public Pamac.Transaction transaction;

		public bool transaction_running;
		bool important_details;

		public UpdaterWindow (Gtk.Application application) {
			Object (application: application);

			button_back.visible = false;
			apply_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
			apply_button.sensitive = false;
			stackswitcher.visible = false;
			aur_scrolledwindow.visible = false;
			transaction_running = false;
			important_details = false;

			Timeout.add (100, populate_window);
		}

		bool populate_window () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));

			repos_updates_list = new Gtk.ListStore (6, typeof (bool), typeof (string), typeof (string), typeof (string),typeof (string), typeof (string));
			repos_updates_treeview.set_model (repos_updates_list);
			aur_updates_list = new Gtk.ListStore (4, typeof (bool), typeof (string), typeof (string), typeof (string));
			aur_updates_treeview.set_model (aur_updates_list);

			transaction = new Transaction (this as Gtk.ApplicationWindow);
			transaction.mode = Mode.UPDATER;
			transaction.start_transaction.connect (on_start_transaction);
			transaction.important_details_outpout.connect (on_important_details_outpout);
			transaction.finished.connect (populate_updates_list);
			transaction.get_updates_finished.connect (on_get_updates_finished);

			// integrate progress box and term widget
			stack.add_named (transaction.term_grid, "term");
			transaction_infobox.pack_start (transaction.progress_box);

			on_refresh_button_clicked ();

			stack.notify["visible-child"].connect (on_stack_visible_child_changed);

			return false;
		}

		void set_transaction_infobox_visible () {
			bool visible = false;
			repos_updates_list.foreach ((model, path, iter) => {
				bool selected;
				repos_updates_list.get (iter, 0, out selected);
				visible = selected;
				return visible;
			});
			if (!visible) {
				aur_updates_list.foreach ((model, path, iter) => {
					bool selected;
					aur_updates_list.get (iter, 0, out selected);
					visible = selected;
					return visible;
				});
			}
			transaction_infobox.visible = visible;
			if (visible) {
				// fix an possible visibility issue
				transaction_infobox.show_all ();
			}
		}

		[GtkCallback]
		void on_repos_select_update_toggled (string path) {
			if (!transaction_running) {
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
				set_transaction_infobox_visible ();
			}
		}

		[GtkCallback]
		void on_aur_select_update_toggled  (string path) {
			if (!transaction_running) {
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
				set_transaction_infobox_visible ();
			}
		}

		[GtkCallback]
		void on_button_back_clicked () {
			stack.visible_child_name = "repos";
		}

		void on_stack_visible_child_changed () {
			if (stack.visible_child_name == "term") {
				button_back.visible = true;
			}
		}

		[GtkCallback]
		void on_menu_button_toggled () {
			preferences_button.sensitive = !transaction_running;
		}

		[GtkCallback]
		void on_preferences_button_clicked () {
			transaction.run_preferences_dialog.begin (() => {
				populate_updates_list ();
			});
		}

		[GtkCallback]
		void on_apply_button_clicked () {
			transaction_running = true;
			transaction.sysupgrade (false);
			apply_button.sensitive = false;
			details_button.sensitive = true;
			cancel_button.sensitive = true;
		}

		[GtkCallback]
		void on_refresh_button_clicked () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			transaction_infobox.visible = true;
			apply_button.sensitive = false;
			details_button.sensitive = true;
			cancel_button.sensitive = true;
			transaction.start_refresh (false);
		}

		[GtkCallback]
		void on_history_button_clicked () {
			transaction.run_history_dialog ();
		}

		[GtkCallback]
		void on_about_button_clicked () {
			transaction.run_about_dialog ();
		}

		[GtkCallback]
		void on_details_button_clicked () {
			details_button.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
			important_details = false;
			stack.visible_child_name = "term";
		}

		[GtkCallback]
		void on_cancel_button_clicked () {
			transaction.cancel ();
		}

		void on_start_transaction () {
			cancel_button.sensitive = false;
		}

		void on_important_details_outpout (bool must_show) {
			if (must_show) {
				stack.visible_child_name = "term";
				button_back.visible = false;
			} else if (stack.visible_child_name != "term") {
				important_details = true;
				details_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
			}
		}

		void populate_updates_list () {
			transaction_running = false;
			apply_button.sensitive = true;
			apply_button.grab_default ();
			details_button.sensitive = false;
			cancel_button.sensitive = false;
			if (stack.visible_child_name == "term") {
				button_back.visible = true;
			}
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			transaction.progress_box.action_label.label = "";
			transaction.start_get_updates ();
		}

		void on_get_updates_finished (Updates updates) {
			headerbar.title = "";
			repos_updates_list.clear ();
			stackswitcher.visible = false;
			repos_scrolledwindow.visible = true;
			aur_updates_list.clear ();
			aur_scrolledwindow.visible = false;
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
														2, infos.new_version,
														3, "(%s)".printf (infos.old_version));
			}
			uint updates_nb = repos_updates_nb + aur_updates_nb;
			if (updates_nb == 0) {
				headerbar.title = dgettext (null, "Your system is up-to-date");
			} else {
				headerbar.title = dngettext (null, "%u available update", "%u available updates", updates_nb).printf (updates_nb);
			}
			set_transaction_infobox_visible ();
			if (dsize != 0) {
				transaction.progress_box.action_label.set_markup("<b>%s: %s</b>".printf (dgettext (null, "Total download size"), format_size(dsize)));
			} else {
				transaction.progress_box.action_label.label = "";
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
