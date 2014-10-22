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

	[GtkTemplate (ui = "/org/manjaro/pamac/manager/packages_chooser_dialog.ui")]
	public class PackagesChooserDialog : Gtk.FileChooserDialog {

		ManagerWindow window;
		Transaction transaction;

		public PackagesChooserDialog (ManagerWindow window, Transaction transaction) {
			Object (transient_for: window, use_header_bar: 0);

			Gtk.FileFilter package_filter = new Gtk.FileFilter ();
			package_filter.set_filter_name (dgettext (null, "Packages"));
			package_filter.add_pattern ("*.pkg.tar.gz");
			package_filter.add_pattern ("*.pkg.tar.xz");
			this.add_filter (package_filter);

			this.window = window;
			this.transaction = transaction;
		}

		[GtkCallback]
		public void on_file_activated () {
			SList<string> packages_paths = this.get_filenames ();
			if (packages_paths.length () != 0) {
				foreach (string path in packages_paths) {
					transaction.data.to_load.insert (path, path);
				}
				window.get_window ().set_cursor (new Gdk.Cursor (Gdk.CursorType.WATCH));
				this.hide ();
				while (Gtk.events_pending ())
					Gtk.main_iteration ();
				transaction.run ();
			}
		}
	}
}
