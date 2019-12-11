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

Pamac.Daemon system_daemon;
MainLoop loop;

[Compact]
public class AlpmAction {
	public Pamac.Daemon pamac_daemon;
	public string sender;
	public bool is_generate_mirrors_list;
	public string country;
	public bool is_write_alpm_config;
	public HashTable<string,Variant> new_alpm_conf;
	#if ENABLE_SNAP
	public bool is_snap_switch;
	public string snap_name;
	public string snap_channel;
	public bool is_snap;
	#endif
	public bool is_set_pkgreason;
	public string pkgname;
	public uint reason;
	public bool is_alpm;
	public bool sysupgrade;
	public bool force_refresh;
	public bool enable_downgrade;
	public bool simple_install;
	public bool check_aur_updates;
	public bool no_confirm_commit;
	public bool keep_built_pkgs;
	public int trans_flags;
	public string[] to_install;
	public string[] to_remove;
	public string[] to_load;
	public string[] to_build;
	public string[] to_install_as_dep;
	public string[] temporary_ignorepkgs;
	public string[] overwrite_files;
	public Cancellable cancellable;
	public AlpmAction (Pamac.Daemon pamac_daemon, string sender) {
		this.pamac_daemon = pamac_daemon;
		this.sender = sender;
	}
	public void run () {
		if (is_generate_mirrors_list) {
			pamac_daemon.generate_mirrors_list (sender, country);
		} else if (is_set_pkgreason) {
			pamac_daemon.set_pkgreason (sender, pkgname, reason);
		} else if (is_write_alpm_config) {
			pamac_daemon.write_alpm_config (sender, new_alpm_conf);
		} else if (is_alpm) {
			pamac_daemon.trans_run (sender,
									sysupgrade,
									force_refresh,
									enable_downgrade,
									simple_install,
									check_aur_updates,
									no_confirm_commit,
									keep_built_pkgs,
									trans_flags,
									to_install,
									to_remove,
									to_load,
									to_build,
									to_install_as_dep,
									temporary_ignorepkgs,
									overwrite_files,
									cancellable);
		#if ENABLE_SNAP
		} else if (is_snap) {
			pamac_daemon.snap_trans_run (sender, to_install, to_remove);
		} else if (is_snap_switch) {
			pamac_daemon.snap_switch_channel (sender, snap_name, snap_channel);
		#endif
		}
	}
}

namespace Pamac {
	[DBus (name = "org.manjaro.pamac.daemon")]
	public class Daemon: Object {
		Config config;
		ThreadPool<AlpmAction> thread_pool;
		bool authorized;
		GLib.File lockfile;
		FileMonitor lockfile_monitor;
		Cond lockfile_cond;
		Mutex lockfile_mutex;
		Cond answer_cond;
		Mutex answer_mutex;
		int? choosen_provider_answer;
		bool? compute_aur_build_list_answer;
		bool? ask_edit_build_files_answer;
		bool? edit_build_files_answer;
		bool? ask_commit_answer;
		HashTable<string, Cancellable> cancellables_table;
		#if ENABLE_SNAP
		SnapPlugin snap_plugin;
		#endif

		public signal void choose_provider (string sender, string depend, string[] providers);
		public signal void compute_aur_build_list (string sender);
		public signal void ask_commit (string sender, TransactionSummaryStruct summary);
		public signal void ask_edit_build_files (string sender, TransactionSummaryStruct summary);
		public signal void edit_build_files (string sender, string[] pkgnames);
		public signal void emit_action (string sender, string action);
		public signal void emit_action_progress (string sender, string action, string status, double progress);
		public signal void emit_download_progress (string sender, string action, string status, double progress);
		public signal void emit_hook_progress (string sender, string action, string details, string status, double progress);
		public signal void emit_script_output (string sender, string message);
		public signal void emit_warning (string sender, string message);
		public signal void emit_error (string sender, string message, string[] details);
		public signal void important_details_outpout (string sender, bool must_show);
		public signal void start_downloading (string sender);
		public signal void stop_downloading (string sender);
		public signal void set_pkgreason_finished (string sender, bool success);
		public signal void start_waiting (string sender);
		public signal void stop_waiting (string sender);
		public signal void trans_run_finished (string sender, bool success);
		public signal void download_updates_finished (string sender);
		public signal void get_authorization_finished (string sender, bool authorized);
		public signal void write_alpm_config_finished (string sender);
		public signal void write_pamac_config_finished (string sender);
		public signal void generate_mirrors_list_data (string sender, string line);
		public signal void generate_mirrors_list_finished (string sender);
		public signal void clean_cache_finished (string sender, bool success);
		public signal void clean_build_files_finished (string sender, bool success);
		#if ENABLE_SNAP
		public signal void snap_trans_run_finished (string sender, bool success);
		public signal void snap_switch_channel_finished (string sender, bool success);
		#endif

