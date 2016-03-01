/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2016 Guillaume Benoit <guillaume@manjaro.org>
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

namespace Pamac {
	[DBus (name = "org.manjaro.pamac")]
	public class Daemon: Object {
		private AlpmConfig alpm_config;
		public Cond provider_cond;
		public Mutex provider_mutex;
		public int? choosen_provider;
		private bool force_refresh;
		private ThreadPool<AlpmAction> thread_pool;
		private Mutex databases_lock_mutex;
		private Json.Array aur_updates_results;
		private bool intern_lock;
		private bool extern_lock;
		private GLib.File lockfile;
		private ErrorInfos current_error;
		public Timer timer;
		public Cancellable cancellable;
		public Curl.Easy curl;

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
														bool enable_aur, bool search_aur, bool check_aur_updates,
														bool no_confirm_build);
		public signal void write_alpm_config_finished (bool checkspace);
		public signal void write_mirrors_config_finished (string choosen_country, string choosen_generation_method);
		public signal void generate_mirrors_list_data (string line);
		public signal void generate_mirrors_list_finished ();

		public Daemon () {
			alpm_config = new AlpmConfig ("/etc/pacman.conf");
			databases_lock_mutex = Mutex ();
			aur_updates_results = new Json.Array ();
			timer = new Timer ();
			intern_lock = false;
			extern_lock = false;
			refresh_handle ();
			Timeout.add (500, check_pacman_running);
			create_thread_pool ();
			cancellable = new Cancellable ();
			Curl.global_init (Curl.GLOBAL_SSL);
		}

