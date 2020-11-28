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
	internal class AUR: Object {
		// AUR urls
		const string rpc_url = "https://aur.archlinux.org/rpc/?v=5";
		const string rpc_search = "&type=search&arg=";
		const string rpc_multiinfo = "&type=info";
		const string rpc_multiinfo_arg = "&arg[]=";
		Soup.Session session;
		HashTable<unowned string, Json.Object> cached_infos;
		HashTable<string, Json.Array> search_results;

		public AUR () {
			Object ();
		}

		construct {
			session = new Soup.Session ();
			session.user_agent = "Pamac/%s".printf (VERSION);
			session.timeout = 30;
			cached_infos = new HashTable<unowned string, Json.Object> (str_hash, str_equal);
			search_results = new HashTable<string, Json.Array> (str_hash, str_equal);
		}

		Json.Array? rpc_query (string uri) {
			try {
				var message = new Soup.Message ("GET", uri);
				InputStream input_stream = session.send (message);
				var parser = new Json.Parser.immutable_new ();
				parser.load_from_stream (input_stream);
				unowned Json.Node? root = parser.get_root ();
				if (root != null) {
					unowned Json.Object obj = root.get_object ();
					if (obj.get_string_member ("type") == "error") {
						unowned string error_details = obj.get_string_member ("error");
						stderr.printf ("Failed to query %s from AUR: %s\n", uri, error_details);
					} else {
						return obj.get_array_member ("results");
					}
				}
			} catch (Error e) {
				warning (e.message);
				stderr.printf ("Failed to query %s from AUR\n", uri);
			}
			return null;
		}

		Json.Array? multiinfo (string[] pkgnames) {
			// query pkgnames hundred by hundred to avoid too long uri error
			// example: ros-lunar-desktop
			if (pkgnames.length <= 200) {
				var builder = new StringBuilder (rpc_url);
				builder.append (rpc_multiinfo);
				foreach (unowned string pkgname in pkgnames) {
					builder.append (rpc_multiinfo_arg);
					builder.append (Uri.escape_string (pkgname));
				}
				return rpc_query (builder.str);
			} else {
				var result = new Json.Array ();
				int index_max = pkgnames.length - 1;
				int index = 0;
				while (index < index_max) {
					var builder = new StringBuilder (rpc_url);
					builder.append (rpc_multiinfo);
					for (int i = 0; i < 200; i++) {
						unowned string pkgname = pkgnames[index];
						builder.append (rpc_multiinfo_arg);
						builder.append (Uri.escape_string (pkgname));
						index++;
						if (index == index_max) {
							break;
						}
					}
					Json.Array? array = rpc_query (builder.str);
					if (array != null) {
						uint array_length = array.get_length ();
						for (uint i = 0; i < array_length; i++) {
							result.add_element (array.dup_element (i));
						}
					}
				}
				return result;
			}
		}

		public unowned Json.Object? get_infos (string pkgname) {
			unowned Json.Object? json_object = cached_infos.lookup (pkgname);
			if (json_object == null) {
				Json.Array? results = multiinfo ({pkgname});
				if (results != null && results.get_length () == 1) {
					lock (cached_infos) {
						json_object = results.get_object_element (0);
						if (json_object != null) {
							cached_infos.insert (json_object.get_string_member ("Name"), json_object);
						}
					}
				}
			}
			return json_object;
		}

		public GenericArray<Json.Object> get_multi_infos (string[] pkgnames) {
			var result = new GenericArray<Json.Object> ();
			var to_query = new GenericArray<string> ();
			lock (cached_infos) {
				foreach (unowned string pkgname in pkgnames) {
					unowned Json.Object? json_object = cached_infos.lookup (pkgname);
					if (json_object == null) {
						to_query.add (pkgname);
					} else {
						result.add (json_object);
					}
				}
			}
			if (to_query.length > 0) {
				Json.Array? results = multiinfo (to_query.data);
				if (results != null) {
					lock (cached_infos) {
						uint results_length = results.get_length ();
						for (uint i = 0; i < results_length; i++) {
							unowned Json.Object json_object = results.get_object_element (i);
							result.add (json_object);
							cached_infos.insert (json_object.get_string_member ("Name"), json_object);
						}
					}
				}
			}
			return result;
		}

		public GenericArray<Json.Object> search (string search_string) {
			string[] needles = search_string.split (" ");
			if (needles.length == 0) {
				return new GenericArray<Json.Object> ();
			} else if (needles.length == 1) {
				unowned string needle = needles[0];
				if (needle.length < 2) {
					// query arg too small
					return new GenericArray<Json.Object> ();
				}
				Json.Array? found;
				lock (search_results) {
					found = search_results.lookup (needle);
				}
				if (found == null) {
					var builder = new StringBuilder (rpc_url);
					builder.append (rpc_search);
					builder.append (Uri.escape_string (needle));
					found = rpc_query (builder.str);
				}
				if (found == null) {
					// a error occured, do not cache the result
					return new GenericArray<Json.Object> ();
				}
				lock (search_results) {
					search_results.insert (needle, found);
				}
				var objects = new GenericArray<Json.Object> ();
				uint found_length = found.get_length ();
				for (uint i = 0; i < found_length; i++) {
					objects.add (found.get_object_element (i));
				}
				return objects;
			} else {
				// compute the intersection of all found packages
				var builder = new StringBuilder (rpc_url);
				builder.append (rpc_search);
				var all_found = new GenericArray<Json.Array> ();
				foreach (unowned string needle in needles) {
					if (needle.length < 2) {
						// query arg too small
						continue;
					}
					Json.Array? found;
					lock (search_results) {
						found = search_results.lookup (needle);
					}
					if (found == null) {
						var needle_builder = new StringBuilder (builder.str);
						needle_builder.append (Uri.escape_string (needle));
						found = rpc_query (needle_builder.str);
					}
					if (found == null) {
						// a error occured, just continue
						continue;
					}
					lock (search_results) {
						search_results.insert (needle, found);
					}
					if (found.get_length () == 0) {
						// a zero length array mean the inter length will be zero
						return new GenericArray<Json.Object> ();
					}
					all_found.add (found);
				}
				uint all_found_length = all_found.length;
				// case of all needle search failed
				if (all_found_length == 0) {
					return new GenericArray<Json.Object> ();
				}
				// case of errors occured and only one needle succeed
				if (all_found_length == 1) {
					unowned Json.Array found = all_found[0];
					var objects = new GenericArray<Json.Object> ();
					uint found_length = found.get_length ();
					for (uint i = 0; i < found_length; i++) {
						objects.add (found.get_object_element (i));
					}
					return objects;
				}
				// add first array member in a hash set
				var check_set = new HashTable<unowned string, Json.Object> (str_hash, str_equal);
				unowned Json.Array found = all_found[0];
				uint found_length = found.get_length ();
				uint i;
				for (i = 0; i < found_length; i++) {
					unowned Json.Object object = found.get_object_element (i);
					check_set.insert (object.get_string_member ("Name"), object);
				}
				// compare next array members with check_set
				// and use inter as next check_set
				for (i = 1; i < all_found_length; i++) {
					var inter = new HashTable<unowned string, Json.Object> (str_hash, str_equal);
					found = all_found[i];
					found_length = found.get_length ();
					for (uint j = 0; j < found_length; j++) {
						unowned Json.Object object = found.get_object_element (j);
						unowned string pkgname = object.get_string_member ("Name");
						if (pkgname in check_set) {
							inter.insert (pkgname, object);
						}
					}
					check_set = (owned) inter;
				}
				var objects = new GenericArray<Json.Object> ();
				var iter = HashTableIter<unowned string, Json.Object> (check_set);
				unowned Json.Object object;
				while (iter.next (null, out object)) {
					objects.add (object);
				}
				return objects;
			}
		}
	}
}
