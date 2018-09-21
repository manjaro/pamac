/*
 *  pamac-vala
 *
 *  Copyright (C) 2018 Guillaume Benoit <guillaume@manjaro.org>
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

		public TransactionInterfaceRoot () {
			// alpm_utils global variable declared in alpm_utils.vala
			// and initiate in database.vala
			alpm_utils.emit_event.connect ((primary_event, secondary_event, details) => {
				emit_event (primary_event, secondary_event, details);
			});
			alpm_utils.emit_providers.connect ((depend, providers) => {
				emit_providers (depend, providers);
			});
			alpm_utils.emit_progress.connect ((progress, pkgname, percent, n_targets, current_target) => {
				emit_progress (progress, pkgname, percent, n_targets, current_target);
			});
			alpm_utils.emit_download.connect ((filename, xfered, total) => {
				emit_download (filename, xfered, total);
			});
			alpm_utils.emit_totaldownload.connect ((total) => {
				emit_totaldownload (total);
			});
			alpm_utils.emit_log.connect ((level, msg) => {
				emit_log (level, msg);
			});
			alpm_utils.refresh_finished.connect ((success) => {
				refresh_finished (success);
			});
			alpm_utils.get_updates_finished.connect ((updates) => {
				get_updates_finished (updates);
			});
			alpm_utils.downloading_updates_finished.connect (() => {
				downloading_updates_finished ();
			});
			alpm_utils.trans_prepare_finished.connect ((success) => {
				trans_prepare_finished (success);
			});
			alpm_utils.trans_commit_finished.connect ((success) => {
				trans_commit_finished (success);
			});
			// set user agent
			var utsname = Posix.utsname();
			Environment.set_variable ("HTTP_USER_AGENT", "pamac (%s %s)".printf (utsname.sysname, utsname.machine), true);
		}

		public ErrorInfos get_current_error () {
			return alpm_utils.current_error;
		}

		public bool get_lock () {
			// we are root
			return true;
		}

		public bool unlock () {
			// we are root
			return true;
		}

		async void get_authorization () {
			// we are root
			get_authorization_finished (true);
		}

		public void start_get_authorization () {
			get_authorization.begin ();
		}

		async void write_pamac_config (HashTable<string,Variant> new_pamac_conf) {
			var pamac_config = new Config ("/etc/pamac.conf");
			pamac_config.write (new_pamac_conf);
			pamac_config.reload ();
			write_pamac_config_finished (pamac_config.recurse, pamac_config.refresh_period, pamac_config.no_update_hide_icon,
										pamac_config.enable_aur, pamac_config.aur_build_dir, pamac_config.check_aur_updates,
										pamac_config.download_updates);
		}

		public void start_write_pamac_config (HashTable<string,Variant> new_pamac_conf) {
			write_pamac_config.begin (new_pamac_conf);
		}

		async void write_alpm_config (HashTable<string,Variant> new_alpm_conf) {
			alpm_utils.alpm_config.write (new_alpm_conf);
			alpm_utils.alpm_config.reload ();
			alpm_utils.refresh_handle ();
			write_alpm_config_finished ((alpm_utils.alpm_handle.checkspace == 1));
		}

		public void start_write_alpm_config (HashTable<string,Variant> new_alpm_conf) {
			write_alpm_config.begin (new_alpm_conf);
		}

		async void generate_mirrors_list (string country) {
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
				stderr.printf ("Error: %s\n", e.message);
			}
			alpm_utils.alpm_config.reload ();
			alpm_utils.refresh_handle ();
			generate_mirrors_list_finished ();
		}

		public void start_generate_mirrors_list (string country) {
			generate_mirrors_list.begin (country);
		}

		public void clean_cache (uint64 keep_nb, bool only_uninstalled) {
			string[] commands = {"paccache", "--nocolor", "-rq"};
			commands += "-k%llu".printf (keep_nb);
			if (only_uninstalled) {
				commands += "-u";
			}
			try {
				new Subprocess.newv (
					commands,
					SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
			} catch (Error e) {
				stderr.printf ("Error: %s\n", e.message);
			}
		}

		async void set_pkgreason (string pkgname, uint reason) {
			alpm_utils.set_pkgreason (pkgname, reason);
			set_pkgreason_finished ();
		}

		public void start_set_pkgreason (string pkgname, uint reason) {
			set_pkgreason.begin (pkgname, reason);
		}

		int refresh () {
			alpm_utils.refresh ();
			return 0;
		}

		public void start_refresh (bool force) {
			alpm_utils.force_refresh = force;
			if (alpm_utils.downloading_updates) {
				alpm_utils.cancellable.cancel ();
				// let time to cancel download updates
				Timeout.add (1000, () => {
					new Thread<int> ("refresh", refresh);
					return false;
				});
			} else {
				new Thread<int> ("refresh", refresh);
			}
		}

		int get_updates_for_sysupgrade () {
			alpm_utils.get_updates_for_sysupgrade ();
			return 0;
		}

		public void start_get_updates_for_sysupgrade (bool check_aur_updates) {
			alpm_utils.check_aur_updates = check_aur_updates;
			new Thread<int> ("get_updates_for_sysupgrade", get_updates_for_sysupgrade);
		}

		int download_updates () {
			alpm_utils.download_updates ();
			return 0;
		}

		public void start_downloading_updates () {
			new Thread<int> ("download_updates", download_updates);
		}

		public void start_sysupgrade_prepare (bool enable_downgrade,
											string[] temporary_ignorepkgs,
											string[] to_build,
											string[] overwrite_files) {
			alpm_utils.enable_downgrade = enable_downgrade;
			alpm_utils.temporary_ignorepkgs = temporary_ignorepkgs;
			alpm_utils.overwrite_files = overwrite_files;
			alpm_utils.sysupgrade = true;
			alpm_utils.flags = 0;
			alpm_utils.to_install = {};
			alpm_utils.to_remove = {};
			alpm_utils.to_load = {};
			alpm_utils.to_build = to_build;
			if (alpm_utils.downloading_updates) {
				alpm_utils.cancellable.cancel ();
				// let time to cancel download updates
				Timeout.add (1000, () => {
					launch_prepare ();
					return false;
				});
			} else {
				launch_prepare ();
			}
		}

		public void start_trans_prepare (int flags,
										string[] to_install,
										string[] to_remove,
										string[] to_load,
										string[] to_build,
										string[] overwrite_files) {
			alpm_utils.flags = flags;
			alpm_utils.to_install = to_install;
			alpm_utils.to_remove = to_remove;
			alpm_utils.to_load = to_load;
			alpm_utils.to_build = to_build;
			alpm_utils.overwrite_files = overwrite_files;
			if (alpm_utils.to_install.length > 0) {
				alpm_utils.sysupgrade = true;
			}
			if (alpm_utils.downloading_updates) {
				alpm_utils.cancellable.cancel ();
				// let time to cancel download updates
				Timeout.add (1000, () => {
					launch_prepare ();
					return false;
				});
			} else {
				launch_prepare ();
			}
		}

		int trans_prepare () {
			alpm_utils.trans_prepare ();
			return 0;
		}

		int build_prepare () {
			alpm_utils.build_prepare ();
			return 0;
		}

		private void launch_prepare () {
			if (alpm_utils.to_build.length != 0) {
				alpm_utils.compute_aur_build_list (alpm_utils.to_build);
				new Thread<int> ("build_prepare", build_prepare);
			} else {
				new Thread<int> ("trans_prepare", trans_prepare);
			}
		}

		public void choose_provider (int provider) {
			alpm_utils.choose_provider (provider);
		}

		public TransactionSummaryStruct get_transaction_summary () {
			return alpm_utils.get_transaction_summary ();
		}

		int trans_commit () {
			alpm_utils.trans_commit ();
			return 0;
		}

		public void start_trans_commit () {
			new Thread<int> ("trans_commit", trans_commit);
		}

		public void trans_release () {
			alpm_utils.trans_release ();
		}

		public void trans_cancel () {
			alpm_utils.trans_cancel ();
		}

		public void quit_daemon () {
			// nothing to do
		}
	}
}
