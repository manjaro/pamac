/*
 *  pamac-vala
 *
 *  Copyright (C) 2018-2023 Guillaume Benoit <guillaume@manjaro.org>
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
	public class DatabaseGtk: Database {
		// parent window
		public Gtk.Window? window { get; set; }

		public DatabaseGtk (Config config) {
			Object (config: config);
			// window is set in manager.vala
		}

		construct {
			// connect to signals
			emit_warning.connect ((message) => {
				if (message.length == 0) {
					return;
				}
				var dialog = new Adw.MessageDialog (window, dgettext (null, "Error"), message);
				string close_id = "close";
				dialog.add_response (close_id, dgettext (null, "_Close"));
				dialog.default_response = close_id;
				dialog.close_response = close_id;
				// run
				dialog.present ();
			});
		}
	}
}
