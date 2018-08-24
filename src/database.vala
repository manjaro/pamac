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
		public abstract string get_lockfile () throws Error;
		public abstract AlpmPackage get_installed_pkg (string pkgname) throws Error;
		public abstract bool get_checkspace () throws Error;
		public abstract string[] get_ignorepkgs () throws Error;
		public abstract bool should_hold (string pkgname) throws Error;
		public abstract uint get_pkg_reason (string pkgname) throws Error;
		public abstract uint get_pkg_origin (string pkgname) throws Error;
		public abstract AlpmPackage[] get_installed_pkgs () throws Error;
		public abstract AlpmPackage[] get_installed_apps () throws Error;
		public abstract AlpmPackage[] get_explicitly_installed_pkgs () throws Error;
		public abstract AlpmPackage[] get_foreign_pkgs () throws Error;
		public abstract AlpmPackage[] get_orphans () throws Error;
		public abstract async AlpmPackage[] get_installed_pkgs_async () throws Error;
		public abstract async AlpmPackage[] get_installed_apps_async () throws Error;
		public abstract async AlpmPackage[] get_explicitly_installed_pkgs_async () throws Error;
		public abstract async AlpmPackage[] get_foreign_pkgs_async() throws Error;
		public abstract async AlpmPackage[] get_orphans_async () throws Error;
		public abstract AlpmPackage find_installed_satisfier (string depstring) throws Error;
		public abstract AlpmPackage get_sync_pkg (string pkgname) throws Error;
		public abstract AlpmPackage find_sync_satisfier (string depstring) throws Error;
		public abstract AlpmPackage[] search_pkgs (string search_string) throws Error;
		public abstract async AlpmPackage[] search_pkgs_async (string search_string) throws Error;
		public abstract async AURPackage[] search_in_aur_async (string search_string) throws Error;
		public abstract HashTable<string, Variant> search_files (string[] files) throws Error;
		public abstract AlpmPackage[] get_category_pkgs (string category) throws Error;
		public abstract async AlpmPackage[] get_category_pkgs_async (string category) throws Error;
		public abstract string[] get_repos_names () throws Error;
		public abstract AlpmPackage[] get_repo_pkgs (string repo) throws Error;
		public abstract async AlpmPackage[] get_repo_pkgs_async (string repo) throws Error;
		public abstract string[] get_groups_names () throws Error;
		public abstract AlpmPackage[] get_group_pkgs (string groupname) throws Error;
		public abstract async AlpmPackage[] get_group_pkgs_async (string groupname) throws Error;
		public abstract AlpmPackageDetails get_pkg_details (string pkgname, string app_name) throws Error;
		public abstract string[] get_pkg_files (string pkgname) throws Error;
		public abstract async AURPackageDetails get_aur_details_async (string pkgname) throws Error;
		public abstract string[] get_pkg_uninstalled_optdeps (string pkgname) throws Error;
		public abstract void start_get_updates (bool check_aur_updates, bool refresh_files_dbs) throws Error;
		[DBus (no_reply = true)]
		public abstract void quit () throws Error;
		public signal void emit_get_updates_progress (uint percent);
		public signal void get_updates_finished (Updates updates);
	}

	public class Database: Object {
		UserDaemon user_daemon;

		public signal void get_updates_progress (uint percent);
		public signal void get_updates_finished (Updates updates);

		public Config config { get; construct set; }

		public Database (Config config) {
			Object (config: config);
		}

		construct {
			connecting_user_daemon ();
			if (config.enable_aur == false) {
				config.check_aur_updates = false;
			}
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

		public void stop_daemon () {
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

		public string[] get_mirrors_countries () {
			string[] countries = {};
			try {
				countries = user_daemon.get_mirrors_countries ();
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

		public string[] get_ignorepkgs () {
			string[] ignorepkgs = {};
			try {
				ignorepkgs = user_daemon.get_ignorepkgs ();
			} catch (Error e) {
				stderr.printf ("get_ignorepkgs: %s\n", e.message);
			}
			return ignorepkgs;
		}

		public AlpmPackage get_installed_pkg (string pkgname) {
			try {
				return user_daemon.get_installed_pkg (pkgname);
			} catch (Error e) {
				stderr.printf ("get_installed_pkg: %s\n", e.message);
				return AlpmPackage () {
					name = "",
					version = "",
					desc = "",
					repo = "",
					icon = ""
				};
			}
		}

		public AlpmPackage find_installed_satisfier (string depstring) {
			try {
				return user_daemon.find_installed_satisfier (depstring);
			} catch (Error e) {
				stderr.printf ("find_installed_satisfier: %s\n", e.message);
				return AlpmPackage () {
					name = "",
					version = "",
					desc = "",
					repo = ""
				};
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

		public uint get_pkg_origin (string pkgname) {
			uint origin = 0;
			try {
				origin = user_daemon.get_pkg_origin (pkgname);
			} catch (Error e) {
				stderr.printf ("get_pkg_origin: %s\n", e.message);
			}
			return origin;
		}

		public AlpmPackage[] get_installed_pkgs () {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = user_daemon.get_installed_pkgs ();
			} catch (Error e) {
				stderr.printf ("get_installed_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public AlpmPackage[] get_installed_apps () {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = user_daemon.get_installed_apps ();
			} catch (Error e) {
				stderr.printf ("get_installed_apps: %s\n", e.message);
			}
			return pkgs;
		}

		public AlpmPackage[] get_explicitly_installed_pkgs () {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = user_daemon.get_explicitly_installed_pkgs ();
			} catch (Error e) {
				stderr.printf ("get_explicitly_installed_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public AlpmPackage[] get_foreign_pkgs () {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = user_daemon.get_foreign_pkgs ();
			} catch (Error e) {
				stderr.printf ("get_foreign_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public AlpmPackage[] get_orphans () {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = user_daemon.get_orphans ();
			} catch (Error e) {
				stderr.printf ("get_orphans: %s\n", e.message);
			}
			return pkgs;
		}

		public async AlpmPackage[] get_installed_pkgs_async () {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = yield user_daemon.get_installed_pkgs_async ();
			} catch (Error e) {
				stderr.printf ("get_installed_pkgs_async: %s\n", e.message);
			}
			return pkgs;
		}

		public async AlpmPackage[] get_installed_apps_async () {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = yield user_daemon.get_installed_apps_async ();
			} catch (Error e) {
				stderr.printf ("get_installed_apps_async: %s\n", e.message);
			}
			return pkgs;
		}

		public async AlpmPackage[] get_explicitly_installed_pkgs_async () {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = yield user_daemon.get_explicitly_installed_pkgs_async ();
			} catch (Error e) {
				stderr.printf ("get_explicitly_installed_pkgs_async: %s\n", e.message);
			}
			return pkgs;
		}

		public async AlpmPackage[] get_foreign_pkgs_async () {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = yield user_daemon.get_foreign_pkgs_async ();
			} catch (Error e) {
				stderr.printf ("get_foreign_pkgs_async: %s\n", e.message);
			}
			return pkgs;
		}

		public async AlpmPackage[] get_orphans_async () {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = yield user_daemon.get_orphans_async ();
			} catch (Error e) {
				stderr.printf ("get_orphans_async: %s\n", e.message);
			}
			return pkgs;
		}

		public AlpmPackage get_sync_pkg (string pkgname) {
			try {
				return user_daemon.get_sync_pkg (pkgname);
			} catch (Error e) {
				stderr.printf ("get_sync_pkg: %s\n", e.message);
				return AlpmPackage () {
					name = "",
					version = "",
					desc = "",
					repo = ""
				};
			}
		}

		public AlpmPackage find_sync_satisfier (string depstring) {
			try {
				return user_daemon.find_sync_satisfier (depstring);
			} catch (Error e) {
				stderr.printf ("find_sync_satisfier: %s\n", e.message);
				return AlpmPackage () {
					name = "",
					version = "",
					desc = "",
					repo = ""
				};
			}
		}

		public AlpmPackage[] search_pkgs (string search_string) {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = user_daemon.search_pkgs (search_string);
			} catch (Error e) {
				stderr.printf ("search_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public async AlpmPackage[] search_pkgs_async (string search_string) {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = yield user_daemon.search_pkgs_async (search_string);
			} catch (Error e) {
				stderr.printf ("search_pkgs_async: %s\n", e.message);
			}
			return pkgs;
		}

		public async AURPackage[] search_in_aur_async (string search_string) {
			AURPackage[] pkgs = {};
			if (config.enable_aur) {
				try {
					pkgs = yield user_daemon.search_in_aur_async (search_string);
				} catch (Error e) {
					stderr.printf ("search_in_aur_async: %s\n", e.message);
				}
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

		public AlpmPackage[] get_category_pkgs (string category) {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = user_daemon.get_category_pkgs (category);
			} catch (Error e) {
				stderr.printf ("get_category_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public async AlpmPackage[] get_category_pkgs_async (string category) {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = yield user_daemon.get_category_pkgs_async (category);
			} catch (Error e) {
				stderr.printf ("get_category_pkgs_async: %s\n", e.message);
			}
			return pkgs;
		}

		public string[] get_repos_names () {
			string[] repos_names = {};
			try {
				repos_names = user_daemon.get_repos_names ();
			} catch (Error e) {
				stderr.printf ("get_repos_names: %s\n", e.message);
			}
			return repos_names;
		}

		public AlpmPackage[] get_repo_pkgs (string repo) {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = user_daemon.get_repo_pkgs (repo);
			} catch (Error e) {
				stderr.printf ("get_repo_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public async AlpmPackage[] get_repo_pkgs_async (string repo) {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = yield user_daemon.get_repo_pkgs_async (repo);
			} catch (Error e) {
				stderr.printf ("get_repo_pkgs_async: %s\n", e.message);
			}
			return pkgs;
		}

		public string[] get_groups_names () {
			string[] groups_names = {};
			try {
				groups_names = user_daemon.get_groups_names ();
			} catch (Error e) {
				stderr.printf ("get_groups_names: %s\n", e.message);
			}
			return groups_names;
		}

		public AlpmPackage[] get_group_pkgs (string group_name) {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = user_daemon.get_group_pkgs (group_name);
			} catch (Error e) {
				stderr.printf ("get_group_pkgs: %s\n", e.message);
			}
			return pkgs;
		}

		public async AlpmPackage[] get_group_pkgs_async (string group_name) {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = yield user_daemon.get_group_pkgs_async (group_name);
			} catch (Error e) {
				stderr.printf ("get_group_pkgs_async: %s\n", e.message);
			}
			return pkgs;
		}

		public string[] get_pkg_uninstalled_optdeps (string pkgname) {
			string[] optdeps = {};
			try {
				optdeps = user_daemon.get_pkg_uninstalled_optdeps (pkgname);
			} catch (Error e) {
				stderr.printf ("get_pkg_uninstalled_optdeps: %s\n", e.message);
			}
			return optdeps;
		}

		public AlpmPackageDetails get_pkg_details (string pkgname, string app_name) {
			try {
				return user_daemon.get_pkg_details (pkgname, app_name);
			} catch (Error e) {
				stderr.printf ("get_pkg_details: %s\n", e.message);
				return AlpmPackageDetails () {
					name = "",
					version = "",
					desc = "",
					repo = "",
					url = "",
					packager = "",
					builddate = "",
					installdate = "",
					reason = "",
					has_signature = ""
				};
			}
		}

		public string[] get_pkg_files (string pkgname) {
			try {
				return user_daemon.get_pkg_files (pkgname);
			} catch (Error e) {
				stderr.printf ("get_pkg_files: %s\n", e.message);
				return {};
			}
		}

		public async AURPackageDetails get_aur_details_async (string pkgname) {
			var pkg = AURPackageDetails () {
				name = "",
				version = "",
				desc = "",
				packagebase = "",
				url = "",
				maintainer = ""
			};
			if (config.enable_aur) {
				try {
					pkg = yield user_daemon.get_aur_details_async (pkgname);
				} catch (Error e) {
					stderr.printf ("get_aur_details_async: %s\n", e.message);
				}
			}
			return pkg;
		}

		public void start_get_updates () {
			user_daemon.emit_get_updates_progress.connect (on_emit_get_updates_progress);
			user_daemon.get_updates_finished.connect (on_get_updates_finished);
			try {
				user_daemon.start_get_updates (config.check_aur_updates, false);
			} catch (Error e) {
				stderr.printf ("start_get_updates: %s\n", e.message);
			}
		}

		void on_emit_get_updates_progress (uint percent) {
			get_updates_progress (percent);
		}

		void on_get_updates_finished (Updates updates) {
			user_daemon.emit_get_updates_progress.disconnect (on_emit_get_updates_progress);
			user_daemon.get_updates_finished.disconnect (on_get_updates_finished);
			get_updates_finished (updates);
		}
	}
}
