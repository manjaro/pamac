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

		public signal void get_updates_progress (uint percent);

		public Config config { get; construct set; }
		public bool refresh_files_dbs_on_get_updates { get; set; }

		public Database (Config config) {
			Object (config: config);
		}

		construct {
			// alpm_utils global variable declared in alpm_utils.vala
			alpm_utils = new AlpmUtils ();
			refresh_files_dbs_on_get_updates = false;
		}

		public void enable_appstream () {
			alpm_utils.enable_appstream ();
		}

		public void refresh () {
			alpm_utils.refresh_handle ();
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

		public bool get_checkspace () {
			return alpm_utils.get_checkspace ();
		}

		public string get_lockfile () {
			return alpm_utils.alpm_handle.lockfile;
		}

		public List<string> get_ignorepkgs () {
			return alpm_utils.get_ignorepkgs ();
		}

		public Package get_installed_pkg (string pkgname) {
			return alpm_utils.get_installed_pkg (pkgname);
		}

		public Package find_installed_satisfier (string depstring) {
			return alpm_utils.find_installed_satisfier (depstring);
		}

		public bool should_hold (string pkgname) {
			return alpm_utils.should_hold (pkgname);
		}

		public uint get_pkg_reason (string pkgname) {
			return alpm_utils.get_pkg_reason (pkgname);
		}

		public List<Package> get_installed_pkgs () {
			return alpm_utils.get_installed_pkgs ();
		}

		public List<Package> get_installed_apps () {
			return alpm_utils.get_installed_apps ();
		}

		public List<Package> get_explicitly_installed_pkgs () {
			return alpm_utils.get_explicitly_installed_pkgs ();
		}

		public List<Package> get_foreign_pkgs () {
			return alpm_utils.get_foreign_pkgs ();
		}

		public List<Package> get_orphans () {
			return alpm_utils.get_orphans ();
		}

		public async List<Package> get_installed_pkgs_async () {
			return alpm_utils.get_installed_pkgs ();
		}

		public async List<Package> get_installed_apps_async () {
			return alpm_utils.get_installed_apps ();
		}

		public async List<Package> get_explicitly_installed_pkgs_async () {
			return alpm_utils.get_explicitly_installed_pkgs ();
		}

		public async List<Package> get_foreign_pkgs_async () {
			return alpm_utils.get_foreign_pkgs ();
		}

		public async List<Package> get_orphans_async () {
			return alpm_utils.get_orphans ();
		}

		public Package get_sync_pkg (string pkgname) {
			return alpm_utils.get_sync_pkg (pkgname);
		}

		public Package find_sync_satisfier (string depstring) {
			return alpm_utils.find_sync_satisfier (depstring);
		}

		public List<Package> search_pkgs (string search_string) {
			return alpm_utils.search_pkgs (search_string);
		}

		public async List<Package> search_pkgs_async (string search_string) {
			return alpm_utils.search_pkgs (search_string);
		}

		public List<AURPackage> search_in_aur (string search_string) {
			var pkgs = new List<AURPackage> ();
			if (config.enable_aur) {
				pkgs = alpm_utils.search_in_aur (search_string);
			}
			return pkgs;
		}

		public async List<AURPackage> search_in_aur_async (string search_string) {
			return search_in_aur (search_string);
		}

		public HashTable<string, Variant> search_files (string[] files) {
			return alpm_utils.search_files (files);
		}

		public List<Package> get_category_pkgs (string category) {
			return alpm_utils.get_category_pkgs (category);
		}

		public async List<Package> get_category_pkgs_async (string category) {
			return alpm_utils.get_category_pkgs (category);
		}

		public List<string> get_repos_names () {
			return alpm_utils.get_repos_names ();
		}

		public List<Package> get_repo_pkgs (string repo) {
			return alpm_utils.get_repo_pkgs (repo);
		}

		public async List<Package> get_repo_pkgs_async (string repo) {
			return alpm_utils.get_repo_pkgs (repo);
		}

		public List<string> get_groups_names () {
			return alpm_utils.get_groups_names ();
		}

		public List<Package> get_group_pkgs (string group_name) {
			return alpm_utils.get_group_pkgs (group_name);
		}

		public async List<Package> get_group_pkgs_async (string group_name) {
			return alpm_utils.get_group_pkgs (group_name);
		}

		public List<string> get_pkg_uninstalled_optdeps (string pkgname) {
			return alpm_utils.get_pkg_uninstalled_optdeps (pkgname);
		}

		public PackageDetails get_pkg_details (string pkgname, string app_name) {
			return alpm_utils.get_pkg_details (pkgname, app_name);
		}

		public List<string> get_pkg_files (string pkgname) {
			return alpm_utils.get_pkg_files (pkgname);
		}

		public async List<string> get_pkg_files_async (string pkgname) {
			return alpm_utils.get_pkg_files (pkgname);
		}

		public AURPackage get_aur_pkg (string pkgname) {
			if (config.enable_aur) {
				return alpm_utils.get_aur_pkg (pkgname);
			} else {
				return new AURPackage ();
			}
		}

		public async AURPackage get_aur_pkg_async (string pkgname) {
			return get_aur_pkg (pkgname);
		}

		public AURPackageDetails get_aur_pkg_details (string pkgname) {
			if (config.enable_aur) {
				return alpm_utils.get_aur_pkg_details (pkgname);
			} else {
				return new AURPackageDetails ();
			}
		}

		public async AURPackageDetails get_aur_pkg_details_async (string pkgname) {
			return get_aur_pkg_details (pkgname);
		}

		public Updates get_updates () {
			alpm_utils.emit_get_updates_progress.connect (on_emit_get_updates_progress);
			alpm_utils.check_aur_updates = config.check_aur_updates;
			// be sure we have the good updates
			alpm_utils.refresh_handle ();
			return alpm_utils.get_updates (refresh_files_dbs_on_get_updates);
		}

		public async Updates get_updates_async () {
			return get_updates ();
		}

		void on_emit_get_updates_progress (uint percent) {
			get_updates_progress (percent);
		}
	}
}
