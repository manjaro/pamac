/*
 *  pamac-vala
 *
 *  Copyright (C) 2019 Guillaume Benoit <guillaume@manjaro.org>
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
	public interface SnapPlugin: Object {
		public signal bool get_authorization (string sender);
		public signal void emit_action_progress (string sender, string action, string status, double progress);
		public signal void emit_download_progress (string sender, string action, string status, double progress);
		public signal void emit_script_output (string sender, string message);
		public signal void emit_error (string sender, string message, string[] details);
		public signal void start_downloading (string sender);
		public signal void stop_downloading (string sender);

		public abstract List<SnapPackage> search_snaps (string search_string);
		public abstract bool is_installed_snap (string name);
		public abstract SnapPackage? get_snap (string name);
		public abstract List<SnapPackage> get_installed_snaps ();
		public abstract string get_installed_snap_icon (string name) throws Error;
		public abstract List<SnapPackage> get_category_snaps (string category);
		public abstract bool trans_run (string sender, string[] to_install, string[] to_remove);
		public abstract bool switch_channel (string sender, string name, string channel);
		public abstract void trans_cancel (string sender);
	}

	public class SnapPackage: Package {
		public string channel { get; internal set; default = "";}
		public string publisher { get; internal set; default = "";}
		public string license { get; internal set; default = "";}
		internal List<string> screenshots_priv;
		public List<string> screenshots { get {return screenshots_priv;} }
		internal List<string> channels_priv;
		public List<string> channels { get {return channels_priv;} }

		internal SnapPackage () {}
	}
}
