/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2020 Guillaume Benoit <guillaume@manjaro.org>
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
		Gtk.IconTheme icon_theme;
		protected UpdatesChecker updates_checker;

		protected TrayIcon () {
			application_id = "org.manjaro.pamac.tray";
			flags = ApplicationFlags.FLAGS_NONE;
			updates_checker = new UpdatesChecker ();
			updates_checker.updates_available.connect ((updates_nb) => {
				if (updates_nb == 0) {
					set_icon (noupdate_icon_name);
					set_tooltip (noupdate_info);
					set_icon_visible (!updates_checker.no_update_hide_icon);
					close_notification ();
				} else {
					show_or_update_notification (updates_checker.updates_nb);
				}
			});
		}

		public abstract void init_status_icon ();

		// Create menu for right button
		public Gtk.Menu create_menu () {
			var menu = new Gtk.Menu ();
			var item = new Gtk.MenuItem.with_label (_("Package Manager"));
			item.activate.connect (execute_manager);
			menu.append (item);
			item = new Gtk.MenuItem.with_mnemonic (_("_Quit"));
			item.activate.connect (this.release);
			menu.append (item);
			menu.show_all ();
			return menu;
		}

		public void left_clicked () {
			if (updates_checker.updates_nb > 0) {
				execute_updater ();
			} else {
				execute_manager ();
			}
		}

		void execute_updater () {
			try {
				Process.spawn_command_line_async ("pamac-manager --updates");
			} catch (SpawnError e) {
				warning (e.message);
			}
		}

		void execute_manager () {
			try {
				Process.spawn_command_line_async ("pamac-manager");
			} catch (SpawnError e) {
				warning (e.message);
			}
		}

		public abstract void set_tooltip (string info);

		public abstract void set_icon (string icon);

		public abstract void set_icon_visible (bool visible);

		void show_or_update_notification (uint updates_nb) {
			string info = ngettext ("%u available update", "%u available updates", updates_nb).printf (updates_nb);
			set_icon (update_icon_name);
			set_tooltip (info);
			set_icon_visible (true);
			update_notification (info);
		}

		void show_notification (string info) {
			try {
				close_notification ();
				notification = new Notify.Notification (_("Package Manager"), info, "system-software-install-symbolic");
				notification.set_timeout (Notify.EXPIRES_DEFAULT);
				notification.add_action ("default", _("Details"), execute_updater);
				notification.show ();
			} catch (Error e) {
				warning (e.message);
			}
		}

		void update_notification (string info) {
			try {
				if (notification != null) {
					if (notification.get_closed_reason () == -1 && notification.body != info) {
						notification.update (_("Package Manager"), info, "system-software-install-symbolic");
						notification.show ();
					}
				} else {
					show_notification (info);
				}
			} catch (Error e) {
				warning (e.message);
			}
		}

		void close_notification () {
			try {
				if (notification != null && notification.get_closed_reason () == -1) {
					notification.close ();
					notification = null;
				}
			} catch (Error e) {
				warning (e.message);
			}
		}

		void launch_refresh_timeout () {
			// check every hour if refresh_timestamp is older than config.refresh_period
			Timeout.add_seconds (3600, updates_checker.check_updates);
		}

		void on_icon_theme_changed () {
			icon_theme = Gtk.IconTheme.get_default ();
			if (updates_checker.updates_nb > 0) {
				set_icon (update_icon_name);
			} else {
				set_icon (noupdate_icon_name);
			}
		}

		public override void startup () {
			// i18n
			Intl.textdomain ("pamac");
			Intl.setlocale (LocaleCategory.ALL, "");

			base.startup ();

			// if refresh period is 0, just return so tray will exit
			if (updates_checker.refresh_period == 0) {
				message ("checking updates is not enabled, exiting");
				return;
			}

			icon_theme = Gtk.IconTheme.get_default ();
			icon_theme.changed.connect (on_icon_theme_changed);
			init_status_icon ();
			set_icon (noupdate_icon_name);
			set_tooltip (noupdate_info);
			set_icon_visible (!updates_checker.no_update_hide_icon);

			Notify.init (_("Package Manager"));

			// wait 30 seconds before check updates
			Timeout.add_seconds (30, () => {
				updates_checker.check_updates ();
				return false;
			});
			launch_refresh_timeout ();

			this.hold ();
		}

		public override void activate () {
			// nothing to do
		}

	}
}
