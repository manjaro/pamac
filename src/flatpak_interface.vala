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
	public interface FlatpakPlugin: Object {
		public signal bool get_authorization (string sender);
		public signal void emit_action_progress (string sender, string action, string status, double progress);
		public signal void emit_script_output (string sender, string message);
		public signal void emit_error (string sender, string message, string[] details);

		public abstract void load_appstream_data ();
		public abstract List<string> get_remotes_names ();
		public abstract List<FlatpakPackage> search_flatpaks (string search_string);
		public abstract bool is_installed_flatpak (string name);
		public abstract FlatpakPackage? get_flatpak (string id);
		public abstract List<FlatpakPackage> get_installed_flatpaks ();
		public abstract List<FlatpakPackage> get_category_flatpaks (string category);
		public abstract List<FlatpakPackage> get_flatpak_updates ();
		public abstract bool trans_run (string sender, string[] to_install, string[] to_remove, string[] to_upgrade);
		public abstract void trans_cancel (string sender);
	}

	public class FlatpakPackage: Package {
		public string id { get; internal set; default = "";}
		public string branch { get; internal set; default = "";}
		public string license { get; internal set; default = "";}
		internal List<string> screenshots_priv;
		public List<string> screenshots { get {return screenshots_priv;} }

		internal FlatpakPackage () {}
	}
}
