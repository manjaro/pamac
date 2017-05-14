/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2017 Guillaume Benoit <guillaume@manjaro.org>
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

// i18n
const string GETTEXT_PACKAGE = "pamac";

Pamac.Daemon pamac_daemon;
MainLoop loop;

public delegate void AlpmActionDelegate ();

[Compact]
public class AlpmAction {
	public unowned AlpmActionDelegate action_delegate;
	public AlpmAction (AlpmActionDelegate action_delegate) {
		this.action_delegate = action_delegate;
	}
	public void run () {
		action_delegate ();
	}
}

private int alpm_pkg_compare_name (Alpm.Package pkg_a, Alpm.Package pkg_b) {
	return strcmp (pkg_a.name, pkg_b.name);
}

private string global_search_string;

private int alpm_pkg_sort_search_by_relevance (Alpm.Package pkg_a, Alpm.Package pkg_b) {
	if (global_search_string != null) {
		// display exact match first
		if (pkg_a.name == global_search_string) {
			return 0;
		}
		if (pkg_b.name == global_search_string) {
			return 1;
		}
		if (pkg_a.name.has_prefix (global_search_string + "-")) {
			if (pkg_b.name.has_prefix (global_search_string + "-")) {
				return strcmp (pkg_a.name, pkg_b.name);
			}
			return 0;
		}
		if (pkg_b.name.has_prefix (global_search_string + "-")) {
			if (pkg_a.name.has_prefix (global_search_string + "-")) {
				return strcmp (pkg_a.name, pkg_b.name);
			}
			return 1;
		}
		if (pkg_a.name.has_prefix (global_search_string)) {
			if (pkg_b.name.has_prefix (global_search_string)) {
				return strcmp (pkg_a.name, pkg_b.name);
			}
			return 0;
		}
		if (pkg_b.name.has_prefix (global_search_string)) {
			if (pkg_a.name.has_prefix (global_search_string)) {
				return strcmp (pkg_a.name, pkg_b.name);
			}
			return 1;
		}
		if (pkg_a.name.contains (global_search_string)) {
			if (pkg_b.name.contains (global_search_string)) {
				return strcmp (pkg_a.name, pkg_b.name);
			}
			return 0;
		}
		if (pkg_b.name.contains (global_search_string)) {
			if (pkg_a.name.contains (global_search_string)) {
				return strcmp (pkg_a.name, pkg_b.name);
			}
			return 1;
		}
	}
	return strcmp (pkg_a.name, pkg_b.name);
}

namespace Pamac {
	[DBus (name = "org.manjaro.pamac")]
	public class Daemon: Object {
		private AlpmConfig alpm_config;
		private Alpm.Handle? alpm_handle;
		private Alpm.Handle? files_handle;
		public Cond provider_cond;
		public Mutex provider_mutex;
		public int? choosen_provider;
		private bool force_refresh;
		private bool enable_downgrade;
		private bool check_aur_updates;
		private HashTable<string,Variant> new_alpm_conf;
		private Alpm.TransFlag flags;
		private string[] to_install;
		private string[] to_remove;
		private string[] to_load;
		private string[] to_build;
		private UpdateInfos[] to_build_infos;
		private GLib.List<string> aur_pkgbases_to_build;
		private GenericSet<string?> aur_desc_list;
		private GenericSet<string?> already_checked_aur_dep;
		private HashTable<string, string> to_install_as_dep;
		private string aurdb_path;
		private string[] temporary_ignorepkgs;
		private UpdateInfos[] aur_conflicts_to_remove;
		private ThreadPool<AlpmAction> thread_pool;
		private Mutex databases_lock_mutex;
		private Json.Array aur_updates_results;
		private HashTable<string, Json.Array> aur_search_results;
		private HashTable<string, Json.Object> aur_infos;
		private bool extern_lock;
		private GLib.File lockfile;
		public ErrorInfos current_error;
		public Timer timer;
		public Cancellable cancellable;
		public Curl.Easy curl;
		private bool authorized;

		public signal void emit_event (uint primary_event, uint secondary_event, string[] details);
		public signal void emit_providers (string depend, string[] providers);
		public signal void emit_progress (uint progress, string pkgname, uint percent, uint n_targets, uint current_target);
		public signal void emit_download (string filename, uint64 xfered, uint64 total);
		public signal void emit_totaldownload (uint64 total);
		public signal void emit_log (uint level, string msg);
		public signal void set_pkgreason_finished ();
		public signal void refresh_finished (bool success);
		public signal void get_updates_finished (Updates updates);
		public signal void trans_prepare_finished (bool success);
		public signal void trans_commit_finished (bool success);
		public signal void get_authorization_finished (bool authorized);
		public signal void write_pamac_config_finished (bool recurse, uint64 refresh_period, bool no_update_hide_icon,
														bool enable_aur, bool search_aur, bool check_aur_updates);
		public signal void write_alpm_config_finished (bool checkspace);
		public signal void write_mirrors_config_finished (string choosen_country, string choosen_generation_method);
		public signal void generate_mirrors_list_data (string line);
		public signal void generate_mirrors_list_finished ();

		public Daemon () {
			alpm_config = new AlpmConfig ("/etc/pacman.conf");
			databases_lock_mutex = Mutex ();
			aur_pkgbases_to_build = new GLib.List<string> ();
			aur_desc_list = new GenericSet<string?> (str_hash, str_equal);
			already_checked_aur_dep = new GenericSet<string?> (str_hash, str_equal);
			to_install_as_dep = new HashTable<string, string> (str_hash, str_equal);
			aurdb_path = "/tmp/pamac-aur";
			aur_updates_results = new Json.Array ();
			aur_search_results = new HashTable<string, Json.Array> (str_hash, str_equal);
			aur_infos = new HashTable<string, Json.Object> (str_hash, str_equal);
			timer = new Timer ();
			extern_lock = false;
			refresh_handle ();
			Timeout.add (500, check_extern_lock);
			create_thread_pool ();
			cancellable = new Cancellable ();
			curl = new Curl.Easy ();
			authorized = false;
		}

		public void set_environment_variables (HashTable<string,string> variables) {
			string[] keys = { "HTTP_USER_AGENT",
							"http_proxy",
							"https_proxy",
							"ftp_proxy",
							"socks_proxy",
							"no_proxy" };
			foreach (unowned string key in keys) {
				unowned string val;
				if (variables.lookup_extended (key, null, out val)) {
					Environment.set_variable (key, val, true);
				}
			}
		}

		public ErrorInfos get_current_error () {
			return current_error;
		}

		private void create_thread_pool () {
			// create a thread pool which will run alpm action one after one
			try {
				thread_pool = new ThreadPool<AlpmAction>.with_owned_data (
					// call alpm_action.run () on thread start
					(alpm_action) => {
						alpm_action.run ();
					},
					// only one thread created so alpm action will run one after one 
					1,
					// no exclusive thread
					false
				);
			} catch (ThreadError e) {
				stderr.printf ("Thread Error %s\n", e.message);
			}
		}

		private void refresh_handle () {
			alpm_handle = alpm_config.get_handle ();
			if (alpm_handle == null) {
				current_error = ErrorInfos () {
					message = _("Failed to initialize alpm library")
				};
				trans_commit_finished (false);
			} else {
				alpm_handle.eventcb = (Alpm.EventCallBack) cb_event;
				alpm_handle.progresscb = (Alpm.ProgressCallBack) cb_progress;
				alpm_handle.questioncb = (Alpm.QuestionCallBack) cb_question;
				alpm_handle.fetchcb = (Alpm.FetchCallBack) cb_fetch;
				alpm_handle.totaldlcb = (Alpm.TotalDownloadCallBack) cb_totaldownload;
				alpm_handle.logcb = (Alpm.LogCallBack) cb_log;
				lockfile = GLib.File.new_for_path (alpm_handle.lockfile);
			}
			files_handle = alpm_config.get_files_handle ();
		}

		private bool check_extern_lock () {
			if (extern_lock) {
				if (!lockfile.query_exists ()) {
					extern_lock = false;
					refresh_handle ();
					databases_lock_mutex.unlock ();
				}
			} else {
				if (lockfile.query_exists ()) {
					if (databases_lock_mutex.trylock ()) {
						extern_lock = true;
						// Functions trans_init, build_prepare and refresh threads are blocked until unlock.
						// An extern lock appears, check if it is not a too old lock.
						int exit_status;
						string output;
						uint64 lockfile_time;
						try {
							// get lockfile modification time since epoch
							Process.spawn_command_line_sync ("stat -c %Y %s".printf (alpm_handle.lockfile),
															out output,
															null,
															out exit_status);
							if (exit_status == 0) {
								string[] splitted = output.split ("\n");
								if (splitted.length == 2) {
									if (uint64.try_parse (splitted[0], out lockfile_time)) {
										uint64 boot_time;
										// get boot time since epoch
										Process.spawn_command_line_sync ("cat /proc/stat",
																		out output,
																		null,
																		out exit_status);
										if (exit_status == 0) {
											splitted = output.split ("\n");
											foreach (unowned string line in splitted) {
												if ("btime" in line) {
													string[] space_splitted = line.split (" ");
													if (space_splitted.length == 2) {
														if (uint64.try_parse (space_splitted[1], out boot_time)) {
															// check if lock file is older than boot time
															if (lockfile_time < boot_time) {
																// remove the unneeded lock file.
																try {
																	lockfile.delete ();
																} catch (Error e) {
																	stderr.printf ("Error: %s\n", e.message);
																}
																extern_lock = false;
																databases_lock_mutex.unlock ();
															}
														}
													}
												}
											}
										}
									}
								}
							}
						} catch (SpawnError e) {
							stderr.printf ("Error: %s\n", e.message);
						}
					}
				}
			}
			return true;
		}

		private async bool check_authorization (GLib.BusName sender) {
			if (authorized) {
				return true;
			}
			SourceFunc callback = check_authorization.callback;
			try {
				Polkit.Authority authority = Polkit.Authority.get_sync ();
				Polkit.Subject subject = Polkit.SystemBusName.new (sender);
				authority.check_authorization.begin (
					subject,
					"org.manjaro.pamac.commit",
					null,
					Polkit.CheckAuthorizationFlags.ALLOW_USER_INTERACTION,
					null,
					(obj, res) => {
						try {
							var result = authority.check_authorization.end (res);
							authorized = result.get_is_authorized ();
						} catch (GLib.Error e) {
							stderr.printf ("%s\n", e.message);
						}
						Idle.add ((owned) callback);
					}
				);
				yield;
			} catch (GLib.Error e) {
				stderr.printf ("%s\n", e.message);
			}
			if (!authorized) {
				current_error = ErrorInfos () {
					message = _("Authentication failed")
				};
			}
			return authorized;
		}

