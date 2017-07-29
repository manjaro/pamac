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

// i18n
const string GETTEXT_PACKAGE = "pamac";

Pamac.UserDaemon user_daemon;
MainLoop loop;

private int alpm_pkg_compare_name (Alpm.Package pkg_a, Alpm.Package pkg_b) {
	return strcmp (pkg_a.name, pkg_b.name);
}

private string global_search_string;

private int alpm_pkg_sort_search_by_relevance (Alpm.Package pkg_a, Alpm.Package pkg_b) {
	if (global_search_string != null) {
		// display exact match first
		if (pkg_a.name == global_search_string) {
			return 0;
		}
		if (pkg_b.name == global_search_string) {
			return 1;
		}
		if (pkg_a.name.has_prefix (global_search_string + "-")) {
			if (pkg_b.name.has_prefix (global_search_string + "-")) {
				return strcmp (pkg_a.name, pkg_b.name);
			}
			return 0;
		}
		if (pkg_b.name.has_prefix (global_search_string + "-")) {
			if (pkg_a.name.has_prefix (global_search_string + "-")) {
				return strcmp (pkg_a.name, pkg_b.name);
			}
			return 1;
		}
		if (pkg_a.name.has_prefix (global_search_string)) {
			if (pkg_b.name.has_prefix (global_search_string)) {
				return strcmp (pkg_a.name, pkg_b.name);
			}
			return 0;
		}
		if (pkg_b.name.has_prefix (global_search_string)) {
			if (pkg_a.name.has_prefix (global_search_string)) {
				return strcmp (pkg_a.name, pkg_b.name);
			}
			return 1;
		}
		if (pkg_a.name.contains (global_search_string)) {
			if (pkg_b.name.contains (global_search_string)) {
				return strcmp (pkg_a.name, pkg_b.name);
			}
			return 0;
		}
		if (pkg_b.name.contains (global_search_string)) {
			if (pkg_a.name.contains (global_search_string)) {
				return strcmp (pkg_a.name, pkg_b.name);
			}
			return 1;
		}
	}
	return strcmp (pkg_a.name, pkg_b.name);
}

namespace Pamac {
	[DBus (name = "org.manjaro.pamac.user")]
	public class UserDaemon: Object {
		private AlpmConfig alpm_config;
		private Alpm.Handle? alpm_handle;
		private Alpm.Handle? files_handle;
		private bool check_aur_updates;
		private bool aur_updates_checked;
		private Json.Array aur_updates_results;
		private HashTable<string, Json.Array> aur_search_results;
		private HashTable<string, Json.Object> aur_infos;

		public signal void get_updates_finished (Updates updates);

		public UserDaemon () {
			alpm_config = new AlpmConfig ("/etc/pacman.conf");
			aur_updates_results = new Json.Array ();
			aur_search_results = new HashTable<string, Json.Array> (str_hash, str_equal);
			aur_infos = new HashTable<string, Json.Object> (str_hash, str_equal);
			refresh_handle ();
		}

		public void refresh_handle () {
			alpm_handle = alpm_config.get_handle ();
			if (alpm_handle == null) {
				return;
			} else {
				files_handle = alpm_config.get_handle (true);
			}
		}

		public bool get_checkspace () {
			return alpm_handle.checkspace == 1 ? true : false;
		}

		public string get_lockfile () {
			return alpm_handle.lockfile;
		}

		public string[] get_ignorepkgs () {
			string[] result = {};
			unowned Alpm.List<unowned string> ignorepkgs = alpm_handle.ignorepkgs;
			while (ignorepkgs != null) {
				unowned string ignorepkg = ignorepkgs.data;
				result += ignorepkg;
				ignorepkgs.next ();
			}
			return result;
		}

		public bool should_hold (string pkgname) {
			if (alpm_config.get_holdpkgs ().find_custom (pkgname, strcmp) != null) {
				return true;
			}
			return false;
		}

		public uint get_pkg_reason (string pkgname) {
			unowned Alpm.Package? pkg = alpm_handle.localdb.get_pkg (pkgname);
			if (pkg != null) {
				return pkg.reason;
			}
			return 0;
		}

		public uint get_pkg_origin (string pkgname) {
			unowned Alpm.Package? pkg = alpm_handle.localdb.get_pkg (pkgname);
			if (pkg != null) {
				return pkg.origin;
			} else {
				pkg = get_syncpkg (pkgname);
				if (pkg != null) {
					return pkg.origin;
				}
			}
			return 0;
		}

