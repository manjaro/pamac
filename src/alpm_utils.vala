/*
 *  pamac-vala
 *
 *  Copyright (C) 2018 Guillaume Benoit <guillaume@manjaro.org>
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

namespace Pamac {
	internal class AlpmUtils: Object {
		Config config;
		internal AlpmConfig alpm_config;
		internal Alpm.Handle? alpm_handle;
		internal Alpm.Handle? files_handle;
		internal string tmp_path;
		internal Cond provider_cond;
		internal Mutex provider_mutex;
		internal int? choosen_provider;
		internal bool force_refresh;
		internal bool enable_downgrade;
		internal int flags;
		string[] to_syncfirst;
		internal string[] to_install;
		internal string[] to_remove;
		internal string[] to_load;
		internal string[] to_build;
		internal bool sysupgrade;
		AURPackageStruct[] to_build_pkgs;
		GLib.List<string> aur_pkgbases_to_build;
		HashTable<string, string> to_install_as_dep;
		internal string[] temporary_ignorepkgs;
		internal string[] overwrite_files;
		PackageStruct[] aur_conflicts_to_remove;
		internal ErrorInfos current_error;
		internal Timer timer;
		internal Cancellable cancellable;
		internal Curl.Easy curl;
		internal bool downloading_updates;

		public signal void emit_event (uint primary_event, uint secondary_event, string[] details);
		public signal void emit_providers (string depend, string[] providers);
		public signal void emit_unresolvables (string[] unresolvables);
		public signal void emit_progress (uint progress, string pkgname, uint percent, uint n_targets, uint current_target);
		public signal void emit_download (string filename, uint64 xfered, uint64 total);
		public signal void emit_totaldownload (uint64 total);
		public signal void emit_log (uint level, string msg);
		public signal void refresh_finished (bool success);
		public signal void emit_get_updates_progress (uint percent);
		public signal void downloading_updates_finished ();
		public signal void trans_prepare_finished (bool success);
		public signal void trans_commit_finished (bool success);

		public AlpmUtils (Config config) {
			this.config = config;
			alpm_config = new AlpmConfig ("/etc/pacman.conf");
			tmp_path = "/tmp/pamac";
			aur_pkgbases_to_build = new GLib.List<string> ();
			to_install_as_dep = new HashTable<string, string> (str_hash, str_equal);
			timer = new Timer ();
			current_error = ErrorInfos ();
			refresh_handle ();
			cancellable = new Cancellable ();
			curl = new Curl.Easy ();
			downloading_updates = false;
			Curl.global_init (Curl.GLOBAL_SSL);
		}

		~AlpmUtils () {
			Curl.global_cleanup ();
		}

		internal void refresh_handle () {
			alpm_config = new AlpmConfig ("/etc/pacman.conf");
			alpm_handle = alpm_config.get_handle ();
			if (alpm_handle == null) {
				current_error = ErrorInfos () {
					message = _("Failed to initialize alpm library")
				};
				trans_commit_finished (false);
				return;
			} else {
				alpm_handle.eventcb = (Alpm.EventCallBack) cb_event;
				alpm_handle.progresscb = (Alpm.ProgressCallBack) cb_progress;
				alpm_handle.questioncb = (Alpm.QuestionCallBack) cb_question;
				alpm_handle.fetchcb = (Alpm.FetchCallBack) cb_fetch;
				alpm_handle.totaldlcb = (Alpm.TotalDownloadCallBack) cb_totaldownload;
				alpm_handle.logcb = (Alpm.LogCallBack) cb_log;
				files_handle = alpm_config.get_handle (true);
				files_handle.eventcb = (Alpm.EventCallBack) cb_event;
				files_handle.progresscb = (Alpm.ProgressCallBack) cb_progress;
				files_handle.questioncb = (Alpm.QuestionCallBack) cb_question;
				files_handle.fetchcb = (Alpm.FetchCallBack) cb_fetch;
				files_handle.totaldlcb = (Alpm.TotalDownloadCallBack) cb_totaldownload;
				files_handle.logcb = (Alpm.LogCallBack) cb_log;
			}
		}

		internal void set_pkgreason (string pkgname, uint reason) {
			unowned Alpm.Package? pkg = alpm_handle.localdb.get_pkg (pkgname);
			if (pkg != null) {
				// lock the database
				if (alpm_handle.trans_init (0) == 0) {
					pkg.reason = (Alpm.Package.Reason) reason;
					alpm_handle.trans_release ();
				}
			}
		}

		unowned Alpm.Package? get_syncpkg (string name) {
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

		bool update_dbs (Alpm.Handle handle, int force) {
			bool success = false;
			unowned Alpm.List<unowned Alpm.DB> syncdbs = handle.syncdbs;
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
					Alpm.Errno errno = handle.errno ();
					if (errno != 0) {
						// download error details are set in cb_fetch
						if (errno != Alpm.Errno.EXTERNAL_DOWNLOAD) {
							current_error.details = { Alpm.strerror (errno) };
						}
					}
				}
				syncdbs.next ();
			}
			return success;
		}

		internal void refresh () {
			current_error = ErrorInfos ();
			write_log_file ("synchronizing package lists");
			cancellable.reset ();
			int force = (force_refresh) ? 1 : 0;
			if (force_refresh) {
				// remove dbs in tmp
				try {
					Process.spawn_command_line_sync ("bash -c 'rm -rf %s/dbs*'".printf (tmp_path));
				} catch (SpawnError e) {
					stderr.printf ("SpawnError: %s\n", e.message);
				}
			} else {
				// try to copy refresh dbs in tmp
				var file = GLib.File.new_for_path (tmp_path);
				if (file.query_exists ()) {
					try {
						Process.spawn_command_line_sync ("bash -c 'cp -u %s/dbs*/sync/*.{db,files} %ssync'".printf (tmp_path, alpm_handle.dbpath));
					} catch (SpawnError e) {
						stderr.printf ("SpawnError: %s\n", e.message);
					}
				}
				// a new handle is required to use copied databases
				refresh_handle ();
			}
			// update ".db"
			bool success = update_dbs (alpm_handle, force);
			if (cancellable.is_cancelled ()) {
				refresh_finished (false);
				return;
			}
			// only refresh ".files" if force
			if (force_refresh) {
				// update ".files", do not need to know if we succeeded
				update_dbs (files_handle, force);
			}
			if (cancellable.is_cancelled ()) {
				refresh_finished (false);
			} else if (success) {
				refresh_finished (true);
			} else {
				current_error.message = _("Failed to synchronize any databases");
				refresh_finished (false);
			}
		}

		void add_ignorepkgs () {
			foreach (unowned string pkgname in temporary_ignorepkgs) {
				alpm_handle.add_ignorepkg (pkgname);
			}
		}

		void remove_ignorepkgs () {
			foreach (unowned string pkgname in temporary_ignorepkgs) {
				alpm_handle.remove_ignorepkg (pkgname);
			}
		}

		void add_overwrite_files () {
			foreach (unowned string name in overwrite_files) {
				alpm_handle.add_overwrite_file (name);
			}
		}

		void remove_overwrite_files () {
			foreach (unowned string name in overwrite_files) {
				alpm_handle.remove_overwrite_file (name);
			}
		}

		PackageStruct initialise_pkg_struct (Alpm.Package? alpm_pkg) {
			if (alpm_pkg != null) {
				string installed_version = "";
				string repo_name = "";
				string desc = alpm_pkg.desc ?? "";
				if (alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
					installed_version = alpm_pkg.version;
					unowned Alpm.Package? sync_pkg = get_syncpkg (alpm_pkg.name);
					if (sync_pkg != null) {
						repo_name = sync_pkg.db.name;
					}
				} else if (alpm_pkg.origin == Alpm.Package.From.SYNCDB) {
					unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (alpm_pkg.name);
					if (local_pkg != null) {
						installed_version = local_pkg.version;
					}
					repo_name = alpm_pkg.db.name;
				} else {
					// load pkg or built pkg
					unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (alpm_pkg.name);
					if (local_pkg != null) {
						installed_version = local_pkg.version;
					}
				}
				return PackageStruct () {
					name = alpm_pkg.name,
					app_name = "",
					version = alpm_pkg.version,
					installed_version = (owned) installed_version,
					desc = (owned) desc,
					repo = (owned) repo_name,
					size = alpm_pkg.isize,
					download_size = alpm_pkg.download_size,
					icon = ""
				};
			} else {
				return PackageStruct () {
					name = "",
					app_name = "",
					version = "",
					installed_version = "",
					desc = "",
					repo = "",
					icon = ""
				};
			}
		}

		internal int download_updates () {
			downloading_updates = true;
			// use tmp handle
			var handle = alpm_config.get_handle (false, true);
			handle.fetchcb = (Alpm.FetchCallBack) cb_fetch;
			cancellable.reset ();
			int success = handle.trans_init (Alpm.TransFlag.DOWNLOADONLY);
			// can't add nolock flag with commit so remove unneeded lock
			handle.unlock ();
			if (success == 0) {
				success = handle.trans_sysupgrade (0);
				if (success == 0) {
					Alpm.List err_data;
					success = handle.trans_prepare (out err_data);
					if (success == 0) {
						success = handle.trans_commit (out err_data);
					}
				}
				handle.trans_release ();
			}
			downloading_updates = false;
			downloading_updates_finished ();
			return success;
		}

		bool trans_init (int flags) {
			current_error = ErrorInfos ();
			cancellable.reset ();
			if (alpm_handle.trans_init ((Alpm.TransFlag) flags) == -1) {
				Alpm.Errno errno = alpm_handle.errno ();
				current_error.message = _("Failed to init transaction");
				if (errno != 0) {
					current_error.details = { Alpm.strerror (errno) };
				}
				return false;
			}
			return true;
		}

		bool trans_sysupgrade () {
			current_error = ErrorInfos ();
			add_ignorepkgs ();
			if (alpm_handle.trans_sysupgrade ((enable_downgrade) ? 1 : 0) == -1) {
				Alpm.Errno errno = alpm_handle.errno ();
				current_error.message = _("Failed to prepare transaction");
				if (errno != 0) {
					current_error.details = { Alpm.strerror (errno) };
				}
				return false;
			}
			// check syncfirsts
			to_syncfirst = {};
			foreach (unowned string name in alpm_config.get_syncfirsts ()) {
				unowned Alpm.Package? pkg = Alpm.find_satisfier (alpm_handle.localdb.pkgcache, name);
				if (pkg != null) {
					unowned Alpm.Package? candidate = pkg.sync_newversion (alpm_handle.syncdbs);
					if (candidate != null) {
						to_syncfirst += candidate.name;
					}
				}
			}
			return true;
		}

		bool trans_add_pkg_real (Alpm.Package pkg) {
			current_error = ErrorInfos ();
			if (alpm_handle.trans_add_pkg (pkg) == -1) {
				Alpm.Errno errno = alpm_handle.errno ();
				if (errno == Alpm.Errno.TRANS_DUP_TARGET || errno == Alpm.Errno.PKG_IGNORED) {
					// just skip duplicate or ignored targets
					return true;
				} else {
					current_error.message = _("Failed to prepare transaction");
					if (errno != 0) {
						current_error.details = { "%s: %s".printf (pkg.name, Alpm.strerror (errno)) };
					}
					return false;
				}
			}
			return true;
		}

		bool trans_add_pkg (string pkgname) {
			current_error = ErrorInfos ();
			unowned Alpm.Package? pkg = alpm_handle.find_dbs_satisfier (alpm_handle.syncdbs, pkgname);
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
								unowned Alpm.Package? installed_module_pkg = alpm_handle.localdb.get_pkg (module);
								if (installed_module_pkg == null) {
									unowned Alpm.Package? module_pkg = get_syncpkg (module);
									if (module_pkg != null) {
										trans_add_pkg_real (module_pkg);
									}
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

		string? download_pkg (string url) {
			// need to call the function twice in order to have the return path
			// it's due to the use of a fetch callback
			// first call to download pkg
			alpm_handle.fetch_pkgurl (url);
			// check for error
			if (current_error.details.length > 0) {
				return null;
			}
			if ((alpm_handle.remotefilesiglevel & Alpm.Signature.Level.PACKAGE) == 1) {
				// try to download signature
				alpm_handle.fetch_pkgurl (url + ".sig");
			}
			return alpm_handle.fetch_pkgurl (url);
		}

		bool trans_load_pkg (string path) {
			current_error = ErrorInfos ();
			Alpm.Package* pkg;
			int siglevel = alpm_handle.localfilesiglevel;
			string? pkgpath = path;
			// download pkg if an url is given
			if ("://" in path) {
				siglevel = alpm_handle.remotefilesiglevel;
				pkgpath = download_pkg (path);
				if (pkgpath == null) {
					return false;
				}
			}
			// load tarball
			if (alpm_handle.load_tarball (pkgpath, 1, siglevel, out pkg) == -1) {
				Alpm.Errno errno = alpm_handle.errno ();
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

		bool trans_remove_pkg (string pkgname) {
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
					current_error.message = _("Failed to prepare transaction");
					if (errno != 0) {
						current_error.details = { "%s: %s".printf (pkg.name, Alpm.strerror (errno)) };
					}
					return false;
				}
			}
			return true;
		}

		bool trans_prepare_real () {
			bool success = true;
			current_error = ErrorInfos ();
			string[] details = {};
			Alpm.List err_data;
			if (alpm_handle.trans_prepare (out err_data) == -1) {
				Alpm.Errno errno = alpm_handle.errno ();
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
								detail = _("unable to satisfy dependency '%s' required by %s").printf (depstring, miss->target);
							} else if ((pkg = Alpm.pkg_find (trans_add, miss->causingpkg)) != null) {
								/* upgrading a package breaks a local dependency */
								detail = _("installing %s (%s) breaks dependency '%s' required by %s").printf (miss->causingpkg, pkg.version, depstring, miss->target);
							} else {
								/* removing a package breaks a local dependency */
								detail = _("removing %s breaks dependency '%s' required by %s").printf (miss->causingpkg, depstring, miss->target);
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

		internal void trans_prepare () {
			to_build_pkgs = {};
			aur_pkgbases_to_build = new GLib.List<string> ();
			to_install_as_dep.remove_all ();
			launch_trans_prepare_real ();
		}

		void launch_trans_prepare_real () {
			bool success = trans_init (flags);
			// check if you add upgrades to transaction
			if (success) {
				if (!sysupgrade && to_install.length > 0) {
					foreach (unowned string name in to_install) {
						unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (name);
						if (local_pkg == null) {
							sysupgrade = true;
							break;
						} else {
							unowned Alpm.Package? sync_pkg = get_syncpkg (name);
							if (sync_pkg != null) {
								if (local_pkg.version != sync_pkg.version) {
									sysupgrade = true;
									break;
								}
							}
						}
					}
				}
				if (sysupgrade) {
					success = trans_sysupgrade ();
				}
			}
			if (success) {
				foreach (unowned string name in to_install) {
					success = trans_add_pkg (name);
					if (!success) {
						break;
					}
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
			trans_prepare_finished (success);
		}

		internal void build_prepare () {
			to_build_pkgs = {};
			aur_pkgbases_to_build = new GLib.List<string> ();
			to_install_as_dep.remove_all ();
			// get an handle with fake aur db and without emit signal callbacks
			alpm_handle = alpm_config.get_handle ();
			if (alpm_handle == null) {
				current_error = ErrorInfos () {
					message = _("Failed to initialize alpm library")
				};
				trans_commit_finished (false);
			} else {
				alpm_handle.questioncb = (Alpm.QuestionCallBack) cb_question;
				// emit warnings here
				alpm_handle.logcb = (Alpm.LogCallBack) cb_log;
				// fake aur db
				try {
					Process.spawn_command_line_sync ("cp %s/aur.db %ssync".printf (tmp_path, alpm_handle.dbpath));
				} catch (SpawnError e) {
					stderr.printf ("SpawnError: %s\n", e.message);
				}
				alpm_handle.register_syncdb ("aur", 0);
				// add to_build in to_install for the fake trans prepare
				foreach (unowned string name in to_build) {
					to_install += name;
					// check if we need to remove debug package to avoid dep problem
					string debug_pkg_name = "%s-debug".printf (name);
					if (alpm_handle.localdb.get_pkg (debug_pkg_name) != null) {
						to_remove += debug_pkg_name;
					}
				}
				// base-devel group is needed to build pkgs
				var backup_to_remove = new GenericSet<string?> (str_hash, str_equal);
				foreach (unowned string name in to_remove) {
					backup_to_remove.add (name);
				}
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
									to_install += pkg.name;
								} else {
									// remove the needed pkg from to_remove
									backup_to_remove.remove (pkg.name);
								}
								packages.next ();
							}
						}
						break;
					}
					syncdbs.next ();
				}
				// git is needed to build pkgs
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
										if (aur_pkgbases_to_build.find_custom (trans_pkg.pkgbase, strcmp) == null) {
											aur_pkgbases_to_build.append (trans_pkg.pkgbase);
										}
										to_build_pkgs += AURPackageStruct () {
											name = trans_pkg.name,
											version = trans_pkg.version,
											installed_version = "",
											desc = "",
											packagebase = "",
											outofdate = ""
										};
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
									aur_conflicts_to_remove += initialise_pkg_struct (trans_pkg);
								}
								pkgs_to_remove.next ();
							}
							trans_release ();
							// get standard handle
							refresh_handle ();
							// warnings already emitted
							alpm_handle.logcb = null;
							// launch standard prepare
							to_install = real_to_install;
							launch_trans_prepare_real ();
							alpm_handle.logcb = (Alpm.LogCallBack) cb_log;
						}
					}
					if (!success) {
						trans_release ();
					}
				}
				try {
					Process.spawn_command_line_sync ("rm -f %ssync/aur.db".printf (alpm_handle.dbpath));
				} catch (SpawnError e) {
					stderr.printf ("SpawnError: %s\n", e.message);
				}
				if (!success) {
					// get standard handle
					refresh_handle ();
					trans_prepare_finished (false);
				}
			}
		}

		internal void choose_provider (int provider) {
			provider_mutex.lock ();
			choosen_provider = provider;
			provider_cond.signal ();
			provider_mutex.unlock ();
		}

		internal TransactionSummaryStruct get_transaction_summary () {
			PackageStruct[] to_install = {};
			PackageStruct[] to_upgrade = {};
			PackageStruct[] to_downgrade = {};
			PackageStruct[] to_reinstall = {};
			PackageStruct[] to_remove = {};
			unowned Alpm.List<unowned Alpm.Package> pkgs_to_add = alpm_handle.trans_to_add ();
			while (pkgs_to_add != null) {
				unowned Alpm.Package trans_pkg = pkgs_to_add.data;
				var infos = initialise_pkg_struct (trans_pkg);
				if (infos.installed_version == "") {
					to_install += (owned) infos;
				} else {
					int cmp = Alpm.pkg_vercmp (infos.version, infos.installed_version);
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
				to_remove += initialise_pkg_struct (trans_pkg);
				pkgs_to_remove.next ();
			}
			PackageStruct[] conflicts_to_remove = {};
			foreach (unowned PackageStruct pkg in aur_conflicts_to_remove){
				conflicts_to_remove += pkg;
			}
			aur_conflicts_to_remove = {};
			string[] pkgbases_to_build = {};
			foreach (unowned string name in aur_pkgbases_to_build) {
				pkgbases_to_build += name;
			}
			var summary = TransactionSummaryStruct () {
				to_install = (owned) to_install,
				to_upgrade = (owned) to_upgrade,
				to_downgrade = (owned) to_downgrade,
				to_reinstall = (owned) to_reinstall,
				to_remove = (owned) to_remove,
				to_build = to_build_pkgs,
				aur_conflicts_to_remove = (owned) conflicts_to_remove,
				aur_pkgbases_to_build = (owned) pkgbases_to_build
			};
			return summary;
		}

		internal void trans_commit () {
			add_overwrite_files ();
			bool success = false;
			if (to_syncfirst.length > 0) {
				trans_release ();
				success = trans_init (flags);
				if (success) {
					foreach (unowned string name in to_syncfirst) {
						success = trans_add_pkg (name);
						if (!success) {
							break;
						}
					}
					if (success) {
						success = trans_prepare_real ();
					}
					if (success) {
						success = trans_commit_real ();
					}
					trans_release ();
					if (success) {
						// remove syncfirsts from to_install
						string[] to_install_backup = to_install;
						to_install = {};
						foreach (unowned string name in to_install_backup) {
							if (!(name in to_syncfirst)) {
								to_install += name;
							}
						}
						success = trans_init (flags);
						if (success && sysupgrade) {
							success = trans_sysupgrade ();
						}
						if (success) {
							foreach (unowned string name in to_install) {
								success = trans_add_pkg (name);
								if (!success) {
									break;
								}
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
							// continue if needed
							if (success && (alpm_handle.trans_to_add ().length + alpm_handle.trans_to_remove ().length) == 0) {
								trans_release ();
								trans_commit_finished (success);
								return;
							}
						}
						if (!success) {
							trans_release ();
						}
					}
				}
				if (!success) {
					trans_commit_finished (success);
					return;
				}
			}
			success = trans_commit_real ();
			if (success) {
				to_install_as_dep.foreach_remove ((pkgname, val) => {
					unowned Alpm.Package? pkg = alpm_handle.localdb.get_pkg (pkgname);
					if (pkg != null) {
						pkg.reason = Alpm.Package.Reason.DEPEND;
						return true; // remove current pkgname
					}
					return false;
				});
			}
			trans_commit_finished (success);
		}

		bool trans_commit_real () {
			current_error = ErrorInfos ();
			bool success = true;
			Alpm.List err_data;
			if (alpm_handle.trans_commit (out err_data) == -1) {
				Alpm.Errno errno = alpm_handle.errno ();
				// cancel the download return an EXTERNAL_DOWNLOAD error
				if (errno == Alpm.Errno.EXTERNAL_DOWNLOAD && cancellable.is_cancelled ()) {
					trans_release ();
					trans_commit_finished (false);
					return false;
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
			return success;
		}

		internal void trans_release () {
			alpm_handle.trans_release ();
			remove_ignorepkgs ();
			remove_overwrite_files ();
		}

		internal void trans_cancel () {
			if (alpm_handle.trans_interrupt () == 0) {
				// a transaction is being interrupted
				// it will end the normal way
				return;
			}
			cancellable.cancel ();
		}
	}
}

void write_log_file (string event) {
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
		case Alpm.Event.Type.DELTA_PATCH_START:
			details += data.delta_patch_delta.to;
			details += data.delta_patch_delta.delta;
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
			string[] unresolvables = {};
			unowned Alpm.List<unowned Alpm.Package> list = data.remove_pkgs_packages;
			while (list != null) {
				unowned Alpm.Package pkg = list.data;
				unresolvables += pkg.name;
				list.next ();
			}
			alpm_utils.emit_unresolvables (unresolvables);
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
			alpm_utils.provider_cond = Cond ();
			alpm_utils.provider_mutex = Mutex ();
			alpm_utils.choosen_provider = null;
			alpm_utils.emit_providers (depend_str, providers_str);
			alpm_utils.provider_mutex.lock ();
			while (alpm_utils.choosen_provider == null) {
				alpm_utils.provider_cond.wait (alpm_utils.provider_mutex);
			}
			data.select_provider_use_index = alpm_utils.choosen_provider;
			alpm_utils.provider_mutex.unlock ();
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

uint64 prevprogress;

int cb_download (void* data, uint64 dltotal, uint64 dlnow, uint64 ultotal, uint64 ulnow) {

	if (unlikely (alpm_utils.cancellable.is_cancelled ())) {
		return 1;
	}

	string filename = (string) data;

	if (unlikely (dlnow == 0 || dltotal == 0 || prevprogress == dltotal)) {
		return 0;
	} else if (unlikely (prevprogress == 0)) {
		alpm_utils.emit_download (filename, 0, dltotal);
		alpm_utils.emit_download (filename, dlnow, dltotal);
		alpm_utils.timer.start ();
	} else if (unlikely (dlnow == dltotal)) {
		alpm_utils.emit_download (filename, dlnow, dltotal);
		alpm_utils.timer.stop ();
	} else if (likely (alpm_utils.timer.elapsed () < 0.5)) {
		return 0;
	} else {
		alpm_utils.emit_download (filename, dlnow, dltotal);
		alpm_utils.timer.start ();
	}

	prevprogress = dlnow;

	return 0;
}

int cb_fetch (string fileurl, string localpath, int force) {
	if (alpm_utils.cancellable.is_cancelled ()) {
		return -1;
	}

	char error_buffer[Curl.ERROR_SIZE];
	var url = GLib.File.new_for_uri (fileurl);
	var destfile = GLib.File.new_for_path (localpath + url.get_basename ());
	var tempfile = GLib.File.new_for_path (destfile.get_path () + ".part");

	alpm_utils.curl.reset ();
	alpm_utils.curl.setopt (Curl.Option.FAILONERROR, 1L);
	alpm_utils.curl.setopt (Curl.Option.CONNECTTIMEOUT, 30L);
	alpm_utils.curl.setopt (Curl.Option.FILETIME, 1L);
	alpm_utils.curl.setopt (Curl.Option.FOLLOWLOCATION, 1L);
	alpm_utils.curl.setopt (Curl.Option.XFERINFOFUNCTION, cb_download);
	alpm_utils.curl.setopt (Curl.Option.LOW_SPEED_LIMIT, 1L);
	alpm_utils.curl.setopt (Curl.Option.LOW_SPEED_TIME, 30L);
	alpm_utils.curl.setopt (Curl.Option.NETRC, Curl.NetRCOption.OPTIONAL);
	alpm_utils.curl.setopt (Curl.Option.HTTPAUTH, Curl.CURLAUTH_ANY);
	alpm_utils.curl.setopt (Curl.Option.URL, fileurl);
	alpm_utils.curl.setopt (Curl.Option.ERRORBUFFER, error_buffer);
	alpm_utils.curl.setopt (Curl.Option.NOPROGRESS, 0L);
	alpm_utils.curl.setopt (Curl.Option.XFERINFODATA, (void*) url.get_basename ());

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
				alpm_utils.curl.setopt (Curl.Option.TIMECONDITION, Curl.TimeCond.IFMODSINCE);
				FileInfo info = destfile.query_info ("time::modified", 0);
				TimeVal time = info.get_modification_time ();
				alpm_utils.curl.setopt (Curl.Option.TIMEVALUE, time.tv_sec);
			} else if (tempfile.query_exists ()) {
				// a previous partial download exists, resume from end of file.
				FileInfo info = tempfile.query_info ("standard::size", 0);
				int64 size = info.get_size ();
				alpm_utils.curl.setopt (Curl.Option.RESUME_FROM_LARGE, size);
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

	alpm_utils.curl.setopt (Curl.Option.WRITEDATA, localf);

	// perform transfer
	Curl.Code err = alpm_utils.curl.perform ();


	// disconnect relationships from the curl handle for things that might go out
	// of scope, but could still be touched on connection teardown. This really
	// only applies to FTP transfers.
	alpm_utils.curl.setopt (Curl.Option.NOPROGRESS, 1L);
	alpm_utils.curl.setopt (Curl.Option.ERRORBUFFER, null);

	int ret;

	// was it a success?
	switch (err) {
		case Curl.Code.OK:
			long timecond, remote_time = -1;
			double remote_size, bytes_dl;
			unowned string effective_url;

			// retrieve info about the state of the transfer
			alpm_utils.curl.getinfo (Curl.Info.FILETIME, out remote_time);
			alpm_utils.curl.getinfo (Curl.Info.CONTENT_LENGTH_DOWNLOAD, out remote_size);
			alpm_utils.curl.getinfo (Curl.Info.SIZE_DOWNLOAD, out bytes_dl);
			alpm_utils.curl.getinfo (Curl.Info.CONDITION_UNMET, out timecond);
			alpm_utils.curl.getinfo (Curl.Info.EFFECTIVE_URL, out effective_url);

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
				alpm_utils.emit_log ((uint) Alpm.LogLevel.ERROR, error);
				alpm_utils.current_error.details = {error};
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
				alpm_utils.emit_log ((uint) Alpm.LogLevel.ERROR, error);
				alpm_utils.current_error.details = {error};
			}
			ret = -1;
			break;
	}

	return ret;
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
