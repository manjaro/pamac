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

namespace Pamac {
	public struct UpdatesInfos {
		public string name;
		public string version;
		public string db_name;
		public string tarpath;
		public uint64 download_size;
	}

	public struct Updates {
		public bool syncfirst;
		public UpdatesInfos[] infos;
	}

	public enum Mode {
		MANAGER,
		UPDATER,
		NO_CONFIRM
	}
 
	public struct TransactionData {
		public Alpm.TransFlag flags;
		// those hashtables will be used as set
		public HashTable<string, string> to_add;
		public HashTable<string, string> to_remove;
		public HashTable<string, string> to_load;
		public HashTable<string, string> to_build;
	}

	public struct ErrorInfos {
		public string str;
		public string[] details;
		public ErrorInfos () {
			str = "";
			details = {};
		}
	}
}

public string format_size (uint64 size) {
	float KiB_size = size / 1024;
	if (KiB_size < 1000) {
		string size_string = dgettext ("pamac", "%.0f KiB").printf (KiB_size);
		return size_string;
	} else {
		string size_string = dgettext ("pamac", "%.2f MiB").printf (KiB_size / 1024);
		return size_string;
	}
}

public int pkgcmp (Alpm.Package pkg1, Alpm.Package pkg2) {
	return strcmp (pkg1.name, pkg2.name);
}

public unowned Alpm.List<Alpm.Package?> search_all_dbs (Alpm.Handle handle, Alpm.List<string?> needles) {
	unowned Alpm.List<Alpm.Package?> syncpkgs = null;
	unowned Alpm.List<Alpm.Package?> tmp = null;
	unowned Alpm.List<Alpm.Package?> diff = null;
	unowned Alpm.List<Alpm.Package?> result = null;

	result = handle.localdb.search (needles);

	foreach (unowned Alpm.DB db in handle.syncdbs) {
		if (syncpkgs.length == 0)
			syncpkgs = db.search (needles);
		else {
			tmp = db.search (needles);
			diff = tmp.diff (syncpkgs, (Alpm.List.CompareFunc) pkgcmp);
			syncpkgs.join (diff);
		}
	}

	diff = syncpkgs.diff (result, (Alpm.List.CompareFunc) pkgcmp);

	result.join (diff);
	//result.sort ((Alpm.List.CompareFunc) pkgcmp);

	return result;
}

public unowned Alpm.List<Alpm.Package?> group_pkgs_all_dbs (Alpm.Handle handle, string grp_name) {
	unowned Alpm.List<Alpm.Package?> result = null;

	unowned Alpm.Group? grp = handle.localdb.get_group (grp_name);
	if (grp != null) {
		foreach (unowned Alpm.Package pkg in grp.packages)
			result.add (pkg);
	}

	// FIX IT: provided methods don't work for syncdbs so it's done manually
	foreach (unowned Alpm.DB db in handle.syncdbs) {
		foreach (unowned Alpm.Package pkg in db.pkgcache) {
			foreach (string name in pkg.groups) {
				if (name == grp_name) {
					if (Alpm.pkg_find (result, pkg.name) == null)
						result.add (pkg);
				}
			}
		}
	}

	//result.sort ((Alpm.List.CompareFunc) pkgcmp);

	return result;
}

public unowned Alpm.List<Alpm.Package?> get_all_pkgs (Alpm.Handle handle) {
	unowned Alpm.List<Alpm.Package?> syncpkgs = null;
	unowned Alpm.List<Alpm.Package?> tmp = null;
	unowned Alpm.List<Alpm.Package?> diff = null;
	unowned Alpm.List<Alpm.Package?> result = null;

	result = handle.localdb.pkgcache;

	foreach (unowned Alpm.DB db in handle.syncdbs) {
		if (syncpkgs.length == 0)
			syncpkgs = db.pkgcache;
		else {
			tmp = db.pkgcache;
			diff = tmp.diff (syncpkgs, (Alpm.List.CompareFunc) pkgcmp);
			syncpkgs.join (diff);
		}
	}

	diff = syncpkgs.diff (result, (Alpm.List.CompareFunc) pkgcmp);

	result.join (diff);
	//result.sort ((Alpm.List.CompareFunc) pkgcmp);

	return result;
}

public unowned Alpm.Package? get_syncpkg (Alpm.Handle handle, string name) {
	unowned Alpm.Package? pkg = null;
	foreach (unowned Alpm.DB db in handle.syncdbs) {
		pkg = db.get_pkg (name);
		if (pkg != null)
			break;
	}
	return pkg;
}

