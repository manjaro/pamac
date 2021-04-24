/*
 *  pamac-vala
 *
 *  Copyright (C) 2019-2021 Guillaume Benoit <guillaume@manjaro.org>
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
	public class Database : Object {
		AlpmConfig alpm_config;
		Alpm.Handle? alpm_handle;
		Alpm.Handle? files_handle;
		AUR aur;
		As.Store app_store;
		HashTable<string, AURPackageData> aur_vcs_pkgs;
		HashTable<unowned string, AlpmPackageLinked> pkgs_cache;
		HashTable<unowned string, AURPackageLinked> aur_pkgs_cache;
		GenericArray<string> mirrors_countries;
		string mirrors_choosen_country;
		GenericArray<string> groups_names;
		GenericArray<string> repos_names;
		GenericArray<string> categories_names;
		bool appstream_enabled;
		SnapPlugin snap_plugin;
		FlatpakPlugin flatpak_plugin;

		public Config config { get; construct set; }
		internal unowned MainContext context { get; private set; }

		public signal void get_updates_progress (uint percent);

		public Database (Config config) {
			Object (config: config);
		}

		construct {
			alpm_config = config.alpm_config;
			context = MainContext.default ();
			aur_vcs_pkgs = new HashTable<string, AURPackageData> (str_hash, str_equal);
			pkgs_cache = new HashTable<unowned string, AlpmPackageLinked> (str_hash, str_equal);
			aur_pkgs_cache = new HashTable<unowned string, AURPackageLinked> (str_hash, str_equal);
			aur = new AUR ();
			// set HTTP_USER_AGENT needed when downloading using libalpm like refreshing dbs
			string user_agent = "Pamac/%s".printf (VERSION);
			Environment.set_variable ("HTTP_USER_AGENT", user_agent, true);
			// load snap plugin
			if (config.support_snap) {
				snap_plugin = config.get_snap_plugin ();
			}
			// load flatpak plugin
			if (config.support_flatpak) {
				flatpak_plugin = config.get_flatpak_plugin ();
				flatpak_plugin.refresh_period = config.refresh_period;
				if (config.enable_flatpak) {
					flatpak_plugin.load_appstream_data ();
				}
			}
			refresh ();
		}

		public void enable_appstream () {
			app_store = new As.Store ();
			app_store.add_filter (As.AppKind.DESKTOP);
			app_store.set_add_flags (As.StoreAddFlags.USE_UNIQUE_ID
									| As.StoreAddFlags.ONLY_NATIVE_LANGS
									| As.StoreAddFlags.USE_MERGE_HEURISTIC);
			try {
				app_store.load (As.StoreLoadFlags.APP_INFO_SYSTEM
								| As.StoreLoadFlags.IGNORE_INVALID);
				app_store.set_search_match (As.AppSearchMatch.PKGNAME
											| As.AppSearchMatch.DESCRIPTION
											| As.AppSearchMatch.NAME
											| As.AppSearchMatch.MIMETYPE
											| As.AppSearchMatch.COMMENT
											| As.AppSearchMatch.KEYWORD);
				appstream_enabled = true;
			} catch (Error e) {
				warning (e.message);
			}
		}

		public void refresh () {
			lock (alpm_config) {
				alpm_config.reload ();
				alpm_handle = alpm_config.get_handle ();
				if (alpm_handle == null) {
					critical (dgettext (null, "Failed to initialize alpm library"));
					return;
				} else {
					files_handle = alpm_config.get_handle (true);
				}
				aur_vcs_pkgs.remove_all ();
				pkgs_cache.remove_all ();
				aur_pkgs_cache.remove_all ();
			}
			if (config.enable_snap) {
				snap_plugin.refresh ();
			}
			if (config.enable_flatpak) {
				flatpak_plugin.refresh ();
			}
		}

		internal Alpm.Handle? get_tmp_handle () {
			lock (alpm_config) {
				return alpm_config.get_handle (false, true);
			}
		}

		public async unowned GenericArray<string> get_mirrors_countries_async () {
			if (mirrors_countries != null) {
				return mirrors_countries;
			}
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
							mirrors_countries = new GenericArray<string> ();
							foreach (unowned string country in countries_str.split ("\n")) {
								if (country != "") {
									mirrors_countries.add (country);
								}
							}
						}
					} catch (SpawnError e) {
						warning (e.message);
					}
					context.invoke (get_mirrors_countries_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return mirrors_countries;
		}

		public async unowned string get_mirrors_choosen_country_async () {
			if (mirrors_choosen_country != null) {
				return mirrors_choosen_country;
			}
			mirrors_choosen_country = "";
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
							mirrors_choosen_country = countries_str.split ("\n", 2)[0];
						}
					} catch (SpawnError e) {
						warning (e.message);
					}
					context.invoke (get_mirrors_choosen_country_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return mirrors_choosen_country;
		}

		public string get_alpm_dep_name (string dep_string) {
			return Alpm.Depend.from_string (dep_string).name;
		}

		public CompareFunc<string> vercmp = Alpm.pkg_vercmp;

		void get_clean_cache_details_real (ref HashTable<string, uint64?> filenames_size) {
			var pkg_version_filenames = new HashTable<string, GenericArray<string>> (str_hash, str_equal);
			var pkg_versions = new HashTable<string, GenericArray<string>> (str_hash, str_equal);
			lock (alpm_config) {
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
			}
			if (config.clean_keep_num_pkgs == 0) {
				return;
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
				uint i;
				uint length = versions.length;
				for (i = 0; i < length; i++) {
					if (i == config.clean_keep_num_pkgs) {
						break;
					}
					unowned GenericArray<string>? filenames = pkg_version_filenames.lookup ("%s-%s".printf (name, versions[i]));
					if (filenames != null) {
						foreach (unowned string filename in filenames) {
							filenames_size.remove (filename);
						}
					}
				}
			}
		}

		public HashTable<string, uint64?> get_clean_cache_details () {
			var filenames_size = new HashTable<string, uint64?> (str_hash, str_equal);
			get_clean_cache_details_real (ref filenames_size);
			return filenames_size;
		}

		public async HashTable<string, uint64?> get_clean_cache_details_async () {
			var filenames_size = new HashTable<string, uint64?> (str_hash, str_equal);
			try {
				new Thread<int>.try ("get_clean_cache_details", () => {
					get_clean_cache_details_real (ref filenames_size);
					context.invoke (get_clean_cache_details_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return filenames_size;
		}

		void get_build_files_details_real (ref HashTable<string, uint64?> filenames_size) {
			File build_directory;
			if (Posix.geteuid () == 0) {
				// build as root with systemd-run
				// set aur_build_dir to "/var/cache/pamac"
				build_directory = File.new_for_path ("/var/cache/pamac");
			} else if (config.aur_build_dir == "/var/tmp" || config.aur_build_dir == "/tmp") {
				build_directory = File.new_for_path (Path.build_filename (config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ())));
			} else {
				build_directory = File.new_for_path (config.aur_build_dir);
			}
			if (!build_directory.query_exists ()) {
				return;
			}
			try {
				FileEnumerator enumerator = build_directory.enumerate_children ("standard::*", FileQueryInfoFlags.NONE);
				FileInfo info;
				while ((info = enumerator.next_file (null)) != null) {
					string absolute_filename = Path.build_filename (build_directory.get_path (), info.get_name ());
					var child = GLib.File.new_for_path (absolute_filename);
					uint64 disk_usage;
					child.measure_disk_usage (FileMeasureFlags.NONE, null, null, out disk_usage, null, null);
					filenames_size.insert (absolute_filename, disk_usage);
				}
			} catch (Error e) {
				warning (e.message);
			}
		}

		public HashTable<string, uint64?> get_build_files_details () {
			var filenames_size = new HashTable<string, uint64?> (str_hash, str_equal);
			get_build_files_details_real (ref filenames_size);
			return filenames_size;
		}

		public async HashTable<string, uint64?> get_build_files_details_async () {
			var filenames_size = new HashTable<string, uint64?> (str_hash, str_equal);
			try {
				new Thread<int>.try ("get_build_files_details", () => {
					get_build_files_details_real (ref filenames_size);
					context.invoke (get_build_files_details_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return filenames_size;
		}

		public bool is_installed_pkg (string pkgname) {
			lock (alpm_config) {
				return alpm_handle.localdb.get_pkg (pkgname) != null;
			}
		}

		public AlpmPackage? get_installed_pkg (string pkgname) {
			lock (alpm_config) {
				return initialise_pkg (alpm_handle.localdb.get_pkg (pkgname));
			}
		}

		public bool has_installed_satisfier (string depstring) {
			lock (alpm_config) {
				return Alpm.find_satisfier (alpm_handle.localdb.pkgcache, depstring) != null;
			}
		}

		public AlpmPackage? get_installed_satisfier (string depstring) {
			lock (alpm_config) {
				return initialise_pkg (Alpm.find_satisfier (alpm_handle.localdb.pkgcache, depstring));
			}
		}

		public GenericArray<unowned AlpmPackage> get_installed_pkgs_by_glob (string glob) {
			var pkgs = new GenericArray<unowned AlpmPackage> ();
			lock (alpm_config) {
				unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
				while (pkgcache != null) {
					unowned Alpm.Package local_pkg = pkgcache.data;
					// only check by name
					if (Posix.fnmatch (glob, local_pkg.name) == 0) {
						pkgs.add (initialise_pkg (local_pkg));
					}
					pkgcache.next ();
				}
			}
			return pkgs;
		}

		public bool should_hold (string pkgname) {
			lock (alpm_config) {
				return pkgname in alpm_config.holdpkgs;
			}
		}

		public uint get_pkg_reason (string pkgname) {
			lock (alpm_config) {
				unowned Alpm.Package? pkg = alpm_handle.localdb.get_pkg (pkgname);
				if (pkg != null) {
					return pkg.reason;
				}
			}
			return 0;
		}

		internal async GenericArray<string> get_uninstalled_optdeps_async (string pkgname) {
			var optdeps = new GenericArray<string> ();
			string pkgname_copy = pkgname;
			try {
				new Thread<int>.try ("get_uninstalled_optdeps", () => {
					lock (alpm_config) {
						unowned Alpm.Package? pkg = get_syncpkg (alpm_handle, pkgname_copy);
						if (pkg != null) {
							unowned Alpm.List<unowned Alpm.Depend> optdepends = pkg.optdepends;
							while (optdepends != null) {
								string optdep = optdepends.data.compute_string ();
								unowned Alpm.Package? satisfier = Alpm.find_satisfier (alpm_handle.localdb.pkgcache, optdep);
								if (satisfier == null) {
									optdeps.add ((owned) optdep);
								}
								optdepends.next ();
							}
						}
					}
					context.invoke (get_uninstalled_optdeps_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return optdeps;
		}

		unowned string? get_app_launchable (As.App app) {
			As.Launchable? launchable = app.get_launchable_by_kind (As.LaunchableKind.DESKTOP_ID);
			if (launchable != null) {
				return launchable.get_value ();
			}
			return null;
		}

		GenericArray<As.App> get_pkgname_matching_apps (string pkgname) {
			var matching_apps = new GenericArray<As.App> ();
			unowned GenericArray<As.App> apps = app_store.get_apps ();
			foreach (unowned As.App app in apps) {
				if (app.get_pkgname_default () == pkgname) {
					matching_apps.add (app);
				}
			}
			return matching_apps;
		}

		AlpmPackageData initialise_pkg_data (Alpm.Handle? handle, Alpm.Package? sync_pkg) {
			// only use for updates so it is a sync_pkg
			unowned Alpm.Package? local_pkg = handle.localdb.get_pkg (sync_pkg.name);
			var pkg = new AlpmPackageData (sync_pkg, local_pkg, sync_pkg);
			if (appstream_enabled) {
				// find if pkgname provides only one app
				var matching_apps = get_pkgname_matching_apps (sync_pkg.name);
				if (matching_apps.length == 1) {
					pkg.set_as_app (matching_apps[0]);
				}
			}
			return pkg;
		}

		AlpmPackage? initialise_pkg (Alpm.Package? alpm_pkg) {
			if (alpm_pkg == null) {
				return null;
			}
			AlpmPackageLinked? pkg = null;
			// first search in cache only with pkgname
			unowned string pkgname = alpm_pkg.name;
			pkg = pkgs_cache.lookup (pkgname);
			if (pkg != null) {
				return pkg;
			}
			pkg = new AlpmPackageLinked.from_alpm (alpm_pkg, alpm_handle);
			if (config.enable_aur) {
				unowned Alpm.Package? sync_pkg = get_syncpkg (alpm_handle, pkgname);
				pkg.set_sync_pkg (sync_pkg);
				if (sync_pkg == null) {
					if (aur.get_infos (alpm_pkg.name) != null) {
						pkg.repo = dgettext (null, "AUR");
					}
				}
			}
			if (appstream_enabled) {
				// find if pkgname provides only one app
				var matching_apps = get_pkgname_matching_apps (pkgname);
				if (matching_apps.length == 1) {
					pkg.set_as_app (matching_apps[0]);
				}
			}
			pkgs_cache.replace (pkg.id, pkg);
			return pkg;
		}

		void initialise_search_pkgs (string search_string, Alpm.List<unowned Alpm.Package>? alpm_pkgs, bool installed, bool repos, ref GenericArray<unowned AlpmPackage> pkgs) {
			var data = new HashTable<unowned string, AlpmPackageLinked> (str_hash, str_equal);
			var foreign_pkgnames = new GenericArray<unowned string> ();
			// search in appstream
			if (appstream_enabled) {
				// add result names in a set
				var result_table = new HashTable<unowned string, unowned Alpm.Package> (str_hash, str_equal);
				unowned Alpm.List<unowned Alpm.Package> list = alpm_pkgs;
				while (list != null) {
					unowned Alpm.Package alpm_pkg = list.data;
					result_table.insert (alpm_pkg.name, alpm_pkg);
					list.next ();
				}
				string[]? search_terms = As.utils_search_tokenize (search_string);
				unowned GenericArray<As.App> apps = app_store.get_apps ();
				foreach (unowned As.App app in apps) {
					unowned string pkgname = app.get_pkgname_default ();
					unowned Alpm.Package alpm_pkg = result_table.lookup (pkgname);
					if (alpm_pkg != null) {
						string id = "%s/%s".printf (pkgname, app.get_name (null));
						AlpmPackageLinked pkg = pkgs_cache.lookup (id);
						if (pkg == null) {
							pkg = new AlpmPackageLinked.from_alpm (alpm_pkg, alpm_handle);
							pkg.set_as_app (app);
							// add in cache
							pkgs_cache.replace (pkg.id, pkg);
						}
						pkgs.add (pkg);
						// remove from result_table
						result_table.remove (pkgname);
					} else if (search_terms != null) {
						uint match_score = app.search_matches_all (search_terms);
						if (match_score > 0) {
							unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (pkgname);
							unowned Alpm.Package? sync_pkg = null;
							if (local_pkg == null && repos) {
								sync_pkg = get_syncpkg (alpm_handle, pkgname);
								alpm_pkg = sync_pkg;
							} else if (installed) {
								alpm_pkg = local_pkg;
							}
							if (alpm_pkg != null) {
								string id = "%s/%s".printf (pkgname, app.get_name (null));
								AlpmPackageLinked pkg = pkgs_cache.lookup (id);
								if (pkg == null) {
									pkg = new AlpmPackageLinked.from_alpm (alpm_pkg, alpm_handle);
									if (local_pkg != null) {
										pkg.set_local_pkg (local_pkg);
										// we didn't search the sync_pkg
									} else {
										// we did search the local_pkg
										pkg.set_local_pkg (local_pkg);
										pkg.set_sync_pkg (sync_pkg);
									}
									pkg.set_as_app (app);
									// add in cache
									pkgs_cache.replace (pkg.id, pkg);
								}
								pkgs.add (pkg);
							}
						}
					}
				}
				// compute pkgs not found in appstream
				var iter = HashTableIter<unowned string, unowned Alpm.Package> (result_table);
				unowned string pkgname;
				unowned Alpm.Package alpm_pkg;
				while (iter.next (out pkgname, out alpm_pkg)) {
					AlpmPackageLinked pkg = pkgs_cache.lookup (pkgname);
					if (pkg == null) {
						pkg = new AlpmPackageLinked.from_alpm (alpm_pkg, alpm_handle);
						if (config.enable_aur && alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
							unowned Alpm.Package? sync_pkg = get_syncpkg (alpm_handle, pkgname);
							pkg.set_sync_pkg (sync_pkg);
							pkg.set_local_pkg (alpm_pkg);
							if (sync_pkg == null) {
								foreign_pkgnames.add (pkgname);
								data.insert (pkgname, pkg);
							}
						} else if (alpm_pkg.origin == Alpm.Package.From.SYNCDB) {
							pkg.set_sync_pkg (alpm_pkg);
						}
						// add in cache
						pkgs_cache.replace (pkg.id, pkg);
					}
					pkgs.add (pkg);
				}
			} else {
				unowned Alpm.List<unowned Alpm.Package> list = alpm_pkgs;
				while (list != null) {
					unowned Alpm.Package alpm_pkg = list.data;
					unowned string pkgname = alpm_pkg.name;
					AlpmPackageLinked pkg = pkgs_cache.lookup (pkgname);
					if (pkg == null) {
						pkg = new AlpmPackageLinked.from_alpm (alpm_pkg, alpm_handle);
						if (config.enable_aur && alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
							unowned Alpm.Package? sync_pkg = get_syncpkg (alpm_handle, pkgname);
							pkg.set_sync_pkg (sync_pkg);
							pkg.set_local_pkg (alpm_pkg);
							if (sync_pkg == null) {
								foreign_pkgnames.add (pkgname);
								data.insert (pkgname, pkg);
							}
						}
						// add in cache
						pkgs_cache.replace (pkg.id, pkg);
					}
					pkgs.add (pkg);
					list.next ();
				}
			}
			// get aur infos
			if (foreign_pkgnames.length > 0) {
				var json_objects = aur.get_multi_infos (foreign_pkgnames.data);
				foreach (unowned Json.Object json_object in json_objects) {
					unowned AlpmPackageLinked? pkg = data.lookup (json_object.get_string_member ("Name"));
					if (pkg != null) {
						pkg.repo = dgettext (null, "AUR");
					}
				}
			}
		}

		void initialise_pkgs (Alpm.List<unowned Alpm.Package>? alpm_pkgs, ref GenericArray<unowned AlpmPackage> pkgs) {
			var data = new HashTable<unowned string, AlpmPackageLinked> (str_hash, str_equal);
			var foreign_pkgnames = new GenericArray<unowned string> ();
			while (alpm_pkgs != null) {
				unowned Alpm.Package alpm_pkg = alpm_pkgs.data;
				unowned string pkgname = alpm_pkg.name;
				// first search in cache only with pkgname
				AlpmPackageLinked? pkg = pkgs_cache.lookup (pkgname);
				if (pkg != null) {
					pkgs.add (pkg);
					alpm_pkgs.next ();
					continue;
				}
				pkg = new AlpmPackageLinked.from_alpm (alpm_pkg, alpm_handle);
				if (config.enable_aur && alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
					unowned Alpm.Package? sync_pkg = get_syncpkg (alpm_handle, pkgname);
					pkg.set_sync_pkg (sync_pkg);
					pkg.set_local_pkg (alpm_pkg);
					if (sync_pkg == null) {
						foreign_pkgnames.add (pkgname);
						data.insert (pkgname, pkg);
					}
				}
				if (appstream_enabled) {
					var apps = get_pkgname_matching_apps (pkgname);
					uint apps_length = apps.length;
					if (apps_length > 0) {
						// alpm_pkg provide some apps
						unowned As.App app = apps[0];
						pkg.set_as_app (app);
						// check if pkg with app exists in cache
						unowned AlpmPackageLinked? cached_pkg = pkgs_cache.lookup (pkg.id);
						if (cached_pkg == null) {
							// add in cache
							pkgs_cache.replace (pkg.id, pkg);
						} else {
							// keep cached pkg
							pkg = cached_pkg;
						}
						for (uint i = 1; i < apps_length; i++) {
							app = apps[i];
							string id = "%s/%s".printf (pkgname, app.get_name (null));
							cached_pkg = pkgs_cache.lookup (id);
							if (cached_pkg == null) {
								var pkg_dup = new AlpmPackageLinked.from_alpm (alpm_pkg, alpm_handle);
								pkg_dup.set_as_app (apps[i]);
								pkgs.add (pkg_dup);
								// add in cache
								pkgs_cache.replace (pkg_dup.id, pkg_dup);
							} else {
								// add cached pkg
								pkgs.add (cached_pkg);
							}
						}
					} else {
						// add in cache
						pkgs_cache.replace (pkg.id, pkg);
					}
				} else {
					// add in cache
					pkgs_cache.replace (pkg.id, pkg);
				}
				pkgs.add (pkg);
				alpm_pkgs.next ();
			}
			// get aur infos
			if (foreign_pkgnames.length > 0) {
				var json_objects = aur.get_multi_infos (foreign_pkgnames.data);
				foreach (unowned Json.Object json_object in json_objects) {
					unowned AlpmPackageLinked? pkg = data.lookup (json_object.get_string_member ("Name"));
					if (pkg != null) {
						pkg.repo = dgettext (null, "AUR");
					}
				}
			}
		}

		public GenericArray<unowned AlpmPackage> get_installed_pkgs () {
			var pkgs = new GenericArray<unowned AlpmPackage> ();
			lock (alpm_config) {
				initialise_pkgs (alpm_handle.localdb.pkgcache, ref pkgs);
			}
			return pkgs;
		}

		public async GenericArray<unowned AlpmPackage> get_installed_pkgs_async () {
			var pkgs = new GenericArray<unowned AlpmPackage> ();
			try {
				new Thread<int>.try ("get_installed_pkgs", () => {
					lock (alpm_config) {
						initialise_pkgs (alpm_handle.localdb.pkgcache, ref pkgs);
					}
					context.invoke (get_installed_pkgs_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return pkgs;
		}

		public async GenericArray<unowned AlpmPackage> get_installed_apps_async () {
			var pkgs = new GenericArray<unowned AlpmPackage> ();
			if (appstream_enabled) {
				try {
					new Thread<int>.try ("get_installed_apps", () => {
						lock (alpm_config) {
							unowned GenericArray<As.App> apps = app_store.get_apps ();
							foreach (unowned As.App app in apps) {
								unowned string pkgname = app.get_pkgname_default ();
								unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (pkgname);
								if (local_pkg != null) {
									unowned string? app_name = app.get_name (null);
									if (app_name != null) {
										AlpmPackageLinked? pkg = pkgs_cache.lookup ("%s/%s".printf (local_pkg.name, app_name));
										if (pkg != null) {
											pkgs.add (pkg);
											continue;
										}
									}
									var pkg = new AlpmPackageLinked.from_alpm (local_pkg, alpm_handle);
									pkg.set_local_pkg (local_pkg);
									pkg.set_as_app (app);
									pkgs.add (pkg);
									pkgs_cache.replace (pkg.id, pkg);
								}
							}
						}
						context.invoke (get_installed_apps_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkgs;
		}

		void get_explicitly_installed_pkgs_real (ref GenericArray<unowned AlpmPackage> pkgs) {
			lock (alpm_config) {
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
			}
		}

		public GenericArray<unowned AlpmPackage> get_explicitly_installed_pkgs () {
			var pkgs = new GenericArray<unowned AlpmPackage> ();
			get_explicitly_installed_pkgs_real (ref pkgs);
			return pkgs;
		}

		public async GenericArray<unowned AlpmPackage> get_explicitly_installed_pkgs_async () {
			var pkgs = new GenericArray<unowned AlpmPackage> ();
			try {
				new Thread<int>.try ("get_explicitly_installed_pkgs", () => {
					get_explicitly_installed_pkgs_real (ref pkgs);
					context.invoke (get_explicitly_installed_pkgs_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return pkgs;
		}

		void get_foreign_pkgs_real (ref GenericArray<unowned AlpmPackage> pkgs) {
			lock (alpm_config) {
				Alpm.List<unowned Alpm.Package> alpm_pkgs = null;
				unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
				while (pkgcache != null) {
					unowned Alpm.Package alpm_pkg = pkgcache.data;
					if (!is_syncpkg (alpm_pkg.name)) {
						alpm_pkgs.add (alpm_pkg);
					}
					pkgcache.next ();
				}
				initialise_pkgs (alpm_pkgs, ref pkgs);
			}
		}

		public GenericArray<unowned AlpmPackage> get_foreign_pkgs () {
			var pkgs = new GenericArray<unowned AlpmPackage> ();
			get_foreign_pkgs_real (ref pkgs);
			return pkgs;
		}

		public async GenericArray<unowned AlpmPackage> get_foreign_pkgs_async () {
			var pkgs = new GenericArray<unowned AlpmPackage> ();
			try {
				new Thread<int>.try ("get_foreign_pkgs", () => {
					get_foreign_pkgs_real (ref pkgs);
					context.invoke (get_foreign_pkgs_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return pkgs;
		}

		void get_orphans_real (ref GenericArray<unowned AlpmPackage> pkgs) {
			lock (alpm_config) {
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
			}
		}

		public GenericArray<unowned AlpmPackage> get_orphans () {
			var pkgs = new GenericArray<unowned AlpmPackage> ();
			get_orphans_real (ref pkgs);
			return pkgs;
		}

		public async GenericArray<unowned AlpmPackage> get_orphans_async () {
			var pkgs = new GenericArray<unowned AlpmPackage> ();
			try {
				new Thread<int>.try ("get_orphans", () => {
					get_orphans_real (ref pkgs);
					context.invoke (get_orphans_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return pkgs;
		}

		unowned Alpm.Package? get_syncpkg (Alpm.Handle? handle, string pkgname) {
			unowned Alpm.Package? pkg = null;
			unowned Alpm.List<unowned Alpm.DB> syncdbs = handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				pkg = db.get_pkg (pkgname);
				if (pkg != null) {
					break;
				}
				syncdbs.next ();
			}
			return pkg;
		}

		bool is_syncpkg (string pkgname) {
			unowned Alpm.Package? pkg = get_syncpkg (alpm_handle, pkgname);
			if (pkg != null) {
				return true;
			}
			return false;
		}

		public bool is_sync_pkg (string pkgname) {
			lock (alpm_config) {
				return is_syncpkg (pkgname);
			}
		}

		public AlpmPackage? get_sync_pkg (string pkgname) {
			lock (alpm_config) {
				return initialise_pkg (get_syncpkg (alpm_handle, pkgname));
			}
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
			lock (alpm_config) {
				return find_dbs_satisfier (depstring) != null;
			}
		}

		public AlpmPackage? get_sync_satisfier (string depstring) {
			lock (alpm_config) {
				return initialise_pkg (find_dbs_satisfier (depstring));
			}
		}

		public GenericArray<unowned AlpmPackage> get_sync_pkgs_by_glob (string glob) {
			var pkgs = new GenericArray<unowned AlpmPackage> ();
			lock (alpm_config) {
				unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
				syncdbs.reverse ();
				while (syncdbs != null) {
					unowned Alpm.DB db = syncdbs.data;
					unowned Alpm.List<unowned Alpm.Package> pkgcache = db.pkgcache;
					while (pkgcache != null) {
						unowned Alpm.Package sync_pkg = pkgcache.data;
						// only check by name
						if (Posix.fnmatch (glob, sync_pkg.name) == 0) {
							pkgs.add (initialise_pkg (sync_pkg));
						}
						pkgcache.next ();
					}
					syncdbs.next ();
				}
			}
			return pkgs;
		}

		public Package? get_app_by_id (string app_id) {
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
			lock (alpm_config) {
				if (appstream_enabled) {
					unowned GenericArray<As.App> apps = app_store.get_apps ();
					foreach (unowned As.App app in apps) {
						if (app.get_id () == app_id_short || app.get_id () == app_id_long || get_app_launchable (app) == app_id_long) {
							unowned string pkgname = app.get_pkgname_default ();
							unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (pkgname);
							if (local_pkg != null) {
								var alpmpkg = new AlpmPackageLinked.from_alpm (local_pkg, alpm_handle);
								alpmpkg.set_local_pkg (local_pkg);
								alpmpkg.set_as_app (app);
								pkg = alpmpkg;
							} else {
								unowned Alpm.Package? sync_pkg = get_syncpkg (alpm_handle, pkgname);
								if (sync_pkg != null) {
									var alpmpkg = new AlpmPackageLinked.from_alpm (sync_pkg, alpm_handle);
									alpmpkg.set_local_pkg (local_pkg);
									alpmpkg.set_sync_pkg (sync_pkg);
									alpmpkg.set_as_app (app);
									pkg = alpmpkg;
								}
							}
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
							var alpmpkg = new AlpmPackageLinked.from_alpm (local_pkg, alpm_handle);
							alpmpkg.set_local_pkg (local_pkg);
							pkg = alpmpkg;
							break;
						}
						pkgcache.next ();
					}
				}
			}
			if (pkg == null && config.enable_flatpak) {
				pkg = flatpak_plugin.get_flatpak_by_app_id (app_id);
			}
			if (pkg == null && config.enable_snap) {
				pkg = snap_plugin.get_snap_by_app_id (app_id);
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
			return custom_db_search (alpm_handle.localdb, needles);
		}

		Alpm.List<unowned Alpm.Package> search_sync_dbs (string search_string) {
			Alpm.List<unowned string> needles = null;
			string[] splitted = search_string.split (" ");
			foreach (unowned string part in splitted) {
				needles.add (part);
			}
			// add local pkgs found
			Alpm.List<unowned Alpm.Package> result = custom_db_search (alpm_handle.localdb, needles);
			// search sync pkgs found
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
			// remove foreign pkgs from local pkgs found
			Alpm.List<unowned Alpm.Package> foreigns = result.diff (syncpkgs, (Alpm.List.CompareFunc) alpm_pkg_compare_name);
			result = result.diff (foreigns, (Alpm.List.CompareFunc) alpm_pkg_compare_name);
			// add sync pkgs not already found in localdb
			result.join (syncpkgs.diff (result, (Alpm.List.CompareFunc) alpm_pkg_compare_name));
			return result;
		}

		public GenericArray<unowned AlpmPackage> search_installed_pkgs (string search_string) {
			string search_string_down = search_string.down ();
			var pkgs = new GenericArray<unowned AlpmPackage> ();
			lock (alpm_config) {
				initialise_search_pkgs (search_string_down, search_local_db (search_string_down), true, false, ref pkgs);
			}
			return pkgs;
		}

		public async GenericArray<unowned AlpmPackage> search_installed_pkgs_async (string search_string) {
			string search_string_down = search_string.down ();
			var pkgs = new GenericArray<unowned AlpmPackage> ();
			try {
				new Thread<int>.try ("search_installed_pkgs", () => {
					lock (alpm_config) {
						initialise_search_pkgs (search_string_down, search_local_db (search_string_down), true, false, ref pkgs);
					}
					context.invoke (search_installed_pkgs_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return pkgs;
		}

		public GenericArray<unowned AlpmPackage> search_repos_pkgs (string search_string) {
			string search_string_down = search_string.down ();
			var pkgs = new GenericArray<unowned AlpmPackage> ();
			lock (alpm_config) {
				initialise_search_pkgs (search_string_down, search_sync_dbs (search_string_down), false, true, ref pkgs);
			}
			return pkgs;
		}

		public async GenericArray<unowned AlpmPackage> search_repos_pkgs_async (string search_string) {
			string search_string_down = search_string.down ();
			var pkgs = new GenericArray<unowned AlpmPackage> ();
			try {
				new Thread<int>.try ("search_repos_pkgs", () => {
					lock (alpm_config) {
						initialise_search_pkgs (search_string_down, search_sync_dbs (search_string_down), false, true, ref pkgs);
					}
					context.invoke (search_repos_pkgs_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return pkgs;
		}

		Alpm.List<unowned Alpm.Package> search_all_dbs (string search_string) {
			Alpm.List<unowned string> needles = null;
			string[] splitted = search_string.split (" ");
			foreach (unowned string part in splitted) {
				needles.add (part);
			}
			// add local pkgs found
			Alpm.List<unowned Alpm.Package> result = custom_db_search (alpm_handle.localdb, needles);
			// search sync pkgs
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
			// add sync pkgs not already found in localdb
			result.join (syncpkgs.diff (result, (Alpm.List.CompareFunc) alpm_pkg_compare_name));
			return result;
		}

		public GenericArray<unowned AlpmPackage> search_uninstalled_apps (string[] search_terms) {
			var search_string = new StringBuilder ();
			foreach (unowned string term in search_terms) {
				if (search_string.len > 0) {
					search_string.append (" ");
				}
				search_string.append (term);
			}
			var pkgs = new GenericArray<unowned AlpmPackage> ();
			// search only in appstream
			lock (alpm_config) {
				Alpm.List<unowned Alpm.Package> appstream_result = null;
				if (appstream_enabled) {
					unowned GenericArray<As.App> apps = app_store.get_apps ();
					foreach (unowned As.App app in apps) {
						uint match_score = app.search_matches_all (search_terms);
						if (match_score > 0) {
							unowned string pkgname = app.get_pkgname_default ();
							unowned Alpm.Package? alpm_pkg = alpm_handle.localdb.get_pkg (pkgname);
							if (alpm_pkg == null) {
								alpm_pkg = get_syncpkg (alpm_handle, pkgname);
								if (alpm_pkg != null) {
									if (appstream_result.find (alpm_pkg, (Alpm.List.CompareFunc) alpm_pkg_compare_name) == null) {
										appstream_result.add (alpm_pkg);
									}
								}
							}
						}
					}
				}
				initialise_pkgs (appstream_result, ref pkgs);
			}
			// doesn't work
			//if (config.enable_snap) {
				//var snap_pkgs = new GenericArray<unowned SnapPackage> ();
				//try {
					//snap_plugin.search_uninstalled_snaps_sync (search_string.str, ref snap_pkgs);
					//foreach (unowned SnapPackage pkg in snap_pkgs) {
						//pkgs.add (pkg);
					//}
				//} catch (Error e) {
					//warning (e.message);
				//}
			//}
			//if (config.enable_flatpak) {
				//var flatpak_pkgs = new GenericArray<unowned FlatpakPackage> ();
				//try {
					//flatpak_plugin.search_uninstalled_flatpaks_sync (search_terms, ref flatpak_pkgs);
					//foreach (unowned FlatpakPackage pkg in flatpak_pkgs) {
						//pkgs.add (pkg);
					//}
				//} catch (Error e) {
					//warning (e.message);
				//}
			//}
			return pkgs;
		}

		public GenericArray<unowned AlpmPackage> search_pkgs (string search_string) {
			string search_string_down = search_string.down ();
			var pkgs = new GenericArray<unowned AlpmPackage> ();
			lock (alpm_config) {
				initialise_search_pkgs (search_string_down, search_all_dbs (search_string_down), true, true, ref pkgs);
			}
			return pkgs;
		}

		public async GenericArray<unowned AlpmPackage> search_pkgs_async (string search_string) {
			string search_string_down = search_string.down ();
			var pkgs = new GenericArray<unowned AlpmPackage> ();
			try {
				new Thread<int>.try ("search_pkgs", () => {
					lock (alpm_config) {
						initialise_search_pkgs (search_string_down, search_all_dbs (search_string_down), true, true, ref pkgs);
					}
					context.invoke (search_pkgs_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return pkgs;
		}

		void search_aur_pkgs_real (string search_string, ref GenericArray<unowned AURPackage> pkgs) {
			var json_objects = aur.search (search_string);
			lock (alpm_config) {
				foreach (unowned Json.Object json_object in json_objects) {
					unowned string name = json_object.get_string_member ("Name");
					AURPackageLinked pkg = aur_pkgs_cache.lookup (name);
					if (pkg == null) {
						unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (name);
						pkg = new AURPackageLinked ();
						pkg.initialise_from_json (json_object, aur, local_pkg);
						aur_pkgs_cache.replace (pkg.id, pkg);
					}
					pkgs.add (pkg);
				}
			}
		}

		public GenericArray<unowned AURPackage> search_aur_pkgs (string search_string) {
			string search_string_down = search_string.down ();
			var pkgs = new GenericArray<unowned AURPackage> ();
			if (config.enable_aur) {
				search_aur_pkgs_real (search_string_down, ref pkgs);
			}
			return pkgs;
		}

		public async GenericArray<unowned AURPackage> search_aur_pkgs_async (string search_string) {
			string search_string_down = search_string.down ();
			var pkgs = new GenericArray<unowned AURPackage> ();
			if (config.enable_aur) {
				try {
					new Thread<int>.try ("search_aur_pkgs", () => {
						search_aur_pkgs_real (search_string_down, ref pkgs);
						context.invoke (search_aur_pkgs_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkgs;
		}

		public HashTable<string, GenericArray<string>> search_files (string[] files) {
			var result = new HashTable<string, GenericArray<string>> (str_hash, str_equal);
			lock (alpm_config) {
				foreach (unowned string file in files) {
					// search in localdb
					unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
					while (pkgcache != null) {
						unowned Alpm.Package alpm_pkg = pkgcache.data;
						var found_files = new GenericArray<string> ();
						unowned Alpm.FileList filelist = alpm_pkg.files;
						Alpm.File* file_ptr = filelist.files;
						for (size_t i = 0; i < filelist.count; i++, file_ptr++) {
							// exclude directory name
							if (!file_ptr->name.has_suffix ("/")) {
								// adding / to compare
								var real_file_name = new StringBuilder (alpm_handle.root);
								real_file_name.append (file_ptr->name);
								if (file in real_file_name.str) {
									found_files.add ((owned) real_file_name.str);
								}
							}
						}
						if (found_files.length != 0) {
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
							var found_files = new GenericArray<string> ();
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
										found_files.add ((owned) real_file_name.str);
									}
								}
							}
							if (found_files.length != 0) {
								result.insert (alpm_pkg.name, (owned) found_files);
							}
							pkgcache.next ();
						}
						syncdbs.next ();
					}
				}
			}
			return result;
		}

		public unowned GenericArray<string> get_categories_names () {
			if (categories_names != null) {
				return categories_names;
			}
			categories_names = new GenericArray<string> ();
			categories_names.add ("Featured");
			categories_names.add ("Photo & Video");
			categories_names.add ("Music & Audio");
			categories_names.add ("Productivity");
			categories_names.add ("Communication & News");
			categories_names.add ("Education & Science");
			categories_names.add ("Games");
			categories_names.add ("Utilities");
			categories_names.add ("Development");
			return categories_names;
		}

		public async GenericArray<unowned AlpmPackage> get_category_pkgs_async (string category) {
			var pkgs = new GenericArray<unowned AlpmPackage> ();
			if (appstream_enabled) {
				string category_copy = category;
				try {
					new Thread<int>.try ("get_category_pkgs", () => {
						var names_set = new GenericSet<string> (str_hash, str_equal);
						switch (category_copy) {
							case "Featured":
								names_set.add ("firefox");
								names_set.add ("vlc");
								names_set.add ("gimp");
								names_set.add ("shotwell");
								names_set.add ("inkscape");
								names_set.add ("blender");
								names_set.add ("libreoffice-still");
								names_set.add ("telegram-desktop");
								names_set.add ("cura");
								names_set.add ("arduino");
								names_set.add ("retroarch");
								names_set.add ("virtualbox");
								lock (alpm_config) {
									unowned GenericArray<As.App> apps = app_store.get_apps ();
									foreach (unowned As.App app in apps) {
										unowned string pkgname = app.get_pkgname_default ();
										if (pkgname in names_set) {
											unowned Alpm.Package? sync_pkg = get_syncpkg (alpm_handle, pkgname);
											if (sync_pkg != null) {
												unowned string? app_name = app.get_name (null);
												if (app_name != null) {
													AlpmPackageLinked? pkg = pkgs_cache.lookup ("%s/%s".printf (sync_pkg.name, app_name));
													if (pkg != null) {
														pkgs.add (pkg);
														continue;
													}
												}
												var pkg = new AlpmPackageLinked.from_alpm (sync_pkg, alpm_handle);
												pkg.set_sync_pkg (sync_pkg);
												pkg.set_as_app (app);
												pkgs.add (pkg);
												pkgs_cache.replace (pkg.id, pkg);
											}
										}
									}
								}
								break;
							case "Photo & Video":
								names_set.add ("Graphics");
								names_set.add ("Video");
								break;
							case "Music & Audio":
								names_set.add ("Audio");
								names_set.add ("Music");
								break;
							case "Productivity":
								names_set.add ("WebBrowser");
								names_set.add ("Email");
								names_set.add ("Office");
								break;
							case "Communication & News":
								names_set.add ("Network");
								break;
							case "Education & Science":
								names_set.add ("Education");
								names_set.add ("Science");
								break;
							case "Games":
								names_set.add ("Game");
								break;
							case "Utilities":
								names_set.add ("Utility");
								break;
							case "Development":
								names_set.add ("Development");
								break;
							default:
								break;
						}
						if (names_set.length > 0) {
							lock (alpm_config) {
								unowned GenericArray<As.App> apps = app_store.get_apps ();
								foreach (unowned As.App app in apps) {
									unowned GenericArray<string> categories = app.get_categories ();
									foreach (unowned string cat_name in categories) {
										if (cat_name in names_set) {
											unowned string pkgname = app.get_pkgname_default ();
											unowned Alpm.Package? sync_pkg = get_syncpkg (alpm_handle, pkgname);
											if (sync_pkg != null) {
												unowned string? app_name = app.get_name (null);
												if (app_name != null) {
													AlpmPackageLinked? pkg = pkgs_cache.lookup ("%s/%s".printf (sync_pkg.name, app_name));
													if (pkg != null) {
														pkgs.add (pkg);
														break;
													}
												}
												var pkg = new AlpmPackageLinked.from_alpm (sync_pkg, alpm_handle);
												pkg.set_sync_pkg (sync_pkg);
												pkg.set_as_app (app);
												pkgs.add (pkg);
												pkgs_cache.replace (pkg.id, pkg);
											}
											break;
										}
									}
								}
							}
						}
						context.invoke (get_category_pkgs_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkgs;
		}

		public unowned GenericArray<string> get_repos_names () {
			if (repos_names != null) {
				return repos_names;
			}
			repos_names = new GenericArray<string> ();
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				repos_names.add (db.name);
				syncdbs.next ();
			}
			return repos_names;
		}

		void get_repo_pkgs_real (string repo, ref GenericArray<unowned AlpmPackage> pkgs) {
			lock (alpm_config) {
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
				initialise_pkgs (alpm_pkgs, ref pkgs);
			}
		}

		public GenericArray<unowned AlpmPackage> get_repo_pkgs (string repo) {
			var pkgs = new GenericArray<unowned AlpmPackage> ();
			get_repo_pkgs_real (repo, ref pkgs);
			return pkgs;
		}

		public async GenericArray<unowned AlpmPackage> get_repo_pkgs_async (string repo) {
			var pkgs = new GenericArray<unowned AlpmPackage> ();
			string repo_copy = repo;
			try {
				new Thread<int>.try ("get_repo_pkgs", () => {
					get_repo_pkgs_real (repo_copy, ref pkgs);
					context.invoke (get_repo_pkgs_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return pkgs;
		}

		public unowned GenericArray<string> get_groups_names () {
			if (groups_names != null) {
				return groups_names;
			}
			groups_names = new GenericArray<string> ();
			lock (alpm_config) {
				unowned Alpm.List<unowned Alpm.Group> groupcache = alpm_handle.localdb.groupcache;
				while (groupcache != null) {
					unowned Alpm.Group group = groupcache.data;
					groups_names.add (group.name);
					groupcache.next ();
				}
				unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
				while (syncdbs != null) {
					unowned Alpm.DB db = syncdbs.data;
					groupcache = db.groupcache;
					while (groupcache != null) {
						unowned Alpm.Group group = groupcache.data;
						if (!groups_names.find_with_equal_func (group.name, str_equal)) {
							groups_names.add (group.name);
						}
						groupcache.next ();
					}
					syncdbs.next ();
				}
			}
			groups_names.sort (strcmp);
			return groups_names;
		}

		void get_group_pkgs_real (string group_name, ref GenericArray<unowned AlpmPackage> pkgs) {
			lock (alpm_config) {
				Alpm.List<unowned Alpm.Package> alpm_pkgs = null;
				int dbs_found = 0;
				unowned Alpm.Group? grp = alpm_handle.localdb.get_group (group_name);
				if (grp != null) {
					dbs_found++;
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
					grp = db.get_group (group_name);
					if (grp != null) {
						dbs_found++;
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
				if (dbs_found > 1) {
					pkgs.sort (pkg_compare_name);
				}
			}
		}

		public GenericArray<unowned AlpmPackage> get_group_pkgs (string group_name) {
			var pkgs = new GenericArray<unowned AlpmPackage> ();
			get_group_pkgs_real (group_name, ref pkgs);
			return pkgs;
		}

		public async GenericArray<unowned AlpmPackage> get_group_pkgs_async (string group_name) {
			var pkgs = new GenericArray<unowned AlpmPackage> ();
			string group_name_copy = group_name;
			try {
				new Thread<int>.try ("get_group_pkgs", () => {
					get_group_pkgs_real (group_name_copy, ref pkgs);
					context.invoke (get_group_pkgs_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return pkgs;
		}

		public AlpmPackage? get_pkg (string pkgname) {
			if (is_installed_pkg (pkgname)) {
				return get_installed_pkg (pkgname);
			}
			return get_sync_pkg (pkgname);
		}

		void get_pkg_files_real (string pkgname, ref GenericArray<string> files) {
			lock (alpm_config) {
				unowned Alpm.Package? alpm_pkg = alpm_handle.localdb.get_pkg (pkgname);
				if (alpm_pkg != null) {
					unowned Alpm.FileList filelist = alpm_pkg.files;
					Alpm.File* file_ptr = filelist.files;
					for (size_t i = 0; i < filelist.count; i++, file_ptr++) {
						if (!file_ptr->name.has_suffix ("/")) {
							var filename = new StringBuilder (alpm_handle.root);
							filename.append (file_ptr->name);
							files.add ((owned) filename.str);
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
									files.add ((owned) filename.str);
								}
							}
							break;
						}
						syncdbs.next ();
					}
				}
			}
		}

		public string[] get_pkg_files (string pkgname) {
			var files = new GenericArray<string> ();
			get_pkg_files_real (pkgname, ref files);
			return files.steal ();
		}

		public async string[] get_pkg_files_async (string pkgname) {
			var files = new GenericArray<string> ();
			string pkgname_copy = pkgname;
			try {
				new Thread<int>.try ("get_pkg_files", () => {
					get_pkg_files_real (pkgname_copy, ref files);
					context.invoke (get_pkg_files_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return files.steal ();
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
			int status = 1;
			string[] cmdline;
			var launcher = new SubprocessLauncher (SubprocessFlags.NONE);
			string real_aur_build_dir;
			if (Posix.geteuid () == 0) {
				// build as root with systemd-run
				// set aur_build_dir to "/var/cache/pamac"
				real_aur_build_dir = "/var/cache/pamac";
			} else if (config.aur_build_dir == "/var/tmp" || config.aur_build_dir == "/tmp") {
				real_aur_build_dir = Path.build_filename (config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()));
			} else {
				real_aur_build_dir = config.aur_build_dir;
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
					string[] dynamic_user_cmdline = get_dynamic_user_cmdline (real_aur_build_dir);
					cmdline = dynamic_user_cmdline;
					cmdline += "rm";
					cmdline += "-rf";
					cmdline += "%s".printf (pkgdir.get_path ());
					launch_subprocess (launcher, cmdline);
					cmdline = dynamic_user_cmdline;
					cmdline += "git";
					cmdline += "clone";
					cmdline += "-q";
					cmdline += "--depth=1";
					cmdline += "https://aur.archlinux.org/%s.git".printf (pkgname);
				} else {
					// fetch modifications
					string cwd = pkgdir.get_path ();
					launcher.set_cwd (cwd);
					string[] dynamic_user_cmdline = get_dynamic_user_cmdline (cwd);
					cmdline = dynamic_user_cmdline;
					cmdline += "git";
					cmdline += "fetch";
					cmdline += "-q";
					status = launch_subprocess (launcher, cmdline, cancellable);
					if (cancellable.is_cancelled ()) {
						return null;
					}
					// write diff file
					if (status == 0) {
						launcher.set_flags (SubprocessFlags.STDOUT_PIPE);
						try {
							var file = File.new_for_path (Path.build_filename (cwd, "diff"));
							if (file.query_exists ()) {
								// delete the file before rewrite it
								file.delete ();
							}
							cmdline = dynamic_user_cmdline;
							cmdline += "git";
							cmdline += "diff";
							//cmdline += "--exit-code";
							cmdline += "origin/master";
							FileEnumerator enumerator = pkgdir.enumerate_children ("standard::*", FileQueryInfoFlags.NONE);
							FileInfo info;
							// don't show .SRCINFO diff
							while ((info = enumerator.next_file (null)) != null) {
								unowned string filename = info.get_name ();
								if (filename != ".SRCINFO") {
									cmdline += filename;
								}
							}
							Subprocess process = launcher.spawnv (cmdline);
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
						cmdline = dynamic_user_cmdline;
						cmdline += "git";
						cmdline += "merge";
						cmdline += "-q";
						status = launch_subprocess (launcher, cmdline);
					}
					if (status == 0) {
						return pkgdir;
					} else {
						launcher.set_cwd (real_aur_build_dir);
						dynamic_user_cmdline = get_dynamic_user_cmdline (real_aur_build_dir);
						cmdline = dynamic_user_cmdline;
						cmdline += "rm";
						cmdline += "-rf";
						cmdline += "%s".printf (pkgdir.get_path ());
						launch_subprocess (launcher, cmdline);
						cmdline = dynamic_user_cmdline;
						cmdline += "git";
						cmdline += "clone";
						cmdline += "-q";
						cmdline += "--depth=1";
						cmdline += "https://aur.archlinux.org/%s.git".printf (pkgname);
					}
				}
			} else {
				launcher.set_cwd (real_aur_build_dir);
				string[] dynamic_user_cmdline = get_dynamic_user_cmdline (real_aur_build_dir);
				cmdline = dynamic_user_cmdline;
				cmdline += "git";
				cmdline += "clone";
				cmdline += "-q";
				cmdline += "--depth=1";
				cmdline += "https://aur.archlinux.org/%s.git".printf (pkgname);
			}
			status = launch_subprocess (launcher, cmdline, cancellable);
			if (status == 0) {
				return pkgdir;
			}
			return null;
		}

		public async File? clone_build_files_async (string pkgname, bool overwrite_files, Cancellable? cancellable = null) {
			File? file = null;
			string pkgname_copy = pkgname;
			try {
				new Thread<int>.try ("clone_build_files", () => {
					file = clone_build_files (pkgname_copy, overwrite_files, cancellable);
					context.invoke (clone_build_files_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return file;
		}

		string[] get_dynamic_user_cmdline (string cwd) {
			string[] cmdline = {};
			if (Posix.geteuid () == 0) {
				cmdline += "systemd-run";
				cmdline += "--service-type=oneshot";
				cmdline += "--pipe";
				cmdline += "--wait";
				cmdline += "--pty";
				cmdline += "--property=DynamicUser=yes";
				cmdline += "--property=CacheDirectory=pamac";
				cmdline += "--property=WorkingDirectory=%s".printf (cwd);
			}
			return cmdline;
		}

		public bool regenerate_srcinfo (string pkgname, Cancellable? cancellable = null) {
			string pkgdir_name;
			if (Posix.geteuid () == 0) {
				// build as root with systemd-run
				// set aur_build_dir to "/var/cache/pamac"
				pkgdir_name = Path.build_filename ("/var/cache/pamac", pkgname);
			} else if (config.aur_build_dir == "/var/tmp" || config.aur_build_dir == "/tmp") {
				pkgdir_name = Path.build_filename (config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()), pkgname);
			} else {
				pkgdir_name = Path.build_filename (config.aur_build_dir, pkgname);
			}
			var srcinfo = File.new_for_path (Path.build_filename (pkgdir_name, ".SRCINFO"));
			var pkgbuild = File.new_for_path (Path.build_filename (pkgdir_name, "PKGBUILD"));
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
				string[] cmdline = get_dynamic_user_cmdline (pkgdir_name);
				cmdline += "makepkg";
				cmdline += "--printsrcinfo";
				Subprocess process = launcher.spawnv (cmdline);
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

		public async bool regenerate_srcinfo_async (string pkgname, Cancellable? cancellable = null) {
			bool success = false;
			string pkgname_copy = pkgname;
			try {
				new Thread<int>.try ("regenerate_srcinfo", () => {
					success = regenerate_srcinfo (pkgname_copy, cancellable);
					context.invoke (regenerate_srcinfo_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return success;
		}

		public AURPackage? get_aur_pkg (string pkgname) {
			AURPackageLinked? pkg = null;
			if (config.enable_aur) {
				lock (alpm_config) {
					pkg = aur_pkgs_cache.lookup (pkgname);
					if (pkg == null) {
						unowned Json.Object? json_object = aur.get_infos (pkgname);
						if (json_object != null) {
							unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (pkgname);
							pkg = new AURPackageLinked ();
							pkg.initialise_from_json (json_object, aur, local_pkg);
							aur_pkgs_cache.replace (pkg.id, pkg);
						}
					}
				}
			}
			return pkg;
		}

		public async AURPackage? get_aur_pkg_async (string pkgname) {
			AURPackage? pkg = null;
			if (config.enable_aur) {
				string pkgname_copy = pkgname;
				try {
					new Thread<int>.try ("get_aur_pkg", () => {
						pkg = get_aur_pkg (pkgname_copy);
						context.invoke (get_aur_pkg_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkg;
		}

		void get_aur_pkgs_real (string[] pkgnames, ref HashTable<string, unowned AURPackageLinked?> data) {
			// prepare data with all keys
			foreach (unowned string pkgname in pkgnames) {
				data.insert (pkgname, null);
			}
			var json_objects = aur.get_multi_infos (pkgnames);
			lock (alpm_config) {
				foreach (unowned Json.Object json_object in json_objects) {
					unowned string name = json_object.get_string_member ("Name");
					AURPackageLinked pkg = aur_pkgs_cache.lookup (name);
					if (pkg == null) {
						unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (name);
						pkg = new AURPackageLinked ();
						pkg.initialise_from_json (json_object, aur, local_pkg);
						aur_pkgs_cache.replace (pkg.id, pkg);
					}
					data.insert (name, pkg);
				}
			}
		}

		public HashTable<string, unowned AURPackage?> get_aur_pkgs (string[] pkgnames) {
			var data = new HashTable<string, unowned AURPackageLinked?> (str_hash, str_equal);
			if (!config.enable_aur) {
				return data;
			}
			get_aur_pkgs_real (pkgnames, ref data);
			return data;
		}

		public async HashTable<string, unowned AURPackage?> get_aur_pkgs_async (string[] pkgnames) {
			var data = new HashTable<string, unowned AURPackageLinked?> (str_hash, str_equal);
			if (!config.enable_aur) {
				return data;
			}
			string[] pkgnames_copy = pkgnames;
			try {
				new Thread<int>.try ("get_aur_pkgs", () => {
					get_aur_pkgs_real (pkgnames_copy, ref data);
					context.invoke (get_aur_pkgs_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return data;
		}

		public string[] get_srcinfo_pkgnames (string pkgdir) {
			var pkgnames = new GenericArray<string> ();
			File srcinfo;
			if (Posix.geteuid () == 0) {
				// build as root with systemd-run
				// set aur_build_dir to "/var/cache/pamac"
				srcinfo = File.new_for_path (Path.build_filename ("/var/cache/pamac", pkgdir, ".SRCINFO"));
			} else if (config.aur_build_dir == "/var/tmp" || config.aur_build_dir == "/tmp") {
				srcinfo = File.new_for_path (Path.build_filename (config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()), pkgdir, ".SRCINFO"));
			} else {
				srcinfo = File.new_for_path (Path.build_filename (config.aur_build_dir, pkgdir, ".SRCINFO"));
			}
			if (srcinfo.query_exists ()) {
				try {
					// read .SRCINFO
					var dis = new DataInputStream (srcinfo.read ());
					string line;
					while ((line = dis.read_line ()) != null) {
						if ("pkgname = " in line) {
							string pkgname = line.split (" = ", 2)[1];
							pkgnames.add ((owned) pkgname);
						}
					}
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkgnames.steal ();
		}

		public void refresh_tmp_files_dbs () {
			lock (alpm_config) {
				var tmp_files_handle = alpm_config.get_handle (true, true);
				if (tmp_files_handle == null) {
					return;
				}
				unowned Alpm.List<unowned Alpm.DB> syncdbs = tmp_files_handle.syncdbs;
				while (syncdbs != null) {
					unowned Alpm.DB db = syncdbs.data;
					db.update (0);
					syncdbs.next ();
				}
			}
		}

		public DateTime? get_last_refresh_time () {
			string timestamp_path = "/tmp/pamac/dbs/sync/refresh_timestamp";
			// check if last refresh is older than config.refresh_period
			try {
				var timestamp_file = File.new_for_path (timestamp_path);
				if (timestamp_file.query_exists ()) {
					FileInfo info = timestamp_file.query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
					return info.get_modification_date_time ().to_local ();
				} else {
					// create config directory
					File? parent = timestamp_file.get_parent ();
					if (parent != null && !parent.query_exists ()) {
						parent.make_directory_with_parents ();
					}
				}
			} catch (Error e) {
				warning (e.message);
			}
			return null;
		}

		int64 get_last_refresh_age () {
			DateTime? last_modifed = get_last_refresh_time ();
			if (last_modifed == null) {
				return int64.MAX;
			}
			var now = new DateTime.now_utc ();
			TimeSpan elapsed_time = now.difference (last_modifed);
			return elapsed_time;
		}

		public bool need_refresh () {
			bool need_refresh = true;
			int64 elapsed_time = get_last_refresh_age ();
			if (elapsed_time < TimeSpan.HOUR) {
				need_refresh = false;
			} else {
				int64 elapsed_hours = elapsed_time / TimeSpan.HOUR;
				if (elapsed_hours < config.refresh_period) {
					need_refresh = false;
				}
			}
			return need_refresh;
		}

		void get_updates_real (bool use_timestamp, ref Updates updates) {
			// be sure we have the good updates
			lock (alpm_config) {
				alpm_config.reload ();
				context.invoke (() => {
					get_updates_progress (0);
					return false;
				});
				var tmp_handle = get_tmp_handle ();
				if (tmp_handle == null) {
					return;
				}
				// add config ignore_pkgs
				foreach (unowned string name in config.ignorepkgs) {
					tmp_handle.add_ignorepkg (name);
				}
				bool refresh_tmp_dbs = true;
				if (use_timestamp) {
					refresh_tmp_dbs = need_refresh ();
				}
				if (refresh_tmp_dbs) {
					// refresh tmp dbs
					// count this step as 90% of the total
					bool success = true;
					unowned Alpm.List<unowned Alpm.DB> syncdbs = tmp_handle.syncdbs;
					size_t dbs_count = syncdbs.length ();
					size_t i = 0;
					while (syncdbs != null) {
						unowned Alpm.DB db = syncdbs.data;
						if (db.update (0) < 0) {
							success = false;
						}
						syncdbs.next ();
						i++;
						context.invoke (() => {
							get_updates_progress ((uint) ((double) i / dbs_count * (double) 90));
							return false;
						});
					}
					if (success) {
						// save now as last refresh time
						try {
							// touch the file
							string timestamp_path = "/tmp/pamac/dbs/sync/refresh_timestamp";
							Process.spawn_command_line_sync ("touch %s".printf (timestamp_path));
						} catch (SpawnError e) {
							warning (e.message);
						}
					}
				} else {
					// refresh step skipped
					context.invoke (() => {
						get_updates_progress (90);
						return false;
					});
				}
				// check updates
				// count this step as 5% of the total
				unowned GenericArray<AlpmPackage> repos_updates = updates.repos_updates;
				unowned GenericArray<AlpmPackage> ignored_repos_updates = updates.ignored_repos_updates;
				var local_pkgs = new GenericArray<string> ();
				var vcs_local_pkgs = new GenericArray<string> ();
				unowned Alpm.List<unowned Alpm.Package> pkgcache = tmp_handle.localdb.pkgcache;
				while (pkgcache != null) {
					unowned Alpm.Package installed_pkg = pkgcache.data;
					unowned Alpm.Package? candidate = installed_pkg.get_new_version (tmp_handle.syncdbs);
					if (candidate != null) {
						// check if installed_pkg is in IgnorePkg or IgnoreGroup
						// check if candidate is in IgnorePkg or IgnoreGroup in case of replacer
						if (tmp_handle.should_ignore (installed_pkg) == 1 ||
							tmp_handle.should_ignore (candidate) == 1) {
							var pkg = initialise_pkg_data (tmp_handle, candidate);
							ignored_repos_updates.add (pkg);
						} else {
							var pkg = initialise_pkg_data (tmp_handle, candidate);
							repos_updates.add (pkg);
						}
					} else {
						if (config.check_aur_updates) {
							// check if installed_pkg is a local pkg
							unowned Alpm.Package? pkg = get_syncpkg (tmp_handle, installed_pkg.name);
							if (pkg == null) {
								if (config.check_aur_vcs_updates &&
									(installed_pkg.name.has_suffix ("-git")
									|| installed_pkg.name.has_suffix ("-svn")
									|| installed_pkg.name.has_suffix ("-bzr")
									|| installed_pkg.name.has_suffix ("-hg"))) {
									// for speed reason, do not check vcs update for ignored packages
									if (tmp_handle.should_ignore (installed_pkg) == 0) {
										vcs_local_pkgs.add (installed_pkg.name);
									}
								} else {
									local_pkgs.add (installed_pkg.name);
								}
							}
						}
					}
					pkgcache.next ();
				}
				GenericArray<unowned FlatpakPackage> flatpak_updates = updates.flatpak_updates;
				if (config.check_flatpak_updates) {
					flatpak_plugin.get_flatpak_updates (ref flatpak_updates);
				}
				if (config.check_aur_updates) {
					if (config.check_aur_vcs_updates && refresh_tmp_dbs) {
						refresh_vcs_sources (vcs_local_pkgs);
					}
					// count this step as 5% of the total
					context.invoke (() => {
						get_updates_progress (95);
						return false;
					});
					get_aur_updates_real (aur.get_multi_infos (local_pkgs.data), vcs_local_pkgs, config.ignorepkgs, ref updates);
					context.invoke (() => {
						get_updates_progress (100);
						return false;
					});
				} else {
					context.invoke (() => {
						get_updates_progress (100);
						return false;
					});
				}
			}
		}

		public Updates get_updates (bool use_timestamp) {
			var updates = new Updates ();
			get_updates_real (use_timestamp, ref updates);
			return updates;
		}

		public async Updates get_updates_async (bool use_timestamp) {
			var updates = new Updates ();
			try {
				new Thread<int>.try ("get_updates", () => {
					get_updates_real (use_timestamp, ref updates);
					context.invoke (get_updates_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return updates;
		}

		void refresh_vcs_sources (GenericArray<string> vcs_local_pkgs) {
			foreach (unowned string pkgname in vcs_local_pkgs) {
				// get last build files
				unowned Json.Object? json_object = aur.get_infos (pkgname);
				if (json_object == null) {
					// error
					continue;
				}
				File? clone_dir = clone_build_files (json_object.get_string_member ("PackageBase"), false, null);
				if (clone_dir != null) {
					// get last sources
					// no output to not pollute checkupdates output
					var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
					string cwd = clone_dir.get_path ();
					launcher.set_cwd (cwd);
					string[] cmdline = get_dynamic_user_cmdline (cwd);
					cmdline += "makepkg";
					cmdline += "--nobuild";
					cmdline += "--noprepare";
					cmdline += "--nodeps";
					cmdline += "--skipinteg";
					int status = launch_subprocess (launcher, cmdline);
					if (status == 0) {
						regenerate_srcinfo (clone_dir.get_basename (), null);
					}
				}
			}
		}

		List<unowned AURPackageData> get_vcs_last_version (GenericArray<string> vcs_local_pkgs) {
			foreach (unowned string pkgname in vcs_local_pkgs) {
				if (aur_vcs_pkgs.contains (pkgname)) {
					continue;
				}
				string real_aur_build_dir;
				if (Posix.geteuid () == 0) {
					// build as root with systemd-run
					// set aur_build_dir to "/var/cache/pamac"
					real_aur_build_dir = "/var/cache/pamac";
				} else if (config.aur_build_dir == "/var/tmp" || config.aur_build_dir == "/tmp") {
					real_aur_build_dir = Path.build_filename (config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()));
				} else {
					real_aur_build_dir = config.aur_build_dir;
				}
				var pkgdir = File.new_for_path (Path.build_filename (real_aur_build_dir, pkgname));
				if (pkgdir.query_exists ()) {
					var srcinfo = pkgdir.get_child (".SRCINFO");
					try {
						// read .SRCINFO
						var dis = new DataInputStream (srcinfo.read ());
						string? line;
						string? current_section = null;
						bool current_section_is_pkgbase = true;
						var version = new StringBuilder ("");
						string? pkgbase = null;
						string? desc = null;
						string arch = Posix.utsname ().machine;
						var pkgnames_found = new GenericArray<string> ();
						var global_depends = new GenericArray<string> ();
						var global_checkdepends = new GenericArray<string> ();
						var global_makedepends = new GenericArray<string> ();
						var global_conflicts = new GenericArray<string> ();
						var global_provides = new GenericArray<string> ();
						var global_replaces = new GenericArray<string> ();
						var global_validpgpkeys = new GenericArray<string> ();
						var pkgnames_table = new HashTable<string, AURPackageData> (str_hash, str_equal);
						while ((line = dis.read_line ()) != null) {
							if ("pkgbase = " in line) {
								pkgbase = line.split (" = ", 2)[1];
							} else if ("pkgdesc = " in line) {
								desc = line.split (" = ", 2)[1];
								if (!current_section_is_pkgbase) {
									unowned AURPackageData? aur_pkg = pkgnames_table.get (current_section);
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
											global_depends.add ((owned) depend);
										}
									} else {
										unowned AURPackageData? aur_pkg = pkgnames_table.get (current_section);
										if (aur_pkg != null) {
											aur_pkg.depends.add ((owned) depend);
										}
									}
								}
							} else if ("provides" in line) {
								if ("provides = " in line || "provides_%s = ".printf (arch) in line) {
									string provide = line.split (" = ", 2)[1];
									if (current_section_is_pkgbase) {
										global_provides.add ((owned) provide);
									} else {
										unowned AURPackageData? aur_pkg = pkgnames_table.get (current_section);
										if (aur_pkg != null) {
											aur_pkg.provides.add ((owned) provide);
										}
									}
								}
							} else if ("conflicts" in line) {
								if ("conflicts = " in line || "conflicts_%s = ".printf (arch) in line) {
									string conflict = line.split (" = ", 2)[1];
									if (current_section_is_pkgbase) {
										global_conflicts.add ((owned) conflict);
									} else {
										unowned AURPackageData? aur_pkg = pkgnames_table.get (current_section);
										if (aur_pkg != null) {
											aur_pkg.conflicts.add ((owned) conflict);
										}
									}
								}
							} else if ("replaces" in line) {
								if ("replaces = " in line || "replaces_%s = ".printf (arch) in line) {
									string replace = line.split (" = ", 2)[1];
									if (current_section_is_pkgbase) {
										global_replaces.add ((owned) replace);
									} else {
										unowned AURPackageData? aur_pkg = pkgnames_table.get (current_section);
										if (aur_pkg != null) {
											aur_pkg.replaces.add ((owned) replace);
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
									var aur_pkg = new AURPackageData ();
									aur_pkg.name = pkgname_found;
									aur_pkg.id = pkgname_found;
									aur_pkg.version = version.str;
									aur_pkg.installed_version = alpm_handle.localdb.get_pkg (pkgname_found).version;
									aur_pkg.desc = desc;
									aur_pkg.packagebase = pkgbase;
									pkgnames_table.insert (pkgname_found, aur_pkg);
									pkgnames_found.add ((owned) pkgname_found);
								}
							}
						}
						foreach (unowned string pkgname_found in pkgnames_found) {
							AURPackageData? aur_pkg = pkgnames_table.take (pkgname_found);
							// populate empty list will global ones
							if (aur_pkg.depends.length == 0 && global_depends.length != 0) {
								aur_pkg.depends = global_depends.copy (strdup);
							}
							if (aur_pkg.provides.length == 0 && global_provides.length != 0) {
								aur_pkg.provides = global_provides.copy (strdup);
							}
							if (aur_pkg.conflicts.length == 0 && global_conflicts.length != 0) {
								aur_pkg.conflicts = global_conflicts.copy (strdup);
							}
							if (aur_pkg.replaces.length == 0 && global_replaces.length != 0) {
								aur_pkg.replaces = global_replaces.copy (strdup);
							}
							// add checkdepends and makedepends in depends
							foreach (unowned string global_checkdepend in global_checkdepends) {
								aur_pkg.depends.add (global_checkdepend);
							}
							foreach (unowned string global_makedepend in global_makedepends) {
								aur_pkg.depends.add (global_makedepend);
							}
							aur_vcs_pkgs.insert (pkgname_found, aur_pkg);
						}
					} catch (Error e) {
						warning (e.message);
						continue;
					}
				}
			}
			return aur_vcs_pkgs.get_values ();
		}

		void get_aur_updates_real (GenericArray<Json.Object> aur_infos, GenericArray<string> vcs_local_pkgs, GenericSet<string?> ignorepkgs, ref Updates updates) {
			unowned GenericArray<AURPackage> aur_updates = updates.aur_updates;
			unowned GenericArray<AURPackage> outofdate = updates.outofdate;
			unowned GenericArray<AURPackage> ignored_aur_updates = updates.ignored_aur_updates;
			foreach (unowned Json.Object json_object in aur_infos) {
				unowned string name = json_object.get_string_member ("Name");
				unowned string new_version = json_object.get_string_member ("Version");
				unowned Alpm.Package local_pkg = alpm_handle.localdb.get_pkg (name);
				unowned string old_version = local_pkg.version;
				var aur_pkg = new AURPackageLinked ();
				aur_pkg.initialise_from_json (json_object, aur, local_pkg, true);
				if (Alpm.pkg_vercmp (new_version, old_version) == 1) {
					if (local_pkg.name in ignorepkgs) {
						ignored_aur_updates.add (aur_pkg);
					} else {
						aur_updates.add (aur_pkg);
					}
				} else if (!json_object.get_member ("OutOfDate").is_null ()) {
					// get out of date packages
					outofdate.add (aur_pkg);
				}
			}
			if (config.check_aur_vcs_updates) {
				var vcs_updates = get_vcs_last_version (vcs_local_pkgs);
				foreach (unowned AURPackage aur_pkg in vcs_updates) {
					if (Alpm.pkg_vercmp (aur_pkg.version, aur_pkg.installed_version) == 1) {
						if (aur_pkg.name in ignorepkgs) {
							ignored_aur_updates.add (aur_pkg);
						} else {
							aur_updates.add (aur_pkg);
						}
					}
				}
			}
		}

		internal async Updates get_aur_updates_async (GenericSet<string?> ignorepkgs) {
			var updates = new Updates ();
			try {
				new Thread<int>.try ("get_aur_updates", () => {
					lock (alpm_config) {
						// get local pkgs
						var local_pkgs = new GenericArray<string> ();
						var vcs_local_pkgs = new GenericArray<string> ();
						// set ignorepkgs
						var full_ignorepkgs = new GenericSet<string?> (str_hash, str_equal);
						foreach (unowned string name in config.ignorepkgs) {
							full_ignorepkgs.add (name);
						}
						foreach (unowned string name in ignorepkgs) {
							full_ignorepkgs.add (name);
						}
						unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
						while (pkgcache != null) {
							unowned Alpm.Package installed_pkg = pkgcache.data;
							// check if installed_pkg is a local pkg
							unowned Alpm.Package? pkg = get_syncpkg (alpm_handle, installed_pkg.name);
							if (pkg == null) {
								if (config.check_aur_vcs_updates &&
									(installed_pkg.name.has_suffix ("-git")
									|| installed_pkg.name.has_suffix ("-svn")
									|| installed_pkg.name.has_suffix ("-bzr")
									|| installed_pkg.name.has_suffix ("-hg"))) {
									// for speed reason, do not check vcs update for ignored packages
									if (!(installed_pkg.name in full_ignorepkgs)) {
										vcs_local_pkgs.add (installed_pkg.name);
									}
								} else {
									// check for ignorepkgs done in get_aur_updates_real
									local_pkgs.add (installed_pkg.name);
								}
							}
							pkgcache.next ();
						}
						get_aur_updates_real (aur.get_multi_infos (local_pkgs.data), vcs_local_pkgs, full_ignorepkgs, ref updates);
					}
					context.invoke (get_aur_updates_async.callback);
					return 0;
				});
				yield;
			} catch (Error e) {
				warning (e.message);
			}
			return updates;
		}

		public async GenericArray<unowned SnapPackage> search_snaps_async (string search_string) {
			string search_string_down = search_string.down ();
			var pkgs = new GenericArray<unowned SnapPackage> ();
			if (config.enable_snap) {
				try {
					new Thread<int>.try ("search_snaps", () => {
						snap_plugin.search_snaps (search_string_down, ref pkgs);
						context.invoke (search_snaps_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkgs;
		}

		public bool is_installed_snap (string name) {
			if (config.enable_snap) {
				return snap_plugin.is_installed_snap (name);
			}
			return false;
		}

		public async SnapPackage? get_snap_async (string name) {
			SnapPackage? pkg = null;
			if (config.enable_snap) {
				string name_copy = name;
				try {
					new Thread<int>.try ("get_snap", () => {
						pkg = snap_plugin.get_snap (name_copy);
						context.invoke (get_snap_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkg;
		}

		public async GenericArray<unowned SnapPackage> get_installed_snaps_async () {
			var pkgs = new GenericArray<unowned SnapPackage> ();
			if (config.enable_snap) {
				try {
					new Thread<int>.try ("get_installed_snaps", () => {
						snap_plugin.get_installed_snaps (ref pkgs);
						context.invoke (get_installed_snaps_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkgs;
		}

		public async string get_installed_snap_icon_async (string name) {
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
						context.invoke (get_installed_snap_icon_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return icon;
		}

		public async GenericArray<unowned SnapPackage> get_category_snaps_async (string category) {
			var pkgs = new GenericArray<unowned SnapPackage> ();
			if (config.enable_snap) {
				string category_copy = category;
				try {
					new Thread<int>.try ("get_category_snaps", () => {
						snap_plugin.get_category_snaps (category_copy, ref pkgs);
						context.invoke (get_category_snaps_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkgs;
		}

		public void refresh_flatpak_appstream_data () {
			if (config.enable_flatpak) {
				flatpak_plugin.refresh_appstream_data ();
			}
		}

		public async void refresh_flatpak_appstream_data_async () {
			if (config.enable_flatpak) {
				try {
					new Thread<int>.try ("refresh_flatpak_appstream_data", () => {
						flatpak_plugin.refresh_appstream_data ();
						context.invoke (refresh_flatpak_appstream_data_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
		}

		public GenericArray<unowned string> get_flatpak_remotes_names () {
			var list = new GenericArray<unowned string> ();
			if (config.enable_flatpak) {
				flatpak_plugin.get_remotes_names (ref list);
			}
			return list;
		}

		public async GenericArray<unowned FlatpakPackage> get_installed_flatpaks_async () {
			var pkgs = new GenericArray<unowned FlatpakPackage> ();
			if (config.enable_flatpak) {
				try {
					new Thread<int>.try ("get_installed_flatpak", () => {
						flatpak_plugin.get_installed_flatpaks (ref pkgs);
						context.invoke (get_installed_flatpaks_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkgs;
		}

		public async GenericArray<unowned FlatpakPackage> search_flatpaks_async (string search_string) {
			var pkgs = new GenericArray<unowned FlatpakPackage> ();
			if (config.enable_flatpak) {
				string search_string_down = search_string.down ();
				try {
					new Thread<int>.try ("search_flatpaks", () => {
						flatpak_plugin.search_flatpaks (search_string_down, ref pkgs);
						context.invoke (search_flatpaks_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkgs;
		}

		public bool is_installed_flatpak (string name) {
			if (config.enable_flatpak) {
				return flatpak_plugin.is_installed_flatpak (name);
			}
			return false;
		}

		public async FlatpakPackage? get_flatpak_async (string id) {
			FlatpakPackage? pkg = null;
			if (config.enable_flatpak) {
				string id_copy = id;
				try {
					new Thread<int>.try ("get_flatpak", () => {
						pkg = flatpak_plugin.get_flatpak (id_copy);
						context.invoke (get_flatpak_async.callback);
						return 0;
					});
					yield;
				} catch (Error e) {
					warning (e.message);
				}
			}
			return pkg;
		}

		public async GenericArray<unowned FlatpakPackage> get_category_flatpaks_async (string category) {
			var pkgs = new GenericArray<unowned FlatpakPackage> ();
			if (config.enable_flatpak) {
				string category_copy = category;
				try {
					new Thread<int>.try ("get_category_flatpaks", () => {
						flatpak_plugin.get_category_flatpaks (category_copy, ref pkgs);
						context.invoke (get_category_flatpaks_async.callback);
						return 0;
					});
					yield;
				} catch (GLib.Error e) {
					warning (e.message);
				}
			}
			return pkgs;
		}
	}
}

int alpm_pkg_compare_name (Alpm.Package pkg_a, Alpm.Package pkg_b) {
	return strcmp (pkg_a.name, pkg_b.name);
}

int pkg_compare_name (Pamac.Package pkg_a, Pamac.Package pkg_b) {
	return strcmp (pkg_a.name, pkg_b.name);
}
