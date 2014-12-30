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
	class Repo {
		public string name;
		public Signature.Level siglevel;
		public DB.Usage usage;
		public string[] urls;

		public Repo (string name) {
			this.name = name;
			usage = 0;
			urls = {};
		} 
	}

	public class Config {
		string conf_path;
		string rootdir;
		string dbpath;
		string gpgdir;
		string logfile;
		string arch;
		double deltaratio;
		int usesyslog;
		public int checkspace;
		Alpm.List<string> cachedirs;
		Alpm.List<string> ignoregrps;
		public string ignorepkg;
		Alpm.List<string> ignorepkgs;
		Alpm.List<string> noextracts;
		Alpm.List<string> noupgrades;
		public GLib.List<string> holdpkgs;
		public GLib.List<string> syncfirsts;
		public string syncfirst;
		Signature.Level defaultsiglevel;
		Signature.Level localfilesiglevel;
		Signature.Level remotefilesiglevel;
		Repo[] repo_order;
		public unowned Handle? handle;

		public Config (string path) {
			conf_path = path;
			handle = null;
			reload ();
		}

		public void reload () {
			// set default options
			rootdir = "/";
			dbpath = "/var/lib/pacman";
			gpgdir = "/etc/pacman.d/gnupg/";
			logfile = "/var/log/pacman.log";
			arch = Posix.utsname().machine;
			holdpkgs = new GLib.List<string> ();
			syncfirsts = new GLib.List<string> ();
			syncfirst = "";
			cachedirs = new Alpm.List<string> ();
			cachedirs.add ("/var/cache/pacman/pkg/");
			ignoregrps = new Alpm.List<string> ();
			ignorepkgs = new Alpm.List<string> ();
			ignorepkg = "";
			noextracts = new Alpm.List<string> ();
			noupgrades = new Alpm.List<string> ();
			usesyslog = 0;
			checkspace = 0;
			deltaratio = 0.7;
			defaultsiglevel = Signature.Level.PACKAGE | Signature.Level.PACKAGE_OPTIONAL | Signature.Level.DATABASE | Signature.Level.DATABASE_OPTIONAL;
			localfilesiglevel = Signature.Level.USE_DEFAULT;
			remotefilesiglevel = Signature.Level.USE_DEFAULT;
			repo_order = {};
			// parse conf file
			parse_file (conf_path);
			get_handle ();
		}

		public void get_handle () {
			Alpm.Errno error;
			if (handle != null)
				Handle.release (handle);
			handle = Handle.new (rootdir, dbpath, out error);
			if (handle == null) {
				stderr.printf ("Failed to initialize alpm library" + " (%s)\n".printf(Alpm.strerror (error)));
				return;
			}
			// define options
			handle.gpgdir = gpgdir;
			handle.logfile = logfile;
			handle.arch = arch;
			handle.deltaratio = deltaratio;
			handle.usesyslog = usesyslog;
			handle.checkspace = checkspace;
			handle.defaultsiglevel = defaultsiglevel;
			handle.localfilesiglevel = localfilesiglevel;
			handle.remotefilesiglevel = remotefilesiglevel;
			handle.cachedirs = cachedirs;
			handle.ignoregroups = ignoregrps;
			handle.ignorepkgs = ignorepkgs;
			handle.noextracts = noextracts;
			handle.noupgrades = noupgrades;
			// register dbs
			foreach (var repo in repo_order) {
				unowned DB db = handle.register_syncdb (repo.name, repo.siglevel);
				foreach (var url in repo.urls)
					db.add_server (url.replace ("$repo", repo.name).replace ("$arch", handle.arch));
				if (repo.usage == 0)
					db.usage = DB.Usage.ALL;
				else
					db.usage = repo.usage;
			}
		}

		public void parse_file (string path, string? section = null) {
			string? current_section = section;
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
						if (line.length == 0) continue;
						// ignore whole line and end of line comments
						string[] splitted = line.split ("#", 2);
						line = splitted[0].strip ();
						if (line.length == 0) continue;
						if (line[0] == '[' && line[line.length-1] == ']') {
							current_section = line[1:-1];
							if (current_section != "options") {
								var repo = new Repo (current_section);
								repo.siglevel = defaultsiglevel;
								repo_order += repo;
							}
							continue;
						}
						splitted = line.split ("=", 2);
						string _key = splitted[0].strip ();
						string? _value = null;
						if (splitted[1] != null)
							_value = splitted[1].strip ();
						if (_key == "Include")
							parse_file (_value, current_section);
						if (current_section == "options") {
							if (_key == "GPGDir")
								gpgdir = _value;
							else if (_key == "LogFile")
								logfile = _value;
							else if (_key == "Architecture") {
								if (_value == "auto")
									arch = Posix.utsname ().machine;
								else
									arch = _value;
							} else if (_key == "UseDelta")
								deltaratio = double.parse (_value);
							else if (_key == "UseSysLog")
								usesyslog = 1;
							else if (_key == "CheckSpace")
								checkspace = 1;
							else if (_key == "SigLevel")
								defaultsiglevel = define_siglevel (defaultsiglevel, _value);
							else if (_key == "LocalSigLevel")
								localfilesiglevel = merge_siglevel (defaultsiglevel, define_siglevel (localfilesiglevel, _value));
							else if (_key == "RemoteSigLevel")
								remotefilesiglevel = merge_siglevel (defaultsiglevel, define_siglevel (remotefilesiglevel, _value));
							else if (_key == "HoldPkg") {
								foreach (string name in _value.split (" "))
									holdpkgs.append (name);
							} else if (_key == "SyncFirst") {
								syncfirst = _value;
								foreach (string name in _value.split (" "))
									syncfirsts.append (name);
							} else if (_key == "CacheDir") {
								foreach (string dir in _value.split (" "))
									cachedirs.add (dir);
							} else if (_key == "IgnoreGroup") {
								foreach (string name in _value.split (" "))
									ignoregrps.add (name);
							} else if (_key == "IgnorePkg") {
								ignorepkg = _value;
								foreach (string name in _value.split (" "))
									ignorepkgs.add (name);
							} else if (_key == "Noextract") {
								foreach (string name in _value.split (" "))
									noextracts.add (name);
							} else if (_key == "NoUpgrade") {
								foreach (string name in _value.split (" "))
									noupgrades.add (name);
							}
						} else {
							foreach (var repo in repo_order) {
								if (repo.name == current_section) {
									if (_key == "Server")
										repo.urls += _value;
									else if (_key == "SigLevel")
										repo.siglevel = define_siglevel (defaultsiglevel, _value);
									else if (_key == "Usage")
										repo.usage = define_usage (_value);
								}
							}
						}
					}
				} catch (GLib.Error e) {
					GLib.stderr.printf("%s\n", e.message);
				}
			}
		}

		public void write (HashTable<string,Variant> new_conf) {
			var file = GLib.File.new_for_path (conf_path);
			if (file.query_exists () == false)
				GLib.stderr.printf ("File '%s' doesn't exist.\n", conf_path);
			else {
				try {
					// Open file for reading and wrap returned FileInputStream into a
					// DataInputStream, so we can read line by line
					var dis = new DataInputStream (file.read ());
					string line;
					string[] data = {};
					// Read lines until end of file (null) is reached
					while ((line = dis.read_line (null)) != null) {
						if (line.length == 0) continue;
						if (line.contains ("IgnorePkg")) {
							if (new_conf.contains ("IgnorePkg")) {
								string _value = new_conf.get ("IgnorePkg").get_string ();
								if (_value == "")
									data += "#IgnorePkg   =\n";
								else
									data += "IgnorePkg   = %s\n".printf (_value);
							} else
								data += line + "\n";
						} else if (line.contains ("SyncFirst")) {
							if (new_conf.contains ("SyncFirst")) {
								string _value = new_conf.get ("SyncFirst").get_string ();
								if (_value == "")
									data += "#SyncFirst   =\n";
								else
									data += "SyncFirst   = %s\n".printf (_value);
							} else
								data += line + "\n";
						} else if (line.contains ("CheckSpace")) {
							if (new_conf.contains ("CheckSpace")) {
								int _value = new_conf.get ("CheckSpace").get_int32 ();
								if (_value == 1)
									data += "CheckSpace\n";
								else
									data += "#CheckSpace\n";
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

		public DB.Usage define_usage (string conf_string) {
			DB.Usage usage = 0;
			foreach (string directive in conf_string.split(" ")) {
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

		public Signature.Level define_siglevel (Signature.Level default_level, string conf_string) {
			foreach (string directive in conf_string.split(" ")) {
				bool affect_package = false;
				bool affect_database = false;
				if ("Package" in directive) affect_package = true;
				else if ("Database" in directive) affect_database = true;
				else {
					affect_package = true;
					affect_database = true;
				}
				if ("Never" in directive) {
					if (affect_package) {
						default_level &= ~Signature.Level.PACKAGE;
						default_level |= Signature.Level.PACKAGE_SET;
					}
					if (affect_database) default_level &= ~Signature.Level.DATABASE;
				}
				else if ("Optional" in directive) {
					if (affect_package) {
						default_level |= Signature.Level.PACKAGE;
						default_level |= Signature.Level.PACKAGE_OPTIONAL;
						default_level |= Signature.Level.PACKAGE_SET;
					}
					if (affect_database) {
						default_level |= Signature.Level.DATABASE;
						default_level |= Signature.Level.DATABASE_OPTIONAL;
					}
				}
				else if ("Required" in directive) {
					if (affect_package) {
						default_level |= Signature.Level.PACKAGE;
						default_level &= ~Signature.Level.PACKAGE_OPTIONAL;
						default_level |= Signature.Level.PACKAGE_SET;
					}
					if (affect_database) {
						default_level |= Signature.Level.DATABASE;
						default_level &= ~Signature.Level.DATABASE_OPTIONAL;
					}
				}
				else if ("TrustedOnly" in directive) {
					if (affect_package) {
						default_level &= ~Signature.Level.PACKAGE_MARGINAL_OK;
						default_level &= ~Signature.Level.PACKAGE_UNKNOWN_OK;
						default_level |= Signature.Level.PACKAGE_TRUST_SET;
					}
					if (affect_database) {
						default_level &= ~Signature.Level.DATABASE_MARGINAL_OK;
						default_level &= ~Signature.Level.DATABASE_UNKNOWN_OK;
					}
				}
				else if ("TrustAll" in directive) {
					if (affect_package) {
						default_level |= Signature.Level.PACKAGE_MARGINAL_OK;
						default_level |= Signature.Level.PACKAGE_UNKNOWN_OK;
						default_level |= Signature.Level.PACKAGE_TRUST_SET;
					}
					if (affect_database) {
						default_level |= Signature.Level.DATABASE_MARGINAL_OK;
						default_level |= Signature.Level.DATABASE_UNKNOWN_OK;
					}
				}
				else GLib.stderr.printf("unrecognized siglevel: %s\n", conf_string);
			}
			default_level &= ~Signature.Level.USE_DEFAULT;
			return default_level;
		}

		public Signature.Level merge_siglevel (Signature.Level base_level, Signature.Level over_level) {
			if ((over_level & Signature.Level.USE_DEFAULT) != 0) over_level = base_level;
			else {
				if ((over_level & Signature.Level.PACKAGE_SET) == 0) {
					over_level |= base_level & Signature.Level.PACKAGE;
					over_level |= base_level & Signature.Level.PACKAGE_OPTIONAL;
				}
				if ((over_level & Signature.Level.PACKAGE_TRUST_SET) == 0) {
					over_level |= base_level & Signature.Level.PACKAGE_MARGINAL_OK;
					over_level |= base_level & Signature.Level.PACKAGE_UNKNOWN_OK;
				}
			}
			return over_level;
		}
	}
}
