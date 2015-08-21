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

using Alpm;
using Polkit;

// i18n
const string GETTEXT_PACKAGE = "pamac";

Pamac.Daemon pamac_daemon;
MainLoop loop;

public delegate void AlpmActionDelegate ();
 
public class AlpmAction: Object {
		unowned AlpmActionDelegate action_delegate;
		public AlpmAction (AlpmActionDelegate action_delegate) {
			this.action_delegate = action_delegate;
		}
		public void run () {
			action_delegate ();
		}
	}

namespace Pamac {
	[DBus (name = "org.manjaro.pamac")]
	public class Daemon : Object {
		private Alpm.Config alpm_config;
		public uint64 previous_percent;
		public Cond provider_cond;
		public Mutex provider_mutex;
		public int? choosen_provider;
		private int force_refresh;
		private ThreadPool<AlpmAction> thread_pool;
		private Mutex databases_lock_mutex;
		private HashTable<string, Json.Array> aur_search_results;
		private Json.Array aur_updates_results;
		private bool intern_lock;
		private bool extern_lock;
		private GLib.File lockfile;

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

		public Daemon () {
			alpm_config = new Alpm.Config ("/etc/pacman.conf");
			databases_lock_mutex = Mutex ();
			aur_search_results = new HashTable<string, Json.Array> (str_hash, str_equal);
			aur_updates_results = new Json.Array ();
			intern_lock = false;
			extern_lock = false;
			force_refresh = 0;
			refresh_handle ();
			Timeout.add (500, check_pacman_running);
			create_thread_pool ();
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
					// exclusive thread
					true
				);
			} catch (ThreadError e) {
				stderr.printf ("Thread Error %s\n", e.message);
			}
		}

		private void refresh_handle () {
			alpm_config.get_handle ();
			if (alpm_config.handle == null) {
				var err = ErrorInfos ();
				err.message = _("Failed to initialize alpm library");
				trans_commit_finished (err);
			} else {
				alpm_config.handle.eventcb = (EventCallBack) cb_event;
				alpm_config.handle.progresscb = (ProgressCallBack) cb_progress;
				alpm_config.handle.questioncb = (QuestionCallBack) cb_question;
				alpm_config.handle.dlcb = (DownloadCallBack) cb_download;
				alpm_config.handle.totaldlcb = (TotalDownloadCallBack) cb_totaldownload;
				alpm_config.handle.logcb = (LogCallBack) cb_log;
				lockfile = GLib.File.new_for_path (alpm_config.handle.lockfile);
			}
			previous_percent = 0;
		}

		private bool check_pacman_running () {
			if (extern_lock) {
				if (lockfile.query_exists () == false) {
					extern_lock = false;
					refresh_handle ();
				}
			} else {
				if (lockfile.query_exists () == true) {
					if (intern_lock == false) {
						extern_lock = true;
					}
				}
			}
			return true;
		}

		private async bool check_authorization (GLib.BusName sender) {
			SourceFunc callback = check_authorization.callback;
			bool authorized = false;
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
			} catch (GLib.Error e) {
				stderr.printf ("%s\n", e.message);
			}
			yield;
			return authorized;
		}

		public void start_get_authorization (GLib.BusName sender) {
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				get_authorization_finished (authorized);
			});
		}

		public void start_write_pamac_config (HashTable<string,Variant> new_pamac_conf, GLib.BusName sender) {
			var pamac_config = new Pamac.Config ("/etc/pamac.conf");
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized ) {
					pamac_config.write (new_pamac_conf);
					pamac_config.reload ();
				}
				write_pamac_config_finished (pamac_config.refresh_period, pamac_config.enable_aur,
											pamac_config.recurse, pamac_config.no_update_hide_icon,
											pamac_config.check_aur_updates, pamac_config.no_confirm_build);
			});
		}

		public void start_write_alpm_config (HashTable<string,Variant> new_alpm_conf, GLib.BusName sender) {
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized ) {
					alpm_config.write (new_alpm_conf);
					alpm_config.reload ();
					refresh_handle ();
				}
				write_alpm_config_finished (get_checkspace ());
			});
		}

		private bool process_line (IOChannel channel, IOCondition condition, string stream_name) {
			if (condition == IOCondition.HUP) {
				return false;
			}
			try {
				string line;
				channel.read_line (out line, null, null);
				generate_mirrors_list_data (line);
			} catch (IOChannelError e) {
				stderr.printf ("%s: IOChannelError: %s\n", stream_name, e.message);
				return false;
			} catch (ConvertError e) {
				stderr.printf ("%s: ConvertError: %s\n", stream_name, e.message);
				return false;
			}
			return true;
		}

		public void start_generate_mirrors_list () {
			int standard_output;
			int standard_error;
			Pid child_pid;
			try {
				Process.spawn_async_with_pipes (null,
					{"pacman-mirrors", "-g"},
					null,
					SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
					null,
					out child_pid,
					null,
					out standard_output,
					out standard_error);
				// stdout
				IOChannel output = new IOChannel.unix_new (standard_output);
				output.add_watch (IOCondition.IN | IOCondition.HUP, (channel, condition) => {
					return process_line (channel, condition, "stdout");
				});
				// stderr
				IOChannel error = new IOChannel.unix_new (standard_error);
				error.add_watch (IOCondition.IN | IOCondition.HUP, (channel, condition) => {
					return process_line (channel, condition, "stderr");
				});
				ChildWatch.add (child_pid, (pid, status) => {
					// Triggered when the child indicated by child_pid exits
					Process.close_pid (pid);
					alpm_config.reload ();
					refresh_handle ();
					generate_mirrors_list_finished ();
				});
			} catch (SpawnError e) {
				generate_mirrors_list_finished ();
				stdout.printf ("SpawnError: %s\n", e.message);
			}
		}

		public void start_write_mirrors_config (HashTable<string,Variant> new_mirrors_conf, GLib.BusName sender) {
			var mirrors_config = new Alpm.MirrorsConfig ("/etc/pacman-mirrors.conf");
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
					unowned Alpm.Package? pkg = alpm_config.handle.localdb.get_pkg (pkgname);
					if (pkg != null) {
						pkg.reason = (Alpm.Package.Reason) reason;
						refresh_handle ();
					}
				}
				set_pkgreason_finished ();
			});
		}

		private void refresh () {
			intern_lock = true;
			var err = ErrorInfos ();
			string[] details = {};
			int success = 0;
			int ret;
			foreach (var db in alpm_config.handle.syncdbs) {
				ret = db.update (force_refresh);
				if (ret >= 0) {
					success++;
				}
			}
			// We should always succeed if at least one DB was upgraded - we may possibly
			// fail later with unresolved deps, but that should be rare, and would be expected
			if (success == 0) {
				err.message = _("Failed to synchronize any databases");
				details += Alpm.strerror (alpm_config.handle.errno ());
				err.details = details;
			}
			refresh_handle ();
			refresh_finished (err);
			force_refresh = 0;
			intern_lock = false;
		}

		public void start_refresh (int force) {
			force_refresh = force;
			try {
				thread_pool.add (new AlpmAction (refresh));
			} catch (ThreadError e) {
				stderr.printf ("Thread Error %s\n", e.message);
			}
		}

		public bool get_checkspace () {
			return alpm_config.checkspace == 1 ? true : false;
		}

		public string[] get_ignorepkgs () {
			string[] ignorepkgs = {};
			for (size_t i = 0; i < alpm_config.ignorepkgs->length; i++) {
				ignorepkgs += alpm_config.ignorepkgs->nth_data (i);
			}
			return ignorepkgs;
		}

		public void add_ignorepkg (string pkgname) {
			alpm_config.handle.add_ignorepkg (pkgname);
		}

		public void remove_ignorepkg (string pkgname) {
			alpm_config.handle.remove_ignorepkg (pkgname);
		}

		public bool should_hold (string pkgname) {
			if (alpm_config.holdpkgs.find_custom (pkgname, strcmp) != null) {
				return true;
			}
			return false;
		}

		public async Pamac.Package[] get_all_pkgs () {
			Pamac.Package[] pkgs = {};
			var alpm_pkgs = all_pkgs (alpm_config.handle);
			foreach (var alpm_pkg in alpm_pkgs) {
				pkgs += Pamac.Package (alpm_pkg, null);
			}
			return pkgs;
		}

		public async Pamac.Package[] get_installed_pkgs () {
			Pamac.Package[] pkgs = {};
			foreach (var alpm_pkg in alpm_config.handle.localdb.pkgcache) {
				pkgs += Pamac.Package (alpm_pkg, null);
			}
			return pkgs;
		}

		public async Pamac.Package[] get_local_pkgs () {
			Pamac.Package[] pkgs = {};
			foreach (var alpm_pkg in alpm_config.handle.localdb.pkgcache) {
				bool sync_found = false;
				foreach (var db in alpm_config.handle.syncdbs) {
					unowned Alpm.Package? sync_pkg = db.get_pkg (alpm_pkg.name);
					if (sync_pkg != null) {
						sync_found = true;
						break;
					}
				}
				if (sync_found == false) {
					pkgs += Pamac.Package (alpm_pkg, null);
				}
			}
			return pkgs;
		}

		public async Pamac.Package[] get_orphans () {
			Pamac.Package[] pkgs = {};
			foreach (var alpm_pkg in alpm_config.handle.localdb.pkgcache) {
				if (alpm_pkg.reason == Alpm.Package.Reason.DEPEND) {
					Alpm.List<string?> *list = alpm_pkg.compute_requiredby ();
					if (list->length == 0) {
						pkgs += Pamac.Package (alpm_pkg, null);
					}
					Alpm.List.free_all (list);
				}
			}
			return pkgs;
		}

		public Pamac.Package find_local_pkg (string pkgname) {
			return Pamac.Package (alpm_config.handle.localdb.get_pkg (pkgname), null);
		}

		private unowned Alpm.Package? get_syncpkg (string name) {
			unowned Alpm.Package? pkg = null;
			foreach (var db in alpm_config.handle.syncdbs) {
				pkg = db.get_pkg (name);
				if (pkg != null) {
					break;
				}
			}
			return pkg;
		}

		public Pamac.Package find_sync_pkg (string pkgname) {
			return Pamac.Package (get_syncpkg (pkgname), null);
		}

		public async Pamac.Package[] search_pkgs (string search_string, bool search_from_aur) {
			Pamac.Package[] result = {};
			var needles = new Alpm.List<string> ();
			string[] splitted = search_string.split (" ");
			foreach (unowned string part in splitted) {
				needles.add (part);
			}
			var alpm_pkgs = search_all_dbs (alpm_config.handle, needles);
			foreach (var alpm_pkg in alpm_pkgs) {
				result += Pamac.Package (alpm_pkg, null);
			}
			if (search_from_aur) {
				Json.Array aur_pkgs;
				if (aur_search_results.contains (search_string)) {
					aur_pkgs = aur_search_results.get (search_string);
				} else {
					aur_pkgs = AUR.search (splitted);
					aur_search_results.insert (search_string, aur_pkgs);
				}
				foreach (var node in aur_pkgs.get_elements ()) {
					var aur_pkg = node.get_object ();
					var pamac_pkg = Pamac.Package (null, aur_pkg);
					bool found = false;
					foreach (var pkg in result) {
						if (pkg.name == pamac_pkg.name) {
							found = true;
							break;
						}
					}
					if (found == false) {
						result += pamac_pkg;
					}
				}
			}
			return result;
		}

		public string[] get_repos_names () {
			string[] repos_names = {};
			foreach (var db in alpm_config.handle.syncdbs) {
				repos_names += db.name;
			}
			return repos_names;
		}

		public async Pamac.Package[] get_repo_pkgs (string repo) {
			Pamac.Package[] pkgs = {};
			unowned Alpm.Package? local_pkg = null;
			foreach (var db in alpm_config.handle.syncdbs) {
				if (db.name == repo) {
					foreach (var sync_pkg in db.pkgcache) {
						local_pkg = alpm_config.handle.localdb.get_pkg (sync_pkg.name);
						if (local_pkg != null) {
							pkgs += Pamac.Package (local_pkg, null);
						} else {
							pkgs += Pamac.Package (sync_pkg, null);
						}
					}
				}
			}
			return pkgs;
		}

		public string[] get_groups_names () {
			string[] groups_names = {};
			foreach (var db in alpm_config.handle.syncdbs) {
				foreach (var group in db.groupcache) {
					if ((group.name in groups_names) == false) { 
						groups_names += group.name;
					}
				}
			}
			return groups_names;
		}

		public async Pamac.Package[] get_group_pkgs (string groupname) {
			Pamac.Package[] pkgs = {};
			var alpm_pkgs = group_pkgs (alpm_config.handle, groupname);
			foreach (var alpm_pkg in alpm_pkgs) {
				pkgs += Pamac.Package (alpm_pkg, null);
			}
			return pkgs;
		}

		public string[] get_pkg_files (string pkgname) {
			string[] files = {};
			unowned Alpm.Package? alpm_pkg = alpm_config.handle.localdb.get_pkg (pkgname);
			if (alpm_pkg != null) {
				foreach (var file in alpm_pkg.files) {
					files += file.name;
				}
			}
			return files;
		}

		public string[] get_pkg_uninstalled_optdeps (string pkgname) {
			string[] optdeps = {};
			unowned Alpm.Package? alpm_pkg = alpm_config.handle.localdb.get_pkg (pkgname);
			if (alpm_pkg == null) {
				alpm_pkg = get_syncpkg (pkgname);
			}
			if (alpm_pkg != null) {
				foreach (unowned Depend optdep in alpm_pkg.optdepends) {
					if (find_satisfier (alpm_config.handle.localdb.pkgcache, optdep.name) == null) {
						optdeps += optdep.compute_string ();
					}
				}
			}
			return optdeps;
		}

		public PackageDetails get_pkg_details (string pkgname) {
			string repo = "";
			string has_signature = _("No");
			int reason = 0;
			string packager = "";
			string install_date = "";
			string[] groups = {};
			string[] backups = {};
			var details = PackageDetails ();
			unowned Alpm.Package? alpm_pkg = alpm_config.handle.localdb.get_pkg (pkgname);
			if (alpm_pkg == null) {
				alpm_pkg = get_syncpkg (pkgname);
			}
			if (alpm_pkg != null) {
				repo = alpm_pkg.db.name;
				packager = alpm_pkg.packager;
				foreach (var group in alpm_pkg.groups) {
					groups += group;
				}
				if (alpm_pkg.db.name == "local") {
					reason = alpm_pkg.reason;
					GLib.Time time = GLib.Time.local ((time_t) alpm_pkg.installdate);
					install_date = time.format ("%a %d %b %Y %X %Z");
					foreach (var backup in alpm_pkg.backups) {
						backups += backup.name;
					}
				} else {
					has_signature = alpm_pkg.base64_sig != null ? _("Yes") : _("No");
				}
			}
			details.repo = repo;
			details.has_signature = has_signature;
			details.reason = reason;
			details.packager = packager;
			details.install_date = install_date;
			details.groups = groups;
			details.backups = backups;
			return details;
		}

		public PackageDeps get_pkg_deps (string pkgname) {
			string repo = "";
			string[] depends = {};
			string[] optdepends = {};
			string[] requiredby = {};
			string[] optionalfor = {};
			string[] provides = {};
			string[] replaces = {};
			string[] conflicts = {};
			var deps = PackageDeps ();
			unowned Alpm.Package? alpm_pkg = alpm_config.handle.localdb.get_pkg (pkgname);
			if (alpm_pkg == null) {
				alpm_pkg = get_syncpkg (pkgname);
			}
			if (alpm_pkg != null) {
				repo = alpm_pkg.db.name;
				foreach (var depend in alpm_pkg.depends) {
					depends += depend.compute_string ();
				}
				foreach (var optdepend in alpm_pkg.optdepends) {
					optdepends += optdepend.compute_string ();
				}
				foreach (var provide in alpm_pkg.provides) {
					provides += provide.compute_string ();
				}
				foreach (var replace in alpm_pkg.replaces) {
					replaces += replace.compute_string ();
				}
				foreach (var conflict in alpm_pkg.conflicts) {
					conflicts += conflict.compute_string ();
				}
				if (alpm_pkg.db.name == "local") {
					Alpm.List<string?> *list = alpm_pkg.compute_requiredby ();
					int i = 0;
					while (i < list->length) {
						requiredby += list->nth_data (i);
						i++;
					}
					Alpm.List.free_all (list);
				}
				if (alpm_pkg.db.name == "local") {
					Alpm.List<string?> *list = alpm_pkg.compute_optionalfor ();
					int i = 0;
					while (i < list->length) {
						optionalfor += list->nth_data (i);
						i++;
					}
					Alpm.List.free_all (list);
				}
			}
			deps.repo = repo;
			deps.depends = depends;
			deps.optdepends = optdepends;
			deps.requiredby = requiredby;
			deps.optionalfor = optionalfor;
			deps.provides = provides;
			deps.replaces = replaces;
			deps.conflicts = conflicts;
			return deps;
		}

		public async Updates get_updates (bool check_aur_updates) {
			var infos = UpdateInfos ();
			UpdateInfos[] updates_infos = {};
			var updates = Updates ();
			unowned Alpm.Package? pkg = null;
			unowned Alpm.Package? candidate = null;
			foreach (var name in alpm_config.syncfirsts) {
				pkg = Alpm.find_satisfier (alpm_config.handle.localdb.pkgcache, name);
				if (pkg != null) {
					candidate = pkg.sync_newversion (alpm_config.handle.syncdbs);
					if (candidate != null) {
						infos.name = candidate.name;
						infos.version = candidate.version;
						infos.db_name = candidate.db.name;
						infos.tarpath = "";
						infos.download_size = candidate.download_size;
						updates_infos += infos;
					}
				}
			}
			if (updates_infos.length != 0) {
				updates.is_syncfirst = true;
				updates.repos_updates = updates_infos;
				return updates;
			} else {
				string[] local_pkgs = {};
				foreach (var installed_pkg in alpm_config.handle.localdb.pkgcache) {
					// check if installed_pkg is in IgnorePkg or IgnoreGroup
					if (alpm_config.handle.should_ignore (installed_pkg) == 0) {
						candidate = installed_pkg.sync_newversion (alpm_config.handle.syncdbs);
						if (candidate != null) {
							infos.name = candidate.name;
							infos.version = candidate.version;
							infos.db_name = candidate.db.name;
							infos.tarpath = "";
							infos.download_size = candidate.download_size;
							updates_infos += infos;
						} else {
							if (check_aur_updates) {
								// check if installed_pkg is a local pkg
								foreach (var db in alpm_config.handle.syncdbs) {
									pkg = Alpm.find_satisfier (db.pkgcache, installed_pkg.name);
									if (pkg != null) {
										break;
									}
								}
								if (pkg == null) {
									local_pkgs += installed_pkg.name;
								}
							}
						}
					}
				}
				updates.repos_updates = updates_infos;
				if (check_aur_updates) {
					// get aur updates
					if (aur_updates_results.get_length () == 0) {
						aur_updates_results = AUR.multiinfo (local_pkgs);
					}
					int cmp;
					unowned Json.Object pkg_info;
					string version;
					string name;
					updates_infos = {};
					foreach (var node in aur_updates_results.get_elements ()) {
						pkg_info = node.get_object ();
						version = pkg_info.get_string_member ("Version");
						name = pkg_info.get_string_member ("Name");
						cmp = Alpm.pkg_vercmp (version, alpm_config.handle.localdb.get_pkg (name).version);
						if (cmp == 1) {
							infos.name = name;
							infos.version = version;
							infos.db_name = "AUR";
							infos.tarpath = pkg_info.get_string_member ("URLPath");
							infos.download_size = 0;
							updates_infos += infos;
						}
					}
					updates.aur_updates = updates_infos;
				}
				return updates;
			}
		}

		public ErrorInfos trans_init (TransFlag transflags) {
			var err = ErrorInfos ();
			string[] details = {};
			int ret = alpm_config.handle.trans_init (transflags);
			if (ret == -1) {
				err.message = _("Failed to init transaction");
				details += Alpm.strerror (alpm_config.handle.errno ());
				err.details = details;
			} else {
				intern_lock = true;
			}
			return err;
		}

		public ErrorInfos trans_sysupgrade (int enable_downgrade) {
			var err = ErrorInfos ();
			string[] details = {};
			int ret = alpm_config.handle.trans_sysupgrade (enable_downgrade);
			if (ret == -1) {
				err.message = _("Failed to prepare transaction");
				details += Alpm.strerror (alpm_config.handle.errno ());
				err.details = details;
			}
			return err;
		}

		private ErrorInfos trans_add_pkg_real (Alpm.Package pkg) {
			var err = ErrorInfos ();
			string[] details = {};
			int ret = alpm_config.handle.trans_add_pkg (pkg);
			if (ret == -1) {
				Alpm.Errno errno = alpm_config.handle.errno ();
				if (errno == Errno.TRANS_DUP_TARGET || errno == Errno.PKG_IGNORED) {
					// just skip duplicate or ignored targets
					return err;
				} else {
					err.message = _("Failed to prepare transaction");
					details += "%s: %s".printf (pkg.name, Alpm.strerror (errno));
					err.details = details;
					return err;
				}
			}
			return err;
		}

		public ErrorInfos trans_add_pkg (string pkgname) {
			var err = ErrorInfos ();
			string[] details = {};
			unowned Alpm.Package? pkg = get_syncpkg (pkgname);
			if (pkg == null) {
				err.message = _("Failed to prepare transaction");
				details += _("target not found: %s").printf (pkgname);
				err.details = details;
				return err;
			} else {
				err = trans_add_pkg_real (pkg);
				if (err.message == "") {
					if (("linux31" in pkg.name) || ("linux4" in pkg.name)) {
						string[] installed_kernels = {};
						string[] installed_modules = {};
						foreach (var local_pkg in alpm_config.handle.localdb.pkgcache) {
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
						}
						string[] splitted = pkg.name.split ("-", 2);
						if (splitted.length == 2) {
							// we are adding a module
							// add the same module for other installed kernels
							foreach (var installed_kernel in installed_kernels) {
								string module = installed_kernel + "-" + splitted[1];
								unowned Alpm.Package? module_pkg = get_syncpkg (module);
								if (module_pkg != null) {
									trans_add_pkg_real (module_pkg);
								}
							}
						} else if (splitted.length == 1) {
							// we are adding a kernel
							// add all installed modules for other kernels
							foreach (var installed_module in installed_modules) {
								string module = splitted[0] + "-" + installed_module;
								unowned Alpm.Package? module_pkg = get_syncpkg (module);
								if (module_pkg != null) {
									trans_add_pkg_real (module_pkg);
								}
							}
						}
					}
				}
				return err;
			}
		}

		public ErrorInfos trans_load_pkg (string pkgpath) {
			var err = ErrorInfos ();
			string[] details = {};
			Alpm.Package* pkg = alpm_config.handle.load_file (pkgpath, 1, alpm_config.handle.localfilesiglevel);
			if (pkg == null) {
				err.message = _("Failed to prepare transaction");
				details += "%s: %s".printf (pkgpath, Alpm.strerror (alpm_config.handle.errno ()));
				err.details = details;
				return err;
			} else {
				int ret = alpm_config.handle.trans_add_pkg (pkg);
				if (ret == -1) {
					Alpm.Errno errno = alpm_config.handle.errno ();
					if (errno == Errno.TRANS_DUP_TARGET || errno == Errno.PKG_IGNORED) {
						// just skip duplicate or ignored targets
						return err;
					 } else {
						err.message = _("Failed to prepare transaction");
						details += "%s: %s".printf (pkg->name, Alpm.strerror (errno));
						err.details = details;
						// free the package because it will not be used
						delete pkg;
						return err;
					}
				}
			}
			return err;
		}

		public ErrorInfos trans_remove_pkg (string pkgname) {
			var err = ErrorInfos ();
			string[] details = {};
			unowned Alpm.Package? pkg =  alpm_config.handle.localdb.get_pkg (pkgname);
			if (pkg == null) {
				err.message = _("Failed to prepare transaction");
				details += _("target not found: %s").printf (pkgname);
				err.details = details;
				return err;
			}
			int ret = alpm_config.handle.trans_remove_pkg (pkg);
			if (ret == -1) {
				err.message = _("Failed to prepare transaction");
				details += "%s: %s".printf (pkg.name, Alpm.strerror (alpm_config.handle.errno ()));
				err.details = details;
			}
			return err;
		}

		private void trans_prepare () {
			var err = ErrorInfos ();
			string[] details = {};
			Alpm.List<void*> err_data = null;
			int ret = alpm_config.handle.trans_prepare (out err_data);
			if (ret == -1) {
				Alpm.Errno errno = alpm_config.handle.errno ();
				err.message = _("Failed to prepare transaction");
				string detail = Alpm.strerror (errno);
				switch (errno) {
					case Errno.PKG_INVALID_ARCH:
						detail += ":";
						details += detail;
						foreach (void *i in err_data) {
							string *pkgname = i;
							details += _("package %s does not have a valid architecture").printf (pkgname);
							delete pkgname;
						}
						break;
					case Errno.UNSATISFIED_DEPS:
						detail += ":";
						details += detail;
						foreach (void *i in err_data) {
							DepMissing *miss = i;
							string depstring = miss->depend.compute_string ();
							details += _("%s: requires %s").printf (miss->target, depstring);
							delete miss;
						}
						break;
					case Errno.CONFLICTING_DEPS:
						detail += ":";
						details += detail;
						foreach (void *i in err_data) {
							Conflict *conflict = i;
							detail = _("%s and %s are in conflict").printf (conflict->package1, conflict->package2);
							// only print reason if it contains new information
							if (conflict->reason.mod != Depend.Mode.ANY) {
								detail += " (%s)".printf (conflict->reason.compute_string ());
							}
							details += detail;
							delete conflict;
						}
						break;
					default:
						details += detail;
						break;
				}
				err.details = details;
				trans_release ();
			} else {
				// Search for holdpkg in target list
				bool found_locked_pkg = false;
				foreach (var pkg in alpm_config.handle.trans_to_remove ()) {
					if (alpm_config.holdpkgs.find_custom (pkg.name, strcmp) != null) {
						details += _("%s needs to be removed but it is a locked package").printf (pkg.name);
						found_locked_pkg = true;
						break;
					}
				}
				if (found_locked_pkg) {
					err.message = _("Failed to prepare transaction");
					err.details = details;
					trans_release ();
				}
			}
			trans_prepare_finished (err);
		}

		public void start_trans_prepare () {
			try {
				thread_pool.add (new AlpmAction (trans_prepare));
			} catch (ThreadError e) {
				stderr.printf ("Thread Error %s\n", e.message);
			}
		}

		public void choose_provider (int provider) {
			provider_mutex.lock ();
			choosen_provider = provider;
			provider_cond.signal ();
			provider_mutex.unlock ();
		}

		public UpdateInfos[] trans_to_add () {
			UpdateInfos info = UpdateInfos ();
			UpdateInfos[] infos = {};
			foreach (var pkg in alpm_config.handle.trans_to_add ()) {
				info.name = pkg.name;
				info.version = pkg.version;
				// if pkg was load from a file, pkg.db is null
				if (pkg.db != null) {
					info.db_name = pkg.db.name;
				} else {
					info.db_name = "";
				}
				info.tarpath = "";
				info.download_size = pkg.download_size;
				infos += info;
			}
			return infos;
		}

		public UpdateInfos[] trans_to_remove () {
			UpdateInfos info = UpdateInfos ();
			UpdateInfos[] infos = {};
			foreach (var pkg in alpm_config.handle.trans_to_remove ()) {
				info.name = pkg.name;
				info.version = pkg.version;
				info.db_name = pkg.db.name;
				info.tarpath = "";
				info.download_size = pkg.download_size;
				infos += info;
			}
			return infos;
		}

		private void trans_commit () {
			var err = ErrorInfos ();
			string[] details = {};
			Alpm.List<void*> err_data = null;
			int ret = alpm_config.handle.trans_commit (out err_data);
			if (ret == -1) {
				Alpm.Errno errno = alpm_config.handle.errno ();
				err.message = _("Failed to commit transaction");
				string detail = Alpm.strerror (errno);
				switch (errno) {
					case Alpm.Errno.FILE_CONFLICTS:
						detail += ":";
						details += detail;
						//TransFlag flags = alpm_config.handle.trans_get_flags ();
						//if ((flags & TransFlag.FORCE) != 0) {
							//details += _("unable to %s directory-file conflicts").printf ("--force");
						//}
						foreach (void *i in err_data) {
							FileConflict *conflict = i;
							switch (conflict->type) {
								case FileConflict.Type.TARGET:
									details += _("%s exists in both %s and %s").printf (conflict->file, conflict->target, conflict->ctarget);
									break;
								case FileConflict.Type.FILESYSTEM:
									details += _("%s: %s already exists in filesystem").printf (conflict->target, conflict->file);
									break;
							}
							delete conflict;
						}
						break;
					case Alpm.Errno.PKG_INVALID:
					case Alpm.Errno.PKG_INVALID_CHECKSUM:
					case Alpm.Errno.PKG_INVALID_SIG:
					case Alpm.Errno.DLT_INVALID:
						detail += ":";
						details += detail;
						foreach (void *i in err_data) {
							string *filename = i;
							details += _("%s is invalid or corrupted").printf (filename);
							delete filename;
						}
						break;
					default:
						details += detail;
						break;
				}
				err.details = details;
			}
			trans_release ();
			refresh_handle ();
			trans_commit_finished (err);
			intern_lock = false;
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
					var err = ErrorInfos ();
					err.message = _("Authentication failed");
					trans_release ();
					refresh_handle ();
					trans_commit_finished (err);
					intern_lock = false;
				}
			});
		}

		public int trans_release () {
			return alpm_config.handle.trans_release ();
		}

		public void trans_cancel () {
			if (alpm_config.handle.trans_interrupt () == 0) {
				// a transaction is being interrupted
				// it will end the normal way
				return;
			}
			var err = ErrorInfos ();
			trans_release ();
			refresh_handle ();
			trans_commit_finished (err);
			intern_lock = false;
		}

		[DBus (no_reply = true)]
		public void quit () {
			// to be sure to not quit with locked databases,
			// the above function will wait for all task in queue
			// to be processed before return; 
			ThreadPool.free ((owned) thread_pool, false, true);
			loop.quit ();
		}
	// End of Daemon Object
	}
}

