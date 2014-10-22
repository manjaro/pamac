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

//~ const string srcpkgdir = "/tmp/pamac";

namespace AUR {
	// AUR urls
	const string aur_url = "http://aur.archlinux.org";
	const string rpc_url = aur_url + "/rpc.php";
	const string rpc_search =  "?type=search&arg=";
	const string rpc_info = "?type=info&arg=";
	const string rpc_multiinfo = "?type=multiinfo";
	const string rpc_multiinfo_arg = "&arg[]=";
	const string aur_url_id =  "/packages.php?setlang=en&ID=";

	public Json.Array search (string needle) {
		string uri = rpc_url + rpc_search + needle;
		var session = new Soup.Session ();
		var message = new Soup.Message ("GET", uri);
		session.send_message (message);
		Json.Array results = new Json.Array ();

		try {
			var parser = new Json.Parser ();
			parser.load_from_data ((string) message.response_body.flatten ().data, -1);

			unowned Json.Object root_object = parser.get_root ().get_object ();
			results = root_object.get_array_member ("results");
//~ 			foreach (unowned Json.Node node in results.get_elements ()) {
//~ 				Json.Object pkg_info = node.get_object ();
//~ 				results.append (new Pamac.Package (null, pkg_info));
//~ 			}
		} catch (Error e) {
			print (e.message);
		}
		return results;
	}

	public Json.Object? info (string pkgname) {
		unowned Json.Object? pkg_info = null;
		string uri = rpc_url + rpc_info + pkgname;
		stdout.printf("get %s from AUR\n", pkgname);
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
//~ 			foreach (var node in results.get_elements ()) {
//~ 				var pkg_info = node.get_object ();
//~ 				results.append (new Pamac.Package (null, pkg_info));
//~ 			}
		} catch (Error e) {
			print (e.message);
		}
		return results;
	}
}
