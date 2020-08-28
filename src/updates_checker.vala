/*
 *  pamac-vala
 *
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

namespace Pamac {
	public class UpdatesChecker : Object {
		MainLoop loop;
		Daemon system_daemon;
		Config config;
		bool extern_lock;
		uint check_lock_timeout_id;
		GLib.File lockfile;
		FileMonitor monitor;
		uint16 _updates_nb;
		public uint16 updates_nb { get { return _updates_nb; } }
		public uint64 refresh_period { get { return config.refresh_period; } }
		public bool no_update_hide_icon { get { return config.no_update_hide_icon; } }

		public signal void updates_available (uint16 updates_nb);

		public UpdatesChecker () {
			loop = new MainLoop ();
			config = new Config ("/etc/pamac.conf");
			extern_lock = false;

			start_system_daemon (config.environment_variables);
			string lockfile_str = "/var/lib/pacman/db.lck";
			try {
				lockfile_str = system_daemon.get_lockfile ();
			} catch (Error e) {
				warning (e.message);
			}
			stop_system_daemon ();

			lockfile = GLib.File.new_for_path (lockfile_str);
			try {
				monitor = lockfile.monitor (FileMonitorFlags.NONE, null);
				monitor.changed.connect (check_extern_lock);
			} catch (Error e) {
				warning (e.message);
			}
		}

		bool check_pamac_running () {
			Application app;
			bool run = false;
			app = new Application ("org.manjaro.pamac.manager", 0);
			try {
				app.register ();
			} catch (GLib.Error e) {
				warning (e.message);
			}
			run = app.get_is_remote ();
			if (run) {
				return run;
			}
			app = new Application ("org.manjaro.pamac.installer", 0);
			try {
				app.register ();
			} catch (GLib.Error e) {
				warning (e.message);
			}
			run = app.get_is_remote ();
			return run;
		}

		void start_system_daemon (HashTable<string,string> environment_variables) {
			if (system_daemon == null) {
				try {
					system_daemon = Bus.get_proxy_sync (BusType.SYSTEM, "org.manjaro.pamac.daemon", "/org/manjaro/pamac/daemon");
					// Set environment variables
					system_daemon.set_environment_variables (environment_variables);
					system_daemon.write_pamac_config_finished.connect (on_write_pamac_config_finished);
				} catch (Error e) {
					warning (e.message);
				}
			}
		}

		void stop_system_daemon () {
			if (!check_pamac_running ()) {
				try {
					system_daemon.quit ();
				} catch (Error e) {
					warning (e.message);
				}
			}
		}

		public bool check_updates () {
			if (loop.is_running ()) {
				loop.run ();
			}
			config.reload ();
			if (config.refresh_period != 0) {
				// get updates
				string[] cmds = {"pamac", "checkupdates", "-q", "--refresh-tmp-files-dbs", "--use-timestamp"};
				if (config.download_updates) {
					cmds+= "--download-updates";
				}
				message ("check updates");
				try {
					var process = new Subprocess.newv (cmds, SubprocessFlags.STDOUT_PIPE);
					process.wait_async.begin (null, () => {
						_updates_nb = 0;
						if (process.get_if_exited ()) {
							int status = process.get_exit_status ();
							// status 100 means updates are available
							if (status == 100) {
								var dis = new DataInputStream (process.get_stdout_pipe ());
								// count lines
								try {
									while (dis.read_line () != null) {
										_updates_nb++;
									}
								} catch (Error e) {
									warning (e.message);
								}
							}
						}
						loop.quit ();
					});
					loop.run ();
				} catch (Error e) {
					warning (e.message);
				}
				updates_available (_updates_nb);
				message ("%u updates found", _updates_nb);
			}
			return true;
		}

		void on_write_pamac_config_finished () {
			check_updates ();
		}

		bool check_lock_and_updates () {
			if (!lockfile.query_exists ()) {
				check_updates ();
			}
			check_lock_timeout_id = 0;
			return false;
		}

		void check_extern_lock (File src, File? dest, FileMonitorEvent event_type) {
			if (event_type == FileMonitorEvent.DELETED) {
				if (check_lock_timeout_id != 0) {
					Source.remove (check_lock_timeout_id);
				}
				check_lock_timeout_id = Timeout.add (500, check_lock_and_updates);
			}
		}
	}
}
