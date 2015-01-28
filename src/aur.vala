/*
 *  pamac-vala
 *
 *  Copyright (C) 2014  Guillaume Benoit <guillaume@manjaro.org>
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
	const string rpc_url = aur_url + "/rpc.php";
	const string rpc_search =  "?type=search&arg=";
	const string rpc_info = "?type=info&arg=";
	const string rpc_multiinfo = "?type=multiinfo";
	const string rpc_multiinfo_arg = "&arg[]=";
	const string aur_url_id =  "/packages.php?setlang=en&ID=";

	public Json.Array search (string[] needles) {
		var prev_inter = new Json.Array ();
		string uri = rpc_url + rpc_search + Uri.escape_string (needles[0]);
		var session = new Soup.Session ();
		var message = new Soup.Message ("GET", uri);
		var parser = new Json.Parser ();
		session.send_message (message);
		try {
			parser.load_from_data ((string) message.response_body.flatten ().data, -1);
		} catch (Error e) {
			print (e.message);
		}
		unowned Json.Node? root = parser.get_root ();
		if (root != null) {
			prev_inter = root.get_object ().get_array_member ("results");
		}
		int length = needles.length;
		if (length == 1)
			return prev_inter;
		int i = 1;
		var inter = new Json.Array ();
		var found = new Json.Array ();
		while (i < length) {
			inter = new Json.Array ();
			uri = rpc_url + rpc_search + Uri.escape_string (needles[i]);
			message = new Soup.Message ("GET", uri);
			session.send_message (message);
			try {
				parser.load_from_data ((string) message.response_body.flatten ().data, -1);
			} catch (Error e) {
				print (e.message);
			}
			root = parser.get_root ();
			if (root != null) {
				found = root.get_object ().get_array_member ("results");
			}
			foreach (var prev_inter_node in prev_inter.get_elements ()) {
				foreach (var found_node in found.get_elements ()) {
					if (strcmp (prev_inter_node.get_object ().get_string_member ("Name"),
								found_node.get_object ().get_string_member ("Name")) == 0) {
						inter.add_element (prev_inter_node);
					}
				}
			}
			if (i != (length -1)) {
				prev_inter = inter;
			}
			i += 1;
		}
		return inter;
	}

	public Json.Object info (string pkgname) {
		var pkg_info = new Json.Object ();
		string uri = rpc_url + rpc_info + Uri.escape_string (pkgname);
		var session = new Soup.Session ();
		var message = new Soup.Message ("GET", uri);
		session.send_message (message);
		var parser = new Json.Parser ();
		try {
			parser.load_from_data ((string) message.response_body.flatten ().data, -1);
		} catch (Error e) {
			stderr.printf ("Failed to get infos about %s from AUR\n", pkgname);
			print (e.message);
		}
		unowned Json.Node? root = parser.get_root ();
		if (root != null) {
			pkg_info = root.get_object ().get_object_member ("results");
		}
		return pkg_info;
	}

	public Json.Array multiinfo (string[] pkgnames) {
		Json.Array results = new Json.Array ();
		var builder = new StringBuilder ();
		builder.append (rpc_url);
		builder.append (rpc_multiinfo);
		foreach (string pkgname in pkgnames) {
			builder.append (rpc_multiinfo_arg);
			builder.append (Uri.escape_string (pkgname));
		}
		var session = new Soup.Session ();
		var message = new Soup.Message ("GET", builder.str);
		session.send_message (message);
		var parser = new Json.Parser ();
		try {
			parser.load_from_data ((string) message.response_body.flatten ().data, -1);
		} catch (Error e) {
			print (e.message);
		}
		unowned Json.Node? root = parser.get_root ();
		if (root != null) {
			results = root.get_object ().get_array_member ("results");
		}
		return results;
	}
}