		public void start_get_authorization (GLib.BusName sender) {
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				get_authorization_finished (authorized);
			});
		}

		public void start_write_pamac_config (HashTable<string,Variant> new_pamac_conf, GLib.BusName sender) {
			check_authorization.begin (sender, (obj, res) => {
				var pamac_config = new Pamac.Config ("/etc/pamac.conf");
				bool authorized = check_authorization.end (res);
				if (authorized ) {
					pamac_config.write (new_pamac_conf);
					pamac_config.reload ();
				}
				write_pamac_config_finished (pamac_config.recurse, pamac_config.refresh_period, pamac_config.no_update_hide_icon,
											pamac_config.enable_aur, pamac_config.search_aur, pamac_config.check_aur_updates);
			});
		}

		private void write_alpm_config () {
			alpm_config.write (new_alpm_conf);
			alpm_config.reload ();
			databases_lock_mutex.lock ();
			refresh_handle ();
			databases_lock_mutex.unlock ();
			write_alpm_config_finished ((alpm_handle.checkspace == 1));
		}

		public void start_write_alpm_config (HashTable<string,Variant> new_alpm_conf_, GLib.BusName sender) {
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized ) {
					new_alpm_conf = new_alpm_conf_;
					try {
						thread_pool.add (new AlpmAction (write_alpm_config));
					} catch (ThreadError e) {
						stderr.printf ("Thread Error %s\n", e.message);
					}
				} else {
					write_alpm_config_finished ((alpm_handle.checkspace == 1));
				}
			});
		}

		private void generate_mirrors_list () {
			try {
				var process = new Subprocess.newv (
					{"pacman-mirrors", "-g"},
					SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
				var dis = new DataInputStream (process.get_stdout_pipe ());
				string? line;
				while ((line = dis.read_line ()) != null) {
					generate_mirrors_list_data (line);
				}
			} catch (Error e) {
				stderr.printf ("Error: %s\n", e.message);
			}
			alpm_config.reload ();
			databases_lock_mutex.lock ();
			refresh_handle ();
			databases_lock_mutex.unlock ();
			generate_mirrors_list_finished ();
		}

		public void start_generate_mirrors_list (GLib.BusName sender) {
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					try {
						thread_pool.add (new AlpmAction (generate_mirrors_list));
					} catch (ThreadError e) {
						stderr.printf ("Thread Error %s\n", e.message);
					}
				}
			});
		}

		public void clean_cache (uint keep_nb, bool only_uninstalled, GLib.BusName sender) {
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					string[] commands = {"paccache", "-rq"};
					commands += "-k%u".printf (keep_nb);
					if (only_uninstalled) {
						commands += "-u";
					}
					try {
						new Subprocess.newv (
							commands,
							SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
					} catch (Error e) {
						stderr.printf ("Error: %s\n", e.message);
					}
				}
			});
		}

		public void start_write_mirrors_config (HashTable<string,Variant> new_mirrors_conf, GLib.BusName sender) {
			var mirrors_config = new MirrorsConfig ("/etc/pacman-mirrors.conf");
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					mirrors_config.write (new_mirrors_conf);
					mirrors_config.reload ();
				}
				write_mirrors_config_finished (mirrors_config.choosen_country, mirrors_config.choosen_generation_method);
			});
		}

		public void start_set_pkgreason (string pkgname, uint reason, GLib.BusName sender) {
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					unowned Alpm.Package? pkg = alpm_handle.localdb.get_pkg (pkgname);
					if (pkg != null) {
						pkg.reason = (Alpm.Package.Reason) reason;
					}
				}
				set_pkgreason_finished ();
			});
		}

		private void refresh () {
			current_error = ErrorInfos ();
			if (!databases_lock_mutex.trylock ()) {
				// Wait for pacman to finish
				emit_event (0, 0, {});
				databases_lock_mutex.lock ();
			}
			if (cancellable.is_cancelled ()) {
				cancellable.reset ();
				refresh_finished (true);
				databases_lock_mutex.unlock ();
				return;
			}
			write_log_file ("synchronizing package lists");
			int force = (force_refresh) ? 1 : 0;
			uint success = 0;
			cancellable.reset ();
			string[] dbexts = {".db", ".files"};
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				if (cancellable.is_cancelled ()) {
					alpm_handle.dbext = ".db";
					refresh_finished (false);
					databases_lock_mutex.unlock ();
					return;
				}
				foreach (unowned string dbext in dbexts) {
					alpm_handle.dbext = dbext;
					if (db.update (force) >= 0) {
						success++;
					} else {
						Alpm.Errno errno = alpm_handle.errno ();
						current_error.errno = (uint) errno;
						if (errno != 0) {
							// download error details are set in cb_fetch
							if (errno != Alpm.Errno.EXTERNAL_DOWNLOAD) {
								current_error.details = { Alpm.strerror (errno) };
							}
						}
					}
				}
				syncdbs.next ();
			}
			alpm_handle.dbext = ".db";
			// We should always succeed if at least one DB was upgraded - we may possibly
			// fail later with unresolved deps, but that should be rare, and would be expected
			if (success == 0) {
				current_error.message = _("Failed to synchronize any databases");
				refresh_finished (false);
			} else {
				refresh_finished (true);
			}
			databases_lock_mutex.unlock ();
		}

		public void start_refresh (bool force) {
			force_refresh = force;
			try {
				thread_pool.add (new AlpmAction (refresh));
			} catch (ThreadError e) {
				stderr.printf ("Thread Error %s\n", e.message);
			}
		}

		public bool get_checkspace () {
			return alpm_handle.checkspace == 1 ? true : false;
		}

		public string get_lockfile () {
			return alpm_handle.lockfile;
		}

		public string[] get_ignorepkgs () {
			string[] result = {};
			unowned Alpm.List<unowned string> ignorepkgs = alpm_handle.ignorepkgs;
			while (ignorepkgs != null) {
				unowned string ignorepkg = ignorepkgs.data;
				result += ignorepkg;
				ignorepkgs.next ();
			}
			return result;
		}

		private void add_ignorepkgs () {
			foreach (unowned string pkgname in temporary_ignorepkgs) {
				alpm_handle.add_ignorepkg (pkgname);
			}
		}

		private void remove_ignorepkgs () {
			foreach (unowned string pkgname in temporary_ignorepkgs) {
				alpm_handle.remove_ignorepkg (pkgname);
			}
			temporary_ignorepkgs = {};
		}

		public bool should_hold (string pkgname) {
			if (alpm_config.get_holdpkgs ().find_custom (pkgname, strcmp) != null) {
				return true;
			}
			return false;
		}

		public uint get_pkg_reason (string pkgname) {
			unowned Alpm.Package? pkg = alpm_handle.localdb.get_pkg (pkgname);
			if (pkg != null) {
				return pkg.reason;
			}
			return 0;
		}

		public uint get_pkg_origin (string pkgname) {
			unowned Alpm.Package? pkg = alpm_handle.localdb.get_pkg (pkgname);
			if (pkg != null) {
				return pkg.origin;
			} else {
				pkg = get_syncpkg (pkgname);
				if (pkg != null) {
					return pkg.origin;
				}
			}
			return 0;
		}

		private AlpmPackage initialise_pkg_struct (Alpm.Package? alpm_pkg) {
			if (alpm_pkg != null) {
				string repo_name = "";
				if (alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
					unowned Alpm.Package? sync_pkg = get_syncpkg (alpm_pkg.name);
					if (sync_pkg != null) {
						repo_name = sync_pkg.db.name;
					}
				} else if (alpm_pkg.origin == Alpm.Package.From.SYNCDB) {
					repo_name = alpm_pkg.db.name;
				}
				return AlpmPackage () {
					name = alpm_pkg.name,
					version = alpm_pkg.version,
					// desc can be null
					desc = alpm_pkg.desc ?? "",
					repo = (owned) repo_name,
					size = alpm_pkg.isize,
					origin = (uint) alpm_pkg.origin
				};
			} else {
				return AlpmPackage () {
					name = "",
					version = "",
					desc = "",
					repo = ""
				};
			}
		}

		public async AlpmPackage[] get_installed_pkgs () {
			AlpmPackage[] pkgs = {};
			unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
			while (pkgcache != null) {
				unowned Alpm.Package alpm_pkg = pkgcache.data;
				pkgs += initialise_pkg_struct (alpm_pkg);
				pkgcache.next ();
			}
			return pkgs;
		}

		public async AlpmPackage[] get_explicitly_installed_pkgs () {
			AlpmPackage[] pkgs = {};
			unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
			while (pkgcache != null) {
				unowned Alpm.Package alpm_pkg = pkgcache.data;
				if (alpm_pkg.reason == Alpm.Package.Reason.EXPLICIT) {
					pkgs += initialise_pkg_struct (alpm_pkg);
				}
				pkgcache.next ();
			}
			return pkgs;
		}

		public async AlpmPackage[] get_foreign_pkgs () {
			AlpmPackage[] pkgs = {};
			unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
			while (pkgcache != null) {
				unowned Alpm.Package alpm_pkg = pkgcache.data;
				bool sync_found = false;
				unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
				while (syncdbs != null) {
					unowned Alpm.DB db = syncdbs.data;
					unowned Alpm.Package? sync_pkg = db.get_pkg (alpm_pkg.name);
					if (sync_pkg != null) {
						sync_found = true;
						break;
					}
					syncdbs.next ();
				}
				if (sync_found == false) {
					pkgs += initialise_pkg_struct (alpm_pkg);
				}
				pkgcache.next ();
			}
			return pkgs;
		}

		public async AlpmPackage[] get_orphans () {
			AlpmPackage[] pkgs = {};
			unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
			while (pkgcache != null) {
				unowned Alpm.Package alpm_pkg = pkgcache.data;
				if (alpm_pkg.reason == Alpm.Package.Reason.DEPEND) {
					Alpm.List<string> requiredby = alpm_pkg.compute_requiredby ();
					if (requiredby.length == 0) {
						Alpm.List<string> optionalfor = alpm_pkg.compute_optionalfor ();
						if (optionalfor.length == 0) {
							pkgs += initialise_pkg_struct (alpm_pkg);
						} else {
							optionalfor.free_inner (GLib.free);
						}
					} else {
						requiredby.free_inner (GLib.free);
					}
				}
				pkgcache.next ();
			}
			return pkgs;
		}

		public AlpmPackage get_installed_pkg (string pkgname) {
			return initialise_pkg_struct (alpm_handle.localdb.get_pkg (pkgname));
		}

		public AlpmPackage find_installed_satisfier (string depstring) {
			return initialise_pkg_struct (Alpm.find_satisfier (alpm_handle.localdb.pkgcache, depstring));
		}

		private unowned Alpm.Package? get_syncpkg (string name) {
			unowned Alpm.Package? pkg = null;
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				pkg = db.get_pkg (name);
				if (pkg != null) {
					break;
				}
				syncdbs.next ();
			}
			return pkg;
		}

		public AlpmPackage get_sync_pkg (string pkgname) {
			return initialise_pkg_struct (get_syncpkg (pkgname));
		}

		private unowned Alpm.Package? find_dbs_satisfier (string depstring) {
			unowned Alpm.Package? pkg = null;
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				pkg = Alpm.find_satisfier (db.pkgcache, depstring);
				if (pkg != null) {
					break;
				}
				syncdbs.next ();
			}
			return pkg;
		}

		public AlpmPackage find_sync_satisfier (string depstring) {
			return initialise_pkg_struct (find_dbs_satisfier (depstring));
		}

		private Alpm.List<unowned Alpm.Package> search_all_dbs (string search_string) {
			Alpm.List<unowned string> needles = null;
			string[] splitted = search_string.split (" ");
			foreach (unowned string part in splitted) {
				needles.add (part);
			}
			Alpm.List<unowned Alpm.Package> result = alpm_handle.localdb.search (needles);
			Alpm.List<unowned Alpm.Package> syncpkgs = null;
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				if (syncpkgs.length == 0) {
					syncpkgs = db.search (needles);
				} else {
					syncpkgs.join (db.search (needles).diff (syncpkgs, (Alpm.List.CompareFunc) alpm_pkg_compare_name));
				}
				syncdbs.next ();
			}
			result.join (syncpkgs.diff (result, (Alpm.List.CompareFunc) alpm_pkg_compare_name));
			// use custom sort function
			global_search_string = search_string;
			result.sort (result.length, (Alpm.List.CompareFunc) alpm_pkg_sort_search_by_relevance);
			return result;
		}

		public async AlpmPackage[] search_pkgs (string search_string) {
			AlpmPackage[] result = {};
			Alpm.List<unowned Alpm.Package> alpm_pkgs = search_all_dbs (search_string);
			unowned Alpm.List<unowned Alpm.Package> list = alpm_pkgs;
			while (list != null) {
				unowned Alpm.Package alpm_pkg = list.data;
				result += initialise_pkg_struct (alpm_pkg);
				list.next ();
			}
			return result;
		}

		private AURPackage initialise_aur_struct (Json.Object json_object) {
			return AURPackage () {
				name = json_object.get_string_member ("Name"),
				version = json_object.get_string_member ("Version"),
				// desc can be null
				desc = json_object.get_null_member ("Description") ? "" : json_object.get_string_member ("Description"),
				popularity = json_object.get_double_member ("Popularity")
			};
		}

		public async AURPackage[] search_in_aur (string search_string) {
			if (!aur_search_results.contains (search_string)) {
				Json.Array pkgs = yield AUR.search (search_string.split (" "));
				aur_search_results.insert (search_string, pkgs);
			}
			AURPackage[] result = {};
			Json.Array aur_pkgs = aur_search_results.get (search_string);
			aur_pkgs.foreach_element ((array, index, node) => {
				Json.Object aur_pkg = node.get_object ();
				// remove results which exist in repos
				if (get_syncpkg (aur_pkg.get_string_member ("Name")) == null) {
					result += initialise_aur_struct (node.get_object ());
				}
			});
			return result;
		}

		public async AURPackageDetails get_aur_details (string pkgname) {
			string name = "";
			string version = "";
			string desc = "";
			double popularity = 0;
			string packagebase = "";
			string url = "";
			string maintainer = "";
			int64 firstsubmitted = 0;
			int64 lastmodified = 0;
			int64 outofdate = 0;
			int64 numvotes = 0;
			string[] licenses = {};
			string[] depends = {};
			string[] makedepends = {};
			string[] checkdepends = {};
			string[] optdepends = {};
			string[] provides = {};
			string[] replaces = {};
			string[] conflicts = {};
			var details = AURPackageDetails ();
			if (!aur_infos.contains (pkgname)) {
				Json.Array results = yield AUR.multiinfo ({pkgname});
				if (results.get_length () > 0) {
					aur_infos.insert (pkgname, results.get_object_element (0));
				}
			}
			unowned Json.Object? json_object = aur_infos.lookup (pkgname);
			if (json_object != null) {
				// name
				name = json_object.get_string_member ("Name");
				// version
				version = json_object.get_string_member ("Version");
				// desc can be null
				if (!json_object.get_null_member ("Description")) {
					desc = json_object.get_string_member ("Description");
				}
				popularity = json_object.get_double_member ("Popularity");
				// packagebase
				packagebase = json_object.get_string_member ("PackageBase");
				// url can be null
				unowned Json.Node? node = json_object.get_member ("URL");
				if (!node.is_null ()) {
					url = node.get_string ();
				}
				// maintainer can be null
				node = json_object.get_member ("Maintainer");
				if (!node.is_null ()) {
					maintainer = node.get_string ();
				}
				// firstsubmitted
				firstsubmitted = json_object.get_int_member ("FirstSubmitted");
				// lastmodified
				lastmodified = json_object.get_int_member ("LastModified");
				// outofdate can be null
				node = json_object.get_member ("OutOfDate");
				if (!node.is_null ()) {
					outofdate = node.get_int ();
				}
				//numvotes
				numvotes = json_object.get_int_member ("NumVotes");
				// licenses
				node = json_object.get_member ("License");
				if (!node.is_null ()) {
					node.get_array ().foreach_element ((array, index, _node) => {
						licenses += _node.get_string ();
					});
				} else {
					licenses += _("Unknown");
				}
				// depends
				node = json_object.get_member ("Depends");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						depends += _node.get_string ();
					});
				}
				// optdepends
				node = json_object.get_member ("OptDepends");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						optdepends += _node.get_string ();
					});
				}
				// makedepends
				node = json_object.get_member ("MakeDepends");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						makedepends += _node.get_string ();
					});
				}
				// checkdepends
				node = json_object.get_member ("CheckDepends");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						checkdepends += _node.get_string ();
					});
				}
				// provides
				node = json_object.get_member ("Provides");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						provides += _node.get_string ();
					});
				}
				// replaces
				node = json_object.get_member ("Replaces");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						replaces += _node.get_string ();
					});
				}
				// conflicts
				node = json_object.get_member ("Conflicts");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						conflicts += _node.get_string ();
					});
				}
			}
			details.name = (owned) name;
			details.version = (owned) version ;
			details.desc = (owned) desc;
			details.popularity = popularity;
			details.packagebase = (owned) packagebase;
			details.url = (owned) url;
			details.maintainer = (owned) maintainer ;
			details.firstsubmitted = firstsubmitted;
			details.lastmodified = lastmodified;
			details.outofdate = outofdate;
			details.numvotes = numvotes;
			details.licenses = (owned) licenses;
			details.depends = (owned) depends;
			details.optdepends = (owned) optdepends;
			details.checkdepends = (owned) checkdepends;
			details.makedepends = (owned) makedepends;
			details.provides = (owned) provides;
			details.replaces = (owned) replaces;
			details.conflicts = (owned) conflicts;
			return details;
		}

		private async void compute_aur_build_list (string[] aur_list) {
			try {
				Process.spawn_command_line_sync ("mkdir -p %s".printf (aurdb_path));
			} catch (SpawnError e) {
				stderr.printf ("SpawnError: %s\n", e.message);
			}
			aur_desc_list.remove_all ();
			already_checked_aur_dep.remove_all ();
			yield check_aur_dep_list (aur_list);
		}

		private string splitdep (string depstring) {
			// split depmod and version from name
			string result;
			string[] splitted = depstring.split (">", 2);
			if (splitted.length > 1) {
				result = splitted[0];
			} else {
				splitted = depstring.split ("<", 2);
				if (splitted.length > 1) {
					result = splitted[0];
				} else {
					splitted = depstring.split ("=", 2);
					if (splitted.length > 1) {
						result = splitted[0];
					} else {
						result = depstring;
					}
				}
			}
			return result;
		}

		private async void check_aur_dep_list (string[] pkgnames) {
			string[] dep_types = {"Depends", "MakeDepends", "CheckDepends"};
			string[] dep_to_check = {};
			Json.Array results = yield AUR.multiinfo (pkgnames);
			results.foreach_element ((array, index, node) => {
				unowned Json.Object? pkg_info = node.get_object ();
				// create fake db desc file
				if (pkg_info != null) {
					string name = pkg_info.get_string_member ("Name");
					string version = pkg_info.get_string_member ("Version");
					string pkgdir = "%s-%s".printf (name, version);
					string pkgdir_path = "%s/%s".printf (aurdb_path, pkgdir);
					aur_desc_list.add (pkgdir);
					already_checked_aur_dep.add (name);
					try {
						var file = GLib.File.new_for_path (pkgdir_path);
						bool write_desc_file = false;
						if (!file.query_exists ()) {
							file.make_directory ();
							write_desc_file = true;
						}
						// compute depends, makedepends and checkdepends in DEPENDS
						var depends = new StringBuilder ();
						foreach (unowned string dep_type in dep_types) {
							unowned Json.Node? dep_node = pkg_info.get_member (dep_type);
							if (dep_node != null) {
								dep_node.get_array ().foreach_element ((array, index, node) => {
									if (write_desc_file) {
										depends.append (node.get_string ());
										depends.append ("\n");
									}
									// check deps
									unowned string dep_string = node.get_string ();
									string dep_name = splitdep (dep_string);
									unowned Alpm.Package? pkg = null;
									// search for the name first to avoid provides trouble
									pkg = alpm_handle.localdb.get_pkg (dep_name);
									if (pkg == null) {
										pkg = get_syncpkg (dep_name);
									}
									if (pkg == null) {
										if (!(dep_name in already_checked_aur_dep)) {
											dep_to_check += (owned) dep_name;
										}
									}
								});
							}
						}
						if (write_desc_file) {
							file = GLib.File.new_for_path ("%s/desc".printf (pkgdir_path));
							// creating a DataOutputStream to the file
							var dos = new DataOutputStream (file.create (FileCreateFlags.REPLACE_DESTINATION));
							// fake filename
							dos.put_string ("%FILENAME%\n" + "%s-%s-any.pkg.tar.xz\n\n".printf (name, version));
							// name
							dos.put_string ("%NAME%\n%s\n\n".printf (name));
							// version
							dos.put_string ("%VERSION%\n%s\n\n".printf (version));
							//base
							dos.put_string ("%BASE%\n%s\n\n".printf (pkg_info.get_string_member ("PackageBase")));
							// desc can be null
							if (!pkg_info.get_null_member ("Description")) {
								dos.put_string ("%DESC%\n%s\n\n".printf (pkg_info.get_string_member ("Description")));
							}
							// version
							dos.put_string ("%VERSION%\n%s\n\n".printf (pkg_info.get_string_member ("Version")));
							// fake arch
							dos.put_string ("%ARCH%\nany\n\n");
							// depends
							if (depends.len > 0) {
								dos.put_string ("%DEPENDS%\n%s\n".printf (depends.str));
							}
							// conflicts
							unowned Json.Node? info_node = pkg_info.get_member ("Conflicts");
							if (info_node != null) {
								try {
									dos.put_string ("%CONFLICTS%\n");
									info_node.get_array ().foreach_element ((array, index, _node) => {
										try {
											dos.put_string ("%s\n".printf (_node.get_string ()));
										} catch (GLib.Error e) {
											GLib.stderr.printf("%s\n", e.message);
										}
									});
									dos.put_string ("\n");
								} catch (GLib.Error e) {
									GLib.stderr.printf("%s\n", e.message);
								}
							}
							// provides
							info_node = pkg_info.get_member ("Provides");
							if (info_node != null) {
								try {
									dos.put_string ("%PROVIDES%\n");
									info_node.get_array ().foreach_element ((array, index, _node) => {
										try {
											dos.put_string ("%s\n".printf (_node.get_string ()));
										} catch (GLib.Error e) {
											GLib.stderr.printf("%s\n", e.message);
										}
									});
									dos.put_string ("\n");
								} catch (GLib.Error e) {
									GLib.stderr.printf("%s\n", e.message);
								}
							}
							// replaces
							info_node = pkg_info.get_member ("Replaces");
							if (info_node != null) {
								try {
									dos.put_string ("%REPLACES%\n");
									info_node.get_array ().foreach_element ((array, index, _node) => {
										try {
											dos.put_string ("%s\n".printf (_node.get_string ()));
										} catch (GLib.Error e) {
											GLib.stderr.printf("%s\n", e.message);
										}
									});
									dos.put_string ("\n");
								} catch (GLib.Error e) {
									GLib.stderr.printf("%s\n", e.message);
								}
							}
						}
					} catch (GLib.Error e) {
						GLib.stderr.printf("%s\n", e.message);
					}
				}
			});
			if (dep_to_check.length > 0) {
				yield check_aur_dep_list (dep_to_check);
			}
		}

		public string[] get_repos_names () {
			string[] repos_names = {};
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				repos_names += db.name;
				syncdbs.next ();
			}
			return repos_names;
		}

		public async AlpmPackage[] get_repo_pkgs (string repo) {
			AlpmPackage[] pkgs = {};
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				if (db.name == repo) {
					unowned Alpm.List<unowned Alpm.Package> pkgcache = db.pkgcache;
					while (pkgcache != null) {
						unowned Alpm.Package sync_pkg = pkgcache.data;
						unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (sync_pkg.name);
						if (local_pkg != null) {
							pkgs += initialise_pkg_struct (local_pkg);
						} else {
							pkgs += initialise_pkg_struct (sync_pkg);
						}
						pkgcache.next ();
					}
					break;
				}
				syncdbs.next ();
			}
			return pkgs;
		}

		public string[] get_groups_names () {
			string[] groups_names = {};
			unowned Alpm.List<unowned Alpm.Group> groupcache = alpm_handle.localdb.groupcache;
			while (groupcache != null) {
				unowned Alpm.Group group = groupcache.data;
				if (!(group.name in groups_names)) { 
					groups_names += group.name;
				}
				groupcache.next ();
			}
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				groupcache = db.groupcache;
				while (groupcache != null) {
					unowned Alpm.Group group = groupcache.data;
					if (!(group.name in groups_names)) { 
						groups_names += group.name;
					}
					groupcache.next ();
				}
				syncdbs.next ();
			}
			return groups_names;
		}

		private Alpm.List<unowned Alpm.Package> group_pkgs (string group_name) {
			Alpm.List<unowned Alpm.Package> result = null;
			unowned Alpm.Group? grp = alpm_handle.localdb.get_group (group_name);
			if (grp != null) {
				unowned Alpm.List<unowned Alpm.Package> packages = grp.packages;
				while (packages != null) {
					unowned Alpm.Package pkg = packages.data;
					result.add (pkg);
					packages.next ();
				}
			}
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				grp = db.get_group (group_name);
				if (grp != null) {
					unowned Alpm.List<unowned Alpm.Package> packages = grp.packages;
					while (packages != null) {
						unowned Alpm.Package pkg = packages.data;
						if (result.find (pkg, (Alpm.List.CompareFunc) alpm_pkg_compare_name) == null) {
							result.add (pkg);
						}
						packages.next ();
					}
				}
				syncdbs.next ();
			}
			return result;
		}

		public async AlpmPackage[] get_group_pkgs (string groupname) {
			AlpmPackage[] pkgs = {};
			Alpm.List<unowned Alpm.Package> alpm_pkgs = group_pkgs (groupname);
			unowned Alpm.List<unowned Alpm.Package> list = alpm_pkgs;
			while (list != null) {
				unowned Alpm.Package alpm_pkg = list.data;
				pkgs += initialise_pkg_struct (alpm_pkg);
				list.next ();
			}
			return pkgs;
		}

		public string[] get_pkg_uninstalled_optdeps (string pkgname) {
			string[] optdeps = {};
			unowned Alpm.Package? alpm_pkg = alpm_handle.localdb.get_pkg (pkgname);
			if (alpm_pkg == null) {
				alpm_pkg = get_syncpkg (pkgname);
			}
			if (alpm_pkg != null) {
				unowned Alpm.List<unowned Alpm.Depend> optdepends = alpm_pkg.optdepends;
				while (optdepends != null) {
					unowned Alpm.Depend optdep = optdepends.data;
					if (Alpm.find_satisfier (alpm_handle.localdb.pkgcache, optdep.name) == null) {
						optdeps += optdep.compute_string ();
					}
					optdepends.next ();
				}
			}
			return optdeps;
		}

		public AlpmPackageDetails get_pkg_details (string pkgname) {
			string name = "";
			string version = "";
			string desc = "";
			string url = "";
			string repo = "";
			string has_signature = "";
			string reason = "";
			string packager = "";
			string builddate = "";
			string installdate = "";
			string[] groups = {};
			string[] backups = {};
			string[] licenses = {};
			string[] depends = {};
			string[] optdepends = {};
			string[] requiredby = {};
			string[] optionalfor = {};
			string[] provides = {};
			string[] replaces = {};
			string[] conflicts = {};
			var details = AlpmPackageDetails ();
			unowned Alpm.Package? alpm_pkg = alpm_handle.localdb.get_pkg (pkgname);
			if (alpm_pkg == null) {
				alpm_pkg = get_syncpkg (pkgname);
			}
			if (alpm_pkg != null) {
				// name
				name = alpm_pkg.name;
				// version
				version = alpm_pkg.version;
				// desc can be null
				if (alpm_pkg.desc != null) {
					desc = alpm_pkg.desc;
				}
				details.origin = (uint) alpm_pkg.origin;
				// url can be null
				if (alpm_pkg.url != null) {
					url = alpm_pkg.url;
				}
				// packager can be null
				packager = alpm_pkg.packager ?? "";
				// groups
				unowned Alpm.List list = alpm_pkg.groups;
				while (list != null) {
					groups += ((Alpm.List<unowned string>) list).data;
					list.next ();
				}
				// licenses
				list = alpm_pkg.licenses;
				while (list != null) {
					licenses += ((Alpm.List<unowned string>) list).data;
					list.next ();
				}
				// build_date
				GLib.Time time = GLib.Time.local ((time_t) alpm_pkg.builddate);
				builddate = time.format ("%a %d %b %Y %X %Z");
				// local pkg
				if (alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
					// repo
					unowned Alpm.Package? sync_pkg = get_syncpkg (alpm_pkg.name);
					if (sync_pkg != null) {
						repo = sync_pkg.db.name;
					}
					// reason
					if (alpm_pkg.reason == Alpm.Package.Reason.EXPLICIT) {
						reason = _("Explicitly installed");
					} else if (alpm_pkg.reason == Alpm.Package.Reason.DEPEND) {
						reason = _("Installed as a dependency for another package");
					} else {
						reason = _("Unknown");
					}
					// install_date
					time = GLib.Time.local ((time_t) alpm_pkg.installdate);
					installdate = time.format ("%a %d %b %Y %X %Z");
					// backups
					list = alpm_pkg.backups;
					while (list != null) {
						backups += "/" + ((Alpm.List<unowned Alpm.Backup>) list).data.name;
						list.next ();
					}
					// requiredby
					Alpm.List<string> pkg_requiredby = alpm_pkg.compute_requiredby ();
					list = pkg_requiredby;
					while (list != null) {
						requiredby += ((Alpm.List<unowned string>) list).data;
						list.next ();
					}
					pkg_requiredby.free_inner (GLib.free);
					// optionalfor
					Alpm.List<string> pkg_optionalfor = alpm_pkg.compute_optionalfor ();
					list = pkg_optionalfor;
					while (list != null) {
						optionalfor += ((Alpm.List<unowned string>) list).data;
						list.next ();
					}
					pkg_optionalfor.free_inner (GLib.free);
				// sync pkg
				} else if (alpm_pkg.origin == Alpm.Package.From.SYNCDB) {
					// repos
					repo = alpm_pkg.db.name;
					// signature
					has_signature = alpm_pkg.base64_sig != null ? _("Yes") : _("No");
				}
				// depends
				list = alpm_pkg.depends;
				while (list != null) {
					depends += ((Alpm.List<unowned Alpm.Depend>) list).data.compute_string ();
					list.next ();
				}
				// optdepends
				list = alpm_pkg.optdepends;
				while (list != null) {
					optdepends += ((Alpm.List<unowned Alpm.Depend>) list).data.compute_string ();
					list.next ();
				}
				// provides
				list = alpm_pkg.provides;
				while (list != null) {
					provides += ((Alpm.List<unowned Alpm.Depend>) list).data.compute_string ();
					list.next ();
				}
				// replaces
				list = alpm_pkg.replaces;
				while (list != null) {
					replaces += ((Alpm.List<unowned Alpm.Depend>) list).data.compute_string ();
					list.next ();
				}
				// conflicts
				list = alpm_pkg.conflicts;
				while (list != null) {
					conflicts += ((Alpm.List<unowned Alpm.Depend>) list).data.compute_string ();
					list.next ();
				}
			}
			details.name = (owned) name;
			details.version = (owned) version;
			details.desc = (owned) desc;
			details.repo = (owned) repo;
			details.url = (owned) url;
			details.packager = (owned) packager;
			details.builddate = (owned) builddate;
			details.installdate = (owned) installdate;
			details.reason = (owned) reason;
			details.has_signature = (owned) has_signature;
			details.licenses = (owned) licenses;
			details.depends = (owned) depends;
			details.optdepends = (owned) optdepends;
			details.requiredby = (owned) requiredby;
			details.optionalfor = (owned) optionalfor;
			details.provides = (owned) provides;
			details.replaces = (owned) replaces;
			details.conflicts = (owned) conflicts;
			details.groups = (owned) groups;
			details.backups = (owned) backups;
			return details;
		}

		public string[] get_pkg_files (string pkgname) {
			string[] files = {};
			unowned Alpm.Package? alpm_pkg = alpm_handle.localdb.get_pkg (pkgname);
			if (alpm_pkg != null) {
				unowned Alpm.FileList filelist = alpm_pkg.files;
				Alpm.File* file_ptr = filelist.files;
				for (size_t i = 0; i < filelist.count; i++, file_ptr++) {
					if (!file_ptr->name.has_suffix ("/")) {
						files += "/" + file_ptr->name;
					}
				}
			} else {
				unowned Alpm.List<unowned Alpm.DB> syncdbs = files_handle.syncdbs;
				while (syncdbs != null) {
					unowned Alpm.DB db = syncdbs.data;
					unowned Alpm.Package? files_pkg = db.get_pkg (pkgname);
					if (files_pkg != null) {
						unowned Alpm.FileList filelist = files_pkg.files;
						Alpm.File* file_ptr = filelist.files;
						for (size_t i = 0; i < filelist.count; i++, file_ptr++) {
							if (!file_ptr->name.has_suffix ("/")) {
								files += "/" + file_ptr->name;
							}
						}
						break;
					}
					syncdbs.next ();
				}
			}
			return files;
		}

		private void get_updates () {
			UpdateInfos[] updates_infos = {};
			unowned Alpm.Package? pkg = null;
			unowned Alpm.Package? candidate = null;
			foreach (unowned string name in alpm_config.get_syncfirsts ()) {
				pkg = Alpm.find_satisfier (alpm_handle.localdb.pkgcache, name);
				if (pkg != null) {
					candidate = pkg.sync_newversion (alpm_handle.syncdbs);
					if (candidate != null) {
						var infos = UpdateInfos () {
							name = candidate.name,
							old_version = pkg.version,
							new_version = candidate.version,
							repo = candidate.db.name,
							download_size = candidate.download_size
						};
						updates_infos += (owned) infos;
					}
				}
			}
			if (updates_infos.length != 0) {
				var updates = Updates () {
					is_syncfirst = true,
					repos_updates = (owned) updates_infos,
					aur_updates = {}
				};
				get_updates_finished (updates);
			} else {
				string[] local_pkgs = {};
				unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
				while (pkgcache != null) {
					unowned Alpm.Package installed_pkg = pkgcache.data;
					// check if installed_pkg is in IgnorePkg or IgnoreGroup
					if (alpm_handle.should_ignore (installed_pkg) == 0) {
						candidate = installed_pkg.sync_newversion (alpm_handle.syncdbs);
						if (candidate != null) {
							var infos = UpdateInfos () {
								name = candidate.name,
								old_version = installed_pkg.version,
								new_version = candidate.version,
								repo = candidate.db.name,
								download_size = candidate.download_size
							};
							updates_infos += (owned) infos;
						} else {
							if (check_aur_updates && (aur_updates_results.get_length () == 0)) {
								// check if installed_pkg is a local pkg
								unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
								while (syncdbs != null) {
									unowned Alpm.DB db = syncdbs.data;
									pkg = Alpm.find_satisfier (db.pkgcache, installed_pkg.name);
									if (pkg != null) {
										break;
									}
									syncdbs.next ();
								}
								if (pkg == null) {
									local_pkgs += installed_pkg.name;
								}
							}
						}
					}
					pkgcache.next ();
				}
				if (check_aur_updates) {
					// get aur updates
					if (aur_updates_results.get_length () == 0) {
						AUR.multiinfo.begin (local_pkgs, (obj, res) => {
							aur_updates_results = AUR.multiinfo.end (res);
							var updates = Updates () {
								is_syncfirst = false,
								repos_updates = (owned) updates_infos,
								aur_updates = get_aur_updates_infos ()
							};
							get_updates_finished (updates);
						});
					} else {
						var updates = Updates () {
							is_syncfirst = false,
							repos_updates = (owned) updates_infos,
							aur_updates = get_aur_updates_infos ()
						};
						get_updates_finished (updates);
					}
				} else {
					var updates = Updates () {
						is_syncfirst = false,
						repos_updates = (owned) updates_infos,
						aur_updates = {}
					};
					get_updates_finished (updates);
				}
			}
		}

		private UpdateInfos[] get_aur_updates_infos () {
			UpdateInfos[] aur_updates_infos = {};
			aur_updates_results.foreach_element ((array, index, node) => {
				unowned Json.Object pkg_info = node.get_object ();
				unowned string name = pkg_info.get_string_member ("Name");
				unowned string new_version = pkg_info.get_string_member ("Version");
				unowned string old_version = alpm_handle.localdb.get_pkg (name).version;
				if (Alpm.pkg_vercmp (new_version, old_version) == 1) {
					var infos = UpdateInfos () {
						name = name,
						old_version = old_version,
						new_version = new_version,
						repo = ""
					};
					aur_updates_infos += (owned) infos;
				}
			});
			return aur_updates_infos;
		}

		public void start_get_updates (bool check_aur_updates_) {
			check_aur_updates = check_aur_updates_;
			try {
				thread_pool.add (new AlpmAction (get_updates));
			} catch (ThreadError e) {
				stderr.printf ("Thread Error %s\n", e.message);
			}
		}

		private bool trans_init (Alpm.TransFlag flags) {
			current_error = ErrorInfos ();
			if (!databases_lock_mutex.trylock ()) {
				// Wait for pacman to finish
				emit_event (0, 0, {});
				databases_lock_mutex.lock ();
			}
			if (cancellable.is_cancelled ()) {
				cancellable.reset ();
				databases_lock_mutex.unlock ();
				return false;
			}
			cancellable.reset ();
			if (alpm_handle.trans_init (flags) == -1) {
				Alpm.Errno errno = alpm_handle.errno ();
				current_error.errno = (uint) errno;
				current_error.message = _("Failed to init transaction");
				if (errno != 0) {
					current_error.details = { Alpm.strerror (errno) };
				}
				databases_lock_mutex.unlock ();
				return false;
			}
			return true;
		}

		private void sysupgrade_prepare () {
			current_error = ErrorInfos ();
			bool success = trans_init (0);
			if (success) {
				add_ignorepkgs ();
				if (alpm_handle.trans_sysupgrade ((enable_downgrade) ? 1 : 0) == -1) {
					Alpm.Errno errno = alpm_handle.errno ();
					current_error.errno = (uint) errno;
					current_error.message = _("Failed to prepare transaction");
					if (errno != 0) {
						current_error.details = { Alpm.strerror (errno) };
					}
					trans_release ();
					success = false;
				} else {
					success = trans_prepare_real ();
				}
			}
			trans_prepare_finished (success);
		}

		public void start_sysupgrade_prepare_ (bool enable_downgrade_, string[] temporary_ignorepkgs_) {
			enable_downgrade = enable_downgrade_;
			temporary_ignorepkgs = temporary_ignorepkgs_;
			try {
				thread_pool.add (new AlpmAction (sysupgrade_prepare));
			} catch (ThreadError e) {
				stderr.printf ("Thread Error %s\n", e.message);
			}
		}

		private bool trans_add_pkg_real (Alpm.Package pkg) {
			current_error = ErrorInfos ();
			if (alpm_handle.trans_add_pkg (pkg) == -1) {
				Alpm.Errno errno = alpm_handle.errno ();
				if (errno == Alpm.Errno.TRANS_DUP_TARGET || errno == Alpm.Errno.PKG_IGNORED) {
					// just skip duplicate or ignored targets
					return true;
				} else {
					current_error.errno = (uint) errno;
					current_error.message = _("Failed to prepare transaction");
					if (errno != 0) {
						current_error.details = { "%s: %s".printf (pkg.name, Alpm.strerror (errno)) };
					}
					return false;
				}
			}
			return true;
		}

		private bool trans_add_pkg (string pkgname) {
			current_error = ErrorInfos ();
			unowned Alpm.Package? pkg = get_syncpkg (pkgname);
			if (pkg == null) {
				current_error.message = _("Failed to prepare transaction");
				current_error.details = { _("target not found: %s").printf (pkgname) };
				return false;
			} else {
				bool success = trans_add_pkg_real (pkg);
				if (success) {
					if (("linux31" in pkg.name) || ("linux4" in pkg.name)) {
						string[] installed_kernels = {};
						string[] installed_modules = {};
						unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
						while (pkgcache != null) {
							unowned Alpm.Package local_pkg = pkgcache.data;
							if (("linux31" in local_pkg.name) || ("linux4" in local_pkg.name)) {
								string[] local_pkg_splitted = local_pkg.name.split ("-", 2);
								if ((local_pkg_splitted[0] in installed_kernels) == false) {
									installed_kernels += local_pkg_splitted[0];
								}
								if (local_pkg_splitted.length == 2) {
									if ((local_pkg_splitted[1] in installed_modules) == false) {
										installed_modules += local_pkg_splitted[1];
									}
								}
							}
							pkgcache.next ();
						}
						string[] splitted = pkg.name.split ("-", 2);
						if (splitted.length == 2) {
							// we are adding a module
							// add the same module for other installed kernels
							foreach (unowned string installed_kernel in installed_kernels) {
								string module = installed_kernel + "-" + splitted[1];
								unowned Alpm.Package? module_pkg = get_syncpkg (module);
								if (module_pkg != null) {
									trans_add_pkg_real (module_pkg);
								}
							}
						} else if (splitted.length == 1) {
							// we are adding a kernel
							// add all installed modules for other kernels
							foreach (unowned string installed_module in installed_modules) {
								string module = splitted[0] + "-" + installed_module;
								unowned Alpm.Package? module_pkg = get_syncpkg (module);
								if (module_pkg != null) {
									trans_add_pkg_real (module_pkg);
								}
							}
						}
					}
				}
				return success;
			}
		}

		private bool trans_load_pkg (string pkgpath) {
			current_error = ErrorInfos ();
			Alpm.Package* pkg;
			if (alpm_handle.load_tarball (pkgpath, 1, alpm_handle.localfilesiglevel, out pkg) == -1) {
				Alpm.Errno errno = alpm_handle.errno ();
				current_error.errno = (uint) errno;
				current_error.message = _("Failed to prepare transaction");
				if (errno != 0) {
					current_error.details = { "%s: %s".printf (pkgpath, Alpm.strerror (errno)) };
				}
				return false;
			} else if (alpm_handle.trans_add_pkg (pkg) == -1) {
				Alpm.Errno errno = alpm_handle.errno ();
				if (errno == Alpm.Errno.TRANS_DUP_TARGET || errno == Alpm.Errno.PKG_IGNORED) {
					// just skip duplicate or ignored targets
					return true;
				} else {
					current_error.errno = (uint) errno;
					current_error.message = _("Failed to prepare transaction");
					if (errno != 0) {
						current_error.details = { "%s: %s".printf (pkg->name, Alpm.strerror (errno)) };
					}
					// free the package because it will not be used
					delete pkg;
					return false;
				}
			}
			return true;
		}

		private bool trans_remove_pkg (string pkgname) {
			current_error = ErrorInfos ();
			unowned Alpm.Package? pkg =  alpm_handle.localdb.get_pkg (pkgname);
			if (pkg == null) {
				current_error.message = _("Failed to prepare transaction");
				current_error.details = { _("target not found: %s").printf (pkgname) };
				return false;
			} else if (alpm_handle.trans_remove_pkg (pkg) == -1) {
				Alpm.Errno errno = alpm_handle.errno ();
				if (errno == Alpm.Errno.TRANS_DUP_TARGET) {
					// just skip duplicate targets
					return true;
				} else {
					current_error.errno = (uint) errno;
					current_error.message = _("Failed to prepare transaction");
					if (errno != 0) {
						current_error.details = { "%s: %s".printf (pkg.name, Alpm.strerror (errno)) };
					}
					return false;
				}
			}
			return true;
		}

		private bool trans_prepare_real () {
			bool success = true;
			current_error = ErrorInfos ();
			string[] details = {};
			Alpm.List err_data;
			if (alpm_handle.trans_prepare (out err_data) == -1) {
				Alpm.Errno errno = alpm_handle.errno ();
				current_error.errno = (uint) errno;
				current_error.message = _("Failed to prepare transaction");
				switch (errno) {
					case 0:
						break;
					case Alpm.Errno.PKG_INVALID_ARCH:
						details += Alpm.strerror (errno) + ":";
						unowned Alpm.List<string*> list = err_data;
						while (list != null) {
							string* pkgname = list.data;
							details += _("package %s does not have a valid architecture").printf (pkgname);
							delete pkgname;
							list.next ();
						}
						break;
					case Alpm.Errno.UNSATISFIED_DEPS:
						details += Alpm.strerror (errno) + ":";
						unowned Alpm.List<Alpm.DepMissing*> list = err_data;
						while (list != null) {
							Alpm.DepMissing* miss = list.data;
							string depstring = miss->depend.compute_string ();
							unowned Alpm.List<unowned Alpm.Package> trans_add = alpm_handle.trans_to_add ();
							unowned Alpm.Package pkg;
							string detail;
							if (miss->causingpkg == null) {
								/* package being installed/upgraded has unresolved dependency */
								detail = _("%s: requires %s").printf (miss->target, depstring);
							} else if ((pkg = Alpm.pkg_find (trans_add, miss->causingpkg)) != null) {
								/* upgrading a package breaks a local dependency */
								detail = _("%s: installing %s (%s) breaks dependency '%s'").printf (miss->target, miss->causingpkg, pkg.version, depstring);
							} else {
								/* removing a package breaks a local dependency */
								detail = _("%s: removing %s breaks dependency '%s'").printf (miss->target, miss->causingpkg, depstring);
							}
							if (!(detail in details)) {
								details += detail;
							}
							delete miss;
							list.next ();
						}
						break;
					case Alpm.Errno.CONFLICTING_DEPS:
						details += Alpm.strerror (errno) + ":";
						unowned Alpm.List<Alpm.Conflict*> list = err_data;
						while (list != null) {
							Alpm.Conflict* conflict = list.data;
							string conflict_detail = _("%s and %s are in conflict").printf (conflict->package1, conflict->package2);
							// only print reason if it contains new information
							if (conflict->reason.mod != Alpm.Depend.Mode.ANY) {
								conflict_detail += " (%s)".printf (conflict->reason.compute_string ());
							}
							details += (owned) conflict_detail;
							delete conflict;
							list.next ();
						}
						break;
					default:
						details += Alpm.strerror (errno);
						break;
				}
				current_error.details = (owned) details;
				trans_release ();
				success = false;
			} else {
				// Search for holdpkg in target list
				bool found_locked_pkg = false;
				unowned Alpm.List<unowned Alpm.Package> to_remove = alpm_handle.trans_to_remove ();
				while (to_remove != null) {
					unowned Alpm.Package pkg = to_remove.data;
					if (alpm_config.get_holdpkgs ().find_custom (pkg.name, strcmp) != null) {
						details += _("%s needs to be removed but it is a locked package").printf (pkg.name);
						found_locked_pkg = true;
						break;
					}
					to_remove.next ();
				}
				if (found_locked_pkg) {
					current_error.message = _("Failed to prepare transaction");
					current_error.details = (owned) details;
					trans_release ();
					success = false;
				}
			}
			return success;
		}

		private void trans_prepare () {
			bool success = trans_init (flags);
			if (success) {
				foreach (unowned string name in to_install) {
					success = trans_add_pkg (name);
					if (!success) {
						break;
					}
				}
				if (success) {
					foreach (unowned string name in to_remove) {
						success = trans_remove_pkg (name);
						if (!success) {
							break;
						}
					}
				}
				if (success) {
					foreach (unowned string path in to_load) {
						success = trans_load_pkg (path);
						if (!success) {
							break;
						}
					}
				}
				if (success) {
					success = trans_prepare_real ();
				} else {
					trans_release ();
				}
			}
			trans_prepare_finished (success);
		}

		private void build_prepare () {
			if (!databases_lock_mutex.trylock ()) {
				// Wait for pacman to finish
				emit_event (0, 0, {});
				databases_lock_mutex.lock ();
			}
			if (cancellable.is_cancelled ()) {
				cancellable.reset ();
				databases_lock_mutex.unlock ();
				return;
			}
			// create a fake aur db
			try {
				var list = new StringBuilder ();
				foreach (unowned string name_version in aur_desc_list) {
					list.append (name_version);
					list.append (" ");
				}
				Process.spawn_command_line_sync ("rm -f %ssync/aur.db".printf (alpm_handle.dbpath));
				Process.spawn_command_line_sync ("bsdtar -cf %ssync/aur.db -C %s %s".printf (alpm_handle.dbpath, aurdb_path, list.str));
			} catch (SpawnError e) {
				stderr.printf ("SpawnError: %s\n", e.message);
			}
			// get an handle without emit signal callbacks AND fake aur db
			alpm_handle = alpm_config.get_handle ();
			if (alpm_handle == null) {
				current_error = ErrorInfos () {
					message = _("Failed to initialize alpm library")
				};
				trans_commit_finished (false);
			} else {
				alpm_handle.questioncb = (Alpm.QuestionCallBack) cb_question;
				lockfile = GLib.File.new_for_path (alpm_handle.lockfile);
				// fake aur db
				alpm_handle.register_syncdb ("aur", 0);
				// add to_build in to_install for the fake trans prpeapre
				foreach (unowned string name in to_build) {
					to_install += name;
				}
				// check base-devel group needed to build pkgs
				var backup_to_remove = new GenericSet<string?> (str_hash, str_equal);
				foreach (unowned string name in to_remove) {
					backup_to_remove.add (name);
				}
				unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
				while (syncdbs != null) {
					unowned Alpm.DB db = syncdbs.data;
					unowned Alpm.Group? grp = db.get_group ("base-devel");
					if (grp != null) {
						unowned Alpm.List<unowned Alpm.Package> packages = grp.packages;
						while (packages != null) {
							unowned Alpm.Package pkg = packages.data;
							if (Alpm.find_satisfier (alpm_handle.localdb.pkgcache, pkg.name) == null) {
								to_install += pkg.name;
							} else {
								// remove the needed pkg from to_remove
								backup_to_remove.remove (pkg.name);
							}
							packages.next ();
						}
					}
					syncdbs.next ();
				}
				// check git needed to build pkgs
				if (Alpm.find_satisfier (alpm_handle.localdb.pkgcache, "git") == null) {
					to_install += "git";
				} else {
					// remove the needed pkg from to_remove
					backup_to_remove.remove ("git");
				}
				to_remove = {};
				foreach (unowned string name in backup_to_remove) {
					to_remove += name;
				}
				// fake trans prepare
				current_error = ErrorInfos ();
				bool success = true;
				if (alpm_handle.trans_init (flags | Alpm.TransFlag.NOLOCK) == -1) {
					Alpm.Errno errno = alpm_handle.errno ();
					current_error.errno = (uint) errno;
					current_error.message = _("Failed to init transaction");
					if (errno != 0) {
						current_error.details = { Alpm.strerror (errno) };
					}
					success = false;
				}
				if (success) {
					foreach (unowned string name in to_install) {
						success = trans_add_pkg (name);
						if (!success) {
							break;
						}
					}
					if (success) {
						foreach (unowned string name in to_remove) {
							success = trans_remove_pkg (name);
							if (!success) {
								break;
							}
						}
					}
					if (success) {
						foreach (unowned string path in to_load) {
							success = trans_load_pkg (path);
							if (!success) {
								break;
							}
						}
					}
					if (success) {
						success = trans_prepare_real ();
						if (success) {
							// check trans preparation result
							string[] real_to_install = {};
							unowned Alpm.List<unowned Alpm.Package> pkgs_to_add = alpm_handle.trans_to_add ();
							while (pkgs_to_add != null) {
								unowned Alpm.Package trans_pkg = pkgs_to_add.data;
								unowned Alpm.DB? db = trans_pkg.db;
								if (db != null) {
									if (db.name == "aur") {
										// it is a aur pkg to build
										aur_pkgbases_to_build.append (trans_pkg.pkgbase);
										var infos = UpdateInfos () {
											name = trans_pkg.name,
											old_version = "",
											new_version = trans_pkg.version,
											repo = "",
											download_size = 0
										};
										to_build_infos += (owned) infos;
										if (!(trans_pkg.name in to_build)) {
											to_install_as_dep.insert (trans_pkg.name, trans_pkg.name);
										}
									} else {
										// it is a pkg to install
										real_to_install += trans_pkg.name;
										if (!(trans_pkg.name in to_install)) {
											to_install_as_dep.insert (trans_pkg.name, trans_pkg.name);
										}
									}
								}
								pkgs_to_add.next ();
							}
							aur_conflicts_to_remove = {};
							unowned Alpm.List<unowned Alpm.Package> pkgs_to_remove = alpm_handle.trans_to_remove ();
							while (pkgs_to_remove != null) {
								unowned Alpm.Package trans_pkg = pkgs_to_remove.data;
								// it is a pkg to remove
								if (!(trans_pkg.name in to_remove)) {
									var infos = UpdateInfos () {
										name = trans_pkg.name,
										old_version = trans_pkg.version,
										new_version = "",
										repo = "",
										download_size = 0
									};
									aur_conflicts_to_remove += (owned) infos;
								}
								pkgs_to_remove.next ();
							}
							trans_release ();
							try {
								Process.spawn_command_line_sync ("rm -f %ssync/aur.db".printf (alpm_handle.dbpath));
							} catch (SpawnError e) {
								stderr.printf ("SpawnError: %s\n", e.message);
							}
							// get standard handle
							databases_lock_mutex.lock ();
							refresh_handle ();
							databases_lock_mutex.unlock ();
							// launch standard prepare
							to_install = real_to_install;
							trans_prepare ();
						}
					} else {
						trans_release ();
					}
				} else {
					databases_lock_mutex.unlock ();
				}
				if (!success) {
					// get standard handle
					databases_lock_mutex.lock ();
					refresh_handle ();
					databases_lock_mutex.unlock ();
					trans_prepare_finished (false);
				}
			}
		}

		public void start_trans_prepare (Alpm.TransFlag flags_,
										string[] to_install_,
										string[] to_remove_,
										string[] to_load_,
										string[] to_build_) {
			flags = flags_;
			to_install = to_install_;
			to_remove = to_remove_;
			to_load = to_load_;
			to_build = to_build_;
			to_build_infos = {};
			aur_pkgbases_to_build = new GLib.List<string> ();
			if (to_build.length != 0) {
				compute_aur_build_list.begin (to_build, (obj, res) => {
					try {
						thread_pool.add (new AlpmAction (build_prepare));
					} catch (ThreadError e) {
						stderr.printf ("Thread Error %s\n", e.message);
					}
				});
			} else {
				try {
					thread_pool.add (new AlpmAction (trans_prepare));
				} catch (ThreadError e) {
					stderr.printf ("Thread Error %s\n", e.message);
				}
			}
		}

		public void choose_provider (int provider) {
			provider_mutex.lock ();
			choosen_provider = provider;
			provider_cond.signal ();
			provider_mutex.unlock ();
		}

		public TransactionSummary get_transaction_summary () {
			UpdateInfos[] to_install = {};
			UpdateInfos[] to_upgrade = {};
			UpdateInfos[] to_downgrade = {};
			UpdateInfos[] to_reinstall = {};
			UpdateInfos[] to_remove = {};
			unowned Alpm.List<unowned Alpm.Package> pkgs_to_add = alpm_handle.trans_to_add ();
			while (pkgs_to_add != null) {
				unowned Alpm.Package trans_pkg = pkgs_to_add.data;
				unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (trans_pkg.name);
				var infos = UpdateInfos () {
					name = trans_pkg.name,
					old_version = local_pkg != null ? local_pkg.version : "",
					new_version = trans_pkg.version,
					// if pkg was load from a file, pkg.db is null
					repo =trans_pkg.db != null ? trans_pkg.db.name : "",
					download_size = trans_pkg.download_size
				};
				if (local_pkg == null) {
					to_install += (owned) infos;
				} else {
					int cmp = Alpm.pkg_vercmp (trans_pkg.version, local_pkg.version);
					if (cmp == 1) {
						to_upgrade += (owned) infos;
					} else if (cmp == 0) {
						to_reinstall += (owned) infos;
					} else {
						to_downgrade += (owned) infos;
					}
				}
				pkgs_to_add.next ();
			}
			unowned Alpm.List<unowned Alpm.Package> pkgs_to_remove = alpm_handle.trans_to_remove ();
			while (pkgs_to_remove != null) {
				unowned Alpm.Package trans_pkg = pkgs_to_remove.data;
				var infos = UpdateInfos () {
					name = trans_pkg.name,
					old_version = trans_pkg.version,
					new_version = "",
					repo = trans_pkg.db.name
				};
				to_remove += (owned) infos;
				pkgs_to_remove.next ();
			}
			UpdateInfos[] conflicts_to_remove = {};
			foreach (unowned UpdateInfos infos in aur_conflicts_to_remove){
				conflicts_to_remove += infos;
			}
			aur_conflicts_to_remove = {};
			string[] pkgbases_to_build = {};
			foreach (unowned string name in aur_pkgbases_to_build) {
				pkgbases_to_build += name;
			}
			var summary = TransactionSummary () {
				to_install = (owned) to_install,
				to_upgrade = (owned) to_upgrade,
				to_downgrade = (owned) to_downgrade,
				to_reinstall = (owned) to_reinstall,
				to_remove = (owned) to_remove,
				to_build = to_build_infos,
				aur_conflicts_to_remove = conflicts_to_remove,
				aur_pkgbases_to_build = pkgbases_to_build
			};
			return summary;
		}

		private void trans_commit () {
			current_error = ErrorInfos ();
			bool success = true;
			Alpm.List err_data;
			if (alpm_handle.trans_commit (out err_data) == -1) {
				Alpm.Errno errno = alpm_handle.errno ();
				current_error.errno = (uint) errno;
				// cancel the download return an EXTERNAL_DOWNLOAD error
				if (errno == Alpm.Errno.EXTERNAL_DOWNLOAD && cancellable.is_cancelled ()) {
					trans_release ();
					trans_commit_finished (false);
					return;
				}
				current_error.message = _("Failed to commit transaction");
				switch (errno) {
					case 0:
						break;
					case Alpm.Errno.FILE_CONFLICTS:
						string[] details = {};
						details += Alpm.strerror (errno) + ":";
						//TransFlag flags = alpm_handle.trans_get_flags ();
						//if ((flags & TransFlag.FORCE) != 0) {
							//details += _("unable to %s directory-file conflicts").printf ("--force");
						//}
						unowned Alpm.List<Alpm.FileConflict*> list = err_data;
						while (list != null) {
							Alpm.FileConflict* conflict = list.data;
							switch (conflict->type) {
								case Alpm.FileConflict.Type.TARGET:
									details += _("%s exists in both %s and %s").printf (conflict->file, conflict->target, conflict->ctarget);
									break;
								case Alpm.FileConflict.Type.FILESYSTEM:
									details += _("%s: %s already exists in filesystem").printf (conflict->target, conflict->file);
									break;
							}
							delete conflict;
							list.next ();
						}
						current_error.details = (owned) details;
						break;
					case Alpm.Errno.PKG_INVALID:
					case Alpm.Errno.PKG_INVALID_CHECKSUM:
					case Alpm.Errno.PKG_INVALID_SIG:
					case Alpm.Errno.DLT_INVALID:
						string[] details = {};
						details += Alpm.strerror (errno) + ":";
						unowned Alpm.List<string*> list = err_data;
						while (list != null) {
							string* filename = list.data;
							details += _("%s is invalid or corrupted").printf (filename);
							delete filename;
							list.next ();
						}
						current_error.details = (owned) details;
						break;
					case Alpm.Errno.EXTERNAL_DOWNLOAD:
						// details are set in cb_fetch
						break;
					default:
						current_error.details = {Alpm.strerror (errno)};
						break;
				}
				success = false;
			}
			trans_release ();
			to_install_as_dep.foreach_remove ((pkgname, val) => {
				unowned Alpm.Package? pkg = alpm_handle.localdb.get_pkg (pkgname);
				if (pkg != null) {
					pkg.reason = Alpm.Package.Reason.DEPEND;
					return true; // remove current pkgname
				}
				return false;
			});
			trans_commit_finished (success);
		}

		public void start_trans_commit (GLib.BusName sender) {
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					try {
						thread_pool.add (new AlpmAction (trans_commit));
					} catch (ThreadError e) {
						stderr.printf ("Thread Error %s\n", e.message);
					}
				} else {
					trans_release ();
					trans_commit_finished (false);
				}
			});
		}

		public void trans_release () {
			alpm_handle.trans_release ();
			remove_ignorepkgs ();
			databases_lock_mutex.unlock ();
		}

		[DBus (no_reply = true)]
		public void trans_cancel () {
			if (alpm_handle.trans_interrupt () == 0) {
				// a transaction is being interrupted
				// it will end the normal way
				return;
			}
			cancellable.cancel ();
		}

		[DBus (no_reply = true)]
		public void quit () {
			// wait for all tasks to be processed
			ThreadPool.free ((owned) thread_pool, false, true);
			loop.quit ();
		}
	// End of Daemon Object
	}
}

