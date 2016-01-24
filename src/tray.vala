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

// i18n
const string GETTEXT_PACKAGE = "pamac";

const string update_icon_name = "pamac-tray-update";
const string noupdate_icon_name = "pamac-tray-no-update";
const string noupdate_info = _("Your system is up-to-date");

namespace Pamac {
	[DBus (name = "org.manjaro.pamac")]
	public interface Daemon : Object {
		public abstract void start_refresh (int force) throws IOError;
		public abstract async Updates get_updates (bool check_aur_updates) throws IOError;
		[DBus (no_reply = true)]
		public abstract void quit () throws IOError;
		public signal void refresh_finished (ErrorInfos error);
		public signal void write_pamac_config_finished (bool recurse, int refresh_period, bool no_update_hide_icon,
														bool enable_aur, bool search_aur, bool check_aur_updates,
														bool no_confirm_build);
		public signal void write_alpm_config_finished (bool checkspace);
	}

	public class TrayIcon: Gtk.Application {
		Notify.Notification notification;
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
				daemon = Bus.get_proxy_sync (BusType.SYSTEM, "org.manjaro.pamac",
														"/org/manjaro/pamac");
				// Connecting to signals
				daemon.write_pamac_config_finished.connect (on_write_pamac_config_finished);
				daemon.write_alpm_config_finished.connect (on_write_alpm_config_finished);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		void stop_daemon () {
			if (check_pamac_running () == false) {
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
					daemon.start_refresh (0);
				} catch (IOError e) {
					stderr.printf ("IOError: %s\n", e.message);
				}
			}
			return true;
		}

		void on_write_pamac_config_finished (bool recurse, int refresh_period, bool no_update_hide_icon,
											bool enable_aur, bool search_aur, bool check_aur_updates,
											bool no_confirm_build) {
			launch_refresh_timeout ((uint) refresh_period);
			if (refresh_period == 0) {
				status_icon.visible = false;
			} else {
				check_updates ();
			}
		}

		void on_write_alpm_config_finished (bool checkspace) {
			check_updates ();
		}

		void check_updates () {
			var pamac_config = new Pamac.Config ("/etc/pamac.conf");
			if (pamac_config.refresh_period == 0) {
				return;
			}
			daemon.get_updates.begin ((pamac_config.enable_aur && pamac_config.check_aur_updates), (obj, res) => {
				var updates = Updates ();
				try {
					updates = daemon.get_updates.end (res);
				} catch (IOError e) {
					stderr.printf ("IOError: %s\n", e.message);
				}
				uint updates_nb = updates.repos_updates.length + updates.aur_updates.length;
				if (updates_nb == 0) {
					this.update_icon (noupdate_icon_name, noupdate_info);
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
					if (check_pamac_running () == false) {
						show_notification (info);
					} else {
						update_notification (info);
					}
				}
				stop_daemon ();
			});
		}

		void on_notification_closed () {
			int reason = notification.get_closed_reason();
			if(reason == 2) { /* NOTIFYD_CLOSED_USER */
				execute_updater ();
			}
		}

		void show_notification (string info) {
			try {
				close_notification();
				notification = new Notify.Notification (_("Update Manager"), info, "system-software-update");
				// notification.add_action ("update", _("Show available updates"), execute_updater);
				notification.closed.connect (on_notification_closed);
				notification.show ();
			} catch (Error e) {
				stderr.printf ("Notify Error: %s", e.message);
			}
		}

		void update_notification (string info) {
			try {
				if(notification != null) {
					if(notification.get_closed_reason() == -1 && notification.body != info) {
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
				if(notification != null) {
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
				if (lockfile.query_exists () == false) {
					extern_lock = false;
					// let the time to the daemon to update packages
					Timeout.add (1000, () => {
						check_updates ();
						return false;
					});
				}
			} else {
				if (lockfile.query_exists () == true) {
					extern_lock = true;
				}
			}
			return true;
		}

		void launch_refresh_timeout (uint refresh_period_in_hours) {
			if (refresh_timeout_id != 0) {
				Source.remove (refresh_timeout_id);
				refresh_timeout_id = 0;
			}
			if (refresh_period_in_hours != 0) {
				refresh_timeout_id = Timeout.add_seconds (refresh_period_in_hours*3600, start_refresh);
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
			this.update_icon (noupdate_icon_name, noupdate_info);
			status_icon.activate.connect (left_clicked);
			create_menu ();
			status_icon.popup_menu.connect (menu_popup);

			Notify.init (_("Update Manager"));

			var alpm_config = new Alpm.Config ("/etc/pacman.conf");
			alpm_config.get_handle ();
			lockfile = GLib.File.new_for_path (alpm_config.handle.lockfile);
			start_daemon ();
			Timeout.add (500, check_pacman_running);
			start_refresh ();
			launch_refresh_timeout ((uint) pamac_config.refresh_period);

			this.hold ();
		}

		public override void activate () {
			// nothing to do
		}

		public static int main (string[] args) {
			var tray_icon = new TrayIcon();
			return tray_icon.run (args);
		}
	}
}
