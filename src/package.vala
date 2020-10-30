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
	public abstract class Package : Object {
		public abstract string name { get; internal set; }
		public abstract string id { get; }
		public abstract string? app_name { get; }
		public abstract string? app_id { get; }
		public abstract string version { get; internal set; }
		public abstract string? installed_version { get; internal set; }
		public abstract string? desc { get; internal set; }
		public abstract string? long_desc { get; }
		public abstract string? repo { get; internal set; }
		public abstract string? launchable { get; }
		public abstract string? license { get; }
		public abstract string? url { get; }
		public abstract string? icon { get; }
		public abstract uint64 installed_size { get; }
		public abstract uint64 download_size { get; }
		public abstract uint64 install_date { get; }
		public abstract GenericArray<string> screenshots { get; }

		internal Package () {}
	}
}
