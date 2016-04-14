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

// i18n
const string GETTEXT_PACKAGE = "pamac";

const string update_icon_name = "pamac-tray-update";
const string noupdate_icon_name = "pamac-tray-no-update";
const string noupdate_info = _("Your system is up-to-date");

namespace Pamac {
	[DBus (name = "org.manjaro.pamac")]
	interface Daemon : Object {
		public abstract string get_lockfile () throws IOError;
		public abstract void start_refresh (bool force) throws IOError;
		public abstract void start_get_updates (bool check_aur_updates) throws IOError;
		[DBus (no_reply = true)]
		public abstract void quit () throws IOError;
		public signal void get_updates_finished (Updates updates);
		public signal void write_pamac_config_finished (bool recurse, uint64 refresh_period, bool no_update_hide_icon,
														bool enable_aur, bool search_aur, bool check_aur_updates,
														bool no_confirm_build);
		public signal void write_alpm_config_finished (bool checkspace);
	}

	class TrayIcon: Gtk.Application {
		Notify.Notification notification;
//~ 		Notification notification;
		Daemon daemon;
		bool extern_lock;
		uint refresh_timeout_id;
		Gtk.StatusIcon status_icon;
		Gtk.Menu menu;
		GLib.File lockfile;

		public TrayIcon () {
			application_id = "org.manjaro.pamac.tray";
			flags = ApplicationFlags.FLAGS_NONE;
		}

