/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2017 Guillaume Benoit <guillaume@manjaro.org>
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
	public struct AlpmPackage {
		public string name;
		public string version;
		public string desc;
		public string repo;
		public uint64 size;
		public uint origin;
	}

	public struct AlpmPackageDetails {
		public string name;
		public string version;
		public string desc;
		public string repo;
		public uint origin;
		public string url;
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

	public struct AURPackage {
		public string name;
		public string version;
		public string desc;
		public double popularity;
	}

	public struct AURPackageDetails {
		public string name;
		public string version;
		public string desc;
		public double popularity;
		public string packagebase;
		public string url;
		public string maintainer;
		public int64 firstsubmitted;
		public int64 lastmodified;
		public int64 outofdate;
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
}
