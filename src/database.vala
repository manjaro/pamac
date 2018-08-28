/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2018 Guillaume Benoit <guillaume@manjaro.org>
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
	[DBus (name = "org.manjaro.pamac.user")]
	interface UserDaemon : Object {
		public abstract void enable_appstream () throws Error;
		public abstract void refresh_handle () throws Error;
		public abstract string[] get_mirrors_countries () throws Error;
		public abstract string get_mirrors_choosen_country () throws Error;
		public abstract PackageStruct get_installed_pkg (string pkgname) throws Error;
		public abstract bool get_checkspace () throws Error;
		public abstract string[] get_ignorepkgs () throws Error;
		public abstract bool should_hold (string pkgname) throws Error;
		public abstract uint get_pkg_reason (string pkgname) throws Error;
		public abstract PackageStruct[] get_installed_pkgs () throws Error;
		public abstract PackageStruct[] get_installed_apps () throws Error;
		public abstract PackageStruct[] get_explicitly_installed_pkgs () throws Error;
		public abstract PackageStruct[] get_foreign_pkgs () throws Error;
		public abstract PackageStruct[] get_orphans () throws Error;
		public abstract async PackageStruct[] get_installed_pkgs_async () throws Error;
		public abstract async PackageStruct[] get_installed_apps_async () throws Error;
		public abstract async PackageStruct[] get_explicitly_installed_pkgs_async () throws Error;
		public abstract async PackageStruct[] get_foreign_pkgs_async() throws Error;
		public abstract async PackageStruct[] get_orphans_async () throws Error;
		public abstract PackageStruct find_installed_satisfier (string depstring) throws Error;
		public abstract PackageStruct get_sync_pkg (string pkgname) throws Error;
		public abstract PackageStruct find_sync_satisfier (string depstring) throws Error;
		public abstract PackageStruct[] search_pkgs (string search_string) throws Error;
		public abstract async PackageStruct[] search_pkgs_async (string search_string) throws Error;
		public abstract async AURPackageStruct[] search_in_aur_async (string search_string) throws Error;
		public abstract HashTable<string, Variant> search_files (string[] files) throws Error;
		public abstract PackageStruct[] get_category_pkgs (string category) throws Error;
		public abstract async PackageStruct[] get_category_pkgs_async (string category) throws Error;
		public abstract string[] get_repos_names () throws Error;
		public abstract PackageStruct[] get_repo_pkgs (string repo) throws Error;
		public abstract async PackageStruct[] get_repo_pkgs_async (string repo) throws Error;
		public abstract string[] get_groups_names () throws Error;
		public abstract PackageStruct[] get_group_pkgs (string groupname) throws Error;
		public abstract async PackageStruct[] get_group_pkgs_async (string groupname) throws Error;
		public abstract PackageDetailsStruct get_pkg_details (string pkgname, string app_name) throws Error;
		public abstract string[] get_pkg_files (string pkgname) throws Error;
		public abstract async AURPackageStruct get_aur_pkg_async (string pkgname) throws Error;
		public abstract async AURPackageDetailsStruct get_aur_pkg_details_async (string pkgname) throws Error;
		public abstract string[] get_pkg_uninstalled_optdeps (string pkgname) throws Error;
		public abstract void start_get_updates (bool check_aur_updates, bool refresh_files_dbs) throws Error;
		[DBus (no_reply = true)]
		public abstract void quit () throws Error;
		public signal void emit_get_updates_progress (uint percent);
		public signal void get_updates_finished (UpdatesStruct updates_struct);
	}

	public class Database: Object {
		UserDaemon user_daemon;

		public signal void get_updates_progress (uint percent);
		public signal void get_updates_finished (Updates updates);

		public Config config { get; construct set; }
		public bool refresh_files_dbs_on_get_updates { get; set; }

		public Database (Config config) {
			Object (config: config);
		}

		construct {
			connecting_user_daemon ();
			if (config.enable_aur == false) {
				config.check_aur_updates = false;
			}
			refresh_files_dbs_on_get_updates = false;
		}

		// destruction
		~Database () {
			stop_daemon ();
		}
    
		void connecting_user_daemon () {
			if (user_daemon == null) {
				try {
					user_daemon = Bus.get_proxy_sync (BusType.SESSION, "org.manjaro.pamac.user", "/org/manjaro/pamac/user");
				} catch (Error e) {
					stderr.printf ("Error: %s\n", e.message);
				}
			}
		}

		void stop_daemon () {
			try {
				user_daemon.quit ();
			} catch (Error e) {
				stderr.printf ("quit: %s\n", e.message);
			}
		}

		public void enable_appstream () {
			try {
				user_daemon.enable_appstream ();
			} catch (Error e) {
				stderr.printf ("enable_appstream: %s\n", e.message);
			}
		}

		public void refresh () {
			try {
				user_daemon.refresh_handle ();
			} catch (Error e) {
				stderr.printf ("refresh_handle: %s\n", e.message);
			}
		}

		public List<string> get_mirrors_countries () {
			var countries = new List<string> ();
			try {
				var countries_array = user_daemon.get_mirrors_countries ();
				foreach (string country in countries_array) {
					countries.append ((owned) country);
				} 
			} catch (Error e) {
				stderr.printf ("get_mirrors_countries: %s\n", e.message);
			}
			return countries;
		}

		public string get_mirrors_choosen_country () {
			string country = "";
			try {
				country = user_daemon.get_mirrors_choosen_country ();
			} catch (Error e) {
				stderr.printf ("get_mirrors_choosen_country: %s\n", e.message);
			}
			return country;
		}

		public bool get_checkspace () {
			bool checkspace = false;
			try {
				checkspace = user_daemon.get_checkspace ();
			} catch (Error e) {
				stderr.printf ("get_checkspace: %s\n", e.message);
			}
			return checkspace;
		}

		public List<string> get_ignorepkgs () {
			var ignorepkgs = new List<string> ();
			try {
				var ignorepkgs_array = user_daemon.get_ignorepkgs ();
				foreach (string ignorepkg in ignorepkgs_array) {
					ignorepkgs.append ((owned) ignorepkg);
				}
			} catch (Error e) {
				stderr.printf ("get_ignorepkgs: %s\n", e.message);
			}
			return ignorepkgs;
		}

		public Package get_installed_pkg (string pkgname) {
			try {
				var pkg_struct  = user_daemon.get_installed_pkg (pkgname);
				return new Package.from_struct (pkg_struct);
			} catch (Error e) {
				stderr.printf ("get_installed_pkg: %s\n", e.message);
				return new Package ();
			}
		}

		public Package find_installed_satisfier (string depstring) {
			try {
				var pkg_struct  = user_daemon.find_installed_satisfier (depstring);
				return new Package.from_struct (pkg_struct);
			} catch (Error e) {
				stderr.printf ("find_installed_satisfier: %s\n", e.message);
				return new Package ();
			}
		}

		public bool should_hold (string pkgname) {
			bool should_hold = false;
			try {
				should_hold = user_daemon.should_hold (pkgname);
			} catch (Error e) {
				stderr.printf ("should_hold: %s\n", e.message);
			}
			return should_hold;
		}

		public uint get_pkg_reason (string pkgname) {
			uint reason = 0;
			try {
				reason = user_daemon.get_pkg_reason (pkgname);
			} catch (Error e) {
				stderr.printf ("get_pkg_reason: %s\n", e.message);
			}
			return reason;
		}

		public List<Package> get_installed_pkgs () {
			var pkgs = new List<Package> ();
			try {
				var pkg_structs = user_daemon.get_installed_pkgs ();
				foreach (unowned PackageStruct pkg_struct in pkg_structs) {
					pkgs.append (new Package.from_struct (pkg_struct));
				}
			} catch (Error e) {
				stderr.printf ("get_installed_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public List<Package> get_installed_apps () {
			var pkgs = new List<Package> ();
			try {
				var pkg_structs = user_daemon.get_installed_apps ();
				foreach (unowned PackageStruct pkg_struct in pkg_structs) {
					pkgs.append (new Package.from_struct (pkg_struct));
				}
			} catch (Error e) {
				stderr.printf ("get_installed_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public List<Package> get_explicitly_installed_pkgs () {
			var pkgs = new List<Package> ();
			try {
				var pkg_structs = user_daemon.get_explicitly_installed_pkgs ();
				foreach (unowned PackageStruct pkg_struct in pkg_structs) {
					pkgs.append (new Package.from_struct (pkg_struct));
				}
			} catch (Error e) {
				stderr.printf ("get_installed_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public List<Package> get_foreign_pkgs () {
			var pkgs = new List<Package> ();
			try {
				var pkg_structs = user_daemon.get_foreign_pkgs ();
				foreach (unowned PackageStruct pkg_struct in pkg_structs) {
					pkgs.append (new Package.from_struct (pkg_struct));
				}
			} catch (Error e) {
				stderr.printf ("get_installed_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public List<Package> get_orphans () {
			var pkgs = new List<Package> ();
			try {
				var pkg_structs = user_daemon.get_orphans ();
				foreach (unowned PackageStruct pkg_struct in pkg_structs) {
					pkgs.append (new Package.from_struct (pkg_struct));
				}
			} catch (Error e) {
				stderr.printf ("get_installed_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public async List<Package> get_installed_pkgs_async () {
			var pkgs = new List<Package> ();
			try {
				var pkg_structs = yield user_daemon.get_installed_pkgs_async ();
				foreach (unowned PackageStruct pkg_struct in pkg_structs) {
					pkgs.append (new Package.from_struct (pkg_struct));
				}
			} catch (Error e) {
				stderr.printf ("get_installed_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public async List<Package> get_installed_apps_async () {
			var pkgs = new List<Package> ();
			try {
				var pkg_structs = yield user_daemon.get_installed_apps_async ();
				foreach (unowned PackageStruct pkg_struct in pkg_structs) {
					pkgs.append (new Package.from_struct (pkg_struct));
				}
			} catch (Error e) {
				stderr.printf ("get_installed_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public async List<Package> get_explicitly_installed_pkgs_async () {
			var pkgs = new List<Package> ();
			try {
				var pkg_structs = yield user_daemon.get_explicitly_installed_pkgs_async ();
				foreach (unowned PackageStruct pkg_struct in pkg_structs) {
					pkgs.append (new Package.from_struct (pkg_struct));
				}
			} catch (Error e) {
				stderr.printf ("get_installed_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public async List<Package> get_foreign_pkgs_async () {
			var pkgs = new List<Package> ();
			try {
				var pkg_structs = yield user_daemon.get_foreign_pkgs_async ();
				foreach (unowned PackageStruct pkg_struct in pkg_structs) {
					pkgs.append (new Package.from_struct (pkg_struct));
				}
			} catch (Error e) {
				stderr.printf ("get_installed_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public async List<Package> get_orphans_async () {
			var pkgs = new List<Package> ();
			try {
				var pkg_structs = yield user_daemon.get_orphans_async ();
				foreach (unowned PackageStruct pkg_struct in pkg_structs) {
					pkgs.append (new Package.from_struct (pkg_struct));
				}
			} catch (Error e) {
				stderr.printf ("get_installed_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public Package get_sync_pkg (string pkgname) {
			try {
				var pkg_struct  = user_daemon.get_sync_pkg (pkgname);
				return new Package.from_struct (pkg_struct);
			} catch (Error e) {
				stderr.printf ("find_installed_satisfier: %s\n", e.message);
				return new Package ();
			}
		}

		public Package find_sync_satisfier (string depstring) {
			try {
				var pkg_struct  = user_daemon.find_sync_satisfier (depstring);
				return new Package.from_struct (pkg_struct);
			} catch (Error e) {
				stderr.printf ("find_installed_satisfier: %s\n", e.message);
				return new Package ();
			}
		}

		public List<Package> search_pkgs (string search_string) {
			var pkgs = new List<Package> ();
			try {
				var pkg_structs = user_daemon.search_pkgs (search_string);
				foreach (unowned PackageStruct pkg_struct in pkg_structs) {
					pkgs.append (new Package.from_struct (pkg_struct));
				}
			} catch (Error e) {
				stderr.printf ("get_installed_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public async List<Package> search_pkgs_async (string search_string) {
			var pkgs = new List<Package> ();
			try {
				var pkg_structs = yield user_daemon.search_pkgs_async (search_string);
				foreach (unowned PackageStruct pkg_struct in pkg_structs) {
					pkgs.append (new Package.from_struct (pkg_struct));
				}
			} catch (Error e) {
				stderr.printf ("get_installed_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public async List<AURPackage> search_in_aur_async (string search_string) {
			var pkgs = new List<AURPackage> ();
			try {
				var pkg_structs = yield user_daemon.search_in_aur_async (search_string);
				foreach (unowned AURPackageStruct pkg_struct in pkg_structs) {
					pkgs.append (new AURPackage.from_struct (pkg_struct));
				}
			} catch (Error e) {
				stderr.printf ("get_installed_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public HashTable<string, Variant> search_files (string[] files) {
			var result = new HashTable<string, Variant> (str_hash, str_equal);
			try {
				result = user_daemon.search_files (files);
			} catch (Error e) {
				stderr.printf ("search_files: %s\n", e.message);
			}
			return result;
		}

		public List<Package> get_category_pkgs (string category) {
			var pkgs = new List<Package> ();
			try {
				var pkg_structs = user_daemon.get_category_pkgs (category);
				foreach (unowned PackageStruct pkg_struct in pkg_structs) {
					pkgs.append (new Package.from_struct (pkg_struct));
				}
			} catch (Error e) {
				stderr.printf ("get_installed_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public async List<Package> get_category_pkgs_async (string category) {
			var pkgs = new List<Package> ();
			try {
				var pkg_structs = yield user_daemon.get_category_pkgs_async (category);
				foreach (unowned PackageStruct pkg_struct in pkg_structs) {
					pkgs.append (new Package.from_struct (pkg_struct));
				}
			} catch (Error e) {
				stderr.printf ("get_installed_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public List<string> get_repos_names () {
			var repos_names = new List<string> ();
			try {
				var repos_names_array = user_daemon.get_repos_names ();
				foreach (string repos_name in repos_names_array) {
					repos_names.append ((owned) repos_name);
				}
			} catch (Error e) {
				stderr.printf ("get_repos_names: %s\n", e.message);
			}
			return repos_names;
		}

		public List<Package> get_repo_pkgs (string repo) {
			var pkgs = new List<Package> ();
			try {
				var pkg_structs = user_daemon.get_repo_pkgs (repo);
				foreach (unowned PackageStruct pkg_struct in pkg_structs) {
					pkgs.append (new Package.from_struct (pkg_struct));
				}
			} catch (Error e) {
				stderr.printf ("get_installed_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public async List<Package> get_repo_pkgs_async (string repo) {
			var pkgs = new List<Package> ();
			try {
				var pkg_structs = yield user_daemon.get_repo_pkgs_async (repo);
				foreach (unowned PackageStruct pkg_struct in pkg_structs) {
					pkgs.append (new Package.from_struct (pkg_struct));
				}
			} catch (Error e) {
				stderr.printf ("get_installed_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public List<string> get_groups_names () {
			var groups_names = new List<string> ();
			try {
				var groups_names_array = user_daemon.get_groups_names ();
				foreach (string groups_name in groups_names_array) {
					groups_names.append ((owned) groups_name);
				}
			} catch (Error e) {
				stderr.printf ("get_groups_names: %s\n", e.message);
			}
			return groups_names;
		}

		public List<Package> get_group_pkgs (string group_name) {
			var pkgs = new List<Package> ();
			try {
				var pkg_structs = user_daemon.get_group_pkgs (group_name);
				foreach (unowned PackageStruct pkg_struct in pkg_structs) {
					pkgs.append (new Package.from_struct (pkg_struct));
				}
			} catch (Error e) {
				stderr.printf ("get_installed_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public async List<Package> get_group_pkgs_async (string group_name) {
			var pkgs = new List<Package> ();
			try {
				var pkg_structs = yield user_daemon.get_group_pkgs_async (group_name);
				foreach (unowned PackageStruct pkg_struct in pkg_structs) {
					pkgs.append (new Package.from_struct (pkg_struct));
				}
			} catch (Error e) {
				stderr.printf ("get_installed_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public List<string> get_pkg_uninstalled_optdeps (string pkgname) {
			var optdeps = new List<string> ();
			try {
				var optdeps_array = user_daemon.get_pkg_uninstalled_optdeps (pkgname);
				foreach (string optdep in optdeps_array) {
					optdeps.append ((owned) optdep);
				}
			} catch (Error e) {
				stderr.printf ("get_pkg_uninstalled_optdeps: %s\n", e.message);
			}
			return optdeps;
		}

		public PackageDetails get_pkg_details (string pkgname, string app_name) {
			try {
				var pkg_struct = user_daemon.get_pkg_details (pkgname, app_name);
				return new PackageDetails.from_struct (pkg_struct);
			} catch (Error e) {
				stderr.printf ("get_pkg_details: %s\n", e.message);
				return new PackageDetails ();
			}
		}

		public List<string> get_pkg_files (string pkgname) {
			var files = new List<string> ();
			try {
				var files_array = user_daemon.get_pkg_files (pkgname);
				foreach (string file in files_array) {
					files.append ((owned) file);
				}
			} catch (Error e) {
				stderr.printf ("get_pkg_files: %s\n", e.message);
			}
			return files;
		}

		public async AURPackage get_aur_pkg_async (string pkgname) {
			if (config.enable_aur) {
				try {
					var pkg_struct = yield user_daemon.get_aur_pkg_async (pkgname);
					return new AURPackage.from_struct (pkg_struct);
				} catch (Error e) {
					stderr.printf ("get_aur_details_async: %s\n", e.message);
					return new AURPackage ();
				}
			} else {
				return new AURPackage ();
			}
		}

		public async AURPackageDetails get_aur_pkg_details_async (string pkgname) {
			if (config.enable_aur) {
				try {
					var pkg_struct = yield user_daemon.get_aur_pkg_details_async (pkgname);
					return new AURPackageDetails.from_struct (pkg_struct);
				} catch (Error e) {
					stderr.printf ("get_aur_details_async: %s\n", e.message);
					return new AURPackageDetails ();
				}
			} else {
				return new AURPackageDetails ();
			}
		}

		public void start_get_updates () {
			user_daemon.emit_get_updates_progress.connect (on_emit_get_updates_progress);
			user_daemon.get_updates_finished.connect (on_get_updates_finished);
			try {
				user_daemon.start_get_updates (config.check_aur_updates, refresh_files_dbs_on_get_updates);
			} catch (Error e) {
				stderr.printf ("start_get_updates: %s\n", e.message);
			}
		}

		void on_emit_get_updates_progress (uint percent) {
			get_updates_progress (percent);
		}

		void on_get_updates_finished (UpdatesStruct updates_struct) {
			user_daemon.emit_get_updates_progress.disconnect (on_emit_get_updates_progress);
			user_daemon.get_updates_finished.disconnect (on_get_updates_finished);
			get_updates_finished (new Updates (updates_struct));
		}
	}
}