private void write_log_file (string event) {
	var now = new DateTime.now_local ();
	string log = "%s %s".printf (now.format ("[%Y-%m-%d %H:%M]"), event);
	var file = GLib.File.new_for_path ("/var/log/pamac.log");
	try {
		// creating a DataOutputStream to the file
		var dos = new DataOutputStream (file.append_to (FileCreateFlags.NONE));
		// writing a short string to the stream
		dos.put_string (log);
	} catch (GLib.Error e) {
		stderr.printf ("%s\n", e.message);
	}
}

private void cb_event (Event.Data data) {
	string[] details = {};
	uint secondary_type = 0;
	switch (data.type) {
		case Event.Type.PACKAGE_OPERATION_START:
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
			}
			break;
		case Event.Type.PACKAGE_OPERATION_DONE:
			switch (data.package_operation_operation) {
				case Alpm.Package.Operation.INSTALL:
					string log = "Installed %s (%s)\n".printf (data.package_operation_newpkg.name, data.package_operation_newpkg.version);
					write_log_file (log);
					break;
				case Alpm.Package.Operation.REMOVE:
					string log = "Removed %s (%s)\n".printf (data.package_operation_oldpkg.name, data.package_operation_oldpkg.version);
					write_log_file (log);
					break;
				case Alpm.Package.Operation.REINSTALL:
					string log = "Reinstalled %s (%s)\n".printf (data.package_operation_newpkg.name, data.package_operation_newpkg.version);
					write_log_file (log);
					break;
				case Alpm.Package.Operation.UPGRADE:
					string log = "Upgraded %s (%s -> %s)\n".printf (data.package_operation_oldpkg.name, data.package_operation_oldpkg.version, data.package_operation_newpkg.version);
					write_log_file (log);
					break;
				case Alpm.Package.Operation.DOWNGRADE:
					string log = "Downgraded %s (%s -> %s)\n".printf (data.package_operation_oldpkg.name, data.package_operation_oldpkg.version, data.package_operation_newpkg.version);
					write_log_file (log);
					break;
			}
			break;
		case Event.Type.DELTA_PATCH_START:
			details += data.delta_patch_delta.to;
			details += data.delta_patch_delta.delta;
			break;
		case Event.Type.SCRIPTLET_INFO:
			details += data.scriptlet_info_line;
			write_log_file (data.scriptlet_info_line);
			break;
		case Event.Type.PKGDOWNLOAD_START:
			details += data.pkgdownload_file;
			break;
		case Event.Type.OPTDEP_REMOVAL:
			details += data.optdep_removal_pkg.name;
			details += data.optdep_removal_optdep.compute_string ();
			break;
		case Event.Type.DATABASE_MISSING:
			details += data.database_missing_dbname;
			break;
		case Event.Type.PACNEW_CREATED:
			details += data.pacnew_created_file;
			break;
		case Event.Type.PACSAVE_CREATED:
			details += data.pacsave_created_file;
			break;
		case Event.Type.PACORIG_CREATED:
			details += data.pacorig_created_file;
			break;
		default:
			break;
	}
	pamac_daemon.emit_event ((uint) data.type, secondary_type, details);
}

