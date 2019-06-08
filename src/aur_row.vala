/*
 *  pamac-vala
 *
 *  Copyright (C) 2019 Guillaume Benoit <guillaume@manjaro.org>
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

	[GtkTemplate (ui = "/org/manjaro/pamac/manager/aur_row.ui")]
	public class AURRow : Gtk.ListBoxRow {

		[GtkChild]
		public Gtk.Image app_icon;
		[GtkChild]
		public Gtk.Label name_label;
		[GtkChild]
		public Gtk.Label desc_label;
		[GtkChild]
		public Gtk.Label version_label;
		[GtkChild]
		public Gtk.ToggleButton action_togglebutton;
		[GtkChild]
		public Gtk.Button details_button;

		public AURPackage aur_pkg;

		public AURRow (AURPackage aur_pkg) {
			Object ();
			this.aur_pkg = aur_pkg;
		}

	}

}
