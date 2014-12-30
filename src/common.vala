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

	public enum Mode {
		MANAGER,
		UPDATER
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

public Alpm.List<unowned Alpm.Package?> search_all_dbs (Alpm.Handle handle, Alpm.List<string?> needles) {
	var syncpkgs = new Alpm.List<unowned Alpm.Package?> ();
	var result = handle.localdb.search (needles);

	foreach (var db in handle.syncdbs) {
		if (syncpkgs.length == 0)
			syncpkgs = db.search (needles);
		else {
			syncpkgs.join (db.search (needles).diff (syncpkgs, (Alpm.List.CompareFunc) pkgcmp));
		}
	}

	result.join (syncpkgs.diff (result, (Alpm.List.CompareFunc) pkgcmp));
	//result.sort ((Alpm.List.CompareFunc) pkgcmp);

	return result;
}

public Alpm.List<unowned Alpm.Package?> group_pkgs_all_dbs (Alpm.Handle handle, string grp_name) {
	var result = new Alpm.List<unowned Alpm.Package?> ();

	unowned Alpm.Group? grp = handle.localdb.get_group (grp_name);
	if (grp != null) {
		foreach (var pkg in grp.packages)
			result.add (pkg);
	}

	result.join (Alpm.find_group_pkgs (handle.syncdbs, grp_name).diff (result, (Alpm.List.CompareFunc) pkgcmp));

	//result.sort ((Alpm.List.CompareFunc) pkgcmp);

	return result;
}

public Alpm.List<unowned Alpm.Package?> get_all_pkgs (Alpm.Handle handle) {
	var syncpkgs = new Alpm.List<unowned Alpm.Package?> ();
	var result = new Alpm.List<unowned Alpm.Package?> ();
	result = handle.localdb.pkgcache.copy ();

	foreach (var db in handle.syncdbs) {
		if (syncpkgs.length == 0)
			syncpkgs = db.pkgcache.copy ();
		else {
			syncpkgs.join (db.pkgcache.diff (syncpkgs, (Alpm.List.CompareFunc) pkgcmp));
		}
	}

	result.join (syncpkgs.diff (result, (Alpm.List.CompareFunc) pkgcmp));
	//result.sort ((Alpm.List.CompareFunc) pkgcmp);

	return result;
}

public unowned Alpm.Package? get_syncpkg (Alpm.Handle handle, string name) {
	unowned Alpm.Package? pkg = null;
	foreach (var db in handle.syncdbs) {
		pkg = db.get_pkg (name);
		if (pkg != null)
			break;
	}
	return pkg;
}

public Pamac.UpdatesInfos[] get_syncfirst_updates (Alpm.Handle handle, GLib.List<string> syncfirsts) {
	Pamac.UpdatesInfos infos = Pamac.UpdatesInfos ();
	Pamac.UpdatesInfos[] syncfirst_infos = {};
	unowned Alpm.Package? pkg = null;
	unowned Alpm.Package? candidate = null;
	foreach (var name in syncfirsts) {
		pkg = Alpm.find_satisfier (handle.localdb.pkgcache, name);
		if (pkg != null) {
			candidate = pkg.sync_newversion (handle.syncdbs);
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

public Pamac.UpdatesInfos[] get_repos_updates (Alpm.Handle handle) {
	unowned Alpm.Package? candidate = null;
	Pamac.UpdatesInfos infos = Pamac.UpdatesInfos ();
	Pamac.UpdatesInfos[] updates = {};
	foreach (var local_pkg in handle.localdb.pkgcache) {
		// continue only if the local pkg is not in IgnorePkg or IgnoreGroup
		if (handle.should_ignore (local_pkg) == 0) {
			candidate = local_pkg.sync_newversion (handle.syncdbs);
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

public Pamac.UpdatesInfos[] get_aur_updates (Alpm.Handle handle) {
	unowned Alpm.Package? sync_pkg = null;
	unowned Alpm.Package? candidate = null;
	string[] local_pkgs = {};
	Pamac.UpdatesInfos infos = Pamac.UpdatesInfos ();
	Pamac.UpdatesInfos[] aur_updates = {};
	// get local pkgs
	foreach (var local_pkg in handle.localdb.pkgcache) {
		// continue only if the local pkg is not in IgnorePkg or IgnoreGroup
		if (handle.should_ignore (local_pkg) == 0) {
			// check updates from AUR only for local packages
			foreach (var db in handle.syncdbs) {
				sync_pkg = Alpm.find_satisfier (db.pkgcache, local_pkg.name);
				if (sync_pkg != null)
					break;
			}
			if (sync_pkg == null) {
				// check update from AUR only if no package from dbs will replace it
				candidate = local_pkg.sync_newversion (handle.syncdbs);
				if (candidate == null) {
					local_pkgs += local_pkg.name;
				}
			}
		}
	}
	// get aur updates
	var aur_pkgs = AUR.multiinfo (local_pkgs);
	int cmp;
	unowned Json.Object pkg_info;
	string version;
	string name;
	foreach (var node in aur_pkgs.get_elements ()) {
		pkg_info = node.get_object ();
		version = pkg_info.get_string_member ("Version");
		name = pkg_info.get_string_member ("Name");
		cmp = Alpm.pkg_vercmp (version, handle.localdb.get_pkg (name).version);
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