		private AlpmPackage initialise_pkg_struct (Alpm.Package? alpm_pkg) {
			if (alpm_pkg != null) {
				string installed_version = "";
				string repo_name = "";
				if (alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
					installed_version = alpm_pkg.version;
					unowned Alpm.Package? sync_pkg = get_syncpkg (alpm_pkg.name);
					if (sync_pkg != null) {
						repo_name = sync_pkg.db.name;
					}
				} else if (alpm_pkg.origin == Alpm.Package.From.SYNCDB) {
					unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (alpm_pkg.name);
					if (local_pkg != null) {
						installed_version = local_pkg.version;
					}
					repo_name = alpm_pkg.db.name;
				}
				return AlpmPackage () {
					name = alpm_pkg.name,
					version = alpm_pkg.version,
					installed_version = (owned) installed_version,
					// desc can be null
					desc = alpm_pkg.desc ?? "",
					repo = (owned) repo_name,
					size = alpm_pkg.isize,
					download_size = alpm_pkg.download_size,
					origin = (uint) alpm_pkg.origin
				};
			} else {
				return AlpmPackage () {
					name = "",
					version = "",
					installed_version = "",
					desc = "",
					repo = ""
				};
			}
		}

		public async AlpmPackage[] get_installed_pkgs () {
			AlpmPackage[] pkgs = {};
			unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
			while (pkgcache != null) {
				unowned Alpm.Package alpm_pkg = pkgcache.data;
				pkgs += initialise_pkg_struct (alpm_pkg);
				pkgcache.next ();
			}
			return pkgs;
		}

		public async AlpmPackage[] get_explicitly_installed_pkgs () {
			AlpmPackage[] pkgs = {};
			unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
			while (pkgcache != null) {
				unowned Alpm.Package alpm_pkg = pkgcache.data;
				if (alpm_pkg.reason == Alpm.Package.Reason.EXPLICIT) {
					pkgs += initialise_pkg_struct (alpm_pkg);
				}
				pkgcache.next ();
			}
			return pkgs;
		}

		public async AlpmPackage[] get_foreign_pkgs () {
			AlpmPackage[] pkgs = {};
			unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
			while (pkgcache != null) {
				unowned Alpm.Package alpm_pkg = pkgcache.data;
				bool sync_found = false;
				unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
				while (syncdbs != null) {
					unowned Alpm.DB db = syncdbs.data;
					unowned Alpm.Package? sync_pkg = db.get_pkg (alpm_pkg.name);
					if (sync_pkg != null) {
						sync_found = true;
						break;
					}
					syncdbs.next ();
				}
				if (sync_found == false) {
					pkgs += initialise_pkg_struct (alpm_pkg);
				}
				pkgcache.next ();
			}
			return pkgs;
		}

		public async AlpmPackage[] get_orphans () {
			AlpmPackage[] pkgs = {};
			unowned Alpm.List<unowned Alpm.Package> pkgcache = alpm_handle.localdb.pkgcache;
			while (pkgcache != null) {
				unowned Alpm.Package alpm_pkg = pkgcache.data;
				if (alpm_pkg.reason == Alpm.Package.Reason.DEPEND) {
					Alpm.List<string> requiredby = alpm_pkg.compute_requiredby ();
					if (requiredby.length == 0) {
						Alpm.List<string> optionalfor = alpm_pkg.compute_optionalfor ();
						if (optionalfor.length == 0) {
							pkgs += initialise_pkg_struct (alpm_pkg);
						} else {
							optionalfor.free_inner (GLib.free);
						}
					} else {
						requiredby.free_inner (GLib.free);
					}
				}
				pkgcache.next ();
			}
			return pkgs;
		}

		public AlpmPackage get_installed_pkg (string pkgname) {
			return initialise_pkg_struct (alpm_handle.localdb.get_pkg (pkgname));
		}

		public AlpmPackage find_installed_satisfier (string depstring) {
			return initialise_pkg_struct (Alpm.find_satisfier (alpm_handle.localdb.pkgcache, depstring));
		}

		private unowned Alpm.Package? get_syncpkg (string name) {
			unowned Alpm.Package? pkg = null;
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				pkg = db.get_pkg (name);
				if (pkg != null) {
					break;
				}
				syncdbs.next ();
			}
			return pkg;
		}

