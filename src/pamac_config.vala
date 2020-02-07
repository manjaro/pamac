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
		HashTable<string, string> environment_variables_priv;
		internal AlpmConfig alpm_config;
		Daemon system_daemon;
		MainLoop loop;

		public string conf_path { get; construct; }
		public bool recurse { get; set; }
		public bool keep_built_pkgs { get; set; }
		public bool enable_downgrade { get; set; }
		public bool simple_install { get; set; }
		public uint64 refresh_period { get; set; }
		public bool no_update_hide_icon { get; set; }
		public bool enable_aur { get; set; }
		#if ENABLE_SNAP
		public bool support_snap { get; set; }
		public bool enable_snap { get; set; }
		PluginLoader<SnapPlugin> snap_plugin_loader;
		#endif
		#if ENABLE_FLATPAK
		public bool support_flatpak { get; set; }
		public bool enable_flatpak { get; set; }
		PluginLoader<FlatpakPlugin> flatpak_plugin_loader;
		#endif
		public string aur_build_dir { get; set; }
		public bool check_aur_updates { get; set; }
		public bool check_aur_vcs_updates { get; set; }
		public bool download_updates { get; set; }
		public uint64 max_parallel_downloads { get; set; }
		public uint64 clean_keep_num_pkgs { get;  set; }
		public bool clean_rm_only_uninstalled { get; set; }
		public HashTable<string, string> environment_variables { get {return environment_variables_priv;} }
		// Alpm Config
		public bool checkspace { get {return alpm_config.checkspace;}
								set {alpm_config.checkspace = value;} }
		public GenericSet<string?> ignorepkgs { get {return alpm_config.ignorepkgs;} }

		public Config (string conf_path) {
			Object(conf_path: conf_path);
		}

		construct {
			//get environment variables
			environment_variables_priv = new HashTable<string, string> (str_hash, str_equal);
			alpm_config = new AlpmConfig ("/etc/pacman.conf");
			unowned string? variable = Environment.get_variable ("http_proxy");
			if (variable != null) {
				environment_variables_priv.insert ("http_proxy", variable);
			}
			variable = Environment.get_variable ("https_proxy");
			if (variable != null) {
				environment_variables_priv.insert ("https_proxy", variable);
			}
			variable = Environment.get_variable ("ftp_proxy");
			if (variable != null) {
				environment_variables_priv.insert ("ftp_proxy", variable);
			}
			variable = Environment.get_variable ("socks_proxy");
			if (variable != null) {
				environment_variables_priv.insert ("socks_proxy", variable);
			}
			variable = Environment.get_variable ("no_proxy");
			if (variable != null) {
				environment_variables_priv.insert ("no_proxy", variable);
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
			#if ENABLE_FLATPAK
			// load flatpak plugin
			support_flatpak = false;
			flatpak_plugin_loader = new PluginLoader<FlatpakPlugin> ("pamac-flatpak");
			if (flatpak_plugin_loader.load ()) {
				support_flatpak = true;
			}
			#endif
			reload ();
		}

		public void add_ignorepkg (string name) {
			alpm_config.ignorepkgs.add (name);
		}

		public void remove_ignorepkg (string name) {
			alpm_config.ignorepkgs.remove (name);
		}

		public void reload () {
			// alpm config
			alpm_config.reload ();
			// set default options
			recurse = false;
			keep_built_pkgs = false;
			enable_downgrade = false;
			simple_install = false;
			refresh_period = 6;
			no_update_hide_icon = false;
			enable_aur = false;
			#if ENABLE_SNAP
			enable_snap = false;
			#endif
			#if ENABLE_FLATPAK
			enable_flatpak = false;
			#endif
			aur_build_dir = "/var/tmp";
			check_aur_updates = false;
			check_aur_vcs_updates = false;
			download_updates = false;
			max_parallel_downloads = 1;
			clean_keep_num_pkgs = 3;
			clean_rm_only_uninstalled = false;
			parse_file (conf_path);
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
			#if ENABLE_FLATPAK
			if (!support_flatpak) {
				enable_flatpak = false;
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

		#if ENABLE_FLATPAK
		public FlatpakPlugin? get_flatpak_plugin () {
			if (support_flatpak) {
				return flatpak_plugin_loader.new_object ();
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
						} else if (key == "SimpleInstall") {
							simple_install = true;
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
						#if ENABLE_FLATPAK
						} else if (key == "EnableFlatpak") {
							enable_flatpak = true;
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
				} catch (Error e) {
					warning (e.message);
				}
			} else {
				warning ("File '%s' doesn't exist.", path);
			}
		}

		public void save () {
			if (system_daemon == null) {
				loop = new MainLoop ();
				try {
					system_daemon = Bus.get_proxy_sync (BusType.SYSTEM, "org.manjaro.pamac.daemon", "/org/manjaro/pamac/daemon");
					system_daemon.write_alpm_config_finished.connect (() => { loop.quit (); });
					system_daemon.write_pamac_config_finished.connect (() => {
						// write alpm config
						var new_alpm_conf = new HashTable<string, Variant> (str_hash, str_equal);
						new_alpm_conf.insert ("CheckSpace", new Variant.boolean (checkspace));
						var ignorepkgs_str = new StringBuilder ();
						foreach (unowned string name in ignorepkgs) {
							if (ignorepkgs_str.len > 0) {
								ignorepkgs_str.append (" ");
							}
							ignorepkgs_str.append (name);
						}
						new_alpm_conf.insert ("IgnorePkg", new Variant.string (ignorepkgs_str.str));
						try {
							system_daemon.start_write_alpm_config (new_alpm_conf);
						} catch (Error e) {
							warning ("save pamac config error: %s", e.message);
							loop.quit ();
						}
					});
				} catch (Error e) {
					warning ("save pamac config error: %s", e.message);
				}
			}
			// write pamac config
			var new_pamac_conf = new HashTable<string, Variant> (str_hash, str_equal);
			new_pamac_conf.insert ("RemoveUnrequiredDeps", new Variant.boolean (recurse));
			new_pamac_conf.insert ("RefreshPeriod", new Variant.uint64 (refresh_period));
			new_pamac_conf.insert ("NoUpdateHideIcon", new Variant.boolean (no_update_hide_icon));
			new_pamac_conf.insert ("DownloadUpdates", new Variant.boolean (download_updates));
			new_pamac_conf.insert ("EnableDowngrade", new Variant.boolean (enable_downgrade));
			new_pamac_conf.insert ("SimpleInstall", new Variant.boolean (simple_install));
			new_pamac_conf.insert ("MaxParallelDownloads", new Variant.uint64 (max_parallel_downloads));
			new_pamac_conf.insert ("KeepNumPackages", new Variant.uint64 (clean_keep_num_pkgs));
			new_pamac_conf.insert ("OnlyRmUninstalled", new Variant.boolean (clean_rm_only_uninstalled));
			new_pamac_conf.insert ("EnableAUR", new Variant.boolean (enable_aur));
			new_pamac_conf.insert ("KeepBuiltPkgs", new Variant.boolean (keep_built_pkgs));
			new_pamac_conf.insert ("CheckAURUpdates", new Variant.boolean (check_aur_updates));
			new_pamac_conf.insert ("CheckAURVCSUpdates", new Variant.boolean (check_aur_vcs_updates));
			new_pamac_conf.insert ("BuildDirectory", new Variant.string (aur_build_dir));
			#if ENABLE_SNAP
			new_pamac_conf.insert ("EnableSnap", new Variant.boolean (enable_snap));
			#endif
			#if ENABLE_FLATPAK
			new_pamac_conf.insert ("EnableFlatpak", new Variant.boolean (enable_flatpak));
			#endif
			try {
				system_daemon.start_write_pamac_config (new_pamac_conf);
				loop.run ();
			} catch (Error e) {
				warning ("save pamac config error: %s", e.message);
			}
		}
	}
}
