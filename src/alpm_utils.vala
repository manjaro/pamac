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

public int alpm_pkg_compare_name (Alpm.Package pkg_a, Alpm.Package pkg_b) {
	return strcmp (pkg_a.name, pkg_b.name);
}

public int alpm_pkg_compare_origin (Alpm.Package pkg_a, Alpm.Package pkg_b) {
	return (int) (pkg_a.origin > pkg_b.origin) - (int) (pkg_a.origin < pkg_b.origin);
}

public int alpm_pkg_compare_version (Alpm.Package pkg_a, Alpm.Package pkg_b) {
	return Alpm.pkg_vercmp (pkg_a.version, pkg_b.version);
}

public int alpm_pkg_compare_db_name (Alpm.Package pkg_a, Alpm.Package pkg_b) {
	return strcmp (pkg_a.db.name, pkg_b.db.name);
}

public int alpm_pkg_compare_installed_size (Alpm.Package pkg_a, Alpm.Package pkg_b) {
	return (int) (pkg_a.isize > pkg_b.isize) - (int) (pkg_a.isize < pkg_b.isize);
}

public class AlpmUtils {
	AlpmConfig alpm_config;

	public AlpmUtils (string conf_file_path) {
		alpm_config = new AlpmConfig (conf_file_path);
		alpm_config.set_handle ();
	}

	public bool reload () {
		alpm_config.reload ();
		alpm_config.set_handle ();
		if (alpm_config.handle != null) {
			return true;
		}
		return false;
	}

	public int get_checkspace () {
		return alpm_config.checkspace;
	}

	public unowned GLib.List<string> get_holdpkgs () {
		return alpm_config.holdpkgs;
	}

	public unowned Alpm.List<unowned string?> get_ignorepkgs () {
		return alpm_config.ignorepkgs;
	}

	public unowned Alpm.Package? get_installed_pkg (string pkg_name) {
		return alpm_config.handle.localdb.get_pkg (pkg_name);
	}

	public unowned Alpm.Package? get_sync_pkg (string pkg_name) {
		unowned Alpm.Package? pkg = null;
		foreach (var db in alpm_config.handle.syncdbs) {
			pkg = db.get_pkg (pkg_name);
			if (pkg != null) {
				break;
			}
		}
		return pkg;
	}

	public unowned Alpm.DB? get_localdb () {
		return alpm_config.handle.localdb;
	}

	public unowned Alpm.List<unowned Alpm.DB?> get_syncdbs () {
		return alpm_config.handle.syncdbs;
	}

	public Alpm.List<unowned Alpm.Package?> search_all_dbs (string search_string) {
		var syncpkgs = new Alpm.List<unowned Alpm.Package?> ();
		var needles = new Alpm.List<unowned string> ();
		string[] splitted = search_string.split (" ");
		foreach (unowned string part in splitted) {
			needles.add (part);
		}
		var result = alpm_config.handle.localdb.search (needles);
		foreach (var db in alpm_config.handle.syncdbs) {
			if (syncpkgs.length == 0) {
				syncpkgs = db.search (needles);
			} else {
				syncpkgs.join (db.search (needles).diff (syncpkgs, (Alpm.List.CompareFunc) alpm_pkg_compare_name));
			}
		}
		result.join (syncpkgs.diff (result, (Alpm.List.CompareFunc) alpm_pkg_compare_name));
		//result.sort ((Alpm.List.CompareFunc) alpm_pkg_compare_name);
		return result;
	}

	public Alpm.List<unowned Alpm.Package?> get_group_pkgs (string group_name) {
		var result = new Alpm.List<unowned Alpm.Package?> ();
		unowned Alpm.Group? grp = alpm_config.handle.localdb.get_group (group_name);
		if (grp != null) {
			foreach (var pkg in grp.packages) {
				result.add (pkg);
			}
		}
		result.join (Alpm.find_group_pkgs (alpm_config.handle.syncdbs, group_name).diff (result, (Alpm.List.CompareFunc) alpm_pkg_compare_name));
		//result.sort ((Alpm.List.CompareFunc) alpm_pkg_compare_name);
		return result;
	}

	public Alpm.List<unowned Alpm.Package?> get_installed_pkgs () {
		return alpm_config.handle.localdb.pkgcache.copy ();
	}

	public Alpm.List<unowned Alpm.Package?> get_orphans () {
		var result = new Alpm.List<unowned Alpm.Package?> ();
		foreach (var pkg in alpm_config.handle.localdb.pkgcache) {
			if (pkg.reason == Alpm.Package.Reason.DEPEND) {
				Alpm.List<string?> requiredby = pkg.compute_requiredby ();
				if (requiredby.length == 0) {
					Alpm.List<string?> optionalfor = pkg.compute_optionalfor ();
					if (optionalfor.length == 0) {
						result.add (pkg);
					}
					optionalfor.free_data ();
				}
				requiredby.free_data ();
			}
		}
		return result;
	}

	public Alpm.List<unowned Alpm.Package?> get_local_pkgs () {
		var result = new Alpm.List<unowned Alpm.Package?> ();
		foreach (var pkg in alpm_config.handle.localdb.pkgcache) {
			if (get_sync_pkg (pkg.name) == null) {
				result.add (pkg);
			}
		}
		return result;
	}

	public Alpm.List<unowned Alpm.Package?> get_repo_pkgs (string repo_name) {
		var result = new Alpm.List<unowned Alpm.Package?> ();
		foreach (var db in alpm_config.handle.syncdbs) {
			if (db.name == repo_name) {
				foreach (var sync_pkg in db.pkgcache) {
					unowned Alpm.Package?local_pkg = alpm_config.handle.localdb.get_pkg (sync_pkg.name);
					if (local_pkg != null) {
						result.add (local_pkg);
					} else {
						result.add (sync_pkg);
					}
				}
			}
		}
		return result;
	}

	public Alpm.List<unowned Alpm.Package?> get_all_pkgs () {
		var syncpkgs = new Alpm.List<unowned Alpm.Package?> ();
		var result = new Alpm.List<unowned Alpm.Package?> ();
		result = alpm_config.handle.localdb.pkgcache.copy ();
		foreach (var db in alpm_config.handle.syncdbs) {
			if (syncpkgs.length == 0)
				syncpkgs = db.pkgcache.copy ();
			else {
				syncpkgs.join (db.pkgcache.diff (syncpkgs, (Alpm.List.CompareFunc) alpm_pkg_compare_name));
			}
		}
		result.join (syncpkgs.diff (result, (Alpm.List.CompareFunc) alpm_pkg_compare_name));
		//result.sort ((Alpm.List.CompareFunc) alpm_pkg_compare_name);
		return result;
	}

}
