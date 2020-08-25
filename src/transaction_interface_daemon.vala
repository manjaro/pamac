/*
 *  pamac-vala
 *
 *  Copyright (C) 2018-2020 Guillaume Benoit <guillaume@manjaro.org>
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
		string sender;
		MainLoop loop;
		bool get_authorization_authorized;
		bool clean_cache_success;
		bool clean_build_files_success;
		bool set_pkgreason_success;
		string download_pkg_path;
		bool trans_refresh_success;
		bool trans_run_success;
		#if ENABLE_SNAP
		bool snap_trans_run_success;
		bool snap_switch_channel_success;
		#endif
		#if ENABLE_FLATPAK
		bool flatpak_trans_run_success;
		#endif

		public TransactionInterfaceDaemon (Config config, MainLoop loop) {
			this.loop = loop;
			try {
				connecting_system_daemon (config);
				connecting_dbus_signals ();
				sender = system_daemon.get_sender ();
			} catch (Error e) {
				warning ("failed to connect to dbus daemon: %s", e.message);
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

		void on_get_authorization_finished (string sender, bool authorized) {
			if (sender == this.sender) {
				get_authorization_authorized = authorized;
				loop.quit ();
			}
		}

		public void remove_authorization () throws Error {
			try {
				system_daemon.remove_authorization ();
			} catch (Error e) {
				throw e;
			}
		}

		public void generate_mirrors_list (string country) throws Error {
			try {
				system_daemon.start_generate_mirrors_list (country);
				loop.run ();
			} catch (Error e) {
				throw e;
			}
		}

		void on_generate_mirrors_list_finished (string sender) {
			if (sender == this.sender) {
				loop.quit ();
			}
		}

		void on_generate_mirrors_list_data (string sender, string line) {
			if (sender == this.sender) {
				generate_mirrors_list_data (line);
			}
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

		void on_clean_cache_finished (string sender, bool success) {
			if (sender == this.sender) {
				clean_cache_success = success;
				loop.quit ();
			}
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

		void on_clean_clean_build_files_finished (string sender, bool success) {
			if (sender == this.sender) {
				clean_build_files_success = success;
				loop.quit ();
			}
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

		void on_set_pkgreason_finished (string sender, bool success) {
			if (sender == this.sender) {
				set_pkgreason_success = success;
				loop.quit ();
			}
		}

		public void download_updates () throws Error {
			try {
				system_daemon.start_download_updates ();
				loop.run ();
			} catch (Error e) {
				throw e;
			}
		}

		void on_download_updates_finished (string sender) {
			if (sender == this.sender) {
				loop.quit ();
			}
		}

		public string download_pkg (string url) throws Error {
			try {
				system_daemon.start_download_pkg (url);
				loop.run ();
				return download_pkg_path;
			} catch (Error e) {
				throw e;
			}
		}

		void on_download_pkg_finished (string sender, string path) {
			if (sender != this.sender) {
				return;
			}
			download_pkg_path = path;
			loop.quit ();
		}

		public bool trans_refresh (bool force) throws Error {
			try {
				system_daemon.start_trans_refresh (force);
				loop.run ();
				return trans_refresh_success;
			} catch (Error e) {
				throw e;
			}
		}

		void on_trans_refresh_finished (string sender, bool success) {
			if (sender != this.sender) {
				return;
			}
			trans_refresh_success = success;
			loop.quit ();
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
								string[] ignorepkgs,
								string[] overwrite_files) throws Error {
			try {
				system_daemon.start_trans_run (sysupgrade,
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
				loop.run ();
				return trans_run_success;
			} catch (Error e) {
				throw e;
			}
		}

		void on_trans_run_finished (string sender, bool success) {
			if (sender != this.sender) {
				return;
			}
			trans_run_success = success;
			loop.quit ();
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

		void on_snap_trans_run_finished (string sender, bool success) {
			if (sender != this.sender) {
				return;
			}
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

		void on_snap_switch_channel_finished (string sender, bool success) {
			if (sender != this.sender) {
				return;
			}
			snap_switch_channel_success = success;
			loop.quit ();
		}
		#endif

		#if ENABLE_FLATPAK
		public bool flatpak_trans_run (string[] to_install, string[] to_remove, string[] to_upgrade) throws Error {
			try {
				system_daemon.start_flatpak_trans_run (to_install, to_remove, to_upgrade);
				loop.run ();
				return flatpak_trans_run_success;
			} catch (Error e) {
				throw e;
			}
		}

		void on_flatpak_trans_run_finished (string sender, bool success) {
			if (sender != this.sender) {
				return;
			}
			flatpak_trans_run_success = success;
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

		void on_emit_action (string sender, string action) {
			if (sender == this.sender) {
				emit_action (action);
			}
		}

		void on_emit_action_progress (string sender, string action, string status, double progress) {
			if (sender == this.sender) {
				emit_action_progress (action, status, progress);
			}
		}

		void on_emit_download_progress (string sender, string action, string status, double progress) {
			if (sender == this.sender) {
				emit_download_progress (action, status, progress);
			}
		}

		void on_emit_hook_progress (string sender, string action, string details, string status, double progress) {
			if (sender == this.sender) {
				emit_hook_progress (action, details, status, progress);
			}
		}

		void on_emit_script_output (string sender, string message) {
			if (sender == this.sender) {
				emit_script_output (message);
			}
		}

		void on_emit_warning (string sender, string message) {
			if (sender == this.sender) {
				emit_warning (message);
			}
		}

		void on_emit_error (string sender, string message, string[] details) {
			if (sender == this.sender) {
				emit_error (message, details);
			}
		}

		void on_important_details_outpout (string sender, bool must_show) {
			if (sender == this.sender) {
				important_details_outpout (must_show);
			}
		}

		void on_start_downloading (string sender) {
			if (sender == this.sender) {
				start_downloading ();
			}
		}

		void on_stop_downloading (string sender) {
			if (sender == this.sender) {
				stop_downloading ();
			}
		}

		void on_start_waiting (string sender) {
			if (sender == this.sender) {
				start_waiting ();
			}
		}

		void on_stop_waiting (string sender) {
			if (sender == this.sender) {
				stop_waiting ();
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
			system_daemon.emit_action.connect (on_emit_action);
			system_daemon.emit_action_progress.connect (on_emit_action_progress);
			system_daemon.emit_download_progress.connect (on_emit_download_progress);
			system_daemon.emit_hook_progress.connect (on_emit_hook_progress);
			system_daemon.emit_script_output.connect (on_emit_script_output);
			system_daemon.emit_warning.connect (on_emit_warning);
			system_daemon.emit_error.connect (on_emit_error);
			system_daemon.important_details_outpout.connect (on_important_details_outpout);
			system_daemon.start_downloading.connect (on_start_downloading);
			system_daemon.stop_downloading.connect (on_stop_downloading);
			system_daemon.start_waiting.connect (on_start_waiting);
			system_daemon.stop_waiting.connect (on_stop_waiting);
			system_daemon.get_authorization_finished.connect (on_get_authorization_finished);
			system_daemon.clean_cache_finished.connect (on_clean_cache_finished);
			system_daemon.clean_build_files_finished.connect (on_clean_clean_build_files_finished);
			system_daemon.set_pkgreason_finished.connect (on_set_pkgreason_finished);
			system_daemon.download_pkg_finished.connect (on_download_pkg_finished);
			system_daemon.trans_refresh_finished.connect (on_trans_refresh_finished);
			system_daemon.trans_run_finished.connect (on_trans_run_finished);
			system_daemon.download_updates_finished.connect (on_download_updates_finished );
			system_daemon.generate_mirrors_list_data.connect (on_generate_mirrors_list_data);
			system_daemon.generate_mirrors_list_finished.connect (on_generate_mirrors_list_finished);
			#if ENABLE_SNAP
			system_daemon.snap_trans_run_finished.connect (on_snap_trans_run_finished);
			system_daemon.snap_switch_channel_finished.connect (on_snap_switch_channel_finished);
			#endif
			#if ENABLE_FLATPAK
			system_daemon.flatpak_trans_run_finished.connect (on_flatpak_trans_run_finished);
			#endif
		}
	}
}
