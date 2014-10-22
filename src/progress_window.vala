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

	[GtkTemplate (ui = "/org/manjaro/pamac/transaction/progress_window.ui")]
	public class ProgressWindow : Gtk.Window {

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

		Transaction transaction;

		public ProgressWindow (Transaction transaction, Gtk.ApplicationWindow? window) {
			Object (transient_for: window);

			this.transaction = transaction;
		}

		[GtkCallback]
		public void on_close_button_clicked () {
			this.hide ();
			while (Gtk.events_pending ())
				Gtk.main_iteration ();
		}

		[GtkCallback]
		public void on_cancel_button_clicked () {
			transaction.cancel ();
			transaction.clear_lists ();
			transaction.finished (false);
			this.hide ();
			while (Gtk.events_pending ())
				Gtk.main_iteration ();
		}
	}
}
