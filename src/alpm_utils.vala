/*
 *  pamac-vala
 *
 *  Copyright (C) 2015-2016 Guillaume Benoit <guillaume@manjaro.org>
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

int compare_name (Alpm.Package pkg_a, Alpm.Package pkg_b) {
	return strcmp (pkg_a.name, pkg_b.name);
}

int compare_state (Alpm.Package pkg_a, Alpm.Package pkg_b) {
	return (int) (pkg_a.origin > pkg_b.origin) - (int) (pkg_a.origin < pkg_b.origin);
}

int compare_version (Alpm.Package pkg_a, Alpm.Package pkg_b) {
	return Alpm.pkg_vercmp (pkg_a.version, pkg_b.version);
}

int compare_repo (Alpm.Package pkg_a, Alpm.Package pkg_b) {
	return strcmp (pkg_a.db.name, pkg_b.db.name);
}

int compare_size (Alpm.Package pkg_a, Alpm.Package pkg_b) {
	return (int) (pkg_a.isize > pkg_b.isize) - (int) (pkg_a.isize < pkg_b.isize);
}
