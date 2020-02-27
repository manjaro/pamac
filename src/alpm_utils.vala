/*
 *  pamac-vala
 *
 *  Copyright (C) 2018-2020 Guillaume Benoit <guillaume@manjaro.org>
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

Pamac.AlpmUtils alpm_utils;

string current_filename;
string current_action;
uint64 total_download;
Mutex multi_progress_mutex;
HashTable<string, uint64?> multi_progress;
HashTable<string, AsyncQueue> queues_table;
GenericArray<string> unresolvables;

class DownloadServer: Object {
	Soup.Session soup_session;
	string cachedir;
	string server_url;
	GenericSet<string?> repos;

	public DownloadServer (Alpm.Handle handle, owned string server_url, owned GenericSet<string?> repos) {
		soup_session = new Soup.Session ();
		soup_session.user_agent = "Pamac/%s".printf (VERSION);
		cachedir = handle.cachedirs.nth (0).data;
		this.server_url = server_url;
		this.repos = repos;
	}

	public void download_files () {
		foreach (unowned string repo in repos) {
			if (alpm_utils.cancellable.is_cancelled ()) {
				return;
			}
			unowned AsyncQueue<string>? dload_queue = queues_table.lookup (repo);
			if (dload_queue == null) {
				continue;
			}
			// check if download are available
			while (dload_queue.length () > 0) {
				if (alpm_utils.cancellable.is_cancelled ()) {
					return;
				}
				// wait for the lock
				dload_queue.lock ();
				string? filename = dload_queue.try_pop_unlocked ();
				dload_queue.unlock ();
				if (filename != null) {
					current_filename = filename;
					int ret = dload (soup_session,
									"%s/%s".printf (server_url.replace ("$repo", repo), filename),
									cachedir,
									0,
									cb_multi_download);
					if (ret == -1) {
						// error
						// re-add filename to queue and return to use another mirror
						dload_queue.lock ();
						dload_queue.push_front_unlocked (filename);
						dload_queue.unlock ();
						return;
					}
				}
			}
		}
	}
}

namespace Pamac {
	internal class AlpmUtils: Object {
		string sender;
		Config config;
		public AlpmConfig alpm_config;
		string tmp_path;
		public GLib.File lockfile;
		MainContext context;
		// run transaction data
		string current_status;
		double current_progress;
		bool sysupgrade;
		bool enable_downgrade;
		bool simple_install;
		bool check_aur_updates;
		bool no_confirm_commit;
		bool keep_built_pkgs;
		int trans_flags;
		GenericSet<string?> to_install;
		GenericSet<string?> to_remove;
		GenericSet<string?> to_load;
		GenericSet<string?> to_build;
		HashTable<string, string> to_install_as_dep;
		GenericSet<string?> temporary_ignorepkgs;
		GenericSet<string?> overwrite_files;
		GenericSet<string?> to_syncfirst;
		public Cancellable cancellable;
		public bool downloading_updates;
		// download data
		public Soup.Session soup_session;
		public Timer timer;
		uint64 already_downloaded;
		uint64 previous_xfered;
		uint64 download_rate;
		uint64 rates_nb;

		public signal int choose_provider (string depend, string[] providers);
		public signal void start_downloading (string sender);
		public signal void stop_downloading (string sender);
		public signal void emit_action (string sender, string action);
		public signal void emit_action_progress (string sender, string action, string status, double progress);
		public signal void emit_download_progress (string sender, string action, string status, double progress);
		public signal void emit_hook_progress (string sender, string action, string details, string status, double progress);
		public signal void emit_script_output (string sender, string message);
		public signal void emit_warning (string sender, string message);
		public signal void emit_error (string sender, string message, string[] details);
		public signal void important_details_outpout (string sender, bool must_show);
		public signal bool get_authorization (string sender);

		public AlpmUtils (Config config, MainContext context) {
			this.config = config;
			multi_progress_mutex = Mutex ();
			this.context = context;
			alpm_config = config.alpm_config;
			tmp_path = "/tmp/pamac";
			to_syncfirst = new GenericSet<string?> (str_hash, str_equal);
			to_install = new GenericSet<string?> (str_hash, str_equal);
			to_remove = new GenericSet<string?> (str_hash, str_equal);
			to_load = new GenericSet<string?> (str_hash, str_equal);
			to_build = new GenericSet<string?> (str_hash, str_equal);
			to_install_as_dep = new HashTable<string, string> (str_hash, str_equal);
			temporary_ignorepkgs = new GenericSet<string?> (str_hash, str_equal);
			overwrite_files = new GenericSet<string?> (str_hash, str_equal);
			current_filename = "";
			current_action = "";
			current_status = "";
			timer = new Timer ();
			cancellable = new Cancellable ();
			soup_session = new Soup.Session ();
			soup_session.user_agent = "Pamac/%s".printf (VERSION);
			downloading_updates = false;
			check_old_lock ();
		}

		public int do_choose_provider (string depend, string[] providers) {
			string[] providers_copy = providers;
			int index = 0;
			var loop = new MainLoop (context);
			var idle = new IdleSource ();
			idle.set_priority (Priority.DEFAULT);
			idle.set_callback (() => {
				index = choose_provider (depend, providers_copy);
				loop.quit ();
				return false;
			});
			idle.attach (context);
			loop.run ();
			return index;
		}

		void do_start_downloading () {
			context.invoke (() => {
				start_downloading (sender);
				return false;
			});
		}

		void do_stop_downloading () {
			context.invoke (() => {
				stop_downloading (sender);
				return false;
			});
		}

		void do_emit_action (string action) {
			context.invoke (() => {
				emit_action (sender, action);
				return false;
			});
		}

		void do_emit_action_progress (string action, string status, double progress) {
			context.invoke (() => {
				emit_action_progress (sender, action, status, progress);
				return false;
			});
		}

		void do_emit_download_progress (string action, string status, double progress) {
			context.invoke (() => {
				emit_download_progress (sender, action, status, progress);
				return false;
			});
		}

		void do_emit_hook_progress (string action, string details, string status, double progress) {
			context.invoke (() => {
				emit_hook_progress (sender, action, details, status, progress);
				return false;
			});
		}

		public void do_emit_script_output (string message) {
			context.invoke (() => {
				emit_script_output (sender, message);
				return false;
			});
		}

		void do_emit_warning (string message) {
			context.invoke (() => {
				emit_warning (sender, message);
				return false;
			});
		}

		void do_emit_error (string message, string[] details) {
			string[] details_copy = details;
			context.invoke (() => {
				emit_error (sender, message, details_copy);
				return false;
			});
		}

		void do_important_details_outpout (bool must_show) {
			context.invoke (() => {
				important_details_outpout (sender, must_show);
				return false;
			});
		}

		bool do_get_authorization () {
			bool authorized = false;
			var loop = new MainLoop (context);
			var idle = new IdleSource ();
			idle.set_priority (Priority.DEFAULT);
			idle.set_callback (() => {
				authorized = get_authorization (sender);
				loop.quit ();
				return false;
			});
			idle.attach (context);
			loop.run ();
			return authorized;
		}

		void check_old_lock () {
			var alpm_handle = get_handle (false, false, false);
			if (alpm_handle == null) {
				return;
			}
			lockfile = GLib.File.new_for_path (alpm_handle.lockfile);
			if (lockfile.query_exists ()) {
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
															warning (e.message);
														}
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
					warning (e.message);
				}
			}
		}

		public Alpm.Handle? get_handle (bool files_db = false, bool tmp_db = false, bool callbacks = true) {
			alpm_config.reload ();
			var alpm_handle = alpm_config.get_handle (files_db, tmp_db);
			if (alpm_handle == null) {
				warning ("%s\n", _("Failed to initialize alpm library"));
				do_emit_error ("Alpm Error", {_("Failed to initialize alpm library")});
			} else if (callbacks) {
				alpm_handle.eventcb = (Alpm.EventCallBack) cb_event;
				alpm_handle.progresscb = (Alpm.ProgressCallBack) cb_progress;
				alpm_handle.questioncb = (Alpm.QuestionCallBack) cb_question;
				alpm_handle.fetchcb = (Alpm.FetchCallBack) cb_fetch;
				alpm_handle.totaldlcb = (Alpm.TotalDownloadCallBack) cb_totaldownload;
				alpm_handle.logcb = (Alpm.LogCallBack) cb_log;
			}
			return alpm_handle;
		}

		public bool set_pkgreason (string pkgname, uint reason) {
			var alpm_handle = get_handle (false, false, false);
			if (alpm_handle == null) {
				return false;
			}
			unowned Alpm.Package? pkg = alpm_handle.localdb.get_pkg (pkgname);
			if (pkg != null) {
				// lock the database
				if (alpm_handle.trans_init (0) == 0) {
					pkg.reason = (Alpm.Package.Reason) reason;
					alpm_handle.trans_release ();
					return true;
				}
			}
			return false;
		}

		public bool clean_cache (string[] filenames) {
			try {
				foreach (unowned string filename in filenames) {
					var file = GLib.File.new_for_path (filename);
					file.delete ();
				}
				return true;
			} catch (Error e) {
				warning (e.message);
			}
			return false;
		}

		internal bool clean_build_files (string aur_build_dir) {
			try {
				Process.spawn_command_line_sync ("rm -rf %s".printf (aur_build_dir));
				return true;
			} catch (SpawnError e) {
				warning (e.message);
			}
			return false;
		}

		unowned Alpm.Package? get_syncpkg (Alpm.Handle alpm_handle, string name) {
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

		bool update_dbs (Alpm.Handle alpm_handle, int force) {
			bool success = false;
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				if (cancellable.is_cancelled ()) {
					break;
				}
				unowned Alpm.DB db = syncdbs.data;
				if (db.update (force) >= 0) {
					// We should always succeed if at least one DB was upgraded - we may possibly
					// fail later with unresolved deps, but that should be rare, and would be expected
					success = true;
				} else {
					Alpm.Errno errno = alpm_handle.errno ();
					if (errno != 0) {
						// download error details are set in cb_fetch
						if (errno != Alpm.Errno.EXTERNAL_DOWNLOAD) {
							do_emit_warning (Alpm.strerror (errno));
						}
					}
				}
				syncdbs.next ();
			}
			return success;
		}

		public bool refresh (string sender, bool force_refresh) {
			this.sender = sender;
			do_emit_action (_("Synchronizing package databases") + "...");
			do_start_downloading ();
			write_log_file ("synchronizing package lists");
			cancellable.reset ();
			int force = (force_refresh) ? 1 : 0;
			if (force_refresh) {
				// remove dbs in tmp
				try {
					Process.spawn_command_line_sync ("bash -c 'rm -rf %s/dbs*'".printf (tmp_path));
				} catch (SpawnError e) {
					warning (e.message);
				}
			} else {
				// try to copy refresh dbs in tmp
				var file = GLib.File.new_for_path (tmp_path);
				if (file.query_exists ()) {
					try {
						var alpm_handle = get_handle ();
						Process.spawn_command_line_sync ("bash -c 'cp -u %s/dbs*/sync/*.{db,files} %ssync'".printf (tmp_path, alpm_handle.dbpath));
					} catch (SpawnError e) {
						warning (e.message);
					}
				}
			}
			// a new handle is required to use copied databases
			var alpm_handle = get_handle ();
			if (alpm_handle == null) {
				return false;
			}
			// update ".db"
			bool success = update_dbs (alpm_handle, force);
			if (cancellable.is_cancelled ()) {
				return false;
			}
			// only refresh ".files" if force
			if (force_refresh) {
				// update ".files", do not need to know if we succeeded
				var files_handle = get_handle (true);
				if (files_handle != null) {
					update_dbs (files_handle, force);
				}
			}
			do_stop_downloading ();
			if (cancellable.is_cancelled ()) {
				return false;
			} else if (!success) {
				do_emit_warning (_("Failed to synchronize databases"));
			}
			current_filename = "";
			// return false only if cancelled
			return true;
		}

		void add_ignorepkgs (Alpm.Handle alpm_handle) {
			foreach (unowned string pkgname in temporary_ignorepkgs) {
				alpm_handle.add_ignorepkg (pkgname);
			}
		}

		void remove_ignorepkgs (Alpm.Handle alpm_handle) {
			foreach (unowned string pkgname in temporary_ignorepkgs) {
				alpm_handle.remove_ignorepkg (pkgname);
			}
		}

		void add_overwrite_files (Alpm.Handle alpm_handle) {
			foreach (unowned string name in overwrite_files) {
				alpm_handle.add_overwrite_file (name);
			}
		}

		void remove_overwrite_files (Alpm.Handle alpm_handle) {
			foreach (unowned string name in overwrite_files) {
				alpm_handle.remove_overwrite_file (name);
			}
		}

		Package initialise_pkg (Alpm.Handle alpm_handle, Alpm.Package? alpm_pkg) {
			var pkg = new Package ();
			if (alpm_pkg != null) {
				pkg.name = alpm_pkg.name;
				pkg.version = alpm_pkg.version;
				if (alpm_pkg.desc != null) {
					pkg.desc = alpm_pkg.desc;
				}
				if (alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
					pkg.installed_version = alpm_pkg.version;
					unowned Alpm.Package? sync_pkg = get_syncpkg (alpm_handle, alpm_pkg.name);
					if (sync_pkg != null) {
						pkg.repo = sync_pkg.db.name;
					}
				} else if (alpm_pkg.origin == Alpm.Package.From.SYNCDB) {
					unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (alpm_pkg.name);
					if (local_pkg != null) {
						pkg.installed_version = local_pkg.version;
					}
					if (alpm_pkg.db.name == "pamac_aur") {
						pkg.repo = dgettext (null, "AUR");
					} else {
						pkg.repo = alpm_pkg.db.name;
					}
				} else {
					// load pkg or built pkg
					unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (alpm_pkg.name);
					if (local_pkg != null) {
						pkg.installed_version = local_pkg.version;
					}
				}
				pkg.installed_size = alpm_pkg.isize;
				pkg.download_size = alpm_pkg.download_size;
				pkg.installdate = alpm_pkg.installdate;
			}
			return pkg;
		}

		public void download_updates () {
			downloading_updates = true;
			// use tmp handle
			var alpm_handle = alpm_config.get_handle (false, true);
			alpm_handle.fetchcb = (Alpm.FetchCallBack) cb_fetch;
			cancellable.reset ();
			// refresh tmp dbs
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				db.update (0);
				syncdbs.next ();
			}
			int success = alpm_handle.trans_init (Alpm.TransFlag.DOWNLOADONLY);
			if (success == 0) {
				// can't add nolock flag with commit so remove unneeded lock
				alpm_handle.unlock ();
				success = alpm_handle.trans_sysupgrade (0);
				if (success == 0) {
					Alpm.List err_data;
					success = alpm_handle.trans_prepare (out err_data);
					if (success == 0) {
						success = alpm_handle.trans_commit (out err_data);
					}
				}
				alpm_handle.trans_release ();
			}
			// remove dbs in tmp
			try {
				Process.spawn_command_line_sync ("rm -rf %s/dbs-root".printf (tmp_path));
			} catch (SpawnError e) {
				warning (e.message);
			}
			downloading_updates = false;
		}

		bool trans_init (Alpm.Handle alpm_handle, int flags) {
			cancellable.reset ();
			if (alpm_handle.trans_init ((Alpm.TransFlag) flags) == -1) {
				Alpm.Errno errno = alpm_handle.errno ();
				if (errno != 0) {
					do_emit_error (_("Failed to init transaction"), {Alpm.strerror (errno)});
				} else {
					do_emit_error (_("Failed to init transaction"), {});
				}
				return false;
			}
			return true;
		}

		bool trans_sysupgrade (Alpm.Handle alpm_handle) {
			add_ignorepkgs (alpm_handle);
			if (alpm_handle.trans_sysupgrade ((enable_downgrade) ? 1 : 0) == -1) {
				Alpm.Errno errno = alpm_handle.errno ();
				if (errno != 0) {
					do_emit_error (_("Failed to prepare transaction"), {Alpm.strerror (errno)});
				} else {
					do_emit_error (_("Failed to prepare transaction"), {});
				}
				return false;
			}
			// check syncfirsts
			to_syncfirst.remove_all ();
			foreach (unowned string name in alpm_config.syncfirsts) {
				unowned Alpm.Package? pkg = Alpm.find_satisfier (alpm_handle.localdb.pkgcache, name);
				if (pkg != null) {
					unowned Alpm.Package? candidate = pkg.get_new_version (alpm_handle.syncdbs);
					if (candidate != null) {
						to_syncfirst.add (candidate.name);
					}
				}
			}
			return true;
		}

		bool trans_add_pkg_real (Alpm.Handle alpm_handle, Alpm.Package pkg) {
			if (alpm_handle.trans_add_pkg (pkg) == -1) {
				Alpm.Errno errno = alpm_handle.errno ();
				if (errno == Alpm.Errno.TRANS_DUP_TARGET || errno == Alpm.Errno.PKG_IGNORED) {
					// just skip duplicate or ignored targets
					return true;
				} else {
					if (errno != 0) {
						do_emit_error (_("Failed to prepare transaction"), {Alpm.strerror (errno)});
					} else {
						do_emit_error (_("Failed to prepare transaction"), {});
					}
					return false;
				}
			}
			return true;
		}

		bool trans_add_pkg (Alpm.Handle alpm_handle, string pkgname) {
			unowned Alpm.Package? pkg = alpm_handle.find_dbs_satisfier (alpm_handle.syncdbs, pkgname);
			if (pkg == null) {
				do_emit_error (_("Failed to prepare transaction"), {_("target not found: %s").printf (pkgname)});
				return false;
			} else {
				bool success = trans_add_pkg_real (alpm_handle, pkg);
				if (success) {
					if (("linux31" in pkg.name) || ("linux4" in pkg.name) || ("linux5" in pkg.name)) {
						var installed_kernels = new GenericArray<unowned string> ();
						var installed_modules = new GenericArray<unowned string> ();
						unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
						while (pkgcache != null) {
							unowned Alpm.Package local_pkg = pkgcache.data;
							if (("linux31" in local_pkg.name) || ("linux4" in local_pkg.name) || ("linux5" in local_pkg.name)) {
								string[] local_pkg_splitted = local_pkg.name.split ("-", 2);
								if (!installed_kernels.find_with_equal_func (local_pkg_splitted[0], str_equal)) {
									installed_kernels.add (local_pkg_splitted[0]);
								}
								if (local_pkg_splitted.length == 2) {
									if (!installed_modules.find_with_equal_func (local_pkg_splitted[1], str_equal)) {
										installed_modules.add (local_pkg_splitted[1]);
									}
								}
							}
							pkgcache.next ();
						}
						string[] splitted = pkg.name.split ("-", 2);
						if (splitted.length == 2) {
							// we are adding a module
							// add the same module for other installed kernels
							for (uint i = 0; i < installed_kernels.length; i++) {
								var module = new StringBuilder ();
								module.append (installed_kernels[i]);
								module.append ("-");
								module.append (splitted[1]);
								unowned Alpm.Package? installed_module_pkg = alpm_handle.localdb.get_pkg (module.str);
								if (installed_module_pkg == null) {
									unowned Alpm.Package? module_pkg = get_syncpkg (alpm_handle, module.str);
									if (module_pkg != null) {
										trans_add_pkg_real (alpm_handle, module_pkg);
									}
								}
							}
						} else if (splitted.length == 1) {
							// we are adding a kernel
							// add all installed modules for other kernels
							for (uint i = 0; i < installed_modules.length; i++) {
								var module = new StringBuilder ();
								module.append (splitted[0]);
								module.append ("-");
								module.append (installed_modules[i]);
								unowned Alpm.Package? module_pkg = get_syncpkg (alpm_handle, module.str);
								if (module_pkg != null) {
									trans_add_pkg_real (alpm_handle, module_pkg);
								}
							}
						}
					}
				}
				return success;
			}
		}

		public string download_pkg (string sender, string url) {
			this.sender = sender;
			var alpm_handle = get_handle ();
			if (alpm_handle == null) {
				return "";
			}
			return download_pkg_priv (alpm_handle, url) ?? "";
		}

		string? download_pkg_priv (Alpm.Handle alpm_handle, string url) {
			// need to call the function twice in order to have the return path
			// it's due to the use of a fetch callback
			// first call to download pkg
			do_start_downloading ();
			alpm_handle.fetch_pkgurl (url);
			// check for error
			if (alpm_handle.errno () != 0) {
				return null;
			}
			if ((alpm_handle.remotefilesiglevel & Alpm.Signature.Level.PACKAGE) == 1) {
				// try to download signature
				alpm_handle.fetch_pkgurl (url + ".sig");
			}
			do_stop_downloading ();
			return alpm_handle.fetch_pkgurl (url);
		}

		bool trans_load_pkg (Alpm.Handle alpm_handle, string path) {
			Alpm.Package* pkg;
			int siglevel = alpm_handle.localfilesiglevel;
			string? pkgpath = path;
			// download pkg if an url is given
			if ("://" in path) {
				siglevel = alpm_handle.remotefilesiglevel;
				pkgpath = download_pkg_priv (alpm_handle, path);
				if (pkgpath == null) {
					return false;
				}
			}
			// load tarball
			if (alpm_handle.load_tarball (pkgpath, 1, siglevel, out pkg) == -1) {
				Alpm.Errno errno = alpm_handle.errno ();
				if (errno != 0) {
					do_emit_error (_("Failed to prepare transaction"), {Alpm.strerror (errno)});
				} else {
					do_emit_error (_("Failed to prepare transaction"), {});
				}
				return false;
			} else if (alpm_handle.trans_add_pkg (pkg) == -1) {
				Alpm.Errno errno = alpm_handle.errno ();
				if (errno == Alpm.Errno.TRANS_DUP_TARGET || errno == Alpm.Errno.PKG_IGNORED) {
					// just skip duplicate or ignored targets
					return true;
				} else {
					if (errno != 0) {
						do_emit_error (_("Failed to prepare transaction"), {"%s: %s".printf (pkg->name, Alpm.strerror (errno))});
					} else {
						do_emit_error (_("Failed to prepare transaction"), {});
					}
					// free the package because it will not be used
					delete pkg;
					return false;
				}
			}
			return true;
		}

		bool trans_remove_pkg (Alpm.Handle alpm_handle, string pkgname) {
			bool success = true;
			unowned Alpm.Package? pkg =  alpm_handle.localdb.get_pkg (pkgname);
			if (pkg == null) {
				do_emit_error (_("Failed to prepare transaction"), {_("target not found: %s").printf (pkgname)});
				success = false;
			} else if (alpm_handle.trans_remove_pkg (pkg) == -1) {
				Alpm.Errno errno = alpm_handle.errno ();
				// just skip duplicate targets
				if (errno != Alpm.Errno.TRANS_DUP_TARGET) {
					if (errno != 0) {
						do_emit_error (_("Failed to prepare transaction"), {"%s: %s".printf (pkg.name, Alpm.strerror (errno))});
					} else {
						do_emit_error (_("Failed to prepare transaction"), {});
					}
					success = false;
				}
			}
			if (success) {
				if ((trans_flags & Alpm.TransFlag.RECURSE) != 0) {
					// also remove uneedded optdepends
					unowned Alpm.List<unowned Alpm.Depend> optdepends = pkg.optdepends;
					while (optdepends != null) {
						unowned Alpm.Depend optdep = optdepends.data;
						unowned Alpm.Package opt_pkg = Alpm.find_satisfier (alpm_handle.localdb.pkgcache, optdep.name);
						if (opt_pkg != null) {
							if (opt_pkg.reason == Alpm.Package.Reason.DEPEND) {
								Alpm.List<string> requiredby = opt_pkg.compute_requiredby ();
								if (requiredby.length == 0) {
									Alpm.List<string> optionalfor = opt_pkg.compute_optionalfor ();
									// opt_pkg is at least optional for pkg
									if (optionalfor.length == 1) {
										success = trans_remove_pkg (alpm_handle, opt_pkg.name);
									}
									optionalfor.free_inner (GLib.free);
								} else {
									requiredby.free_inner (GLib.free);
								}
							}
						}
						if (!success) {
							break;
						}
						optdepends.next ();
					}
				}
			}
			return success;
		}

		bool trans_prepare_real (Alpm.Handle alpm_handle) {
			bool success = true;
			Alpm.List err_data;
			if (alpm_handle.trans_prepare (out err_data) == -1) {
				string[] details = {};
				Alpm.Errno errno = alpm_handle.errno ();
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
							if (miss->causingpkg == null) {
								/* package being installed/upgraded has unresolved dependency */
								details += _("unable to satisfy dependency '%s' required by %s").printf (depstring, miss->target);
							} else if ((pkg = Alpm.pkg_find (trans_add, miss->causingpkg)) != null) {
								/* upgrading a package breaks a local dependency */
								details += _("installing %s (%s) breaks dependency '%s' required by %s").printf (miss->causingpkg, pkg.version, depstring, miss->target);
							} else {
								/* removing a package breaks a local dependency */
								details += _("removing %s breaks dependency '%s' required by %s").printf (miss->causingpkg, depstring, miss->target);
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
				do_emit_error (_("Failed to prepare transaction"), details);
				trans_release (alpm_handle);
				success = false;
			} else {
				string[] details = {};
				// Search for holdpkg in target list
				bool found_locked_pkg = false;
				unowned Alpm.List<unowned Alpm.Package> to_remove = alpm_handle.trans_to_remove ();
				while (to_remove != null) {
					unowned Alpm.Package pkg = to_remove.data;
					if (pkg.name in alpm_config.holdpkgs) {
						details += _("%s needs to be removed but it is a locked package").printf (pkg.name);
						found_locked_pkg = true;
					}
					to_remove.next ();
				}
				if (found_locked_pkg) {
					do_emit_error (_("Failed to prepare transaction"), details);
					trans_release (alpm_handle);
					success = false;
				}
			}
			if (cancellable.is_cancelled ()) {
				trans_release (alpm_handle);
				return false;
			}
			return success;
		}

		public bool trans_check_prepare (bool sysupgrade,
										bool enable_downgrade,
										bool simple_install,
										bool check_aur_updates,
										int trans_flags,
										GenericSet<string?> to_install,
										GenericSet<string?> to_remove,
										GenericSet<string?> to_load,
										GenericSet<string?> to_build,
										GenericSet<string?> temporary_ignorepkgs,
										GenericSet<string?> overwrite_files,
										out TransactionSummary summary) {
			this.sender = "";
			this.sysupgrade = sysupgrade;
			this.enable_downgrade = enable_downgrade;
			this.simple_install = simple_install;
			this.check_aur_updates = check_aur_updates;
			this.trans_flags = trans_flags;
			foreach (unowned string name in to_install) {
				this.to_install.add (name);
			}
			foreach (unowned string name in to_remove) {
				this.to_remove.add (name);
			}
			foreach (unowned string name in to_load) {
				this.to_load.add (name);
			}
			foreach (unowned string name in to_build) {
				this.to_build.add (name);
			}
			foreach (unowned string name in temporary_ignorepkgs) {
				this.temporary_ignorepkgs.add (name);
			}
			foreach (unowned string name in overwrite_files) {
				this.overwrite_files.add (name);
			}
			summary = new TransactionSummary ();
			bool success;
			if (to_build.length > 0 || check_aur_updates) {
				success = build_prepare (ref summary);
			} else {
				var alpm_handle = get_handle ();
				if (alpm_handle == null) {
					return false;
				}
				success = trans_prepare (alpm_handle);
				if (success) {
					summary = get_transaction_summary (alpm_handle);
					trans_release (alpm_handle);
				}
			}
			trans_reset ();
			return success;
		}

		public bool trans_run (string sender,
								bool sysupgrade,
								bool enable_downgrade,
								bool simple_install,
								bool keep_built_pkgs,
								int trans_flags,
								string[] to_install,
								string[] to_remove,
								string[] to_load,
								string[] to_install_as_dep,
								string[] temporary_ignorepkgs,
								string[] overwrite_files) {
			this.sender = sender;
			this.sysupgrade = sysupgrade;
			this.enable_downgrade = enable_downgrade;
			this.simple_install = simple_install;
			this.no_confirm_commit = true;
			this.keep_built_pkgs = keep_built_pkgs;
			this.trans_flags = trans_flags;
			foreach (unowned string name in to_install) {
				this.to_install.add (name);
			}
			foreach (unowned string name in to_remove) {
				this.to_remove.add (name);
			}
			foreach (unowned string name in to_load) {
				this.to_load.add (name);
			}
			foreach (unowned string name in to_install_as_dep) {
				this.to_install_as_dep.insert (name, name);
			}
			foreach (unowned string name in temporary_ignorepkgs) {
				this.temporary_ignorepkgs.add (name);
			}
			foreach (unowned string name in overwrite_files) {
				this.overwrite_files.add (name);
			}
			// use an handle with no callback to avoid double prepare signals
			var alpm_handle = get_handle (false, false, false);
			if (alpm_handle == null) {
				return false;
			}
			// add question callback for replaces/conflicts/corrupted pkgs and import keys
			alpm_handle.questioncb = (Alpm.QuestionCallBack) cb_question;
			bool success = trans_prepare (alpm_handle);
			if (success) {
				if (alpm_handle.trans_to_add ().length > 0 ||
					alpm_handle.trans_to_remove ().length > 0) {
					if (do_get_authorization ()) {
						// add callbacks to have commit signals
						alpm_handle.eventcb = (Alpm.EventCallBack) cb_event;
						alpm_handle.progresscb = (Alpm.ProgressCallBack) cb_progress;
						alpm_handle.fetchcb = (Alpm.FetchCallBack) cb_fetch;
						alpm_handle.totaldlcb = (Alpm.TotalDownloadCallBack) cb_totaldownload;
						alpm_handle.logcb = (Alpm.LogCallBack) cb_log;
						success = trans_commit (alpm_handle);
					} else {
						trans_release (alpm_handle);
						success = false;
					}
				} else {
					do_emit_action (dgettext (null, "Nothing to do") + ".");
					trans_release (alpm_handle);
					success = true;
				}
			}
			trans_reset ();
			return success;
		}

		void trans_reset () {
			total_download = 0;
			already_downloaded = 0;
			current_filename = "";
			to_install.remove_all ();
			to_remove.remove_all ();
			to_load.remove_all ();
			to_build.remove_all ();
			temporary_ignorepkgs.remove_all ();
			overwrite_files.remove_all ();
			to_install_as_dep.remove_all ();
			no_confirm_commit = false;
		}

		bool trans_prepare (Alpm.Handle alpm_handle) {
			bool success = trans_init (alpm_handle, trans_flags);
			if (success && sysupgrade) {
				success = trans_sysupgrade (alpm_handle);
			}
			if (success) {
				foreach (unowned string name in to_install) {
					success = trans_add_pkg (alpm_handle, name);
					if (!success) {
						break;
					}
				}
			}
			if (success) {
				foreach (unowned string name in to_remove) {
					success = trans_remove_pkg (alpm_handle, name);
					if (!success) {
						break;
					}
				}
			}
			if (success) {
				foreach (unowned string path in to_load) {
					success = trans_load_pkg (alpm_handle, path);
					if (!success) {
						break;
					}
				}
			}
			if (success) {
				success = trans_prepare_real (alpm_handle);
			} else {
				trans_release (alpm_handle);
			}
			return success;
		}

		bool build_prepare (ref TransactionSummary summary) {
			// get an handle with fake aur db and without emit signal callbacks
			var tmp_handle = get_handle (false, true);
			if (tmp_handle == null) {
				return false;
			} else {
				// fake aur db
				try {
					Process.spawn_command_line_sync ("cp %s/pamac_aur.db %ssync".printf (tmp_path, tmp_handle.dbpath));
				} catch (SpawnError e) {
					do_emit_warning (e.message);
				}
				unowned Alpm.DB? aur_db = tmp_handle.register_syncdb ("pamac_aur", 0);
				if (aur_db == null) {
					do_emit_error (_("Failed to initialize alpm library"), {});
					return false;
				}
				// check if we need to remove debug package to avoid dep problem
				foreach (unowned string name in to_build) {
					string debug_pkg_name = "%s-debug".printf (name);
					if (tmp_handle.localdb.get_pkg (debug_pkg_name) != null) {
						to_remove.add (debug_pkg_name);
					}
				}
				// base-devel group is needed to build pkgs
				unowned Alpm.List<unowned Alpm.DB> syncdbs = tmp_handle.syncdbs;
				while (syncdbs != null) {
					unowned Alpm.DB db = syncdbs.data;
					// base-devel group is in core
					if (db.name == "core") {
						unowned Alpm.Group? grp = db.get_group ("base-devel");
						if (grp != null) {
							unowned Alpm.List<unowned Alpm.Package> packages = grp.packages;
							while (packages != null) {
								unowned Alpm.Package pkg = packages.data;
								if (Alpm.find_satisfier (tmp_handle.localdb.pkgcache, pkg.name) == null) {
									to_install.add (pkg.name);
								} else {
									// remove the needed pkg from to_remove
									to_remove.remove (pkg.name);
								}
								packages.next ();
							}
						}
						break;
					}
					syncdbs.next ();
				}
				// fake trans prepare
				bool success = true;
				if (tmp_handle.trans_init (trans_flags | Alpm.TransFlag.NOLOCK) == -1) {
					Alpm.Errno errno = tmp_handle.errno ();
					if (errno != 0) {
						do_emit_error (_("Failed to init transaction"), {Alpm.strerror (errno)});
					} else {
						do_emit_error (_("Failed to init transaction"), {});
					}
					success = false;
				}
				if (success && sysupgrade) {
					success = trans_sysupgrade (tmp_handle);
					if (!success) {
						trans_release (tmp_handle);
					}
				}
				if (success) {
					foreach (unowned string name in to_install) {
						success = trans_add_pkg (tmp_handle, name);
						if (!success) {
							break;
						}
					}
					if (success) {
						foreach (unowned string name in to_remove) {
							success = trans_remove_pkg (tmp_handle, name);
							if (!success) {
								break;
							}
						}
					}
					if (success) {
						// add to_build from fake aur db
						foreach (unowned string name in to_build) {
							unowned Alpm.Package? pkg = aur_db.get_pkg (name);
							if (pkg == null) {
								do_emit_error (_("Failed to prepare transaction"), {_("target not found: %s").printf (name)});
								success = false;
								break;
							} else {
								success = trans_add_pkg_real (tmp_handle, pkg);
								if (!success) {
									break;
								}
							}
						}
					}
					if (success) {
						foreach (unowned string path in to_load) {
							success = trans_load_pkg (tmp_handle, path);
							if (!success) {
								break;
							}
						}
					}
					if (success) {
						success = trans_prepare_real (tmp_handle);
						if (success) {
							summary = get_transaction_summary (tmp_handle);
						}
					}
					trans_release (tmp_handle);
				}
				try {
					Process.spawn_command_line_sync ("rm -f %ssync/aur.db".printf (tmp_handle.dbpath));
				} catch (SpawnError e) {
					warning (e.message);
				}
				return success;
			}
		}

		TransactionSummary get_transaction_summary (Alpm.Handle alpm_handle) {
			var summary = new TransactionSummary ();
			unowned Alpm.List<unowned Alpm.Package> pkgs_to_add = alpm_handle.trans_to_add ();
			while (pkgs_to_add != null) {
				unowned Alpm.Package trans_pkg = pkgs_to_add.data;
				unowned Alpm.DB? db = trans_pkg.db;
				if (db != null && db.name == "pamac_aur") {
					// it is a aur pkg to build
					if (!summary.aur_pkgbases_to_build_priv.find_with_equal_func (trans_pkg.pkgbase, str_equal)) {
						summary.aur_pkgbases_to_build_priv.add (trans_pkg.pkgbase);
					}
					summary.to_build_priv.prepend (initialise_pkg (alpm_handle, trans_pkg));
				} else {
					var pkg = initialise_pkg (alpm_handle, trans_pkg);
					if (pkg.installed_version == "") {
						summary.to_install_priv.prepend (pkg);
					} else {
						int cmp = Alpm.pkg_vercmp (pkg.version, pkg.installed_version);
						if (cmp == 1) {
							summary.to_upgrade_priv.prepend (pkg);
						} else if (cmp == 0) {
							summary.to_reinstall_priv.prepend (pkg);
						} else {
							summary.to_downgrade_priv.prepend (pkg);
						}
					}
				}
				pkgs_to_add.next ();
			}
			unowned Alpm.List<unowned Alpm.Package> pkgs_to_remove = alpm_handle.trans_to_remove ();
			while (pkgs_to_remove != null) {
				unowned Alpm.Package trans_pkg = pkgs_to_remove.data;
				summary.to_remove_priv.prepend (initialise_pkg (alpm_handle, trans_pkg));
				pkgs_to_remove.next ();
			}
			summary.sort ();
			return summary;
		}

		public bool compute_multi_download_progress () {
			// this will be run in this.context
			if (alpm_utils.cancellable.is_cancelled ()) {
				return true;
			}
			multi_progress_mutex.lock ();
			uint64 total_progress = 0;
			multi_progress.foreach ((filename, progress) => {
				total_progress += progress;
			});
			if (total_progress > 0) {
				emit_download (total_progress, total_download);
			}
			multi_progress_mutex.unlock ();
			return true;
		}

		void download_files (Alpm.Handle handle, uint64 max_parallel_downloads) {
			multi_progress = new HashTable<string, uint64?> (str_hash, str_equal);
			// create the table of async queues
			// one queue per repo
			queues_table = new HashTable<string, AsyncQueue<string>> (str_hash, str_equal);
			// get files to download
			total_download = 0;
			unowned Alpm.List<unowned Alpm.Package> pkgs_to_add = handle.trans_to_add ();
			while (pkgs_to_add != null) {
				unowned Alpm.Package trans_pkg = pkgs_to_add.data;
				uint64 download_size = trans_pkg.download_size;
				if (download_size > 0) {
					total_download += trans_pkg.download_size;
					if (trans_pkg.db != null) {
						if (queues_table.contains (trans_pkg.db.name)) {
							unowned AsyncQueue<string> queue = queues_table.lookup (trans_pkg.db.name);
							queue.push (trans_pkg.filename);
						} else {
							var queue = new AsyncQueue<string> ();
							queue.push (trans_pkg.filename);
							queues_table.insert (trans_pkg.db.name, queue);
						}
					}
				}
				pkgs_to_add.next ();
			}
			// compute the dbs available for each mirror
			var mirrors_table = new HashTable<string, GenericSet<string>> (str_hash, str_equal);
			unowned Alpm.List<unowned Alpm.DB> syncdbs = handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				unowned Alpm.List<unowned string> servers = db.servers;
				while (servers != null) {
					unowned string server_full = servers.data;
					string server = server_full.replace (db.name, "$repo");
					if (mirrors_table.contains (server)) {
						unowned GenericSet<string> repos_set = mirrors_table.lookup (server);
						repos_set.add (db.name);
					} else {
						var repos_set = new GenericSet<string> (str_hash, str_equal);
						repos_set.add (db.name);
						mirrors_table.insert (server, repos_set);
					}
					servers.next ();
				}
				syncdbs.next ();
			}
			emit_totaldownload (total_download);
			emit_event (Alpm.Event.Type.RETRIEVE_START, 0, {});
			current_filename = "";
			// use to track downloads progress
			var timeout = new TimeoutSource (500);
			timeout.set_callback (compute_multi_download_progress);
			uint timeout_id = timeout.attach (context);
			// create a thread pool which will download files
			// there will be two threads per mirror
			try {
				var dload_thread_pool = new ThreadPool<DownloadServer>.with_owned_data (
					// call alpm_action.run () on thread start
					(download_server) => {
						download_server.download_files ();
					},
					// max simultaneous threads = max simultaneous downloads
					(int) max_parallel_downloads,
					// exclusive threads
					true
				);
				mirrors_table.foreach_steal ((mirror, repo_set) => {
					try {
						// two connections per mirror
						dload_thread_pool.add (new DownloadServer (handle, mirror, repo_set));
						dload_thread_pool.add (new DownloadServer (handle, mirror, repo_set));
					} catch (ThreadError e) {
						warning (e.message);
					}
					return true;
				});
				// wait for all thread to finish
				ThreadPool.free ((owned) dload_thread_pool, false, true);
			} catch (ThreadError e) {
				warning (e.message);
			}
			// stop compute_multi_download_progress
			Source.remove (timeout_id);
			emit_event (Alpm.Event.Type.RETRIEVE_DONE, 0, {});
			emit_totaldownload (0);
		}

		bool trans_commit (Alpm.Handle alpm_handle) {
			add_overwrite_files (alpm_handle);
			bool success = false;
			if (to_syncfirst.length > 0) {
				trans_release (alpm_handle);
				success = trans_init (alpm_handle, trans_flags);
				if (success) {
					foreach (unowned string name in to_syncfirst) {
						success = trans_add_pkg (alpm_handle, name);
						if (!success) {
							break;
						}
					}
					if (success) {
						success = trans_prepare_real (alpm_handle);
					}
					if (success) {
						success = trans_commit_real (alpm_handle);
					}
					trans_release (alpm_handle);
					if (success) {
						// remove syncfirsts from to_install
						foreach (unowned string name in to_syncfirst) {
							to_install.remove (name);
						}
						success = trans_init (alpm_handle, trans_flags);
						if (success && sysupgrade) {
							success = trans_sysupgrade (alpm_handle);
						}
						if (success) {
							foreach (unowned string name in to_install) {
								success = trans_add_pkg (alpm_handle, name);
								if (!success) {
									break;
								}
							}
						}
						if (success) {
							foreach (unowned string name in to_remove) {
								success = trans_remove_pkg (alpm_handle, name);
								if (!success) {
									break;
								}
							}
						}
						if (success) {
							foreach (unowned string path in to_load) {
								success = trans_load_pkg (alpm_handle, path);
								if (!success) {
									break;
								}
							}
						}
						if (success) {
							success = trans_prepare_real (alpm_handle);
							// continue if needed
							if (success && (alpm_handle.trans_to_add ().length + alpm_handle.trans_to_remove ().length) == 0) {
								trans_release (alpm_handle);
								return true;
							}
						}
						if (!success) {
							trans_release (alpm_handle);
						}
					}
				}
				if (!success) {
					return false;
				}
			}
			success = trans_commit_real (alpm_handle);
			if (success) {
				foreach (unowned string path in to_load) {
					// check tarball if it's a built package
					// check for "/var/tmp/pamac-build" because
					// default aur_build_dir is "/var/tmp/pamac-build-root" here
					// if a custom PKGDEST is set in makepkg.conf, package won't be moved or deleted
					if (path.has_prefix ("/var/tmp/pamac-build") || path.has_prefix (config.aur_build_dir)) {
						if (keep_built_pkgs) {
							// get first cachedir
							unowned Alpm.List<unowned string> cachedirs = alpm_handle.cachedirs;
							unowned string cachedir = cachedirs.data;
							try {
								Process.spawn_command_line_sync ("mv -f %s %s".printf (path, cachedir));
							} catch (SpawnError e) {
								warning (e.message);
							}
						} else {
							// rm built package
							try {
								Process.spawn_command_line_sync ("rm -f %s".printf (path));
							} catch (SpawnError e) {
								warning (e.message);
							}
						}
					}
				}
				to_install_as_dep.foreach_remove ((pkgname, val) => {
					unowned Alpm.Package? pkg = alpm_handle.localdb.get_pkg (pkgname);
					if (pkg != null) {
						pkg.reason = Alpm.Package.Reason.DEPEND;
						return true; // remove current pkgname
					}
					return false;
				});
			}
			return success;
		}

		bool trans_commit_real (Alpm.Handle alpm_handle) {
			bool success = true;
			if (config.max_parallel_downloads >= 2) {
				// custom parallel downloads
				download_files (alpm_handle, config.max_parallel_downloads);
				if (cancellable.is_cancelled ()) {
					trans_release (alpm_handle);
					return false;
				}
			}
			// real commit
			Alpm.List err_data;
			if (alpm_handle.trans_commit (out err_data) == -1) {
				Alpm.Errno errno = alpm_handle.errno ();
				// cancel the download return an EXTERNAL_DOWNLOAD error
				if (errno == Alpm.Errno.EXTERNAL_DOWNLOAD && cancellable.is_cancelled ()) {
					trans_release (alpm_handle);
					return false;
				}
				string[] details = {};
				switch (errno) {
					case 0:
						break;
					case Alpm.Errno.FILE_CONFLICTS:
						details += Alpm.strerror (errno) + ":";
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
						break;
					case Alpm.Errno.PKG_INVALID:
					case Alpm.Errno.PKG_INVALID_CHECKSUM:
					case Alpm.Errno.PKG_INVALID_SIG:
						details += Alpm.strerror (errno) + ":";
						unowned Alpm.List<string*> list = err_data;
						while (list != null) {
							string* filename = list.data;
							details += _("%s is invalid or corrupted").printf (filename);
							delete filename;
							list.next ();
						}
						break;
					case Alpm.Errno.EXTERNAL_DOWNLOAD:
						details += _("failed to retrieve some files");
						break;
					default:
						details += Alpm.strerror (errno);
						break;
				}
				do_emit_error (_("Failed to commit transaction"), details);
				success = false;
			}
			trans_release (alpm_handle);
			return success;
		}

		void trans_release (Alpm.Handle alpm_handle) {
			alpm_handle.trans_release ();
			remove_ignorepkgs (alpm_handle);
			remove_overwrite_files (alpm_handle);
		}

		public void trans_cancel (string sender) {
			if (sender != this.sender) {
				return;
			}
			//if (alpm_handle.trans_interrupt () == 0) {
				// a transaction is being interrupted
				// it will end the normal way
				//return;
			//}
			cancellable.cancel ();
			trans_reset ();
		}

		string remove_bash_colors (string msg) {
			Regex regex = /\x1B\[[0-9;]*[JKmsu]/;
			try {
				return regex.replace (msg, -1, 0, "");
			} catch (Error e) {
				return msg;
			}
		}

		public void emit_event (uint primary_event, uint secondary_event, string[] details) {
			switch (primary_event) {
				case 1: //Alpm.Event.Type.CHECKDEPS_START
					do_emit_action (dgettext (null, "Checking dependencies") + "...");
					break;
				case 3: //Alpm.Event.Type.FILECONFLICTS_START
					current_action = dgettext (null, "Checking file conflicts") + "...";
					break;
				case 5: //Alpm.Event.Type.RESOLVEDEPS_START
					do_emit_action (dgettext (null, "Resolving dependencies") + "...");
					break;
				case 7: //Alpm.Event.Type.INTERCONFLICTS_START
					do_emit_action (dgettext (null, "Checking inter-conflicts") + "...");
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
				case 17: //Alpm.Event.Type.SCRIPTLET_INFO
					// hooks output are also emitted as SCRIPTLET_INFO
					if (current_filename != "") {
						do_emit_action (dgettext (null, "Configuring %s").printf (current_filename) + "...");
						current_filename = "";
					}
					string msg = remove_bash_colors (details[0]).replace ("\n", "");
					do_emit_script_output (msg);
					if ("error" in msg.down ()) {
						do_emit_warning (dgettext (null, "Error while configuring %s").printf (current_filename));
						do_important_details_outpout (true);
					} else {
						do_important_details_outpout (false);
					}
					break;
				case 18: //Alpm.Event.Type.RETRIEVE_START
					do_start_downloading ();
					break;
				case 19: //Alpm.Event.Type.RETRIEVE_DONE
				case 20: //Alpm.Event.Type.RETRIEVE_FAILED
					do_stop_downloading ();
					break;
				case 24: //Alpm.Event.Type.DISKSPACE_START
					current_action = dgettext (null, "Checking available disk space") + "...";
					break;
				case 26: //Alpm.Event.Type.OPTDEP_REMOVAL
					do_emit_warning ("%s: %s".printf (dgettext (null, "Warning"), dgettext (null, "%s optionally requires %s").printf (details[0], details[1])));
					break;
				case 27: //Alpm.Event.Type.DATABASE_MISSING
					do_emit_script_output (dgettext (null, "Database file for %s does not exist").printf (details[0]) + ".");
					break;
				case 28: //Alpm.Event.Type.KEYRING_START
					current_action = dgettext (null, "Checking keyring") + "...";
					break;
				case 30: //Alpm.Event.Type.KEY_DOWNLOAD_START
					do_emit_action (dgettext (null, "Downloading required keys") + "...");
					break;
				case 32: //Alpm.Event.Type.PACNEW_CREATED
					do_emit_script_output (dgettext (null, "%s installed as %s.pacnew").printf (details[0], details[0])+ ".");
					break;
				case 33: //Alpm.Event.Type.PACSAVE_CREATED
					do_emit_script_output (dgettext (null, "%s installed as %s.pacsave").printf (details[0], details[0])+ ".");
					break;
				case 34: //Alpm.Event.Type.HOOK_START
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
				case 36: // Alpm.Event.Type.HOOK_RUN_START
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
							do_emit_hook_progress (current_action, details[1], current_status, current_progress);
							if ("error" in details[1].down ()) {
								do_emit_warning (dgettext (null, "Error while running hooks"));
								do_important_details_outpout (true);
							}
						} else {
							do_emit_hook_progress (current_action, details[0], current_status, current_progress);
							if ("error" in details[0].down ()) {
								do_emit_warning (dgettext (null, "Error while running hooks"));
								do_important_details_outpout (true);
							}
						}
					}
					break;
				default:
					break;
			}
		}

		public void emit_progress (uint progress, string pkgname, uint percent, uint n_targets, uint current_target) {
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
					do_emit_action_progress (current_action, current_status, current_progress);
				}
			}
		}

		public void emit_download_in_context (uint64 xfered, uint64 total, bool force_emit) {
			context.invoke (() => {
				emit_download (xfered, total, force_emit);
				return false;
			});
		}

		public void emit_download (uint64 xfered, uint64 total, bool force_emit = false) {
			var text = new StringBuilder ("");
			double fraction;
			if (total_download > 0) {
				if (force_emit || timer.elapsed () > 0.5) {
					download_rate = ((download_rate * rates_nb) + (uint64) ((xfered - previous_xfered) / timer.elapsed ())) / (rates_nb + 1);
					rates_nb++;
				} else if (xfered != 0 && xfered != total) {
					return;
				}
				if (already_downloaded < total) {
					already_downloaded += xfered - previous_xfered;
				}
				if (xfered == total) {
					previous_xfered = 0;
				} else {
					previous_xfered = xfered;
				}
				fraction = (double) already_downloaded / total_download;
				if (fraction <= 1) {
					text.append ("%s/%s  ".printf (format_size (already_downloaded), format_size (total_download)));
					uint64 remaining_seconds = 0;
					if (download_rate > 0) {
						remaining_seconds = (total_download - already_downloaded) / download_rate;
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
					text.append (format_size (already_downloaded));
				}
				timer.start ();
			} else {
				if (xfered == 0) {
					previous_xfered = 0;
					download_rate = 0;
					rates_nb = 0;
					fraction = 0;
					timer.start ();
				} else if (xfered == total) {
					timer.stop ();
					fraction = 1;
				} else {
					if (timer.elapsed () > 0.5) {
						download_rate = ((download_rate * rates_nb) + (uint64) ((xfered - previous_xfered) / timer.elapsed ())) / (rates_nb + 1);
						rates_nb++;
					} else {
						return;
					}
					previous_xfered = xfered;
					fraction = (double) xfered / total;
					if (fraction <= 1) {
						text.append ("%s/%s".printf (format_size (xfered), format_size (total)));
						uint64 remaining_seconds = 0;
						if (download_rate > 0) {
							remaining_seconds = (total - xfered) / download_rate;
						}
						// display remaining time after 5s and only if more than 10s are remaining
						if (remaining_seconds > 9 && rates_nb > 9) {
							text.append ("  ");
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
			do_emit_download_progress (current_action, current_status, current_progress);
		}

		public void emit_totaldownload (uint64 total) {
			//  this is emitted at the end of the total download 
			// with the value 0 so stop our timer
			if (total == 0) {
				timer.stop ();
				current_filename = "";
				do_emit_download_progress (current_action, current_status, 1);
			}
			download_rate = 0;
			rates_nb = 0;
			current_progress = 0;
			previous_xfered = 0;
			current_status = "";
			total_download = total;
		}

		public void emit_log (uint level, string msg) {
			// msg ends with \n
			string? line = null;
			if (level == 1) { //Alpm.LogLevel.ERROR
				if (current_filename != "") {
					line = dgettext (null, "Error") + ": " + current_filename + ": " + msg;
				} else {
					line = dgettext (null, "Error") + ": " + msg;
				}
				do_important_details_outpout (false);
				do_emit_warning (line.replace ("\n", ""));
			} else if (level == (1 << 1)) { //Alpm.LogLevel.WARNING
				// warnings when no_confirm_commit should already have been sent
				if (alpm_utils.no_confirm_commit) {
					return;
				}
				// do not show warning when manjaro-system remove db.lck
				if (current_filename != "manjaro-system") {
					if (current_filename != "") {
						line = dgettext (null, "Warning") + ": " + current_filename + ": " + msg;
					} else {
						line = dgettext (null, "Warning") + ": " + msg;
					}
					do_emit_script_output (line.replace ("\n", ""));
				}
			}
		}
	}
}

void write_log_file (string event) {
	var now = new DateTime.now_local ();
	string log = "%s [PAMAC] %s\n".printf (now.format ("[%Y-%m-%dT%H:%M:%S%z]"), event);
	var file = GLib.File.new_for_path ("/var/log/pacman.log");
	try {
		// creating a DataOutputStream to the file
		var dos = new DataOutputStream (file.append_to (FileCreateFlags.NONE));
		// writing a short string to the stream
		dos.put_string (log);
	} catch (Error e) {
		warning (e.message);
	}
}

void cb_event (Alpm.Event.Data data) {
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
		case Alpm.Event.Type.SCRIPTLET_INFO:
			details += data.scriptlet_info_line;
			break;
		case Alpm.Event.Type.PKGDOWNLOAD_START:
			// do not emit event when download is cancelled
			if (alpm_utils.cancellable.is_cancelled ()) {
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
	alpm_utils.emit_event ((uint) data.type, secondary_type, details);
}

void cb_question (Alpm.Question.Data data) {
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
			unresolvables = new GenericArray<string> ();
			unowned Alpm.List<unowned Alpm.Package> list = data.remove_pkgs_packages;
			while (list != null) {
				unowned Alpm.Package pkg = list.data;
				unresolvables.add (pkg.name);
				list.next ();
			}
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
			data.select_provider_use_index = alpm_utils.do_choose_provider (depend_str, providers_str);
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

void cb_progress (Alpm.Progress progress, string pkgname, int percent, uint n_targets, uint current_target) {
	if (percent == 0) {
		alpm_utils.emit_progress ((uint) progress, pkgname, (uint) percent, n_targets, current_target);
		alpm_utils.timer.start ();
	} else if (percent == 100) {
		alpm_utils.emit_progress ((uint) progress, pkgname, (uint) percent, n_targets, current_target);
		alpm_utils.timer.stop ();
	} else if (alpm_utils.timer.elapsed () < 0.5) {
		return;
	} else {
		alpm_utils.emit_progress ((uint) progress, pkgname, (uint) percent, n_targets, current_target);
		alpm_utils.timer.start ();
	}
}

delegate void DownloadCallback (string filename, uint64 xfered, uint64 total);

void cb_multi_download (string filename, uint64 xfered, uint64 total) {
	// this will be run in the threadpool
	if (xfered == 0) {
		string? name_version_release = filename.slice (0, filename.last_index_of_char ('-'));
		if (name_version_release == null) {
			return;
		}
		string? name_version = name_version_release.slice (0, name_version_release.last_index_of_char ('-'));
		if (name_version == null) {
			return;
		}
		int version_index = name_version.last_index_of_char ('-');
		string? name = name_version.slice (0, version_index);
		if (name == null) {
			return;
		}
		string? version_release = name_version_release.slice (version_index + 1, name_version_release.length);
		if (version_release == null) {
			return;
		}
		multi_progress_mutex.lock ();
		current_action = _("Download of %s started").printf ("%s (%s)".printf (name, version_release));
		uint64 total_progress = 0;
		multi_progress.foreach ((filename, progress) => {
			total_progress += progress;
		});
		alpm_utils.emit_download_in_context (total_progress, total_download, true);
		multi_progress_mutex.unlock ();
	} else if (xfered == total) {
		string? name_version_release = filename.slice (0, filename.last_index_of_char ('-'));
		if (name_version_release == null) {
			return;
		}
		string? name_version = name_version_release.slice (0, name_version_release.last_index_of_char ('-'));
		if (name_version == null) {
			return;
		}
		int version_index = name_version.last_index_of_char ('-');
		string? name = name_version.slice (0, version_index);
		if (name == null) {
			return;
		}
		string? version_release = name_version_release.slice (version_index + 1, name_version_release.length);
		if (version_release == null) {
			return;
		}
		multi_progress_mutex.lock ();
		current_action = _("Download of %s finished").printf ("%s (%s)".printf (name, version_release));
		uint64 total_progress = 0;
		multi_progress.insert (filename, xfered);
		multi_progress.foreach ((filename, progress) => {
			total_progress += progress;
		});
		alpm_utils.emit_download_in_context (total_progress, total_download, true);
		multi_progress_mutex.unlock ();
	} else {
		multi_progress_mutex.lock ();
		multi_progress.insert (filename, xfered);
		multi_progress_mutex.unlock ();
	}
}

void cb_download (string filename, uint64 xfered, uint64 total) {
	if (xfered == 0) {
		if (filename.has_suffix (".db") || filename.has_suffix (".files")) {
			current_action = _("Refreshing %s").printf (filename) + "...";
		} else {
			string? name_version_release = filename.slice (0, filename.last_index_of_char ('-'));
			if (name_version_release == null) {
				return;
			}
			string? name_version = name_version_release.slice (0, name_version_release.last_index_of_char ('-'));
			if (name_version == null) {
				return;
			}
			int version_index = name_version.last_index_of_char ('-');
			string? name = name_version.slice (0, version_index);
			if (name == null) {
				return;
			}
			string? version_release = name_version_release.slice (version_index + 1, name_version_release.length);
			if (version_release == null) {
				return;
			}
			current_action = _("Downloading %s").printf ("%s (%s)".printf (name, version_release)) + "...";
		}
	}
	alpm_utils.emit_download (xfered, total);
}

int cb_fetch (string fileurl, string localpath, int force) {
	current_filename = Path.get_basename (fileurl);
	return dload (alpm_utils.soup_session, fileurl, localpath, force, cb_download);
}

int dload (Soup.Session soup_session, string url, string localpath, int force, DownloadCallback dl_callback) {
	if (alpm_utils.cancellable.is_cancelled ()) {
		return -1;
	}

	string filename =  Path.get_basename (url);
	var destfile = GLib.File.new_for_path (localpath + filename); 
	var tempfile = GLib.File.new_for_path (destfile.get_path () + ".part");

	bool remove_partial_download = true;
	if (url.contains (".pkg.tar.") && !url.has_suffix (".sig")) {
		remove_partial_download = false;
	}

	int64 size = 0;
	string? last_modified = null;
	bool continue_download = false;
	try {
		var message = new Soup.Message ("GET", url);
		if (force == 0) {
			if (destfile.query_exists ()) {
				// start from scratch only download if our local is out of date.
				FileInfo info = destfile.query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
				DateTime time = info.get_modification_date_time ();
				var date = new Soup.Date.from_string (time.to_string ());
				message.request_headers.append ("If-Modified-Since", date.to_string (Soup.DateFormat.HTTP));
				if (tempfile.query_exists ()) {
					tempfile.delete ();
				}
			} else if (tempfile.query_exists ()) {
				// a previous partial download exists, resume from end of file.
				FileInfo info = tempfile.query_info ("standard::size", 0);
				int64 downloaded_size = info.get_size ();
				message.request_headers.set_range (downloaded_size, -1);
				continue_download = true;
			}
		} else {
			if (tempfile.query_exists ()) {
				tempfile.delete ();
			}
		}

		InputStream input = soup_session.send (message);
		if (message.status_code == 304) {
			return 1;
		}
		if (message.status_code >= 400) {
			// do not report error for missing sig
			if (!url.has_suffix (".sig")) {
				alpm_utils.do_emit_script_output ("%s: %s %s".printf (url, _("Error"), message.status_code.to_string ()));
			}
			return -1;
		}
		size = message.response_headers.get_content_length ();
		last_modified = message.response_headers.get_one ("Last-Modified");

		FileOutputStream output;
		if (continue_download) {
			output = tempfile.append_to (FileCreateFlags.NONE);
		} else {
			output = tempfile.create (FileCreateFlags.NONE);
		}

		uint64 progress = 0;
		uint8[] buf = new uint8[4096];
		// start download
		dl_callback (filename, 0, size);
		while (true) {
			ssize_t read = input.read (buf, alpm_utils.cancellable);
			if (read == 0) {
				// End of file reached
				break;
			}
			output.write (buf[0:read]);
			if (alpm_utils.cancellable.is_cancelled ()) {
				break;
			}
			progress += read;
			dl_callback (filename, progress, size);
		}
	} catch (Error e) {
		// cancelled download goes here
		if (e.code != IOError.CANCELLED) {
			alpm_utils.do_emit_script_output ("%s: %s".printf (url, e.message));
		}
		if (remove_partial_download) {
			try {
				if (tempfile.query_exists ()) {
					tempfile.delete ();
				}
			} catch (Error e) {
				warning (e.message);
			}
		}
		return -1;
	}

	// download succeeded
	dl_callback (filename, size, size);
	try {
		tempfile.move (destfile, FileCopyFlags.OVERWRITE);
		// set modification time
		if (last_modified != null) {
			string time_str = new Soup.Date.from_string (last_modified).to_string (Soup.DateFormat.ISO8601);
			var datetime = new DateTime.from_iso8601 (time_str, new TimeZone.utc ());
			FileInfo info = destfile.query_info ("time::modified", 0);
			info.set_modification_date_time (datetime);
			destfile.set_attributes_from_info (info, FileQueryInfoFlags.NONE);
		}
		return 0;
	} catch (Error e) {
		warning (e.message);
		return -1;
	}
}

void cb_totaldownload (uint64 total) {
	alpm_utils.emit_totaldownload (total);
}

void cb_log (Alpm.LogLevel level, string fmt, va_list args) {
	// do not log errors when download is cancelled
	if (alpm_utils.cancellable.is_cancelled ()) {
		return;
	}
	Alpm.LogLevel logmask = Alpm.LogLevel.ERROR | Alpm.LogLevel.WARNING;
	if ((level & logmask) == 0) {
		return;
	}
	string? log = null;
	log = fmt.vprintf (args);
	if (log != null) {
		alpm_utils.emit_log ((uint) level, log);
	}
}
