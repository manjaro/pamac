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
		internal SList<string> licenses_priv;
		internal SList<string> depends_priv;
		internal SList<string> optdepends_priv;
		internal SList<string> requiredby_priv;
		internal SList<string> optionalfor_priv;
		internal SList<string> provides_priv;
		internal SList<string> replaces_priv;
		internal SList<string> conflicts_priv;
		internal SList<string> groups_priv;
		internal SList<string> backups_priv;
		internal SList<string> screenshots_priv;
		public SList<string> licenses { get {return licenses_priv;} }
		public SList<string> depends { get {return depends_priv;} }
		public SList<string> optdepends { get {return optdepends_priv;} }
		public SList<string> requiredby { get {return requiredby_priv;} }
		public SList<string> optionalfor { get {return optionalfor_priv;} }
		public SList<string> provides { get {return provides_priv;} }
		public SList<string> replaces { get {return replaces_priv;} }
		public SList<string> conflicts { get {return conflicts_priv;} }
		public SList<string> groups { get {return groups_priv;} }
		public SList<string> backups { get {return backups_priv;} }
		public SList<string> screenshots { get {return screenshots_priv;} }

		internal AlpmPackage () {}

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
			pkg.packager = this.packager;
			pkg.reason = this.reason;
			pkg.has_signature = this.has_signature;
			pkg.screenshots_priv = this.screenshots_priv.copy_deep (strdup);
			pkg.licenses_priv = this.licenses_priv.copy_deep (strdup);
			pkg.depends_priv = this.depends_priv.copy_deep (strdup);
			pkg.optdepends_priv = this.optdepends_priv.copy_deep (strdup);
			pkg.requiredby_priv = this.requiredby_priv.copy_deep (strdup);
			pkg.optionalfor_priv = this.optionalfor_priv.copy_deep (strdup);
			pkg.provides_priv = this.provides_priv.copy_deep (strdup);
			pkg.replaces_priv = this.replaces_priv.copy_deep (strdup);
			pkg.conflicts_priv = this.conflicts_priv.copy_deep (strdup);
			pkg.groups_priv = this.groups_priv.copy_deep (strdup);
			pkg.backups_priv = this.backups_priv.copy_deep (strdup);
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
		internal SList<string> makedepends_priv;
		internal SList<string> checkdepends_priv;
		public SList<string> makedepends { get {return makedepends_priv;} }
		public SList<string> checkdepends { get {return checkdepends_priv;} }

		internal AURPackage () {
			repo = dgettext (null, "AUR");
		}
	}

	public class TransactionSummary: Object {
		internal SList<Package> to_install_priv;
		internal SList<Package> to_upgrade_priv;
		internal SList<Package> to_downgrade_priv;
		internal SList<Package> to_reinstall_priv;
		internal SList<Package> to_remove_priv;
		internal SList<Package> to_build_priv;
		internal SList<string> aur_pkgbases_to_build_priv;
		public SList<Package> to_install { get {return to_install_priv;} }
		public SList<Package> to_upgrade { get {return to_upgrade_priv;} }
		public SList<Package> to_downgrade { get {return to_downgrade_priv;} }
		public SList<Package> to_reinstall { get {return to_reinstall_priv;} }
		public SList<Package> to_remove { get {return to_remove_priv;} }
		public SList<Package> to_build { get {return to_build_priv;} }
		public SList<string> aur_pkgbases_to_build { get {return aur_pkgbases_to_build_priv;} }

		internal TransactionSummary () {}

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
		SList<AlpmPackage> repos_updates_priv;
		SList<AlpmPackage> ignored_repos_updates_priv;
		SList<AURPackage> aur_updates_priv;
		SList<AURPackage> ignored_aur_updates_priv;
		SList<AURPackage> outofdate_priv;
		#if ENABLE_FLATPAK
		SList<FlatpakPackage> flatpak_updates_priv;
		#endif
		public SList<AlpmPackage> repos_updates { get {return repos_updates_priv;} }
		public SList<AlpmPackage> ignored_repos_updates { get {return ignored_repos_updates_priv;} }
		public SList<AURPackage> aur_updates { get {return aur_updates_priv;} }
		public SList<AURPackage> ignored_aur_updates { get {return ignored_aur_updates_priv;} }
		public SList<AURPackage> outofdate { get {return outofdate_priv;} }
		#if ENABLE_FLATPAK
		public SList<FlatpakPackage> flatpak_updates { get {return flatpak_updates_priv;} }
		#endif

		internal Updates () {}

		internal Updates.from_lists (owned SList<AlpmPackage> repos_updates,
									owned SList<AlpmPackage> ignored_repos_updates,
									owned SList<AURPackage> aur_updates,
									owned SList<AURPackage> ignored_aur_updates,
									owned SList<AURPackage> outofdate) {
			repos_updates_priv = (owned) repos_updates;
			ignored_repos_updates_priv = (owned) ignored_repos_updates;
			aur_updates_priv = (owned) aur_updates;
			ignored_aur_updates_priv = (owned) ignored_aur_updates;
			outofdate_priv = (owned) outofdate;
		}
		
		#if ENABLE_FLATPAK
		internal void set_flatpak_updates (owned SList<FlatpakPackage> flatpak_updates) {
			flatpak_updates_priv = (owned) flatpak_updates;
		}
		#endif
	}
}

int compare_name_pkg (Pamac.Package pkg_a, Pamac.Package pkg_b) {
	return strcmp (pkg_a.name, pkg_b.name);
}
