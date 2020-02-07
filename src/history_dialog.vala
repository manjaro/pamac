/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2020 Guillaume Benoit <guillaume@manjaro.org>
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

	[GtkTemplate (ui = "/org/manjaro/pamac/manager/history_dialog.ui")]
	class HistoryDialog : Gtk.Dialog {

		[GtkChild]
		Gtk.TextView textview;
		[GtkChild]
		Gtk.SearchEntry search_entry;

		Gtk.TextIter search_start;

		public HistoryDialog (Gtk.ApplicationWindow window) {
			int use_header_bar;
			Gtk.Settings.get_default ().get ("gtk-dialogs-use-header", out use_header_bar);
			Object (transient_for: window, use_header_bar: use_header_bar);

			// populate history
			var file = GLib.File.new_for_path ("/var/log/pacman.log");
			if (!file.query_exists ()) {
				GLib.stderr.printf ("File '%s' doesn't exist.\n", file.get_path ());
			} else {
				try {
					StringBuilder text = new StringBuilder ();
					// Open file for reading and wrap returned FileInputStream into a
					// DataInputStream, so we can read line by line
					var dis = new DataInputStream (file.read ());
					string line;
					// Read lines until end of file (null) is reached
					while ((line = dis.read_line ()) != null) {
						// construct text in reverse order
						if ("installed" in line
							|| "removed" in line
							|| "upgraded" in line
							|| "downgraded" in line) {
							text.prepend (line + "\n");
						}
					}
					textview.buffer.set_text (text.str, -1);
				} catch (Error e) {
					warning (e.message);
				}
			}
			set_cursor_at_start ();
		}

		[GtkCallback]
		void on_search_entry_search_changed () {
			search_forward ();
		}

		[GtkCallback]
		void on_search_entry_icon_press (Gtk.EntryIconPosition pos, Gdk.Event event) {
			if (pos == Gtk.EntryIconPosition.SECONDARY) {
				search_entry.set_text ("");
			}
		}

		[GtkCallback]
		void on_search_entry_next_match () {
			on_go_down_button_clicked ();
		}

		[GtkCallback]
		void on_search_entry_previous_match () {
			on_go_up_button_clicked ();
		}

		[GtkCallback]
		void on_go_up_button_clicked () {
			textview.buffer.get_selection_bounds (out search_start, null);
			search_backward ();
		}

		[GtkCallback]
		void on_go_down_button_clicked () {
			textview.buffer.get_selection_bounds (null, out search_start);
			search_forward ();
		}

		void search_forward () {
			string search_string = search_entry.get_text ().strip ();
			if (search_string != "") {
				Gtk.TextIter match_start;
				Gtk.TextIter match_end;
				Gtk.TextSearchFlags flags = Gtk.TextSearchFlags.CASE_INSENSITIVE | Gtk.TextSearchFlags.TEXT_ONLY;
				if (search_start.forward_search (search_string, flags, out match_start, out match_end, null)) {
					textview.buffer.select_range (match_start, match_end);
					scroll_to_cursor ();
				} else {
					set_cursor_at_start ();
					if (search_start.forward_search (search_string, flags, out match_start, out match_end, null)) {
						textview.buffer.select_range (match_start, match_end);
						scroll_to_cursor ();
					}
				}
			} else {
				textview.buffer.get_iter_at_mark (out search_start, textview.buffer.get_insert ());
				textview.buffer.place_cursor (search_start);
			}
		}

		void search_backward () {
			string search_string = search_entry.get_text ().strip ();
			if (search_string != "") {
				Gtk.TextIter match_start;
				Gtk.TextIter match_end;
				Gtk.TextSearchFlags flags = Gtk.TextSearchFlags.CASE_INSENSITIVE | Gtk.TextSearchFlags.TEXT_ONLY;
				if (search_start.backward_search (search_string, flags, out match_start, out match_end, null)) {
					textview.buffer.select_range (match_start, match_end);
					scroll_to_cursor ();
				} else {
					set_cursor_at_end ();
					if (search_start.backward_search (search_string, flags, out match_start, out match_end, null)) {
						textview.buffer.select_range (match_start, match_end);
						scroll_to_cursor ();
					}
				}
			} else {
				textview.buffer.get_iter_at_mark (out search_start, textview.buffer.get_insert ());
				textview.buffer.place_cursor (search_start);
			}
		}

		void set_cursor_at_start () {
			textview.buffer.get_start_iter (out search_start);
			textview.buffer.place_cursor (search_start);
		}

		void set_cursor_at_end () {
			textview.buffer.get_end_iter (out search_start);
			textview.buffer.place_cursor (search_start);
		}

		void scroll_to_cursor () {
			textview.scroll_to_mark (textview.buffer.get_insert (), 0.1, false, 0, 0);
		}
	}
}
