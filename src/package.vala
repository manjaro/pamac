/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2015 Guillaume Benoit <guillaume@manjaro.org>
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
	public struct Package {
		public string name;
		public string version;
		public string desc;
		public string repo;
		public uint64 size;
		public string size_string;
		public string url;
		public string licenses;
		public int reason;

		public Package (Alpm.Package? alpm_pkg, Json.Object? aur_json) {
			if (alpm_pkg != null) {
				name = alpm_pkg.name;
				version = alpm_pkg.version;
				desc = alpm_pkg.desc;
				repo = alpm_pkg.db != null ? alpm_pkg.db.name : "";
				size = alpm_pkg.isize;
				size_string = format_size (alpm_pkg.isize);
				// alpm pkg url can be null
				url = alpm_pkg.url ?? "";
				StringBuilder licenses_build = new StringBuilder ();
				foreach (var license in alpm_pkg.licenses) {
					if (licenses_build.len != 0) {
						licenses_build.append (" ");
					}
					licenses_build.append (license);
				}
				licenses = licenses_build.str;
				reason = alpm_pkg.reason;
			} else if (aur_json != null ) {
				name = aur_json.get_string_member ("Name");
				version = aur_json.get_string_member ("Version");
				desc = aur_json.get_string_member ("Description");
				repo = "AUR";
				size = 0;
				size_string = "";
				url = aur_json.get_string_member ("URL");
				licenses = aur_json.get_string_member ("License");
				reason = 0;
			} else {
				name = "";
				version = "";
				desc = "";
				repo = "";
				size = 0;
				size_string = "";
				url = "";
				licenses= "";
				reason = 0;
			}
		}
	}

	public struct PackageDetails {
		string repo;
		string has_signature;
		int reason;
		string packager;
		string install_date;
		string[] groups;
		string[] backups;
	}

	public struct PackageDeps {
		string repo;
		string[] depends;
		string[] optdepends;
		string[] requiredby;
		string[] provides;
		string[] replaces;
		string[] conflicts;
	}
}
