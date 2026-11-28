/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2026 Guillaume Benoit <guillaume@manjaro.org>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

namespace Pamac {

	[GtkTemplate (ui = "/org/manjaro/pamac/manager/history_dialog.ui")]
	class HistoryDialog : Adw.Window {

		[GtkChild]
		unowned Gtk.TextView textview;
		[GtkChild]
		unowned Gtk.SearchEntry search_entry;

		Gtk.TextIter search_start;

		public HistoryDialog (Gtk.ApplicationWindow window) {
			Object (transient_for: window);

			set_cursor_at_start ();
			populate_history.begin ();
		}

		// pacman.log can be large: read it asynchronously, and build the
		// reversed text from a list instead of prepending each line
		async void populate_history () {
			var file = GLib.File.new_for_path ("/var/log/pacman.log");
			// keep a reference: the dialog can be closed while loading
			Gtk.TextView view = textview;
			try {
				uint8[] contents;
				yield file.load_contents_async (null, out contents, null);
				// load_contents adds a trailing nul byte
				string[] lines = ((string) contents).split ("\n");
				var text = new StringBuilder.sized (contents.length);
				// construct text in reverse order
				for (int i = lines.length - 1; i >= 0; i--) {
					unowned string line = lines[i];
					if ("installed" in line
						|| "removed" in line
						|| "upgraded" in line
						|| "downgraded" in line) {
						text.append (line);
						text.append_c ('\n');
					}
				}
				view.buffer.set_text (text.str, (int) text.len);
			} catch (Error e) {
				warning ("%s: %s", file.get_path (), e.message);
			}
			// setting the text invalidates search_start
			view.buffer.get_start_iter (out search_start);
			view.buffer.place_cursor (search_start);
		}

		[GtkCallback]
		void on_search_entry_search_changed () {
			search_forward ();
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
