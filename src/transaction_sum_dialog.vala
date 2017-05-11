/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2017 Guillaume Benoit <guillaume@manjaro.org>
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

	[GtkTemplate (ui = "/org/manjaro/pamac/transaction/transaction_sum_dialog.ui")]
	class TransactionSumDialog : Gtk.Dialog {

		[GtkChild]
		public Gtk.Label top_label;
		[GtkChild]
		Gtk.TreeView treeview;

		public Gtk.ListStore sum_list;

		public TransactionSumDialog (Gtk.ApplicationWindow? window) {
			int use_header_bar;
			Gtk.Settings.get_default ().get ("gtk-dialogs-use-header", out use_header_bar);
			Object (transient_for: window, use_header_bar: use_header_bar);

			sum_list = new Gtk.ListStore (4, typeof (string), typeof (string), typeof (string), typeof (string));
			treeview.set_model (sum_list);
		}
	}
}
