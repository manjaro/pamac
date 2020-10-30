/*
 *  Copyright (C) 2020 Guillaume Benoit <guillaume@manjaro.org>
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
	// get packages build over 3 years ago by default
	uint years = 3;
	if (args.length > 2) {
		stderr.printf ("Error: only one argument needed\n");
		return 1;
	}
	if (args.length == 2) {
		if (args[1] == "-h" || args[1] == "--help") {
			stdout.printf ("Usage:  outdated-checker <number_of_years>\n\n");
			stdout.printf ("Displays packages built a given number of years ago\n");
			stdout.printf ("The number of years is optional, default to 3\n");
			return 0;
		}
		uint nb;
		if (uint.try_parse (args[1], out nb)) {
			years = nb;
		} else {
			stderr.printf ("Error parsing number of years argument\n");
			return 1;
		}
	}
	var alpm_config = new AlpmConfig ("/etc/pacman.conf");
	Alpm.Handle? alpm_handle = alpm_config.get_handle ();
	if (alpm_handle == null) {
		warning ("Failed to initialize alpm library");
		return 1;
	}
	var now = new DateTime.now_utc ();
	// get packages
	TimeSpan years_time = TimeSpan.DAY * 365 * years;
	var found = new GenericArray<unowned Alpm.Package> ();
	unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
	while (syncdbs != null) {
		unowned Alpm.DB db = syncdbs.data;
		unowned Alpm.List<unowned Alpm.Package> cache = db.pkgcache;
		while (cache != null) {
			unowned Alpm.Package pkg = cache.data;
			if (pkg.builddate != 0) {
				var build_time = new DateTime.from_unix_utc ((int64) pkg.builddate);
				TimeSpan elapsed_time = now.difference (build_time);
				if (elapsed_time > years_time) {
					found.add (pkg);
					
				}
			}
			cache.next ();
		}
		syncdbs.next ();
	}
	// print found packages sorted by date
	found.sort ((pkg1, pkg2) => {
		var date1 = pkg1.builddate;
		var date2 = pkg2.builddate;
		if (date1 < date2) return 1;
		if (date1 > date2) return -1;
		return 0;
	});
	stdout.printf ("Packages built over %u years ago:\n", years);
	foreach (unowned Alpm.Package pkg in found) {
		var build_time = new DateTime.from_unix_utc ((int64) pkg.builddate);
		stdout.printf ("%s/%s: built the %s by %s\n", pkg.db.name, pkg.name, build_time.format ("%x"), pkg.packager);
		Alpm.List<string> requiredby = pkg.compute_requiredby ();
		if (requiredby != null) {
			stdout.printf ("  required by:\n");
			unowned Alpm.List<string> list = requiredby;
			while (list != null) {
				stdout.printf ("    %s\n", list.data);
				list.next ();
			}
			requiredby.free_inner (GLib.free);
		}
	}
	return 0;
}
