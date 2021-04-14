/*
 *  pamac-vala
 *
 *  Copyright (C) 2018-2021 Guillaume Benoit <guillaume@manjaro.org>
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
double current_progress;
uint64 total_download;
uint64 already_downloaded;
Mutex multi_progress_mutex;
HashTable<string, uint64?> multi_progress;
GenericArray<string> unresolvables;

class Download: Object {
	unowned string cachedir;
	unowned Alpm.Package alpm_pkg;
	bool emit_signals;

	public Download (string cachedir, Alpm.Package alpm_pkg, bool emit_signals) {
		this.cachedir = cachedir;
		this.alpm_pkg = alpm_pkg;
		this.emit_signals = emit_signals;
	}

	public void run () {
		unowned Alpm.DB? db = alpm_pkg.db;
		if (db == null) {
			return;
		}
		// a copy is needed because trans pkg can be deleted when cancellation
		string filename = alpm_pkg.filename;
		unowned Alpm.List<unowned string> servers = db.servers;
		while (servers != null) {
			int ret;
			unowned string mirror = servers.data;
			if (emit_signals) {
				ret = dload (mirror, filename, cachedir, 0, true, true);
			} else {
				ret = dload (mirror, filename, cachedir, 0, true, false);
			}
			if (ret == 0) {
				// success
				return;
			}
			if (alpm_utils.cancellable.is_cancelled ()) {
				return;
			}
			servers.next ();
		}
	}
}

namespace Pamac {
	internal class AlpmUtils: Object {
		string sender;
		Config config;
		public AlpmConfig alpm_config;
		string tmp_path;
		public File lockfile;
		// run transaction data
		uint8 commit_retries;
		string current_status;
		bool sysupgrade;
		bool enable_downgrade;
		bool simple_install;
		bool no_confirm_commit;
		bool keep_built_pkgs;
		int trans_flags;
		GenericSet<string?> to_install;
		GenericSet<string?> deps_to_install;
		GenericSet<string?> to_remove;
		GenericSet<string?> required_to_remove;
		GenericSet<string?> orphans_to_remove;
		GenericSet<string?> conflicts_to_remove;
		GenericSet<string?> to_load;
		GenericSet<string?> to_build;
		GenericSet<string?> checked_deps;
		HashTable<string, string> to_install_as_dep;
		GenericSet<string?> ignorepkgs;
		GenericSet<string?> overwrite_files;
		GenericSet<string?> to_syncfirst;
		public Cancellable cancellable;
		public bool downloading_updates;
		// download data
		public Soup.Session soup_session;
		public Timer rate_timer;
		Queue<double?> download_rates;
		double download_rate;

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

		public AlpmUtils (Config config) {
			this.config = config;
			multi_progress_mutex = Mutex ();
			multi_progress = new HashTable<string, uint64?> (str_hash, str_equal);
			alpm_config = config.alpm_config;
			tmp_path = "/tmp/pamac";
			to_syncfirst = new GenericSet<string?> (str_hash, str_equal);
			to_install = new GenericSet<string?> (str_hash, str_equal);
			deps_to_install = new GenericSet<string?> (str_hash, str_equal);
			to_remove = new GenericSet<string?> (str_hash, str_equal);
			required_to_remove = new GenericSet<string?> (str_hash, str_equal);
			orphans_to_remove = new GenericSet<string?> (str_hash, str_equal);
			conflicts_to_remove = new GenericSet<string?> (str_hash, str_equal);
			to_load = new GenericSet<string?> (str_hash, str_equal);
			to_build = new GenericSet<string?> (str_hash, str_equal);
			checked_deps = new GenericSet<string?> (str_hash, str_equal);
			to_install_as_dep = new HashTable<string, string> (str_hash, str_equal);
			ignorepkgs = new GenericSet<string?> (str_hash, str_equal);
			overwrite_files = new GenericSet<string?> (str_hash, str_equal);
			current_filename = "";
			current_action = "";
			current_status = "";
			rate_timer = new Timer ();
			download_rates = new Queue<double?> ();
			cancellable = new Cancellable ();
			soup_session = new Soup.Session ();
			string user_agent = "Pamac/%s".printf (VERSION);
			soup_session.user_agent = user_agent;
			// set HTTP_USER_AGENT needed when downloading using libalpm like refreshing dbs
			Environment.set_variable ("HTTP_USER_AGENT", user_agent, true);
			soup_session.timeout = 30;
			downloading_updates = false;
			check_old_lock ();
		}

		public int do_choose_provider (string depend, string[] providers) {
			string[] providers_copy = providers;
			return choose_provider (depend, providers_copy);
		}

		void do_start_downloading () {
			start_downloading (sender);
		}

		void do_stop_downloading () {
			stop_downloading (sender);
		}

		void do_emit_action (string action) {
			emit_action (sender, action);
		}

		void do_emit_action_progress (string action, string status, double progress) {
			emit_action_progress (sender, action, status, progress);
		}

		void do_emit_download_progress (string action, string status, double progress) {
			emit_download_progress (sender, action, status, progress);
		}

		void do_emit_hook_progress (string action, string details, string status, double progress) {
			emit_hook_progress (sender, action, details, status, progress);
		}

		public void do_emit_script_output (string message) {
			emit_script_output (sender, message);
		}

		void do_emit_warning (string message) {
			emit_warning (sender, message);
		}

		void do_emit_error (string message, string[] details) {
			string[] details_copy = details;
			emit_error (sender, message, details_copy);
		}

		void do_important_details_outpout (bool must_show) {
			important_details_outpout (sender, must_show);
		}

		bool do_get_authorization () {
			return get_authorization (sender);
		}

		void check_old_lock () {
			var alpm_handle = get_handle (false, false, false);
			if (alpm_handle == null) {
				return;
			}
			lockfile = File.new_for_path (alpm_handle.lockfile);
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
				warning (_("Failed to initialize alpm library"));
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

		public bool set_pkgreason (string sender, string pkgname, uint reason) {
			this.sender = sender;
			if (do_get_authorization ()) {
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
			}
			return false;
		}

		public bool clean_cache (string[] filenames) {
			try {
				foreach (unowned string filename in filenames) {
					var file = File.new_for_path (filename);
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
				Process.spawn_command_line_sync ("bash -c 'rm -rf %s/*'".printf (aur_build_dir));
				return true;
			} catch (SpawnError e) {
				warning (e.message);
			}
			return false;
		}

		unowned Alpm.Package? get_syncpkg (Alpm.Handle? alpm_handle, string name) {
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

		bool update_dbs (Alpm.Handle? alpm_handle, int force) {
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
					Alpm.Errno err_no = alpm_handle.errno ();
					if (err_no != 0) {
						// download error details are set in cb_fetch
						if (err_no != Alpm.Errno.EXTERNAL_DOWNLOAD) {
							do_emit_warning (Alpm.strerror (err_no));
						}
					}
				}
				syncdbs.next ();
			}
			return success;
		}

		public bool refresh (string sender, bool force_refresh) {
			this.sender = sender;
			if (!do_get_authorization ()) {
				return false;
			}
			do_emit_action (_("Synchronizing package databases") + "...");
			do_start_downloading ();
			write_log_file ("synchronizing package lists");
			cancellable.reset ();
			int force = (force_refresh) ? 1 : 0;
			if (force_refresh) {
				// remove dbs in tmp
				try {
					Process.spawn_command_line_sync ("bash -c 'rm -rf %s/dbs'".printf (tmp_path));
				} catch (SpawnError e) {
					warning (e.message);
				}
			} else {
				// try to copy refresh dbs from tmp
				var file = File.new_for_path (tmp_path);
				if (file.query_exists ()) {
					try {
						var alpm_handle = get_handle ();
						if (alpm_handle != null) {
							Process.spawn_command_line_sync ("bash -c 'cp --preserve=timestamps -u %s/dbs/sync/* %ssync'".printf (tmp_path, alpm_handle.dbpath));
						}
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
			} else if (success) {
				// save now as last refresh time
				try {
					// touch the file
					string timestamp_path = "%ssync/refresh_timestamp".printf (alpm_handle.dbpath);
					Process.spawn_command_line_sync ("touch %s".printf (timestamp_path));
				} catch (SpawnError e) {
					warning (e.message);
				}
			} else {
				do_emit_warning (_("Failed to synchronize databases"));
			}
			current_filename = "";
			// return false only if cancelled
			return true;
		}

		void add_ignorepkgs (Alpm.Handle? alpm_handle) {
			foreach (unowned string pkgname in ignorepkgs) {
				alpm_handle.add_ignorepkg (pkgname);
			}
		}

		void remove_ignorepkgs (Alpm.Handle? alpm_handle) {
			foreach (unowned string pkgname in ignorepkgs) {
				alpm_handle.remove_ignorepkg (pkgname);
			}
		}

		void add_overwrite_files (Alpm.Handle? alpm_handle) {
			foreach (unowned string name in overwrite_files) {
				alpm_handle.add_overwrite_file (name);
			}
		}

		void remove_overwrite_files (Alpm.Handle? alpm_handle) {
			foreach (unowned string name in overwrite_files) {
				alpm_handle.remove_overwrite_file (name);
			}
		}

		AlpmPackage initialise_pkg (Alpm.Handle? alpm_handle, Alpm.Package? alpm_pkg) {
			// use AlpmPackageData because alpm_pkg will be freed at trans release
			unowned Alpm.Package? local_pkg;
			unowned Alpm.Package? sync_pkg;
			if (alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
				local_pkg = alpm_pkg;
				sync_pkg = get_syncpkg (alpm_handle, alpm_pkg.name);
			} else if (alpm_pkg.origin == Alpm.Package.From.SYNCDB) {
				local_pkg = alpm_handle.localdb.get_pkg (alpm_pkg.name);
				sync_pkg = alpm_pkg;
			} else {
				// load pkg or built pkg
				local_pkg = alpm_handle.localdb.get_pkg (alpm_pkg.name);
				sync_pkg = get_syncpkg (alpm_handle, alpm_pkg.name);
			}
			return new AlpmPackageData.transaction (alpm_pkg, local_pkg, sync_pkg);
		}

		public void download_updates (string sender) {
			this.sender = sender;
			downloading_updates = true;
			// use tmp handle
			var alpm_handle = alpm_config.get_handle (false, true);
			if (alpm_handle == null) {
				return;
			}
			cancellable.reset ();
			int success = alpm_handle.trans_init (Alpm.TransFlag.NOLOCK);
			if (success == 0) {
				success = alpm_handle.trans_sysupgrade (0);
				if (success == 0) {
					Alpm.List err_data;
					success = alpm_handle.trans_prepare (out err_data);
					if (success == 0) {
						// custom parallel downloads
						download_files (alpm_handle, config.max_parallel_downloads, false);
					}
				}
				alpm_handle.trans_release ();
			}
			downloading_updates = false;
		}

		bool trans_init (Alpm.Handle? alpm_handle, int flags) {
			cancellable.reset ();
			if (alpm_handle.trans_init ((Alpm.TransFlag) flags) == -1) {
				Alpm.Errno err_no = alpm_handle.errno ();
				if (err_no != 0) {
					do_emit_error (_("Failed to init transaction"), {Alpm.strerror (err_no)});
				} else {
					do_emit_error (_("Failed to init transaction"), {});
				}
				return false;
			}
			return true;
		}

		bool trans_sysupgrade (Alpm.Handle? alpm_handle) {
			add_ignorepkgs (alpm_handle);
			if (alpm_handle.trans_sysupgrade ((enable_downgrade) ? 1 : 0) == -1) {
				Alpm.Errno err_no = alpm_handle.errno ();
				if (err_no != 0) {
					do_emit_error (_("Failed to prepare transaction"), {Alpm.strerror (err_no)});
				} else {
					do_emit_error (_("Failed to prepare transaction"), {});
				}
				return false;
			}
			// check syncfirsts
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

		bool trans_add_pkg_real (Alpm.Handle? alpm_handle, Alpm.Package? pkg) {
			if (alpm_handle.trans_add_pkg (pkg) == -1) {
				Alpm.Errno err_no = alpm_handle.errno ();
				if (err_no == Alpm.Errno.TRANS_DUP_TARGET || err_no == Alpm.Errno.PKG_IGNORED) {
					// just skip duplicate or ignored targets
					return true;
				} else {
					if (err_no != 0) {
						do_emit_error (_("Failed to prepare transaction"), {Alpm.strerror (err_no)});
					} else {
						do_emit_error (_("Failed to prepare transaction"), {});
					}
					return false;
				}
			}
			return true;
		}

		bool trans_add_pkg (Alpm.Handle? alpm_handle, string pkgname) {
			unowned Alpm.Package? pkg = alpm_handle.find_dbs_satisfier (alpm_handle.syncdbs, pkgname);
			if (pkg == null) {
				do_emit_error (_("Failed to prepare transaction"), {_("target not found: %s").printf (pkgname)});
				return false;
			} else {
				bool success = trans_add_pkg_real (alpm_handle, pkg);
				if (success) {
					if (("linux4" in pkg.name) || ("linux5" in pkg.name)) {
						var installed_kernels = new GenericArray<string> ();
						var installed_modules = new GenericArray<string> ();
						unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
						while (pkgcache != null) {
							unowned Alpm.Package local_pkg = pkgcache.data;
							if (("linux4" in local_pkg.name) || ("linux5" in local_pkg.name)) {
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
							foreach (unowned string installed_kernel in installed_kernels) {
								var module = new StringBuilder ();
								module.append (installed_kernel);
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
							foreach (unowned string installed_module in installed_modules) {
								var module = new StringBuilder ();
								module.append (splitted[0]);
								module.append ("-");
								module.append (installed_module);
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
			if (!do_get_authorization ()) {
				return "";
			}
			var alpm_handle = get_handle ();
			if (alpm_handle == null) {
				return "";
			}
			return download_pkg_priv (alpm_handle, url) ?? "";
		}

		string? download_pkg_priv (Alpm.Handle? alpm_handle, string url) {
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

		bool trans_load_pkg (Alpm.Handle? alpm_handle, string path) {
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
				Alpm.Errno err_no = alpm_handle.errno ();
				if (err_no != 0) {
					do_emit_error (_("Failed to prepare transaction"), {Alpm.strerror (err_no)});
				} else {
					do_emit_error (_("Failed to prepare transaction"), {});
				}
				return false;
			} else if (alpm_handle.trans_add_pkg (pkg) == -1) {
				Alpm.Errno err_no = alpm_handle.errno ();
				if (err_no == Alpm.Errno.TRANS_DUP_TARGET || err_no == Alpm.Errno.PKG_IGNORED) {
					// just skip duplicate or ignored targets
					return true;
				} else {
					if (err_no != 0) {
						do_emit_error (_("Failed to prepare transaction"), {"%s: %s".printf (pkg->name, Alpm.strerror (err_no))});
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

		bool trans_remove_pkg (Alpm.Handle? alpm_handle, string pkgname) {
			bool success = true;
			unowned Alpm.Package? pkg =  alpm_handle.localdb.get_pkg (pkgname);
			if (pkg == null) {
				do_emit_error (_("Failed to prepare transaction"), {_("target not found: %s").printf (pkgname)});
				success = false;
			} else if (alpm_handle.trans_remove_pkg (pkg) == -1) {
				Alpm.Errno err_no = alpm_handle.errno ();
				// just skip duplicate targets
				if (err_no != Alpm.Errno.TRANS_DUP_TARGET) {
					if (err_no != 0) {
						do_emit_error (_("Failed to prepare transaction"), {"%s: %s".printf (pkg.name, Alpm.strerror (err_no))});
					} else {
						do_emit_error (_("Failed to prepare transaction"), {});
					}
					success = false;
				}
			}
			return success;
		}

		bool trans_prepare_real (Alpm.Handle? alpm_handle, bool emit_error = true) {
			bool success = true;
			bool need_retry = false;
			Alpm.List err_data;
			if (alpm_handle.trans_prepare (out err_data) == -1) {
				var details = new GenericArray<string> ();
				Alpm.Errno err_no = alpm_handle.errno ();
				switch (err_no) {
					case 0:
						break;
					case Alpm.Errno.PKG_INVALID_ARCH:
						details.add (Alpm.strerror (err_no) + ":");
						unowned Alpm.List<string*> list = err_data;
						while (list != null) {
							string* pkgname = list.data;
							details.add ("- " + _("package %s does not have a valid architecture").printf (pkgname));
							delete pkgname;
							list.next ();
						}
						break;
					case Alpm.Errno.UNSATISFIED_DEPS:
						details.add (Alpm.strerror (err_no) + ":");
						unowned Alpm.List<Alpm.DepMissing*> list = err_data;
						// display one error by unsatisfied dep
						var depstrings = new GenericSet<string?> (str_hash, str_equal);
						while (list != null) {
							Alpm.DepMissing* miss = list.data;
							string depstring = miss->depend.compute_string ();
							if (depstring in depstrings) {
								delete miss;
								list.next ();
								continue;
							}
							unowned Alpm.List<unowned Alpm.Package> trans_add = alpm_handle.trans_to_add ();
							unowned Alpm.Package pkg;
							if (miss->causingpkg == null) {
								/* package being installed/upgraded has unresolved dependency */
								details.add ("- " + _("unable to satisfy dependency '%s' required by %s").printf (depstring, miss->target));
							} else if ((pkg = Alpm.pkg_find (trans_add, miss->causingpkg)) != null) {
								/* upgrading a package breaks a local dependency */
								if (commit_retries < 1) {
									do_emit_warning (_("Warning") + ": " + _("installing %s (%s) breaks dependency '%s' required by %s").printf (miss->causingpkg, pkg.version, depstring, miss->target));
									do_emit_warning (_("Add %s to remove").printf (miss->target));
									required_to_remove.add (miss->target);
									if (trans_remove_pkg (alpm_handle, miss->target)) {
										need_retry = true;
									}
								} else {
									details.add ("- " + _("installing %s (%s) breaks dependency '%s' required by %s").printf (miss->causingpkg, pkg.version, depstring, miss->target) + ",");
									details.add ("- " + _("if possible, remove %s and retry").printf (miss->target));
								}
							} else {
								/* removing a package breaks a local dependency */
								if (commit_retries < 1) {
									do_emit_warning (_("Warning") + ": " + _("removing %s breaks dependency '%s' required by %s").printf (miss->causingpkg, depstring, miss->target));
									do_emit_warning (_("Add %s to remove").printf (miss->target));
									required_to_remove.add (miss->target);
									if (trans_remove_pkg (alpm_handle, miss->target)) {
										need_retry = true;
									}
								} else {
									details.add ("- " + _("removing %s breaks dependency '%s' required by %s").printf (miss->causingpkg, depstring, miss->target) + ",");
									details.add ("- " + _("if possible, remove %s and retry").printf (miss->target));
								}
							}
							depstrings.add ((owned) depstring);
							delete miss;
							list.next ();
						}
						break;
					case Alpm.Errno.CONFLICTING_DEPS:
						details.add (Alpm.strerror (err_no) + ":");
						unowned Alpm.List<Alpm.Conflict*> list = err_data;
						while (list != null) {
							Alpm.Conflict* conflict = list.data;
							string conflict_detail = "- " + _("%s and %s are in conflict").printf (conflict->package1, conflict->package2);
							// only print reason if it contains new information
							if (conflict->reason.mod != Alpm.Depend.Mode.ANY) {
								conflict_detail += " (%s)".printf (conflict->reason.compute_string ());
							}
							details.add ((owned) conflict_detail);
							delete conflict;
							list.next ();
						}
						break;
					default:
						details.add (Alpm.strerror (err_no));
						break;
				}
				if (need_retry && commit_retries < 1) {
					// retry
					commit_retries++;
					success = trans_prepare_real (alpm_handle);
				} else {
					trans_release (alpm_handle);
					if (emit_error) {
						do_emit_error (_("Failed to prepare transaction"), details.data);
					}
					success = false;
				}
			} else if (emit_error) {
				var details = new GenericArray<string> ();
				// Search for holdpkg in target list
				bool found_locked_pkg = false;
				unowned Alpm.List<unowned Alpm.Package> to_remove = alpm_handle.trans_to_remove ();
				while (to_remove != null) {
					unowned Alpm.Package pkg = to_remove.data;
					if (pkg.name in alpm_config.holdpkgs) {
						details.add ("- " + _("%s needs to be removed but it is a locked package").printf (pkg.name));
						found_locked_pkg = true;
					}
					to_remove.next ();
				}
				if (found_locked_pkg) {
					do_emit_error (_("Failed to prepare transaction"), details.data);
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

		void prepare_aur_db (Alpm.Handle? alpm_handle) {
			// fake aur db
			try {
				Process.spawn_command_line_sync ("cp %s/pamac_aur.db %ssync".printf (tmp_path, alpm_handle.dbpath));
			} catch (SpawnError e) {
				do_emit_warning (e.message);
			}
			// check if we need to remove debug package to avoid dep problem
			foreach (unowned string name in to_build) {
				string debug_pkg_name = "%s-debug".printf (name);
				if (alpm_handle.localdb.get_pkg (debug_pkg_name) != null) {
					to_remove.add (debug_pkg_name);
				}
			}
			// base-devel group is needed to build pkgs
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				// base-devel group is in core
				if (db.name == "core") {
					unowned Alpm.Group? grp = db.get_group ("base-devel");
					if (grp != null) {
						unowned Alpm.List<unowned Alpm.Package> packages = grp.packages;
						while (packages != null) {
							unowned Alpm.Package pkg = packages.data;
							if (Alpm.find_satisfier (alpm_handle.localdb.pkgcache, pkg.name) == null) {
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
		}

		void remove_aur_db (Alpm.Handle? alpm_handle) {
			// remove fake aur db
			try {
				Process.spawn_command_line_sync ("rm -f %ssync/pamac_aur.db".printf (alpm_handle.dbpath));
			} catch (SpawnError e) {
				warning (e.message);
			}
		}

		public bool trans_check_prepare (bool sysupgrade,
										bool enable_downgrade,
										bool simple_install,
										int trans_flags,
										GenericSet<string?> to_install,
										GenericSet<string?> to_remove,
										GenericSet<string?> to_load,
										GenericSet<string?> to_build,
										GenericSet<string?> ignorepkgs,
										GenericSet<string?> overwrite_files,
										ref TransactionSummary summary) {
			// use an tmp handle with no callback to avoid double prepare signals
			var tmp_handle = get_handle (false, true, false);
			if (tmp_handle == null) {
				return false;
			}
			// add question callback for replaces/conflicts/corrupted pkgs and import keys
			tmp_handle.questioncb = (Alpm.QuestionCallBack) cb_question;
			// compute arguments
			this.sender = "";
			this.sysupgrade = sysupgrade;
			this.enable_downgrade = enable_downgrade;
			this.simple_install = simple_install;
			this.trans_flags = trans_flags | Alpm.TransFlag.NOLOCK;
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
			foreach (unowned string name in ignorepkgs) {
				this.ignorepkgs.add (name);
			}
			foreach (unowned string name in overwrite_files) {
				this.overwrite_files.add (name);
			}
			return trans_check_prepare_real (tmp_handle, ref summary);
		}

		bool trans_check_prepare_real (Alpm.Handle? tmp_handle, ref TransactionSummary summary) {
			unowned Alpm.DB? aur_db = null;
			if (to_remove.length > 0) {
				intern_compute_pkgs_to_remove (tmp_handle);
			}
			if (to_install.length > 0 || sysupgrade || to_build.length > 0 || to_load.length > 0) {
				if (to_build.length > 0) {
					prepare_aur_db (tmp_handle);
					// fake aur db
					aur_db = tmp_handle.register_syncdb ("pamac_aur", 0);
					if (aur_db == null) {
						remove_aur_db (tmp_handle);
						Alpm.Errno err_no = tmp_handle.errno ();
						do_emit_error (_("Failed to initialize AUR database"), {Alpm.strerror (err_no)});
						return false;
					}
				}
				intern_compute_pkgs_to_install (tmp_handle, aur_db);
			}
			if ((trans_flags & Alpm.TransFlag.RECURSE) != 0) {
				intern_compute_orphans_to_remove (tmp_handle);
			}
			// add signals for the real prepare
			tmp_handle.eventcb = (Alpm.EventCallBack) cb_event;
			tmp_handle.progresscb = (Alpm.ProgressCallBack) cb_progress;
			// add log callback for warnings/errors
			tmp_handle.logcb = (Alpm.LogCallBack) cb_log;
			bool success = trans_prepare (tmp_handle, aur_db);
			if (success) {
				get_transaction_summary (tmp_handle, ref summary);
				trans_release (tmp_handle);
			}
			if (aur_db != null) {
				remove_aur_db (tmp_handle);
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
								string[] ignorepkgs,
								string[] overwrite_files) {
			this.sender = sender;
			this.sysupgrade = sysupgrade;
			this.enable_downgrade = enable_downgrade;
			this.simple_install = simple_install;
			this.no_confirm_commit = true;
			this.keep_built_pkgs = keep_built_pkgs;
			this.trans_flags = trans_flags;
			// CASCADE and RECURSE flags already internally handled in trans_check_prepare
			this.trans_flags &= ~Alpm.TransFlag.CASCADE;
			this.trans_flags &= ~Alpm.TransFlag.RECURSE;
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
			foreach (unowned string name in ignorepkgs) {
				this.ignorepkgs.add (name);
			}
			foreach (unowned string name in overwrite_files) {
				this.overwrite_files.add (name);
			}
			return trans_run_real ();
		}

		bool trans_run_real () {
			// use an handle with no callback to avoid double prepare signals
			var alpm_handle = get_handle (false, false, false);
			if (alpm_handle == null) {
				return false;
			}
			// add question callback for replaces/conflicts/corrupted pkgs and import keys
			alpm_handle.questioncb = (Alpm.QuestionCallBack) cb_question;
			// aur db not used
			unowned Alpm.DB? aur_db = null;
			bool success = trans_prepare (alpm_handle, aur_db);
			if (success) {
				if (alpm_handle.trans_to_add () != null ||
					alpm_handle.trans_to_remove () != null) {
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
						trans_reset ();
						success = false;
					}
				} else {
					//do_emit_action (dgettext (null, "Nothing to do") + ".");
					trans_release (alpm_handle);
					trans_reset ();
					success = true;
				}
			}
			return success;
		}

		void trans_reset () {
			commit_retries = 0;
			total_download = 0;
			already_downloaded = 0;
			current_filename = "";
			to_syncfirst.remove_all ();
			to_install.remove_all ();
			deps_to_install.remove_all ();
			to_remove.remove_all ();
			required_to_remove.remove_all ();
			orphans_to_remove.remove_all ();
			conflicts_to_remove.remove_all ();
			to_load.remove_all ();
			to_build.remove_all ();
			checked_deps.remove_all ();
			ignorepkgs.remove_all ();
			overwrite_files.remove_all ();
			to_install_as_dep.remove_all ();
			no_confirm_commit = false;
		}

		void intern_compute_pkgs_to_remove (Alpm.Handle? alpm_handle) {
			int tmp_trans_flags = Alpm.TransFlag.NOLOCK;
			if ((trans_flags & Alpm.TransFlag.UNNEEDED) != 0) {
				// remove UNNEEDED to trans_flags
				trans_flags &= ~Alpm.TransFlag.UNNEEDED;
				tmp_trans_flags |= Alpm.TransFlag.UNNEEDED;
			} else if ((trans_flags & Alpm.TransFlag.CASCADE) != 0) {
				// remove CASCADE to trans_flags
				trans_flags &= ~Alpm.TransFlag.CASCADE;
				tmp_trans_flags |= Alpm.TransFlag.CASCADE;
			}
			bool success = trans_init (alpm_handle, tmp_trans_flags);
			if (success) {
				foreach (unowned string name in to_remove) {
					success = trans_remove_pkg (alpm_handle, name);
					if (!success) {
						break;
					}
				}
				if (success) {
					success = trans_prepare_real (alpm_handle, false);
				} else {
					trans_release (alpm_handle);
				}
			}
			if (success) {
				// UNNEEDED flag could remove some packages
				var to_remove_copy = (owned) to_remove;
				to_remove = new GenericSet<string?> (str_hash, str_equal);
				unowned Alpm.List<unowned Alpm.Package> pkgs_to_remove = alpm_handle.trans_to_remove ();
				while (pkgs_to_remove != null) {
					unowned Alpm.Package trans_pkg = pkgs_to_remove.data;
					unowned string name = trans_pkg.name;
					if (name in to_remove_copy) {
						to_remove.add (name);
					} else {
						required_to_remove.add (name);
					}
					pkgs_to_remove.next ();
				}
				trans_release (alpm_handle);
			}
		}

		void remove_install_deps_in_to_remove (Alpm.Handle? alpm_handle, Alpm.List<unowned Alpm.Package>? deps_to_check) {
			Alpm.List<unowned Alpm.Package> deps_to_check_next = null;
			while (deps_to_check != null) {
				unowned Alpm.Package alpm_pkg = deps_to_check.data;
				checked_deps.add (alpm_pkg.name);
				// deps
				unowned Alpm.List<unowned Alpm.Depend> depends = alpm_pkg.depends;
				while (depends != null) {
					unowned Alpm.Package? satisfier = Alpm.find_satisfier (alpm_handle.localdb.pkgcache, depends.data.compute_string ());
					if (satisfier != null) {
						if (!(satisfier.name in checked_deps)) {
							if (to_remove.remove (satisfier.name)) {
								do_emit_script_output (dgettext (null, "Warning") + ": " + dgettext (null, "removing %s from target list").printf (satisfier.name));
							}
							deps_to_check_next.add (satisfier);
						}
					}
					depends.next ();
				}
				// optdepends
				depends = alpm_pkg.optdepends;
				while (depends != null) {
					unowned Alpm.Package? satisfier = Alpm.find_satisfier (alpm_handle.localdb.pkgcache, depends.data.compute_string ());
					if (satisfier != null) {
						if (!(satisfier.name in checked_deps)) {
							if (to_remove.remove (satisfier.name)) {
								do_emit_script_output (dgettext (null, "Warning") + ": " + dgettext (null, "removing %s from target list").printf (satisfier.name));
							}
							deps_to_check_next.add (satisfier);
						}
					}
					depends.next ();
				}
				deps_to_check.next ();
			}
			if (deps_to_check_next != null) {
				remove_install_deps_in_to_remove (alpm_handle, deps_to_check_next);
			}
		}

		void intern_compute_pkgs_to_install (Alpm.Handle? alpm_handle, Alpm.DB? aur_db) {
			int tmp_trans_flags = Alpm.TransFlag.NOLOCK;
			if ((trans_flags & Alpm.TransFlag.NEEDED) != 0) {
				// remove NEEDED to trans_flags
				trans_flags &= ~Alpm.TransFlag.NEEDED;
				tmp_trans_flags |= Alpm.TransFlag.NEEDED;
			}
			bool success = trans_init (alpm_handle, tmp_trans_flags);
			if (success && sysupgrade) {
				success = trans_sysupgrade (alpm_handle);
				if (!success) {
					trans_release (alpm_handle);
				}
			}
			if (success) {
				foreach (unowned string name in to_install) {
					success = trans_add_pkg (alpm_handle, name);
					if (!success) {
						break;
					}
				}
				if (success) {
					// add to_build from fake aur db
					Alpm.List<unowned Alpm.DB> dbs = null;
					dbs.add (aur_db);
					foreach (unowned string name in to_build) {
						unowned Alpm.Package? pkg = alpm_handle.find_dbs_satisfier (dbs, name);
						if (pkg == null) {
							success = false;
							break;
						} else {
							success = trans_add_pkg_real (alpm_handle, pkg);
							if (!success) {
								break;
							}
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
					success = trans_prepare_real (alpm_handle, false);
				} else {
					trans_release (alpm_handle);
				}
			}
			if (success) {
				// NEEDED flag could remove some packages
				// to_build can contain some virtual package
				var to_install_copy = (owned) to_install;
				to_install = new GenericSet<string?> (str_hash, str_equal);
				to_build = new GenericSet<string?> (str_hash, str_equal);
				Alpm.List<unowned Alpm.Package> deps_to_check = null;
				unowned Alpm.List<unowned Alpm.Package> pkgs_to_add = alpm_handle.trans_to_add ();
				while (pkgs_to_add != null) {
					unowned Alpm.Package trans_pkg = pkgs_to_add.data;
					if (trans_pkg.db != null) {
						unowned string name = trans_pkg.name;
						if (trans_pkg.db.name == "pamac_aur") {
							to_build.add (name);
						} else {
							if (name in to_install_copy) {
								to_install.add (name);
							} else {
								deps_to_install.add (name);
							}
						}
					}
					if (to_remove.length > 0) {
						if (to_remove.remove (trans_pkg.name)) {
							do_emit_script_output (dgettext (null, "Warning") + ": " + dgettext (null, "removing %s from target list").printf (trans_pkg.name));
						}
						checked_deps.add (trans_pkg.name);
						// deps
						unowned Alpm.List<unowned Alpm.Depend> depends = trans_pkg.depends;
						while (depends != null) {
							unowned Alpm.Package? satisfier = Alpm.find_satisfier (alpm_handle.localdb.pkgcache, depends.data.compute_string ());
							if (satisfier != null) {
								if (!(satisfier.name in checked_deps)) {
									if (to_remove.remove (satisfier.name)) {
										do_emit_script_output (dgettext (null, "Warning") + ": " + dgettext (null, "removing %s from target list").printf (satisfier.name));
									}
									deps_to_check.add (satisfier);
								}
							}
							depends.next ();
						}
						// optdepends
						depends = trans_pkg.optdepends;
						while (depends != null) {
							unowned Alpm.Package? satisfier = Alpm.find_satisfier (alpm_handle.localdb.pkgcache, depends.data.compute_string ());
							if (satisfier != null) {
								if (!(satisfier.name in checked_deps)) {
									if (to_remove.remove (satisfier.name)) {
										do_emit_script_output (dgettext (null, "Warning") + ": " + dgettext (null, "removing %s from target list").printf (satisfier.name));
									}
									deps_to_check.add (satisfier);
								}
							}
							depends.next ();
						}
					}
					pkgs_to_add.next ();
				}
				// get conflicts to remove
				unowned Alpm.List<unowned Alpm.Package> pkgs_to_remove = alpm_handle.trans_to_remove ();
				while (pkgs_to_remove != null) {
					unowned Alpm.Package trans_pkg = pkgs_to_remove.data;
					conflicts_to_remove.add (trans_pkg.name);
					pkgs_to_remove.next ();
				}
				trans_release (alpm_handle);
				if (deps_to_check != null) {
					remove_install_deps_in_to_remove (alpm_handle, deps_to_check);
				}
			}
		}

		void check_orphans_to_remove (Alpm.Handle? alpm_handle, Alpm.List<unowned Alpm.Package>? deps_to_check) {
			Alpm.List<unowned Alpm.Package> deps_to_check_next = null;
			while (deps_to_check != null) {
				unowned Alpm.Package alpm_pkg = deps_to_check.data;
				if (!(alpm_pkg.name in checked_deps)) {
					if (alpm_pkg.reason == Alpm.Package.Reason.DEPEND) {
						// check if alpm_pkg is only required by package in to_remove
						Alpm.List<string> requiredby = alpm_pkg.compute_requiredby ();
						unowned Alpm.List<string> list = requiredby;
						bool extern_dep = false;
						while (list != null) {
							unowned Alpm.Package? satisfier = Alpm.find_satisfier (alpm_handle.localdb.pkgcache, list.data);
							if (satisfier != null) {
								if (!(satisfier.name in to_remove)
									&& !(satisfier.name in required_to_remove)
									&& !(satisfier.name in orphans_to_remove)) {
									extern_dep = true;
									break;
								}
							}
							list.next ();
						}
						requiredby.free_inner (GLib.free);
						if (!extern_dep) {
							// check if alpm_pkg is only optional by package in to_remove
							Alpm.List<string> optionalfor = alpm_pkg.compute_optionalfor ();
							list = optionalfor;
							while (list != null) {
								unowned Alpm.Package? satisfier = Alpm.find_satisfier (alpm_handle.localdb.pkgcache, list.data);
								if (satisfier != null) {
									if (!(satisfier.name in to_remove)
										&& !(satisfier.name in required_to_remove)
										&& !(satisfier.name in orphans_to_remove)) {
										extern_dep = true;
										break;
									}
								}
								list.next ();
							}
							optionalfor.free_inner (GLib.free);
							if (!extern_dep) {
								orphans_to_remove.add (alpm_pkg.name);
								checked_deps.add (alpm_pkg.name);
								unowned Alpm.List<unowned Alpm.Depend> depends = alpm_pkg.depends;
								while (depends != null) {
									unowned Alpm.Package? satisfier = Alpm.find_satisfier (alpm_handle.localdb.pkgcache, depends.data.compute_string ());
									if (satisfier != null) {
										if (!(satisfier.name in to_remove)
											&& !(satisfier.name in required_to_remove)
											&& !(satisfier.name in orphans_to_remove)) {
											deps_to_check_next.add (satisfier);
										}
									}
									depends.next ();
								}
							}
						}
					}
				}
				deps_to_check.next ();
			}
			if (deps_to_check_next != null) {
				check_orphans_to_remove (alpm_handle, deps_to_check_next);
			}
		}

		void intern_compute_orphans_to_remove (Alpm.Handle? alpm_handle) {
			// remove RECURSE to trans_flags
			trans_flags &= ~Alpm.TransFlag.RECURSE;
			checked_deps.remove_all ();
			Alpm.List<unowned Alpm.Package> deps_to_check = null;
			foreach (unowned string name in to_remove) {
				unowned Alpm.Package? trans_pkg = alpm_handle.localdb.get_pkg (name);
				if (trans_pkg != null) {
					if (!(trans_pkg.name in checked_deps)) {
						checked_deps.add (trans_pkg.name);
						unowned Alpm.List<unowned Alpm.Depend> depends = trans_pkg.depends;
						while (depends != null) {
							unowned Alpm.Package? satisfier = Alpm.find_satisfier (alpm_handle.localdb.pkgcache, depends.data.compute_string ());
							if (satisfier != null) {
								if (!(satisfier.name in to_remove)
									&& !(satisfier.name in required_to_remove)) {
									deps_to_check.add (satisfier);
								}
							}
							depends.next ();
						}
					}
				}
			}
			foreach (unowned string name in required_to_remove) {
				unowned Alpm.Package? trans_pkg = alpm_handle.localdb.get_pkg (name);
				if (trans_pkg != null) {
					if (!(trans_pkg.name in checked_deps)) {
						checked_deps.add (trans_pkg.name);
						unowned Alpm.List<unowned Alpm.Depend> depends = trans_pkg.depends;
						while (depends != null) {
							unowned Alpm.Package? satisfier = Alpm.find_satisfier (alpm_handle.localdb.pkgcache, depends.data.compute_string ());
							if (satisfier != null) {
								if (!(satisfier.name in to_remove)
									&& !(satisfier.name in required_to_remove)) {
									deps_to_check.add (satisfier);
								}
							}
							depends.next ();
						}
					}
				}
			}
			if (deps_to_check != null) {
				check_orphans_to_remove (alpm_handle, deps_to_check);
			}
		}

		bool trans_prepare (Alpm.Handle? alpm_handle, Alpm.DB? aur_db) {
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
				foreach (unowned string name in deps_to_install) {
					success = trans_add_pkg (alpm_handle, name);
					if (!success) {
						break;
					}
				}
			}
			if (to_build.length > 0) {
				// add to_build from fake aur db
				Alpm.List<unowned Alpm.DB> dbs = null;
				dbs.add (aur_db);
				foreach (unowned string name in to_build) {
					unowned Alpm.Package? pkg = alpm_handle.find_dbs_satisfier (dbs, name);
					if (pkg == null) {
						do_emit_error (_("Failed to prepare transaction"), {_("target not found: %s").printf (name)});
						success = false;
						break;
					} else {
						success = trans_add_pkg_real (alpm_handle, pkg);
						if (!success) {
							break;
						}
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
				foreach (unowned string name in required_to_remove) {
					success = trans_remove_pkg (alpm_handle, name);
					if (!success) {
						break;
					}
				}
			}
			if (success) {
				foreach (unowned string name in orphans_to_remove) {
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

		TransactionSummary get_transaction_summary (Alpm.Handle? alpm_handle, ref TransactionSummary summary) {
			var checked = new HashTable<string, int> (str_hash, str_equal);
			// to_install
			unowned Alpm.List<unowned Alpm.Package> pkgs_to_add = alpm_handle.trans_to_add ();
			while (pkgs_to_add != null) {
				unowned Alpm.Package trans_pkg = pkgs_to_add.data;
				unowned Alpm.DB? db = trans_pkg.db;
				unowned string trans_pkg_name = trans_pkg.name;
				if (db != null && db.name == "pamac_aur") {
					// it is a aur pkg to build
					var pkg = initialise_pkg (alpm_handle, trans_pkg);
					if (!summary.aur_pkgbases_to_build.find_with_equal_func (trans_pkg.pkgbase, str_equal)) {
						summary.aur_pkgbases_to_build.add (trans_pkg.pkgbase);
					}
					if (pkg.installed_version == null) {
						if (!(trans_pkg_name in to_build)) {
							// it is a new required dep
							bool dep_found = false;
							unowned Alpm.Package check_pkg = trans_pkg;
							while (!dep_found) {
								Alpm.List<string> pkg_requiredby = check_pkg.compute_requiredby ();
								unowned Alpm.List<string> requiredby_list = pkg_requiredby;
								while (requiredby_list != null) {
									bool check_pkg_found = false;
									unowned Alpm.List<unowned Alpm.Package> pkgs_to_add2 = alpm_handle.trans_to_add ();
									while (pkgs_to_add2 != null) {
										unowned Alpm.Package pkg_to_add = pkgs_to_add2.data;
										unowned string pkg_to_add_name = pkg_to_add.name;
										if (pkg_to_add_name == requiredby_list.data) {
											if (pkg_to_add_name in to_build) {
												// found the top requiredby package
												pkg.requiredby.add (requiredby_list.data);
												dep_found = true;
											} else {
												if (pkg_to_add_name in checked) {
													int i = checked.lookup (pkg_to_add_name);
													// security for dependency cycle
													if (i < 100) {
														// check pkg_to_add requiredby
														check_pkg = pkg_to_add;
														check_pkg_found = true;
														checked.insert (pkg_to_add_name, i + 1);
													}
												} else {
													// check pkg_to_add requiredby
													check_pkg = pkg_to_add;
													check_pkg_found = true;
													checked.insert (pkg_to_add_name, 0);
												}
											}
											break;
										}
										pkgs_to_add2.next ();
									}
									if (dep_found || check_pkg_found) {
										break;
									}
									requiredby_list.next ();
								}
								if (requiredby_list == null) {
									break;
								}
							}
						}
					}
					summary.to_build.add (pkg);
				} else {
					var pkg = initialise_pkg (alpm_handle, trans_pkg);
					if (pkg.installed_version == null) {
						if (db != null && !(trans_pkg_name in to_install)) {
							// it is a new required dep or a replace
							bool dep_found = false;
							// 1 - check for required dep
							unowned Alpm.Package check_pkg = trans_pkg;
							while (!dep_found) {
								Alpm.List<string> pkg_requiredby = check_pkg.compute_requiredby ();
								unowned Alpm.List<string> requiredby_list = pkg_requiredby;
								while (requiredby_list != null) {
									bool check_pkg_found = false;
									unowned Alpm.List<unowned Alpm.Package> pkgs_to_add2 = alpm_handle.trans_to_add ();
									while (pkgs_to_add2 != null) {
										unowned Alpm.Package pkg_to_add = pkgs_to_add2.data;
										unowned string pkg_to_add_name = pkg_to_add.name;
										if (pkg_to_add_name == requiredby_list.data) {
											if (pkg_to_add_name in to_install
												|| pkg_to_add_name in to_build) {
												// found the top requiredby package
												pkg.requiredby.add (requiredby_list.data);
												dep_found = true;
											} else {
												if (pkg_to_add_name in checked) {
													int i = checked.lookup (pkg_to_add_name);
													// security for dependency cycle
													if (i < 100) {
														// check pkg_to_add requiredby
														check_pkg = pkg_to_add;
														check_pkg_found = true;
														checked.insert (pkg_to_add_name, i + 1);
													}
												} else {
													// check pkg_to_add requiredby
													check_pkg = pkg_to_add;
													check_pkg_found = true;
													checked.insert (pkg_to_add_name, 0);
												}
											}
											break;
										}
										pkgs_to_add2.next ();
									}
									if (dep_found || check_pkg_found) {
										break;
									}
									requiredby_list.next ();
								}
								if (requiredby_list == null) {
									break;
								}
							}
							// 2 - check for replaces
							if (!dep_found) {
								unowned Alpm.List<unowned Alpm.Depend> depends_list = trans_pkg.replaces;
								while (depends_list != null) {
									string depstring = depends_list.data.compute_string ();
									if (Alpm.find_satisfier (alpm_handle.localdb.pkgcache, depstring) != null) {
										pkg.replaces.add (depends_list.data.compute_string ());
										break;
									}
									depends_list.next ();
								}
							}
						}
						summary.to_install.add (pkg);
					} else {
						int cmp = Alpm.pkg_vercmp (pkg.version, pkg.installed_version);
						if (cmp == 1) {
							summary.to_upgrade.add (pkg);
						} else if (cmp == 0) {
							summary.to_reinstall.add (pkg);
						} else {
							summary.to_downgrade.add (pkg);
						}
					}
					if (db == null) {
						summary.to_load.add (trans_pkg_name);
					}
				}
				pkgs_to_add.next ();
			}
			// to_remove
			unowned Alpm.List<unowned Alpm.Package> pkgs_to_remove = alpm_handle.trans_to_remove ();
			while (pkgs_to_remove != null) {
				unowned Alpm.Package trans_pkg = pkgs_to_remove.data;
				var pkg = initialise_pkg (alpm_handle, trans_pkg);
				// add the reason why trans_pkg must be removed
				if (trans_pkg.name in to_remove) {
					// 1 - direct to_remove
					summary.to_remove.add (pkg);
				} else if (trans_pkg.name in required_to_remove) {
					// 2 - depends on a package to_remove
					bool dep_found = false;
					unowned Alpm.Package check_pkg = trans_pkg;
					while (!dep_found) {
						unowned Alpm.List<unowned Alpm.Depend> depends_list = check_pkg.depends;
						while (depends_list != null) {
							string depstring = depends_list.data.compute_string ();
							unowned Alpm.Package? dep = Alpm.find_satisfier (alpm_handle.trans_to_remove (), depstring);
							if (dep != null) {
								if (dep.name in to_remove
									|| dep.name in conflicts_to_remove) {
									// found the top depend package
									pkg.depends.add (dep.name);
									dep_found = true;
								} else {
									// check dep depends
									check_pkg = dep;
								}
								break;
							}
							depends_list.next ();
						}
						if (depends_list == null) {
							break;
						}
					}
					summary.to_remove.add (pkg);
				} else if (trans_pkg.name in orphans_to_remove) {
					// 3 - orphans
					bool dep_found = false;
					unowned Alpm.Package check_pkg = trans_pkg;
					while (!dep_found) {
						Alpm.List<string> requiredby = check_pkg.compute_requiredby ();
						// it is an orphan so requiredby list contains only one element
						if (requiredby != null) {
							unowned string name = requiredby.data;
							if (name in to_remove) {
								// found the top requiredby package
								pkg.requiredby.add (requiredby.data);
								dep_found = true;
							} else {
								// check name requiredby
								check_pkg = alpm_handle.localdb.get_pkg (name);
								// security
								if (check_pkg == null) {
									break;
								}
							}
						} else {
							break;
						}
					}
					summary.to_remove.add (pkg);
				} else {
					// 4 - it is a conflict.
					bool conflict_found = false;
					// a - check direct conflict
					unowned Alpm.List<unowned Alpm.Depend> depends_list = trans_pkg.conflicts;
					while (depends_list != null) {
						string depstring = depends_list.data.compute_string ();
						if (Alpm.find_satisfier (alpm_handle.trans_to_add (), depstring) != null) {
							pkg.conflicts.add ((owned) depstring);
							conflict_found = true;
							break;
						}
						depends_list.next ();
					}
					// b - check indirect conflict
					if (!conflict_found) {
						pkgs_to_add = alpm_handle.trans_to_add ();
						while (pkgs_to_add != null) {
							unowned Alpm.Package add_pkg = pkgs_to_add.data;
							depends_list = add_pkg.conflicts;
							while (depends_list != null) {
								string depstring = depends_list.data.compute_string ();
								Alpm.List<unowned Alpm.Package> list = null;
								list.add (trans_pkg);
								if (Alpm.find_satisfier (list, depstring) != null) {
									pkg.conflicts.add (add_pkg.name);
									conflict_found = true;
									break;
								}
								depends_list.next ();
							}
							pkgs_to_add.next ();
						}
					}
					// Add it in a separate list because it could be a aur conflict
					// that must not be explicilty removed.
					summary.conflicts_to_remove.add (pkg);
				}
				pkgs_to_remove.next ();
			}
			return summary;
		}

		void download_files (Alpm.Handle? handle, uint64 max_parallel_downloads, bool emit_signals) {
			// create the table of async queues
			// one queue per repo with files to download
			total_download = 0;
			var to_download = new GenericArray<unowned Alpm.Package> ();
			unowned Alpm.List<unowned Alpm.Package> pkgs_to_add = handle.trans_to_add ();
			while (pkgs_to_add != null) {
				unowned Alpm.Package trans_pkg = pkgs_to_add.data;
				uint64 download_size = trans_pkg.download_size;
				if (download_size > 0) {
					total_download += trans_pkg.download_size;
					to_download.add (trans_pkg);
				}
				pkgs_to_add.next ();
			}
			if (total_download == 0) {
				return;
			}
			if (emit_signals) {
				emit_totaldownload (total_download);
				emit_event (Alpm.Event.Type.RETRIEVE_START, 0, {});
				current_filename = "";
			}
			// create a thread pool which will download files
			try {
				var dload_thread_pool = new ThreadPool<Download>.with_owned_data (
					// call alpm_action.run () on thread start
					(download) => {
						download.run ();
					},
					// max simultaneous threads = max simultaneous downloads
					(int) max_parallel_downloads,
					// exclusive threads
					true
				);
				unowned string cachedir = handle.cachedirs.nth (0).data;
				foreach (unowned Alpm.Package pkg in to_download) {
					dload_thread_pool.add (new Download (cachedir, pkg, emit_signals));
				}
				// wait for all thread to finish
				ThreadPool.free ((owned) dload_thread_pool, false, true);
			} catch (ThreadError e) {
				warning (e.message);
			}
			if (emit_signals) {
				emit_event (Alpm.Event.Type.RETRIEVE_DONE, 0, {});
				emit_totaldownload (0);
			}
		}

		bool need_reboot (Alpm.Handle? alpm_handle) {
			bool reboot_needed = false;
			string[] prefix = {"linux-", "nvidia-", "lib32-nvidia-", "systemd", "xf86-", "xorg-"};
			string[] contains = {"mesa", "wayland"};
			string[] full = {"cryptsetup"};
			string[] suffix = {"-ucode"};
			unowned Alpm.List<unowned Alpm.Package> to_add = alpm_handle.trans_to_add ();
			while (to_add != null) {
				unowned Alpm.Package pkg = to_add.data;
				foreach (unowned string str in prefix) {
					if (pkg.name.has_prefix (str)) {
						reboot_needed = true;
						break;
					}
				}
				if (reboot_needed) {
					break;
				}
				foreach (unowned string str in contains) {
					if (str in pkg.name) {
						reboot_needed = true;
						break;
					}
				}
				if (reboot_needed) {
					break;
				}
				foreach (unowned string str in full) {
					if (str == pkg.name) {
						reboot_needed = true;
						break;
					}
				}
				if (reboot_needed) {
					break;
				}
				foreach (unowned string str in suffix) {
					if (pkg.name.has_suffix (str)) {
						reboot_needed = true;
						break;
					}
				}
				if (reboot_needed) {
					break;
				}
				to_add.next ();
			}
			return reboot_needed;
		}

		bool trans_commit (Alpm.Handle? alpm_handle) {
			add_overwrite_files (alpm_handle);
			bool need_retry = false;
			bool success = false;
			bool reboot_needed = false;
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
						// check if reboot needed
						reboot_needed = need_reboot (alpm_handle);
						success = trans_commit_real (alpm_handle, ref need_retry);
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
							if (success && alpm_handle.trans_to_add () == null && alpm_handle.trans_to_remove () == null) {
								trans_release (alpm_handle);
								trans_reset ();
								return true;
							}
						}
						if (!success) {
							trans_release (alpm_handle);
						}
					} else if (need_retry) {
						// retry
						if (commit_retries < 1) {
							commit_retries++;
							success = trans_run_real ();
						}
					}
				}
				if (!success) {
					trans_reset ();
					return false;
				}
			}
			if (!reboot_needed) {
				// check if reboot needed
				reboot_needed = need_reboot (alpm_handle);
			}
			success = trans_commit_real (alpm_handle, ref need_retry);
			if (success) {
				foreach (unowned string path in to_load) {
					// check tarball if it's a built package
					// check for "/var/tmp/pamac-build" because
					// default aur_build_dir is "/var/tmp/pamac-build-root" here
					// if a custom PKGDEST is set in makepkg.conf, package won't be moved or deleted
					if (path.has_prefix ("/var/tmp/pamac-build")
						|| path.has_prefix ("/tmp/pamac-build")
						|| path.has_prefix (config.aur_build_dir)) {
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
				if (reboot_needed) {
					do_emit_warning (dgettext (null, "A restart is required for the changes to take effect") + ".");
				}
			} else if (need_retry) {
				// retry
				if (commit_retries < 1) {
					commit_retries++;
					success = trans_run_real ();
				}
			}
			trans_reset ();
			return success;
		}

		string? backup_conflict_file (string file_path) {
			var backup_file_path = new StringBuilder (file_path);
			backup_file_path.append (".old");
			var backup_file = File.new_for_path (backup_file_path.str);
			if (backup_file.query_exists ()) {
				uint i = 0;
				do {
					i++;
					var new_backup_file_path = new StringBuilder (backup_file_path.str);
					new_backup_file_path.append ("%u".printf (i));
					backup_file = File.new_for_path (new_backup_file_path.str);
				} while (backup_file.query_exists ());
			}
			// mv the conflict file
			try {
				Process.spawn_command_line_sync ("mv -f %s %s".printf (file_path, backup_file.get_path ()));
				return backup_file.get_path ();
			} catch (SpawnError e) {
				warning (e.message);
			}
			return null;
		}

		bool trans_commit_real (Alpm.Handle? alpm_handle, ref bool need_retry) {
			bool success = true;
			if (config.max_parallel_downloads >= 2) {
				// custom parallel downloads
				download_files (alpm_handle, config.max_parallel_downloads, true);
				if (cancellable.is_cancelled ()) {
					trans_release (alpm_handle);
					do_emit_script_output ("");
					do_emit_action (dgettext (null, "Transaction cancelled") + ".");
					return false;
				}
			}
			// real commit
			Alpm.List err_data;
			if (alpm_handle.trans_commit (out err_data) == -1) {
				Alpm.Errno err_no = alpm_handle.errno ();
				// cancel the download return an EXTERNAL_DOWNLOAD error
				if (err_no == Alpm.Errno.EXTERNAL_DOWNLOAD && cancellable.is_cancelled ()) {
					trans_release (alpm_handle);
					do_emit_script_output ("");
					do_emit_action (dgettext (null, "Transaction cancelled") + ".");
					return false;
				}
				need_retry = false;
				var details = new GenericArray<string> ();
				switch (err_no) {
					case 0:
						break;
					case Alpm.Errno.FILE_CONFLICTS:
						details.add (Alpm.strerror (err_no) + ":");
						unowned Alpm.List<Alpm.FileConflict*> list = err_data;
						while (list != null) {
							Alpm.FileConflict* conflict = list.data;
							switch (conflict->type) {
								case Alpm.FileConflict.Type.TARGET:
									details.add ("- " + _("%s exists in both %s and %s").printf (conflict->file, conflict->target, conflict->ctarget));
									break;
								case Alpm.FileConflict.Type.FILESYSTEM:
									if (conflict->ctarget.length > 0) {
										details.add ("- " + _("%s: %s already exists in filesystem (owned by %s)").printf (conflict->target, conflict->file, conflict->ctarget));
									} else {
										if (commit_retries < 1) {
											string? backup_path = backup_conflict_file (conflict->file);
											if (backup_path == null) {
												details.add ("- " + _("%s: %s already exists in filesystem").printf (conflict->target, conflict->file) + ",");
												details.add ("  " + _("if this file is not needed, remove it and retry"));
											} else {
												do_emit_warning (_("Warning") + ": " + _("%s: %s already existed in filesystem").printf (conflict->target, conflict->file));
												do_emit_warning (_("It has been backed up to %s").printf (backup_path));
												need_retry = true;
											}
										} else {
											details.add ("- " + _("%s: %s already exists in filesystem").printf (conflict->target, conflict->file) + ",");
											details.add ("  " + _("if this file is not needed, remove it and retry"));
										}
									}
									break;
							}
							delete conflict;
							list.next ();
						}
						break;
					case Alpm.Errno.PKG_INVALID_CHECKSUM:
						unowned Alpm.List<string*> list = err_data;
						if (commit_retries < 1) {
							do_emit_script_output (_("Removing invalid files and retrying") + "...");
							need_retry = true;
						} else {
							details.add (Alpm.strerror (err_no) + ":");
						}
						while (list != null) {
							string* filename = list.data;
							if (!need_retry) {
								details.add ("- " + _("%s is invalid or corrupted").printf (filename) + ",");
								details.add ("- " + _("you can remove this file and retry"));
							}
							// question cb will remove the file
							delete filename;
							list.next ();
						}
						break;
					case Alpm.Errno.PKG_INVALID:
					case Alpm.Errno.PKG_INVALID_SIG:
						if (commit_retries < 1) {
							do_emit_script_output (_("Removing invalid files and retrying") + "...");
							need_retry = true;
						} else {
							details.add (Alpm.strerror (err_no) + ":");
						}
						unowned Alpm.List<string*> list = err_data;
						while (list != null) {
							string* filename = list.data;
							if (!need_retry) {
								details.add ("- " + _("%s is invalid or corrupted").printf (filename) + ",");
								details.add ("  " + _("you can remove this file and retry"));
							} else {
								// remove the invalid file
								try {
									Process.spawn_command_line_sync ("rm -f %s".printf (filename));
								} catch (SpawnError e) {
									warning (e.message);
								}
							}
							delete filename;
							list.next ();
						}
						break;
					case Alpm.Errno.EXTERNAL_DOWNLOAD:
						details.add (_("failed to retrieve some files"));
						break;
					default:
						details.add (Alpm.strerror (err_no));
						break;
				}
				success = false;
				if (!need_retry) {
					do_emit_error (_("Failed to commit transaction"), details.data);
				}
			}
			trans_release (alpm_handle);
			return success;
		}

		void trans_release (Alpm.Handle? alpm_handle) {
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
					string msg = remove_bash_colors (details[0]).replace ("\n", "");
					do_emit_script_output (msg);
					if (current_filename != "") {
						string action = dgettext (null, "Configuring %s").printf (current_filename) + "...";
						if (action != current_action) {
							current_action = (owned) action;
						}
						//do_emit_action (current_action);
						if ("error" in msg.down ()) {
							do_emit_warning (dgettext (null, "Error while configuring %s").printf (current_filename));
							do_important_details_outpout (true);
						} else {
							do_important_details_outpout (false);
						}
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
						current_status = (owned) status;
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
				current_status = (owned) status;
				changed = true;
			}
			if (changed) {
				if (current_action != "") {
					do_emit_action_progress (current_action, current_status, current_progress);
				}
			}
		}

		public void emit_download (uint64 xfered, uint64 total) {
			// this will be run in the threadpool
			if (xfered == 0) {
				rate_timer.start ();
				if (total_download == 0) {
					download_rates.clear ();
					download_rate = 0;
				}
			}
			var text = new StringBuilder ("%s".printf (format_size (xfered)));
			// if previous progress is out of limit no need to continue
			if (current_progress < 1) {
				double fraction = (double) xfered / total;
				if (fraction <= 1) {
					text.append ("/%s".printf (format_size (total)));
					double elapsed = rate_timer.elapsed ();
					if (elapsed > 1) {
						double current_rate = (xfered - already_downloaded) / elapsed;
						already_downloaded = xfered;
						// only keep the last 10 rates
						if (download_rates.length > 10) {
							download_rates.pop_head ();
						}
						download_rates.push_tail (current_rate);
						if (xfered == total) {
							rate_timer.stop ();
						} else {
							// reinitialize rate_timer
							rate_timer.start ();
						}
						// calculate download on the last 10 rates
						if (download_rates.length == 10) {
							double total_rates = 0;
							foreach (double previous_rate in download_rates.head) {
								total_rates += previous_rate;
							}
							download_rate = total_rates /10;
						}
					}
					if (download_rate > 0) {
						uint remaining_seconds = (uint) Math.round ((total - xfered) / download_rate);
						// display remaining
						text.append (" ");
						if (remaining_seconds > 0) {
							if (remaining_seconds < 60) {
								text.append (dngettext (null, "About %lu second remaining",
											"About %lu seconds remaining", remaining_seconds).printf (remaining_seconds));
							} else {
								uint remaining_minutes = (uint) Math.round (remaining_seconds / 60);
								text.append (dngettext (null, "About %lu minute remaining",
											"About %lu minutes remaining", remaining_minutes).printf (remaining_minutes));
							}
						}
					}
				} else {
					fraction = 1;
					// rate_timer no more needed
					rate_timer.stop ();
				}
				if (fraction != current_progress) {
					current_progress = fraction;
				}
			}
			if (text.str != current_status) {
				current_status = (owned) text.str;
			}
			do_emit_download_progress (current_action, current_status, current_progress);
		}

		public void emit_totaldownload (uint64 total) {
			// this is emitted at the end of the total download with the value 0
			if (total == 0) {
				current_filename = "";
				multi_progress_mutex.lock ();
				multi_progress.remove_all ();
				multi_progress_mutex.unlock ();
			}
			download_rates.clear ();
			download_rate = 0;
			current_progress = 0;
			already_downloaded = 0;
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
				do_emit_script_output (line.replace ("\n", ""));
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
	var file = File.new_for_path ("/var/log/pacman.log");
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
	var details = new GenericArray<string> ();
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
			details.add (data.hook_run_name);
			details.add (data.hook_run_desc ?? "");
			details.add (data.hook_run_position.to_string ());
			details.add (data.hook_run_total.to_string ());
			break;
		case Alpm.Event.Type.PACKAGE_OPERATION_START:
			switch (data.package_operation_operation) {
				case Alpm.Package.Operation.REMOVE:
					details.add (data.package_operation_oldpkg.name);
					details.add (data.package_operation_oldpkg.version);
					secondary_type = (uint) Alpm.Package.Operation.REMOVE;
					break;
				case Alpm.Package.Operation.INSTALL:
					details.add (data.package_operation_newpkg.name);
					details.add (data.package_operation_newpkg.version);
					secondary_type = (uint) Alpm.Package.Operation.INSTALL;
					break;
				case Alpm.Package.Operation.REINSTALL:
					details.add (data.package_operation_newpkg.name);
					details.add (data.package_operation_newpkg.version);
					secondary_type = (uint) Alpm.Package.Operation.REINSTALL;
					break;
				case Alpm.Package.Operation.UPGRADE:
					details.add (data.package_operation_oldpkg.name);
					details.add (data.package_operation_oldpkg.version);
					details.add (data.package_operation_newpkg.version);
					secondary_type = (uint) Alpm.Package.Operation.UPGRADE;
					break;
				case Alpm.Package.Operation.DOWNGRADE:
					details.add (data.package_operation_oldpkg.name);
					details.add (data.package_operation_oldpkg.version);
					details.add (data.package_operation_newpkg.version);
					secondary_type = (uint) Alpm.Package.Operation.DOWNGRADE;
					break;
				default:
					break;
			}
			break;
		case Alpm.Event.Type.SCRIPTLET_INFO:
			details.add (data.scriptlet_info_line);
			break;
		case Alpm.Event.Type.PKGDOWNLOAD_START:
			// do not emit event when download is cancelled
			if (alpm_utils.cancellable.is_cancelled ()) {
				return;
			}
			details.add (data.pkgdownload_file);
			break;
		case Alpm.Event.Type.OPTDEP_REMOVAL:
			details.add (data.optdep_removal_pkg.name);
			details.add (data.optdep_removal_optdep.compute_string ());
			break;
		case Alpm.Event.Type.DATABASE_MISSING:
			details.add (data.database_missing_dbname);
			break;
		case Alpm.Event.Type.PACNEW_CREATED:
			details.add (data.pacnew_created_file);
			break;
		case Alpm.Event.Type.PACSAVE_CREATED:
			details.add (data.pacsave_created_file);
			break;
		default:
			break;
	}
	alpm_utils.emit_event ((uint) data.type, secondary_type, details.data);
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
			var providers_str = new GenericArray<string> ();
			unowned Alpm.List<unowned Alpm.Package> list = data.select_provider_providers;
			while (list != null) {
				unowned Alpm.Package pkg = list.data;
				providers_str.add (pkg.name);
				list.next ();
			}
			data.select_provider_use_index = alpm_utils.do_choose_provider (depend_str, providers_str.data);
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
	alpm_utils.emit_progress ((uint) progress, pkgname, (uint) percent, n_targets, current_target);
}

void compute_multi_download_progress () {
	// this will be run in the threadpool
	// multi_progress_mutex already locked
	uint64 total_progress = 0;
	var iter = HashTableIter<string, uint64?> (multi_progress);
	uint64? progress;
	while (iter.next (null, out progress)) {
		total_progress += progress;
	}
	alpm_utils.emit_download (total_progress, total_download);
}

void cb_download (string filename, uint64 xfered, uint64 total) {
	// this will be run in the threadpool
	if (total_download == 0) {
		alpm_utils.emit_download (xfered, total);
	} else {
		multi_progress_mutex.lock ();
		multi_progress.insert (filename, xfered);
		compute_multi_download_progress ();
		multi_progress_mutex.unlock ();
	}
}

int cb_fetch (string fileurl, string localpath, int force) {
	string mirror =  Path.get_dirname (fileurl);
	current_filename = Path.get_basename (fileurl);
	int ret = dload (mirror, current_filename, localpath, force, false, true);
	already_downloaded = 0;
	current_progress = 0;
	if (total_download == 0) {
		multi_progress_mutex.lock ();
		multi_progress.remove_all ();
		multi_progress_mutex.unlock ();
	}
	return ret;
}

int dload (string mirror, string filename, string localpath, int force, bool parallel, bool emit_signals) {
	if (alpm_utils.cancellable.is_cancelled ()) {
		return -1;
	}

	string url =  Path.build_filename (mirror, filename);
	var destfile = File.new_for_path (Path.build_filename (localpath, filename));
	var tempfile = File.new_for_path (destfile.get_path () + ".part");
	string name = "";
	string version_release = "";

	bool remove_partial_download = true;
	if (url.contains (".pkg.tar.") && !url.has_suffix (".sig")) {
		remove_partial_download = false;
	}

	int64 size = 0;
	string? last_modified = null;
	bool continue_download = false;
	var emit_timer = new Timer ();
	try {
		InputStream input;
		if (url.has_prefix ("http")) {
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
					// try if removing partial download support helps
					tempfile.delete ();
					// a previous partial download exists, resume from end of file.
					//FileInfo info = tempfile.query_info (FileAttribute.STANDARD_SIZE, FileQueryInfoFlags.NONE);
					//int64 downloaded_size = info.get_size ();
					//message.request_headers.set_range (downloaded_size, -1);
					//continue_download = true;
				}
			} else {
				if (tempfile.query_exists ()) {
					tempfile.delete ();
				}
			}

			input = alpm_utils.soup_session.send (message);
			if (message.status_code == 304) {
				// not modified, our existing file is up to date
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
		} else {
			// try standard file support for file:// url
			var file = File.new_for_uri (url);
			FileInfo new_info = file.query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
			DateTime new_time = new_info.get_modification_date_time ();
			last_modified = new_time.format_iso8601 ();
			if (force == 0) {
				if (destfile.query_exists ()) {
					// start from scratch only download if our local is out of date.
					FileInfo old_info = destfile.query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
					DateTime old_time = old_info.get_modification_date_time ();
					TimeSpan elapsed_time = new_time.difference (old_time);
					if (elapsed_time <= 0) {
						// not modified, our existing file is up to date
						return 1;
					}
					if (tempfile.query_exists ()) {
						tempfile.delete ();
					}
				} else if (tempfile.query_exists ()) {
					// don't support partial donwload here
					tempfile.delete ();
				}
			} else {
				if (tempfile.query_exists ()) {
					tempfile.delete ();
				}
			}
			input = file.read ();
		}

		FileOutputStream output;
		if (continue_download) {
			output = tempfile.append_to (FileCreateFlags.NONE);
		} else {
			output = tempfile.create (FileCreateFlags.NONE);
		}

		uint64 progress = 0;
		uint8[] buf = new uint8[8192];
		// start download
		if (emit_signals) {
			if (filename.has_suffix (".db") || filename.has_suffix (".files")) {
				string filename_copy = filename;
				multi_progress_mutex.lock ();
				current_action = _("Refreshing %s").printf (filename_copy) + "...";
				multi_progress_mutex.unlock ();
			} else {
				// compute name and version_release
				string? name_version_release = filename.slice (0, filename.last_index_of_char ('-'));
				if (name_version_release != null) {
					string? name_version = name_version_release.slice (0, name_version_release.last_index_of_char ('-'));
					if (name_version != null) {
						int version_index = name_version.last_index_of_char ('-');
						string? tmp_name = name_version.slice (0, version_index);
						if (tmp_name != null) {
							name = tmp_name;
							string? tmp_version_release = name_version_release.slice (version_index + 1, name_version_release.length);
							if (tmp_version_release != null) {
								version_release = tmp_version_release;
								multi_progress_mutex.lock ();
								if (parallel) {
									current_action = _("Download of %s started").printf ("%s (%s)".printf (name, version_release));
								} else {
									current_action = _("Downloading %s").printf ("%s (%s)".printf (name, version_release)) + "...";
								}
								multi_progress_mutex.unlock ();
							}
						}
					}
				}
			}
			cb_download (filename, 0, size);
		}
		if (emit_signals) {
			emit_timer.start ();
		}
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
			if (emit_signals && emit_timer.elapsed () > 0.1) {
				cb_download (filename, progress, size);
				// reinitialize emit_timer
				emit_timer.start ();
			}
		}
	} catch (Error e) {
		// cancelled download goes here
		if (e.code != IOError.CANCELLED) {
			alpm_utils.do_emit_script_output ("%s: %s".printf (url, e.message));
		}
		emit_timer.stop ();
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
	if (emit_signals) {
		emit_timer.stop ();
		if (parallel && name != "" && version_release != "") {
			multi_progress_mutex.lock ();
			current_action = _("Download of %s finished").printf ("%s (%s)".printf (name, version_release));
			multi_progress_mutex.unlock ();
		}
		cb_download (filename, size, size);
	}
	try {
		tempfile.move (destfile, FileCopyFlags.OVERWRITE);
		// set modification time
		if (last_modified != null) {
			string time_str = new Soup.Date.from_string (last_modified).to_string (Soup.DateFormat.ISO8601);
			var datetime = new DateTime.from_iso8601 (time_str, new TimeZone.utc ());
			FileInfo info = destfile.query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
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
