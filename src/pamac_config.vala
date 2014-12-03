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

namespace Pamac {
	public class Config: Object {
		string conf_path;
		public uint64 refresh_period;
		public bool enable_aur;
		public bool recurse;

		public Config (string path) {
			conf_path = path;
			// set default options
			refresh_period = 4;
			enable_aur = false;
			recurse = false;
			// parse conf file
			parse_include_file (conf_path);
		}

		public void parse_include_file (string path) {
			var file = GLib.File.new_for_path (path);
			if (file.query_exists () == false)
				GLib.stderr.printf ("File '%s' doesn't exist.\n", file.get_path ());
			else {
				try {
					// Open file for reading and wrap returned FileInputStream into a
					// DataInputStream, so we can read line by line
					var dis = new DataInputStream (file.read ());
					string line;
					// Read lines until end of file (null) is reached
					while ((line = dis.read_line (null)) != null) {
						line = line.strip ();
						if (line.length == 0) continue;
						if (line[0] == '#') continue;
						string[] splitted = line.split ("=");
						string _key = splitted[0].strip ();
						string _value = null;
						if (splitted[1] != null)
							_value = splitted[1].strip ();
						if (_key == "RefreshPeriod")
							refresh_period = uint64.parse (_value);
						else if (_key == "EnableAUR")
							enable_aur = true;
						else if (_key == "RemoveUnrequiredDeps")
							recurse = true;
					}
				} catch (GLib.Error e) {
					GLib.stderr.printf("%s\n", e.message);
				}
			}
		}

		public void write (HashTable<string,string> new_conf) {
			var file = GLib.File.new_for_path (conf_path);
			if (file.query_exists () == false)
				GLib.stderr.printf ("File '%s' doesn't exist.\n", file.get_path ());
			else {
				try {
					// Open file for reading and wrap returned FileInputStream into a
					// DataInputStream, so we can read line by line
					var dis = new DataInputStream (file.read ());
					string line;
					string[] data = {};
					// Read lines until end of file (null) is reached
					while ((line = dis.read_line (null)) != null) {
						if (line.contains ("RefreshPeriod")) {
							if (new_conf.contains ("RefreshPeriod")) {
								string _value = new_conf.get ("RefreshPeriod");
								data += "RefreshPeriod = %s\n".printf (_value);
								refresh_period = uint64.parse (_value);
							} else
								data += line + "\n";
						} else if (line.contains ("EnableAUR")) {
							if (new_conf.contains ("EnableAUR")) {
								bool _value = bool.parse (new_conf.get ("EnableAUR"));
								if (_value == true)
									data += "EnableAUR\n";
								else
									data += "#EnableAUR\n";
								enable_aur = _value;
							} else
								data += line + "\n";
						} else if (line.contains ("RemoveUnrequiredDeps")) {
							if (new_conf.contains ("RemoveUnrequiredDeps")) {
								bool _value = bool.parse (new_conf.get ("RemoveUnrequiredDeps"));
								if (_value == true)
									data += "RemoveUnrequiredDeps\n";
								else
									data += "#RemoveUnrequiredDeps\n";
								enable_aur = _value;
							} else
								data += line + "\n";
						} else
							data += line + "\n";
					}
					// delete the file before rewrite it
					file.delete ();
					// creating a DataOutputStream to the file
					var dos = new DataOutputStream (file.create (FileCreateFlags.REPLACE_DESTINATION));
					foreach (string new_line in data) {
						// writing a short string to the stream
						dos.put_string (new_line);
					}
				} catch (GLib.Error e) {
					GLib.stderr.printf("%s\n", e.message);
				}
			}
		}

		public void reload () {
			enable_aur = false;
			recurse = false;
			parse_include_file (conf_path);
		}
	}
}
