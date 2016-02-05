/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2016 Guillaume Benoit <guillaume@manjaro.org>
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
	[Compact]
	public class Repo {
		public string name;
		public Signature.Level siglevel;
		public Signature.Level siglevel_mask;
		public DB.Usage usage;
		public GLib.List<string> urls;

		public Repo (string name) {
			this.name = name;
			siglevel = Signature.Level.USE_DEFAULT;
			usage = 0;
			urls = new GLib.List<string> ();
		}

		public static int compare_name (Repo a, Repo b) {
			return strcmp (a.name, b.name);
		}

		public static int search_name (Repo a, string name) {
			return strcmp (a.name, name);
		}

	}

	[Compact]
	public class Config {
		public string conf_path;
		public string? rootdir;
		public string? dbpath;
		public string? logfile;
		public string? gpgdir;
		public string? arch;
		public double deltaratio;
		public int usesyslog;
		public int checkspace;
		public Alpm.List<string>? cachedirs;
		public Alpm.List<string?>? hookdirs;
		public Alpm.List<string>? ignoregroups;
		public Alpm.List<string>? ignorepkgs;
		public Alpm.List<string>? noextracts;
		public Alpm.List<string>? noupgrades;
		public GLib.List<string>? holdpkgs;
		public GLib.List<string>? syncfirsts;
		public Signature.Level siglevel;
		public Signature.Level localfilesiglevel;
		public Signature.Level remotefilesiglevel;
		public Signature.Level siglevel_mask;
		public Signature.Level localfilesiglevel_mask;
		public Signature.Level remotefilesiglevel_mask;
		public GLib.List<Repo> repo_order;
		public Handle? handle;

		public Config (string path) {
			conf_path = path;
			reload ();
		}

		public void reload () {
			// set default options
			holdpkgs = new GLib.List<string> ();
			syncfirsts = new GLib.List<string> ();
			// free internal data of alpm lists
			if (cachedirs != null) {
				cachedirs.free_data ();
				cachedirs = new Alpm.List<string> ();
			}
			if (hookdirs != null) {
				hookdirs.free_data ();
				hookdirs = new Alpm.List<string?> ();
			}
			if (ignoregroups != null) {
				ignoregroups.free_data ();
				ignoregroups = new Alpm.List<string> ();
			}
			if (ignorepkgs != null) {
				ignorepkgs.free_data ();
				ignorepkgs = new Alpm.List<string> ();
			}
			if (noextracts != null) {
				noextracts.free_data ();
				noextracts = new Alpm.List<string> ();
			}
			if (noupgrades != null) {
				noupgrades.free_data ();
				noupgrades = new Alpm.List<string> ();
			}
			usesyslog = 0;
			checkspace = 0;
			deltaratio = 0.7;
			siglevel = Signature.Level.PACKAGE | Signature.Level.PACKAGE_OPTIONAL | Signature.Level.DATABASE | Signature.Level.DATABASE_OPTIONAL;
			localfilesiglevel = Signature.Level.USE_DEFAULT;
			remotefilesiglevel = Signature.Level.USE_DEFAULT;
			repo_order = new GLib.List<Repo> ();
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
			if (cachedirs.length == 0) {
				cachedirs.add ("/var/cache/pacman/pkg/");
			}
			if (hookdirs.length == 0) {
				hookdirs.add ("/etc/pacman.d/hooks/");
			}
			if (gpgdir == null) {
				// gpgdir it is not relative to rootdir, even if
				// rootdir is defined because it contains configuration data.
				gpgdir = "/etc/pacman.d/gnupg/";
			}
			if (arch == null) {
				arch = Posix.utsname().machine;
			}
		}

		public void get_handle () {
			Alpm.Errno error;
			handle = Handle.new (rootdir, dbpath, out error);
			if (handle == null) {
				stderr.printf ("Failed to initialize alpm library" + " (%s)\n".printf(Alpm.strerror (error)));
				return;
			}
			// define options
			handle.logfile = logfile;
			handle.gpgdir = gpgdir;
			handle.arch = arch;
			handle.deltaratio = deltaratio;
			handle.usesyslog = usesyslog;
			handle.checkspace = checkspace;
			handle.defaultsiglevel = siglevel;
			localfilesiglevel = merge_siglevel (siglevel, localfilesiglevel, localfilesiglevel_mask);
			remotefilesiglevel = merge_siglevel (siglevel, remotefilesiglevel, remotefilesiglevel_mask);
			handle.localfilesiglevel = localfilesiglevel;
			handle.remotefilesiglevel = remotefilesiglevel;
			handle.cachedirs = cachedirs;
			// add hook directories 1-by-1 to avoid overwriting the system directory
			foreach (unowned string hookdir in hookdirs) {
				handle.add_hookdir (hookdir);
			}
			handle.ignoregroups = ignoregroups;
			handle.ignorepkgs = ignorepkgs;
			handle.noextracts = noextracts;
			handle.noupgrades = noupgrades;
			// register dbs
			foreach (unowned Repo repo in repo_order) {
				repo.siglevel = merge_siglevel (siglevel, repo.siglevel, repo.siglevel_mask);
				unowned DB db = handle.register_syncdb (repo.name, repo.siglevel);
				foreach (unowned string url in repo.urls) {
					db.add_server (url.replace ("$repo", repo.name).replace ("$arch", handle.arch));
				}
				if (repo.usage == 0) {
					db.usage = DB.Usage.ALL;
				} else {
					db.usage = repo.usage;
				}
			}
		}

		public void parse_file (string path, string? section = null) {
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
								var repo = new Repo (current_section);
								if (repo_order.find_custom (repo, Repo.compare_name) == null) {
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
									cachedirs.add (dir);
								}
							} else if (key == "HookDir") {
								foreach (unowned string dir in val.split (" ")) {
									hookdirs.add (dir);
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
							} else if (key == "CheckSpace") {
								checkspace = 1;
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
									ignoregroups.add (name);
								}
							} else if (key == "IgnorePkg") {
								foreach (unowned string name in val.split (" ")) {
									ignorepkgs.add (name);
								}
							} else if (key == "Noextract") {
								foreach (unowned string name in val.split (" ")) {
									noextracts.add (name);
								}
							} else if (key == "NoUpgrade") {
								foreach (unowned string name in val.split (" ")) {
									noupgrades.add (name);
								}
							}
						} else {
							unowned GLib.List<Repo>? found = repo_order.search (current_section, (SearchFunc) Repo.search_name);
							if (found != null) {
								unowned Repo repo = found.data;
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

		public void write (HashTable<string,Variant> new_conf) {
			var file = GLib.File.new_for_path (conf_path);
			if (file.query_exists ()) {
				try {
					// Open file for reading and wrap returned FileInputStream into a
					// DataInputStream, so we can read line by line
					var dis = new DataInputStream (file.read ());
					string? line;
					string[] data = {};
					// Read lines until end of file (null) is reached
					while ((line = dis.read_line ()) != null) {
						if (line.length == 0) {
							data += "\n";
							continue;
						}
						if (line.contains ("IgnorePkg")) {
							if (new_conf.contains ("IgnorePkg")) {
								string val = new_conf.get ("IgnorePkg").get_string ();
								if (val == "") {
									data += "#IgnorePkg   =\n";
								} else {
									data += "IgnorePkg   = %s\n".printf (val);
								}
								new_conf.remove ("IgnorePkg");
							} else {
								data += line + "\n";
							}
						} else if (line.contains ("CheckSpace")) {
							if (new_conf.contains ("CheckSpace")) {
								bool val = new_conf.get ("CheckSpace").get_boolean ();
								if (val) {
									data += "CheckSpace\n";
								} else {
									data += "#CheckSpace\n";
								}
								new_conf.remove ("CheckSpace");
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
					foreach (unowned string new_line in data) {
						// writing a short string to the stream
						dos.put_string (new_line);
					}
				} catch (GLib.Error e) {
					GLib.stderr.printf("%s\n", e.message);
				}
			} else {
				GLib.stderr.printf ("File '%s' doesn't exist.\n", conf_path);
			}
		}

		public DB.Usage define_usage (string conf_string) {
			DB.Usage usage = 0;
			foreach (unowned string directive in conf_string.split(" ")) {
				if (directive == "Sync") {
					usage |= DB.Usage.SYNC;
				} else if (directive == "Search") {
					usage |= DB.Usage.SEARCH;
				} else if (directive == "Install") {
					usage |= DB.Usage.INSTALL;
				} else if (directive == "Upgrade") {
					usage |= DB.Usage.UPGRADE;
				} else if (directive == "All") {
					usage |= DB.Usage.ALL;
				}
			}
			return usage;
		}

		public void process_siglevel (string conf_string, ref Signature.Level siglevel, ref Signature.Level siglevel_mask) {
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
						siglevel &= ~Signature.Level.PACKAGE;
						siglevel_mask |= Signature.Level.PACKAGE;
					}
					if (affect_database) {
						siglevel &= ~Signature.Level.DATABASE;
						siglevel_mask |= Signature.Level.DATABASE;
					}
				} else if ("Optional" in directive) {
					if (affect_package) {
						siglevel |= (Signature.Level.PACKAGE | Signature.Level.PACKAGE_OPTIONAL);
						siglevel_mask |= (Signature.Level.PACKAGE | Signature.Level.PACKAGE_OPTIONAL);
					}
					if (affect_database) {
						siglevel |= (Signature.Level.DATABASE | Signature.Level.DATABASE_OPTIONAL);
						siglevel_mask |= (Signature.Level.DATABASE | Signature.Level.DATABASE_OPTIONAL);
					}
				} else if ("Required" in directive) {
					if (affect_package) {
						siglevel |= Signature.Level.PACKAGE;
						siglevel_mask |= Signature.Level.PACKAGE;
						siglevel &= ~Signature.Level.PACKAGE_OPTIONAL;
						siglevel_mask |= Signature.Level.PACKAGE_OPTIONAL;
					}
					if (affect_database) {
						siglevel |= Signature.Level.DATABASE;
						siglevel_mask |= Signature.Level.DATABASE;
						siglevel &= ~Signature.Level.DATABASE_OPTIONAL;
						siglevel_mask |= Signature.Level.DATABASE_OPTIONAL;
					}
				} else if ("TrustedOnly" in directive) {
					if (affect_package) {
						siglevel &= ~(Signature.Level.PACKAGE_MARGINAL_OK | Signature.Level.PACKAGE_UNKNOWN_OK);
						siglevel_mask |= (Signature.Level.PACKAGE_MARGINAL_OK | Signature.Level.PACKAGE_UNKNOWN_OK);
					}
					if (affect_database) {
						siglevel &= ~(Signature.Level.DATABASE_MARGINAL_OK | Signature.Level.DATABASE_UNKNOWN_OK);
						siglevel_mask |= (Signature.Level.DATABASE_MARGINAL_OK | Signature.Level.DATABASE_UNKNOWN_OK);
					}
				} else if ("TrustAll" in directive) {
					if (affect_package) {
						siglevel |= (Signature.Level.PACKAGE_MARGINAL_OK | Signature.Level.PACKAGE_UNKNOWN_OK);
						siglevel_mask |= (Signature.Level.PACKAGE_MARGINAL_OK | Signature.Level.PACKAGE_UNKNOWN_OK);
					}
					if (affect_database) {
						siglevel |= (Signature.Level.DATABASE_MARGINAL_OK | Signature.Level.DATABASE_UNKNOWN_OK);
						siglevel_mask |= (Signature.Level.DATABASE_MARGINAL_OK | Signature.Level.DATABASE_UNKNOWN_OK);
					}
				} else {
					GLib.stderr.printf("unrecognized siglevel: %s\n", conf_string);
				}
			}
			siglevel &= ~Signature.Level.USE_DEFAULT;
		}

		public Signature.Level merge_siglevel(Signature.Level sigbase, Signature.Level sigover, Signature.Level sigmask) {
			return (sigmask != 0) ? (sigover & sigmask) | (sigbase & ~sigmask) : sigover;
		}
	}
}
