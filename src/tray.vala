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

// i18n
const string GETTEXT_PACKAGE = "pamac";

const string update_icon_name = "pamac-tray-update";
const string noupdate_icon_name = "pamac-tray-no-update";
const string noupdate_info = _("Your system is up-to-date");

namespace Pamac {
	[DBus (name = "org.manjaro.pamac.user")]
	interface UserDaemon : Object {
		public abstract void refresh_handle () throws Error;
		public abstract string get_lockfile () throws Error;
		public abstract void start_get_updates (bool check_aur_updates) throws Error;
		[DBus (no_reply = true)]
		public abstract void quit () throws Error;
		public signal void get_updates_finished (Updates updates);
	}

	public abstract class TrayIcon: Gtk.Application {
		Notify.Notification notification;
		UserDaemon daemon;
		bool extern_lock;
		uint refresh_timeout_id;
		public Gtk.Menu menu;
		GLib.File lockfile;

		public TrayIcon () {
			application_id = "org.manjaro.pamac.tray";
			flags = ApplicationFlags.FLAGS_NONE;
		}

		public abstract void init_status_icon ();

		void start_daemon () {
			try {
				daemon = Bus.get_proxy_sync (BusType.SESSION, "org.manjaro.pamac.user", "/org/manjaro/pamac/user");
				daemon.get_updates_finished.connect (on_get_updates_finished);
			} catch (Error e) {
				stderr.printf ("Error: %s\n", e.message);
			}
		}

		void stop_daemon () {
			if (!check_pamac_running ()) {
				try {
					daemon.quit ();
				} catch (Error e) {
					stderr.printf ("Error: %s\n", e.message);
				}
			}
		}

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
			var pamac_config = new Pamac.Config ("/etc/pamac.conf");
			if (pamac_config.refresh_period != 0) {
				try {
					daemon.start_get_updates (pamac_config.enable_aur && pamac_config.check_aur_updates);
				} catch (Error e) {
					stderr.printf ("Error: %s\n", e.message);
				}
			}
			return true;
		}

		void on_get_updates_finished (Updates updates) {
			uint updates_nb = updates.repos_updates.length + updates.aur_updates.length;
			if (updates_nb == 0) {
				set_icon (noupdate_icon_name);
				set_tooltip (noupdate_info);
				var pamac_config = new Pamac.Config ("/etc/pamac.conf");
				set_icon_visible (!pamac_config.no_update_hide_icon);
				close_notification ();
			} else {
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
			stop_daemon ();
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
					try {
						daemon.refresh_handle ();
					} catch (Error e) {
						stderr.printf ("Error: %s\n", e.message);
					}
					check_updates ();
				}
			} else {
				if (lockfile.query_exists ()) {
					if (!check_pamac_running ()) {
						extern_lock = true;
					}
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

			var pamac_config = new Pamac.Config ("/etc/pamac.conf");
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

			start_daemon ();
			try {
				lockfile = GLib.File.new_for_path (daemon.get_lockfile ());
			} catch (Error e) {
				stderr.printf ("Error: %s\n", e.message);
				//try standard lock file
				lockfile = GLib.File.new_for_path ("var/lib/pacman/db.lck");
			}
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
