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
	internal class AlpmUtils: Object {
		internal AlpmConfig alpm_config;
		internal Alpm.Handle? alpm_handle;
		internal Alpm.Handle? files_handle;
		internal Cond provider_cond;
		internal Mutex provider_mutex;
		internal int? choosen_provider;
		internal bool force_refresh;
		internal bool refreshed;
		internal bool enable_downgrade;
		internal bool check_aur_updates;
		internal int flags;
		internal string[] to_install;
		internal string[] to_remove;
		internal string[] to_load;
		internal string[] to_build;
		internal bool sysupgrade;
		AURPackageStruct[] to_build_pkgs;
		GLib.List<string> aur_pkgbases_to_build;
		GenericSet<string?> aur_desc_list;
		GenericSet<string?> already_checked_aur_dep;
		HashTable<string, string> to_install_as_dep;
		string aurdb_path;
		internal string[] temporary_ignorepkgs;
		internal string[] overwrite_files;
		PackageStruct[] aur_conflicts_to_remove;
		internal ErrorInfos current_error;
		internal Timer timer;
		internal Cancellable cancellable;
		internal Curl.Easy curl;
		internal bool downloading_updates;
		AURPackageStruct[] aur_updates;
		HashTable<string, Json.Array> aur_search_results;
		HashTable<string, Json.Object> aur_infos;
		As.Store app_store;
		string locale;
		RWLock rwlock;

		public signal void emit_event (uint primary_event, uint secondary_event, string[] details);
		public signal void emit_providers (string depend, string[] providers);
		public signal void emit_progress (uint progress, string pkgname, uint percent, uint n_targets, uint current_target);
		public signal void emit_download (string filename, uint64 xfered, uint64 total);
		public signal void emit_totaldownload (uint64 total);
		public signal void emit_log (uint level, string msg);
		public signal void refresh_finished (bool success);
		public signal void emit_get_updates_progress (uint percent);
		public signal void get_updates_finished (UpdatesStruct updates);
		public signal void downloading_updates_finished ();
		public signal void trans_prepare_finished (bool success);
		public signal void trans_commit_finished (bool success);

		public AlpmUtils () {
			alpm_config = new AlpmConfig ("/etc/pacman.conf");
			aur_pkgbases_to_build = new GLib.List<string> ();
			aur_desc_list = new GenericSet<string?> (str_hash, str_equal);
			already_checked_aur_dep = new GenericSet<string?> (str_hash, str_equal);
			to_install_as_dep = new HashTable<string, string> (str_hash, str_equal);
			aurdb_path = "/tmp/pamac-aur";
			timer = new Timer ();
			current_error = ErrorInfos ();
			refresh_handle ();
			cancellable = new Cancellable ();
			curl = new Curl.Easy ();
			aur_updates = {};
			aur_search_results = new HashTable<string, Json.Array> (str_hash, str_equal);
			aur_infos = new HashTable<string, Json.Object> (str_hash, str_equal);
			refreshed = false;
			downloading_updates = false;
			Curl.global_init (Curl.GLOBAL_SSL);
			// init appstream
			app_store = new As.Store ();
			app_store.set_add_flags (As.StoreAddFlags.USE_UNIQUE_ID
									| As.StoreAddFlags.ONLY_NATIVE_LANGS
									| As.StoreAddFlags.USE_MERGE_HEURISTIC);
			locale = Environ.get_variable (Environ.get (), "LANG");
			if (locale != null) {
				// remove .UTF-8 from locale
				locale = locale.split (".")[0];
			} else {
				locale = "C";
			}
			rwlock = RWLock ();
		}

		~AlpmUtils () {
			Curl.global_cleanup ();
		}

		internal void enable_appstream () {
			try {
				app_store.load (As.StoreLoadFlags.APP_INFO_SYSTEM);
				app_store.set_search_match (As.AppSearchMatch.PKGNAME
											| As.AppSearchMatch.DESCRIPTION
											| As.AppSearchMatch.COMMENT
											| As.AppSearchMatch.NAME
											| As.AppSearchMatch.KEYWORD);
			} catch (Error e) {
				stderr.printf ("Error: %s\n", e.message);
			}
		}

		internal void refresh_handle () {
			rwlock.writer_lock ();
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
			rwlock.writer_unlock ();
		}

		internal bool get_checkspace () {
			rwlock.reader_lock ();
			bool checkspace = alpm_handle.checkspace == 1 ? true : false;
			rwlock.reader_unlock ();
			return checkspace;
		}

		internal List<string> get_ignorepkgs () {
			var result = new List<string> ();
			rwlock.reader_lock ();
			unowned Alpm.List<unowned string> ignorepkgs = alpm_handle.ignorepkgs;
			while (ignorepkgs != null) {
				unowned string ignorepkg = ignorepkgs.data;
				result.append (ignorepkg);
				ignorepkgs.next ();
			}
			rwlock.reader_unlock ();
			return result;
		}

		internal bool should_hold (string pkgname) {
			if (alpm_config.get_holdpkgs ().find_custom (pkgname, strcmp) != null) {
				return true;
			}
			return false;
		}

		internal uint get_pkg_reason (string pkgname) {
			rwlock.reader_lock ();
			unowned Alpm.Package? pkg = alpm_handle.localdb.get_pkg (pkgname);
			rwlock.reader_unlock ();
			if (pkg != null) {
				return pkg.reason;
			}
			return 0;
		}

		internal void set_pkgreason (string pkgname, uint reason) {
			rwlock.writer_lock ();
			unowned Alpm.Package? pkg = alpm_handle.localdb.get_pkg (pkgname);
			if (pkg != null) {
				// lock the database
				if (alpm_handle.trans_init (0) == 0) {
					pkg.reason = (Alpm.Package.Reason) reason;
					alpm_handle.trans_release ();
				}
			}
			rwlock.writer_unlock ();
		}

		string get_localized_string (HashTable<string,string> hashtable) {
			unowned string val;
			if (!hashtable.lookup_extended (locale, null, out val)) {
				// try with just the language
				if (!hashtable.lookup_extended (locale.split ("_")[0], null, out val)) {
					// try C locale
					if (!hashtable.lookup_extended ("C", null, out val)) {
						return "";
					}
				}
			}
			return val;
		}

		string get_app_name (As.App app) {
			return get_localized_string (app.get_names ());
		}

		string get_app_summary (As.App app) {
			return get_localized_string (app.get_comments ());
		}

		string get_app_description (As.App app) {
			return get_localized_string (app.get_descriptions ());
		}

		string get_app_icon (As.App app, string dbname) {
			string icon = "";
			app.get_icons ().foreach ((as_icon) => {
				if (as_icon.get_kind () == As.IconKind.CACHED) {
					if (as_icon.get_height () == 64) {
						icon = "/usr/share/app-info/icons/archlinux-arch-%s/64x64/%s".printf (dbname, as_icon.get_name ());
					}
				}
			});
			return icon;
		}

		string get_app_screenshot (As.App app) {
			string screenshot = "";
			app.get_screenshots ().foreach ((as_screenshot) => {
				if (as_screenshot.get_kind () == As.ScreenshotKind.DEFAULT) {
					As.Image? as_image = as_screenshot.get_source ();
					if (as_image != null) {
						screenshot = as_image.get_url ();
					}
				}
			});
			return screenshot;
		}

		As.App[] get_pkgname_matching_apps (string pkgname) {
			As.App[] matching_apps = {};
			app_store.get_apps ().foreach ((app) => {
				if (app.get_pkgname_default () == pkgname) {
					matching_apps += app;
				}
			});
			return matching_apps;
		}

		List<Package> initialise_pkgs (Alpm.Package? alpm_pkg) {
			var pkgs = new List<Package> ();
			if (alpm_pkg != null) {
				string installed_version = "";
				string repo_name = "";
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
				}
				if (repo_name != "") {
					As.App[] apps = get_pkgname_matching_apps (alpm_pkg.name);
					if (apps.length > 0) {
						// alpm_pkg provide some apps
						foreach (unowned As.App app in apps) {
							pkgs.append (new Package.from_struct (PackageStruct () {
								name = alpm_pkg.name,
								app_name = get_app_name (app),
								version = alpm_pkg.version,
								installed_version = installed_version,
								desc = get_app_summary (app),
								repo = repo_name,
								size = alpm_pkg.isize,
								download_size = alpm_pkg.download_size,
								icon = get_app_icon (app, repo_name)
							}));
						}
					} else {
						pkgs.append (new Package.from_struct (PackageStruct () {
							name = alpm_pkg.name,
							app_name = "",
							version = alpm_pkg.version,
							installed_version = (owned) installed_version,
							desc = alpm_pkg.desc ?? "",
							repo = (owned) repo_name,
							size = alpm_pkg.isize,
							download_size = alpm_pkg.download_size,
							icon = ""
						}));
					}
				} else {
					pkgs.append (new Package.from_struct (PackageStruct () {
						name = alpm_pkg.name,
						app_name = "",
						version = alpm_pkg.version,
						installed_version = (owned) installed_version,
						desc = alpm_pkg.desc ?? "",
						repo = (owned) repo_name,
						size = alpm_pkg.isize,
						download_size = alpm_pkg.download_size,
						icon = ""
					}));
				}
			}
			return pkgs;
		}

		internal List<Package> get_installed_pkgs () {
			var pkgs = new List<Package> ();
			rwlock.reader_lock ();
			unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
			while (pkgcache != null) {
				unowned Alpm.Package alpm_pkg = pkgcache.data;
				foreach (unowned Package pkg in initialise_pkgs (alpm_pkg)) {
					pkgs.append (pkg);
				}
				pkgcache.next ();
			}
			rwlock.reader_unlock ();
			return pkgs;
		}

		internal List<Package> get_installed_apps () {
			var result = new List<Package> ();
			app_store.get_apps ().foreach ((app) => {
				unowned string pkgname = app.get_pkgname_default ();
				rwlock.reader_lock ();
				unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (pkgname);
				if (local_pkg != null) {
					unowned Alpm.Package? sync_pkg = get_syncpkg (pkgname);
					if (sync_pkg != null) {
						result.append (new Package.from_struct (PackageStruct () {
							name = sync_pkg.name,
							app_name = get_app_name (app),
							version = sync_pkg.version,
							installed_version = local_pkg.version,
							desc = get_app_summary (app),
							repo = sync_pkg.db.name,
							size = sync_pkg.isize,
							download_size = sync_pkg.download_size,
							icon = get_app_icon (app, sync_pkg.db.name)
						}));
					}
				}
				rwlock.reader_unlock ();
			});
			// keep a ref pkg is needed
			var pkgs = new List<Package> ();
			foreach (unowned Package pkg in result) {
				pkgs.append (pkg);
			}
			return pkgs;
		}

		internal List<Package> get_explicitly_installed_pkgs () {
			var pkgs = new List<Package> ();
			rwlock.reader_lock ();
			unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
			while (pkgcache != null) {
				unowned Alpm.Package alpm_pkg = pkgcache.data;
				if (alpm_pkg.reason == Alpm.Package.Reason.EXPLICIT) {
					foreach (unowned Package pkg in initialise_pkgs (alpm_pkg)) {
						pkgs.append (pkg);
					}
				}
				pkgcache.next ();
			}
			rwlock.reader_unlock ();
			return pkgs;
		}

		internal List<Package> get_foreign_pkgs () {
			var pkgs = new List<Package> ();
			rwlock.reader_lock ();
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
					foreach (unowned Package pkg in initialise_pkgs (alpm_pkg)) {
						pkgs.append (pkg);
					}
				}
				pkgcache.next ();
			}
			rwlock.reader_unlock ();
			return pkgs;
		}

		internal List<Package> get_orphans () {
			var pkgs = new List<Package> ();
			rwlock.reader_lock ();
			unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
			while (pkgcache != null) {
				unowned Alpm.Package alpm_pkg = pkgcache.data;
				if (alpm_pkg.reason == Alpm.Package.Reason.DEPEND) {
					Alpm.List<string> requiredby = alpm_pkg.compute_requiredby ();
					if (requiredby.length == 0) {
						Alpm.List<string> optionalfor = alpm_pkg.compute_optionalfor ();
						if (optionalfor.length == 0) {
							foreach (unowned Package pkg in initialise_pkgs (alpm_pkg)) {
								pkgs.append (pkg);
							}
						} else {
							optionalfor.free_inner (GLib.free);
						}
					} else {
						requiredby.free_inner (GLib.free);
					}
				}
				pkgcache.next ();
			}
			rwlock.reader_unlock ();
			return pkgs;
		}

		internal Package get_installed_pkg (string pkgname) {
			rwlock.reader_lock ();
			var pkg = new Package.from_struct (initialise_pkg_struct (alpm_handle.localdb.get_pkg (pkgname)));
			rwlock.reader_unlock ();
			return pkg;
		}

		internal Package find_installed_satisfier (string depstring) {
			rwlock.reader_lock ();
			var pkg = new Package.from_struct (initialise_pkg_struct (Alpm.find_satisfier (alpm_handle.localdb.pkgcache, depstring)));
			rwlock.reader_unlock ();
			return pkg;
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

		internal Package get_sync_pkg (string pkgname) {
			rwlock.reader_lock ();
			var pkg = new Package.from_struct (initialise_pkg_struct (get_syncpkg (pkgname)));
			rwlock.reader_unlock ();
			return pkg;
		}

		unowned Alpm.Package? find_dbs_satisfier (string depstring) {
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

		internal Package find_sync_satisfier (string depstring) {
			rwlock.reader_lock ();
			var pkg = new Package.from_struct (initialise_pkg_struct (find_dbs_satisfier (depstring)));
			rwlock.reader_unlock ();
			return pkg;
		}

		Alpm.List<unowned Alpm.Package> search_all_dbs (string search_string) {
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
			// search in appstream
			if (search_string.length >= 3) {
				Alpm.List<unowned Alpm.Package> appstream_result = null;
				string[] search_terms = As.utils_search_tokenize (search_string);
				app_store.get_apps ().foreach ((app) => {
					uint match_score = app.search_matches_all (search_terms);
					if (match_score > 0) {
						unowned string pkgname = app.get_pkgname_default ();
						unowned Alpm.Package? alpm_pkg = alpm_handle.localdb.get_pkg (pkgname);
						if (alpm_pkg == null) {
							alpm_pkg = get_syncpkg (pkgname);
						}
						if (alpm_pkg != null) {
							if (appstream_result.find (alpm_pkg, (Alpm.List.CompareFunc) alpm_pkg_compare_name) == null) {
								appstream_result.add (alpm_pkg);
							}
						}
					}
				});
				result.join (appstream_result.diff (result, (Alpm.List.CompareFunc) alpm_pkg_compare_name));
			}
			// use custom sort function
			global_search_string = search_string;
			result.sort (result.length, (Alpm.List.CompareFunc) alpm_pkg_sort_search_by_relevance);
			return result;
		}

		internal List<Package> search_pkgs (string search_string) {
			var pkgs = new List<Package> ();
			rwlock.reader_lock ();
			Alpm.List<unowned Alpm.Package> alpm_pkgs = search_all_dbs (search_string);
			unowned Alpm.List<unowned Alpm.Package> list = alpm_pkgs;
			while (list != null) {
				unowned Alpm.Package alpm_pkg = list.data;
				foreach (unowned Package pkg in initialise_pkgs (alpm_pkg)) {
					pkgs.append (pkg);
				}
				list.next ();
			}
			rwlock.reader_unlock ();
			return pkgs;
		}

		AURPackageStruct initialise_aur_struct (Json.Object? json_object) {
			if (json_object == null) {
				return AURPackageStruct () {
					name = "",
					version = "",
					installed_version = "",
					desc = ""
				};
			}
			string installed_version = "";
			unowned Alpm.Package? pkg = alpm_handle.localdb.get_pkg (json_object.get_string_member ("Name"));
			if (pkg != null) {
				installed_version = pkg.version;
			}
			return AURPackageStruct () {
				name = json_object.get_string_member ("Name"),
				version = json_object.get_string_member ("Version"),
				installed_version = (owned) installed_version,
				// desc can be null
				desc = json_object.get_null_member ("Description") ? "" : json_object.get_string_member ("Description"),
				popularity = json_object.get_double_member ("Popularity")
			};
		}

		internal List<AURPackage> search_in_aur (string search_string) {
			if (!aur_search_results.contains (search_string)) {
				Json.Array pkgs = aur_search (search_string.split (" "));
				aur_search_results.insert (search_string, pkgs);
			}
			var result = new List<AURPackage> ();
			Json.Array aur_pkgs = aur_search_results.get (search_string);
			aur_pkgs.foreach_element ((array, index, node) => {
				Json.Object aur_pkg = node.get_object ();
				// remove results which exist in repos
				rwlock.reader_lock ();
				if (get_syncpkg (aur_pkg.get_string_member ("Name")) == null) {
					result.append (new AURPackage.from_struct (initialise_aur_struct (aur_pkg)));
				}
				rwlock.reader_unlock ();
			});
			// keep a ref pkg is needed
			var pkgs = new List<AURPackage> ();
			foreach (unowned AURPackage pkg in result) {
				pkgs.append (pkg);
			}
			return pkgs;
		}

		internal AURPackage get_aur_pkg (string pkgname) {
			if (!aur_infos.contains (pkgname)) {
				Json.Array results = aur_multiinfo ({pkgname});
				if (results.get_length () > 0) {
					aur_infos.insert (pkgname, results.get_object_element (0));
				}
			}
			unowned Json.Object? json_object = aur_infos.lookup (pkgname);
			return new AURPackage.from_struct (initialise_aur_struct (json_object));
		}

		internal AURPackageDetails get_aur_pkg_details (string pkgname) {
			string name = "";
			string version = "";
			string desc = "";
			double popularity = 0;
			string packagebase = "";
			string url = "";
			string maintainer = "";
			string firstsubmitted = "";
			string lastmodified = "";
			string outofdate = "";
			int64 numvotes = 0;
			string[] licenses = {};
			string[] depends = {};
			string[] makedepends = {};
			string[] checkdepends = {};
			string[] optdepends = {};
			string[] provides = {};
			string[] replaces = {};
			string[] conflicts = {};
			var details = AURPackageDetailsStruct ();
			if (!aur_infos.contains (pkgname)) {
				Json.Array results = aur_multiinfo ({pkgname});
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
				GLib.Time time = GLib.Time.local ((time_t) json_object.get_int_member ("FirstSubmitted"));
				firstsubmitted = time.format ("%x");
				// lastmodified
				time = GLib.Time.local ((time_t) json_object.get_int_member ("LastModified"));
				lastmodified = time.format ("%x");
				// outofdate can be null
				node = json_object.get_member ("OutOfDate");
				if (!node.is_null ()) {
					time = GLib.Time.local ((time_t) node.get_int ());
					outofdate = time.format ("%x");
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
			details.firstsubmitted = (owned) firstsubmitted;
			details.lastmodified = (owned) lastmodified;
			details.outofdate = (owned) outofdate;
			details.numvotes = numvotes;
			details.licenses = (owned) licenses;
			details.depends = (owned) depends;
			details.optdepends = (owned) optdepends;
			details.checkdepends = (owned) checkdepends;
			details.makedepends = (owned) makedepends;
			details.provides = (owned) provides;
			details.replaces = (owned) replaces;
			details.conflicts = (owned) conflicts;
			return new AURPackageDetails.from_struct (details);
		}

		internal List<string> get_repos_names () {
			var repos_names = new List<string> ();
			rwlock.reader_lock ();
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				repos_names.append (db.name);
				syncdbs.next ();
			}
			rwlock.reader_unlock ();
			return repos_names;
		}

		internal List<Package> get_repo_pkgs (string repo) {
			var pkgs = new List<Package> ();
			rwlock.reader_lock ();
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				if (db.name == repo) {
					unowned Alpm.List<unowned Alpm.Package> pkgcache = db.pkgcache;
					while (pkgcache != null) {
						unowned Alpm.Package sync_pkg = pkgcache.data;
						unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (sync_pkg.name);
						if (local_pkg != null) {
							foreach (unowned Package pkg in initialise_pkgs (local_pkg)) {
								pkgs.append (pkg);
							}
						} else {
							foreach (unowned Package pkg in initialise_pkgs (sync_pkg)) {
								pkgs.append (pkg);
							}
						}
						pkgcache.next ();
					}
					break;
				}
				syncdbs.next ();
			}
			rwlock.reader_unlock ();
			return pkgs;
		}

		internal List<string> get_groups_names () {
			var groups_names = new List<string> ();
			rwlock.reader_lock ();
			unowned Alpm.List<unowned Alpm.Group> groupcache = alpm_handle.localdb.groupcache;
			while (groupcache != null) {
				unowned Alpm.Group group = groupcache.data;
				if (groups_names.find_custom (group.name, strcmp) == null) { 
					groups_names.append (group.name);
				}
				groupcache.next ();
			}
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				groupcache = db.groupcache;
				while (groupcache != null) {
					unowned Alpm.Group group = groupcache.data;
					if (groups_names.find_custom (group.name, strcmp) == null) { 
						groups_names.append (group.name);
					}
					groupcache.next ();
				}
				syncdbs.next ();
			}
			rwlock.reader_unlock ();
			return groups_names;
		}

		Alpm.List<unowned Alpm.Package> group_pkgs (string group_name) {
			Alpm.List<unowned Alpm.Package> result = null;
			rwlock.reader_lock ();
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
			rwlock.reader_unlock ();
			return result;
		}

		internal List<Package> get_group_pkgs (string groupname) {
			var pkgs = new List<Package> ();
			rwlock.reader_lock ();
			Alpm.List<unowned Alpm.Package> alpm_pkgs = group_pkgs (groupname);
			unowned Alpm.List<unowned Alpm.Package> list = alpm_pkgs;
			while (list != null) {
				unowned Alpm.Package alpm_pkg = list.data;
				foreach (unowned Package pkg in initialise_pkgs (alpm_pkg)) {
					pkgs.append (pkg);
				}
				list.next ();
			}
			rwlock.reader_unlock ();
			return pkgs;
		}

		internal List<Package> get_category_pkgs (string category) {
			var result = new List<Package> ();
			app_store.get_apps ().foreach ((app) => {
				app.get_categories ().foreach ((cat_name) => {
					if (cat_name == category) {
						unowned string pkgname = app.get_pkgname_default ();
						string installed_version = "";
						string repo_name = "";
						rwlock.reader_lock ();
						unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (pkgname);
						unowned Alpm.Package? sync_pkg = get_syncpkg (pkgname);
						if (sync_pkg != null) {
							if (local_pkg == null) {
								repo_name = sync_pkg.db.name;
							} else {
								repo_name = sync_pkg.db.name;
								installed_version = local_pkg.version;
							}
							result.append (new Package.from_struct (PackageStruct () {
								name = sync_pkg.name,
								app_name = get_app_name (app),
								version = sync_pkg.version,
								installed_version = (owned) installed_version,
								desc = get_app_summary (app),
								repo = (owned) repo_name,
								size = sync_pkg.isize,
								download_size = sync_pkg.download_size,
								icon = get_app_icon (app, sync_pkg.db.name)
							}));
						}
						rwlock.reader_unlock ();
					}
				});
			});
			// keep a ref pkg is needed
			var pkgs = new List<Package> ();
			foreach (unowned Package pkg in result) {
				pkgs.append (pkg);
			}
			return pkgs;
		}

		internal List<string> get_pkg_uninstalled_optdeps (string pkgname) {
			var optdeps = new List<string> ();
			rwlock.reader_lock ();
			unowned Alpm.Package? alpm_pkg = alpm_handle.localdb.get_pkg (pkgname);
			if (alpm_pkg == null) {
				alpm_pkg = get_syncpkg (pkgname);
			}
			if (alpm_pkg != null) {
				unowned Alpm.List<unowned Alpm.Depend> optdepends = alpm_pkg.optdepends;
				while (optdepends != null) {
					unowned Alpm.Depend optdep = optdepends.data;
					if (Alpm.find_satisfier (alpm_handle.localdb.pkgcache, optdep.name) == null) {
						optdeps.append (optdep.compute_string ());
					}
					optdepends.next ();
				}
			}
			rwlock.reader_unlock ();
			return optdeps;
		}

		internal PackageDetails get_pkg_details (string pkgname, string appname) {
			string name = "";
			string app_name = "";
			string version = "";
			string installed_version = "";
			string desc = "";
			string long_desc = "";
			string url = "";
			string icon = "";
			string screenshot = "";
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
			var details = PackageDetailsStruct ();
			rwlock.reader_lock ();
			unowned Alpm.Package? alpm_pkg = alpm_handle.localdb.get_pkg (pkgname);
			unowned Alpm.Package? sync_pkg = get_syncpkg (pkgname);
			if (alpm_pkg == null) {
				alpm_pkg = sync_pkg;
			} else {
				installed_version = alpm_pkg.version;
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
				if (sync_pkg != null) {
					if (appname != "") {
						app_store.get_apps ().foreach ((app) => {
							if (get_app_name (app) == appname) {
								if (app.get_pkgname_default () == alpm_pkg.name) {
									app_name = appname;
									desc = get_app_summary (app);
									try {
										long_desc = As.markup_convert_simple (get_app_description (app));
									} catch (Error e) {
										stderr.printf ("Error: %s\n", e.message);
									}
									icon = get_app_icon (app, sync_pkg.db.name);
									screenshot = get_app_screenshot (app);
								}
							}
						});
					} else {
						// find if pkgname provides only one app
						As.App[] matching_apps = get_pkgname_matching_apps (pkgname);
						if (matching_apps.length == 1) {
							As.App app = matching_apps[0];
							app_name = get_app_name (app);
							desc = get_app_summary (app);
							try {
								long_desc = As.markup_convert_simple (get_app_description (app));
							} catch (Error e) {
								stderr.printf ("Error: %s\n", e.message);
							}
							icon = get_app_icon (app, sync_pkg.db.name);
							screenshot = get_app_screenshot (app);
						}
					}
				}
				details.size = alpm_pkg.isize;
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
				builddate = time.format ("%x");
				// local pkg
				if (alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
					// repo
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
					installdate = time.format ("%x");
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
			rwlock.reader_unlock ();
			details.name = (owned) name;
			details.app_name = (owned) app_name;
			details.version = (owned) version;
			details.installed_version = (owned) installed_version;
			details.desc = (owned) desc;
			details.long_desc = (owned) long_desc;
			details.repo = (owned) repo;
			details.url = (owned) url;
			details.icon = (owned) icon;
			details.screenshot = (owned) screenshot;
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
			return new PackageDetails.from_struct (details);
		}

		internal List<string> get_pkg_files (string pkgname) {
			var files = new List<string> ();
			rwlock.reader_lock ();
			unowned Alpm.Package? alpm_pkg = alpm_handle.localdb.get_pkg (pkgname);
			if (alpm_pkg != null) {
				unowned Alpm.FileList filelist = alpm_pkg.files;
				Alpm.File* file_ptr = filelist.files;
				for (size_t i = 0; i < filelist.count; i++, file_ptr++) {
					if (!file_ptr->name.has_suffix ("/")) {
						files.append (alpm_handle.root + file_ptr->name);
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
								files.append (alpm_handle.root + file_ptr->name);
							}
						}
						break;
					}
					syncdbs.next ();
				}
			}
			rwlock.reader_unlock ();
			return files;
		}

		internal HashTable<string, Variant> search_files (string[] files) {
			var result = new HashTable<string, Variant> (str_hash, str_equal);
			rwlock.reader_lock ();
			foreach (unowned string file in files) {
				// search in localdb
				unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
				while (pkgcache != null) {
					unowned Alpm.Package alpm_pkg = pkgcache.data;
					string[] found_files = {};
					unowned Alpm.FileList filelist = alpm_pkg.files;
					Alpm.File* file_ptr = filelist.files;
					for (size_t i = 0; i < filelist.count; i++, file_ptr++) {
						// exclude directory name
						if (!file_ptr->name.has_suffix ("/")) {
							// adding / to compare
							string real_file_name = alpm_handle.root + file_ptr->name;
							if (file in real_file_name) {
								found_files += real_file_name;
							}
						}
					}
					if (found_files.length > 0) {
						result.insert (alpm_pkg.name, new Variant.strv (found_files));
					}
					pkgcache.next ();
				}
				// search in syncdbs
				unowned Alpm.List<unowned Alpm.DB> syncdbs = files_handle.syncdbs;
				while (syncdbs != null) {
					unowned Alpm.DB db = syncdbs.data;
					pkgcache = db.pkgcache;
					while (pkgcache != null) {
						unowned Alpm.Package alpm_pkg = pkgcache.data;
						string[] found_files = {};
						unowned Alpm.FileList filelist = alpm_pkg.files;
						Alpm.File* file_ptr = filelist.files;
						for (size_t i = 0; i < filelist.count; i++, file_ptr++) {
							// exclude directory name
							if (!file_ptr->name.has_suffix ("/")) {
								// adding / to compare
								string real_file_name = alpm_handle.root + file_ptr->name;
								if (file in real_file_name) {
									found_files += real_file_name;
								}
							}
						}
						if (found_files.length > 0) {
							result.insert (alpm_pkg.name, new Variant.strv (found_files));
						}
						pkgcache.next ();
					}
					syncdbs.next ();
				}
			}
			rwlock.reader_unlock ();
			return result;
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
			// try to copy refresh dbs in tmp
			string tmp_dbpath = "/tmp/pamac-checkdbs";
			var file = GLib.File.new_for_path (tmp_dbpath);
			if (file.query_exists ()) {
				try {
					Process.spawn_command_line_sync ("cp -au %s/sync %s".printf (tmp_dbpath, alpm_handle.dbpath));
				} catch (SpawnError e) {
					stderr.printf ("SpawnError: %s\n", e.message);
				}
			}
			// a new handle is required to use copied databases
			refresh_handle ();
			// update ".db"
			rwlock.writer_lock ();
			bool success = update_dbs (alpm_handle, force);
			rwlock.writer_unlock ();
			if (cancellable.is_cancelled ()) {
				refresh_finished (false);
				return;
			}
			// only refresh ".files" if force
			if (force_refresh) {
				// update ".files", do not need to know if we succeeded
				rwlock.writer_lock ();
				update_dbs (files_handle, force);
				rwlock.writer_unlock ();
			}
			if (cancellable.is_cancelled ()) {
				refresh_finished (false);
			} else if (success) {
				refreshed = true;
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
				string icon = "";
				string app_name = "";
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
				if (repo_name != "") {
					// find if pkgname provides only one app
					As.App[] matching_apps = get_pkgname_matching_apps (alpm_pkg.name);
					if (matching_apps.length == 1) {
						As.App app = matching_apps[0];
						app_name = get_app_name (app);
						desc = get_app_summary (app);
						icon = get_app_icon (app, repo_name);
					}
				}
				return PackageStruct () {
					name = alpm_pkg.name,
					app_name = (owned) app_name,
					version = alpm_pkg.version,
					installed_version = (owned) installed_version,
					desc = (owned) desc,
					repo = (owned) repo_name,
					size = alpm_pkg.isize,
					download_size = alpm_pkg.download_size,
					icon = (owned) icon
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

		internal void compute_aur_build_list (string[] aur_list) {
			try {
				Process.spawn_command_line_sync ("mkdir -p %s".printf (aurdb_path));
			} catch (SpawnError e) {
				stderr.printf ("SpawnError: %s\n", e.message);
			}
			aur_desc_list.remove_all ();
			already_checked_aur_dep.remove_all ();
			check_aur_dep_list (aur_list);
		}

		void check_aur_dep_list (string[] pkgnames) {
			string[] dep_types = {"Depends", "MakeDepends", "CheckDepends"};
			string[] dep_to_check = {};
			Json.Array results = aur_multiinfo (pkgnames);
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
									string dep_name = Alpm.Depend.from_string (dep_string).name;
									unowned Alpm.Package? pkg = null;
									// search for the name first to avoid provides trouble
									rwlock.reader_lock ();
									pkg = alpm_handle.localdb.get_pkg (dep_name);
									if (pkg == null) {
										pkg = get_syncpkg (dep_name);
									}
									if (pkg == null) {
										if (!(dep_name in already_checked_aur_dep)) {
											dep_to_check += (owned) dep_name;
										}
									}
									rwlock.reader_unlock ();
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
				check_aur_dep_list (dep_to_check);
			}
		}

		internal Updates get_updates (bool refresh_files_dbs) {
			PackageStruct[] repos_updates = {};
			unowned Alpm.Package? pkg = null;
			unowned Alpm.Package? candidate = null;
			// use a tmp handle
			rwlock.reader_lock ();
			var tmp_handle = alpm_config.get_handle (false, true);
			// refresh tmp dbs
			// count this step as 90% of the total
			emit_get_updates_progress (0);
			unowned Alpm.List<unowned Alpm.DB> syncdbs = tmp_handle.syncdbs;
			size_t dbs_count = syncdbs.length;
			size_t i = 0;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				db.update (0);
				syncdbs.next ();
				i++;
				emit_get_updates_progress ((uint) ((double) i / dbs_count * (double) 90));
			}
			if (refresh_files_dbs) {
				// refresh file dbs
				// do not send progress because it is done in background
				var tmp_files_handle = alpm_config.get_handle (true, true);
				syncdbs = tmp_files_handle.syncdbs;
				dbs_count = syncdbs.length;
				i = 0;
				while (syncdbs != null) {
					unowned Alpm.DB db = syncdbs.data;
					db.update (0);
					syncdbs.next ();
					i++;
				}
			}
			// check updates
			// count this step as 5% of the total
			string[] local_pkgs = {};
			unowned Alpm.List<unowned Alpm.Package> pkgcache = tmp_handle.localdb.pkgcache;
			while (pkgcache != null) {
				unowned Alpm.Package installed_pkg = pkgcache.data;
				// check if installed_pkg is in IgnorePkg or IgnoreGroup
				if (tmp_handle.should_ignore (installed_pkg) == 0) {
					candidate = installed_pkg.sync_newversion (tmp_handle.syncdbs);
					if (candidate != null) {
						var infos = initialise_pkg_struct (candidate);
						repos_updates += (owned) infos;
					} else {
						if (check_aur_updates) {
							// check if installed_pkg is a local pkg
							syncdbs = tmp_handle.syncdbs;
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
			emit_get_updates_progress (95);
			if (check_aur_updates) {
				// count this step as 5% of the total
				get_aur_updates (aur_multiinfo (local_pkgs));
			}
			var updates = UpdatesStruct () {
				repos_updates = (owned) repos_updates,
				aur_updates = (owned) aur_updates
			};
			rwlock.reader_unlock ();
			emit_get_updates_progress (100);
			return new Updates.from_struct (updates);
		}

		internal void get_updates_for_sysupgrade () {
			bool syncfirst = false;
			PackageStruct[] updates_infos = {};
			unowned Alpm.Package? pkg = null;
			unowned Alpm.Package? candidate = null;
			rwlock.reader_lock ();
			foreach (unowned string name in alpm_config.get_syncfirsts ()) {
				pkg = Alpm.find_satisfier (alpm_handle.localdb.pkgcache, name);
				if (pkg != null) {
					candidate = pkg.sync_newversion (alpm_handle.syncdbs);
					if (candidate != null) {
						var infos = initialise_pkg_struct (candidate);
						updates_infos += (owned) infos;
						syncfirst = true;
					}
				}
			}
			string[] local_pkgs = {};
			unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
			while (pkgcache != null) {
				unowned Alpm.Package installed_pkg = pkgcache.data;
				// check if installed_pkg is in IgnorePkg or IgnoreGroup
				if (alpm_handle.should_ignore (installed_pkg) == 0) {
					if (syncfirst) {
						candidate = null;
					} else {
						candidate = installed_pkg.sync_newversion (alpm_handle.syncdbs);
					}
					if (candidate != null) {
						var infos = initialise_pkg_struct (candidate);
						updates_infos += (owned) infos;
					} else {
						if (check_aur_updates) {
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
				get_aur_updates (aur_multiinfo (local_pkgs));
			}
			var updates = UpdatesStruct () {
				syncfirst = syncfirst,
				repos_updates = (owned) updates_infos,
				aur_updates = aur_updates
			};
			rwlock.reader_unlock ();
			get_updates_finished (updates);
		}

		void get_aur_updates (Json.Array aur_updates_json) {
			aur_updates = {};
			aur_updates_json.foreach_element ((array, index, node) => {
				unowned Json.Object pkg_info = node.get_object ();
				unowned string name = pkg_info.get_string_member ("Name");
				unowned string new_version = pkg_info.get_string_member ("Version");
				unowned string old_version = alpm_handle.localdb.get_pkg (name).version;
				if (Alpm.pkg_vercmp (new_version, old_version) == 1) {
					var infos = initialise_aur_struct (pkg_info);
					infos.installed_version = old_version;
					aur_updates += (owned) infos;
				}
			});
		}

		internal int download_updates () {
			downloading_updates = true;
			// use tmp handle
			rwlock.reader_lock ();
			var handle = alpm_config.get_handle (false, true, false);
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
			rwlock.reader_unlock ();
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
			add_overwrite_files ();
			if (alpm_handle.trans_sysupgrade ((enable_downgrade) ? 1 : 0) == -1) {
				Alpm.Errno errno = alpm_handle.errno ();
				current_error.message = _("Failed to prepare transaction");
				if (errno != 0) {
					current_error.details = { Alpm.strerror (errno) };
				}
				return false;
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
			rwlock.writer_lock ();
			launch_trans_prepare_real ();
			rwlock.writer_unlock ();
		}

		void launch_trans_prepare_real () {
			bool success = trans_init (flags);
			if (success && sysupgrade) {
				// add upgrades to transaction
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
			} else {
				trans_release ();
			}
			trans_prepare_finished (success);
		}

		internal void build_prepare () {
			to_build_pkgs = {};
			aur_pkgbases_to_build = new GLib.List<string> ();
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
			// get an handle with fake aur db and without emit signal callbacks
			rwlock.writer_lock ();
			alpm_handle = alpm_config.get_handle ();
			if (alpm_handle == null) {
				current_error = ErrorInfos () {
					message = _("Failed to initialize alpm library")
				};
				rwlock.writer_unlock ();
				trans_commit_finished (false);
			} else {
				alpm_handle.questioncb = (Alpm.QuestionCallBack) cb_question;
				// emit warnings here
				alpm_handle.logcb = (Alpm.LogCallBack) cb_log;
				// fake aur db
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
										var pkg = AURPackageStruct () {
											name = trans_pkg.name,
											version = trans_pkg.version,
											installed_version = "",
											desc = ""
										};
										to_build_pkgs += (owned) pkg;
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
									var pkg = initialise_pkg_struct (trans_pkg);
									aur_conflicts_to_remove += (owned) pkg;
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
							rwlock.writer_unlock ();
							refresh_handle ();
							rwlock.writer_lock ();
							// warnings already emitted
							alpm_handle.logcb = null;
							// launch standard prepare
							to_install = real_to_install;
							launch_trans_prepare_real ();
							alpm_handle.logcb = (Alpm.LogCallBack) cb_log;
						}
					} else {
						trans_release ();
					}
				}
				rwlock.writer_unlock ();
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
				var infos = initialise_pkg_struct (trans_pkg);
				to_remove += (owned) infos;
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
			current_error = ErrorInfos ();
			bool success = true;
			rwlock.writer_lock ();
			add_overwrite_files ();
			Alpm.List err_data;
			if (alpm_handle.trans_commit (out err_data) == -1) {
				Alpm.Errno errno = alpm_handle.errno ();
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
			rwlock.writer_unlock ();
			trans_commit_finished (success);
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
