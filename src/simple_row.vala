/*
 *  pamac-vala
 *
 *  Copyright (C) 2020 Guillaume Benoit <guillaume@manjaro.org>
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
	[GtkTemplate (ui = "/org/manjaro/pamac/manager/simple_row.ui")]
	public class SimpleRow: Gtk.ListBoxRow {
		[GtkChild]
		public unowned Gtk.Label label;

		public string? title { get { return label.label; } }

		public SimpleRow (string? title) {
			label.label = title;
		}
	}
}
