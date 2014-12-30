/*
 *  pamac-vala
 *
 *  Copyright (C) 2014  Guillaume Benoit <guillaume@manjaro.org>
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

using Gtk;

namespace Pamac {

	[GtkTemplate (ui = "/org/manjaro/pamac/updater/updater_window.ui")]
	public class UpdaterWindow : Gtk.ApplicationWindow {

		[GtkChild]
		public Label top_label;
		[GtkChild]
		public TreeView updates_treeview;
		[GtkChild]
		public Label bottom_label;
		[GtkChild]
		public Button apply_button;

		public ListStore updates_list;
		public Pamac.Config pamac_config;
		public Pamac.Transaction transaction;

		public UpdaterWindow (Gtk.Application application) {
			Object (application: application);

			pamac_config = new Pamac.Config ("/etc/pamac.conf");

			updates_list = new Gtk.ListStore (2, typeof (string), typeof (string));
			updates_treeview.set_model (updates_list);

			transaction = new Transaction (this as ApplicationWindow);
			transaction.mode = Mode.UPDATER;
			transaction.check_aur = pamac_config.enable_aur;
			transaction.finished.connect (on_emit_trans_finished);

			bottom_label.set_visible (false);
			apply_button.set_sensitive (false);

			on_refresh_button_clicked ();
		}

		[GtkCallback]
		public void on_preferences_button_clicked () {
			bool changes = transaction.run_preferences_dialog (pamac_config);
			if (changes)
				set_updates_list.begin ();
		}

		[GtkCallback]
		public void on_apply_button_clicked () {
			this.get_window ().set_cursor (new Gdk.Cursor (Gdk.CursorType.WATCH));
			while (Gtk.events_pending ())
				Gtk.main_iteration ();
			transaction.sysupgrade (0);
		}

		[GtkCallback]
		public void on_refresh_button_clicked () {
			this.get_window ().set_cursor (new Gdk.Cursor (Gdk.CursorType.WATCH));
			while (Gtk.events_pending ())
				Gtk.main_iteration ();
			transaction.refresh (0);
		}

		[GtkCallback]
		public void on_close_button_clicked () {
			this.application.quit ();
		}

		public void on_emit_trans_finished (bool error) {
			set_updates_list.begin ();
		}

		public async void set_updates_list () {
			TreeIter iter;
			string name;
			string size;
			uint64 dsize = 0;
			uint updates_nb = 0;
			this.get_window ().set_cursor (new Gdk.Cursor (Gdk.CursorType.WATCH));
			while (Gtk.events_pending ())
				Gtk.main_iteration ();
			top_label.set_markup ("");
			updates_list.clear ();
			// get syncfirst updates
			UpdatesInfos[] syncfirst_updates = get_syncfirst_updates (transaction.alpm_config.handle, transaction.alpm_config.syncfirsts);
			if (syncfirst_updates.length != 0) {
				updates_nb = syncfirst_updates.length;
				foreach (UpdatesInfos infos in syncfirst_updates) {
					name = infos.name + " " + infos.version;
					if (infos.download_size != 0)
						size = format_size (infos.download_size);
					else
						size = "";
					dsize += infos.download_size;
					updates_list.insert_with_values (out iter, -1, 0, name, 1, size);
				}
			} else {
				while (Gtk.events_pending ())
					Gtk.main_iteration ();
				UpdatesInfos[] updates = get_repos_updates (transaction.alpm_config.handle);
				foreach (UpdatesInfos infos in updates) {
					name = infos.name + " " + infos.version;
					if (infos.download_size != 0)
						size = format_size (infos.download_size);
					else
						size = "";
					dsize += infos.download_size;
					updates_list.insert_with_values (out iter, -1, 0, name, 1, size);
				}
				updates_nb += updates.length;
				if (pamac_config.enable_aur) {
					UpdatesInfos[] aur_updates = get_aur_updates (transaction.alpm_config.handle);
					updates_nb += aur_updates.length;
					foreach (UpdatesInfos infos in aur_updates) {
						name = infos.name + " " + infos.version;
						if (infos.download_size != 0)
							size = format_size (infos.download_size);
						else
							size = "";
						dsize += infos.download_size;
						updates_list.insert_with_values (out iter, -1, 0, name, 1, size);
					}
				}
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
			} else
				bottom_label.set_visible (false);

			this.get_window ().set_cursor (null);
			while (Gtk.events_pending ())
				Gtk.main_iteration ();
		}
	}
}
