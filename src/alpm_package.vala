/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2019 Guillaume Benoit <guillaume@manjaro.org>
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
		internal List<string> licenses_priv;
		internal List<string> depends_priv;
		internal List<string> optdepends_priv;
		internal List<string> requiredby_priv;
		internal List<string> optionalfor_priv;
		internal List<string> provides_priv;
		internal List<string> replaces_priv;
		internal List<string> conflicts_priv;
		internal List<string> groups_priv;
		internal List<string> backups_priv;
		internal List<string> screenshots_priv;
		public List<string> licenses { get {return licenses_priv;} }
		public List<string> depends { get {return depends_priv;} }
		public List<string> optdepends { get {return optdepends_priv;} }
		public List<string> requiredby { get {return requiredby_priv;} }
		public List<string> optionalfor { get {return optionalfor_priv;} }
		public List<string> provides { get {return provides_priv;} }
		public List<string> replaces { get {return replaces_priv;} }
		public List<string> conflicts { get {return conflicts_priv;} }
		public List<string> groups { get {return groups_priv;} }
		public List<string> backups { get {return backups_priv;} }
		public List<string> screenshots { get {return screenshots_priv;} }

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
			screenshots_priv = pkg.screenshots_priv.copy_deep (str_dup);
			licenses_priv = pkg.licenses_priv.copy_deep (str_dup);
			depends_priv = pkg.depends_priv.copy_deep (str_dup);
			optdepends_priv = pkg.optdepends_priv.copy_deep (str_dup);
			requiredby_priv = pkg.requiredby_priv.copy_deep (str_dup);
			optionalfor_priv = pkg.optionalfor_priv.copy_deep (str_dup);
			provides_priv = pkg.provides_priv.copy_deep (str_dup);
			replaces_priv = pkg.replaces_priv.copy_deep (str_dup);
			conflicts_priv = pkg.conflicts_priv.copy_deep (str_dup);
			groups_priv = pkg.groups_priv.copy_deep (str_dup);
			backups_priv = pkg.backups_priv.copy_deep (str_dup);
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
 		internal List<string> makedepends_priv;
 		internal List<string> checkdepends_priv;
 		public List<string> makedepends { get {return makedepends_priv;} }
 		public List<string> checkdepends { get {return checkdepends_priv;} }

		internal AURPackage () {
			repo = dgettext (null, "AUR");
		}
	}

	public class TransactionSummary: Object {
		internal List<Package> to_install_priv;
		internal List<Package> to_upgrade_priv;
		List<Package> to_downgrade_priv;
		List<Package> to_reinstall_priv;
		internal List<Package> to_remove_priv;
		List<Package> to_build_priv;
		List<string> aur_pkgbases_to_build_priv;
		public List<Package> to_install { get {return to_install_priv;} }
		public List<Package> to_upgrade { get {return to_upgrade_priv;} }
		public List<Package> to_downgrade { get {return to_downgrade_priv;} }
		public List<Package> to_reinstall { get {return to_reinstall_priv;} }
		public List<Package> to_remove { get {return to_remove_priv;} }
		public List<Package> to_build { get {return to_build_priv;} }
		public List<string> aur_pkgbases_to_build { get {return aur_pkgbases_to_build_priv;} }

		internal TransactionSummary () {}

		internal TransactionSummary.from_struct (TransactionSummaryStruct summary_struct) {
			foreach (unowned PackageStruct pkg_struct in summary_struct.to_install) {
				to_install_priv.append (pkg_struct.to_pkg ());
			}
			to_install_priv.sort (compare_name_pkg);
			foreach (unowned PackageStruct pkg_struct in summary_struct.to_upgrade) {
				to_upgrade_priv.append (pkg_struct.to_pkg ());
			}
			to_upgrade_priv.sort (compare_name_pkg);
			foreach (unowned PackageStruct pkg_struct in summary_struct.to_downgrade) {
				to_downgrade_priv.append (pkg_struct.to_pkg ());
			}
			to_downgrade_priv.sort (compare_name_pkg);
			foreach (unowned PackageStruct pkg_struct in summary_struct.to_reinstall) {
				to_reinstall_priv.append (pkg_struct.to_pkg ());
			}
			to_reinstall_priv.sort (compare_name_pkg);
			foreach (unowned PackageStruct pkg_struct in summary_struct.to_remove) {
				to_remove_priv.append (pkg_struct.to_pkg ());
			}
			foreach (unowned PackageStruct pkg_struct in summary_struct.to_build) {
				to_build_priv.append (pkg_struct.to_pkg ());
			}
			to_build_priv.sort (compare_name_pkg);
			foreach (unowned PackageStruct pkg_struct in summary_struct.aur_conflicts_to_remove) {
				to_remove_priv.append (pkg_struct.to_pkg ());
			}
			to_remove_priv.sort (compare_name_pkg);
			foreach (unowned string str in summary_struct.aur_pkgbases_to_build) {
				aur_pkgbases_to_build_priv.append (str);
			}
		}
	}

	public class Updates: Object {
		List<AlpmPackage> repos_updates_priv;
		List<AURPackage> aur_updates_priv;
		List<AURPackage> outofdate_priv;
		public List<AlpmPackage> repos_updates { get {return repos_updates_priv;} }
		public List<AURPackage> aur_updates { get {return aur_updates_priv;} }
		public List<AURPackage> outofdate { get {return outofdate_priv;} }

		internal Updates () {
			repos_updates_priv = new List<AlpmPackage> ();
			aur_updates_priv = new List<AURPackage> ();
			outofdate_priv =  new List<AURPackage> ();
		}

		internal Updates.from_lists (owned List<AlpmPackage> repos_updates, owned List<AURPackage> aur_updates, owned List<AURPackage> outofdate) {
			repos_updates_priv = (owned) repos_updates;
			aur_updates_priv = (owned) aur_updates;
			outofdate_priv = (owned) outofdate;
		}
	}
}

int compare_name_pkg (Pamac.Package pkg_a, Pamac.Package pkg_b) {
	return strcmp (pkg_a.name, pkg_b.name);
}

string str_dup (string str) {
	return str.dup ();
}
