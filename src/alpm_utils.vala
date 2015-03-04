/*
 *  pamac-vala
 *
 *  Copyright (C) 2015  Guillaume Benoit <guillaume@manjaro.org>
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

public Alpm.List<unowned Alpm.Package?> group_pkgs (Alpm.Handle handle, string grp_name) {
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

public Alpm.List<unowned Alpm.Package?> all_pkgs (Alpm.Handle handle) {
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
