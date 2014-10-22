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
	const string aur_url = "http://aur3.org/";


	public string[] search (string needle) {
		string[] results = {};
		try {
			// Resolve hostname to IP address
			var resolver = Resolver.get_default ();
			var addresses = resolver.lookup_by_name (host, null);
			var address = addresses.nth_data (0);
			// Connect
			var client = new SocketClient ();
			var conn = client.connect (new InetSocketAddress (address, 1819));
			// Send HTTP GET request
			var message = @"nd $query";
			conn.output_stream.write (message.data);
			// Receive response
			var response = new DataInputStream (conn.input_stream);
			string line;
			while ((line = response.read_line (null)) != null) {
				results += line;
			}
		} catch (Error e) {
			stderr.printf ("%s\n", e.message);
		}
		return results;
	}

	public void info (string pkgname) {
		string uri = rpc_url + rpc_info + pkgname;
		var session = new Soup.Session ();
		var message = new Soup.Message ("GET", uri);
		session.send_message (message);

		try {
			var parser = new Json.Parser ();
			parser.load_from_data ((string) message.response_body.flatten ().data, -1);

			var root_object = parser.get_root ().get_object ();
			var pkg_info = root_object.get_object_member ("results");
			AUR.Pkg aur_pkg = new AUR.Pkg (pkg_info);
			stdout.printf ("got %s (%s)\n", aur_pkg.name, aur_pkg.license);
		} catch (Error e) {
			stderr.printf ("Failed to get infos about %s from AUR\n", pkgname);
			print (e.message);
		}
	}

}