		public Daemon () {
			config = new Config ("/etc/pamac.conf");
			authorized = false;
			// alpm_utils global variable declared in alpm_utils.vala
			alpm_utils = new AlpmUtils (config);
			lockfile_cond = Cond ();
			lockfile_mutex = Mutex ();
			lockfile = GLib.File.new_for_path (alpm_utils.alpm_handle.lockfile);
			if (lockfile.query_exists ()) {
				new Thread<int> ("set_extern_lock", set_extern_lock);
			}
			try {
				lockfile_monitor = lockfile.monitor (FileMonitorFlags.NONE, null);
				lockfile_monitor.changed.connect (check_extern_lock);
			} catch (Error e) {
				critical ("%s\n", e.message);
			}
			create_thread_pool ();
			answer_cond = Cond ();
			answer_mutex = Mutex ();
			cancellables_table = new HashTable<string, Cancellable> (str_hash, str_equal);
			alpm_utils.choose_provider.connect ((sender, depend, providers) => {
				return choose_provider_callback (sender, depend, providers);
			});
			alpm_utils.compute_aur_build_list.connect ((sender) => {
				compute_aur_build_list_callback (sender);
			});
			alpm_utils.ask_edit_build_files.connect ((sender, summary) => {
				return ask_edit_build_files_callback (sender, summary);
			});
			alpm_utils.edit_build_files.connect ((sender, pkgnames) => {
				edit_build_files_callback (sender, pkgnames);
			});
			alpm_utils.ask_commit.connect ((sender, summary) => {
				return ask_commit_callback (sender, summary);
			});
			alpm_utils.emit_action.connect ((sender, action) => {
				emit_action (sender, action);
			});
			alpm_utils.emit_action_progress.connect ((sender, action, status, progress) => {
				emit_action_progress (sender, action, status, progress);
			});
			alpm_utils.emit_hook_progress.connect ((sender, action, details, status, progress) => {
				emit_hook_progress (sender, action, details, status, progress);
			});
			alpm_utils.emit_download_progress.connect ((sender, action, status, progress) => {
				emit_download_progress (sender, action, status, progress);
			});
			alpm_utils.start_downloading.connect ((sender) => {
				start_downloading (sender);
			});
			alpm_utils.stop_downloading.connect ((sender) => {
				stop_downloading (sender);
			});
			alpm_utils.emit_script_output.connect ((sender, message) => {
				emit_script_output (sender, message);
			});
			alpm_utils.emit_warning.connect ((sender, message) => {
				emit_warning (sender, message);
			});
			alpm_utils.emit_error.connect ((sender, message, details) => {
				emit_error (sender, message, details);
			});
			alpm_utils.important_details_outpout.connect ((sender, must_show) => {
				important_details_outpout (sender, must_show);
			});
			alpm_utils.get_authorization.connect ((sender) => {
				return get_authorization_sync (sender);
			});
			#if ENABLE_SNAP
			if (config.support_snap) {
				snap_plugin = config.get_snap_plugin ();
				snap_plugin.get_authorization.connect ((sender) => {
					return get_authorization_sync (sender);
				});
				snap_plugin.emit_action_progress.connect ((sender, action, status, progress) => {
					emit_action_progress (sender, action, status, progress);
				});
				snap_plugin.emit_download_progress.connect ((sender, action, status, progress) => {
					emit_download_progress (sender, action, status, progress);
				});
				snap_plugin.emit_script_output.connect ((sender, message) => {
					emit_script_output (sender, message);
				});
				snap_plugin.emit_error.connect ((sender, message,  details) => {
					emit_error (sender, message, details);
				});
				snap_plugin.start_downloading.connect ((sender) => {
					start_downloading (sender);
				});
				snap_plugin.stop_downloading.connect ((sender) => {
					stop_downloading (sender);
				});
			}
			#endif
		}

