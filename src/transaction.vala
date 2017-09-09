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

namespace Pamac {
	[DBus (name = "org.manjaro.pamac.user")]
	interface UserDaemon : Object {
		public abstract void refresh_handle () throws IOError;
		public abstract AlpmPackage get_installed_pkg (string pkgname) throws IOError;
		public abstract bool get_checkspace () throws IOError;
		public abstract string[] get_ignorepkgs () throws IOError;
		public abstract bool should_hold (string pkgname) throws IOError;
		public abstract uint get_pkg_reason (string pkgname) throws IOError;
		public abstract uint get_pkg_origin (string pkgname) throws IOError;
		public abstract async AlpmPackage[] get_installed_pkgs () throws IOError;
		public abstract async AlpmPackage[] get_explicitly_installed_pkgs () throws IOError;
		public abstract async AlpmPackage[] get_foreign_pkgs () throws IOError;
		public abstract async AlpmPackage[] get_orphans () throws IOError;
		public abstract AlpmPackage find_installed_satisfier (string depstring) throws IOError;
		public abstract AlpmPackage get_sync_pkg (string pkgname) throws IOError;
		public abstract AlpmPackage find_sync_satisfier (string depstring) throws IOError;
		public abstract async AlpmPackage[] search_pkgs (string search_string) throws IOError;
		public abstract async AURPackage[] search_in_aur (string search_string) throws IOError;
		public abstract string[] get_repos_names () throws IOError;
		public abstract async AlpmPackage[] get_repo_pkgs (string repo) throws IOError;
		public abstract string[] get_groups_names () throws IOError;
		public abstract async AlpmPackage[] get_group_pkgs (string groupname) throws IOError;
		public abstract AlpmPackageDetails get_pkg_details (string pkgname) throws IOError;
		public abstract string[] get_pkg_files (string pkgname) throws IOError;
		public abstract async AURPackageDetails get_aur_details (string pkgname) throws IOError;
		public abstract string[] get_pkg_uninstalled_optdeps (string pkgname) throws IOError;
		public abstract void start_get_updates (bool check_aur_updates) throws IOError;
		[DBus (no_reply = true)]
		public abstract void quit () throws IOError;
		public signal void get_updates_finished (Updates updates);
	}
	[DBus (name = "org.manjaro.pamac.system")]
	interface SystemDaemon : Object {
		public abstract void set_environment_variables (HashTable<string,string> variables) throws IOError;
		public abstract string[] get_mirrors_countries () throws IOError;
		public abstract ErrorInfos get_current_error () throws IOError;
		public abstract bool get_lock () throws IOError;
		public abstract bool unlock () throws IOError;
		public abstract void start_get_authorization () throws IOError;
		public abstract void start_write_pamac_config (HashTable<string,Variant> new_pamac_conf) throws IOError;
		public abstract void start_write_alpm_config (HashTable<string,Variant> new_alpm_conf) throws IOError;
		public abstract void start_write_mirrors_config (HashTable<string,Variant> new_mirrors_conf) throws IOError;
		public abstract void start_generate_mirrors_list () throws IOError;
		public abstract void clean_cache (uint keep_nb, bool only_uninstalled) throws IOError;
		public abstract void start_set_pkgreason (string pkgname, uint reason) throws IOError;
		public abstract void start_refresh (bool force) throws IOError;
		public abstract void start_sysupgrade_prepare (bool enable_downgrade, string[] temporary_ignorepkgs) throws IOError;
		public abstract void start_trans_prepare (int transflags, string[] to_install, string[] to_remove, string[] to_load, string[] to_build) throws IOError;
		public abstract void choose_provider (int provider) throws IOError;
		public abstract TransactionSummary get_transaction_summary () throws IOError;
		public abstract void start_trans_commit () throws IOError;
		public abstract void trans_release () throws IOError;
		public abstract void trans_cancel () throws IOError;
		public abstract void start_get_updates (bool check_aur_updates) throws IOError;
		[DBus (no_reply = true)]
		public abstract void quit () throws IOError;
		public signal void get_updates_finished (Updates updates);
		public signal void emit_event (uint primary_event, uint secondary_event, string[] details);
		public signal void emit_providers (string depend, string[] providers);
		public signal void emit_progress (uint progress, string pkgname, uint percent, uint n_targets, uint current_target);
		public signal void emit_download (string filename, uint64 xfered, uint64 total);
		public signal void emit_totaldownload (uint64 total);
		public signal void emit_log (uint level, string msg);
		public signal void set_pkgreason_finished ();
		public signal void refresh_finished (bool success);
		public signal void trans_prepare_finished (bool success);
		public signal void trans_commit_finished (bool success);
		public signal void get_authorization_finished (bool authorized);
		public signal void write_pamac_config_finished (bool recurse, uint64 refresh_period, bool no_update_hide_icon,
														bool enable_aur, bool search_aur, bool check_aur_updates);
		public signal void write_alpm_config_finished (bool checkspace);
		public signal void write_mirrors_config_finished (string choosen_country, string choosen_generation_method);
		public signal void generate_mirrors_list_data (string line);
		public signal void generate_mirrors_list_finished ();
	}

	public class Transaction: Object {

		enum Type {
			STANDARD = (1 << 0),
			UPDATE = (1 << 1),
			BUILD = (1 << 2)
		}

		public enum Mode {
			MANAGER,
			INSTALLER
		}

		UserDaemon user_daemon;
		SystemDaemon system_daemon;

		public Mode mode;
		Pamac.Config pamac_config;
		public bool check_aur_updates { get { return pamac_config.check_aur_updates; } }
		public bool enable_aur { get { return pamac_config.enable_aur; }  }
		public unowned GLib.HashTable<string,string> environment_variables { get {return pamac_config.environment_variables; } }
		public bool no_update_hide_icon { get { return pamac_config.no_update_hide_icon; } }
		public bool recurse { get { return pamac_config.recurse; } }
		public uint64 refresh_period { get { return pamac_config.refresh_period; } }
		public bool search_aur { get { return pamac_config.search_aur; } }

		//Alpm.TransFlag
		int flags;

		public GenericSet<string?> to_install;
		public GenericSet<string?> to_remove;
		public GenericSet<string?> to_load;
		public GenericSet<string?> to_build;
		public GenericSet<string?> to_update;
		Queue<string> to_build_queue;
		string[] aur_pkgs_to_install;
		GenericSet<string?> previous_to_install;
		GenericSet<string?> previous_to_remove;
		public GenericSet<string?> transaction_summary;
		public GenericSet<string?> temporary_ignorepkgs;

		uint64 total_download;
		uint64 already_downloaded;
		string previous_textbar;
		float previous_percent;
		string previous_filename;
		uint pulse_timeout_id;
		bool sysupgrade_after_trans;
		bool enable_downgrade;
		bool no_confirm_commit;
		bool build_after_sysupgrade;
		bool building;
		uint64 previous_xfered;
		uint64 download_rate;
		uint64 rates_nb;
		Timer timer;
		bool success;
		StringBuilder warning_textbuffer;

		//dialogs
		TransactionSumDialog transaction_sum_dialog;
		public ProgressBox progress_box;
		Vte.Terminal term;
		Vte.Pty pty;
		Cancellable build_cancellable;
		public Gtk.ScrolledWindow term_window;
		//parent window
		public Gtk.ApplicationWindow? application_window { get; private set; }

