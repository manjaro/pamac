/*
 *  pamac-vala
 *
 *  Copyright (C) 2019 Guillaume Benoit <guillaume@manjaro.org>
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

		class AURUpdates {
			public List<AURPackage> updates;
			public List<AURPackage> outofdate;
			public AURUpdates (owned List<AURPackage> updates, owned List<AURPackage> outofdate) {
				this.updates = (owned) updates;
				this.outofdate = (owned) outofdate;
			}
		}

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
			// load alpm databases in memory
			unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
			unowned Alpm.List<unowned Alpm.Group> groupcache = alpm_handle.localdb.groupcache;
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				pkgcache = db.pkgcache;
				groupcache = db.groupcache;
				syncdbs.next ();
			}
		}

		public void enable_appstream () {
			try {
				app_store.load (As.StoreLoadFlags.APP_INFO_SYSTEM);
				app_store.set_search_match (As.AppSearchMatch.PKGNAME
											| As.AppSearchMatch.DESCRIPTION
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

		public CompareFunc<string> vercmp = Alpm.pkg_vercmp;

		public HashTable<string, int64?> get_clean_cache_details (uint64 keep_nb, bool only_uninstalled) {
			var filenames_size = new HashTable<string, int64?> (str_hash, str_equal);
			var pkg_version_filenames = new HashTable<string, SList<string>> (str_hash, str_equal);
			var pkg_versions = new HashTable<string, SList<string>> (str_hash, str_equal);
			// compute all infos
			unowned Alpm.List<unowned string> cachedirs_names = alpm_handle.cachedirs;
			while (cachedirs_names != null) {
				unowned string cachedir_name = cachedirs_names.data;
				var cachedir = File.new_for_path (cachedir_name);
				try {
					FileEnumerator enumerator = cachedir.enumerate_children ("standard::*", FileQueryInfoFlags.NONE);
					FileInfo info;
					while ((info = enumerator.next_file (null)) != null) {
						unowned string filename = info.get_name ();
						string absolute_filename = "%s%s".printf (cachedir_name, filename);
						string name_version_release = filename.slice (0, filename.last_index_of_char ('-'));
						int release_index = name_version_release.last_index_of_char ('-');
						string name_version = name_version_release.slice (0, release_index);
						int version_index = name_version.last_index_of_char ('-');
						string name = name_version.slice (0, version_index);
						if (only_uninstalled && is_installed_pkg (name)) {
							continue;
						}
						filenames_size.insert (absolute_filename, info.get_size ());
						if (pkg_versions.contains (name)) {
							if (pkg_version_filenames.contains (name_version_release)) {
								// case of .sig file
								unowned SList<string> filenames = pkg_version_filenames.lookup (name_version_release);
								filenames.append (absolute_filename);
							} else {
								unowned SList<string> versions = pkg_versions.lookup (name);
								string version = name_version.slice (version_index + 1, name_version.length);
								string release = name_version_release.slice (release_index + 1, name_version_release.length);
								string version_release = "%s-%s".printf (version, release);
								versions.append ((owned) version_release);
								var filenames = new SList<string> ();
								filenames.append (absolute_filename);
								pkg_version_filenames.insert (name_version_release, (owned) filenames);
							}
						} else {
							var versions = new SList<string> ();
							string version = name_version.slice (version_index + 1, name_version.length);
							string release = name_version_release.slice (release_index + 1, name_version_release.length);
							string version_release = "%s-%s".printf (version, release);
							versions.append ((owned) version_release);
							pkg_versions.insert (name, (owned) versions);
							var filenames = new SList<string> ();
							filenames.append (absolute_filename);
							pkg_version_filenames.insert (name_version_release, (owned) filenames);
						}
					}
				} catch (GLib.Error e) {
					stderr.printf ("Error: %s\n", e.message);
				}
				cachedirs_names.next ();
			}
			if (keep_nb == 0) {
				return filenames_size;
			}
			// filter candidates
			var iter = HashTableIter<string, SList<string>> (pkg_versions);
			unowned string name;
			unowned SList<string> versions;
			while (iter.next (out name, out versions)) {
				// sort versions
				uint length = versions.length ();
				if (length > keep_nb) {
					versions.sort ((version1, version2) => {
						// reverse version 1 and version2 to have higher versions first
						return Alpm.pkg_vercmp (version2, version1);
					});
				}
				uint i = 1;
				foreach (unowned string version in versions) {
					unowned SList<string>? filenames = pkg_version_filenames.lookup ("%s-%s".printf (name, version));
					if (filenames != null) {
						foreach (unowned string filename in filenames) {
							filenames_size.remove (filename);
						}
					}
					i++;
					if (i > keep_nb) {
						break;
					}
				}
			}
			return filenames_size;
		}

		void enumerate_directory (string directory_path, ref HashTable<string, int64?> filenames_size) {
			var directory = GLib.File.new_for_path (directory_path);
			try {
				FileEnumerator enumerator = directory.enumerate_children ("standard::*", FileQueryInfoFlags.NONE);
				FileInfo info;
				while ((info = enumerator.next_file (null)) != null) {
					string absolute_filename = Path.build_path ("/", directory.get_path (), info.get_name ());
					if (info.get_file_type () == FileType.DIRECTORY) {
						enumerate_directory (absolute_filename, ref filenames_size);
					} else {
						filenames_size.insert (absolute_filename, info.get_size ());
					}
				}
			} catch (GLib.Error e) {
				stderr.printf ("Error: %s\n", e.message);
			}
		}

		public HashTable<string, int64?> get_build_files_details (string aur_build_dir) {
			var filenames_size = new HashTable<string, int64?> (str_hash, str_equal);
			enumerate_directory (aur_build_dir, ref filenames_size);
			return filenames_size;
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

		public bool is_installed_pkg (string pkgname) {
			return alpm_handle.localdb.get_pkg (pkgname) != null;
		}

		public Package get_installed_pkg (string pkgname) {
			return initialise_pkg (alpm_handle.localdb.get_pkg (pkgname));
		}

		public Package find_installed_satisfier (string depstring) {
			return initialise_pkg (Alpm.find_satisfier (alpm_handle.localdb.pkgcache, depstring));
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

		public List<string> get_uninstalled_optdeps (string pkgname) {
			var optdeps = new List<string> ();
			unowned Alpm.Package? pkg = get_syncpkg (pkgname);
			if (pkg != null) {
				unowned Alpm.List<unowned Alpm.Depend> optdepends = pkg.optdepends;
				while (optdepends != null) {
					string optdep = optdepends.data.compute_string ();
					unowned Alpm.Package? satisfier = Alpm.find_satisfier (alpm_handle.localdb.pkgcache, optdep);
					if (satisfier == null) {
						optdeps.append ((owned) optdep);
					}
					optdepends.next ();
				}
			}
			return optdeps;
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

		string get_app_launchable (As.App app) {
			As.Launchable? launchable = app.get_launchable_by_kind (As.LaunchableKind.DESKTOP_ID);
			if (launchable != null) {
				return launchable.get_value ();
			}
			return "";
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
						unowned string? url = as_image.get_url ();
						if (url != null) {
							screenshot = url;
						}
					}
				}
			});
			return screenshot;
		}

		SList<As.App> get_pkgname_matching_apps (string pkgname) {
			var matching_apps = new SList<As.App> ();
			app_store.get_apps ().foreach ((app) => {
				if (app.get_kind () == As.AppKind.DESKTOP) {
					if (app.get_pkgname_default () == pkgname) {
						matching_apps.append (app);
					}
				}
			});
			return (owned) matching_apps;
		}

		Package initialise_pkg (Alpm.Package? alpm_pkg) {
			var pkg = new Package ();
			if (alpm_pkg != null) {
				pkg.name = alpm_pkg.name;
				pkg.version = alpm_pkg.version;
				pkg.installed_size = alpm_pkg.isize;
				pkg.download_size = alpm_pkg.download_size;
				pkg.builddate = alpm_pkg.builddate;
				pkg.installdate = alpm_pkg.installdate;
				if (alpm_pkg.desc != null) {
					pkg.desc = alpm_pkg.desc;
				}
				if (alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
					pkg.installed_version = alpm_pkg.version;
					unowned Alpm.Package? sync_pkg = get_syncpkg (alpm_pkg.name);
					if (sync_pkg != null) {
						pkg.repo = sync_pkg.db.name;
					} else if (config.enable_aur) {
						var loop = new MainLoop ();
						get_aur_pkg.begin (alpm_pkg.name, (obj, res) => {
							var aur_pkg = get_aur_pkg.end (res);
							if (aur_pkg.name != "") {
								pkg.repo = dgettext (null, "AUR");
							}
							loop.quit ();
						});
						loop.run ();
					}
				} else if (alpm_pkg.origin == Alpm.Package.From.SYNCDB) {
					unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (alpm_pkg.name);
					if (local_pkg != null) {
						pkg.installed_version = local_pkg.version;
					}
					pkg.repo = alpm_pkg.db.name;
				}
				if (pkg.repo != "" && pkg.repo != dgettext (null, "AUR")) {
					// find if pkgname provides only one app
					var matching_apps = get_pkgname_matching_apps (alpm_pkg.name);
					if (matching_apps.length () == 1) {
						As.App app = matching_apps.nth_data (0);
						pkg.app_name = get_app_name (app);
						pkg.desc = get_app_summary (app);
						pkg.icon = get_app_icon (app, pkg.repo);
					}
				}
			}
			return pkg;
		}

		List<Package> initialise_pkgs (Alpm.List<unowned Alpm.Package>? alpm_pkgs) {
			var pkgs = new List<Package> ();
			var data = new HashTable<string, Package> (str_hash, str_equal);
			string[] foreign_pkgnames = {};
			while (alpm_pkgs != null) {
				unowned Alpm.Package alpm_pkg = alpm_pkgs.data;
				var pkg = new Package ();
				pkg.name = alpm_pkg.name;
				pkg.version = alpm_pkg.version;
				if (alpm_pkg.desc != null) {
					pkg.desc = alpm_pkg.desc;
				}
				pkg.installed_size = alpm_pkg.isize;
				pkg.download_size = alpm_pkg.download_size;
				pkg.builddate = alpm_pkg.builddate;
				pkg.installdate = alpm_pkg.installdate;
				if (alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
					pkg.installed_version = alpm_pkg.version;
					unowned Alpm.Package? sync_pkg = get_syncpkg (alpm_pkg.name);
					if (sync_pkg != null) {
						pkg.repo = sync_pkg.db.name;
					} else if (config.enable_aur) {
						foreign_pkgnames += alpm_pkg.name;
					}
				} else if (alpm_pkg.origin == Alpm.Package.From.SYNCDB) {
					unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (alpm_pkg.name);
					if (local_pkg != null) {
						pkg.installed_version = local_pkg.version;
					}
					pkg.repo = alpm_pkg.db.name;
				}
				if (pkg.repo == "" ) {
					if (config.enable_aur) {
						data.insert (alpm_pkg.name, pkg);
					} else {
						pkgs.append (pkg);
					}
				} else {
					var apps = get_pkgname_matching_apps (alpm_pkg.name);
					if (apps.length () > 0) {
						// alpm_pkg provide some apps
						unowned SList<As.App> apps_list = apps;
						unowned As.App app = apps_list.data;
						pkg.app_name = get_app_name (app);
						pkg.desc = get_app_summary (app);
						pkg.icon = get_app_icon (app, pkg.repo);
						pkgs.append (pkg);
						apps_list = apps_list.next;
						while (apps_list != null) {
							app = apps_list.data;
							var pkg_dup = pkg.dup ();
							pkg_dup.app_name = get_app_name (app);
							pkg_dup.desc = get_app_summary (app);
							pkg_dup.icon = get_app_icon (app, pkg_dup.repo);
							pkgs.append (pkg_dup);
							apps_list = apps_list.next;
						}
					} else {
						pkgs.append (pkg);
					}
				}
				alpm_pkgs.next ();
			}
			// get aur infos
			if (foreign_pkgnames.length > 0) {
				var loop = new MainLoop ();
				get_aur_pkgs.begin (foreign_pkgnames, (obj, res) => {
					var aur_pkgs = get_aur_pkgs.end (res);
					var iter = HashTableIter<string, AURPackage> (aur_pkgs);
					unowned string pkgname;
					unowned AURPackage aur_pkg;
					while (iter.next (out pkgname, out aur_pkg)) {
						if (aur_pkg.name != "") {
							unowned Package pkg = data.lookup (pkgname);
							if (pkg != null) {
								pkg.repo = dgettext (null, "AUR");
							}
						}
					}
					loop.quit ();
				});
				loop.run ();
				var iter = HashTableIter<string, Package> (data);
				unowned Package pkg;
				while (iter.next (null, out pkg)) {
					pkgs.append (pkg);
				}
			}
			return pkgs;
		}

		public List<Package> get_installed_pkgs () {
			var pkgs = initialise_pkgs (alpm_handle.localdb.pkgcache);
			pkgs.sort (pkg_compare_name);
			return pkgs;
		}

		public List<Package> get_installed_apps () {
			var result = new List<Package> ();
			app_store.get_apps ().foreach ((app) => {
				if (app.get_kind () == As.AppKind.DESKTOP) {
					unowned string pkgname = app.get_pkgname_default ();
					unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (pkgname);
					if (local_pkg != null) {
						unowned Alpm.Package? sync_pkg = get_syncpkg (pkgname);
						if (sync_pkg != null) {
							var pkg = new Package ();
							pkg.name = sync_pkg.name;
							pkg.app_name = get_app_name (app);
							pkg.version = sync_pkg.version;
							pkg.installed_version = local_pkg.version;
							pkg.desc = get_app_summary (app);
							pkg.repo = sync_pkg.db.name;
							pkg.installed_size = local_pkg.isize;
							pkg.download_size = sync_pkg.download_size;
							pkg.builddate = local_pkg.builddate;
							pkg.installdate = local_pkg.installdate;
							pkg.icon = get_app_icon (app, sync_pkg.db.name);
							result.append (pkg);
						}
					}
				}
			});
			return (owned) result;
		}

		public List<Package> get_explicitly_installed_pkgs () {
			Alpm.List<unowned Alpm.Package> alpm_pkgs = null;
			unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
			while (pkgcache != null) {
				unowned Alpm.Package alpm_pkg = pkgcache.data;
				if (alpm_pkg.reason == Alpm.Package.Reason.EXPLICIT) {
					alpm_pkgs.add (alpm_pkg);
				}
				pkgcache.next ();
			}
			var pkgs = initialise_pkgs (alpm_pkgs);
			pkgs.sort (pkg_compare_name);
			return pkgs;
		}

		public List<Package> get_foreign_pkgs () {
			Alpm.List<unowned Alpm.Package> alpm_pkgs = null;
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
					alpm_pkgs.add (alpm_pkg);
				}
				pkgcache.next ();
			}
			var pkgs = initialise_pkgs (alpm_pkgs);
			pkgs.sort (pkg_compare_name);
			return pkgs;
		}

		public List<Package> get_orphans () {
			Alpm.List<unowned Alpm.Package> alpm_pkgs = null;
			unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
			while (pkgcache != null) {
				unowned Alpm.Package alpm_pkg = pkgcache.data;
				if (alpm_pkg.reason == Alpm.Package.Reason.DEPEND) {
					Alpm.List<string> requiredby = alpm_pkg.compute_requiredby ();
					if (requiredby.length == 0) {
						Alpm.List<string> optionalfor = alpm_pkg.compute_optionalfor ();
						if (optionalfor.length == 0) {
							alpm_pkgs.add (alpm_pkg);
						} else {
							optionalfor.free_inner (GLib.free);
						}
					} else {
						requiredby.free_inner (GLib.free);
					}
				}
				pkgcache.next ();
			}
			var pkgs = initialise_pkgs (alpm_pkgs);
			pkgs.sort (pkg_compare_name);
			return pkgs;
		}

		public async List<Package> get_installed_pkgs_async () {
			var pkgs = new List<Package> ();
			new Thread<int> ("get_installed_pkgs", () => {
				pkgs =  get_installed_pkgs ();
				Idle.add (get_installed_pkgs_async.callback);
				return 0;
			});
			yield;
			return (owned) pkgs;
		}

		public async List<Package> get_installed_apps_async () {
			var pkgs = new List<Package> ();
			new Thread<int> ("get_installed_apps", () => {
				pkgs =  get_installed_apps ();
				Idle.add (get_installed_apps_async.callback);
				return 0;
			});
			yield;
			return (owned) pkgs;
		}

		public async List<Package> get_explicitly_installed_pkgs_async () {
			var pkgs = new List<Package> ();
			new Thread<int> ("get_explicitly_installed_pkgs", () => {
				pkgs =  get_explicitly_installed_pkgs ();
				Idle.add (get_explicitly_installed_pkgs_async.callback);
				return 0;
			});
			yield;
			return (owned) pkgs;
		}

		public async List<Package> get_foreign_pkgs_async () {
			var pkgs = new List<Package> ();
			new Thread<int> ("get_foreign_pkgs", () => {
				pkgs =  get_foreign_pkgs ();
				Idle.add (get_foreign_pkgs_async.callback);
				return 0;
			});
			yield;
			return (owned) pkgs;
		}

		public async List<Package> get_orphans_async () {
			var pkgs = new List<Package> ();
			new Thread<int> ("get_orphans", () => {
				pkgs =  get_orphans ();
				Idle.add (get_orphans_async.callback);
				return 0;
			});
			yield;
			return (owned) pkgs;
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

		public bool is_sync_pkg (string pkgname) {
			return get_syncpkg (pkgname) != null;
		}

		public Package get_sync_pkg (string pkgname) {
			return initialise_pkg (get_syncpkg (pkgname));
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
			return initialise_pkg (find_dbs_satisfier (depstring));
		}

		Alpm.List<unowned Alpm.Package> search_local_db (string search_string) {
			Alpm.List<unowned string> needles = null;
			string[] splitted = search_string.split (" ");
			foreach (unowned string part in splitted) {
				needles.add (part);
			}
			Alpm.List<unowned Alpm.Package> result = alpm_handle.localdb.search (needles);
			// search in appstream
			string[]? search_terms = As.utils_search_tokenize (search_string);
			if (search_terms != null) {
				Alpm.List<unowned Alpm.Package> appstream_result = null;
				app_store.get_apps ().foreach ((app) => {
					if (app.get_kind () == As.AppKind.DESKTOP) {
						uint match_score = app.search_matches_all (search_terms);
						if (match_score > 0) {
							unowned string pkgname = app.get_pkgname_default ();
							unowned Alpm.Package? alpm_pkg = alpm_handle.localdb.get_pkg (pkgname);
							if (alpm_pkg != null) {
								if (appstream_result.find (alpm_pkg, (Alpm.List.CompareFunc) alpm_pkg_compare_name) == null) {
									appstream_result.add (alpm_pkg);
								}
							}
						}
					}
				});
				result.join (appstream_result.diff (result, (Alpm.List.CompareFunc) alpm_pkg_compare_name));
			}
			return result;
		}

		Alpm.List<unowned Alpm.Package> search_sync_dbs (string search_string) {
			Alpm.List<unowned string> needles = null;
			string[] splitted = search_string.split (" ");
			foreach (unowned string part in splitted) {
				needles.add (part);
			}
			Alpm.List<unowned Alpm.Package> localpkgs = alpm_handle.localdb.search (needles);
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
			// remove localpkgs
			Alpm.List<unowned Alpm.Package> result = syncpkgs.diff (localpkgs, (Alpm.List.CompareFunc) alpm_pkg_compare_name);
			// search in appstream
			string[]? search_terms = As.utils_search_tokenize (search_string);
			if (search_terms != null) {
				Alpm.List<unowned Alpm.Package> appstream_result = null;
				app_store.get_apps ().foreach ((app) => {
					if (app.get_kind () == As.AppKind.DESKTOP) {
						uint match_score = app.search_matches_all (search_terms);
						if (match_score > 0) {
							unowned string pkgname = app.get_pkgname_default ();
							unowned Alpm.Package? alpm_pkg = alpm_handle.localdb.get_pkg (pkgname);
							if (alpm_pkg == null) {
								alpm_pkg = get_syncpkg (pkgname);
								if (alpm_pkg != null) {
									if (appstream_result.find (alpm_pkg, (Alpm.List.CompareFunc) alpm_pkg_compare_name) == null) {
										appstream_result.add (alpm_pkg);
									}
								}
							}
						}
					}
				});
				result.join (appstream_result.diff (result, (Alpm.List.CompareFunc) alpm_pkg_compare_name));
			}
			return result;
		}

		public List<Package> search_installed_pkgs (string search_string) {
			var pkgs = initialise_pkgs (search_local_db (search_string));
			// use custom sort function
			global_search_string = search_string;
			pkgs.sort (pkg_sort_search_by_relevance);
			return pkgs;
		}

		public async List<Package> search_installed_pkgs_async (string search_string) {
			var pkgs = new List<Package> ();
			new Thread<int> ("search_installed_pkgs", () => {
				pkgs =  search_installed_pkgs (search_string);
				Idle.add (search_installed_pkgs_async.callback);
				return 0;
			});
			yield;
			return (owned) pkgs;
		}

		public List<Package> search_repos_pkgs (string search_string) {
			var pkgs = initialise_pkgs (search_sync_dbs (search_string));
			// use custom sort function
			global_search_string = search_string;
			pkgs.sort (pkg_sort_search_by_relevance);
			return pkgs;
		}

		public async List<Package> search_repos_pkgs_async (string search_string) {
			var pkgs = new List<Package> ();
			new Thread<int> ("search_repos_pkgs", () => {
				pkgs =  search_repos_pkgs (search_string);
				Idle.add (search_repos_pkgs_async.callback);
				return 0;
			});
			yield;
			return (owned) pkgs;
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
			string[]? search_terms = As.utils_search_tokenize (search_string);
			if (search_terms != null) {
				Alpm.List<unowned Alpm.Package> appstream_result = null;
				app_store.get_apps ().foreach ((app) => {
					if (app.get_kind () == As.AppKind.DESKTOP) {
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
					}
				});
				result.join (appstream_result.diff (result, (Alpm.List.CompareFunc) alpm_pkg_compare_name));
			}
			return result;
		}

		public List<Package> search_pkgs (string search_string) {
			var pkgs = initialise_pkgs (search_all_dbs (search_string));
			// use custom sort function
			global_search_string = search_string;
			pkgs.sort (pkg_sort_search_by_relevance);
			return pkgs;
		}

		public async List<Package> search_pkgs_async (string search_string) {
			var pkgs = new List<Package> ();
			new Thread<int> ("search_pkgs", () => {
				pkgs =  search_pkgs (search_string);
				Idle.add (search_pkgs_async.callback);
				return 0;
			});
			yield;
			return (owned) pkgs;
		}

		AURPackage initialise_aur_pkg (Json.Object? json_object) {
			var aur_pkg = new AURPackage ();
			if (json_object == null) {
				return aur_pkg;
			}
			aur_pkg.name = json_object.get_string_member ("Name");
			aur_pkg.version = json_object.get_string_member ("Version");
			// desc can be null
			aur_pkg.desc = json_object.get_null_member ("Description") ? "" : json_object.get_string_member ("Description");
			aur_pkg.popularity = json_object.get_double_member ("Popularity");
			aur_pkg.packagebase = json_object.get_string_member ("PackageBase");
			aur_pkg.lastmodified = (uint64) json_object.get_int_member ("LastModified");
			unowned Alpm.Package? pkg = alpm_handle.localdb.get_pkg (json_object.get_string_member ("Name"));
			if (pkg != null) {
				aur_pkg.installed_version = pkg.version;
			}
			// set out of date
			unowned Json.Node? out_node = json_object.get_member ("OutOfDate");
			if (out_node != null) {
				aur_pkg.outofdate = (uint64) out_node.get_int ();
			}
			return aur_pkg;
		}

		public async List<AURPackage> search_in_aur (string search_string) {
			if (!aur_search_results.contains (search_string)) {
				Json.Array pkgs = yield aur_search (search_string.split (" "));
				aur_search_results.insert (search_string, pkgs);
			}
			var result = new List<AURPackage> ();
			var json_array = aur_search_results.get (search_string);
			json_array.foreach_element ((array, index, node) => {
				Json.Object json_object = node.get_object ();
				// remove results which is installed or exist in repos
				if (alpm_handle.localdb.get_pkg (json_object.get_string_member ("Name")) == null
					&& get_syncpkg (json_object.get_string_member ("Name")) == null) {
					result.append (initialise_aur_pkg (json_object));
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
							var real_file_name = new StringBuilder (alpm_handle.root);
							real_file_name.append (file_ptr->name);
							if (file in real_file_name.str) {
								found_files += (owned) real_file_name.str;
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
									found_files += (owned) real_file_name.str;
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
							var pkg = new Package ();
							pkg.name = sync_pkg.name;
							pkg.app_name = get_app_name (app);
							pkg.version = sync_pkg.version;
							pkg.installed_version = installed_version;
							pkg.desc = get_app_summary (app);
							pkg.repo = repo_name;
							pkg.installed_size = sync_pkg.isize;
							pkg.download_size = sync_pkg.download_size;
							pkg.icon = get_app_icon (app, sync_pkg.db.name);
							result.append (pkg);
						}
					}
				});
			});
			return (owned) result;
		}

		public async List<Package> get_category_pkgs_async (string category) {
			var pkgs = new List<Package> ();
			new Thread<int> ("get_category_pkgs", () => {
				pkgs =  get_category_pkgs (category);
				Idle.add (get_category_pkgs_async.callback);
				return 0;
			});
			yield;
			return (owned) pkgs;
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
			Alpm.List<unowned Alpm.Package> alpm_pkgs = null;
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				if (db.name == repo) {
					unowned Alpm.List<unowned Alpm.Package> pkgcache = db.pkgcache;
					while (pkgcache != null) {
						unowned Alpm.Package sync_pkg = pkgcache.data;
						unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (sync_pkg.name);
						if (local_pkg != null) {
							alpm_pkgs.add (local_pkg);
						} else {
							alpm_pkgs.add (sync_pkg);
						}
						pkgcache.next ();
					}
					break;
				}
				syncdbs.next ();
			}
			var pkgs = initialise_pkgs (alpm_pkgs);
			pkgs.sort (pkg_compare_name);
			return pkgs;
		}

		public async List<Package> get_repo_pkgs_async (string repo) {
			var pkgs = new List<Package> ();
			new Thread<int> ("get_repo_pkgs", () => {
				pkgs =  get_repo_pkgs (repo);
				Idle.add (get_repo_pkgs_async.callback);
				return 0;
			});
			yield;
			return (owned) pkgs;
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
			var pkgs = initialise_pkgs (group_pkgs (group_name));
			pkgs.sort (pkg_compare_name);
			return pkgs;
		}

		public async List<Package> get_group_pkgs_async (string group_name) {
			var pkgs = new List<Package> ();
			new Thread<int> ("get_group_pkgs", () => {
				pkgs =  get_group_pkgs (group_name);
				Idle.add (get_group_pkgs_async.callback);
				return 0;
			});
			yield;
			return (owned) pkgs;
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
			var details = new PackageDetails ();
			unowned Alpm.Package? alpm_pkg = alpm_handle.localdb.get_pkg (pkgname);
			unowned Alpm.Package? sync_pkg = get_syncpkg (pkgname);
			if (alpm_pkg != null) {
				details.installed_version = alpm_pkg.version;
			}
			if (alpm_pkg == null || use_sync_pkg) {
				alpm_pkg = sync_pkg;
			}
			if (alpm_pkg != null) {
				// name
				details.name = alpm_pkg.name;
				// version
				details.version = alpm_pkg.version;
				// desc can be null
				if (alpm_pkg.desc != null) {
					details.desc = alpm_pkg.desc;
				}
				if (sync_pkg != null) {
					if (appname != "") {
						bool found = false;
						app_store.get_apps ().foreach ((app) => {
							if (!found && app.get_kind () == As.AppKind.DESKTOP
								&& get_app_name (app) == appname) {
								found = true;
								if (app.get_pkgname_default () == alpm_pkg.name) {
									details.app_name = appname;
									details.launchable = get_app_launchable (app);
									details.desc = get_app_summary (app);
									try {
										details.long_desc = As.markup_convert_simple (get_app_description (app));
									} catch (Error e) {
										stderr.printf ("Error: %s\n", e.message);
									}
									details.icon = get_app_icon (app, sync_pkg.db.name);
									details.screenshot = get_app_screenshot (app);
								}
							}
						});
					} else {
						// find if pkgname provides only one app
						var matching_apps = get_pkgname_matching_apps (pkgname);
						if (matching_apps.length () == 1) {
							As.App app = matching_apps.nth_data (0);
							details.app_name = get_app_name (app);
							details.launchable = get_app_launchable (app);
							details.desc = get_app_summary (app);
							try {
								details.long_desc = As.markup_convert_simple (get_app_description (app));
							} catch (Error e) {
								stderr.printf ("Error: %s\n", e.message);
							}
							details.icon = get_app_icon (app, sync_pkg.db.name);
							details.screenshot = get_app_screenshot (app);
						}
					}
				}
				details.installed_size = alpm_pkg.isize;
				// url can be null
				if (alpm_pkg.url != null) {
					details.url = alpm_pkg.url;
				}
				// packager can be null
				details.packager = alpm_pkg.packager ?? "";
				// groups
				unowned Alpm.List<unowned string> list = alpm_pkg.groups;
				while (list != null) {
					details.groups_priv.append (list.data);
					list.next ();
				}
				// licenses
				list = alpm_pkg.licenses;
				while (list != null) {
					details.licenses_priv.append (list.data);
					list.next ();
				}
				// build_date
				details.builddate = alpm_pkg.builddate;
				// local pkg
				if (alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
					// repo
					if (sync_pkg != null) {
						details.repo = sync_pkg.db.name;
					} else if (config.enable_aur) {
						var loop = new MainLoop ();
						get_aur_pkg.begin (alpm_pkg.name, (obj, res) => {
							var aur_pkg = get_aur_pkg.end (res);
							if (aur_pkg.name != "") {
								details.repo = dgettext (null, "AUR");
							}
							loop.quit ();
						});
						loop.run ();
					}
					// reason
					if (alpm_pkg.reason == Alpm.Package.Reason.EXPLICIT) {
						details.reason = dgettext (null, "Explicitly installed");
					} else if (alpm_pkg.reason == Alpm.Package.Reason.DEPEND) {
						details.reason = dgettext (null, "Installed as a dependency for another package");
					} else {
						details.reason = dgettext (null, "Unknown");
					}
					// install_date
					details.installdate = alpm_pkg.installdate;
					// backups
					unowned Alpm.List<unowned Alpm.Backup> backups_list = alpm_pkg.backups;
					while (backups_list != null) {
						details.backups_priv.append ("/" + backups_list.data.name);
						backups_list.next ();
					}
					// requiredby
					Alpm.List<string> pkg_requiredby = alpm_pkg.compute_requiredby ();
					unowned Alpm.List<string> string_list = pkg_requiredby;
					while (string_list != null) {
						details.requiredby_priv.append ((owned) string_list.data);
						string_list.next ();
					}
					// optionalfor
					Alpm.List<string> pkg_optionalfor = alpm_pkg.compute_optionalfor ();
					string_list = pkg_optionalfor;
					while (string_list != null) {
						details.optionalfor_priv.append ((owned) string_list.data);
						string_list.next ();
					}
				// sync pkg
				} else if (alpm_pkg.origin == Alpm.Package.From.SYNCDB) {
					// repos
					details.repo = alpm_pkg.db.name;
					// signature
					if (alpm_pkg.base64_sig != null) {
						details.has_signature = dgettext (null, "Yes");
					} else {
						details.has_signature = dgettext (null, "No");
					}
				}
				// depends
				unowned Alpm.List<unowned Alpm.Depend> depends_list = alpm_pkg.depends;
				while (depends_list != null) {
					details.depends_priv.append (depends_list.data.compute_string ());
					depends_list.next ();
				}
				// optdepends
				depends_list = alpm_pkg.optdepends;
				while (depends_list != null) {
					details.optdepends_priv.append (depends_list.data.compute_string ());
					depends_list.next ();
				}
				// provides
				depends_list = alpm_pkg.provides;
				while (depends_list != null) {
					details.provides_priv.append (depends_list.data.compute_string ());
					depends_list.next ();
				}
				// replaces
				depends_list = alpm_pkg.replaces;
				while (depends_list != null) {
					details.replaces_priv.append (depends_list.data.compute_string ());
					depends_list.next ();
				}
				// conflicts
				depends_list = alpm_pkg.conflicts;
				while (depends_list != null) {
					details.conflicts_priv.append (depends_list.data.compute_string ());
					depends_list.next ();
				}
			}
			return details;
		}

		public List<string> get_pkg_files (string pkgname) {
			var files = new List<string> ();
			unowned Alpm.Package? alpm_pkg = alpm_handle.localdb.get_pkg (pkgname);
			if (alpm_pkg != null) {
				unowned Alpm.FileList filelist = alpm_pkg.files;
				Alpm.File* file_ptr = filelist.files;
				for (size_t i = 0; i < filelist.count; i++, file_ptr++) {
					if (!file_ptr->name.has_suffix ("/")) {
						var filename = new StringBuilder (alpm_handle.root);
						filename.append (file_ptr->name);
						files.append ((owned) filename.str);
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
								var filename = new StringBuilder (alpm_handle.root);
								filename.append (file_ptr->name);
								files.append ((owned) filename.str);
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
			var files = new List<string> ();
			new Thread<int> ("get_pkg_files", () => {
				files =  get_pkg_files (pkgname);
				Idle.add (get_pkg_files_async.callback);
				return 0;
			});
			yield;
			return (owned) files;
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
							// don't show .SRCINFO diff
							while ((info = enumerator.next_file (null)) != null) {
								unowned string filename = info.get_name ();
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
						launcher.set_flags (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
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

		public async bool regenerate_srcinfo (string pkgname, Cancellable? cancellable = null) {
			string pkgdir_name = Path.build_path ("/", config.aur_build_dir, pkgname);
			var srcinfo = File.new_for_path (Path.build_path ("/", pkgdir_name, ".SRCINFO"));
			var pkgbuild = File.new_for_path (Path.build_path ("/", pkgdir_name, "PKGBUILD"));
			// check if PKGBUILD was modified after .SRCINFO
			try {
				FileInfo info = srcinfo.query_info ("time::modified", 0);
				TimeVal srcinfo_time = info.get_modification_time ();
				info = pkgbuild.query_info ("time::modified", 0);
				TimeVal pkgbuild_time = info.get_modification_time ();
				if (pkgbuild_time.tv_sec <= srcinfo_time.tv_sec) {
					// no need to regenerate
					return true;
				}
			} catch (Error e) {
				stderr.printf ("Error: %s\n", e.message);
			}
			// generate .SRCINFO
			var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);
			launcher.set_cwd (pkgdir_name);
			try {
				Subprocess process = launcher.spawnv ({"makepkg", "--printsrcinfo"});
				try {
					yield process.wait_async (cancellable);
					if (process.get_if_exited ()) {
						if (process.get_exit_status () == 0) {
							try {
								var dis = new DataInputStream (process.get_stdout_pipe ());
								var file = File.new_for_path (Path.build_path ("/", pkgdir_name, ".SRCINFO"));
								// delete the file before rewrite it
								yield file.delete_async ();
								// creating a DataOutputStream to the file
								var dos = new DataOutputStream (yield file.create_async (FileCreateFlags.REPLACE_DESTINATION));
								// writing makepkg output to .SRCINFO
								yield dos.splice_async (dis, 0);
								return true;
							} catch (Error e) {
								stderr.printf ("Error: %s\n", e.message);
							}
						}
					}
				} catch (Error e) {
					// cancelled
					process.send_signal (Posix.Signal.INT);
					process.send_signal (Posix.Signal.KILL);
				}
			} catch (Error e) {
				stderr.printf ("Error: %s\n", e.message);
			}
			return false;
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
				return initialise_aur_pkg (aur_infos.lookup (pkgname));
			} else {
				return new AURPackage ();
			}
		}

		public async HashTable<string, AURPackage> get_aur_pkgs (string[] pkgnames) {
			var data = new HashTable<string, AURPackage> (str_hash, str_equal);
			if (config.enable_aur) {
				yield populate_aur_infos (pkgnames);
				foreach (unowned string pkgname in pkgnames) {
					data.insert (pkgname, initialise_aur_pkg (aur_infos.lookup (pkgname)));
				}
			}
			return data;
		}

		AURPackageDetails initialise_aur_details (Json.Object? json_object) {
			var aur_details = new AURPackageDetails ();
			if (json_object != null) {
				// name
				aur_details.name = json_object.get_string_member ("Name");
				// version
				aur_details.version = json_object.get_string_member ("Version");
				// desc can be null
				if (!json_object.get_null_member ("Description")) {
					aur_details.desc = json_object.get_string_member ("Description");
				}
				aur_details.popularity = json_object.get_double_member ("Popularity");
				// packagebase
				aur_details.packagebase = json_object.get_string_member ("PackageBase");
				// url can be null
				unowned Json.Node? node = json_object.get_member ("URL");
				if (node != null) {
					aur_details.url = node.get_string ();
				}
				// maintainer can be null
				node = json_object.get_member ("Maintainer");
				if (node != null) {
					aur_details.maintainer = node.get_string ();
				}
				// firstsubmitted
				aur_details.firstsubmitted = (uint64) json_object.get_int_member ("FirstSubmitted");
				// lastmodified
				aur_details.lastmodified = (uint64) json_object.get_int_member ("LastModified");
				// outofdate can be null
				node = json_object.get_member ("OutOfDate");
				if (node != null) {
					aur_details.outofdate = (uint64) node.get_int ();
				}
				//numvotes
				aur_details.numvotes = (uint64) json_object.get_int_member ("NumVotes");
				// licenses
				node = json_object.get_member ("License");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						aur_details.licenses_priv.append (_node.get_string ());
					});
				} else {
					aur_details.licenses_priv.append (dgettext (null, "Unknown"));
				}
				// depends
				node = json_object.get_member ("Depends");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						aur_details.depends_priv.append (_node.get_string ());
					});
				}
				// optdepends
				node = json_object.get_member ("OptDepends");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						aur_details.optdepends_priv.append (_node.get_string ());
					});
				}
				// makedepends
				node = json_object.get_member ("MakeDepends");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						aur_details.makedepends_priv.append (_node.get_string ());
					});
				}
				// checkdepends
				node = json_object.get_member ("CheckDepends");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						aur_details.checkdepends_priv.append (_node.get_string ());
					});
				}
				// provides
				node = json_object.get_member ("Provides");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						aur_details.provides_priv.append (_node.get_string ());
					});
				}
				// replaces
				node = json_object.get_member ("Replaces");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						aur_details.replaces_priv.append (_node.get_string ());
					});
				}
				// conflicts
				node = json_object.get_member ("Conflicts");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						aur_details.conflicts_priv.append (_node.get_string ());
					});
				}
			}
			return aur_details;
		}

		public async AURPackageDetails get_aur_pkg_details (string pkgname) {
			if (config.enable_aur) {
				yield populate_aur_infos ({pkgname});
				return initialise_aur_details (aur_infos.lookup (pkgname));
			} else {
				return new AURPackageDetails ();
			}
		}

		public async HashTable<string, AURPackageDetails> get_aur_pkgs_details (string[] pkgnames) {
			var data = new HashTable<string, AURPackageDetails> (str_hash, str_equal);
			if (config.enable_aur) {
				yield populate_aur_infos (pkgnames);
				foreach (unowned string pkgname in pkgnames) {
					data.insert (pkgname, initialise_aur_details (aur_infos.lookup (pkgname)));
				}
			}
			return data;
		}

		public string[] get_srcinfo_pkgnames (string pkgdir) {
			string[] pkgnames = {};
			var srcinfo = File.new_for_path (Path.build_path ("/", config.aur_build_dir, pkgdir, ".SRCINFO"));
			if (srcinfo.query_exists ()) {
				try {
					// read .SRCINFO
					var dis = new DataInputStream (srcinfo.read ());
					string line;
					while ((line = dis.read_line ()) != null) {
						if ("pkgname = " in line) {
							string pkgname = line.split (" = ", 2)[1];
							pkgnames += (owned) pkgname;
						}
					}
				} catch (GLib.Error e) {
					stderr.printf ("Error: %s\n", e.message);
				}
			}
			return pkgnames;
		}

		public async List<AURPackage> get_aur_updates () {
			// get local pkgs
			string[] local_pkgs = {};
			string[] vcs_local_pkgs = {};
			unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
			while (pkgcache != null) {
				unowned Alpm.Package installed_pkg = pkgcache.data;
				// check if installed_pkg is in IgnorePkg or IgnoreGroup
				if (alpm_handle.should_ignore (installed_pkg) == 0) {
					// check if installed_pkg is a local pkg
					unowned Alpm.Package? pkg = get_syncpkg (installed_pkg.name);
					if (pkg == null) {
						if (config.check_aur_vcs_updates &&
							(installed_pkg.name.has_suffix ("-git")
							|| installed_pkg.name.has_suffix ("-svn")
							|| installed_pkg.name.has_suffix ("-bzr")
							|| installed_pkg.name.has_suffix ("-hg"))) {
							vcs_local_pkgs += installed_pkg.name;
						} else {
							local_pkgs += installed_pkg.name;
						}
					}
				}
				pkgcache.next ();
			}
			Json.Array aur_infos = yield aur_multiinfo (local_pkgs);
			AURUpdates aur_updates = yield get_aur_updates_real (aur_infos, vcs_local_pkgs);
			return (owned) aur_updates.updates;
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
			SourceFunc callback = get_updates.callback;
			// be sure we have the good updates
			alpm_config = new AlpmConfig ("/etc/pacman.conf");
			string[] local_pkgs = {};
			string[] vcs_local_pkgs = {};
			var repos_updates = new List<Package> ();
			get_updates_progress (0);
			ThreadFunc<int> run = () => {
				var tmp_handle = alpm_config.get_handle (false, true);
				// refresh tmp dbs
				// count this step as 90% of the total
				unowned Alpm.List<unowned Alpm.DB> syncdbs = tmp_handle.syncdbs;
				size_t dbs_count = syncdbs.length;
				size_t i = 0;
				while (syncdbs != null) {
					unowned Alpm.DB db = syncdbs.data;
					db.update (0);
					syncdbs.next ();
					i++;
					Idle.add (() => {
						get_updates_progress ((uint) ((double) i / dbs_count * (double) 90));
						return false;
					});
				}
				// check updates
				// count this step as 5% of the total
				unowned Alpm.List<unowned Alpm.Package> pkgcache = tmp_handle.localdb.pkgcache;
				while (pkgcache != null) {
					unowned Alpm.Package installed_pkg = pkgcache.data;
					// check if installed_pkg is in IgnorePkg or IgnoreGroup
					if (tmp_handle.should_ignore (installed_pkg) == 0) {
						unowned Alpm.Package? candidate = installed_pkg.sync_newversion (tmp_handle.syncdbs);
						if (candidate != null) {
							repos_updates.append (initialise_pkg (candidate));
						} else {
							if (config.check_aur_updates) {
								// check if installed_pkg is a local pkg
								unowned Alpm.Package? pkg = get_syncpkg (installed_pkg.name);
								if (pkg == null) {
									if (config.check_aur_vcs_updates &&
										(installed_pkg.name.has_suffix ("-git")
										|| installed_pkg.name.has_suffix ("-svn")
										|| installed_pkg.name.has_suffix ("-bzr")
										|| installed_pkg.name.has_suffix ("-hg"))) {
										vcs_local_pkgs += installed_pkg.name;
									} else {
										local_pkgs += installed_pkg.name;
									}
								}
							}
						}
					}
					pkgcache.next ();
				}
				Idle.add ((owned) callback);
				return 0;
			};
			new Thread<int> ("get_updates", run);
			yield;
			get_updates_progress (95);
			if (config.check_aur_updates) {
				// count this step as 5% of the total
				get_updates_progress (100);
				Json.Array aur_infos = yield aur_multiinfo (local_pkgs);
				AURUpdates aur_updates = yield get_aur_updates_real (aur_infos, vcs_local_pkgs);
				return new Updates.from_lists ((owned) repos_updates, (owned) aur_updates.updates, (owned) aur_updates.outofdate);
			} else {
				get_updates_progress (100);
				return new Updates.from_lists ((owned) repos_updates, new List<AURPackage> (), new List<AURPackage> ());
			}
		}

		async List<AURPackage> get_vcs_last_version (string[] vcs_local_pkgs) {
			var vcs_packages = new List<AURPackage> ();
			var already_checked =  new GenericSet<string?> (str_hash, str_equal);
			foreach (unowned string pkgname in vcs_local_pkgs) {
				if (already_checked.contains (pkgname)) {
					continue;
				}
				// get last build files
				File? clone_dir = yield clone_build_files (pkgname, false);
				if (clone_dir != null) {
					// get last sources
					// no output to not pollute checkupdates output
					var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
					launcher.set_cwd (clone_dir.get_path ());
					string[] cmds = {"makepkg", "--nobuild", "--noprepare"};
					int status = yield launch_subprocess (launcher, cmds);
					if (status == 0) {
						bool success = yield regenerate_srcinfo (clone_dir.get_basename ());
						if (success) {
							var srcinfo = clone_dir.get_child (".SRCINFO");
							try {
								// read .SRCINFO
								var dis = new DataInputStream (srcinfo.read ());
								string line;
								string current_section = "";
								bool current_section_is_pkgbase = true;
								var version = new StringBuilder ("");
								string pkgbase = "";
								string desc = "";
								var pkgnames_found = new SList<string> ();
								var pkgnames_table = new HashTable<string, AURPackage> (str_hash, str_equal);
								while ((line = yield dis.read_line_async ()) != null) {
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
									} else if ("pkgname = " in line) {
										string pkgname_found = line.split (" = ", 2)[1];
										current_section = pkgname_found;
										current_section_is_pkgbase = false;
										if (pkgname_found in vcs_local_pkgs) {
											var aur_pkg = new AURPackage ();
											aur_pkg.name = pkgname_found;
											aur_pkg.version = version.str;
											aur_pkg.installed_version = alpm_handle.localdb.get_pkg (pkgname_found).version;
											aur_pkg.desc = desc;
											aur_pkg.packagebase = pkgbase;
											pkgnames_table.insert (pkgname_found, aur_pkg);
											pkgnames_found.append (pkgname_found);
											already_checked.add ((owned) pkgname_found);
										}
									}
								}
								foreach (unowned string pkgname_found in pkgnames_found) {
									AURPackage? aur_pkg = pkgnames_table.take (pkgname_found);
									vcs_packages.append (aur_pkg);
								}
							} catch (GLib.Error e) {
								stderr.printf ("Error: %s\n", e.message);
								continue;
							}
						}
					}
				}
			}
			return vcs_packages;
		}

		async AURUpdates get_aur_updates_real (Json.Array aur_infos, string[] vcs_local_pkgs) {
			var updates = new List<AURPackage> ();
			var outofdate = new List<AURPackage> ();
			if (config.check_aur_vcs_updates) {
				var vcs_updates = yield get_vcs_last_version (vcs_local_pkgs);
				foreach (unowned AURPackage aur_pkg in vcs_updates) {
					if (Alpm.pkg_vercmp (aur_pkg.version, aur_pkg.installed_version) == 1) {
						updates.append (aur_pkg);
					}
				}
			}
			aur_infos.foreach_element ((array, index, node) => {
				unowned Json.Object pkg_info = node.get_object ();
				unowned string name = pkg_info.get_string_member ("Name");
				unowned string new_version = pkg_info.get_string_member ("Version");
				unowned string old_version = alpm_handle.localdb.get_pkg (name).version;
				if (Alpm.pkg_vercmp (new_version, old_version) == 1) {
					updates.append (initialise_aur_pkg (pkg_info));
				} else if (pkg_info.get_member ("OutOfDate") != null) {
					// get out of date packages
					outofdate.append (initialise_aur_pkg (pkg_info));
				}
			});
			return new AURUpdates ((owned) updates, (owned) outofdate);
		}
	}
}

private int alpm_pkg_compare_name (Alpm.Package pkg_a, Alpm.Package pkg_b) {
	return strcmp (pkg_a.name, pkg_b.name);
}

private int pkg_compare_name (Pamac.Package pkg_a, Pamac.Package pkg_b) {
	return strcmp (pkg_a.name, pkg_b.name);
}

private string global_search_string;

private int pkg_sort_search_by_relevance (Pamac.Package pkg_a, Pamac.Package pkg_b) {
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
