/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2019 Guillaume Benoit <guillaume@manjaro.org>
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
		HashTable<string,string> _environment_variables;
		Daemon system_daemon;
		MainLoop loop;

		public string conf_path { get; construct; }
		public bool recurse { get; set; }
		public bool keep_built_pkgs { get; set; }
		public bool enable_downgrade { get; set; }
		public uint64 refresh_period { get; set; }
		public bool no_update_hide_icon { get; set; }
		public bool enable_aur { get; set; }
		#if ENABLE_SNAP
		public bool support_snap { get; set; }
		public bool enable_snap { get; set; }
		PluginLoader<SnapPlugin> snap_plugin_loader;
		#endif
		public string aur_build_dir { get; set; }
		public bool check_aur_updates { get; set; }
		public bool check_aur_vcs_updates { get; set; }
		public bool download_updates { get; set; }
		public uint64 max_parallel_downloads { get; set; }
		public uint64 clean_keep_num_pkgs { get;  set; }
		public bool clean_rm_only_uninstalled { get; set; }
		public unowned HashTable<string,string> environment_variables {
			get {
				return _environment_variables;
			}
		}

		public Config (string conf_path) {
			Object(conf_path: conf_path);
		}

		construct {
			//get environment variables
			_environment_variables = new HashTable<string,string> (str_hash, str_equal);
			var utsname = Posix.utsname();
			_environment_variables.insert ("HTTP_USER_AGENT", "pamac (%s %s)".printf (utsname.sysname, utsname.machine));
			unowned string? variable = Environment.get_variable ("http_proxy");
			if (variable != null) {
				_environment_variables.insert ("http_proxy", variable);
			}
			variable = Environment.get_variable ("https_proxy");
			if (variable != null) {
				_environment_variables.insert ("https_proxy", variable);
			}
			variable = Environment.get_variable ("ftp_proxy");
			if (variable != null) {
				_environment_variables.insert ("ftp_proxy", variable);
			}
			variable = Environment.get_variable ("socks_proxy");
			if (variable != null) {
				_environment_variables.insert ("socks_proxy", variable);
			}
			variable = Environment.get_variable ("no_proxy");
			if (variable != null) {
				_environment_variables.insert ("no_proxy", variable);
			}
			// set default option
			refresh_period = 6;
			#if ENABLE_SNAP
			// load snap plugin
			support_snap = false;
			snap_plugin_loader = new PluginLoader<SnapPlugin> ("pamac-snap");
			if (snap_plugin_loader.load ()) {
				support_snap = true;
			}
			#endif
			reload ();
		}

		public void reload () {
			// set default options
			recurse = false;
			keep_built_pkgs = false;
			enable_downgrade = false;
			refresh_period = 6;
			no_update_hide_icon = false;
			enable_aur = false;
			#if ENABLE_SNAP
			enable_snap = false;
			#endif
			aur_build_dir = "/var/tmp";
			check_aur_updates = false;
			check_aur_vcs_updates = false;
			download_updates = false;
			max_parallel_downloads = 1;
			clean_keep_num_pkgs = 3;
			clean_rm_only_uninstalled = false;
			parse_file (conf_path);
			if (aur_build_dir == "/var/tmp") {
				aur_build_dir = Path.build_path ("/", aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()));
			} else {
				aur_build_dir = Path.build_path ("/", aur_build_dir, "pamac-build");
			}
			if (enable_aur == false) {
				check_aur_updates = false;
				check_aur_vcs_updates = false;
			} else if (check_aur_updates == false) {
				check_aur_vcs_updates = false;
			}
			// limited max_parallel_downloads
			if (max_parallel_downloads > 10) {
				max_parallel_downloads = 10;
			}
			// check updates at least once a week
			if (refresh_period > 168) {
				refresh_period = 168;
			}
			#if ENABLE_SNAP
			if (!support_snap) {
				enable_snap = false;
			}
			#endif
		}

		#if ENABLE_SNAP
		public SnapPlugin? get_snap_plugin () {
			if (support_snap) {
				return snap_plugin_loader.new_object ();
			}
			return null;
		}
		#endif

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
						if (key == "RemoveUnrequiredDeps") {
							recurse = true;
						} else if (key == "EnableDowngrade") {
							enable_downgrade = true;
						} else if (key == "RefreshPeriod") {
							if (splitted.length == 2) {
								unowned string val = splitted[1]._strip ();
								refresh_period = uint64.parse (val);
							}
						} else if (key == "KeepNumPackages") {
							if (splitted.length == 2) {
								unowned string val = splitted[1]._strip ();
								clean_keep_num_pkgs = uint64.parse (val);
							}
						} else if (key == "OnlyRmUninstalled") {
							clean_rm_only_uninstalled = true;
						} else if (key == "NoUpdateHideIcon") {
							no_update_hide_icon = true;
						} else if (key == "EnableAUR") {
							enable_aur = true;
						} else if (key == "KeepBuiltPkgs") {
							keep_built_pkgs = true;
						#if ENABLE_SNAP
						} else if (key == "EnableSnap") {
							enable_snap = true;
						#endif
						} else if (key == "BuildDirectory") {
							if (splitted.length == 2) {
								aur_build_dir = splitted[1]._strip ();
							}
						} else if (key == "CheckAURUpdates") {
							check_aur_updates = true;
						} else if (key == "CheckAURVCSUpdates") {
							check_aur_vcs_updates = true;
						} else if (key == "DownloadUpdates") {
							download_updates = true;
						} else if (key == "MaxParallelDownloads") {
							if (splitted.length == 2) {
								unowned string val = splitted[1]._strip ();
								max_parallel_downloads = uint64.parse (val);
							}
						}
					}
				} catch (GLib.Error e) {
					GLib.stderr.printf("%s\n", e.message);
				}
			} else {
				GLib.stderr.printf ("File '%s' doesn't exist.\n", path);
			}
		}

		public void save () {
			if (system_daemon == null) {
				loop = new MainLoop ();
				try {
					system_daemon = Bus.get_proxy_sync (BusType.SYSTEM, "org.manjaro.pamac.daemon", "/org/manjaro/pamac/daemon");
					system_daemon.write_pamac_config_finished.connect (() => { loop.quit (); });
				} catch (Error e) {
					critical ("save pamac config error: %s\n", e.message);
				}
			}
			var new_pamac_conf = new HashTable<string,Variant> (str_hash, str_equal);
			new_pamac_conf.insert ("RemoveUnrequiredDeps", new Variant.boolean (recurse));
			new_pamac_conf.insert ("RefreshPeriod", new Variant.uint64 (refresh_period));
			new_pamac_conf.insert ("NoUpdateHideIcon", new Variant.boolean (no_update_hide_icon));
			new_pamac_conf.insert ("DownloadUpdates", new Variant.boolean (download_updates));
			new_pamac_conf.insert ("EnableDowngrade", new Variant.boolean (enable_downgrade));
			new_pamac_conf.insert ("MaxParallelDownloads", new Variant.uint64 (max_parallel_downloads));
			new_pamac_conf.insert ("KeepNumPackages", new Variant.uint64 (clean_keep_num_pkgs));
			new_pamac_conf.insert ("OnlyRmUninstalled", new Variant.boolean (clean_rm_only_uninstalled));
			new_pamac_conf.insert ("EnableAUR", new Variant.boolean (enable_aur));
			new_pamac_conf.insert ("KeepBuiltPkgs", new Variant.boolean (keep_built_pkgs));
			new_pamac_conf.insert ("CheckAURUpdates", new Variant.boolean (check_aur_updates));
			new_pamac_conf.insert ("CheckAURVCSUpdates", new Variant.boolean (check_aur_vcs_updates));
			string new_aur_build_dir = Path.get_dirname (aur_build_dir);
			new_pamac_conf.insert ("BuildDirectory", new Variant.string (new_aur_build_dir));
			#if ENABLE_SNAP
			new_pamac_conf.insert ("EnableSnap", new Variant.boolean (enable_snap));
			#endif
			try {
				system_daemon.start_write_pamac_config (new_pamac_conf);
				loop.run ();
			} catch (Error e) {
				critical ("save pamac config error: %s\n", e.message);
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
						#if ENABLE_SNAP
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
						#endif
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
					} else if (key == "EnableDowngrade") {
						if (val.get_boolean ()) {
							data.append ("EnableDowngrade\n");
						} else {
							data.append ("#EnableDowngrade\n");
						}
					} else if (key == "RefreshPeriod") {
						data.append ("RefreshPeriod = %llu\n".printf (val.get_uint64 ()));
					} else if (key == "KeepNumPackages") {
						data.append ("KeepNumPackages = %llu\n".printf (val.get_uint64 ()));
					} else if (key == "OnlyRmUninstalled") {
						if (val.get_boolean ()) {
							data.append ("OnlyRmUninstalled\n");
						} else {
							data.append ("#OnlyRmUninstalled\n");
						}
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
					} else if (key == "KeepBuiltPkgs") {
						if (val.get_boolean ()) {
							data.append ("KeepBuiltPkgs\n");
						} else {
							data.append ("#KeepBuiltPkgs\n");
						}
					#if ENABLE_SNAP
					} else if (key == "EnableSnap") {
						if (val.get_boolean ()) {
							data.append ("EnableSnap\n");
						} else {
							data.append ("#EnableSnap\n");
						}
					#endif
					} else if (key == "BuildDirectory") {
						data.append ("BuildDirectory = %s\n".printf (val.get_string ()));
					} else if (key == "CheckAURUpdates") {
						if (val.get_boolean ()) {
							data.append ("CheckAURUpdates\n");
						} else {
							data.append ("#CheckAURUpdates\n");
						}
					} else if (key == "CheckAURVCSUpdates") {
						if (val.get_boolean ()) {
							data.append ("CheckAURVCSUpdates\n");
						} else {
							data.append ("#CheckAURVCSUpdates\n");
						}
					} else if (key == "DownloadUpdates") {
						if (val.get_boolean ()) {
							data.append ("DownloadUpdates\n");
						} else {
							data.append ("#DownloadUpdates\n");
						}
					} else if (key == "MaxParallelDownloads") {
						data.append ("MaxParallelDownloads = %llu\n".printf (val.get_uint64 ()));
					}
				}
			}
			// write the file
			try {
				// creating a DataOutputStream to the file
				var dos = new DataOutputStream (file.create (FileCreateFlags.REPLACE_DESTINATION));
				dos.put_string (data.str);
			} catch (GLib.Error e) {
				GLib.stderr.printf("%s\n", e.message);
			}
		}
	}
}
