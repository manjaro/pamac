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
	struct PackageStruct {
		public string name;
		public string app_name;
		public string version;
		public string installed_version;
		public string desc;
		public string repo;
		public uint64 size;
		public uint64 download_size;
		public string icon;
	}

	struct PackageDetailsStruct {
		public string name;
		public string app_name;
		public string version;
		public string installed_version;
		public string desc;
		public string long_desc;
		public string repo;
		public uint64 size;
		public string url;
		public string icon;
		public string screenshot;
		public string packager;
		public string builddate;
		public string installdate;
		public string reason;
		public string has_signature;
		public string[] licenses;
		public string[] depends;
		public string[] optdepends;
		public string[] requiredby;
		public string[] optionalfor;
		public string[] provides;
		public string[] replaces;
		public string[] conflicts;
		public string[] groups;
		public string[] backups;
	}

	struct AURPackageStruct {
		public string name;
		public string version;
		public string installed_version;
		public string desc;
		public double popularity;
	}

	struct AURPackageDetailsStruct {
		public string name;
		public string version;
		public string desc;
		public double popularity;
		public string packagebase;
		public string url;
		public string maintainer;
		public string firstsubmitted;
		public string lastmodified;
		public string outofdate;
		public int64 numvotes;
		public string[] licenses;
		public string[] depends;
		public string[] makedepends;
		public string[] checkdepends;
		public string[] optdepends;
		public string[] provides;
		public string[] replaces;
		public string[] conflicts;
	}

	struct TransactionSummaryStruct {
		public PackageStruct[] to_install;
		public PackageStruct[] to_upgrade;
		public PackageStruct[] to_downgrade;
		public PackageStruct[] to_reinstall;
		public PackageStruct[] to_remove;
		public AURPackageStruct[] to_build;
		public PackageStruct[] aur_conflicts_to_remove;
		public string[] aur_pkgbases_to_build;
	}

	struct UpdatesStruct {
		public PackageStruct[] syncfirst_repos_updates;
		public AURPackageStruct[] aur_updates;
	}
}
