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
	[DBus (name = "org.manjaro.pamac.daemon")]
	public class Daemon: Object {
		Config config;
		bool refreshed;
		string mirrorlist_country;
		ThreadPool<AlpmAction> thread_pool;
		BusName lock_id;
		bool authorized;
		GLib.BusName trans_run_sender;
		GLib.File lockfile;
		Cond cond;
		Mutex mutex;
		int? choosen_provider_answer;
		bool? compute_aur_build_list_answer;
		bool? ask_edit_build_files_answer;
		bool? edit_build_files_answer;
		bool? ask_commit_answer;
		#if ENABLE_SNAP
		SnapPlugin snap_plugin;
		string[] snap_to_install;
		string[] snap_to_remove;
		string snap_switch_name;
		string snap_channel;
		#endif

		public signal void choose_provider (string depend, string[] providers);
		public signal void compute_aur_build_list ();
		public signal void ask_commit (TransactionSummaryStruct summary);
		public signal void ask_edit_build_files (TransactionSummaryStruct summary);
		public signal void edit_build_files (string[] pkgnames);
		public signal void emit_action (string action);
		public signal void emit_action_progress (string action, string status, double progress);
		public signal void emit_download_progress (string action, string status, double progress);
		public signal void emit_hook_progress (string action, string details, string status, double progress);
		public signal void emit_script_output (string message);
		public signal void emit_warning (string message);
		public signal void emit_error (string message, string[] details);
		public signal void important_details_outpout (bool must_show);
		public signal void start_downloading ();
		public signal void stop_downloading ();
		public signal void set_pkgreason_finished (bool success);
		public signal void trans_run_finished (bool success);
		public signal void download_updates_finished ();
		public signal void get_authorization_finished (bool authorized);
		public signal void write_pamac_config_finished ();
		public signal void generate_mirrors_list_data (string line);
		public signal void generate_mirrors_list_finished ();
		public signal void clean_cache_finished (bool success);
		public signal void clean_build_files_finished (bool success);
		#if ENABLE_SNAP
		public signal void snap_trans_run_finished (bool success);
		public signal void snap_switch_channel_finished (bool success);
		#endif

		public Daemon () {
			config = new Config ("/etc/pamac.conf");
			lock_id = new BusName ("");
			authorized = false;
			// alpm_utils global variable declared in alpm_utils.vala
			alpm_utils = new AlpmUtils (config);
			lockfile = GLib.File.new_for_path (alpm_utils.alpm_handle.lockfile);
			check_extern_lock ();
			Timeout.add (200, check_extern_lock);
			create_thread_pool ();
			refreshed = false;
			cond = Cond ();
			mutex = Mutex ();
			alpm_utils.choose_provider.connect ((depend, providers) => {
				return choose_provider_callback (depend, providers);
			});
			alpm_utils.compute_aur_build_list.connect (() => {
				compute_aur_build_list_callback ();
			});
			alpm_utils.ask_edit_build_files.connect ((summary) => {
				return ask_edit_build_files_callback (summary);
			});
			alpm_utils.edit_build_files.connect ((pkgnames) => {
				edit_build_files_callback (pkgnames);
			});
			alpm_utils.ask_commit.connect ((summary) => {
				return ask_commit_callback (summary);
			});
			alpm_utils.emit_action.connect ((action) => {
				emit_action (action);
			});
			alpm_utils.emit_action_progress.connect ((action, status, progress) => {
				emit_action_progress (action, status, progress);
			});
			alpm_utils.emit_hook_progress.connect ((action, details, status, progress) => {
				emit_hook_progress (action, details, status, progress);
			});
			alpm_utils.emit_download_progress.connect ((action, status, progress) => {
				emit_download_progress (action, status, progress);
			});
			alpm_utils.start_downloading.connect (() => {
				start_downloading ();
			});
			alpm_utils.stop_downloading.connect (() => {
				stop_downloading ();
			});
			alpm_utils.emit_script_output.connect ((message) => {
				emit_script_output (message);
			});
			alpm_utils.emit_warning.connect ((message) => {
				emit_warning (message);
			});
			alpm_utils.emit_error.connect ((message, details) => {
				emit_error (message, details);
			});
			alpm_utils.important_details_outpout.connect ((must_show) => {
				important_details_outpout (must_show);
			});
			alpm_utils.get_authorization.connect (() => {
				return get_authorization_sync ();
			});
			#if ENABLE_SNAP
			snap_plugin = config.get_snap_plugin ();
			snap_plugin.emit_action_progress.connect ((action, status, progress) => {
				emit_action_progress (action, status, progress);
			});
			snap_plugin.emit_download_progress.connect ((action, status, progress) => {
				emit_download_progress (action, status, progress);
			});
			snap_plugin.emit_script_output.connect ((message) => {
				emit_script_output (message);
			});
			snap_plugin.emit_error.connect ((message,  details) => {
				emit_error (message,  details);
			});
			snap_plugin.start_downloading.connect (() => { start_downloading (); });
			snap_plugin.stop_downloading.connect (() => { stop_downloading (); });
			#endif
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

		void create_thread_pool () {
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
				critical ("%s\n", e.message);
				emit_error ("Daemon Error", {e.message});
			}
		}

		bool check_extern_lock () {
			if (lock_id == "extern") {
				if (!lockfile.query_exists ()) {
					lock_id = new BusName ("");
					alpm_utils.refresh_handle ();
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

		public bool get_lock () throws Error {
			if (lock_id != "extern") {
				return true;
			}
			return false;
		}

		async bool check_authorization (GLib.BusName sender) {
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
				if (!authorized) {
					emit_error (_("Authentication failed"), {});
				}
			} catch (Error e) {
				critical ("%s\n", e.message);
				emit_error (_("Authentication failed"), {e.message});
			}
			return authorized;
		}

		bool get_authorization_sync () {
			if (authorized) {
				return true;
			}
			authorized = false;
			try {
				Polkit.Authority authority = Polkit.Authority.get_sync ();
				Polkit.Subject subject = new Polkit.SystemBusName (trans_run_sender);
				var result = authority.check_authorization_sync (
					subject,
					"org.manjaro.pamac.commit",
					null,
					Polkit.CheckAuthorizationFlags.ALLOW_USER_INTERACTION);
				authorized = result.get_is_authorized ();
			} catch (Error e) {
				critical ("%s\n", e.message);
				emit_error (_("Authentication failed"), {e.message});
			}
			return authorized;
		}

		public void start_get_authorization (GLib.BusName sender) throws Error {
			check_authorization.begin (sender, (obj, res) => {
				bool tmp_authorized = check_authorization.end (res);
				get_authorization_finished (tmp_authorized);
			});
		}

		public void start_write_pamac_config (HashTable<string,Variant> new_pamac_conf, GLib.BusName sender) throws Error {
			check_authorization.begin (sender, (obj, res) => {
				bool tmp_authorized = check_authorization.end (res);
				if (tmp_authorized) {
					config.write (new_pamac_conf);
					config.reload ();
				}
				write_pamac_config_finished ();
			});
		}

		void generate_mirrors_list () {
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
				critical ("%s\n", e.message);
				emit_error ("Daemon Error", {e.message});
			}
			alpm_utils.alpm_config.reload ();
			alpm_utils.refresh_handle ();
			generate_mirrors_list_finished ();
		}

		public void start_generate_mirrors_list (string country, GLib.BusName sender) throws Error {
			check_authorization.begin (sender, (obj, res) => {
				bool tmp_authorized = check_authorization.end (res);
				if (tmp_authorized) {
					mirrorlist_country = country;
					try {
						thread_pool.add (new AlpmAction (generate_mirrors_list));
					} catch (ThreadError e) {
						critical ("%s\n", e.message);
						emit_error ("Daemon Error", {e.message});
						generate_mirrors_list_finished ();
					}
				}
			});
		}

		public void start_clean_cache (string[] filenames, GLib.BusName sender) throws Error {
			string[] names = filenames;
			check_authorization.begin (sender, (obj, res) => {
				bool tmp_authorized = check_authorization.end (res);
				if (tmp_authorized) {
					alpm_utils.clean_cache (names);
				}
				clean_cache_finished (tmp_authorized);
			});
		}

		public void start_clean_build_files (string aur_build_dir, GLib.BusName sender) throws Error {
			check_authorization.begin (sender, (obj, res) => {
				bool tmp_authorized = check_authorization.end (res);
				if (tmp_authorized) {
					alpm_utils.clean_build_files (aur_build_dir);
				}
				clean_build_files_finished (tmp_authorized);
			});
		}

		public void start_set_pkgreason (string pkgname, uint reason, GLib.BusName sender) throws Error {
			check_authorization.begin (sender, (obj, res) => {
				bool tmp_authorized = check_authorization.end (res);
				bool success = false;
				if (tmp_authorized) {
					lock_id = sender;
					success = alpm_utils.set_pkgreason (pkgname, reason);
					lock_id = new BusName ("");
				}
				set_pkgreason_finished (success);
			});
		}

		public void start_download_updates () throws Error {
			// do not add this thread to the threadpool so it won't be queued
			new Thread<int> ("download updates thread", download_updates);
		}

		int download_updates () {
			alpm_utils.download_updates ();
			download_updates_finished ();
			return 0;
		}

		public void set_trans_flags (int flags) throws Error {
			alpm_utils.flags = flags;
		}

		public void set_no_confirm_commit () throws Error {
			alpm_utils.no_confirm_commit = true;
		}

		public void add_pkg_to_install (string name) throws Error {
			alpm_utils.to_install.add (name);
		}

		public void add_pkg_to_remove (string name) throws Error {
			alpm_utils.to_remove.add (name);
		}

		public void add_path_to_load (string path) throws Error {
			alpm_utils.to_load.add (path);
		}

		public void add_aur_pkg_to_build (string name) throws Error {
			alpm_utils.to_build.add (name);
		}

		public void add_temporary_ignore_pkg (string name) throws Error {
			alpm_utils.temporary_ignorepkgs.add (name);
		}

		public void add_overwrite_file (string glob) throws Error {
			alpm_utils.overwrite_files.add (glob);
		}

		public void add_pkg_to_mark_as_dep (string name) throws Error {
			alpm_utils.to_install_as_dep.insert (name, name);
		}

		public void set_sysupgrade () throws Error {
			alpm_utils.sysupgrade = true;
		}

		public void set_enable_downgrade (bool downgrade) throws Error {
			alpm_utils.enable_downgrade = downgrade;
		}

		public void set_force_refresh () throws Error {
			alpm_utils.force_refresh = true;
		}

		void trans_run () {
			bool success = alpm_utils.trans_run ();
			trans_run_finished (success);
		}

		public void start_trans_run (GLib.BusName sender) throws Error {
			trans_run_sender = sender;
			if (alpm_utils.downloading_updates) {
				alpm_utils.cancellable.cancel ();
				// let time to cancel download updates
				Timeout.add (1000, () => {
					lock_id = sender;
					try {
						thread_pool.add (new AlpmAction (trans_run));
					} catch (ThreadError e) {
						critical ("%s\n", e.message);
						emit_error ("Daemon Error", {e.message});
						trans_run_finished (false);
					}
					return false;
				});
			} else {
				lock_id = sender;
				try {
					thread_pool.add (new AlpmAction (trans_run));
				} catch (ThreadError e) {
					critical ("%s\n", e.message);
					emit_error ("Daemon Error", {e.message});
					trans_run_finished (false);
				}
			}
		}

		int choose_provider_callback (string depend, string[] providers) {
			choosen_provider_answer = null;
			choose_provider (depend, providers);
			mutex.lock ();
			while (choosen_provider_answer == null) {
				cond.wait (mutex);
			}
			mutex.unlock ();
			return choosen_provider_answer;
		}

		public void answer_choose_provider (int provider) throws Error {
			mutex.lock ();
			choosen_provider_answer = provider;
			cond.signal ();
			mutex.unlock ();
		}

		void compute_aur_build_list_callback () {
			compute_aur_build_list_answer = null;
			compute_aur_build_list ();
			mutex.lock ();
			while (compute_aur_build_list_answer == null) {
				cond.wait (mutex);
			}
			mutex.unlock ();
		}

		public void aur_build_list_computed () throws Error {
			mutex.lock ();
			compute_aur_build_list_answer = true;
			cond.signal ();
			mutex.unlock ();
		}

		bool ask_edit_build_files_callback (TransactionSummaryStruct summary) {
			ask_edit_build_files_answer = null;
			ask_edit_build_files (summary);
			mutex.lock ();
			while (ask_edit_build_files_answer == null) {
				cond.wait (mutex);
			}
			mutex.unlock ();
			return ask_edit_build_files_answer;
		}

		public void answer_ask_edit_build_files (bool answer) throws Error {
			mutex.lock ();
			ask_edit_build_files_answer = answer;
			cond.signal ();
			mutex.unlock ();
		}

		void edit_build_files_callback (string[] pkgnames) {
			edit_build_files_answer = null;
			edit_build_files (pkgnames);
			mutex.lock ();
			while (edit_build_files_answer == null) {
				cond.wait (mutex);
			}
			mutex.unlock ();
		}

		public void build_files_edited () throws Error {
			mutex.lock ();
			edit_build_files_answer = true;
			cond.signal ();
			mutex.unlock ();
		}

		bool ask_commit_callback (TransactionSummaryStruct summary) {
			ask_commit_answer = null;
			ask_commit (summary);
			mutex.lock ();
			while (ask_commit_answer == null) {
				cond.wait (mutex);
			}
			mutex.unlock ();
			return ask_commit_answer;
		}

		public void answer_ask_commit (bool answer) throws Error {
			mutex.lock ();
			ask_commit_answer = answer;
			cond.signal ();
			mutex.unlock ();
		}

		#if ENABLE_SNAP
		void snap_trans_run () {
			bool success = snap_plugin.trans_run (snap_to_install, snap_to_remove);
			snap_trans_run_finished (success);
		}

		public void start_snap_trans_run (string[] to_install, string[] to_remove, GLib.BusName sender) throws Error {
			snap_to_install = to_install;
			snap_to_remove = to_remove;
			check_authorization.begin (sender, (obj, res) => {
				bool tmp_authorized = check_authorization.end (res);
				if (tmp_authorized) {
					try {
						thread_pool.add (new AlpmAction (snap_trans_run));
					} catch (ThreadError e) {
						critical ("%s\n", e.message);
						emit_error ("Daemon Error", {e.message});
						snap_trans_run_finished (false);
					}
				} else {
					snap_trans_run_finished (false);
				}
			});
			
		}

		void snap_switch_channel () {
			bool success = snap_plugin.switch_channel (snap_switch_name, snap_channel);
			snap_switch_channel_finished (success);
		}

		public void start_snap_switch_channel (string snap_name, string channel, GLib.BusName sender) throws Error {
			snap_switch_name = snap_name;
			snap_channel = channel;
			check_authorization.begin (sender, (obj, res) => {
				bool tmp_authorized = check_authorization.end (res);
				if (tmp_authorized) {
					try {
						thread_pool.add (new AlpmAction (snap_switch_channel));
					} catch (ThreadError e) {
						critical ("%s\n", e.message);
						emit_error ("Daemon Error", {e.message});
						snap_switch_channel_finished (false);
					}
				} else {
					snap_switch_channel_finished (false);
				}
			});
		}
		#endif

		public void trans_cancel (GLib.BusName sender) throws Error {
			#if ENABLE_SNAP
			snap_plugin.trans_cancel ();
			#endif
			if (lock_id != sender) {
				return;
			}
			alpm_utils.trans_cancel ();
		}

		[DBus (no_reply = true)]
		public void quit () throws Error {
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
