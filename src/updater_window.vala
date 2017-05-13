/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2017 Guillaume Benoit <guillaume@manjaro.org>
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

		bool transaction_running;
		bool generate_mirrors_list;
		bool important_details;
		string previous_visible_child_name;

		public UpdaterWindow (Gtk.Application application) {
			Object (application: application);

			button_back.visible = false;
			apply_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
			apply_button.sensitive = false;
			stackswitcher.visible = false;
			aur_scrolledwindow.visible = false;
			transaction_running = false;
			important_details = false;
			generate_mirrors_list = false;

			headerbar.title = dgettext (null, "Update Manager");
			Timeout.add (100, populate_window);
		}

		bool populate_window () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));

			repos_updates_list = new Gtk.ListStore (7, typeof (bool), typeof (string), typeof (string), typeof (string),typeof (string), typeof (string), typeof (uint64));
			repos_updates_treeview.set_model (repos_updates_list);
			aur_updates_list = new Gtk.ListStore (4, typeof (bool), typeof (string), typeof (string), typeof (string));
			aur_updates_treeview.set_model (aur_updates_list);

			transaction = new Transaction (this as Gtk.ApplicationWindow);
			transaction.mode = Mode.UPDATER;
			transaction.start_waiting.connect (on_start_waiting);
			transaction.stop_waiting.connect (on_stop_waiting);
			transaction.start_downloading.connect (on_start_downloading);
			transaction.stop_downloading.connect (on_stop_downloading);
			transaction.start_building.connect (on_start_building);
			transaction.stop_building.connect (on_stop_building);
			transaction.important_details_outpout.connect (on_important_details_output);
			transaction.finished.connect (populate_updates_list);
			transaction.get_updates_finished.connect (on_get_updates_finished);
			transaction.generate_mirrors_list.connect (on_generate_mirrors_list);

			// integrate progress box and term widget
			stack.add_named (transaction.term_window, "term");
			transaction_infobox.pack_start (transaction.progress_box);

			// A timeout is needed to let the time to the daemon to deal
			// with potential other package manager process running.
			Timeout.add (500, () => {
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				transaction_infobox.show_all ();
				details_button.sensitive = true;
				cancel_button.sensitive = true;
				transaction.start_refresh (false);
				return false;
			});

			stack.notify["visible-child"].connect (on_stack_visible_child_changed);

			return false;
		}

		void set_transaction_infobox_visible () {
			if (important_details) {
				transaction_infobox.show_all ();
				return;
			}
			if (!generate_mirrors_list) {
				bool visible = false;
				uint64 total_dsize = 0;
				repos_updates_list.foreach ((model, path, iter) => {
					bool selected;
					uint64 dsize;
					repos_updates_list.get (iter, 0, out selected, 6, out dsize);
					visible |= selected;
					if (selected) {
						total_dsize += dsize;
					}
					return false;
				});
				if (!visible) {
					aur_updates_list.foreach ((model, path, iter) => {
						bool selected;
						aur_updates_list.get (iter, 0, out selected);
						visible |= selected;
						return visible;
					});
				}
				if (visible) {
					if (total_dsize != 0) {
						transaction.progress_box.action_label.set_markup("<b>%s: %s</b>".printf (dgettext (null, "Total download size"), format_size (total_dsize)));
					} else {
						transaction.progress_box.action_label.label = "";
					}
					// fix an possible visibility issue
					transaction_infobox.show_all ();
				} else {
					transaction_infobox.visible = false;
				}
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
			if (aur_scrolledwindow.visible) {
				stackswitcher.visible = true;
				stack.visible_child_name = previous_visible_child_name;
			} else {
				stack.visible_child_name = "repos";
			}
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
				if (!generate_mirrors_list) {
					populate_updates_list ();
				}
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
			transaction_infobox.show_all ();
			apply_button.sensitive = false;
			details_button.sensitive = true;
			cancel_button.sensitive = true;
			transaction.start_refresh (true);
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
			previous_visible_child_name = stack.visible_child_name;
			stack.visible_child_name = "term";
		}

		[GtkCallback]
		void on_cancel_button_clicked () {
			transaction.cancel ();
		}

		void on_start_waiting () {
			cancel_button.sensitive = true;
		}

		void on_stop_waiting () {
			populate_updates_list ();
		}

		void on_start_downloading () {
			cancel_button.sensitive = true;
		}

		void on_stop_downloading () {
			cancel_button.sensitive = false;
		}

		void on_start_building () {
			cancel_button.sensitive = true;
		}

		void on_stop_building () {
			cancel_button.sensitive = false;
		}

		void on_important_details_output (bool must_show) {
			if (must_show) {
				stackswitcher.visible = false;
				previous_visible_child_name = stack.visible_child_name;
				stack.visible_child_name = "term";
				button_back.visible = false;
			} else if (stack.visible_child_name != "term") {
				important_details = true;
				details_button.sensitive = true;
				details_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
			}
		}

		void on_generate_mirrors_list () {
			generate_mirrors_list = true;
			apply_button.sensitive = false;
			transaction_infobox.show_all ();
		}

		void populate_updates_list () {
			transaction_running = false;
			generate_mirrors_list = false;
			apply_button.grab_default ();
			if (!important_details) {
				details_button.sensitive = false;
			}
			cancel_button.sensitive = false;
			if (stack.visible_child_name == "term") {
				button_back.visible = true;
			}
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			transaction.progress_box.action_label.label = "";
			transaction.start_get_updates ();
		}

		void on_get_updates_finished (Updates updates) {
			headerbar.title = dgettext (null, "Update Manager");
			repos_updates_list.clear ();
			stackswitcher.visible = false;
			repos_scrolledwindow.visible = true;
			aur_updates_list.clear ();
			aur_scrolledwindow.visible = false;
			uint repos_updates_nb = 0;
			uint aur_updates_nb = 0;
			foreach (unowned UpdateInfos infos in updates.repos_updates) {
				string size = infos.download_size != 0 ? format_size (infos.download_size) : "";
				repos_updates_nb++;
				repos_updates_list.insert_with_values (null, -1,
														0, !transaction.temporary_ignorepkgs.contains (infos.name),
														1, infos.name,
														2, infos.new_version,
														3, "(%s)".printf (infos.old_version),
														4, infos.repo,
														5, size,
														6, infos.download_size);
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
				apply_button.sensitive = false;
			} else {
				headerbar.title = dngettext (null, "%u available update", "%u available updates", updates_nb).printf (updates_nb);
				apply_button.sensitive = true;
			}
			set_transaction_infobox_visible ();
			if (aur_updates_nb != 0) {
				aur_scrolledwindow.visible = true;
				if (repos_updates_nb == 0) {
					repos_scrolledwindow.visible = false;
				}
				if (stack.visible_child_name != "term") {
					stackswitcher.visible = true;
				}
			}
			this.get_window ().set_cursor (null);
		}
	}
}