		~Daemon () {
			Curl.global_cleanup ();
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
					// exclusive thread
					true
				);
			} catch (ThreadError e) {
				stderr.printf ("Thread Error %s\n", e.message);
			}
		}

		private void refresh_handle () {
			alpm_config.set_handle ();
			if (alpm_config.handle == null) {
				current_error = ErrorInfos () {
					message = _("Failed to initialize alpm library")
				};
				trans_commit_finished (false);
			} else {
				alpm_config.handle.eventcb = (Alpm.EventCallBack) cb_event;
				alpm_config.handle.progresscb = (Alpm.ProgressCallBack) cb_progress;
				alpm_config.handle.questioncb = (Alpm.QuestionCallBack) cb_question;
				alpm_config.handle.fetchcb = (Alpm.FetchCallBack) cb_fetch;
				alpm_config.handle.totaldlcb = (Alpm.TotalDownloadCallBack) cb_totaldownload;
				alpm_config.handle.logcb = (Alpm.LogCallBack) cb_log;
				lockfile = GLib.File.new_for_path (alpm_config.handle.lockfile);
			}
		}

		private bool check_pacman_running () {
			if (extern_lock) {
				if (!lockfile.query_exists ()) {
					extern_lock = false;
					refresh_handle ();
				}
			} else {
				if (lockfile.query_exists ()) {
					if (!intern_lock) {
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
				yield;
			} catch (GLib.Error e) {
				stderr.printf ("%s\n", e.message);
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
			var pamac_config = new Pamac.Config ("/etc/pamac.conf");
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized ) {
					pamac_config.write (new_pamac_conf);
					pamac_config.reload ();
				}
				write_pamac_config_finished (pamac_config.recurse, pamac_config.refresh_period, pamac_config.no_update_hide_icon,
											pamac_config.enable_aur, pamac_config.search_aur, pamac_config.check_aur_updates,
											pamac_config.no_confirm_build);
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
				write_alpm_config_finished ((alpm_config.checkspace == 1));
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
					unowned Alpm.Package? pkg = alpm_config.handle.localdb.get_pkg (pkgname);
					if (pkg != null) {
						pkg.reason = (Alpm.Package.Reason) reason;
						refresh_handle ();
					}
				}
				set_pkgreason_finished ();
			});
		}

		public PackageInfos get_installed_pkg (string pkgname) {
			unowned Alpm.Package? pkg = alpm_config.handle.localdb.get_pkg (pkgname);
			if (pkg == null) {
				return PackageInfos () {
					name = "",
					version = "",
					db_name = "",
					download_size = 0
				};
			}
			return PackageInfos () {
				name = pkg.name,
				version = pkg.version,
				db_name = pkg.db.name,
				download_size = pkg.download_size
			};
		}

		private void refresh () {
			intern_lock = true;
			current_error = ErrorInfos ();
			int force = (force_refresh) ? 1 : 0;
			uint success = 0;
			cancellable.reset ();
			foreach (var db in alpm_config.handle.syncdbs) {
				if (cancellable.is_cancelled ()) {
					refresh_handle ();
					refresh_finished (false);
					intern_lock = false;
					return;
				}
				if (db.update (force) >= 0) {
					success++;
				}
			}
			refresh_handle ();
			// We should always succeed if at least one DB was upgraded - we may possibly
			// fail later with unresolved deps, but that should be rare, and would be expected
			if (success == 0) {
				Alpm.Errno errno = alpm_config.handle.errno ();
				current_error.errno = (uint) errno;
				current_error.message = _("Failed to synchronize any databases");
				current_error.details = { Alpm.strerror (errno) };
				refresh_finished (false);
			} else {
				refresh_finished (true);
			}
			intern_lock = false;
		}

		public void start_refresh (bool force) {
			force_refresh = force;
			try {
				thread_pool.add (new AlpmAction (refresh));
			} catch (ThreadError e) {
				stderr.printf ("Thread Error %s\n", e.message);
			}
		}

		public void add_ignorepkg (string pkgname) {
			alpm_config.handle.add_ignorepkg (pkgname);
		}

		public void remove_ignorepkg (string pkgname) {
			alpm_config.handle.remove_ignorepkg (pkgname);
		}

		public void start_get_updates (bool check_aur_updates) {
			PackageInfos[] updates_infos = {};
			unowned Alpm.Package? pkg = null;
			unowned Alpm.Package? candidate = null;
			foreach (var name in alpm_config.syncfirsts) {
				pkg = Alpm.find_satisfier (alpm_config.handle.localdb.pkgcache, name);
				if (pkg != null) {
					candidate = pkg.sync_newversion (alpm_config.handle.syncdbs);
					if (candidate != null) {
						var infos = PackageInfos () {
							name = candidate.name,
							version = candidate.version,
							db_name = candidate.db.name,
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
				return;
			} else {
				string[] local_pkgs = {};
				foreach (var installed_pkg in alpm_config.handle.localdb.pkgcache) {
					// check if installed_pkg is in IgnorePkg or IgnoreGroup
					if (alpm_config.handle.should_ignore (installed_pkg) == 0) {
						candidate = installed_pkg.sync_newversion (alpm_config.handle.syncdbs);
						if (candidate != null) {
							var infos = PackageInfos () {
								name = candidate.name,
								version = candidate.version,
								db_name = candidate.db.name,
								download_size = candidate.download_size
							};
							updates_infos += (owned) infos;
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
				PackageInfos[] aur_updates_infos = {};
				if (check_aur_updates) {
					// get aur updates
					if (aur_updates_results.get_length () == 0) {
						aur_updates_results = AUR.multiinfo (local_pkgs);
					}
					aur_updates_results.foreach_element ((array, index,node) => {
						unowned Json.Object pkg_info = node.get_object ();
						string version = pkg_info.get_string_member ("Version");
						string name = pkg_info.get_string_member ("Name");
						int cmp = Alpm.pkg_vercmp (version, alpm_config.handle.localdb.get_pkg (name).version);
						if (cmp == 1) {
							var infos = PackageInfos () {
								name = name,
								version = version,
								db_name = "AUR",
								download_size = 0
							};
							aur_updates_infos += (owned) infos;
						}
					});
				}
				var updates = Updates () {
					is_syncfirst = false,
					repos_updates = (owned) updates_infos,
					aur_updates = (owned) aur_updates_infos
				};
				get_updates_finished (updates);
			}
		}

		public bool trans_init (Alpm.TransFlag transflags) {
			current_error = ErrorInfos ();
			cancellable.reset ();
			if (alpm_config.handle.trans_init (transflags) == -1) {
				Alpm.Errno errno = alpm_config.handle.errno ();
				current_error.errno = (uint) errno;
				current_error.message = _("Failed to init transaction");
				current_error.details = { Alpm.strerror (errno) };
				return false;
			} else {
				intern_lock = true;
			}
			return true;
		}

		public bool trans_sysupgrade (bool enable_downgrade) {
			current_error = ErrorInfos ();
			if (alpm_config.handle.trans_sysupgrade ((enable_downgrade) ? 1 : 0) == -1) {
				Alpm.Errno errno = alpm_config.handle.errno ();
				current_error.errno = (uint) errno;
				current_error.message = _("Failed to prepare transaction");
				current_error.details = { Alpm.strerror (errno) };
				return false;
			}
			return true;
		}

		private bool trans_add_pkg_real (Alpm.Package pkg) {
			current_error = ErrorInfos ();
			if (alpm_config.handle.trans_add_pkg (pkg) == -1) {
				Alpm.Errno errno = alpm_config.handle.errno ();
				if (errno == Alpm.Errno.TRANS_DUP_TARGET || errno == Alpm.Errno.PKG_IGNORED) {
					// just skip duplicate or ignored targets
					return true;
				} else {
					current_error.errno = (uint) errno;
					current_error.message = _("Failed to prepare transaction");
					current_error.details = { "%s: %s".printf (pkg.name, Alpm.strerror (errno)) };
					return false;
				}
			}
			return true;
		}

		private unowned Alpm.Package? get_sync_pkg (string pkgname) {
			unowned Alpm.Package? pkg = null;
			foreach (var db in alpm_config.handle.syncdbs) {
				pkg = db.get_pkg (pkgname);
				if (pkg != null) {
					break;
				}
			}
			return pkg;
		}

		public bool trans_add_pkg (string pkgname) {
			current_error = ErrorInfos ();
			unowned Alpm.Package? pkg = get_sync_pkg (pkgname);
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
							foreach (unowned string installed_kernel in installed_kernels) {
								string module = installed_kernel + "-" + splitted[1];
								unowned Alpm.Package? module_pkg = get_sync_pkg (module);
								if (module_pkg != null) {
									trans_add_pkg_real (module_pkg);
								}
							}
						} else if (splitted.length == 1) {
							// we are adding a kernel
							// add all installed modules for other kernels
							foreach (unowned string installed_module in installed_modules) {
								string module = splitted[0] + "-" + installed_module;
								unowned Alpm.Package? module_pkg = get_sync_pkg (module);
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

		public bool trans_load_pkg (string pkgpath) {
			current_error = ErrorInfos ();
			Alpm.Package* pkg = alpm_config.handle.load_file (pkgpath, 1, alpm_config.handle.localfilesiglevel);
			if (pkg == null) {
				Alpm.Errno errno = alpm_config.handle.errno ();
				current_error.errno = (uint) errno;
				current_error.message = _("Failed to prepare transaction");
				current_error.details = { "%s: %s".printf (pkgpath, Alpm.strerror (errno)) };
				return false;
			} else if (alpm_config.handle.trans_add_pkg (pkg) == -1) {
				Alpm.Errno errno = alpm_config.handle.errno ();
				current_error.errno = (uint) errno;
				current_error.message = _("Failed to prepare transaction");
				current_error.details = { "%s: %s".printf (pkg->name, Alpm.strerror (errno)) };
				// free the package because it will not be used
				delete pkg;
				return false;
			}
			return true;
		}

		public bool trans_remove_pkg (string pkgname) {
			current_error = ErrorInfos ();
			unowned Alpm.Package? pkg =  alpm_config.handle.localdb.get_pkg (pkgname);
			if (pkg == null) {
				current_error.message = _("Failed to prepare transaction");
				current_error.details = { _("target not found: %s").printf (pkgname) };
				return false;
			} else if (alpm_config.handle.trans_remove_pkg (pkg) == -1) {
				Alpm.Errno errno = alpm_config.handle.errno ();
				current_error.errno = (uint) errno;
				current_error.message = _("Failed to prepare transaction");
				current_error.details = { "%s: %s".printf (pkg.name, Alpm.strerror (errno)) };
				return false;
			}
			return true;
		}

		private void trans_prepare () {
			current_error = ErrorInfos ();
			string[] details = {};
			Alpm.List<void*> err_data;
			if (alpm_config.handle.trans_prepare (out err_data) == -1) {
				Alpm.Errno errno = alpm_config.handle.errno ();
				current_error.errno = (uint) errno;
				current_error.message = _("Failed to prepare transaction");
				string detail = Alpm.strerror (errno);
				switch (errno) {
					case Alpm.Errno.PKG_INVALID_ARCH:
						detail += ":";
						details += (owned) detail;
						foreach (void* i in err_data) {
							string* pkgname = i;
							details += _("package %s does not have a valid architecture").printf (pkgname);
							delete pkgname;
						}
						break;
					case Alpm.Errno.UNSATISFIED_DEPS:
						detail += ":";
						details += (owned) detail;
						foreach (void* i in err_data) {
							Alpm.DepMissing* miss = i;
							details += _("%s: requires %s").printf (miss->target, miss->depend.compute_string ());
							delete miss;
						}
						break;
					case Alpm.Errno.CONFLICTING_DEPS:
						detail += ":";
						details += (owned) detail;
						foreach (void* i in err_data) {
							Alpm.Conflict* conflict = i;
							string conflict_detail = _("%s and %s are in conflict").printf (conflict->package1, conflict->package2);
							// only print reason if it contains new information
							if (conflict->reason.mod != Alpm.Depend.Mode.ANY) {
								conflict_detail += " (%s)".printf (conflict->reason.compute_string ());
							}
							details += (owned) conflict_detail;
							delete conflict;
						}
						break;
					default:
						details += (owned) detail;
						break;
				}
				current_error.details = (owned) details;
				trans_release ();
				trans_prepare_finished (false);
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
					current_error.message = _("Failed to prepare transaction");
					current_error.details = (owned) details;
					trans_release ();
					trans_prepare_finished (false);
				} else {
					trans_prepare_finished (true);
				}
			}
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

		public PackageInfos[] trans_to_add () {
			PackageInfos[] to_add = {};
			foreach (var pkg in alpm_config.handle.trans_to_add ()) {
				var infos = PackageInfos () {
					name = pkg.name,
					version = pkg.version,
					// if pkg was load from a file, pkg.db is null
					db_name = pkg.db != null ? pkg.db.name : "",
					download_size = pkg.download_size
				};
				to_add += (owned) infos;
			}
			return to_add;
		}

		public PackageInfos[] trans_to_remove () {
			PackageInfos[] to_remove = {};
			foreach (var pkg in alpm_config.handle.trans_to_remove ()) {
				var infos = PackageInfos () {
					name = pkg.name,
					version = pkg.version,
					db_name = pkg.db.name,
					download_size = pkg.download_size
				};
				to_remove += (owned) infos;
			}
			return to_remove;
		}

		private void trans_commit () {
			current_error = ErrorInfos ();
			bool success = true;
			Alpm.List<void*> err_data;
			if (alpm_config.handle.trans_commit (out err_data) == -1) {
				Alpm.Errno errno = alpm_config.handle.errno ();
				// cancel the download return an EXTERNAL_DOWNLOAD error
				if (errno == Alpm.Errno.EXTERNAL_DOWNLOAD && cancellable.is_cancelled ()) {
					trans_release ();
					refresh_handle ();
					trans_commit_finished (false);
					return;
				}
				current_error.errno = (uint) errno;
				current_error.message = _("Failed to commit transaction");
				string detail = Alpm.strerror (errno);
				string[] details = {};
				switch (errno) {
					case Alpm.Errno.FILE_CONFLICTS:
						detail += ":";
						details += (owned) detail;
						//TransFlag flags = alpm_config.handle.trans_get_flags ();
						//if ((flags & TransFlag.FORCE) != 0) {
							//details += _("unable to %s directory-file conflicts").printf ("--force");
						//}
						foreach (void* i in err_data) {
							Alpm.FileConflict* conflict = i;
							switch (conflict->type) {
								case Alpm.FileConflict.Type.TARGET:
									details += _("%s exists in both %s and %s").printf (conflict->file, conflict->target, conflict->ctarget);
									break;
								case Alpm.FileConflict.Type.FILESYSTEM:
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
						details += (owned) detail;
						foreach (void* i in err_data) {
							string* filename = i;
							details += _("%s is invalid or corrupted").printf (filename);
							delete filename;
						}
						break;
					default:
						details += (owned) detail;
						break;
				}
				current_error.details = (owned) details;
				success = false;
			}
			trans_release ();
			refresh_handle ();
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
					current_error = ErrorInfos () {
						message = _("Authentication failed")
					};
					trans_release ();
					refresh_handle ();
					trans_commit_finished (false);
				}
			});
		}

		public void trans_release () {
			alpm_config.handle.trans_release ();
			intern_lock = false;
		}

		[DBus (no_reply = true)]
		public void trans_cancel () {
			if (alpm_config.handle.trans_interrupt () == 0) {
				// a transaction is being interrupted
				// it will end the normal way
				return;
			}
			cancellable.cancel ();
		}

		[DBus (no_reply = true)]
		public void quit () {
			// to be sure to not quit with locked databases,
			// the above function will wait for all task in queue
			// to be processed before return; 
			ThreadPool.free ((owned) thread_pool, false, true);
			alpm_config.handle.unlock ();
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
		case Alpm.Event.Type.PACKAGE_OPERATION_DONE:
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
		case Alpm.Event.Type.DELTA_PATCH_START:
			details += data.delta_patch_delta.to;
			details += data.delta_patch_delta.delta;
			break;
		case Alpm.Event.Type.SCRIPTLET_INFO:
			details += data.scriptlet_info_line;
			write_log_file (data.scriptlet_info_line);
			break;
		case Alpm.Event.Type.PKGDOWNLOAD_START:
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
			// Do not upgrade packages which have unresolvable dependencies
			data.remove_pkgs_skip = 1;
			break;
		case Alpm.Question.Type.SELECT_PROVIDER:
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

	if (unlikely (dltotal == 0 || prevprogress == dltotal)) {
		return 0;
	} else if (unlikely (dlnow == 0)) {
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

//~ 	// avoid displaying progress for redirects with a body
//~ 	if (respcode >= 300) {
//~ 		return 0;
//~ 	}

	prevprogress = dlnow;

	return 0;
}

private int cb_fetch (string fileurl, string localpath, int force) {
	if (pamac_daemon.cancellable.is_cancelled ()) {
		return -1;
	}

	if (pamac_daemon.curl == null) {
		pamac_daemon.curl = new Curl.Easy ();
	}

	char error_buffer[Curl.ERROR_SIZE];
	var url = GLib.File.new_for_uri (fileurl);
	var destfile = GLib.File.new_for_path (localpath + url.get_basename ());
	var tempfile = GLib.File.new_for_path (destfile.get_path () + ".part");

	pamac_daemon.curl.reset ();
	pamac_daemon.curl.setopt (Curl.Option.URL, fileurl);
	pamac_daemon.curl.setopt (Curl.Option.FAILONERROR, 1L);
	pamac_daemon.curl.setopt (Curl.Option.ERRORBUFFER, error_buffer);
	pamac_daemon.curl.setopt (Curl.Option.CONNECTTIMEOUT, 30L);
	pamac_daemon.curl.setopt (Curl.Option.FILETIME, 1L);
	pamac_daemon.curl.setopt (Curl.Option.NOPROGRESS, 0L);
	pamac_daemon.curl.setopt (Curl.Option.FOLLOWLOCATION, 1L);
	pamac_daemon.curl.setopt (Curl.Option.XFERINFOFUNCTION, cb_download);
	pamac_daemon.curl.setopt (Curl.Option.XFERINFODATA, (void*) url.get_basename ());
	pamac_daemon.curl.setopt (Curl.Option.LOW_SPEED_LIMIT, 1L);
	pamac_daemon.curl.setopt (Curl.Option.LOW_SPEED_TIME, 30L);
	pamac_daemon.curl.setopt (Curl.Option.NETRC, Curl.NetRCOption.OPTIONAL);
	pamac_daemon.curl.setopt (Curl.Option.HTTPAUTH, Curl.CURLAUTH_ANY);

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
		stdout.printf ("could not open file %s\n", tempfile.get_path ());
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
				pamac_daemon.emit_log ((uint) Alpm.LogLevel.ERROR,
										_("%s appears to be truncated: %jd/%jd bytes\n").printf (
											fileurl, bytes_dl, remote_size));
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
			// do not report error for missing sig with db
			if (!fileurl.has_suffix ("db.sig")) {
				string hostname = url.get_uri ().split("/")[2];
				pamac_daemon.emit_log ((uint) Alpm.LogLevel.ERROR,
										_("failed retrieving file '%s' from %s : %s\n").printf (
											url.get_basename (), hostname, error_buffer));
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

	loop = new MainLoop ();
	loop.run ();
}
