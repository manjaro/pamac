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

	public class Installer: Gtk.Application {
		ApplicationCommandLine cmd;
		Database database;
		TransactionGtk transaction;
		ProgressDialog progress_dialog;
		bool important_details;
		bool waiting;
		bool cancelled;

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
			waiting = false;
			cancelled = false;
			var config = new Config ("/etc/pamac.conf");
			// do not remove orphans
			config.recurse = false;
			database = new Database (config);
			// integrate progress box and term widget
			progress_dialog = new ProgressDialog (this);
			// set translated title
			var appinfo = new DesktopAppInfo ("pamac-installer.desktop");
			progress_dialog.title = appinfo.get_name ();
			transaction = new TransactionGtk (database, progress_dialog as Gtk.ApplicationWindow);
			transaction.start_waiting.connect (on_start_waiting);
			transaction.stop_waiting.connect (on_stop_waiting);
			transaction.start_preparing.connect (on_start_preparing);
			transaction.stop_preparing.connect (on_stop_preparing);
			transaction.start_downloading.connect (on_start_downloading);
			transaction.stop_downloading.connect (on_stop_downloading);
			transaction.important_details_outpout.connect (on_important_details_outpout);
			progress_dialog.box.pack_start (transaction.progress_box);
			progress_dialog.box.reorder_child (transaction.progress_box, 0);
			transaction.details_window.height_request = 200;
			progress_dialog.expander.add (transaction.details_window);
			progress_dialog.close_button.clicked.connect (on_close_button_clicked);
			progress_dialog.cancel_button.clicked.connect (on_cancel_button_clicked);
		}

		public override int command_line (ApplicationCommandLine cmd) {
			this.cmd = cmd;
			string[] args = cmd.get_arguments ();
			string[] to_install = {};
			string[] to_remove = {};
			string[] to_load = {};
			string[] to_build = {};
			if (args.length == 1) {
				display_help ();
				this.release ();
				return cmd.get_exit_status ();
			}
			if (args[1] == "--help" || args[1] == "-h") {
				display_help ();
				this.release ();
				return cmd.get_exit_status ();
			} else {
				bool add_to_remove = false;
				bool add_to_build = false;
				int i = 1;
				while (i < args.length) {
					unowned string target = args[i];
					if (target == "--remove") {
						add_to_remove = true;
						add_to_build = false;
					} else if (target == "--build") {
						add_to_build = true;
						add_to_remove = false;
					} else {
						if (add_to_remove) {
							to_remove += target;
						} else if (add_to_build) {
							to_build += target;
						} else if (".pkg.tar" in target) {
							// check for local or remote path
							if ("://" in target) {
								if ("file://" in target) {
									// handle file:// uri
									var file = File.new_for_uri (target);
									string? absolute_path = file.get_path ();
									if (absolute_path != null) {
										to_load += absolute_path;
									}
								} else {
									// add url in to_load, pkg will be downloaded by system_daemon
									to_load += target;
								}
							} else {
								// handle local or absolute path
								var file = File.new_for_path (target);
								string? absolute_path = file.get_path ();
								if (absolute_path != null) {
									to_load += absolute_path;
								}
							}
						} else {
							to_install += target;
						}
					}
					i++;
				}
			}
			if (to_install.length == 0 
				&& to_load.length == 0
				&& to_build.length == 0
				&& to_remove.length == 0) {
				stdout.printf (dgettext (null, "Nothing to do") + ".\n");
			} else {
				if (to_build.length > 0) {
					// check if targets exist
					bool success = check_build_pkgs (to_build);
					if (success) {
						foreach (unowned string name in to_build) {
							transaction.add_aur_pkg_to_build (name);
						}
					} else {
						this.release ();
						return 1;
					}
				}
				foreach (unowned string name in to_install) {
					transaction.add_pkg_to_install (name);
				}
				foreach (unowned string name in to_remove) {
					transaction.add_pkg_to_remove (name);
				}
				foreach (unowned string path in to_load) {
					transaction.add_path_to_load (path);
				}
				progress_dialog.cancel_button.sensitive = false;
				progress_dialog.close_button.visible = false;
				progress_dialog.show ();
				transaction.run_async.begin ((obj, res) => {
					bool success = transaction.run_async.end (res);
					if ((!success && transaction.commit_transaction_answer && !cancelled) || important_details) {
						progress_dialog.expander.expanded = true;
						progress_dialog.close_button.visible = true;
					} else {
						this.release ();
					}
					if (!success) {
						cmd.set_exit_status (1);
					}
				});
			}
			return cmd.get_exit_status ();
		}

		bool check_build_pkgs (string[] targets) {
			var aur_pkgs = database.get_aur_pkgs (targets);
			var iter = HashTableIter<string, unowned AURPackage?> (aur_pkgs);
			unowned string pkgname;
			unowned AURPackage? aur_pkg;
			while (iter.next (out pkgname, out aur_pkg)) {
				if (aur_pkg == null) {
					transaction.display_error (dgettext (null, "Failed to prepare transaction"), {dgettext (null, "target not found: %s").printf (pkgname)});
					return false;
				}
			}
			return true;
		}

		void display_help () {
			stdout.printf (dgettext (null, "Install packages from repositories, path or url"));
			stdout.printf ("\n");
			stdout.printf (dgettext (null, "Remove packages"));
			stdout.printf ("\n");
			stdout.printf (dgettext (null, "Build packages from AUR and install them with their dependencies"));
			stdout.printf ("\n\n");
			stdout.printf ("pamac-installer [%s] [--remove] [%s] [--build] [%s]".printf (dgettext (null, "package(s)"), dgettext (null, "package(s)"), dgettext (null, "package(s)")));
			stdout.printf ("\n");
		}

		void on_important_details_outpout (bool must_show) {
			important_details = true;
		}

		void on_close_button_clicked () {
			this.release ();
		}

		void on_cancel_button_clicked () {
			cancelled = true;
			transaction.cancel ();
			if (waiting) {
				waiting = false;
				transaction.stop_progressbar_pulse ();
			}
		}

		void on_start_waiting () {
			waiting = true;
			progress_dialog.cancel_button.sensitive = true;
		}

		void on_stop_waiting () {
			waiting = false;
			progress_dialog.cancel_button.sensitive = false;
		}

		void on_start_preparing () {
			progress_dialog.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			progress_dialog.cancel_button.sensitive = false;
		}

		void on_stop_preparing () {
			progress_dialog.cancel_button.sensitive = false;
			progress_dialog.get_window ().set_cursor (null);
		}

		void on_start_downloading () {
			progress_dialog.cancel_button.sensitive = true;
		}

		void on_stop_downloading () {
			progress_dialog.cancel_button.sensitive = false;
		}

		public override void shutdown () {
			base.shutdown ();
			if (!check_pamac_running ()) {
				// stop system_daemon
				transaction.quit_daemon ();
			}
		}

		bool check_pamac_running () {
			GLib.Application app;
			bool run = false;
			app = new GLib.Application ("org.manjaro.pamac.manager", 0);
			try {
				app.register ();
			} catch (Error e) {
				warning (e.message);
			}
			run = app.get_is_remote ();
			return run;
		}

		public static int main (string[] args) {
			var installer = new Installer();
			return installer.run (args);
		}
	}
}
