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
	public class Package: Object {
		public string name { get; internal set; default = "";}
		public string app_name { get; internal set; default = "";}
		public string version { get; internal set; default = "";}
		public string installed_version { get; internal set; default = "";}
		public string desc { get; internal set; default = "";}
		public string repo { get; internal set; default = "";}
		public uint64 installed_size { get; internal set; }
		public uint64 download_size { get; internal set; }
		public string icon { get; internal set; default = "";}
		public uint64 builddate { get; internal set; }
		public uint64 installdate { get; internal set; }
		internal Package () {}
		internal Package.from_struct (PackageStruct pkg_struct) {
			name = pkg_struct.name;
			app_name = pkg_struct.app_name;
			version = pkg_struct.version;
			installed_version = pkg_struct.installed_version;
			desc = pkg_struct.desc;
			repo = pkg_struct.repo;
			icon = pkg_struct.icon;
			installed_size = pkg_struct.installed_size;
			download_size = pkg_struct.download_size;
			builddate = pkg_struct.builddate;
			installdate = pkg_struct.installdate;
		}
		internal Package dup () {
			var pkg = new Package ();
			pkg.name = this.name;
			pkg.app_name = this.app_name;
			pkg.version = this.version;
			pkg.installed_version = this.installed_version;
			pkg.desc = this.desc;
			pkg.repo = this.repo;
			pkg.icon = this.icon;
			pkg.installed_size = this.installed_size;
			pkg.download_size = this.download_size;
			pkg.builddate = this.builddate;
			pkg.installdate = this.installdate;
			return pkg;
		}
	}

	public class PackageDetails: Object {
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
		public string name { get; internal set; default = "";}
		public string app_name { get; internal set; default = "";}
		public string version { get; internal set; default = "";}
		public string installed_version { get; internal set; default = "";}
		public string desc { get; internal set; default = "";}
		public string long_desc { get; internal set; default = "";}
		public string repo { get; internal set; default = "";}
		public string url { get; internal set; default = "";}
		public string icon { get; internal set; default = "";}
		public string screenshot { get; internal set; default = "";}
		public string packager { get; internal set; default = "";}
		public uint64 installed_size { get; internal set; }
		public uint64 builddate { get; internal set; }
		public uint64 installdate { get; internal set; }
		public string reason { get; internal set; default = "";}
		public string has_signature { get; internal set; default = "";}
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
		internal PackageDetails () {
			licenses_priv = new List<string> ();
			depends_priv = new List<string> ();
			optdepends_priv = new List<string> ();
			requiredby_priv = new List<string> ();
			optionalfor_priv = new List<string> ();
			provides_priv = new List<string> ();
			replaces_priv = new List<string> ();
			conflicts_priv = new List<string> ();
			groups_priv = new List<string> ();
			backups_priv = new List<string> ();
		}
	}

	public class AURPackage: Object {
		public string name { get; internal set; default = "";}
		public string version { get; internal set; default = "";}
		public string installed_version { get; internal set; default = "";}
		public string desc { get; internal set; default = "";}
		public double popularity { get; internal set; }
		public string packagebase { get; internal set; default = "";}
		public uint64 lastmodified { get; internal set; }
		public uint64 outofdate { get; internal set; }
		internal AURPackage () {}
		internal AURPackage.from_struct (AURPackageStruct pkg_struct) {
			name = pkg_struct.name;
			version = pkg_struct.version;
			desc = pkg_struct.desc;
			installed_version = pkg_struct.installed_version;
			packagebase = pkg_struct.packagebase;
			popularity = pkg_struct.popularity;
			lastmodified = pkg_struct.lastmodified;
			outofdate = pkg_struct.outofdate;
		}
	}

	public class AURPackageDetails: Object {
		public string name { get; internal set; default = "";}
		public string version { get; internal set; default = "";}
		public string desc { get; internal set; default = "";}
		public double popularity { get; internal set; }
		public string packagebase { get; internal set; default = "";}
		public string url { get; internal set; default = "";}
		public string maintainer { get; internal set; default = "";}
		public uint64 firstsubmitted { get; internal set; }
		public uint64 lastmodified { get; internal set; }
		public uint64 outofdate { get; internal set; }
		public uint64 numvotes  { get; internal set; }
		internal List<string> licenses_priv;
		internal List<string> depends_priv;
		internal List<string> makedepends_priv;
		internal List<string> checkdepends_priv;
		internal List<string> optdepends_priv;
		internal List<string> provides_priv;
		internal List<string> replaces_priv;
		internal List<string> conflicts_priv;
		public List<string> licenses { get {return licenses_priv;} }
		public List<string> depends { get {return depends_priv;} }
		public List<string> makedepends { get {return makedepends_priv;} }
		public List<string> checkdepends { get {return checkdepends_priv;} }
		public List<string> optdepends { get {return optdepends_priv;} }
		public List<string> provides { get {return provides_priv;} }
		public List<string> replaces { get {return replaces_priv;} }
		public List<string> conflicts { get {return conflicts_priv;} }
		internal AURPackageDetails () {
			licenses_priv = new List<string> ();
			depends_priv = new List<string> ();
			makedepends_priv = new List<string> ();
			checkdepends_priv = new List<string> ();
			optdepends_priv = new List<string> ();
			provides_priv = new List<string> ();
			replaces_priv = new List<string> ();
			conflicts_priv = new List<string> ();
		}
	}

	public class TransactionSummary: Object {
		List<Package> to_install_priv;
		List<Package> to_upgrade_priv;
		List<Package> to_downgrade_priv;
		List<Package> to_reinstall_priv;
		List<Package> to_remove_priv;
		List<AURPackage> to_build_priv;
		List<string> aur_pkgbases_to_build_priv;
		public List<Package> to_install { get {return to_install_priv;} }
		public List<Package> to_upgrade { get {return to_upgrade_priv;} }
		public List<Package> to_downgrade { get {return to_downgrade_priv;} }
		public List<Package> to_reinstall { get {return to_reinstall_priv;} }
		public List<Package> to_remove { get {return to_remove_priv;} }
		public List<AURPackage> to_build { get {return to_build_priv;} }
		public List<string> aur_pkgbases_to_build { get {return aur_pkgbases_to_build_priv;} }
		internal TransactionSummary (TransactionSummaryStruct summary_struct) {
			to_install_priv = new List<Package> ();
			to_upgrade_priv = new List<Package> ();
			to_downgrade_priv = new List<Package> ();
			to_reinstall_priv = new List<Package> ();
			to_remove_priv = new List<Package> ();
			to_build_priv = new List<AURPackage> ();
			aur_pkgbases_to_build_priv = new List<string> ();
			foreach (unowned PackageStruct pkg_struct in summary_struct.to_install) {
				to_install_priv.append (new Package.from_struct (pkg_struct));
			}
			to_install_priv.sort (compare_name_pkg);
			foreach (unowned PackageStruct pkg_struct in summary_struct.to_upgrade) {
				to_upgrade_priv.append (new Package.from_struct (pkg_struct));
			}
			to_upgrade_priv.sort (compare_name_pkg);
			foreach (unowned PackageStruct pkg_struct in summary_struct.to_downgrade) {
				to_downgrade_priv.append (new Package.from_struct (pkg_struct));
			}
			to_downgrade_priv.sort (compare_name_pkg);
			foreach (unowned PackageStruct pkg_struct in summary_struct.to_reinstall) {
				to_reinstall_priv.append (new Package.from_struct (pkg_struct));
			}
			to_reinstall_priv.sort (compare_name_pkg);
			foreach (unowned PackageStruct pkg_struct in summary_struct.to_remove) {
				to_remove_priv.append (new Package.from_struct (pkg_struct));
			}
			foreach (unowned AURPackageStruct pkg_struct in summary_struct.to_build) {
				to_build_priv.append (new AURPackage.from_struct (pkg_struct));
			}
			to_build_priv.sort (compare_name_aur);
			foreach (unowned PackageStruct pkg_struct in summary_struct.aur_conflicts_to_remove) {
				to_remove_priv.append (new Package.from_struct (pkg_struct));
			}
			to_remove_priv.sort (compare_name_pkg);
			foreach (unowned string str in summary_struct.aur_pkgbases_to_build) {
				aur_pkgbases_to_build_priv.append (str);
			}
		}
	}

	public class Updates: Object {
		List<Package> repos_updates_priv;
		List<AURPackage> aur_updates_priv;
		List<AURPackage> outofdate_priv;
		public List<Package> repos_updates { get {return repos_updates_priv;} }
		public List<AURPackage> aur_updates { get {return aur_updates_priv;} }
		public List<AURPackage> outofdate { get {return outofdate_priv;} }
		internal Updates () {
			repos_updates_priv = new List<Package> ();
			aur_updates_priv = new List<AURPackage> ();
			outofdate_priv =  new List<AURPackage> ();
		}
		internal Updates.from_lists (owned List<Package> repos_updates, owned List<AURPackage> aur_updates, owned List<AURPackage> outofdate) {
			repos_updates_priv = (owned) repos_updates;
			aur_updates_priv = (owned) aur_updates;
			outofdate_priv = (owned) outofdate;
		}
	}
}

int compare_name_pkg (Pamac.Package pkg_a, Pamac.Package pkg_b) {
	return strcmp (pkg_a.name, pkg_b.name);
}

int compare_name_aur (Pamac.AURPackage pkg_a, Pamac.AURPackage pkg_b) {
	return strcmp (pkg_a.name, pkg_b.name);
}
