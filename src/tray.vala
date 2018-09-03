/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2018 Guillaume Benoit <guillaume@manjaro.org>
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

// i18n
const string GETTEXT_PACKAGE = "pamac";

const string update_icon_name = "pamac-tray-update";
const string noupdate_icon_name = "pamac-tray-no-update";
const string noupdate_info = _("Your system is up-to-date");

namespace Pamac {
	public abstract class TrayIcon: Gtk.Application {
		Notify.Notification notification;
		Database database;
		Transaction transaction;
		bool extern_lock;
		uint refresh_timeout_id;
		public Gtk.Menu menu;
		GLib.File lockfile;
		uint updates_nb;

		public TrayIcon () {
			application_id = "org.manjaro.pamac.tray";
			flags = ApplicationFlags.FLAGS_NONE;
		}

		void init_database () {
			if (database == null) {
				var config = new Config ("/etc/pamac.conf");
				database = new Database (config);
				database.refresh_files_dbs_on_get_updates = true;
			}
		}

		void init_transaction () {
			if (transaction == null) {
				if (database == null) {
					init_database ();
				}
				transaction = new Transaction (database);
			}
		}

		public abstract void init_status_icon ();

		// Create menu for right button
		void create_menu () {
			menu = new Gtk.Menu ();
			var item = new Gtk.MenuItem.with_label (_("Package Manager"));
			item.activate.connect (execute_manager);
			menu.append (item);
			item = new Gtk.MenuItem.with_mnemonic (_("_Quit"));
			item.activate.connect (this.release);
			menu.append (item);
			menu.show_all ();
		}

		public void left_clicked () {
			if (get_icon () == "pamac-tray-update") {
				execute_updater ();
			} else {
				execute_manager ();
			}
		}

		void execute_updater () {
			try {
				Process.spawn_command_line_async ("pamac-updater");
			} catch (SpawnError e) {
				stderr.printf ("SpawnError: %s\n", e.message);
			}
		}

		void execute_manager () {
			try {
				Process.spawn_command_line_async ("pamac-manager");
			} catch (SpawnError e) {
				stderr.printf ("SpawnError: %s\n", e.message);
			}
		}

		public abstract void set_tooltip (string info);

		public abstract void set_icon (string icon);

		public abstract string get_icon ();

		public abstract void set_icon_visible (bool visible);

		bool check_updates () {
			init_database ();
			if (database.config.refresh_period != 0) {
				database.start_get_updates ();
				database.get_updates_finished.connect (on_get_updates_finished);
			}
			return true;
		}

		void on_get_updates_finished (Updates updates) {
			database.get_updates_finished.disconnect (on_get_updates_finished);
			updates_nb = updates.repos_updates.length () + updates.aur_updates.length ();
			if (updates_nb == 0) {
				set_icon (noupdate_icon_name);
				set_tooltip (noupdate_info);
				set_icon_visible (!database.config.no_update_hide_icon);
				close_notification ();
				// stop user_daemon
				database = null;
			} else {
				if (!check_pamac_running () && database.config.download_updates) {
					init_transaction ();
					transaction.start_downloading_updates ();
					transaction.downloading_updates_finished.connect (on_downloading_updates_finished);
				} else {
					show_or_update_notification ();
					// stop user_daemon
					database = null;
				}
			}
		}

		void on_downloading_updates_finished () {
			transaction.downloading_updates_finished.disconnect (on_downloading_updates_finished);
			show_or_update_notification ();
			// stop system_daemon
			transaction = null;
			// stop user_daemon
			database = null;
		}

		void show_or_update_notification () {
			string info = ngettext ("%u available update", "%u available updates", updates_nb).printf (updates_nb);
			set_icon (update_icon_name);
			set_tooltip (info);
			set_icon_visible (true);
			if (check_pamac_running ()) {
				update_notification (info);
			} else {
				show_notification (info);
			}
		}

		void show_notification (string info) {
			try {
				close_notification ();
				notification = new Notify.Notification (_("Package Manager"), info, "system-software-update");
				notification.add_action ("default", _("Details"), execute_updater);
				notification.show ();
			} catch (Error e) {
				stderr.printf ("Notify Error: %s", e.message);
			}
		}

		void update_notification (string info) {
			try {
				if (notification != null) {
					if (notification.get_closed_reason () == -1 && notification.body != info) {
						notification.update (_("Package Manager"), info, "system-software-update");
						notification.show ();
					}
				} else {
					show_notification (info);
				}
			} catch (Error e) {
				stderr.printf ("Notify Error: %s", e.message);
			}
		}

		void close_notification () {
			try {
				if (notification != null && notification.get_closed_reason () == -1) {
					notification.close ();
					notification = null;
				}
			} catch (Error e) {
				stderr.printf ("Notify Error: %s", e.message);
			}
		}

		bool check_pamac_running () {
			Application app;
			bool run = false;
			app = new Application ("org.manjaro.pamac.manager", 0);
			try {
				app.register ();
			} catch (GLib.Error e) {
				stderr.printf ("%s\n", e.message);
			}
			run = app.get_is_remote ();
			if (run) {
				return run;
			}
			app = new Application ("org.manjaro.pamac.installer", 0);
			try {
				app.register ();
			} catch (GLib.Error e) {
				stderr.printf ("%s\n", e.message);
			}
			run = app.get_is_remote ();
			return run;
		}

		bool check_extern_lock () {
			if (extern_lock) {
				if (!lockfile.query_exists ()) {
					extern_lock = false;
					if (database != null) {
						database.refresh ();
					}
					check_updates ();
				}
			} else {
				if (lockfile.query_exists ()) {
					extern_lock = true;
				}
			}
			return true;
		}

		void launch_refresh_timeout (uint64 refresh_period_in_hours) {
			if (refresh_timeout_id != 0) {
				Source.remove (refresh_timeout_id);
				refresh_timeout_id = 0;
			}
			if (refresh_period_in_hours != 0) {
				refresh_timeout_id = Timeout.add_seconds ((uint) refresh_period_in_hours*3600, check_updates);
			}
		}

		public override void startup () {
			// i18n
			Intl.textdomain ("pamac");
			Intl.setlocale (LocaleCategory.ALL, "");

			var pamac_config = new Config ("/etc/pamac.conf");
			// if refresh period is 0, just return so tray will exit
			if (pamac_config.refresh_period == 0) {
				return;
			}

			base.startup ();

			extern_lock = false;
			refresh_timeout_id = 0;

			create_menu ();
			init_status_icon ();
			set_icon (noupdate_icon_name);
			set_tooltip (noupdate_info);
			set_icon_visible (!pamac_config.no_update_hide_icon);

			Notify.init (_("Package Manager"));

			init_transaction ();
			lockfile = GLib.File.new_for_path (transaction.get_lockfile ());
			// stop system_daemon
			transaction = null;

			Timeout.add (200, check_extern_lock);
			// wait 30 seconds before check updates
			Timeout.add_seconds (30, () => {
				check_updates ();
				return false;
			});
			launch_refresh_timeout (pamac_config.refresh_period);

			this.hold ();
		}

		public override void activate () {
			// nothing to do
		}

	}
}