		public signal void start_downloading ();
		public signal void stop_downloading ();
		public signal void start_building ();
		public signal void stop_building ();
		public signal void important_details_outpout (bool must_show);
		public signal void finished (bool success);
		public signal void set_pkgreason_finished ();
		public signal void write_pamac_config_finished (bool recurse, uint64 refresh_period, bool no_update_hide_icon,
														bool enable_aur, bool search_aur, bool check_aur_updates);
		public signal void write_alpm_config_finished (bool checkspace);
		public signal void write_mirrors_config_finished (string choosen_country, string choosen_generation_method);
		public signal void generate_mirrors_list ();
		public signal void run_preferences_dialog_finished ();
		public signal void get_updates_finished (Updates updates);

		public Transaction (Gtk.ApplicationWindow? application_window) {
			mode = Mode.MANAGER;
			pamac_config = new Pamac.Config ("/etc/pamac.conf");
			flags = (1 << 4); //Alpm.TransFlag.CASCADE
			if (pamac_config.recurse) {
				flags |= (1 << 5); //Alpm.TransFlag.RECURSE
			}
			to_install = new GenericSet<string?> (str_hash, str_equal);
			to_remove = new GenericSet<string?> (str_hash, str_equal);
			to_load = new GenericSet<string?> (str_hash, str_equal);
			to_build = new GenericSet<string?> (str_hash, str_equal);
			to_update = new GenericSet<string?> (str_hash, str_equal);
			to_build_queue = new Queue<string> ();
			previous_to_install = new GenericSet<string?> (str_hash, str_equal);
			previous_to_remove = new GenericSet<string?> (str_hash, str_equal);
			transaction_summary = new GenericSet<string?> (str_hash, str_equal);
			temporary_ignorepkgs = new GenericSet<string?> (str_hash, str_equal);
			connecting_user_daemon ();
			//creating dialogs
			this.application_window = application_window;
			transaction_sum_dialog = new TransactionSumDialog (application_window);
			progress_box = new ProgressBox ();
			progress_box.progressbar.text = "";
			//creating terminal
			term = new Vte.Terminal ();
			term.set_scrollback_lines (-1);
			term.expand = true;
			term.visible = true;
			var black = Gdk.RGBA ();
			black.parse ("black");
			term.set_color_cursor (black);
			term.button_press_event.connect (on_term_button_press_event);
			term.key_press_event.connect (on_term_key_press_event);
			// creating pty for term
			try {
				pty = term.pty_new_sync (Vte.PtyFlags.NO_HELPER);
			} catch (Error e) {
				stderr.printf ("Error: %s\n", e.message);
			}
			// add term in a grid with a scrollbar
			term_window = new Gtk.ScrolledWindow (null, term.vadjustment);
			term_window.expand = true;
			term_window.visible = true;
			term_window.propagate_natural_height = true;
			term_window.add (term);
			build_cancellable = new Cancellable ();
			// progress data
			previous_textbar = "";
			previous_filename = "";
			sysupgrade_after_trans = false;
			no_confirm_commit = false;
			build_after_sysupgrade = false;
			building = false;
			timer = new Timer ();
			success = false;
			warning_textbuffer = new StringBuilder ();
		}

		public void run_preferences_dialog () {
			check_authorization.begin ((obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					var preferences_dialog = new PreferencesDialog (this);
					preferences_dialog.run ();
					preferences_dialog.destroy ();
					while (Gtk.events_pending ()) {
						Gtk.main_iteration ();
					}
				}
				run_preferences_dialog_finished ();
			});
		}

		public ErrorInfos get_current_error () {
			try {
				return system_daemon.get_current_error ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				return ErrorInfos ();
			}
		}

