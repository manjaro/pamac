/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2019 Guillaume Benoit <guillaume@manjaro.org>
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

// i18n
const string GETTEXT_PACKAGE = "pamac";

Pamac.SystemDaemon system_daemon;
MainLoop loop;

public delegate void AlpmActionDelegate ();

[Compact]
public class AlpmAction {
	public unowned AlpmActionDelegate action_delegate;
	public AlpmAction (AlpmActionDelegate action_delegate) {
		this.action_delegate = action_delegate;
	}
	public void run () {
		action_delegate ();
	}
}

namespace Pamac {
	[DBus (name = "org.manjaro.pamac.system")]
	public class SystemDaemon: Object {
		private Config config;
		private bool refreshed;
		private HashTable<string,Variant> new_alpm_conf;
		private string mirrorlist_country;
		private ThreadPool<AlpmAction> thread_pool;
		private BusName lock_id;
		private bool authorized;
		private GLib.File lockfile;

		public signal void emit_event (uint primary_event, uint secondary_event, string[] details);
		public signal void emit_providers (string depend, string[] providers);
		public signal void emit_unresolvables (string[] unresolvables);
		public signal void emit_progress (uint progress, string pkgname, uint percent, uint n_targets, uint current_target);
		public signal void emit_download (string filename, uint64 xfered, uint64 total);
		public signal void emit_totaldownload (uint64 total);
		public signal void emit_log (uint level, string msg);
		public signal void set_pkgreason_finished (bool success);
		public signal void refresh_finished (bool success);
		public signal void database_modified ();
		public signal void downloading_updates_finished ();
		public signal void trans_prepare_finished (bool success);
		public signal void trans_commit_finished (bool success);
		public signal void get_authorization_finished (bool authorized);
		public signal void write_pamac_config_finished (bool recurse, uint64 refresh_period, bool no_update_hide_icon,
														bool enable_aur, string aur_build_dir, bool check_aur_updates,
														bool check_aur_vcs_updates, bool download_updates);
		public signal void write_alpm_config_finished (bool checkspace);
		public signal void generate_mirrors_list_data (string line);
		public signal void generate_mirrors_list_finished ();
		public signal void clean_cache_finished (bool success);
		public signal void clean_build_files_finished (bool success);

		public SystemDaemon () {
			config = new Config ("/etc/pamac.conf");
			lock_id = new BusName ("");
			authorized = false;
			// alpm_utils global variable declared in alpm_utils.vala
			alpm_utils = new AlpmUtils (config);
			lockfile = GLib.File.new_for_path (alpm_utils.alpm_handle.lockfile);
			check_old_lock ();
			check_extern_lock ();
			Timeout.add (200, check_extern_lock);
			create_thread_pool ();
			refreshed = false;
			alpm_utils.emit_event.connect ((primary_event, secondary_event, details) => {
				emit_event (primary_event, secondary_event, details);
			});
			alpm_utils.emit_providers.connect ((depend, providers) => {
				emit_providers (depend, providers);
			});
			alpm_utils.emit_unresolvables.connect ((unresolvables) => {
				emit_unresolvables (unresolvables);
			});
			alpm_utils.emit_progress.connect ((progress, pkgname, percent, n_targets, current_target) => {
				emit_progress (progress, pkgname, percent, n_targets, current_target);
			});
			alpm_utils.emit_download.connect ((filename, xfered, total) => {
				emit_download (filename, xfered, total);
			});
			alpm_utils.emit_totaldownload.connect ((total) => {
				emit_totaldownload (total);
			});
			alpm_utils.emit_log.connect ((level, msg) => {
				emit_log (level, msg);
			});
			alpm_utils.refresh_finished.connect ((success) => {
				refresh_finished (success);
			});
			alpm_utils.downloading_updates_finished.connect (() => {
				downloading_updates_finished ();
			});
			alpm_utils.trans_prepare_finished.connect ((success) => {
				if (!success) {
					unlock_priv ();
				}
				trans_prepare_finished (success);
			});
			alpm_utils.trans_commit_finished.connect ((success) => {
				unlock_priv ();
				database_modified ();
				trans_commit_finished (success);
			});
		}

		public void set_environment_variables (HashTable<string,string> variables) throws Error {
			string[] keys = { "HTTP_USER_AGENT",
							"http_proxy",
							"https_proxy",
							"ftp_proxy",
							"socks_proxy",
							"no_proxy" };
			foreach (unowned string key in keys) {
				unowned string val;
				if (variables.lookup_extended (key, null, out val)) {
					Environment.set_variable (key, val, true);
				}
			}
		}

