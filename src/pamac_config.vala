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
		public bool no_update_hide_icon;
		public bool check_aur_updates;
		public bool no_confirm_build;

		public Config (string path) {
			conf_path = path;
			// set default option
			refresh_period = 6;
			reload ();
		}

		public void reload () {
			// set default options
			enable_aur = false;
			recurse = false;
			no_update_hide_icon = false;
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
						splitted = line.split ("=");
						string key = splitted[0].strip ();
						string? val = null;
						if (splitted[1] != null) {
							val = splitted[1].strip ();
						}
						if (key == "RemoveUnrequiredDeps") {
							recurse = true;
						} else if (key == "RefreshPeriod") {
							refresh_period = int.parse (val);
						} else if (key == "NoUpdateHideIcon") {
							no_update_hide_icon = true;
						} else if (key == "EnableAUR") {
							enable_aur = true;
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
			string[] data = {};
			if (file.query_exists ()) {
				try {
					// Open file for reading and wrap returned FileInputStream into a
					// DataInputStream, so we can read line by line
					var dis = new DataInputStream (file.read ());
					string? line;
					// Read lines until end of file (null) is reached
					while ((line = dis.read_line ()) != null) {
						if (line.length == 0) {
							data += "\n";
							continue;
						}
						if (line.contains ("RemoveUnrequiredDeps")) {
							if (new_conf.contains ("RemoveUnrequiredDeps")) {
								bool val = new_conf.get ("RemoveUnrequiredDeps").get_boolean ();
								if (val == true) {
									data += "RemoveUnrequiredDeps\n";
								} else {
									data += "#RemoveUnrequiredDeps\n";
								}
								new_conf.remove ("RemoveUnrequiredDeps");
							} else {
								data += line + "\n";
							}
						} else if (line.contains ("RefreshPeriod")) {
							if (new_conf.contains ("RefreshPeriod")) {
								int val = new_conf.get ("RefreshPeriod").get_int32 ();
								data += "RefreshPeriod = %u\n".printf (val);
								new_conf.remove ("RefreshPeriod");
							} else {
								data += line + "\n";
							}
						} else if (line.contains ("NoUpdateHideIcon")) {
							if (new_conf.contains ("NoUpdateHideIcon")) {
								bool val = new_conf.get ("NoUpdateHideIcon").get_boolean ();
								if (val == true) {
									data += "NoUpdateHideIcon\n";
								} else {
									data += "#NoUpdateHideIcon\n";
								}
								new_conf.remove ("NoUpdateHideIcon");
							} else {
								data += line + "\n";
							}
						} else if (line.contains ("EnableAUR")) {
							if (new_conf.contains ("EnableAUR")) {
								bool val = new_conf.get ("EnableAUR").get_boolean ();
								if (val == true) {
									data += "EnableAUR\n";
								} else {
									data += "#EnableAUR\n";
								}
								new_conf.remove ("EnableAUR");
							} else {
								data += line + "\n";
							}
						} else if (line.contains ("CheckAURUpdates")) {
							if (new_conf.contains ("CheckAURUpdates")) {
								bool val = new_conf.get ("CheckAURUpdates").get_boolean ();
								if (val == true) {
									data += "CheckAURUpdates\n";
								} else {
									data += "#CheckAURUpdates\n";
								}
								new_conf.remove ("CheckAURUpdates");
							} else {
								data += line + "\n";
							}
						} else if (line.contains ("NoConfirmBuild")) {
							if (new_conf.contains ("NoConfirmBuild")) {
								bool val = new_conf.get ("NoConfirmBuild").get_boolean ();
								if (val == true) {
									data += "NoConfirmBuild\n";
								} else {
									data += "#NoConfirmBuild\n";
								}
								new_conf.remove ("NoConfirmBuild");
							} else {
								data += line + "\n";
							}
						} else {
							data += line + "\n";
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
				data += "\n";
				new_conf.foreach ((key, val) => {
					if (key == "RemoveUnrequiredDeps") {
						if (val.get_boolean () == true) {
							data += "RemoveUnrequiredDeps\n";
						} else {
							data += "#RemoveUnrequiredDeps\n";
						}
					} else if (key == "RefreshPeriod") {
						data += "RefreshPeriod = %u\n".printf (val.get_int32 ());
					} else if (key =="NoUpdateHideIcon") {
						if (val.get_boolean () == true) {
							data += "NoUpdateHideIcon\n";
						} else {
							data += "#NoUpdateHideIcon\n";
						}
					} else if (key == "EnableAUR") {
						if (val.get_boolean () == true) {
							data += "EnableAUR\n";
						} else {
							data += "#EnableAUR\n";
						}
					} else if (key == "CheckAURUpdates") {
						if (val.get_boolean () == true) {
							data += "CheckAURUpdates\n";
						} else {
							data += "#CheckAURUpdates\n";
						}
					} else if (key == "NoConfirmBuild") {
						if (val.get_boolean () == true) {
							data += "NoConfirmBuild\n";
						} else {
							data += "#NoConfirmBuild\n";
						}
					}
				});
			}
			// write the file
			try {
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
