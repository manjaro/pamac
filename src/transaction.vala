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
		public abstract async void refresh (int force, bool emit_signal) throws IOError;
		public abstract ErrorInfos trans_init (TransFlag transflags) throws IOError;
		public abstract ErrorInfos trans_sysupgrade (int enable_downgrade) throws IOError;
		public abstract ErrorInfos trans_add_pkg (string pkgname) throws IOError;
		public abstract ErrorInfos trans_remove_pkg (string pkgname) throws IOError;
		public abstract ErrorInfos trans_load_pkg (string pkgpath) throws IOError;
		public abstract async void trans_prepare () throws IOError;
		public abstract void choose_provider (int provider) throws IOError;
		public abstract UpdatesInfos[] trans_to_add () throws IOError;
		public abstract UpdatesInfos[] trans_to_remove () throws IOError;
		public abstract async void trans_commit () throws IOError;
		public abstract void trans_release () throws IOError;
		public abstract void trans_cancel () throws IOError;
		[DBus (no_reply = true)]
		public abstract void quit () throws IOError;
		public signal void emit_event (uint event, string msg);
		public signal void emit_providers (string depend, string[] providers);
		public signal void emit_progress (uint progress, string action, string pkgname, int percent, uint n_targets, uint current_target);
		public signal void emit_download (string filename, uint64 xfered, uint64 total);
		public signal void emit_totaldownload (uint64 total);
		public signal void emit_log (uint level, string msg);
		public signal void emit_refreshed (ErrorInfos error);
		public signal void emit_trans_prepared (ErrorInfos error);
		public signal void emit_trans_committed (ErrorInfos error);
	}

	public class Transaction: Object {
		public Daemon daemon;

		public Alpm.Config alpm_config;
		public Pamac.Config pamac_config;

		public TransactionData data;
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

		Terminal term;
		Pty pty;

		//dialogs
		ChooseProviderDialog choose_provider_dialog;
		TransactionSumDialog transaction_sum_dialog;
		TransactionInfoDialog transaction_info_dialog;
		ProgressWindow progress_window;
		//parent window
		ApplicationWindow? window;

		public signal void finished (bool error);

		public Transaction (ApplicationWindow? window, Pamac.Config pamac_config) {
			alpm_config = new Alpm.Config ("/etc/pacman.conf");
			this.pamac_config = pamac_config;
			mode = Mode.MANAGER;
			data = TransactionData ();
			data.flags = Alpm.TransFlag.CASCADE;
			data.to_add = new HashTable<string, string> (str_hash, str_equal);
			data.to_remove = new HashTable<string, string> (str_hash, str_equal);
			data.to_load = new HashTable<string, string> (str_hash, str_equal);
			data.to_build = new HashTable<string, string> (str_hash, str_equal);
			connecting_dbus_signals ();
			//creating dialogs
			this.window = window;
			choose_provider_dialog = new ChooseProviderDialog (window);
			transaction_sum_dialog = new TransactionSumDialog (window);
			transaction_info_dialog = new TransactionInfoDialog (window);
			progress_window = new ProgressWindow (this, window);
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
			progress_window.expander.add (grid);
			// progress data
			total_download = 0;
			already_downloaded = 0;
			previous_label = "";
			previous_textbar = "";
			previous_percent = 0.0;
			previous_filename = "";
			sysupgrade_after_trans = false;
			sysupgrade_after_build = false;
		}

		public void write_config (HashTable<string,string> new_conf) {
			try {
				daemon.write_config (new_conf);
			} catch (IOError e) {
				stderr.printf ("IOError: %s\n", e.message);
			}
		}

		public void refresh_alpm_config () {
			alpm_config = new Alpm.Config ("/etc/pacman.conf");
		}

		public void refresh (int force) {
			string action = dgettext ("pacman", "Synchronizing package databases...\n").replace ("\n", "");
			spawn_in_term ({"/usr/bin/echo", action}, null);
			progress_window.action_label.set_text (action);
			progress_window.progressbar.set_fraction (0);
			progress_window.progressbar.set_text ("");
			progress_window.cancel_button.visible = true;
			progress_window.close_button.visible = false;
			progress_window.show ();
			daemon.refresh.begin (force, true, (obj, res) => {
				try {
					daemon.refresh.end (res);
				} catch (IOError e) {
					stderr.printf ("IOError: %s\n", e.message);
				}
			});
		}

		public void sysupgrade_simple (int enable_downgrade) {
			print("simple sysupgrade\n");
			progress_window.progressbar.set_fraction (0);
			progress_window.cancel_button.visible = true;
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
					progress_window.show ();
					while (Gtk.events_pending ())
						Gtk.main_iteration ();
					daemon.trans_prepare.begin ((obj, res) => {
						try {
							daemon.trans_prepare.end (res);
						} catch (IOError e) {
							stderr.printf ("IOError: %s\n", e.message);
						}
					});
				} else {
					release ();
					finished (true);
					handle_error (err);
				}
			}
		}

		public void sysupgrade (int enable_downgrade) {
			string action = dgettext ("pacman", "Starting full system upgrade...\n").replace ("\n", "");
			spawn_in_term ({"/usr/bin/echo", action}, null);
			progress_window.action_label.set_text (action);
			progress_window.progressbar.set_fraction (0);
			progress_window.progressbar.set_text ("");
			progress_window.cancel_button.visible = true;
			progress_window.close_button.visible = false;
			while (Gtk.events_pending ())
				Gtk.main_iteration ();
			// sysupgrade
			print("get syncfirst\n");
			// get syncfirst updates
			UpdatesInfos[] syncfirst_updates = get_syncfirst_updates (alpm_config);
			if (syncfirst_updates.length != 0) {
				clear_lists ();
				if (mode == Mode.MANAGER)
					sysupgrade_after_trans = true;
				foreach (UpdatesInfos infos in syncfirst_updates)
					data.to_add.insert (infos.name, infos.name);
				// run as a standard transaction
				run ();
			} else {
				if (pamac_config.enable_aur) {
					print("get aur updates\n");
					string[] ignore_pkgs = get_ignore_pkgs (alpm_config);
					UpdatesInfos[] aur_updates = get_aur_updates (alpm_config, ignore_pkgs);
					if (aur_updates.length != 0) {
						clear_lists ();
						sysupgrade_after_build = true;
						foreach (UpdatesInfos infos in aur_updates)
							data.to_build.insert (infos.name, infos.name);
					}
				}
				sysupgrade_simple (enable_downgrade);
			}
		}

		public void clear_lists () {
			data.to_add.steal_all ();
			data.to_remove.steal_all ();
			data.to_build.steal_all ();
		}

		public void run () {
			string action = dgettext (null,"Preparing") + "...";
			spawn_in_term ({"/usr/bin/echo", action}, null);
			progress_window.action_label.set_text (action);
			progress_window.progressbar.set_fraction (0);
			progress_window.progressbar.set_text ("");
			progress_window.cancel_button.visible = true;
			progress_window.close_button.visible = false;
			progress_window.show ();
			while (Gtk.events_pending ())
				Gtk.main_iteration ();
			// run
			ErrorInfos err = ErrorInfos ();
			if (data.to_add.size () == 0
					&& data.to_remove.size () == 0
					&& data.to_load.size () == 0
					&& data.to_build.size () != 0) {
				// there only AUR packages to build so no need to prepare transaction
				on_emit_trans_prepared (err);
			} else {
				try {
					err = daemon.trans_init (data.flags);
				} catch (IOError e) {
					stderr.printf ("IOError: %s\n", e.message);
				}
				if (err.str != "") {
					finished (true);
					handle_error (err);
				} else {
					foreach (string name in data.to_add.get_keys ()) {
						try {
							err = daemon.trans_add_pkg (name);
						} catch (IOError e) {
							stderr.printf ("IOError: %s\n", e.message);
						}
						if (err.str != "")
							break;
					}
					foreach (string name in data.to_remove.get_keys ()) {
						try {
							err = daemon.trans_remove_pkg (name);
						} catch (IOError e) {
							stderr.printf ("IOError: %s\n", e.message);
						}
						if (err.str != "")
							break;
					}
					foreach (string path in data.to_load.get_keys ()) {
						try {
							err = daemon.trans_load_pkg (path);
						} catch (IOError e) {
							stderr.printf ("IOError: %s\n", e.message);
						}
						if (err.str != "")
							break;
					}
					if (err.str == "") {
						daemon.trans_prepare.begin ((obj, res) => {
							try {
								daemon.trans_prepare.end (res);
							} catch (IOError e) {
								stderr.printf ("IOError: %s\n", e.message);
							}
						});
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
			choose_provider_dialog.label.set_markup ("<b>%s</b>".printf (dgettext (null, "Choose a provider for %s:").printf (depend, len)));
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
			string[] to_build = {};
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
				unowned Alpm.Package? local_pkg = alpm_config.handle.localdb.get_pkg (pkg_info.name);
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
			foreach (string name in data.to_build.get_keys ())
				to_build += name;
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
			len = to_build.length;
			if (len != 0) {
				ret = 0;
				transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												0, dgettext (null, "To build") + ":",
												1, to_build[0]);
				i = 1;
				while (i < len) {
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, to_build[i]);
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
				transaction_sum_dialog.bottom_label.set_markup ("<b>%s %s</b>".printf (dgettext (null, "Total download size:"), format_size (dsize)));
				transaction_sum_dialog.bottom_label.set_visible (true);
			}
			return ret;
		}

		public void commit () {
			progress_window.cancel_button.visible = false;
			daemon.trans_commit.begin ((obj, res) => {
				try {
					daemon.trans_commit.end (res);
				} catch (IOError e) {
					stderr.printf ("IOError: %s\n", e.message);
				}
			});
		}

		public void build_aur_packages () {
			print ("building packages\n");
			string action = dgettext (null,"Building packages") + "...";
			spawn_in_term ({"/usr/bin/echo", "-n", action}, null);
			progress_window.action_label.set_text (action);
			progress_window.progressbar.set_fraction (0);
			progress_window.progressbar.set_text ("");
			progress_window.cancel_button.visible = false;
			progress_window.close_button.visible = false;
			progress_window.expander.set_expanded (true);
			progress_window.width_request = 700;
			term.grab_focus ();
			build_timeout_id = Timeout.add (500, (GLib.SourceFunc) progress_window.progressbar.pulse);
			string[] cmds = {"/usr/bin/yaourt", "-S"};
			foreach (string name in data.to_build.get_keys ())
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

		void spawn_in_term (string[] args, out int pid) {
			try {
				Process.spawn_async (null, args, null, SpawnFlags.DO_NOT_REAP_CHILD, pty.child_setup, out pid);
			} catch (SpawnError e) {
				stderr.printf ("SpawnError: %s\n", e.message);
			}
			term.set_pty (pty);
		}

		void on_emit_event (uint event, string msg) {
			switch (event) {
				case Event.CHECKDEPS_START:
					break;
				case Event.FILECONFLICTS_START:
					break;
				case Event.RESOLVEDEPS_START:
					break;
				case Event.INTERCONFLICTS_START:
					break;
				case Event.ADD_START:
					progress_window.cancel_button.visible = false;
					break;
				case Event.ADD_DONE:
					break;
				case Event.REMOVE_START:
					progress_window.cancel_button.visible = false;
					break;
				case Event.REMOVE_DONE:
					break;
				case Event.UPGRADE_START:
					break;
				case Event.UPGRADE_DONE:
					break;
				case Event.DOWNGRADE_START:
					break;
				case Event.DOWNGRADE_DONE:
					break;
				case Event.REINSTALL_START:
					break;
				case Event.REINSTALL_DONE:
					break;
				case Event.INTEGRITY_START:
					break;
				case Event.KEYRING_START:
					break;
		//~ 		case Event.KEY_DOWNLOAD_START:
		//~ 			break;
				case Event.LOAD_START:
					break;
		//~ 		case Event.DELTA_INTEGRITY_START:
		//~ 			break;
		//~ 		case Event.DELTA_PATCHES_START:
		//~ 			break;
		//~ 		case Event.DELTA_PATCH_START:
		//~ 			break;
		//~ 		case Event.DELTA_PATCH_DONE:
		//~ 			break;
		//~ 		case Event.DELTA_PATCH_FAILED:
		//~ 			break;
				case Event.SCRIPTLET_INFO:
					progress_window.expander.set_expanded (true);
					break;
				case Event.RETRIEVE_START:
					progress_window.action_label.set_text (msg.replace ("\n", ""));
					break;
				case Event.DISKSPACE_START:
					break;
		//~ 		case Event.OPTDEP_REQUIRED:
		//~ 			break;
		//~ 		case Event.DATABASE_MISSING:
		//~ 			break;
				case Event.FILECONFLICTS_DONE:
				case Event.CHECKDEPS_DONE:
				case Event.RESOLVEDEPS_DONE:
				case Event.INTERCONFLICTS_DONE:
				case Event.INTEGRITY_DONE:
				case Event.KEYRING_DONE:
				case Event.KEY_DOWNLOAD_DONE:
				case Event.LOAD_DONE:
				case Event.DELTA_INTEGRITY_DONE:
				case Event.DELTA_PATCHES_DONE:
				case Event.DISKSPACE_DONE:
					break;
				default:
					break;
			}
			spawn_in_term ({"/usr/bin/echo", "-n", msg}, null);
		}

		void on_emit_providers (string depend, string[] providers) {
			choose_provider (depend, providers);
		}

		void on_emit_progress (uint progress, string action, string pkgname, int percent, uint n_targets, uint current_target) {
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
			string label;
			if (pkgname != "")
				label = "%s %s...".printf (action, pkgname);
			else
				label = "%s...".printf (action);
			if (label != previous_label) {
				previous_label = label;
				progress_window.action_label.set_text (label);
			}
			string textbar = "%lu/%lu".printf (current_target, n_targets);
			if (textbar != previous_textbar) {
				previous_textbar = textbar;
				progress_window.progressbar.set_text (textbar);
			}
			if (fraction != previous_percent) {
				previous_percent = fraction;
				progress_window.progressbar.set_fraction (fraction);
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
					label = dgettext (null, "Refreshing {repo}").replace ("{repo}", filename.replace (".db", "")) + "...";
				} else {
					label = dgettext (null, "Downloading {pkgname}").replace ("{pkgname}", filename.replace (".pkg.tar.xz", "")) + "...";
				}
				if (label != previous_label) {
					previous_label = label;
					progress_window.action_label.set_text (label);
					spawn_in_term ({"/usr/bin/echo", label}, null);
				}
			}
			if (total_download > 0) {
				fraction = (float) (xfered + already_downloaded) / total_download;
				textbar = "%s/%s".printf (format_size (xfered + already_downloaded), format_size (total_download));
			} else {
				fraction = (float) xfered / total;
				textbar = "%s/%s".printf (format_size (xfered), format_size (total));
			}
			if (fraction != previous_percent) {
				previous_percent = fraction;
				progress_window.progressbar.set_fraction (fraction);
			}
			
			if (textbar != previous_textbar) {
				previous_textbar = textbar;
				progress_window.progressbar.set_text (textbar);
			}
			if (xfered == total)
				already_downloaded += total;
		}

		void on_emit_totaldownload (uint64 total) {
			total_download = total;
		}

		void on_emit_log (uint level, string msg) {
			// msg ends with \n
			string? line = null;
			TextIter end_iter;
			if ((Alpm.LogLevel) level == Alpm.LogLevel.WARNING) {
				line = dgettext (null, "Warning") + ": " + msg;
				transaction_info_dialog.textbuffer.get_end_iter (out end_iter);
				transaction_info_dialog.textbuffer.insert (ref end_iter, msg, msg.length);
			} else if ((Alpm.LogLevel) level == Alpm.LogLevel.ERROR) {
				line = dgettext (null, "Error") + ": " + msg;
			}
			if (line != null) {
				progress_window.expander.set_expanded (true);
				spawn_in_term ({"/usr/bin/echo", "-n", line}, null);
			}
		}

		public void handle_warning () {
			if (transaction_info_dialog.textbuffer.text != "") {
				transaction_info_dialog.set_title (dgettext (null, "Warning"));
				transaction_info_dialog.label.set_visible (false);
				transaction_info_dialog.expander.set_visible (true);
				transaction_info_dialog.expander.set_expanded (true);
				transaction_info_dialog.run ();
				transaction_info_dialog.hide ();
				TextIter start_iter;
				TextIter end_iter;
				transaction_info_dialog.textbuffer.get_start_iter (out start_iter);
				transaction_info_dialog.textbuffer.get_end_iter (out end_iter);
				transaction_info_dialog.textbuffer.delete (ref start_iter, ref end_iter);
			}
		}

		public void handle_error (ErrorInfos error) {
			TextIter start_iter;
			TextIter end_iter;
			transaction_info_dialog.set_title (dgettext (null, "Error"));
			transaction_info_dialog.label.set_visible (true);
			transaction_info_dialog.label.set_markup (error.str.replace ("\n", ""));
			transaction_info_dialog.textbuffer.get_start_iter (out start_iter);
			transaction_info_dialog.textbuffer.get_end_iter (out end_iter);
			transaction_info_dialog.textbuffer.delete (ref start_iter, ref end_iter);
			if (error.details.length != 0) {
				foreach (string detail in error.details) {
					transaction_info_dialog.textbuffer.get_end_iter (out end_iter);
					transaction_info_dialog.textbuffer.insert (ref end_iter, detail, detail.length);
				}
				transaction_info_dialog.expander.set_visible (true);
			} else
				transaction_info_dialog.expander.set_visible (false);
			transaction_info_dialog.run ();
			transaction_info_dialog.hide ();
			progress_window.hide ();
			while (Gtk.events_pending ())
				Gtk.main_iteration ();
		}

		public void on_emit_refreshed (ErrorInfos error) {
			print("transaction refreshed\n");
			refresh_alpm_config ();
			if (error.str == "") {
				if (mode == Mode.UPDATER) {
					progress_window.hide ();
					finished (false);
				} else {
					sysupgrade (0);
				}
			} else {
				handle_error (error);
				finished (true);
			}
		}

		public void on_emit_trans_prepared (ErrorInfos error) {
			print ("transaction prepared\n");
			if (error.str == "") {
				handle_warning ();
				int ret = set_transaction_sum ();
				if (ret == 0) {
					if (data.to_add.size () == 0
							&& data.to_remove.size () == 0
							&& data.to_load.size () == 0
							&& data.to_build.size () != 0) {
						// there only AUR packages to build or we update AUR packages first
						release ();
						if (transaction_sum_dialog.run () == ResponseType.OK) {
							transaction_sum_dialog.hide ();
							while (Gtk.events_pending ())
								Gtk.main_iteration ();
							ErrorInfos err = ErrorInfos ();
							on_emit_trans_committed (err);
						} else {
							progress_window.hide ();
							transaction_sum_dialog.hide ();
							finished (true);
						}
					} else if (sysupgrade_after_build) {
						print("sysupgrade_after_build\n");
						sysupgrade_after_build = false;
						commit ();
					} else if (transaction_sum_dialog.run () == ResponseType.OK) {
						transaction_sum_dialog.hide ();
						while (Gtk.events_pending ())
							Gtk.main_iteration ();
						commit ();
					} else {
						progress_window.hide ();
						transaction_sum_dialog.hide ();
						release ();
						finished (true);
					}
				} else if (mode == Mode.UPDATER) {
					commit ();
				} else {
					//ErrorInfos err = ErrorInfos ();
					//err.str = dgettext (null, "Nothing to do") + "\n";
					progress_window.hide ();
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
			print("transaction committed\n");
			if (error.str == "") {
				if (data.to_build.size () != 0) {
					if (data.to_add.size () != 0
							|| data.to_remove.size () != 0
							|| data.to_load.size () != 0) {
						spawn_in_term ({"/usr/bin/echo", dgettext (null, "Transaction successfully finished") + "\n"}, null);
					}
					build_aur_packages ();
				} else {
					//progress_window.action_label.set_text (dgettext (null, "Transaction successfully finished"));
					//progress_window.close_button.set_visible (true);
					clear_lists ();
					handle_warning ();
					refresh_alpm_config ();
					if (sysupgrade_after_trans) {
						sysupgrade_after_trans = false;
						sysupgrade (0);
					} else if (sysupgrade_after_build) {
						sysupgrade_simple (0);
					} else {
						progress_window.hide ();
						spawn_in_term ({"/usr/bin/echo", dgettext (null, "Transaction successfully finished") + "\n"}, null);
						finished (false);
					}
				}
			} else {
				finished (true);
				handle_error (error);
			}
			total_download = 0;
			already_downloaded = 0;
		}

		void on_term_child_exited (int status) {
			Source.remove (build_timeout_id);
			data.to_build.steal_all ();
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
