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

		class AURUpdates {
			public List<AURPackage> updates;
			public List<AURPackage> outofdate;
			public AURUpdates (owned List<AURPackage> updates, owned List<AURPackage> outofdate) {
				this.updates = (owned) updates;
				this.outofdate = (owned) outofdate;
			}
		}

		AlpmConfig alpm_config;
		Alpm.Handle? alpm_handle;
		Alpm.Handle? files_handle;
		MainLoop loop;
		AUR aur;
		As.Store app_store;
		string locale;
		HashTable<string, AURPackage> aur_vcs_pkgs;
		#if ENABLE_SNAP
		SnapPlugin snap_plugin;
		#endif

		public Config config { get; construct set; }

		public signal void get_updates_progress (uint percent);

		public Database (Config config) {
			Object (config: config);
		}

		construct {
			loop = new MainLoop ();
			aur_vcs_pkgs = new HashTable<string, AURPackage>  (str_hash, str_equal);
			refresh ();
			aur = new AUR ();
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
			#if ENABLE_SNAP
			// load snap plugin
			if (config.support_snap) {
				snap_plugin = config.get_snap_plugin ();
			}
			#endif
		}

		public void enable_appstream () {
			try {
				app_store.load (As.StoreLoadFlags.APP_INFO_SYSTEM);
				app_store.set_search_match (As.AppSearchMatch.PKGNAME
											| As.AppSearchMatch.DESCRIPTION
											| As.AppSearchMatch.NAME
											| As.AppSearchMatch.KEYWORD);
			} catch (Error e) {
				critical ("%s\n", e.message);
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
			aur_vcs_pkgs.remove_all ();
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
				critical ("%s\n", e.message);
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
				critical ("%s\n", e.message);
			}
			return country;
		}

		public string get_alpm_dep_name (string dep_string) {
			return Alpm.Depend.from_string (dep_string).name;
		}

		public CompareFunc<string> vercmp = Alpm.pkg_vercmp;

		public HashTable<string, int64?> get_clean_cache_details () {
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
						if (config.clean_rm_only_uninstalled && is_installed_pkg (name)) {
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
					critical ("%s\n", e.message);
				}
				cachedirs_names.next ();
			}
			if (config.clean_keep_num_pkgs == 0) {
				return filenames_size;
			}
			// filter candidates
			var iter = HashTableIter<string, SList<string>> (pkg_versions);
			unowned string name;
			unowned SList<string> versions;
			while (iter.next (out name, out versions)) {
				// sort versions
				uint length = versions.length ();
				if (length > config.clean_keep_num_pkgs) {
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
					if (i > config.clean_keep_num_pkgs) {
						break;
					}
				}
			}
			return filenames_size;
		}

		async void enumerate_directory (string directory_path, HashTable<string, int64?> filenames_size) {
			var directory = GLib.File.new_for_path (directory_path);
			if (!directory.query_exists ()) {
				return;
			}
			try {
				FileEnumerator enumerator = yield directory.enumerate_children_async ("standard::*", FileQueryInfoFlags.NONE);
				FileInfo info;
				while ((info = enumerator.next_file (null)) != null) {
					string absolute_filename = Path.build_path ("/", directory.get_path (), info.get_name ());
					if (info.get_file_type () == FileType.DIRECTORY) {
						yield enumerate_directory (absolute_filename, filenames_size);
					} else {
						filenames_size.insert (absolute_filename, info.get_size ());
					}
				}
			} catch (GLib.Error e) {
				stdout.printf ("%s\n", e.message);
			}
		}

		public HashTable<string, int64?> get_build_files_details () {
			var filenames_size = new HashTable<string, int64?> (str_hash, str_equal);
			enumerate_directory.begin (config.aur_build_dir, filenames_size, (obj, res) => {
				loop.quit ();
			});
			loop.run ();
			return filenames_size;
		}

		public bool is_installed_pkg (string pkgname) {
			return alpm_handle.localdb.get_pkg (pkgname) != null;
		}

		public AlpmPackage? get_installed_pkg (string pkgname) {
			return initialise_pkg (alpm_handle.localdb.get_pkg (pkgname));
		}

		public bool has_installed_satisfier (string depstring) {
			return Alpm.find_satisfier (alpm_handle.localdb.pkgcache, depstring) != null;
		}

		public AlpmPackage? get_installed_satisfier (string depstring) {
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
			new Thread<int> ("get_uninstalled_optdeps", () => {
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
				loop.quit ();
				return 0;
			});
			loop.run ();
			return (owned) optdeps;
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

		List<string> get_app_screenshots (As.App app) {
			var screenshots = new List<string> ();
			app.get_screenshots ().foreach ((as_screenshot) => {
				As.Image? as_image = as_screenshot.get_source ();
				if (as_image != null) {
					string? url = as_image.get_url ();
					if (url != null) {
						screenshots.append ((owned) url);
					}
				}
			});
			return (owned) screenshots;
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

		AlpmPackage? initialise_pkg (Alpm.Package? alpm_pkg) {
			if (alpm_pkg == null) {
				return null;
			}
			var pkg = new AlpmPackage ();
			initialise_pkg_common (alpm_pkg, ref pkg);
			if (alpm_pkg.origin == Alpm.Package.From.SYNCDB) {
				pkg.repo = alpm_pkg.db.name;
			} else if (alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
				unowned Alpm.Package? sync_pkg = get_syncpkg (alpm_pkg.name);
				if (sync_pkg != null) {
					pkg.repo = sync_pkg.db.name;
				} else if (config.enable_aur) {
					if (aur.get_infos (alpm_pkg.name) != null) {
						pkg.repo = dgettext (null, "AUR");
					}
				}
			}
			// find if pkgname provides only one app
			var matching_apps = get_pkgname_matching_apps (alpm_pkg.name);
			if (matching_apps.length () == 1) {
				initialize_app_data (matching_apps.nth_data (0), ref pkg);
			}
			return pkg;
		}

		void initialise_pkg_common (Alpm.Package alpm_pkg, ref AlpmPackage pkg) {
			// name
			pkg.name = alpm_pkg.name;
			// version
			pkg.version = alpm_pkg.version;
			// desc can be null
			if (alpm_pkg.desc != null) {
				pkg.desc = alpm_pkg.desc;
			}
			// url can be null
			if (alpm_pkg.url != null) {
				pkg.url = alpm_pkg.url;
			}
			// packager can be null
			pkg.packager = alpm_pkg.packager ?? "";
			// groups
			unowned Alpm.List<unowned string> list = alpm_pkg.groups;
			while (list != null) {
				pkg.groups_priv.append (list.data);
				list.next ();
			}
			// licenses
			list = alpm_pkg.licenses;
			while (list != null) {
				pkg.licenses_priv.append (list.data);
				list.next ();
			}
			// build_date
			pkg.builddate = alpm_pkg.builddate;
			// installed_size
			pkg.installed_size = alpm_pkg.isize;
			// installed_size
			pkg.download_size = alpm_pkg.download_size;
			// local pkg
			if (alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
				// installed_version
				pkg.installed_version = alpm_pkg.version;
				// reason
				if (alpm_pkg.reason == Alpm.Package.Reason.EXPLICIT) {
					pkg.reason = dgettext (null, "Explicitly installed");
				} else if (alpm_pkg.reason == Alpm.Package.Reason.DEPEND) {
					pkg.reason = dgettext (null, "Installed as a dependency for another package");
				} else {
					pkg.reason = dgettext (null, "Unknown");
				}
				// install_date
				pkg.installdate = alpm_pkg.installdate;
				// backups
				unowned Alpm.List<unowned Alpm.Backup> backups_list = alpm_pkg.backups;
				while (backups_list != null) {
					pkg.backups_priv.append ("/" + backups_list.data.name);
					backups_list.next ();
				}
				// requiredby
				Alpm.List<string> pkg_requiredby = alpm_pkg.compute_requiredby ();
				unowned Alpm.List<string> string_list = pkg_requiredby;
				while (string_list != null) {
					pkg.requiredby_priv.append ((owned) string_list.data);
					string_list.next ();
				}
				// optionalfor
				Alpm.List<string> pkg_optionalfor = alpm_pkg.compute_optionalfor ();
				string_list = pkg_optionalfor;
				while (string_list != null) {
					pkg.optionalfor_priv.append ((owned) string_list.data);
					string_list.next ();
				}
			// sync pkg
			} else if (alpm_pkg.origin == Alpm.Package.From.SYNCDB) {
				// installed_version
				unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (alpm_pkg.name);
				if (local_pkg != null) {
					pkg.installed_version = local_pkg.version;
				}
				// signature
				if (alpm_pkg.base64_sig != null) {
					pkg.has_signature = dgettext (null, "Yes");
				} else {
					pkg.has_signature = dgettext (null, "No");
				}
			}
			// depends
			unowned Alpm.List<unowned Alpm.Depend> depends_list = alpm_pkg.depends;
			while (depends_list != null) {
				pkg.depends_priv.append (depends_list.data.compute_string ());
				depends_list.next ();
			}
			// optdepends
			depends_list = alpm_pkg.optdepends;
			while (depends_list != null) {
				pkg.optdepends_priv.append (depends_list.data.compute_string ());
				depends_list.next ();
			}
			// provides
			depends_list = alpm_pkg.provides;
			while (depends_list != null) {
				pkg.provides_priv.append (depends_list.data.compute_string ());
				depends_list.next ();
			}
			// replaces
			depends_list = alpm_pkg.replaces;
			while (depends_list != null) {
				pkg.replaces_priv.append (depends_list.data.compute_string ());
				depends_list.next ();
			}
			// conflicts
			depends_list = alpm_pkg.conflicts;
			while (depends_list != null) {
				pkg.conflicts_priv.append (depends_list.data.compute_string ());
				depends_list.next ();
			}
		}

		void initialize_app_data (As.App app, ref AlpmPackage pkg) {
			pkg.app_name = get_app_name (app);
			pkg.launchable = get_app_launchable (app);
			pkg.desc = get_app_summary (app);
			try {
				pkg.long_desc = As.markup_convert_simple (get_app_description (app));
			} catch (Error e) {
				critical ("%s\n", e.message);
			}
			pkg.icon = get_app_icon (app, pkg.repo);
			pkg.screenshots_priv = get_app_screenshots (app);
		}

		List<AlpmPackage> initialise_pkgs (Alpm.List<unowned Alpm.Package>? alpm_pkgs) {
			var pkgs = new List<AlpmPackage> ();
			var data = new HashTable<string, AlpmPackage> (str_hash, str_equal);
			string[] foreign_pkgnames = {};
			while (alpm_pkgs != null) {
				unowned Alpm.Package alpm_pkg = alpm_pkgs.data;
				var pkg = new AlpmPackage ();
				initialise_pkg_common (alpm_pkg, ref pkg);
				if (alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
					unowned Alpm.Package? sync_pkg = get_syncpkg (alpm_pkg.name);
					if (sync_pkg != null) {
						pkg.repo = sync_pkg.db.name;
					} else if (config.enable_aur) {
						foreign_pkgnames += alpm_pkg.name;
					}
				} else if (alpm_pkg.origin == Alpm.Package.From.SYNCDB) {
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
						initialize_app_data (app, ref pkg);
						pkgs.append (pkg);
						apps_list = apps_list.next;
						while (apps_list != null) {
							app = apps_list.data;
							var pkg_dup = pkg.dup ();
							initialize_app_data (app, ref pkg_dup);
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
				foreach (unowned Json.Object json_object in aur.get_multi_infos (foreign_pkgnames)) {
					unowned AlpmPackage? pkg = data.lookup (json_object.get_string_member ("Name"));
					if (pkg != null) {
						pkg.repo = dgettext (null, "AUR");
					}
				}
				var iter = HashTableIter<string, AlpmPackage> (data);
				unowned AlpmPackage pkg;
				while (iter.next (null, out pkg)) {
					pkgs.append (pkg);
				}
			}
			return pkgs;
		}

		public List<AlpmPackage> get_installed_pkgs () {
			var pkgs = new List<AlpmPackage> ();
			new Thread<int> ("get_installed_pkgs", () => {
				pkgs = initialise_pkgs (alpm_handle.localdb.pkgcache);
				pkgs.sort (pkg_compare_name);
				loop.quit ();
				return 0;
			});
			loop.run ();
			return (owned) pkgs;
		}

		public List<AlpmPackage> get_installed_apps () {
			var pkgs = new List<AlpmPackage> ();
			new Thread<int> ("get_installed_apps", () => {
				app_store.get_apps ().foreach ((app) => {
					if (app.get_kind () == As.AppKind.DESKTOP) {
						unowned string pkgname = app.get_pkgname_default ();
						unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (pkgname);
						if (local_pkg != null) {
							unowned Alpm.Package? sync_pkg = get_syncpkg (pkgname);
							if (sync_pkg != null) {
								var pkg = new AlpmPackage ();
								initialise_pkg_common (local_pkg, ref pkg);
								pkg.repo = sync_pkg.db.name;
								initialize_app_data (app, ref pkg);
								pkgs.append (pkg);
							}
						}
					}
				});
				loop.quit ();
				return 0;
			});
			loop.run ();
			return (owned) pkgs;
		}

		public List<AlpmPackage> get_explicitly_installed_pkgs () {
			var pkgs = new List<AlpmPackage> ();
			new Thread<int> ("get_explicitly_installed_pkgs", () => {
				Alpm.List<unowned Alpm.Package> alpm_pkgs = null;
				unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
				while (pkgcache != null) {
					unowned Alpm.Package alpm_pkg = pkgcache.data;
					if (alpm_pkg.reason == Alpm.Package.Reason.EXPLICIT) {
						alpm_pkgs.add (alpm_pkg);
					}
					pkgcache.next ();
				}
				pkgs = initialise_pkgs (alpm_pkgs);
				pkgs.sort (pkg_compare_name);
				loop.quit ();
				return 0;
			});
			loop.run ();
			return (owned) pkgs;
		}

		public List<AlpmPackage> get_foreign_pkgs () {
			var pkgs = new List<AlpmPackage> ();
			new Thread<int> ("get_foreign_pkgs", () => {
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
				pkgs = initialise_pkgs (alpm_pkgs);
				pkgs.sort (pkg_compare_name);
				loop.quit ();
				return 0;
			});
			loop.run ();
			return (owned) pkgs;
		}

		public List<AlpmPackage> get_orphans () {
			var pkgs = new List<AlpmPackage> ();
			new Thread<int> ("get_orphans", () => {
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
				pkgs = initialise_pkgs (alpm_pkgs);
				pkgs.sort (pkg_compare_name);
				loop.quit ();
				return 0;
			});
			loop.run ();
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

		public AlpmPackage? get_sync_pkg (string pkgname) {
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

		public bool has_sync_satisfier (string depstring) {
			return find_dbs_satisfier (depstring) != null;
		}

		public AlpmPackage? get_sync_satisfier (string depstring) {
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
			// remove foreign pkgs
			Alpm.List<unowned Alpm.Package> localpkgs = alpm_handle.localdb.search (needles);
			Alpm.List<unowned Alpm.Package> result = syncpkgs.diff (localpkgs.diff (syncpkgs, (Alpm.List.CompareFunc) alpm_pkg_compare_name), (Alpm.List.CompareFunc) alpm_pkg_compare_name);
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

		public List<AlpmPackage> search_installed_pkgs (string search_string) {
			string search_string_down = search_string.down ();
			var pkgs = new List<AlpmPackage> ();
			new Thread<int> ("search_installed_pkgs", () => {
				pkgs = initialise_pkgs (search_local_db (search_string_down));
				// use custom sort function
				global_search_string = (owned) search_string_down;
				pkgs.sort (pkg_sort_search_by_relevance);
				loop.quit ();
				return 0;
			});
			loop.run ();
			return (owned) pkgs;
		}

		public List<AlpmPackage> search_repos_pkgs (string search_string) {
			string search_string_down = search_string.down ();
			var pkgs = new List<AlpmPackage> ();
			new Thread<int> ("search_repos_pkgs", () => {
				pkgs = initialise_pkgs (search_sync_dbs (search_string_down));
				// use custom sort function
				global_search_string = (owned) search_string_down;
				pkgs.sort (pkg_sort_search_by_relevance);
				loop.quit ();
				return 0;
			});
			loop.run ();
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

		public List<AlpmPackage> search_pkgs (string search_string) {
			string search_string_down = search_string.down ();
			var pkgs = new List<AlpmPackage> ();
			new Thread<int> ("search_pkgs", () => {
				pkgs = initialise_pkgs (search_all_dbs (search_string_down));
				// use custom sort function
				global_search_string = (owned) search_string_down;
				pkgs.sort (pkg_sort_search_by_relevance);
				loop.quit ();
				return 0;
			});
			loop.run ();
			return (owned) pkgs;
		}

		public List<AURPackage> search_aur_pkgs (string search_string) {
			string search_string_down = search_string.down ();
			var pkgs = new List<AURPackage> ();
			if (config.enable_aur) {
				new Thread<int> ("search_aur_pkgs", () => {
					foreach (unowned Json.Object json_object in aur.search_aur (search_string_down)) {
						unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (json_object.get_string_member ("Name"));
						pkgs.append (initialise_aur_pkg (json_object, local_pkg));
					}
					loop.quit ();
					return 0;
				});
				loop.run ();
			}
			return (owned) pkgs;
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

		public List<string> get_categories_names () {
			var result = new List<string> ();
			result.append ("Featured");
			result.append ("Photo & Video");
			result.append ("Music & Audio");
			result.append ("Productivity");
			result.append ("Communication & News");
			result.append ("Education & Science");
			result.append ("Games");
			result.append ("Utilities");
			result.append ("Development");
			return result;
		}

		public List<AlpmPackage> get_category_pkgs (string category) {
			var result = new List<AlpmPackage> ();
			string category_copy = category;
			new Thread<int> ("get_category_pkgs", () => {
				string[] appstream_categories = {};
				switch (category_copy) {
					case "Featured":
						string[] featured_pkgs = {"firefox", "vlc", "gimp", "shotwell", "inkscape", "blender", "libreoffice-still", "telegram-desktop", "cura", "arduino", "retroarch", "virtualbox"};
						app_store.get_apps ().foreach ((app) => {
							if (app.get_kind () == As.AppKind.DESKTOP) {
								unowned string pkgname = app.get_pkgname_default ();
								if (pkgname in featured_pkgs) {
									unowned Alpm.Package? sync_pkg = get_syncpkg (pkgname);
									if (sync_pkg != null) {
										var pkg = new AlpmPackage ();
										unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (pkgname);
										if (local_pkg != null) {
											initialise_pkg_common (local_pkg, ref pkg);
										} else {
											initialise_pkg_common (sync_pkg, ref pkg);
										}
										pkg.repo = sync_pkg.db.name;
										initialize_app_data (app, ref pkg);
										result.append (pkg);
									}
								}
							}
						});
						break;
					case "Photo & Video":
						appstream_categories = {"Graphics", "Video"};
						break;
					case "Music & Audio":
						appstream_categories = {"Audio", "Music"};
						break;
					case "Productivity":
						appstream_categories = {"WebBrowser", "Email", "Office"};
						break;
					case "Communication & News":
						appstream_categories = {"Network"};
						break;
					case "Education & Science":
						appstream_categories = {"Education", "Science"};
						break;
					case "Games":
						appstream_categories = {"Game"};
						break;
					case "Utilities":
						appstream_categories = {"Utility"};
						break;
					case "Development":
						appstream_categories = {"Development"};
						break;
					default:
						appstream_categories = {};
						break;
				}
				if (appstream_categories.length > 0) {
					app_store.get_apps ().foreach ((app) => {
						if (app.get_kind () == As.AppKind.DESKTOP) {
							app.get_categories ().foreach ((cat_name) => {
								if (cat_name in appstream_categories) {
									unowned string pkgname = app.get_pkgname_default ();
									if (result.search (pkgname, (SearchFunc) pkg_search_name) == null) {
										unowned Alpm.Package? sync_pkg = get_syncpkg (pkgname);
										if (sync_pkg != null) {
											var pkg = new AlpmPackage ();
											unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (pkgname);
											if (local_pkg != null) {
												initialise_pkg_common (local_pkg, ref pkg);
											} else {
												initialise_pkg_common (sync_pkg, ref pkg);
											}
											pkg.repo = sync_pkg.db.name;
											initialize_app_data (app, ref pkg);
											result.append (pkg);
										}
									}
								}
							});
						}
					});
				}
				loop.quit ();
				return 0;
			});
			loop.run ();
			return (owned) result;
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

		public List<AlpmPackage> get_repo_pkgs (string repo) {
			var pkgs = new List<AlpmPackage> ();
			string repo_copy = repo;
			new Thread<int> ("get_repo_pkgs", () => {
				Alpm.List<unowned Alpm.Package> alpm_pkgs = null;
				unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
				while (syncdbs != null) {
					unowned Alpm.DB db = syncdbs.data;
					if (db.name == repo_copy) {
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
				pkgs = initialise_pkgs (alpm_pkgs);
				pkgs.sort (pkg_compare_name);
				loop.quit ();
				return 0;
			});
			loop.run ();
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

		public List<AlpmPackage> get_group_pkgs (string group_name) {
			var pkgs = new List<AlpmPackage> ();
			string group_name_copy = group_name;
			new Thread<int> ("get_group_pkgs", () => {
				Alpm.List<unowned Alpm.Package> alpm_pkgs = null;
				unowned Alpm.Group? grp = alpm_handle.localdb.get_group (group_name_copy);
				if (grp != null) {
					unowned Alpm.List<unowned Alpm.Package> packages = grp.packages;
					while (packages != null) {
						unowned Alpm.Package pkg = packages.data;
						alpm_pkgs.add (pkg);
						packages.next ();
					}
				}
				unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
				while (syncdbs != null) {
					unowned Alpm.DB db = syncdbs.data;
					grp = db.get_group (group_name_copy);
					if (grp != null) {
						unowned Alpm.List<unowned Alpm.Package> packages = grp.packages;
						while (packages != null) {
							unowned Alpm.Package pkg = packages.data;
							if (alpm_pkgs.find (pkg, (Alpm.List.CompareFunc) alpm_pkg_compare_name) == null) {
								alpm_pkgs.add (pkg);
							}
							packages.next ();
						}
					}
					syncdbs.next ();
				}
				pkgs = initialise_pkgs (alpm_pkgs);
				pkgs.sort (pkg_compare_name);
				loop.quit ();
				return 0;
			});
			loop.run ();
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

		public AlpmPackage? get_pkg (string pkgname) {
			if (is_installed_pkg (pkgname)) {
				return get_installed_pkg (pkgname);
			}
			return get_sync_pkg (pkgname);
		}

		public List<string> get_pkg_files (string pkgname) {
			var files = new List<string> ();
			string pkgname_copy = pkgname;
			new Thread<int> ("get_pkg_files", () => {
				unowned Alpm.Package? alpm_pkg = alpm_handle.localdb.get_pkg (pkgname_copy);
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
						unowned Alpm.Package? files_pkg = db.get_pkg (pkgname_copy);
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
				loop.quit ();
				return 0;
			});
			loop.run ();
			return (owned) files;
		}

		int launch_subprocess (SubprocessLauncher launcher, string[] cmds, Cancellable? cancellable = null) {
			int status = 1;
			try {
				Subprocess process = launcher.spawnv (cmds);
				process.wait (cancellable);
				if (cancellable.is_cancelled ()) {
					process.force_exit ();
					return 1;
				}
				if (process.get_if_exited ()) {
					status = process.get_exit_status ();
				}
			} catch (Error e) {
				critical ("%s\n", e.message);
			}
			return status;
		}

		public File? clone_build_files (string pkgname, bool overwrite_files, Cancellable? cancellable = null) {
			File? file = null;
			string pkgname_copy = pkgname;
			new Thread<int> ("clone_build_files", () => {
				file = clone_build_files_real (pkgname_copy, overwrite_files, cancellable);
				loop.quit ();
				return 0;
			});
			loop.run ();
			return file;
		}

		File? clone_build_files_real (string pkgname, bool overwrite_files, Cancellable? cancellable) {
			int status = 1;
			string[] cmds;
			var launcher = new SubprocessLauncher (SubprocessFlags.NONE);
			var builddir = File.new_for_path (config.aur_build_dir);
			if (!builddir.query_exists ()) {
				try {
					builddir.make_directory_with_parents ();
				} catch (Error e) {
					critical ("%s\n", e.message);
				}
			}
			var pkgdir = builddir.get_child (pkgname);
			if (pkgdir.query_exists ()) {
				if (overwrite_files) {
					launcher.set_cwd (config.aur_build_dir);
					cmds = {"rm", "-rf", "%s".printf (pkgdir.get_path ())};
					launch_subprocess (launcher, cmds);
					cmds = {"git", "clone", "-q", "--depth=1", "https://aur.archlinux.org/%s.git".printf (pkgname)};
				} else {
					// fetch modifications
					launcher.set_cwd (pkgdir.get_path ());
					cmds = {"git", "fetch", "-q"};
					status = launch_subprocess (launcher, cmds, cancellable);
					if (cancellable.is_cancelled ()) {
						return null;
					}
					// write diff file
					if (status == 0) {
						launcher.set_flags (SubprocessFlags.STDOUT_PIPE);
						try {
							var file = File.new_for_path (Path.build_path ("/", pkgdir.get_path (), "diff"));
							if (file.query_exists ()) {
								// delete the file before rewrite it
								file.delete ();
							}
							cmds = {"git", "diff", "--exit-code", "origin/master"};
							FileEnumerator enumerator = pkgdir.enumerate_children ("standard::*", FileQueryInfoFlags.NONE);
							FileInfo info;
							// don't show .SRCINFO diff
							while ((info = enumerator.next_file (null)) != null) {
								unowned string filename = info.get_name ();
								if (filename != ".SRCINFO") {
									cmds += filename;
								}
							}
							Subprocess process = launcher.spawnv (cmds);
							process.wait ();
							if (process.get_if_exited ()) {
								status = process.get_exit_status ();
							}
							if (status == 1) {
								// there is a diff
								var dis = new DataInputStream (process.get_stdout_pipe ());
								var dos = new DataOutputStream (file.create (FileCreateFlags.NONE));
								// writing output to diff
								dos.splice (dis, OutputStreamSpliceFlags.NONE);
								status = 0;
							}
						} catch (Error e) {
							critical ("%s\n", e.message);
						}
						launcher.set_flags (SubprocessFlags.NONE);
					}
					// merge modifications
					if (status == 0) {
						launcher.set_flags (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
						cmds = {"git", "merge", "-q"};
						status = launch_subprocess (launcher, cmds);
					}
					if (status == 0) {
						return pkgdir;
					} else {
						launcher.set_cwd (config.aur_build_dir);
						cmds = {"rm", "-rf", "%s".printf (pkgdir.get_path ())};
						launch_subprocess (launcher, cmds);
						cmds = {"git", "clone", "-q", "--depth=1", "https://aur.archlinux.org/%s.git".printf (pkgname)};
					}
				}
			} else {
				launcher.set_cwd (config.aur_build_dir);
				cmds = {"git", "clone", "-q", "--depth=1", "https://aur.archlinux.org/%s.git".printf (pkgname)};
			}
			status = launch_subprocess (launcher, cmds, cancellable);
			if (status == 0) {
				return pkgdir;
			}
			return null;
		}

		public bool regenerate_srcinfo (string pkgname, Cancellable? cancellable = null) {
			bool success = false;
			string pkgname_copy = pkgname;
			new Thread<int> ("clone_build_files", () => {
				success = regenerate_srcinfo_real (pkgname_copy, cancellable);
				loop.quit ();
				return 0;
			});
			loop.run ();
			return success;
		}

		bool regenerate_srcinfo_real (string pkgname, Cancellable? cancellable) {
			string pkgdir_name = Path.build_path ("/", config.aur_build_dir, pkgname);
			var srcinfo = File.new_for_path (Path.build_path ("/", pkgdir_name, ".SRCINFO"));
			var pkgbuild = File.new_for_path (Path.build_path ("/", pkgdir_name, "PKGBUILD"));
			if (srcinfo.query_exists ()) {
				// check if PKGBUILD was modified after .SRCINFO
				try {
					FileInfo info = srcinfo.query_info ("time::modified", 0);
					DateTime srcinfo_time = info.get_modification_date_time ();
					info = pkgbuild.query_info ("time::modified", 0);
					DateTime pkgbuild_time = info.get_modification_date_time ();
					if (srcinfo_time.compare (pkgbuild_time) == 1) {
						// no need to regenerate
						return true;
					}
				} catch (Error e) {
					critical ("%s\n", e.message);
				}
			}
			// generate .SRCINFO
			var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);
			launcher.set_cwd (pkgdir_name);
			try {
				Subprocess process = launcher.spawnv ({"makepkg", "--printsrcinfo"});
				try {
					process.wait (cancellable);
					if (process.get_if_exited ()) {
						if (process.get_exit_status () == 0) {
							try {
								var dis = new DataInputStream (process.get_stdout_pipe ());
								FileOutputStream fos;
								if (srcinfo.query_exists ()) {
									fos = srcinfo.replace (null, false, FileCreateFlags.NONE);
								} else {
									fos = srcinfo.create (FileCreateFlags.NONE);
								}
								// creating a DataOutputStream to the file
								var dos = new DataOutputStream (fos);
								// writing makepkg output to .SRCINFO
								dos.splice (dis, OutputStreamSpliceFlags.NONE);
								return true;
							} catch (Error e) {
								critical ("%s\n", e.message);
							}
						}
					}
				} catch (Error e) {
					// cancelled
					process.send_signal (Posix.Signal.INT);
					process.send_signal (Posix.Signal.KILL);
				}
			} catch (Error e) {
				critical ("%s\n", e.message);
			}
			return false;
		}

		public AURPackage? get_aur_pkg (string pkgname) {
			AURPackage? pkg = null;
			if (config.enable_aur) {
				string pkgname_copy = pkgname;
				new Thread<int> ("get_aur_pkg", () => {
					unowned Alpm.Package? local_pkg = null;
					unowned Json.Object? json_object = aur.get_infos (pkgname_copy);
					if (json_object != null){
						local_pkg = alpm_handle.localdb.get_pkg (json_object.get_string_member ("Name"));
					}
					pkg = initialise_aur_pkg (json_object, local_pkg);
					loop.quit ();
					return 0;
				});
				loop.run ();
			}
			return pkg;
		}

		public HashTable<string, AURPackage?> get_aur_pkgs (string[] pkgnames) {
			var data = new HashTable<string, AURPackage?> (str_hash, str_equal);
			if (!config.enable_aur) {
				return data;
			}
			string[] pkgnames_copy = pkgnames;
			new Thread<int> ("get_aur_pkgs", () => {
				foreach (unowned Json.Object json_object in aur.get_multi_infos (pkgnames_copy)) {
					unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (json_object.get_string_member ("Name"));
					data.insert (json_object.get_string_member ("Name"), initialise_aur_pkg (json_object, local_pkg));
				}
				loop.quit ();
				return 0;
			});
			loop.run ();
			foreach (unowned string pkgname in pkgnames_copy) {
				if (!data.contains (pkgname)) {
					data.insert (pkgname, null);
				}
			}
			return (owned) data;
		}

		AURPackage? initialise_aur_pkg (Json.Object? json_object, Alpm.Package? local_pkg, bool is_update = false) {
			if (json_object == null) {
				return null;
			}
			var aur_pkg = new AURPackage ();
			// check if it's installed
			if (!is_update && local_pkg != null) {
				var pkg = aur_pkg as AlpmPackage;
				initialise_pkg_common (local_pkg, ref pkg);
			} else {
				// name
				aur_pkg.name = json_object.get_string_member ("Name");
				// version
				aur_pkg.version = json_object.get_string_member ("Version");
				if (local_pkg != null) {
					aur_pkg.installed_version = local_pkg.version;
				}
				// desc can be null
				if (!json_object.get_null_member ("Description")) {
					aur_pkg.desc = json_object.get_string_member ("Description");
				}
				// url can be null
				unowned Json.Node? node = json_object.get_member ("URL");
				if (!node.is_null ()) {
					aur_pkg.url = node.get_string ();
				}
				// licenses
				node = json_object.get_member ("License");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						aur_pkg.licenses_priv.append (_node.get_string ());
					});
				} else {
					aur_pkg.licenses_priv.append (dgettext (null, "Unknown"));
				}
				// depends
				node = json_object.get_member ("Depends");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						aur_pkg.depends_priv.append (_node.get_string ());
					});
				}
				// optdepends
				node = json_object.get_member ("OptDepends");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						aur_pkg.optdepends_priv.append (_node.get_string ());
					});
				}
				// provides
				node = json_object.get_member ("Provides");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						aur_pkg.provides_priv.append (_node.get_string ());
					});
				}
				// replaces
				node = json_object.get_member ("Replaces");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						aur_pkg.replaces_priv.append (_node.get_string ());
					});
				}
				// conflicts
				node = json_object.get_member ("Conflicts");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						aur_pkg.conflicts_priv.append (_node.get_string ());
					});
				}
			}
			// popularity
			aur_pkg.popularity = json_object.get_double_member ("Popularity");
			// packagebase
			aur_pkg.packagebase = json_object.get_string_member ("PackageBase");
			// maintainer can be null
			unowned Json.Node? node = json_object.get_member ("Maintainer");
			if (!node.is_null ()) {
				aur_pkg.maintainer = node.get_string ();
			}
			// firstsubmitted
			aur_pkg.firstsubmitted = (uint64) json_object.get_int_member ("FirstSubmitted");
			// lastmodified
			aur_pkg.lastmodified = (uint64) json_object.get_int_member ("LastModified");
			// outofdate can be null
			node = json_object.get_member ("OutOfDate");
			if (!node.is_null ()) {
				aur_pkg.outofdate = (uint64) node.get_int ();
			}
			//numvotes
			aur_pkg.numvotes = (uint64) json_object.get_int_member ("NumVotes");
			// makedepends
			node = json_object.get_member ("MakeDepends");
			if (node != null) {
				node.get_array ().foreach_element ((array, index, _node) => {
					aur_pkg.makedepends_priv.append (_node.get_string ());
				});
			}
			// checkdepends
			node = json_object.get_member ("CheckDepends");
			if (node != null) {
				node.get_array ().foreach_element ((array, index, _node) => {
					aur_pkg.checkdepends_priv.append (_node.get_string ());
				});
			}
			return aur_pkg;
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
					critical ("%s\n", e.message);
				}
			}
			return pkgnames;
		}

		public List<AURPackage> get_aur_updates () {
			var pkgs = new List<AURPackage> ();
			var local_pkgs = new GenericArray<string> ();
			string[] vcs_local_pkgs = {};
			if (config.enable_aur) {
				new Thread<int> ("get_aur_updates", () => {
					// get local pkgs
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
									local_pkgs.add (installed_pkg.name);
								}
							}
						}
						pkgcache.next ();
					}
					var aur_updates = get_aur_updates_real (aur.get_multi_infos (local_pkgs.data), vcs_local_pkgs);
					pkgs = (owned) aur_updates.updates;
					loop.quit ();
					return 0;
				});
				loop.run ();
			}
			return (owned) pkgs;
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

		public Updates get_updates () {
			var updates = new Updates ();
			var local_pkgs = new GenericArray<string> ();
			string[] vcs_local_pkgs = {};
			var repos_updates = new List<AlpmPackage> ();
			new Thread<int> ("get_updates", () => {
				// be sure we have the good updates
				alpm_config = new AlpmConfig ("/etc/pacman.conf");
				get_updates_progress (0);
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
						unowned Alpm.Package? candidate = installed_pkg.get_new_version (tmp_handle.syncdbs);
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
										local_pkgs.add (installed_pkg.name);
									}
								}
							}
						}
					}
					pkgcache.next ();
				}
				if (config.check_aur_updates) {
					// count this step as 5% of the total
					Idle.add (() => {
						get_updates_progress (95);
						return false;
					});
					var aur_updates = get_aur_updates_real (aur.get_multi_infos (local_pkgs.data), vcs_local_pkgs);
					Idle.add (() => {
						get_updates_progress (100);
						return false;
					});
					updates = new Updates.from_lists ((owned) repos_updates, (owned) aur_updates.updates, (owned) aur_updates.outofdate);
				} else {
					Idle.add (() => {
						get_updates_progress (100);
						return false;
					});
					updates = new Updates.from_lists ((owned) repos_updates, new List<AURPackage> (), new List<AURPackage> ());
				}
				loop.quit ();
				return 0;
			});
			loop.run ();
			return updates;
		}

		List<unowned AURPackage> get_vcs_last_version (string[] vcs_local_pkgs) {
			foreach (unowned string pkgname in vcs_local_pkgs) {
				if (aur_vcs_pkgs.contains (pkgname)) {
					continue;
				}
				// get last build files
				unowned Json.Object? json_object = aur.get_infos (pkgname);
				if (json_object == null) {
					// error
					continue;
				}
				File? clone_dir = clone_build_files_real (json_object.get_string_member ("PackageBase"), false, null);
				if (clone_dir != null) {
					// get last sources
					// no output to not pollute checkupdates output
					var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
					launcher.set_cwd (clone_dir.get_path ());
					string[] cmds = {"makepkg", "--nobuild", "--noprepare"};
					int status = launch_subprocess (launcher, cmds);
					if (status == 0) {
						bool success = regenerate_srcinfo_real (clone_dir.get_basename (), null);
						if (success) {
							var srcinfo = clone_dir.get_child (".SRCINFO");
							try {
								// read .SRCINFO
								var dis = new DataInputStream (srcinfo.read ());
								string? line;
								string current_section = "";
								bool current_section_is_pkgbase = true;
								var version = new StringBuilder ("");
								string pkgbase = "";
								string desc = "";
								string arch = Posix.utsname ().machine;
								var pkgnames_found = new SList<string> ();
								var global_depends = new List<string> ();
								var global_checkdepends = new List<string> ();
								var global_makedepends = new List<string> ();
								var global_conflicts = new List<string> ();
								var global_provides = new List<string> ();
								var global_replaces = new List<string> ();
								var global_validpgpkeys = new SList<string> ();
								var pkgnames_table = new HashTable<string, AURPackage> (str_hash, str_equal);
								while ((line = dis.read_line ()) != null) {
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
									// don't compute optdepends, it will be done by makepkg
									} else if ("optdepends" in line) {
										// pass
										continue;
									// compute depends, makedepends and checkdepends:
									// list name may contains arch, e.g. depends_x86_64
									// depends, provides, replaces and conflicts in pkgbase section are stored
									// in order to be added after if the list in pkgname is empty,
									// makedepends and checkdepends will be added in depends
									} else if ("depends" in line) {
										if ("depends = " in line || "depends_%s = ".printf (arch) in line) {
											string depend = line.split (" = ", 2)[1];
											if (current_section_is_pkgbase){
												if ("checkdepends" in line) {
													global_checkdepends.append ((owned) depend);
												} else if ("makedepends" in line) {
													global_makedepends.append ((owned) depend);
												} else {
													global_depends.append ((owned) depend);
												}
											} else {
												unowned AURPackage? aur_pkg = pkgnames_table.get (current_section);
												if (aur_pkg != null) {
													aur_pkg.depends_priv.append ((owned) depend);
												}
											}
										}
									} else if ("provides" in line) {
										if ("provides = " in line || "provides_%s = ".printf (arch) in line) {
											string provide = line.split (" = ", 2)[1];
											if (current_section_is_pkgbase) {
												global_provides.append ((owned) provide);
											} else {
												unowned AURPackage? aur_pkg = pkgnames_table.get (current_section);
												if (aur_pkg != null) {
													aur_pkg.provides_priv.append ((owned) provide);
												}
											}
										}
									} else if ("conflicts" in line) {
										if ("conflicts = " in line || "conflicts_%s = ".printf (arch) in line) {
											string conflict = line.split (" = ", 2)[1];
											if (current_section_is_pkgbase) {
												global_conflicts.append ((owned) conflict);
											} else {
												unowned AURPackage? aur_pkg = pkgnames_table.get (current_section);
												if (aur_pkg != null) {
													aur_pkg.conflicts_priv.append ((owned) conflict);
												}
											}
										}
									} else if ("replaces" in line) {
										if ("replaces = " in line || "replaces_%s = ".printf (arch) in line) {
											string replace = line.split (" = ", 2)[1];
											if (current_section_is_pkgbase) {
												global_replaces.append ((owned) replace);
											} else {
												unowned AURPackage? aur_pkg = pkgnames_table.get (current_section);
												if (aur_pkg != null) {
													aur_pkg.replaces_priv.append ((owned) replace);
												}
											}
										}
									// grab validpgpkeys to check if they are imported
									} else if ("validpgpkeys" in line) {
										if ("validpgpkeys = " in line) {
											global_validpgpkeys.append (line.split (" = ", 2)[1]);
										}
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
											pkgnames_found.append ((owned) pkgname_found);
										}
									}
								}
								foreach (unowned string pkgname_found in pkgnames_found) {
									AURPackage? aur_pkg = pkgnames_table.take (pkgname_found);
									// populate empty list will global ones
									if (global_depends.length () > 0 && aur_pkg.depends.length () == 0) {
										aur_pkg.depends_priv = (owned) global_depends;
									}
									if (global_provides.length () > 0 && aur_pkg.provides.length () == 0) {
										aur_pkg.provides_priv = (owned) global_provides;
									}
									if (global_conflicts.length () > 0 && aur_pkg.conflicts.length () == 0) {
										aur_pkg.conflicts_priv = (owned) global_conflicts;
									}
									if (global_replaces.length () > 0 && aur_pkg.replaces.length () == 0) {
										aur_pkg.replaces_priv = (owned) global_replaces;
									}
									if (global_checkdepends.length () > 0 ) {
										aur_pkg.checkdepends_priv = (owned) global_checkdepends;
									}
									if (global_makedepends.length () > 0 ) {
										aur_pkg.makedepends_priv = (owned) global_makedepends;
									}
									aur_vcs_pkgs.insert (pkgname_found, aur_pkg);
								}
							} catch (GLib.Error e) {
								critical ("%s\n", e.message);
								continue;
							}
						}
					}
				}
			}
			return aur_vcs_pkgs.get_values ();
		}

		AURUpdates get_aur_updates_real (List<unowned Json.Object> aur_infos, string[] vcs_local_pkgs) {
			var updates = new List<AURPackage> ();
			var outofdate = new List<AURPackage> ();
			foreach (unowned Json.Object pkg_info in aur_infos) {
				unowned string name = pkg_info.get_string_member ("Name");
				unowned string new_version = pkg_info.get_string_member ("Version");
				unowned Alpm.Package local_pkg = alpm_handle.localdb.get_pkg (name);
				unowned string old_version = local_pkg.version;
				if (Alpm.pkg_vercmp (new_version, old_version) == 1) {
					updates.append (initialise_aur_pkg (pkg_info, local_pkg, true));
				} else if (!pkg_info.get_member ("OutOfDate").is_null ()) {
					// get out of date packages
					outofdate.append (initialise_aur_pkg (pkg_info, local_pkg));
				}
			}
			if (config.check_aur_vcs_updates) {
				var vcs_updates = get_vcs_last_version (vcs_local_pkgs);
				foreach (unowned AURPackage aur_pkg in vcs_updates) {
					if (Alpm.pkg_vercmp (aur_pkg.version, aur_pkg.installed_version) == 1) {
						updates.append (aur_pkg);
					}
				}
			}
			return new AURUpdates ((owned) updates, (owned) outofdate);
		}

		#if ENABLE_SNAP
		public List<SnapPackage> search_snaps (string search_string) {
			string search_string_down = search_string.down ();
			var pkgs = new List<SnapPackage> ();
			if (config.enable_snap) {
				new Thread<int> ("search_snaps", () => {
					pkgs = snap_plugin.search_snaps (search_string_down);
					loop.quit ();
					return 0;
				});
				loop.run ();
			}
			return (owned) pkgs;
		}

		public bool is_installed_snap (string name) {
			if (config.enable_snap) {
				return snap_plugin.is_installed_snap (name);
			}
			return false;
		}

		public SnapPackage? get_snap (string name) {
			SnapPackage? pkg = null;
			string name_copy = name;
			if (config.enable_snap) {
				new Thread<int> ("get_snap", () => {
					pkg = snap_plugin.get_snap (name_copy);
					loop.quit ();
					return 0;
				});
				loop.run ();
			}
			return pkg;
		}

		public List<SnapPackage> get_installed_snaps () {
			var pkgs = new List<SnapPackage> ();
			if (config.enable_snap) {
				new Thread<int> ("get_installed_snaps", () => {
					pkgs = snap_plugin.get_installed_snaps ();
					loop.quit ();
					return 0;
				});
				loop.run ();
			}
			return (owned) pkgs;
		}

		public string get_installed_snap_icon (string name) {
			string icon = "";
			string name_copy = name;
			if (config.enable_snap) {
				new Thread<int> ("get_category_snaps", () => {
					try {
						icon = snap_plugin.get_installed_snap_icon (name_copy);
					} catch (Error e) {
						critical ("%s: %s\n", name_copy, e.message);
					}
					loop.quit ();
					return 0;
				});
				loop.run ();
			}
			return icon;
		}

		public List<SnapPackage> get_category_snaps (string category) {
			var pkgs = new List<SnapPackage> ();
			string category_copy = category;
			if (config.enable_snap) {
				new Thread<int> ("get_category_snaps", () => {
					pkgs = snap_plugin.get_category_snaps (category_copy);
					loop.quit ();
					return 0;
				});
				loop.run ();
			}
			return (owned) pkgs;
		}
		#endif
	}
}