		public void set_environment_variables (HashTable<string,string> variables) throws Error {
			string[] keys = {"http_proxy",
							"https_proxy",
							"ftp_proxy",
							"socks_proxy",
							"no_proxy"};
			foreach (unowned string key in keys) {
				unowned string val;
				if (variables.lookup_extended (key, null, out val)) {
					Environment.set_variable (key, val, true);
				}
			}
		}

		public string get_sender (BusName sender) throws Error {
			return sender;
		}

		public string get_lockfile () throws Error {
			return alpm_utils.alpm_handle.lockfile;
		}

		void create_thread_pool () {
			// create a thread pool which will run alpm action one after one
			try {
				thread_pool = new ThreadPool<AlpmAction>.with_owned_data (
					// call alpm_action.run () on thread start
					(alpm_action) => {
						alpm_action.run ();
					},
					// unlimited threads
					-1,
					// no exclusive thread
					false
				);
			} catch (ThreadError e) {
				critical ("%s\n", e.message);
			}
		}

		int set_extern_lock () {
//~ 			if (lockfile_mutex.trylock ()) {
//~ 				try {
//~ 					var tmp_loop = new MainLoop ();
//~ 					var unlock_monitor = lockfile.monitor (FileMonitorFlags.NONE, null);
//~ 					unlock_monitor.changed.connect ((src, dest, event_type) => {
//~ 						if (event_type == FileMonitorEvent.DELETED) {
//~ 							lockfile_mutex.unlock ();
//~ 							tmp_loop.quit ();
//~ 						}
//~ 					});
//~ 					tmp_loop.run ();
//~ 				} catch (Error e) {
//~ 					critical ("%s\n", e.message);
//~ 				}
//~ 			}
			return 0;
		}

		void check_extern_lock (File src, File? dest, FileMonitorEvent event_type) {
			if (event_type == FileMonitorEvent.CREATED) {
				new Thread<int> ("set_extern_lock", set_extern_lock);
			}
		}

		async bool check_authorization (BusName sender) {
			bool tmp_authorized = false;
			try {
				Polkit.Authority authority = yield Polkit.Authority.get_async ();
				Polkit.Subject subject = new Polkit.SystemBusName (sender);
				var result = yield authority.check_authorization (
					subject,
					"org.manjaro.pamac.commit",
					null,
					Polkit.CheckAuthorizationFlags.ALLOW_USER_INTERACTION);
				tmp_authorized = result.get_is_authorized ();
				if (!tmp_authorized) {
					emit_error (sender, _("Authentication failed"), {});
				}
			} catch (Error e) {
				critical ("%s\n", e.message);
				emit_error (sender, _("Authentication failed"), {e.message});
			}
			return tmp_authorized;
		}

		bool get_authorization_sync (string sender) {
			if (authorized) {
				return true;
			}
			answer_mutex.lock ();
			try {
				Polkit.Authority authority = Polkit.Authority.get_sync ();
				Polkit.Subject subject = new Polkit.SystemBusName (sender);
				var result = authority.check_authorization_sync (
					subject,
					"org.manjaro.pamac.commit",
					null,
					Polkit.CheckAuthorizationFlags.ALLOW_USER_INTERACTION);
				authorized = result.get_is_authorized ();
				if (!authorized) {
					emit_error (sender, _("Authentication failed"), {});
				}
			} catch (Error e) {
				critical ("%s\n", e.message);
				emit_error (sender, _("Authentication failed"), {e.message});
			}
			answer_mutex.unlock ();
			return authorized;
		}

