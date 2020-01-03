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
	public class Package: Object {
		public string name { get; internal set; default = "";}
		public string app_name { get; internal set; default = "";}
		public string version { get; internal set; default = "";}
		public string installed_version { get; internal set; default = "";}
		public string desc { get; internal set; default = "";}
		public string long_desc { get; internal set; default = "";}
		public string repo { get; internal set; default = "";}
		public string launchable { get; internal set; default = "";}
		public uint64 installed_size { get; internal set; }
		public uint64 download_size { get; internal set; }
		public string url { get; internal set; default = "";}
		public string icon { get; internal set; default = "";}
		public uint64 installdate { get; internal set; }

		internal Package () {}
	}
}
