/*
 *  Copyright (C) 2019-2021 Guillaume Benoit <guillaume@manjaro.org>
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

int main (string[] args) {
	if (args.length != 2) {
		stdout.printf ("Error: one dependecy argument needed\n");
		return 1;
	}
	var alpm_config = new AlpmConfig ("/etc/pacman.conf");
	Alpm.Handle? alpm_handle = alpm_config.get_handle ();
	if (alpm_handle == null) {
		warning ("Failed to initialize alpm library");
		return 1;
	}
	unowned string depend = args[1];
	unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
	while (syncdbs != null) {
		unowned Alpm.DB db = syncdbs.data;
		unowned Alpm.List<unowned Alpm.Package> cache = db.pkgcache;
		while (cache != null) {
			unowned Alpm.Package pkg = cache.data;
			bool found = false;
			// deps
			unowned Alpm.List<unowned Alpm.Depend> depends = pkg.depends;
			while (depends != null) {
				unowned Alpm.Depend dep = depends.data;
				if (dep.name == depend) {
					stdout.printf ("%s/%s depends on %s (built by %s)\n", db.name, pkg.name, dep.compute_string (), pkg.packager);
					found = true;
				}
				depends.next ();
			}
			// optdeps
			if (!found) {
				depends = pkg.optdepends;
				while (depends != null) {
					unowned Alpm.Depend dep = depends.data;
					if (dep.name == depend) {
						stdout.printf ("%s/%s optionally depends on %s (built by %s)\n", db.name, pkg.name, dep.compute_string (), pkg.packager);
						found = true;
					}
					depends.next ();
				}
			}
			// makedeps
			if (!found) {
				depends = pkg.makedepends;
				while (depends != null) {
					unowned Alpm.Depend dep = depends.data;
					if (dep.name == depend) {
						stdout.printf ("%s/%s make depends on %s (built by %s)\n", db.name, pkg.name, dep.compute_string (), pkg.packager);
						found = true;
					}
					depends.next ();
				}
			}
			// checkdeps
			if (!found) {
				depends = pkg.checkdepends;
				while (depends != null) {
					unowned Alpm.Depend dep = depends.data;
					if (dep.name == depend) {
						stdout.printf ("%s/%s check depends on %s (built by %s)\n", db.name, pkg.name, dep.compute_string (), pkg.packager);
					}
					depends.next ();
				}
			}
			cache.next ();
		}
		syncdbs.next ();
	}
	return 0;
}