private void write_log_file (string event) {
	var now = new DateTime.now_local ();
	string log = "%s [PAMAC] %s\n".printf (now.format ("[%Y-%m-%d %H:%M]"), event);
	var file = GLib.File.new_for_path ("/var/log/pacman.log");
	try {
		// creating a DataOutputStream to the file
		var dos = new DataOutputStream (file.append_to (FileCreateFlags.NONE));
		// writing a short string to the stream
		dos.put_string (log);
	} catch (GLib.Error e) {
		stderr.printf ("%s\n", e.message);
	}
}

private void cb_event (Alpm.Event.Data data) {
	string[] details = {};
	uint secondary_type = 0;
	switch (data.type) {
		case Alpm.Event.Type.HOOK_START:
			switch (data.hook_when) {
				case Alpm.HookWhen.PRE_TRANSACTION:
					secondary_type = (uint) Alpm.HookWhen.PRE_TRANSACTION;
					break;
				case Alpm.HookWhen.POST_TRANSACTION:
					secondary_type = (uint) Alpm.HookWhen.POST_TRANSACTION;
					break;
				default:
					break;
			}
			break;
		case Alpm.Event.Type.HOOK_RUN_START:
			details += data.hook_run_name;
			details += data.hook_run_desc ?? "";
			details += data.hook_run_position.to_string ();
			details += data.hook_run_total.to_string ();
			break;
		case Alpm.Event.Type.PACKAGE_OPERATION_START:
			switch (data.package_operation_operation) {
				case Alpm.Package.Operation.REMOVE:
					details += data.package_operation_oldpkg.name;
					details += data.package_operation_oldpkg.version;
					secondary_type = (uint) Alpm.Package.Operation.REMOVE;
					break;
				case Alpm.Package.Operation.INSTALL:
					details += data.package_operation_newpkg.name;
					details += data.package_operation_newpkg.version;
					secondary_type = (uint) Alpm.Package.Operation.INSTALL;
					break;
				case Alpm.Package.Operation.REINSTALL:
					details += data.package_operation_newpkg.name;
					details += data.package_operation_newpkg.version;
					secondary_type = (uint) Alpm.Package.Operation.REINSTALL;
					break;
				case Alpm.Package.Operation.UPGRADE:
					details += data.package_operation_oldpkg.name;
					details += data.package_operation_oldpkg.version;
					details += data.package_operation_newpkg.version;
					secondary_type = (uint) Alpm.Package.Operation.UPGRADE;
					break;
				case Alpm.Package.Operation.DOWNGRADE:
					details += data.package_operation_oldpkg.name;
					details += data.package_operation_oldpkg.version;
					details += data.package_operation_newpkg.version;
					secondary_type = (uint) Alpm.Package.Operation.DOWNGRADE;
					break;
				default:
					break;
			}
			break;
		case Alpm.Event.Type.DELTA_PATCH_START:
			details += data.delta_patch_delta.to;
			details += data.delta_patch_delta.delta;
			break;
		case Alpm.Event.Type.SCRIPTLET_INFO:
			details += data.scriptlet_info_line;
			break;
		case Alpm.Event.Type.PKGDOWNLOAD_START:
			// do not emit event when download is cancelled
			if (pamac_daemon.cancellable.is_cancelled ()) {
				return;
			}
			details += data.pkgdownload_file;
			break;
		case Alpm.Event.Type.OPTDEP_REMOVAL:
			details += data.optdep_removal_pkg.name;
			details += data.optdep_removal_optdep.compute_string ();
			break;
		case Alpm.Event.Type.DATABASE_MISSING:
			details += data.database_missing_dbname;
			break;
		case Alpm.Event.Type.PACNEW_CREATED:
			details += data.pacnew_created_file;
			break;
		case Alpm.Event.Type.PACSAVE_CREATED:
			details += data.pacsave_created_file;
			break;
		default:
			break;
	}
	pamac_daemon.emit_event ((uint) data.type, secondary_type, details);
}

