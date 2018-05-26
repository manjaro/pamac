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
		Transaction transaction;
		ProgressDialog progress_dialog;
		bool pamac_run;
		bool important_details;

		public Installer () {
			application_id = "org.manjaro.pamac.installer";
			flags |= ApplicationFlags.HANDLES_OPEN;
		}

		public override void startup () {
			// i18n
			Intl.textdomain ("pamac");
			Intl.setlocale (LocaleCategory.ALL, "");

			base.startup ();

			pamac_run = check_pamac_running ();
			if (pamac_run) {
				var msg = new Gtk.MessageDialog (null,
												Gtk.DialogFlags.MODAL,
												Gtk.MessageType.ERROR,
												Gtk.ButtonsType.OK,
												dgettext (null, "Pamac is already running"));
				msg.run ();
				msg.destroy ();
			} else {
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
				this.hold ();
			}
		}

		public override void activate () {
			if (!pamac_run) {
				print ("\nError: Path(s) of tarball(s) to install is needed\n");
				transaction.stop_daemon ();
				this.release ();
			}
		}

		public override void open (File[] files, string hint) {
			if (!pamac_run) {
				foreach (unowned File file in files) {
					transaction.to_load.add (file.get_path ());
				}
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
		}

		bool check_pamac_running () {
			Application app;
			bool run = false;
			app = new Application ("org.manjaro.pamac.manager", 0);
			try {
				app.register ();
			} catch (GLib.Error e) {
				stderr.printf ("%s\n", e.message);
			}
			run = app.get_is_remote ();
			return run;
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
		}

		public static int main (string[] args) {
			var installer = new Installer();
			return installer.run (args);
		}
	}
}
