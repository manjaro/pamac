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
		Config config;
		uint check_localdb_timeout_id;
		GLib.File localdb;
		FileMonitor monitor;
		uint16 _updates_nb;
		string[] _updates_list;
		public uint16 updates_nb { get { return _updates_nb; } }
		public string[] updates_list { get { return _updates_list; } }
		public uint64 refresh_period { get { return config.refresh_period; } }
		public bool no_update_hide_icon { get { return config.no_update_hide_icon; } }

		public signal void updates_available (uint16 updates_nb);

		public UpdatesChecker () {
			Object ();
		}

		construct {
			loop = new MainLoop ();
			config = new Config ("/etc/pamac.conf");
			string localdb_str = Path.build_filename (config.db_path, "local");
			localdb = GLib.File.new_for_path (localdb_str);
			try {
				monitor = localdb.monitor_directory (FileMonitorFlags.NONE);
				monitor.changed.connect (on_localdb_changed);
			} catch (Error e) {
				warning (e.message);
			}
		}

		public void check_updates () {
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
						_updates_list = {};
						if (process.get_if_exited ()) {
							int status = process.get_exit_status ();
							// status 100 means updates are available
							if (status == 100) {
								var dis = new DataInputStream (process.get_stdout_pipe ());
								// count lines
								try {
									string line;
									while ((line = dis.read_line ()) != null) {
										_updates_nb++;
										_updates_list += line;
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
		}

		void on_localdb_changed (File src, File? dest, FileMonitorEvent event_type) {
			if (check_localdb_timeout_id != 0) {
				Source.remove (check_localdb_timeout_id);
			}
			check_localdb_timeout_id = Timeout.add (5000, () => {
				check_updates ();
				check_localdb_timeout_id = 0;
				return false;
			});
		}
	}
}
