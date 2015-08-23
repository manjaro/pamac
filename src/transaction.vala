/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2015 Guillaume Benoit <guillaume@manjaro.org>
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
	[DBus (name = "org.manjaro.pamac")]
	public interface Daemon : Object {
		public abstract void start_get_authorization () throws IOError;
		public abstract void start_write_pamac_config (HashTable<string,Variant> new_pamac_conf) throws IOError;
		public abstract void start_write_alpm_config (HashTable<string,Variant> new_alpm_conf) throws IOError;
		public abstract void start_write_mirrors_config (HashTable<string,Variant> new_mirrors_conf) throws IOError;
		public abstract void start_generate_mirrors_list () throws IOError;
		public abstract void start_set_pkgreason (string pkgname, uint reason) throws IOError;
		public abstract void start_refresh (int force) throws IOError;
		public abstract bool get_checkspace () throws IOError;
		public abstract string[] get_ignorepkgs () throws IOError;
		public abstract void add_ignorepkg (string pkgname) throws IOError;
		public abstract void remove_ignorepkg (string pkgname) throws IOError;
		public abstract bool should_hold (string pkgname) throws IOError;
		public abstract async Pamac.Package[] get_all_pkgs () throws IOError;
		public abstract async Pamac.Package[] get_installed_pkgs () throws IOError;
		public abstract async Pamac.Package[] get_local_pkgs () throws IOError;
		public abstract async Pamac.Package[] get_orphans () throws IOError;
		public abstract Pamac.Package find_local_pkg (string pkgname) throws IOError;
		public abstract Pamac.Package find_local_satisfier (string pkgname) throws IOError;
		public abstract Pamac.Package find_sync_pkg (string pkgname) throws IOError;
		public abstract async Pamac.Package[] search_pkgs (string search_string, bool search_from_aur) throws IOError;
		public abstract string[] get_repos_names () throws IOError;
		public abstract async Pamac.Package[] get_repo_pkgs (string repo) throws IOError;
		public abstract string[] get_groups_names () throws IOError;
		public abstract async Pamac.Package[] get_group_pkgs (string group_name) throws IOError;
		public abstract string[] get_pkg_files (string pkgname) throws IOError;
		public abstract string[] get_pkg_uninstalled_optdeps (string pkgname) throws IOError;
		public abstract PackageDeps get_pkg_deps (string pkgname) throws IOError;
		public abstract PackageDetails get_pkg_details (string pkgname) throws IOError;
		public abstract async Updates get_updates (bool check_aur_updates) throws IOError;
		public abstract ErrorInfos trans_init (Alpm.TransFlag transflags) throws IOError;
		public abstract ErrorInfos trans_sysupgrade (int enable_downgrade) throws IOError;
		public abstract ErrorInfos trans_add_pkg (string pkgname) throws IOError;
		public abstract ErrorInfos trans_remove_pkg (string pkgname) throws IOError;
		public abstract ErrorInfos trans_load_pkg (string pkgpath) throws IOError;
		public abstract void start_trans_prepare () throws IOError;
		public abstract void choose_provider (int provider) throws IOError;
		public abstract UpdateInfos[] trans_to_add () throws IOError;
		public abstract UpdateInfos[] trans_to_remove () throws IOError;
		public abstract void start_trans_commit () throws IOError;
		public abstract int trans_release () throws IOError;
		public abstract void trans_cancel () throws IOError;
		[DBus (no_reply = true)]
		public abstract void quit () throws IOError;
		public signal void emit_event (uint primary_event, uint secondary_event, string[] details);
		public signal void emit_providers (string depend, string[] providers);
		public signal void emit_progress (uint progress, string pkgname, int percent, uint n_targets, uint current_target);
		public signal void emit_download (string filename, uint64 xfered, uint64 total);
		public signal void emit_totaldownload (uint64 total);
		public signal void emit_log (uint level, string msg);
		public signal void set_pkgreason_finished ();
		public signal void refresh_finished (ErrorInfos error);
		public signal void trans_prepare_finished (ErrorInfos error);
		public signal void trans_commit_finished (ErrorInfos error);
		public signal void get_authorization_finished (bool authorized);
		public signal void write_pamac_config_finished (int refresh_period, bool aur_enabled, bool recurse,
														bool no_update_hide_icon, bool check_aur_updates,
														bool no_confirm_build);
		public signal void write_alpm_config_finished (bool checkspace);
		public signal void write_mirrors_config_finished (string choosen_country, string choosen_generation_method);
		public signal void generate_mirrors_list_data (string line);
		public signal void generate_mirrors_list_finished ();
	}

	public enum TransactionType {
		STANDARD = (1 << 0),
		UPDATE = (1 << 1),
		BUILD = (1 << 2)
	}

	public class Transaction: Object {
		public Daemon daemon;

		public Alpm.TransFlag flags;
		// those hashtables will be used as set
		public GenericSet<string?> to_add;
		public GenericSet<string?> to_remove;
		public GenericSet<string?> to_load;
		public GenericSet<string?> to_build;
		public GenericSet<string?> special_ignorepkgs;

		public Mode mode;

		uint64 total_download;
		uint64 already_downloaded;
		string previous_label;
		string previous_textbar;
		double previous_percent;
		string previous_filename;
		uint pulse_timeout_id;
		bool sysupgrade_after_trans;
		int build_status;
		int enable_downgrade;

		//dialogs
		TransactionSumDialog transaction_sum_dialog;
		TransactionInfoDialog transaction_info_dialog;
		ProgressDialog progress_dialog;
		//parent window
		Gtk.ApplicationWindow? window;

		public signal void finished (bool with_error);
		public signal void enable_aur (bool enable);

		public Transaction (Gtk.ApplicationWindow? window) {
			flags = Alpm.TransFlag.CASCADE;
			to_add = new GenericSet<string?> (str_hash, str_equal);
			to_remove = new GenericSet<string?> (str_hash, str_equal);
			to_load = new GenericSet<string?> (str_hash, str_equal);
			to_build = new GenericSet<string?> (str_hash, str_equal);
			special_ignorepkgs = new GenericSet<string?> (str_hash, str_equal);
			connecting_dbus_signals ();
			//creating dialogs
			this.window = window;
			transaction_sum_dialog = new TransactionSumDialog (window);
			transaction_info_dialog = new TransactionInfoDialog (window);
			progress_dialog = new ProgressDialog (this, window);
			// connect to child_exited signal which will only be emit after a call to watch_child
			progress_dialog.term.child_exited.connect (on_term_child_exited);
			// progress data
			total_download = 0;
			already_downloaded = 0;
			previous_label = "";
			previous_textbar = "";
			previous_percent = 0.0;
			previous_filename = "";
			sysupgrade_after_trans = false;
			build_status = 0;
		}

		public void start_get_authorization () {
			try {
				daemon.start_get_authorization ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void start_write_pamac_config (HashTable<string,Variant> new_pamac_conf) {
			try {
				daemon.start_write_pamac_config (new_pamac_conf);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void start_write_alpm_config (HashTable<string,Variant> new_alpm_conf) {
			try {
				daemon.start_write_alpm_config (new_alpm_conf);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void start_write_mirrors_config (HashTable<string,Variant> new_mirrors_conf) {
			try {
				daemon.start_write_mirrors_config (new_mirrors_conf);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void start_generate_mirrors_list () {
			string action = dgettext (null, "Refreshing mirrors list") + "...";
			progress_dialog.spawn_in_term ({"echo", action});
			progress_dialog.action_label.set_text (action);
			progress_dialog.progressbar.set_fraction (0);
			progress_dialog.progressbar.set_text ("");
			progress_dialog.cancel_button.set_visible (false);
			progress_dialog.close_button.set_visible (false);
			progress_dialog.expander.set_expanded (true);
			progress_dialog.width_request = 700;
			pulse_timeout_id = Timeout.add (500, (GLib.SourceFunc) progress_dialog.progressbar.pulse);
			progress_dialog.show ();
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
			try {
				daemon.start_generate_mirrors_list ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void start_set_pkgreason (string pkgname, Alpm.Package.Reason reason) {
			try {
				daemon.start_set_pkgreason (pkgname, (uint) reason);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void start_refresh (int force) {
			string action = dgettext (null, "Synchronizing package databases") + "...";
			progress_dialog.spawn_in_term ({"echo", action});
			progress_dialog.action_label.set_text (action);
			progress_dialog.progressbar.set_fraction (0);
			progress_dialog.progressbar.set_text ("");
			progress_dialog.cancel_button.set_visible (true);
			progress_dialog.close_button.set_visible (false);
			progress_dialog.show ();
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
			try {
				daemon.refresh_finished.connect (on_refresh_finished);
				daemon.start_refresh (force);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				daemon.refresh_finished.disconnect (on_refresh_finished);
			}
		}

		public bool get_checkspace () {
			bool checkspace = false;
			try {
				checkspace = daemon.get_checkspace ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return checkspace;
		}

		public string[] get_ignorepkgs () {
			string[] ignorepkgs = {};
			try {
				ignorepkgs = daemon.get_ignorepkgs ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return ignorepkgs;
		}

		public void add_ignorepkg (string pkgname) {
			try {
				daemon.add_ignorepkg (pkgname);
				special_ignorepkgs.add (pkgname);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void remove_ignorepkg (string pkgname) {
			try {
				daemon.remove_ignorepkg (pkgname);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public bool should_hold (string pkgname) {
			bool should_hold = false;
			try {
				should_hold = daemon.should_hold (pkgname);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return should_hold;
		}

		public async Pamac.Package[] get_all_pkgs () {
			Pamac.Package[] pkgs = {};
			try {
				pkgs = yield daemon.get_all_pkgs ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return pkgs;
		}

		public async Pamac.Package[] get_installed_pkgs () {
			Pamac.Package[] pkgs = {};
			try {
				pkgs = yield daemon.get_installed_pkgs ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return pkgs;
		}

		public async Pamac.Package[] get_local_pkgs () {
			Pamac.Package[] pkgs = {};
			try {
				pkgs = yield daemon.get_local_pkgs ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return pkgs;
		}

		public async Pamac.Package[] get_orphans () {
			Pamac.Package[] pkgs = {};
			try {
				pkgs = yield daemon.get_orphans ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return pkgs;
		}

		public Pamac.Package find_local_pkg (string pkgname) {
			var pkg = Pamac.Package (null, null);
			try {
				pkg = daemon.find_local_pkg (pkgname);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return pkg;
		}

		public Pamac.Package find_local_satisfier (string pkgname) {
			var pkg = Pamac.Package (null, null);
			try {
				pkg = daemon.find_local_satisfier (pkgname);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return pkg;
		}

		public Pamac.Package find_sync_pkg (string pkgname) {
			var pkg = Pamac.Package (null, null);
			try {
				pkg = daemon.find_sync_pkg (pkgname);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return pkg;
		}

		public async Pamac.Package[] search_pkgs (string search_string, bool search_aur) {
			Pamac.Package[] pkgs = {};
			try {
				pkgs = yield daemon.search_pkgs (search_string, search_aur);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return pkgs;
		}

		public string[] get_repos_names () {
			string[] repos_names = {};
			try {
				repos_names = daemon.get_repos_names ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return repos_names;
		}

		public async Pamac.Package[] get_repo_pkgs (string repo) {
			Pamac.Package[] pkgs = {};
			try {
				pkgs = yield daemon.get_repo_pkgs (repo);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return pkgs;
		}

		public string[] get_groups_names () {
			string[] groups_names = {};
			try {
				groups_names = daemon.get_groups_names ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return groups_names;
		}

		public async Pamac.Package[] get_group_pkgs (string group_name) {
			Pamac.Package[] pkgs = {};
			try {
				pkgs = yield daemon.get_group_pkgs (group_name);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return pkgs;
		}

		public string[] get_pkg_files (string pkgname) {
			string[] files = {};
			try {
				files = daemon.get_pkg_files (pkgname);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return files;
		}

		public string[] get_pkg_uninstalled_optdeps (string pkgname) {
			string[] optdeps = {};
			try {
				optdeps = daemon.get_pkg_uninstalled_optdeps (pkgname);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return optdeps;
		}

		public PackageDeps get_pkg_deps (string pkgname) {
			var deps = PackageDeps ();
			try {
				deps = daemon.get_pkg_deps (pkgname);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return deps;
		}

		public PackageDetails get_pkg_details (string pkgname) {
			var details = PackageDetails ();
			try {
				details = daemon.get_pkg_details (pkgname);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return details;
		}

		public async Updates get_updates () {
			var updates = Updates ();
			var pamac_config = new Pamac.Config ("/etc/pamac.conf");
			try {
				updates = yield daemon.get_updates (pamac_config.enable_aur && pamac_config.check_aur_updates);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return updates;
		}

		public ErrorInfos init () {
			var err = ErrorInfos ();
			foreach (string pkgname in special_ignorepkgs) {
				add_ignorepkg (pkgname);
			}
			try {
				err = daemon.trans_init (0);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return err;
		}

		public void sysupgrade_simple (int enable_downgrade) {
			progress_dialog.progressbar.set_fraction (0);
			progress_dialog.cancel_button.set_visible (true);
			var err = init ();
			if (err.message != "") {
				finished (true);
				handle_error (err);
			} else {
				try {
					err = daemon.trans_sysupgrade (enable_downgrade);
				} catch (IOError e) {
					stderr.printf ("IOError: %s\n", e.message);
				}
				if (err.message == "") {
					progress_dialog.show ();
					while (Gtk.events_pending ()) {
						Gtk.main_iteration ();
					}
					try {
						daemon.start_trans_prepare ();
					} catch (IOError e) {
						stderr.printf ("IOError: %s\n", e.message);
					}
				} else {
					release ();
					finished (true);
					handle_error (err);
				}
			}
		}

		public void sysupgrade (int enable_downgrade) {
			this.enable_downgrade = enable_downgrade;
			string action = dgettext (null, "Starting full system upgrade") + "...";
			progress_dialog.spawn_in_term ({"echo", action});
			progress_dialog.action_label.set_text (action);
			progress_dialog.progressbar.set_fraction (0);
			progress_dialog.progressbar.set_text ("");
			progress_dialog.cancel_button.set_visible (true);
			progress_dialog.close_button.set_visible (false);
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
			// sysupgrade
			get_updates.begin ((obj, res) => {
				Updates updates = get_updates.end (res);
				// get syncfirst updates
				if (updates.is_syncfirst) {
					clear_lists ();
					if (mode == Mode.MANAGER) {
						sysupgrade_after_trans = true;
					}
					foreach (UpdateInfos infos in updates.repos_updates) {
						to_add.add (infos.name);
					}
					// run as a standard transaction
					run ();
				} else {
					if (updates.aur_updates.length != 0) {
						clear_lists ();
						foreach (UpdateInfos infos in updates.aur_updates) {
							if ((infos.name in special_ignorepkgs) == false) {
								to_build.add (infos.name);
							}
						}
					}
					if (updates.repos_updates.length != 0) {
						sysupgrade_simple (enable_downgrade);
					} else {
						progress_dialog.show ();
						while (Gtk.events_pending ()) {
							Gtk.main_iteration ();
						}
						var err = ErrorInfos ();
						on_trans_prepare_finished (err);
					}
				}
			});
		}

		public void clear_lists () {
			to_add.remove_all ();
			to_remove.remove_all ();
			to_build.remove_all ();
		}

		public void run () {
			string action = dgettext (null,"Preparing") + "...";
			progress_dialog.spawn_in_term ({"echo", action});
			progress_dialog.action_label.set_text (action);
			progress_dialog.progressbar.set_fraction (0);
			progress_dialog.progressbar.set_text ("");
			progress_dialog.cancel_button.set_visible (true);
			progress_dialog.close_button.set_visible (false);
			progress_dialog.show ();
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
			// run
			var err = ErrorInfos ();
			if (to_add.length == 0
					&& to_remove.length == 0
					&& to_load.length == 0
					&& to_build.length != 0) {
				// there only AUR packages to build so no need to prepare transaction
				on_trans_prepare_finished (err);
			} else {
				try {
					err = daemon.trans_init (flags);
				} catch (IOError e) {
					stderr.printf ("IOError: %s\n", e.message);
				}
				if (err.message != "") {
					finished (true);
					handle_error (err);
				} else {
					foreach (string name in to_add) {
						try {
							err = daemon.trans_add_pkg (name);
						} catch (IOError e) {
							stderr.printf ("IOError: %s\n", e.message);
						}
						if (err.message != "") {
							break;
						}
					}
					foreach (string name in to_remove) {
						try {
							err = daemon.trans_remove_pkg (name);
						} catch (IOError e) {
							stderr.printf ("IOError: %s\n", e.message);
						}
						if (err.message != "") {
							break;
						}
					}
					foreach (string path in to_load) {
						try {
							err = daemon.trans_load_pkg (path);
						} catch (IOError e) {
							stderr.printf ("IOError: %s\n", e.message);
						}
						if (err.message != "") {
							break;
						}
					}
					if (err.message == "") {
						try {
							daemon.start_trans_prepare ();
						} catch (IOError e) {
							stderr.printf ("IOError: %s\n", e.message);
						}
					} else {
						release ();
						finished (true);
						handle_error (err);
					}
				}
			}
		}

		public void choose_provider (string depend, string[] providers) {
			var choose_provider_dialog = new ChooseProviderDialog (depend, providers, window);
			choose_provider_dialog.run ();
			try {
				daemon.choose_provider (choose_provider_dialog.comboboxtext.active);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			choose_provider_dialog.destroy ();
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
		}

		public TransactionType set_transaction_sum () {
			// return 0 if transaction_sum is empty, 2, if there are only aur updates, 1 otherwise
			TransactionType type = 0;
			uint64 dsize = 0;
			UpdateInfos[] prepared_to_add = {};
			UpdateInfos[] prepared_to_remove = {};
			string[] to_downgrade = {};
			string[] to_install = {};
			string[] to_reinstall = {};
			string[] to_update = {};
			string[] _to_build = {};
			Gtk.TreeIter iter;
			transaction_sum_dialog.top_label.set_markup ("<big><b>%s</b></big>".printf (dgettext (null, "Transaction Summary")));
			transaction_sum_dialog.sum_list.clear ();
			try {
				prepared_to_add = daemon.trans_to_add ();
				prepared_to_remove = daemon.trans_to_remove ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			foreach (UpdateInfos pkg_info in prepared_to_add) {
				dsize += pkg_info.download_size;
				Pamac.Package local_pkg = find_local_pkg (pkg_info.name);
				if (local_pkg.name == "") {
					to_install += "%s %s".printf (pkg_info.name, pkg_info.version);
				} else {
					int cmp = Alpm.pkg_vercmp (pkg_info.version, local_pkg.version);
					if (cmp == 1) {
						to_update += "%s %s".printf (pkg_info.name, pkg_info.version);
					} else if (cmp == 0) {
						to_reinstall += "%s %s".printf (pkg_info.name, pkg_info.version);
					} else {
						to_downgrade += "%s %s".printf (pkg_info.name, pkg_info.version);
					}
				}
			}
			foreach (string name in to_build) {
				_to_build += name;
			}
			int len = prepared_to_remove.length;
			int i;
			if (len != 0) {
				type |= TransactionType.STANDARD;
				transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												0, dgettext (null, "To remove") + ":",
												1, "%s %s".printf (prepared_to_remove[0].name, prepared_to_remove[0].version));
				i = 1;
				while (i < len) {
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, "%s %s".printf (prepared_to_remove[i].name, prepared_to_remove[i].version));
					i++;
				}
			}
			len = to_downgrade.length;
			if (len != 0) {
				type |= TransactionType.STANDARD;
				transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												0, dgettext (null, "To downgrade") + ":",
												1, to_downgrade[0]);
				i = 1;
				while (i < len) {
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, to_downgrade[i]);
					i++;
				}
			}
			len = _to_build.length;
			if (len != 0) {
				type |= TransactionType.BUILD;
				transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												0, dgettext (null, "To build") + ":",
												1, _to_build[0]);
				i = 1;
				while (i < len) {
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, _to_build[i]);
					i++;
				}
			}
			len = to_install.length;
			if (len != 0) {
				type |= TransactionType.STANDARD;
				transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												0, dgettext (null, "To install") + ":",
												1, to_install[0]);
				i = 1;
				while (i < len) {
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, to_install[i]);
					i++;
				}
			}
			len = to_reinstall.length;
			if (len != 0) {
				type |= TransactionType.STANDARD;
				transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												0, dgettext (null, "To reinstall") + ":",
												1, to_reinstall[0]);
				i = 1;
				while (i < len) {
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, to_reinstall[i]);
					i++;
				}
			}
			len = to_update.length;
			if (len != 0) {
				type |= TransactionType.UPDATE;
				if (mode != Mode.UPDATER) {
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
													0, dgettext (null, "To update") + ":",
													1, to_update[0]);
					i = 1;
					while (i < len) {
						transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
													1, to_update[i]);
						i++;
					}
				}
			}
			if (dsize == 0) {
				transaction_sum_dialog.bottom_label.set_visible (false);
			} else {
				transaction_sum_dialog.bottom_label.set_markup ("<b>%s: %s</b>".printf (dgettext (null, "Total download size"), format_size (dsize)));
				transaction_sum_dialog.bottom_label.set_visible (true);
			}
			return type;
		}

		public void start_commit () {
			progress_dialog.cancel_button.set_visible (false);
			try {
				daemon.start_trans_commit ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void build_aur_packages () {
			string action = dgettext (null,"Building packages") + "...";
			progress_dialog.spawn_in_term ({"echo", action});
			progress_dialog.action_label.set_text (action);
			progress_dialog.progressbar.set_fraction (0);
			progress_dialog.progressbar.set_text ("");
			progress_dialog.cancel_button.set_visible (false);
			progress_dialog.close_button.set_visible (false);
			progress_dialog.expander.set_expanded (true);
			progress_dialog.width_request = 700;
			progress_dialog.term.grab_focus ();
			pulse_timeout_id = Timeout.add (500, (GLib.SourceFunc) progress_dialog.progressbar.pulse);
			string[] cmds = {"yaourt", "-S"};
			var pamac_config = new Pamac.Config ("/etc/pamac.conf");
			if (pamac_config.no_confirm_build) {
				cmds += "--noconfirm";
			}
			foreach (string name in to_build) {
				cmds += name;
			}
			Pid child_pid;
			progress_dialog.spawn_in_term (cmds, out child_pid);
			// watch_child is needed in order to have the child_exited signal emitted
			progress_dialog.term.watch_child (child_pid);
		}

		public void cancel () {
			try {
				daemon.trans_cancel ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void release () {
			try {
				daemon.trans_release ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			foreach (string pkgname in special_ignorepkgs) {
				remove_ignorepkg (pkgname);
			}
		}

		public void stop_daemon () {
			try {
				daemon.quit ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		void on_emit_event (uint primary_event, uint secondary_event, string[] details) {
			string msg;
			switch (primary_event) {
				case Alpm.Event.Type.CHECKDEPS_START:
					msg = dgettext (null, "Checking dependencies") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.FILECONFLICTS_START:
					msg = dgettext (null, "Checking file conflicts") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.RESOLVEDEPS_START:
					msg = dgettext (null, "Resolving dependencies") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.INTERCONFLICTS_START:
					msg = dgettext (null, "Checking inter-conflicts") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.PACKAGE_OPERATION_START:
					switch (secondary_event) {
						case Alpm.Package.Operation.INSTALL:
							progress_dialog.cancel_button.set_visible (false);
							previous_filename = details[0];
							msg = dgettext (null, "Installing %s").printf (details[0]) + "...";
							progress_dialog.action_label.set_text (msg);
							msg = dgettext (null, "Installing %s").printf ("%s (%s)".printf (details[0], details[1]))+ "...";
							progress_dialog.spawn_in_term ({"echo", msg});
							break;
						case Alpm.Package.Operation.REINSTALL:
							progress_dialog.cancel_button.set_visible (false);
							previous_filename = details[0];
							msg = dgettext (null, "Reinstalling %s").printf (details[0]) + "...";
							progress_dialog.action_label.set_text (msg);
							msg = dgettext (null, "Reinstalling %s").printf ("%s (%s)".printf (details[0], details[1]))+ "...";
							progress_dialog.spawn_in_term ({"echo", msg});
							break;
						case Alpm.Package.Operation.REMOVE:
							progress_dialog.cancel_button.set_visible (false);
							previous_filename = details[0];
							msg = dgettext (null, "Removing %s").printf (details[0]) + "...";
							progress_dialog.action_label.set_text (msg);
							msg = dgettext (null, "Removing %s").printf ("%s (%s)".printf (details[0], details[1]))+ "...";
							progress_dialog.spawn_in_term ({"echo", msg});
							break;
						case Alpm.Package.Operation.UPGRADE:
							progress_dialog.cancel_button.set_visible (false);
							previous_filename = details[0];
							msg = dgettext (null, "Upgrading %s").printf (details[0]) + "...";
							progress_dialog.action_label.set_text (msg);
							msg = dgettext (null, "Upgrading %s").printf ("%s (%s -> %s)".printf (details[0], details[1], details[2]))+ "...";
							progress_dialog.spawn_in_term ({"echo", msg});
							break;
						case Alpm.Package.Operation.DOWNGRADE:
							progress_dialog.cancel_button.set_visible (false);
							previous_filename = details[0];
							msg = dgettext (null, "Downgrading %s").printf (details[0]) + "...";
							progress_dialog.action_label.set_text (msg);
							msg = dgettext (null, "Downgrading %s").printf ("%s (%s -> %s)".printf (details[0], details[1], details[2]))+ "...";
							progress_dialog.spawn_in_term ({"echo", msg});
							break;
					}
					break;
				case Alpm.Event.Type.INTEGRITY_START:
					msg = dgettext (null, "Checking integrity") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.KEYRING_START:
					progress_dialog.cancel_button.set_visible (true);
					msg = dgettext (null, "Checking keyring") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.KEY_DOWNLOAD_START:
					msg = dgettext (null, "Downloading required keys") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.LOAD_START:
					msg = dgettext (null, "Loading packages files") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.DELTA_INTEGRITY_START:
					msg = dgettext (null, "Checking delta integrity") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.DELTA_PATCHES_START:
					msg = dgettext (null, "Applying deltas") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.DELTA_PATCH_START:
					msg = dgettext (null, "Generating %s with %s").printf (details[0], details[1]) + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.DELTA_PATCH_DONE:
					msg = dgettext (null, "Generation succeeded") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.DELTA_PATCH_FAILED:
					msg = dgettext (null, "Generation failed") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.SCRIPTLET_INFO:
					progress_dialog.action_label.set_text (dgettext (null, "Configuring %s").printf (previous_filename) + "...");
					progress_dialog.expander.set_expanded (true);
					progress_dialog.spawn_in_term ({"echo", "-n", details[0]});
					break;
				case Alpm.Event.Type.RETRIEVE_START:
					progress_dialog.cancel_button.set_visible (true);
					msg = dgettext (null, "Downloading") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.DISKSPACE_START:
					msg = dgettext (null, "Checking available disk space") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.OPTDEP_REMOVAL:
					msg = dgettext (null, "%s optionally requires %s").printf (details[0], details[1]);
					progress_dialog.spawn_in_term ({"echo", msg});
					Gtk.TextIter end_iter;
					msg += "\n";
					transaction_info_dialog.textbuffer.get_end_iter (out end_iter);
					transaction_info_dialog.textbuffer.insert (ref end_iter, msg, msg.length);
					break;
				case Alpm.Event.Type.DATABASE_MISSING:
					progress_dialog.spawn_in_term ({"echo", dgettext (null, "Database file for %s does not exist").printf (details[0])});
					break;
				case Alpm.Event.Type.PACNEW_CREATED:
					progress_dialog.spawn_in_term ({"echo", dgettext (null, "%s installed as %s.pacnew").printf (details[0])});
					break;
				case Alpm.Event.Type.PACSAVE_CREATED:
					progress_dialog.spawn_in_term ({"echo", dgettext (null, "%s installed as %s.pacsave").printf (details[0])});
					break;
				case Alpm.Event.Type.PACORIG_CREATED:
					progress_dialog.spawn_in_term ({"echo", dgettext (null, "%s installed as %s.pacorig").printf (details[0])});
					break;
				default:
					break;
			}
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
		}

		void on_emit_providers (string depend, string[] providers) {
			choose_provider (depend, providers);
		}

		void on_emit_progress (uint progress, string pkgname, int percent, uint n_targets, uint current_target) {
			double fraction;
			switch (progress) {
				case Alpm.Progress.ADD_START:
				case Alpm.Progress.UPGRADE_START:
				case Alpm.Progress.DOWNGRADE_START:
				case Alpm.Progress.REINSTALL_START:
				case Alpm.Progress.REMOVE_START:
					fraction = ((float) (current_target-1)/n_targets)+((float) percent/(100*n_targets));
					break;
				case Alpm.Progress.CONFLICTS_START:
				case Alpm.Progress.DISKSPACE_START:
				case Alpm.Progress.INTEGRITY_START:
				case Alpm.Progress.KEYRING_START:
				case Alpm.Progress.LOAD_START:
				default:
					fraction = (float) percent/100;
					break;
			}
			string textbar = "%lu/%lu".printf (current_target, n_targets);
			if (textbar != previous_textbar) {
				previous_textbar = textbar;
				progress_dialog.progressbar.set_text (textbar);
			}
			if (fraction != previous_percent) {
				previous_percent = fraction;
				progress_dialog.progressbar.set_fraction (fraction);
			}
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
		}

		void on_emit_download (string filename, uint64 xfered, uint64 total) {
			string label;
			string textbar;
			double fraction;
			if (filename != previous_filename) {
				previous_filename = filename;
				if (filename.has_suffix (".db")) {
					label = dgettext (null, "Refreshing %s").printf (filename.replace (".db", "")) + "...";
				} else {
					label = dgettext (null, "Downloading %s").printf (filename.replace (".pkg.tar.xz", "")) + "...";
				}
				if (label != previous_label) {
					previous_label = label;
					progress_dialog.action_label.set_text (label);
					progress_dialog.spawn_in_term ({"echo", label});
				}
			}
			if (total_download > 0) {
				fraction = (float) (xfered + already_downloaded) / total_download;
				if (fraction <= 1) {
					textbar = "%s/%s".printf (format_size (xfered + already_downloaded), format_size (total_download));
				} else {
					textbar = "%s".printf (format_size (xfered + already_downloaded));
				}
			} else {
				fraction = (float) xfered / total;
				if (fraction <= 1) {
					textbar = "%s/%s".printf (format_size (xfered), format_size (total));
				} else {
					textbar = "%s".printf (format_size (xfered));
				}
			}
			if (fraction > 0) {
				if (fraction != previous_percent) {
					previous_percent = fraction;
					progress_dialog.progressbar.set_fraction (fraction);
				}
			} else {
				progress_dialog.progressbar.set_fraction (0);
			}
			if (textbar != previous_textbar) {
				previous_textbar = textbar;
				progress_dialog.progressbar.set_text (textbar);
			}
			if (xfered == total) {
				already_downloaded += total;
				previous_filename = "";
			}
		}

		void on_emit_totaldownload (uint64 total) {
			total_download = total;
		}

		void on_emit_log (uint level, string msg) {
			// msg ends with \n
			string? line = null;
			Gtk.TextIter end_iter;
			if ((Alpm.LogLevel) level == Alpm.LogLevel.WARNING) {
				// do not show warning when manjaro-system remove db.lck
				if (previous_filename != "manjaro-system") {
					if (previous_filename != "") {
						line = dgettext (null, "Warning") + ": " + previous_filename + ": " + msg;
					} else {
						line = dgettext (null, "Warning") + ": " + msg;
					}
					transaction_info_dialog.textbuffer.get_end_iter (out end_iter);
					transaction_info_dialog.textbuffer.insert (ref end_iter, msg, msg.length);
				}
			} else if ((Alpm.LogLevel) level == Alpm.LogLevel.ERROR) {
				if (previous_filename != "") {
					line = dgettext (null, "Error") + ": " + previous_filename + ": " + msg;
				} else {
					line = dgettext (null, "Error") + ": " + msg;
				}
			}
			if (line != null) {
				progress_dialog.expander.set_expanded (true);
				progress_dialog.spawn_in_term ({"echo", "-n", line});
			}
		}

		public void show_warnings () {
			if (transaction_info_dialog.textbuffer.text != "") {
				transaction_info_dialog.set_title (dgettext (null, "Warning"));
				transaction_info_dialog.label.set_visible (false);
				transaction_info_dialog.expander.set_visible (true);
				transaction_info_dialog.expander.set_expanded (true);
				transaction_info_dialog.run ();
				transaction_info_dialog.hide ();
				while (Gtk.events_pending ()) {
					Gtk.main_iteration ();
				}
				Gtk.TextIter start_iter;
				Gtk.TextIter end_iter;
				transaction_info_dialog.textbuffer.get_start_iter (out start_iter);
				transaction_info_dialog.textbuffer.get_end_iter (out end_iter);
				transaction_info_dialog.textbuffer.delete (ref start_iter, ref end_iter);
			}
		}

		public void handle_error (ErrorInfos error) {
			progress_dialog.expander.set_expanded (true);
			progress_dialog.spawn_in_term ({"echo", "-n", error.message});
			Gtk.TextIter start_iter;
			Gtk.TextIter end_iter;
			transaction_info_dialog.set_title (dgettext (null, "Error"));
			transaction_info_dialog.label.set_visible (true);
			transaction_info_dialog.label.set_markup (error.message);
			if (error.details.length != 0) {
				transaction_info_dialog.textbuffer.get_start_iter (out start_iter);
				transaction_info_dialog.textbuffer.get_end_iter (out end_iter);
				transaction_info_dialog.textbuffer.delete (ref start_iter, ref end_iter);
				transaction_info_dialog.expander.set_visible (true);
				transaction_info_dialog.expander.set_expanded (true);
				progress_dialog.spawn_in_term ({"echo", ":"});
				foreach (string detail in error.details) {
					progress_dialog.spawn_in_term ({"echo", detail});
					string str = detail + "\n";
					transaction_info_dialog.textbuffer.get_end_iter (out end_iter);
					transaction_info_dialog.textbuffer.insert (ref end_iter, str, str.length);
				}
			} else {
				transaction_info_dialog.expander.set_visible (false);
			}
			progress_dialog.spawn_in_term ({"echo"});
			transaction_info_dialog.run ();
			transaction_info_dialog.hide ();
			progress_dialog.hide ();
			transaction_info_dialog.textbuffer.get_start_iter (out start_iter);
			transaction_info_dialog.textbuffer.get_end_iter (out end_iter);
			transaction_info_dialog.textbuffer.delete (ref start_iter, ref end_iter);
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
		}

		public void on_refresh_finished (ErrorInfos error) {
			if (error.message == "") {
				if (mode == Mode.UPDATER) {
					progress_dialog.hide ();
					while (Gtk.events_pending ()) {
						Gtk.main_iteration ();
					}
					finished (false);
				} else {
					clear_lists ();
					sysupgrade (0);
				}
			} else {
				finished (true);
				handle_error (error);
			}
			previous_filename = "";
			daemon.refresh_finished.disconnect (on_refresh_finished);
		}

		public void on_trans_prepare_finished (ErrorInfos error) {
			if (error.message == "") {
				show_warnings ();
				TransactionType type = set_transaction_sum ();
				if (type == TransactionType.UPDATE && mode == Mode.UPDATER) {
					// there only updates
					start_commit ();
				} else if (type != 0) {
					if (transaction_sum_dialog.run () == Gtk.ResponseType.OK) {
						transaction_sum_dialog.hide ();
						while (Gtk.events_pending ()) {
							Gtk.main_iteration ();
						}
						if (type == TransactionType.BUILD) {
							// there only AUR packages to build
							var err = ErrorInfos ();
							on_trans_commit_finished (err);
						} else {
							start_commit ();
						}
					} else {
						progress_dialog.spawn_in_term ({"echo", dgettext (null, "Transaction cancelled") + ".\n"});
						progress_dialog.hide ();
						transaction_sum_dialog.hide ();
						while (Gtk.events_pending ()) {
							Gtk.main_iteration ();
						}
						release ();
						to_build.remove_all ();
						sysupgrade_after_trans = false;
						finished (true);
					}
				} else {
					//var err = ErrorInfos ();
					//err.message = dgettext (null, "Nothing to do") + "\n";
					progress_dialog.spawn_in_term ({"echo", dgettext (null, "Nothing to do") + ".\n"});
					progress_dialog.hide ();
					while (Gtk.events_pending ()) {
						Gtk.main_iteration ();
					}
					release ();
					clear_lists ();
					finished (false);
					//handle_error (err);
				}
			} else {
				finished (true);
				handle_error (error);
			}
		}

		public void on_trans_commit_finished (ErrorInfos error) {
			if (error.message == "") {
				if (to_build.length != 0) {
					if (to_add.length != 0
							|| to_remove.length != 0
							|| to_load.length != 0) {
						progress_dialog.spawn_in_term ({"echo", dgettext (null, "Transaction successfully finished") + ".\n"});
					}
					build_aur_packages ();
				} else {
					//progress_dialog.action_label.set_text (dgettext (null, "Transaction successfully finished"));
					clear_lists ();
					show_warnings ();
					if (sysupgrade_after_trans) {
						sysupgrade_after_trans = false;
						sysupgrade (0);
					} else {
						if (build_status == 0) {
							progress_dialog.spawn_in_term ({"echo", dgettext (null, "Transaction successfully finished") + ".\n"});
							progress_dialog.hide ();
							while (Gtk.events_pending ()) {
								Gtk.main_iteration ();
							}
						} else {
							progress_dialog.progressbar.set_fraction (0);
							progress_dialog.cancel_button.set_visible (false);
							progress_dialog.close_button.set_visible (true);
							progress_dialog.spawn_in_term ({"echo"});
						}
						finished (false);
					}
				}
			} else {
				finished (true);
				handle_error (error);
			}
			total_download = 0;
			already_downloaded = 0;
			build_status = 0;
			previous_filename = "";
		}

		void on_term_child_exited (int status) {
			Source.remove (pulse_timeout_id);
			to_build.remove_all ();
			build_status = status;
			// let the time to the daemon to update packages
			Timeout.add (1000, () => {
				var err = ErrorInfos ();
				on_trans_commit_finished (err);
				return false;
			});
		}

		void on_write_pamac_config_finished (int refresh_period, bool aur_enabled, bool recurse) {
			flags = Alpm.TransFlag.CASCADE;
			if (recurse) {
				flags |= Alpm.TransFlag.RECURSE;
			}
			Pamac.Package pkg = find_local_pkg ("yaourt");
			if (pkg.name != "") {
				enable_aur (aur_enabled);
			}
		}

		void on_generate_mirrors_list_data (string line) {
			progress_dialog.spawn_in_term ({"echo", "-n", line});
		}

		void on_generate_mirrors_list_finished () {
			Source.remove (pulse_timeout_id);
			progress_dialog.spawn_in_term ({"echo"});
			// force a dbs refresh
			start_refresh (1);
		}

		void connecting_dbus_signals () {
			try {
				daemon = Bus.get_proxy_sync (BusType.SYSTEM, "org.manjaro.pamac",
														"/org/manjaro/pamac");
				// Connecting to signals
				daemon.emit_event.connect (on_emit_event);
				daemon.emit_providers.connect (on_emit_providers);
				daemon.emit_progress.connect (on_emit_progress);
				daemon.emit_download.connect (on_emit_download);
				daemon.emit_totaldownload.connect (on_emit_totaldownload);
				daemon.emit_log.connect (on_emit_log);
				daemon.trans_prepare_finished.connect (on_trans_prepare_finished);
				daemon.trans_commit_finished.connect (on_trans_commit_finished);
				daemon.write_pamac_config_finished.connect (on_write_pamac_config_finished);
				daemon.generate_mirrors_list_data.connect (on_generate_mirrors_list_data);
				daemon.generate_mirrors_list_finished.connect (on_generate_mirrors_list_finished);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}
	}
}
