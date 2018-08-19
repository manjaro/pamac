/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2018 Guillaume Benoit <guillaume@manjaro.org>
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

	public class Installer: Gtk.Application {
		ApplicationCommandLine cmd;
		Transaction transaction;
		ProgressDialog progress_dialog;
		bool important_details;

		public Installer () {
			application_id = "org.manjaro.pamac.installer";
			flags |= ApplicationFlags.HANDLES_COMMAND_LINE;
		}

		public override void startup () {
			// i18n
			Intl.textdomain ("pamac");
			Intl.setlocale (LocaleCategory.ALL, "");

			base.startup ();

			important_details = false;
			// integrate progress box and term widget
			progress_dialog = new ProgressDialog ();
			transaction = new Transaction (progress_dialog as Gtk.ApplicationWindow);
			transaction.mode = Transaction.Mode.INSTALLER;
			transaction.finished.connect (on_transaction_finished);
			transaction.important_details_outpout.connect (on_important_details_outpout);
			progress_dialog.box.pack_start (transaction.progress_box);
			progress_dialog.box.reorder_child (transaction.progress_box, 0);
			transaction.term_window.height_request = 200;
			progress_dialog.expander.add (transaction.term_window);
			progress_dialog.close_button.clicked.connect (on_close_button_clicked);
			progress_dialog.close_button.visible = false;
		}

		public override int command_line (ApplicationCommandLine cmd) {
			this.cmd = cmd;
			string[] args = cmd.get_arguments ();
			foreach (unowned string target in args[1:args.length]) {
				// check for local or remote path
				if (".pkg.tar" in target) {
					if ("://" in target) {
						if ("file://" in target) {
							// handle file:// uri
							var file = File.new_for_uri (target);
							string? absolute_path = file.get_path ();
							if (absolute_path != null) {
								transaction.to_load.add (absolute_path);
							}
						} else {
							// add url in to_load, pkg will be downloaded by system_daemon
							transaction.to_load.add (target);
						}
					} else {
						// handle local or absolute path
						var file = File.new_for_path (target);
						string? absolute_path = file.get_path ();
						if (absolute_path != null) {
							transaction.to_load.add (absolute_path);
						}
					}
				} else {
					transaction.to_install.add (target);
				}
			}
			if (transaction.to_install.length == 0 && transaction.to_load.length == 0) {
				stdout.printf (dgettext (null, "Nothing to do") + ".\n");
			} else {
				this.hold ();
				progress_dialog.show ();
				if (transaction.get_lock ()) {
					transaction.run ();
				} else {
					transaction.progress_box.action_label.label = dgettext (null, "Waiting for another package manager to quit") + "...";
					transaction.start_progressbar_pulse ();
					Timeout.add (5000, () => {
						bool locked = transaction.get_lock ();
						if (locked) {
							transaction.stop_progressbar_pulse ();
							transaction.run ();
						}
						return !locked;
					});
				}
			}
			return cmd.get_exit_status ();
		}

		void on_important_details_outpout (bool must_show) {
			important_details = true;
			progress_dialog.expander.expanded = true;
		}

		void on_close_button_clicked () {
			this.release ();
		}

		void on_transaction_finished (bool success) {
			transaction.stop_daemon ();
			if (!success || important_details) {
				progress_dialog.close_button.visible = true;
			} else {
				this.release ();
			}
			if (!success) {
				cmd.set_exit_status (1);
			}
		}

		public static int main (string[] args) {
			var installer = new Installer();
			return installer.run (args);
		}
	}
}
