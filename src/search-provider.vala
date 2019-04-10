/*
 *  pamac-vala
 *
 *  Copyright (C) 2014  Paolo Borelli <pborelli@gnome.org>
 *  Copyright (C) 2018 Guillaume Benoit <guillaume@manjaro.org>
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

	[DBus (name = "org.gnome.Shell.SearchProvider2")]
	public class SearchProvider : Object {
		Database database;

		[DBus (visible = false)]
		public signal void show_details (string pkgname, uint32 timestamp);
		[DBus (visible = false)]
		public signal void search_full (string[] terms, uint32 timestamp);

		public SearchProvider (Database database) {
			this.database = database;
		}

		private string[] normalize_terms (string[] terms) {
			var normalized_terms = new GenericArray<string> ();
			foreach (string t in terms) {
				normalized_terms.add (t.normalize ().casefold ());
			}
			return normalized_terms.data;
		}

		private async string[] search_pkgs (string[] normalized_terms) {
			var str_builder = new StringBuilder ();
			foreach (unowned string str in normalized_terms) {
				if (str_builder.len > 0) {
					str_builder.append (" ");
				}
				str_builder.append (str);
			}
			List<Package> pkgs = yield database.search_repos_pkgs_async (str_builder.str);
			var result = new GenericArray<string> ();
			foreach (unowned Package pkg in pkgs) {
				result.add (pkg.name);
			}
			return result.data;
		}

		public async string[] get_initial_result_set (string[] terms) throws Error {
			var normalized_terms = normalize_terms (terms);
			return yield search_pkgs (normalized_terms);
		}

		public async string[] get_subsearch_result_set (string[] previous_results, string[] terms) throws Error {
			var normalized_terms = normalize_terms (terms);
			return yield search_pkgs (normalized_terms);
		}

		public HashTable<string, Variant>[] get_result_metas (string[] results) throws Error {
			var result = new GenericArray<HashTable<string, Variant>> ();
			int count = 0;
			foreach (unowned string str in results) {
				var meta = new HashTable<string, Variant> (str_hash, str_equal);
				var pkg = database.get_installed_pkg (str);
				if (pkg.name == "") {
					pkg = database.get_sync_pkg (str);
				}
				if (pkg.name != "") {
					count++;
					meta.insert ("id", pkg.name);
					meta.insert ("name", pkg.name);
					meta.insert ("description", pkg.desc);
					Icon? icon = null;
					if (pkg.icon != "") {
						try {
							icon = new Gdk.Pixbuf.from_file (pkg.icon);
						} catch (GLib.Error e) {
							// some icons are not in the right repo
							string icon_path = pkg.icon;
							if ("extra" in pkg.icon) {
								icon_path = pkg.icon.replace ("extra", "community");
							} else if ("community" in pkg.icon) {
								icon_path = pkg.icon.replace ("community", "extra");
							}
							try {
								icon = new Gdk.Pixbuf.from_file (icon_path);
							} catch (GLib.Error e) {
								icon = new ThemedIcon ("package-x-generic");
							}
						}
					} else {
						icon = new ThemedIcon ("package-x-generic");
					}
					if (icon != null) {
						meta.insert ("icon", icon.serialize ());
					}
					result.add (meta);
				}
			}
			return result.data;
		}

		public void activate_result (string result, string[] terms, uint32 timestamp) throws Error {
			show_details (result, timestamp);
		}

		public void launch_search (string[] terms, uint32 timestamp) throws Error {
			search_full (terms, timestamp);
		}
	}
}
