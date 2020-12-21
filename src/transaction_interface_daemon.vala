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
		SourceFunc generate_mirrors_list_callback;
		SourceFunc download_updates_callback;
		SourceFunc get_authorization_callback;
		bool get_authorization_authorized;
		SourceFunc clean_cache_callback;
		bool clean_cache_success;
		SourceFunc clean_build_files_callback;
		bool clean_build_files_success;
		SourceFunc set_pkgreason_callback;
		bool set_pkgreason_success;
		SourceFunc download_pkg_callback;
		string download_pkg_path;
		SourceFunc trans_refresh_callback;
		bool trans_refresh_success;
		SourceFunc trans_run_callback;
		bool trans_run_success;
		SourceFunc snap_trans_run_callback;
		bool snap_trans_run_success;
		SourceFunc snap_switch_channel_callback;
		bool snap_switch_channel_success;
		SourceFunc flatpak_trans_run_callback;
		bool flatpak_trans_run_success;

		public TransactionInterfaceDaemon (Config config) {
			try {
				connecting_system_daemon (config);
				connecting_dbus_signals ();
				sender = system_daemon.get_sender ();
			} catch (Error e) {
				warning ("failed to connect to dbus daemon: %s", e.message);
			}
		}

		public async bool get_authorization () throws Error {
			get_authorization_callback = get_authorization.callback;
			try {
				system_daemon.start_get_authorization ();
				yield;
				return get_authorization_authorized;
			} catch (Error e) {
				throw e;
			}
		}

		void on_get_authorization_finished (string sender, bool authorized) {
			if (sender == this.sender) {
				get_authorization_authorized = authorized;
				get_authorization_callback ();
			}
		}

		public void remove_authorization () throws Error {
			try {
				system_daemon.remove_authorization ();
			} catch (Error e) {
				throw e;
			}
		}

		public async void generate_mirrors_list (string country) throws Error {
			generate_mirrors_list_callback = generate_mirrors_list.callback;
			try {
				system_daemon.start_generate_mirrors_list (country);
				yield;
			} catch (Error e) {
				throw e;
			}
		}

		void on_generate_mirrors_list_finished (string sender) {
			if (sender == this.sender) {
				generate_mirrors_list_callback ();
			}
		}

		void on_generate_mirrors_list_data (string sender, string line) {
			if (sender == this.sender) {
				generate_mirrors_list_data (line);
			}
		}

		public async bool clean_cache (string[] filenames) throws Error {
			clean_cache_callback = clean_cache.callback;
			try {
				system_daemon.start_clean_cache (filenames);
				yield;
				return clean_cache_success;
			} catch (Error e) {
				throw e;
			}
		}

		void on_clean_cache_finished (string sender, bool success) {
			if (sender == this.sender) {
				clean_cache_success = success;
				clean_cache_callback ();
			}
		}

		public async bool clean_build_files (string aur_build_dir) throws Error {
			clean_build_files_callback = clean_build_files.callback;
			try {
				system_daemon.start_clean_build_files (aur_build_dir);
				yield;
				return clean_build_files_success;
			} catch (Error e) {
				throw e;
			}
		}

		void on_clean_clean_build_files_finished (string sender, bool success) {
			if (sender == this.sender) {
				clean_build_files_success = success;
				clean_build_files_callback ();
			}
		}

		public async bool set_pkgreason (string pkgname, uint reason) throws Error {
			set_pkgreason_callback = set_pkgreason.callback;
			try {
				system_daemon.start_set_pkgreason (pkgname, reason);
				yield;
				return set_pkgreason_success;
			} catch (Error e) {
				throw e;
			}
		}

		void on_set_pkgreason_finished (string sender, bool success) {
			if (sender == this.sender) {
				set_pkgreason_success = success;
				clean_build_files_callback ();
			}
		}

		public async void download_updates () throws Error {
			download_updates_callback = download_updates.callback;
			try {
				system_daemon.start_download_updates ();
				yield;
			} catch (Error e) {
				throw e;
			}
		}

		void on_download_updates_finished (string sender) {
			if (sender == this.sender) {
				download_updates_callback ();
			}
		}

		public async string download_pkg (string url) throws Error {
			download_pkg_callback = download_pkg.callback;
			try {
				system_daemon.start_download_pkg (url);
				yield;
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
			download_pkg_callback ();
		}

		public async bool trans_refresh (bool force) throws Error {
			trans_refresh_callback = trans_refresh.callback;
			try {
				system_daemon.start_trans_refresh (force);
				yield;
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
			trans_refresh_callback ();
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
								string[] overwrite_files) throws Error {
			trans_run_callback = trans_run.callback;
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
				yield;
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
			trans_run_callback ();
		}

		public void trans_cancel () throws Error {
			try {
				system_daemon.trans_cancel ();
			} catch (Error e) {
				throw e;
			}
		}

		public async bool snap_trans_run (string[] to_install, string[] to_remove) throws Error {
			snap_trans_run_callback = snap_trans_run.callback;
			try {
				system_daemon.start_snap_trans_run (to_install, to_remove);
				yield;
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
			snap_trans_run_callback ();
		}

		public async bool snap_switch_channel (string snap_name, string channel) throws Error {
			snap_switch_channel_callback = snap_switch_channel.callback;
			try {
				system_daemon.start_snap_switch_channel (snap_name, channel);
				yield;
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
			snap_switch_channel_callback ();
		}

		public async bool flatpak_trans_run (string[] to_install, string[] to_remove, string[] to_upgrade) throws Error {
			flatpak_trans_run_callback = flatpak_trans_run.callback;
			try {
				system_daemon.start_flatpak_trans_run (to_install, to_remove, to_upgrade);
				yield;
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
			flatpak_trans_run_callback ();
		}

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
			system_daemon.snap_trans_run_finished.connect (on_snap_trans_run_finished);
			system_daemon.snap_switch_channel_finished.connect (on_snap_switch_channel_finished);
			system_daemon.flatpak_trans_run_finished.connect (on_flatpak_trans_run_finished);
		}
	}
}
