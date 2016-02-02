/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2015 Guillaume Benoit <guillaume@manjaro.org>
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

	[GtkTemplate (ui = "/org/manjaro/pamac/transaction/progress_dialog.ui")]
	public class ProgressDialog : Gtk.Dialog {

		[GtkChild]
		public Gtk.ProgressBar progressbar;
		[GtkChild]
		public Gtk.Label action_label;
		[GtkChild]
		public Gtk.Button cancel_button;
		[GtkChild]
		public Gtk.Button close_button;
		[GtkChild]
		public Gtk.Expander expander;

		public Vte.Terminal term;
		Vte.Pty pty;

		public ProgressDialog (Gtk.ApplicationWindow? window) {
			Object (transient_for: window, use_header_bar: 0);

			//creating terminal
			term = new Vte.Terminal ();
			term.scroll_on_output = false;
			term.expand = true;
			term.height_request = 200;
			term.visible = true;
			// creating pty for term
			try {
				pty = term.pty_new_sync (Vte.PtyFlags.NO_HELPER);
			} catch (Error e) {
				stderr.printf ("Error: %s\n", e.message);
			}
			// add term in a grid with a scrollbar
			var grid = new Gtk.Grid ();
			grid.expand = true;
			grid.visible = true;
			var sb = new Gtk.Scrollbar (Gtk.Orientation.VERTICAL, term.vadjustment);
			sb.visible = true;
			grid.attach (term, 0, 0, 1, 1);
			grid.attach (sb, 1, 0, 1, 1);
			this.expander.add (grid);
		}

		[GtkCallback]
		public void on_close_button_clicked () {
			this.hide ();
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
		}

		public void spawn_in_term (string[] args, out Pid child_pid = null) {
			Pid intern_pid;
			try {
				Process.spawn_async (null, args, null, SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD, pty.child_setup, out intern_pid);
			} catch (SpawnError e) {
				stderr.printf ("SpawnError: %s\n", e.message);
			}
			child_pid = intern_pid;
			term.set_pty (pty);
		}
	}
}
