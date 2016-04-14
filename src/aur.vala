/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2016 Guillaume Benoit <guillaume@manjaro.org>
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

namespace AUR {
	// AUR urls
	const string aur_url = "http://aur.archlinux.org";
	const string rpc_url = aur_url + "/rpc/?v=5";
	const string rpc_search = "&type=search&arg=";
	const string rpc_multiinfo = "&type=info";
	const string rpc_multiinfo_arg = "&arg[]=";

	Json.Array rpc_query (string uri) {
		var results = new Json.Array ();
		var session = new Soup.Session ();
		// set a 15 seconds timeout because it is also the dbus daemon timeout
		session.timeout = 15;
		var message = new Soup.Message ("GET", uri);
		var parser = new Json.Parser ();
		session.send_message (message);
		try {
			parser.load_from_data ((string) message.response_body.flatten ().data, -1);
		} catch (Error e) {
			critical (e.message);
		}
		unowned Json.Node? root = parser.get_root ();
		if (root != null) {
			if (root.get_object ().get_string_member ("type") == "error") {
				critical ("Failed to query %s from AUR", uri);
			} else {
				results = root.get_object ().get_array_member ("results");
			}
		}
		return results;
	}

	public async Json.Array search (string[] needles) {
		if (needles.length == 0) {
			return new Json.Array ();
		} else if (needles.length == 1) {
			return rpc_query (rpc_url + rpc_search + Uri.escape_string (needles[0]));
		} else {
			var inter = new Json.Array ();
			var prev_inter = new Json.Array ();
			foreach (unowned string needle in needles) {
				inter = new Json.Array ();
				var found = rpc_query (rpc_url + rpc_search + Uri.escape_string (needle));
				prev_inter.foreach_element ((prev_inter_array, prev_inter_index, prev_inter_node) => {
					found.foreach_element ((found_array, found_index, found_node) => {
						if (strcmp (prev_inter_node.get_object ().get_string_member ("Name"),
									found_node.get_object ().get_string_member ("Name")) == 0) {
							inter.add_element (prev_inter_node);
						}
					});
				});
				prev_inter = (owned) inter;
			}
			return inter;
		}
	}

	public async Json.Array multiinfo (string[] pkgnames) {
		if (pkgnames.length == 0) {
			return new Json.Array ();
		}
		var builder = new StringBuilder ();
		builder.append (rpc_url);
		builder.append (rpc_multiinfo);
		foreach (unowned string pkgname in pkgnames) {
			builder.append (rpc_multiinfo_arg);
			builder.append (Uri.escape_string (pkgname));
		}
		return rpc_query (builder.str);
	}
}
