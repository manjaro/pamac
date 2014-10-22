/*
 *  pamac-vala
 *
 *  Copyright (C) 2014  Guillaume Benoit <guillaume@manjaro.org>
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
		Pamac.Config pamac_config; 

		public Installer () {
			application_id = "org.manjaro.pamac.install";
			flags |= ApplicationFlags.HANDLES_OPEN;
		}

		public override void startup () {
			// i18n
			Intl.textdomain ("pamac");
			Intl.setlocale (LocaleCategory.ALL, "");

			base.startup ();

			pamac_config = new Pamac.Config ("/etc/pamac.conf");
			transaction = new Pamac.Transaction (null, pamac_config);
			transaction.finished.connect (on_emit_trans_finished);

			this.hold ();
		}

		public override void activate () {
			print ("\nError: Path(s) of tarball(s) to install is needed\n");
			transaction.stop_daemon ();
			this.release ();
		}

		public override void open (File[] files, string hint) {
			foreach (File file in files) {
				string? path = file.get_path ();
				transaction.data.to_load.insert (path, path);
			}
			transaction.run ();
		}

		public void on_emit_trans_finished (bool error) {
			transaction.stop_daemon ();
			this.release ();
		}

		public static int main (string[] args) {
			var installer = new Installer();
			return installer.run (args);
		}
	}
}
