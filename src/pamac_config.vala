/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2015 Guillaume Benoit <guillaume@manjaro.org>
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

const string VERSION = "3.1.0";

namespace Pamac {
	[Compact]
	public class Config {
		public string conf_path;
		public bool recurse;
		public uint64 refresh_period;
		public bool no_update_hide_icon;
		public bool enable_aur;
		public bool search_aur;
		public bool check_aur_updates;
		public bool no_confirm_build;
		public HashTable<string,string> environment_variables;

		public Config (string path) {
			conf_path = path;
			//get environment variables
			environment_variables = new HashTable<string,string> (str_hash, str_equal);
			var utsname = Posix.utsname();
			environment_variables.insert ("HTTP_USER_AGENT", "pamac/%s (%s %s)".printf (VERSION, utsname.sysname, utsname.machine));
			unowned string? variable = Environment.get_variable ("http_proxy");
			if (variable != null) {
				environment_variables.insert ("http_proxy", variable);
			}
			variable = Environment.get_variable ("https_proxy");
			if (variable != null) {
				environment_variables.insert ("https_proxy", variable);
			}
			variable = Environment.get_variable ("ftp_proxy");
			if (variable != null) {
				environment_variables.insert ("ftp_proxy", variable);
			}
			variable = Environment.get_variable ("socks_proxy");
			if (variable != null) {
				environment_variables.insert ("socks_proxy", variable);
			}
			variable = Environment.get_variable ("no_proxy");
			if (variable != null) {
				environment_variables.insert ("no_proxy", variable);
			}
			// set default option
			refresh_period = 6;
			reload ();
		}

		public void reload () {
			// set default options
			recurse = false;
			no_update_hide_icon = false;
			enable_aur = false;
			search_aur = false;
			check_aur_updates = false;
			no_confirm_build = false;
			parse_file (conf_path);
		}

		public void parse_file (string path) {
			var file = GLib.File.new_for_path (path);
			if (file.query_exists ()) {
				try {
					// Open file for reading and wrap returned FileInputStream into a
					// DataInputStream, so we can read line by line
					var dis = new DataInputStream (file.read ());
					string? line;
					// Read lines until end of file (null) is reached
					while ((line = dis.read_line ()) != null) {
						if (line.length == 0) {
							continue;
						}
						// ignore whole line and end of line comments
						string[] splitted = line.split ("#", 2);
						line = splitted[0].strip ();
						if (line.length == 0) {
							continue;
						}
						splitted = line.split ("=", 2);
						unowned string key = splitted[0]._strip ();
						if (key == "RemoveUnrequiredDeps") {
							recurse = true;
						} else if (key == "RefreshPeriod") {
							if (splitted.length == 2) {
								unowned string val = splitted[1]._strip ();
								refresh_period = uint64.parse (val);
							}
						} else if (key == "NoUpdateHideIcon") {
							no_update_hide_icon = true;
						} else if (key == "EnableAUR") {
							enable_aur = true;
						} else if (key == "SearchInAURByDefault") {
							search_aur = true;
						} else if (key == "CheckAURUpdates") {
							check_aur_updates = true;
						} else if (key == "NoConfirmBuild") {
							no_confirm_build = true;
						}
					}
				} catch (GLib.Error e) {
					GLib.stderr.printf("%s\n", e.message);
				}
			} else {
				GLib.stderr.printf ("File '%s' doesn't exist.\n", path);
			}
		}

