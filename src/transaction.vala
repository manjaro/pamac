/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2016 Guillaume Benoit <guillaume@manjaro.org>
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
	[DBus (name = "org.manjaro.pamac")]
	interface Daemon : Object {
		public abstract void set_environment_variables (HashTable<string,string> variables) throws IOError;
		public abstract ErrorInfos get_current_error () throws IOError;
		public abstract void start_get_authorization () throws IOError;
		public abstract void start_write_pamac_config (HashTable<string,Variant> new_pamac_conf) throws IOError;
		public abstract void start_write_alpm_config (HashTable<string,Variant> new_alpm_conf) throws IOError;
		public abstract void start_write_mirrors_config (HashTable<string,Variant> new_mirrors_conf) throws IOError;
		public abstract void start_generate_mirrors_list () throws IOError;
		public abstract void start_set_pkgreason (string pkgname, uint reason) throws IOError;
		public abstract PackageInfos get_installed_pkg (string pkgname) throws IOError;
		public abstract void start_refresh (bool force) throws IOError;
		public abstract void add_ignorepkg (string pkgname) throws IOError;
		public abstract void remove_ignorepkg (string pkgname) throws IOError;
		public abstract void start_get_updates (bool check_aur_updates) throws IOError;
		public abstract bool trans_init (Alpm.TransFlag transflags) throws IOError;
		public abstract bool trans_sysupgrade (bool enable_downgrade) throws IOError;
		public abstract bool trans_add_pkg (string pkgname) throws IOError;
		public abstract bool trans_remove_pkg (string pkgname) throws IOError;
		public abstract bool trans_load_pkg (string pkgpath) throws IOError;
		public abstract void start_trans_prepare () throws IOError;
		public abstract void choose_provider (int provider) throws IOError;
		public abstract PackageInfos[] trans_to_add () throws IOError;
		public abstract PackageInfos[] trans_to_remove () throws IOError;
		public abstract void start_trans_commit () throws IOError;
		public abstract void trans_release () throws IOError;
		[DBus (no_reply = true)]
		public abstract void trans_cancel () throws IOError;
		[DBus (no_reply = true)]
		public abstract void quit () throws IOError;
		public signal void emit_event (uint primary_event, uint secondary_event, string[] details);
		public signal void emit_providers (string depend, string[] providers);
		public signal void emit_progress (uint progress, string pkgname, uint percent, uint n_targets, uint current_target);
		public signal void emit_download (string filename, uint64 xfered, uint64 total);
		public signal void emit_totaldownload (uint64 total);
		public signal void emit_log (uint level, string msg);
		public signal void set_pkgreason_finished ();
		public signal void refresh_finished (bool success);
		public signal void get_updates_finished (Updates updates);
		public signal void trans_prepare_finished (bool success);
		public signal void trans_commit_finished (bool success);
		public signal void get_authorization_finished (bool authorized);
		public signal void write_pamac_config_finished (bool recurse, uint64 refresh_period, bool no_update_hide_icon,
														bool enable_aur, bool search_aur, bool check_aur_updates,
														bool no_confirm_build);
		public signal void write_alpm_config_finished (bool checkspace);
		public signal void write_mirrors_config_finished (string choosen_country, string choosen_generation_method);
		public signal void generate_mirrors_list_data (string line);
		public signal void generate_mirrors_list_finished ();
	}

	public enum Mode {
		MANAGER,
		UPDATER
	}

	public class Transaction: Object {

		enum Type {
			STANDARD = (1 << 0),
			UPDATE = (1 << 1),
			BUILD = (1 << 2)
		}

		Daemon daemon;

		public AlpmUtils alpm_utils;
		public Pamac.Config pamac_config;

		public Alpm.TransFlag flags;

		public GenericSet<string?> to_add;
		public GenericSet<string?> to_remove;
		public GenericSet<string?> to_load;
		public GenericSet<string?> to_build;
		public GenericSet<string?> temporary_ignorepkgs;

		HashTable<string,Json.Object> aur_infos;

		public Mode mode;

		uint64 total_download;
		uint64 already_downloaded;
		string previous_label;
		string previous_textbar;
		float previous_percent;
		string previous_filename;
		uint pulse_timeout_id;
		bool sysupgrade_after_trans;
		bool enable_downgrade;
		uint64 previous_xfered;
		uint64 download_rate;
		uint64 rates_nb;
		Timer timer;
		bool database_modified;
		bool success;

		//dialogs
		TransactionSumDialog transaction_sum_dialog;
		TransactionInfoDialog transaction_info_dialog;
		ProgressDialog progress_dialog;
		//parent window
		public Gtk.ApplicationWindow? application_window;

		public signal void finished (bool success);
		public signal void set_pkgreason_finished ();
		public signal void get_updates_finished (Updates updates);
		public signal void write_pamac_config_finished (bool recurse, uint64 refresh_period, bool no_update_hide_icon,
														bool enable_aur, bool search_aur, bool check_aur_updates,
														bool no_confirm_build);
		public signal void write_alpm_config_finished (bool checkspace);
		public signal void write_mirrors_config_finished (string choosen_country, string choosen_generation_method);

		public Transaction (Gtk.ApplicationWindow? application_window) {
			alpm_utils = new AlpmUtils ("/etc/pacman.conf");
			pamac_config = new Pamac.Config ("/etc/pamac.conf");
			flags = Alpm.TransFlag.CASCADE;
			if (pamac_config.recurse) {
				flags |= Alpm.TransFlag.RECURSE;
			}
			
			to_add = new GenericSet<string?> (str_hash, str_equal);
			to_remove = new GenericSet<string?> (str_hash, str_equal);
			to_load = new GenericSet<string?> (str_hash, str_equal);
			to_build = new GenericSet<string?> (str_hash, str_equal);
			temporary_ignorepkgs = new GenericSet<string?> (str_hash, str_equal);
			aur_infos = new HashTable<string,Json.Object> (str_hash, str_equal);
			connecting_dbus_signals ();
			//creating dialogs
			this.application_window = application_window;
			transaction_sum_dialog = new TransactionSumDialog (application_window);
			transaction_info_dialog = new TransactionInfoDialog (application_window);
			progress_dialog = new ProgressDialog (application_window);
			progress_dialog.close_button.clicked.connect (on_progress_dialog_close_button_clicked);
			progress_dialog.cancel_button.clicked.connect (on_progress_dialog_cancel_button_clicked);
			// connect to child_exited signal which will only be emit after a call to watch_child
			progress_dialog.term.child_exited.connect (on_term_child_exited);
			// progress data
			previous_label = "";
			previous_textbar = "";
			previous_filename = "";
			sysupgrade_after_trans = false;
			timer = new Timer ();
			database_modified = false;
			success = false;
		}

		public async void run_preferences_dialog () {
			SourceFunc callback = run_preferences_dialog.callback;
			ulong handler_id = daemon.get_authorization_finished.connect ((authorized) => {
				if (authorized) {
					var preferences_dialog = new PreferencesDialog (this);
					preferences_dialog.run ();
					preferences_dialog.destroy ();
					while (Gtk.events_pending ()) {
						Gtk.main_iteration ();
					}
				}
				Idle.add((owned) callback);
			});
			start_get_authorization ();
			yield;
			daemon.disconnect (handler_id);
		}

		public ErrorInfos get_current_error () {
			try {
				return daemon.get_current_error ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				return ErrorInfos ();
			}
		}

		public void start_get_authorization () {
			try {
				daemon.start_get_authorization ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void start_write_pamac_config (HashTable<string,Variant> new_pamac_conf) {
			try {
				daemon.start_write_pamac_config (new_pamac_conf);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void start_write_alpm_config (HashTable<string,Variant> new_alpm_conf) {
			try {
				daemon.start_write_alpm_config (new_alpm_conf);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void start_write_mirrors_config (HashTable<string,Variant> new_mirrors_conf) {
			try {
				daemon.start_write_mirrors_config (new_mirrors_conf);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void start_generate_mirrors_list () {
			string action = dgettext (null, "Refreshing mirrors list") + "...";
			progress_dialog.spawn_in_term ({"echo", action});
			progress_dialog.action_label.set_text (action);
			progress_dialog.progressbar.set_fraction (0);
			progress_dialog.progressbar.set_text ("");
			progress_dialog.cancel_button.set_visible (false);
			progress_dialog.close_button.set_visible (false);
			progress_dialog.expander.set_expanded (true);
			progress_dialog.width_request = 700;
			pulse_timeout_id = Timeout.add (500, (GLib.SourceFunc) progress_dialog.progressbar.pulse);
			progress_dialog.show ();
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
			try {
				daemon.start_generate_mirrors_list ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				Source.remove (pulse_timeout_id);
			}
		}

		public void start_set_pkgreason (string pkgname, Alpm.Package.Reason reason) {
			try {
				daemon.start_set_pkgreason (pkgname, (uint) reason);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void start_refresh (bool force) {
			string action = dgettext (null, "Synchronizing package databases") + "...";
			progress_dialog.spawn_in_term ({"echo", action});
			progress_dialog.action_label.set_text (action);
			progress_dialog.progressbar.set_fraction (0);
			progress_dialog.progressbar.set_text ("");
			progress_dialog.cancel_button.set_visible (true);
			progress_dialog.close_button.set_visible (false);
			progress_dialog.show ();
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
			try {
				daemon.refresh_finished.connect (on_refresh_finished);
				daemon.start_refresh (force);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				daemon.refresh_finished.disconnect (on_refresh_finished);
				database_modified = true;
				success = false;
				finish_transaction ();
			}
		}

		public void start_get_updates () {
			daemon.get_updates_finished.connect (on_get_updates_finished);
			try {
				daemon.start_get_updates (pamac_config.enable_aur && pamac_config.check_aur_updates);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				success = false;
				finish_transaction ();
			}
		}

		void start_get_updates_for_sysupgrade () {
			daemon.get_updates_finished.connect (on_get_updates_for_sysupgrade_finished);
			try {
				daemon.start_get_updates (pamac_config.enable_aur && pamac_config.check_aur_updates);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				success = false;
				finish_transaction ();
			}
		}

		public void add_ignorepkg (string pkgname) {
			try {
				daemon.add_ignorepkg (pkgname);
				//temporary_ignorepkgs.add (pkgname);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void remove_ignorepkg (string pkgname) {
			try {
				daemon.remove_ignorepkg (pkgname);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public bool init (Alpm.TransFlag flags) {
			foreach (unowned string pkgname in temporary_ignorepkgs) {
				add_ignorepkg (pkgname);
			}
			try {
				return daemon.trans_init (flags);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				return false;
			}
		}

		void sysupgrade_simple (bool enable_downgrade) {
			progress_dialog.progressbar.set_fraction (0);
			progress_dialog.cancel_button.set_visible (true);
			success = init (0);
			if (success) {
				try {
					success = daemon.trans_sysupgrade (enable_downgrade);
				} catch (IOError e) {
					stderr.printf ("IOError: %s\n", e.message);
					success = false;
				}
				if (success) {
					progress_dialog.show ();
					while (Gtk.events_pending ()) {
						Gtk.main_iteration ();
					}
					try {
						daemon.start_trans_prepare ();
					} catch (IOError e) {
						stderr.printf ("IOError: %s\n", e.message);
						release ();
						success = false;
						finish_transaction ();
					}
				} else {
					release ();
					handle_error (get_current_error ());
				}
			} else {
				handle_error (get_current_error ());
			}
		}

		public void sysupgrade (bool enable_downgrade) {
			this.enable_downgrade = enable_downgrade;
			string action = dgettext (null, "Starting full system upgrade") + "...";
			progress_dialog.spawn_in_term ({"echo", action});
			progress_dialog.action_label.set_text (action);
			progress_dialog.progressbar.set_fraction (0);
			progress_dialog.progressbar.set_text ("");
			progress_dialog.cancel_button.set_visible (true);
			progress_dialog.close_button.set_visible (false);
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
			start_get_updates_for_sysupgrade ();
		}

		void on_get_updates_finished (Updates updates) {
			daemon.get_updates_finished.disconnect (on_get_updates_finished);
			get_updates_finished (updates);
		}

		void on_get_updates_for_sysupgrade_finished (Updates updates) {
			daemon.get_updates_finished.disconnect (on_get_updates_for_sysupgrade_finished);
			// get syncfirst updates
			if (updates.is_syncfirst) {
				clear_lists ();
				if (mode == Mode.MANAGER) {
					sysupgrade_after_trans = true;
				}
				foreach (unowned PackageInfos infos in updates.repos_updates) {
					to_add.add (infos.name);
				}
				// run as a standard transaction
				run ();
			} else {
				if (updates.aur_updates.length != 0) {
					clear_lists ();
					foreach (unowned PackageInfos infos in updates.aur_updates) {
						if (!(infos.name in temporary_ignorepkgs)) {
							to_build.add (infos.name);
						}
					}
				}
				if (updates.repos_updates.length != 0) {
					sysupgrade_simple (enable_downgrade);
				} else {
					progress_dialog.show ();
					while (Gtk.events_pending ()) {
						Gtk.main_iteration ();
					}
					on_trans_prepare_finished (true);
				}
			}
		}

		public void clear_lists () {
			to_add.remove_all ();
			to_remove.remove_all ();
			to_build.remove_all ();
		}

		public void run () {
			string action = dgettext (null, "Preparing") + "...";
			progress_dialog.spawn_in_term ({"echo", action});
			progress_dialog.action_label.set_text (action);
			progress_dialog.progressbar.set_fraction (0);
			progress_dialog.progressbar.set_text ("");
			progress_dialog.cancel_button.set_visible (true);
			progress_dialog.close_button.set_visible (false);
			progress_dialog.show ();
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
			// run
			if (to_add.length == 0
					&& to_remove.length == 0
					&& to_load.length == 0
					&& to_build.length != 0) {
				// there only AUR packages to build so no need to prepare transaction
				on_trans_prepare_finished (true);
			} else {
				success = false;
				try {
					success = daemon.trans_init (flags);
				} catch (IOError e) {
					stderr.printf ("IOError: %s\n", e.message);
				}
				if (success) {
					success = false;
					foreach (unowned string name in to_add) {
						try {
							success = daemon.trans_add_pkg (name);
						} catch (IOError e) {
							stderr.printf ("IOError: %s\n", e.message);
						}
						if (!success) {
							break;
						}
					}
					foreach (unowned string name in to_remove) {
						try {
							success = daemon.trans_remove_pkg (name);
						} catch (IOError e) {
							stderr.printf ("IOError: %s\n", e.message);
						}
						if (!success) {
							break;
						}
					}
					foreach (unowned string path in to_load) {
						try {
							success = daemon.trans_load_pkg (path);
						} catch (IOError e) {
							stderr.printf ("IOError: %s\n", e.message);
						}
						if (!success) {
							break;
						}
					}
					if (success) {
						try {
							daemon.start_trans_prepare ();
						} catch (IOError e) {
							stderr.printf ("IOError: %s\n", e.message);
							release ();
							success = false;
							finish_transaction ();
						}
					} else {
						release ();
						handle_error (get_current_error ());
					}
				} else {
					handle_error (get_current_error ());
				}
			}
		}

		void choose_provider (string depend, string[] providers) {
			var choose_provider_dialog = new ChooseProviderDialog (application_window);
			choose_provider_dialog.label.set_markup ("<b>%s</b>".printf (dgettext (null, "Choose a provider for %s").printf (depend)));
			foreach (unowned string provider in providers) {
				choose_provider_dialog.comboboxtext.append_text (provider);
			}
			choose_provider_dialog.comboboxtext.active = 0;
			choose_provider_dialog.run ();
			try {
				daemon.choose_provider (choose_provider_dialog.comboboxtext.active);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
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
			PackageInfos[] prepared_to_add = {};
			PackageInfos[] prepared_to_remove = {};
			string[] to_downgrade = {};
			string[] to_install = {};
			string[] to_reinstall = {};
			string[] to_update = {};
			string[] _to_build = {};
			Gtk.TreeIter iter;
			transaction_sum_dialog.top_label.set_markup ("<big><b>%s</b></big>".printf (dgettext (null, "Transaction Summary")));
			transaction_sum_dialog.sum_list.clear ();
			try {
				prepared_to_add = daemon.trans_to_add ();
				prepared_to_remove = daemon.trans_to_remove ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			foreach (unowned PackageInfos pkg_info in prepared_to_add) {
				dsize += pkg_info.download_size;
				try {
					PackageInfos local_pkg_info = daemon.get_installed_pkg (pkg_info.name);
					if (local_pkg_info.name == "") {
						to_install += "%s %s".printf (pkg_info.name, pkg_info.version);
					} else {
						int cmp = Alpm.pkg_vercmp (pkg_info.version, local_pkg_info.version);
						if (cmp == 1) {
							to_update += "%s %s".printf (pkg_info.name, pkg_info.version);
						} else if (cmp == 0) {
							to_reinstall += "%s %s".printf (pkg_info.name, pkg_info.version);
						} else {
							to_downgrade += "%s %s".printf (pkg_info.name, pkg_info.version);
						}
					}
				} catch (IOError e) {
					stderr.printf ("IOError: %s\n", e.message);
				}
			}
			foreach (unowned string name in to_build) {
				_to_build += name;
			}
			int len = prepared_to_remove.length;
			int i;
			if (len != 0) {
				type |= Type.STANDARD;
				transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												0, dgettext (null, "To remove") + ":",
												1, "%s %s".printf (prepared_to_remove[0].name, prepared_to_remove[0].version));
				i = 1;
				while (i < len) {
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, "%s %s".printf (prepared_to_remove[i].name, prepared_to_remove[i].version));
					i++;
				}
			}
			len = to_downgrade.length;
			if (len != 0) {
				type |= Type.STANDARD;
				transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												0, dgettext (null, "To downgrade") + ":",
												1, to_downgrade[0]);
				i = 1;
				while (i < len) {
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, to_downgrade[i]);
					i++;
				}
			}
			len = _to_build.length;
			if (len != 0) {
				type |= Type.BUILD;
				transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												0, dgettext (null, "To build") + ":",
												1, _to_build[0]);
				i = 1;
				while (i < len) {
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, _to_build[i]);
					i++;
				}
			}
			len = to_install.length;
			if (len != 0) {
				type |= Type.STANDARD;
				transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												0, dgettext (null, "To install") + ":",
												1, to_install[0]);
				i = 1;
				while (i < len) {
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, to_install[i]);
					i++;
				}
			}
			len = to_reinstall.length;
			if (len != 0) {
				type |= Type.STANDARD;
				transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												0, dgettext (null, "To reinstall") + ":",
												1, to_reinstall[0]);
				i = 1;
				while (i < len) {
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, to_reinstall[i]);
					i++;
				}
			}
			len = to_update.length;
			if (len != 0) {
				type |= Type.UPDATE;
				if (mode != Mode.UPDATER) {
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
													0, dgettext (null, "To update") + ":",
													1, to_update[0]);
					i = 1;
					while (i < len) {
						transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
													1, to_update[i]);
						i++;
					}
				}
			}
			if (dsize == 0) {
				transaction_sum_dialog.bottom_label.set_visible (false);
			} else {
				transaction_sum_dialog.bottom_label.set_markup ("<b>%s: %s</b>".printf (dgettext (null, "Total download size"), format_size (dsize)));
				transaction_sum_dialog.bottom_label.set_visible (true);
			}
			return type;
		}

		public void start_commit () {
			progress_dialog.cancel_button.set_visible (false);
			try {
				daemon.start_trans_commit ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
				database_modified = true;
				success = false;
				finish_transaction ();
			}
		}

		public void build_aur_packages () {
			string action = dgettext (null, "Building packages") + "...";
			progress_dialog.spawn_in_term ({"echo", action});
			progress_dialog.action_label.set_text (action);
			progress_dialog.progressbar.set_fraction (0);
			progress_dialog.progressbar.set_text ("");
			progress_dialog.cancel_button.set_visible (false);
			progress_dialog.close_button.set_visible (false);
			progress_dialog.expander.set_expanded (true);
			progress_dialog.width_request = 700;
			progress_dialog.term.grab_focus ();
			pulse_timeout_id = Timeout.add (500, (GLib.SourceFunc) progress_dialog.progressbar.pulse);
			string[] cmds = {"yaourt", "-S"};
			if (pamac_config.no_confirm_build) {
				cmds += "--noconfirm";
			}
			foreach (unowned string name in to_build) {
				cmds += name;
			}
			Pid child_pid;
			progress_dialog.spawn_in_term (cmds, out child_pid);
			// watch_child is needed in order to have the child_exited signal emitted
			progress_dialog.term.watch_child (child_pid);
		}

		public async Json.Object get_aur_infos (string aur_name) {
			if (!aur_infos.contains (aur_name)) {
				Json.Array results = AUR.multiinfo ({aur_name});
				aur_infos.insert (aur_name, results.get_object_element (0));
			}
			return aur_infos.lookup (aur_name);
		}

		public void cancel () {
			try {
				daemon.trans_cancel ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			progress_dialog.expander.set_expanded (false);
			Gtk.TextIter start_iter;
			Gtk.TextIter end_iter;
			transaction_info_dialog.textbuffer.get_start_iter (out start_iter);
			transaction_info_dialog.textbuffer.get_end_iter (out end_iter);
			transaction_info_dialog.textbuffer.delete (ref start_iter, ref end_iter);
		}

		public void release () {
			try {
				daemon.trans_release ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			foreach (unowned string pkgname in temporary_ignorepkgs) {
				remove_ignorepkg (pkgname);
			}
		}

		public void stop_daemon () {
			try {
				daemon.quit ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		void on_emit_event (uint primary_event, uint secondary_event, string[] details) {
			string msg;
			switch (primary_event) {
				case Alpm.Event.Type.HOOK_START:
					switch (secondary_event) {
						case Alpm.HookWhen.PRE_TRANSACTION:
							msg = dgettext (null, "Running pre-transaction hooks") + "...";
							progress_dialog.action_label.set_text (msg);
							progress_dialog.spawn_in_term ({"echo", msg});
							break;
						case Alpm.HookWhen.POST_TRANSACTION:
							msg = dgettext (null, "Running post-transaction hooks") + "...";
							progress_dialog.action_label.set_text (msg);
							progress_dialog.spawn_in_term ({"echo", msg});
							break;
						default:
							break;
					}
					break;
				case Alpm.Event.Type.HOOK_RUN_START:
					string textbar = "%s/%s".printf (details[2], details[3]);
					if (textbar != previous_textbar) {
						previous_textbar = textbar;
						progress_dialog.progressbar.set_text (textbar);
					}
					float fraction = (float) int.parse (details[2]) / int.parse (details[3]);
					if (fraction != previous_percent) {
						previous_percent = fraction;
						progress_dialog.progressbar.set_fraction (fraction);
					}
					if (details[1] != "") {
						msg = details[1] + ":";
					} else {
						msg = details[0] + ":";
					}
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.CHECKDEPS_START:
					msg = dgettext (null, "Checking dependencies") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.FILECONFLICTS_START:
					msg = dgettext (null, "Checking file conflicts") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.RESOLVEDEPS_START:
					msg = dgettext (null, "Resolving dependencies") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.INTERCONFLICTS_START:
					msg = dgettext (null, "Checking inter-conflicts") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.TRANSACTION_START:
					progress_dialog.cancel_button.set_visible (false);
					break;
				case Alpm.Event.Type.PACKAGE_OPERATION_START:
					switch (secondary_event) {
						case Alpm.Package.Operation.INSTALL:
							previous_filename = details[0];
							msg = dgettext (null, "Installing %s").printf (details[0]) + "...";
							progress_dialog.action_label.set_text (msg);
							msg = dgettext (null, "Installing %s").printf ("%s (%s)".printf (details[0], details[1]))+ "...";
							progress_dialog.spawn_in_term ({"echo", msg});
							break;
						case Alpm.Package.Operation.REINSTALL:
							previous_filename = details[0];
							msg = dgettext (null, "Reinstalling %s").printf (details[0]) + "...";
							progress_dialog.action_label.set_text (msg);
							msg = dgettext (null, "Reinstalling %s").printf ("%s (%s)".printf (details[0], details[1]))+ "...";
							progress_dialog.spawn_in_term ({"echo", msg});
							break;
						case Alpm.Package.Operation.REMOVE:
							previous_filename = details[0];
							msg = dgettext (null, "Removing %s").printf (details[0]) + "...";
							progress_dialog.action_label.set_text (msg);
							msg = dgettext (null, "Removing %s").printf ("%s (%s)".printf (details[0], details[1]))+ "...";
							progress_dialog.spawn_in_term ({"echo", msg});
							break;
						case Alpm.Package.Operation.UPGRADE:
							previous_filename = details[0];
							msg = dgettext (null, "Upgrading %s").printf (details[0]) + "...";
							progress_dialog.action_label.set_text (msg);
							msg = dgettext (null, "Upgrading %s").printf ("%s (%s -> %s)".printf (details[0], details[1], details[2]))+ "...";
							progress_dialog.spawn_in_term ({"echo", msg});
							break;
						case Alpm.Package.Operation.DOWNGRADE:
							previous_filename = details[0];
							msg = dgettext (null, "Downgrading %s").printf (details[0]) + "...";
							progress_dialog.action_label.set_text (msg);
							msg = dgettext (null, "Downgrading %s").printf ("%s (%s -> %s)".printf (details[0], details[1], details[2]))+ "...";
							progress_dialog.spawn_in_term ({"echo", msg});
							break;
					}
					break;
				case Alpm.Event.Type.INTEGRITY_START:
					msg = dgettext (null, "Checking integrity") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.KEYRING_START:
					progress_dialog.cancel_button.set_visible (true);
					msg = dgettext (null, "Checking keyring") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.KEY_DOWNLOAD_START:
					msg = dgettext (null, "Downloading required keys") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.LOAD_START:
					msg = dgettext (null, "Loading packages files") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.DELTA_INTEGRITY_START:
					msg = dgettext (null, "Checking delta integrity") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.DELTA_PATCHES_START:
					msg = dgettext (null, "Applying deltas") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.DELTA_PATCH_START:
					msg = dgettext (null, "Generating %s with %s").printf (details[0], details[1]) + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.DELTA_PATCH_DONE:
					msg = dgettext (null, "Generation succeeded") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.DELTA_PATCH_FAILED:
					msg = dgettext (null, "Generation failed") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.SCRIPTLET_INFO:
					progress_dialog.action_label.set_text (dgettext (null, "Configuring %s").printf (previous_filename) + "...");
					progress_dialog.expander.set_expanded (true);
					progress_dialog.spawn_in_term ({"echo", "-n", details[0]});
					break;
				case Alpm.Event.Type.RETRIEVE_START:
					progress_dialog.cancel_button.set_visible (true);
					msg = dgettext (null, "Downloading") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.DISKSPACE_START:
					msg = dgettext (null, "Checking available disk space") + "...";
					progress_dialog.action_label.set_text (msg);
					progress_dialog.spawn_in_term ({"echo", msg});
					break;
				case Alpm.Event.Type.OPTDEP_REMOVAL:
					msg = dgettext (null, "%s optionally requires %s").printf (details[0], details[1]);
					progress_dialog.spawn_in_term ({"echo", msg});
					Gtk.TextIter end_iter;
					msg += "\n";
					transaction_info_dialog.textbuffer.get_end_iter (out end_iter);
					transaction_info_dialog.textbuffer.insert (ref end_iter, msg, msg.length);
					break;
				case Alpm.Event.Type.DATABASE_MISSING:
					progress_dialog.spawn_in_term ({"echo", dgettext (null, "Database file for %s does not exist").printf (details[0])});
					break;
				case Alpm.Event.Type.PACNEW_CREATED:
					progress_dialog.spawn_in_term ({"echo", dgettext (null, "%s installed as %s.pacnew").printf (details[0])});
					break;
				case Alpm.Event.Type.PACSAVE_CREATED:
					progress_dialog.spawn_in_term ({"echo", dgettext (null, "%s installed as %s.pacsave").printf (details[0])});
					break;
				default:
					break;
			}
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
		}

		void on_emit_providers (string depend, string[] providers) {
			choose_provider (depend, providers);
		}

		void on_emit_progress (uint progress, string pkgname, uint percent, uint n_targets, uint current_target) {
			float fraction;
			switch (progress) {
				case Alpm.Progress.ADD_START:
				case Alpm.Progress.UPGRADE_START:
				case Alpm.Progress.DOWNGRADE_START:
				case Alpm.Progress.REINSTALL_START:
				case Alpm.Progress.REMOVE_START:
					fraction = ((float) (current_target - 1) / n_targets) + ((float) percent / (100 * n_targets));
					break;
				case Alpm.Progress.CONFLICTS_START:
				case Alpm.Progress.DISKSPACE_START:
				case Alpm.Progress.INTEGRITY_START:
				case Alpm.Progress.KEYRING_START:
				case Alpm.Progress.LOAD_START:
				default:
					fraction = (float) percent / 100;
					break;
			}
			string textbar = "%lu/%lu".printf (current_target, n_targets);
			if (textbar != previous_textbar) {
				previous_textbar = textbar;
				progress_dialog.progressbar.set_text (textbar);
			}
			if (fraction != previous_percent) {
				previous_percent = fraction;
				progress_dialog.progressbar.set_fraction (fraction);
			}
//~ 			while (Gtk.events_pending ()) {
//~ 				Gtk.main_iteration ();
//~ 			}
		}

		void on_emit_download (string filename, uint64 xfered, uint64 total) {
			string label;
			var text = new StringBuilder ();
			float fraction;
			if (filename != previous_filename) {
				previous_filename = filename;
				if (filename.has_suffix (".db")) {
					label = dgettext (null, "Refreshing %s").printf (filename.replace (".db", "")) + "...";
				} else {
					label = dgettext (null, "Downloading %s").printf (filename.replace (".pkg.tar.xz", "")) + "...";
				}
				if (label != previous_label) {
					previous_label = label;
					progress_dialog.action_label.set_text (label);
					progress_dialog.spawn_in_term ({"echo", label});
				}
			}
			if (total_download > 0) {
				if (xfered == 0) {
					previous_xfered = 0;
					fraction = previous_percent;
					text.append (previous_textbar);
					timer.start ();
				} else {
					if (timer.elapsed () > 0) {
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
				} else if (xfered == total) {
					timer.stop ();
					fraction = 1;
					previous_filename = "";
				} else {
					if (timer.elapsed () > 0) {
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
				progress_dialog.progressbar.set_fraction (fraction);
			}
			if (text.str != previous_textbar) {
				previous_textbar = text.str;
				progress_dialog.progressbar.set_text (text.str);
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
			}
		}

		void on_emit_log (uint level, string msg) {
			// msg ends with \n
			string? line = null;
			Gtk.TextIter end_iter;
			if ((Alpm.LogLevel) level == Alpm.LogLevel.WARNING) {
				// do not show warning when manjaro-system remove db.lck
				if (previous_filename != "manjaro-system") {
					if (previous_filename != "") {
						line = dgettext (null, "Warning") + ": " + previous_filename + ": " + msg;
					} else {
						line = dgettext (null, "Warning") + ": " + msg;
					}
					transaction_info_dialog.textbuffer.get_end_iter (out end_iter);
					transaction_info_dialog.textbuffer.insert (ref end_iter, msg, msg.length);
				}
			} else if ((Alpm.LogLevel) level == Alpm.LogLevel.ERROR) {
				if (previous_filename != "") {
					line = dgettext (null, "Error") + ": " + previous_filename + ": " + msg;
				} else {
					line = dgettext (null, "Error") + ": " + msg;
				}
			}
			if (line != null) {
				progress_dialog.expander.set_expanded (true);
				progress_dialog.spawn_in_term ({"echo", "-n", line});
			}
		}

		void show_warnings () {
			if (transaction_info_dialog.textbuffer.text != "") {
				transaction_info_dialog.set_title (dgettext (null, "Warning"));
				transaction_info_dialog.label.set_visible (false);
				transaction_info_dialog.expander.set_visible (true);
				transaction_info_dialog.expander.set_expanded (true);
				transaction_info_dialog.run ();
				transaction_info_dialog.hide ();
				while (Gtk.events_pending ()) {
					Gtk.main_iteration ();
				}
				Gtk.TextIter start_iter;
				Gtk.TextIter end_iter;
				transaction_info_dialog.textbuffer.get_start_iter (out start_iter);
				transaction_info_dialog.textbuffer.get_end_iter (out end_iter);
				transaction_info_dialog.textbuffer.delete (ref start_iter, ref end_iter);
			}
		}

		void handle_error (ErrorInfos error) {
			if (error.message != null && error.message != "") {
				progress_dialog.expander.set_expanded (true);
				progress_dialog.spawn_in_term ({"echo", "-n", error.message});
				Gtk.TextIter start_iter;
				Gtk.TextIter end_iter;
				transaction_info_dialog.set_title (dgettext (null, "Error"));
				transaction_info_dialog.label.set_visible (true);
				transaction_info_dialog.label.set_markup (error.message);
				if (error.details.length != 0) {
					transaction_info_dialog.textbuffer.get_start_iter (out start_iter);
					transaction_info_dialog.textbuffer.get_end_iter (out end_iter);
					transaction_info_dialog.textbuffer.delete (ref start_iter, ref end_iter);
					transaction_info_dialog.expander.set_visible (true);
					transaction_info_dialog.expander.set_expanded (true);
					progress_dialog.spawn_in_term ({"echo", ":"});
					foreach (unowned string detail in error.details) {
						progress_dialog.spawn_in_term ({"echo", detail});
						string str = detail + "\n";
						transaction_info_dialog.textbuffer.get_end_iter (out end_iter);
						transaction_info_dialog.textbuffer.insert (ref end_iter, str, str.length);
					}
				} else {
					transaction_info_dialog.expander.set_visible (false);
				}
				progress_dialog.spawn_in_term ({"echo"});
				transaction_info_dialog.run ();
				transaction_info_dialog.hide ();
				transaction_info_dialog.textbuffer.get_start_iter (out start_iter);
				transaction_info_dialog.textbuffer.get_end_iter (out end_iter);
				transaction_info_dialog.textbuffer.delete (ref start_iter, ref end_iter);
				progress_dialog.progressbar.set_fraction (0);
				progress_dialog.spawn_in_term ({"echo"});
				while (Gtk.events_pending ()) {
					Gtk.main_iteration ();
				}
			}
			finish_transaction ();
		}

		void finish_transaction () {
			if (database_modified) {
				alpm_utils.reload ();
				database_modified = false;
			}
			if (progress_dialog.expander.get_expanded ()) {
				progress_dialog.cancel_button.set_visible (false);
				progress_dialog.close_button.set_visible (true);
			} else {
				on_progress_dialog_close_button_clicked ();
			}
		}

		void on_refresh_finished (bool success) {
			database_modified = true;
			this.success = success;
			clear_lists ();
			if (success) {
				finish_transaction ();
			} else {
				handle_error (get_current_error ());
			}
			previous_filename = "";
			daemon.refresh_finished.disconnect (on_refresh_finished);
		}

		void on_progress_dialog_close_button_clicked () {
			finished (success);
			progress_dialog.hide ();
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
			success = false;
		}

		void on_progress_dialog_cancel_button_clicked () {
			cancel ();
			clear_lists ();
			progress_dialog.spawn_in_term ({"/usr/bin/echo", dgettext (null, "Transaction cancelled") + ".\n"});
			progress_dialog.hide ();
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
		}

		void on_trans_prepare_finished (bool success) {
			this.success = success;
			if (success) {
				show_warnings ();
				Type type = set_transaction_sum ();
				if (type == Type.UPDATE && mode == Mode.UPDATER) {
					// there only updates
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
							start_commit ();
						}
					} else {
						transaction_sum_dialog.hide ();
						unowned string action = dgettext (null, "Transaction cancelled");
						progress_dialog.spawn_in_term ({"echo", action + ".\n"});
						progress_dialog.action_label.set_text (action);
						release ();
						//to_build.remove_all ();
						sysupgrade_after_trans = false;
						success = false;
						finish_transaction ();
					}
				} else {
					//var err = ErrorInfos ();
					//err.message = dgettext (null, "Nothing to do") + "\n";
					progress_dialog.spawn_in_term ({"echo", dgettext (null, "Nothing to do") + ".\n"});
					release ();
					clear_lists ();
					finish_transaction ();
					//handle_error (err);
				}
			} else {
				handle_error (get_current_error ());
			}
		}

		void on_trans_commit_finished (bool success) {
			this.success = success;
			if (success) {
				if (to_build.length != 0) {
					if (to_add.length != 0
							|| to_remove.length != 0
							|| to_load.length != 0) {
						progress_dialog.spawn_in_term ({"echo", dgettext (null, "Transaction successfully finished") + ".\n"});
					}
					build_aur_packages ();
				} else {
					clear_lists ();
					show_warnings ();
					if (sysupgrade_after_trans) {
						sysupgrade_after_trans = false;
						sysupgrade (false);
					} else {
						unowned string action = dgettext (null, "Transaction successfully finished");
						progress_dialog.spawn_in_term ({"echo", action + ".\n"});
						progress_dialog.action_label.set_text (action);
						database_modified = true;
						finish_transaction ();
					}
				}
			} else {
				// if it is an authentication error, database was not modified
				var err = get_current_error ();
				if (err.message != dgettext (null, "Authentication failed")) {
					clear_lists ();
					database_modified = true;
				}
				handle_error (err);
			}
			total_download = 0;
			already_downloaded = 0;
			previous_filename = "";
		}

		void on_term_child_exited (int status) {
			Source.remove (pulse_timeout_id);
			clear_lists ();
			// let the time to the daemon to update databases
			Timeout.add (1000, () => {
				if (status == 0) {
					success = true;
					unowned string action = dgettext (null, "Transaction successfully finished");
					progress_dialog.spawn_in_term ({"echo", action + ".\n"});
					progress_dialog.action_label.set_text (action);
				} else {
					success = false;
					progress_dialog.spawn_in_term ({"echo"});
				}
				progress_dialog.progressbar.set_fraction (1);
				alpm_utils.reload ();
				database_modified = false;
				progress_dialog.cancel_button.set_visible (false);
				progress_dialog.close_button.set_visible (true);
				return false;
			});
		}

		void on_set_pkgreason_finished () {
			alpm_utils.reload ();
			set_pkgreason_finished ();
		}

		void on_write_pamac_config_finished (bool recurse, uint64 refresh_period, bool no_update_hide_icon,
												bool enable_aur, bool search_aur, bool check_aur_updates,
												bool no_confirm_build) {
			pamac_config.reload ();
			write_pamac_config_finished (recurse, refresh_period, no_update_hide_icon,
											enable_aur, search_aur, check_aur_updates,
											no_confirm_build);
		}

		void on_write_alpm_config_finished (bool checkspace) {
			alpm_utils.reload ();
			write_alpm_config_finished (checkspace);
		}

		void on_write_mirrors_config_finished (string choosen_country, string choosen_generation_method) {
			write_mirrors_config_finished (choosen_country, choosen_generation_method);
		}

		void on_generate_mirrors_list_data (string line) {
			progress_dialog.spawn_in_term ({"echo", "-n", line});
		}

		void on_generate_mirrors_list_finished () {
			Source.remove (pulse_timeout_id);
			progress_dialog.spawn_in_term ({"echo"});
			// force a dbs refresh
			start_refresh (true);
		}

		void connecting_dbus_signals () {
			try {
				daemon = Bus.get_proxy_sync (BusType.SYSTEM, "org.manjaro.pamac", "/org/manjaro/pamac");
				// Set environment variables
				daemon.set_environment_variables (pamac_config.environment_variables);
				// Connecting to signals
				daemon.emit_event.connect (on_emit_event);
				daemon.emit_providers.connect (on_emit_providers);
				daemon.emit_progress.connect (on_emit_progress);
				daemon.emit_download.connect (on_emit_download);
				daemon.emit_totaldownload.connect (on_emit_totaldownload);
				daemon.emit_log.connect (on_emit_log);
				daemon.trans_prepare_finished.connect (on_trans_prepare_finished);
				daemon.trans_commit_finished.connect (on_trans_commit_finished);
				daemon.set_pkgreason_finished.connect (on_set_pkgreason_finished);
				daemon.write_mirrors_config_finished.connect (on_write_mirrors_config_finished);
				daemon.write_alpm_config_finished.connect (on_write_alpm_config_finished);
				daemon.write_pamac_config_finished.connect (on_write_pamac_config_finished);
				daemon.generate_mirrors_list_data.connect (on_generate_mirrors_list_data);
				daemon.generate_mirrors_list_finished.connect (on_generate_mirrors_list_finished);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}
	}
}
