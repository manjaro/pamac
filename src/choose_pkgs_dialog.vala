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
	public class ChoosePkgsDialog : Gtk.Dialog {
		[GtkChild]
		public unowned Adw.Clamp search_clamp;
		[GtkChild]
		public unowned Gtk.SearchEntry search_entry;
		[GtkChild]
		public unowned Gtk.Separator search_separator;
		[GtkChild]
		public unowned Gtk.ListBox listbox;
		[GtkChild]
		public unowned Gtk.Button cancel_button;

		public ChoosePkgsDialog (Gtk.Window window) {
			int use_header_bar;
			Gtk.Settings.get_default ().get ("gtk-dialogs-use-header", out use_header_bar);
			Object (transient_for: window, use_header_bar: use_header_bar);
		}

		public void enable_search () {
			// enable "type to search"
			search_entry.set_key_capture_widget (this);
		}

		public void add_pkg (string pkgname) {
			var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
			box.margin_top = 12;
			box.margin_bottom = 12;
			box.margin_start = 12;
			box.margin_end = 12;
			var select_image = new Gtk.Image.from_icon_name ("object-select-symbolic");
			select_image.visible = false;
			select_image.pixel_size = 16;
			box.append (select_image);
			var label = new Gtk.Label (pkgname);
			label.visible = true;
			label.margin_start = 22;
			label.margin_end = 22;
			label.halign = Gtk.Align.START;
			label.ellipsize = Pango.EllipsizeMode.END;
			box.append (label);
			listbox.append (box);
		}

		public GenericArray<string> get_selected_pkgs () {
			var selected = new GenericArray<string> ();
			unowned Gtk.Widget? widget = listbox.get_first_child ();
			while (widget != null) {
				unowned Gtk.ListBoxRow row = widget as Gtk.ListBoxRow;
				unowned Gtk.Widget child = row.get_child ();
				unowned Gtk.Box box = child as Gtk.Box;
				bool select = false;
				unowned Gtk.Widget? widget2 = box.get_first_child ();
				while (widget2 != null) {
					if (widget2.name == "GtkImage") {
						unowned Gtk.Image select_image = widget2 as Gtk.Image;
						select = select_image.visible;
					}
					if (widget2.name == "GtkLabel") {
						unowned Gtk.Label label = widget2 as Gtk.Label;
						if (select) {
							selected.add (label.label);
							select = false;
						}
					}
					widget2 = widget2.get_next_sibling ();
				}
				widget = widget.get_next_sibling ();
			}
			return selected;
		}

		[GtkCallback]
		void on_row_activated (Gtk.ListBoxRow row) {
			unowned Gtk.Widget child = row.get_child ();
			unowned Gtk.Box box = child as Gtk.Box;
			unowned Gtk.Widget? widget = box.get_first_child ();
			while (widget != null) {
				if (widget.name == "GtkImage") {
					unowned Gtk.Image select_image = widget as Gtk.Image;
					if (select_image.visible) {
						select_image.visible = false;
					} else {
						select_image.visible = true;
					}
				}
				if (widget.name == "GtkLabel") {
					unowned Gtk.Label label = widget as Gtk.Label;
					if (label.margin_start == 22) {
						label.margin_start = 0;
					} else {
						label.margin_start = 22;
					}
				}
				widget = widget.get_next_sibling ();
			}
		}

		[GtkCallback]
		void on_search_text_changed () {
			string search_string = search_entry.get_text ().down().strip ();
			if (search_string != "") {
				listbox.set_filter_func ((row) => {
					unowned Gtk.Widget child = row.get_child ();
					unowned Gtk.Box box = child as Gtk.Box;
					unowned Gtk.Widget? widget = box.get_first_child ();
					while (widget != null) {
						if (widget.name == "GtkLabel") {
							unowned Gtk.Label label = widget as Gtk.Label;
							if (label.label.has_prefix (search_string)) {
								return true;
							}
						}
						widget = widget.get_next_sibling ();
					}
					return false;
				});
			} else {
				listbox.set_filter_func (null);
			}
		}
	}
}