		public string[] get_mirrors_countries () {
			string[] countries = {};
			connecting_system_daemon ();
			try {
				countries = system_daemon.get_mirrors_countries ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return countries;
		}

		public bool get_lock () {
			bool locked = false;
			connecting_system_daemon ();
			try {
				locked = system_daemon.get_lock ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return locked;
		}

		public bool unlock () {
			bool unlocked = false;
			try {
				unlocked = system_daemon.unlock ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return unlocked;
		}

		async bool check_authorization () {
			SourceFunc callback = check_authorization.callback;
			bool authorized = false;
			ulong handler_id = system_daemon.get_authorization_finished.connect ((authorized_) => {
				authorized = authorized_;
				Idle.add ((owned) callback);
			});
			try {
				system_daemon.start_get_authorization ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			yield;
			system_daemon.disconnect (handler_id);
			return authorized;
		}

		public void start_write_pamac_config (HashTable<string,Variant> new_pamac_conf) {
			try {
				system_daemon.write_pamac_config_finished.connect (on_write_pamac_config_finished);
				system_daemon.start_write_pamac_config (new_pamac_conf);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				system_daemon.write_pamac_config_finished.disconnect (on_write_pamac_config_finished);
			}
		}

		public void start_write_alpm_config (HashTable<string,Variant> new_alpm_conf) {
			try {
				system_daemon.write_alpm_config_finished.connect (on_write_alpm_config_finished);
				system_daemon.start_write_alpm_config (new_alpm_conf);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				system_daemon.write_alpm_config_finished.disconnect (on_write_alpm_config_finished);
			}
		}

		public void start_write_mirrors_config (HashTable<string,Variant> new_mirrors_conf) {
			try {
				system_daemon.write_mirrors_config_finished.connect (on_write_mirrors_config_finished);
				system_daemon.start_write_mirrors_config (new_mirrors_conf);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				system_daemon.write_mirrors_config_finished.disconnect (on_write_mirrors_config_finished);
			}
		}

		bool on_term_button_press_event (Gdk.EventButton event) {
			// Check if right mouse button was clicked
			if (event.type == Gdk.EventType.BUTTON_PRESS && event.button == 3) {
				if (term.get_has_selection ()) {
					var right_click_menu = new Gtk.Menu ();
					var copy_item = new Gtk.MenuItem.with_label (dgettext (null, "Copy"));
					copy_item.activate.connect (() => {term.copy_clipboard ();});
					right_click_menu.append (copy_item);
					right_click_menu.show_all ();
					right_click_menu.popup (null, null, null, event.button, event.time);
					return true;
				}
			}
			return false;
		}

		bool on_term_key_press_event (Gdk.EventKey event) {
			// Check if Ctrl + c keys were pressed
			if (((event.state & Gdk.ModifierType.CONTROL_MASK) != 0) && (Gdk.keyval_name (event.keyval) == "c")) {
				term.copy_clipboard ();
				return true;
			}
			return false;
		}

		void show_in_term (string message) {
			term.set_pty (pty);
			try {
				Process.spawn_async (null, {"echo", message}, null, SpawnFlags.SEARCH_PATH, pty.child_setup, null);
			} catch (SpawnError e) {
				stderr.printf ("SpawnError: %s\n", e.message);
			}
		}

		async int spawn_in_term (string[] args, string? working_directory = null) {
			SourceFunc callback = spawn_in_term.callback;
			int status = 1;
			term.set_pty (pty);
			var launcher = new SubprocessLauncher (SubprocessFlags.NONE);
			launcher.set_cwd (working_directory);
			launcher.set_environ (Environ.get ());
			launcher.set_child_setup (pty.child_setup);
			try {
				Subprocess process = launcher.spawnv (args);
				process.wait_async.begin (build_cancellable, (obj, res) => {
					try {
						process.wait_async.end (res);
						if (process.get_if_exited ()) {
							status = process.get_exit_status ();
						}
					} catch (Error e) {
						// cancelled
						process.send_signal (Posix.SIGINT);
						process.send_signal (Posix.SIGKILL);
					}
					Idle.add ((owned) callback);
				});
				yield;
			} catch (Error e) {
				stderr.printf ("Error: %s\n", e.message);
			}
			return status;
		}

		void reset_progress_box (string action) {
			show_in_term (action);
			progress_box.action_label.label = action;
			stop_progressbar_pulse ();
			progress_box.progressbar.fraction = 0;
			progress_box.progressbar.text = "";
		}

		public void start_progressbar_pulse () {
			stop_progressbar_pulse ();
			pulse_timeout_id = Timeout.add (500, (GLib.SourceFunc) progress_box.progressbar.pulse);
		}

		public void stop_progressbar_pulse () {
			if (pulse_timeout_id != 0) {
				Source.remove (pulse_timeout_id);
				pulse_timeout_id = 0;
				progress_box.progressbar.fraction = 0;
			}
		}

		public void start_generate_mirrors_list () {
			string action = dgettext (null, "Refreshing mirrors list") + "...";
			reset_progress_box (action);
			start_progressbar_pulse ();
			important_details_outpout (false);
			generate_mirrors_list ();
			try {
				system_daemon.generate_mirrors_list_data.connect (on_generate_mirrors_list_data);
				system_daemon.generate_mirrors_list_finished.connect (on_generate_mirrors_list_finished);
				system_daemon.start_generate_mirrors_list ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				stop_progressbar_pulse ();
				system_daemon.generate_mirrors_list_data.disconnect (on_generate_mirrors_list_data);
				system_daemon.generate_mirrors_list_finished.disconnect (on_generate_mirrors_list_finished);
			}
		}

		public void clean_cache (uint keep_nb, bool only_uninstalled) {
			try {
				system_daemon.clean_cache (keep_nb, only_uninstalled);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void start_set_pkgreason (string pkgname, uint reason) {
			try {
				system_daemon.set_pkgreason_finished.connect (on_set_pkgreason_finished);
				system_daemon.start_set_pkgreason (pkgname, reason);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				system_daemon.set_pkgreason_finished.disconnect (on_set_pkgreason_finished);
			}
		}

		public void start_refresh (bool force) {
			check_authorization.begin ((obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					string action = dgettext (null, "Synchronizing package databases") + "...";
					reset_progress_box (action);
					connecting_system_daemon ();
					connecting_dbus_signals ();
					try {
						system_daemon.refresh_finished.connect (on_refresh_finished);
						system_daemon.start_refresh (force);
					} catch (IOError e) {
						stderr.printf ("IOError: %s\n", e.message);
						system_daemon.refresh_finished.disconnect (on_refresh_finished);
						success = false;
						finish_transaction ();
					}
				} else {
					success = false;
					finish_transaction ();
				}
			});
		}

		public void refresh_handle () {
			try {
				user_daemon.refresh_handle ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public bool get_checkspace () {
			bool checkspace = false;
			try {
				checkspace = user_daemon.get_checkspace ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return checkspace;
		}

		public string[] get_ignorepkgs () {
			string[] ignorepkgs = {};
			try {
				ignorepkgs = user_daemon.get_ignorepkgs ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return ignorepkgs;
		}

		public AlpmPackage get_installed_pkg (string pkgname) {
			try {
				return user_daemon.get_installed_pkg (pkgname);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				return AlpmPackage () {
					name = "",
					version = "",
					desc = "",
					repo = ""
				};
			}
		}

		public AlpmPackage find_installed_satisfier (string depstring) {
			try {
				return user_daemon.find_installed_satisfier (depstring);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				return AlpmPackage () {
					name = "",
					version = "",
					desc = "",
					repo = ""
				};
			}
		}

		public bool should_hold (string pkgname) {
			bool should_hold = false;
			try {
				should_hold = user_daemon.should_hold (pkgname);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return should_hold;
		}

		public uint get_pkg_reason (string pkgname) {
			uint reason = 0;
			try {
				reason = user_daemon.get_pkg_reason (pkgname);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return reason;
		}

		public uint get_pkg_origin (string pkgname) {
			uint origin = 0;
			try {
				origin = user_daemon.get_pkg_origin (pkgname);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return origin;
		}

		public async AlpmPackage[] get_installed_pkgs () {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = yield user_daemon.get_installed_pkgs ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return pkgs;
		}

		public async AlpmPackage[] get_explicitly_installed_pkgs () {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = yield user_daemon.get_explicitly_installed_pkgs ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return pkgs;
		}

		public async AlpmPackage[] get_foreign_pkgs () {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = yield user_daemon.get_foreign_pkgs ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return pkgs;
		}

		public async AlpmPackage[] get_orphans () {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = yield user_daemon.get_orphans ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return pkgs;
		}

		public AlpmPackage get_sync_pkg (string pkgname) {
			try {
				return user_daemon.get_sync_pkg (pkgname);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				return AlpmPackage () {
					name = "",
					version = "",
					desc = "",
					repo = ""
				};
			}
		}

		public AlpmPackage find_sync_satisfier (string depstring) {
			try {
				return user_daemon.find_sync_satisfier (depstring);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				return AlpmPackage () {
					name = "",
					version = "",
					desc = "",
					repo = ""
				};
			}
		}

		public async AlpmPackage[] search_pkgs (string search_string) {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = yield user_daemon.search_pkgs (search_string);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return pkgs;
		}

		public async AURPackage[] search_in_aur (string search_string) {
			AURPackage[] pkgs = {};
			try {
				pkgs = yield user_daemon.search_in_aur (search_string);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return pkgs;
		}

		public string[] get_repos_names () {
			string[] repos_names = {};
			try {
				repos_names = user_daemon.get_repos_names ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return repos_names;
		}

		public async AlpmPackage[] get_repo_pkgs (string repo) {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = yield user_daemon.get_repo_pkgs (repo);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return pkgs;
		}

		public string[] get_groups_names () {
			string[] groups_names = {};
			try {
				groups_names = user_daemon.get_groups_names ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return groups_names;
		}

		public async AlpmPackage[] get_group_pkgs (string group_name) {
			AlpmPackage[] pkgs = {};
			try {
				pkgs = yield user_daemon.get_group_pkgs (group_name);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return pkgs;
		}

		public string[] get_pkg_uninstalled_optdeps (string pkgname) {
			string[] optdeps = {};
			try {
				optdeps = user_daemon.get_pkg_uninstalled_optdeps (pkgname);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			return optdeps;
		}

		public AlpmPackageDetails get_pkg_details (string pkgname) {
			try {
				return user_daemon.get_pkg_details (pkgname);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				return AlpmPackageDetails () {
					name = "",
					version = "",
					desc = "",
					repo = "",
					url = "",
					packager = "",
					builddate = "",
					installdate = "",
					reason = "",
					has_signature = ""
				};
			}
		}

		public string[] get_pkg_files (string pkgname) {
			try {
				return user_daemon.get_pkg_files (pkgname);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				return {};
			}
		}

		public async AURPackageDetails get_aur_details (string pkgname) {
			var pkg = AURPackageDetails () {
				name = "",
				version = "",
				desc = "",
				packagebase = "",
				url = "",
				maintainer = ""
			};
			try {
				pkg = yield user_daemon.get_aur_details (pkgname);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message); 
			}
			return pkg;
		}

		public void start_get_updates () {
			user_daemon.get_updates_finished.connect (on_get_updates_finished);
			try {
				user_daemon.start_get_updates (pamac_config.enable_aur && pamac_config.check_aur_updates);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				success = false;
				finish_transaction ();
			}
		}

		void start_get_updates_for_sysupgrade () {
			system_daemon.get_updates_finished.connect (on_get_updates_for_sysupgrade_finished);
			try {
				system_daemon.start_get_updates (pamac_config.enable_aur && pamac_config.check_aur_updates);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				success = false;
				finish_transaction ();
			}
		}

		void sysupgrade_simple (bool enable_downgrade) {
			progress_box.progressbar.fraction = 0;
			string[] temporary_ignorepkgs_ = {};
			foreach (unowned string pkgname in temporary_ignorepkgs) {
				temporary_ignorepkgs_ += pkgname;
			}
			connecting_system_daemon ();
			connecting_dbus_signals ();
			try {
				// this will respond with trans_prepare_finished signal
				system_daemon.start_sysupgrade_prepare (enable_downgrade, temporary_ignorepkgs_);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				success = false;
				finish_transaction ();
			}
		}

		public void sysupgrade (bool enable_downgrade) {
			this.enable_downgrade = enable_downgrade;
			string action = dgettext (null, "Starting full system upgrade") + "...";
			reset_progress_box (action);
			start_get_updates_for_sysupgrade ();
		}

		void on_get_updates_finished (Updates updates) {
			user_daemon.get_updates_finished.disconnect (on_get_updates_finished);
			get_updates_finished (updates);
		}

		void on_get_updates_for_sysupgrade_finished (Updates updates) {
			system_daemon.get_updates_finished.disconnect (on_get_updates_for_sysupgrade_finished);
			// get syncfirst updates
			if (updates.is_syncfirst) {
				clear_lists ();
				sysupgrade_after_trans = true;
				no_confirm_commit = true;
				foreach (unowned AlpmPackage infos in updates.repos_updates) {
					to_install.add (infos.name);
				}
				// run as a standard transaction
				run ();
			} else {
				if (updates.aur_updates.length != 0) {
					clear_lists ();
					foreach (unowned AURPackage infos in updates.aur_updates) {
						if (!(infos.name in temporary_ignorepkgs)) {
							to_build.add (infos.name);
						}
					}
					if (updates.repos_updates.length != 0) {
						build_after_sysupgrade = true;
						sysupgrade_simple (enable_downgrade);
					} else {
						// only aur updates
						// run as a standard transaction
						run ();
					}
				} else {
					if (updates.repos_updates.length != 0) {
						sysupgrade_simple (enable_downgrade);
					} else {
						finish_transaction ();
						stop_progressbar_pulse ();
					}
				}
			}
		}

		public void clear_lists () {
			to_install.remove_all ();
			to_remove.remove_all ();
			to_build.remove_all ();
			to_load.remove_all ();
		}

		void clear_previous_lists () {
			previous_to_install.remove_all ();
			previous_to_remove.remove_all ();
		}

		void start_trans_prepare (int transflags, string[] to_install, string[] to_remove, string[] to_load, string[] to_build) {
			try {
				system_daemon.start_trans_prepare (transflags, to_install, to_remove, to_load, to_build);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				stop_progressbar_pulse ();
				success = false;
				finish_transaction ();
			}
		}

		public void run () {
			string action = dgettext (null, "Preparing") + "...";
			reset_progress_box (action);
			start_progressbar_pulse ();
			string[] to_install_ = {};
			string[] to_remove_ = {};
			string[] to_load_ = {};
			string[] to_build_ = {};
			foreach (unowned string name in to_install) {
				to_install_ += name;
			}
			foreach (unowned string name in to_remove) {
				to_remove_ += name;
			}
			foreach (unowned string path in to_load) {
				to_load_ += path;
			}
			foreach (unowned string name in to_build) {
				to_build_ += name;
			}
			connecting_system_daemon ();
			connecting_dbus_signals ();
			start_trans_prepare (flags, to_install_, to_remove_, to_load_, to_build_);
		}

		void choose_provider (string depend, string[] providers) {
			var choose_provider_dialog = new ChooseProviderDialog (application_window);
			choose_provider_dialog.title = dgettext (null, "Choose a provider for %s").printf (depend);
			unowned Gtk.Box box = choose_provider_dialog.get_content_area ();
			Gtk.RadioButton? last_radiobutton = null;
			Gtk.RadioButton? first_radiobutton = null;
			foreach (unowned string provider in providers) {
				var radiobutton = new Gtk.RadioButton.with_label_from_widget (last_radiobutton, provider);
				radiobutton.visible = true;
				// active first provider
				if (last_radiobutton == null) {
					radiobutton.active = true;
					first_radiobutton = radiobutton;
				}
				last_radiobutton = radiobutton;
				box.add (radiobutton);
			}
			choose_provider_dialog.run ();
			// get active provider
			int index = 0;
			// list is given in reverse order so reverse it !
			SList<unowned Gtk.RadioButton> list = last_radiobutton.get_group ().copy ();
			list.reverse ();
			foreach (var radiobutton in list) {
				if (radiobutton.active) {
					try {
						system_daemon.choose_provider (index);
					} catch (IOError e) {
						stderr.printf ("IOError: %s\n", e.message);
					}
				}
				index++;
			}
			choose_provider_dialog.destroy ();
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
		}

		Type set_transaction_sum () {
			// return 0 if transaction_sum is empty, 2, if there are only aur updates, 1 otherwise
			Type type = 0;
			uint64 dsize = 0;
			transaction_summary.remove_all ();
			var summary = TransactionSummary ();
			transaction_sum_dialog.sum_list.clear ();
			try {
				summary = system_daemon.get_transaction_summary ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			var iter = Gtk.TreeIter ();
			if (summary.to_remove.length > 0) {
				type |= Type.STANDARD;
				foreach (unowned UpdateInfos infos in summary.to_remove) {
					transaction_summary.add (infos.name);
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, infos.name,
												2, infos.old_version);
				}
				Gtk.TreePath path = transaction_sum_dialog.sum_list.get_path (iter);
				int pos = (path.get_indices ()[0]) - (summary.to_remove.length - 1);
				transaction_sum_dialog.sum_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				transaction_sum_dialog.sum_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "To remove") + ":"));
			}
			if (summary.aur_conflicts_to_remove.length > 0) {
				// do not add type enum because it is just infos
				foreach (unowned UpdateInfos infos in summary.aur_conflicts_to_remove) {
					transaction_summary.add (infos.name);
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, infos.name,
												2, infos.old_version);
				}
				Gtk.TreePath path = transaction_sum_dialog.sum_list.get_path (iter);
				int pos = (path.get_indices ()[0]) - (summary.aur_conflicts_to_remove.length - 1);
				transaction_sum_dialog.sum_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				transaction_sum_dialog.sum_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "To remove") + ":"));
			}
			if (summary.to_downgrade.length > 0) {
				type |= Type.STANDARD;
				foreach (unowned UpdateInfos infos in summary.to_downgrade) {
					dsize += infos.download_size;
					transaction_summary.add (infos.name);
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, infos.name,
												2, infos.new_version,
												3, "(%s)".printf (infos.old_version));
				}
				Gtk.TreePath path = transaction_sum_dialog.sum_list.get_path (iter);
				int pos = (path.get_indices ()[0]) - (summary.to_downgrade.length - 1);
				transaction_sum_dialog.sum_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				transaction_sum_dialog.sum_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "To downgrade") + ":"));
			}
			if (summary.to_build.length > 0) {
				type |= Type.BUILD;
				// populate build queue
				foreach (unowned string name in summary.aur_pkgbases_to_build) {
					to_build_queue.push_tail (name);
				}
				aur_pkgs_to_install = {};
				foreach (unowned UpdateInfos infos in summary.to_build) {
					aur_pkgs_to_install += infos.name;
					transaction_summary.add (infos.name);
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, infos.name,
												2, infos.new_version);
				}
				Gtk.TreePath path = transaction_sum_dialog.sum_list.get_path (iter);
				int pos = (path.get_indices ()[0]) - (summary.to_build.length - 1);
				transaction_sum_dialog.sum_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				transaction_sum_dialog.sum_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "To build") + ":"));
			}
			if (summary.to_install.length > 0) {
				type |= Type.STANDARD;
				foreach (unowned UpdateInfos infos in summary.to_install) {
					dsize += infos.download_size;
					transaction_summary.add (infos.name);
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, infos.name,
												2, infos.new_version);
				}
				Gtk.TreePath path = transaction_sum_dialog.sum_list.get_path (iter);
				int pos = (path.get_indices ()[0]) - (summary.to_install.length - 1);
				transaction_sum_dialog.sum_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				transaction_sum_dialog.sum_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "To install") + ":"));
			}
			if (summary.to_reinstall.length > 0) {
				type |= Type.STANDARD;
				foreach (unowned UpdateInfos infos in summary.to_reinstall) {
					dsize += infos.download_size;
					transaction_summary.add (infos.name);
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, infos.name,
												2, infos.old_version);
				}
				Gtk.TreePath path = transaction_sum_dialog.sum_list.get_path (iter);
				int pos = (path.get_indices ()[0]) - (summary.to_reinstall.length - 1);
				transaction_sum_dialog.sum_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				transaction_sum_dialog.sum_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "To reinstall") + ":"));
			}
			if (summary.to_upgrade.length > 0) {
				type |= Type.UPDATE;
				if (mode == Mode.INSTALLER) {
					foreach (unowned UpdateInfos infos in summary.to_upgrade) {
						dsize += infos.download_size;
						transaction_summary.add (infos.name);
						transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
													1, infos.name,
													2, infos.new_version,
													3, "(%s)".printf (infos.old_version));
					}
					Gtk.TreePath path = transaction_sum_dialog.sum_list.get_path (iter);
					int pos = (path.get_indices ()[0]) - (summary.to_upgrade.length - 1);
					transaction_sum_dialog.sum_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
					transaction_sum_dialog.sum_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "To upgrade") + ":"));
				}
			}
			if (dsize == 0) {
				transaction_sum_dialog.top_label.visible = false;
			} else {
				transaction_sum_dialog.top_label.set_markup ("<b>%s: %s</b>".printf (dgettext (null, "Total download size"), format_size (dsize)));
				transaction_sum_dialog.top_label.visible = true;
			}
			return type;
		}

		void start_commit () {
			try {
				system_daemon.start_trans_commit ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				success = false;
				finish_transaction ();
			}
		}

		async void build_aur_packages () {
			string pkgname = to_build_queue.pop_head ();
			string action = dgettext (null, "Building %s").printf (pkgname) + "...";
			reset_progress_box (action);
			build_cancellable.reset ();
			start_progressbar_pulse ();
			important_details_outpout (false);
			to_build.remove_all ();
			string [] built_pkgs = {};
			int status = 1;
			string builddir = "/tmp/pamac-build-%s".printf (Environment.get_user_name ());
			status = yield spawn_in_term ({"mkdir", "-p", builddir});
			if (status == 0) {
				status = yield spawn_in_term ({"rm", "-rf", pkgname}, builddir);
				if (!build_cancellable.is_cancelled ()) {
					if (status == 0) {
						building = true;
						start_building ();
						status = yield spawn_in_term ({"git", "clone", "https://aur.archlinux.org/%s.git".printf (pkgname)}, builddir);
						if (status == 0) {
							string pkgdir = "%s/%s".printf (builddir, pkgname);
							status = yield spawn_in_term ({"makepkg", "-c"}, pkgdir);
							building = false;
							if (status == 0) {
								foreach (unowned string aurpkg in aur_pkgs_to_install) {
									string standard_output;
									try {
										Process.spawn_command_line_sync ("find %s -name %s".printf (pkgdir, "'%s-*.pkg.tar*'".printf (aurpkg)),
																	out standard_output,
																	null,
																	out status);
										if (status == 0) {
											foreach (unowned string path in standard_output.split ("\n")) {
												if (path != "" && !(path in built_pkgs)) {
													built_pkgs += path;
												}
											}
										}
									} catch (SpawnError e) {
										stderr.printf ("SpawnError: %s\n", e.message);
										status = 1;
									}
								}
							}
						}
						stop_building ();
					}
				} else {
					status = 1;
				}
			}
			building = false;
			if (status == 0) {
				if (built_pkgs.length > 0) {
					no_confirm_commit = true;
					show_in_term ("");
					stop_progressbar_pulse ();
					start_trans_prepare (flags, {}, {}, built_pkgs, {});
				}
			} else {
				important_details_outpout (true);
				to_load.remove_all ();
				to_build_queue.clear ();
				stop_progressbar_pulse ();
				success = false;
				finish_transaction ();
			}
		}

		public void cancel () {
			if (building) {
				build_cancellable.cancel ();
			} else {
				try {
					system_daemon.trans_cancel ();
				} catch (IOError e) {
					stderr.printf ("IOError: %s\n", e.message);
				}
			}
			show_in_term ("\n" + dgettext (null, "Transaction cancelled") + ".\n");
			progress_box.action_label.label = "";
			warning_textbuffer = new StringBuilder ();
		}

		public void release () {
			try {
				system_daemon.trans_release ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			warning_textbuffer = new StringBuilder ();
		}

		public void stop_daemon () {
			try {
				user_daemon.quit ();
				if (system_daemon != null) {
					system_daemon.quit ();
				}
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		void on_emit_event (uint primary_event, uint secondary_event, string[] details) {
			string? action = null;
			string? detailed_action = null;
			switch (primary_event) {
				case 1: //Alpm.Event.Type.CHECKDEPS_START
					action = dgettext (null, "Checking dependencies") + "...";
					break;
				case 3: //Alpm.Event.Type.FILECONFLICTS_START
					action = dgettext (null, "Checking file conflicts") + "...";
					break;
				case 5: //Alpm.Event.Type.RESOLVEDEPS_START
					action = dgettext (null, "Resolving dependencies") + "...";
					break;
				case 7: //Alpm.Event.Type.INTERCONFLICTS_START
					action = dgettext (null, "Checking inter-conflicts") + "...";
					break;
				case 11: //Alpm.Event.Type.PACKAGE_OPERATION_START
					switch (secondary_event) {
						// special case handle differently
						case 1: //Alpm.Package.Operation.INSTALL
							previous_filename = details[0];
							string msg = dgettext (null, "Installing %s").printf (details[0]) + "...";
							progress_box.action_label.label = msg;
							show_in_term (dgettext (null, "Installing %s").printf ("%s (%s)".printf (details[0], details[1])) + "...");
							break;
						case 2: //Alpm.Package.Operation.UPGRADE
							previous_filename = details[0];
							string msg = dgettext (null, "Upgrading %s").printf (details[0]) + "...";
							progress_box.action_label.label = msg;
							show_in_term (dgettext (null, "Upgrading %s").printf ("%s (%s -> %s)".printf (details[0], details[1], details[2])) + "...");
							break;
						case 3: //Alpm.Package.Operation.REINSTALL
							previous_filename = details[0];
							string msg = dgettext (null, "Reinstalling %s").printf (details[0]) + "...";
							progress_box.action_label.label = msg;
							show_in_term (dgettext (null, "Reinstalling %s").printf ("%s (%s)".printf (details[0], details[1])) + "...");
							break;
						case 4: //Alpm.Package.Operation.DOWNGRADE
							previous_filename = details[0];
							string msg = dgettext (null, "Downgrading %s").printf (details[0]) + "...";
							progress_box.action_label.label = msg;
							show_in_term (dgettext (null, "Downgrading %s").printf ("%s (%s -> %s)".printf (details[0], details[1], details[2])) + "...");
							break;
						case 5: //Alpm.Package.Operation.REMOVE
							previous_filename = details[0];
							string msg = dgettext (null, "Removing %s").printf (details[0]) + "...";
							progress_box.action_label.label = msg;
							show_in_term (dgettext (null, "Removing %s").printf ("%s (%s)".printf (details[0], details[1])) + "...");
							break;
					}
					break;
				case 13: //Alpm.Event.Type.INTEGRITY_START
					action = dgettext (null, "Checking integrity") + "...";
					break;
				case 15: //Alpm.Event.Type.LOAD_START
					action = dgettext (null, "Loading packages files") + "...";
					break;
				case 17: //Alpm.Event.Type.DELTA_INTEGRITY_START
					action = dgettext (null, "Checking delta integrity") + "...";
					break;
				case 19: //Alpm.Event.Type.DELTA_PATCHES_START
					action = dgettext (null, "Applying deltas") + "...";
					break;
				case 21: //Alpm.Event.Type.DELTA_PATCH_START
					detailed_action = dgettext (null, "Generating %s with %s").printf (details[0], details[1]) + "...";
					break;
				case 22: //Alpm.Event.Type.DELTA_PATCH_DONE
					detailed_action = dgettext (null, "Generation succeeded") + "...";
					break;
				case 23: //Alpm.Event.Type.DELTA_PATCH_FAILED
					detailed_action = dgettext (null, "Generation failed") + "...";
					break;
				case 24: //Alpm.Event.Type.SCRIPTLET_INFO
					// hooks output are also emitted as SCRIPTLET_INFO
					if (previous_filename != "") {
						progress_box.action_label.label = dgettext (null, "Configuring %s").printf (previous_filename) + "...";
					}
					detailed_action = details[0].replace ("\n", "");
					important_details_outpout (false);
					break;
				case 25: //Alpm.Event.Type.RETRIEVE_START
					start_downloading ();
					action = dgettext (null, "Downloading") + "...";
					break;
				case 26: //Alpm.Event.Type.RETRIEVE_DONE
				case 27: //Alpm.Event.Type.RETRIEVE_FAILED
					stop_downloading ();
					break;
				case 28: //Alpm.Event.Type.PKGDOWNLOAD_START
					// special case handle differently
					show_in_term (dgettext (null, "Downloading %s").printf (details[0]) + "...");
					string name_version_release = details[0].slice (0, details[0].last_index_of_char ('-'));
					string name_version = name_version_release.slice (0, name_version_release.last_index_of_char ('-'));
					string name = name_version.slice (0, name_version.last_index_of_char ('-'));
					progress_box.action_label.label = dgettext (null, "Downloading %s").printf (name) + "...";
					break;
				case 31: //Alpm.Event.Type.DISKSPACE_START
					action = dgettext (null, "Checking available disk space") + "...";
					break;
				case 33: //Alpm.Event.Type.OPTDEP_REMOVAL
					detailed_action = dgettext (null, "%s optionally requires %s").printf (details[0], details[1]);
					warning_textbuffer.append (detailed_action + "\n");
					break;
				case 34: //Alpm.Event.Type.DATABASE_MISSING
					detailed_action = dgettext (null, "Database file for %s does not exist").printf (details[0]);
					break;
				case 35: //Alpm.Event.Type.KEYRING_START
					action = dgettext (null, "Checking keyring") + "...";
					break;
				case 37: //Alpm.Event.Type.KEY_DOWNLOAD_START
					action = dgettext (null, "Downloading required keys") + "...";
					break;
				case 39: //Alpm.Event.Type.PACNEW_CREATED
					detailed_action = dgettext (null, "%s installed as %s.pacnew").printf (details[0], details[0]);
					break;
				case 40: //Alpm.Event.Type.PACSAVE_CREATED
					detailed_action = dgettext (null, "%s installed as %s.pacsave").printf (details[0], details[0]);
					break;
				case 41: //Alpm.Event.Type.HOOK_START
					switch (secondary_event) {
						case 1: //Alpm.HookWhen.PRE_TRANSACTION
							action = dgettext (null, "Running pre-transaction hooks") + "...";
							break;
						case 2: //Alpm.HookWhen.POST_TRANSACTION
							previous_filename = "";
							action = dgettext (null, "Running post-transaction hooks") + "...";
							break;
						default:
							break;
					}
					break;
				case 43: // Alpm.Event.Type.HOOK_RUN_START
					float fraction = (float) int.parse (details[2]) / int.parse (details[3]);
					if (fraction != previous_percent) {
						previous_percent = fraction;
						progress_box.progressbar.fraction = fraction;
					}
					string textbar = "%s/%s".printf (details[2], details[3]);
					if (textbar != previous_textbar) {
						previous_textbar = textbar;
						progress_box.progressbar.text = textbar;
					}
					if (details[1] != "") {
						detailed_action = details[1];
					} else {
						detailed_action = details[0];
					}
					break;
				default:
					break;
			}
			if (action != null) {
				progress_box.action_label.label = action;
				show_in_term (action);
			}
			if (detailed_action != null) {
				show_in_term (detailed_action);
			}
		}

		void on_emit_providers (string depend, string[] providers) {
			choose_provider (depend, providers);
		}

		void on_emit_progress (uint progress, string pkgname, uint percent, uint n_targets, uint current_target) {
			float fraction;
			switch (progress) {
				case 0: //Alpm.Progress.ADD_START
				case 1: //Alpm.Progress.UPGRADE_START
				case 2: //Alpm.Progress.DOWNGRADE_START
				case 3: //Alpm.Progress.REINSTALL_START
				case 4: //Alpm.Progress.REMOVE_START
					fraction = ((float) (current_target - 1) / n_targets) + ((float) percent / (100 * n_targets));
					break;
				case 5: //Alpm.Progress.CONFLICTS_START
				case 6: //Alpm.Progress.DISKSPACE_START
				case 7: //Alpm.Progress.INTEGRITY_START
				case 8: //Alpm.Progress.LOAD_START
				case 9: //Alpm.Progress.KEYRING_START
				default:
					fraction = (float) percent / 100;
					break;
			}
			string textbar = "%lu/%lu".printf (current_target, n_targets);
			if (textbar != previous_textbar) {
				previous_textbar = textbar;
				progress_box.progressbar.text = textbar;
			}
			if (fraction != previous_percent) {
				previous_percent = fraction;
				progress_box.progressbar.fraction = fraction;
			}
		}

		void on_emit_download (string filename, uint64 xfered, uint64 total) {
			var text = new StringBuilder ();
			float fraction;
			if (total_download > 0) {
				if (xfered == 0) {
					// start download pkg is handled by Alpm.Event.Type.PKGDOWNLOAD_START
					previous_xfered = 0;
					fraction = previous_percent;
					text.append (previous_textbar);
					timer.start ();
				} else {
					if (timer.elapsed () > 0.1) {
						download_rate = ((download_rate * rates_nb) + (uint64) ((xfered - previous_xfered) / timer.elapsed ())) / (rates_nb + 1);
						rates_nb++;
					}
					previous_xfered = xfered;
					uint64 downloaded_total = xfered + already_downloaded;
					fraction = (float) downloaded_total / total_download;
					if (fraction <= 1) {
						text.append ("%s/%s  ".printf (format_size (xfered + already_downloaded), format_size (total_download)));
						uint64 remaining_seconds = 0;
						if (download_rate > 0) {
							remaining_seconds = (total_download - downloaded_total) / download_rate;
						}
						// display remaining time after 5s and only if more than 10s are remaining
						if (remaining_seconds > 9 && rates_nb > 9) {
							if (remaining_seconds <= 50) {
								text.append (dgettext (null, "About %u seconds remaining").printf ((uint) Math.ceilf ((float) remaining_seconds / 10) * 10));
							} else {
								uint remaining_minutes = (uint) Math.ceilf ((float) remaining_seconds / 60);
								text.append (dngettext (null, "About %lu minute remaining",
											"About %lu minutes remaining", remaining_minutes).printf (remaining_minutes));
							}
						}
					} else {
						text.append ("%s".printf (format_size (xfered + already_downloaded)));
					}
					if (xfered == total) {
						previous_filename = "";
						already_downloaded += total;
					} else {
						timer.start ();
					}
				}
			} else {
				if (xfered == 0) {
					previous_xfered = 0;
					download_rate = 0;
					rates_nb = 0;
					fraction = 0;
					timer.start ();
					if (filename.has_suffix (".db") || filename.has_suffix (".files")) {
						string action = dgettext (null, "Refreshing %s").printf (filename) + "...";
						reset_progress_box (action);
					}
				} else if (xfered == total) {
					timer.stop ();
					fraction = 1;
					previous_filename = "";
				} else {
					if (timer.elapsed () > 0.1) {
						download_rate = ((download_rate * rates_nb) + (uint64) ((xfered - previous_xfered) / timer.elapsed ())) / (rates_nb + 1);
						rates_nb++;
					}
					previous_xfered = xfered;
					fraction = (float) xfered / total;
					if (fraction <= 1) {
						text.append ("%s/%s  ".printf (format_size (xfered), format_size (total)));
						uint64 remaining_seconds = 0;
						if (download_rate > 0) {
							remaining_seconds = (total - xfered) / download_rate;
						}
						// display remaining time after 5s and only if more than 10s are remaining
						if (remaining_seconds > 9 && rates_nb > 9) {
							if (remaining_seconds <= 50) {
								text.append (dgettext (null, "About %u seconds remaining").printf ((uint) Math.ceilf ((float) remaining_seconds / 10) * 10));
							} else {
								uint remaining_minutes = (uint) Math.ceilf ((float) remaining_seconds / 60);
								text.append (dngettext (null, "About %lu minute remaining",
											"About %lu minutes remaining", remaining_minutes).printf (remaining_minutes));
							}
						}
					} else {
						text.append ("%s".printf (format_size (xfered)));
					}
					// reinitialize timer
					timer.start ();
				}
			}
			if (fraction != previous_percent) {
				previous_percent = fraction;
				progress_box.progressbar.fraction = fraction;
			}
			if (text.str != previous_textbar) {
				previous_textbar = text.str;
				progress_box.progressbar.text = text.str;
			}
		}

		void on_emit_totaldownload (uint64 total) {
			download_rate = 0;
			rates_nb = 0;
			previous_percent = 0;
			previous_textbar = "";
			total_download = total;
			//  this is emitted at the end of the total download 
			// with the value 0 so stop our timer
			if (total == 0) {
				timer.stop ();
				progress_box.progressbar.text = "";
			}
		}

		void on_emit_log (uint level, string msg) {
			// msg ends with \n
			string? line = null;
			if (level == 1) { //Alpm.LogLevel.ERROR
				if (previous_filename != "") {
					line = dgettext (null, "Error") + ": " + previous_filename + ": " + msg;
				} else {
					line = dgettext (null, "Error") + ": " + msg;
				}
				important_details_outpout (false);
			} else if (level == (1 << 1)) { //Alpm.LogLevel.WARNING
				// do not show warning when manjaro-system remove db.lck
				if (previous_filename != "manjaro-system") {
					if (previous_filename != "") {
						line = dgettext (null, "Warning") + ": " + previous_filename + ": " + msg;
					} else {
						line = dgettext (null, "Warning") + ": " + msg;
					}
					warning_textbuffer.append (msg);
				}
			}
			if (line != null) {
				show_in_term (line.replace ("\n", ""));
			}
		}

		void show_warnings () {
			if (warning_textbuffer.len > 0) {
				var flags = Gtk.DialogFlags.MODAL;
				int use_header_bar;
				Gtk.Settings.get_default ().get ("gtk-dialogs-use-header", out use_header_bar);
				if (use_header_bar == 1) {
					flags |= Gtk.DialogFlags.USE_HEADER_BAR;
				}
				var dialog = new Gtk.Dialog.with_buttons (dgettext (null, "Warning"),
														application_window,
														flags);
				dialog.border_width = 6;
				dialog.icon_name = "system-software-install";
				dialog.deletable = false;
				unowned Gtk.Widget widget = dialog.add_button (dgettext (null, "_Close"), Gtk.ResponseType.CLOSE);
				widget.can_focus = true;
				widget.has_focus = true;
				widget.can_default = true;
				widget.has_default = true;
				var scrolledwindow = new Gtk.ScrolledWindow (null, null);
				var label = new Gtk.Label (warning_textbuffer.str);
				label.margin = 12;
				scrolledwindow.visible = true;
				label.visible = true;
				scrolledwindow.add (label);
				scrolledwindow.expand = true;
				unowned Gtk.Box box = dialog.get_content_area ();
				box.add (scrolledwindow);
				dialog.default_width = 600;
				dialog.default_height = 300;
				dialog.run ();
				dialog.destroy ();
				warning_textbuffer = new StringBuilder ();
			}
		}

		public void display_error (string message, string[] details) {
			var flags = Gtk.DialogFlags.MODAL;
			int use_header_bar;
			Gtk.Settings.get_default ().get ("gtk-dialogs-use-header", out use_header_bar);
			if (use_header_bar == 1) {
				flags |= Gtk.DialogFlags.USE_HEADER_BAR;
			}
			var dialog = new Gtk.Dialog.with_buttons (message,
													application_window,
													flags);
			dialog.border_width = 6;
			dialog.icon_name = "system-software-install";
			var textbuffer = new StringBuilder ();
			if (details.length != 0) {
				show_in_term (message + ":");
				foreach (unowned string detail in details) {
					show_in_term (detail);
					textbuffer.append (detail + "\n");
				}
			} else {
				show_in_term (message);
				textbuffer.append (message);
			}
			dialog.deletable = false;
			unowned Gtk.Widget widget = dialog.add_button (dgettext (null, "_Close"), Gtk.ResponseType.CLOSE);
			widget.can_focus = true;
			widget.has_focus = true;
			widget.can_default = true;
			widget.has_default = true;
			var scrolledwindow = new Gtk.ScrolledWindow (null, null);
			var label = new Gtk.Label (textbuffer.str);
			label.margin = 12;
			scrolledwindow.visible = true;
			label.visible = true;
			scrolledwindow.add (label);
			scrolledwindow.expand = true;
			unowned Gtk.Box box = dialog.get_content_area ();
			box.add (scrolledwindow);
			dialog.default_width = 600;
			dialog.default_height = 300;
			dialog.run ();
			dialog.destroy ();
		}

		void handle_error (ErrorInfos error) {
			if (error.message != "") {
				reset_progress_box ("");
				display_error (error.message, error.details);
			}
			finish_transaction ();
		}

		void finish_transaction () {
			disconnecting_dbus_signals ();
			transaction_summary.remove_all ();
			reset_progress_box ("");
			finished (success);
			success = false;
		}

		void on_refresh_finished (bool success) {
			stop_progressbar_pulse ();
			this.success = success;
			if (success) {
				finished (success);
				reset_progress_box ("");
				success = false;
			} else {
				handle_error (get_current_error ());
			}
			previous_filename = "";
			disconnecting_dbus_signals ();
			system_daemon.refresh_finished.disconnect (on_refresh_finished);
		}

		void on_trans_prepare_finished (bool success) {
			stop_progressbar_pulse ();
			this.success = success;
			if (success) {
				show_warnings ();
				Type type = set_transaction_sum ();
				if (mode != Mode.INSTALLER && (no_confirm_commit || type == Type.UPDATE)) {
					// no_confirm_commit or only updates
					to_install.remove_all ();
					start_commit ();
				} else if (type != 0) {
					if (transaction_sum_dialog.run () == Gtk.ResponseType.OK) {
						transaction_sum_dialog.hide ();
						while (Gtk.events_pending ()) {
							Gtk.main_iteration ();
						}
						if (type == Type.BUILD) {
							// there only AUR packages to build
							release ();
							on_trans_commit_finished (true);
						} else {
							// backup to_install and to_remove
							foreach (unowned string name in to_install) {
								previous_to_install.add (name);
							}
							foreach (unowned string name in to_remove) {
								previous_to_remove.add (name);
							}
							to_install.remove_all ();
							to_remove.remove_all ();
							start_commit ();
						}
					} else {
						transaction_sum_dialog.hide ();
						unowned string action = dgettext (null, "Transaction cancelled");
						show_in_term (action + ".\n");
						progress_box.action_label.label = action;
						release ();
						transaction_summary.remove_all ();
						to_build_queue.clear ();
						sysupgrade_after_trans = false;
						success = false;
						finish_transaction ();
					}
				} else if (build_after_sysupgrade) {
					// there only AUR packages to build
					release ();
					on_trans_commit_finished (true);
				} else {
					//var err = ErrorInfos ();
					//err.message = dgettext (null, "Nothing to do") + "\n";
					show_in_term (dgettext (null, "Nothing to do") + ".\n");
					release ();
					clear_lists ();
					finish_transaction ();
					//handle_error (err);
				}
			} else {
				to_load.remove_all ();
				warning_textbuffer = new StringBuilder ();
				handle_error (get_current_error ());
			}
		}

		void on_trans_commit_finished (bool success) {
			this.success = success;
			// needed before build_aur_packages and remove_makedeps
			no_confirm_commit = false;
			if (success) {
				show_warnings ();
				to_load.remove_all ();
				if (to_build_queue.get_length () != 0) {
					show_in_term ("");
					clear_previous_lists ();
					check_authorization.begin ((obj, res) => {
						bool authorized = check_authorization.end (res);
						if (authorized) {
							build_aur_packages.begin ();
						} else {
							to_build_queue.clear ();
							on_trans_commit_finished (false);
						}
					});
				} else {
					clear_previous_lists ();
					if (sysupgrade_after_trans) {
						sysupgrade_after_trans = false;
						sysupgrade (false);
					} else if (build_after_sysupgrade) {
						build_after_sysupgrade = false;
						disconnecting_dbus_signals ();
						// build aur updates in to_build
						run ();
					} else {
						unowned string action = dgettext (null, "Transaction successfully finished");
						show_in_term (action + ".\n");
						progress_box.action_label.label = action;
						finish_transaction ();
					}
				}
			} else {
				// if it is an authentication or a download error, database was not modified
				var err = get_current_error ();
				if (err.message == dgettext (null, "Authentication failed")
					|| err.errno == 54) { //Alpm.Errno.EXTERNAL_DOWNLOAD
					// recover old pkgnames
					foreach (unowned string name in previous_to_install) {
						to_install.add (name);
					}
					foreach (unowned string name in previous_to_remove) {
						to_remove.add (name);
					}
				} else {
					to_load.remove_all ();
				}
				clear_previous_lists ();
				to_build_queue.clear ();
				warning_textbuffer = new StringBuilder ();
				handle_error (err);
			}
			total_download = 0;
			already_downloaded = 0;
			previous_filename = "";
		}

		void on_set_pkgreason_finished () {
			system_daemon.set_pkgreason_finished.disconnect (on_set_pkgreason_finished);
			set_pkgreason_finished ();
		}

		void on_write_pamac_config_finished (bool recurse, uint64 refresh_period, bool no_update_hide_icon,
												bool enable_aur, bool search_aur, bool check_aur_updates) {
			system_daemon.write_pamac_config_finished.disconnect (on_write_pamac_config_finished);
			pamac_config.reload ();
			flags = (1 << 4); //Alpm.TransFlag.CASCADE
			if (pamac_config.recurse) {
				flags |= (1 << 5); //Alpm.TransFlag.RECURSE
			}
			write_pamac_config_finished (recurse, refresh_period, no_update_hide_icon,
											enable_aur, search_aur, check_aur_updates);
		}

		void on_write_alpm_config_finished (bool checkspace) {
			system_daemon.write_alpm_config_finished.disconnect (on_write_alpm_config_finished);
			write_alpm_config_finished (checkspace);
		}

		void on_write_mirrors_config_finished (string choosen_country, string choosen_generation_method) {
			system_daemon.write_mirrors_config_finished.disconnect (on_write_mirrors_config_finished);
			write_mirrors_config_finished (choosen_country, choosen_generation_method);
		}

		void on_generate_mirrors_list_data (string line) {
			show_in_term (line);
		}

		void on_generate_mirrors_list_finished () {
			refresh_handle ();
			system_daemon.generate_mirrors_list_data.disconnect (on_generate_mirrors_list_data);
			system_daemon.generate_mirrors_list_finished.disconnect (on_generate_mirrors_list_finished);
			reset_progress_box ("");
		}

		void connecting_user_daemon () {
			try {
				user_daemon = Bus.get_proxy_sync (BusType.SESSION, "org.manjaro.pamac.user", "/org/manjaro/pamac/user");
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		void connecting_system_daemon () {
			try {
				system_daemon = Bus.get_proxy_sync (BusType.SYSTEM, "org.manjaro.pamac.system", "/org/manjaro/pamac/system");
				// Set environment variables
				system_daemon.set_environment_variables (pamac_config.environment_variables);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		void connecting_dbus_signals () {
			system_daemon.emit_event.connect (on_emit_event);
			system_daemon.emit_providers.connect (on_emit_providers);
			system_daemon.emit_progress.connect (on_emit_progress);
			system_daemon.emit_download.connect (on_emit_download);
			system_daemon.emit_totaldownload.connect (on_emit_totaldownload);
			system_daemon.emit_log.connect (on_emit_log);
			system_daemon.trans_prepare_finished.connect (on_trans_prepare_finished);
			system_daemon.trans_commit_finished.connect (on_trans_commit_finished);
		}

		void disconnecting_dbus_signals () {
			system_daemon.emit_event.disconnect (on_emit_event);
			system_daemon.emit_providers.disconnect (on_emit_providers);
			system_daemon.emit_progress.disconnect (on_emit_progress);
			system_daemon.emit_download.disconnect (on_emit_download);
			system_daemon.emit_totaldownload.disconnect (on_emit_totaldownload);
			system_daemon.emit_log.disconnect (on_emit_log);
			system_daemon.trans_prepare_finished.disconnect (on_trans_prepare_finished);
			system_daemon.trans_commit_finished.disconnect (on_trans_commit_finished);
		}
	}
}