private void cb_question (Alpm.Question.Data data) {
	switch (data.type) {
		case Alpm.Question.Type.INSTALL_IGNOREPKG:
			// Do not install package in IgnorePkg/IgnoreGroup
			data.install_ignorepkg_install = 0;
			break;
		case Alpm.Question.Type.REPLACE_PKG:
			// Auto-remove conflicts in case of replaces
			data.replace_replace = 1;
			break;
		case Alpm.Question.Type.CONFLICT_PKG:
			// Auto-remove conflicts
			data.conflict_remove = 1;
			break;
		case Alpm.Question.Type.REMOVE_PKGS:
			// Return an error if there are top-level packages which have unresolvable dependencies
			data.remove_pkgs_skip = 0;
			break;
		case Alpm.Question.Type.SELECT_PROVIDER:
			string depend_str = data.select_provider_depend.compute_string ();
			string[] providers_str = {};
			unowned Alpm.List<unowned Alpm.Package> list = data.select_provider_providers;
			while (list != null) {
				unowned Alpm.Package pkg = list.data;
				providers_str += pkg.name;
				list.next ();
			}
			pamac_daemon.provider_cond = Cond ();
			pamac_daemon.provider_mutex = Mutex ();
			pamac_daemon.choosen_provider = null;
			pamac_daemon.emit_providers (depend_str, providers_str);
			pamac_daemon.provider_mutex.lock ();
			while (pamac_daemon.choosen_provider == null) {
				pamac_daemon.provider_cond.wait (pamac_daemon.provider_mutex);
			}
			data.select_provider_use_index = pamac_daemon.choosen_provider;
			pamac_daemon.provider_mutex.unlock ();
			break;
		case Alpm.Question.Type.CORRUPTED_PKG:
			// Auto-remove corrupted pkgs in cache
			data.corrupted_remove = 1;
			break;
		case Alpm.Question.Type.IMPORT_KEY:
			if (data.import_key_key.revoked == 1) {
				// Do not get revoked key
				data.import_key_import = 0;
			} else {
				// Auto get not revoked key
				data.import_key_import = 1;
			}
			break;
		default:
			data.any_answer = 0;
			break;
	}
}

