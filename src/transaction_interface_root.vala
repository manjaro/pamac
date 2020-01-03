/*
 *  pamac-vala
 *
 *  Copyright (C) 2018-2019 Guillaume Benoit <guillaume@manjaro.org>
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

		public TransactionInterfaceRoot (Config config) {
			trans_cancellable = new Cancellable ();
			// alpm_utils global variable declared in alpm_utils.vala
			alpm_utils = new AlpmUtils (config);
			alpm_utils.emit_action.connect ((sender, action) => {
				emit_action (action);
			});
			alpm_utils.emit_action_progress.connect ((sender, action, status, progress) => {
				emit_action_progress (action, status, progress);
			});
			alpm_utils.emit_hook_progress.connect ((sender, action, details, status, progress) => {
				emit_hook_progress (action, details, status, progress);
			});
			alpm_utils.emit_download_progress.connect ((sender, action, status, progress) => {
				emit_download_progress (action, status, progress);
			});
			alpm_utils.start_downloading.connect ((sender) => {
				start_downloading ();
			});
			alpm_utils.stop_downloading.connect ((sender) => {
				stop_downloading ();
			});
			alpm_utils.emit_script_output.connect ((sender, message) => {
				emit_script_output (message);
			});
			alpm_utils.emit_warning.connect ((sender, message) => {
				emit_warning (message);
			});
			alpm_utils.emit_error.connect ((sender, message, details) => {
				emit_error (message, details);
			});
			alpm_utils.important_details_outpout.connect ((sender, must_show) => {
				important_details_outpout (must_show);
			});
			alpm_utils.get_authorization.connect ((sender) => {
				try {
					return get_authorization ();
				} catch (Error e) {
					critical ("get_authorization: %s\n", e.message);
				}
				return false;
			});
			// set user agent
			var utsname = Posix.utsname();
			Environment.set_variable ("HTTP_USER_AGENT", "pamac (%s %s)".printf (utsname.sysname, utsname.machine), true);
		}

		public bool get_authorization () {
			// we are root
			return true;
		}

		public void remove_authorization () {
			// nothing to do
		}

		public void generate_mirrors_list (string country) {
			try {
				var process = new Subprocess.newv (
					{"pacman-mirrors", "-c", country},
					SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
				var dis = new DataInputStream (process.get_stdout_pipe ());
				string? line;
				while ((line = dis.read_line ()) != null) {
					generate_mirrors_list_data (line);
				}
			} catch (Error e) {
				critical ("%s\n", e.message);
			}
			alpm_utils.alpm_config.reload ();
		}

		public bool clean_cache (string[] filenames) {
			return alpm_utils.clean_cache (filenames);
		}

		public bool clean_build_files (string aur_build_dir) {
			return alpm_utils.clean_build_files (aur_build_dir);
		}

		public bool set_pkgreason (string pkgname, uint reason) {
			bool success = alpm_utils.set_pkgreason (pkgname, reason);
			return success;
		}

		public void download_updates () {
			alpm_utils.download_updates ();
		}

		void trans_refresh_real (bool force) {
			var loop = new MainLoop ();
			bool waiting = false;
			trans_cancellable.reset ();
			if (alpm_utils.lockfile.query_exists ()) {
				waiting = true;
				start_waiting ();
				emit_action (dgettext (null, "Waiting for another package manager to quit") + "...");
				int i = 0;
				Timeout.add (200, () => {
					if (!alpm_utils.lockfile.query_exists () || trans_cancellable.is_cancelled ()) {
						loop.quit ();
						return false;
					}
					i++;
					// wait 5 min max
					if (i == 1500) {
						emit_action ("%s: %s.".printf (dgettext (null, "Transaction cancelled"), dgettext (null, "Timeout expired")));
						trans_cancellable.cancel ();
						loop.quit ();
						return false;
					}
					return true;
				});
				loop.run ();
			}
			if (waiting) {
				stop_waiting ();
			}
			if (trans_cancellable.is_cancelled ()) {
				// cancelled
				return;
			}
			new Thread<int> ("trans_rrefresh_real", () => {
				trans_refresh_success = alpm_utils.refresh ("root", force);
				loop.quit ();
				return 0;
			});
			loop.run ();
		}

		public bool trans_refresh (bool force) {
			if (alpm_utils.downloading_updates) {
				alpm_utils.cancellable.cancel ();
				// let time to cancel download updates
				var loop = new MainLoop ();
				Timeout.add (1000, () => {
					trans_refresh_real (force);
					loop.quit ();
					return false;
				});
				loop.run ();
			} else {
				trans_refresh_real (force);
			}
			return trans_refresh_success;
		}

		void trans_run_real (bool sysupgrade,
							bool enable_downgrade,
							bool simple_install,
							bool keep_built_pkgs,
							int trans_flags,
							string[] to_install,
							string[] to_remove,
							string[] to_load,
							string[] to_install_as_dep,
							string[] temporary_ignorepkgs,
							string[] overwrite_files) {
			var loop = new MainLoop ();
			bool waiting = false;
			trans_cancellable.reset ();
			if (alpm_utils.lockfile.query_exists ()) {
				waiting = true;
				start_waiting ();
				emit_action (dgettext (null, "Waiting for another package manager to quit") + "...");
				int i = 0;
				Timeout.add (200, () => {
					if (!alpm_utils.lockfile.query_exists () || trans_cancellable.is_cancelled ()) {
						loop.quit ();
						return false;
					}
					i++;
					// wait 5 min max
					if (i == 1500) {
						emit_action ("%s: %s.".printf (dgettext (null, "Transaction cancelled"), dgettext (null, "Timeout expired")));
						trans_cancellable.cancel ();
						loop.quit ();
						return false;
					}
					return true;
				});
				loop.run ();
			}
			if (waiting) {
				stop_waiting ();
			}
			if (trans_cancellable.is_cancelled ()) {
				// cancelled
				return;
			}
			new Thread<int> ("trans_run_real", () => {
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
														temporary_ignorepkgs,
														overwrite_files);
				loop.quit ();
				return 0;
			});
			loop.run ();
		}

		public bool trans_run (bool sysupgrade,
								bool enable_downgrade,
								bool simple_install,
								bool keep_built_pkgs,
								int trans_flags,
								string[] to_install,
								string[] to_remove,
								string[] to_load,
								string[] to_install_as_dep,
								string[] temporary_ignorepkgs,
								string[] overwrite_files) {
			if (alpm_utils.downloading_updates) {
				alpm_utils.cancellable.cancel ();
				// let time to cancel download updates
				var loop = new MainLoop ();
				Timeout.add (1000, () => {
					trans_run_real (sysupgrade,
									enable_downgrade,
									simple_install,
									keep_built_pkgs,
									trans_flags,
									to_install,
									to_remove,
									to_load,
									to_install_as_dep,
									temporary_ignorepkgs,
									overwrite_files);
					loop.quit ();
					return false;
				});
				loop.run ();
			} else {
				trans_run_real (sysupgrade,
								enable_downgrade,
								simple_install,
								keep_built_pkgs,
								trans_flags,
								to_install,
								to_remove,
								to_load,
								to_install_as_dep,
								temporary_ignorepkgs,
								overwrite_files);
			}
			return trans_run_success;
		}

		#if ENABLE_SNAP
		public bool snap_trans_run (string[] to_install, string[] to_remove) {
			// not implemented
			return false;
		}

		public bool snap_switch_channel (string snap_name, string channel) {
			// not implemented
			return false;
		}
		#endif

		public void trans_cancel () {
			trans_cancellable.cancel ();
			alpm_utils.trans_cancel ("root");
		}

		public void quit_daemon () {
			// nothing to do
		}
	}
}
