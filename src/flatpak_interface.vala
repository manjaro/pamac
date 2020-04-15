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
	internal interface FlatpakPlugin: Object {
		public abstract uint64 refresh_period { get; set; }
		public abstract MainContext context { get; set; }

		public signal bool get_authorization (string sender);
		public signal void emit_action_progress (string sender, string action, string status, double progress);
		public signal void emit_script_output (string sender, string message);
		public signal void emit_error (string sender, string message, string[] details);

		public abstract void load_appstream_data ();
		public abstract SList<string> get_remotes_names ();
		public abstract void search_flatpaks (string search_string, ref SList<FlatpakPackage> pkgs);
		public abstract void search_uninstalled_flatpaks_sync (string[] search_terms, ref SList<FlatpakPackage> pkgs);
		public abstract bool is_installed_flatpak (string name);
		public abstract FlatpakPackage? get_flatpak_by_app_id (string app_id);
		public abstract FlatpakPackage? get_flatpak (string id);
		public abstract void get_installed_flatpaks (ref SList<FlatpakPackage> pkgs);
		public abstract void get_category_flatpaks (string category, ref SList<FlatpakPackage> pkgs);
		public abstract void get_flatpak_updates (ref SList<FlatpakPackage> pkgs);
		public abstract bool trans_run (string sender, string[] to_install, string[] to_remove, string[] to_upgrade);
		public abstract void trans_cancel (string sender);
	}

	public class FlatpakPackage: Package {
		public string id { get; internal set; default = "";}
		public string branch { get; internal set; default = "";}
		public string license { get; internal set; default = "";}
		internal SList<string> screenshots_priv;
		public SList<string> screenshots { get {return screenshots_priv;} }

		internal FlatpakPackage () {
			screenshots_priv = new SList<string> ();
		}
	}
}
