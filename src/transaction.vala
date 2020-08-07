/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2020 Guillaume Benoit <guillaume@manjaro.org>
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
		MainContext context;
		protected MainLoop loop;
		// run transaction data
		bool sysupgrading;
		bool force_refresh;
		int trans_flags;
		GenericSet<string?> to_install;
		GenericSet<string?> to_remove;
		GenericSet<string?> to_load;
		GenericSet<string?> to_build;
		GenericSet<string?> temporary_ignorepkgs;
		GenericSet<string?> overwrite_files;
		GenericSet<string?> to_install_as_dep;
		#if ENABLE_SNAP
		HashTable<string, SnapPackage> snap_to_install;
		HashTable<string, SnapPackage> snap_to_remove;
		#endif
		#if ENABLE_FLATPAK
		HashTable<string, FlatpakPackage> flatpak_to_install;
		HashTable<string, FlatpakPackage> flatpak_to_remove;
		HashTable<string, FlatpakPackage> flatpak_to_upgrade;
		#endif
		// building data
		string tmp_path;
		string aurdb_path;
		GenericSet<string?> already_checked_aur_dep;
		GenericSet<string?> aur_desc_list;
		Queue<string> to_build_queue;
		GenericSet<string?> aur_pkgs_to_install;
		SList<AURPackage> aur_updates;
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
			context = MainContext.ref_thread_default ();
			loop = new MainLoop (context);
			if (Posix.geteuid () == 0) {
				// we are root
				transaction_interface = new TransactionInterfaceRoot (loop);
			} else {
				// use dbus daemon
				transaction_interface = new TransactionInterfaceDaemon (database.config, loop);
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
			temporary_ignorepkgs = new GenericSet<string?> (str_hash, str_equal);
			overwrite_files = new GenericSet<string?> (str_hash, str_equal);
			to_install_as_dep = new GenericSet<string?> (str_hash, str_equal);
			// alpm_utils global variable declared in alpm_utils.vala
			alpm_utils = new AlpmUtils (database.config, context);
			alpm_utils.choose_provider.connect (choose_provider_real);
			alpm_utils.emit_action.connect ((sender, action) => {
				emit_action (action);
			});
			alpm_utils.emit_action_progress.connect ((sender, action, status, progress) => {
				emit_action_progress (action, status, progress);
			});
			alpm_utils.emit_hook_progress.connect ((sender, action, details, status, progress) => {
				emit_hook_progress (action, details, status, progress);
			});
			alpm_utils.emit_download_progress.connect ((sender, action, status, progress) => {
				emit_download_progress (action, status, progress);
			});
			alpm_utils.start_downloading.connect ((sender) => {
				start_downloading ();
			});
			alpm_utils.stop_downloading.connect ((sender) => {
				stop_downloading ();
			});
			alpm_utils.emit_script_output.connect ((sender, message) => {
				emit_script_output (message);
			});
			alpm_utils.emit_warning.connect ((sender, message) => {
				emit_warning (message);
			});
			alpm_utils.emit_error.connect ((sender, message, details) => {
				emit_error (message, details);
			});
			alpm_utils.important_details_outpout.connect ((sender, must_show) => {
				important_details_outpout (must_show);
			});
			// only used as root in transaction_interface_root.vala
			alpm_utils.get_authorization.connect ((sender) => {
				if (Posix.geteuid () == 0) {
					return true;
				}
				return false;
			});
			#if ENABLE_SNAP
			snap_to_install = new HashTable<string, SnapPackage> (str_hash, str_equal);
			snap_to_remove = new HashTable<string, SnapPackage> (str_hash, str_equal);
			#endif
			#if ENABLE_FLATPAK
			flatpak_to_install = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			flatpak_to_remove = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			flatpak_to_upgrade = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			#endif
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

		protected virtual bool ask_commit (TransactionSummary summary) {
			// no confirm
			return true;
		}

		protected virtual bool ask_edit_build_files (TransactionSummary summary) {
			// no edit
			return false;
		}

		protected virtual void edit_build_files (string[] pkgnames) {
			// do nothing
		}

		protected virtual bool ask_import_key (string pkgname, string key, string owner) {
			// no import
			return false;
		}

		protected async GenericArray<string> get_build_files (string pkgname) {
			string pkgdir_name;
			if (database.config.aur_build_dir == "/var/tmp") {
				pkgdir_name = Path.build_path ("/", database.config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()), pkgname);
			} else {
				pkgdir_name = Path.build_path ("/", database.config.aur_build_dir, "pamac-build", pkgname);
			}
			var files = new GenericArray<string> ();
			// PKGBUILD
			files.add (Path.build_path ("/", pkgdir_name, "PKGBUILD"));
			var srcinfo = File.new_for_path (Path.build_path ("/", pkgdir_name, ".SRCINFO"));
			try {
				// read .SRCINFO
				var dis = new DataInputStream (yield srcinfo.read_async ());
				string line;
				while ((line = yield dis.read_line_async ()) != null) {
					if ("source = " in line) {
						string source = line.split (" = ", 2)[1];
						if (!("://" in source)) {
							string source_path = Path.build_path ("/", pkgdir_name, source);
							var source_file = File.new_for_path (source_path);
							if (source_file.query_exists ()) {
								files.add ((owned) source_path);
							}
						}
					} else if ("install = " in line) {
						string install = line.split (" = ", 2)[1];
						string install_path = Path.build_path ("/", pkgdir_name, install);
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

		protected virtual string[] choose_optdeps (string pkgname, string[] optdeps) {
			// do not install optdeps
			return {};
		}

		protected virtual int choose_provider (string depend, string[] providers) {
			// choose first provider
			return 0;
		}

		#if ENABLE_SNAP
		protected virtual bool ask_snap_install_classic (string name) {
			// do not install
			return false;
		}
		#endif

		public bool get_authorization () {
			try {
				return transaction_interface.get_authorization ();
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

		public void generate_mirrors_list (string country) {
			emit_action (dgettext (null, "Refreshing mirrors list") + "...");
			important_details_outpout (false);
			transaction_interface.generate_mirrors_list_data.connect (on_generate_mirrors_list_data);
			try {
				transaction_interface.generate_mirrors_list (country);
			} catch (Error e) {
				emit_error ("Daemon Error", {"generate_mirrors_list: %s".printf (e.message)});
			}
			transaction_interface.generate_mirrors_list_data.disconnect (on_generate_mirrors_list_data);
			database.refresh ();
		}

		void on_generate_mirrors_list_data (string line) {
			emit_script_output (line);
		}

		public void clean_cache () {
			HashTable<string, uint64?> details = database.get_clean_cache_details ();
			var iter = HashTableIter<string, uint64?> (details);
			var array = new GenericArray<string> (details.length);
			unowned string name;
			while (iter.next (out name, null)) {
				array.add (name);
			}
			try {
				transaction_interface.clean_cache (array.data);
			} catch (Error e) {
				emit_error ("Daemon Error", {"clean_cache: %s".printf (e.message)});
			}
		}

		public void clean_build_files () {
			string real_aur_build_dir;
			if (database.config.aur_build_dir == "/var/tmp") {
				real_aur_build_dir = Path.build_path ("/", database.config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()));
			} else {
				real_aur_build_dir = Path.build_path ("/", database.config.aur_build_dir, "pamac-build");
			}
			try {
				transaction_interface.clean_build_files (real_aur_build_dir);
			} catch (Error e) {
				emit_error ("Daemon Error", {"clean_build_files: %s".printf (e.message)});
			}
			// recreate buildir here to have good permissions
			try {
				Process.spawn_command_line_sync ("mkdir -p %s".printf (database.config.aur_build_dir));
			} catch (SpawnError e) {
				emit_error ("SpawnError: %s".printf (e.message), {});
			}
		}

		public bool set_pkgreason (string pkgname, uint reason) {
			bool success = false;
			try {
				success = transaction_interface.set_pkgreason (pkgname, reason);
			} catch (Error e) {
				emit_error ("Daemon Error", {"set_pkgreason: %s".printf (e.message)});
			}
			database.refresh ();
			return success;
		}

		public void download_updates () {
			try {
				transaction_interface.download_updates ();
			} catch (Error e) {
				emit_error ("Daemon Error", {"download_updates: %s".printf (e.message)});
			}
		}

		bool compute_aur_build_list () {
			// set building to allow cancellation
			building = true;
			build_cancellable.reset ();
			start_building ();
			bool success = compute_aur_build_list_real ();
			stop_building ();
			building = false;
			if (build_cancellable.is_cancelled ()) {
				emit_script_output ("");
				emit_action (dgettext (null, "Transaction cancelled") + ".");
			}
			return success;
		}

		int launch_subprocess (string[] cmds) {
			int status = 1;
			try {
				var process = new Subprocess.newv (cmds, SubprocessFlags.NONE);
				process.wait ();
				if (process.get_if_exited ()) {
					status = process.get_exit_status ();
				}
			} catch (Error e) {
				emit_error (dgettext (null, "Failed to prepare transaction"), {e.message});
			}
			return status;
		}

		bool compute_aur_build_list_real () {
			var file = GLib.File.new_for_path (tmp_path);
			if (!file.query_exists ()) {
				launch_subprocess ({"mkdir", "-p", tmp_path});
				launch_subprocess ({"chmod", "a+w", tmp_path});
			}
			launch_subprocess ({"mkdir", "-p", aurdb_path});
			aur_desc_list.remove_all ();
			already_checked_aur_dep.remove_all ();
			var to_build_array = new GenericArray<string> ();
			foreach (unowned string pkgname in to_build) {
				to_build_array.add (pkgname);
			}
			foreach (unowned AURPackage aur_update in aur_updates) {
				to_build_array.add (aur_update.name);
			}
			if (!check_aur_dep_list (to_build_array.data)) {
				return false;
			}
			if (aur_desc_list.length > 0) {
				// create a fake aur db
				launch_subprocess ({"rm", "-f", "%s/pamac_aur.db".printf (tmp_path)});
				string[] cmds = {"bsdtar", "-cf", "%s/pamac_aur.db".printf (tmp_path), "-C", aurdb_path};
				foreach (unowned string name_version in aur_desc_list) {
					cmds += name_version;
				}
				if (launch_subprocess (cmds) != 0) {
					return false;
				}
			}
			return true;
		}

		bool check_aur_dep_list (string[] pkgnames) {
			var dep_to_check = new GenericArray<string> ();
			var aur_pkgs = new HashTable<string, AURPackage?> (str_hash, str_equal);
			if (clone_build_files) {
				aur_pkgs = database.get_aur_pkgs (pkgnames);
			}
			foreach (unowned string pkgname in pkgnames) {
				if (build_cancellable.is_cancelled ()) {
					return false;
				}
				if (already_checked_aur_dep.contains (pkgname)) {
					continue;
				}
				File? clone_dir;
				if (clone_build_files) {
					unowned AURPackage? aur_pkg = aur_pkgs.lookup (pkgname);
					if (aur_pkg == null) {
						// may be a virtual package
						// use search and add results
						foreach (unowned AURPackage found_pkg in database.search_aur_pkgs (pkgname)) {
							dep_to_check.add (found_pkg.name);
						}
						already_checked_aur_dep.add (pkgname);
						// make this error not fatal to propose to edit build files
						continue;
					}
					// clone build files
					// use packagebase in case of split package
					emit_action (dgettext (null, "Cloning %s build files").printf (aur_pkg.packagebase) + "...");
					clone_dir = database.clone_build_files (aur_pkg.packagebase, false, build_cancellable);
					if (build_cancellable.is_cancelled ()) {
						return false;
					}
					if (clone_dir == null) {
						// error
						emit_error (dgettext (null, "Failed to prepare transaction"), {dgettext (null, "Failed to clone %s build files").printf (aur_pkg.packagebase)});
						return false;
					}
					already_checked_aur_dep.add (aur_pkg.packagebase);
				} else {
					string real_aur_build_dir;
					if (database.config.aur_build_dir == "/var/tmp") {
						real_aur_build_dir = Path.build_path ("/", database.config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()));
					} else {
						real_aur_build_dir = Path.build_path ("/", database.config.aur_build_dir, "pamac-build");
					}
					clone_dir = File.new_for_path (Path.build_path ("/", real_aur_build_dir, pkgname));
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
					if (!(database.regenerate_srcinfo (pkgname, build_cancellable))) {
						// error
						emit_error (dgettext (null, "Failed to prepare transaction"), {dgettext (null, "Failed to generate %s information").printf (pkgname)});
						return false;
					}
				}
				if (build_cancellable.is_cancelled ()) {
					return false;
				}
				emit_action (dgettext (null, "Checking %s dependencies").printf (pkgname) + "...");
				var srcinfo = clone_dir.get_child (".SRCINFO");
				try {
					// read .SRCINFO
					var dis = new DataInputStream (srcinfo.read ());
					string? line;
					string current_section = "";
					bool current_section_is_pkgbase = true;
					var version = new StringBuilder ("");
					string pkgbase = "";
					string desc = "";
					string arch = Posix.utsname ().machine;
					var pkgnames_found = new GenericArray<string> ();
					var global_depends = new SList<string> ();
					var global_checkdepends = new GenericArray<string> ();
					var global_makedepends = new GenericArray<string> ();
					var global_conflicts = new SList<string> ();
					var global_provides = new SList<string> ();
					var global_replaces = new SList<string> ();
					var global_validpgpkeys = new GenericArray<string> ();
					var pkgnames_table = new HashTable<string, AURPackage> (str_hash, str_equal);
					while ((line = dis.read_line ()) != null) {
						if ("pkgbase = " in line) {
							pkgbase = line.split (" = ", 2)[1];
						} else if ("pkgdesc = " in line) {
							desc = line.split (" = ", 2)[1];
							if (!current_section_is_pkgbase) {
								unowned AURPackage? aur_pkg = pkgnames_table.get (current_section);
								if (aur_pkg != null) {
									aur_pkg.desc = desc;
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
										global_depends.prepend ((owned) depend);
									}
								} else {
									unowned AURPackage? aur_pkg = pkgnames_table.get (current_section);
									if (aur_pkg != null) {
										aur_pkg.depends_priv.prepend ((owned) depend);
									}
								}
							}
						} else if ("provides" in line) {
							if ("provides = " in line || "provides_%s = ".printf (arch) in line) {
								string provide = line.split (" = ", 2)[1];
								if (current_section_is_pkgbase) {
									global_provides.prepend ((owned) provide);
								} else {
									unowned AURPackage? aur_pkg = pkgnames_table.get (current_section);
									if (aur_pkg != null) {
										aur_pkg.provides_priv.prepend ((owned) provide);
									}
								}
							}
						} else if ("conflicts" in line) {
							if ("conflicts = " in line || "conflicts_%s = ".printf (arch) in line) {
								string conflict = line.split (" = ", 2)[1];
								if (current_section_is_pkgbase) {
									global_conflicts.prepend ((owned) conflict);
								} else {
									unowned AURPackage? aur_pkg = pkgnames_table.get (current_section);
									if (aur_pkg != null) {
										aur_pkg.conflicts_priv.prepend ((owned) conflict);
									}
								}
							}
						} else if ("replaces" in line) {
							if ("replaces = " in line || "replaces_%s = ".printf (arch) in line) {
								string replace = line.split (" = ", 2)[1];
								if (current_section_is_pkgbase) {
									global_replaces.prepend ((owned) replace);
								} else {
									unowned AURPackage? aur_pkg = pkgnames_table.get (current_section);
									if (aur_pkg != null) {
										aur_pkg.replaces_priv.prepend ((owned) replace);
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
								var aur_pkg = new AURPackage ();
								aur_pkg.name = pkgname_found;
								aur_pkg.version = version.str;
								aur_pkg.desc = desc;
								aur_pkg.packagebase = pkgbase;
								pkgnames_table.insert (pkgname_found, aur_pkg);
								pkgnames_found.add ((owned) pkgname_found);
							}
						}
					}
					uint i;
					for (i = 0; i < pkgnames_found.length; i++) {
						already_checked_aur_dep.add (pkgnames_found[i]);
					}
					// create fake aur db entries
					for (i = 0; i < pkgnames_found.length; i++) {
						unowned string pkgname_found = pkgnames_found[i];
						unowned AURPackage? aur_pkg = pkgnames_table.get (pkgname_found);
						// populate empty list will global ones
						if (global_depends != null && aur_pkg.depends == null) {
							aur_pkg.depends_priv = (owned) global_depends;
						}
						if (global_provides != null && aur_pkg.provides == null) {
							aur_pkg.provides_priv = (owned) global_provides;
						}
						if (global_conflicts != null && aur_pkg.conflicts == null) {
							aur_pkg.conflicts_priv = (owned) global_conflicts;
						}
						if (global_replaces != null && aur_pkg.replaces == null) {
							aur_pkg.replaces_priv = (owned) global_replaces;
						}
						// add checkdepends and makedepends in depends
						uint j;
						for (j = 0; j < global_checkdepends.length; j++) {
							aur_pkg.depends_priv.prepend (global_checkdepends[j]);
						}
						for (j = 0; j < global_makedepends.length; j++) {
							aur_pkg.depends_priv.prepend (global_makedepends[j]);
						}
						// check deps
						foreach (unowned string dep_string in aur_pkg.depends) {
							Package? pkg = null;
							if (database.has_installed_satisfier (dep_string)) {
								pkg = database.get_installed_satisfier (dep_string);
							} else if (database.has_sync_satisfier (dep_string)) {
								pkg = database.get_sync_satisfier (dep_string);
							}
							if (pkg == null) {
								string dep_name = database.get_alpm_dep_name (dep_string);
								if (!(dep_name in already_checked_aur_dep)) {
									dep_to_check.add ((owned) dep_name);
								}
							}
						}
						// write desc file
						string pkgdir = "%s-%s".printf (pkgname_found, aur_pkg.version);
						string pkgdir_path = "%s/%s".printf (aurdb_path, pkgdir);
						aur_desc_list.add (pkgdir);
						var file = GLib.File.new_for_path (pkgdir_path);
						if (!file.query_exists ()) {
							file.make_directory ();
						}
						file = GLib.File.new_for_path ("%s/desc".printf (pkgdir_path));
						FileOutputStream fos;
						// always recreate desc in case of .SRCINFO modifications
						if (file.query_exists ()) {
							fos = file.replace (null, false, FileCreateFlags.NONE);
						} else {
							fos = file.create (FileCreateFlags.NONE);
						}
						// creating a DataOutputStream to the file
						var dos = new DataOutputStream (fos);
						// fake filename
						dos.put_string ("%FILENAME%\n" + "%s-%s-any.pkg.tar\n\n".printf (pkgname_found, aur_pkg.version));
						// name
						dos.put_string ("%NAME%\n%s\n\n".printf (pkgname_found));
						// version
						dos.put_string ("%VERSION%\n%s\n\n".printf (aur_pkg.version));
						// base
						dos.put_string ("%BASE%\n%s\n\n".printf (aur_pkg.packagebase));
						// desc
						dos.put_string ("%DESC%\n%s\n\n".printf (aur_pkg.desc));
						// arch (double %% before ARCH to escape %A)
						dos.put_string ("%%ARCH%\n%s\n\n".printf (arch));
						// depends
						if (aur_pkg.depends != null) {
							dos.put_string ("%DEPENDS%\n");
							foreach (unowned string name in aur_pkg.depends) {
								dos.put_string ("%s\n".printf (name));
							}
							dos.put_string ("\n");
						}
						// conflicts
						if (aur_pkg.conflicts != null) {
							dos.put_string ("%CONFLICTS%\n");
							foreach (unowned string name in aur_pkg.conflicts) {
								dos.put_string ("%s\n".printf (name));
							}
							dos.put_string ("\n");
						}
						// provides
						if (aur_pkg.provides != null) {
							dos.put_string ("%PROVIDES%\n");
							foreach (unowned string name in aur_pkg.provides) {
								dos.put_string ("%s\n".printf (name));
							}
							dos.put_string ("\n");
						}
						// replaces
						if (aur_pkg.replaces != null) {
							dos.put_string ("%REPLACES%\n");
							foreach (unowned string name in aur_pkg.replaces) {
								dos.put_string ("%s\n".printf (name));
							}
							dos.put_string ("\n");
						}
					}
					// check signature
					if (global_validpgpkeys.length > 0) {
						check_signature (pkgname, global_validpgpkeys);
					}
				} catch (Error e) {
					emit_error (dgettext (null, "Failed to prepare transaction"), {dgettext (null, "Failed to check %s dependencies").printf (pkgname)});
					return false;
				}
			}
			if (dep_to_check.length > 0) {
				return check_aur_dep_list (dep_to_check.data);
			}
			return true;
		}

		void check_signature (string pkgname, GenericArray<string> keys) {
			for (uint i = 0; i < keys.length; i++) {
				unowned string key = keys[i];
				var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
				try {
					var process = launcher.spawnv ({"gpg", "--with-colons", "--batch", "--list-keys", key});
					process.wait ();
					if (process.get_if_exited ()) {
						if (process.get_exit_status () != 0) {
							// key is not imported in keyring
							// try to get key infos
							launcher.set_flags (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
							process = launcher.spawnv ({"gpg", "--with-colons", "--batch", "--search-keys", key});
							process.wait ();
							if (process.get_if_exited ()) {
								if (process.get_exit_status () == 0) {
									var dis = new DataInputStream (process.get_stdout_pipe ());
									string? line;
									while ((line = dis.read_line ()) != null) {
										// get first uid line
										if ("uid:" in line) {
											string owner = line.split (":", 3)[1];
											if (ask_import_key (pkgname, key, owner)) {
												int status = run_cmd_line ({"gpg", "--with-colons", "--batch", "--recv-keys", key}, null, build_cancellable);
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

		public bool run () {
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
				success = run_alpm_transaction ();
				if (success) {
					if (to_build_queue.get_length () != 0) {
						success = build_aur_packages ();
						build_cancellable.reset ();
					}
					#if ENABLE_SNAP
					if (success) {
						if (snap_to_install.length > 0 ||
							snap_to_remove.length > 0) {
							success = run_snap_transaction ();
						}
					}
					#endif
					#if ENABLE_FLATPAK
					if (success) {
						if (flatpak_to_install.length > 0 ||
							flatpak_to_remove.length > 0 ||
							flatpak_to_upgrade.length > 0) {
							success = run_flatpak_transaction ();
						}
					}
					#endif
				}
				remove_authorization ();
				database.refresh ();
				if (success) {
					emit_action (dgettext (null, "Transaction successfully finished") + ".");
				} else {
					to_build_queue.clear ();
					#if ENABLE_SNAP
					snap_to_install.remove_all ();
					snap_to_remove.remove_all ();
					#endif
					#if ENABLE_FLATPAK
					flatpak_to_install.remove_all ();
					flatpak_to_remove.remove_all ();
					flatpak_to_upgrade.remove_all ();
					#endif
				}
				sysupgrading = false;
				force_refresh = false;
				to_install.remove_all ();
				to_remove.remove_all ();
				to_load.remove_all ();
				to_build.remove_all ();
				temporary_ignorepkgs.remove_all ();
				overwrite_files.remove_all ();
				to_install_as_dep.remove_all ();
			#if ENABLE_SNAP || ENABLE_FLATPAK
			} else {
			#endif
				#if ENABLE_SNAP
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
							if (!ask_snap_install_classic (pkg.app_name)) {
								not_install.add (snap_name);
							}
						}
					}
					for (uint i = 0; i < not_install.length; i++) {
						snap_to_install.remove (not_install[i]);
					}
					stop_preparing ();
				}
				#endif
				#if ENABLE_SNAP || ENABLE_FLATPAK
				// ask confirmation
				var summary = new TransactionSummary ();
				#endif
				#if ENABLE_SNAP
				if (snap_to_install.length > 0 ||
					snap_to_remove.length > 0) {
					start_preparing ();
					var iter = HashTableIter<string, SnapPackage> (snap_to_install);
					SnapPackage pkg;
					while (iter.next (null, out pkg)) {
						summary.to_install_priv.append (pkg);
					}
					iter = HashTableIter<string, SnapPackage> (snap_to_remove);
					while (iter.next (null, out pkg)) {
						summary.to_remove_priv.append (pkg);
					}
					stop_preparing ();
				}
				#endif
				#if ENABLE_FLATPAK
				if (flatpak_to_install.length > 0 ||
					flatpak_to_remove.length > 0 ||
					flatpak_to_upgrade.length > 0) {
					start_preparing ();
					var iter = HashTableIter<string, FlatpakPackage> (flatpak_to_install);
					FlatpakPackage pkg;
					while (iter.next (null, out pkg)) {
						summary.to_install_priv.append (pkg);
					}
					iter = HashTableIter<string, FlatpakPackage> (flatpak_to_remove);
					while (iter.next (null, out pkg)) {
						summary.to_remove_priv.append (pkg);
					}
					iter = HashTableIter<string, FlatpakPackage> (flatpak_to_upgrade);
					while (iter.next (null, out pkg)) {
						summary.to_upgrade_priv.append (pkg);
					}
					stop_preparing ();
				}
				#endif
				#if ENABLE_SNAP || ENABLE_FLATPAK
				if (summary.to_install_priv == null &&
					summary.to_remove_priv == null &&
					summary.to_upgrade_priv == null) {
					emit_action (dgettext (null, "Nothing to do") + ".");
					return false;
				} else if (ask_commit (summary)) {
				#endif
					#if ENABLE_SNAP
					if (snap_to_install.length > 0 ||
						snap_to_remove.length > 0) {
						success = run_snap_transaction ();
					}
					#endif
					#if ENABLE_FLATPAK
					if (flatpak_to_install.length > 0 ||
						flatpak_to_remove.length > 0 ||
						flatpak_to_upgrade.length > 0) {
						success = run_flatpak_transaction ();
					}
					#endif
					#if ENABLE_SNAP || ENABLE_FLATPAK
					if (success) {
						emit_action (dgettext (null, "Transaction successfully finished") + ".");
					}
					#endif
				#if ENABLE_SNAP || ENABLE_FLATPAK
				} else {
				#endif
					#if ENABLE_SNAP
					snap_to_install.remove_all ();
					snap_to_remove.remove_all ();
					#endif
					#if ENABLE_FLATPAK
					flatpak_to_install.remove_all ();
					flatpak_to_remove.remove_all ();
					flatpak_to_upgrade.remove_all ();
					#endif
					#if ENABLE_SNAP || ENABLE_FLATPAK
					stop_preparing ();
					emit_action (dgettext (null, "Transaction cancelled") + ".");
					success = false;
					#endif
				#if ENABLE_SNAP || ENABLE_FLATPAK
				}
				#endif
			}
			return success;
		}

		void add_optdeps () {
			var to_add_to_install = new GenericSet<string?> (str_hash, str_equal);
			foreach (unowned string name in to_install) {
				// do not check if reinstall
				if (!database.is_installed_pkg (name)) {
					SList<string> uninstalled_optdeps = database.get_uninstalled_optdeps (name);
					var real_uninstalled_optdeps = new GenericArray<unowned string> ();
					foreach (unowned string optdep in uninstalled_optdeps) {
						string[] splitted = optdep.split (": ", 2);
						unowned string optdep_name = splitted[0];
						if (!(optdep_name in to_install) && !(optdep_name in to_add_to_install)) {
							real_uninstalled_optdeps.add (optdep);
						}
					}
					if (real_uninstalled_optdeps.length > 0) {
						foreach (unowned string optdep in choose_optdeps (name, real_uninstalled_optdeps.data)) {
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

		bool run_alpm_transaction () {
			emit_action (dgettext (null, "Preparing") + "...");
			add_optdeps ();
			bool check_aur_updates = false;
			if (sysupgrading && database.config.check_aur_updates) {
				// add all aur updates with also ignored pkgs
				aur_updates = database.get_aur_updates (temporary_ignorepkgs);
				if (aur_updates != null) {
					check_aur_updates = true;
				}
			}
			bool success;
			if (to_build.length > 0 || check_aur_updates) {
				success = compute_aur_build_list ();
				aur_updates = new SList<AURPackage> ();
				if (!success) {
					return false;
				}
			}
			return trans_prepare_and_run (check_aur_updates);
		}

		bool trans_prepare_and_run (bool check_aur_updates) {
			// check if we need to sysupgrade
			if (!sysupgrading && !database.config.simple_install && to_install.length > 0) {
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
				success = get_authorization ();
				if (!success) {
					return false;
				}
				try {
					success = transaction_interface.trans_refresh (force_refresh);
				} catch (Error e) {
					emit_error ("Daemon Error", {"trans_refresh: %s".printf (e.message)});
				}
				if (!success) {
					return false;
				}
			}
			TransactionSummary summary;
			success = trans_prepare (check_aur_updates, out summary);
			if (success) {
				success = trans_run (check_aur_updates, summary);
			}
			return success;
		}

		bool trans_prepare (bool check_aur_updates, out TransactionSummary summary) {
			// download urls provided in to_load if we are not root
			if (to_load.length > 0 && Posix.geteuid () != 0) {
				var to_load_real = new GenericSet<string?> (str_hash, str_equal);
				foreach (unowned string path in to_load) {
					if ("://" in path) {
						if (!get_authorization ()) {
							summary = new TransactionSummary ();
							return false;
						}
						try {
							string downloaded_path = transaction_interface.download_pkg (path);
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
			bool success = alpm_utils.trans_check_prepare (sysupgrading,
													database.config.enable_downgrade,
													database.config.simple_install,
													check_aur_updates,
													trans_flags,
													to_install,
													to_remove,
													to_load,
													to_build,
													temporary_ignorepkgs,
													overwrite_files,
													out summary);
			stop_preparing ();
			if (!success) {
				if (to_build.length > 0) {
					var empty_summary = new TransactionSummary ();
					if (ask_edit_build_files_real (empty_summary)) {
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
						edit_build_files (unresolvables.data);
						unresolvables = new GenericArray<string> ();
						emit_script_output ("");
						if (!compute_aur_build_list ()) {
							return false;
						}
						success = trans_prepare (check_aur_updates, out summary);
					} else {
						emit_action (dgettext (null, "Transaction cancelled") + ".");
					}
				}
			}
			return success;
		}

		bool trans_run (bool check_aur_updates, TransactionSummary summary) {
			if (summary.aur_pkgbases_to_build != null) {
				if (ask_edit_build_files_real (summary)) {
					var build_files = new GenericArray<unowned string> (summary.aur_pkgbases_to_build.length ());
					foreach (unowned string name in summary.aur_pkgbases_to_build) {
						build_files.add (name);
					}
					edit_build_files (build_files.data);
					emit_script_output ("");
					if (!compute_aur_build_list ()) {
						return false;
					}
					TransactionSummary new_summary;
					bool success = trans_prepare (check_aur_updates, out new_summary);
					if (success) {
						return trans_run (check_aur_updates, new_summary);
					}
				}
			}
			if (summary.to_install != null ||
				summary.to_upgrade != null ||
				summary.to_downgrade != null ||
				summary.to_reinstall != null ||
				summary.conflicts_to_remove != null ||
				summary.to_remove != null) {
				foreach (unowned Package pkg in summary.to_install) {
					if (!to_install.contains (pkg.name) &&
						summary.to_load_priv.find_custom (pkg.name, strcmp) == null) {
						to_install.add (pkg.name);
						to_install_as_dep.add (pkg.name);
					}
				}
				to_remove.remove_all ();
				foreach (unowned Package pkg in summary.to_remove) {
					to_remove.add (pkg.name);
				}
				// ask_commit_real add flatpaks and snaps
				if (ask_commit_real (summary)) {
					var to_install_array = new GenericArray<string> (to_install.length);
					var to_remove_array = new GenericArray<string> (to_remove.length);
					var to_load_array = new GenericArray<string> (to_load.length);
					var to_install_as_dep_array = new GenericArray<string> (to_install_as_dep.length);
					var temporary_ignorepkgs_array = new GenericArray<string> (temporary_ignorepkgs.length);
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
					foreach (unowned string name in temporary_ignorepkgs) {
						temporary_ignorepkgs_array.add (name);
					}
					foreach (unowned string name in overwrite_files) {
						overwrite_files_array.add (name);
					}
					bool success = false;
					try {
						success = transaction_interface.trans_run (sysupgrading,
																	database.config.enable_downgrade,
																	database.config.simple_install,
																	database.config.keep_built_pkgs,
																	trans_flags,
																	to_install_array.data,
																	to_remove_array.data,
																	to_load_array.data,
																	to_install_as_dep_array.data,
																	temporary_ignorepkgs_array.data,
																	overwrite_files_array.data);
					} catch (Error e) {
						emit_error ("Daemon Error", {"trans_run: %s".printf (e.message)});
		 			}
		 			return success;
				} else {
					emit_action (dgettext (null, "Transaction cancelled") + ".");
					return false;
				}
			} else if (summary.to_build != null) {
				// only AUR packages to build
				if (ask_commit_real (summary)) {
					// get_authorization here before building
					return get_authorization ();
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
			temporary_ignorepkgs.add (name);
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

		#if ENABLE_SNAP
		public void add_snap_to_install (SnapPackage pkg) {
			snap_to_install.insert (pkg.name, pkg);
		}

		public void add_snap_to_remove (SnapPackage pkg) {
			snap_to_remove.insert (pkg.name, pkg);
		}

		bool run_snap_transaction () {
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
				bool success = transaction_interface.snap_trans_run (snap_to_install_array.data, snap_to_remove_array.data);
				stop_downloading ();
				return success;
			} catch (Error e) {
				emit_error ("Daemon Error", {"snap_trans_run: %s".printf (e.message)});
				return false;
			}
		}

		public bool snap_switch_channel (string snap_name, string channel) {
			try {
				return transaction_interface.snap_switch_channel (snap_name, channel);
			} catch (Error e) {
				emit_error ("Daemon Error", {"snap_switch_channel: %s".printf (e.message)});
			}
			return false;
		}
		#endif

		#if ENABLE_FLATPAK
		public void add_flatpak_to_install (FlatpakPackage pkg) {
			flatpak_to_install.insert (pkg.id, pkg);
		}

		public void add_flatpak_to_remove (FlatpakPackage pkg) {
			flatpak_to_remove.insert (pkg.id, pkg);
		}

		public void add_flatpak_to_upgrade (FlatpakPackage pkg) {
			flatpak_to_upgrade.insert (pkg.id, pkg);
		}

		bool run_flatpak_transaction () {
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
				bool success = transaction_interface.flatpak_trans_run (flatpak_to_install_array.data,
																flatpak_to_remove_array.data,
																flatpak_to_upgrade_array.data);
				stop_downloading ();
				return success;
			} catch (Error e) {
				emit_error ("Daemon Error", {"flatpak_trans_run: %s".printf (e.message)});
				return false;
			}
		}
		#endif

		string remove_bash_colors (string msg) {
			Regex regex = /\x1B\[[0-9;]*[JKmsu]/;
			try {
				return regex.replace (msg, -1, 0, "");
			} catch (Error e) {
				return msg;
			}
		}

		public virtual int run_cmd_line (string[] args, string? working_directory, Cancellable cancellable) {
			int status = 1;
			var launcher = new SubprocessLauncher (SubprocessFlags.STDIN_INHERIT | SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
			if (working_directory != null) {
				launcher.set_cwd (working_directory);
			}
			launcher.set_environ (Environ.get ());
			try {
				Subprocess process = launcher.spawnv (args);
				var dis = new DataInputStream (process.get_stdout_pipe ());
				string? line = null;
				dis.read_line_async.begin (Priority.DEFAULT, cancellable, (obj, res) => {
					try {
						line = dis.read_line_async.end (res);
					} catch (Error e) {
						if (!cancellable.is_cancelled ()) {
							warning (e.message);
						}
					}
					loop.quit ();
				});
				loop.run ();
				while (line != null) {
					if (cancellable.is_cancelled ()) {
						break;
					}
					emit_script_output (remove_bash_colors (line));
					dis.read_line_async.begin (Priority.DEFAULT, cancellable, (obj, res) => {
						try {
							line = dis.read_line_async.end (res);
						} catch (Error e) {
							if (!cancellable.is_cancelled ()) {
								warning (e.message);
							}
						}
						loop.quit ();
					});
					loop.run ();
				}
				if (cancellable.is_cancelled ()) {
					process.send_signal (Posix.Signal.INT);
					process.send_signal (Posix.Signal.KILL);
				}
				process.wait_async.begin (cancellable, (obj, res) => {
					try {
						process.wait_async.end (res);
						if (process.get_if_exited ()) {
							status = process.get_exit_status ();
						}
					} catch (Error e) {
						// cancelled
						process.send_signal (Posix.Signal.INT);
						process.send_signal (Posix.Signal.KILL);
					}
					loop.quit ();
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
			}
			return status;
		}

		bool build_aur_packages () {
			bool success = true;
			// get a fake aur db to check deps
			unowned Alpm.DB? aur_db = null;
			var tmp_handle = database.get_tmp_handle ();
			if (tmp_handle != null) {
				try {
					Process.spawn_command_line_sync ("cp %s/pamac_aur.db %ssync".printf (tmp_path, tmp_handle.dbpath));
					aur_db = tmp_handle.register_syncdb ("pamac_aur", 0);
					if (aur_db == null) {
						emit_warning (dgettext (null, "Failed to initialize AUR database"));
					}
				} catch (SpawnError e) {
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
				if (database.config.aur_build_dir == "/var/tmp") {
					pkgdir = Path.build_path ("/", database.config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()), pkgname);
				} else {
					pkgdir = Path.build_path ("/", database.config.aur_build_dir, "pamac-build", pkgname);
				}
				// building
				building = true;
				start_building ();
				string[] cmdline = {"makepkg", "-cCf"};
				if (!database.config.keep_built_pkgs) {
					cmdline += "--nosign";
					cmdline += "PKGDEST=%s".printf (pkgdir);
					cmdline += "PKGEXT=.pkg.tar";
				}
				important_details_outpout (false);
				int status = run_cmd_line (cmdline, pkgdir, build_cancellable);
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
						cmdline = {"makepkg", "--packagelist"};
						if (!database.config.keep_built_pkgs) {
							cmdline += "PKGDEST=%s".printf (pkgdir);
							cmdline += "PKGEXT=.pkg.tar";
						}
						Subprocess process = launcher.spawnv (cmdline);
						process.wait_async.begin (null, () => {
							loop.quit ();
						});
						loop.run ();
						if (process.get_if_exited ()) {
							status = process.get_exit_status ();
						}
						if (status == 0) {
							var dis = new DataInputStream (process.get_stdout_pipe ());
							string? line = null;
							dis.read_line_async.begin (Priority.DEFAULT, null, (obj, res) => {
								try {
									line = dis.read_line_async.end (res);
								} catch (Error e) {
									warning (e.message);
								}
								loop.quit ();
							});
							loop.run ();
							while (line != null) {
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
								dis.read_line_async.begin (Priority.DEFAULT, null, (obj, res) => {
									try {
										line = dis.read_line_async.end (res);
									} catch (Error e) {
										warning (e.message);
									}
									loop.quit ();
								});
								loop.run ();
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
						success = install_built_pkgs (to_load_array, to_install_as_dep_array);
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

		bool install_built_pkgs (GenericArray<string> to_load_array, GenericArray<string> to_install_as_dep_array) {
			bool success = false;
			try {
				emit_script_output ("");
				success = transaction_interface.trans_run (false, // sysupgrading,
															false, // enable_downgrade
															false, // simple_install
															database.config.keep_built_pkgs,
															0, // trans_flags,
															{}, // to_install
															{}, // to_remove
															to_load_array.data,
															to_install_as_dep_array.data,
															{}, // temporary_ignorepkgs
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
			int index = choose_provider (depend, providers);
			unowned string pkgname = providers[index];
			to_install.add (pkgname);
			to_install_as_dep.add (pkgname);
			return index;
		}

		bool ask_commit_real (TransactionSummary summary) {
			if (build_cancellable.is_cancelled ()) {
				return false;
			} else {
				#if ENABLE_SNAP
				if (snap_to_install.length > 0) {
					// ask classic snaps
					var iter = HashTableIter<string, SnapPackage> (snap_to_install);
					var not_install = new GenericArray<unowned string> ();
					unowned string snap_name;
					SnapPackage pkg;
					while (iter.next (out snap_name, out pkg)) {
						if (pkg.confined != dgettext (null, "Yes")) {
							if (!ask_snap_install_classic (pkg.app_name)) {
								not_install.add (snap_name);
							}
						}
					}
					for (uint i = 0; i < not_install.length; i++) {
						snap_to_install.remove (not_install[i]);
					}
				}
				// add snaps to summary
				var snap_iter = HashTableIter<string, SnapPackage> (snap_to_install);
				SnapPackage snap_pkg;
				while (snap_iter.next (null, out snap_pkg)) {
					summary.to_install_priv.append (snap_pkg);
				}
				snap_iter = HashTableIter<string, SnapPackage> (snap_to_remove);
				while (snap_iter.next (null, out snap_pkg)) {
					summary.to_remove_priv.append (snap_pkg);
				}
				#endif
				#if ENABLE_FLATPAK
				// add flatpaks to summary
				var flatpak_iter = HashTableIter<string, FlatpakPackage> (flatpak_to_install);
				FlatpakPackage flatpak_pkg;
				while (flatpak_iter.next (null, out flatpak_pkg)) {
					summary.to_install_priv.append (flatpak_pkg);
				}
				flatpak_iter = HashTableIter<string, FlatpakPackage> (flatpak_to_remove);
				while (flatpak_iter.next (null, out flatpak_pkg)) {
					summary.to_remove_priv.append (flatpak_pkg);
				}
				flatpak_iter = HashTableIter<string, FlatpakPackage> (flatpak_to_upgrade);
				while (flatpak_iter.next (null, out flatpak_pkg)) {
					summary.to_upgrade_priv.append (flatpak_pkg);
				}
				#endif
				return ask_commit (summary);
			}
		}

		bool ask_edit_build_files_real (TransactionSummary summary) {
			#if ENABLE_SNAP
			var iter = HashTableIter<string, SnapPackage> (snap_to_install);
			SnapPackage pkg;
			while (iter.next (null, out pkg)) {
				summary.to_install_priv.append (pkg);
			}
			iter = HashTableIter<string, SnapPackage> (snap_to_remove);
			while (iter.next (null, out pkg)) {
				summary.to_remove_priv.append (pkg);
			}
			#endif
			// populate build queue
			to_build_queue.clear ();
			foreach (unowned string name in summary.aur_pkgbases_to_build) {
				to_build_queue.push_tail (name);
			}
			aur_pkgs_to_install.remove_all ();
			foreach (unowned Package build_pkg in summary.to_build) {
				aur_pkgs_to_install.add (build_pkg.name);
			}
			return ask_edit_build_files (summary);
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
