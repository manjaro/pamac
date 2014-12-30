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

namespace Alpm {
	public class MirrorsConfig: Object {
		string conf_path;
		string mirrorlists_dir;
		public string choosen_generation_method;
		public string choosen_country;
		public GLib.List<string> countrys;

		public MirrorsConfig (string path) {
			conf_path = path;
			reload ();
		}

		public void reload () {
			// set default options
			choosen_generation_method = "rank";
			choosen_country = dgettext (null, "Worldwide");
			mirrorlists_dir = "/etc/pacman.d/mirrors";
			parse_file (conf_path);
		}

		public void get_countrys () {
			try {
				var directory = GLib.File.new_for_path (mirrorlists_dir);
				var enumerator = directory.enumerate_children (FileAttribute.STANDARD_NAME, 0);
				FileInfo file_info;
				countrys = new GLib.List<string> ();
				while ((file_info = enumerator.next_file ()) != null) {
					countrys.append(file_info.get_name ());
				}
				countrys.sort ((a, b) => {
					return strcmp (a, b);
				});
			} catch (Error e) {
				stderr.printf ("%s\n", e.message);
			}
		}

		public void parse_file (string path) {
			var file = GLib.File.new_for_path (path);
			if (file.query_exists () == false)
				GLib.stderr.printf ("File '%s' doesn't exist.\n", path);
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
						if (_key == "Method")
							choosen_generation_method = _value;
						else if (_key == "OnlyCountry")
							choosen_country = _value;
						else if (_key == "MirrorlistsDir")
							mirrorlists_dir = _value.replace ("\"", "");
					}
				} catch (Error e) {
					GLib.stderr.printf("%s\n", e.message);
				}
			}
		}

		public void write (HashTable<string,Variant> new_conf) {
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
						if (line.contains ("Method")) {
							if (new_conf.contains ("Method")) {
								string _value = new_conf.get ("Method").get_string ();
								data += "Method=%s\n".printf (_value);
							} else
								data += line + "\n";
						} else if (line.contains ("OnlyCountry")) {
							if (new_conf.contains ("OnlyCountry")) {
								string _value = new_conf.get ("OnlyCountry").get_string ();
								if (_value == dgettext (null, "Worldwide"))
									data += "#%s\n".printf (line);
								else
									data += "OnlyCountry=%s\n".printf (_value);
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
	}
}