		public string get_lockfile () throws Error {
			return alpm_utils.alpm_handle.lockfile;
		}

		public ErrorInfos get_current_error () throws Error {
			return alpm_utils.current_error;
		}

		private void create_thread_pool () {
			// create a thread pool which will run alpm action one after one
			try {
				thread_pool = new ThreadPool<AlpmAction>.with_owned_data (
					// call alpm_action.run () on thread start
					(alpm_action) => {
						alpm_action.run ();
					},
					// only one thread created so alpm action will run one after one
					1,
					// no exclusive thread
					false
				);
			} catch (ThreadError e) {
				stderr.printf ("Thread Error %s\n", e.message);
			}
		}

		private void check_old_lock () {
			if (lockfile.query_exists ()) {
				int exit_status;
				string output;
				uint64 lockfile_time;
				try {
					// get lockfile modification time since epoch
					Process.spawn_command_line_sync ("stat -c %Y %s".printf (alpm_utils.alpm_handle.lockfile),
													out output,
													null,
													out exit_status);
					if (exit_status == 0) {
						string[] splitted = output.split ("\n");
						if (splitted.length == 2) {
							if (uint64.try_parse (splitted[0], out lockfile_time)) {
								uint64 boot_time;
								// get boot time since epoch
								Process.spawn_command_line_sync ("cat /proc/stat",
																out output,
																null,
																out exit_status);
								if (exit_status == 0) {
									splitted = output.split ("\n");
									foreach (unowned string line in splitted) {
										if ("btime" in line) {
											string[] space_splitted = line.split (" ");
											if (space_splitted.length == 2) {
												if (uint64.try_parse (space_splitted[1], out boot_time)) {
													// check if lock file is older than boot time
													if (lockfile_time < boot_time) {
														// remove the unneeded lock file.
														try {
															lockfile.delete ();
														} catch (Error e) {
															stderr.printf ("Error: %s\n", e.message);
														}
														lock_id = new BusName ("");
													}
												}
											}
										}
									}
								}
							}
						}
					}
				} catch (SpawnError e) {
					stderr.printf ("Error: %s\n", e.message);
				}
			}
		}

		private bool check_extern_lock () {
			if (lock_id == "extern") {
				if (!lockfile.query_exists ()) {
					lock_id = new BusName ("");
					alpm_utils.refresh_handle ();
					database_modified ();
				}
			} else {
				if (lockfile.query_exists ()) {
					if (lock_id == "") {
						// An extern lock appears
						lock_id = new BusName ("extern");
					}
				}
			}
			return true;
		}

		public bool get_lock (GLib.BusName sender) throws Error {
			if (lock_id == sender) {
				return true;
			} else if (lock_id == "") {
				lock_id = sender;
				return true;
			}
			return false;
		}

		public bool unlock (GLib.BusName sender) throws Error {
			if (lock_id == sender) {
				unlock_priv ();
				return true;
			}
			return false;
		}

		private async bool check_authorization (GLib.BusName sender) {
			if (authorized) {
				return true;
			}
			authorized = false;
			try {
				Polkit.Authority authority = yield Polkit.Authority.get_async ();
				Polkit.Subject subject = new Polkit.SystemBusName (sender);
				var result = yield authority.check_authorization (
					subject,
					"org.manjaro.pamac.commit",
					null,
					Polkit.CheckAuthorizationFlags.ALLOW_USER_INTERACTION);
				authorized = result.get_is_authorized ();
			} catch (GLib.Error e) {
				stderr.printf ("%s\n", e.message);
			}
			if (!authorized) {
				alpm_utils.current_error = ErrorInfos () {
					message = _("Authentication failed")
				};
			}
			return authorized;
		}

