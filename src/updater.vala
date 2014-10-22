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

	public class Updater : Gtk.Application {

		UpdaterWindow updater_window;

		public Updater () {
			application_id = "org.manjaro.pamac.updater";
			flags = ApplicationFlags.FLAGS_NONE;
		}

		public override void startup () {
			// i18n
			Intl.textdomain ("pamac");
			Intl.setlocale (LocaleCategory.ALL, "");

			base.startup ();

			updater_window = new UpdaterWindow (this);
		}

		public override void activate () {
			updater_window.present ();
		}

		public override void shutdown () {
			base.shutdown ();
			updater_window.transaction.stop_daemon ();
		}
	}

	public static int main (string[] args) {
		var updater = new Updater ();
		return updater.run (args);
	}
}
