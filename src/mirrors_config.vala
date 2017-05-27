/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2017 Guillaume Benoit <guillaume@manjaro.org>
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
	class MirrorsConfig {
		string conf_path;
		GLib.List<string> _countries ;

		public string mirrorlists_dir { get; private set; }
		public string choosen_generation_method { get; private set; }
		public string choosen_country { get; private set; }
		public unowned GLib.List<string> countries {
			get {
				try {
					var file = File.new_for_path ("/usr/bin/pacman-mirrors");
					if (file.query_exists ()) {
						string countries_str;
						int status;
						Process.spawn_command_line_sync ("pacman-mirrors -l",
												out countries_str,
												null,
												out status);
						_countries = new GLib.List<string> ();
						if (status == 0) {
							foreach (unowned string country in countries_str.split ("\n")) {
							_countries.append (country);
							}
						}
					} else {
						var directory = GLib.File.new_for_path (mirrorlists_dir);
						var enumerator = directory.enumerate_children (FileAttribute.STANDARD_NAME, 0);
						FileInfo file_info;
						_countries = new GLib.List<string> ();
						while ((file_info = enumerator.next_file ()) != null) {
							_countries.append(file_info.get_name ());
						}
						_countries.sort (strcmp);
					}
				} catch (SpawnError e) {
					stdout.printf ("Error: %s\n", e.message);
				}
				return _countries;
			}
		}

		public MirrorsConfig (string path) {
			conf_path = path;
			reload ();
		}

		public void reload () {
			// set default options
			choosen_generation_method = "rank";
			choosen_country = "ALL";
			mirrorlists_dir = "/etc/pacman.d/mirrors";
			parse_file (conf_path);
		}

		void parse_file (string path) {
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
						unowned string? val = null;
						if (splitted.length == 2) {
							val = splitted[1]._strip ();
						}
						if (key == "Method") {
							choosen_generation_method = val;
						} else if (key == "OnlyCountry") {
							choosen_country = val;
						}
					}
				} catch (Error e) {
					GLib.stderr.printf("%s\n", e.message);
				}
			} else {
				GLib.stderr.printf ("File '%s' doesn't exist.\n", path);
			}
		}

		public void write (HashTable<string,Variant> new_conf) {
			var file = GLib.File.new_for_path (conf_path);
			if (file.query_exists ()) {
				try {
					// Open file for reading and wrap returned FileInputStream into a
					// DataInputStream, so we can read line by line
					var dis = new DataInputStream (file.read ());
					string? line;
					var data = new GLib.List<string> ();
					// Read lines until end of file (null) is reached
					while ((line = dis.read_line ()) != null) {
						if (line.length == 0) {
							data.append ("\n");
							continue;
						}
						unowned Variant variant;
						if (line.contains ("Method")) {
							if (new_conf.lookup_extended ("Method", null, out variant)) {
								data.append ("Method = %s\n".printf (variant.get_string ()));
							} else {
								data.append (line + "\n");
							}
						} else if (line.contains ("OnlyCountry")) {
							if (new_conf.lookup_extended ("OnlyCountry", null, out variant)) {
								if (variant.get_string () == "ALL") {
									data.append ("#%s\n".printf (line));
								} else {
									data.append ("OnlyCountry = %s\n".printf (variant.get_string ()));
								}
							} else {
								data.append (line + "\n");
							}
						} else {
							data.append (line + "\n");
						}
					}
					// delete the file before rewrite it
					file.delete ();
					// creating a DataOutputStream to the file
					var dos = new DataOutputStream (file.create (FileCreateFlags.REPLACE_DESTINATION));
					foreach (unowned string new_line in data) {
						// writing a short string to the stream
						dos.put_string (new_line);
					}
				} catch (GLib.Error e) {
					GLib.stderr.printf("%s\n", e.message);
				}
			} else {
				GLib.stderr.printf ("File '%s' doesn't exist.\n", file.get_path ());
			}
		}
	}
}
