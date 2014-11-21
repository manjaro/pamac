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
		Json.Array prev_inter = new Json.Array ();
		string uri = rpc_url + rpc_search + Uri.escape_string (needles[0]);
		var session = new Soup.Session ();
		var message = new Soup.Message ("GET", uri);
		var parser = new Json.Parser ();
		unowned Json.Object root_object;
		session.send_message (message);
		try {
			parser.load_from_data ((string) message.response_body.flatten ().data, -1);
			root_object = parser.get_root ().get_object ();
			prev_inter = root_object.get_array_member ("results");
		} catch (Error e) {
			print (e.message);
		}
		int length = needles.length;
		if (length == 1)
			return prev_inter;
		int i = 1;
		Json.Array inter = new Json.Array ();
		Json.Array found = new Json.Array ();
		while (i < length) {
			inter = new Json.Array ();
			uri = rpc_url + rpc_search + Uri.escape_string (needles[i]);
			message = new Soup.Message ("GET", uri);
			session.send_message (message);
			try {
				parser.load_from_data ((string) message.response_body.flatten ().data, -1);
				root_object = parser.get_root ().get_object ();
				found = root_object.get_array_member ("results");
			} catch (Error e) {
				print (e.message);
			}
			foreach (Json.Node prev_inter_node in prev_inter.get_elements ()) {
				foreach (Json.Node found_node in found.get_elements ()) {
					if (strcmp (prev_inter_node.get_object ().get_string_member ("Name"),
								found_node.get_object ().get_string_member ("Name")) == 0) {
						inter.add_element (prev_inter_node);
					}
				}
			}
			if (i != (length -1))
				prev_inter = inter;
			i += 1;
		}
		return inter;
	}

	public Json.Object? info (string pkgname) {
		unowned Json.Object? pkg_info = null;
		string uri = rpc_url + rpc_info + pkgname;
		var session = new Soup.Session ();
		var message = new Soup.Message ("GET", uri);
		session.send_message (message);

		try {
			var parser = new Json.Parser ();
			parser.load_from_data ((string) message.response_body.flatten ().data, -1);
			pkg_info = parser.get_root ().get_object ().get_object_member ("results");
		} catch (Error e) {
			stderr.printf ("Failed to get infos about %s from AUR\n", pkgname);
			print (e.message);
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
			builder.append (pkgname);
		}
		var session = new Soup.Session ();
		var message = new Soup.Message ("GET", builder.str);
		session.send_message (message);

		try {
			var parser = new Json.Parser ();
			parser.load_from_data ((string) message.response_body.flatten ().data, -1);
	
			unowned Json.Object root_object = parser.get_root ().get_object ();
			results = root_object.get_array_member ("results");
		} catch (Error e) {
			print (e.message);
		}
		return results;
	}
}
