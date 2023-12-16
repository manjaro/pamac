/*
 *  pamac-vala
 *
 *  Copyright (C) 2015-2021 Guillaume Benoit <guillaume@manjaro.org>
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
	[GtkTemplate (ui = "/org/manjaro/pamac/transaction/choose_pkgs_dialog.ui")]
	public class ChoosePkgsDialog : Adw.MessageDialog {
		[GtkChild]
		public unowned Gtk.SearchEntry search_entry;
		[GtkChild]
		public unowned Gtk.ListBox listbox;

		public ChoosePkgsDialog (Gtk.Window window) {
			Object (transient_for: window);
		}

		public void enable_search () {
			// enable "type to search"
			search_entry.visible = true;
			search_entry.set_key_capture_widget (this);
		}

		public void add_pkg (string pkgname) {
			var radiobutton = new Gtk.CheckButton ();
			// add label manually to make it wrapable
			var label = new Gtk.Label (pkgname);
			label.wrap = true;
			radiobutton.set_child (label);
			radiobutton.add_css_class ("selection-mode");
			listbox.append (radiobutton);
		}

		public GenericArray<string> get_selected_pkgs () {
			var selected = new GenericArray<string> ();
			unowned Gtk.Widget? widget = listbox.get_first_child ();
			while (widget != null) {
				unowned Gtk.ListBoxRow row = widget as Gtk.ListBoxRow;
				unowned Gtk.Widget child = row.get_child ();
				unowned Gtk.CheckButton radiobutton = child as Gtk.CheckButton;
				child = radiobutton.get_child ();
				unowned Gtk.Label label = child as Gtk.Label;
				if (radiobutton.active) {
					selected.add (label.label);
				}
				widget = widget.get_next_sibling ();
			}
			return selected;
		}

		[GtkCallback]
		void on_search_text_changed () {
			string search_string = search_entry.get_text ().down().strip ();
			if (search_string != "") {
				listbox.set_filter_func ((row) => {
					unowned Gtk.Widget child = row.get_child ();
					unowned Gtk.CheckButton radiobutton = child as Gtk.CheckButton;
					if (radiobutton.label.has_prefix (search_string)) {
						return true;
					}
					return false;
				});
			} else {
				listbox.set_filter_func (null);
			}
		}
	}
}
