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

	public class Manager : Gtk.Application {

		ManagerWindow manager_window;

		public Manager () {
			application_id = "org.manjaro.pamac.manager";
			flags = ApplicationFlags.FLAGS_NONE;
		}

		public override void startup () {
			// i18n
			Intl.textdomain ("pamac");
			Intl.setlocale (LocaleCategory.ALL, "");

			base.startup ();

			manager_window = new ManagerWindow (this);
		}

		public override void activate () {
			manager_window.present ();
		}

		public override void shutdown () {
			base.shutdown ();
			manager_window.transaction.stop_daemon ();
		}
	}

	public static int main (string[] args) {
		var manager = new Manager ();
		return manager.run (args);
	}
}