private int alpm_pkg_compare_name (Alpm.Package pkg_a, Alpm.Package pkg_b) {
	return strcmp (pkg_a.name, pkg_b.name);
}

private int pkg_compare_name (Pamac.Package pkg_a, Pamac.Package pkg_b) {
	return strcmp (pkg_a.name, pkg_b.name);
}

private int pkg_search_name (Pamac.Package pkg, string name) {
	return strcmp (pkg.name, name);
}

private string global_search_string;

private int pkg_sort_search_by_relevance (Pamac.Package pkg_a, Pamac.Package pkg_b) {
	if (global_search_string != null) {
		// display exact match first
		if (pkg_a.app_name.down () == global_search_string) {
			return 0;
		}
		if (pkg_b.app_name.down () == global_search_string) {
			return 1;
		}
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
		if (pkg_a.app_name.has_prefix (global_search_string)) {
			if (pkg_b.app_name.has_prefix (global_search_string)) {
				return strcmp (pkg_a.app_name, pkg_b.app_name);
			}
			return 0;
		}
		if (pkg_b.app_name.has_prefix (global_search_string)) {
			if (pkg_a.app_name.has_prefix (global_search_string)) {
				return strcmp (pkg_a.app_name, pkg_b.app_name);
			}
			return 1;
		}
		if (pkg_a.app_name.contains (global_search_string)) {
			if (pkg_b.app_name.contains (global_search_string)) {
				return strcmp (pkg_a.app_name, pkg_b.app_name);
			}
			return 0;
		}
		if (pkg_b.app_name.contains (global_search_string)) {
			if (pkg_a.app_name.contains (global_search_string)) {
				return strcmp (pkg_a.app_name, pkg_b.app_name);
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
