/*
 *  pamac-vala
 *
 *  Copyright (C) 2019-2021 Guillaume Benoit <guillaume@manjaro.org>
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
	public class LocalConfig: Object {
		public string conf_path { get; construct; }
		public uint64 width { get; private set; }
		public uint64 height { get; private set; }
		public bool maximized { get; private set; }
		public bool software_mode { get; set; }

		public LocalConfig (string conf_path) {
			Object (conf_path: conf_path);
		}

		construct {
			reload ();
		}

		public void reload () {
			// set default options
			width = 950;
			height = 550;
			maximized = false;
			software_mode = false;
			parse_file ();
		}

		void parse_file () {
			var file = GLib.File.new_for_path (conf_path);
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
						if (key == "width") {
							if (splitted.length == 2) {
								unowned string val = splitted[1]._strip ();
								width = uint64.parse (val);
							}
						} else if (key == "height") {
							if (splitted.length == 2) {
								unowned string val = splitted[1]._strip ();
								height = uint64.parse (val);
							}
						} else if (key == "maximized") {
							if (splitted.length == 2) {
								unowned string val = splitted[1]._strip ();
								maximized = bool.parse (val);
							}
						} else if (key == "software_mode") {
							if (splitted.length == 2) {
								unowned string val = splitted[1]._strip ();
								software_mode = bool.parse (val);
							}
						}
					}
				} catch (Error e) {
					warning (e.message);
				}
			}
		}

		public void write (HashTable<string,Variant> new_conf) {
			var file = GLib.File.new_for_path (conf_path);
			var data = new StringBuilder();
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
						if (line.contains ("width")) {
							if (new_conf.lookup_extended ("width", null, out variant)) {
								data.append ("width = %llu\n".printf (variant.get_uint64 ()));
								new_conf.remove ("width");
							} else {
								data.append (line);
								data.append ("\n");
							}
						} else if (line.contains ("height")) {
							if (new_conf.lookup_extended ("height", null, out variant)) {
								data.append ("height = %llu\n".printf (variant.get_uint64 ()));
								new_conf.remove ("height");
							} else {
								data.append (line);
								data.append ("\n");
							}
						} else if (line.contains ("maximized")) {
							if (new_conf.lookup_extended ("maximized", null, out variant)) {
								if (variant.get_boolean ()) {
									data.append ("maximized = true\n");
								} else {
									data.append ("maximized = false\n");
								}
								new_conf.remove ("maximized");
							} else {
								data.append (line);
								data.append ("\n");
							}
						} else if (line.contains ("software_mode")) {
							if (new_conf.lookup_extended ("software_mode", null, out variant)) {
								if (variant.get_boolean ()) {
									data.append ("software_mode = true\n");
								} else {
									data.append ("software_mode = false\n");
								}
								new_conf.remove ("software_mode");
							} else {
								data.append (line);
								data.append ("\n");
							}
						} else {
							data.append (line);
							data.append ("\n");
						}
					}
					// delete the file before rewrite it
					file.delete ();
				} catch (Error e) {
					warning (e.message);
				}
			} else {
				try {
					File? parent = file.get_parent ();
					if (parent != null && !parent.query_exists ()) {
						parent.make_directory_with_parents ();
					}
				} catch (Error e) {
					warning (e.message);
				}
			}
			// create lines for unexisted options
			if (new_conf.size () != 0) {
				var iter = HashTableIter<string,Variant> (new_conf);
				unowned string key;
				unowned Variant val;
				while (iter.next (out key, out val)) {
					if (key == "width") {
						data.append ("width = %llu\n".printf (val.get_uint64 ()));
					} else if (key == "height") {
						data.append ("height = %llu\n".printf (val.get_uint64 ()));
					} else if (key == "maximized") {
						if (val.get_boolean ()) {
							data.append ("maximized = true\n");
						} else {
							data.append ("maximized = false\n");
						}
					} else if (key == "software_mode") {
						if (val.get_boolean ()) {
							data.append ("software_mode = true\n");
						} else {
							data.append ("software_mode = false\n");
						}
					}
				}
			}
			// write the file
			try {
				// creating a DataOutputStream to the file
				var dos = new DataOutputStream (file.create (FileCreateFlags.REPLACE_DESTINATION));
				dos.put_string (data.str);
			} catch (Error e) {
				warning (e.message);
			}
		}
	}
}
