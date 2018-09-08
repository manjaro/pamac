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
		bool started;

		public Manager () {
			application_id = "org.manjaro.pamac.manager";
			flags = ApplicationFlags.HANDLES_COMMAND_LINE;
		}

		public override void startup () {
			// i18n
			Intl.textdomain ("pamac");
			Intl.setlocale (LocaleCategory.ALL, "");

			base.startup ();

			manager_window = new ManagerWindow (this);
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

		public override int command_line (ApplicationCommandLine cmd) {
			// fix #367
			if (manager_window == null) {
				return 1;
			}
			if (cmd.get_arguments ()[0] == "pamac-updater") {
				if (!started) {
					manager_window.update_lists ();
					started = true;
				}
				manager_window.display_package_queue.clear ();
				manager_window.main_stack.visible_child_name = "browse";
				manager_window.filters_stack.visible_child_name = "updates";
			} else if (!started) {
				manager_window.update_lists ();
				manager_window.refresh_packages_list ();
				started = true;
			}
			if (cmd.get_arguments ().length == 3) {
				if (cmd.get_arguments ()[1] == "--search") {
					manager_window.display_package_queue.clear ();
					manager_window.search_button.active = true;
					var entry = manager_window.search_comboboxtext.get_child () as Gtk.Entry;
					entry.set_text (cmd.get_arguments ()[2]);
				}
			}
			manager_window.present ();
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
			return 0;
		}

		public override void shutdown () {
			base.shutdown ();
			if (!check_pamac_running ()) {
				// stop system_daemon
				manager_window.transaction = null;
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

	static int main (string[] args) {
		var manager = new Manager ();
		return manager.run (args);
	}
}
