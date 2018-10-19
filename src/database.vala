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

namespace Pamac {
	public class Database: Object {
		AlpmConfig alpm_config;
		Alpm.Handle? alpm_handle;
		Alpm.Handle? files_handle;
		HashTable<string, Json.Array> aur_search_results;
		HashTable<string, Json.Object> aur_infos;
		As.Store app_store;
		string locale;

		public signal void get_updates_progress (uint percent);
		public signal void refreshed ();

		public Config config { get; construct set; }

		public Database (Config config) {
			Object (config: config);
		}

		construct {
			refresh ();
			aur_search_results = new HashTable<string, Json.Array> (str_hash, str_equal);
			aur_infos = new HashTable<string, Json.Object> (str_hash, str_equal);
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
		}

		public void enable_appstream () {
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

		public void refresh () {
			alpm_config = new AlpmConfig ("/etc/pacman.conf");
			alpm_handle = alpm_config.get_handle ();
			if (alpm_handle == null) {
				critical (dgettext (null, "Failed to initialize alpm library"));
				return;
			} else {
				files_handle = alpm_config.get_handle (true);
			}
			refreshed ();
		}

		public List<string> get_mirrors_countries () {
			var countries = new List<string> ();
			try {
				string countries_str;
				int status;
				Process.spawn_command_line_sync ("pacman-mirrors -l",
											out countries_str,
											null,
											out status);
				if (status == 0) {
					foreach (unowned string country in countries_str.split ("\n")) {
						if (country != "") {
							countries.append (country);
						}
					}
				}
			} catch (SpawnError e) {
				stderr.printf ("Error: %s\n", e.message);
			}
			return countries;
		}

		public string get_mirrors_choosen_country () {
			string country = "";
			try {
				string countries_str;
				int status;
				Process.spawn_command_line_sync ("pacman-mirrors -lc",
											out countries_str,
											null,
											out status);
				if (status == 0) {
					// only take first country
					country = countries_str.split ("\n", 2)[0];
				}
			} catch (SpawnError e) {
				stderr.printf ("Error: %s\n", e.message);
			}
			return country;
		}

		public string get_alpm_dep_name (string dep_string) {
			return Alpm.Depend.from_string (dep_string).name;
		}

		public bool get_checkspace () {
			return alpm_handle.checkspace == 1 ? true : false;
		}

		public List<string> get_ignorepkgs () {
			var result = new List<string> ();
			unowned Alpm.List<unowned string> ignorepkgs = alpm_handle.ignorepkgs;
			while (ignorepkgs != null) {
				unowned string ignorepkg = ignorepkgs.data;
				result.append (ignorepkg);
				ignorepkgs.next ();
			}
			return result;
		}

		public Package get_installed_pkg (string pkgname) {
			return new Package.from_struct (initialise_pkg_struct (alpm_handle.localdb.get_pkg (pkgname)));
		}

		public Package find_installed_satisfier (string depstring) {
			return new Package.from_struct (initialise_pkg_struct (Alpm.find_satisfier (alpm_handle.localdb.pkgcache, depstring)));
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

		public List<Package> get_installed_pkgs () {
			var pkgs = new List<Package> ();
			unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
			while (pkgcache != null) {
				unowned Alpm.Package alpm_pkg = pkgcache.data;
				foreach (unowned Package pkg in initialise_pkgs (alpm_pkg)) {
					pkgs.append (pkg);
				}
				pkgcache.next ();
			}
			return pkgs;
		}

		public List<Package> get_installed_apps () {
			var result = new List<Package> ();
			app_store.get_apps ().foreach ((app) => {
				unowned string pkgname = app.get_pkgname_default ();
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
			});
			return (owned) result;
		}

		public List<Package> get_explicitly_installed_pkgs () {
			var pkgs = new List<Package> ();
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
			return pkgs;
		}

		public List<Package> get_foreign_pkgs () {
			var pkgs = new List<Package> ();
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
			return pkgs;
		}

		public List<Package> get_orphans () {
			var pkgs = new List<Package> ();
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
			return pkgs;
		}

		public async List<Package> get_installed_pkgs_async () {
			return get_installed_pkgs ();
		}

		public async List<Package> get_installed_apps_async () {
			return get_installed_apps ();
		}

		public async List<Package> get_explicitly_installed_pkgs_async () {
			return get_explicitly_installed_pkgs ();
		}

		public async List<Package> get_foreign_pkgs_async () {
			return get_foreign_pkgs ();
		}

		public async List<Package> get_orphans_async () {
			return get_orphans ();
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

		public Package get_sync_pkg (string pkgname) {
			return new Package.from_struct (initialise_pkg_struct (get_syncpkg (pkgname)));
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

		public Package find_sync_satisfier (string depstring) {
			return new Package.from_struct (initialise_pkg_struct (find_dbs_satisfier (depstring)));
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

		public List<Package> search_pkgs (string search_string) {
			var pkgs = new List<Package> ();
			Alpm.List<unowned Alpm.Package> alpm_pkgs = search_all_dbs (search_string);
			unowned Alpm.List<unowned Alpm.Package> list = alpm_pkgs;
			while (list != null) {
				unowned Alpm.Package alpm_pkg = list.data;
				foreach (unowned Package pkg in initialise_pkgs (alpm_pkg)) {
					pkgs.append (pkg);
				}
				list.next ();
			}
			return pkgs;
		}

		public async List<Package> search_pkgs_async (string search_string) {
			return search_pkgs (search_string);
		}

		AURPackageStruct initialise_aur_struct (Json.Object? json_object) {
			if (json_object == null) {
				return AURPackageStruct () {
					name = "",
					version = "",
					installed_version = "",
					desc = "",
					packagebase = ""
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
				popularity = json_object.get_double_member ("Popularity"),
				packagebase = json_object.get_string_member ("PackageBase")
			};
		}

		public async List<AURPackage> search_in_aur (string search_string) {
			if (!aur_search_results.contains (search_string)) {
				Json.Array pkgs = yield aur_search (search_string.split (" "));
				aur_search_results.insert (search_string, pkgs);
			}
			var result = new List<AURPackage> ();
			Json.Array aur_pkgs = aur_search_results.get (search_string);
			aur_pkgs.foreach_element ((array, index, node) => {
				Json.Object aur_pkg = node.get_object ();
				// remove results which exist in repos
				if (get_syncpkg (aur_pkg.get_string_member ("Name")) == null) {
					result.append (new AURPackage.from_struct (initialise_aur_struct (aur_pkg)));
				}
			});
			return (owned) result;
		}

		public HashTable<string, Variant> search_files (string[] files) {
			var result = new HashTable<string, Variant> (str_hash, str_equal);
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
							var real_file_name = new StringBuilder ();
							real_file_name.append (alpm_handle.root);
							real_file_name.append (file_ptr->name);
							if (file in real_file_name.str) {
								found_files += real_file_name.str;
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
								var real_file_name = new StringBuilder ();
								real_file_name.append (alpm_handle.root);
								real_file_name.append (file_ptr->name);
								if (file in real_file_name.str) {
									found_files += real_file_name.str;
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
			return result;
		}

		public List<Package> get_category_pkgs (string category) {
			var result = new List<Package> ();
			app_store.get_apps ().foreach ((app) => {
				app.get_categories ().foreach ((cat_name) => {
					if (cat_name == category) {
						unowned string pkgname = app.get_pkgname_default ();
						string installed_version = "";
						string repo_name = "";
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
					}
				});
			});
			return (owned) result;
		}

		public async List<Package> get_category_pkgs_async (string category) {
			return get_category_pkgs (category);
		}

		public List<string> get_repos_names () {
			var repos_names = new List<string> ();
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				repos_names.append (db.name);
				syncdbs.next ();
			}
			return repos_names;
		}

		public List<Package> get_repo_pkgs (string repo) {
			var pkgs = new List<Package> ();
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
			return pkgs;
		}

		public async List<Package> get_repo_pkgs_async (string repo) {
			return get_repo_pkgs (repo);
		}

		public List<string> get_groups_names () {
			var groups_names = new List<string> ();
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
			return groups_names;
		}

		Alpm.List<unowned Alpm.Package> group_pkgs (string group_name) {
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

		public List<Package> get_group_pkgs (string group_name) {
			var pkgs = new List<Package> ();
			Alpm.List<unowned Alpm.Package> alpm_pkgs = group_pkgs (group_name);
			unowned Alpm.List<unowned Alpm.Package> list = alpm_pkgs;
			while (list != null) {
				unowned Alpm.Package alpm_pkg = list.data;
				foreach (unowned Package pkg in initialise_pkgs (alpm_pkg)) {
					pkgs.append (pkg);
				}
				list.next ();
			}
			return pkgs;
		}

		public async List<Package> get_group_pkgs_async (string group_name) {
			return get_group_pkgs (group_name);
		}

		public List<string> get_pkg_uninstalled_optdeps (string pkgname) {
			var optdeps = new List<string> ();
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
			return optdeps;
		}

		public PackageDetails get_pkg_details (string pkgname, string appname, bool use_sync_pkg) {
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
			unowned Alpm.Package? alpm_pkg = alpm_handle.localdb.get_pkg (pkgname);
			unowned Alpm.Package? sync_pkg = get_syncpkg (pkgname);
			if (alpm_pkg == null || use_sync_pkg) {
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
						reason = dgettext (null, "Explicitly installed");
					} else if (alpm_pkg.reason == Alpm.Package.Reason.DEPEND) {
						reason = dgettext (null, "Installed as a dependency for another package");
					} else {
						reason = dgettext (null, "Unknown");
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
					has_signature = alpm_pkg.base64_sig != null ? dgettext (null, "Yes") : dgettext (null, "No");
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

		public List<string> get_pkg_files (string pkgname) {
			var files = new List<string> ();
			unowned Alpm.Package? alpm_pkg = alpm_handle.localdb.get_pkg (pkgname);
			if (alpm_pkg != null) {
				unowned Alpm.FileList filelist = alpm_pkg.files;
				Alpm.File* file_ptr = filelist.files;
				for (size_t i = 0; i < filelist.count; i++, file_ptr++) {
					if (!file_ptr->name.has_suffix ("/")) {
						var filename = new StringBuilder ();
						filename.append (alpm_handle.root);
						filename.append (file_ptr->name);
						files.append (filename.str);
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
								var filename = new StringBuilder ();
								filename.append (alpm_handle.root);
								filename.append (file_ptr->name);
								files.append (filename.str);
							}
						}
						break;
					}
					syncdbs.next ();
				}
			}
			return files;
		}

		public async List<string> get_pkg_files_async (string pkgname) {
			return get_pkg_files (pkgname);
		}

		async int launch_subprocess (SubprocessLauncher launcher, string[] cmds) {
			int status = 1;
			try {
				Subprocess process = launcher.spawnv (cmds);
				yield process.wait_async ();
				if (process.get_if_exited ()) {
					status = process.get_exit_status ();
				}
			} catch (Error e) {
				stderr.printf ("Error: %s\n", e.message);
			}
			return status;
		}

		public async File? clone_build_files (string pkgname, bool overwrite_files) {
			int status = 1;
			string[] cmds;
			var launcher = new SubprocessLauncher (SubprocessFlags.NONE);
			var builddir = File.new_for_path (config.aur_build_dir);
			if (!builddir.query_exists ()) {
				try {
					builddir.make_directory_with_parents ();
				} catch (Error e) {
					stderr.printf ("Error: %s\n", e.message);
				}
			}
			var pkgdir = builddir.get_child (pkgname);
			if (pkgdir.query_exists ()) {
				if (overwrite_files) {
					launcher.set_cwd (config.aur_build_dir);
					cmds = {"rm", "-rf", "%s".printf (pkgdir.get_path ())};
					yield launch_subprocess (launcher, cmds);
					cmds = {"git", "clone", "-q", "--depth=1", "https://aur.archlinux.org/%s.git".printf (pkgname)};
				} else {
					// fetch modifications
					launcher.set_cwd (pkgdir.get_path ());
					cmds = {"git", "fetch", "-q"};
					status = yield launch_subprocess (launcher, cmds);
					// write diff file
					if (status == 0) {
						launcher.set_flags (SubprocessFlags.STDOUT_PIPE);
						try {
							var file = File.new_for_path (Path.build_path ("/", pkgdir.get_path (), "diff"));
							if (file.query_exists ()) {
								// delete the file before rewrite it
								yield file.delete_async ();
							}
							cmds = {"git", "diff", "--exit-code", "origin/master"};
							FileEnumerator enumerator = yield pkgdir.enumerate_children_async ("standard::*", FileQueryInfoFlags.NONE);
							FileInfo info;
							// don't see .SRCINFO diff
							while ((info = enumerator.next_file (null)) != null) {
								string filename = info.get_name ();
								if (filename != ".SRCINFO") {
									cmds += filename;
								}
							}
							Subprocess process = launcher.spawnv (cmds);
							yield process.wait_async ();
							if (process.get_if_exited ()) {
								status = process.get_exit_status ();
							}
							if (status == 1) {
								// there is a diff
								var dis = new DataInputStream (process.get_stdout_pipe ());
								var dos = new DataOutputStream (yield file.create_async (FileCreateFlags.REPLACE_DESTINATION));
								// writing output to diff
								yield dos.splice_async (dis, 0);
								status = 0;
							}
						} catch (Error e) {
							stderr.printf ("Error: %s\n", e.message);
						}
						launcher.set_flags (SubprocessFlags.NONE);
					}
					// merge modifications
					if (status == 0) {
						cmds = {"git", "merge", "-q"};
						status = yield launch_subprocess (launcher, cmds);
					}
					if (status == 0) {
						return pkgdir;
					} else {
						launcher.set_cwd (config.aur_build_dir);
						cmds = {"rm", "-rf", "%s".printf (pkgdir.get_path ())};
						yield launch_subprocess (launcher, cmds);
						cmds = {"git", "clone", "-q", "--depth=1", "https://aur.archlinux.org/%s.git".printf (pkgname)};
					}
				}
			} else {
				launcher.set_cwd (config.aur_build_dir);
				cmds = {"git", "clone", "-q", "--depth=1", "https://aur.archlinux.org/%s.git".printf (pkgname)};
			}
			status = yield launch_subprocess (launcher, cmds);
			if (status == 0) {
				return pkgdir;
			}
			return null;
		}

		async void populate_aur_infos (string[] pkgnames) {
			string[] names = {};
			foreach (unowned string pkgname in pkgnames) {
				if (!aur_infos.contains (pkgname)) {
					names += pkgname;
				}
			}
			if (names.length > 0) {
				Json.Array results = yield aur_multiinfo (names);
				results.foreach_element ((array, index, node) => {
					unowned Json.Object? json_object = node.get_object ();
					aur_infos.insert (json_object.get_string_member ("Name"), json_object);
				});
			}
		}

		public async AURPackage get_aur_pkg (string pkgname) {
			if (config.enable_aur) {
				yield populate_aur_infos ({pkgname});
				return new AURPackage.from_struct (initialise_aur_struct (aur_infos.lookup (pkgname)));
			} else {
				return new AURPackage ();
			}
		}

		public async HashTable<string, AURPackage> get_aur_pkgs (string[] pkgnames) {
			var data = new HashTable<string, AURPackage> (str_hash, str_equal);
			if (config.enable_aur) {
				yield populate_aur_infos (pkgnames);
				foreach (unowned string pkgname in pkgnames) {
					data.insert (pkgname, new AURPackage.from_struct (initialise_aur_struct (aur_infos.lookup (pkgname))));
				}
			}
			return data;
		}

		AURPackageDetailsStruct initialise_aur_details_struct (Json.Object? json_object) {
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
					licenses += dgettext (null, "Unknown");
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
			var details = AURPackageDetailsStruct ();
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
			return details;
		}

		public async AURPackageDetails get_aur_pkg_details (string pkgname) {
			if (config.enable_aur) {
				yield populate_aur_infos ({pkgname});
				return new AURPackageDetails.from_struct (initialise_aur_details_struct (aur_infos.lookup (pkgname)));
			} else {
				return new AURPackageDetails ();
			}
		}

		public async HashTable<string, AURPackageDetails> get_aur_pkgs_details (string[] pkgnames) {
			var data = new HashTable<string, AURPackageDetails> (str_hash, str_equal);
			if (config.enable_aur) {
				yield populate_aur_infos (pkgnames);
				foreach (unowned string pkgname in pkgnames) {
					data.insert (pkgname, new AURPackageDetails.from_struct (initialise_aur_details_struct (aur_infos.lookup (pkgname))));
				}
			}
			return data;
		}

		public async List<AURPackage> get_aur_updates () {
			// get local pkgs
			string[] local_pkgs = {};
			unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
			while (pkgcache != null) {
				unowned Alpm.Package installed_pkg = pkgcache.data;
				// check if installed_pkg is in IgnorePkg or IgnoreGroup
				if (alpm_handle.should_ignore (installed_pkg) == 0) {
					// check if installed_pkg is a local pkg
					unowned Alpm.Package? pkg = get_syncpkg (installed_pkg.name);
					if (pkg == null) {
						local_pkgs += installed_pkg.name;
					}
				}
				pkgcache.next ();
			}
			return get_aur_updates_real (yield aur_multiinfo (local_pkgs));
		}

		public void refresh_tmp_files_dbs () {
			var tmp_files_handle = alpm_config.get_handle (true, true);
			unowned Alpm.List<unowned Alpm.DB> syncdbs = tmp_files_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				db.update (0);
				syncdbs.next ();
			}
		}

		public async Updates get_updates () {
			// be sure we have the good updates
			alpm_config = new AlpmConfig ("/etc/pacman.conf");
			var tmp_handle = alpm_config.get_handle (false, true);
			var repos_updates = new List<Package> ();
			unowned Alpm.Package? pkg = null;
			unowned Alpm.Package? candidate = null;
			// refresh tmp dbs
			// count this step as 90% of the total
			get_updates_progress (0);
			unowned Alpm.List<unowned Alpm.DB> syncdbs = tmp_handle.syncdbs;
			size_t dbs_count = syncdbs.length;
			size_t i = 0;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				db.update (0);
				syncdbs.next ();
				i++;
				get_updates_progress ((uint) ((double) i / dbs_count * (double) 90));
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
						repos_updates.append (new Package.from_struct (initialise_pkg_struct (candidate)));
					} else {
						if (config.check_aur_updates) {
							// check if installed_pkg is a local pkg
							pkg = get_syncpkg (installed_pkg.name);
							if (pkg == null) {
								local_pkgs += installed_pkg.name;
							}
						}
					}
				}
				pkgcache.next ();
			}
			get_updates_progress (95);
			if (config.check_aur_updates) {
				// count this step as 5% of the total
				get_updates_progress (100);
				return new Updates.from_lists ((owned) repos_updates, get_aur_updates_real (yield aur_multiinfo (local_pkgs)));
			} else {
				get_updates_progress (100);
				return new Updates.from_lists ((owned) repos_updates, new List<AURPackage> ());
			}
		}

		List<AURPackage> get_aur_updates_real (Json.Array aur_updates_json) {
			var aur_updates = new List<AURPackage> ();
			aur_updates_json.foreach_element ((array, index, node) => {
				unowned Json.Object pkg_info = node.get_object ();
				unowned string name = pkg_info.get_string_member ("Name");
				unowned string new_version = pkg_info.get_string_member ("Version");
				unowned string old_version = alpm_handle.localdb.get_pkg (name).version;
				if (Alpm.pkg_vercmp (new_version, old_version) == 1) {
					var infos = initialise_aur_struct (pkg_info);
					infos.installed_version = old_version;
					aur_updates.append (new AURPackage.from_struct ((owned) infos));
				}
			});
			return (owned) aur_updates;
		}
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