private void cb_question (Question.Data data) {
	switch (data.type) {
		case Question.Type.INSTALL_IGNOREPKG:
			// Do not install package in IgnorePkg/IgnoreGroup
			data.install_ignorepkg_install = 0;
			break;
		case Question.Type.REPLACE_PKG:
			// Auto-remove conflicts in case of replaces
			data.replace_replace = 1;
			break;
		case Question.Type.CONFLICT_PKG:
			// Auto-remove conflicts
			data.conflict_remove = 1;
			break;
		case Question.Type.REMOVE_PKGS:
			// Do not upgrade packages which have unresolvable dependencies
			data.remove_pkgs_skip = 1;
			break;
		case Question.Type.SELECT_PROVIDER:
			string depend_str = data.select_provider_depend.compute_string ();
			string[] providers_str = {};
			foreach (unowned Alpm.Package pkg in data.select_provider_providers) {
				providers_str += pkg.name;
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
		case Question.Type.CORRUPTED_PKG:
			// Auto-remove corrupted pkgs in cache
			data.corrupted_remove = 1;
			break;
		case Question.Type.IMPORT_KEY:
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

private void cb_progress (Progress progress, string pkgname, int percent, uint n_targets, uint current_target) {
	if ((uint64) percent != pamac_daemon.previous_percent) {
		pamac_daemon.previous_percent = (uint64) percent;
		pamac_daemon.emit_progress ((uint) progress, pkgname, percent, n_targets, current_target);
	}
}

private void cb_download (string filename, uint64 xfered, uint64 total) {
	if (xfered != pamac_daemon.previous_percent) {
		pamac_daemon.previous_percent = xfered;
		pamac_daemon.emit_download (filename, xfered, total);
	}
}

private void cb_totaldownload (uint64 total) {
	pamac_daemon.emit_totaldownload (total);
}

private void cb_log (LogLevel level, string fmt, va_list args) {
	LogLevel logmask = LogLevel.ERROR | LogLevel.WARNING;
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

	Bus.own_name (BusType.SYSTEM, "org.manjaro.pamac", BusNameOwnerFlags.NONE,
				on_bus_acquired,
				null,
				() => {
					stderr.printf ("Could not acquire name\n");
					loop.quit ();
				});

	loop = new MainLoop ();
	loop.run ();
}