private void cb_progress (Alpm.Progress progress, string pkgname, int percent, uint n_targets, uint current_target) {
	if (percent == 0) {
		pamac_daemon.emit_progress ((uint) progress, pkgname, (uint) percent, n_targets, current_target);
		pamac_daemon.timer.start ();
	} else if (percent == 100) {
		pamac_daemon.emit_progress ((uint) progress, pkgname, (uint) percent, n_targets, current_target);
		pamac_daemon.timer.stop ();
	}else if (pamac_daemon.timer.elapsed () < 0.5) {
		return;
	} else {
		pamac_daemon.emit_progress ((uint) progress, pkgname, (uint) percent, n_targets, current_target);
		pamac_daemon.timer.start ();
	}
}

private uint64 prevprogress;

private int cb_download (void* data, uint64 dltotal, uint64 dlnow, uint64 ultotal, uint64 ulnow) {

	if (unlikely (pamac_daemon.cancellable.is_cancelled ())) {
		return 1;
	}

	string filename = (string) data;

	if (unlikely (dlnow == 0 || dltotal == 0 || prevprogress == dltotal)) {
		return 0;
	} else if (unlikely (prevprogress == 0)) {
		pamac_daemon.emit_download (filename, 0, dltotal);
		pamac_daemon.emit_download (filename, dlnow, dltotal);
		pamac_daemon.timer.start ();
	} else if (unlikely (dlnow == dltotal)) {
		pamac_daemon.emit_download (filename, dlnow, dltotal);
		pamac_daemon.timer.stop ();
	} else if (likely (pamac_daemon.timer.elapsed () < 0.5)) {
		return 0;
	} else {
		pamac_daemon.emit_download (filename, dlnow, dltotal);
		pamac_daemon.timer.start ();
	}

	prevprogress = dlnow;

	return 0;
}