		void start_daemon () {
			try {
				daemon = Bus.get_proxy_sync (BusType.SYSTEM, "org.manjaro.pamac", "/org/manjaro/pamac");
				// Connecting to signals
				daemon.get_updates_finished.connect (on_get_updates_finished);
				daemon.write_pamac_config_finished.connect (on_write_pamac_config_finished);
				daemon.write_alpm_config_finished.connect (on_write_alpm_config_finished);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		void stop_daemon () {
			if (!check_pamac_running ()) {
				try {
					daemon.quit ();
				} catch (IOError e) {
					stderr.printf ("IOError: %s\n", e.message);
				}
			}
		}

		// Create menu for right button
		void create_menu () {
			menu = new Gtk.Menu ();
			Gtk.MenuItem item;
			item = new Gtk.MenuItem.with_label (_("Update Manager"));
			item.activate.connect (execute_updater);
			menu.append (item);
			item = new Gtk.MenuItem.with_label (_("Package Manager"));
			item.activate.connect (execute_manager);
			menu.append (item);
			item = new Gtk.MenuItem.with_mnemonic (_("_Quit"));
			item.activate.connect (this.release);
			menu.append (item);
			menu.show_all ();
		}

		// Show popup menu on right button
		void menu_popup (uint button, uint time) {
			menu.popup (null, null, null, button, time);
		}

		void left_clicked () {
			if (status_icon.icon_name == "pamac-tray-update") {
				execute_updater ();
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

		public void update_icon (string icon, string info) {
			status_icon.set_from_icon_name (icon);
			status_icon.set_tooltip_markup (info);
		}

		bool start_refresh () {
			// if pamac is not running start refresh else just check updates 
			if (check_pamac_running ()) {
				check_updates ();
			} else {
				try {
					daemon.start_refresh (false);
				} catch (IOError e) {
					stderr.printf ("IOError: %s\n", e.message);
				}
			}
			return true;
		}

		void on_write_pamac_config_finished (bool recurse, uint64 refresh_period) {
			launch_refresh_timeout (refresh_period);
			if (refresh_period == 0) {
				status_icon.visible = false;
			} else {
				check_updates ();
			}
		}

		void on_write_alpm_config_finished (bool checkspace) {
			check_updates ();
		}

		void on_get_updates_finished (Updates updates) {
			uint updates_nb = updates.repos_updates.length + updates.aur_updates.length;
			if (updates_nb == 0) {
				this.update_icon (noupdate_icon_name, noupdate_info);
				var pamac_config = new Pamac.Config ("/etc/pamac.conf");
				if (pamac_config.no_update_hide_icon) {
					status_icon.visible = false;
				} else {
					status_icon.visible = true;
				}
				close_notification();
			} else {
				string info = ngettext ("%u available update", "%u available updates", updates_nb).printf (updates_nb);
				this.update_icon (update_icon_name, info);
				status_icon.visible = true;
				if (check_pamac_running ()) {
					update_notification (info);
				} else {
					show_notification (info);
				}
			}
			stop_daemon ();
		}

		void check_updates () {
			var pamac_config = new Pamac.Config ("/etc/pamac.conf");
			if (pamac_config.refresh_period == 0) {
				return;
			}
			try {
				daemon.start_get_updates (pamac_config.enable_aur && pamac_config.check_aur_updates);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		void show_notification (string info) {
//~ 				notification = new Notification (_("Update Manager"));
//~ 				notification.set_body (info);
//~ 				Gtk.IconTheme icon_theme = Gtk.IconTheme.get_default ();
//~ 				Gdk.Pixbuf icon = icon_theme.load_icon ("system-software-update", 32, 0);
//~ 				notification.set_icon (icon);
//~ 				var action = new SimpleAction ("update", null);
//~ 				action.activate.connect (execute_updater);
//~ 				this.add_action (action);
//~ 				notification.add_button (_("Show available updates"), "app.update");
//~ 				notification.set_default_action ("app.update");
//~ 				this.send_notification (_("Update Manager"), notification);
			try {
				close_notification();
				notification = new Notify.Notification (_("Update Manager"), info, "system-software-update");
				notification.add_action ("default", _("Show available updates"), execute_updater);
				notification.show ();
			} catch (Error e) {
				stderr.printf ("Notify Error: %s", e.message);
			}
		}

		void update_notification (string info) {
			try {
				if (notification != null) {
					if (notification.get_closed_reason() == -1 && notification.body != info) {
						notification.update (_("Update Manager"), info, "system-software-update");
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
				if (notification != null) {
				 	notification.close();
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
			app = new Application ("org.manjaro.pamac.updater", 0);
			try {
				app.register ();
			} catch (GLib.Error e) {
				stderr.printf ("%s\n", e.message);
			}
			run = app.get_is_remote ();
			if (run) {
				return run;
			}
			app = new Application ("org.manjaro.pamac.install", 0);
			try {
				app.register ();
			} catch (GLib.Error e) {
				stderr.printf ("%s\n", e.message);
			}
			run = app.get_is_remote ();
			return run;
		}

		bool check_pacman_running () {
			if (extern_lock) {
				if (!lockfile.query_exists ()) {
					extern_lock = false;
					// let the time to the daemon to update packages
					Timeout.add (1000, () => {
						check_updates ();
						return false;
					});
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
				refresh_timeout_id = Timeout.add_seconds ((uint) refresh_period_in_hours*3600, start_refresh);
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

			status_icon = new Gtk.StatusIcon ();
			status_icon.visible  = !(pamac_config.no_update_hide_icon);
			update_icon (noupdate_icon_name, noupdate_info);
			status_icon.activate.connect (left_clicked);
			create_menu ();
			status_icon.popup_menu.connect (menu_popup);

			Notify.init (_("Update Manager"));

			start_daemon ();
			try {
				lockfile = GLib.File.new_for_path (daemon.get_lockfile ());
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				//try standard lock file
				lockfile = GLib.File.new_for_path ("var/lib/pacman/db.lck");
			}
			Timeout.add (200, check_pacman_running);
			start_refresh ();
			launch_refresh_timeout (pamac_config.refresh_period);

			this.hold ();
		}

		public override void activate () {
			// nothing to do
		}

		static int main (string[] args) {
			var tray_icon = new TrayIcon();
			return tray_icon.run (args);
		}
	}
}
