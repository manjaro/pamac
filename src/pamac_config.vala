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

namespace Pamac {
	public class Config: Object {
		string conf_path;
		public int refresh_period;
		public bool enable_aur;
		public bool recurse;
		public bool noupdate_hide_icon;

		public Config (string path) {
			conf_path = path;
			// set default option
			refresh_period = 4;
			reload ();
		}

		public void reload () {
			// set default options
			enable_aur = false;
			recurse = false;
			noupdate_hide_icon = false;
			parse_file (conf_path);
		}

		public void parse_file (string path) {
			var file = GLib.File.new_for_path (path);
			if (file.query_exists () == false) {
				GLib.stderr.printf ("File '%s' doesn't exist.\n", path);
			} else {
				try {
					// Open file for reading and wrap returned FileInputStream into a
					// DataInputStream, so we can read line by line
					var dis = new DataInputStream (file.read ());
					string line;
					// Read lines until end of file (null) is reached
					while ((line = dis.read_line (null)) != null) {
						line = line.strip ();
						if (line.length == 0) {
							continue;
						}
						if (line[0] == '#') {
							continue;
						}
						string[] splitted = line.split ("=");
						string _key = splitted[0].strip ();
						string _value = null;
						if (splitted[1] != null) {
							_value = splitted[1].strip ();
						}
						if (_key == "RefreshPeriod") {
							refresh_period = int.parse (_value);
						} else if (_key == "EnableAUR") {
							enable_aur = true;
						} else if (_key == "RemoveUnrequiredDeps") {
							recurse = true;
						} else if (_key == "NoUpdateHideIcon") {
							noupdate_hide_icon = true;
						}
					}
				} catch (GLib.Error e) {
					GLib.stderr.printf("%s\n", e.message);
				}
			}
		}

		public void write (HashTable<string,Variant> new_conf) {
			var file = GLib.File.new_for_path (conf_path);
			if (file.query_exists () == false) {
				GLib.stderr.printf ("File '%s' doesn't exist.\n", conf_path);
			} else {
				try {
					// Open file for reading and wrap returned FileInputStream into a
					// DataInputStream, so we can read line by line
					var dis = new DataInputStream (file.read ());
					string line;
					string[] data = {};
					// Read lines until end of file (null) is reached
					while ((line = dis.read_line (null)) != null) {
						if (line.length == 0) {
							continue;
						}
						if (line.contains ("RefreshPeriod")) {
							if (new_conf.contains ("RefreshPeriod")) {
								int _value = new_conf.get ("RefreshPeriod").get_int32 ();
								data += "RefreshPeriod = %u\n".printf (_value);
							} else {
								data += line + "\n";
							}
						} else if (line.contains ("EnableAUR")) {
							if (new_conf.contains ("EnableAUR")) {
								bool _value = new_conf.get ("EnableAUR").get_boolean ();
								if (_value == true) {
									data += "EnableAUR\n";
								} else {
									data += "#EnableAUR\n";
								}
							} else {
								data += line + "\n";
							}
						} else if (line.contains ("RemoveUnrequiredDeps")) {
							if (new_conf.contains ("RemoveUnrequiredDeps")) {
								bool _value = new_conf.get ("RemoveUnrequiredDeps").get_boolean ();
								if (_value == true) {
									data += "RemoveUnrequiredDeps\n";
								} else {
									data += "#RemoveUnrequiredDeps\n";
								}
							} else {
								data += line + "\n";
							}
						} else if (line.contains ("NoUpdateHideIcon")) {
							if (new_conf.contains ("NoUpdateHideIcon")) {
								bool _value = new_conf.get ("NoUpdateHideIcon").get_boolean ();
								if (_value == true) {
									data += "NoUpdateHideIcon\n";
								} else {
									data += "#NoUpdateHideIcon\n";
								}
							} else {
								data += line + "\n";
							}
						} else {
							data += line + "\n";
						}
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
	}
}
