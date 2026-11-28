/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2026 Guillaume Benoit <guillaume@manjaro.org>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

// i18n
const string GETTEXT_PACKAGE = "pamac";

namespace Pamac {
	public abstract class TrayIcon: Gtk3.Application {
		string update_icon_name = "pamac-tray-update";
		string noupdate_icon_name = "pamac-tray-no-update";
		// translated when used: field initializers run in the constructor,
		// before setlocale () is called in startup ()
		const string update_info = N_("Updates Available");
		const string noupdate_info = N_("Your system is up to date");
		Notify.Notification notification;
		// number of updates the last notification was shown for
		uint notified_updates_nb;
		Gtk3.IconTheme icon_theme;
		protected UpdatesChecker updates_checker;

		protected TrayIcon () {
			application_id = "org.manjaro.pamac.tray";
			flags = ApplicationFlags.FLAGS_NONE;
			updates_checker = new UpdatesChecker ();
			updates_checker.updates_available.connect ((updates_nb) => {
				if (updates_nb == 0) {
					set_icon (noupdate_icon_name);
					set_tooltip (_(noupdate_info));
					set_icon_visible (!updates_checker.no_update_hide_icon);
					notified_updates_nb = 0;
					close_notification ();
				} else {
					show_or_update_notification (updates_checker.updates_nb);
				}
			});
		}

		public abstract void init_status_icon ();

		// Create menu for right button
		public Gtk3.Menu create_menu () {
			var menu = new Gtk3.Menu ();
			var item = new Gtk3.MenuItem.with_label (_("Package Manager"));
			item.activate.connect (execute_manager);
			menu.append (item);
			item = new Gtk3.MenuItem.with_mnemonic (_("_Quit"));
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
			// notify again only when available updates changed,
			// not at each hourly check
			if (updates_nb != notified_updates_nb) {
				notified_updates_nb = updates_nb;
				update_notification (_(update_info), get_notification_body (info));
			}
		}

		// number of updates and download size, number of updates by source if there are several,
		// names of the first updated packages and the need of a restart
		string get_notification_body (string info) {
			var body = new StringBuilder (info);
			uint64 download_size = updates_checker.download_size;
			if (download_size > 0) {
				body.append (" (%s)".printf (format_size (download_size)));
			}
			// number of updates by source
			string[] sources = {};
			if (updates_checker.repos_updates_nb > 0) {
				sources += "%s: %u".printf (_("Repositories"), updates_checker.repos_updates_nb);
			}
			if (updates_checker.aur_updates_nb > 0) {
				sources += "%s: %u".printf (_("AUR"), updates_checker.aur_updates_nb);
			}
			if (updates_checker.flatpak_updates_nb > 0) {
				sources += "%s: %u".printf (_("Flatpak"), updates_checker.flatpak_updates_nb);
			}
			if (sources.length > 1) {
				body.append_c ('\n');
				body.append (Markup.escape_text (string.joinv (", ", sources)));
			}
			const uint MAX_NAMES = 5;
			var names = new StringBuilder ();
			uint names_nb = 0;
			foreach (unowned string line in updates_checker.updates_list) {
				// lines are "name  version" or "name  installed_version -> version"
				string name = line.split (" ", 2)[0];
				if (name == "") {
					continue;
				}
				if (names_nb == MAX_NAMES) {
					names.append (", …");
					break;
				}
				if (names_nb > 0) {
					names.append (", ");
				}
				names.append (Markup.escape_text (name));
				names_nb++;
			}
			if (names_nb > 0) {
				body.append_c ('\n');
				body.append (names.str);
			}
			if (updates_checker.reboot_required) {
				body.append_c ('\n');
				body.append (Markup.escape_text (_("A restart will be required")));
			}
			return body.str;
		}

		void show_notification (string summary, string body) {
			try {
				close_notification ();
				notification = new Notify.Notification (summary, body, "system-software-install-symbolic");
				notification.set_timeout (Notify.EXPIRES_DEFAULT);
				notification.add_action ("default", _("Details"), execute_updater);
				notification.show ();
			} catch (Error e) {
				warning (e.message);
			}
		}

		void update_notification (string summary, string body) {
			try {
				// get_closed_reason () is -1 while the notification is still displayed
				if (notification != null && notification.get_closed_reason () == -1) {
					notification.update (summary, body, "system-software-install-symbolic");
					notification.show ();
				} else {
					// no notification yet, or it expired or was dismissed: show a new one
					show_notification (summary, body);
				}
			} catch (Error e) {
				warning (e.message);
			}
		}

		void close_notification () {
			try {
				if (notification != null) {
					if (notification.get_closed_reason () == -1) {
						notification.close ();
					}
					// also forget an expired or dismissed notification
					notification = null;
				}
			} catch (Error e) {
				warning (e.message);
			}
		}

		void launch_refresh_timeout () {
			// check every hour if refresh_timestamp is older than config.refresh_period
			Timeout.add_seconds (3600, () => {
				updates_checker.check_updates ();
				return true;
			});
		}

		void on_icon_theme_changed () {
			icon_theme = Gtk3.IconTheme.get_default ();
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

			icon_theme = Gtk3.IconTheme.get_default ();
			icon_theme.changed.connect (on_icon_theme_changed);
			init_status_icon ();
			set_icon (noupdate_icon_name);
			set_tooltip (_(noupdate_info));
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
