/*
 *  pamac-vala
 *
 *  Copyright (C) 2014  Paolo Borelli <pborelli@gnome.org>
 *  Copyright (C) 2018-2025 Guillaume Benoit <guillaume@manjaro.org>
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
		// results returned to the caller: GetResultMetas and ActivateResult
		// only accept these, never data built by another D-Bus client
		GenericSet<string> known_results;

		[DBus (visible = false)]
		public signal void show_details (string app_id, uint32 timestamp);
		[DBus (visible = false)]
		public signal void search_full (string[] terms, uint32 timestamp);

		public SearchProvider (Database database) {
			this.database = database;
			known_results = new GenericSet<string> (str_hash, str_equal);
		}

		GenericArray<string> normalize_terms (string[] terms) {
			var normalized_terms = new GenericArray<string> ();
			foreach (string t in terms) {
				normalized_terms.add (t.normalize ().casefold ());
			}
			return normalized_terms;
		}

		string[] search_pkgs (GenericArray<string> normalized_terms) {
			GenericArray<unowned Package> pkgs = database.search_uninstalled_apps (normalized_terms);
			var result = new GenericArray<string> ();
			foreach (unowned Package pkg in pkgs) {
				// concat data into a string
				var data_builder = new StringBuilder (pkg.app_id);
				data_builder.append (";");
				data_builder.append (pkg.app_name);
				data_builder.append (";");
				data_builder.append (pkg.long_desc);
				data_builder.append (";");
				data_builder.append (pkg.icon);
				known_results.add (data_builder.str);
				result.add (data_builder.str);
			}
			return result.data;
		}

		public async string[] get_initial_result_set (string[] terms) throws Error {
			known_results.remove_all ();
			var normalized_terms = normalize_terms (terms);
			return search_pkgs (normalized_terms);
		}

		public async string[] get_subsearch_result_set (string[] previous_results, string[] terms) throws Error {
			var normalized_terms = normalize_terms (terms);
			return search_pkgs (normalized_terms);
		}

		public HashTable<string, Variant>[] get_result_metas (string[] results) throws Error {
			var result = new GenericArray<HashTable<string, Variant>> ();
			foreach (unowned string str in results) {
				if (!known_results.contains (str)) {
					continue;
				}
				string[] pkg_data = str.split (";", 4);
				if (pkg_data.length != 4) {
					continue;
				}
				var meta = new HashTable<string, Variant> (str_hash, str_equal);
				meta.insert ("id", pkg_data[0]);
				meta.insert ("name", pkg_data[1]);
				meta.insert ("description", pkg_data[2]);
				Icon? icon = null;
				if (pkg_data[3] != "") {
					try {
						icon = new Gdk.Pixbuf.from_file (pkg_data[3]);
					} catch (Error e) {
						icon = new ThemedIcon ("package-x-generic");
					}
				} else {
					icon = new ThemedIcon ("package-x-generic");
				}
				if (icon != null) {
					meta.insert ("icon", icon.serialize ());
				}
				result.add (meta);
			}
			return result.data;
		}

		public void activate_result (string result, string[] terms, uint32 timestamp) throws Error {
			if (!known_results.contains (result)) {
				return;
			}
			// the result is "app_id;app_name;long_desc;icon"
			show_details (result.split (";", 2)[0], timestamp);
		}

		public void launch_search (string[] terms, uint32 timestamp) throws Error {
			search_full (terms, timestamp);
		}
	}
}
