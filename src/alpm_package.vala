/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2020 Guillaume Benoit <guillaume@manjaro.org>
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
	public class AlpmPackage: Package {
		public uint64 builddate { get; internal set; }
		public string packager { get; internal set; default = "";}
		public string reason { get; internal set; default = "";}
		public string has_signature { get; internal set; default = "";}
		internal GenericArray<string> licenses_priv;
		internal GenericArray<string> depends_priv;
		internal GenericArray<string> optdepends_priv;
		internal GenericArray<string> requiredby_priv;
		internal GenericArray<string> optionalfor_priv;
		internal GenericArray<string> provides_priv;
		internal GenericArray<string> replaces_priv;
		internal GenericArray<string> conflicts_priv;
		internal GenericArray<string> groups_priv;
		internal GenericArray<string> backups_priv;
		internal GenericArray<string> screenshots_priv;
		public GenericArray<string> licenses { get {return licenses_priv;} }
		public GenericArray<string> depends { get {return depends_priv;} }
		public GenericArray<string> optdepends { get {return optdepends_priv;} }
		public GenericArray<string> requiredby { get {return requiredby_priv;} }
		public GenericArray<string> optionalfor { get {return optionalfor_priv;} }
		public GenericArray<string> provides { get {return provides_priv;} }
		public GenericArray<string> replaces { get {return replaces_priv;} }
		public GenericArray<string> conflicts { get {return conflicts_priv;} }
		public GenericArray<string> groups { get {return groups_priv;} }
		public GenericArray<string> backups { get {return backups_priv;} }
		public GenericArray<string> screenshots { get {return screenshots_priv;} }

		internal AlpmPackage () {
			licenses_priv = new GenericArray<string> ();
			depends_priv = new GenericArray<string> ();
			optdepends_priv = new GenericArray<string> ();
			requiredby_priv = new GenericArray<string> ();
			optionalfor_priv = new GenericArray<string> ();
			provides_priv = new GenericArray<string> ();
			replaces_priv = new GenericArray<string> ();
			conflicts_priv = new GenericArray<string> ();
			groups_priv = new GenericArray<string> ();
			backups_priv = new GenericArray<string> ();
			screenshots_priv = new GenericArray<string> ();
		}

		internal AlpmPackage dup () {
			var pkg = new AlpmPackage ();
			pkg.name = this.name;
			pkg.app_name = this.app_name;
			pkg.version = this.version;
			pkg.installed_version = this.installed_version;
			pkg.desc = this.desc;
			pkg.long_desc = this.long_desc;
			pkg.repo = this.repo;
			pkg.launchable = this.launchable;
			pkg.icon = this.icon;
			pkg.installed_size = this.installed_size;
			pkg.download_size = this.download_size;
			pkg.url = this.url;
			pkg.builddate = this.builddate;
			pkg.installdate = this.installdate;
			screenshots_priv = pkg.screenshots_priv.copy (strdup);
			licenses_priv = pkg.licenses_priv.copy (strdup);
			depends_priv = pkg.depends_priv.copy (strdup);
			optdepends_priv = pkg.optdepends_priv.copy (strdup);
			requiredby_priv = pkg.requiredby_priv.copy (strdup);
			optionalfor_priv = pkg.optionalfor_priv.copy (strdup);
			provides_priv = pkg.provides_priv.copy (strdup);
			replaces_priv = pkg.replaces_priv.copy (strdup);
			conflicts_priv = pkg.conflicts_priv.copy (strdup);
			groups_priv = pkg.groups_priv.copy (strdup);
			backups_priv = pkg.backups_priv.copy (strdup);
			return pkg;
		}
	}

	public class AURPackage: AlpmPackage {
		public double popularity { get; internal set; }
		public string packagebase { get; internal set; default = "";}
		public uint64 lastmodified { get; internal set; }
		public uint64 outofdate { get; internal set; }
		public string maintainer { get; internal set; default = "";}
		public uint64 firstsubmitted { get; internal set; }
		public uint64 numvotes  { get; internal set; }
		internal GenericArray<string> makedepends_priv;
		internal GenericArray<string> checkdepends_priv;
		public GenericArray<string> makedepends { get {return makedepends_priv;} }
		public GenericArray<string> checkdepends { get {return checkdepends_priv;} }

		internal AURPackage () {
			repo = dgettext (null, "AUR");
			makedepends_priv = new GenericArray<string> ();
			checkdepends_priv = new GenericArray<string> ();
		}
	}

	public class TransactionSummary: Object {
		internal GenericArray<Package> to_install_priv;
		internal GenericArray<Package> to_upgrade_priv;
		internal GenericArray<Package> to_downgrade_priv;
		internal GenericArray<Package> to_reinstall_priv;
		internal GenericArray<Package> to_remove_priv;
		internal GenericArray<Package> to_build_priv;
		internal GenericArray<string> aur_pkgbases_to_build_priv;
		public GenericArray<Package> to_install { get {return to_install_priv;} }
		public GenericArray<Package> to_upgrade { get {return to_upgrade_priv;} }
		public GenericArray<Package> to_downgrade { get {return to_downgrade_priv;} }
		public GenericArray<Package> to_reinstall { get {return to_reinstall_priv;} }
		public GenericArray<Package> to_remove { get {return to_remove_priv;} }
		public GenericArray<Package> to_build { get {return to_build_priv;} }
		public GenericArray<string> aur_pkgbases_to_build { get {return aur_pkgbases_to_build_priv;} }

		internal TransactionSummary () {
			to_install_priv = new GenericArray<Package> ();
			to_upgrade_priv = new GenericArray<Package> ();
			to_downgrade_priv = new GenericArray<Package> ();
			to_reinstall_priv = new GenericArray<Package> ();
			to_remove_priv = new GenericArray<Package> ();
			to_build_priv = new GenericArray<Package> ();
			aur_pkgbases_to_build_priv = new GenericArray<string> ();
		}

		internal void sort () {
			to_install_priv.sort (compare_name_pkg);
			to_upgrade_priv.sort (compare_name_pkg);
			to_downgrade_priv.sort (compare_name_pkg);
			to_reinstall_priv.sort (compare_name_pkg);
			to_remove_priv.sort (compare_name_pkg);
			to_build_priv.sort (compare_name_pkg);
		}
	}

	public class Updates: Object {
		GenericArray<AlpmPackage> repos_updates_priv;
		GenericArray<AlpmPackage> ignored_repos_updates_priv;
		GenericArray<AURPackage> aur_updates_priv;
		GenericArray<AURPackage> ignored_aur_updates_priv;
		GenericArray<AURPackage> outofdate_priv;
		#if ENABLE_FLATPAK
		GenericArray<FlatpakPackage> flatpak_updates_priv;
		#endif
		public GenericArray<AlpmPackage> repos_updates { get {return repos_updates_priv;} }
		public GenericArray<AlpmPackage> ignored_repos_updates { get {return ignored_repos_updates_priv;} }
		public GenericArray<AURPackage> aur_updates { get {return aur_updates_priv;} }
		public GenericArray<AURPackage> ignored_aur_updates { get {return ignored_aur_updates_priv;} }
		public GenericArray<AURPackage> outofdate { get {return outofdate_priv;} }
		#if ENABLE_FLATPAK
		public GenericArray<FlatpakPackage> flatpak_updates { get {return flatpak_updates_priv;} }
		#endif

		internal Updates () {}

		internal Updates.from_lists (GenericArray<AlpmPackage> repos_updates,
									GenericArray<AlpmPackage> ignored_repos_updates,
									GenericArray<AURPackage> aur_updates,
									GenericArray<AURPackage> ignored_aur_updates,
									GenericArray<AURPackage> outofdate) {
			repos_updates_priv = repos_updates;
			ignored_repos_updates_priv = ignored_repos_updates;
			aur_updates_priv = aur_updates;
			ignored_aur_updates_priv = ignored_aur_updates;
			outofdate_priv = outofdate;
		}
		
		#if ENABLE_FLATPAK
		internal void set_flatpak_updates ( GenericArray<FlatpakPackage> flatpak_updates) {
			flatpak_updates_priv = flatpak_updates;
		}
		#endif
	}
}

int compare_name_pkg (Pamac.Package pkg_a, Pamac.Package pkg_b) {
	return strcmp (pkg_a.name, pkg_b.name);
}