		public AlpmPackage get_sync_pkg (string pkgname) {
			return initialise_pkg_struct (get_syncpkg (pkgname));
		}

		private unowned Alpm.Package? find_dbs_satisfier (string depstring) {
			unowned Alpm.Package? pkg = null;
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				pkg = Alpm.find_satisfier (db.pkgcache, depstring);
				if (pkg != null) {
					break;
				}
				syncdbs.next ();
			}
			return pkg;
		}

		public AlpmPackage find_sync_satisfier (string depstring) {
			return initialise_pkg_struct (find_dbs_satisfier (depstring));
		}

		private Alpm.List<unowned Alpm.Package> search_all_dbs (string search_string) {
			Alpm.List<unowned string> needles = null;
			string[] splitted = search_string.split (" ");
			foreach (unowned string part in splitted) {
				needles.add (part);
			}
			Alpm.List<unowned Alpm.Package> result = alpm_handle.localdb.search (needles);
			Alpm.List<unowned Alpm.Package> syncpkgs = null;
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				if (syncpkgs.length == 0) {
					syncpkgs = db.search (needles);
				} else {
					syncpkgs.join (db.search (needles).diff (syncpkgs, (Alpm.List.CompareFunc) alpm_pkg_compare_name));
				}
				syncdbs.next ();
			}
			result.join (syncpkgs.diff (result, (Alpm.List.CompareFunc) alpm_pkg_compare_name));
			// use custom sort function
			global_search_string = search_string;
			result.sort (result.length, (Alpm.List.CompareFunc) alpm_pkg_sort_search_by_relevance);
			return result;
		}

		public async AlpmPackage[] search_pkgs (string search_string) {
			AlpmPackage[] result = {};
			Alpm.List<unowned Alpm.Package> alpm_pkgs = search_all_dbs (search_string);
			unowned Alpm.List<unowned Alpm.Package> list = alpm_pkgs;
			while (list != null) {
				unowned Alpm.Package alpm_pkg = list.data;
				result += initialise_pkg_struct (alpm_pkg);
				list.next ();
			}
			return result;
		}

		private AURPackage initialise_aur_struct (Json.Object json_object) {
			string installed_version = "";
			unowned Alpm.Package? pkg = alpm_handle.localdb.get_pkg (json_object.get_string_member ("Name"));
			if (pkg != null) {
				installed_version = pkg.version;
			}
			return AURPackage () {
				name = json_object.get_string_member ("Name"),
				version = json_object.get_string_member ("Version"),
				installed_version = (owned) installed_version,
				// desc can be null
				desc = json_object.get_null_member ("Description") ? "" : json_object.get_string_member ("Description"),
				popularity = json_object.get_double_member ("Popularity")
			};
		}

		public async AURPackage[] search_in_aur (string search_string) {
			if (!aur_search_results.contains (search_string)) {
				Json.Array pkgs = yield AUR.search (search_string.split (" "));
				aur_search_results.insert (search_string, pkgs);
			}
			AURPackage[] result = {};
			Json.Array aur_pkgs = aur_search_results.get (search_string);
			aur_pkgs.foreach_element ((array, index, node) => {
				Json.Object aur_pkg = node.get_object ();
				// remove results which exist in repos
				if (get_syncpkg (aur_pkg.get_string_member ("Name")) == null) {
					result += initialise_aur_struct (node.get_object ());
				}
			});
			return result;
		}

		public async AURPackageDetails get_aur_details (string pkgname) {
			string name = "";
			string version = "";
			string desc = "";
			double popularity = 0;
			string packagebase = "";
			string url = "";
			string maintainer = "";
			int64 firstsubmitted = 0;
			int64 lastmodified = 0;
			int64 outofdate = 0;
			int64 numvotes = 0;
			string[] licenses = {};
			string[] depends = {};
			string[] makedepends = {};
			string[] checkdepends = {};
			string[] optdepends = {};
			string[] provides = {};
			string[] replaces = {};
			string[] conflicts = {};
			var details = AURPackageDetails ();
			if (!aur_infos.contains (pkgname)) {
				Json.Array results = yield AUR.multiinfo ({pkgname});
				if (results.get_length () > 0) {
					aur_infos.insert (pkgname, results.get_object_element (0));
				}
			}
			unowned Json.Object? json_object = aur_infos.lookup (pkgname);
			if (json_object != null) {
				// name
				name = json_object.get_string_member ("Name");
				// version
				version = json_object.get_string_member ("Version");
				// desc can be null
				if (!json_object.get_null_member ("Description")) {
					desc = json_object.get_string_member ("Description");
				}
				popularity = json_object.get_double_member ("Popularity");
				// packagebase
				packagebase = json_object.get_string_member ("PackageBase");
				// url can be null
				unowned Json.Node? node = json_object.get_member ("URL");
				if (!node.is_null ()) {
					url = node.get_string ();
				}
				// maintainer can be null
				node = json_object.get_member ("Maintainer");
				if (!node.is_null ()) {
					maintainer = node.get_string ();
				}
				// firstsubmitted
				firstsubmitted = json_object.get_int_member ("FirstSubmitted");
				// lastmodified
				lastmodified = json_object.get_int_member ("LastModified");
				// outofdate can be null
				node = json_object.get_member ("OutOfDate");
				if (!node.is_null ()) {
					outofdate = node.get_int ();
				}
				//numvotes
				numvotes = json_object.get_int_member ("NumVotes");
				// licenses
				node = json_object.get_member ("License");
				if (!node.is_null ()) {
					node.get_array ().foreach_element ((array, index, _node) => {
						licenses += _node.get_string ();
					});
				} else {
					licenses += _("Unknown");
				}
				// depends
				node = json_object.get_member ("Depends");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						depends += _node.get_string ();
					});
				}
				// optdepends
				node = json_object.get_member ("OptDepends");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						optdepends += _node.get_string ();
					});
				}
				// makedepends
				node = json_object.get_member ("MakeDepends");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						makedepends += _node.get_string ();
					});
				}
				// checkdepends
				node = json_object.get_member ("CheckDepends");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						checkdepends += _node.get_string ();
					});
				}
				// provides
				node = json_object.get_member ("Provides");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						provides += _node.get_string ();
					});
				}
				// replaces
				node = json_object.get_member ("Replaces");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						replaces += _node.get_string ();
					});
				}
				// conflicts
				node = json_object.get_member ("Conflicts");
				if (node != null) {
					node.get_array ().foreach_element ((array, index, _node) => {
						conflicts += _node.get_string ();
					});
				}
			}
			details.name = (owned) name;
			details.version = (owned) version ;
			details.desc = (owned) desc;
			details.popularity = popularity;
			details.packagebase = (owned) packagebase;
			details.url = (owned) url;
			details.maintainer = (owned) maintainer ;
			details.firstsubmitted = firstsubmitted;
			details.lastmodified = lastmodified;
			details.outofdate = outofdate;
			details.numvotes = numvotes;
			details.licenses = (owned) licenses;
			details.depends = (owned) depends;
			details.optdepends = (owned) optdepends;
			details.checkdepends = (owned) checkdepends;
			details.makedepends = (owned) makedepends;
			details.provides = (owned) provides;
			details.replaces = (owned) replaces;
			details.conflicts = (owned) conflicts;
			return details;
		}

		public string[] get_repos_names () {
			string[] repos_names = {};
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				repos_names += db.name;
				syncdbs.next ();
			}
			return repos_names;
		}

		public async AlpmPackage[] get_repo_pkgs (string repo) {
			AlpmPackage[] pkgs = {};
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				if (db.name == repo) {
					unowned Alpm.List<unowned Alpm.Package> pkgcache = db.pkgcache;
					while (pkgcache != null) {
						unowned Alpm.Package sync_pkg = pkgcache.data;
						unowned Alpm.Package? local_pkg = alpm_handle.localdb.get_pkg (sync_pkg.name);
						if (local_pkg != null) {
							pkgs += initialise_pkg_struct (local_pkg);
						} else {
							pkgs += initialise_pkg_struct (sync_pkg);
						}
						pkgcache.next ();
					}
					break;
				}
				syncdbs.next ();
			}
			return pkgs;
		}

		public string[] get_groups_names () {
			string[] groups_names = {};
			unowned Alpm.List<unowned Alpm.Group> groupcache = alpm_handle.localdb.groupcache;
			while (groupcache != null) {
				unowned Alpm.Group group = groupcache.data;
				if (!(group.name in groups_names)) { 
					groups_names += group.name;
				}
				groupcache.next ();
			}
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				groupcache = db.groupcache;
				while (groupcache != null) {
					unowned Alpm.Group group = groupcache.data;
					if (!(group.name in groups_names)) { 
						groups_names += group.name;
					}
					groupcache.next ();
				}
				syncdbs.next ();
			}
			return groups_names;
		}

		private Alpm.List<unowned Alpm.Package> group_pkgs (string group_name) {
			Alpm.List<unowned Alpm.Package> result = null;
			unowned Alpm.Group? grp = alpm_handle.localdb.get_group (group_name);
			if (grp != null) {
				unowned Alpm.List<unowned Alpm.Package> packages = grp.packages;
				while (packages != null) {
					unowned Alpm.Package pkg = packages.data;
					result.add (pkg);
					packages.next ();
				}
			}
			unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				grp = db.get_group (group_name);
				if (grp != null) {
					unowned Alpm.List<unowned Alpm.Package> packages = grp.packages;
					while (packages != null) {
						unowned Alpm.Package pkg = packages.data;
						if (result.find (pkg, (Alpm.List.CompareFunc) alpm_pkg_compare_name) == null) {
							result.add (pkg);
						}
						packages.next ();
					}
				}
				syncdbs.next ();
			}
			return result;
		}

		public async AlpmPackage[] get_group_pkgs (string groupname) {
			AlpmPackage[] pkgs = {};
			Alpm.List<unowned Alpm.Package> alpm_pkgs = group_pkgs (groupname);
			unowned Alpm.List<unowned Alpm.Package> list = alpm_pkgs;
			while (list != null) {
				unowned Alpm.Package alpm_pkg = list.data;
				pkgs += initialise_pkg_struct (alpm_pkg);
				list.next ();
			}
			return pkgs;
		}

		public string[] get_pkg_uninstalled_optdeps (string pkgname) {
			string[] optdeps = {};
			unowned Alpm.Package? alpm_pkg = alpm_handle.localdb.get_pkg (pkgname);
			if (alpm_pkg == null) {
				alpm_pkg = get_syncpkg (pkgname);
			}
			if (alpm_pkg != null) {
				unowned Alpm.List<unowned Alpm.Depend> optdepends = alpm_pkg.optdepends;
				while (optdepends != null) {
					unowned Alpm.Depend optdep = optdepends.data;
					if (Alpm.find_satisfier (alpm_handle.localdb.pkgcache, optdep.name) == null) {
						optdeps += optdep.compute_string ();
					}
					optdepends.next ();
				}
			}
			return optdeps;
		}

		public AlpmPackageDetails get_pkg_details (string pkgname) {
			string name = "";
			string version = "";
			string desc = "";
			string url = "";
			string repo = "";
			string has_signature = "";
			string reason = "";
			string packager = "";
			string builddate = "";
			string installdate = "";
			string[] groups = {};
			string[] backups = {};
			string[] licenses = {};
			string[] depends = {};
			string[] optdepends = {};
			string[] requiredby = {};
			string[] optionalfor = {};
			string[] provides = {};
			string[] replaces = {};
			string[] conflicts = {};
			var details = AlpmPackageDetails ();
			unowned Alpm.Package? alpm_pkg = alpm_handle.localdb.get_pkg (pkgname);
			if (alpm_pkg == null) {
				alpm_pkg = get_syncpkg (pkgname);
			}
			if (alpm_pkg != null) {
				// name
				name = alpm_pkg.name;
				// version
				version = alpm_pkg.version;
				// desc can be null
				if (alpm_pkg.desc != null) {
					desc = alpm_pkg.desc;
				}
				details.origin = (uint) alpm_pkg.origin;
				// url can be null
				if (alpm_pkg.url != null) {
					url = alpm_pkg.url;
				}
				// packager can be null
				packager = alpm_pkg.packager ?? "";
				// groups
				unowned Alpm.List list = alpm_pkg.groups;
				while (list != null) {
					groups += ((Alpm.List<unowned string>) list).data;
					list.next ();
				}
				// licenses
				list = alpm_pkg.licenses;
				while (list != null) {
					licenses += ((Alpm.List<unowned string>) list).data;
					list.next ();
				}
				// build_date
				GLib.Time time = GLib.Time.local ((time_t) alpm_pkg.builddate);
				builddate = time.format ("%a %d %b %Y %X %Z");
				// local pkg
				if (alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
					// repo
					unowned Alpm.Package? sync_pkg = get_syncpkg (alpm_pkg.name);
					if (sync_pkg != null) {
						repo = sync_pkg.db.name;
					}
					// reason
					if (alpm_pkg.reason == Alpm.Package.Reason.EXPLICIT) {
						reason = _("Explicitly installed");
					} else if (alpm_pkg.reason == Alpm.Package.Reason.DEPEND) {
						reason = _("Installed as a dependency for another package");
					} else {
						reason = _("Unknown");
					}
					// install_date
					time = GLib.Time.local ((time_t) alpm_pkg.installdate);
					installdate = time.format ("%a %d %b %Y %X %Z");
					// backups
					list = alpm_pkg.backups;
					while (list != null) {
						backups += "/" + ((Alpm.List<unowned Alpm.Backup>) list).data.name;
						list.next ();
					}
					// requiredby
					Alpm.List<string> pkg_requiredby = alpm_pkg.compute_requiredby ();
					list = pkg_requiredby;
					while (list != null) {
						requiredby += ((Alpm.List<unowned string>) list).data;
						list.next ();
					}
					pkg_requiredby.free_inner (GLib.free);
					// optionalfor
					Alpm.List<string> pkg_optionalfor = alpm_pkg.compute_optionalfor ();
					list = pkg_optionalfor;
					while (list != null) {
						optionalfor += ((Alpm.List<unowned string>) list).data;
						list.next ();
					}
					pkg_optionalfor.free_inner (GLib.free);
				// sync pkg
				} else if (alpm_pkg.origin == Alpm.Package.From.SYNCDB) {
					// repos
					repo = alpm_pkg.db.name;
					// signature
					has_signature = alpm_pkg.base64_sig != null ? _("Yes") : _("No");
				}
				// depends
				list = alpm_pkg.depends;
				while (list != null) {
					depends += ((Alpm.List<unowned Alpm.Depend>) list).data.compute_string ();
					list.next ();
				}
				// optdepends
				list = alpm_pkg.optdepends;
				while (list != null) {
					optdepends += ((Alpm.List<unowned Alpm.Depend>) list).data.compute_string ();
					list.next ();
				}
				// provides
				list = alpm_pkg.provides;
				while (list != null) {
					provides += ((Alpm.List<unowned Alpm.Depend>) list).data.compute_string ();
					list.next ();
				}
				// replaces
				list = alpm_pkg.replaces;
				while (list != null) {
					replaces += ((Alpm.List<unowned Alpm.Depend>) list).data.compute_string ();
					list.next ();
				}
				// conflicts
				list = alpm_pkg.conflicts;
				while (list != null) {
					conflicts += ((Alpm.List<unowned Alpm.Depend>) list).data.compute_string ();
					list.next ();
				}
			}
			details.name = (owned) name;
			details.version = (owned) version;
			details.desc = (owned) desc;
			details.repo = (owned) repo;
			details.url = (owned) url;
			details.packager = (owned) packager;
			details.builddate = (owned) builddate;
			details.installdate = (owned) installdate;
			details.reason = (owned) reason;
			details.has_signature = (owned) has_signature;
			details.licenses = (owned) licenses;
			details.depends = (owned) depends;
			details.optdepends = (owned) optdepends;
			details.requiredby = (owned) requiredby;
			details.optionalfor = (owned) optionalfor;
			details.provides = (owned) provides;
			details.replaces = (owned) replaces;
			details.conflicts = (owned) conflicts;
			details.groups = (owned) groups;
			details.backups = (owned) backups;
			return details;
		}

		public string[] get_pkg_files (string pkgname) {
			string[] files = {};
			unowned Alpm.Package? alpm_pkg = alpm_handle.localdb.get_pkg (pkgname);
			if (alpm_pkg != null) {
				unowned Alpm.FileList filelist = alpm_pkg.files;
				Alpm.File* file_ptr = filelist.files;
				for (size_t i = 0; i < filelist.count; i++, file_ptr++) {
					if (!file_ptr->name.has_suffix ("/")) {
						files += "/" + file_ptr->name;
					}
				}
			} else {
				unowned Alpm.List<unowned Alpm.DB> syncdbs = files_handle.syncdbs;
				while (syncdbs != null) {
					unowned Alpm.DB db = syncdbs.data;
					unowned Alpm.Package? files_pkg = db.get_pkg (pkgname);
					if (files_pkg != null) {
						unowned Alpm.FileList filelist = files_pkg.files;
						Alpm.File* file_ptr = filelist.files;
						for (size_t i = 0; i < filelist.count; i++, file_ptr++) {
							if (!file_ptr->name.has_suffix ("/")) {
								files += "/" + file_ptr->name;
							}
						}
						break;
					}
					syncdbs.next ();
				}
			}
			return files;
		}

		private int get_updates () {
			AlpmPackage[] updates_infos = {};
			unowned Alpm.Package? pkg = null;
			unowned Alpm.Package? candidate = null;
			// use a tmp handle
			var tmp_handle = alpm_config.get_handle (false, true);
			// refresh tmp dbs
			unowned Alpm.List<unowned Alpm.DB> syncdbs = tmp_handle.syncdbs;
			while (syncdbs != null) {
				unowned Alpm.DB db = syncdbs.data;
				db.update (0);
				syncdbs.next ();
			}
			string[] local_pkgs = {};
			unowned Alpm.List<unowned Alpm.Package> pkgcache = tmp_handle.localdb.pkgcache;
			while (pkgcache != null) {
				unowned Alpm.Package installed_pkg = pkgcache.data;
				// check if installed_pkg is in IgnorePkg or IgnoreGroup
				if (tmp_handle.should_ignore (installed_pkg) == 0) {
					candidate = installed_pkg.sync_newversion (tmp_handle.syncdbs);
					if (candidate != null) {
						var infos = initialise_pkg_struct (candidate);
						infos.installed_version = installed_pkg.version;
						updates_infos += (owned) infos;
					} else {
						if (check_aur_updates && (!aur_updates_checked)) {
							// check if installed_pkg is a local pkg
							syncdbs = tmp_handle.syncdbs;
							while (syncdbs != null) {
								unowned Alpm.DB db = syncdbs.data;
								pkg = Alpm.find_satisfier (db.pkgcache, installed_pkg.name);
								if (pkg != null) {
									break;
								}
								syncdbs.next ();
							}
							if (pkg == null) {
								local_pkgs += installed_pkg.name;
							}
						}
					}
				}
				pkgcache.next ();
			}
			if (check_aur_updates) {
				// get aur updates
				if (!aur_updates_checked) {
					AUR.multiinfo.begin (local_pkgs, (obj, res) => {
						aur_updates_results = AUR.multiinfo.end (res);
						aur_updates_checked = true;
						var updates = Updates () {
							repos_updates = (owned) updates_infos,
							aur_updates = get_aur_updates_infos ()
						};
						get_updates_finished (updates);
					});
				} else {
					var updates = Updates () {
						repos_updates = (owned) updates_infos,
						aur_updates = get_aur_updates_infos ()
					};
					get_updates_finished (updates);
				}
			} else {
				var updates = Updates () {
					repos_updates = (owned) updates_infos,
					aur_updates = {}
				};
				get_updates_finished (updates);
			}
			return 0;
		}

		private AURPackage[] get_aur_updates_infos () {
			AURPackage[] aur_updates_infos = {};
			aur_updates_results.foreach_element ((array, index, node) => {
				unowned Json.Object pkg_info = node.get_object ();
				unowned string name = pkg_info.get_string_member ("Name");
				unowned string new_version = pkg_info.get_string_member ("Version");
				unowned string old_version = alpm_handle.localdb.get_pkg (name).version;
				if (Alpm.pkg_vercmp (new_version, old_version) == 1) {
					var infos = initialise_aur_struct (pkg_info);
					infos.installed_version = old_version;
					aur_updates_infos += (owned) infos;
				}
			});
			return aur_updates_infos;
		}

		public void start_get_updates (bool check_aur_updates_) {
			check_aur_updates = check_aur_updates_;
			new Thread<int> ("get updates thread", get_updates);
		}

		[DBus (no_reply = true)]
		public void quit () {
			loop.quit ();
		}
	// End of Daemon Object
	}
}

void on_bus_acquired (DBusConnection conn) {
	user_daemon = new Pamac.UserDaemon ();
	try {
		conn.register_object ("/org/manjaro/pamac/user", user_daemon);
	}
	catch (IOError e) {
		stderr.printf ("Could not register service\n");
		loop.quit ();
	}
}

void main () {
	// i18n
	Intl.setlocale (LocaleCategory.ALL, "");
	Intl.textdomain (GETTEXT_PACKAGE);

	Bus.own_name (BusType.SESSION,
				"org.manjaro.pamac.user",
				BusNameOwnerFlags.NONE,
				on_bus_acquired,
				null,
				() => {
					stderr.printf ("Could not acquire name\n");
					loop.quit ();
				});

	loop = new MainLoop ();
	loop.run ();
}
