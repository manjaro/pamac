/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2018 Guillaume Benoit <guillaume@manjaro.org>
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
	// AUR urls
	const string aur_url = "http://aur.archlinux.org";
	const string rpc_url = aur_url + "/rpc/?v=5";
	const string rpc_search = "&type=search&arg=";
	const string rpc_multiinfo = "&type=info";
	const string rpc_multiinfo_arg = "&arg[]=";

	async Json.Array rpc_query (string uri) {
		SourceFunc callback = rpc_query.callback;
		var results = new Json.Array ();
		var session = new Soup.Session ();
		// set a 15 seconds timeout because it is also the dbus daemon timeout
		session.timeout = 15;
		var message = new Soup.Message ("GET", uri);
		var parser = new Json.Parser ();
		session.queue_message (message, (sess, mess) => {
			try {
				parser.load_from_data ((string) mess.response_body.flatten ().data, -1);
				unowned Json.Node? root = parser.get_root ();
				if (root != null) {
					if (root.get_object ().get_string_member ("type") == "error") {
						stderr.printf ("Failed to query %s from AUR\n", uri);
					} else {
						results = root.get_object ().get_array_member ("results");
					}
				}
			} catch (Error e) {
				critical (e.message);
			}
			Idle.add ((owned) callback);
		});
		yield;
		return results;
	}

	internal async Json.Array aur_search (string[] needles) {
		if (needles.length == 0) {
			return new Json.Array ();
		} else {
			Json.Array[] found_array = {};
			foreach (unowned string needle in needles) {
				found_array += yield rpc_query (rpc_url + rpc_search + Uri.escape_string (needle));
			}
			var result = new Json.Array ();
			foreach (unowned Json.Array found in found_array) {
				if (found.get_length () == 0) {
					continue;
				}
				if (result.get_length () == 0) {
					result = found;
					continue;
				}
				var inter = new Json.Array ();
				result.foreach_element ((result_array, result_index, result_node) => {
					found.foreach_element ((found_array, found_index, found_node) => {
						if (strcmp (result_node.get_object ().get_string_member ("Name"),
									found_node.get_object ().get_string_member ("Name")) == 0) {
							inter.add_element (result_node);
						}
					});
				});
				result = (owned) inter;
			}
			return result;
		}
	}

	internal async Json.Array aur_multiinfo (string[] pkgnames) {
		if (pkgnames.length == 0) {
			return new Json.Array ();
		}
		// query pkgnames hundred by hundred to avoid too long uri error
		// example: ros-lunar-desktop
		if (pkgnames.length <= 100) {
			var builder = new StringBuilder ();
			builder.append (rpc_url);
			builder.append (rpc_multiinfo);
			foreach (unowned string pkgname in pkgnames) {
				builder.append (rpc_multiinfo_arg);
				builder.append (Uri.escape_string (pkgname));
			}
			return yield rpc_query (builder.str);
		} else {
			var result = new Json.Array ();
			int index_max = pkgnames.length - 1;
			int index = 0;
			while (index < index_max) {
				var builder = new StringBuilder ();
				builder.append (rpc_url);
				builder.append (rpc_multiinfo);
				for (int i = 0; i < 100; i++) {
					unowned string pkgname = pkgnames[index];
					builder.append (rpc_multiinfo_arg);
					builder.append (Uri.escape_string (pkgname));
					index++;
					if (index == index_max) {
						break;
					}
				}
				var array = yield rpc_query (builder.str);
				array.foreach_element ((array, index, node) => {
					result.add_element (node);
				});
			}
			return result;
		}
	}
}
