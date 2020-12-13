/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2020 Guillaume Benoit <guillaume@manjaro.org>
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
		public string conf_path { get; construct; }
		public bool support_snap { get; set; }
		public bool enable_snap { get; set; }
		PluginLoader<SnapPlugin> snap_plugin_loader;
		public bool support_flatpak{ get; set; }
		public bool enable_flatpak { get; set; }
		PluginLoader<FlatpakPlugin> flatpak_plugin_loader;
		public string aur_build_dir { get; set; }
		public uint64 max_parallel_downloads { get; set; }

		internal AlpmConfig alpm_config { get; private set; }

		public Config (string conf_path) {
			Object(conf_path: conf_path);
		}

		construct {
			//get environment variables
			alpm_config = new AlpmConfig ("/etc/pacman.conf");
			// load snap plugin
			support_snap = false;
			snap_plugin_loader = new PluginLoader<SnapPlugin> ("pamac-snap");
			if (snap_plugin_loader.load ()) {
				support_snap = true;
			}
			// load snap plugin
			support_flatpak = false;
			flatpak_plugin_loader = new PluginLoader<FlatpakPlugin> ("pamac-flatpak");
			if (flatpak_plugin_loader.load ()) {
				support_flatpak = true;
			}
			reload ();
		}

		public void reload () {
			enable_snap = false;
			enable_flatpak = false;
			aur_build_dir = "/var/tmp";
			max_parallel_downloads = 1;
			parse_file (conf_path);
			// limited max_parallel_downloads
			if (max_parallel_downloads > 10) {
				max_parallel_downloads = 10;
			}
			if (!support_snap) {
				enable_snap = false;
			}
			if (!support_flatpak) {
				enable_flatpak = false;
			}
		}

		internal SnapPlugin? get_snap_plugin () {
			if (support_snap) {
				return snap_plugin_loader.new_object ();
			}
			return null;
		}

		internal FlatpakPlugin? get_flatpak_plugin () {
			if (support_flatpak) {
				return flatpak_plugin_loader.new_object ();
			}
			return null;
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
						if (key == "BuildDirectory") {
							if (splitted.length == 2) {
								aur_build_dir = splitted[1]._strip ();
							}
						} else if (key == "EnableSnap") {
							enable_snap = true;
						} else if (key == "EnableFlatpak") {
							enable_flatpak = true;
						} else if (key == "MaxParallelDownloads") {
							if (splitted.length == 2) {
								unowned string val = splitted[1]._strip ();
								max_parallel_downloads = uint64.parse (val);
							}
						}
					}
				} catch (GLib.Error e) {
					warning ("parse_file: %s", e.message);
				}
			} else {
				warning ("File '%s' doesn't exist.", path);
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
						if (line.contains ("RemoveUnrequiredDeps")) {
							if (new_conf.lookup_extended ("RemoveUnrequiredDeps", null, out variant)) {
								if (variant.get_boolean ()) {
									data.append ("RemoveUnrequiredDeps\n");
								} else {
									data.append ("#RemoveUnrequiredDeps\n");
								}
								new_conf.remove ("RemoveUnrequiredDeps");
							} else {
								data.append (line);
								data.append ("\n");
							}
						} else if (line.contains ("EnableDowngrade")) {
							if (new_conf.lookup_extended ("EnableDowngrade", null, out variant)) {
								if (variant.get_boolean ()) {
									data.append ("EnableDowngrade\n");
								} else {
									data.append ("#EnableDowngrade\n");
								}
								new_conf.remove ("EnableDowngrade");
							} else {
								data.append (line);
								data.append ("\n");
							}
						} else if (line.contains ("SimpleInstall")) {
							if (new_conf.lookup_extended ("SimpleInstall", null, out variant)) {
								if (variant.get_boolean ()) {
									data.append ("SimpleInstall\n");
								} else {
									data.append ("#SimpleInstall\n");
								}
								new_conf.remove ("SimpleInstall");
							} else {
								data.append (line);
								data.append ("\n");
							}
						} else if (line.contains ("RefreshPeriod")) {
							if (new_conf.lookup_extended ("RefreshPeriod", null, out variant)) {
								data.append ("RefreshPeriod = %llu\n".printf (variant.get_uint64 ()));
								new_conf.remove ("RefreshPeriod");
							} else {
								data.append (line);
								data.append ("\n");
							}
						} else if (line.contains ("KeepNumPackages")) {
							if (new_conf.lookup_extended ("KeepNumPackages", null, out variant)) {
								data.append ("KeepNumPackages = %llu\n".printf (variant.get_uint64 ()));
								new_conf.remove ("KeepNumPackages");
							} else {
								data.append (line);
								data.append ("\n");
							}
						} else if (line.contains ("OnlyRmUninstalled")) {
							if (new_conf.lookup_extended ("OnlyRmUninstalled", null, out variant)) {
								if (variant.get_boolean ()) {
									data.append ("OnlyRmUninstalled\n");
								} else {
									data.append ("#OnlyRmUninstalled\n");
								}
								new_conf.remove ("OnlyRmUninstalled");
							} else {
								data.append (line);
								data.append ("\n");
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
								data.append (line);
								data.append ("\n");
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
								data.append (line);
								data.append ("\n");
							}
						} else if (line.contains ("KeepBuiltPkgs")) {
							if (new_conf.lookup_extended ("KeepBuiltPkgs", null, out variant)) {
								if (variant.get_boolean ()) {
									data.append ("KeepBuiltPkgs\n");
								} else {
									data.append ("#KeepBuiltPkgs\n");
								}
								new_conf.remove ("KeepBuiltPkgs");
							} else {
								data.append (line);
								data.append ("\n");
							}
						} else if (line.contains ("EnableSnap")) {
							if (new_conf.lookup_extended ("EnableSnap", null, out variant)) {
								if (variant.get_boolean ()) {
									data.append ("EnableSnap\n");
								} else {
									data.append ("#EnableSnap\n");
								}
								new_conf.remove ("EnableSnap");
							} else {
								data.append (line);
								data.append ("\n");
							}
						} else if (line.contains ("EnableFlatpak")) {
							if (new_conf.lookup_extended ("EnableFlatpak", null, out variant)) {
								if (variant.get_boolean ()) {
									data.append ("EnableFlatpak\n");
								} else {
									data.append ("#EnableFlatpak\n");
								}
								new_conf.remove ("EnableFlatpak");
							} else {
								data.append (line);
								data.append ("\n");
							}
						} else if (line.contains ("CheckFlatpakUpdates")) {
							if (new_conf.lookup_extended ("CheckFlatpakUpdates", null, out variant)) {
								if (variant.get_boolean ()) {
									data.append ("CheckFlatpakUpdates\n");
								} else {
									data.append ("#CheckFlatpakUpdates\n");
								}
								new_conf.remove ("CheckFlatpakUpdates");
							} else {
								data.append (line);
								data.append ("\n");
							}
						} else if (line.contains ("BuildDirectory")) {
							if (new_conf.lookup_extended ("BuildDirectory", null, out variant)) {
								data.append ("BuildDirectory = %s\n".printf (variant.get_string ()));
								new_conf.remove ("BuildDirectory");
							} else {
								data.append (line);
								data.append ("\n");
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
								data.append (line);
								data.append ("\n");
							}
						} else if (line.contains ("CheckAURVCSUpdates")) {
							if (new_conf.lookup_extended ("CheckAURVCSUpdates", null, out variant)) {
								if (variant.get_boolean ()) {
									data.append ("CheckAURVCSUpdates\n");
								} else {
									data.append ("#CheckAURVCSUpdates\n");
								}
								new_conf.remove ("CheckAURVCSUpdates");
							} else {
								data.append (line);
								data.append ("\n");
							}
						} else if (line.contains ("DownloadUpdates")) {
							if (new_conf.lookup_extended ("DownloadUpdates", null, out variant)) {
								if (variant.get_boolean ()) {
									data.append ("DownloadUpdates\n");
								} else {
									data.append ("#DownloadUpdates\n");
								}
								new_conf.remove ("DownloadUpdates");
							} else {
								data.append (line);
								data.append ("\n");
							}
						} else if (line.contains ("MaxParallelDownloads")) {
							if (new_conf.lookup_extended ("MaxParallelDownloads", null, out variant)) {
								data.append ("MaxParallelDownloads = %llu\n".printf (variant.get_uint64 ()));
								new_conf.remove ("MaxParallelDownloads");
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
				warning ("File '%s' doesn't exist", conf_path);
			}
			// create lines for unexisted options
			if (new_conf.size () != 0) {
				data.append ("\n");
				var iter = HashTableIter<string, Variant> (new_conf);
				unowned string key;
				unowned Variant val;
				while (iter.next (out key, out val)) {
					if (key == "RemoveUnrequiredDeps") {
						if (val.get_boolean ()) {
							data.append ("RemoveUnrequiredDeps\n\n");
						} else {
							data.append ("#RemoveUnrequiredDeps\n\n");
						}
					} else if (key == "EnableDowngrade") {
						if (val.get_boolean ()) {
							data.append ("EnableDowngrade\n\n");
						} else {
							data.append ("#EnableDowngrade\n\n");
						}
					} else if (key == "SimpleInstall") {
						if (val.get_boolean ()) {
							data.append ("SimpleInstall\n\n");
						} else {
							data.append ("#SimpleInstall\n\n");
						}
					} else if (key == "RefreshPeriod") {
						data.append ("RefreshPeriod = %llu\n\n".printf (val.get_uint64 ()));
					} else if (key == "KeepNumPackages") {
						data.append ("KeepNumPackages = %llu\n\n".printf (val.get_uint64 ()));
					} else if (key == "OnlyRmUninstalled") {
						if (val.get_boolean ()) {
							data.append ("OnlyRmUninstalled\n\n");
						} else {
							data.append ("#OnlyRmUninstalled\n\n");
						}
					} else if (key =="NoUpdateHideIcon") {
						if (val.get_boolean ()) {
							data.append ("NoUpdateHideIcon\n\n");
						} else {
							data.append ("#NoUpdateHideIcon\n\n");
						}
					} else if (key == "EnableAUR") {
						if (val.get_boolean ()) {
							data.append ("EnableAUR\n\n");
						} else {
							data.append ("#EnableAUR\n\n");
						}
					} else if (key == "KeepBuiltPkgs") {
						if (val.get_boolean ()) {
							data.append ("KeepBuiltPkgs\n\n");
						} else {
							data.append ("#KeepBuiltPkgs\n\n");
						}
					} else if (key == "EnableSnap") {
						if (val.get_boolean ()) {
							data.append ("EnableSnap\n\n");
						} else {
							data.append ("#EnableSnap\n\n");
						}
					} else if (key == "EnableFlatpak") {
						if (val.get_boolean ()) {
							data.append ("EnableFlatpak\n\n");
						} else {
							data.append ("#EnableFlatpak\n\n");
						}
					} else if (key == "CheckFlatpakUpdates") {
						if (val.get_boolean ()) {
							data.append ("CheckFlatpakUpdates\n\n");
						} else {
							data.append ("#CheckFlatpakUpdates\n\n");
						}
					} else if (key == "BuildDirectory") {
						data.append ("BuildDirectory = %s\n\n".printf (val.get_string ()));
					} else if (key == "CheckAURUpdates") {
						if (val.get_boolean ()) {
							data.append ("CheckAURUpdates\n\n");
						} else {
							data.append ("#CheckAURUpdates\n\n");
						}
					} else if (key == "CheckAURVCSUpdates") {
						if (val.get_boolean ()) {
							data.append ("CheckAURVCSUpdates\n\n");
						} else {
							data.append ("#CheckAURVCSUpdates\n\n");
						}
					} else if (key == "DownloadUpdates") {
						if (val.get_boolean ()) {
							data.append ("DownloadUpdates\n\n");
						} else {
							data.append ("#DownloadUpdates\n\n");
						}
					} else if (key == "MaxParallelDownloads") {
						data.append ("MaxParallelDownloads = %llu\n\n".printf (val.get_uint64 ()));
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
