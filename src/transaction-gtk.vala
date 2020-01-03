/*
 *  pamac-vala
 *
 *  Copyright (C) 2018-2020 Guillaume Benoit <guillaume@manjaro.org>
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
		public StringBuilder warning_textbuffer;
		string current_action;
		public ProgressBox progress_box;
		uint pulse_timeout_id;
		public Gtk.ScrolledWindow details_window;
		double scroll_value;
		public Gtk.TextView details_textview;
		public Gtk.Notebook build_files_notebook;
		public ChoosePkgsDialog choose_pkgs_dialog;
		//parent window
		public Gtk.ApplicationWindow? application_window { get; construct; }
		// ask_confirmation option
		public bool no_confirm_upgrade { get; set; }
		bool summary_shown;
		bool commit_transaction_answer;

		public signal void transaction_sum_populated ();

		public TransactionGtk (Database database, Gtk.ApplicationWindow? application_window) {
			Object (database: database, application_window: application_window);
		}

		construct {
			// create dialogs
			transaction_sum_dialog = new TransactionSumDialog (application_window);
			transaction_summary = new GenericSet<string?> (str_hash, str_equal);
			warning_textbuffer = new StringBuilder ();
			current_action = "";
			progress_box = new ProgressBox ();
			progress_box.progressbar.text = "";
			progress_box.progressbar.visible = false;
			choose_pkgs_dialog = new ChoosePkgsDialog (application_window);
			// create details textview
			details_window = new Gtk.ScrolledWindow (null, null);
			details_window.visible = true;
			details_window.expand = true;
			details_textview = new Gtk.TextView ();
			details_textview.visible = true;
			details_textview.editable = false;
			details_textview.wrap_mode = Gtk.WrapMode.NONE;
			details_textview.set_monospace (true);
			details_textview.input_hints = Gtk.InputHints.NO_EMOJI;
			details_textview.top_margin = 8;
			details_textview.bottom_margin = 8;
			details_textview.left_margin = 8;
			details_textview.right_margin = 8;
			Gtk.TextIter iter;
			details_textview.buffer.get_end_iter (out iter);
			// place a mark at iter, the mark will stay there after we
			// insert some text at the end because it has right gravity.
			details_textview.buffer.create_mark ("scroll", iter, false);
			details_window.add (details_textview);
			// create build files notebook
			build_files_notebook = new Gtk.Notebook ();
			build_files_notebook.visible = true;
			build_files_notebook.show_border = false;
			build_files_notebook.expand = true;
			build_files_notebook.scrollable = true;
			build_files_notebook.enable_popup = true;
			// connect to signals
			emit_action.connect (display_action);
			emit_action_progress.connect (display_action_progress);
			emit_download_progress.connect (display_action_progress);
			emit_hook_progress.connect (display_hook_progress);
			emit_script_output.connect (show_details);
			emit_warning.connect ((msg) => {
				show_details (msg);
				warning_textbuffer.append (msg + "\n");
			});
			emit_error.connect (display_error);
			start_downloading.connect (() => {progress_box.progressbar.visible = true;});
			start_waiting.connect (start_progressbar_pulse);
			stop_waiting.connect (stop_progressbar_pulse);
			start_preparing.connect (start_progressbar_pulse);
			stop_preparing.connect (stop_progressbar_pulse);
			start_building.connect (start_progressbar_pulse);
			stop_building.connect (stop_progressbar_pulse);
			// flags
			set_trans_flags ();
			// ask_confirmation option
			no_confirm_upgrade = false;
			summary_shown = false;
			commit_transaction_answer = false;
		}

		public void set_trans_flags () {
			int flags = (1 << 4); //Alpm.TransFlag.CASCADE
			if (database.config.recurse) {
				flags |= (1 << 5); //Alpm.TransFlag.RECURSE
			}
			set_flags (flags);
		}

		public void show_details (string message) {
			Gtk.TextIter iter;
			details_textview.buffer.get_end_iter (out iter);
			details_textview.buffer.insert (ref iter, message, -1);
			details_textview.buffer.insert (ref iter, "\n", 1);
			if (details_window.vadjustment.value >= scroll_value) {
				scroll_value = details_window.vadjustment.value;
				// scroll the mark onscreen
				details_textview.scroll_mark_onscreen (details_textview.buffer.get_mark ("scroll"));
			}
		}

		void display_action (string action) {
			if (action != current_action) {
				current_action = action;
				show_details (action);
				progress_box.action_label.label = action;
				//if (pulse_timeout_id == 0) {
					//progress_box.progressbar.fraction = 0;
				//}
				//progress_box.progressbar.text = "";
			}
		}

		void display_action_progress (string action, string status, double progress) {
			if (action != current_action) {
				current_action = action;
				show_details (action);
				progress_box.action_label.label = action;
			}
			progress_box.progressbar.fraction = progress;
			progress_box.progressbar.text = status;
		}

		void display_hook_progress (string action, string details, string status, double progress) {
			if (action != current_action) {
				current_action = action;
				show_details (action);
				progress_box.action_label.label = action;
			}
			show_details (details);
			progress_box.progressbar.fraction = progress;
			progress_box.progressbar.text = status;
		}

		public void reset_progress_box () {
			current_action = "";
			progress_box.action_label.label = "";
			stop_progressbar_pulse ();
			progress_box.progressbar.fraction = 0;
			progress_box.progressbar.text = "";
			progress_box.progressbar.visible = false;
		}

		public void start_progressbar_pulse () {
			stop_progressbar_pulse ();
			progress_box.progressbar.visible = true;
			pulse_timeout_id = Timeout.add (500, (GLib.SourceFunc) progress_box.progressbar.pulse);
		}

		public void stop_progressbar_pulse () {
			if (pulse_timeout_id != 0) {
				Source.remove (pulse_timeout_id);
				pulse_timeout_id = 0;
				progress_box.progressbar.fraction = 0;
			}
		}

		protected override string[] choose_optdeps (string pkgname, string[] optdeps) {
			var optdeps_to_install = new GenericArray<string> ();
			choose_pkgs_dialog.title = dgettext (null, "Choose optional dependencies for %s").printf (pkgname);
			choose_pkgs_dialog.pkgs_list.clear ();
			foreach (unowned string name in optdeps) {
				choose_pkgs_dialog.pkgs_list.insert_with_values (null, -1, 0, false, 1, name);
			}
			choose_pkgs_dialog.valid_button.grab_focus ();
			if (choose_pkgs_dialog.run () == Gtk.ResponseType.OK) {
				choose_pkgs_dialog.pkgs_list.foreach ((model, path, iter) => {
					GLib.Value val;
					// get value at column 0 to know if it is selected
					model.get_value (iter, 0, out val);
					if ((bool) val) {
						// get value at column 1 to get the pkg name
						model.get_value (iter, 1, out val);
						optdeps_to_install.add ((string) val);
					}
					return false;
				});
			}
			choose_pkgs_dialog.hide ();
			return (owned) optdeps_to_install.data;
		}

		protected override int choose_provider (string depend, string[] providers) {
			var choose_provider_dialog = new ChooseProviderDialog (application_window);
			choose_provider_dialog.title = dgettext (null, "Choose a provider for %s").printf (depend);
			unowned Gtk.Box box = choose_provider_dialog.get_content_area ();
			box.vexpand = true;
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

		protected override bool ask_import_key (string pkgname, string key, string owner) {
			var flags = Gtk.DialogFlags.MODAL;
			int use_header_bar;
			Gtk.Settings.get_default ().get ("gtk-dialogs-use-header", out use_header_bar);
			if (use_header_bar == 1) {
				flags |= Gtk.DialogFlags.USE_HEADER_BAR;
			}
			var dialog = new Gtk.Dialog.with_buttons (dgettext (null, "Import PGP key"),
													application_window,
													flags);
			dialog.border_width = 3;
			dialog.icon_name = "system-software-install";
			dialog.deletable = false;
			dialog.add_button (dgettext (null, "Trust and Import"), Gtk.ResponseType.OK);
			unowned Gtk.Widget widget = dialog.add_button (dgettext (null, "_Cancel"), Gtk.ResponseType.CANCEL);
			widget.can_focus = true;
			widget.has_focus = true;
			widget.can_default = true;
			widget.has_default = true;
			var textbuffer = new StringBuilder ();
			textbuffer.append (dgettext (null, "The PGP key %s is needed to verify %s source files").printf (key, pkgname));
			textbuffer.append (".\n");
			textbuffer.append (dgettext (null, "Trust %s and import the PGP key").printf (owner));
			textbuffer.append (" ?");
			var label = new Gtk.Label (textbuffer.str);
			label.selectable = true;
			label.margin = 12;
			label.visible = true;
			unowned Gtk.Box box = dialog.get_content_area ();
			box.add (label);
			box.valign = Gtk.Align.CENTER;
			box.spacing = 6;
			dialog.default_width = 800;
			dialog.default_height = 150;
			int response = dialog.run ();
			dialog.destroy ();
			if (response == Gtk.ResponseType.OK) {
				return true;
			}
			return false;
		}

		protected override bool ask_edit_build_files (TransactionSummary summary) {
			bool answer = false;
			summary_shown = true;
			int response = show_summary (summary);
			if (response == Gtk.ResponseType.OK) {
				// Commit
				commit_transaction_answer = true;
			} else if (response == Gtk.ResponseType.CANCEL) {
				// Cancel transaction
				commit_transaction_answer = false;
			} else if (response == Gtk.ResponseType.REJECT) {
				// Edit build files
				answer = true;
			}
			return answer;
		}

		protected override bool ask_commit (TransactionSummary summary) {
			if (summary_shown) {
				summary_shown = false;
				return commit_transaction_answer;
			} else {
				uint must_confirm_length = summary.to_downgrade.length ()
									+ summary.to_remove.length ()
									+ summary.to_build.length ();
				if (no_confirm_upgrade
					&& must_confirm_length == 0
					&& summary.to_upgrade.length () > 0) {
					show_warnings (true);
					return true;
				}
				int response = show_summary (summary);
				if (response == Gtk.ResponseType.OK) {
					// Commit
					return true;
				}
			}
			return false;
		}

		int show_summary (TransactionSummary summary) {
			uint64 dsize = 0;
			transaction_summary.remove_all ();
			transaction_sum_dialog.sum_list.clear ();
			transaction_sum_dialog.edit_button.visible = false;
			var iter = Gtk.TreeIter ();
			if (summary.to_remove.length () > 0) {
				foreach (unowned Package pkg in summary.to_remove) {
					transaction_summary.add (pkg.name);
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, pkg.name,
												2, pkg.version,
												4, pkg.repo);
				}
				Gtk.TreePath path = transaction_sum_dialog.sum_list.get_path (iter);
				uint pos = (path.get_indices ()[0]) - (summary.to_remove.length () - 1);
				transaction_sum_dialog.sum_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				transaction_sum_dialog.sum_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "To remove") + ":"));
			}
			if (summary.to_downgrade.length () > 0) {
				foreach (unowned Package pkg in summary.to_downgrade) {
					dsize += pkg.download_size;
					string size = pkg.download_size == 0 ? "" : format_size (pkg.download_size);
					transaction_summary.add (pkg.name);
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, pkg.name,
												2, pkg.version,
												3, "(%s)".printf (pkg.installed_version),
												4, pkg.repo,
												5, size);
				}
				Gtk.TreePath path = transaction_sum_dialog.sum_list.get_path (iter);
				uint pos = (path.get_indices ()[0]) - (summary.to_downgrade.length () - 1);
				transaction_sum_dialog.sum_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				transaction_sum_dialog.sum_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "To downgrade") + ":"));
			}
			if (summary.to_build.length () > 0) {
				transaction_sum_dialog.edit_button.visible = true;
				foreach (unowned Package pkg in summary.to_build) {
					transaction_summary.add (pkg.name);
					string installed_version = "";
					if (pkg.installed_version != "" && pkg.installed_version != pkg.version) {
						installed_version = "(%s)".printf (pkg.installed_version);
					}
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, pkg.name,
												2, pkg.version,
												3, installed_version,
												4, pkg.repo);
				}
				Gtk.TreePath path = transaction_sum_dialog.sum_list.get_path (iter);
				uint pos = (path.get_indices ()[0]) - (summary.to_build.length () - 1);
				transaction_sum_dialog.sum_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				transaction_sum_dialog.sum_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "To build") + ":"));
			}
			if (summary.to_install.length () > 0) {
				foreach (unowned Package pkg in summary.to_install) {
					dsize += pkg.download_size;
					string size = pkg.download_size == 0 ? "" : format_size (pkg.download_size);
					transaction_summary.add (pkg.name);
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, pkg.name,
												2, pkg.version,
												4, pkg.repo,
												5, size);
				}
				Gtk.TreePath path = transaction_sum_dialog.sum_list.get_path (iter);
				uint pos = (path.get_indices ()[0]) - (summary.to_install.length () - 1);
				transaction_sum_dialog.sum_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				transaction_sum_dialog.sum_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "To install") + ":"));
			}
			if (summary.to_reinstall.length () > 0) {
				foreach (unowned Package pkg in summary.to_reinstall) {
					dsize += pkg.download_size;
					string size = pkg.download_size == 0 ? "" : format_size (pkg.download_size);
					transaction_summary.add (pkg.name);
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												1, pkg.name,
												2, pkg.version,
												4, pkg.repo,
												5, size);
				}
				Gtk.TreePath path = transaction_sum_dialog.sum_list.get_path (iter);
				uint pos = (path.get_indices ()[0]) - (summary.to_reinstall.length () - 1);
				transaction_sum_dialog.sum_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				transaction_sum_dialog.sum_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "To reinstall") + ":"));
			}
			if (summary.to_upgrade.length () > 0) {
				if (!no_confirm_upgrade) {
					foreach (unowned Package pkg in summary.to_upgrade) {
						dsize += pkg.download_size;
						string size = pkg.download_size == 0 ? "" : format_size (pkg.download_size);
						transaction_summary.add (pkg.name);
						transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
													1, pkg.name,
													2, pkg.version,
													3, "(%s)".printf (pkg.installed_version),
													4, pkg.repo,
													5, size);
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
			if (transaction_summary.length == 0) {
				// empty summary comes in case of transaction preparation failure
				// with pkgs to build so we show warnings ans ask to edit build files
				transaction_sum_dialog.edit_button.visible = true;
				if (warning_textbuffer.len > 0) {
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												0, Markup.escape_text (warning_textbuffer.str));
					warning_textbuffer = new StringBuilder ();
				} else {
					transaction_sum_dialog.sum_list.insert_with_values (out iter, -1,
												0, dgettext (null, "Failed to prepare transaction"));
				}
			} else {
				show_warnings (true);
			}
			transaction_sum_populated ();
			transaction_sum_dialog.cancel_button.grab_focus ();
			int response = transaction_sum_dialog.run ();
			transaction_sum_dialog.hide ();
			return response;
		}

		public void destroy_widget (Gtk.Widget widget) {
			widget.destroy ();
		}

		protected override void edit_build_files (string[] pkgnames) {
			foreach (unowned string pkgname in pkgnames) {
				string action = dgettext (null, "Edit %s build files".printf (pkgname));
				display_action (action);
				// populate notebook
				bool success = false;
				populate_build_files.begin (pkgname, false, false, (obj, res) => {
					success = populate_build_files.end (res);
					loop.quit ();
				});
				loop.run ();
				if (!success) {
					continue;
				}
				// remove noteboook from manager_window properties stack
				unowned Gtk.Box? manager_box = build_files_notebook.get_parent () as Gtk.Box;
				if (manager_box != null) {
					manager_box.remove (build_files_notebook);
				}
				// create dialog
				var flags = Gtk.DialogFlags.MODAL;
				int use_header_bar;
				Gtk.Settings.get_default ().get ("gtk-dialogs-use-header", out use_header_bar);
				if (use_header_bar == 1) {
					flags |= Gtk.DialogFlags.USE_HEADER_BAR;
				}
				var dialog = new Gtk.Dialog.with_buttons (action,
														application_window,
														flags);
				dialog.icon_name = "system-software-install";
				dialog.border_width = 3;
				dialog.add_button (dgettext (null, "Save"), Gtk.ResponseType.CLOSE);
				unowned Gtk.Widget widget = dialog.add_button (dgettext (null, "_Cancel"), Gtk.ResponseType.CANCEL);
				widget.can_focus = true;
				widget.has_focus = true;
				widget.can_default = true;
				widget.has_default = true;
				unowned Gtk.Box box = dialog.get_content_area ();
				box.spacing = 6;
				box.add (build_files_notebook);
				dialog.default_width = 700;
				dialog.default_height = 500;
				// run
				int response = dialog.run ();
				// re-add noteboook to manager_window properties stack
				box.remove (build_files_notebook);
				if (manager_box != null) {
					manager_box.add (build_files_notebook);
				}
				dialog.destroy ();
				if (response == Gtk.ResponseType.CLOSE) {
					// save modifications
					save_build_files.begin (pkgname, () => {
						loop.quit ();
					});
					loop.run ();
				}
			}
		}

		async void create_build_files_tab (string filename, bool editable = true) {
			var file = File.new_for_path (filename);
			try {
				StringBuilder text = new StringBuilder ();
				var fis = yield file.read_async ();
				var dis = new DataInputStream (fis);
				string line;
				while ((line = yield dis.read_line_async ()) != null) {
					text.append (line);
					text.append ("\n");
				}
				// only show text file
				if (!text.str.validate ()) {
					return;
				}
				var scrolled_window = new Gtk.ScrolledWindow (null, null);
				scrolled_window.visible = true;
				var textview = new Gtk.TextView ();
				textview.visible = true;
				textview.editable = editable;
				textview.wrap_mode = Gtk.WrapMode.NONE;
				textview.set_monospace (true);
				textview.input_hints = Gtk.InputHints.NO_EMOJI;
				textview.top_margin = 8;
				textview.bottom_margin = 8;
				textview.left_margin = 8;
				textview.right_margin = 8;
				textview.buffer.set_text (text.str, (int) text.len);
				textview.buffer.set_modified (false);
				if (editable) {
					Gtk.TextIter iter;
					textview.buffer.get_start_iter (out iter);
					textview.buffer.place_cursor (iter);
				} else {
					textview.cursor_visible = false;
				}
				scrolled_window.add (textview);
				var label =  new Gtk.Label (file.get_basename ());
				label.visible = true;
				build_files_notebook.append_page (scrolled_window, label);
			} catch (GLib.Error e) {
				critical ("%s\n", e.message);
			}
		}

		public async bool populate_build_files (string pkgname, bool clone, bool overwrite) {
			if (clone) {
				File? clone_dir = database.clone_build_files (pkgname, overwrite);
				if (clone_dir == null) {
					// error
					build_files_notebook.foreach (destroy_widget);
					return false;
				}
			}
			build_files_notebook.foreach (destroy_widget);
			var file_paths = yield get_build_files (pkgname);
			if (file_paths.length () == 0) {
				return false;
			}
			foreach (unowned string path in file_paths) {
				if ("PKGBUILD" in path) {
					yield create_build_files_tab (path);
					// add diff after PKGBUILD, do not failed if no diff
					string diff_path;
					if (database.config.aur_build_dir == "/var/tmp") {
						diff_path = Path.build_path ("/", database.config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()), pkgname, "diff");
					} else {
						diff_path = Path.build_path ("/", database.config.aur_build_dir, "pamac-build", pkgname, "diff");
					}
					var diff_file = File.new_for_path (diff_path);
					if (diff_file.query_exists ()) {
						yield create_build_files_tab (diff_path, false);
					}
				} else {
					// other file
					yield create_build_files_tab (path);
				}
			}
			return true;
		}

		public async void save_build_files (string pkgname) {
			int num_pages = build_files_notebook.get_n_pages ();
			int index = 0;
			while (index < num_pages) {
				Gtk.Widget child = build_files_notebook.get_nth_page (index);
				var scrolled_window = child as Gtk.ScrolledWindow;
				var textview = scrolled_window.get_child () as Gtk.TextView;
				if (textview.buffer.get_modified () == true) {
					string file_name;
					if (database.config.aur_build_dir == "/var/tmp") {
						file_name = Path.build_path ("/", database.config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()), pkgname, build_files_notebook.get_tab_label_text (child));
					} else {
						file_name = Path.build_path ("/", database.config.aur_build_dir, "pamac-build", pkgname, build_files_notebook.get_tab_label_text (child));
					}
					var file = File.new_for_path (file_name);
					Gtk.TextIter start_iter;
					Gtk.TextIter end_iter;
					textview.buffer.get_start_iter (out start_iter);
					textview.buffer.get_end_iter (out end_iter);
					try {
						// delete the file before rewrite it
						yield file.delete_async ();
						// creating a DataOutputStream to the file
						FileOutputStream fos = yield file.create_async (FileCreateFlags.NONE);
						// writing a string to the stream
						string text = textview.buffer.get_text (start_iter, end_iter, false);
						yield fos.write_all_async (text.data, Priority.DEFAULT, null, null);
						if (build_files_notebook.get_tab_label_text (child) == "PKGBUILD") {
							database.regenerate_srcinfo (pkgname);
						}
					} catch (GLib.Error e) {
						critical ("%s\n", e.message);
					}
				}
				index++;
			}
		}

		public void show_warnings (bool block) {
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
				dialog.border_width = 3;
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
				box.spacing = 6;
				dialog.default_width = 600;
				dialog.default_height = 300;
				if (block) {
					dialog.run ();
					dialog.destroy ();
				} else {
					dialog.response.connect (() => {
						dialog.destroy ();
					});
					dialog.show ();
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
			dialog.border_width = 3;
			dialog.icon_name = "system-software-install";
			var textbuffer = new StringBuilder ();
			if (details.length != 0) {
				show_details (message + ":");
				foreach (unowned string detail in details) {
					show_details (detail);
					textbuffer.append (detail + "\n");
				}
			} else {
				show_details (message);
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
			box.spacing = 6;
			dialog.default_width = 600;
			dialog.default_height = 300;
			Timeout.add (1000, () => {
				show_notification (message);
				return false;
			});
			dialog.run ();
			dialog.destroy ();
		}

		#if ENABLE_SNAP
		protected override bool ask_snap_install_classic (string name) {
			var flags = Gtk.DialogFlags.MODAL;
			int use_header_bar;
			Gtk.Settings.get_default ().get ("gtk-dialogs-use-header", out use_header_bar);
			if (use_header_bar == 1) {
				flags |= Gtk.DialogFlags.USE_HEADER_BAR;
			}
			var dialog = new Gtk.Dialog.with_buttons (dgettext (null, "Warning"),
													application_window,
													flags);
			dialog.border_width = 3;
			dialog.icon_name = "system-software-install";
			dialog.deletable = false;
			dialog.add_button (dgettext (null, "Install"), Gtk.ResponseType.OK);
			unowned Gtk.Widget widget = dialog.add_button (dgettext (null, "_Cancel"), Gtk.ResponseType.CANCEL);
			widget.can_focus = true;
			widget.has_focus = true;
			widget.can_default = true;
			widget.has_default = true;
			var scrolledwindow = new Gtk.ScrolledWindow (null, null);
			var textbuffer = new StringBuilder ();
			textbuffer.append (dgettext (null, "The snap %s was published using classic confinement").printf (name));
			textbuffer.append (".\n");
			textbuffer.append ("It thus may perform arbitrary system changes outside of the security sandbox that snaps are usually confined to, which may put your system at risk");
			textbuffer.append (".\n");
			textbuffer.append (dgettext (null, "Install %s anyway").printf (name));
			textbuffer.append (" ?");
			var label = new Gtk.Label (textbuffer.str);
			label.selectable = true;
			label.margin = 12;
			scrolledwindow.visible = true;
			label.visible = true;
			scrolledwindow.add (label);
			scrolledwindow.expand = true;
			unowned Gtk.Box box = dialog.get_content_area ();
			box.add (scrolledwindow);
			box.spacing = 6;
			dialog.default_width = 900;
			dialog.default_height = 150;
			int response = dialog.run ();
			dialog.destroy ();
			if (response == Gtk.ResponseType.OK) {
				return true;
			}
			return false;
		}
		#endif

		public void show_notification (string message) {
			var notification = new Notification (dgettext (null, "Package Manager"));
			notification.set_body (message);
			application_window.application.send_notification ("pamac-manager", notification);
		}
	}
}
