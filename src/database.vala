/*
 *  pamac-vala
 *
 *  Copyright (C) 2019-2020 Guillaume Benoit <guillaume@manjaro.org>
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
			public SList<AURPackage> updates;
			public SList<AURPackage> ignored_updates;
			public SList<AURPackage> outofdate;
			public AURUpdates (owned SList<AURPackage> updates, owned SList<AURPackage> ignored_updates, owned SList<AURPackage> outofdate) {
				this.updates = (owned) updates;
				this.ignored_updates = (owned) ignored_updates;
				this.outofdate = (owned) outofdate;
			}
		}

		AlpmConfig alpm_config;
		Alpm.Handle? alpm_handle;
		Alpm.Handle? files_handle;
		MainContext context;
		MainLoop loop;
		AUR aur;
		As.Store app_store;
		HashTable<string, AURPackage> aur_vcs_pkgs;
		HashTable<unowned string, unowned Alpm.Package> repos_pkgs;
		#if ENABLE_SNAP
		SnapPlugin snap_plugin;
		#endif
		#if ENABLE_FLATPAK
		FlatpakPlugin flatpak_plugin;
		#endif

		public Config config { get; construct set; }

		public signal void get_updates_progress (uint percent);

		public Database (Config config) {
			Object (config: config);
		}

		construct {
			alpm_config = config.alpm_config;
			context = MainContext.ref_thread_default ();
			loop = new MainLoop (context);
			aur_vcs_pkgs = new HashTable<string, AURPackage>  (str_hash, str_equal);
			repos_pkgs = new HashTable<unowned string, unowned Alpm.Package>  (str_hash, str_equal);
			refresh ();
			aur = new AUR ();
			// init appstream
			app_store = new As.Store ();
			app_store.add_filter (As.AppKind.DESKTOP);
			app_store.set_add_flags (As.StoreAddFlags.USE_UNIQUE_ID
									| As.StoreAddFlags.ONLY_NATIVE_LANGS
									| As.StoreAddFlags.USE_MERGE_HEURISTIC);
			#if ENABLE_SNAP
			// load snap plugin
			if (config.support_snap) {
				snap_plugin = config.get_snap_plugin ();
			}
			#endif
			#if ENABLE_FLATPAK
			// load flatpak plugin
			if (config.support_flatpak) {
				flatpak_plugin = config.get_flatpak_plugin ();
				flatpak_plugin.refresh_period = config.refresh_period;
				if (config.enable_flatpak) {
					load_flatpak_appstream_data ();
				}
				config.notify["enable-flatpak"].connect (() => {
					if (config.enable_flatpak) {
						load_flatpak_appstream_data ();
					}
				});
			}
			#endif
		}

		public void enable_appstream () {
			try {
				app_store.load (As.StoreLoadFlags.APP_INFO_SYSTEM);
				app_store.set_search_match (As.AppSearchMatch.PKGNAME
											| As.AppSearchMatch.DESCRIPTION
											| As.AppSearchMatch.NAME
											| As.AppSearchMatch.MIMETYPE
											| As.AppSearchMatch.COMMENT
											| As.AppSearchMatch.KEYWORD);
				app_store.load_search_cache ();
			} catch (Error e) {
				warning (e.message);
			}
		}

		#if ENABLE_FLATPAK
		void load_flatpak_appstream_data () {
			try {
				new Thread<int>.try ("load_flatpak_appstream_data", () => {
					flatpak_plugin.load_appstream_data ();
					return 0;
				});
			} catch (Error e) {
				warning (e.message);
			}
		}
		#endif

		public void refresh () {
			alpm_config.reload ();
			alpm_handle = alpm_config.get_handle ();
			if (alpm_handle == null) {
				critical (dgettext (null, "Failed to initialize alpm library"));
				return;
			} else {
				files_handle = alpm_config.get_handle (true);
			}
			aur_vcs_pkgs.remove_all ();
			repos_pkgs.remove_all ();
		}

		public SList<string> get_mirrors_countries () {
			if (loop.is_running ()) {
				loop.run ();
			}
			var countries = new SList<string> ();
			try {
				new Thread<int>.try ("get_mirrors_countries", () => {
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
									countries.prepend (country);
								}
							}
							countries.reverse ();
						}
					} catch (SpawnError e) {
						warning (e.message);
					}
					loop.quit ();
					return 0;
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
			}
			return (owned) countries;
		}

		public string get_mirrors_choosen_country () {
			if (loop.is_running ()) {
				loop.run ();
			}
			string country = "";
			try {
				new Thread<int>.try ("get_mirrors_choosen_country", () => {
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
						warning (e.message);
					}
					loop.quit ();
					return 0;
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
			}
			return country;
		}

		public string get_alpm_dep_name (string dep_string) {
			return Alpm.Depend.from_string (dep_string).name;
		}

		public CompareFunc<string> vercmp = Alpm.pkg_vercmp;

		public HashTable<string, uint64?> get_clean_cache_details () {
			if (loop.is_running ()) {
				loop.run ();
			}
			var filenames_size = new HashTable<string, uint64?> (str_hash, str_equal);
			// compute all infos
			try {
				new Thread<int>.try ("get_clean_cache_details", () => {
					var pkg_version_filenames = new HashTable<string, GenericArray<string>> (str_hash, str_equal);
					var pkg_versions = new HashTable<string, GenericArray<string>> (str_hash, str_equal);
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
								string? name_version_release = filename.slice (0, filename.last_index_of_char ('-'));
								if (name_version_release == null) {
									continue;
								}
								int release_index = name_version_release.last_index_of_char ('-');
								string? name_version = name_version_release.slice (0, release_index);
								if (name_version == null) {
									continue;
								}
								int version_index = name_version.last_index_of_char ('-');
								string? name = name_version.slice (0, version_index);
								if (name == null) {
									continue;
								}
								if (config.clean_rm_only_uninstalled && is_installed_pkg (name)) {
									continue;
								}
								filenames_size.insert (absolute_filename, info.get_size ());
								if (pkg_versions.contains (name)) {
									if (pkg_version_filenames.contains (name_version_release)) {
										// case of .sig file
										unowned GenericArray<string> filenames = pkg_version_filenames.lookup (name_version_release);
										filenames.add ((owned) absolute_filename);
									} else {
										unowned GenericArray<string> versions = pkg_versions.lookup (name);
										string? version_release = name_version_release.slice (version_index + 1, name_version_release.length);
										if (version_release == null) {
											continue;
										}
										versions.add ((owned) version_release);
										var filenames = new GenericArray<string> ();
										filenames.add ((owned) absolute_filename);
										pkg_version_filenames.insert ((owned) name_version_release, (owned) filenames);
									}
								} else {
									var versions = new GenericArray<string> ();
									string? version_release = name_version_release.slice (version_index + 1, name_version_release.length);
									if (version_release == null) {
										continue;
									}
									versions.add ((owned) version_release);
									pkg_versions.insert (name, (owned) versions);
									var filenames = new GenericArray<string> ();
									filenames.add ((owned) absolute_filename);
									pkg_version_filenames.insert ((owned) name_version_release, (owned) filenames);
								}
							}
						} catch (Error e) {
							warning (e.message);
						}
						cachedirs_names.next ();
					}
					if (config.clean_keep_num_pkgs == 0) {
						loop.quit ();
						return 0;
					}
					// filter candidates
					var iter = HashTableIter<string, GenericArray<string>> (pkg_versions);
					unowned string name;
					unowned GenericArray<string> versions;
					while (iter.next (out name, out versions)) {
						// sort versions
						if (versions.length > config.clean_keep_num_pkgs) {
							versions.sort ((version1, version2) => {
								// reverse version 1 and version2 to have higher versions first
								return Alpm.pkg_vercmp (version2, version1);
							});
						}
						for (uint i = 0; i < versions.length; i++) {
							if (i == config.clean_keep_num_pkgs) {
								break;
							}
							unowned GenericArray<string>? filenames = pkg_version_filenames.lookup ("%s-%s".printf (name, versions[i]));
							if (filenames != null) {
								for (uint j = 0; j < filenames.length; j++) {
									filenames_size.remove (filenames[j]);
								}
							}
						}
					}
					loop.quit ();
					return 0;
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
			}
			return filenames_size;
		}

		public HashTable<string, uint64?> get_build_files_details () {
			if (loop.is_running ()) {
				loop.run ();
			}
			string real_aur_build_dir;
			if (config.aur_build_dir == "/var/tmp") {
				real_aur_build_dir = Path.build_path ("/", config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()));
			} else {
				real_aur_build_dir = Path.build_path ("/", config.aur_build_dir, "pamac-build");
			}
			var filenames_size = new HashTable<string, uint64?> (str_hash, str_equal);
			var build_directory = GLib.File.new_for_path (real_aur_build_dir);
			if (!build_directory.query_exists ()) {
				return filenames_size;
			}
			try {
				new Thread<int>.try ("get_build_files_details", () => {
					try {
						FileEnumerator enumerator = build_directory.enumerate_children ("standard::*", FileQueryInfoFlags.NONE);
						FileInfo info;
						while ((info = enumerator.next_file (null)) != null) {
							string absolute_filename = Path.build_path ("/", build_directory.get_path (), info.get_name ());
							var child = GLib.File.new_for_path (absolute_filename);
							uint64 disk_usage;
							child.measure_disk_usage (FileMeasureFlags.NONE, null, null, out disk_usage, null, null);
							filenames_size.insert (absolute_filename, disk_usage);
						}
					} catch (Error e) {
						warning (e.message);
					}
					loop.quit ();
					return 0;
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
			}
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

		public SList<AlpmPackage> get_installed_pkgs_by_glob (string glob) {
			var pkgs = new SList<AlpmPackage> ();
			unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
			while (pkgcache != null) {
				unowned Alpm.Package local_pkg = pkgcache.data;
				// only check by name
				if (Posix.fnmatch (glob, local_pkg.name) == 0) {
					pkgs.prepend (initialise_pkg (local_pkg));
				}
				pkgcache.next ();
			}
			pkgs.reverse ();
			return pkgs;
		}

		public bool should_hold (string pkgname) {
			return pkgname in alpm_config.holdpkgs;
		}

		public uint get_pkg_reason (string pkgname) {
			unowned Alpm.Package? pkg = alpm_handle.localdb.get_pkg (pkgname);
			if (pkg != null) {
				return pkg.reason;
			}
			return 0;
		}

		public SList<string> get_uninstalled_optdeps (string pkgname) {
			if (loop.is_running ()) {
				loop.run ();
			}
			var optdeps = new SList<string> ();
			try {
				new Thread<int>.try ("get_uninstalled_optdeps", () => {
					unowned Alpm.Package? pkg = get_syncpkg (pkgname);
					if (pkg != null) {
						unowned Alpm.List<unowned Alpm.Depend> optdepends = pkg.optdepends;
						while (optdepends != null) {
							string optdep = optdepends.data.compute_string ();
							unowned Alpm.Package? satisfier = Alpm.find_satisfier (alpm_handle.localdb.pkgcache, optdep);
							if (satisfier == null) {
								optdeps.prepend ((owned) optdep);
							}
							optdepends.next ();
						}
					}
					optdeps.reverse ();
					loop.quit ();
					return 0;
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
			}
			return (owned) optdeps;
		}

		string get_app_name (As.App app) {
			return app.get_name (null) ?? "";
		}

		string get_app_launchable (As.App app) {
			As.Launchable? launchable = app.get_launchable_by_kind (As.LaunchableKind.DESKTOP_ID);
			if (launchable != null) {
				return launchable.get_value ();
			}
			return "";
		}

		string get_app_summary (As.App app) {
			return app.get_comment (null) ?? "";
		}

		string get_app_description (As.App app) {
			return app.get_description (null) ?? "";
		}

		string get_app_icon (As.App app, string dbname) {
			string icon = "";
			unowned GenericArray<As.Icon> icons = app.get_icons ();
			for (uint i = 0; i < icons.length; i++) {
				As.Icon as_icon = icons[i];
				if (as_icon.get_kind () == As.IconKind.CACHED) {
					if (as_icon.get_height () == 64) {
						icon = "/usr/share/app-info/icons/archlinux-arch-%s/64x64/%s".printf (dbname, as_icon.get_name ());
					}
				}
			}
			return icon;
		}

		SList<string> get_app_screenshots (As.App app) {
			var screenshots = new SList<string> ();
			unowned GLib.GenericArray<As.Screenshot> as_screenshots = app.get_screenshots ();
			for (uint i = 0; i < as_screenshots.length; i++) {
				unowned As.Screenshot as_screenshot = as_screenshots[i];
				As.Image? as_image = as_screenshot.get_source ();
				if (as_image != null) {
					string? url = as_image.get_url ();
					if (url != null) {
						screenshots.prepend ((owned) url);
					}
				}
			}
			screenshots.reverse ();
			return screenshots;
		}

		GenericArray<As.App> get_pkgname_matching_apps (string pkgname) {
			var matching_apps = new GenericArray<As.App> ();
			unowned GenericArray<As.App> apps = app_store.get_apps ();
			for (uint i = 0; i < apps.length; i++) {
				As.App app = apps[i];
				if (app.get_pkgname_default () == pkgname) {
					matching_apps.add (app);
				}
			}
			return matching_apps;
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
			if (matching_apps.length == 1) {
				initialize_app_data (matching_apps[0], ref pkg);
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
				pkg.groups_priv.prepend (list.data);
				list.next ();
			}
			pkg.groups_priv.reverse ();
			// licenses
			list = alpm_pkg.licenses;
			while (list != null) {
				pkg.licenses_priv.prepend (list.data);
				list.next ();
			}
			pkg.licenses_priv.reverse ();
			// build_date
			pkg.builddate = alpm_pkg.builddate;
			// installed_size
			pkg.installed_size = alpm_pkg.isize;
			// download_size
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
					var builder = new StringBuilder ("/");
					builder.append (backups_list.data.name);
					pkg.backups_priv.prepend ((owned) builder.str);
					backups_list.next ();
				}
				pkg.backups_priv.reverse ();
				// requiredby
				Alpm.List<string> pkg_requiredby = alpm_pkg.compute_requiredby ();
				unowned Alpm.List<string> string_list = pkg_requiredby;
				while (string_list != null) {
					pkg.requiredby_priv.prepend ((owned) string_list.data);
					string_list.next ();
				}
				pkg.requiredby_priv.reverse ();
				// optionalfor
				Alpm.List<string> pkg_optionalfor = alpm_pkg.compute_optionalfor ();
				string_list = pkg_optionalfor;
				while (string_list != null) {
					pkg.optionalfor_priv.prepend ((owned) string_list.data);
					string_list.next ();
				}
				pkg.optionalfor_priv.reverse ();
			// sync pkg
			} else if (alpm_pkg.origin == Alpm.Package.From.SYNCDB) {
				// signature
				if (alpm_pkg.base64_sig != null) {
					pkg.has_signature = dgettext (null, "Yes");
				} else {
					pkg.has_signature = dgettext (null, "No");
				}
				// check if it is installed
				unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (alpm_pkg.name);
				if (local_pkg != null) {
					// installed_version
					pkg.installed_version = local_pkg.version;
					// compute details from local pkg, useful for updates
					// reason
					if (local_pkg.reason == Alpm.Package.Reason.EXPLICIT) {
						pkg.reason = dgettext (null, "Explicitly installed");
					} else if (local_pkg.reason == Alpm.Package.Reason.DEPEND) {
						pkg.reason = dgettext (null, "Installed as a dependency for another package");
					} else {
						pkg.reason = dgettext (null, "Unknown");
					}
					// backups
					unowned Alpm.List<unowned Alpm.Backup> backups_list = local_pkg.backups;
					while (backups_list != null) {
						var builder = new StringBuilder ("/");
						builder.append (backups_list.data.name);
						pkg.backups_priv.prepend ((owned) builder.str);
						backups_list.next ();
					}
					pkg.backups_priv.reverse ();
					// requiredby
					Alpm.List<string> pkg_requiredby = local_pkg.compute_requiredby ();
					unowned Alpm.List<string> string_list = pkg_requiredby;
					while (string_list != null) {
						pkg.requiredby_priv.prepend ((owned) string_list.data);
						string_list.next ();
					}
					pkg.requiredby_priv.reverse ();
					// optionalfor
					Alpm.List<string> pkg_optionalfor = local_pkg.compute_optionalfor ();
					string_list = pkg_optionalfor;
					while (string_list != null) {
						pkg.optionalfor_priv.prepend ((owned) string_list.data);
						string_list.next ();
					}
					pkg.optionalfor_priv.reverse ();
				}
			}
			// depends
			unowned Alpm.List<unowned Alpm.Depend> depends_list = alpm_pkg.depends;
			while (depends_list != null) {
				pkg.depends_priv.prepend (depends_list.data.compute_string ());
				depends_list.next ();
			}
			pkg.depends_priv.reverse ();
			// optdepends
			depends_list = alpm_pkg.optdepends;
			while (depends_list != null) {
				pkg.optdepends_priv.prepend (depends_list.data.compute_string ());
				depends_list.next ();
			}
			pkg.optdepends_priv.reverse ();
			// provides
			depends_list = alpm_pkg.provides;
			while (depends_list != null) {
				pkg.provides_priv.prepend (depends_list.data.compute_string ());
				depends_list.next ();
			}
			pkg.provides_priv.reverse ();
			// replaces
			depends_list = alpm_pkg.replaces;
			while (depends_list != null) {
				pkg.replaces_priv.prepend (depends_list.data.compute_string ());
				depends_list.next ();
			}
			pkg.replaces_priv.reverse ();
			// conflicts
			depends_list = alpm_pkg.conflicts;
			while (depends_list != null) {
				pkg.conflicts_priv.prepend (depends_list.data.compute_string ());
				depends_list.next ();
			}
			pkg.conflicts_priv.reverse ();
		}

		void initialize_app_data (As.App app, ref AlpmPackage pkg) {
			pkg.app_name = get_app_name (app);
			pkg.app_id = app.get_id ();
			pkg.launchable = get_app_launchable (app);
			pkg.desc = get_app_summary (app);
			try {
				pkg.long_desc = As.markup_convert_simple (get_app_description (app));
			} catch (Error e) {
				warning (e.message);
			}
			pkg.icon = get_app_icon (app, pkg.repo);
			pkg.screenshots_priv = get_app_screenshots (app);
		}

		void initialise_pkgs (Alpm.List<unowned Alpm.Package>? alpm_pkgs, ref SList<AlpmPackage> pkgs) {
			var data = new HashTable<string, AlpmPackage> (str_hash, str_equal);
			var foreign_pkgnames = new GenericArray<unowned string> ();
			while (alpm_pkgs != null) {
				unowned Alpm.Package alpm_pkg = alpm_pkgs.data;
				var pkg = new AlpmPackage ();
				initialise_pkg_common (alpm_pkg, ref pkg);
				if (alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
					unowned Alpm.Package? sync_pkg = get_syncpkg (alpm_pkg.name);
					if (sync_pkg != null) {
						pkg.repo = sync_pkg.db.name;
					} else if (config.enable_aur) {
						foreign_pkgnames.add (alpm_pkg.name);
					}
				} else if (alpm_pkg.origin == Alpm.Package.From.SYNCDB) {
					pkg.repo = alpm_pkg.db.name;
				}
				if (pkg.repo == "" ) {
					if (config.enable_aur) {
						data.insert (alpm_pkg.name, pkg);
					} else {
						pkgs.prepend (pkg);
					}
				} else {
					var apps = get_pkgname_matching_apps (alpm_pkg.name);
					if (apps.length > 0) {
						// alpm_pkg provide some apps
						initialize_app_data (apps[0], ref pkg);
						pkgs.prepend (pkg);
						for (uint i = 1; i < apps.length; i++) {
							var pkg_dup = pkg.dup ();
							initialize_app_data (apps[i], ref pkg_dup);
							pkgs.prepend (pkg_dup);
						}
					} else {
						pkgs.prepend (pkg);
					}
				}
				alpm_pkgs.next ();
			}
			// get aur infos
			if (foreign_pkgnames.length > 0) {
				var json_objects = aur.get_multi_infos (foreign_pkgnames.data);
				for (uint i = 0; i < json_objects.length; i++) {
					unowned Json.Object json_object = json_objects[i];
					unowned AlpmPackage? pkg = data.lookup (json_object.get_string_member ("Name"));
					if (pkg != null) {
						pkg.repo = dgettext (null, "AUR");
					}
				}
				var iter = HashTableIter<string, AlpmPackage> (data);
				unowned AlpmPackage pkg;
				while (iter.next (null, out pkg)) {
					pkgs.prepend (pkg);
				}
			}
		}

		public SList<AlpmPackage> get_installed_pkgs () {
			if (loop.is_running ()) {
				loop.run ();
			}
			var pkgs = new SList<AlpmPackage> ();
			try {
				new Thread<int>.try ("get_installed_pkgs", () => {
					initialise_pkgs (alpm_handle.localdb.pkgcache, ref pkgs);
					pkgs.sort (pkg_compare_name);
					loop.quit ();
					return 0;
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
			}
			return (owned) pkgs;
		}

		public SList<AlpmPackage> get_installed_apps () {
			if (loop.is_running ()) {
				loop.run ();
			}
			var pkgs = new SList<AlpmPackage> ();
			try {
				new Thread<int>.try ("get_installed_apps", () => {
					unowned GenericArray<As.App> apps = app_store.get_apps ();
					for (uint i = 0; i < apps.length; i++) {
						As.App app = apps[i];
						unowned string pkgname = app.get_pkgname_default ();
						unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (pkgname);
						if (local_pkg != null) {
							unowned Alpm.Package? sync_pkg = get_syncpkg (pkgname);
							if (sync_pkg != null) {
								var pkg = new AlpmPackage ();
								initialise_pkg_common (local_pkg, ref pkg);
								pkg.repo = sync_pkg.db.name;
								initialize_app_data (app, ref pkg);
								pkgs.prepend (pkg);
							}
						}
					}
					pkgs.reverse ();
					loop.quit ();
					return 0;
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
			}
			return (owned) pkgs;
		}

		public SList<AlpmPackage> get_explicitly_installed_pkgs () {
			if (loop.is_running ()) {
				loop.run ();
			}
			var pkgs = new SList<AlpmPackage> ();
			try {
				new Thread<int>.try ("get_explicitly_installed_pkgs", () => {
					Alpm.List<unowned Alpm.Package> alpm_pkgs = null;
					unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
					while (pkgcache != null) {
						unowned Alpm.Package alpm_pkg = pkgcache.data;
						if (alpm_pkg.reason == Alpm.Package.Reason.EXPLICIT) {
							alpm_pkgs.add (alpm_pkg);
						}
						pkgcache.next ();
					}
					initialise_pkgs (alpm_pkgs, ref pkgs);
					pkgs.sort (pkg_compare_name);
					loop.quit ();
					return 0;
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
			}
			return (owned) pkgs;
		}

		public SList<AlpmPackage> get_foreign_pkgs () {
			if (loop.is_running ()) {
				loop.run ();
			}
			var pkgs = new SList<AlpmPackage> ();
			try {
				new Thread<int>.try ("get_foreign_pkgs", () => {
					Alpm.List<unowned Alpm.Package> alpm_pkgs = null;
					unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
					while (pkgcache != null) {
						unowned Alpm.Package alpm_pkg = pkgcache.data;
						if (!is_sync_pkg (alpm_pkg.name)) {
							alpm_pkgs.add (alpm_pkg);
						}
						pkgcache.next ();
					}
					initialise_pkgs (alpm_pkgs, ref pkgs);
					pkgs.sort (pkg_compare_name);
					loop.quit ();
					return 0;
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
			}
			return (owned) pkgs;
		}

		public SList<AlpmPackage> get_orphans () {
			if (loop.is_running ()) {
				loop.run ();
			}
			var pkgs = new SList<AlpmPackage> ();
			try {
				new Thread<int>.try ("get_orphans", () => {
					Alpm.List<unowned Alpm.Package> alpm_pkgs = null;
					unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
					while (pkgcache != null) {
						unowned Alpm.Package alpm_pkg = pkgcache.data;
						if (alpm_pkg.reason == Alpm.Package.Reason.DEPEND) {
							Alpm.List<string> requiredby = alpm_pkg.compute_requiredby ();
							if (requiredby == null) {
								Alpm.List<string> optionalfor = alpm_pkg.compute_optionalfor ();
								if (optionalfor == null) {
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
					initialise_pkgs (alpm_pkgs, ref pkgs);
					pkgs.sort (pkg_compare_name);
					loop.quit ();
					return 0;
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
			}
			return (owned) pkgs;
		}

		unowned Alpm.Package? get_syncpkg (string pkgname) {
			// check repos_pkgs first
			unowned Alpm.Package? pkg;
			if (repos_pkgs.lookup_extended (pkgname, null, out pkg)) {
				return pkg;
			}
			// parse dbs and add pkg in repos_pkgs
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				pkg = db.get_pkg (pkgname);
				if (pkg != null) {
					break;
				}
				syncdbs.next ();
			}
			repos_pkgs.insert (pkgname, pkg);
			return pkg;
		}

		public bool is_sync_pkg (string pkgname) {
			// check repos_pkgs first
			unowned Alpm.Package? pkg;
			if (repos_pkgs.lookup_extended (pkgname, null, out pkg)) {
				if (pkg != null) {
					return true;
				}
				return false;
			}
			// parse dbs and add pkg in repos_pkgs
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				pkg = db.get_pkg (pkgname);
				if (pkg != null) {
					break;
				}
				syncdbs.next ();
			}
			repos_pkgs.insert (pkgname, pkg);
			if (pkg != null) {
				return true;
			}
			return false;
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

		public SList<AlpmPackage> get_sync_pkgs_by_glob (string glob) {
			var pkgs = new SList<AlpmPackage> ();
			// populate complete repos_pkgs
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			syncdbs.reverse ();
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				unowned Alpm.List<unowned Alpm.Package> pkgcache = db.pkgcache;
				while (pkgcache != null) {
					unowned Alpm.Package sync_pkg = pkgcache.data;
					repos_pkgs.replace (sync_pkg.name, sync_pkg);
					pkgcache.next ();
				}
				syncdbs.next ();
			}
			var iter = HashTableIter<unowned string, unowned Alpm.Package> (repos_pkgs);
			unowned Alpm.Package sync_pkg;
			while (iter.next (null, out sync_pkg)) {
				// only check by name
				if (Posix.fnmatch (glob, sync_pkg.name) == 0) {
					pkgs.prepend (initialise_pkg (sync_pkg));
				}
			}
			pkgs.reverse ();
			return pkgs;
		}

		public Package? get_app_by_id (string app_id) {
			if (loop.is_running ()) {
				loop.run ();
			}
			string app_id_short;
			string app_id_long;
			if (app_id.has_suffix (".desktop")) {
				app_id_long = app_id;
				app_id_short = app_id.replace (".desktop", "");
			} else {
				app_id_short = app_id;
				app_id_long = app_id + ".desktop";
			}
			Package? pkg = null;
			try {
				new Thread<int>.try ("get_uninstalled_app", () => {
					unowned GenericArray<As.App> apps = app_store.get_apps ();
					for (uint i = 0; i < apps.length; i++) {
						As.App app = apps[i];
						if (app.get_id () == app_id_short || app.get_id () == app_id_long || get_app_launchable (app) == app_id_long) {
							unowned string pkgname = app.get_pkgname_default ();
							unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (pkgname);
							unowned Alpm.Package? sync_pkg = get_syncpkg (pkgname);
							if (local_pkg != null) {
								var alpmpkg = new AlpmPackage ();
								initialise_pkg_common (local_pkg, ref alpmpkg);
								if (sync_pkg != null) {
									alpmpkg.repo = sync_pkg.db.name;
								}
								initialize_app_data (app, ref alpmpkg);
								pkg = alpmpkg;
							} else if (sync_pkg != null) {
								var alpmpkg = new AlpmPackage ();
								initialise_pkg_common (sync_pkg, ref alpmpkg);
								alpmpkg.repo = sync_pkg.db.name;
								initialize_app_data (app, ref alpmpkg);
								pkg = alpmpkg;
							}
						}
					}
					// try in installed files
					if (pkg == null) {
						bool found = false;
						unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
						while (pkgcache != null) {
							unowned Alpm.Package local_pkg = pkgcache.data;
							unowned Alpm.FileList filelist = local_pkg.files;
							Alpm.File* file_ptr = filelist.files;
							for (size_t i = 0; i < filelist.count; i++, file_ptr++) {
								// exclude directory name
								if (file_ptr->name.has_suffix (app_id_long)) {
									found = true;
									break;
								}
							}
							if (found) {
								var alpmpkg = new AlpmPackage ();
								initialise_pkg_common (local_pkg, ref alpmpkg);
								unowned Alpm.Package? sync_pkg = get_syncpkg (local_pkg.name);
								if (sync_pkg != null) {
									alpmpkg.repo = sync_pkg.db.name;
								}
								pkg = alpmpkg;
								break;
							}
							pkgcache.next ();
						}
					}
					#if ENABLE_FLATPAK
					if (pkg == null && config.enable_flatpak) {
						pkg = flatpak_plugin.get_flatpak_by_app_id (app_id);
					}
					#endif
					#if ENABLE_SNAP
					if (pkg == null && config.enable_snap) {
						pkg = snap_plugin.get_snap_by_app_id (app_id);
					}
					#endif
					loop.quit ();
					return 0;
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
			}
			return pkg;
		}

		Alpm.List<unowned Alpm.Package> custom_db_search (Alpm.DB db, Alpm.List<unowned string> needles) {
			Alpm.List<unowned Alpm.Package> needle_match = null;
			//if((db.usage & Alpm.DB.Usage.SEARCH) == 0) {
				//return result;
			//}
			// copy the pkgcache, we will free the list var after each needle
			Alpm.List<unowned Alpm.Package> all_match = db.pkgcache.copy ();
			unowned Alpm.List<unowned string> i = needles;
			while (i != null) {
				if (i.data == null) {
					continue;
				}
				needle_match = null;
				unowned string targ = i.data;
				Regex? regex = null;
				try {
					regex = new Regex (targ);
				} catch (Error e) {
					warning (e.message);
				}
				unowned Alpm.List<unowned Alpm.Package> j = all_match;
				while (j != null) {
					unowned Alpm.Package pkg = j.data;
					bool matched = false;
					unowned string name = pkg.name;
					unowned string desc = pkg.desc;
					// check name as plain text AND pattern
					if (name != null && (targ == name || (regex != null && regex.match (name)))) {
						matched = true;
					}
					// check if desc contains targ
					else if (desc != null && (targ in desc)) {
						matched = true;
					}
					if (!matched) {
						// check provides as plain text AND pattern
						unowned Alpm.List<unowned Alpm.Depend> provides = pkg.provides;
						while (provides != null) {
							unowned Alpm.Depend provide = provides.data;
							if (targ == provide.name || (regex != null && regex.match (provide.name))) {
								matched = true;
								break;
							}
							provides.next ();
						}
					}
					if (!matched) {
						// check groups as plain text AND pattern
						unowned Alpm.List<unowned string> groups = pkg.groups;
						while (groups != null) {
							unowned string group = groups.data;
							if (targ == group || (regex != null && regex.match (group))) {
								matched = true;
								break;
							}
							groups.next ();
						}
					}
					if (matched) {
						needle_match.add (pkg);
					}
					j.next ();
				}
				// use the returned list for the next needle
				// this allows for AND-based package searching
				all_match = (owned) needle_match;
				i.next ();
			}
			return all_match;
		}

		Alpm.List<unowned Alpm.Package> search_local_db (string search_string) {
			Alpm.List<unowned string> needles = null;
			string[] splitted = search_string.split (" ");
			foreach (unowned string part in splitted) {
				needles.add (part);
			}
			Alpm.List<unowned Alpm.Package> result = custom_db_search (alpm_handle.localdb, needles);
			// search in appstream
			string[]? search_terms = As.utils_search_tokenize (search_string);
			if (search_terms != null) {
				Alpm.List<unowned Alpm.Package> appstream_result = null;
				unowned GenericArray<As.App> apps = app_store.get_apps ();
				for (uint i = 0; i < apps.length; i++) {
					As.App app = apps[i];
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
				if (syncpkgs == null) {
					syncpkgs = custom_db_search (db, needles);
				} else {
					syncpkgs.join (custom_db_search (db, needles).diff (syncpkgs, (Alpm.List.CompareFunc) alpm_pkg_compare_name));
				}
				syncdbs.next ();
			}
			// remove foreign pkgs
			Alpm.List<unowned Alpm.Package> localpkgs = custom_db_search (alpm_handle.localdb, needles);
			Alpm.List<unowned Alpm.Package> result = syncpkgs.diff (localpkgs.diff (syncpkgs, (Alpm.List.CompareFunc) alpm_pkg_compare_name), (Alpm.List.CompareFunc) alpm_pkg_compare_name);
			// search in appstream
			string[]? search_terms = As.utils_search_tokenize (search_string);
			if (search_terms != null) {
				Alpm.List<unowned Alpm.Package> appstream_result = null;
				unowned GenericArray<As.App> apps = app_store.get_apps ();
				for (uint i = 0; i < apps.length; i++) {
					As.App app = apps[i];
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
				result.join (appstream_result.diff (result, (Alpm.List.CompareFunc) alpm_pkg_compare_name));
			}
			return result;
		}

		public SList<AlpmPackage> search_installed_pkgs (string search_string) {
			if (loop.is_running ()) {
				loop.run ();
			}
			string search_string_down = search_string.down ();
			var pkgs = new SList<AlpmPackage> ();
			try {
				new Thread<int>.try ("search_installed_pkgs", () => {
					initialise_pkgs (search_local_db (search_string_down), ref pkgs);
					// use custom sort function
					global_search_string = (owned) search_string_down;
					pkgs.sort (sort_search_pkgs_by_relevance);
					loop.quit ();
					return 0;
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
			}
			return (owned) pkgs;
		}

		public SList<AlpmPackage> search_repos_pkgs (string search_string) {
			if (loop.is_running ()) {
				loop.run ();
			}
			string search_string_down = search_string.down ();
			var pkgs = new SList<AlpmPackage> ();
			try {
				new Thread<int>.try ("search_repos_pkgs", () => {
					initialise_pkgs (search_sync_dbs (search_string_down), ref pkgs);
					// use custom sort function
					global_search_string = (owned) search_string_down;
					pkgs.sort (sort_search_pkgs_by_relevance);
					loop.quit ();
					return 0;
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
			}
			return (owned) pkgs;
		}

		Alpm.List<unowned Alpm.Package> search_all_dbs (string search_string) {
			Alpm.List<unowned string> needles = null;
			string[] splitted = search_string.split (" ");
			foreach (unowned string part in splitted) {
				needles.add (part);
			}
			Alpm.List<unowned Alpm.Package> result = custom_db_search (alpm_handle.localdb, needles);
			Alpm.List<unowned Alpm.Package> syncpkgs = null;
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				if (syncpkgs == null) {
					syncpkgs = custom_db_search (db, needles);
				} else {
					syncpkgs.join (custom_db_search (db, needles).diff (syncpkgs, (Alpm.List.CompareFunc) alpm_pkg_compare_name));
				}
				syncdbs.next ();
			}
			result.join (syncpkgs.diff (result, (Alpm.List.CompareFunc) alpm_pkg_compare_name));
			// search in appstream
			string[]? search_terms = As.utils_search_tokenize (search_string);
			if (search_terms != null) {
				Alpm.List<unowned Alpm.Package> appstream_result = null;
				unowned GenericArray<As.App> apps = app_store.get_apps ();
				for (uint i = 0; i < apps.length; i++) {
					As.App app = apps[i];
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
				result.join (appstream_result.diff (result, (Alpm.List.CompareFunc) alpm_pkg_compare_name));
			}
			return result;
		}

		public SList<AlpmPackage> search_uninstalled_apps_sync (string[] search_terms) {
			var search_string = new StringBuilder ();
			foreach (unowned string term in search_terms) {
				if (search_string.len > 0) {
					search_string.append (" ");
				}
				search_string.append (term);
			}
			// search only in appstream
			Alpm.List<unowned Alpm.Package> appstream_result = null;
			unowned GenericArray<As.App> apps = app_store.get_apps ();
			for (uint i = 0; i < apps.length; i++) {
				As.App app = apps[i];
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
			var pkgs = new SList<AlpmPackage> ();
			initialise_pkgs (appstream_result, ref pkgs);
			// doesn't work
			//#if ENABLE_SNAP
			//if (config.enable_snap) {
				//var snap_pkgs = new SList<SnapPackage> ();
				//try {
					//snap_plugin.search_uninstalled_snaps_sync (search_string.str, ref snap_pkgs);
					//foreach (unowned SnapPackage pkg in snap_pkgs) {
						//pkgs.prepend (pkg);
					//}
				//} catch (Error e) {
					//warning (e.message);
				//}
			//}
			//#endif
			//#if ENABLE_FLATPAK
			//if (config.enable_flatpak) {
				//var flatpak_pkgs = new SList<FlatpakPackage> ();
				//try {
					//flatpak_plugin.search_uninstalled_flatpaks_sync (search_terms, ref flatpak_pkgs);
					//foreach (unowned FlatpakPackage pkg in flatpak_pkgs) {
						//pkgs.prepend (pkg);
					//}
				//} catch (Error e) {
					//warning (e.message);
				//}
			//}
			//#endif
			global_search_string = (owned) search_string.str;
			pkgs.sort (sort_search_pkgs_by_relevance);
			return pkgs;
		}

		public SList<AlpmPackage> search_pkgs (string search_string) {
			if (loop.is_running ()) {
				loop.run ();
			}
			string search_string_down = search_string.down ();
			var pkgs = new SList<AlpmPackage> ();
			try {
				new Thread<int>.try ("search_pkgs", () => {
					initialise_pkgs (search_all_dbs (search_string_down), ref pkgs);
					// use custom sort function
					global_search_string = (owned) search_string_down;
					pkgs.sort (sort_search_pkgs_by_relevance);
					loop.quit ();
					return 0;
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
			}
			return (owned) pkgs;
		}

		public SList<AURPackage> search_aur_pkgs (string search_string) {
			if (loop.is_running ()) {
				loop.run ();
			}
			string search_string_down = search_string.down ();
			var pkgs = new SList<AURPackage> ();
			if (config.enable_aur) {
				try {
					new Thread<int>.try ("search_aur_pkgs", () => {
						var json_objects = aur.search (search_string_down);
						for (uint i = 0; i < json_objects.length; i++) {
							unowned Json.Object json_object = json_objects[i];
							unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (json_object.get_string_member ("Name"));
							pkgs.prepend (initialise_aur_pkg (json_object, local_pkg));
						}
						pkgs.reverse ();
						loop.quit ();
						return 0;
					});
					loop.run ();
				} catch (Error e) {
					warning (e.message);
				}
			}
			return (owned) pkgs;
		}

		public HashTable<string, SList<string>> search_files (string[] files) {
			var result = new HashTable<string, SList<string>> (str_hash, str_equal);
			foreach (unowned string file in files) {
				// search in localdb
				unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
				while (pkgcache != null) {
					unowned Alpm.Package alpm_pkg = pkgcache.data;
					var found_files = new SList<string> ();
					unowned Alpm.FileList filelist = alpm_pkg.files;
					Alpm.File* file_ptr = filelist.files;
					for (size_t i = 0; i < filelist.count; i++, file_ptr++) {
						// exclude directory name
						if (!file_ptr->name.has_suffix ("/")) {
							// adding / to compare
							var real_file_name = new StringBuilder (alpm_handle.root);
							real_file_name.append (file_ptr->name);
							if (file in real_file_name.str) {
								found_files.prepend ((owned) real_file_name.str);
							}
						}
					}
					found_files.reverse ();
					if (found_files != null) {
						result.insert (alpm_pkg.name, (owned) found_files);
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
						var found_files = new SList<string> ();
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
									found_files.prepend ((owned) real_file_name.str);
								}
							}
						}
						found_files.reverse ();
						if (found_files != null) {
							result.insert (alpm_pkg.name, (owned) found_files);
						}
						pkgcache.next ();
					}
					syncdbs.next ();
				}
			}
			return result;
		}

		public SList<string> get_categories_names () {
			var result = new SList<string> ();
			result.prepend ("Featured");
			result.prepend ("Photo & Video");
			result.prepend ("Music & Audio");
			result.prepend ("Productivity");
			result.prepend ("Communication & News");
			result.prepend ("Education & Science");
			result.prepend ("Games");
			result.prepend ("Utilities");
			result.prepend ("Development");
			result.reverse ();
			return result;
		}

		public SList<AlpmPackage> get_category_pkgs (string category) {
			if (loop.is_running ()) {
				loop.run ();
			}
			var result = new SList<AlpmPackage> ();
			string category_copy = category;
			try {
				new Thread<int>.try ("get_category_pkgs", () => {
					var appstream_categories = new GenericArray<string> ();
					switch (category_copy) {
						case "Featured":
							var featured_pkgs = new GenericArray<string> ();
							featured_pkgs.add ("firefox");
							featured_pkgs.add ("vlc");
							featured_pkgs.add ("gimp");
							featured_pkgs.add ("shotwell");
							featured_pkgs.add ("inkscape");
							featured_pkgs.add ("blender");
							featured_pkgs.add ("libreoffice-still");
							featured_pkgs.add ("telegram-desktop");
							featured_pkgs.add ("cura");
							featured_pkgs.add ("arduino");
							featured_pkgs.add ("retroarch");
							featured_pkgs.add ("virtualbox");
							unowned GenericArray<As.App> apps = app_store.get_apps ();
							for (uint i = 0; i < apps.length; i++) {
								As.App app = apps[i];
								unowned string pkgname = app.get_pkgname_default ();
								if (featured_pkgs.find_with_equal_func (pkgname, str_equal)) {
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
										result.prepend (pkg);
									}
								}
							}
							break;
						case "Photo & Video":
							appstream_categories.add ("Graphics");
							appstream_categories.add ("Video");
							break;
						case "Music & Audio":
							appstream_categories.add ("Audio");
							appstream_categories.add ("Music");
							break;
						case "Productivity":
							appstream_categories.add ("WebBrowser");
							appstream_categories.add ("Email");
							appstream_categories.add ("Office");
							break;
						case "Communication & News":
							appstream_categories.add ("Network");
							break;
						case "Education & Science":
							appstream_categories.add ("Education");
							appstream_categories.add ("Science");
							break;
						case "Games":
							appstream_categories.add ("Game");
							break;
						case "Utilities":
							appstream_categories.add ("Utility");
							break;
						case "Development":
							appstream_categories.add ("Development");
							break;
						default:
							break;
					}
					if (appstream_categories.length > 0) {
						unowned GenericArray<As.App> apps = app_store.get_apps ();
						for (uint i = 0; i < apps.length; i++) {
							As.App app = apps[i];
							unowned GenericArray<string> categories = app.get_categories ();
							for (uint j = 0; j < categories.length; j++) {
								string cat_name = categories[j];
								if (appstream_categories.find_with_equal_func (cat_name, str_equal)) {
									unowned string pkgname = app.get_pkgname_default ();
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
										result.prepend (pkg);
									}
									break;
								}
							}
						}
					}
					result.reverse ();
					loop.quit ();
					return 0;
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
			}
			return (owned) result;
		}

		public SList<string> get_repos_names () {
			var repos_names = new SList<string> ();
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				repos_names.prepend (db.name);
				syncdbs.next ();
			}
			repos_names.reverse ();
			return repos_names;
		}

		public SList<AlpmPackage> get_repo_pkgs (string repo) {
			if (loop.is_running ()) {
				loop.run ();
			}
			var pkgs = new SList<AlpmPackage> ();
			string repo_copy = repo;
			try {
				new Thread<int>.try ("get_repo_pkgs", () => {
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
					initialise_pkgs (alpm_pkgs, ref pkgs);
					pkgs.sort (pkg_compare_name);
					loop.quit ();
					return 0;
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
			}
			return (owned) pkgs;
		}

		public SList<string> get_groups_names () {
			var groups_names = new SList<string> ();
			unowned Alpm.List<unowned Alpm.Group> groupcache = alpm_handle.localdb.groupcache;
			while (groupcache != null) {
				unowned Alpm.Group group = groupcache.data;
				if (groups_names.find_custom (group.name, strcmp) == null) {
					groups_names.prepend (group.name);
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
						groups_names.prepend (group.name);
					}
					groupcache.next ();
				}
				syncdbs.next ();
			}
			groups_names.sort (strcmp);
			return groups_names;
		}

		public SList<AlpmPackage> get_group_pkgs (string group_name) {
			if (loop.is_running ()) {
				loop.run ();
			}
			var pkgs = new SList<AlpmPackage> ();
			string group_name_copy = group_name;
			try {
				new Thread<int>.try ("get_group_pkgs", () => {
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
					initialise_pkgs (alpm_pkgs, ref pkgs);
					pkgs.sort (pkg_compare_name);
					loop.quit ();
					return 0;
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
			}
			return (owned) pkgs;
		}

		public AlpmPackage? get_pkg (string pkgname) {
			if (is_installed_pkg (pkgname)) {
				return get_installed_pkg (pkgname);
			}
			return get_sync_pkg (pkgname);
		}

		public SList<string> get_pkg_files (string pkgname) {
			if (loop.is_running ()) {
				loop.run ();
			}
			var files = new SList<string> ();
			string pkgname_copy = pkgname;
			try {
				new Thread<int>.try ("get_pkg_files", () => {
					unowned Alpm.Package? alpm_pkg = alpm_handle.localdb.get_pkg (pkgname_copy);
					if (alpm_pkg != null) {
						unowned Alpm.FileList filelist = alpm_pkg.files;
						Alpm.File* file_ptr = filelist.files;
						for (size_t i = 0; i < filelist.count; i++, file_ptr++) {
							if (!file_ptr->name.has_suffix ("/")) {
								var filename = new StringBuilder (alpm_handle.root);
								filename.append (file_ptr->name);
								files.prepend ((owned) filename.str);
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
										files.prepend ((owned) filename.str);
									}
								}
								break;
							}
							syncdbs.next ();
						}
					}
					files.reverse ();
					loop.quit ();
					return 0;
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
			}
			return (owned) files;
		}

		int launch_subprocess (SubprocessLauncher launcher, string[] cmds, Cancellable? cancellable = null) {
			int status = 1;
			try {
				Subprocess process = launcher.spawnv (cmds);
				try {
					process.wait (cancellable);
					if (process.get_if_exited ()) {
						status = process.get_exit_status ();
					}
				} catch (Error e) {
					// cancelled
					process.send_signal (Posix.Signal.INT);
					process.send_signal (Posix.Signal.KILL);
					return 1;
				}
			} catch (Error e) {
				warning (e.message);
			}
			return status;
		}

		public File? clone_build_files (string pkgname, bool overwrite_files, Cancellable? cancellable = null) {
			if (loop.is_running ()) {
				loop.run ();
			}
			File? file = null;
			string pkgname_copy = pkgname;
			try {
				new Thread<int>.try ("clone_build_files", () => {
					file = clone_build_files_real (pkgname_copy, overwrite_files, cancellable);
					loop.quit ();
					return 0;
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
			}
			return file;
		}

		File? clone_build_files_real (string pkgname, bool overwrite_files, Cancellable? cancellable) {
			int status = 1;
			string[] cmds;
			var launcher = new SubprocessLauncher (SubprocessFlags.NONE);
			string real_aur_build_dir;
			if (config.aur_build_dir == "/var/tmp") {
				real_aur_build_dir = Path.build_path ("/", config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()));
			} else {
				real_aur_build_dir = Path.build_path ("/", config.aur_build_dir, "pamac-build");
			}
			var builddir = File.new_for_path (real_aur_build_dir);
			if (!builddir.query_exists ()) {
				try {
					builddir.make_directory_with_parents ();
				} catch (Error e) {
					warning (e.message);
					return null;
				}
			}
			var pkgdir = builddir.get_child (pkgname);
			if (pkgdir.query_exists ()) {
				if (overwrite_files) {
					launcher.set_cwd (real_aur_build_dir);
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
							warning (e.message);
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
						launcher.set_cwd (real_aur_build_dir);
						cmds = {"rm", "-rf", "%s".printf (pkgdir.get_path ())};
						launch_subprocess (launcher, cmds);
						cmds = {"git", "clone", "-q", "--depth=1", "https://aur.archlinux.org/%s.git".printf (pkgname)};
					}
				}
			} else {
				launcher.set_cwd (real_aur_build_dir);
				cmds = {"git", "clone", "-q", "--depth=1", "https://aur.archlinux.org/%s.git".printf (pkgname)};
			}
			status = launch_subprocess (launcher, cmds, cancellable);
			if (status == 0) {
				return pkgdir;
			}
			return null;
		}

		public bool regenerate_srcinfo (string pkgname, Cancellable? cancellable = null) {
			if (loop.is_running ()) {
				loop.run ();
			}
			bool success = false;
			string pkgname_copy = pkgname;
			try {
				new Thread<int>.try ("regenerate_srcinfo", () => {
					success = regenerate_srcinfo_real (pkgname_copy, cancellable);
					loop.quit ();
					return 0;
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
			}
			return success;
		}

		bool regenerate_srcinfo_real (string pkgname, Cancellable? cancellable) {
			string pkgdir_name;
			if (config.aur_build_dir == "/var/tmp") {
				pkgdir_name = Path.build_path ("/", config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()), pkgname);
			} else {
				pkgdir_name = Path.build_path ("/", config.aur_build_dir, "pamac-build", pkgname);
			}
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
					warning (e.message);
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
								warning (e.message);
							}
						}
					}
				} catch (Error e) {
					// cancelled
					process.send_signal (Posix.Signal.INT);
					process.send_signal (Posix.Signal.KILL);
				}
			} catch (Error e) {
				warning (e.message);
			}
			return false;
		}

		public AURPackage? get_aur_pkg (string pkgname) {
			if (loop.is_running ()) {
				loop.run ();
			}
			AURPackage? pkg = null;
			if (config.enable_aur) {
				string pkgname_copy = pkgname;
				try {
					new Thread<int>.try ("get_aur_pkg", () => {
						unowned Alpm.Package? local_pkg = null;
						unowned Json.Object? json_object = aur.get_infos (pkgname_copy);
						if (json_object != null) {
							local_pkg = alpm_handle.localdb.get_pkg (json_object.get_string_member ("Name"));
						}
						pkg = initialise_aur_pkg (json_object, local_pkg);
						loop.quit ();
						return 0;
					});
					loop.run ();
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkg;
		}

		public HashTable<string, AURPackage?> get_aur_pkgs (string[] pkgnames) {
			if (loop.is_running ()) {
				loop.run ();
			}
			var data = new HashTable<string, AURPackage?> (str_hash, str_equal);
			if (!config.enable_aur) {
				return data;
			}
			string[] pkgnames_copy = pkgnames;
			try {
				new Thread<int>.try ("get_aur_pkgs", () => {
					var json_objects = aur.get_multi_infos (pkgnames_copy);
					for (uint i = 0; i < json_objects.length; i++) {
						unowned Json.Object json_object = json_objects[i];
						unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (json_object.get_string_member ("Name"));
						data.insert (json_object.get_string_member ("Name"), initialise_aur_pkg (json_object, local_pkg));
					}
					loop.quit ();
					return 0;
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
			}
			foreach (unowned string pkgname in pkgnames_copy) {
				if (!data.contains (pkgname)) {
					data.insert (pkgname, null);
				}
			}
			return data;
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
						aur_pkg.licenses_priv.prepend (_node.get_string ());
					});
					aur_pkg.licenses_priv.reverse ();
				} else {
					aur_pkg.licenses_priv.append (dgettext (null, "Unknown"));
				}
				// depends
				node = json_object.get_member ("Depends");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						aur_pkg.depends_priv.prepend (_node.get_string ());
					});
					aur_pkg.depends_priv.reverse ();
				}
				// optdepends
				node = json_object.get_member ("OptDepends");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						aur_pkg.optdepends_priv.prepend (_node.get_string ());
					});
					aur_pkg.optdepends_priv.reverse ();
				}
				// provides
				node = json_object.get_member ("Provides");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						aur_pkg.provides_priv.prepend (_node.get_string ());
					});
					aur_pkg.provides_priv.reverse ();
				}
				// replaces
				node = json_object.get_member ("Replaces");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						aur_pkg.replaces_priv.prepend (_node.get_string ());
					});
					aur_pkg.replaces_priv.reverse ();
				}
				// conflicts
				node = json_object.get_member ("Conflicts");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						aur_pkg.conflicts_priv.prepend (_node.get_string ());
					});
					aur_pkg.conflicts_priv.reverse ();
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
					aur_pkg.makedepends_priv.prepend (_node.get_string ());
				});
				aur_pkg.makedepends_priv.reverse ();
			}
			// checkdepends
			node = json_object.get_member ("CheckDepends");
			if (node != null) {
				node.get_array ().foreach_element ((array, index, _node) => {
					aur_pkg.checkdepends_priv.prepend (_node.get_string ());
				});
				aur_pkg.checkdepends_priv.reverse ();
			}
			return aur_pkg;
		}

		public SList<string> get_srcinfo_pkgnames (string pkgdir) {
			var pkgnames = new SList<string> ();
			File srcinfo;
			if (config.aur_build_dir == "/var/tmp") {
				srcinfo = File.new_for_path (Path.build_path ("/", config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()), pkgdir, ".SRCINFO"));
			} else {
				srcinfo = File.new_for_path (Path.build_path ("/", config.aur_build_dir, "pamac-build", pkgdir, ".SRCINFO"));
			}
			if (srcinfo.query_exists ()) {
				try {
					// read .SRCINFO
					var dis = new DataInputStream (srcinfo.read ());
					string line;
					while ((line = dis.read_line ()) != null) {
						if ("pkgname = " in line) {
							string pkgname = line.split (" = ", 2)[1];
							pkgnames.prepend ((owned) pkgname);
						}
					}
				} catch (Error e) {
					warning (e.message);
				}
			}
			pkgnames.reverse ();
			return pkgnames;
		}

		internal SList<AURPackage> get_aur_updates (GenericSet<string?> temporary_ignorepkgs) {
			if (loop.is_running ()) {
				loop.run ();
			}
			// do not check for ignore pkgs here to have a warning in alpm_utils build_prepare
			var pkgs = new SList<AURPackage> ();
			var local_pkgs = new GenericArray<string> ();
			var vcs_local_pkgs = new GenericArray<string> ();
			try {
				new Thread<int>.try ("get_all_aur_updates", () => {
					// get local pkgs
					unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
					while (pkgcache != null) {
						unowned Alpm.Package installed_pkg = pkgcache.data;
						if (alpm_handle.should_ignore (installed_pkg) == 1 || installed_pkg.name in temporary_ignorepkgs) {
							pkgcache.next ();
							continue;
						}
						// check if installed_pkg is a local pkg
						unowned Alpm.Package? pkg = get_syncpkg (installed_pkg.name);
						if (pkg == null) {
							if (config.check_aur_vcs_updates &&
								(installed_pkg.name.has_suffix ("-git")
								|| installed_pkg.name.has_suffix ("-svn")
								|| installed_pkg.name.has_suffix ("-bzr")
								|| installed_pkg.name.has_suffix ("-hg"))) {
								vcs_local_pkgs.add (installed_pkg.name);
							} else {
								local_pkgs.add (installed_pkg.name);
							}
						}
						pkgcache.next ();
					}
					var aur_updates = get_aur_updates_real (aur.get_multi_infos (local_pkgs.data), vcs_local_pkgs, false);
					pkgs = (owned) aur_updates.updates;
					loop.quit ();
					return 0;
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
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
			if (loop.is_running ()) {
				loop.run ();
			}
			var updates = new Updates ();
			var local_pkgs = new GenericArray<string> ();
			var vcs_local_pkgs = new GenericArray<string> ();
			var repos_updates = new SList<AlpmPackage> ();
			var ignored_updates = new SList<AlpmPackage> ();
			try {
				new Thread<int>.try ("get_updates", () => {
					// be sure we have the good updates
					alpm_config.reload ();
					context.invoke (() => {
						get_updates_progress (0);
						return false;
					});
					var tmp_handle = alpm_config.get_handle (false, true);
					// refresh tmp dbs
					// count this step as 90% of the total
					unowned Alpm.List<unowned Alpm.DB> syncdbs = tmp_handle.syncdbs;
					size_t dbs_count = syncdbs.length ();
					size_t i = 0;
					while (syncdbs != null) {
						unowned Alpm.DB db = syncdbs.data;
						db.update (0);
						syncdbs.next ();
						i++;
						context.invoke (() => {
							get_updates_progress ((uint) ((double) i / dbs_count * (double) 90));
							return false;
						});
					}
					// check updates
					// count this step as 5% of the total
					unowned Alpm.List<unowned Alpm.Package> pkgcache = tmp_handle.localdb.pkgcache;
					while (pkgcache != null) {
						unowned Alpm.Package installed_pkg = pkgcache.data;
						unowned Alpm.Package? candidate = installed_pkg.get_new_version (tmp_handle.syncdbs);
						if (candidate != null) {
							// check if installed_pkg is in IgnorePkg or IgnoreGroup
							// check if candidate is in IgnorePkg or IgnoreGroup in case of replacer
							if (tmp_handle.should_ignore (installed_pkg) == 1 ||
								tmp_handle.should_ignore (candidate) == 1) {
								ignored_updates.prepend (initialise_pkg (candidate));
							} else {
								repos_updates.prepend (initialise_pkg (candidate));
							}
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
										vcs_local_pkgs.add (installed_pkg.name);
									} else {
										local_pkgs.add (installed_pkg.name);
									}
								}
							}
						}
						pkgcache.next ();
					}
					#if ENABLE_FLATPAK
					var flatpak_updates = new SList<FlatpakPackage> ();
					if (config.check_flatpak_updates) {
						flatpak_plugin.get_flatpak_updates (ref flatpak_updates);
					}
					#endif
					if (config.check_aur_updates) {
						// count this step as 5% of the total
						context.invoke (() => {
							get_updates_progress (95);
							return false;
						});
						var aur_updates = get_aur_updates_real (aur.get_multi_infos (local_pkgs.data), vcs_local_pkgs, true);
						context.invoke (() => {
							get_updates_progress (100);
							return false;
						});
						updates = new Updates.from_lists ((owned) repos_updates, (owned) ignored_updates, (owned) aur_updates.updates, (owned) aur_updates.ignored_updates, (owned) aur_updates.outofdate);
					} else {
						context.invoke (() => {
							get_updates_progress (100);
							return false;
						});
						updates = new Updates.from_lists ((owned) repos_updates, (owned) ignored_updates, new SList<AURPackage> (), new SList<AURPackage> (), new SList<AURPackage> ());
					}
					#if ENABLE_FLATPAK
					updates.set_flatpak_updates ((owned) flatpak_updates);
					#endif
					loop.quit ();
					return 0;
				});
				loop.run ();
			} catch (Error e) {
				warning (e.message);
			}
			return updates;
		}

		List<unowned AURPackage> get_vcs_last_version (GenericArray<string> vcs_local_pkgs) {
			for (uint i = 0; i < vcs_local_pkgs.length; i++) {
				unowned string pkgname = vcs_local_pkgs[i];
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
								var pkgnames_found = new GenericArray<string> ();
								var global_depends = new SList<string> ();
								var global_checkdepends = new GenericArray<string> ();
								var global_makedepends = new GenericArray<string> ();
								var global_conflicts = new SList<string> ();
								var global_provides = new SList<string> ();
								var global_replaces = new SList<string> ();
								var global_validpgpkeys = new GenericArray<string> ();
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
													global_checkdepends.add ((owned) depend);
												} else if ("makedepends" in line) {
													global_makedepends.add ((owned) depend);
												} else {
													global_depends.prepend ((owned) depend);
												}
											} else {
												unowned AURPackage? aur_pkg = pkgnames_table.get (current_section);
												if (aur_pkg != null) {
													aur_pkg.depends_priv.prepend ((owned) depend);
												}
											}
										}
									} else if ("provides" in line) {
										if ("provides = " in line || "provides_%s = ".printf (arch) in line) {
											string provide = line.split (" = ", 2)[1];
											if (current_section_is_pkgbase) {
												global_provides.prepend ((owned) provide);
											} else {
												unowned AURPackage? aur_pkg = pkgnames_table.get (current_section);
												if (aur_pkg != null) {
													aur_pkg.provides_priv.prepend ((owned) provide);
												}
											}
										}
									} else if ("conflicts" in line) {
										if ("conflicts = " in line || "conflicts_%s = ".printf (arch) in line) {
											string conflict = line.split (" = ", 2)[1];
											if (current_section_is_pkgbase) {
												global_conflicts.prepend ((owned) conflict);
											} else {
												unowned AURPackage? aur_pkg = pkgnames_table.get (current_section);
												if (aur_pkg != null) {
													aur_pkg.conflicts_priv.prepend ((owned) conflict);
												}
											}
										}
									} else if ("replaces" in line) {
										if ("replaces = " in line || "replaces_%s = ".printf (arch) in line) {
											string replace = line.split (" = ", 2)[1];
											if (current_section_is_pkgbase) {
												global_replaces.prepend ((owned) replace);
											} else {
												unowned AURPackage? aur_pkg = pkgnames_table.get (current_section);
												if (aur_pkg != null) {
													aur_pkg.replaces_priv.prepend ((owned) replace);
												}
											}
										}
									// grab validpgpkeys to check if they are imported
									} else if ("validpgpkeys" in line) {
										if ("validpgpkeys = " in line) {
											global_validpgpkeys.add (line.split (" = ", 2)[1]);
										}
									} else if ("pkgname = " in line) {
										string pkgname_found = line.split (" = ", 2)[1];
										current_section = pkgname_found;
										current_section_is_pkgbase = false;
										if (vcs_local_pkgs.find_with_equal_func (pkgname_found, str_equal)) {
											var aur_pkg = new AURPackage ();
											aur_pkg.name = pkgname_found;
											aur_pkg.version = version.str;
											aur_pkg.installed_version = alpm_handle.localdb.get_pkg (pkgname_found).version;
											aur_pkg.desc = desc;
											aur_pkg.packagebase = pkgbase;
											pkgnames_table.insert (pkgname_found, aur_pkg);
											pkgnames_found.add ((owned) pkgname_found);
										}
									}
								}
								for (uint j = 0; j < pkgnames_found.length; j++) {
									unowned string pkgname_found = pkgnames_found[j];
									AURPackage? aur_pkg = pkgnames_table.take (pkgname_found);
									// populate empty list will global ones
									uint k;
									if (aur_pkg.depends == null && global_depends.length != null) {
										aur_pkg.depends_priv = (owned) global_depends;
									}
									if (aur_pkg.provides == null && global_provides.length != null) {
										aur_pkg.provides_priv = (owned) global_provides;
									}
									if (aur_pkg.conflicts == null && global_conflicts.length != null) {
										aur_pkg.conflicts_priv = (owned) global_conflicts;
									}
									if (aur_pkg.replaces == null && global_replaces.length != null) {
										aur_pkg.replaces_priv = (owned) global_replaces;
									}
									// add checkdepends and makedepends in depends
									for (k = 0; k < global_checkdepends.length; k++) {
										aur_pkg.depends_priv.prepend (global_checkdepends[k]);
									}
									for (k = 0; k < global_makedepends.length; k++) {
										aur_pkg.depends_priv.prepend (global_makedepends[k]);
									}
									aur_vcs_pkgs.insert (pkgname_found, aur_pkg);
								}
							} catch (Error e) {
								warning (e.message);
								continue;
							}
						}
					}
				}
			}
			return aur_vcs_pkgs.get_values ();
		}

		AURUpdates get_aur_updates_real (GenericArray<unowned Json.Object> aur_infos, GenericArray<string> vcs_local_pkgs, bool check_ignorepkgs) {
			var updates = new SList<AURPackage> ();
			var outofdate = new SList<AURPackage> ();
			var ignored_updates = new SList<AURPackage> ();
			for (uint i = 0; i < aur_infos.length; i++) {
				unowned Json.Object pkg_info = aur_infos[i];
				unowned string name = pkg_info.get_string_member ("Name");
				unowned string new_version = pkg_info.get_string_member ("Version");
				unowned Alpm.Package local_pkg = alpm_handle.localdb.get_pkg (name);
				unowned string old_version = local_pkg.version;
				if (Alpm.pkg_vercmp (new_version, old_version) == 1) {
					if (check_ignorepkgs) {
						if (alpm_handle.ignorepkgs.find_str (name) == null) {
							updates.prepend (initialise_aur_pkg (pkg_info, local_pkg, true));
						} else {
							ignored_updates.prepend (initialise_aur_pkg (pkg_info, local_pkg, true));
						}
					} else {
						updates.prepend (initialise_aur_pkg (pkg_info, local_pkg, true));
					}
				} else if (!pkg_info.get_member ("OutOfDate").is_null ()) {
					// get out of date packages
					outofdate.prepend (initialise_aur_pkg (pkg_info, local_pkg));
				}
			}
			if (config.check_aur_vcs_updates) {
				var vcs_updates = get_vcs_last_version (vcs_local_pkgs);
				foreach (unowned AURPackage aur_pkg in vcs_updates) {
					if (Alpm.pkg_vercmp (aur_pkg.version, aur_pkg.installed_version) == 1) {
						if (check_ignorepkgs) {
							if (alpm_handle.ignorepkgs.find_str (aur_pkg.name) == null) {
								updates.prepend (aur_pkg);
							} else {
								ignored_updates.prepend (aur_pkg);
							}
						} else {
							updates.prepend (aur_pkg);
						}
					}
				}
			}
			return new AURUpdates ((owned) updates, (owned) ignored_updates, (owned) outofdate);
		}

		#if ENABLE_SNAP
		public SList<SnapPackage> search_snaps (string search_string) {
			if (loop.is_running ()) {
				loop.run ();
			}
			string search_string_down = search_string.down ();
			var pkgs = new SList<SnapPackage> ();
			if (config.enable_snap) {
				try {
					new Thread<int>.try ("search_snaps", () => {
						snap_plugin.search_snaps (search_string_down, ref pkgs);
						loop.quit ();
						return 0;
					});
					loop.run ();
				} catch (Error e) {
					warning (e.message);
				}
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
			if (loop.is_running ()) {
				loop.run ();
			}
			SnapPackage? pkg = null;
			if (config.enable_snap) {
				string name_copy = name;
				try {
					new Thread<int>.try ("get_snap", () => {
						pkg = snap_plugin.get_snap (name_copy);
						loop.quit ();
						return 0;
					});
					loop.run ();
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkg;
		}

		public SList<SnapPackage> get_installed_snaps () {
			if (loop.is_running ()) {
				loop.run ();
			}
			var pkgs = new SList<SnapPackage> ();
			if (config.enable_snap) {
				try {
					new Thread<int>.try ("get_installed_snaps", () => {
						snap_plugin.get_installed_snaps (ref pkgs);
						loop.quit ();
						return 0;
					});
					loop.run ();
				} catch (Error e) {
					warning (e.message);
				}
			}
			return (owned) pkgs;
		}

		public string get_installed_snap_icon (string name) {
			if (loop.is_running ()) {
				loop.run ();
			}
			string icon = "";
			if (config.enable_snap) {
				string name_copy = name;
				try {
					new Thread<int>.try ("get_installed_snap_icon", () => {
						try {
							icon = snap_plugin.get_installed_snap_icon (name_copy);
						} catch (Error e) {
							warning ("%s: %s", name_copy, e.message);
						}
						loop.quit ();
						return 0;
					});
					loop.run ();
				} catch (Error e) {
					warning (e.message);
				}
			}
			return icon;
		}

		public SList<SnapPackage> get_category_snaps (string category) {
			if (loop.is_running ()) {
				loop.run ();
			}
			var pkgs = new SList<SnapPackage> ();
			if (config.enable_snap) {
				string category_copy = category;
				try {
					new Thread<int>.try ("get_category_snaps", () => {
						snap_plugin.get_category_snaps (category_copy, ref pkgs);
						loop.quit ();
						return 0;
					});
					loop.run ();
				} catch (Error e) {
					warning (e.message);
				}
			}
			return (owned) pkgs;
		}
		#endif

		#if ENABLE_FLATPAK
		public SList<string> get_flatpak_remotes_names () {
			var list = new SList<string> ();
			if (config.enable_flatpak) {
				list = flatpak_plugin.get_remotes_names ();
			}
			return list;
		}

		public SList<FlatpakPackage> get_installed_flatpaks () {
			if (loop.is_running ()) {
				loop.run ();
			}
			var pkgs = new SList<FlatpakPackage> ();
			if (config.enable_flatpak) {
				try {
					new Thread<int>.try ("get_installed_flatpak", () => {
						flatpak_plugin.get_installed_flatpaks (ref pkgs);
						loop.quit ();
						return 0;
					});
					loop.run ();
				} catch (Error e) {
					warning (e.message);
				}
			}
			return (owned) pkgs;
		}

		public SList<FlatpakPackage> search_flatpaks (string search_string) {
			if (loop.is_running ()) {
				loop.run ();
			}
			var pkgs = new SList<FlatpakPackage> ();
			if (config.enable_flatpak) {
				string search_string_down = search_string.down ();
				try {
					new Thread<int>.try ("search_flatpaks", () => {
						flatpak_plugin.search_flatpaks (search_string_down, ref pkgs);
						loop.quit ();
						return 0;
					});
					loop.run ();
				} catch (Error e) {
					warning (e.message);
				}
			}
			return (owned) pkgs;
		}

		public bool is_installed_flatpak (string name) {
			if (config.enable_flatpak) {
				return flatpak_plugin.is_installed_flatpak (name);
			}
			return false;
		}

		public FlatpakPackage? get_flatpak (string id) {
			if (loop.is_running ()) {
				loop.run ();
			}
			FlatpakPackage? pkg = null;
			if (config.enable_flatpak) {
				string id_copy = id;
				try {
					new Thread<int>.try ("get_flatpak", () => {
						pkg = flatpak_plugin.get_flatpak (id_copy);
						loop.quit ();
						return 0;
					});
					loop.run ();
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkg;
		}

		public SList<FlatpakPackage> get_category_flatpaks (string category) {
			if (loop.is_running ()) {
				loop.run ();
			}
			var pkgs = new SList<FlatpakPackage> ();
			if (config.enable_flatpak) {
				string category_copy = category;
				try {
					new Thread<int>.try ("get_category_flatpaks", () => {
						flatpak_plugin.get_category_flatpaks (category_copy, ref pkgs);
						loop.quit ();
						return 0;
					});
					loop.run ();
				} catch (GLib.Error e) {
					warning (e.message);
				}
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

private int sort_search_pkgs_by_relevance (Pamac.Package pkg_a, Pamac.Package pkg_b) {
	if (global_search_string != null) {
		// display exact match first
		if (pkg_a.app_name.down () == global_search_string) {
			if (pkg_b.app_name.down () == global_search_string) {
				return sort_pkgs_by_relevance (pkg_a, pkg_b);
			}
			return -1;
		}
		if (pkg_b.app_name.down () == global_search_string) {
			return 1;
		}
		if (pkg_a.name == global_search_string) {
			if (pkg_b.name == global_search_string) {
				return sort_pkgs_by_relevance (pkg_a, pkg_b);
			}
			return -1;
		}
		if (pkg_b.name == global_search_string) {
			return 1;
		}
		if (pkg_a.app_name.down ().has_prefix (global_search_string)) {
			if (pkg_b.app_name.down ().has_prefix (global_search_string)) {
				return sort_pkgs_by_relevance (pkg_a, pkg_b);
			}
			return -1;
		}
		if (pkg_b.app_name.down ().has_prefix (global_search_string)) {
			return 1;
		}
		if (pkg_a.app_name.down ().contains (global_search_string)) {
			if (pkg_b.app_name.down ().contains (global_search_string)) {
				return sort_pkgs_by_relevance (pkg_a, pkg_b);
			}
			return -1;
		}
		if (pkg_b.app_name.down ().contains (global_search_string)) {
			return 1;
		}
		if (pkg_a.name.has_prefix (global_search_string + "-")) {
			if (pkg_b.name.has_prefix (global_search_string + "-")) {
				return sort_pkgs_by_relevance (pkg_a, pkg_b);
			}
			return -1;
		}
		if (pkg_b.name.has_prefix (global_search_string + "-")) {
			return 1;
		}
		if (pkg_a.name.has_prefix (global_search_string)) {
			if (pkg_b.name.has_prefix (global_search_string)) {
				return sort_pkgs_by_relevance (pkg_a, pkg_b);
			}
			return -1;
		}
		if (pkg_b.name.has_prefix (global_search_string)) {
			return 1;
		}
		if (pkg_a.name.contains (global_search_string)) {
			if (pkg_b.name.contains (global_search_string)) {
				return sort_pkgs_by_relevance (pkg_a, pkg_b);
			}
			return -1;
		}
		if (pkg_b.name.contains (global_search_string)) {
			return 1;
		}
	}
	return sort_pkgs_by_relevance (pkg_a, pkg_b);
}

private int sort_pkgs_by_relevance (Pamac.Package pkg_a, Pamac.Package pkg_b) {
	if (pkg_a.installed_version == "") {
		if (pkg_b.installed_version == "") {
			return sort_pkgs_by_name (pkg_a, pkg_b);
		}
		return 1;
	}
	if (pkg_b.installed_version == "") {
		return -1;
	}
	if (pkg_a.app_name == "") {
		if (pkg_b.app_name == "") {
			return sort_pkgs_by_name (pkg_a, pkg_b);
		}
		return 1;
	}
	if (pkg_b.app_name == "") {
		return -1;
	}
	return sort_pkgs_by_name (pkg_a, pkg_b);
}

private int sort_pkgs_by_name (Pamac.Package pkg_a, Pamac.Package pkg_b) {
	string str_a = pkg_a.app_name == "" ? pkg_a.name.collate_key () : pkg_a.app_name.down ().collate_key ();
	string str_b = pkg_b.app_name == "" ? pkg_b.name.collate_key () : pkg_b.app_name.down ().collate_key ();
	return strcmp (str_a, str_b);
}
