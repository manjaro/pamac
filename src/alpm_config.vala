/*
 *  alpm_config
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

[Compact]
class AlpmRepo {
	public string name;
	public Alpm.Signature.Level siglevel;
	public Alpm.Signature.Level siglevel_mask;
	public Alpm.DB.Usage usage;
	public GLib.List<string> urls;

	public AlpmRepo (string name) {
		this.name = name;
		siglevel = Alpm.Signature.Level.USE_DEFAULT;
		usage = 0;
		urls = new GLib.List<string> ();
	}

	public static int compare_name (AlpmRepo a, AlpmRepo b) {
		return strcmp (a.name, b.name);
	}

	public static int search_name (AlpmRepo a, string name) {
		return strcmp (a.name, name);
	}

}

internal class AlpmConfig {
	string conf_path;
	string? rootdir;
	string? dbpath;
	string? logfile;
	string? gpgdir;
	string? arch;
	double deltaratio;
	int usesyslog;
	GLib.List<string> cachedirs;
	GLib.List<string> hookdirs;
	GLib.List<string> ignoregroups;
	GLib.List<string> ignorepkgs;
	GLib.List<string> noextracts;
	GLib.List<string> noupgrades;
	GLib.List<string> holdpkgs;
	GLib.List<string> syncfirsts;
	Alpm.Signature.Level siglevel;
	Alpm.Signature.Level localfilesiglevel;
	Alpm.Signature.Level remotefilesiglevel;
	Alpm.Signature.Level siglevel_mask;
	Alpm.Signature.Level localfilesiglevel_mask;
	Alpm.Signature.Level remotefilesiglevel_mask;
	GLib.List<AlpmRepo> repo_order;

	public AlpmConfig (string path) {
		conf_path = path;
		reload ();
	}

	public unowned GLib.List<string> get_holdpkgs () {
		return holdpkgs;
	}

	public unowned GLib.List<string> get_syncfirsts () {
		return syncfirsts;
	}

	public void reload () {
		// set default options
		cachedirs = new GLib.List<string> ();
		hookdirs = new GLib.List<string> ();
		ignoregroups = new GLib.List<string> ();
		ignorepkgs = new GLib.List<string> ();
		noextracts = new GLib.List<string> ();
		noupgrades = new GLib.List<string> ();
		holdpkgs = new GLib.List<string> ();
		syncfirsts = new GLib.List<string> ();
		usesyslog = 0;
		deltaratio = 0.7;
		siglevel = Alpm.Signature.Level.PACKAGE | Alpm.Signature.Level.PACKAGE_OPTIONAL | Alpm.Signature.Level.DATABASE | Alpm.Signature.Level.DATABASE_OPTIONAL;
		localfilesiglevel = Alpm.Signature.Level.USE_DEFAULT;
		remotefilesiglevel = Alpm.Signature.Level.USE_DEFAULT;
		repo_order = new GLib.List<AlpmRepo> ();
		// parse conf file
		parse_file (conf_path);
		// if rootdir is set and dbpath/logfile are not
		// set, then set those as well to reside under the root.
		if (rootdir != null) {
			if (dbpath == null) {
				dbpath = Path.build_path ("/", rootdir, "var/lib/pacman/");
			}
			if (logfile == null) {
				logfile = Path.build_path ("/", rootdir, "var/log/pacman.log");
			}
		} else {
			rootdir = "/";
			if (dbpath == null) {
				dbpath = "/var/lib/pacman/";
			}
			if (logfile == null) {
				logfile = "/var/log/pacman.log";
			}
		}
		if (cachedirs.length () == 0) {
			cachedirs.append ("/var/cache/pacman/pkg/");
		}
		if (hookdirs.length () == 0) {
			hookdirs.append ("/etc/pacman.d/hooks/");
		}
		if (gpgdir == null) {
			// gpgdir it is not relative to rootdir, even if
			// rootdir is defined because it contains configuration data.
			gpgdir = "/etc/pacman.d/gnupg/";
		}
		if (arch == null) {
			arch = Posix.utsname().machine;
		}
		// add archlinux-keyring and manjaro-keyring to syncfirsts
		if (syncfirsts.find_custom ("archlinux-keyring", strcmp) == null) {
			syncfirsts.append ("archlinux-keyring");
		}
		if (syncfirsts.find_custom ("manjaro-keyring", strcmp) == null) {
			syncfirsts.append ("manjaro-keyring");
		}
	}

	public Alpm.Handle? get_handle (bool files_db = false, bool tmp_db = false) {
		Alpm.Errno error = 0;
		Alpm.Handle? handle = null;
		if (tmp_db) {
			string tmp_path = "/tmp/pamac";
			string tmp_dbpath = "/tmp/pamac/dbs-%s".printf (Environment.get_user_name ());
			try {
				var file = GLib.File.new_for_path (tmp_path);
				if (!file.query_exists ()) {
					Process.spawn_command_line_sync ("mkdir -p %s".printf (tmp_path));
					Process.spawn_command_line_sync ("chmod a+w %s".printf (tmp_path));
				}
				file = GLib.File.new_for_path (tmp_dbpath);
				if (!file.query_exists ()) {
					Process.spawn_command_line_sync ("mkdir -p %s".printf (tmp_dbpath));
					Process.spawn_command_line_sync ("ln -s %slocal %s".printf (dbpath, tmp_dbpath));
				}
				Process.spawn_command_line_sync ("cp -au %ssync %s".printf (dbpath, tmp_dbpath));
				handle = new Alpm.Handle (rootdir, tmp_dbpath, out error);
				if (error == Alpm.Errno.DB_VERSION) {
					try {
						Process.spawn_command_line_sync ("pacman-db-upgrade", null, null, null);
					} catch (SpawnError e) {
						stdout.printf ("Error: %s\n", e.message);
					}
					handle = new Alpm.Handle (rootdir, tmp_dbpath, out error);
				}
			} catch (SpawnError e) {
				stderr.printf ("SpawnError: %s\n", e.message);
			}
		} else {
			handle = new Alpm.Handle (rootdir, dbpath, out error);
			if (error == Alpm.Errno.DB_VERSION) {
				try {
					Process.spawn_command_line_sync ("pacman-db-upgrade", null, null, null);
				} catch (SpawnError e) {
					stdout.printf ("Error: %s\n", e.message);
				}
				handle = new Alpm.Handle (rootdir, dbpath, out error);
			}
		}
		if (handle == null) {
			stderr.printf ("Failed to initialize alpm library" + " (%s)\n".printf (Alpm.strerror (error)));
			return null;
		}
		// define options
		if (files_db) {
			handle.dbext = ".files";
		}
		if (!tmp_db) {
			handle.logfile = logfile;
		}
		handle.gpgdir = gpgdir;
		handle.arch = arch;
		handle.deltaratio = deltaratio;
		handle.usesyslog = usesyslog;
		handle.checkspace = 1;
		handle.defaultsiglevel = siglevel;
		localfilesiglevel = merge_siglevel (siglevel, localfilesiglevel, localfilesiglevel_mask);
		remotefilesiglevel = merge_siglevel (siglevel, remotefilesiglevel, remotefilesiglevel_mask);
		handle.localfilesiglevel = localfilesiglevel;
		handle.remotefilesiglevel = remotefilesiglevel;
		foreach (unowned string cachedir in cachedirs) {
			handle.add_cachedir (cachedir);
		}
		foreach (unowned string hookdir in hookdirs) {
			handle.add_hookdir (hookdir);
		}
		foreach (unowned string ignoregroup in ignoregroups) {
			handle.add_ignoregroup (ignoregroup);
		}
		foreach (unowned string ignorepkg in ignorepkgs) {
			handle.add_ignorepkg (ignorepkg);
		}
		foreach (unowned string noextract in noextracts) {
			handle.add_noextract (noextract);
		}
		foreach (unowned string noupgrade in noupgrades) {
			handle.add_noupgrade (noupgrade);
		}
		// register dbs
		foreach (unowned AlpmRepo repo in repo_order) {
			repo.siglevel = merge_siglevel (siglevel, repo.siglevel, repo.siglevel_mask);
			unowned Alpm.DB db = handle.register_syncdb (repo.name, repo.siglevel);
			foreach (unowned string url in repo.urls) {
				db.add_server (url.replace ("$repo", repo.name).replace ("$arch", handle.arch));
			}
			if (repo.usage == 0) {
				db.usage = Alpm.DB.Usage.ALL;
			} else {
				db.usage = repo.usage;
			}
		}
		return handle;
	}

	void parse_file (string path, string? section = null) {
		string? current_section = section;
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
					if (line[0] == '[' && line[line.length-1] == ']') {
						current_section = line[1:-1];
						if (current_section != "options") {
							var repo = new AlpmRepo (current_section);
							if (repo_order.find_custom (repo, AlpmRepo.compare_name) == null) {
								repo_order.append ((owned) repo);
							}
						}
						continue;
					}
					splitted = line.split ("=", 2);
					unowned string key = splitted[0]._strip ();
					unowned string? val = null;
					if (splitted.length == 2) {
						val = splitted[1]._strip ();
					}
					if (key == "Include") {
						parse_file (val, current_section);
					}
					if (current_section == "options") {
						if (key == "RootDir") {
							rootdir = val;
						} else if (key == "DBPath") {
							dbpath = val;
						} else if (key == "CacheDir") {
							foreach (unowned string dir in val.split (" ")) {
								cachedirs.append (dir);
							}
						} else if (key == "HookDir") {
							foreach (unowned string dir in val.split (" ")) {
								hookdirs.append (dir);
							}
						} else if (key == "LogFile") {
							logfile = val;
						} else if (key == "GPGDir") {
							gpgdir = val;
						} else if (key == "LogFile") {
							logfile = val;
						} else if (key == "Architecture") {
							if (val == "auto") {
								arch = Posix.utsname ().machine;
							} else {
								arch = val;
							}
						} else if (key == "UseDelta") {
							deltaratio = double.parse (val);
						} else if (key == "UseSysLog") {
							usesyslog = 1;
						} else if (key == "SigLevel") {
							process_siglevel (val, ref siglevel, ref siglevel_mask);
						} else if (key == "LocalFileSigLevel") {
							process_siglevel (val, ref localfilesiglevel, ref localfilesiglevel_mask);
						} else if (key == "RemoteFileSigLevel") {
							process_siglevel (val, ref remotefilesiglevel, ref remotefilesiglevel_mask);
						} else if (key == "HoldPkg") {
							foreach (unowned string name in val.split (" ")) {
								holdpkgs.append (name);
							}
						} else if (key == "SyncFirst") {
							foreach (unowned string name in val.split (" ")) {
								syncfirsts.append (name);
							}
						} else if (key == "IgnoreGroup") {
							foreach (unowned string name in val.split (" ")) {
								ignoregroups.append (name);
							}
						} else if (key == "IgnorePkg") {
							foreach (unowned string name in val.split (" ")) {
								ignorepkgs.append (name);
							}
						} else if (key == "Noextract") {
							foreach (unowned string name in val.split (" ")) {
								noextracts.append (name);
							}
						} else if (key == "NoUpgrade") {
							foreach (unowned string name in val.split (" ")) {
								noupgrades.append (name);
							}
						}
					} else {
						unowned GLib.List<AlpmRepo>? found = repo_order.search (current_section, (SearchFunc) AlpmRepo.search_name);
						if (found != null) {
							unowned AlpmRepo repo = found.data;
							if (key == "Server") {
								repo.urls.append (val);
							} else if (key == "SigLevel") {
								process_siglevel (val, ref repo.siglevel, ref repo.siglevel_mask);
							} else if (key == "Usage") {
								repo.usage = define_usage (val);
							}
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

//~ 	public void write (HashTable<string,Variant> new_conf) {
//~ 		var file = GLib.File.new_for_path (conf_path);
//~ 		if (file.query_exists ()) {
//~ 			try {
//~ 				// Open file for reading and wrap returned FileInputStream into a
//~ 				// DataInputStream, so we can read line by line
//~ 				var dis = new DataInputStream (file.read ());
//~ 				string? line;
//~ 				var data = new StringBuilder ();
//~ 				// Read lines until end of file (null) is reached
//~ 				while ((line = dis.read_line ()) != null) {
//~ 					if (line.length == 0) {
//~ 						data.append ("\n");
//~ 						continue;
//~ 					}
//~ 					if (line.contains ("IgnorePkg")) {
//~ 						if (new_conf.contains ("IgnorePkg")) {
//~ 							string val = new_conf.get ("IgnorePkg").get_string ();
//~ 							if (val == "") {
//~ 								data.append ("#IgnorePkg   =\n");
//~ 							} else {
//~ 								data.append ("IgnorePkg   = %s\n".printf (val));
//~ 							}
//~ 							// simply comment other IgnorePkg lines
//~ 							new_conf.replace ("IgnorePkg", "");
//~ 						} else {
//~ 							data.append (line);
//~ 							data.append ("\n");
//~ 						}
//~ 					} else {
//~ 						data.append (line);
//~ 						data.append ("\n");
//~ 					}
//~ 				}
//~ 				// delete the file before rewrite it
//~ 				file.delete ();
//~ 				// creating a DataOutputStream to the file
//~ 				var dos = new DataOutputStream (file.create (FileCreateFlags.REPLACE_DESTINATION));
//~ 				dos.put_string (data.str);
//~ 				reload ();
//~ 			} catch (GLib.Error e) {
//~ 				GLib.stderr.printf("%s\n", e.message);
//~ 			}
//~ 		} else {
//~ 			GLib.stderr.printf ("File '%s' doesn't exist.\n", conf_path);
//~ 		}
//~ 	}

	Alpm.DB.Usage define_usage (string conf_string) {
		Alpm.DB.Usage usage = 0;
		foreach (unowned string directive in conf_string.split(" ")) {
			if (directive == "Sync") {
				usage |= Alpm.DB.Usage.SYNC;
			} else if (directive == "Search") {
				usage |= Alpm.DB.Usage.SEARCH;
			} else if (directive == "Install") {
				usage |= Alpm.DB.Usage.INSTALL;
			} else if (directive == "Upgrade") {
				usage |= Alpm.DB.Usage.UPGRADE;
			} else if (directive == "All") {
				usage |= Alpm.DB.Usage.ALL;
			}
		}
		return usage;
	}

	void process_siglevel (string conf_string, ref Alpm.Signature.Level siglevel, ref Alpm.Signature.Level siglevel_mask) {
		foreach (unowned string directive in conf_string.split(" ")) {
			bool affect_package = false;
			bool affect_database = false;
			if ("Package" in directive) {
				affect_package = true;
			} else if ("Database" in directive) {
				affect_database = true;
			} else {
				affect_package = true;
				affect_database = true;
			}
			if ("Never" in directive) {
				if (affect_package) {
					siglevel &= ~Alpm.Signature.Level.PACKAGE;
					siglevel_mask |= Alpm.Signature.Level.PACKAGE;
				}
				if (affect_database) {
					siglevel &= ~Alpm.Signature.Level.DATABASE;
					siglevel_mask |= Alpm.Signature.Level.DATABASE;
				}
			} else if ("Optional" in directive) {
				if (affect_package) {
					siglevel |= (Alpm.Signature.Level.PACKAGE | Alpm.Signature.Level.PACKAGE_OPTIONAL);
					siglevel_mask |= (Alpm.Signature.Level.PACKAGE | Alpm.Signature.Level.PACKAGE_OPTIONAL);
				}
				if (affect_database) {
					siglevel |= (Alpm.Signature.Level.DATABASE | Alpm.Signature.Level.DATABASE_OPTIONAL);
					siglevel_mask |= (Alpm.Signature.Level.DATABASE | Alpm.Signature.Level.DATABASE_OPTIONAL);
				}
			} else if ("Required" in directive) {
				if (affect_package) {
					siglevel |= Alpm.Signature.Level.PACKAGE;
					siglevel_mask |= Alpm.Signature.Level.PACKAGE;
					siglevel &= ~Alpm.Signature.Level.PACKAGE_OPTIONAL;
					siglevel_mask |= Alpm.Signature.Level.PACKAGE_OPTIONAL;
				}
				if (affect_database) {
					siglevel |= Alpm.Signature.Level.DATABASE;
					siglevel_mask |= Alpm.Signature.Level.DATABASE;
					siglevel &= ~Alpm.Signature.Level.DATABASE_OPTIONAL;
					siglevel_mask |= Alpm.Signature.Level.DATABASE_OPTIONAL;
				}
			} else if ("TrustedOnly" in directive) {
				if (affect_package) {
					siglevel &= ~(Alpm.Signature.Level.PACKAGE_MARGINAL_OK | Alpm.Signature.Level.PACKAGE_UNKNOWN_OK);
					siglevel_mask |= (Alpm.Signature.Level.PACKAGE_MARGINAL_OK | Alpm.Signature.Level.PACKAGE_UNKNOWN_OK);
				}
				if (affect_database) {
					siglevel &= ~(Alpm.Signature.Level.DATABASE_MARGINAL_OK | Alpm.Signature.Level.DATABASE_UNKNOWN_OK);
					siglevel_mask |= (Alpm.Signature.Level.DATABASE_MARGINAL_OK | Alpm.Signature.Level.DATABASE_UNKNOWN_OK);
				}
			} else if ("TrustAll" in directive) {
				if (affect_package) {
					siglevel |= (Alpm.Signature.Level.PACKAGE_MARGINAL_OK | Alpm.Signature.Level.PACKAGE_UNKNOWN_OK);
					siglevel_mask |= (Alpm.Signature.Level.PACKAGE_MARGINAL_OK | Alpm.Signature.Level.PACKAGE_UNKNOWN_OK);
				}
				if (affect_database) {
					siglevel |= (Alpm.Signature.Level.DATABASE_MARGINAL_OK | Alpm.Signature.Level.DATABASE_UNKNOWN_OK);
					siglevel_mask |= (Alpm.Signature.Level.DATABASE_MARGINAL_OK | Alpm.Signature.Level.DATABASE_UNKNOWN_OK);
				}
			} else {
				GLib.stderr.printf("unrecognized siglevel: %s\n", conf_string);
			}
		}
		siglevel &= ~Alpm.Signature.Level.USE_DEFAULT;
	}

	Alpm.Signature.Level merge_siglevel(Alpm.Signature.Level sigbase, Alpm.Signature.Level sigover, Alpm.Signature.Level sigmask) {
		return (sigmask != 0) ? (sigover & sigmask) | (sigbase & ~sigmask) : sigover;
	}
}