		public void remove_authorization () throws Error {
			authorized = false;
		}

		public void start_get_authorization (BusName sender) throws Error {
			check_authorization.begin (sender, (obj, res) => {
				bool tmp_authorized = check_authorization.end (res);
				get_authorization_finished (sender, tmp_authorized);
			});
		}

		[DBus (visible = false)]
		public void write_alpm_config (string sender, HashTable<string,Variant> new_alpm_conf) {
			lockfile_mutex.lock ();
			alpm_utils.alpm_config.write (new_alpm_conf);
			alpm_utils.alpm_config.reload ();
			alpm_utils.refresh_handle ();
			lockfile_mutex.unlock ();
			write_alpm_config_finished (sender);
		}

		public void start_write_alpm_config (HashTable<string,Variant> new_alpm_conf, BusName sender) throws Error {
			check_authorization.begin (sender, (obj, res) => {
				bool tmp_authorized = check_authorization.end (res);
				if (tmp_authorized) {
					try {
						var action = new AlpmAction (this, sender);
						action.is_write_alpm_config = true;
						action.new_alpm_conf = new_alpm_conf;
						thread_pool.add ((owned) action);
					} catch (ThreadError e) {
						critical ("%s\n", e.message);
						emit_error (sender, "Daemon Error", {e.message});
						write_alpm_config_finished (sender);
					}
				}
			});
		}

		public void start_write_pamac_config (HashTable<string,Variant> new_pamac_conf, BusName sender) throws Error {
			check_authorization.begin (sender, (obj, res) => {
				bool tmp_authorized = check_authorization.end (res);
				if (tmp_authorized) {
					config.write (new_pamac_conf);
					config.reload ();
					#if ENABLE_SNAP
					if (config.enable_snap) {
						try {
							Process.spawn_command_line_async ("systemctl enable --now snapd.service");
						} catch (SpawnError e) {
							critical ("%s\n", e.message);
						}
					}
					#endif
				}
				write_pamac_config_finished (sender);
			});
		}

