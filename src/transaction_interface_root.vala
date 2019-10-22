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
		bool trans_run_success;

		public TransactionInterfaceRoot (Config config) {
			// alpm_utils global variable declared in alpm_utils.vala
			alpm_utils = new AlpmUtils (config);
			alpm_utils.edit_build_files.connect ((pkgnames) => {
				edit_build_files (pkgnames);
			});
			alpm_utils.emit_action.connect ((action) => {
				emit_action (action);
			});
			alpm_utils.emit_action_progress.connect ((action, status, progress) => {
				emit_action_progress (action, status, progress);
			});
			alpm_utils.emit_hook_progress.connect ((action, details, status, progress) => {
				emit_hook_progress (action, details, status, progress);
			});
			alpm_utils.choose_provider.connect ((depend, providers) => {
				return choose_provider (depend, providers);
			});
			alpm_utils.compute_aur_build_list.connect (() => {
				compute_aur_build_list ();
			});
			alpm_utils.emit_download_progress.connect ((action, status, progress) => {
				emit_download_progress (action, status, progress);
			});
			alpm_utils.start_downloading.connect (() => {
				start_downloading ();
			});
			alpm_utils.stop_downloading.connect (() => {
				stop_downloading ();
			});
			alpm_utils.emit_script_output.connect ((message) => {
				emit_script_output (message);
			});
			alpm_utils.emit_warning.connect ((message) => {
				emit_warning (message);
			});
			alpm_utils.emit_error.connect ((message, details) => {
				emit_error (message, details);
			});
			alpm_utils.important_details_outpout.connect ((must_show) => {
				important_details_outpout (must_show);
			});
			alpm_utils.get_authorization.connect (() => {
				try {
					return get_authorization ();
				} catch (Error e) {
					critical ("get_authorization: %s\n", e.message);
				}
				return false;
			});
			alpm_utils.ask_commit.connect ((summary) => {
				return ask_commit (summary);
			});
			// set user agent
			var utsname = Posix.utsname();
			Environment.set_variable ("HTTP_USER_AGENT", "pamac (%s %s)".printf (utsname.sysname, utsname.machine), true);
		}

		public bool get_lock () {
			var lockfile = GLib.File.new_for_path (alpm_utils.alpm_handle.lockfile);
			if (lockfile.query_exists ()) {
				return false;
			}
			return true;
		}

		public bool get_authorization () {
			// we are root
			return true;
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
			alpm_utils.refresh_handle ();
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

		public void set_trans_flags (int flags) {
			alpm_utils.flags = flags;
		}

		public void set_no_confirm_commit () {
			alpm_utils.no_confirm_commit = true;
		}

		public void add_pkg_to_install (string name) {
			alpm_utils.to_install.add (name);
		}

		public void add_pkg_to_remove (string name) {
			alpm_utils.to_remove.add (name);
		}

		public void add_path_to_load (string path) {
			alpm_utils.to_load.add (path);
		}

		public void add_aur_pkg_to_build (string name) {
			alpm_utils.to_build.add (name);
		}

		public void add_temporary_ignore_pkg (string name) {
			alpm_utils.temporary_ignorepkgs.add (name);
		}

		public void add_overwrite_file (string glob) {
			alpm_utils.overwrite_files.add (glob);
		}

		public void add_pkg_to_mark_as_dep (string name) {
			alpm_utils.to_install_as_dep.insert (name, name);
		}

		public void set_sysupgrade () {
			alpm_utils.sysupgrade = true;
		}

		public void set_keep_built_pkgs (bool keep_built_pkgs) {
			alpm_utils.keep_built_pkgs = keep_built_pkgs;
		}

		public void set_enable_downgrade (bool downgrade) {
			alpm_utils.enable_downgrade = downgrade;
		}
 
		public void set_force_refresh () {
			alpm_utils.force_refresh = true;
		}

		void trans_run_real () {
			var loop = new MainLoop ();
			new Thread<int> ("trans_run_real", () => {
				trans_run_success = alpm_utils.trans_run ();
				loop.quit ();
				return 0;
			});
			loop.run ();
		}

		public bool trans_run () {
			if (alpm_utils.downloading_updates) {
				alpm_utils.cancellable.cancel ();
				// let time to cancel download updates
				var loop = new MainLoop ();
				Timeout.add (1000, () => {
					trans_run_real ();
					loop.quit ();
					return false;
				});
				loop.run ();
			} else {
				trans_run_real ();
			}
			return trans_run_success;
		}

		#if ENABLE_SNAP
		public bool snap_trans_run (string[] to_install, string[] to_remove) {
			// not implemented
			return true;
		}

		public bool snap_switch_channel (string snap_name, string channel) {
			// not implemented
			return true;
		}
		#endif

		public void trans_cancel () {
			alpm_utils.trans_cancel ();
		}

		public void quit_daemon () {
			// nothing to do
		}
	}
}
