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
	public class Package: Object {
		PackageStruct pkg_struct;
		public string name { get {return pkg_struct.name;} }
		public string app_name { get {return pkg_struct.app_name;} }
		public string version { get {return pkg_struct.version;} }
		public string installed_version { get {return pkg_struct.installed_version;} }
		public string desc { get {return pkg_struct.desc;} }
		public string repo { get {return pkg_struct.repo;} }
		public uint64 size { get {return pkg_struct.size;} }
		public uint64 download_size { get {return pkg_struct.download_size;} }
		public string icon { get {return pkg_struct.icon;} }
		internal Package () {
			pkg_struct = PackageStruct () {
				name = "",
				app_name = "",
				version = "",
				installed_version = "",
				desc = "",
				repo = "",
				icon = ""
			};
		}
		internal Package.from_struct (owned PackageStruct pkg_struct) {
			this.pkg_struct = (owned) pkg_struct;
		}
	}

	public class PackageDetails: Object {
		PackageDetailsStruct pkg_struct;
		public string name { get {return pkg_struct.name;} }
		public string app_name { get {return pkg_struct.app_name;} }
		public string version { get {return pkg_struct.version;} }
		public string installed_version { get {return pkg_struct.installed_version;} }
		public string desc { get {return pkg_struct.desc;} }
		public string long_desc { get {return pkg_struct.long_desc;} }
		public string repo { get {return pkg_struct.repo;} }
		public uint64 size { get {return pkg_struct.size;} }
		public string url { get {return pkg_struct.url;} }
		public string icon { get {return pkg_struct.icon;} }
		public string screenshot { get {return pkg_struct.screenshot;} }
		public string packager { get {return pkg_struct.packager;} }
		public string builddate { get {return pkg_struct.builddate;} }
		public string installdate { get {return pkg_struct.installdate;} }
		public string reason { get {return pkg_struct.reason;} }
		public string has_signature { get {return pkg_struct.has_signature;} }
		List<string> licenses_priv;
		List<string> depends_priv;
		List<string> optdepends_priv;
		List<string> requiredby_priv;
		List<string> optionalfor_priv;
		List<string> provides_priv;
		List<string> replaces_priv;
		List<string> conflicts_priv;
		List<string> groups_priv;
		List<string> backups_priv;
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
			pkg_struct = PackageDetailsStruct () {
				name = "",
				app_name = "",
				version = "",
				desc = "",
				long_desc = "",
				repo = "",
				url = "",
				icon = "",
				screenshot = "",
				packager = "",
				builddate = "",
				installdate = "",
				reason = "",
				has_signature = ""
			};
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
		internal PackageDetails.from_struct (owned PackageDetailsStruct pkg_struct) {
			this.pkg_struct = (owned) pkg_struct;
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
			foreach (unowned string str in pkg_struct.licenses) {
				licenses_priv.append (str);
			}
			foreach (unowned string str in pkg_struct.depends) {
				depends_priv.append (str);
			}
			foreach (unowned string str in pkg_struct.optdepends) {
				optdepends_priv.append (str);
			}
			foreach (unowned string str in pkg_struct.requiredby) {
				requiredby_priv.append (str);
			}
			foreach (unowned string str in pkg_struct.optionalfor) {
				optionalfor_priv.append (str);
			}
			foreach (unowned string str in pkg_struct.provides) {
				provides_priv.append (str);
			}
			foreach (unowned string str in pkg_struct.replaces) {
				replaces_priv.append (str);
			}
			foreach (unowned string str in pkg_struct.conflicts) {
				conflicts_priv.append (str);
			}
			foreach (unowned string str in pkg_struct.groups) {
				groups_priv.append (str);
			}
			foreach (unowned string str in pkg_struct.backups) {
				backups_priv.append (str);
			}
		}
	}

	public class AURPackage: Object {
		AURPackageStruct pkg_struct;
		public string name { get {return pkg_struct.name;} }
		public string version { get {return pkg_struct.version;} }
		public string installed_version { get {return pkg_struct.installed_version;} }
		public string desc { get {return pkg_struct.desc;} }
		public double popularity { get {return pkg_struct.popularity;} }
		internal AURPackage () {
			pkg_struct = AURPackageStruct () {
				name = "",
				version = "",
				installed_version = "",
				desc = ""
			};
		}
		internal AURPackage.from_struct (owned AURPackageStruct pkg_struct) {
			this.pkg_struct = (owned) pkg_struct;
		}
	}

	public class AURPackageDetails: Object {
		AURPackageDetailsStruct pkg_struct;
		public string name { get {return pkg_struct.name;} }
		public string version { get {return pkg_struct.version;} }
		public string desc { get {return pkg_struct.desc;} }
		public double popularity { get {return pkg_struct.popularity;} }
		public string packagebase { get {return pkg_struct.packagebase;} }
		public string url { get {return pkg_struct.url;} }
		public string maintainer { get {return pkg_struct.maintainer;} }
		public string firstsubmitted { get {return pkg_struct.firstsubmitted;} }
		public string lastmodified { get {return pkg_struct.lastmodified;} }
		public string outofdate { get {return pkg_struct.outofdate;} }
		public int64 numvotes  { get {return pkg_struct.numvotes;} }
		List<string> licenses_priv;
		List<string> depends_priv;
		List<string> makedepends_priv;
		List<string> checkdepends_priv;
		List<string> optdepends_priv;
		List<string> provides_priv;
		List<string> replaces_priv;
		List<string> conflicts_priv;
		public List<string> licenses { get {return licenses_priv;} }
		public List<string> depends { get {return depends_priv;} }
		public List<string> makedepends { get {return makedepends_priv;} }
		public List<string> checkdepends { get {return checkdepends_priv;} }
		public List<string> optdepends { get {return optdepends_priv;} }
		public List<string> provides { get {return provides_priv;} }
		public List<string> replaces { get {return replaces_priv;} }
		public List<string> conflicts { get {return conflicts_priv;} }
		internal AURPackageDetails () {
			pkg_struct = AURPackageDetailsStruct () {
				name = "",
				version = "",
				desc = "",
				packagebase = "",
				url = "",
				maintainer = "",
				firstsubmitted = "",
				lastmodified = "",
				outofdate = ""
			};
			licenses_priv = new List<string> ();
			depends_priv = new List<string> ();
			makedepends_priv = new List<string> ();
			checkdepends_priv = new List<string> ();
			optdepends_priv = new List<string> ();
			provides_priv = new List<string> ();
			replaces_priv = new List<string> ();
			conflicts_priv = new List<string> ();
		}
		internal AURPackageDetails.from_struct (owned AURPackageDetailsStruct pkg_struct) {
			this.pkg_struct = (owned) pkg_struct;
			licenses_priv = new List<string> ();
			depends_priv = new List<string> ();
			makedepends_priv = new List<string> ();
			checkdepends_priv = new List<string> ();
			optdepends_priv = new List<string> ();
			provides_priv = new List<string> ();
			replaces_priv = new List<string> ();
			conflicts_priv = new List<string> ();
			foreach (unowned string str in pkg_struct.licenses) {
				licenses_priv.append (str);
			}
			foreach (unowned string str in pkg_struct.depends) {
				depends_priv.append (str);
			}
			foreach (unowned string str in pkg_struct.makedepends) {
				makedepends_priv.append (str);
			}
			foreach (unowned string str in pkg_struct.checkdepends) {
				checkdepends_priv.append (str);
			}
			foreach (unowned string str in pkg_struct.optdepends) {
				optdepends_priv.append (str);
			}
			foreach (unowned string str in pkg_struct.provides) {
				provides_priv.append (str);
			}
			foreach (unowned string str in pkg_struct.replaces) {
				replaces_priv.append (str);
			}
			foreach (unowned string str in pkg_struct.conflicts) {
				conflicts_priv.append (str);
			}
		}
	}

	public class TransactionSummary: Object {
		List<Package> to_install_priv;
		List<Package> to_upgrade_priv;
		List<Package> to_downgrade_priv;
		List<Package> to_reinstall_priv;
		List<Package> to_remove_priv;
		List<AURPackage> to_build_priv;
		List<Package> aur_conflicts_to_remove_priv;
		List<string> aur_pkgbases_to_build_priv;
		public List<Package> to_install { get {return to_install_priv;} }
		public List<Package> to_upgrade { get {return to_upgrade_priv;} }
		public List<Package> to_downgrade { get {return to_downgrade_priv;} }
		public List<Package> to_reinstall { get {return to_reinstall_priv;} }
		public List<Package> to_remove { get {return to_remove_priv;} }
		public List<AURPackage> to_build { get {return to_build_priv;} }
		public List<Package> aur_conflicts_to_remove { get {return aur_conflicts_to_remove_priv;} }
		public List<string> aur_pkgbases_to_build { get {return aur_pkgbases_to_build_priv;} }
		internal TransactionSummary (TransactionSummaryStruct summary_struct) {
			to_install_priv = new List<Package> ();
			to_upgrade_priv = new List<Package> ();
			to_downgrade_priv = new List<Package> ();
			to_reinstall_priv = new List<Package> ();
			to_remove_priv = new List<Package> ();
			to_build_priv = new List<AURPackage> ();
			aur_conflicts_to_remove_priv = new List<Package> ();
			aur_pkgbases_to_build_priv = new List<string> ();
			foreach (unowned PackageStruct pkg_struct in summary_struct.to_install) {
				to_install_priv.append (new Package.from_struct (pkg_struct));
			}
			foreach (unowned PackageStruct pkg_struct in summary_struct.to_upgrade) {
				to_upgrade_priv.append (new Package.from_struct (pkg_struct));
			}
			foreach (unowned PackageStruct pkg_struct in summary_struct.to_downgrade) {
				to_downgrade_priv.append (new Package.from_struct (pkg_struct));
			}
			foreach (unowned PackageStruct pkg_struct in summary_struct.to_reinstall) {
				to_reinstall_priv.append (new Package.from_struct (pkg_struct));
			}
			foreach (unowned PackageStruct pkg_struct in summary_struct.to_remove) {
				to_remove_priv.append (new Package.from_struct (pkg_struct));
			}
			foreach (unowned AURPackageStruct pkg_struct in summary_struct.to_build) {
				to_build_priv.append (new AURPackage.from_struct (pkg_struct));
			}
			foreach (unowned PackageStruct pkg_struct in summary_struct.aur_conflicts_to_remove) {
				aur_conflicts_to_remove_priv.append (new Package.from_struct (pkg_struct));
			}
			foreach (unowned string str in summary_struct.aur_pkgbases_to_build) {
				aur_pkgbases_to_build_priv.append (str);
			}
		}
	}

	public class Updates: Object {
		List<Package> repos_updates_priv;
		List<AURPackage> aur_updates_priv;
		public List<Package> repos_updates { get {return repos_updates_priv;} }
		public List<AURPackage> aur_updates { get {return aur_updates_priv;} }
		internal Updates () {
			repos_updates_priv = new List<Package> ();
			aur_updates_priv = new List<AURPackage> ();
		}
		internal Updates.from_lists (owned List<Package> repos_updates, owned List<AURPackage> aur_updates) {
			repos_updates_priv = (owned) repos_updates;
			aur_updates_priv = (owned) aur_updates;
		}
	}
}
