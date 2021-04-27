/*
 *  pamac-vala
 *
 *  Copyright (C) 2018-2021 Guillaume Benoit <guillaume@manjaro.org>
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
	internal class TransactionInterfaceRoot: Object, TransactionInterface {
		bool trans_refresh_success;
		bool trans_run_success;
		Cancellable trans_cancellable;
		MainContext context;

		public TransactionInterfaceRoot (MainContext context) {
			this.context = context;
			trans_cancellable = new Cancellable ();
		}

		public async bool get_authorization () {
			// we are root
			return true;
		}

		public void remove_authorization () {
			// we are root
		}

		public async void generate_mirrors_list (string country) {
			try {
				var process = new Subprocess.newv (
					{"pacman-mirrors", "-c", country},
					SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
				var dis = new DataInputStream (process.get_stdout_pipe ());
				string? line;
				while ((line = yield dis.read_line_async ()) != null) {
					generate_mirrors_list_data (line);
				}
			} catch (Error e) {
				warning (e.message);
			}
			alpm_utils.alpm_config.reload ();
		}

		public async bool clean_cache (string[] filenames) {
			return alpm_utils.clean_cache (filenames);
		}

		public async bool clean_build_files (string aur_build_dir) {
			return alpm_utils.clean_build_files (aur_build_dir);
		}

		public async bool set_pkgreason (string pkgname, uint reason) {
			bool success = alpm_utils.set_pkgreason ("root", pkgname, reason);
			return success;
		}

		public async void download_updates () {
			alpm_utils.download_updates ("root");
		}

		public async string download_pkg (string url) {
			// return special value
			// downloads will be done as root by alpm_utils.trans_load_pkg
			return "root";
		}

		async bool wait_for_lock () {
			bool waiting = false;
			bool success = false;
			trans_cancellable.reset ();
			if (alpm_utils.lockfile.query_exists ()) {
				waiting = true;
				start_waiting ();
				emit_action (dgettext (null, "Waiting for another package manager to quit") + "...");
				int i = 0;
				var timeout = new TimeoutSource (200);
				timeout.set_callback (() => {
					if (!alpm_utils.lockfile.query_exists () || trans_cancellable.is_cancelled ()) {
						context.invoke (wait_for_lock.callback);
						success = true;
						return false;
					}
					i++;
					// wait 5 min max
					if (i == 1500) {
						emit_action ("%s: %s.".printf (dgettext (null, "Transaction cancelled"), dgettext (null, "Timeout expired")));
						trans_cancellable.cancel ();
						context.invoke (wait_for_lock.callback);
						return false;
					}
					return true;
				});
				timeout.attach (context);
				yield;
			} else {
				success = true;
			}
			if (waiting) {
				stop_waiting ();
			}
			return success;
		}

		async void trans_refresh_real (bool force) {
			bool success = yield wait_for_lock ();
			if (!success) {
				// cancelled
				trans_refresh_success = false;
				return;
			}
			try {
				new Thread<int>.try ("trans_refresh_real", () => {
					trans_refresh_success = alpm_utils.refresh ("root", force);
					context.invoke (trans_refresh_real.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
				trans_refresh_success = false;
			}
		}

		public async bool trans_refresh (bool force) {
			if (alpm_utils.downloading_updates) {
				alpm_utils.cancellable.cancel ();
				// let time to cancel download updates
				var timeout = new TimeoutSource (1000);
				timeout.set_callback (() => {
					context.invoke (trans_refresh.callback);
					return false;
				});
				timeout.attach (context);
				yield;
			}
			yield trans_refresh_real (force);
			return trans_refresh_success;
		}

		async void trans_run_real (bool sysupgrade,
							bool enable_downgrade,
							bool simple_install,
							bool keep_built_pkgs,
							int trans_flags,
							string[] to_install,
							string[] to_remove,
							string[] to_load,
							string[] to_install_as_dep,
							string[] ignorepkgs,
							string[] overwrite_files) {
			bool success = yield wait_for_lock ();
			if (!success) {
				// cancelled
				trans_run_success = false;
				return;
			}
			try {
				new Thread<int>.try ("trans_run_real", () => {
					trans_run_success = alpm_utils.trans_run ("root",
															sysupgrade,
															enable_downgrade,
															simple_install,
															keep_built_pkgs,
															trans_flags,
															to_install,
															to_remove,
															to_load,
															to_install_as_dep,
															ignorepkgs,
															overwrite_files);
					context.invoke (trans_run_real.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
				trans_run_success = false;
			}
		}

		public async bool trans_run (bool sysupgrade,
								bool enable_downgrade,
								bool simple_install,
								bool keep_built_pkgs,
								int trans_flags,
								string[] to_install,
								string[] to_remove,
								string[] to_load,
								string[] to_install_as_dep,
								string[] ignorepkgs,
								string[] overwrite_files) {
			string[] to_install_copy = to_install;
			string[] to_remove_copy = to_remove;
			string[] to_load_copy = to_load;
			string[] to_install_as_dep_copy = to_install_as_dep;
			string[] ignorepkgs_copy = ignorepkgs;
			string[] overwrite_files_copy = overwrite_files;
			if (alpm_utils.downloading_updates) {
				alpm_utils.cancellable.cancel ();
				// let time to cancel download updates
				var timeout = new TimeoutSource (1000);
				timeout.set_callback (() => {
					context.invoke (trans_run.callback);
					return false;
				});
				timeout.attach (context);
				yield;
			}
			yield trans_run_real (sysupgrade,
								enable_downgrade,
								simple_install,
								keep_built_pkgs,
								trans_flags,
								to_install_copy,
								to_remove_copy,
								to_load_copy,
								to_install_as_dep_copy,
								ignorepkgs_copy,
								overwrite_files_copy);
			return trans_run_success;
		}

		public async bool snap_trans_run (string[] to_install, string[] to_remove) {
			// not implemented
			return false;
		}

		public async bool snap_switch_channel (string snap_name, string channel) {
			// not implemented
			return false;
		}

		public async bool flatpak_trans_run (string[] to_install, string[] to_remove, string[] to_upgrade) {
			// not implemented
			return false;
		}

		public void trans_cancel () {
			trans_cancellable.cancel ();
			alpm_utils.trans_cancel ("root");
		}

		public void quit_daemon () {
			// nothing to do
		}
	}
}