private int cb_fetch (string fileurl, string localpath, int force) {
	if (pamac_daemon.cancellable.is_cancelled ()) {
		return -1;
	}

	char error_buffer[Curl.ERROR_SIZE];
	var url = GLib.File.new_for_uri (fileurl);
	var destfile = GLib.File.new_for_path (localpath + url.get_basename ());
	var tempfile = GLib.File.new_for_path (destfile.get_path () + ".part");

	pamac_daemon.curl.reset ();
	pamac_daemon.curl.setopt (Curl.Option.FAILONERROR, 1L);
	pamac_daemon.curl.setopt (Curl.Option.CONNECTTIMEOUT, 30L);
	pamac_daemon.curl.setopt (Curl.Option.FILETIME, 1L);
	pamac_daemon.curl.setopt (Curl.Option.FOLLOWLOCATION, 1L);
	pamac_daemon.curl.setopt (Curl.Option.XFERINFOFUNCTION, cb_download);
	pamac_daemon.curl.setopt (Curl.Option.LOW_SPEED_LIMIT, 1L);
	pamac_daemon.curl.setopt (Curl.Option.LOW_SPEED_TIME, 30L);
	pamac_daemon.curl.setopt (Curl.Option.NETRC, Curl.NetRCOption.OPTIONAL);
	pamac_daemon.curl.setopt (Curl.Option.HTTPAUTH, Curl.CURLAUTH_ANY);
	pamac_daemon.curl.setopt (Curl.Option.URL, fileurl);
	pamac_daemon.curl.setopt (Curl.Option.ERRORBUFFER, error_buffer);
	pamac_daemon.curl.setopt (Curl.Option.NOPROGRESS, 0L);
	pamac_daemon.curl.setopt (Curl.Option.XFERINFODATA, (void*) url.get_basename ());

	bool remove_partial_download = true;
	if (fileurl.contains (".pkg.tar.") && !fileurl.has_suffix (".sig")) {
		remove_partial_download = false;
	}

	string open_mode = "wb";
	prevprogress = 0;

	try {
		if (force == 0) {
			if (destfile.query_exists ()) {
				// start from scratch only download if our local is out of date.
				pamac_daemon.curl.setopt (Curl.Option.TIMECONDITION, Curl.TimeCond.IFMODSINCE);
				FileInfo info = destfile.query_info ("time::modified", 0);
				TimeVal time = info.get_modification_time ();
				pamac_daemon.curl.setopt (Curl.Option.TIMEVALUE, time.tv_sec);
			} else if (tempfile.query_exists ()) {
				// a previous partial download exists, resume from end of file.
				FileInfo info = tempfile.query_info ("standard::size", 0);
				int64 size = info.get_size ();
				pamac_daemon.curl.setopt (Curl.Option.RESUME_FROM_LARGE, size);
				open_mode = "ab";
			}
		} else {
			if (tempfile.query_exists ()) {
				tempfile.delete ();
			}
		}
	} catch (GLib.Error e) {
		stderr.printf ("Error: %s\n", e.message);
	}

	Posix.FILE localf = Posix.FILE.open (tempfile.get_path (), open_mode);
	if (localf == null) {
		stderr.printf ("could not open file %s\n", tempfile.get_path ());
		return -1;
	}

	pamac_daemon.curl.setopt (Curl.Option.WRITEDATA, localf);

	// perform transfer
	Curl.Code err = pamac_daemon.curl.perform ();


	// disconnect relationships from the curl handle for things that might go out
	// of scope, but could still be touched on connection teardown. This really
	// only applies to FTP transfers.
	pamac_daemon.curl.setopt (Curl.Option.NOPROGRESS, 1L);
	pamac_daemon.curl.setopt (Curl.Option.ERRORBUFFER, null);

	int ret;

	// was it a success?
	switch (err) {
		case Curl.Code.OK:
			long timecond, remote_time = -1;
			double remote_size, bytes_dl;
			unowned string effective_url;

			// retrieve info about the state of the transfer
			pamac_daemon.curl.getinfo (Curl.Info.FILETIME, out remote_time);
			pamac_daemon.curl.getinfo (Curl.Info.CONTENT_LENGTH_DOWNLOAD, out remote_size);
			pamac_daemon.curl.getinfo (Curl.Info.SIZE_DOWNLOAD, out bytes_dl);
			pamac_daemon.curl.getinfo (Curl.Info.CONDITION_UNMET, out timecond);
			pamac_daemon.curl.getinfo (Curl.Info.EFFECTIVE_URL, out effective_url);

			if (timecond == 1 && bytes_dl == 0) {
				// time condition was met and we didn't download anything. we need to
				// clean up the 0 byte .part file that's left behind.
				try {
					if (tempfile.query_exists ()) {
						tempfile.delete ();
					}
				} catch (GLib.Error e) {
					stderr.printf ("Error: %s\n", e.message);
				}
				ret = 1;
			}
			// remote_size isn't necessarily the full size of the file, just what the
			// server reported as remaining to download. compare it to what curl reported
			// as actually being transferred during curl_easy_perform ()
			else if (remote_size != -1 && bytes_dl != -1 && bytes_dl != remote_size) {
				string error = _("%s appears to be truncated: %jd/%jd bytes\n").printf (
											fileurl, bytes_dl, remote_size);
				pamac_daemon.emit_log ((uint) Alpm.LogLevel.ERROR, error);
				pamac_daemon.current_error.details = {error};
				if (remove_partial_download) {
					try {
						if (tempfile.query_exists ()) {
							tempfile.delete ();
						}
					} catch (GLib.Error e) {
						stderr.printf ("Error: %s\n", e.message);
					}
				}
				ret = -1;
			} else {
				try {
					tempfile.move (destfile, FileCopyFlags.OVERWRITE);
				} catch (GLib.Error e) {
					stderr.printf ("Error: %s\n", e.message);
				}
				ret = 0;
			}
			break;
		case Curl.Code.ABORTED_BY_CALLBACK:
			if (remove_partial_download) {
				try {
					if (tempfile.query_exists ()) {
						tempfile.delete ();
					}
				} catch (GLib.Error e) {
					stderr.printf ("Error: %s\n", e.message);
				}
			}
			ret = -1;
			break;
		default:
			// other cases are errors
			try {
				if (tempfile.query_exists ()) {
					if (remove_partial_download) {
						tempfile.delete ();
					} else {
						// delete zero length downloads
						FileInfo info = tempfile.query_info ("standard::size", 0);
						int64 size = info.get_size ();
						if (size == 0) {
							tempfile.delete ();
						}
					}
				}
			} catch (GLib.Error e) {
				stderr.printf ("Error: %s\n", e.message);
			}
			// do not report error for missing sig
			if (!fileurl.has_suffix (".sig")) {
				string hostname = url.get_uri ().split("/")[2];
				string error = _("failed retrieving file '%s' from %s : %s\n").printf (
											url.get_basename (), hostname, (string) error_buffer);
				pamac_daemon.emit_log ((uint) Alpm.LogLevel.ERROR, error);
				pamac_daemon.current_error.details = {error};
			}
			ret = -1;
			break;
	}

	return ret;
}

