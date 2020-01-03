/*
 *  pamac-vala
 *
 *  Copyright (C) 2019-2020 Guillaume Benoit <guillaume@manjaro.org>
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
	[DBus (name = "org.manjaro.pamac.daemon")]
	interface Daemon : Object {
		public abstract string get_sender () throws Error;
		public abstract void set_environment_variables (HashTable<string,string> variables) throws Error;
		public abstract void start_get_authorization () throws Error;
		public abstract void remove_authorization () throws Error;
		public abstract void start_write_alpm_config (HashTable<string,Variant> new_alpm_conf) throws Error;
		public abstract void start_write_pamac_config (HashTable<string,Variant> new_pamac_conf) throws Error;
		public abstract void start_generate_mirrors_list (string country) throws Error;
		public abstract void start_clean_cache (string[] filenames) throws Error;
		public abstract void start_clean_build_files (string aur_build_dir) throws Error;
		public abstract void start_set_pkgreason (string pkgname, uint reason) throws Error;
		public abstract void start_download_updates () throws Error;
		public abstract void start_trans_refresh (bool force) throws Error;
		public abstract void start_trans_run (bool sysupgrade,
											bool enable_downgrade,
											bool simple_install,
											bool keep_built_pkgs,
											int trans_flags,
											string[] to_install,
											string[] to_remove,
											string[] to_load,
											string[] to_install_as_dep,
											string[] temporary_ignorepkgs,
											string[] overwrite_files) throws Error;
		public abstract void trans_cancel () throws Error;
		[DBus (no_reply = true)]
		public abstract void quit () throws Error;
		public signal void emit_action (string sender, string action);
		public signal void emit_action_progress (string sender, string action, string status, double progress);
		public signal void emit_download_progress (string sender, string action, string status, double progress);
		public signal void emit_hook_progress (string sender, string action, string details, string status, double progress);
		public signal void emit_script_output (string sender, string message);
		public signal void emit_warning (string sender, string message);
		public signal void emit_error (string sender, string message, string[] details);
		public signal void important_details_outpout (string sender, bool must_show);
		public signal void start_downloading (string sender);
		public signal void stop_downloading (string sender);
		public signal void set_pkgreason_finished (string sender, bool success);
		public signal void start_waiting (string sender);
		public signal void stop_waiting (string sender);
		public signal void trans_refresh_finished (string sender, bool success);
		public signal void trans_run_finished (string sender, bool success);
		public signal void download_updates_finished (string sender);
		public signal void get_authorization_finished (string sender, bool authorized);
		public signal void write_alpm_config_finished (string sender);
		public signal void write_pamac_config_finished (string sender);
		public signal void generate_mirrors_list_data (string sender, string line);
		public signal void generate_mirrors_list_finished (string sender);
		public signal void clean_cache_finished (string sender, bool success);
		public signal void clean_build_files_finished (string sender, bool success);
		#if ENABLE_SNAP
		public abstract void start_snap_trans_run (string[] to_install, string[] to_remove) throws Error;
		public abstract void start_snap_switch_channel (string snap_name, string channel) throws Error;
		public signal void snap_trans_run_finished (string sender, bool success);
		public signal void snap_switch_channel_finished (string sender, bool success);
		#endif
	}
}
