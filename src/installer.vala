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

namespace Pamac {

	public class Installer: Gtk.Application {
		Transaction transaction;
		bool pamac_run;

		public Installer () {
			application_id = "org.manjaro.pamac.install";
			flags |= ApplicationFlags.HANDLES_OPEN;
		}

		public override void startup () {
			// i18n
			Intl.textdomain ("pamac");
			Intl.setlocale (LocaleCategory.ALL, "");

			base.startup ();

			pamac_run = check_pamac_running ();
			if (pamac_run) {
				var msg = new Gtk.MessageDialog (null,
												Gtk.DialogFlags.MODAL,
												Gtk.MessageType.ERROR,
												Gtk.ButtonsType.OK,
												dgettext (null, "Pamac is already running"));
				msg.run ();
				msg.destroy ();
			} else {
				transaction = new Pamac.Transaction (null);
				transaction.finished.connect (on_transaction_finished);
				this.hold ();
			}
		}

		public override void activate () {
			if (!pamac_run) {
				print ("\nError: Path(s) of tarball(s) to install is needed\n");
				transaction.stop_daemon ();
				this.release ();
			}
		}

		public override void open (File[] files, string hint) {
			if (!pamac_run) {
				foreach (unowned File file in files) {
					transaction.to_load.add (file.get_path ());
				}
				transaction.run ();
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
			return run;
		}

		void on_transaction_finished () {
			transaction.stop_daemon ();
			this.release ();
		}

		public static int main (string[] args) {
			var installer = new Installer();
			return installer.run (args);
		}
	}
}
