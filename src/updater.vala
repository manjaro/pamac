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

namespace Pamac {

	public class Updater : Gtk.Application {
		UpdaterWindow updater_window;
		bool pamac_run;

		public Updater () {
			application_id = "org.manjaro.pamac.updater";
			flags = ApplicationFlags.FLAGS_NONE;
		}

		public override void startup () {
			// i18n
			Intl.textdomain ("pamac");
			Intl.setlocale (LocaleCategory.ALL, "");

			base.startup ();

			pamac_run = check_pamac_running ();
			if (pamac_run) {
				var transaction_info_dialog = new TransactionInfoDialog (null);
				transaction_info_dialog.set_title (dgettext (null, "Error"));
				transaction_info_dialog.label.set_visible (true);
				transaction_info_dialog.label.set_markup (dgettext (null, "Pamac is already running"));
				transaction_info_dialog.expander.set_visible (false);
				transaction_info_dialog.run ();
				transaction_info_dialog.hide ();
			} else {
				updater_window = new UpdaterWindow (this);
			}
		}

		public override void activate () {
			if (!pamac_run) {
				updater_window.present ();
			}
		}

		public override void shutdown () {
			base.shutdown ();
			if (!pamac_run) {
				updater_window.transaction.stop_daemon ();
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
			app = new Application ("org.manjaro.pamac.install", 0);
			try {
				app.register ();
			} catch (GLib.Error e) {
				stderr.printf ("%s\n", e.message);
			}
			run = app.get_is_remote ();
			return run;
		}
	}

	public static int main (string[] args) {
		var updater = new Updater ();
		return updater.run (args);
	}
}
