/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2023 Guillaume Benoit <guillaume@manjaro.org>
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
	[GtkTemplate (ui = "/org/manjaro/pamac/transaction/choose_provider_dialog.ui")]
	class ChooseProviderDialog : Adw.MessageDialog {
		[GtkChild]
		unowned Gtk.Box box;

		public ChooseProviderDialog (Gtk.Window? window) {
			Object (transient_for: window);
		}

		public void add_providers (GenericArray<Package> pkgs) {
			unowned Gtk.CheckButton? last_radiobutton = null;
			foreach (unowned Package pkg in pkgs) {
				string provider = "%s  %s  %s".printf (pkg.name, pkg.version, pkg.repo);
				var radiobutton = new Gtk.CheckButton ();
				// add label manually to make it wrapable
				var label = new Gtk.Label (provider);
				label.wrap = true;
				radiobutton.set_child (label);
				radiobutton.add_css_class ("selection-mode");
				// active first provider
				if (last_radiobutton == null) {
					radiobutton.active = true;
				} else {
					radiobutton.set_group (last_radiobutton);
				}
				last_radiobutton = radiobutton;
				box.append (radiobutton);
			}
		}

		public async int choose_provider () {
			int index = 0;
			yield this.choose (null);
			unowned Gtk.Widget child = box.get_first_child ();
			var radiobutton = child as Gtk.CheckButton;
			while (radiobutton != null) {
				if (radiobutton.active) {
					break;
				}
				index++;
				child = radiobutton.get_next_sibling ();
				radiobutton = child as Gtk.CheckButton;
			}
			return index;
		}
	}
}