public Pamac.UpdatesInfos[] get_syncfirst_updates (Alpm.Config alpm_config) {
	Pamac.UpdatesInfos infos = Pamac.UpdatesInfos ();
	Pamac.UpdatesInfos[] syncfirst_infos = {};
	unowned Alpm.Package? pkg = null;
	unowned Alpm.Package? candidate = null;
	foreach (string name in alpm_config.syncfirst) {
		pkg = Alpm.find_satisfier (alpm_config.handle.localdb.pkgcache, name);
		if (pkg != null) {
			candidate = Alpm.sync_newversion (pkg, alpm_config.handle.syncdbs);
			if (candidate != null) {
				infos.name = candidate.name;
				infos.version = candidate.version;
				infos.db_name = candidate.db.name;
				infos.tarpath = "";
				infos.download_size = candidate.download_size;
				syncfirst_infos += infos;
			}
		}
	}
	return syncfirst_infos;
}

public string[] get_ignore_pkgs (Alpm.Config alpm_config) {
	string[] ignore_pkgs = {};
	unowned Alpm.Group? group = null;
	foreach (string name in alpm_config.handle.ignorepkgs)
		ignore_pkgs += name;
	foreach (string grp_name in alpm_config.handle.ignoregroups) {
		group = alpm_config.handle.localdb.get_group (grp_name);
		if (group != null) {
			foreach (unowned Alpm.Package found_pkg in group.packages)
				ignore_pkgs += found_pkg.name;
		}
	}
	return ignore_pkgs;
}

public Pamac.UpdatesInfos[] get_repos_updates (Alpm.Config alpm_config, string[] ignore_pkgs) {
	unowned Alpm.Package? candidate = null;
	Pamac.UpdatesInfos infos = Pamac.UpdatesInfos ();
	Pamac.UpdatesInfos[] updates = {};
	foreach (unowned Alpm.Package local_pkg in alpm_config.handle.localdb.pkgcache) {
		// continue only if the local pkg is not in IgnorePkg or IgnoreGroup
		if ((local_pkg.name in ignore_pkgs) == false) {
			candidate = Alpm.sync_newversion (local_pkg, alpm_config.handle.syncdbs);
			if (candidate != null) {
				infos.name = candidate.name;
				infos.version = candidate.version;
				infos.db_name = candidate.db.name;
				infos.tarpath = "";
				infos.download_size = candidate.download_size;
				updates += infos;
			}
		}
	}
	return updates;
}

public Pamac.UpdatesInfos[] get_aur_updates (Alpm.Config alpm_config, string[] ignore_pkgs) {
	unowned Alpm.Package? sync_pkg = null;
	unowned Alpm.Package? candidate = null;
	string[] local_pkgs = {};
	Pamac.UpdatesInfos infos = Pamac.UpdatesInfos ();
	Pamac.UpdatesInfos[] aur_updates = {};
	// get local pkgs
	foreach (unowned Alpm.Package local_pkg in alpm_config.handle.localdb.pkgcache) {
		// continue only if the local pkg is not in IgnorePkg or IgnoreGroup
		if ((local_pkg.name in ignore_pkgs) == false) {
			// check updates from AUR only for local packages
			foreach (unowned Alpm.DB db in alpm_config.handle.syncdbs) {
				sync_pkg = Alpm.find_satisfier (db.pkgcache, local_pkg.name);
				if (sync_pkg != null)
					break;
			}
			if (sync_pkg == null) {
				// check update from AUR only if no package from dbs will replace it
				candidate = Alpm.sync_newversion (local_pkg, alpm_config.handle.syncdbs);
				if (candidate == null) {
					local_pkgs += local_pkg.name;
				}
			}
		}
	}
	// get aur updates
	Json.Array aur_pkgs = AUR.multiinfo (local_pkgs);
	int cmp;
	string version;
	string name;
	foreach (Json.Node node in aur_pkgs.get_elements ()) {
		unowned Json.Object pkg_info = node.get_object ();
		version = pkg_info.get_string_member ("Version");
		name = pkg_info.get_string_member ("Name");
		cmp = Alpm.pkg_vercmp (version, alpm_config.handle.localdb.get_pkg (name).version);
		if (cmp == 1) {
			infos.name = name;
			infos.version = version;
			infos.db_name = "AUR";
			infos.tarpath = pkg_info.get_string_member ("URLPath");
			infos.download_size = 0;
			aur_updates += infos;
		}
	}
	return aur_updates;
}
