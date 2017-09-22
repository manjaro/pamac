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

int main () {
	var pamac_config = new Pamac.Config ("/etc/pamac.conf");
	string rm_only_uninstalled_str = "";
	if (pamac_config.rm_only_uninstalled) {
		rm_only_uninstalled_str = "-u";
	}
	try {
		Process.spawn_command_line_sync ("paccache -q --nocolor %s -r -k %llu".printf (rm_only_uninstalled_str, pamac_config.keep_num_pkgs));
	} catch (SpawnError e) {
		stderr.printf ("SpawnError: %s\n", e.message);
	}
	return 0;
}
