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
	internal class TransactionInterfaceDaemon: Object, TransactionInterface {
		Daemon system_daemon;
		MainLoop loop;
		bool get_authorization_authorized;
		bool clean_cache_success;
		bool clean_build_files_success;
		bool set_pkgreason_success;
		bool trans_run_success;
		#if ENABLE_SNAP
		bool snap_trans_run_success;
		bool snap_switch_channel_success;
		#endif

		public TransactionInterfaceDaemon (Config config) {
			loop = new MainLoop ();
			try {
				connecting_system_daemon (config);
				connecting_dbus_signals ();
			} catch (Error e) {
				critical ("failed to connect to dbus daemon: %s\n", e.message);
			}
		}

		ErrorInfos get_current_error () throws Error {
			try {
				return system_daemon.get_current_error ();
			} catch (Error e) {
				throw e;
			}
		}

		public bool get_lock () throws Error {
			try {
				return system_daemon.get_lock ();
			} catch (Error e) {
				throw e;
			}
		}

		public bool get_authorization () throws Error {
			try {
				system_daemon.start_get_authorization ();
				loop.run ();
				return get_authorization_authorized;
			} catch (Error e) {
				throw e;
			}
		}

		void on_get_authorization_finished (bool authorized) {
			get_authorization_authorized = authorized;
			loop.quit ();
		}


		public void generate_mirrors_list (string country) throws Error {
			try {
				system_daemon.start_generate_mirrors_list (country);
				loop.run ();
			} catch (Error e) {
				throw e;
			}
		}

		void on_generate_mirrors_list_finished () {
			loop.quit ();
		}

		public bool clean_cache (string[] filenames) throws Error {
			try {
				system_daemon.start_clean_cache (filenames);
				loop.run ();
				return clean_cache_success;
			} catch (Error e) {
				throw e;
			}
		}

		void on_clean_cache_finished (bool success) {
			clean_cache_success = success;
			loop.quit ();
		}

		public bool clean_build_files (string aur_build_dir) throws Error {
			try {
				system_daemon.start_clean_build_files (aur_build_dir);
				loop.run ();
				return clean_build_files_success;
			} catch (Error e) {
				throw e;
			}
		}

		void on_clean_clean_build_files_finished (bool success) {
			clean_build_files_success = success;
			loop.quit ();
		}

		public bool set_pkgreason (string pkgname, uint reason) throws Error {
			try {
				system_daemon.start_set_pkgreason (pkgname, reason);
				loop.run ();
				return set_pkgreason_success;
			} catch (Error e) {
				throw e;
			}
		}

		void on_set_pkgreason_finished (bool success) {
			set_pkgreason_success = success;
			loop.quit ();
		}

		public void download_updates () throws Error {
			try {
				system_daemon.start_download_updates ();
				loop.run ();
			} catch (Error e) {
				throw e;
			}
		}

		void on_download_updates_finished () {
			loop.quit ();
		}

		public void set_trans_flags (int flags) throws Error {
			try {
				system_daemon.set_trans_flags (flags);
			} catch (Error e) {
				throw e;
			}
		}

		public void set_no_confirm_commit () throws Error {
			try {
				system_daemon.set_no_confirm_commit ();
			} catch (Error e) {
				throw e;
			}
		}

		public void add_pkg_to_install (string name) throws Error {
			try {
				system_daemon.add_pkg_to_install (name);
			} catch (Error e) {
				throw e;
			}
		}

		public void add_pkg_to_remove (string name) throws Error {
			try {
				system_daemon.add_pkg_to_remove (name);
			} catch (Error e) {
				throw e;
			}
		}

		public void add_path_to_load (string path) throws Error {
			try {
				system_daemon.add_path_to_load (path);
			} catch (Error e) {
				throw e;
			}
		}

		public void add_aur_pkg_to_build (string name) throws Error {
			try {
				system_daemon.add_aur_pkg_to_build (name);
			} catch (Error e) {
				throw e;
			}
		}

		public void add_temporary_ignore_pkg (string name) throws Error {
			try {
				system_daemon.add_temporary_ignore_pkg (name);
			} catch (Error e) {
				throw e;
			}
		}

		public void add_overwrite_file (string glob) throws Error {
			try {
				system_daemon.add_overwrite_file (glob);
			} catch (Error e) {
				throw e;
			}
		}

		public void add_pkg_to_mark_as_dep (string name) throws Error {
			try {
				system_daemon.add_pkg_to_mark_as_dep (name);
			} catch (Error e) {
				throw e;
			}
		}

		public void set_sysupgrade () throws Error {
			try {
				system_daemon.set_sysupgrade ();
			} catch (Error e) {
				throw e;
			}
		}

		public void set_enable_downgrade (bool downgrade) throws Error {
			try {
				system_daemon.set_enable_downgrade (downgrade);
			} catch (Error e) {
				throw e;
			}
		}

		public void set_force_refresh () throws Error {
			try {
				system_daemon.set_force_refresh ();
			} catch (Error e) {
				throw e;
			}
		}

		public bool trans_run () throws Error {
			try {
				system_daemon.trans_run_finished.connect ((success) => {
					trans_run_success = success;
					loop.quit ();
				});
				system_daemon.start_trans_run ();
				loop.run ();
				return trans_run_success;
			} catch (Error e) {
				throw e;
			}
		}

		public void trans_cancel () throws Error {
			try {
				system_daemon.trans_cancel ();
			} catch (Error e) {
				throw e;
			}
		}

		#if ENABLE_SNAP
		public bool snap_trans_run (string[] to_install, string[] to_remove) throws Error {
			try {
				system_daemon.start_snap_trans_run (to_install, to_remove);
				loop.run ();
				return snap_trans_run_success;
			} catch (Error e) {
				throw e;
			}
		}

		void on_snap_trans_run_finished (bool success) {
			snap_trans_run_success = success;
			loop.quit ();
		}

		public bool snap_switch_channel (string snap_name, string channel) throws Error {
			try {
				system_daemon.start_snap_switch_channel (snap_name, channel);
				loop.run ();
				return snap_switch_channel_success;
			} catch (Error e) {
				throw e;
			}
		}

		void on_snap_switch_channel_finished (bool success) {
			snap_switch_channel_success = success;
			loop.quit ();
		}
		#endif

		public void quit_daemon () throws Error {
			try {
				system_daemon.quit ();
			} catch (Error e) {
				throw e;
			}
		}

		void on_choose_provider (string depend, string[] providers) {
			int index = choose_provider (depend, providers);
			try {
				system_daemon.answer_choose_provider (index);
			} catch (Error e) {
				critical ("answer_choose_provider: %s\n", e.message);
			}
		}

		void on_compute_aur_build_list () {
			compute_aur_build_list ();
			try {
				system_daemon.aur_build_list_computed ();
			} catch (Error e) {
				critical ("build_files_edited: %s\n", e.message);
			}
		}

		void on_ask_edit_build_files (TransactionSummaryStruct summary) {
			bool answer = ask_edit_build_files (summary);
			try {
				system_daemon.answer_ask_edit_build_files (answer);
			} catch (Error e) {
				critical ("answer_ask_edit_build_files: %s\n", e.message);
			}
		}

		void on_edit_build_files (string[] pkgnames) {
			edit_build_files (pkgnames);
			try {
				system_daemon.build_files_edited ();
			} catch (Error e) {
				critical ("build_files_edited: %s\n", e.message);
			}
		}

		void on_ask_commit (TransactionSummaryStruct summary) {
			bool answer = ask_commit (summary);
			try {
				system_daemon.answer_ask_commit (answer);
			} catch (Error e) {
				critical ("answer_ask_commit: %s\n", e.message);
			}
		}

		void connecting_system_daemon (Config config) throws Error {
			if (system_daemon == null) {
				try {
					system_daemon = Bus.get_proxy_sync (BusType.SYSTEM, "org.manjaro.pamac.daemon", "/org/manjaro/pamac/daemon");
					// Set environment variables
					system_daemon.set_environment_variables (config.environment_variables);
				} catch (Error e) {
					throw e;
				}
			}
		}

		void connecting_dbus_signals () {
			system_daemon.choose_provider.connect (on_choose_provider);
			system_daemon.compute_aur_build_list.connect (on_compute_aur_build_list);
			system_daemon.ask_edit_build_files.connect (on_ask_edit_build_files);
			system_daemon.edit_build_files.connect (on_edit_build_files);
			system_daemon.ask_commit.connect (on_ask_commit);
			system_daemon.emit_action.connect ((action) => { emit_action (action); });
			system_daemon.emit_action_progress.connect ((action, status, progress) => { emit_action_progress (action, status, progress); });
			system_daemon.emit_download_progress.connect ((action, status, progress) => { emit_download_progress (action, status, progress); });
			system_daemon.emit_hook_progress.connect ((action, details, status, progress) => { emit_hook_progress (action, details, status, progress); });
			system_daemon.emit_script_output.connect ((message) => { emit_script_output (message); });
			system_daemon.emit_warning.connect ((message) => { emit_warning (message); });
			system_daemon.emit_error.connect ((message,  details) => { emit_error (message,  details); });
			system_daemon.important_details_outpout.connect ((must_show) => { important_details_outpout (must_show); });
			system_daemon.start_downloading.connect (() => { start_downloading (); });
			system_daemon.stop_downloading.connect (() => { stop_downloading (); });
			system_daemon.get_authorization_finished.connect (on_get_authorization_finished);
			system_daemon.clean_cache_finished.connect (on_clean_cache_finished);
			system_daemon.clean_build_files_finished.connect (on_clean_clean_build_files_finished);
			system_daemon.set_pkgreason_finished.connect (on_set_pkgreason_finished);
			system_daemon.download_updates_finished.connect (on_download_updates_finished );
			system_daemon.generate_mirrors_list_data.connect ((line) => { generate_mirrors_list_data (line); });
			system_daemon.generate_mirrors_list_finished.connect (on_generate_mirrors_list_finished);
			#if ENABLE_SNAP
			system_daemon.snap_trans_run_finished.connect (on_snap_trans_run_finished);
			system_daemon.snap_switch_channel_finished.connect (on_snap_switch_channel_finished);
			#endif
		}
	}
}
