/*
 *  pamac-vala
 *
 *  Copyright (C) 2014  Guillaume Benoit <guillaume@manjaro.org>
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

using Gtk;
using Vte;
using Alpm;

namespace Pamac {
	[DBus (name = "org.manjaro.pamac")]
	public interface Daemon : Object {
		public abstract void write_config (HashTable<string,string> new_conf) throws IOError;
		public abstract void set_pkgreason (string pkgname, uint reason) throws IOError;
		public abstract void refresh (int force, bool emit_signal) throws IOError;
		public abstract ErrorInfos trans_init (TransFlag transflags) throws IOError;
		public abstract ErrorInfos trans_sysupgrade (int enable_downgrade) throws IOError;
		public abstract ErrorInfos trans_add_pkg (string pkgname) throws IOError;
		public abstract ErrorInfos trans_remove_pkg (string pkgname) throws IOError;
		public abstract ErrorInfos trans_load_pkg (string pkgpath) throws IOError;
		public abstract void trans_prepare () throws IOError;
		public abstract void choose_provider (int provider) throws IOError;
		public abstract UpdatesInfos[] trans_to_add () throws IOError;
		public abstract UpdatesInfos[] trans_to_remove () throws IOError;
		public abstract void trans_commit () throws IOError;
		public abstract void trans_release () throws IOError;
		public abstract void trans_cancel () throws IOError;
		[DBus (no_reply = true)]
		public abstract void quit () throws IOError;
		public signal void emit_event (uint event, string[] details);
		public signal void emit_providers (string depend, string[] providers);
		public signal void emit_progress (uint progress, string pkgname, int percent, uint n_targets, uint current_target);
		public signal void emit_download (string filename, uint64 xfered, uint64 total);
		public signal void emit_totaldownload (uint64 total);
		public signal void emit_log (uint level, string msg);
		public signal void emit_refreshed (ErrorInfos error);
		public signal void emit_trans_prepared (ErrorInfos error);
		public signal void emit_trans_committed (ErrorInfos error);
	}

	public class Transaction: Object {
		public Daemon daemon;

		public string[] syncfirst;
		public string[] holdpkg;
		public string[] ignorepkg;
		public Handle handle;

		public Alpm.TransFlag flags;
		// those hashtables will be used as set
		public HashTable<string, string> to_add;
		public HashTable<string, string> to_remove;
		public HashTable<string, string> to_load;
		public HashTable<string, string> to_build;

		public Mode mode;

		uint64 total_download;
		uint64 already_downloaded;
		string previous_label;
		string previous_textbar;
		double previous_percent;
		string previous_filename;
		uint build_timeout_id;
		bool sysupgrade_after_trans;
		bool sysupgrade_after_build;
		int build_status;
		int enable_downgrade;
		public bool check_aur;
		UpdatesInfos[] aur_updates;
		bool aur_checked;

		Terminal term;
		Pty pty;

		//dialogs
		TransactionSumDialog transaction_sum_dialog;
		TransactionInfoDialog transaction_info_dialog;
		ProgressDialog progress_dialog;
		//parent window
		ApplicationWindow? window;

		public signal void finished (bool error);

		public Transaction (ApplicationWindow? window) {
			refresh_alpm_config ();
			mode = Mode.MANAGER;
			flags = Alpm.TransFlag.CASCADE;
			to_add = new HashTable<string, string> (str_hash, str_equal);
			to_remove = new HashTable<string, string> (str_hash, str_equal);
			to_load = new HashTable<string, string> (str_hash, str_equal);
			to_build = new HashTable<string, string> (str_hash, str_equal);
			connecting_dbus_signals ();
			//creating dialogs
			this.window = window;
			transaction_sum_dialog = new TransactionSumDialog (window);
			transaction_info_dialog = new TransactionInfoDialog (window);
			progress_dialog = new ProgressDialog (this, window);
			//creating terminal
			term = new Terminal ();
			term.scroll_on_output = false;
			term.expand = true;
			term.height_request = 200;
			term.set_visible (true);
			// creating pty for term
			try {
				pty = term.pty_new_sync (PtyFlags.NO_HELPER);
			} catch (Error e) {
				stderr.printf ("Error: %s\n", e.message);
			}
			// connect to child_exited signal which will only be emit after a call to watch_child
			term.child_exited.connect (on_term_child_exited);
			// add term in a grid with a scrollbar
			var grid = new Grid ();
			grid.expand = true;
			grid.set_visible (true);
			var sb = new Scrollbar (Orientation.VERTICAL, term.vadjustment);
			sb.set_visible (true);
			grid.attach (term, 0, 0, 1, 1);
			grid.attach (sb, 1, 0, 1, 1);
			progress_dialog.expander.add (grid);
			// progress data
			total_download = 0;
			already_downloaded = 0;
			previous_label = "";
			previous_textbar = "";
			previous_percent = 0.0;
			previous_filename = "";
			sysupgrade_after_trans = false;
			sysupgrade_after_build = false;
			build_status = 0;
			check_aur = false;
			aur_updates = {};
			aur_checked = false;
		}

		public void write_config (HashTable<string,string> new_conf) {
			try {
				daemon.write_config (new_conf);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void set_pkgreason (string pkgname, PkgReason reason) {
			try {
				daemon.set_pkgreason (pkgname, (uint) reason);
				refresh_alpm_config ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void refresh_alpm_config () {
			var alpm_config = new Alpm.Config ("/etc/pacman.conf");
			syncfirst = alpm_config.get_syncfirst ();
			holdpkg = alpm_config.get_holdpkg ();
			ignorepkg = alpm_config.get_ignore_pkgs ();
			handle = alpm_config.get_handle ();
		}

		public void refresh (int force) {
			string action = dgettext (null, "Synchronizing package databases") + "...";
			spawn_in_term ({"/usr/bin/echo", action});
			progress_dialog.action_label.set_text (action);
			progress_dialog.progressbar.set_fraction (0);
			progress_dialog.progressbar.set_text ("");
			progress_dialog.cancel_button.set_visible (true);
			progress_dialog.close_button.set_visible (false);
			progress_dialog.show ();
			while (Gtk.events_pending ())
				Gtk.main_iteration ();
			try {
				daemon.refresh (force, true);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void sysupgrade_simple (int enable_downgrade) {
			progress_dialog.progressbar.set_fraction (0);
			progress_dialog.cancel_button.set_visible (true);
			ErrorInfos err = ErrorInfos ();
			try {
				err = daemon.trans_init (0);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			if (err.str != "") {
				finished (true);
				handle_error (err);
			} else {
				try {
					err = daemon.trans_sysupgrade (enable_downgrade);
				} catch (IOError e) {
					stderr.printf ("IOError: %s\n", e.message);
				}
				if (err.str == "") {
					progress_dialog.show ();
					while (Gtk.events_pending ())
						Gtk.main_iteration ();
					try {
						daemon.trans_prepare ();
					} catch (IOError e) {
						stderr.printf ("IOError: %s\n", e.message);
					}
				} else {
					release ();
					finished (true);
					handle_error (err);
				}
			}
		}

		public void sysupgrade (int enable_downgrade) {
			this.enable_downgrade = enable_downgrade;
			string action = dgettext (null, "Starting full system upgrade") + "...";
			spawn_in_term ({"/usr/bin/echo", action});
			progress_dialog.action_label.set_text (action);
			progress_dialog.progressbar.set_fraction (0);
			progress_dialog.progressbar.set_text ("");
			progress_dialog.cancel_button.set_visible (true);
			progress_dialog.close_button.set_visible (false);
			while (Gtk.events_pending ())
				Gtk.main_iteration ();
			// sysupgrade
			// get syncfirst updates
			UpdatesInfos[] syncfirst_updates = get_syncfirst_updates (handle, syncfirst);
			if (syncfirst_updates.length != 0) {
				clear_lists ();
				if (mode == Mode.MANAGER)
					sysupgrade_after_trans = true;
				foreach (UpdatesInfos infos in syncfirst_updates)
					to_add.insert (infos.name, infos.name);
				// run as a standard transaction
				run ();
			} else {
				UpdatesInfos[] repos_updates = get_repos_updates (handle, ignorepkg);
				int repos_updates_len = repos_updates.length;
				if (check_aur) {
					if (aur_checked == false) {
						aur_updates = get_aur_updates (handle, ignorepkg);
						aur_checked = true;
					}
					if (aur_updates.length != 0) {
						clear_lists ();
						if (repos_updates_len != 0)
							sysupgrade_after_build = true;
						foreach (UpdatesInfos infos in aur_updates)
							to_build.insert (infos.name, infos.name);
					}
				}
				if (repos_updates_len != 0)
					sysupgrade_simple (enable_downgrade);
				else {
					progress_dialog.show ();
					while (Gtk.events_pending ())
						Gtk.main_iteration ();
					ErrorInfos err = ErrorInfos ();
					on_emit_trans_prepared (err);
				}
			}
		}

		public void clear_lists () {
			to_add.steal_all ();
			to_remove.steal_all ();
			to_build.steal_all ();
		}

		public void run () {
			string action = dgettext (null,"Preparing") + "...";
			spawn_in_term ({"/usr/bin/echo", action});
			progress_dialog.action_label.set_text (action);
			progress_dialog.progressbar.set_fraction (0);
			progress_dialog.progressbar.set_text ("");
			progress_dialog.cancel_button.set_visible (true);
			progress_dialog.close_button.set_visible (false);
			progress_dialog.show ();
			while (Gtk.events_pending ())
				Gtk.main_iteration ();
			// run
			ErrorInfos err = ErrorInfos ();
			if (to_add.size () == 0
					&& to_remove.size () == 0
					&& to_load.size () == 0
					&& to_build.size () != 0) {
				// there only AUR packages to build so no need to prepare transaction
				on_emit_trans_prepared (err);
			} else {
				try {
					err = daemon.trans_init (flags);
				} catch (IOError e) {
					stderr.printf ("IOError: %s\n", e.message);
				}
				if (err.str != "") {
					finished (true);
					handle_error (err);
				} else {
					foreach (string name in to_add.get_keys ()) {
						try {
							err = daemon.trans_add_pkg (name);
						} catch (IOError e) {
							stderr.printf ("IOError: %s\n", e.message);
						}
						if (err.str != "")
							break;
					}
					foreach (string name in to_remove.get_keys ()) {
						try {
							err = daemon.trans_remove_pkg (name);
						} catch (IOError e) {
							stderr.printf ("IOError: %s\n", e.message);
						}
						if (err.str != "")
							break;
					}
					foreach (string path in to_load.get_keys ()) {
						try {
							err = daemon.trans_load_pkg (path);
						} catch (IOError e) {
							stderr.printf ("IOError: %s\n", e.message);
						}
						if (err.str != "")
							break;
					}
					if (err.str == "") {
						try {
							daemon.trans_prepare ();
						} catch (IOError e) {
							stderr.printf ("IOError: %s\n", e.message);
						}
					} else {
						release ();
						finished (true);
						handle_error (err);
					}
				}
			}
		}

		public void choose_provider (string depend, string[] providers) {
			int len = providers.length;
			var choose_provider_dialog = new ChooseProviderDialog (window);
			choose_provider_dialog.label.set_markup ("<b>%s</b>".printf (dgettext (null, "Choose a provider for %s").printf (depend, len)));
			choose_provider_dialog.comboboxtext.remove_all ();
			foreach (string provider in providers)
				choose_provider_dialog.comboboxtext.append_text (provider);
			choose_provider_dialog.comboboxtext.active = 0;
			choose_provider_dialog.run ();
			choose_provider_dialog.hide ();
			while (Gtk.events_pending ())
				Gtk.main_iteration ();
			try {
				daemon.choose_provider (choose_provider_dialog.comboboxtext.active);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public int set_transaction_sum () {
			// return 1 if transaction_sum is empty, 0 otherwise
			int ret = 1;
			uint64 dsize = 0;
			UpdatesInfos[] prepared_to_add = {};
			UpdatesInfos[] prepared_to_remove = {};
			string[] to_downgrade = {};
			string[] to_install = {};
			string[] to_reinstall = {};
			string[] to_update = {};
			string[] _to_build = {};
			TreeIter iter;
			transaction_sum_dialog.top_label.set_markup ("<big><b>%s</b></big>".printf (dgettext (null, "Transaction Summary")));
			transaction_sum_dialog.sum_list.clear ();
			try {
				prepared_to_add = daemon.trans_to_add ();
				prepared_to_remove = daemon.trans_to_remove ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
			foreach (UpdatesInfos pkg_info in prepared_to_add) {
				dsize += pkg_info.download_size;
				unowned Alpm.Package? local_pkg = handle.localdb.get_pkg (pkg_info.name);
				if (local_pkg == null) {
					to_install += "%s %s".printf (pkg_info.name, pkg_info.version);
				} else {
					int cmp = pkg_vercmp (pkg_info.version, local_pkg.version);
					if (cmp == 1)
						to_update += "%s %s".printf (pkg_info.name, pkg_info.version);
					else if (cmp == 0)
						to_reinstall += "%s %s".printf (pkg_info.name, pkg_info.version);
					else
						to_downgrade += "%s %s".printf (pkg_info.name, pkg_info.version);
				}
			}
			foreach (string name in to_build.get_keys ())
				_to_build += name;
			int len = prepared_to_remove.length;
			int i;
			if (len != 0) {
				ret = 0;
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
				ret = 0;
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
				ret = 0;
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
				ret = 0;
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
				ret = 0;
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
			if (mode == Mode.MANAGER) {
				len = to_update.length;
				if (len != 0) {
					ret = 0;
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
			if (dsize == 0)
				transaction_sum_dialog.bottom_label.set_visible (false);
			else {
				transaction_sum_dialog.bottom_label.set_markup ("<b>%s: %s</b>".printf (dgettext (null, "Total download size"), format_size (dsize)));
				transaction_sum_dialog.bottom_label.set_visible (true);
			}
			return ret;
		}

		public void commit () {
			progress_dialog.cancel_button.set_visible (false);
			try {
				daemon.trans_commit ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void build_aur_packages () {
			print ("building packages\n");
			string action = dgettext (null,"Building packages") + "...";
			spawn_in_term ({"/usr/bin/echo", "-n", action});
			progress_dialog.action_label.set_text (action);
			progress_dialog.progressbar.set_fraction (0);
			progress_dialog.progressbar.set_text ("");
			progress_dialog.cancel_button.set_visible (false);
			progress_dialog.close_button.set_visible (false);
			progress_dialog.expander.set_expanded (true);
			progress_dialog.width_request = 700;
			term.grab_focus ();
			build_timeout_id = Timeout.add (500, (GLib.SourceFunc) progress_dialog.progressbar.pulse);
			string[] cmds = {"/usr/bin/yaourt", "-S"};
			foreach (string name in to_build.get_keys ())
				cmds += name;
			Pid child_pid;
			spawn_in_term (cmds, out child_pid);
			// watch_child is needed in order to have the child_exited signal emitted
			term.watch_child (child_pid);
		}

		public void cancel () {
			try {
				daemon.trans_cancel ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void release () {
			try {
				daemon.trans_release ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void stop_daemon () {
			try {
				daemon.quit ();
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void spawn_in_term (string[] args, out Pid child_pid = null) {
			Pid intern_pid;
			try {
				Process.spawn_async (null, args, null, SpawnFlags.DO_NOT_REAP_CHILD, pty.child_setup, out intern_pid);
				ChildWatch.add (intern_pid, (pid, status) => {
					// triggered when the child indicated by intern_pid exits
					Process.close_pid (pid);
				});
			} catch (SpawnError e) {
				stderr.printf ("SpawnError: %s\n", e.message);
			}
			child_pid = intern_pid;
			term.set_pty (pty);
		}

		void on_emit_event (uint event, string[] details) {
			string msg;
			switch (event) {
				case Event.CHECKDEPS_START:
					msg = dgettext (null, "Checking dependencies") + "...";
					progress_dialog.action_label.set_text (msg);
					spawn_in_term ({"/usr/bin/echo", msg});
					break;
				case Event.FILECONFLICTS_START:
					msg = dgettext (null, "Checking file conflicts") + "...";
					progress_dialog.action_label.set_text (msg);
					spawn_in_term ({"/usr/bin/echo", msg});
					break;
				case Event.RESOLVEDEPS_START:
					msg = dgettext (null, "Resolving dependencies") + "...";
					progress_dialog.action_label.set_text (msg);
					spawn_in_term ({"/usr/bin/echo", msg});
					break;
				case Event.INTERCONFLICTS_START:
					msg = dgettext (null, "Checking inter-conflicts") + "...";
					progress_dialog.action_label.set_text (msg);
					spawn_in_term ({"/usr/bin/echo", msg});
					break;
				case Event.ADD_START:
					progress_dialog.cancel_button.set_visible (false);
					previous_filename = details[0];
					msg = dgettext (null, "Installing %s").printf (details[0]) + "...";
					progress_dialog.action_label.set_text (msg);
					msg = dgettext (null, "Installing %s").printf ("%s (%s)".printf (details[0], details[1]))+ "...";
					spawn_in_term ({"/usr/bin/echo", msg});
					break;
				case Event.REINSTALL_START:
					progress_dialog.cancel_button.set_visible (false);
					previous_filename = details[0];
					msg = dgettext (null, "Reinstalling %s").printf (details[0]) + "...";
					progress_dialog.action_label.set_text (msg);
					msg = dgettext (null, "Reinstalling %s").printf ("%s (%s)".printf (details[0], details[1]))+ "...";
					spawn_in_term ({"/usr/bin/echo", msg});
					break;
				case Event.REMOVE_START:
					progress_dialog.cancel_button.set_visible (false);
					previous_filename = details[0];
					msg = dgettext (null, "Removing %s").printf (details[0]) + "...";
					progress_dialog.action_label.set_text (msg);
					msg = dgettext (null, "Removing %s").printf ("%s (%s)".printf (details[0], details[1]))+ "...";
					spawn_in_term ({"/usr/bin/echo", msg});
					break;
				case Event.UPGRADE_START:
					progress_dialog.cancel_button.set_visible (false);
					previous_filename = details[0];
					msg = dgettext (null, "Upgrading %s").printf (details[0]) + "...";
					progress_dialog.action_label.set_text (msg);
					msg = dgettext (null, "Upgrading %s").printf ("%s (%s -> %s)".printf (details[0], details[1], details[2]))+ "...";
					spawn_in_term ({"/usr/bin/echo", msg});
					break;
				case Event.DOWNGRADE_START:
					progress_dialog.cancel_button.set_visible (false);
					previous_filename = details[0];
					msg = dgettext (null, "Downgrading %s").printf (details[0]) + "...";
					progress_dialog.action_label.set_text (msg);
					msg = dgettext (null, "Downgrading %s").printf ("%s (%s -> %s)".printf (details[0], details[1], details[2]))+ "...";
					spawn_in_term ({"/usr/bin/echo", msg});
					break;
				case Event.INTEGRITY_START:
					msg = dgettext (null, "Checking integrity") + "...";
					progress_dialog.action_label.set_text (msg);
					spawn_in_term ({"/usr/bin/echo", msg});
					break;
				case Event.KEYRING_START:
					progress_dialog.cancel_button.set_visible (true);
					msg = dgettext (null, "Checking keyring") + "...";
					progress_dialog.action_label.set_text (msg);
					spawn_in_term ({"/usr/bin/echo", msg});
					break;
				case Event.KEY_DOWNLOAD_START:
					msg = dgettext (null, "Downloading required keys") + "...";
					progress_dialog.action_label.set_text (msg);
					spawn_in_term ({"/usr/bin/echo", msg});
					break;
				case Event.LOAD_START:
					msg = dgettext (null, "Loading packages files") + "...";
					progress_dialog.action_label.set_text (msg);
					spawn_in_term ({"/usr/bin/echo", msg});
					break;
				case Event.DELTA_INTEGRITY_START:
					msg = dgettext (null, "Checking delta integrity") + "...";
					progress_dialog.action_label.set_text (msg);
					spawn_in_term ({"/usr/bin/echo", msg});
					break;
				case Event.DELTA_PATCHES_START:
					msg = dgettext (null, "Applying deltas") + "...";
					progress_dialog.action_label.set_text (msg);
					spawn_in_term ({"/usr/bin/echo", msg});
					break;
				case Event.DELTA_PATCH_START:
					msg = dgettext (null, "Generating %s with %s").printf (details[0], details[1]) + "...";
					progress_dialog.action_label.set_text (msg);
					spawn_in_term ({"/usr/bin/echo", msg});
					break;
				case Event.DELTA_PATCH_DONE:
					msg = dgettext (null, "Generation succeeded") + "...";
					progress_dialog.action_label.set_text (msg);
					spawn_in_term ({"/usr/bin/echo", msg});
					break;
				case Event.DELTA_PATCH_FAILED:
					msg = dgettext (null, "Generation failed") + "...";
					progress_dialog.action_label.set_text (msg);
					spawn_in_term ({"/usr/bin/echo", msg});
					break;
				case Event.SCRIPTLET_INFO:
					progress_dialog.action_label.set_text (dgettext (null, "Configuring %s").printf (previous_filename) + "...");
					progress_dialog.expander.set_expanded (true);
					spawn_in_term ({"/usr/bin/echo", "-n", details[0]});
					break;
				case Event.RETRIEVE_START:
					progress_dialog.cancel_button.set_visible (true);
					msg = dgettext (null, "Downloading") + "...";
					progress_dialog.action_label.set_text (msg);
					spawn_in_term ({"/usr/bin/echo", msg});
					break;
				case Event.DISKSPACE_START:
					msg = dgettext (null, "Checking available disk space") + "...";
					progress_dialog.action_label.set_text (msg);
					spawn_in_term ({"/usr/bin/echo", msg});
					break;
				case Event.OPTDEP_REQUIRED:
					spawn_in_term ({"/usr/bin/echo", dgettext (null, "%s optionally requires %s").printf (details[0], details[1])});
					break;
				case Event.DATABASE_MISSING:
					spawn_in_term ({"/usr/bin/echo", dgettext (null, "Database file for %s does not exist").printf (details[0])});
					break;
				default:
					break;
			}
			while (Gtk.events_pending ())
				Gtk.main_iteration ();
		}

		void on_emit_providers (string depend, string[] providers) {
			choose_provider (depend, providers);
		}

		void on_emit_progress (uint progress, string pkgname, int percent, uint n_targets, uint current_target) {
			double fraction;
			switch (progress) {
				case Progress.ADD_START:
				case Progress.UPGRADE_START:
				case Progress.DOWNGRADE_START:
				case Progress.REINSTALL_START:
				case Progress.REMOVE_START:
					fraction = ((float) (current_target-1)/n_targets)+((float) percent/(100*n_targets));
					break;
				case Progress.CONFLICTS_START:
				case Progress.DISKSPACE_START:
				case Progress.INTEGRITY_START:
				case Progress.KEYRING_START:
				case Progress.LOAD_START:
				default:
					fraction = (float) percent/100;
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
			while (Gtk.events_pending ())
				Gtk.main_iteration ();
		}

		void on_emit_download (string filename, uint64 xfered, uint64 total) {
			string label;
			string textbar;
			double fraction;
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
					spawn_in_term ({"/usr/bin/echo", label});
				}
			}
			if (total_download > 0) {
				fraction = (float) (xfered + already_downloaded) / total_download;
				if (fraction > 0)
					textbar = "%s/%s".printf (format_size (xfered + already_downloaded), format_size (total_download));
				else
					textbar = "%s".printf (format_size (xfered + already_downloaded));
			} else {
				fraction = (float) xfered / total;
				if (fraction > 0)
					textbar = "%s/%s".printf (format_size (xfered), format_size (total));
				else
					textbar = "%s".printf (format_size (xfered));
			}
			if (fraction > 0) {
				if (fraction != previous_percent) {
					previous_percent = fraction;
					progress_dialog.progressbar.set_fraction (fraction);
				}
			} else
				progress_dialog.progressbar.set_fraction (0);
			if (textbar != previous_textbar) {
				previous_textbar = textbar;
				progress_dialog.progressbar.set_text (textbar);
			}
			if (xfered == total) {
				already_downloaded += total;
				previous_filename = "";
			}
		}

		void on_emit_totaldownload (uint64 total) {
			total_download = total;
		}

		void on_emit_log (uint level, string msg) {
			// msg ends with \n
			string? line = null;
			TextIter end_iter;
			if ((Alpm.LogLevel) level == Alpm.LogLevel.WARNING) {
				if (previous_filename != "")
					line = dgettext (null, "Warning") + ": " + previous_filename + ": " + msg;
				else
					line = dgettext (null, "Warning") + ": " + msg;
				transaction_info_dialog.textbuffer.get_end_iter (out end_iter);
				transaction_info_dialog.textbuffer.insert (ref end_iter, msg, msg.length);
			} else if ((Alpm.LogLevel) level == Alpm.LogLevel.ERROR) {
				if (previous_filename != "")
					line = dgettext (null, "Error") + ": " + previous_filename + ": " + msg;
				else
					line = dgettext (null, "Error") + ": " + msg;
			}
			if (line != null) {
				progress_dialog.expander.set_expanded (true);
				spawn_in_term ({"/usr/bin/echo", "-n", line});
			}
		}

		public void show_warnings () {
			if (transaction_info_dialog.textbuffer.text != "") {
				transaction_info_dialog.set_title (dgettext (null, "Warning"));
				transaction_info_dialog.label.set_visible (false);
				transaction_info_dialog.expander.set_visible (true);
				transaction_info_dialog.expander.set_expanded (true);
				transaction_info_dialog.run ();
				transaction_info_dialog.hide ();
				while (Gtk.events_pending ())
					Gtk.main_iteration ();
				TextIter start_iter;
				TextIter end_iter;
				transaction_info_dialog.textbuffer.get_start_iter (out start_iter);
				transaction_info_dialog.textbuffer.get_end_iter (out end_iter);
				transaction_info_dialog.textbuffer.delete (ref start_iter, ref end_iter);
			}
		}

		public void handle_error (ErrorInfos error) {
			progress_dialog.expander.set_expanded (true);
			spawn_in_term ({"/usr/bin/echo", "-n", error.str});
			TextIter start_iter;
			TextIter end_iter;
			transaction_info_dialog.set_title (dgettext (null, "Error"));
			transaction_info_dialog.label.set_visible (true);
			transaction_info_dialog.label.set_markup (error.str);
			if (error.details.length != 0) {
				transaction_info_dialog.textbuffer.get_start_iter (out start_iter);
				transaction_info_dialog.textbuffer.get_end_iter (out end_iter);
				transaction_info_dialog.textbuffer.delete (ref start_iter, ref end_iter);
				transaction_info_dialog.expander.set_visible (true);
				transaction_info_dialog.expander.set_expanded (true);
				spawn_in_term ({"/usr/bin/echo", ":"});
				foreach (string detail in error.details) {
					spawn_in_term ({"/usr/bin/echo", detail});
					string str = detail + "\n";
					transaction_info_dialog.textbuffer.get_end_iter (out end_iter);
					transaction_info_dialog.textbuffer.insert (ref end_iter, str, str.length);
				}
			} else
				transaction_info_dialog.expander.set_visible (false);
			spawn_in_term ({"/usr/bin/echo"});
			transaction_info_dialog.run ();
			transaction_info_dialog.hide ();
			progress_dialog.hide ();
			transaction_info_dialog.textbuffer.get_start_iter (out start_iter);
			transaction_info_dialog.textbuffer.get_end_iter (out end_iter);
			transaction_info_dialog.textbuffer.delete (ref start_iter, ref end_iter);
			while (Gtk.events_pending ())
				Gtk.main_iteration ();
		}

		public void on_emit_refreshed (ErrorInfos error) {
			print ("transaction refreshed\n");
			refresh_alpm_config ();
			if (error.str == "") {
				if (mode == Mode.UPDATER) {
					progress_dialog.hide ();
					while (Gtk.events_pending ())
						Gtk.main_iteration ();
					finished (false);
				} else {
					clear_lists ();
					finished (false);
					sysupgrade (0);
				}
			} else {
				handle_error (error);
				finished (true);
			}
			previous_filename = "";
		}

		public void on_emit_trans_prepared (ErrorInfos error) {
			print ("transaction prepared\n");
			if (error.str == "") {
				show_warnings ();
				int ret = set_transaction_sum ();
				if (ret == 0) {
					if (to_add.size () == 0
							&& to_remove.size () == 0
							&& to_load.size () == 0
							&& to_build.size () != 0) {
						// there only AUR packages to build or we update AUR packages first
						release ();
						if (transaction_sum_dialog.run () == ResponseType.OK) {
							transaction_sum_dialog.hide ();
							while (Gtk.events_pending ())
								Gtk.main_iteration ();
							ErrorInfos err = ErrorInfos ();
							on_emit_trans_committed (err);
						} else {
							spawn_in_term ({"/usr/bin/echo", dgettext (null, "Transaction cancelled") + ".\n"});
							progress_dialog.hide ();
							transaction_sum_dialog.hide ();
							while (Gtk.events_pending ())
								Gtk.main_iteration ();
							if (aur_updates.length != 0)
								to_build.steal_all ();
							sysupgrade_after_trans = false;
							sysupgrade_after_build = false;
							finished (true);
						}
					} else if (sysupgrade_after_build) {
						sysupgrade_after_build = false;
						commit ();
					} else if (transaction_sum_dialog.run () == ResponseType.OK) {
						transaction_sum_dialog.hide ();
						while (Gtk.events_pending ())
							Gtk.main_iteration ();
						commit ();
					} else {
						spawn_in_term ({"/usr/bin/echo", dgettext (null, "Transaction cancelled") + ".\n"});
						progress_dialog.hide ();
						transaction_sum_dialog.hide ();
						while (Gtk.events_pending ())
							Gtk.main_iteration ();
						release ();
						if (aur_updates.length != 0)
							to_build.steal_all ();
						sysupgrade_after_trans = false;
						sysupgrade_after_build = false;
						finished (true);
					}
				} else if (mode == Mode.UPDATER) {
					sysupgrade_after_build = false;
					commit ();
				} else {
					//ErrorInfos err = ErrorInfos ();
					//err.str = dgettext (null, "Nothing to do") + "\n";
					spawn_in_term ({"/usr/bin/echo", dgettext (null, "Nothing to do") + ".\n"});
					progress_dialog.hide ();
					while (Gtk.events_pending ())
						Gtk.main_iteration ();
					release ();
					clear_lists ();
					finished (false);
					//handle_error (err);
				}
			} else {
				finished (true);
				handle_error (error);
			}
		}

		public void on_emit_trans_committed (ErrorInfos error) {
			print ("transaction committed\n");
			if (error.str == "") {
				if (to_build.size () != 0) {
					if (to_add.size () != 0
							|| to_remove.size () != 0
							|| to_load.size () != 0) {
						spawn_in_term ({"/usr/bin/echo", dgettext (null, "Transaction successfully finished") + ".\n"});
					}
					build_aur_packages ();
				} else {
					//progress_dialog.action_label.set_text (dgettext (null, "Transaction successfully finished"));
					//progress_dialog.close_button.set_visible (true);
					clear_lists ();
					show_warnings ();
					refresh_alpm_config ();
					if (sysupgrade_after_trans) {
						sysupgrade_after_trans = false;
						sysupgrade (0);
					} else if (sysupgrade_after_build) {
						sysupgrade_simple (enable_downgrade);
					} else {
						if (build_status == 0)
							spawn_in_term ({"/usr/bin/echo", dgettext (null, "Transaction successfully finished") + ".\n"});
						else
							spawn_in_term ({"/usr/bin/echo"});
						progress_dialog.hide ();
						while (Gtk.events_pending ())
							Gtk.main_iteration ();
						finished (false);
					}
				}
			} else {
				refresh_alpm_config ();
				finished (true);
				handle_error (error);
			}
			total_download = 0;
			already_downloaded = 0;
			build_status = 0;
			previous_filename = "";
			aur_checked = false;
		}

		void on_term_child_exited (int status) {
			Source.remove (build_timeout_id);
			to_build.steal_all ();
			build_status = status;
			ErrorInfos err = ErrorInfos ();
			on_emit_trans_committed (err);
		}

		void connecting_dbus_signals () {
			try {
				daemon = Bus.get_proxy_sync (BusType.SYSTEM, "org.manjaro.pamac",
														"/org/manjaro/pamac");
				// Connecting to signals
				daemon.emit_event.connect (on_emit_event);
				daemon.emit_providers.connect (on_emit_providers);
				daemon.emit_progress.connect (on_emit_progress);
				daemon.emit_download.connect (on_emit_download);
				daemon.emit_totaldownload.connect (on_emit_totaldownload);
				daemon.emit_log.connect (on_emit_log);
				daemon.emit_refreshed.connect (on_emit_refreshed);
				daemon.emit_trans_prepared.connect (on_emit_trans_prepared);
				daemon.emit_trans_committed.connect (on_emit_trans_committed);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}
	}
}
