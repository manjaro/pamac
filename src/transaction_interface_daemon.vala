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
	[DBus (name = "org.manjaro.pamac.system")]
	interface SystemDaemon : Object {
		public abstract void set_environment_variables (HashTable<string,string> variables) throws Error;
		public abstract ErrorInfos get_current_error () throws Error;
		public abstract bool get_lock () throws Error;
		public abstract bool unlock () throws Error;
		public abstract void start_get_authorization () throws Error;
		public abstract void start_write_pamac_config (HashTable<string,Variant> new_pamac_conf) throws Error;
		public abstract void start_write_alpm_config (HashTable<string,Variant> new_alpm_conf) throws Error;
		public abstract void start_generate_mirrors_list (string country) throws Error;
		public abstract void clean_cache (uint64 keep_nb, bool only_uninstalled) throws Error;
		public abstract void start_set_pkgreason (string pkgname, uint reason) throws Error;
		public abstract void start_refresh (bool force) throws Error;
		public abstract void start_downloading_updates () throws Error;
		public abstract void start_sysupgrade_prepare (bool enable_downgrade, string[] to_build, string[] temporary_ignorepkgs, string[] overwrite_files) throws Error;
		public abstract void start_trans_prepare (int transflags, string[] to_install, string[] to_remove, string[] to_load, string[] to_build, string[] temporary_ignorepkgs, string[] overwrite_files) throws Error;
		public abstract void choose_provider (int provider) throws Error;
		public abstract TransactionSummaryStruct get_transaction_summary () throws Error;
		public abstract void start_trans_commit () throws Error;
		public abstract void trans_release () throws Error;
		public abstract void trans_cancel () throws Error;
		[DBus (no_reply = true)]
		public abstract void quit () throws Error;
		public signal void emit_event (uint primary_event, uint secondary_event, string[] details);
		public signal void emit_providers (string depend, string[] providers);
		public signal void emit_unresolvables (string[] unresolvables);
		public signal void emit_progress (uint progress, string pkgname, uint percent, uint n_targets, uint current_target);
		public signal void emit_download (string filename, uint64 xfered, uint64 total);
		public signal void emit_multi_download (uint64 xfered, uint64 total);
		public signal void emit_totaldownload (uint64 total);
		public signal void emit_log (uint level, string msg);
		public signal void set_pkgreason_finished ();
		public signal void refresh_finished (bool success);
		public signal void database_modified ();
		public signal void downloading_updates_finished ();
		public signal void trans_prepare_finished (bool success);
		public signal void trans_commit_finished (bool success);
		public signal void get_authorization_finished (bool authorized);
		public signal void write_pamac_config_finished (bool recurse, uint64 refresh_period, bool no_update_hide_icon,
														bool enable_aur, string aur_build_dir, bool check_aur_updates,
														bool check_aur_vcs_updates, bool download_updates);
		public signal void write_alpm_config_finished (bool checkspace);
		public signal void generate_mirrors_list_data (string line);
		public signal void generate_mirrors_list_finished ();
	}

	internal class TransactionInterfaceDaemon: Object, TransactionInterface {
		SystemDaemon system_daemon;

		public TransactionInterfaceDaemon (Config config) {
			connecting_system_daemon (config);
			connecting_dbus_signals ();
		}

		ErrorInfos get_current_error () {
			try {
				return system_daemon.get_current_error ();
			} catch (Error e) {
				stderr.printf ("get_current_error: %s\n", e.message);
				return ErrorInfos ();
			}
		}

		public bool get_lock () {
			bool locked = false;
			try {
				locked = system_daemon.get_lock ();
			} catch (Error e) {
				stderr.printf ("get_lock: %s\n", e.message);
			}
			return locked;
		}

		public bool unlock () {
			bool unlocked = false;
			try {
				unlocked = system_daemon.unlock ();
			} catch (Error e) {
				stderr.printf ("unlock: %s\n", e.message);
			}
			return unlocked;
		}

		public void start_get_authorization () {
			try {
				system_daemon.start_get_authorization ();
				system_daemon.get_authorization_finished.connect (on_get_authorization_finished);
			} catch (Error e) {
				stderr.printf ("start_get_authorization: %s\n", e.message);
			}
		}

		void on_get_authorization_finished (bool authorized) {
			system_daemon.get_authorization_finished.disconnect (on_get_authorization_finished);
			get_authorization_finished (authorized);
		}

		public void start_write_pamac_config (HashTable<string,Variant> new_pamac_conf) {
			try {
				system_daemon.start_write_pamac_config (new_pamac_conf);
				system_daemon.write_pamac_config_finished.connect (on_write_pamac_config_finished);
			} catch (Error e) {
				stderr.printf ("start_write_pamac_config: %s\n", e.message);
			}
		}

		void on_write_pamac_config_finished (bool recurse, uint64 refresh_period, bool no_update_hide_icon,
											bool enable_aur, string aur_build_dir, bool check_aur_updates,
											bool check_aur_vcs_updates, bool download_updates) {
			system_daemon.write_pamac_config_finished.disconnect (on_write_pamac_config_finished);
			write_pamac_config_finished (recurse, refresh_period, no_update_hide_icon,
										enable_aur, aur_build_dir, check_aur_updates,
										check_aur_vcs_updates, download_updates);
		}

		public void start_write_alpm_config (HashTable<string,Variant> new_alpm_conf) {
			try {
				system_daemon.start_write_alpm_config (new_alpm_conf);
				system_daemon.write_alpm_config_finished.connect (on_write_alpm_config_finished);
			} catch (Error e) {
				stderr.printf ("start_write_alpm_config: %s\n", e.message);
			}
		}

		void on_write_alpm_config_finished (bool checkspace) {
			system_daemon.write_alpm_config_finished.disconnect (on_write_alpm_config_finished);
			write_alpm_config_finished (checkspace);
		}

		public void start_generate_mirrors_list (string country) {
			try {
				system_daemon.start_generate_mirrors_list (country);
				system_daemon.generate_mirrors_list_data.connect (on_generate_mirrors_list_data);
				system_daemon.generate_mirrors_list_finished.connect (on_generate_mirrors_list_finished);
			} catch (Error e) {
				stderr.printf ("start_generate_mirrors_list: %s\n", e.message);
			}
		}

		void on_generate_mirrors_list_data (string line) {
			generate_mirrors_list_data (line);
		}

		void on_generate_mirrors_list_finished () {
			system_daemon.generate_mirrors_list_data.disconnect (on_generate_mirrors_list_data);
			system_daemon.generate_mirrors_list_finished.disconnect (on_generate_mirrors_list_finished);
			generate_mirrors_list_finished ();
		}

		public void clean_cache (uint64 keep_nb, bool only_uninstalled) {
			try {
				system_daemon.clean_cache (keep_nb, only_uninstalled);
			} catch (Error e) {
				stderr.printf ("clean_cache: %s\n", e.message);
			}
		}

		public void start_set_pkgreason (string pkgname, uint reason) {
			try {
				system_daemon.start_set_pkgreason (pkgname, reason);
				system_daemon.set_pkgreason_finished.connect (on_set_pkgreason_finished);
			} catch (Error e) {
				stderr.printf ("start_set_pkgreason: %s\n", e.message);
			}
		}

		void on_set_pkgreason_finished () {
			system_daemon.set_pkgreason_finished.disconnect (on_set_pkgreason_finished);
			set_pkgreason_finished ();
		}

		public void start_refresh (bool force) {
			try {
				system_daemon.start_refresh (force);
				system_daemon.refresh_finished.connect (on_refresh_finished);
			} catch (Error e) {
				stderr.printf ("start_refresh: %s\n", e.message);
			}
		}

		void on_refresh_finished (bool success) {
			system_daemon.refresh_finished.disconnect (on_refresh_finished);
			refresh_finished (success);
		}

		public void start_downloading_updates () {
			try {
				system_daemon.start_downloading_updates ();
				system_daemon.downloading_updates_finished.connect (on_downloading_updates_finished);
			} catch (Error e) {
				stderr.printf ("start_downloading_updates: %s\n", e.message);
			}
		}

		void on_downloading_updates_finished () {
			system_daemon.downloading_updates_finished.disconnect (on_downloading_updates_finished);
			downloading_updates_finished ();
		}

		void start_sysupgrade_prepare (bool enable_downgrade,
										string[] to_build,
										string[] temporary_ignorepkgs,
										string[] overwrite_files) {
			try {
				// this will respond with trans_prepare_finished signal
				system_daemon.start_sysupgrade_prepare (enable_downgrade, to_build, temporary_ignorepkgs, overwrite_files);
			} catch (Error e) {
				stderr.printf ("start_sysupgrade_prepare: %s\n", e.message);
			}
		}


		void start_trans_prepare (int flags,
								string[] to_install,
								string[] to_remove,
								string[] to_load,
								string[] to_build,
								string[] temporary_ignorepkgs,
								string[] overwrite_files) {
			try {
				system_daemon.start_trans_prepare (flags, to_install, to_remove, to_load, to_build, temporary_ignorepkgs, overwrite_files);
			} catch (Error e) {
				stderr.printf ("start_trans_prepare: %s\n", e.message);
			}
		}

		void on_trans_prepare_finished (bool success) {
			trans_prepare_finished (success);
		}

		public void start_trans_commit () {
			try {
				system_daemon.start_trans_commit ();
			} catch (Error e) {
				stderr.printf ("start_trans_commit: %s\n", e.message);
			}
		}

		void on_trans_commit_finished (bool success) {
			trans_commit_finished (success);
		}

		public void trans_cancel () {
			try {
				system_daemon.trans_cancel ();
			} catch (Error e) {
				stderr.printf ("trans_cancel: %s\n", e.message);
			}
		}

		public void trans_release () {
			try {
				system_daemon.trans_release ();
			} catch (Error e) {
				stderr.printf ("trans_release: %s\n", e.message);
			}
		}

		public void quit_daemon () {
			try {
				system_daemon.quit ();
			} catch (Error e) {
				stderr.printf ("quit: %s\n", e.message);
			}
		}

		void on_emit_event (uint primary_event, uint secondary_event, string[] details) {
			emit_event (primary_event, secondary_event, details);
		}

		void on_emit_providers (string depend, string[] providers) {
			emit_providers (depend, providers);
		}

		public void choose_provider (int index) {
			try {
				system_daemon.choose_provider (index);
			} catch (Error e) {
				stderr.printf ("choose_provider: %s\n", e.message);
			}
		}

		void on_emit_unresolvables (string[] unresolvables) {
			emit_unresolvables (unresolvables);
		}

		void on_emit_progress (uint progress, string pkgname, uint percent, uint n_targets, uint current_target) {
			emit_progress (progress, pkgname, percent, n_targets, current_target);
		}

		void on_emit_download (string filename, uint64 xfered, uint64 total) {
			emit_download (filename, xfered, total);
		}

		void on_emit_multi_download (uint64 xfered, uint64 total) {
			emit_multi_download (xfered, total);
		}

		void on_emit_totaldownload (uint64 total) {
			emit_totaldownload (total);
		}

		void on_emit_log (uint level, string msg) {
			emit_log (level, msg);
		}

		void on_database_modified () {
			database_modified ();
		}

		public TransactionSummaryStruct get_transaction_summary () {
			var summary_struct = TransactionSummaryStruct ();
			try {
				summary_struct = system_daemon.get_transaction_summary ();
			} catch (Error e) {
				stderr.printf ("get_transaction_summary: %s\n", e.message);
			}
			return summary_struct;
		}

		void connecting_system_daemon (Config config) {
			if (system_daemon == null) {
				try {
					system_daemon = Bus.get_proxy_sync (BusType.SYSTEM, "org.manjaro.pamac.system", "/org/manjaro/pamac/system");
					// Set environment variables
					system_daemon.set_environment_variables (config.environment_variables);
				} catch (Error e) {
					stderr.printf ("set_environment_variables: %s\n", e.message);
				}
			}
		}

		void connecting_dbus_signals () {
			system_daemon.emit_event.connect (on_emit_event);
			system_daemon.emit_providers.connect (on_emit_providers);
			system_daemon.emit_unresolvables.connect (on_emit_unresolvables);
			system_daemon.emit_progress.connect (on_emit_progress);
			system_daemon.emit_download.connect (on_emit_download);
			system_daemon.emit_multi_download.connect (on_emit_multi_download);
			system_daemon.emit_totaldownload.connect (on_emit_totaldownload);
			system_daemon.emit_log.connect (on_emit_log);
			system_daemon.database_modified.connect (on_database_modified);
			system_daemon.trans_prepare_finished.connect (on_trans_prepare_finished);
			system_daemon.trans_commit_finished.connect (on_trans_commit_finished);
		}
	}
}
