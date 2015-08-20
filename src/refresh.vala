/*
 *  pamac-vala
 *
 *  Copyright (C) 2014 Guillaume Benoit <guillaume@manjaro.org>
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
	public struct ErrorInfos {
		public string message;
		public string[] details;
	}
	[DBus (name = "org.manjaro.pamac")]
	public interface Daemon : Object {
		public abstract void start_refresh (int force) throws IOError;
		[DBus (no_reply = true)]
		public abstract void quit () throws IOError;
		public signal void refresh_finished (ErrorInfos error);
	}
}

Pamac.Daemon pamac_daemon;
MainLoop loop;

bool check_pamac_running () {
	Application app;
	bool run = false;
	app = new Application ("org.manjaro.pamac.manager", 0);
	try {
		app.register ();
	} catch (GLib.Error e) {
		stderr.printf ("%s\n", e.message);
	}
	run = app.get_is_remote ();
	if (run) {
		return run;
	}
	app = new Application ("org.manjaro.pamac.updater", 0);
	try {
		app.register ();
	} catch (GLib.Error e) {
		stderr.printf ("%s\n", e.message);
	}
	run = app.get_is_remote ();
	if (run) {
		return run;
	}
	app = new Application ("org.manjaro.pamac.install", 0);
	try {
		app.register ();
	} catch (GLib.Error e) {
		stderr.printf ("%s\n", e.message);
	}
	run = app.get_is_remote ();
	return run;
}

void on_refresh_finished () {
	if (check_pamac_running () == false) {
		try {
			pamac_daemon.quit ();
		} catch (IOError e) {
			stderr.printf ("IOError: %s\n", e.message);
		}
	}
	loop.quit ();
}

int main () {
	if (check_pamac_running () == false) {
		try {
			pamac_daemon = Bus.get_proxy_sync (BusType.SYSTEM, "org.manjaro.pamac",
													"/org/manjaro/pamac");
			pamac_daemon.refresh_finished.connect (on_refresh_finished);
			pamac_daemon.start_refresh (0);
			loop = new MainLoop ();
			loop.run ();
		} catch (IOError e) {
			stderr.printf ("IOError: %s\n", e.message);
		}
	}
	return 0;
}
