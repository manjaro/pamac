/*
 *  pamac-vala
 *
 *  Copyright (C) 2019-2020 Guillaume Benoit <guillaume@manjaro.org>
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

		public abstract void search_snaps (string search_string, ref SList<SnapPackage> pkgs);
		public abstract bool is_installed_snap (string name);
		public abstract SnapPackage? get_snap (string name);
		public abstract void get_installed_snaps (ref SList<SnapPackage> pkgs);
		public abstract string get_installed_snap_icon (string name) throws Error;
		public abstract void get_category_snaps (string category, ref SList<SnapPackage> pkgs);
		public abstract bool trans_run (string sender, string[] to_install, string[] to_remove);
		public abstract bool switch_channel (string sender, string name, string channel);
		public abstract void trans_cancel (string sender);
	}

	public class SnapPackage: Package {
		public string channel { get; internal set; default = "";}
		public string publisher { get; internal set; default = "";}
		public string license { get; internal set; default = "";}
		public string confined { get; internal set; default = "";}
		internal SList<string> screenshots_priv;
		public SList<string> screenshots { get {return screenshots_priv;} }
		internal SList<string> channels_priv;
		public SList<string> channels { get {return channels_priv;} }

		internal SnapPackage () {
			screenshots_priv = new SList<string> ();
			channels_priv = new SList<string> ();
		}
	}
}