		public void write (HashTable<string,Variant> new_conf) {
			var file = GLib.File.new_for_path (conf_path);
			var data = new GLib.List<string> ();
			if (file.query_exists ()) {
				try {
					// Open file for reading and wrap returned FileInputStream into a
					// DataInputStream, so we can read line by line
					var dis = new DataInputStream (file.read ());
					string? line;
					// Read lines until end of file (null) is reached
					while ((line = dis.read_line ()) != null) {
						if (line.length == 0) {
							data.append ("\n");
							continue;
						}
						unowned Variant variant;
						if (line.contains ("RemoveUnrequiredDeps")) {
							if (new_conf.lookup_extended ("RemoveUnrequiredDeps", null, out variant)) {
								if (variant.get_boolean ()) {
									data.append ("RemoveUnrequiredDeps\n");
								} else {
									data.append ("#RemoveUnrequiredDeps\n");
								}
								new_conf.remove ("RemoveUnrequiredDeps");
							} else {
								data.append (line + "\n");
							}
						} else if (line.contains ("RefreshPeriod")) {
							if (new_conf.lookup_extended ("RefreshPeriod", null, out variant)) {
								data.append ("RefreshPeriod = %llu\n".printf (variant.get_uint64 ()));
								new_conf.remove ("RefreshPeriod");
							} else {
								data.append (line + "\n");
							}
						} else if (line.contains ("NoUpdateHideIcon")) {
							if (new_conf.lookup_extended ("NoUpdateHideIcon", null, out variant)) {
								if (variant.get_boolean ()) {
									data.append ("NoUpdateHideIcon\n");
								} else {
									data.append ("#NoUpdateHideIcon\n");
								}
								new_conf.remove ("NoUpdateHideIcon");
							} else {
								data.append (line + "\n");
							}
						} else if (line.contains ("EnableAUR")) {
							if (new_conf.lookup_extended ("EnableAUR", null, out variant)) {
								if (variant.get_boolean ()) {
									data.append ("EnableAUR\n");
								} else {
									data.append ("#EnableAUR\n");
								}
								new_conf.remove ("EnableAUR");
							} else {
								data.append (line + "\n");
							}
						} else if (line.contains ("SearchInAURByDefault")) {
							if (new_conf.lookup_extended ("SearchInAURByDefault", null, out variant)) {
								if (variant.get_boolean ()) {
									data.append ("SearchInAURByDefault\n");
								} else {
									data.append ("#SearchInAURByDefault\n");
								}
								new_conf.remove ("SearchInAURByDefault");
							} else {
								data.append (line + "\n");
							}
						} else if (line.contains ("CheckAURUpdates")) {
							if (new_conf.lookup_extended ("CheckAURUpdates", null, out variant)) {
								if (variant.get_boolean ()) {
									data.append ("CheckAURUpdates\n");
								} else {
									data.append ("#CheckAURUpdates\n");
								}
								new_conf.remove ("CheckAURUpdates");
							} else {
								data.append (line + "\n");
							}
						} else if (line.contains ("NoConfirmBuild")) {
							if (new_conf.lookup_extended ("NoConfirmBuild", null, out variant)) {
								if (variant.get_boolean ()) {
									data.append ("NoConfirmBuild\n");
								} else {
									data.append ("#NoConfirmBuild\n");
								}
								new_conf.remove ("NoConfirmBuild");
							} else {
								data.append (line + "\n");
							}
						} else {
							data.append (line + "\n");
						}
					}
					// delete the file before rewrite it
					file.delete ();
				} catch (GLib.Error e) {
					GLib.stderr.printf("%s\n", e.message);
				}
			} else {
				GLib.stderr.printf ("File '%s' doesn't exist.\n", conf_path);
			}
			// create lines for unexisted options
			if (new_conf.size () != 0) {
				data.append ("\n");
				var iter = HashTableIter<string,Variant> (new_conf);
				unowned string key;
				unowned Variant val;
				while (iter.next (out key, out val)) {
					if (key == "RemoveUnrequiredDeps") {
						if (val.get_boolean ()) {
							data.append ("RemoveUnrequiredDeps\n");
						} else {
							data.append ("#RemoveUnrequiredDeps\n");
						}
					} else if (key == "RefreshPeriod") {
						data.append ("RefreshPeriod = %llu\n".printf (val.get_uint64 ()));
					} else if (key =="NoUpdateHideIcon") {
						if (val.get_boolean ()) {
							data.append ("NoUpdateHideIcon\n");
						} else {
							data.append ("#NoUpdateHideIcon\n");
						}
					} else if (key == "EnableAUR") {
						if (val.get_boolean ()) {
							data.append ("EnableAUR\n");
						} else {
							data.append ("#EnableAUR\n");
						}
					} else if (key == "SearchInAURByDefault") {
						if (val.get_boolean ()) {
							data.append ("SearchInAURByDefault\n");
						} else {
							data.append ("#SearchInAURByDefault\n");
						}
					} else if (key == "CheckAURUpdates") {
						if (val.get_boolean ()) {
							data.append ("CheckAURUpdates\n");
						} else {
							data.append ("#CheckAURUpdates\n");
						}
					} else if (key == "NoConfirmBuild") {
						if (val.get_boolean ()) {
							data.append ("NoConfirmBuild\n");
						} else {
							data.append ("#NoConfirmBuild\n");
						}
					}
				}
			}
			// write the file
			try {
				// creating a DataOutputStream to the file
				var dos = new DataOutputStream (file.create (FileCreateFlags.REPLACE_DESTINATION));
				foreach (unowned string new_line in data) {
					// writing a short string to the stream
					dos.put_string (new_line);
				}
			} catch (GLib.Error e) {
				GLib.stderr.printf("%s\n", e.message);
			}
		}
	}
}
