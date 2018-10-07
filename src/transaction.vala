/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2018 Guillaume Benoit <guillaume@manjaro.org>
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
		// run transaction data
		string current_action;
		string current_status;
		double current_progress;
		string current_filename;
		bool no_confirm_commit;
		bool enable_downgrade;
		bool sysupgrading;
		bool force_refresh;
		string[] to_install;
		string[] to_remove;
		string[] to_load;
		string[] to_build;
		string[] temporary_ignorepkgs;
		string[] overwrite_files;
		// building data
		string aurdb_path;
		GenericSet<string?> already_checked_aur_dep;
		GenericSet<string?> aur_desc_list;
		Queue<string> to_build_queue;
		string[] aur_pkgs_to_install;
		GenericSet<string?> build_files_reviewed;
		bool building;
		Cancellable build_cancellable;
		// download data
		Timer timer;
		uint64 total_download;
		uint64 already_downloaded;
		uint64 previous_xfered;
		uint64 download_rate;
		uint64 rates_nb;

		// transaction options
		public Database database { get; construct set; }
		public int flags { get; set; } //Alpm.TransFlag

		public signal void emit_action (string action);
		public signal void emit_action_progress (string action, string status, double progress);
		public signal void emit_hook_progress (string action, string details, string status, double progress);
		public signal void emit_script_output (string message);
		public signal void emit_warning (string message);
		public signal void emit_error (string message, string[] details);
		public signal void start_preparing ();
		public signal void stop_preparing ();
		public signal void start_downloading ();
		public signal void stop_downloading ();
		public signal void start_building ();
		public signal void stop_building ();
		public signal void important_details_outpout (bool must_show);
		public signal void downloading_updates_finished ();
		public signal void get_authorization_finished (bool authorized);
		public signal void finished (bool success);
		public signal void sysupgrade_finished (bool success);
		public signal void set_pkgreason_finished ();
		public signal void write_pamac_config_finished (bool recurse, uint64 refresh_period, bool no_update_hide_icon,
														bool enable_aur, string aur_build_dir, bool check_aur_updates,
														bool download_updates);
		public signal void write_alpm_config_finished (bool checkspace);
		public signal void start_generating_mirrors_list ();
		public signal void generate_mirrors_list_finished ();

		public Transaction (Database database) {
			Object (database: database);
		}

		construct {
			if (Posix.geteuid () == 0) {
				// we are root
				transaction_interface = new TransactionInterfaceRoot (database.config);
			} else {
				// use dbus daemon
				transaction_interface = new TransactionInterfaceDaemon (database.config);
			}
			transaction_interface.get_authorization_finished.connect (on_get_authorization_finished);
			transaction_interface.database_modified.connect (on_database_modified);
			// transaction options
			flags = 0;
			enable_downgrade = false;
			// run transaction data
			current_action = "";
			current_status = "";
			current_filename = "";
			no_confirm_commit = false;
			sysupgrading = false;
			temporary_ignorepkgs = {};
			overwrite_files = {};
			// building data
			aurdb_path = "/tmp/pamac-aur";
			already_checked_aur_dep = new GenericSet<string?> (str_hash, str_equal);
			aur_desc_list = new GenericSet<string?> (str_hash, str_equal);
			to_build_queue = new Queue<string> ();
			build_files_reviewed = new GenericSet<string?> (str_hash, str_equal);
			build_cancellable = new Cancellable ();
			building = false;
			// download data
			timer = new Timer ();
		}

		public void quit_daemon () {
			transaction_interface.quit_daemon ();
		}

		protected virtual bool ask_confirmation (TransactionSummary summary) {
			// no confirm
			return true;
		}

		protected virtual bool ask_review_build_files () {
			// no review
			return false;
		}

		protected virtual async void review_build_files (string pkgname) {
			// nothing
		}

		protected async void regenerate_srcinfo (string pkgname) {
			string pkgdir_name = Path.build_path ("/", database.config.aur_build_dir, "pamac-build", pkgname);
			// generate .SRCINFO
			var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);
			launcher.set_cwd (pkgdir_name);
			try {
				Subprocess process = launcher.spawnv ({"makepkg", "--printsrcinfo"});
				yield process.wait_async ();
				var dis = new DataInputStream (process.get_stdout_pipe ());
				var file = File.new_for_path (Path.build_path ("/", pkgdir_name, ".SRCINFO"));
				// delete the file before rewrite it
				yield file.delete_async ();
				// creating a DataOutputStream to the file
				var dos = new DataOutputStream (yield file.create_async (FileCreateFlags.REPLACE_DESTINATION));
				// writing makepkg output to .SRCINFO
				yield dos.splice_async (dis, 0);
			} catch (Error e) {
				stderr.printf ("Error: %s\n", e.message);
			}
		}

		protected virtual int choose_provider (string depend, string[] providers) {
			// choose first provider
			return 0;
		}

		ErrorInfos get_current_error () {
			return transaction_interface.get_current_error ();
		}

		public bool get_lock () {
			return transaction_interface.get_lock ();
		}

		public bool unlock () {
			return transaction_interface.unlock ();
		}

		void on_database_modified () {
			database.refresh ();
		}

		public void start_get_authorization () {
			transaction_interface.start_get_authorization ();
		}

		void on_get_authorization_finished (bool authorized) {
			get_authorization_finished (authorized);
		}

		public void start_write_pamac_config (HashTable<string,Variant> new_pamac_conf) {
			transaction_interface.write_pamac_config_finished.connect (on_write_pamac_config_finished);
			transaction_interface.start_write_pamac_config (new_pamac_conf);
		}

		public void start_write_alpm_config (HashTable<string,Variant> new_alpm_conf) {
			transaction_interface.write_alpm_config_finished.connect (on_write_alpm_config_finished);
			transaction_interface.start_write_alpm_config (new_alpm_conf);
		}

		public void start_generate_mirrors_list (string country) {
			emit_action (dgettext (null, "Refreshing mirrors list") + "...");
			important_details_outpout (false);
			start_generating_mirrors_list ();
			transaction_interface.generate_mirrors_list_data.connect (on_generate_mirrors_list_data);
			transaction_interface.generate_mirrors_list_finished.connect (on_generate_mirrors_list_finished);
			transaction_interface.start_generate_mirrors_list (country);
		}

		public void clean_cache (uint64 keep_nb, bool only_uninstalled) {
			transaction_interface.clean_cache (keep_nb, only_uninstalled);
		}

		public void start_set_pkgreason (string pkgname, uint reason) {
			transaction_interface.set_pkgreason_finished.connect (on_set_pkgreason_finished);
			transaction_interface.start_set_pkgreason (pkgname, reason);
		}

		void on_refresh_for_sysupgrade_finished (bool success) {
			stop_downloading ();
			current_filename = "";
			transaction_interface.refresh_finished.disconnect (on_refresh_for_sysupgrade_finished);
			if (!success) {
				on_trans_prepare_finished (false);
			} else {
				sysupgrading = true;
				emit_action (dgettext (null, "Starting full system upgrade") + "...");
				if (database.config.check_aur_updates) {
					database.get_aur_updates.begin ((obj, res) => {
						var aur_updates = database.get_aur_updates.end (res);
						to_build = {};
						foreach (unowned AURPackage aur_update in aur_updates) {
							if (!(aur_update.name in temporary_ignorepkgs)) {
								to_build += aur_update.name;
							}
						}
						sysupgrade_real ();
					});
				} else {
					sysupgrade_real ();
				}
			}
		}

		void launch_refresh_for_sysupgrade (bool authorized) {
			get_authorization_finished.disconnect (launch_refresh_for_sysupgrade);
			if (authorized) {
				emit_action (dgettext (null, "Synchronizing package databases") + "...");
				connecting_signals ();
				transaction_interface.refresh_finished.connect (on_refresh_for_sysupgrade_finished);
				transaction_interface.start_refresh (force_refresh);
				start_downloading ();
			} else {
				on_refresh_for_sysupgrade_finished (false);
			}
		}

		void start_refresh_for_sysupgrade () {
			// check autorization to send start_downloading signal after that
			get_authorization_finished.connect (launch_refresh_for_sysupgrade);
			start_get_authorization ();
		}

		public void start_downloading_updates () {
			transaction_interface.downloading_updates_finished.connect (on_downloading_updates_finished);
			transaction_interface.start_downloading_updates ();
		}

		void on_downloading_updates_finished () {
			transaction_interface.downloading_updates_finished.disconnect (on_downloading_updates_finished);
			downloading_updates_finished ();
		}

		async void compute_aur_build_list () {
			try {
				Process.spawn_command_line_sync ("mkdir -p %s".printf (aurdb_path));
			} catch (SpawnError e) {
				stderr.printf ("SpawnError: %s\n", e.message);
			}
			aur_desc_list.remove_all ();
			already_checked_aur_dep.remove_all ();
			yield check_aur_dep_list (to_build);
			// create a fake aur db
			try {
				var list = new StringBuilder ();
				foreach (unowned string name_version in aur_desc_list) {
					list.append (name_version);
					list.append (" ");
				}
				Process.spawn_command_line_sync ("rm -f %ssync/aur.db".printf (database.get_tmp_db_path ()));
				Process.spawn_command_line_sync ("bsdtar -cf %ssync/aur.db -C %s %s".printf (database.get_tmp_db_path (), aurdb_path, list.str));
			} catch (SpawnError e) {
				stderr.printf ("SpawnError: %s\n", e.message);
			}
		}

		async void check_aur_dep_list (string[] pkgnames) {
			string[] dep_to_check = {};
			foreach (unowned string name in pkgnames) {
				if (build_cancellable.is_cancelled ()) {
					break;
				}
				string version = "";
				string pkgbase = "";
				string desc = "";
				string[] depends = {};
				string[] conflicts = {};
				string[] provides = {};
				string[] replaces = {};
				// clone build files
				emit_action (dgettext (null, "Checking %s dependencies".printf (name)) + "...");
				File? clone_dir = yield database.clone_build_files (name, false);
				if (clone_dir == null) {
					// error
					continue;
				}
				// read .SRCINFO
				var srcinfo = clone_dir.get_child (".SRCINFO");
				try {
					var dis = new DataInputStream (srcinfo.read ());
					string line;
					while ((line = dis.read_line ()) != null) {
						if ("pkgbase = " in line) {
							pkgbase = line.split ("pkgbase = ", 2)[1];
						} else if ("pkgdesc = " in line) {
							desc = line.split ("pkgdesc = ", 2)[1];
						} else if ("pkgver = " in line) {
							version = line.split ("pkgver = ", 2)[1];
						} else if ("pkgrel = " in line) {
							version += "-";
							version += line.split ("pkgrel = ", 2)[1];
						// compute depends, makedepends and checkdepends in depends
						} else if ("checkdepends = " in line) {
							depends += line.split ("checkdepends = ", 2)[1];
						} else if ("makedepends = " in line) {
							depends += line.split ("makedepends = ", 2)[1];
						} else if ("optdepends = " in line) {
							// pass
							continue;
						} else if ("depends = " in line) {
							depends += line.split ("depends = ", 2)[1];
						} else if ("provides = " in line) {
							provides += line.split ("provides = ", 2)[1];
						} else if ("conflicts = " in line) {
							conflicts += line.split ("conflicts = ", 2)[1];
						} else if ("replaces = " in line) {
							replaces += line.split ("replaces = ", 2)[1];
						}
					}
					// check deps
					foreach (unowned string dep_string in depends) {
						var pkg = database.find_installed_satisfier (dep_string);
						if (pkg.name == "") {
							pkg = database.find_sync_satisfier (dep_string);
						}
						if (pkg.name == "") {
							string dep_name = Alpm.Depend.from_string (dep_string).name;
							if (!(dep_name in already_checked_aur_dep)) {
								already_checked_aur_dep.add (dep_name);
								var aur_pkg = yield database.get_aur_pkg (dep_name);
								if (aur_pkg.name != "") {
									dep_to_check += (owned) dep_name;
								}
							}
						}
					}
					// write desc file
					string pkgdir = "%s-%s".printf (name, version);
					string pkgdir_path = "%s/%s".printf (aurdb_path, pkgdir);
					aur_desc_list.add (pkgdir);
					var file = GLib.File.new_for_path (pkgdir_path);
					// always recreate desc in case of .SRCINFO modifications
					if (file.query_exists ()) {
						Process.spawn_command_line_sync ("rm -rf %s".printf (pkgdir_path));
					}
					file.make_directory ();
					file = GLib.File.new_for_path ("%s/desc".printf (pkgdir_path));
					// creating a DataOutputStream to the file
					var dos = new DataOutputStream (file.create (FileCreateFlags.REPLACE_DESTINATION));
					// fake filename
					dos.put_string ("%FILENAME%\n" + "%s-%s-any.pkg.tar.xz\n\n".printf (name, version));
					// name
					dos.put_string ("%NAME%\n%s\n\n".printf (name));
					// version
					dos.put_string ("%VERSION%\n%s\n\n".printf (version));
					// base
					dos.put_string ("%BASE%\n%s\n\n".printf (pkgbase));
					// desc
					dos.put_string ("%DESC%\n%s\n\n".printf (desc));
					// version
					dos.put_string ("%VERSION%\n%s\n\n".printf (version));
					// fake arch
					dos.put_string ("%ARCH%\nany\n\n");
					// depends
					if (depends.length > 0) {
						dos.put_string ("%DEPENDS%\n");
						foreach (unowned string depend in depends) {
							dos.put_string ("%s\n".printf (depend));
						}
						dos.put_string ("\n");
					}
					// conflicts
					if (conflicts.length > 0) {
						dos.put_string ("%CONFLICTS%\n");
						foreach (unowned string conflict in conflicts) {
							dos.put_string ("%s\n".printf (conflict));
						}
						dos.put_string ("\n");
					}
					// provides
					if (provides.length > 0) {
						dos.put_string ("%PROVIDES%\n");
						foreach (unowned string provide in provides) {
							dos.put_string ("%s\n".printf (provide));
						}
						dos.put_string ("\n");
					}
					// replaces
					if (replaces.length > 0) {
						dos.put_string ("%REPLACES%\n");
						foreach (unowned string replace in replaces) {
							dos.put_string ("%s\n".printf (replace));
						}
						dos.put_string ("\n");
					}
				} catch (GLib.Error e) {
					GLib.stderr.printf("%s\n", e.message);
				}
			}
			if (dep_to_check.length > 0) {
				yield check_aur_dep_list (dep_to_check);
			}
		}

		void sysupgrade_real () {
			start_preparing ();
			// this will respond with trans_prepare_finished signal
			transaction_interface.start_sysupgrade_prepare (enable_downgrade, temporary_ignorepkgs, to_build, overwrite_files);
		}

		public void start_sysupgrade (bool force_refresh, bool enable_downgrade, string[] temporary_ignorepkgs, string[] overwrite_files) {
			this.force_refresh = force_refresh;
			this.enable_downgrade = enable_downgrade;
			this.temporary_ignorepkgs = temporary_ignorepkgs;
			this.overwrite_files = overwrite_files;
			start_refresh_for_sysupgrade ();
		}

		void trans_prepare_real () {
			if (to_build.length != 0) {
				// set building to allow cancellation
				building = true;
				build_cancellable.reset ();
				compute_aur_build_list.begin (() => {
					building = false;
					if (build_cancellable.is_cancelled ()) {
						on_trans_prepare_finished (false);
					}
					transaction_interface.start_trans_prepare (flags, to_install, to_remove, to_load, to_build, overwrite_files);
				});
			} else {
				transaction_interface.start_trans_prepare (flags, to_install, to_remove, to_load, to_build, overwrite_files);
			}
		}

		public void start (string[] to_install, string[] to_remove, string[] to_load, string[] to_build, string[] overwrite_files) {
			this.to_install = to_install;
			this.to_remove = to_remove;
			this.to_load = to_load;
			this.to_build = to_build;
			this.overwrite_files = overwrite_files;
			emit_action (dgettext (null, "Preparing") + "...");
			start_preparing ();
			connecting_signals ();
			trans_prepare_real ();
		}

		void start_commit () {
			transaction_interface.start_trans_commit ();
		}

		public virtual async int run_cmd_line (string[] args, string working_directory, Cancellable cancellable) {
			int status = 1;
			var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
			launcher.set_cwd (working_directory);
			launcher.set_environ (Environ.get ());
			try {
				Subprocess process = launcher.spawnv (args);
				var dis = new DataInputStream (process.get_stdout_pipe ());
				string? line;
				while ((line = yield dis.read_line_async (Priority.DEFAULT, cancellable)) != null) {
					emit_script_output (line);
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
				stderr.printf ("Error: %s\n", e.message);
			}
			return status;
		}

		async void build_next_aur_package () {
			string pkgname = to_build_queue.pop_head ();
			emit_action (dgettext (null, "Building %s").printf (pkgname) + "...");
			build_cancellable.reset ();
			important_details_outpout (false);
			string [] built_pkgs = {};
			string pkgdir = Path.build_path ("/", database.config.aur_build_dir, "pamac-build", pkgname);
			// building
			building = true;
			start_building ();
			int status = yield run_cmd_line ({"makepkg", "-cf"}, pkgdir, build_cancellable);
			if (build_cancellable.is_cancelled ()) {
				status = 1;
			}
			if (status == 0) {
				// get built pkgs path
				var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);
				launcher.set_cwd (pkgdir);
				try {
					Subprocess process = launcher.spawnv ({"makepkg", "--packagelist"});
					yield process.wait_async (null);
					if (process.get_if_exited ()) {
						status = process.get_exit_status ();
					}
					if (status == 0) {
						var dis = new DataInputStream (process.get_stdout_pipe ());
						string? line;
						// Read lines until end of file (null) is reached
						while ((line = yield dis.read_line_async ()) != null) {
							var file = GLib.File.new_for_path (line);
							string filename = file.get_basename ();
							string name_version_release = filename.slice (0, filename.last_index_of_char ('-'));
							string name_version = name_version_release.slice (0, name_version_release.last_index_of_char ('-'));
							string name = name_version.slice (0, name_version.last_index_of_char ('-'));
							if (name in aur_pkgs_to_install) {
								if (!(line in built_pkgs)) {
									built_pkgs += line;
								}
							}
						}
					}
				} catch (Error e) {
					stderr.printf ("Error: %s\n", e.message);
					status = 1;
				}
			}
			stop_building ();
			building = false;
			if (status == 0 && built_pkgs.length > 0) {
				no_confirm_commit = true;
				emit_script_output ("");
				to_install = {};
				to_remove = {};
				to_load = built_pkgs;
				to_build = {};
				overwrite_files = {};
				trans_prepare_real ();
			} else {
				important_details_outpout (true);
				to_build_queue.clear ();
				finish_transaction (false);
			}
		}

		public void cancel () {
			if (building) {
				build_cancellable.cancel ();
			} else {
				transaction_interface.trans_cancel ();
			}
			emit_script_output ("");
			emit_action (dgettext (null, "Transaction cancelled") + ".");
			emit_script_output ("");
		}

		public void release () {
			transaction_interface.trans_release ();
		}

		void on_emit_event (uint primary_event, uint secondary_event, string[] details) {
			switch (primary_event) {
				case 1: //Alpm.Event.Type.CHECKDEPS_START
					emit_action (dgettext (null, "Checking dependencies") + "...");
					break;
				case 3: //Alpm.Event.Type.FILECONFLICTS_START
					current_action = dgettext (null, "Checking file conflicts") + "...";
					break;
				case 5: //Alpm.Event.Type.RESOLVEDEPS_START
					emit_action (dgettext (null, "Resolving dependencies") + "...");
					break;
				case 7: //Alpm.Event.Type.INTERCONFLICTS_START
					emit_action (dgettext (null, "Checking inter-conflicts") + "...");
					break;
				case 11: //Alpm.Event.Type.PACKAGE_OPERATION_START
					switch (secondary_event) {
						// special case handle differently
						case 1: //Alpm.Package.Operation.INSTALL
							current_filename = details[0];
							current_action = dgettext (null, "Installing %s").printf ("%s (%s)".printf (details[0], details[1])) + "...";
							break;
						case 2: //Alpm.Package.Operation.UPGRADE
							current_filename = details[0];
							current_action = dgettext (null, "Upgrading %s").printf ("%s (%s -> %s)".printf (details[0], details[1], details[2])) + "...";
							break;
						case 3: //Alpm.Package.Operation.REINSTALL
							current_filename = details[0];
							current_action = dgettext (null, "Reinstalling %s").printf ("%s (%s)".printf (details[0], details[1])) + "...";
							break;
						case 4: //Alpm.Package.Operation.DOWNGRADE
							current_filename = details[0];
							current_action = dgettext (null, "Downgrading %s").printf ("%s (%s -> %s)".printf (details[0], details[1], details[2])) + "...";
							break;
						case 5: //Alpm.Package.Operation.REMOVE
							current_filename = details[0];
							current_action = dgettext (null, "Removing %s").printf ("%s (%s)".printf (details[0], details[1])) + "...";
							break;
					}
					break;
				case 13: //Alpm.Event.Type.INTEGRITY_START
					current_action = dgettext (null, "Checking integrity") + "...";
					break;
				case 15: //Alpm.Event.Type.LOAD_START
					current_action = dgettext (null, "Loading packages files") + "...";
					break;
				case 17: //Alpm.Event.Type.DELTA_INTEGRITY_START
					emit_action (dgettext (null, "Checking delta integrity") + "...");
					break;
				case 19: //Alpm.Event.Type.DELTA_PATCHES_START
					emit_action (dgettext (null, "Applying deltas") + "...");
					break;
				case 21: //Alpm.Event.Type.DELTA_PATCH_START
					emit_script_output (dgettext (null, "Generating %s with %s").printf (details[0], details[1]) + "...");
					break;
				case 22: //Alpm.Event.Type.DELTA_PATCH_DONE
					emit_script_output (dgettext (null, "Generation succeeded") + ".");
					break;
				case 23: //Alpm.Event.Type.DELTA_PATCH_FAILED
					emit_script_output (dgettext (null, "Generation failed") + ".");
					break;
				case 24: //Alpm.Event.Type.SCRIPTLET_INFO
					// hooks output are also emitted as SCRIPTLET_INFO
					if (current_filename != "") {
						emit_action (dgettext (null, "Configuring %s").printf (current_filename) + "...");
						current_filename = "";
					}
					emit_script_output (details[0].replace ("\n", ""));
					important_details_outpout (false);
					break;
				case 25: //Alpm.Event.Type.RETRIEVE_START
					start_downloading ();
					emit_action (dgettext (null, "Downloading") + "...");
					break;
				case 26: //Alpm.Event.Type.RETRIEVE_DONE
				case 27: //Alpm.Event.Type.RETRIEVE_FAILED
					stop_downloading ();
					break;
				case 28: //Alpm.Event.Type.PKGDOWNLOAD_START
					// special case handle differently
					string name_version_release = details[0].slice (0, details[0].last_index_of_char ('-'));
					string name_version = name_version_release.slice (0, name_version_release.last_index_of_char ('-'));
					string name = name_version.slice (0, name_version.last_index_of_char ('-'));
					string version_release = details[0].replace (name + "-", "").replace (".pkg.tar.xz", "");
					current_action = dgettext (null, "Downloading %s").printf ("%s (%s)".printf (name, version_release)) + "...";
					break;
				case 31: //Alpm.Event.Type.DISKSPACE_START
					current_action = dgettext (null, "Checking available disk space") + "...";
					break;
				case 33: //Alpm.Event.Type.OPTDEP_REMOVAL
					emit_warning (dgettext (null, "%s optionally requires %s").printf (details[0], details[1]));
					break;
				case 34: //Alpm.Event.Type.DATABASE_MISSING
					emit_script_output (dgettext (null, "Database file for %s does not exist").printf (details[0]) + ".");
					break;
				case 35: //Alpm.Event.Type.KEYRING_START
					current_action = dgettext (null, "Checking keyring") + "...";
					break;
				case 37: //Alpm.Event.Type.KEY_DOWNLOAD_START
					emit_action (dgettext (null, "Downloading required keys") + "...");
					break;
				case 39: //Alpm.Event.Type.PACNEW_CREATED
					emit_script_output (dgettext (null, "%s installed as %s.pacnew").printf (details[0], details[0])+ ".");
					break;
				case 40: //Alpm.Event.Type.PACSAVE_CREATED
					emit_script_output (dgettext (null, "%s installed as %s.pacsave").printf (details[0], details[0])+ ".");
					break;
				case 41: //Alpm.Event.Type.HOOK_START
					switch (secondary_event) {
						case 1: //Alpm.HookWhen.PRE_TRANSACTION
							current_action = dgettext (null, "Running pre-transaction hooks") + "...";
							break;
						case 2: //Alpm.HookWhen.POST_TRANSACTION
							current_filename = "";
							current_action = dgettext (null, "Running post-transaction hooks") + "...";
							break;
						default:
							break;
					}
					break;
				case 43: // Alpm.Event.Type.HOOK_RUN_START
					double progress = (double) int.parse (details[2]) / int.parse (details[3]);
					string status = "%s/%s".printf (details[2], details[3]);
					bool changed = false;
					if (progress != current_progress) {
						current_progress = progress;
						changed = true;
					}
					if (status != current_status) {
						current_status = status;
						changed = true;
					}
					if (changed) {
						if (details[1] != "") {
							emit_hook_progress (current_action, details[1], current_status, current_progress);
						} else {
							emit_hook_progress (current_action, details[0], current_status, current_progress);
						}
					}
					break;
				default:
					break;
			}
		}

		void on_emit_providers (string depend, string[] providers) {
			int index = choose_provider (depend, providers);
			transaction_interface.choose_provider (index);
		}

		void on_emit_progress (uint progress, string pkgname, uint percent, uint n_targets, uint current_target) {
			double fraction;
			switch (progress) {
				case 0: //Alpm.Progress.ADD_START
				case 1: //Alpm.Progress.UPGRADE_START
				case 2: //Alpm.Progress.DOWNGRADE_START
				case 3: //Alpm.Progress.REINSTALL_START
				case 4: //Alpm.Progress.REMOVE_START
					fraction = ((double) (current_target - 1) / n_targets) + ((double) percent / (100 * n_targets));
					break;
				case 5: //Alpm.Progress.CONFLICTS_START
				case 6: //Alpm.Progress.DISKSPACE_START
				case 7: //Alpm.Progress.INTEGRITY_START
				case 8: //Alpm.Progress.LOAD_START
				case 9: //Alpm.Progress.KEYRING_START
				default:
					fraction = (double) percent / 100;
					break;
			}
			string status = "%lu/%lu".printf (current_target, n_targets);
			bool changed = false;
			if (fraction != current_progress) {
				current_progress = fraction;
				changed = true;
			}
			if (status != current_status) {
				current_status = status;
				changed = true;
			}
			if (changed) {
				if (current_action != "") {
					emit_action_progress (current_action, current_status, current_progress);
				}
			}
		}

		void on_emit_download (string filename, uint64 xfered, uint64 total) {
			var text = new StringBuilder ();
			double fraction;
			if (total_download > 0) {
				if (xfered == 0) {
					// start download pkg is handled by Alpm.Event.Type.PKGDOWNLOAD_START
					previous_xfered = 0;
					fraction = current_progress;
					text.append (current_status);
					timer.start ();
				} else {
					if (timer.elapsed () > 0.1) {
						download_rate = ((download_rate * rates_nb) + (uint64) ((xfered - previous_xfered) / timer.elapsed ())) / (rates_nb + 1);
						rates_nb++;
					}
					previous_xfered = xfered;
					uint64 downloaded_total = xfered + already_downloaded;
					fraction = (double) downloaded_total / total_download;
					if (fraction <= 1) {
						text.append ("%s/%s  ".printf (format_size (xfered + already_downloaded), format_size (total_download)));
						uint64 remaining_seconds = 0;
						if (download_rate > 0) {
							remaining_seconds = (total_download - downloaded_total) / download_rate;
						}
						// display remaining time after 5s and only if more than 10s are remaining
						if (remaining_seconds > 9 && rates_nb > 9) {
							if (remaining_seconds <= 50) {
								text.append (dgettext (null, "About %u seconds remaining").printf ((uint) Math.ceilf ((float) remaining_seconds / 10) * 10));
							} else {
								uint remaining_minutes = (uint) Math.ceilf ((float) remaining_seconds / 60);
								text.append (dngettext (null, "About %lu minute remaining",
											"About %lu minutes remaining", remaining_minutes).printf (remaining_minutes));
							}
						}
					} else {
						text.append ("%s".printf (format_size (xfered + already_downloaded)));
					}
					if (xfered == total) {
						current_filename = "";
						already_downloaded += total;
					} else {
						timer.start ();
					}
				}
			} else {
				if (xfered == 0) {
					previous_xfered = 0;
					download_rate = 0;
					rates_nb = 0;
					fraction = 0;
					timer.start ();
					if (filename.has_suffix (".db") || filename.has_suffix (".files")) {
						current_action = dgettext (null, "Refreshing %s").printf (filename) + "...";
					}
				} else if (xfered == total) {
					timer.stop ();
					fraction = 1;
					current_filename = "";
				} else {
					if (timer.elapsed () > 0.1) {
						download_rate = ((download_rate * rates_nb) + (uint64) ((xfered - previous_xfered) / timer.elapsed ())) / (rates_nb + 1);
						rates_nb++;
					}
					previous_xfered = xfered;
					fraction = (double) xfered / total;
					if (fraction <= 1) {
						text.append ("%s/%s  ".printf (format_size (xfered), format_size (total)));
						uint64 remaining_seconds = 0;
						if (download_rate > 0) {
							remaining_seconds = (total - xfered) / download_rate;
						}
						// display remaining time after 5s and only if more than 10s are remaining
						if (remaining_seconds > 9 && rates_nb > 9) {
							if (remaining_seconds <= 50) {
								text.append (dgettext (null, "About %u seconds remaining").printf ((uint) Math.ceilf ((float) remaining_seconds / 10) * 10));
							} else {
								uint remaining_minutes = (uint) Math.ceilf ((float) remaining_seconds / 60);
								text.append (dngettext (null, "About %lu minute remaining",
											"About %lu minutes remaining", remaining_minutes).printf (remaining_minutes));
							}
						}
					} else {
						text.append ("%s".printf (format_size (xfered)));
					}
					// reinitialize timer
					timer.start ();
				}
			}
			if (fraction != current_progress) {
				current_progress = fraction;
			}
			if (text.str != current_status) {
				current_status = text.str;
			}
			emit_action_progress (current_action, current_status, current_progress);
		}

		void on_emit_totaldownload (uint64 total) {
			download_rate = 0;
			rates_nb = 0;
			current_progress = 0;
			current_status = "";
			total_download = total;
			//  this is emitted at the end of the total download 
			// with the value 0 so stop our timer
			if (total == 0) {
				timer.stop ();
			}
		}

		void on_emit_log (uint level, string msg) {
			// msg ends with \n
			string? line = null;
			if (level == 1) { //Alpm.LogLevel.ERROR
				if (current_filename != "") {
					line = dgettext (null, "Error") + ": " + current_filename + ": " + msg;
				} else {
					line = dgettext (null, "Error") + ": " + msg;
				}
				important_details_outpout (false);
				emit_warning (line.replace ("\n", ""));
			} else if (level == (1 << 1)) { //Alpm.LogLevel.WARNING
				// warnings when no_confirm_commit should already have been sent
				if (no_confirm_commit) {
					return;
				}
				// do not show warning when manjaro-system remove db.lck
				if (current_filename != "manjaro-system") {
					if (current_filename != "") {
						line = dgettext (null, "Warning") + ": " + current_filename + ": " + msg;
					} else {
						line = dgettext (null, "Warning") + ": " + msg;
					}
					emit_warning (line.replace ("\n", ""));
				}
			}
		}

		void handle_error (ErrorInfos error) {
			if (error.message != "") {
				emit_error (error.message, error.details);
			}
			finish_transaction (false);
		}

		void finish_transaction (bool success) {
			disconnecting_signals ();
			if (sysupgrading) {
				sysupgrade_finished (success);
				sysupgrading = false;
			} else {
				finished (success);
			}
		}

		string[] get_build_files_to_review (string[] aur_pkgbases_to_build) {
			string[] build_files_to_review = {};
			foreach (unowned string name in aur_pkgbases_to_build) {
				if (!build_files_reviewed.contains (name)) {
					build_files_to_review += name;
				}
			}
			return build_files_to_review;
		}

		void on_trans_prepare_finished (bool success) {
			if (success) {
				var summary_struct = transaction_interface.get_transaction_summary ();
				Type type = 0;
				if ((summary_struct.to_install.length
					+ summary_struct.to_downgrade.length
					+ summary_struct.to_reinstall.length) > 0) {
					type |= Type.INSTALL;
				}
				if (summary_struct.to_remove.length > 0) {
					type |= Type.REMOVE;
				}
				if (summary_struct.to_upgrade.length > 0) {
					type |= Type.UPDATE;
				}
				if (summary_struct.to_build.length > 0) {
					type |= Type.BUILD;
				}
				if (no_confirm_commit) {
					no_confirm_commit = false;
					start_commit ();
				} else if (type != 0) {
					var summary = new TransactionSummary (summary_struct);
					if ((type & Type.BUILD) != 0) {
						// ask to review build files
						string[] build_files_to_review = get_build_files_to_review (summary_struct.aur_pkgbases_to_build);
						if (build_files_to_review.length > 0) {
							release ();
							review_build_files_and_reprepare.begin ((owned) build_files_to_review);
							return;
						}
						// populate build queue
						foreach (unowned string name in summary_struct.aur_pkgbases_to_build) {
							to_build_queue.push_tail (name);
						}
						aur_pkgs_to_install = {};
						foreach (unowned AURPackageStruct infos in summary_struct.to_build) {
							aur_pkgs_to_install += infos.name;
						}
						stop_preparing ();
						if (ask_confirmation (summary)) {
							if (type == Type.BUILD) {
								// there only AUR packages to build
								release ();
								on_trans_commit_finished (true);
							} else {
								start_commit ();
							}
						} else if (ask_review_build_files ()) {
							release ();
							build_files_reviewed.remove_all ();
							emit_script_output ("");
							review_build_files_and_reprepare.begin (get_build_files_to_review (summary_struct.aur_pkgbases_to_build));
							return;
						} else {
							emit_action (dgettext (null, "Transaction cancelled") + ".");
							release ();
							to_build_queue.clear ();
							finish_transaction (false);
						}
					} else if (ask_confirmation (summary)) {
						stop_preparing ();
						start_commit ();
					} else {
						stop_preparing ();
						emit_action (dgettext (null, "Transaction cancelled") + ".");
						release ();
						finish_transaction (false);
					}
				} else {
					//var err = ErrorInfos ();
					//err.message = dgettext (null, "Nothing to do") + "\n";
					stop_preparing ();
					emit_action (dgettext (null, "Nothing to do") + ".");
					release ();
					finish_transaction (true);
					//handle_error (err);
				}
			} else {
				stop_preparing ();
				handle_error (get_current_error ());
			}
		}

		async void review_build_files_and_reprepare (owned string[] build_files_to_review) {
			// keep string during review_build_files
			string[] build_files = (owned) build_files_to_review;
			foreach (unowned string name in build_files) {
				yield review_build_files (name);
				build_files_reviewed.add (name);
			}
			emit_script_output ("");
			// prepare again
			if (sysupgrading) {
				emit_action (dgettext (null, "Starting full system upgrade") + "...");
				sysupgrade_real ();
			} else {
				emit_action (dgettext (null, "Preparing") + "...");
				trans_prepare_real ();
			}
		}

		void launch_build_next_aur_package (bool authorized) {
			get_authorization_finished.disconnect (launch_build_next_aur_package);
			if (authorized) {
				build_next_aur_package.begin ();
			} else {
				on_trans_commit_finished (false);
			}
		}

		void on_trans_commit_finished (bool success) {
			if (success) {
				if (to_build_queue.get_length () != 0) {
					build_files_reviewed.remove_all ();
					emit_script_output ("");
					get_authorization_finished.connect (launch_build_next_aur_package);
					start_get_authorization ();
				} else {
					emit_action (dgettext (null, "Transaction successfully finished") + ".");
					finish_transaction (true);
				}
			} else {
				to_build_queue.clear ();
				handle_error (get_current_error ());
			}
			total_download = 0;
			already_downloaded = 0;
			current_filename = "";
		}

		void on_set_pkgreason_finished () {
			transaction_interface.set_pkgreason_finished.disconnect (on_set_pkgreason_finished);
			set_pkgreason_finished ();
		}

		void on_write_pamac_config_finished (bool recurse, uint64 refresh_period, bool no_update_hide_icon,
											bool enable_aur, string aur_build_dir, bool check_aur_updates,
											bool download_updates) {
			transaction_interface.write_pamac_config_finished.disconnect (on_write_pamac_config_finished);
			database.config.reload ();
			write_pamac_config_finished (recurse, refresh_period, no_update_hide_icon,
										enable_aur, aur_build_dir, check_aur_updates,
										download_updates);
		}

		void on_write_alpm_config_finished (bool checkspace) {
			transaction_interface.write_alpm_config_finished.disconnect (on_write_alpm_config_finished);
			write_alpm_config_finished (checkspace);
		}

		void on_generate_mirrors_list_data (string line) {
			emit_script_output (line);
		}

		void on_generate_mirrors_list_finished () {
			transaction_interface.generate_mirrors_list_data.disconnect (on_generate_mirrors_list_data);
			transaction_interface.generate_mirrors_list_finished.disconnect (on_generate_mirrors_list_finished);
			generate_mirrors_list_finished ();
		}

		void connecting_signals () {
			transaction_interface.emit_event.connect (on_emit_event);
			transaction_interface.emit_providers.connect (on_emit_providers);
			transaction_interface.emit_progress.connect (on_emit_progress);
			transaction_interface.emit_download.connect (on_emit_download);
			transaction_interface.emit_totaldownload.connect (on_emit_totaldownload);
			transaction_interface.emit_log.connect (on_emit_log);
			transaction_interface.trans_prepare_finished.connect (on_trans_prepare_finished);
			transaction_interface.trans_commit_finished.connect (on_trans_commit_finished);
		}

		void disconnecting_signals () {
			transaction_interface.emit_event.disconnect (on_emit_event);
			transaction_interface.emit_providers.disconnect (on_emit_providers);
			transaction_interface.emit_progress.disconnect (on_emit_progress);
			transaction_interface.emit_download.disconnect (on_emit_download);
			transaction_interface.emit_totaldownload.disconnect (on_emit_totaldownload);
			transaction_interface.emit_log.disconnect (on_emit_log);
			transaction_interface.trans_prepare_finished.disconnect (on_trans_prepare_finished);
			transaction_interface.trans_commit_finished.disconnect (on_trans_commit_finished);
		}
	}
}