private void cb_totaldownload (uint64 total) {
	pamac_daemon.emit_totaldownload (total);
}

private void cb_log (Alpm.LogLevel level, string fmt, va_list args) {
	// do not log errors when download is cancelled
	if (pamac_daemon.cancellable.is_cancelled ()) {
		return;
	}
	Alpm.LogLevel logmask = Alpm.LogLevel.ERROR | Alpm.LogLevel.WARNING;
	if ((level & logmask) == 0) {
		return;
	}
	string? log = null;
	log = fmt.vprintf (args);
	if (log != null) {
		pamac_daemon.emit_log ((uint) level, log);
	}
}

void on_bus_acquired (DBusConnection conn) {
	pamac_daemon = new Pamac.Daemon ();
	try {
		conn.register_object ("/org/manjaro/pamac", pamac_daemon);
	}
	catch (IOError e) {
		stderr.printf ("Could not register service\n");
		loop.quit ();
	}
}

void main () {
	// i18n
	Intl.setlocale (LocaleCategory.ALL, "");
	Intl.textdomain (GETTEXT_PACKAGE);

	Bus.own_name (BusType.SYSTEM,
				"org.manjaro.pamac",
				BusNameOwnerFlags.NONE,
				on_bus_acquired,
				null,
				() => {
					stderr.printf ("Could not acquire name\n");
					loop.quit ();
				});

	Curl.global_init (Curl.GLOBAL_SSL);
	loop = new MainLoop ();
	loop.run ();
	Curl.global_cleanup ();
}