		[DBus (visible = false)]
		public void generate_mirrors_list (string sender, string country) {
			try {
				var process = new Subprocess.newv (
					{"pacman-mirrors", "--no-color", "-c", country},
					SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
				var dis = new DataInputStream (process.get_stdout_pipe ());
				string? line;
				while ((line = dis.read_line ()) != null) {
					generate_mirrors_list_data (sender, line);
				}
			} catch (Error e) {
				critical ("%s\n", e.message);
				emit_error (sender, "Daemon Error", {e.message});
			}
			lockfile_mutex.lock ();
			alpm_utils.alpm_config.reload ();
			alpm_utils.refresh_handle ();
			lockfile_mutex.unlock ();
			generate_mirrors_list_finished (sender);
		}

		public void start_generate_mirrors_list (string country, BusName sender) throws Error {
			check_authorization.begin (sender, (obj, res) => {
				bool tmp_authorized = check_authorization.end (res);
				if (tmp_authorized) {
					try {
						var action = new AlpmAction (this, sender);
						action.is_generate_mirrors_list = true;
						action.country = country;
						thread_pool.add ((owned) action);
					} catch (ThreadError e) {
						critical ("%s\n", e.message);
						emit_error (sender, "Daemon Error", {e.message});
						generate_mirrors_list_finished (sender);
					}
				}
			});
		}

		public void start_clean_cache (string[] filenames, BusName sender) throws Error {
			string[] names = filenames;
			check_authorization.begin (sender, (obj, res) => {
				bool tmp_authorized = check_authorization.end (res);
				if (tmp_authorized) {
					alpm_utils.clean_cache (names);
				}
				clean_cache_finished (sender, tmp_authorized);
			});
		}

		public void start_clean_build_files (string aur_build_dir, BusName sender) throws Error {
			check_authorization.begin (sender, (obj, res) => {
				bool tmp_authorized = check_authorization.end (res);
				if (tmp_authorized) {
					alpm_utils.clean_build_files (aur_build_dir);
				}
				clean_build_files_finished (sender, tmp_authorized);
			});
		}

		[DBus (visible = false)]
		public void set_pkgreason (string sender, string pkgname, uint reason) {
			authorized = get_authorization_sync (sender);
			bool success = false;
			if (authorized) {
				lockfile_mutex.lock ();
				success = alpm_utils.set_pkgreason (pkgname, reason);
				lockfile_mutex.unlock ();
			}
			authorized = false;
			set_pkgreason_finished (sender, success);
		}

		public void start_set_pkgreason (string pkgname, uint reason, BusName sender) throws Error {
			var action = new AlpmAction (this, sender);
			action.is_set_pkgreason = true;
			action.pkgname = pkgname;
			action.reason = reason;
			thread_pool.add ((owned) action);
		}

		public void start_download_updates (BusName sender) throws Error {
			// do not add this thread to the threadpool so it won't be queued
			new Thread<int> ("download updates thread", () => {
				alpm_utils.download_updates ();
				download_updates_finished (sender);
				return 0;
			});
		}

		[DBus (visible = false)]
		public void trans_run (string sender,
								bool sysupgrade,
								bool force_refresh,
								bool enable_downgrade,
								bool simple_install,
								bool check_aur_updates,
								bool no_confirm_commit,
								bool keep_built_pkgs,
								int trans_flags,
								string[] to_install,
								string[] to_remove,
								string[] to_load,
								string[] to_build,
								string[] to_install_as_dep,
								string[] temporary_ignorepkgs,
								string[] overwrite_files,
								Cancellable cancellable) {
			bool waiting = false;
			cancellable.reset ();
			if (!lockfile_mutex.trylock ()) {
				waiting = true;
				start_waiting (sender);
				emit_action (sender, _("Waiting for another package manager to quit") + "...");
				answer_mutex.lock ();
				int i = 0;
				while (!cancellable.is_cancelled ()) {
					// wait 200 ms for cancellation
					int64 end_time = get_monotonic_time () + 200 * TimeSpan.MILLISECOND;
					answer_cond.wait_until (answer_mutex, end_time);
					if (lockfile_mutex.trylock ()) {
						break;
					}
					i++;
					// wait 5 min max
					if (i == 1500) {
						cancellable.cancel ();
						emit_action (sender, "%s: %s.".printf (_("Transaction cancelled"), _("Timeout expired")));
					}
				}
				answer_mutex.unlock ();
			}
			if (waiting) {
				stop_waiting (sender);
			}
			if (cancellable.is_cancelled ()) {
				// cancelled
				trans_run_finished (sender, false);
				return;
			}
			bool success = alpm_utils.trans_run (sender,
												sysupgrade,
												force_refresh,
												enable_downgrade,
												simple_install,
												check_aur_updates,
												no_confirm_commit,
												keep_built_pkgs,
												trans_flags,
												to_install,
												to_remove,
												to_load,
												to_build,
												to_install_as_dep,
												temporary_ignorepkgs,
												overwrite_files);
			lockfile_mutex.unlock ();
			trans_run_finished (sender, success);
		}

		public void start_trans_run (bool sysupgrade,
									bool force_refresh,
									bool enable_downgrade,
									bool simple_install,
									bool check_aur_updates,
									bool no_confirm_commit,
									bool keep_built_pkgs,
									int trans_flags,
									string[] to_install,
									string[] to_remove,
									string[] to_load,
									string[] to_build,
									string[] to_install_as_dep,
									string[] temporary_ignorepkgs,
									string[] overwrite_files,
									BusName sender) throws Error {
			if (alpm_utils.downloading_updates) {
				alpm_utils.cancellable.cancel ();
				// let time to cancel download updates
				Timeout.add (1000, () => {
					try {
						var action = new AlpmAction (this, sender);
						action.is_alpm = true;
						action.sysupgrade = sysupgrade;
						action.force_refresh = force_refresh;
						action.enable_downgrade = enable_downgrade;
						action.simple_install = simple_install;
						action.check_aur_updates = check_aur_updates;
						action.no_confirm_commit = no_confirm_commit;
						action.keep_built_pkgs = keep_built_pkgs;
						action.trans_flags = trans_flags;
						action.to_install = to_install;
						action.to_remove = to_remove;
						action.to_load = to_load;
						action.to_build = to_build;
						action.to_install_as_dep = to_install_as_dep;
						action.temporary_ignorepkgs = temporary_ignorepkgs;
						action.overwrite_files = overwrite_files;
						if (!cancellables_table.contains (sender)) {
							cancellables_table.insert (sender, new Cancellable ());
						}
						action.cancellable = cancellables_table.lookup (sender);
						thread_pool.add ((owned) action);
					} catch (ThreadError e) {
						critical ("%s\n", e.message);
						emit_error (sender, "Daemon Error", {e.message});
						trans_run_finished (sender, false);
					}
					return false;
				});
			} else {
				try {
					var action = new AlpmAction (this, sender);
					action.is_alpm = true;
					action.sysupgrade = sysupgrade;
					action.force_refresh = force_refresh;
					action.enable_downgrade = enable_downgrade;
					action.simple_install = simple_install;
					action.check_aur_updates = check_aur_updates;
					action.no_confirm_commit = no_confirm_commit;
					action.keep_built_pkgs = keep_built_pkgs;
					action.trans_flags = trans_flags;
					action.to_install = to_install;
					action.to_remove = to_remove;
					action.to_load = to_load;
					action.to_build = to_build;
					action.to_install_as_dep = to_install_as_dep;
					action.temporary_ignorepkgs = temporary_ignorepkgs;
					action.overwrite_files = overwrite_files;
					if (!cancellables_table.contains (sender)) {
						cancellables_table.insert (sender, new Cancellable ());
					}
					action.cancellable = cancellables_table.lookup (sender);
					thread_pool.add ((owned) action);
				} catch (ThreadError e) {
					critical ("%s\n", e.message);
					emit_error (sender, "Daemon Error", {e.message});
					trans_run_finished (sender, false);
				}
			}
		}

		int choose_provider_callback (string sender, string depend, string[] providers) {
			choosen_provider_answer = null;
			choose_provider (sender, depend, providers);
			answer_mutex.lock ();
			while (choosen_provider_answer == null) {
				answer_cond.wait (answer_mutex);
			}
			answer_mutex.unlock ();
			return choosen_provider_answer;
		}

		public void answer_choose_provider (int provider) throws Error {
			answer_mutex.lock ();
			choosen_provider_answer = provider;
			answer_cond.signal ();
			answer_mutex.unlock ();
		}

		void compute_aur_build_list_callback (string sender) {
			compute_aur_build_list_answer = null;
			compute_aur_build_list (sender);
			answer_mutex.lock ();
			while (compute_aur_build_list_answer == null) {
				answer_cond.wait (answer_mutex);
			}
			answer_mutex.unlock ();
		}

		public void aur_build_list_computed () throws Error {
			answer_mutex.lock ();
			compute_aur_build_list_answer = true;
			answer_cond.signal ();
			answer_mutex.unlock ();
		}

		bool ask_edit_build_files_callback (string sender, TransactionSummaryStruct summary) {
			ask_edit_build_files_answer = null;
			ask_edit_build_files (sender, summary);
			answer_mutex.lock ();
			while (ask_edit_build_files_answer == null) {
				answer_cond.wait (answer_mutex);
			}
			answer_mutex.unlock ();
			return ask_edit_build_files_answer;
		}

		public void answer_ask_edit_build_files (bool answer) throws Error {
			answer_mutex.lock ();
			ask_edit_build_files_answer = answer;
			answer_cond.signal ();
			answer_mutex.unlock ();
		}

		void edit_build_files_callback (string sender, string[] pkgnames) {
			edit_build_files_answer = null;
			edit_build_files (sender, pkgnames);
			answer_mutex.lock ();
			while (edit_build_files_answer == null) {
				answer_cond.wait (answer_mutex);
			}
			answer_mutex.unlock ();
		}

		public void build_files_edited () throws Error {
			answer_mutex.lock ();
			edit_build_files_answer = true;
			answer_cond.signal ();
			answer_mutex.unlock ();
		}

		bool ask_commit_callback (string sender, TransactionSummaryStruct summary) {
			ask_commit_answer = null;
			ask_commit (sender, summary);
			answer_mutex.lock ();
			while (ask_commit_answer == null) {
				answer_cond.wait (answer_mutex);
			}
			answer_mutex.unlock ();
			return ask_commit_answer;
		}

		public void answer_ask_commit (bool answer) throws Error {
			answer_mutex.lock ();
			ask_commit_answer = answer;
			answer_cond.signal ();
			answer_mutex.unlock ();
		}

		#if ENABLE_SNAP
		[DBus (visible = false)]
		public void snap_trans_run (string sender, string[] to_install, string[] to_remove) {
			bool success = snap_plugin.trans_run (sender, to_install, to_remove);
			snap_trans_run_finished (sender, success);
		}

		public void start_snap_trans_run (string[] to_install, string[] to_remove, BusName sender) throws Error {
			if (!config.enable_snap) {
				Idle.add (() => {
					snap_trans_run_finished (sender, false);
					return false;
				});
				return;
			}
			try {
				var action = new AlpmAction (this, sender);
				action.is_snap = true;
				action.to_install = to_install;
				action.to_remove = to_remove;
				thread_pool.add ((owned) action);
			} catch (ThreadError e) {
				critical ("%s\n", e.message);
				emit_error (sender, "Daemon Error", {e.message});
				snap_trans_run_finished (sender, false);
			}
		}

		[DBus (visible = false)]
		public void snap_switch_channel (string sender, string snap_name, string snap_channel) {
			bool success = snap_plugin.switch_channel (snap_name, snap_channel, sender);
			snap_switch_channel_finished (sender, success);
		}

		public void start_snap_switch_channel (string snap_name, string snap_channel, BusName sender) throws Error {
			if (!config.enable_snap) {
				Idle.add (() => {
					snap_switch_channel_finished (sender, false);
					return false;
				});
				return;
			}
			try {
				var action = new AlpmAction (this, sender);
				action.is_snap_switch = true;
				action.snap_name = snap_name;
				action.snap_channel = snap_channel;
				thread_pool.add ((owned) action);
			} catch (ThreadError e) {
				critical ("%s\n", e.message);
				emit_error (sender, "Daemon Error", {e.message});
				snap_switch_channel_finished (sender, false);
			}
		}
		#endif

		public void trans_cancel (BusName sender) throws Error {
			Cancellable? cancellable = cancellables_table.lookup (sender);
			if (cancellable != null) {
				answer_mutex.lock ();
				cancellable.cancel ();
				answer_cond.signal ();
				answer_mutex.unlock ();
			}
			#if ENABLE_SNAP
			if (config.enable_snap) {
				snap_plugin.trans_cancel (sender);
			}
			#endif
			alpm_utils.trans_cancel (sender);
		}

		[DBus (no_reply = true)]
		public void quit () throws Error {
			// do not quit if downloading updates
			if (alpm_utils.downloading_updates) {
				return;
			}
			ThreadPool.stop_unused_threads ();
			if (thread_pool.unprocessed () == 0 && thread_pool.get_num_threads () <= 1 ) {
				// wait for last task to be processed
				ThreadPool.free ((owned) thread_pool, false, true);
				loop.quit ();
			}
		}
	}
}

void on_bus_acquired (DBusConnection conn) {
	system_daemon = new Pamac.Daemon ();
	try {
		conn.register_object ("/org/manjaro/pamac/daemon", system_daemon);
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
				"org.manjaro.pamac.daemon",
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
