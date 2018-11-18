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

namespace Pamac {

	class Manager : Gtk.Application {
		ManagerWindow manager_window;
		Database database;
		SearchProvider search_provider;
		uint search_provider_id;
		const OptionEntry[] option_entries = {
			{ "version", 0, 0, OptionArg.NONE, null, "Display version number", null },
			{ "updates", 0, 0, OptionArg.NONE, null, "Display updates", null },
			{ null }
		};


		public Manager (Database database) {
			Object (application_id: "org.manjaro.pamac.manager", flags: ApplicationFlags.FLAGS_NONE);
			this.database = database;
			database.enable_appstream ();

			add_main_option_entries (option_entries);

			search_provider_id = 0;
			search_provider = new SearchProvider (database);
			search_provider.show_details.connect ((pkgname, timestamp) => {
				if (manager_window == null) {
					create_manager_window ();
					manager_window.refresh_packages_list ();
				}
				manager_window.main_stack.visible_child_name = "details";
				manager_window.display_package_properties (pkgname, "", false);
				manager_window.present_with_time (timestamp);
			});
			search_provider.search_full.connect ((terms, timestamp) => {
				var str_builder = new StringBuilder ();
				foreach (unowned string str in terms) {
					if (str_builder.len > 0) {
						str_builder.append (" ");
					}
					str_builder.append (str);
				}
				if (manager_window == null) {
					create_manager_window ();
				}
				manager_window.display_package_queue.clear ();
				manager_window.search_button.active = true;
				var entry = manager_window.search_comboboxtext.get_child () as Gtk.Entry;
				entry.set_text (str_builder.str);
				entry.set_position (-1);
				manager_window.present_with_time (timestamp);
			});
		}

		public override void startup () {
			// i18n
			Intl.textdomain ("pamac");
			Intl.setlocale (LocaleCategory.ALL, "");
			base.startup ();

			var action = new SimpleAction ("updates", null);
			action.activate.connect (() => {
				if (manager_window == null) {
					create_manager_window ();
				}
				manager_window.display_package_queue.clear ();
				manager_window.main_stack.visible_child_name = "browse";
				manager_window.filters_stack.visible_child_name = "updates";
				manager_window.present ();
			});
			this.add_action (action);
		}

		void create_manager_window () {
			manager_window = new ManagerWindow (this, database);
			// quit accel
			var action =  new SimpleAction ("quit", null);
			action.activate.connect  (() => {this.quit ();});
			this.add_action (action);
			string[] accels = {"<Ctrl>Q", "<Ctrl>W"};
			this.set_accels_for_action ("app.quit", accels);
			// back accel
			action =  new SimpleAction ("back", null);
			action.activate.connect  (() => {manager_window.on_button_back_clicked ();});
			this.add_action (action);
			accels = {"<Alt>Left"};
			this.set_accels_for_action ("app.back", accels);
			// search accel
			action =  new SimpleAction ("search", null);
			action.activate.connect  (() => {manager_window.search_button.activate ();});
			this.add_action (action);
			accels = {"<Ctrl>F"};
			this.set_accels_for_action ("app.search", accels);
		}

		public override bool dbus_register (DBusConnection connection, string object_path) {
			try {
				search_provider_id = connection.register_object (object_path + "/SearchProvider", search_provider);
			} catch (IOError error) {
				printerr ("Could not register search provider service: %s\n", error.message);
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
			if (manager_window == null) {
				create_manager_window ();
				manager_window.refresh_packages_list ();
			}
			manager_window.present ();
		}

		protected override int handle_local_options (VariantDict options) {
			if (options.contains ("version")) {
				stdout.printf ("Pamac  %s\n", VERSION);
				return 0;
			} else if (options.contains ("updates")) {
				try {
					this.register (null);
					this.activate_action ("updates", null);
				} catch (Error e) {
					stderr.printf ("%s\n", e.message);
					return 0;
				}
			}
			return -1;
		}

		public override void shutdown () {
			base.shutdown ();
			if (!check_pamac_running () && manager_window != null) {
				// stop system_daemon
				manager_window.transaction.quit_daemon ();
			}
		}

		bool check_pamac_running () {
			Application app;
			bool run = false;
			app = new Application ("org.manjaro.pamac.installer", 0);
			try {
				app.register ();
			} catch (GLib.Error e) {
				stderr.printf ("%s\n", e.message);
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
	return manager.run (args);
}
