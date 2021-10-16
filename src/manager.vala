/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2021 Guillaume Benoit <guillaume@manjaro.org>
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

	class Manager : Gtk.Application {
		Database database;
		SearchProvider search_provider;
		uint search_provider_id;
		bool version;
		bool updates;
		bool mobile;
		string? pkgname;
		string? app_id;
		string? search;
		OptionEntry[] options;


		public Manager (Database database) {
			Object (application_id: "org.manjaro.pamac.manager", flags: ApplicationFlags.HANDLES_OPEN);
			this.database = database;
			database.enable_appstream ();

			version = false;
			updates = false;
			pkgname = null;
			app_id = null;
			search = null;
			mobile = false;
			options = new OptionEntry[6];
			options[0] = { "version", 0, 0, OptionArg.NONE, ref version, "Display version number", null };
			options[1] = { "updates", 0, 0, OptionArg.NONE, ref updates, "Display updates", null };
			options[2] = { "details", 0, 0, OptionArg.STRING, ref pkgname, "Display package details", "PACKAGE_NAME" };
			options[3] = { "details-id", 0, 0, OptionArg.STRING, ref app_id, "Display package details", "APP_ID" };
			options[4] = { "search", 0, 0, OptionArg.STRING, ref search, "Search packages", "SEARCH" };
			options[5] = { "mobile", 0, 0, OptionArg.NONE, ref mobile, "Mobile version", null };
			add_main_option_entries (options);

			search_provider_id = 0;
			search_provider = new SearchProvider (database);
			search_provider.show_details.connect ((app_id, timestamp) => {
				this.activate_action ("details-id", new Variant ("s", app_id));
			});
			search_provider.search_full.connect ((terms, timestamp) => {
				var str_builder = new StringBuilder ();
				foreach (unowned string str in terms) {
					if (str_builder.len > 0) {
						str_builder.append (" ");
					}
					str_builder.append (str);
				}
				var manager_window = get_manager_window ();
				manager_window.display_package_queue.clear ();
				manager_window.search_button.clicked ();
				manager_window.search_entry.set_text (str_builder.str);
				manager_window.present_with_time (timestamp);
			});
		}

		public override void startup () {
			// i18n
			Intl.textdomain ("pamac");
			Intl.setlocale (LocaleCategory.ALL, "");
			base.startup ();

			// init libhandy
			Hdy.init ();

			// updates
			var action = new SimpleAction ("updates", null);
			action.activate.connect (() => {
				var manager_window = get_manager_window ();
				manager_window.display_package_queue.clear ();
				manager_window.main_stack.visible_child_name = "browse";
				manager_window.view_stack.visible_child_name = "updates";
				manager_window.activate_action ("back", null);
				manager_window.present ();
			});
			this.add_action (action);
			// details
			action = new SimpleAction ("details", new VariantType ("s"));
			action.activate.connect  ((parameter) => {
				var manager_window = get_manager_window ();
				pkgname = parameter.get_string ();
				AlpmPackage? pkg = this.database.get_pkg (pkgname);
				if (pkg != null) {
					manager_window.display_package_details (pkg);
					manager_window.main_stack.visible_child_name = "browse";
					manager_window.packages_leaflet.visible_child_name = "details";
					manager_window.main_details_box.visible = true;
					manager_window.browse_flap.visible = false;
					manager_window.set_adaptative_details (true);
					manager_window.view_stack_switcher.visible = false;
					manager_window.search_button.visible = false;
					manager_window.button_back.visible = true;
				}
				manager_window.present ();
			});
			this.add_action (action);
			// details_id
			action = new SimpleAction ("details-id", new VariantType ("s"));
			action.activate.connect  ((parameter) => {
				var manager_window = get_manager_window ();
				app_id = parameter.get_string ();
				Package? pkg = this.database.get_app_by_id (app_id);
				if (pkg != null) {
					manager_window.display_details (pkg);
					manager_window.main_stack.visible_child_name = "browse";
					manager_window.packages_leaflet.visible_child_name = "details";
					manager_window.main_details_box.visible = true;
					manager_window.browse_flap.visible = false;
					manager_window.set_adaptative_details (true);
					manager_window.view_stack_switcher.visible = false;
					manager_window.search_button.visible = false;
					manager_window.button_back.visible = true;
				}
				manager_window.present ();
			});
			this.add_action (action);
			// search
			action = new SimpleAction ("search", new VariantType ("s"));
			action.activate.connect  ((parameter) => {
				var manager_window = get_manager_window ();
				search = parameter.get_string ();
				manager_window.display_package_queue.clear ();
				manager_window.search_button.clicked ();
				manager_window.search_entry.set_text (search);
				manager_window.present ();
			});
			this.add_action (action);
		}

		ManagerWindow get_manager_window () {
			ManagerWindow manager_window;
			unowned Gtk.Window window = this.active_window;
			if (window == null) {
				manager_window = new ManagerWindow (this, database, mobile);
			} else {
				manager_window = window as ManagerWindow;
			}
			return manager_window;
		}

		public override bool dbus_register (DBusConnection connection, string object_path) {
			try {
				search_provider_id = connection.register_object (object_path + "/SearchProvider", search_provider);
			} catch (IOError error) {
				warning ("Could not register search provider service: %s", error.message);
			}
			return true;
		}

		public override void dbus_unregister (DBusConnection connection, string object_path) {
			if (search_provider_id != 0) {
				connection.unregister_object (search_provider_id);
				search_provider_id = 0;
			}
		}

		protected override void activate () {
			base.activate ();
			var manager_window = get_manager_window ();
			manager_window.refresh_packages_list ();
			manager_window.present ();
		}

		protected override int handle_local_options (VariantDict options) {
			if (version) {
				stdout.printf ("Pamac  %s\n", VERSION);
				return 0;
			} else if (updates) {
				try {
					this.register (null);
					this.activate_action ("updates", null);
				} catch (Error e) {
					warning (e.message);
					return 0;
				}
			} else if (pkgname != null) {
				try {
					this.register (null);
					this.activate_action ("details", new Variant ("s", pkgname));
				} catch (Error e) {
					warning (e.message);
					return 0;
				}
			} else if (app_id != null) {
				try {
					this.register (null);
					this.activate_action ("details-id", new Variant ("s", app_id));
				} catch (Error e) {
					warning (e.message);
					return 0;
				}
			} else if (search != null) {
				try {
					this.register (null);
					this.activate_action ("search", new Variant ("s", search));
				} catch (Error e) {
					warning (e.message);
					return 0;
				}
			}
			return -1;
		}

		public override void open (File[] files, string hint) {
			// open first file
			unowned File file = files[0];
			if (file.has_uri_scheme ("snap")) {
				string app_id = file.get_uri ().replace ("snap:", "").replace ("/", "");
				this.activate_action ("details-id", new Variant ("s", app_id));
				return;
			}
			if (file.has_uri_scheme ("appstream")) {
				string app_id = file.get_uri ().replace ("appstream:", "").replace ("/", "");
				this.activate_action ("details-id", new Variant ("s", app_id));
			} else {
				// just open pamac-manager
				this.activate_action ("details", new Variant ("s", ""));
			}
		}

		public override void shutdown () {
			base.shutdown ();
			unowned Gtk.Window window = this.active_window;
			if (!check_pamac_running () && window != null) {
				// stop system_daemon
				var manager_window = get_manager_window ();
				manager_window.transaction.quit_daemon ();
			}
		}

		bool check_pamac_running () {
			GLib.Application app;
			bool run = false;
			app = new GLib.Application ("org.manjaro.pamac.installer", 0);
			try {
				app.register ();
			} catch (Error e) {
				warning (e.message);
			}
			run = app.get_is_remote ();
			return run;
		}
	}
}

int main (string[] args) {
	var config = new Pamac.Config ("/etc/pamac.conf");
	var database = new Pamac.Database (config);
	var manager = new Pamac.Manager (database);
	// set translated app name
	var appinfo = new DesktopAppInfo ("org.manjaro.pamac.manager.desktop");
	Environment.set_application_name (appinfo.get_name ());
	return manager.run (args);
}
