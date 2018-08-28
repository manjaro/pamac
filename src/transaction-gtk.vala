/*
 *  pamac-vala
 *
 *  Copyright (C) 2018 Guillaume Benoit <guillaume@manjaro.org>
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
	public class TransactionGtk: Transaction {
		//dialogs
		TransactionSumDialog transaction_sum_dialog;
		public GenericSet<string?> transaction_summary;
		StringBuilder warning_textbuffer;
		string current_action;
		public ProgressBox progress_box;
		uint pulse_timeout_id;
		Vte.Terminal term;
		Vte.Pty pty;
		public Gtk.ScrolledWindow term_window;
		//parent window
		public Gtk.ApplicationWindow? application_window { get; construct; }
		// ask_confirmation option
		public bool no_confirm_upgrade { get; set; }

		public TransactionGtk (Database database, Gtk.ApplicationWindow? application_window) {
			Object (database: database, application_window: application_window);
		}

		construct {
			//creating dialogs
			this.application_window = application_window;
			transaction_sum_dialog = new TransactionSumDialog (application_window);
			transaction_summary = new GenericSet<string?> (str_hash, str_equal);
			warning_textbuffer = new StringBuilder ();
			current_action = "";
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
			// connect to signal
			emit_action.connect (display_action);
			emit_action_progress.connect (display_action_progress);
			emit_hook_progress.connect (display_hook_progress);
			emit_script_output.connect (show_in_term);
			emit_warning.connect ((msg) => {
				warning_textbuffer.append (msg + "\n");
			});
			emit_error.connect (display_error);
			refresh_finished.connect (on_refresh_finished);
			finished.connect (on_finished);
			sysupgrade_finished.connect (on_finished);
			start_generating_mirrors_list.connect (start_progressbar_pulse);
			generate_mirrors_list_finished.connect (reset_progress_box);
			start_building.connect (start_progressbar_pulse);
			stop_building.connect (stop_progressbar_pulse);
			// notify
			Notify.init (dgettext (null, "Package Manager"));
			// flags
			flags = (1 << 4); //Alpm.TransFlag.CASCADE
			if (database.config.recurse) {
				flags |= (1 << 5); //Alpm.TransFlag.RECURSE
			}
			no_confirm_upgrade = false;
		}

		// destruction
		~TransactionGtk () {
			stop_daemon ();
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
					right_click_menu.popup_at_pointer (event);
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

		protected override async int run_cmd_line (string[] args, string working_directory, Cancellable cancellable) {
			int status = 1;
			term.set_pty (pty);
			var launcher = new SubprocessLauncher (SubprocessFlags.NONE);
			launcher.set_cwd (working_directory);
			launcher.set_environ (Environ.get ());
			launcher.set_child_setup (pty.child_setup);
			try {
				Subprocess process = launcher.spawnv (args);
				try {
					yield process.wait_async (cancellable);
					if (process.get_if_exited ()) {
						status = process.get_exit_status ();
					}
				} catch (Error e) {
					// cancelled
					process.send_signal (Posix.Signal.INT);
					process.send_signal (Posix.Signal.KILL);
				}
			} catch (Error e) {
				stderr.printf ("Error: %s\n", e.message);
			}
			return status;
		}

		void display_action (string action) {
			if (action != current_action) {
				current_action = action;
				show_in_term (action);
				progress_box.action_label.label = action;
				progress_box.progressbar.fraction = 0;
				progress_box.progressbar.text = "";
			}
		}

		void display_action_progress (string action, string status, double progress) {
			if (action != current_action) {
				current_action = action;
				show_in_term (action);
				progress_box.action_label.label = action;
			}
			progress_box.progressbar.fraction = progress;
			progress_box.progressbar.text = status;
		}

		void display_hook_progress (string action, string details, string status, double progress) {
			if (action != current_action) {
				current_action = action;
				show_in_term (action);
				progress_box.action_label.label = action;
			}
			show_in_term (details);
			progress_box.progressbar.fraction = progress;
			progress_box.progressbar.text = status;
		}

		public void reset_progress_box () {
			current_action = "";
			progress_box.action_label.label = "";
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

		protected override int choose_provider (string depend, string[] providers) {
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
					break;
				}
				index++;
			}
			choose_provider_dialog.destroy ();
			return index;
		}

		protected override bool ask_confirmation (TransactionSummary summary) {
			show_warnings (true);
			uint must_confirm_length = summary.to_install.length ()
									+ summary.to_downgrade.length ()
									+ summary.to_reinstall.length ()
									+ summary.to_remove.length ()
									+ summary.to_build.length ();
			if (no_confirm_upgrade 
				&& must_confirm_length == 0
				&& summary.to_upgrade.length () > 0) {
				return true;
			}
			uint64 dsize = 0;
			transaction_summary.remove_all ();
			transaction_sum_dialog.sum_list.clear ();
			var iter = Gtk.TreeIter ();
			if (summary.to_remove.length () > 0) {
				foreach (unowned Package infos in summary.to_remove) {
					transaction_summary.add (infos.name);
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, infos.name,
												2, infos.version);
				}
				Gtk.TreePath path = transaction_sum_dialog.sum_list.get_path (iter);
				uint pos = (path.get_indices ()[0]) - (summary.to_remove.length () - 1);
				transaction_sum_dialog.sum_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				transaction_sum_dialog.sum_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "To remove") + ":"));
			}
			if (summary.aur_conflicts_to_remove.length () > 0) {
				// do not add type enum because it is just infos
				foreach (unowned Package infos in summary.aur_conflicts_to_remove) {
					transaction_summary.add (infos.name);
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, infos.name,
												2, infos.version);
				}
				Gtk.TreePath path = transaction_sum_dialog.sum_list.get_path (iter);
				uint pos = (path.get_indices ()[0]) - (summary.aur_conflicts_to_remove.length () - 1);
				transaction_sum_dialog.sum_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				transaction_sum_dialog.sum_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "To remove") + ":"));
			}
			if (summary.to_downgrade.length () > 0) {
				foreach (unowned Package infos in summary.to_downgrade) {
					dsize += infos.download_size;
					transaction_summary.add (infos.name);
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, infos.name,
												2, infos.version,
												3, "(%s)".printf (infos.installed_version));
				}
				Gtk.TreePath path = transaction_sum_dialog.sum_list.get_path (iter);
				uint pos = (path.get_indices ()[0]) - (summary.to_downgrade.length () - 1);
				transaction_sum_dialog.sum_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				transaction_sum_dialog.sum_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "To downgrade") + ":"));
			}
			if (summary.to_build.length () > 0) {
				foreach (unowned AURPackage infos in summary.to_build) {
					transaction_summary.add (infos.name);
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, infos.name,
												2, infos.version);
				}
				Gtk.TreePath path = transaction_sum_dialog.sum_list.get_path (iter);
				uint pos = (path.get_indices ()[0]) - (summary.to_build.length () - 1);
				transaction_sum_dialog.sum_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				transaction_sum_dialog.sum_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "To build") + ":"));
			}
			if (summary.to_install.length () > 0) {
				foreach (unowned Package infos in summary.to_install) {
					dsize += infos.download_size;
					transaction_summary.add (infos.name);
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, infos.name,
												2, infos.version);
				}
				Gtk.TreePath path = transaction_sum_dialog.sum_list.get_path (iter);
				uint pos = (path.get_indices ()[0]) - (summary.to_install.length () - 1);
				transaction_sum_dialog.sum_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				transaction_sum_dialog.sum_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "To install") + ":"));
			}
			if (summary.to_reinstall.length () > 0) {
				foreach (unowned Package infos in summary.to_reinstall) {
					dsize += infos.download_size;
					transaction_summary.add (infos.name);
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, infos.name,
												2, infos.version);
				}
				Gtk.TreePath path = transaction_sum_dialog.sum_list.get_path (iter);
				uint pos = (path.get_indices ()[0]) - (summary.to_reinstall.length () - 1);
				transaction_sum_dialog.sum_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				transaction_sum_dialog.sum_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "To reinstall") + ":"));
			}
			if (summary.to_upgrade.length () > 0) {
				if (!no_confirm_upgrade) {
					foreach (unowned Package infos in summary.to_upgrade) {
						dsize += infos.download_size;
						transaction_summary.add (infos.name);
						transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
													1, infos.name,
													2, infos.version,
													3, "(%s)".printf (infos.installed_version));
					}
					Gtk.TreePath path = transaction_sum_dialog.sum_list.get_path (iter);
					uint pos = (path.get_indices ()[0]) - (summary.to_upgrade.length () - 1);
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
			if (transaction_sum_dialog.run () == Gtk.ResponseType.OK) {
				transaction_sum_dialog.hide ();
				return true;
			} else {
				transaction_sum_dialog.hide ();
				transaction_summary.remove_all ();
			}
			return false;
		}

		void show_warnings (bool block) {
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
				label.selectable = true;
				label.margin = 12;
				scrolledwindow.visible = true;
				label.visible = true;
				scrolledwindow.add (label);
				scrolledwindow.expand = true;
				unowned Gtk.Box box = dialog.get_content_area ();
				box.add (scrolledwindow);
				dialog.default_width = 600;
				dialog.default_height = 300;
				if (block) {
					dialog.run ();
					dialog.destroy ();
				} else {
					dialog.show ();
					dialog.response.connect (() => {
						dialog.destroy ();
					});
				}
				warning_textbuffer = new StringBuilder ();
			}
		}

		public void display_error (string message, string[] details) {
			reset_progress_box ();
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
			label.selectable = true;
			label.margin = 12;
			scrolledwindow.visible = true;
			label.visible = true;
			scrolledwindow.add (label);
			scrolledwindow.expand = true;
			unowned Gtk.Box box = dialog.get_content_area ();
			box.add (scrolledwindow);
			dialog.default_width = 600;
			dialog.default_height = 300;
			dialog.show ();
			dialog.response.connect (() => {
				dialog.destroy ();
			});
			Timeout.add (1000, () => {
				try {
					var notification = new Notify.Notification (dgettext (null, "Package Manager"),
																message,
																"system-software-update");
					notification.show ();
				} catch (Error e) {
					stderr.printf ("Notify Error: %s", e.message);
				}
				return false;
			});
		}

		void on_refresh_finished (bool success) {
			reset_progress_box ();
			show_in_term ("");
		}

		void on_finished (bool success) {
			if (success) {
				try {
					var notification = new Notify.Notification (dgettext (null, "Package Manager"),
																dgettext (null, "Transaction successfully finished"),
																"system-software-update");
					notification.show ();
				} catch (Error e) {
					stderr.printf ("Notify Error: %s", e.message);
				}
			}
			transaction_summary.remove_all ();
			reset_progress_box ();
			show_in_term ("");
			show_warnings (false);
		}
	}
}
