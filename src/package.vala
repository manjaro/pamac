/*
 *  pamac-vala
 *
 *  Copyright (C) 2014  Guillaume Benoit <guillaume@manjaro.org>
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
		public unowned Alpm.Package? alpm_pkg;
		public unowned Json.Object? aur_json;
		public string name;
		public string version;
		public string repo;
		public uint64 size;
		public string size_string;

		public Package (Alpm.Package? alpm_pkg, Json.Object? aur_json) {
			if (alpm_pkg != null) {
				this.alpm_pkg = alpm_pkg;
				this.aur_json = null;
				name = alpm_pkg.name;
				version = alpm_pkg.version;
				if (alpm_pkg.db != null)
					repo = alpm_pkg.db.name;
				else 
					repo = "";
				size = alpm_pkg.isize;
				size_string = format_size (alpm_pkg.isize);
			} else if (aur_json != null ) {
				this.alpm_pkg = null;
				this.aur_json = aur_json;
				name = aur_json.get_string_member ("Name");
				version = aur_json.get_string_member ("Version");
				repo = "AUR";
				size = 0;
				size_string = "";
			} else {
				this.alpm_pkg = null;
				this.aur_json = null;
				name = dgettext (null, "No package found");
				version = "";
				repo = "";
				size = 0;
				size_string = "";
			}
		}
	}
}
