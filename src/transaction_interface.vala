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
	internal interface TransactionInterface : Object {
		public abstract bool get_lock () throws Error;
		public abstract bool get_authorization () throws Error;
		public abstract void generate_mirrors_list (string country) throws Error;
		public abstract bool clean_cache (string[] filenames) throws Error;
		public abstract bool clean_build_files (string aur_build_dir) throws Error;
		public abstract bool set_pkgreason (string pkgname, uint reason) throws Error;
		public abstract void download_updates () throws Error;
		public abstract void set_trans_flags (int flags) throws Error;
		public abstract void add_pkg_to_install (string name) throws Error;
		public abstract void add_pkg_to_remove (string name) throws Error;
		public abstract void add_path_to_load (string path) throws Error;
		public abstract void add_aur_pkg_to_build (string name) throws Error;
		public abstract void add_temporary_ignore_pkg (string name) throws Error;
		public abstract void add_overwrite_file (string glob) throws Error;
		public abstract void add_pkg_to_mark_as_dep (string name) throws Error;
		public abstract void set_sysupgrade () throws Error;
		public abstract void set_enable_downgrade (bool downgrade) throws Error;
		public abstract void set_no_confirm_commit () throws Error;
		public abstract void set_force_refresh () throws Error;
		public abstract bool trans_run () throws Error;
		public abstract void trans_cancel () throws Error;
		public abstract void quit_daemon () throws Error;
		public signal int choose_provider (string depend, string[] providers);
		public signal void compute_aur_build_list ();
		public signal bool ask_edit_build_files (TransactionSummaryStruct summary);
		public signal void edit_build_files (string[] pkgnames);
		public signal bool ask_commit (TransactionSummaryStruct summary);
		public signal void emit_unresolvables (string[] unresolvables);
		public signal void emit_action (string action);
		public signal void emit_action_progress (string action, string status, double progress);
		public signal void start_downloading ();
		public signal void stop_downloading ();
		public signal void emit_download_progress (string action, string status, double progress);
		public signal void emit_hook_progress (string action, string details, string status, double progress);
		public signal void emit_script_output (string message);
		public signal void emit_warning (string message);
		public signal void emit_error (string message, string[] details);
		public signal void important_details_outpout (bool must_show);
		public signal void generate_mirrors_list_data (string line);
		#if ENABLE_SNAP
		public abstract bool snap_trans_run (string[] to_install, string[] to_remove) throws Error;
		public abstract bool snap_switch_channel (string snap_name, string channel) throws Error;
		#endif
	}
}
