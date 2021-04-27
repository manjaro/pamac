/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2021 Guillaume Benoit <guillaume@manjaro.org>
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
	public class Transaction: Object {
		enum Type {
			INSTALL = (1 << 0),
			REMOVE = (1 << 1),
			UPDATE = (1 << 2),
			BUILD = (1 << 3)
		}
		TransactionInterface transaction_interface;
		delegate void TransactionAction ();
		bool waiting;
		unowned Config config;
		unowned MainContext context;
		// run transaction data
		bool sysupgrading;
		bool force_refresh;
		int trans_flags;
		GenericSet<string?> to_install;
		GenericSet<string?> to_remove;
		GenericSet<string?> to_load;
		GenericSet<string?> to_build;
		GenericSet<string?> ignorepkgs;
		GenericSet<string?> overwrite_files;
		GenericSet<string?> to_install_as_dep;
		HashTable<string, SnapPackage> snap_to_install;
		HashTable<string, SnapPackage> snap_to_remove;
		HashTable<string, FlatpakPackage> flatpak_to_install;
		HashTable<string, FlatpakPackage> flatpak_to_remove;
		HashTable<string, FlatpakPackage> flatpak_to_upgrade;
		// building data
		string tmp_path;
		string aurdb_path;
		GenericSet<string?> already_checked_aur_dep;
		GenericSet<string?> aur_desc_list;
		Queue<string> to_build_queue;
		GenericSet<string?> aur_pkgs_to_install;
		bool building;
		Cancellable build_cancellable;
		// transaction options
		public Database database { get; construct set; }
		public bool clone_build_files { get; set; }

		public signal void emit_action (string action);
		public signal void emit_action_progress (string action, string status, double progress);
		public signal void emit_download_progress (string action, string status, double progress);
		public signal void emit_hook_progress (string action, string details, string status, double progress);
		public signal void emit_script_output (string message);
		public signal void emit_warning (string message);
		public signal void emit_error (string message, string[] details);
		public signal void start_waiting ();
		public signal void stop_waiting ();
		public signal void start_preparing ();
		public signal void stop_preparing ();
		public signal void start_downloading ();
		public signal void stop_downloading ();
		public signal void start_building ();
		public signal void stop_building ();
		public signal void important_details_outpout (bool must_show);

		public Transaction (Database database) {
			Object (database: database);
		}

		construct {
			config = database.config;
			context = database.context;
			if (Posix.geteuid () == 0) {
				// we are root
				transaction_interface = new TransactionInterfaceRoot (context);
			} else {
				// use dbus daemon
				transaction_interface = new TransactionInterfaceDaemon (config);
			}
			waiting = false;
			// transaction options
			clone_build_files = true;
			// run transaction data
			sysupgrading = false;
			force_refresh = false;
			to_install = new GenericSet<string?> (str_hash, str_equal);
			to_remove = new GenericSet<string?> (str_hash, str_equal);
			to_load = new GenericSet<string?> (str_hash, str_equal);
			to_build = new GenericSet<string?> (str_hash, str_equal);
			ignorepkgs = new GenericSet<string?> (str_hash, str_equal);
			overwrite_files = new GenericSet<string?> (str_hash, str_equal);
			to_install_as_dep = new GenericSet<string?> (str_hash, str_equal);
			// alpm_utils global variable declared in alpm_utils.vala
			alpm_utils = new AlpmUtils (config, database.soup_session);
			alpm_utils.choose_provider.connect (choose_provider_real);
			alpm_utils.emit_action.connect ((sender, action) => {
				context.invoke (() => {
					emit_action (action);
					return false;
				});
			});
			alpm_utils.emit_action_progress.connect ((sender, action, status, progress) => {
				context.invoke (() => {
					emit_action_progress (action, status, progress);
					return false;
				});
			});
			alpm_utils.emit_hook_progress.connect ((sender, action, details, status, progress) => {
				context.invoke (() => {
					emit_hook_progress (action, details, status, progress);
					return false;
				});
			});
			alpm_utils.emit_download_progress.connect ((sender, action, status, progress) => {
				context.invoke (() => {
					emit_download_progress (action, status, progress);
					return false;
				});
			});
			alpm_utils.start_downloading.connect ((sender) => {
				context.invoke (() => {
					start_downloading ();
					return false;
				});
			});
			alpm_utils.stop_downloading.connect ((sender) => {
				context.invoke (() => {
					stop_downloading ();
					return false;
				});
			});
			alpm_utils.emit_script_output.connect ((sender, message) => {
				context.invoke (() => {
					emit_script_output (message);
					return false;
				});
			});
			alpm_utils.emit_warning.connect ((sender, message) => {
				context.invoke (() => {
					emit_warning (message);
					return false;
				});
			});
			alpm_utils.emit_error.connect ((sender, message, details) => {
				string[] details_copy = details;
				context.invoke (() => {
					emit_error (message, details_copy);
					return false;
				});
			});
			alpm_utils.important_details_outpout.connect ((sender, must_show) => {
				context.invoke (() => {
					important_details_outpout (must_show);
					return false;
				});
			});
			// only used as root in transaction_interface_root.vala
			alpm_utils.get_authorization.connect ((sender) => {
				if (Posix.geteuid () == 0) {
					return true;
				}
				return false;
			});
			snap_to_install = new HashTable<string, SnapPackage> (str_hash, str_equal);
			snap_to_remove = new HashTable<string, SnapPackage> (str_hash, str_equal);
			flatpak_to_install = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			flatpak_to_remove = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			flatpak_to_upgrade = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			// building data
			tmp_path = "/tmp/pamac";
			aurdb_path = "/tmp/pamac/aur-%s".printf (Environment.get_user_name ());
			already_checked_aur_dep = new GenericSet<string?> (str_hash, str_equal);
			aur_desc_list = new GenericSet<string?> (str_hash, str_equal);
			aur_pkgs_to_install = new GenericSet<string?> (str_hash, str_equal);
			to_build_queue = new Queue<string> ();
			build_cancellable = new Cancellable ();
			building = false;
			connecting_signals ();
		}

		public void quit_daemon () {
			try {
				transaction_interface.quit_daemon ();
			} catch (Error e) {
				emit_error ("Daemon Error", {"quit_daemon: %s".printf (e.message)});
			}
		}

		protected virtual async bool ask_commit (TransactionSummary summary) {
			// no confirm
			return true;
		}

		protected virtual async bool ask_edit_build_files (TransactionSummary summary) {
			// no edit
			return false;
		}

		protected virtual async void edit_build_files (string[] pkgnames) {
			// do nothing
		}

		protected virtual async bool ask_import_key (string pkgname, string key, string owner) {
			// no import
			return false;
		}

		protected async GenericArray<string> get_build_files_async (string pkgname) {
			string pkgdir_name;
			if (Posix.geteuid () == 0) {
				// build as root with systemd-run
				// set aur_build_dir to "/var/cache/pamac"
				pkgdir_name = Path.build_filename ("/var/cache/pamac", pkgname);
			} else if (config.aur_build_dir == "/var/tmp" || config.aur_build_dir == "/tmp") {
				pkgdir_name = Path.build_filename (config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()), pkgname);
			} else {
				pkgdir_name = Path.build_filename (config.aur_build_dir, pkgname);
			}
			var files = new GenericArray<string> ();
			// PKGBUILD
			files.add (Path.build_filename (pkgdir_name, "PKGBUILD"));
			var srcinfo = File.new_for_path (Path.build_filename (pkgdir_name, ".SRCINFO"));
			try {
				// read .SRCINFO
				var dis = new DataInputStream (yield srcinfo.read_async ());
				string? line;
				while ((line = yield dis.read_line_async ()) != null) {
					if ("source = " in line) {
						string source = line.split (" = ", 2)[1];
						if (!("://" in source)) {
							string source_path = Path.build_filename (pkgdir_name, source);
							var source_file = File.new_for_path (source_path);
							if (source_file.query_exists ()) {
								files.add ((owned) source_path);
							}
						}
					} else if ("install = " in line) {
						string install = line.split (" = ", 2)[1];
						string install_path = Path.build_filename (pkgdir_name, install);
						var install_file = File.new_for_path (install_path);
						if (install_file.query_exists ()) {
							files.add ((owned) install_path);
						}
					}
				}
			} catch (Error e) {
				warning (e.message);
			}
			return files;
		}

		protected virtual async string[] choose_optdeps (string pkgname, string[] optdeps) {
			// do not install optdeps
			return {};
		}

		protected virtual async int choose_provider (string depend, string[] providers) {
			// choose first provider
			return 0;
		}

		protected virtual async bool ask_snap_install_classic (string name) {
			// do not install
			return false;
		}

		public async bool get_authorization_async () {
			try {
				return yield transaction_interface.get_authorization ();
			} catch (Error e) {
				emit_error ("Daemon Error", {"get_authorization: %s".printf (e.message)});
			}
			return false;
		}

		public void remove_authorization () {
			try {
				transaction_interface.remove_authorization ();
			} catch (Error e) {
				emit_error ("Daemon Error", {"remove_authorization: %s".printf (e.message)});
			}
		}

		public async void generate_mirrors_list_async (string country) {
			emit_action (dgettext (null, "Refreshing mirrors list") + "...");
			important_details_outpout (false);
			transaction_interface.generate_mirrors_list_data.connect (on_generate_mirrors_list_data);
			try {
				yield transaction_interface.generate_mirrors_list (country);
			} catch (Error e) {
				emit_error ("Daemon Error", {"generate_mirrors_list: %s".printf (e.message)});
			}
			transaction_interface.generate_mirrors_list_data.disconnect (on_generate_mirrors_list_data);
			database.refresh ();
		}

		void on_generate_mirrors_list_data (string line) {
			emit_script_output (line);
		}

		public async void clean_cache_async () {
			HashTable<string, uint64?> details = yield database.get_clean_cache_details_async ();
			var iter = HashTableIter<string, uint64?> (details);
			var array = new GenericArray<string> (details.length);
			unowned string name;
			while (iter.next (out name, null)) {
				array.add (name);
			}
			try {
				yield transaction_interface.clean_cache (array.data);
			} catch (Error e) {
				emit_error ("Daemon Error", {"clean_cache: %s".printf (e.message)});
			}
		}

		public async void clean_build_files_async () {
			string real_aur_build_dir;
			if (Posix.geteuid () == 0) {
				// build as root with systemd-run
				// set aur_build_dir to "/var/cache/pamac"
				// use private here to get ride of the symlink
				real_aur_build_dir = "/var/cache/pamac";
			} else if (config.aur_build_dir == "/var/tmp" || config.aur_build_dir == "/tmp") {
				real_aur_build_dir = Path.build_filename (config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()));
			} else {
				real_aur_build_dir = config.aur_build_dir;
			}
			try {
				yield transaction_interface.clean_build_files (real_aur_build_dir);
			} catch (Error e) {
				emit_error ("Daemon Error", {"clean_build_files: %s".printf (e.message)});
			}
		}

		public async bool set_pkgreason_async (string pkgname, uint reason) {
			bool success = false;
			try {
				success = yield transaction_interface.set_pkgreason (pkgname, reason);
			} catch (Error e) {
				emit_error ("Daemon Error", {"set_pkgreason: %s".printf (e.message)});
			}
			database.refresh ();
			return success;
		}

		public async void download_updates_async () {
			try {
				yield transaction_interface.download_updates ();
			} catch (Error e) {
				emit_error ("Daemon Error", {"download_updates: %s".printf (e.message)});
			}
		}

		async bool compute_aur_build_list () {
			// set building to allow cancellation
			building = true;
			build_cancellable.reset ();
			start_building ();
			bool success = yield compute_aur_build_list_real ();
			stop_building ();
			building = false;
			if (build_cancellable.is_cancelled ()) {
				emit_script_output ("");
				emit_action (dgettext (null, "Transaction cancelled") + ".");
			}
			return success;
		}

		async int launch_subprocess (string[] cmds) {
			int status = 1;
			try {
				var process = new Subprocess.newv (cmds, SubprocessFlags.NONE);
				yield process.wait_async ();
				if (process.get_if_exited ()) {
					status = process.get_exit_status ();
				}
			} catch (Error e) {
				emit_error (dgettext (null, "Failed to prepare transaction"), {e.message});
			}
			return status;
		}

		async bool compute_aur_build_list_real () {
			var file = GLib.File.new_for_path (tmp_path);
			if (!file.query_exists ()) {
				yield launch_subprocess ({"mkdir", "-p", tmp_path});
				yield launch_subprocess ({"chmod", "a+w", tmp_path});
			}
			yield launch_subprocess ({"mkdir", "-p", aurdb_path});
			aur_desc_list.remove_all ();
			already_checked_aur_dep.remove_all ();
			var to_build_array = new GenericArray<string> ();
			foreach (unowned string pkgname in to_build) {
				to_build_array.add (pkgname);
			}
			bool success = yield check_aur_dep_list (to_build_array.data);
			if (success && aur_desc_list.length > 0) {
				// create a fake aur db
				yield launch_subprocess ({"rm", "-f", "%s/pamac_aur.db".printf (tmp_path)});
				string[] cmds = {"bsdtar", "-cf", "%s/pamac_aur.db".printf (tmp_path), "-C", aurdb_path};
				foreach (unowned string name_version in aur_desc_list) {
					cmds += name_version;
				}
				int ret = yield launch_subprocess (cmds);
				if (ret != 0) {
					success = false;
				}
			}
			return success;
		}

		async bool check_aur_dep_list (string[] pkgnames) {
			var dep_to_check = new GenericArray<string> ();
			var aur_pkgs = new HashTable<string, unowned AURPackage?> (str_hash, str_equal);
			if (clone_build_files) {
				aur_pkgs = yield database.get_aur_pkgs_async (pkgnames);
			}
			foreach (unowned string pkgname in pkgnames) {
				if (build_cancellable.is_cancelled ()) {
					return false;
				}
				if (already_checked_aur_dep.contains (pkgname)) {
					continue;
				}
				string real_aur_build_dir;
				if (Posix.geteuid () == 0) {
					// build as root with systemd-run
					// set aur_build_dir to "/var/cache/pamac"
					real_aur_build_dir = "/var/cache/pamac";
				} else if (config.aur_build_dir == "/var/tmp" || config.aur_build_dir == "/tmp") {
					real_aur_build_dir = Path.build_filename (config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()));
				} else {
					real_aur_build_dir = config.aur_build_dir;
				}
				unowned AURPackage? aur_pkg = aur_pkgs.lookup (pkgname);
				File? clone_dir = File.new_for_path (Path.build_filename (real_aur_build_dir, pkgname));
				if (clone_build_files) {
					if (aur_pkg == null) {
						// may be a virtual package
						// use search and add results
						var search_aur_pkgs = yield database.search_aur_pkgs_async (pkgname);
						foreach (unowned AURPackage found_pkg in search_aur_pkgs) {
							foreach (unowned string dep_string in found_pkg.provides) {
								string dep_name = database.get_alpm_dep_name (dep_string);
								if (dep_name == pkgname) {
									dep_to_check.add (found_pkg.name);
								}
							}
						}
						already_checked_aur_dep.add (pkgname);
						// make this error not fatal to propose to edit build files
						continue;
					}
					if (clone_dir.query_exists ()) {
						// refresh build files
						// use packagebase in case of split package
						emit_action (dgettext (null, "Cloning %s build files").printf (aur_pkg.packagebase) + "...");
						clone_dir = yield database.clone_build_files_async (aur_pkg.packagebase, false, build_cancellable);
						if (build_cancellable.is_cancelled ()) {
							return false;
						}
						if (clone_dir == null) {
							// error
							emit_error (dgettext (null, "Failed to prepare transaction"), {dgettext (null, "Failed to clone %s build files").printf (aur_pkg.packagebase)});
							return false;
						}
					}
					already_checked_aur_dep.add (aur_pkg.packagebase);
				} else {
					if (!clone_dir.query_exists ()) {
						// didn't find the target
						// parse all builddir to be sure to find it
						var builddir = File.new_for_path (real_aur_build_dir);
						try {
							FileEnumerator enumerator = builddir.enumerate_children ("standard::*", FileQueryInfoFlags.NONE);
							FileInfo info;
							while ((info = enumerator.next_file (null)) != null) {
								unowned string filename = info.get_name ();
								if (!(filename in already_checked_aur_dep)) {
									dep_to_check.add (filename);
								}
							}
						} catch (Error e) {
							emit_error (dgettext (null, "Failed to prepare transaction"), {dgettext (null, "target not found: %s").printf (pkgname)});
							return false;
						}
						continue;
					}
					emit_action (dgettext (null, "Generating %s information").printf (pkgname) + "...");
					bool success = yield database.regenerate_srcinfo_async (pkgname, build_cancellable);
					if (!success) {
						// error
						emit_error (dgettext (null, "Failed to prepare transaction"), {dgettext (null, "Failed to generate %s information").printf (pkgname)});
						return false;
					}
				}
				if (build_cancellable.is_cancelled ()) {
					return false;
				}
				emit_action (dgettext (null, "Checking %s dependencies").printf (pkgname) + "...");
				string arch = Posix.utsname ().machine;
				if (clone_dir.query_exists ()) {
					// use .SRCINFO
					var srcinfo = clone_dir.get_child (".SRCINFO");
					try {
						// read .SRCINFO
						var dis = new DataInputStream (yield srcinfo.read_async ());
						string? line;
						string current_section = "";
						bool current_section_is_pkgbase = true;
						var version = new StringBuilder ("");
						string pkgbase = "";
						string desc = "";
						var pkgnames_found = new GenericArray<string> ();
						var global_depends = new GenericArray<string> ();
						var global_checkdepends = new GenericArray<string> ();
						var global_makedepends = new GenericArray<string> ();
						var global_conflicts = new GenericArray<string> ();
						var global_provides = new GenericArray<string> ();
						var global_replaces = new GenericArray<string> ();
						var global_validpgpkeys = new GenericArray<string> ();
						var pkgnames_table = new HashTable<string, AURPackage> (str_hash, str_equal);
						while ((line = yield dis.read_line_async ()) != null) {
							if ("pkgbase = " in line) {
								pkgbase = line.split (" = ", 2)[1];
							} else if ("pkgdesc = " in line) {
								desc = line.split (" = ", 2)[1];
								if (!current_section_is_pkgbase) {
									unowned AURPackage? aur_pkg_found = pkgnames_table.get (current_section);
									if (aur_pkg_found != null) {
										aur_pkg_found.desc = desc;
									}
								}
							} else if ("pkgver = " in line) {
								version.append (line.split (" = ", 2)[1]);
							} else if ("pkgrel = " in line) {
								version.append ("-");
								version.append (line.split (" = ", 2)[1]);
							} else if ("epoch = " in line) {
								version.prepend (":");
								version.prepend (line.split (" = ", 2)[1]);
							// don't compute optdepends, it will be done by makepkg
							} else if ("optdepends" in line) {
								// pass
								continue;
							// compute depends, makedepends and checkdepends:
							// list name may contains arch, e.g. depends_x86_64
							// depends, provides, replaces and conflicts in pkgbase section are stored
							// in order to be added after if the list in pkgname is empty,
							// makedepends and checkdepends will be added in depends
							} else if ("depends" in line) {
								if ("depends = " in line || "depends_%s = ".printf (arch) in line) {
									string depend = line.split (" = ", 2)[1];
									if (current_section_is_pkgbase){
										if ("checkdepends" in line) {
											global_checkdepends.add ((owned) depend);
										} else if ("makedepends" in line) {
											global_makedepends.add ((owned) depend);
										} else {
											global_depends.add ((owned) depend);
										}
									} else {
										unowned AURPackage? aur_pkg_found = pkgnames_table.get (current_section);
										if (aur_pkg_found != null) {
											aur_pkg_found.depends.add ((owned) depend);
										}
									}
								}
							} else if ("provides" in line) {
								if ("provides = " in line || "provides_%s = ".printf (arch) in line) {
									string provide = line.split (" = ", 2)[1];
									if (current_section_is_pkgbase) {
										global_provides.add ((owned) provide);
									} else {
										unowned AURPackage? aur_pkg_found = pkgnames_table.get (current_section);
										if (aur_pkg_found != null) {
											aur_pkg_found.provides.add ((owned) provide);
										}
									}
								}
							} else if ("conflicts" in line) {
								if ("conflicts = " in line || "conflicts_%s = ".printf (arch) in line) {
									string conflict = line.split (" = ", 2)[1];
									if (current_section_is_pkgbase) {
										global_conflicts.add ((owned) conflict);
									} else {
										unowned AURPackage? aur_pkg_found = pkgnames_table.get (current_section);
										if (aur_pkg_found != null) {
											aur_pkg_found.conflicts.add ((owned) conflict);
										}
									}
								}
							} else if ("replaces" in line) {
								if ("replaces = " in line || "replaces_%s = ".printf (arch) in line) {
									string replace = line.split (" = ", 2)[1];
									if (current_section_is_pkgbase) {
										global_replaces.add ((owned) replace);
									} else {
										unowned AURPackage? aur_pkg_found = pkgnames_table.get (current_section);
										if (aur_pkg_found != null) {
											aur_pkg_found.replaces.add ((owned) replace);
										}
									}
								}
							// grab validpgpkeys to check if they are imported
							} else if ("validpgpkeys" in line) {
								if ("validpgpkeys = " in line) {
									global_validpgpkeys.add (line.split (" = ", 2)[1]);
								}
							} else if ("pkgname = " in line) {
								string pkgname_found = line.split (" = ", 2)[1];
								current_section = pkgname_found;
								current_section_is_pkgbase = false;
								if (!pkgnames_table.contains (pkgname_found)) {
									var aur_pkg_found = new AURPackageData ();
									aur_pkg_found.name = pkgname_found;
									aur_pkg_found.version = version.str;
									aur_pkg_found.desc = desc;
									aur_pkg_found.packagebase = pkgbase;
									pkgnames_table.insert (pkgname_found, aur_pkg_found);
									pkgnames_found.add ((owned) pkgname_found);
								}
							}
						}
						foreach (unowned string pkgname_found in pkgnames_found) {
							already_checked_aur_dep.add (pkgname_found);
						}
						// create fake aur db entries
						foreach (unowned string pkgname_found in pkgnames_found) {
							unowned AURPackage? aur_pkg_found = pkgnames_table.get (pkgname_found);
							// populate empty list will global ones
							if (global_depends.length != 0 && aur_pkg_found.depends.length == 0) {
								aur_pkg_found.depends = global_depends.copy (strdup);
							}
							if (global_provides.length != 0 && aur_pkg_found.provides.length == 0) {
								aur_pkg_found.provides = global_provides.copy (strdup);
							}
							if (global_conflicts.length != 0 && aur_pkg_found.conflicts.length == 0) {
								aur_pkg_found.conflicts = global_conflicts.copy (strdup);
							}
							if (global_replaces.length != 0 && aur_pkg_found.replaces.length == 0) {
								aur_pkg_found.replaces = global_replaces.copy (strdup);
							}
							// add checkdepends and makedepends in depends
							foreach (unowned string global_checkdepend in global_checkdepends) {
								aur_pkg_found.depends.add (global_checkdepend);
							}
							foreach (unowned string global_makedepend in global_makedepends) {
								aur_pkg_found.depends.add (global_makedepend);
							}
							// check deps
							foreach (unowned string dep_string in aur_pkg_found.depends) {
								if (!database.has_installed_satisfier (dep_string) &&
									!database.has_sync_satisfier (dep_string)) {
									string dep_name = database.get_alpm_dep_name (dep_string);
									if (!(dep_name in already_checked_aur_dep)) {
										dep_to_check.add ((owned) dep_name);
									}
								}
							}
							// write desc file
							string pkgdir = "%s-%s".printf (pkgname_found, aur_pkg_found.version);
							string pkgdir_path = "%s/%s".printf (aurdb_path, pkgdir);
							aur_desc_list.add (pkgdir);
							var file = GLib.File.new_for_path (pkgdir_path);
							if (!file.query_exists ()) {
								yield file.make_directory_async ();
							}
							file = GLib.File.new_for_path ("%s/desc".printf (pkgdir_path));
							FileOutputStream fos;
							// always recreate desc in case of .SRCINFO modifications
							if (file.query_exists ()) {
								fos = yield file.replace_async (null, false, FileCreateFlags.NONE);
							} else {
								fos = yield file.create_async (FileCreateFlags.NONE);
							}
							// creating a DataOutputStream to the file
							var dos = new DataOutputStream (fos);
							// fake filename
							dos.put_string ("%FILENAME%\n" + "%s-%s-any.pkg.tar\n\n".printf (pkgname_found, aur_pkg_found.version));
							// name
							dos.put_string ("%NAME%\n%s\n\n".printf (pkgname_found));
							// version
							dos.put_string ("%VERSION%\n%s\n\n".printf (aur_pkg_found.version));
							// base
							dos.put_string ("%BASE%\n%s\n\n".printf (aur_pkg_found.packagebase));
							// desc
							dos.put_string ("%DESC%\n%s\n\n".printf (aur_pkg_found.desc));
							// arch (double %% before ARCH to escape %A)
							dos.put_string ("%%ARCH%\n%s\n\n".printf (arch));
							// depends
							if (aur_pkg_found.depends.length != 0) {
								dos.put_string ("%DEPENDS%\n");
								foreach (unowned string name in aur_pkg_found.depends) {
									dos.put_string ("%s\n".printf (name));
								}
								dos.put_string ("\n");
							}
							// conflicts
							if (aur_pkg_found.conflicts.length != 0) {
								dos.put_string ("%CONFLICTS%\n");
								foreach (unowned string name in aur_pkg_found.conflicts) {
									dos.put_string ("%s\n".printf (name));
								}
								dos.put_string ("\n");
							}
							// provides
							if (aur_pkg_found.provides.length != 0) {
								dos.put_string ("%PROVIDES%\n");
								foreach (unowned string name in aur_pkg_found.provides) {
									dos.put_string ("%s\n".printf (name));
								}
								dos.put_string ("\n");
							}
							// replaces
							if (aur_pkg_found.replaces.length != 0) {
								dos.put_string ("%REPLACES%\n");
								foreach (unowned string name in aur_pkg_found.replaces) {
									dos.put_string ("%s\n".printf (name));
								}
								dos.put_string ("\n");
							}
						}
						// check signature
						if (global_validpgpkeys.length > 0) {
							yield check_signature (pkgname, global_validpgpkeys);
						}
					} catch (Error e) {
						emit_error (dgettext (null, "Failed to prepare transaction"), {dgettext (null, "Failed to check %s dependencies").printf (pkgname)});
						return false;
					}
				} else {
					// use aur infos
					// write desc file
					try {
						string pkgdir = "%s-%s".printf (aur_pkg.name, aur_pkg.version);
						string pkgdir_path = "%s/%s".printf (aurdb_path, pkgdir);
						aur_desc_list.add (pkgdir);
						var file = GLib.File.new_for_path (pkgdir_path);
						if (!file.query_exists ()) {
							yield file.make_directory_async ();
						}
						file = GLib.File.new_for_path ("%s/desc".printf (pkgdir_path));
						FileOutputStream fos;
						// always recreate desc in case of .SRCINFO modifications
						if (file.query_exists ()) {
							fos = yield file.replace_async (null, false, FileCreateFlags.NONE);
						} else {
							fos = yield file.create_async (FileCreateFlags.NONE);
						}
						// creating a DataOutputStream to the file
						var dos = new DataOutputStream (fos);
						// fake filename
						dos.put_string ("%FILENAME%\n" + "%s-%s-any.pkg.tar\n\n".printf (aur_pkg.name, aur_pkg.version));
						// name
						dos.put_string ("%NAME%\n%s\n\n".printf (aur_pkg.name));
						// version
						dos.put_string ("%VERSION%\n%s\n\n".printf (aur_pkg.version));
						// base
						dos.put_string ("%BASE%\n%s\n\n".printf (aur_pkg.packagebase));
						// desc
						dos.put_string ("%DESC%\n%s\n\n".printf (aur_pkg.desc));
						// arch (double %% before ARCH to escape %A)
						dos.put_string ("%%ARCH%\n%s\n\n".printf (arch));
						// depends
						bool depends_created = false;
						if (aur_pkg.depends.length != 0) {
							dos.put_string ("%DEPENDS%\n");
							depends_created = true;
							foreach (unowned string name in aur_pkg.depends) {
								dos.put_string ("%s\n".printf (name));
								// check dep
								if (!database.has_installed_satisfier (name) &&
									!database.has_sync_satisfier (name)) {
									string dep_name = database.get_alpm_dep_name (name);
									if (!(dep_name in already_checked_aur_dep)) {
										dep_to_check.add ((owned) dep_name);
									}
								}
							}
						}
						// add checkdepends and makedepends in depends
						if (aur_pkg.checkdepends.length != 0) {
							if (!depends_created) {
								dos.put_string ("%DEPENDS%\n");
								depends_created = true;
							}
							foreach (unowned string name in aur_pkg.checkdepends) {
								dos.put_string ("%s\n".printf (name));
								// check dep
								if (!database.has_installed_satisfier (name) &&
									!database.has_sync_satisfier (name)) {
									string dep_name = database.get_alpm_dep_name (name);
									if (!(dep_name in already_checked_aur_dep)) {
										dep_to_check.add ((owned) dep_name);
									}
								}
							}
						}
						if (aur_pkg.makedepends.length != 0) {
							if (!depends_created) {
								dos.put_string ("%DEPENDS%\n");
								depends_created = true;
							}
							foreach (unowned string name in aur_pkg.makedepends) {
								dos.put_string ("%s\n".printf (name));
								// check dep
								if (!database.has_installed_satisfier (name) &&
									!database.has_sync_satisfier (name)) {
									string dep_name = database.get_alpm_dep_name (name);
									if (!(dep_name in already_checked_aur_dep)) {
										dep_to_check.add ((owned) dep_name);
									}
								}
							}
						}
						// add after %DEPENDS new line
						if (depends_created) {
							dos.put_string ("\n");
						}
						// conflicts
						if (aur_pkg.conflicts.length != 0) {
							dos.put_string ("%CONFLICTS%\n");
							foreach (unowned string name in aur_pkg.conflicts) {
								dos.put_string ("%s\n".printf (name));
							}
							dos.put_string ("\n");
						}
						// provides
						if (aur_pkg.provides.length != 0) {
							dos.put_string ("%PROVIDES%\n");
							foreach (unowned string name in aur_pkg.provides) {
								dos.put_string ("%s\n".printf (name));
							}
							dos.put_string ("\n");
						}
						// replaces
						if (aur_pkg.replaces.length != 0) {
							dos.put_string ("%REPLACES%\n");
							foreach (unowned string name in aur_pkg.replaces) {
								dos.put_string ("%s\n".printf (name));
							}
							dos.put_string ("\n");
						}
					} catch (Error e) {
						emit_error (dgettext (null, "Failed to prepare transaction"), {dgettext (null, "Failed to check %s dependencies").printf (pkgname)});
						return false;
					}
				}
			}
			if (dep_to_check.length > 0) {
				return yield check_aur_dep_list (dep_to_check.data);
			}
			return true;
		}

		async bool clone_build_files_if_needed (string pkgdir, string pkgname) {
			File? clone_dir = File.new_for_path (pkgdir);
			if (!clone_dir.query_exists ()) {
				// clone build files
				emit_action (dgettext (null, "Cloning %s build files").printf (pkgname) + "...");
				clone_dir = yield database.clone_build_files_async (pkgname, false, build_cancellable);
				if (build_cancellable.is_cancelled ()) {
					return false;
				}
				if (clone_dir == null) {
					// error
					return false;
				}
			}
			return true;
		}

		async void check_signature (string pkgname, GenericArray<string> keys) {
			foreach (unowned string key in keys) {
				var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
				try {
					var process = launcher.spawnv ({"gpg", "--with-colons", "--batch", "--list-keys", key});
					yield process.wait_async ();
					if (process.get_if_exited ()) {
						if (process.get_exit_status () != 0) {
							// key is not imported in keyring
							// try to get key infos
							launcher.set_flags (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
							process = launcher.spawnv ({"gpg", "--with-colons", "--batch", "--search-keys", key});
							yield process.wait_async ();
							if (process.get_if_exited ()) {
								if (process.get_exit_status () == 0) {
									var dis = new DataInputStream (process.get_stdout_pipe ());
									string? line;
									while ((line = yield dis.read_line_async ()) != null) {
										// get first uid line
										if ("uid:" in line) {
											string owner = line.split (":", 3)[1];
											if (yield ask_import_key (pkgname, key, owner)) {
												int status = yield run_cmd_line_async ({"gpg", "--with-colons", "--batch", "--recv-keys", key}, null, build_cancellable);
												emit_script_output ("");
												if (status != 0) {
													emit_error (dgettext (null, "key %s could not be imported").printf (key), {});
												}
											}
											break;
										}
									}
								}
							}
						}
					}
				} catch (Error e) {
					warning (e.message);
				}
			}
		}

		public async bool run_async () {
			if (transaction_interface == null) {
				emit_error ("Daemon Error", {"failed to connect to dbus daemon"});
				return false;
			}
			bool success = true;
			if (sysupgrading ||
				to_install.length > 0 ||
				to_remove.length > 0 ||
				to_load.length > 0 ||
				to_build.length > 0) {
				success = yield run_alpm_transaction ();
				if (success) {
					if (to_build_queue.get_length () != 0) {
						success = yield build_aur_packages ();
						build_cancellable.reset ();
					}
					if (success) {
						if (snap_to_install.length > 0 ||
							snap_to_remove.length > 0) {
							success = yield run_snap_transaction ();
						}
					}
					if (success) {
						if (flatpak_to_install.length > 0 ||
							flatpak_to_remove.length > 0 ||
							flatpak_to_upgrade.length > 0) {
							success = yield run_flatpak_transaction ();
						}
					}
				}
				remove_authorization ();
				database.refresh ();
				if (success) {
					emit_action (dgettext (null, "Transaction successfully finished") + ".");
				} else {
					to_build_queue.clear ();
					snap_to_install.remove_all ();
					snap_to_remove.remove_all ();
					flatpak_to_install.remove_all ();
					flatpak_to_remove.remove_all ();
					flatpak_to_upgrade.remove_all ();
				}
				sysupgrading = false;
				force_refresh = false;
				to_install.remove_all ();
				to_remove.remove_all ();
				to_load.remove_all ();
				to_build.remove_all ();
				ignorepkgs.remove_all ();
				overwrite_files.remove_all ();
				to_install_as_dep.remove_all ();
			} else {
				if (snap_to_install.length > 0) {
					emit_action (dgettext (null, "Preparing") + "...");
					start_preparing ();
					// ask classic snaps
					var iter = HashTableIter<string, SnapPackage> (snap_to_install);
					var not_install = new GenericArray<unowned string> ();
					unowned string snap_name;
					SnapPackage pkg;
					while (iter.next (out snap_name, out pkg)) {
						if (pkg.confined != dgettext (null, "Yes")) {
							bool answer = yield ask_snap_install_classic (pkg.app_name);
							if (!answer) {
								not_install.add (snap_name);
							}
						}
					}
					foreach (unowned string name in not_install) {
						snap_to_install.remove (name);
					}
					stop_preparing ();
				}
				// ask confirmation
				var summary = new TransactionSummary ();
				if (snap_to_install.length > 0 ||
					snap_to_remove.length > 0) {
					start_preparing ();
					var iter = HashTableIter<string, SnapPackage> (snap_to_install);
					SnapPackage pkg;
					while (iter.next (null, out pkg)) {
						summary.to_install.add (pkg);
					}
					iter = HashTableIter<string, SnapPackage> (snap_to_remove);
					while (iter.next (null, out pkg)) {
						summary.to_remove.add (pkg);
					}
					stop_preparing ();
				}
				if (flatpak_to_install.length > 0 ||
					flatpak_to_remove.length > 0 ||
					flatpak_to_upgrade.length > 0) {
					start_preparing ();
					var iter = HashTableIter<string, FlatpakPackage> (flatpak_to_install);
					FlatpakPackage pkg;
					while (iter.next (null, out pkg)) {
						summary.to_install.add (pkg);
					}
					iter = HashTableIter<string, FlatpakPackage> (flatpak_to_remove);
					while (iter.next (null, out pkg)) {
						summary.to_remove.add (pkg);
					}
					iter = HashTableIter<string, FlatpakPackage> (flatpak_to_upgrade);
					while (iter.next (null, out pkg)) {
						summary.to_upgrade.add (pkg);
					}
					stop_preparing ();
				}
				if (summary.to_install.length == 0 &&
					summary.to_remove.length == 0 &&
					summary.to_upgrade.length == 0) {
					emit_action (dgettext (null, "Nothing to do") + ".");
					return false;
				} else if (yield ask_commit (summary)) {
					if (snap_to_install.length > 0 ||
						snap_to_remove.length > 0) {
						success = yield run_snap_transaction ();
					}
					if (flatpak_to_install.length > 0 ||
						flatpak_to_remove.length > 0 ||
						flatpak_to_upgrade.length > 0) {
						success = yield run_flatpak_transaction ();
					}
					if (success) {
						emit_action (dgettext (null, "Transaction successfully finished") + ".");
					}
					database.refresh ();
				} else {
					snap_to_install.remove_all ();
					snap_to_remove.remove_all ();
					flatpak_to_install.remove_all ();
					flatpak_to_remove.remove_all ();
					flatpak_to_upgrade.remove_all ();
					stop_preparing ();
					emit_action (dgettext (null, "Transaction cancelled") + ".");
					success = false;
				}
			}
			return success;
		}

		void add_config_ignore_pkgs () {
			foreach (unowned string name in config.ignorepkgs) {
				ignorepkgs.add (name);
			}
		}

		async void add_optdeps () {
			var to_add_to_install = new GenericSet<string?> (str_hash, str_equal);
			foreach (unowned string name in to_install) {
				// do not check if reinstall
				if (!database.is_installed_pkg (name)) {
					var uninstalled_optdeps = yield database.get_uninstalled_optdeps_async (name);
					var real_uninstalled_optdeps = new GenericArray<unowned string> ();
					foreach (unowned string optdep in uninstalled_optdeps) {
						string[] splitted = optdep.split (": ", 2);
						unowned string optdep_name = splitted[0];
						if (!(optdep_name in to_install) && !(optdep_name in to_add_to_install)) {
							real_uninstalled_optdeps.add (optdep);
						}
					}
					if (real_uninstalled_optdeps.length > 0) {
						string[] optdeps = yield choose_optdeps (name, real_uninstalled_optdeps.data);
						foreach (unowned string optdep in optdeps) {
							string optdep_name = optdep.split (": ", 2)[0];
							to_add_to_install.add ((owned) optdep_name);
						}
					}
				}
			}
			foreach (unowned string name in to_add_to_install) {
				add_pkg_to_install (name);
				add_pkg_to_mark_as_dep (name);
			}
		}

		async bool run_alpm_transaction () {
			emit_action (dgettext (null, "Preparing") + "...");
			if (to_install.length > 0) {
				yield add_optdeps ();
			}
			if (sysupgrading && config.check_aur_updates) {
				var updates = yield database.get_aur_updates_async (ignorepkgs);
				foreach (unowned AURPackage aur_pkg in updates.aur_updates) {
					to_build.add (aur_pkg.name);
				}
				foreach (unowned AURPackage aur_pkg in updates.ignored_aur_updates) {
					emit_script_output ("%s: %s".printf (
										dgettext (null, "Warning"),
										dgettext ("libalpm", "%s: ignoring package upgrade (%s => %s)\n").printf (
												aur_pkg.name, aur_pkg.installed_version, aur_pkg.version)).replace ("\n", ""));
				}
			}
			if (to_build.length > 0) {
				bool success = yield compute_aur_build_list ();
				if (!success) {
					return false;
				}
			}
			return yield trans_prepare_and_run ();
		}

		async bool trans_prepare_and_run () {
			// check if we need to sysupgrade
			if (!sysupgrading && !config.simple_install && to_install.length > 0) {
				foreach (unowned string name in to_install) {
					if (database.is_installed_pkg (name)) {
						if (database.is_sync_pkg (name)) {
							Package? local_pkg = database.get_installed_pkg (name);
							Package? sync_pkg = database.get_sync_pkg (name);
							if (local_pkg.version != sync_pkg.version) {
								sysupgrading = true;
								break;
							}
						}
					} else {
						sysupgrading = true;
						break;
					}
				}
			}
			bool success = false;
			if (sysupgrading) {
				success = yield get_authorization_async ();
				if (!success) {
					return false;
				}
				try {
					success = yield transaction_interface.trans_refresh (force_refresh);
				} catch (Error e) {
					emit_error ("Daemon Error", {"trans_refresh: %s".printf (e.message)});
				}
				if (!success) {
					return false;
				}
			}
			TransactionSummary summary;
			success = yield trans_prepare (out summary);
			if (success) {
				success = yield trans_run (summary);
			}
			return success;
		}

		async bool trans_check_prepare (bool sysupgrade,
										bool enable_downgrade,
										bool simple_install,
										int trans_flags,
										GenericSet<string?> to_install,
										GenericSet<string?> to_remove,
										GenericSet<string?> to_load,
										GenericSet<string?> to_build,
										GenericSet<string?> ignorepkgs,
										GenericSet<string?> overwrite_files,
										out TransactionSummary summary) {
			bool success = false;
			var new_summary = new TransactionSummary ();
			try {
				new Thread<int>.try ("trans_check_prepare", () => {
					success = alpm_utils.trans_check_prepare (sysupgrade,
															enable_downgrade,
															simple_install,
															trans_flags,
															to_install,
															to_remove,
															to_load,
															to_build,
															ignorepkgs,
															overwrite_files,
															ref new_summary);
					context.invoke (trans_check_prepare.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			summary = new_summary;
			return success;
		}

		async bool trans_prepare (out TransactionSummary summary) {
			// download urls provided in to_load if we are not root
			if (to_load.length > 0 && Posix.geteuid () != 0) {
				var to_load_real = new GenericSet<string?> (str_hash, str_equal);
				foreach (unowned string path in to_load) {
					if ("://" in path) {
						bool success = yield get_authorization_async ();
						if (!success) {
							summary = new TransactionSummary ();
							return false;
						}
						try {
							string downloaded_path = yield transaction_interface.download_pkg (path);
							if (downloaded_path != "") {
								to_load_real.add ((owned) downloaded_path);
							} else {
								summary = new TransactionSummary ();
								return false;
							}
						} catch (Error e) {
							emit_error ("Daemon Error", {"download_pkg: %s".printf (e.message)});
							summary = new TransactionSummary ();
							return false;
						}
					} else {
						to_load_real.add (path);
					}
				}
				to_load = (owned) to_load_real;
			}
			start_preparing ();
			add_config_ignore_pkgs ();
			bool success = yield trans_check_prepare (sysupgrading,
													config.enable_downgrade,
													config.simple_install,
													trans_flags,
													to_install,
													to_remove,
													to_load,
													to_build,
													ignorepkgs,
													overwrite_files,
													out summary);
			stop_preparing ();
			if (!success) {
				if (to_build.length > 0) {
					var empty_summary = new TransactionSummary ();
					if (yield ask_edit_build_files_real (empty_summary)) {
						foreach (unowned string name in to_build) {
							// unresolvables declared in alpm_utils.vala
							// it can be null
							if (unresolvables == null) {
								unresolvables = new GenericArray<string> ();
							}
							bool found = unresolvables.find_with_equal_func (name, str_equal, null);
							if (!found) {
								unresolvables.add (name);
							}
						}
						foreach (unowned string pkgname in unresolvables) {
							string pkgdir;
							bool as_root = Posix.geteuid () == 0;
							if (as_root) {
								// build as root with systemd-run
								// set aur_build_dir to "/var/cache/pamac"
								pkgdir = Path.build_filename ("/var/cache/pamac", pkgname);
							} else if (config.aur_build_dir == "/var/tmp" || config.aur_build_dir == "/tmp") {
								pkgdir = Path.build_filename (config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()), pkgname);
							} else {
								pkgdir = Path.build_filename (config.aur_build_dir, pkgname);
							}
							success = yield clone_build_files_if_needed (pkgdir, pkgname);
							if (!success) {
								emit_error (dgettext (null, "Failed to prepare transaction"), {dgettext (null, "Failed to clone %s build files").printf (pkgname)});
								unresolvables = new GenericArray<string> ();
								return false;
							}
						}
						yield edit_build_files (unresolvables.data);
						unresolvables = new GenericArray<string> ();
						emit_script_output ("");
						bool clone_build_files_old = clone_build_files;
						clone_build_files = false;
						success = yield compute_aur_build_list ();
						clone_build_files = clone_build_files_old;
						if (!success) {
							return false;
						}
						success = yield trans_prepare (out summary);
					} else {
						emit_action (dgettext (null, "Transaction cancelled") + ".");
					}
				}
			}
			return success;
		}

		async bool trans_run (TransactionSummary summary) {
			if (summary.aur_pkgbases_to_build.length != 0) {
				if (yield ask_edit_build_files_real (summary)) {
					foreach (unowned string pkgname in summary.aur_pkgbases_to_build) {
						string pkgdir;
						bool as_root = Posix.geteuid () == 0;
						if (as_root) {
							// build as root with systemd-run
							// set aur_build_dir to "/var/cache/pamac"
							pkgdir = Path.build_filename ("/var/cache/pamac", pkgname);
						} else if (config.aur_build_dir == "/var/tmp" || config.aur_build_dir == "/tmp") {
							pkgdir = Path.build_filename (config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()), pkgname);
						} else {
							pkgdir = Path.build_filename (config.aur_build_dir, pkgname);
						}
						bool success = yield clone_build_files_if_needed (pkgdir, pkgname);
						if (!success) {
							emit_error (dgettext (null, "Failed to prepare transaction"), {dgettext (null, "Failed to clone %s build files").printf (pkgname)});
							return false;
						}
					}
					yield edit_build_files (summary.aur_pkgbases_to_build.data);
					emit_script_output ("");
					bool clone_build_files_old = clone_build_files;
					clone_build_files = false;
					bool success = yield compute_aur_build_list ();
					clone_build_files = clone_build_files_old;
					TransactionSummary new_summary;
					success = yield trans_prepare (out new_summary);
					if (success) {
						return yield trans_run (new_summary);
					}
				}
			}
			if (summary.to_install.length != 0 ||
				summary.to_upgrade.length != 0 ||
				summary.to_downgrade.length != 0 ||
				summary.to_reinstall.length != 0 ||
				summary.conflicts_to_remove.length != 0 ||
				summary.to_remove.length != 0) {
				foreach (unowned Package pkg in summary.to_install) {
					if (!to_install.contains (pkg.name) &&
						!summary.to_load.find_with_equal_func (pkg.name, str_equal)) {
						to_install.add (pkg.name);
						to_install_as_dep.add (pkg.name);
					}
				}
				to_remove.remove_all ();
				foreach (unowned Package pkg in summary.to_remove) {
					to_remove.add (pkg.name);
				}
				// ask_commit_real add flatpaks and snaps
				if (yield ask_commit_real (summary)) {
					var to_install_array = new GenericArray<string> (to_install.length);
					var to_remove_array = new GenericArray<string> (to_remove.length);
					var to_load_array = new GenericArray<string> (to_load.length);
					var to_install_as_dep_array = new GenericArray<string> (to_install_as_dep.length);
					var ignorepkgs_array = new GenericArray<string> (ignorepkgs.length);
					var overwrite_files_array = new GenericArray<string> (overwrite_files.length);
					foreach (unowned string name in to_install) {
						to_install_array.add (name);
					}
					foreach (unowned string name in to_remove) {
						to_remove_array.add (name);
					}
					foreach (unowned string name in to_load) {
						to_load_array.add (name);
					}
					foreach (unowned string name in to_install_as_dep) {
						to_install_as_dep_array.add (name);
					}
					foreach (unowned string name in ignorepkgs) {
						ignorepkgs_array.add (name);
					}
					foreach (unowned string name in overwrite_files) {
						overwrite_files_array.add (name);
					}
					bool success = false;
					try {
						success = yield transaction_interface.trans_run (sysupgrading,
																	config.enable_downgrade,
																	config.simple_install,
																	config.keep_built_pkgs,
																	trans_flags,
																	to_install_array.data,
																	to_remove_array.data,
																	to_load_array.data,
																	to_install_as_dep_array.data,
																	ignorepkgs_array.data,
																	overwrite_files_array.data);
					} catch (Error e) {
						emit_error ("Daemon Error", {"trans_run: %s".printf (e.message)});
		 			}
		 			return success;
				} else {
					emit_action (dgettext (null, "Transaction cancelled") + ".");
					return false;
				}
			} else if (summary.to_build.length != 0) {
				// only AUR packages to build
				if (yield ask_commit_real (summary)) {
					// get_authorization here before building
					return yield get_authorization_async ();
				} else {
					emit_action (dgettext (null, "Transaction cancelled") + ".");
					return false;
				}
			} else {
				emit_action (dgettext (null, "Nothing to do") + ".");
				return true;
			}
		}

		public void set_flags (int flags) {
			trans_flags = flags;
		}

		public void add_pkg_to_install (string name) {
			to_install.add (name);
		}

		public void add_pkg_to_remove (string name) {
			to_remove.add (name);
		}

		public void add_path_to_load (string path) {
			to_load.add (path);
		}

		public void add_aur_pkg_to_build (string name) {
			to_build.add (name);
		}

		public void add_temporary_ignore_pkg (string name) {
			ignorepkgs.add (name);
		}

		public void add_overwrite_file (string glob) {
			overwrite_files.add (glob);
		}

		public void add_pkg_to_mark_as_dep (string name) {
			to_install_as_dep.add (name);
		}

		public void add_pkgs_to_upgrade (bool force_refresh) {
			this.force_refresh = force_refresh;
			sysupgrading = true;
		}

		public void add_snap_to_install (SnapPackage pkg) {
			if (config.enable_snap) {
				snap_to_install.insert (pkg.name, pkg);
			} else {
				warning ("snap support disabled");
			}
		}

		public void add_snap_to_remove (SnapPackage pkg) {
			if (config.enable_snap) {
				snap_to_remove.insert (pkg.name, pkg);
			} else {
				warning ("snap support disabled");
			}
		}

		async bool run_snap_transaction () {
			var snap_to_install_array = new GenericArray<string> (snap_to_install.length);
			var snap_to_remove_array = new GenericArray<string> (snap_to_remove.length);
			var iter = HashTableIter<string, SnapPackage> (snap_to_install);
			unowned string name;
			while (iter.next (out name, null)) {
				snap_to_install_array.add (name);
			}
			iter = HashTableIter<string, SnapPackage> (snap_to_remove);
			while (iter.next (out name, null)) {
				snap_to_remove_array.add (name);
			}
			snap_to_install.remove_all ();
			snap_to_remove.remove_all ();
			try {
				// emit download signal to allow cancellation
				start_downloading ();
				bool success = yield transaction_interface.snap_trans_run (snap_to_install_array.data, snap_to_remove_array.data);
				stop_downloading ();
				return success;
			} catch (Error e) {
				emit_error ("Daemon Error", {"snap_trans_run: %s".printf (e.message)});
				return false;
			}
		}

		public async bool snap_switch_channel_async (string snap_name, string channel) {
			if (config.enable_snap) {
				try {
					return yield transaction_interface.snap_switch_channel (snap_name, channel);
				} catch (Error e) {
					emit_error ("Daemon Error", {"snap_switch_channel: %s".printf (e.message)});
				}
			} else {
				warning ("snap support disabled");
			}
			return false;
		}

		public void add_flatpak_to_install (FlatpakPackage pkg) {
			if (config.enable_flatpak) {
				flatpak_to_install.insert (pkg.id, pkg);
			} else {
				warning ("flatpak support disabled");
			}
		}

		public void add_flatpak_to_remove (FlatpakPackage pkg) {
			if (config.enable_flatpak) {
				flatpak_to_remove.insert (pkg.id, pkg);
			} else {
				warning ("flatpak support disabled");
			}
		}

		public void add_flatpak_to_upgrade (FlatpakPackage pkg) {
			if (config.enable_flatpak) {
				flatpak_to_upgrade.insert (pkg.id, pkg);
			} else {
				warning ("flatpak support disabled");
			}
		}

		async bool run_flatpak_transaction () {
			var flatpak_to_install_array = new GenericArray<string> (flatpak_to_install.length);
			var flatpak_to_remove_array = new GenericArray<string> (flatpak_to_remove.length);
			var flatpak_to_upgrade_array = new GenericArray<string> (flatpak_to_upgrade.length);
			var iter = HashTableIter<string, FlatpakPackage> (flatpak_to_install);
			unowned string id;
			while (iter.next (out id, null)) {
				flatpak_to_install_array.add (id);
			}
			iter = HashTableIter<string, FlatpakPackage> (flatpak_to_remove);
			while (iter.next (out id, null)) {
				flatpak_to_remove_array.add (id);
			}
			iter = HashTableIter<string, FlatpakPackage> (flatpak_to_upgrade);
			while (iter.next (out id, null)) {
				flatpak_to_upgrade_array.add (id);
			}
			flatpak_to_install.remove_all ();
			flatpak_to_remove.remove_all ();
			flatpak_to_upgrade.remove_all ();
			try {
				// emit download signal to allow cancellation
				start_downloading ();
				bool success = yield transaction_interface.flatpak_trans_run (flatpak_to_install_array.data,
																flatpak_to_remove_array.data,
																flatpak_to_upgrade_array.data);
				stop_downloading ();
				return success;
			} catch (Error e) {
				emit_error ("Daemon Error", {"flatpak_trans_run: %s".printf (e.message)});
				return false;
			}
		}

		string remove_bash_colors (string msg) {
			Regex regex = /\x1B\[[0-9;]*[JKmsu]/;
			try {
				return regex.replace (msg, -1, 0, "");
			} catch (Error e) {
				return msg;
			}
		}

		public async virtual int run_cmd_line_async (string[] args, string? working_directory, Cancellable cancellable) {
			int status = 1;
			var launcher = new SubprocessLauncher (SubprocessFlags.STDIN_INHERIT | SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
			if (working_directory != null) {
				launcher.set_cwd (working_directory);
			}
			launcher.set_environ (Environ.get ());
			try {
				Subprocess process = launcher.spawnv (args);
				var dis = new DataInputStream (process.get_stdout_pipe ());
				string? line;
				while ((line = yield dis.read_line_async ()) != null) {
					if (cancellable.is_cancelled ()) {
						break;
					}
					emit_script_output (remove_bash_colors (line));
				}
				if (cancellable.is_cancelled ()) {
					process.send_signal (Posix.Signal.INT);
					process.send_signal (Posix.Signal.KILL);
				}
				try {
					yield process.wait_async (cancellable);
					if (process.get_if_exited ()) {
						status = process.get_exit_status ();
					}
				} catch (Error e) {
					// cancelled
					process.send_signal (Posix.Signal.INT);
					process.send_signal (Posix.Signal.KILL);
				}
			} catch (Error e) {
				warning (e.message);
			}
			return status;
		}

		async bool build_aur_packages () {
			bool success = true;
			// get a fake aur db to check deps
			unowned Alpm.DB? aur_db = null;
			var tmp_handle = database.get_tmp_handle ();
			if (tmp_handle != null) {
				try {
					var process = new Subprocess.newv ({"cp", "%s/pamac_aur.db".printf (tmp_path), "%ssync".printf (tmp_handle.dbpath)}, SubprocessFlags.NONE);
					yield process.wait_async ();
					aur_db = tmp_handle.register_syncdb ("pamac_aur", 0);
					if (aur_db == null) {
						emit_warning (dgettext (null, "Failed to initialize AUR database"));
					}
				} catch (Error e) {
					warning (e.message);
				}
			}
			var built_pkgs = new HashTable<string, string> (str_hash, str_equal);
			var to_install_as_dep_array = new GenericArray<string> ();
			while (to_build_queue.length > 0) {
				string pkgname = to_build_queue.pop_head ();
				build_cancellable.reset ();
				emit_script_output ("");
				emit_action (dgettext (null, "Building %s").printf (pkgname) + "...");
				important_details_outpout (false);
				var built_pkgs_path = new GenericArray<string> ();
				string pkgdir;
				bool as_root = Posix.geteuid () == 0;
				if (as_root) {
					// build as root with systemd-run
					// set aur_build_dir to "/var/cache/pamac"
					pkgdir = Path.build_filename ("/var/cache/pamac", pkgname);
				} else if (config.aur_build_dir == "/var/tmp" || config.aur_build_dir == "/tmp") {
					pkgdir = Path.build_filename (config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()), pkgname);
				} else {
					pkgdir = Path.build_filename (config.aur_build_dir, pkgname);
				}
				success = yield clone_build_files_if_needed (pkgdir, pkgname);
				if (!success) {
					emit_error (dgettext (null, "Failed to build %s").printf (pkgname), {});
					to_build_queue.clear ();
					return false;
				}
				// building
				building = true;
				start_building ();
				string[] cmdline = {};
				if (as_root) {
					cmdline += "systemd-run";
					cmdline += "--service-type=oneshot";
					cmdline += "--pipe";
					cmdline += "--wait";
					cmdline += "--pty";
					cmdline += "--property=DynamicUser=yes";
					cmdline += "--property=CacheDirectory=pamac";
					cmdline += "--property=WorkingDirectory=/var/cache/pamac/%s".printf (pkgname);
				}
				cmdline += "makepkg";
				cmdline += "-cCf";
				if (!config.keep_built_pkgs) {
					cmdline += "--nosign";
					cmdline += "PKGDEST=%s".printf (pkgdir);
					cmdline += "PKGEXT=.pkg.tar";
				}
				important_details_outpout (false);
				int status = yield run_cmd_line_async (cmdline, pkgdir, build_cancellable);
				if (build_cancellable.is_cancelled ()) {
					status = 1;
				} else if (status == 1) {
					emit_error (dgettext (null, "Failed to build %s").printf (pkgname), {});
				}
				if (status == 0) {
					// get built pkgs path
					var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);
					launcher.set_cwd (pkgdir);
					try {
						cmdline = {};
						if (as_root) {
							cmdline += "systemd-run";
							cmdline += "--service-type=oneshot";
							cmdline += "--pipe";
							cmdline += "--wait";
							cmdline += "--pty";
							cmdline += "--property=DynamicUser=yes";
							cmdline += "--property=CacheDirectory=pamac";
							cmdline += "--property=WorkingDirectory=/var/cache/pamac/%s".printf (pkgname);
						}
						cmdline += "makepkg";
						cmdline += "--packagelist";
						if (!config.keep_built_pkgs) {
							cmdline += "PKGDEST=%s".printf (pkgdir);
							cmdline += "PKGEXT=.pkg.tar";
						}
						Subprocess process = launcher.spawnv (cmdline);
						yield process.wait_async ();
						if (process.get_if_exited ()) {
							status = process.get_exit_status ();
						}
						if (status == 0) {
							var dis = new DataInputStream (process.get_stdout_pipe ());
							string? line = null;
							while ((line = yield dis.read_line_async ()) != null) {
								var file = GLib.File.new_for_path (line);
								string filename = file.get_basename ();
								string? name_version_release = filename.slice (0, filename.last_index_of_char ('-'));
								if (name_version_release == null) {
									break;
								}
								string? name_version = name_version_release.slice (0, name_version_release.last_index_of_char ('-'));
								if (name_version == null) {
									break;
								}
								string? name = name_version.slice (0, name_version.last_index_of_char ('-'));
								if (name == null) {
									break;
								}
								if (name in aur_pkgs_to_install) {
									built_pkgs_path.add (line);
									built_pkgs.insert (name, line);
									if (!(name in to_build)) {
										to_install_as_dep_array.add (name);
									}
								}
							}
						}
					} catch (Error e) {
						warning (e.message);
						status = 1;
					}
				}
				stop_building ();
				building = false;
				if (status == 0 && built_pkgs_path.length > 0) {
					bool built_pkgs_needed = false;
					if (to_build_queue.length == 0) {
						// no more package to build
						built_pkgs_needed = true;
					} else if (aur_db == null) {
						// error, can't check deps
						built_pkgs_needed = true;
					} else {
						// check if built pkgs need to be installed
						// because next pkg to build depends on one of them
						unowned string next_pkg_name = to_build_queue.peek_head ();
						unowned Alpm.Package? next_pkg = aur_db.get_pkg (next_pkg_name);
						if (next_pkg == null) {
							// error
							built_pkgs_needed = true;
						} else {
							var iter = HashTableIter<string, string> (built_pkgs);
							unowned string built_pkg_name;
							unowned string built_pkg_path;
							while (iter.next (out built_pkg_name, out built_pkg_path)) {
								unowned Alpm.Package? built_pkg = aur_db.get_pkg (built_pkg_name);
								if (built_pkg == null) {
									// error
									built_pkgs_needed = true;
									break;
								}
								unowned Alpm.List<unowned Alpm.Depend> depends = next_pkg.depends;
								while (depends != null) {
									// check if built_pkg satisfy a dep of next_pkg
									Alpm.List<unowned Alpm.Package> list = null;
									list.add (built_pkg);
									if (Alpm.find_satisfier (list, depends.data.compute_string ()) != null) {
										built_pkgs_needed = true;
										break;
									}
									depends.next ();
								}
								if (built_pkgs_needed) {
									break;
								}
							}
						}
					}
					if (built_pkgs_needed) {
						var to_load_array = new GenericArray<string> ();
						var iter = HashTableIter<string, string> (built_pkgs);
						unowned string built_pkg_path;
						while (iter.next (null, out built_pkg_path)) {
							to_load_array.add (built_pkg_path);
						}
						success = yield install_built_pkgs (to_load_array, to_install_as_dep_array);
						if (!success) {
							break;
						}
						built_pkgs.remove_all ();
						to_install_as_dep_array = new GenericArray<string> ();
					}
				} else {
					important_details_outpout (true);
					to_build_queue.clear ();
					success = false;
					break;
				}
			}
			return success;
		}

		async bool install_built_pkgs (GenericArray<string> to_load_array, GenericArray<string> to_install_as_dep_array) {
			bool success = false;
			try {
				emit_script_output ("");
				success = yield transaction_interface.trans_run (false, // sysupgrading,
															false, // enable_downgrade
															false, // simple_install
															config.keep_built_pkgs,
															0, // trans_flags,
															{}, // to_install
															{}, // to_remove
															to_load_array.data,
															to_install_as_dep_array.data,
															{}, // ignorepkgs
															{}); // overwrite_files
			} catch (Error e) {
				emit_error ("Daemon Error", {"trans_run: %s".printf (e.message)});
				success = false;
			}
			return success;
		}

		public void cancel () {
			if (building) {
				build_cancellable.cancel ();
			} else if (waiting) {
				waiting = false;
			} else {
				try {
					transaction_interface.trans_cancel ();
				} catch (Error e) {
					emit_error ("Daemon Error", {"trans_cancel: %s".printf (e.message)});
				}
			}
		}

		int choose_provider_real (string depend, string[] providers) {
			string[] providers_copy = providers;
			int index = 0;
			var loop = new MainLoop (context);
			context.invoke (() => {
				choose_provider.begin (depend, providers_copy, (obj, res) => {
					index = choose_provider.end (res);
					loop.quit ();
				});
				return false;
			});
			loop.run ();
			unowned string pkgname = providers_copy[index];
			to_install.add (pkgname);
			to_install_as_dep.add (pkgname);
			return index;
		}

		async bool ask_commit_real (TransactionSummary summary) {
			if (build_cancellable.is_cancelled ()) {
				return false;
			} else {
				if (snap_to_install.length > 0) {
					// ask classic snaps
					var iter = HashTableIter<string, SnapPackage> (snap_to_install);
					var not_install = new GenericArray<unowned string> ();
					unowned string snap_name;
					SnapPackage pkg;
					while (iter.next (out snap_name, out pkg)) {
						if (pkg.confined != dgettext (null, "Yes")) {
							bool answser = yield ask_snap_install_classic (pkg.app_name);
							if (!answser) {
								not_install.add (snap_name);
							}
						}
					}
					foreach (unowned string name in not_install) {
						snap_to_install.remove (name);
					}
				}
				// add snaps to summary
				var snap_iter = HashTableIter<string, SnapPackage> (snap_to_install);
				SnapPackage snap_pkg;
				while (snap_iter.next (null, out snap_pkg)) {
					summary.to_install.add (snap_pkg);
				}
				snap_iter = HashTableIter<string, SnapPackage> (snap_to_remove);
				while (snap_iter.next (null, out snap_pkg)) {
					summary.to_remove.add (snap_pkg);
				}
				// add flatpaks to summary
				var flatpak_iter = HashTableIter<string, FlatpakPackage> (flatpak_to_install);
				FlatpakPackage flatpak_pkg;
				while (flatpak_iter.next (null, out flatpak_pkg)) {
					summary.to_install.add (flatpak_pkg);
				}
				flatpak_iter = HashTableIter<string, FlatpakPackage> (flatpak_to_remove);
				while (flatpak_iter.next (null, out flatpak_pkg)) {
					summary.to_remove.add (flatpak_pkg);
				}
				flatpak_iter = HashTableIter<string, FlatpakPackage> (flatpak_to_upgrade);
				while (flatpak_iter.next (null, out flatpak_pkg)) {
					summary.to_upgrade.add (flatpak_pkg);
				}
				return yield ask_commit (summary);
			}
		}

		async bool ask_edit_build_files_real (TransactionSummary summary) {
			var iter = HashTableIter<string, SnapPackage> (snap_to_install);
			SnapPackage pkg;
			while (iter.next (null, out pkg)) {
				summary.to_install.add (pkg);
			}
			iter = HashTableIter<string, SnapPackage> (snap_to_remove);
			while (iter.next (null, out pkg)) {
				summary.to_remove.add (pkg);
			}
			// populate build queue
			to_build_queue.clear ();
			foreach (unowned string name in summary.aur_pkgbases_to_build) {
				to_build_queue.push_tail (name);
			}
			aur_pkgs_to_install.remove_all ();
			foreach (unowned Package build_pkg in summary.to_build) {
				aur_pkgs_to_install.add (build_pkg.name);
			}
			return yield ask_edit_build_files (summary);
		}

		void on_emit_action (string action) {
			emit_action (action);
		}

		void on_emit_action_progress (string action, string status, double progress) {
			emit_action_progress (action, status, progress);
		}

		void on_emit_download_progress (string action, string status, double progress) {
			emit_download_progress (action, status, progress);
		}

		void on_emit_hook_progress (string action, string details, string status, double progress) {
			emit_hook_progress (action, details, status, progress);
		}

		void on_emit_script_output (string message) {
			emit_script_output (message);
		}

		void on_emit_warning (string message) {
			emit_warning (message);
		}

		void on_emit_error (string message, string[] details) {
			emit_error (message, details);
		}

		void on_important_details_outpout (bool must_show) {
			important_details_outpout (must_show);
		}

		void on_start_downloading () {
			start_downloading ();
		}

		void on_stop_downloading () {
			stop_downloading ();
		}

		void on_start_waiting () {
			start_waiting ();
		}

		void on_stop_waiting () {
			stop_waiting ();
		}

		void connecting_signals () {
			transaction_interface.emit_action.connect (on_emit_action);
			transaction_interface.emit_action_progress.connect (on_emit_action_progress);
			transaction_interface.emit_download_progress.connect (on_emit_download_progress);
			transaction_interface.emit_hook_progress.connect (on_emit_hook_progress);
			transaction_interface.emit_script_output.connect (on_emit_script_output);
			transaction_interface.emit_warning.connect (on_emit_warning);
			transaction_interface.emit_error.connect (on_emit_error);
			transaction_interface.important_details_outpout.connect (on_important_details_outpout);
			transaction_interface.start_downloading.connect (on_start_downloading);
			transaction_interface.stop_downloading.connect (on_stop_downloading);
			transaction_interface.start_waiting.connect (on_start_waiting);
			transaction_interface.stop_waiting.connect (on_stop_waiting);
		}
	}
}
