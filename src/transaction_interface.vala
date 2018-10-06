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
	internal interface TransactionInterface : Object {
		public abstract ErrorInfos get_current_error ();
		public abstract bool get_lock ();
		public abstract bool unlock ();
		public abstract void start_get_authorization ();
		public abstract void start_write_pamac_config (HashTable<string,Variant> new_pamac_conf);
		public abstract void start_write_alpm_config (HashTable<string,Variant> new_alpm_conf);
		public abstract void start_generate_mirrors_list (string country);
		public abstract void clean_cache (uint64 keep_nb, bool only_uninstalled);
		public abstract void start_set_pkgreason (string pkgname, uint reason);
		public abstract void start_refresh (bool force);
		public abstract void start_downloading_updates ();
		public abstract void start_sysupgrade_prepare (bool enable_downgrade, string[] temporary_ignorepkgs, string[] to_build, string[] overwrite_files);
		public abstract void start_trans_prepare (int transflags, string[] to_install, string[] to_remove, string[] to_load, string[] to_build, string[] overwrite_files);
		public abstract void choose_provider (int provider);
		public abstract TransactionSummaryStruct get_transaction_summary ();
		public abstract void start_trans_commit ();
		public abstract void trans_release ();
		public abstract void trans_cancel ();
		public abstract void quit_daemon ();
		public signal void emit_event (uint primary_event, uint secondary_event, string[] details);
		public signal void emit_providers (string depend, string[] providers);
		public signal void emit_progress (uint progress, string pkgname, uint percent, uint n_targets, uint current_target);
		public signal void emit_download (string filename, uint64 xfered, uint64 total);
		public signal void emit_totaldownload (uint64 total);
		public signal void emit_log (uint level, string msg);
		public signal void set_pkgreason_finished ();
		public signal void database_modified ();
		public signal void refresh_finished (bool success);
		public signal void downloading_updates_finished ();
		public signal void trans_prepare_finished (bool success);
		public signal void trans_commit_finished (bool success);
		public signal void get_authorization_finished (bool authorized);
		public signal void write_pamac_config_finished (bool recurse, uint64 refresh_period, bool no_update_hide_icon,
														bool enable_aur, string aur_build_dir, bool check_aur_updates,
														bool download_updates);
		public signal void write_alpm_config_finished (bool checkspace);
		public signal void generate_mirrors_list_data (string line);
		public signal void generate_mirrors_list_finished ();
	}
}