		public void start_get_authorization (GLib.BusName sender) throws Error {
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				get_authorization_finished (authorized);
			});
		}

		public void start_write_pamac_config (HashTable<string,Variant> new_pamac_conf, GLib.BusName sender) throws Error {
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					config.write (new_pamac_conf);
					config.reload ();
				}
				write_pamac_config_finished (config.recurse, config.refresh_period, config.no_update_hide_icon,
											config.enable_aur, config.aur_build_dir, config.check_aur_updates,
											config.check_aur_vcs_updates, config.download_updates);
			});
		}

		private void write_alpm_config () {
			alpm_utils.alpm_config.write (new_alpm_conf);
			alpm_utils.alpm_config.reload ();
			alpm_utils.refresh_handle ();
			database_modified ();
			write_alpm_config_finished ((alpm_utils.alpm_handle.checkspace == 1));
		}

		public void start_write_alpm_config (HashTable<string,Variant> new_alpm_conf, GLib.BusName sender) throws Error {
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					this.new_alpm_conf = new_alpm_conf;
					try {
						thread_pool.add (new AlpmAction (write_alpm_config));
					} catch (ThreadError e) {
						stderr.printf ("Thread Error %s\n", e.message);
					}
				} else {
					write_alpm_config_finished ((alpm_utils.alpm_handle.checkspace == 1));
				}
			});
		}

		private void generate_mirrors_list () {
			try {
				var process = new Subprocess.newv (
					{"pacman-mirrors", "--no-color", "-c", mirrorlist_country},
					SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
				var dis = new DataInputStream (process.get_stdout_pipe ());
				string? line;
				while ((line = dis.read_line ()) != null) {
					generate_mirrors_list_data (line);
				}
			} catch (Error e) {
				stderr.printf ("Error: %s\n", e.message);
			}
			alpm_utils.alpm_config.reload ();
			alpm_utils.refresh_handle ();
			database_modified ();
			generate_mirrors_list_finished ();
		}

		public void start_generate_mirrors_list (string country, GLib.BusName sender) throws Error {
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					mirrorlist_country = country;
					try {
						thread_pool.add (new AlpmAction (generate_mirrors_list));
					} catch (ThreadError e) {
						stderr.printf ("Thread Error %s\n", e.message);
					}
				}
			});
		}

		public void start_clean_cache (uint64 keep_nb, bool only_uninstalled, GLib.BusName sender) throws Error {
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					alpm_utils.clean_cache (keep_nb, only_uninstalled);
				}
				clean_cache_finished (authorized);
			});
		}

		public void start_clean_build_files (string build_dir, GLib.BusName sender) throws Error {
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					alpm_utils.clean_build_files (build_dir);
				}
				clean_build_files_finished (authorized);
			});
		}

		public void start_set_pkgreason (string pkgname, uint reason, GLib.BusName sender) throws Error {
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				bool success = false;
				if (authorized) {
					success = alpm_utils.set_pkgreason (pkgname, reason);
				}
				database_modified ();
				set_pkgreason_finished (success);
			});
		}

		public void start_refresh (bool force, GLib.BusName sender) throws Error {
			alpm_utils.force_refresh = force;
			if (alpm_utils.downloading_updates) {
				alpm_utils.cancellable.cancel ();
				// let time to cancel download updates
				Timeout.add (1000, () => {
					check_authorization.begin (sender, (obj, res) => {
						bool authorized = check_authorization.end (res);
						if (authorized) {
							launch_refresh_thread ();
						} else {
							refresh_finished (false);
						}
					});
					return false;
				});
			} else {
				check_authorization.begin (sender, (obj, res) => {
					bool authorized = check_authorization.end (res);
					if (authorized) {
						launch_refresh_thread ();
					} else {
						refresh_finished (false);
					}
				});
			}
		}

		private void launch_refresh_thread () {
			try {
				thread_pool.add (new AlpmAction (alpm_utils.refresh));
			} catch (ThreadError e) {
				stderr.printf ("Thread Error %s\n", e.message);
			}
		}

		public void start_downloading_updates () throws Error {
			// do not add this thread to the threadpool so it won't be queued
			new Thread<int> ("download updates thread", alpm_utils.download_updates);
		}

		public void start_sysupgrade_prepare (bool enable_downgrade,
											string[] to_build,
											string[] temporary_ignorepkgs,
											string[] overwrite_files,
											GLib.BusName sender) throws Error {
			if (lock_id != sender) {
				trans_prepare_finished (false);
				return;
			}
			alpm_utils.config.enable_downgrade = enable_downgrade;
			alpm_utils.temporary_ignorepkgs = temporary_ignorepkgs;
			alpm_utils.overwrite_files = overwrite_files;
			alpm_utils.sysupgrade = true;
			alpm_utils.flags = 0;
			alpm_utils.to_install = {};
			alpm_utils.to_remove = {};
			alpm_utils.to_load = {};
			alpm_utils.to_build = to_build;
			if (alpm_utils.downloading_updates) {
				alpm_utils.cancellable.cancel ();
				// let time to cancel download updates
				Timeout.add (1000, () => {
					launch_prepare_thread ();
					return false;
				});
			} else {
				launch_prepare_thread ();
			}
		}

		public void start_trans_prepare (Alpm.TransFlag flags,
										string[] to_install,
										string[] to_remove,
										string[] to_load,
										string[] to_build,
										string[] temporary_ignorepkgs,
										string[] overwrite_files,
										string[] to_mark_as_dep,
										GLib.BusName sender) throws Error {
			if (lock_id != sender) {
				trans_prepare_finished (false);
				return;
			}
			alpm_utils.flags = flags;
			alpm_utils.to_install = to_install;
			alpm_utils.to_remove = to_remove;
			alpm_utils.to_load = to_load;
			alpm_utils.to_build = to_build;
			alpm_utils.temporary_ignorepkgs = temporary_ignorepkgs;
			alpm_utils.overwrite_files = overwrite_files;
			alpm_utils.to_mark_as_dep = to_mark_as_dep;
			alpm_utils.sysupgrade = false;
			if (alpm_utils.downloading_updates) {
				alpm_utils.cancellable.cancel ();
				// let time to cancel download updates
				Timeout.add (1000, () => {
					launch_prepare_thread ();
					return false;
				});
			} else {
				launch_prepare_thread ();
			}
		}

		private void launch_prepare_thread () {
			if (alpm_utils.to_build.length != 0) {
				try {
					thread_pool.add (new AlpmAction (alpm_utils.build_prepare));
				} catch (ThreadError e) {
					stderr.printf ("Thread Error %s\n", e.message);
				}
			} else {
				try {
					thread_pool.add (new AlpmAction (alpm_utils.trans_prepare));
				} catch (ThreadError e) {
					stderr.printf ("Thread Error %s\n", e.message);
				}
			}
		}

		public void choose_provider (int provider) throws Error {
			alpm_utils.choose_provider (provider);
		}

		public TransactionSummaryStruct get_transaction_summary () throws Error {
			return alpm_utils.get_transaction_summary ();
		}

		public void start_trans_commit (GLib.BusName sender) throws Error {
			if (lock_id != sender) {
				return;
			}
			check_authorization.begin (sender, (obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					try {
						thread_pool.add (new AlpmAction (alpm_utils.trans_commit));
					} catch (ThreadError e) {
						stderr.printf ("Thread Error %s\n", e.message);
					}
				} else {
					alpm_utils.trans_release ();
					trans_commit_finished (false);
				}
			});
		}

		public void trans_release (GLib.BusName sender) throws Error {
			if (lock_id != sender) {
				return;
			}
			alpm_utils.trans_release ();
			unlock_priv ();
		}

		public void trans_cancel (GLib.BusName sender) throws Error {
			if (lock_id != sender) {
				return;
			}
			alpm_utils.trans_cancel ();
			unlock_priv ();
		}

		private void unlock_priv () {
			lock_id = new BusName ("");
			authorized = false;
		}

		[DBus (no_reply = true)]
		public void quit () throws Error {
			// do not quit if locked
			if (lock_id != "" && lock_id != "extern"){
				return;
			}
			// do not quit if downloading updates
			if (alpm_utils.downloading_updates) {
				return;
			}
			// wait for all tasks to be processed
			ThreadPool.free ((owned) thread_pool, false, true);
			loop.quit ();
		}
	}
}

void on_bus_acquired (DBusConnection conn) {
	system_daemon = new Pamac.SystemDaemon ();
	try {
		conn.register_object ("/org/manjaro/pamac/system", system_daemon);
	}
	catch (IOError e) {
		stderr.printf ("Could not register service\n");
		loop.quit ();
	}
}

void main () {
	// i18n
	Intl.setlocale (LocaleCategory.ALL, "");
	Intl.textdomain (GETTEXT_PACKAGE);

	Bus.own_name (BusType.SYSTEM,
				"org.manjaro.pamac.system",
				BusNameOwnerFlags.NONE,
				on_bus_acquired,
				null,
				() => {
					stderr.printf ("Could not acquire name\n");
					loop.quit ();
				});

	loop = new MainLoop ();
	loop.run ();
}
