/*
 *  pamac-vala
 *
 *  Copyright (C) 2018-2023 Guillaume Benoit <guillaume@manjaro.org>
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
		// dialogs
		GenericSet<string?> transaction_summary;
		StringBuilder warning_textbuffer;
		string current_action;
		public ProgressBox progress_box;
		uint pulse_timeout_id;
		public Gtk.ScrolledWindow details_window;
		double scroll_value;
		public Gtk.TextView details_textview;
		public Gtk.Notebook build_files_notebook;
		// parent window
		public Gtk.Application? application { get; construct; }
		// local config
		public LocalConfig local_config { get; construct; }
		// ask_confirmation option
		public bool no_confirm_upgrade { get; set; }
		bool summary_shown;
		public bool commit_transaction_answer;

		public signal void transaction_sum_populated ();

		public TransactionGtk (Database database, LocalConfig local_config, Gtk.Application? application) {
			Object (database: database, local_config: local_config, application: application);
		}

		construct {
			// create dialogs
			transaction_summary = new GenericSet<string?> (str_hash, str_equal);
			warning_textbuffer = new StringBuilder ();
			current_action = "";
			progress_box = new ProgressBox ();
			progress_box.progressbar.text = "";
			progress_box.progressbar.visible = false;
			// create details textview
			details_window = new Gtk.ScrolledWindow ();
			details_window.hexpand = true;
			details_window.vexpand = true;
			details_textview = new Gtk.TextView ();
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
			details_window.set_child (details_textview);
			// create build files notebook
			build_files_notebook = new Gtk.Notebook ();
			build_files_notebook.show_border = false;
			build_files_notebook.hexpand = true;
			build_files_notebook.vexpand = true;
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
			// ask_confirmation option
			no_confirm_upgrade = false;
			summary_shown = false;
			commit_transaction_answer = false;
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
			lock (current_action) {
				if (action != current_action) {
					current_action = action;
					show_details (action);
					progress_box.action_label.label = action;
					if (pulse_timeout_id == 0) {
						progress_box.progressbar.fraction = 0;
					}
					progress_box.progressbar.text = "";
				}
			}
		}

		void display_action_progress (string action, string status, double progress) {
			lock (current_action) {
				if (action != current_action) {
					current_action = action;
					show_details (action);
					progress_box.action_label.label = action;
				}
				progress_box.progressbar.fraction = progress;
				progress_box.progressbar.text = status;
			}
		}

		void display_hook_progress (string action, string details, string status, double progress) {
			lock (current_action) {
				if (action != current_action) {
					current_action = action;
					show_details (action);
					progress_box.action_label.label = action;
				}
				show_details (details);
				progress_box.progressbar.fraction = progress;
				progress_box.progressbar.text = status;
			}
		}

		public void reset_progress_box () {
			lock (current_action) {
				current_action = "";
				progress_box.action_label.label = "";
				stop_progressbar_pulse ();
				progress_box.progressbar.fraction = 0;
				progress_box.progressbar.text = "";
				progress_box.progressbar.visible = false;
			}
		}

		public void start_progressbar_pulse () {
			stop_progressbar_pulse ();
			progress_box.progressbar.visible = true;
			pulse_timeout_id = Timeout.add (500, () => {
				progress_box.progressbar.pulse ();
				return true;
			});
		}

		public void stop_progressbar_pulse () {
			if (pulse_timeout_id != 0) {
				Source.remove (pulse_timeout_id);
				pulse_timeout_id = 0;
				progress_box.progressbar.fraction = 0;
			}
		}

		public ChoosePkgsDialog create_choose_pkgs_dialog () {
			var application_window = application.active_window;
			return new ChoosePkgsDialog (application_window);
		}

		protected override async GenericArray<string> choose_optdeps (string pkgname, GenericArray<string> optdeps) {
			GenericArray<string> optdeps_to_install;
			var choose_pkgs_dialog = create_choose_pkgs_dialog ();
			choose_pkgs_dialog.title = dgettext (null, "Choose optional dependencies for %s").printf (pkgname);
			foreach (unowned string name in optdeps) {
				choose_pkgs_dialog.add_pkg (name);
			}
			choose_pkgs_dialog.cancel_button.grab_focus ();
			int response = Gtk.ResponseType.CANCEL;
			choose_pkgs_dialog.response.connect ((res) => {
				response = res;
				Idle.add (choose_optdeps.callback);
			});
			choose_pkgs_dialog.show ();
			yield;
			if (response == Gtk.ResponseType.OK) {
				optdeps_to_install = choose_pkgs_dialog.get_selected_pkgs ();
			} else {
				optdeps_to_install = new GenericArray<string> ();
			}
			choose_pkgs_dialog.destroy ();
			return optdeps_to_install;
		}

		protected override async int choose_provider (string depend, GenericArray<string> providers) {
			var application_window = application.active_window;
			var choose_provider_dialog = new ChooseProviderDialog (application_window);
			choose_provider_dialog.title = dgettext (null, "Choose a provider for %s").printf (depend);
			unowned Gtk.Box box = choose_provider_dialog.box;
			var pkgs = new GenericArray<Package> ();
			foreach (unowned string provider in providers) {
				var pkg = database.get_sync_pkg (provider);
				if (pkg == null)  {
					pkg = database.get_aur_pkg (provider);
				}
				if (pkg != null)  {
					pkgs.add (pkg);
				}
			}
			unowned Gtk.CheckButton? last_radiobutton = null;
			foreach (unowned Package pkg in pkgs) {
				string provider = "%s  %s  %s".printf (pkg.name, pkg.version, pkg.repo);
				var radiobutton = new Gtk.CheckButton.with_label (provider);
				radiobutton.get_style_context ().add_class ("selection-mode");
				// active first provider
				if (last_radiobutton == null) {
					radiobutton.active = true;
				} else {
					radiobutton.set_group (last_radiobutton);
				}
				last_radiobutton = radiobutton;
				box.append (radiobutton);
			}
			int index = 0;
			choose_provider_dialog.response.connect (() => {
				// get active provider
				unowned Gtk.Widget child = box.get_first_child ();
				var radiobutton = child as Gtk.CheckButton;
				while (radiobutton != null) {
					if (radiobutton.active) {
						break;
					}
					index++;
					child = radiobutton.get_next_sibling ();
					radiobutton = child as Gtk.CheckButton;
				}
				Idle.add (choose_provider.callback);
				choose_provider_dialog.destroy ();
			});
			choose_provider_dialog.show ();
			yield;
			return index;
		}

		protected override async bool ask_import_key (string pkgname, string key, string owner) {
			var flags = Gtk.DialogFlags.MODAL;
			int use_header_bar;
			Gtk.Settings.get_default ().get ("gtk-dialogs-use-header", out use_header_bar);
			if (use_header_bar == 1) {
				flags |= Gtk.DialogFlags.USE_HEADER_BAR;
			}
			var application_window = application.active_window;
			var dialog = new Gtk.Dialog.with_buttons (dgettext (null, "Import PGP key"),
													application_window,
													flags);
			dialog.margin_top = 3;
			dialog.margin_bottom = 3;
			dialog.margin_start = 3;
			dialog.margin_end = 3;
			dialog.icon_name = "system-software-install";
			dialog.deletable = false;
			dialog.add_button (dgettext (null, "Trust and Import"), Gtk.ResponseType.OK);
			unowned Gtk.Widget widget = dialog.add_button (dgettext (null, "_Cancel"), Gtk.ResponseType.CANCEL);
			dialog.focus_widget = widget;
			var textbuffer = new StringBuilder ();
			textbuffer.append (dgettext (null, "The PGP key %s is needed to verify %s source files").printf (key, pkgname));
			textbuffer.append (".\n");
			textbuffer.append (dgettext (null, "Trust %s and import the PGP key").printf (owner));
			textbuffer.append (" ?");
			var label = new Gtk.Label (textbuffer.str);
			label.selectable = true;
			label.margin_top = 12;
			label.margin_bottom = 12;
			label.margin_start = 12;
			label.margin_end = 12;
			unowned Gtk.Box box = dialog.get_content_area ();
			box.append (label);
			box.valign = Gtk.Align.CENTER;
			box.spacing = 6;
			dialog.default_width = 800;
			dialog.default_height = 150;
			int response = Gtk.ResponseType.CANCEL;
			dialog.response.connect ((res) => {
				response = res;
				Idle.add (ask_import_key.callback);
				dialog.destroy ();
			});
			dialog.show ();
			yield;
			if (response == Gtk.ResponseType.OK) {
				return true;
			}
			return false;
		}

		protected override async bool ask_edit_build_files (TransactionSummary summary) {
			bool answer = false;
			summary_shown = true;
			int response = yield show_summary (summary);
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

		protected override async bool ask_commit (TransactionSummary summary) {
			if (summary_shown) {
				summary_shown = false;
				return commit_transaction_answer;
			} else {
				bool must_confirm = summary.to_downgrade.length != 0
									|| summary.to_install.length != 0
									|| summary.to_remove.length != 0
									|| summary.conflicts_to_remove.length != 0
									|| summary.to_build.length != 0;
				if (no_confirm_upgrade
					&& !must_confirm
					&& summary.to_upgrade.length != 0) {
					show_warnings (true);
					commit_transaction_answer = true;
					return true;
				}
				int response = yield show_summary (summary);
				if (response == Gtk.ResponseType.OK) {
					// Commit
					commit_transaction_answer = true;
					return true;
				}
			}
			commit_transaction_answer = false;
			return false;
		}

		public void transaction_summary_remove_all () {
			lock (transaction_summary) {
				transaction_summary.remove_all ();
			}
		}

		void transaction_summary_add (string id) {
			lock (transaction_summary) {
				transaction_summary.add (id);
			}
		}

		public bool transaction_summary_contains (string id) {
			bool contains = false;
			lock (transaction_summary){
				contains = transaction_summary.contains (id);
			}
			return contains;
		}

		public uint transaction_summary_length () {
			uint length = 0;
			lock (transaction_summary){
				length = transaction_summary.length;
			}
			return length;
		}

		AlpmPackage? get_full_alpm_pkg (Package pkg) {
			AlpmPackage? full_pkg = null;
			if (pkg is AlpmPackage) {
				full_pkg = database.get_pkg (pkg.name);
			}
			return full_pkg;
		}

		public async File get_icon_file (string url) {
			var uri = File.new_for_uri (url);
			var cached_icon = File.new_for_path ("/tmp/pamac-app-icons/%s".printf (uri.get_basename ()));
			try {
				if (!cached_icon.query_exists ()) {
					// download icon
					var inputstream = yield database.get_url_stream (url);
					var pixbuf = new Gdk.Pixbuf.from_stream (inputstream);
					// scale pixbux at 64 pixels
					int width = pixbuf.get_width ();
					if (width > 64) {
						pixbuf = pixbuf.scale_simple (64, 64, Gdk.InterpType.BILINEAR);
					}
					// save scaled image in tmp
					FileOutputStream os = cached_icon.append_to (FileCreateFlags.NONE);
					pixbuf.save_to_stream (os, "png");
				}
			} catch (Error e) {
				warning ("%s: %s", url, e.message);
			}
			return cached_icon;
		}

		void set_row_app_icon (SummaryRow row, Package pkg) {
			var icon_theme = Gtk.IconTheme.get_for_display (Gdk.Display.get_default ());
			Gtk.IconPaintable paintable = icon_theme.lookup_icon ("package-x-generic", null, 64, 1, 0, 0);
			unowned string? icon = pkg.icon;
			if (icon != null) {
				if ("http" in icon) {
					get_icon_file.begin (icon, (obj, res) => {
						var file = get_icon_file.end (res);
						if (file.query_exists ()) {
							row.app_icon.paintable = new Gtk.IconPaintable.for_file (file, 64, 1);
						}
					});
				} else {
					var file = File.new_for_path (icon);
					if (file.query_exists ()) {
						paintable = new Gtk.IconPaintable.for_file (file, 64, 1);
					} else if (pkg is SnapPackage && pkg.installed_version != null) {
						// try to retrieve icon
						database.get_installed_snap_icon_async.begin (pkg.name, (obj, res) => {
							string downloaded_image_path = database.get_installed_snap_icon_async.end (res);
							var new_file = File.new_for_path (downloaded_image_path);
							if (new_file.query_exists ()) {
								row.app_icon.paintable = new Gtk.IconPaintable.for_file (new_file, 64, 1);
							}
						});
					} else {
						// some icons are not in the right repo
						string new_icon = icon;
						if ("extra" in icon) {
							new_icon = icon.replace ("extra", "community");
						} else if ("community" in icon) {
							new_icon = icon.replace ("community", "extra");
						}
						var new_file = File.new_for_path (new_icon);
						if (new_file.query_exists ()) {
							paintable = new Gtk.IconPaintable.for_file (new_file, 64, 1);
						}
					}
				}
			}
			row.app_icon.paintable = paintable;
		}

		SummaryRow? create_summary_row (Package pkg, AlpmPackage? full_alpm_pkg, string? infos_string) {
			var row = new SummaryRow ();
			bool software_mode = local_config.software_mode;
			// populate infos
			unowned string? app_name = pkg.app_name;
			if (app_name == null && full_alpm_pkg != null) {
				app_name = full_alpm_pkg.app_name;
			}
			if (app_name == null) {
				row.name_label.label = pkg.name;
			} else if (full_alpm_pkg != null && !software_mode) {
				row.name_label.label = "%s (%s)".printf (app_name, pkg.name);
			} else {
				row.name_label.label = app_name;
			}
			if (infos_string == null || software_mode) {
				row.infos_label.visible = false;
			} else {
				row.infos_label.label = infos_string;
			}
			if (!software_mode) {
				row.version_label.label = pkg.version;
			}
			uint64 download_size = pkg.download_size;
			if (download_size > 0) {
				row.size_label.label = format_size (download_size);
			}
			if (pkg.repo != null) {
				if (full_alpm_pkg != null) {
					if (pkg.repo == "community" || pkg.repo == "extra" || pkg.repo == "core" || pkg.repo == "multilib") {
						if (software_mode) {
							row.repo_label.label = dgettext (null, "Official Repositories");
						} else {
							row.repo_label.label = "%s (%s)".printf (dgettext (null, "Official Repositories"), pkg.repo);
						}
					} else if (pkg.repo == dgettext (null, "AUR")) {
						row.repo_label.label = pkg.repo;
					} else {
						row.repo_label.label = "%s (%s)".printf (dgettext (null, "Repositories"), pkg.repo);
					}
				} else if (pkg is FlatpakPackage) {
					row.repo_label.label = "%s (%s)".printf (dgettext (null, "Flatpak"), pkg.repo);
				} else {
					row.repo_label.label = pkg.repo;
				}
			}
			if (full_alpm_pkg != null) {
				set_row_app_icon (row, full_alpm_pkg);
			} else {
				set_row_app_icon (row, pkg);
			}
			return row;
		}

		string get_pkgname_display_name (string pkgname) {
			AlpmPackage? full_pkg = database.get_pkg (pkgname);
			if (full_pkg != null) {
				unowned string app_name = full_pkg.app_name;
				if (app_name != null) {
					return app_name;
				}
			}
			return pkgname;
		}

		void add_infos_to_summary (Gtk.ListBox listbox, Package pkg, string? infos_string) {
			unowned string id;
			var alpm_pkg = get_full_alpm_pkg (pkg);
			if (alpm_pkg != null) {
				id = alpm_pkg.id;
			} else {
				id = pkg.id;
			}
			transaction_summary_add (id);
			SummaryRow? row = create_summary_row (pkg, alpm_pkg, infos_string);
			// row null for standard pkg in software_mode
			if (row != null) {
				listbox.append (row);
			}
		}

		void add_remove_to_summary (Gtk.ListBox listbox, Package pkg) {
			string? infos = null;
			// check for remove reason to display in place of installed_version
			var alpm_pkg = pkg as AlpmPackage;
			if (alpm_pkg != null) {
				unowned GenericArray<string> dep_list = alpm_pkg.depends;
				if (dep_list.length != 0) {
					// depends list populated in alpm_utils/get_transaction_summary, it contains only one element.
					infos = "%s: %s".printf (dgettext (null, "Depends On"), get_pkgname_display_name (dep_list[0]));
				} else {
					unowned GenericArray<string> requiredby_list = alpm_pkg.requiredby;
					if (requiredby_list.length != 0) {
						// requiredby list populated in alpm_utils/get_transaction_summary, it contains only one element.
						infos = "%s: %s".printf (dgettext (null, "Orphan Of"), get_pkgname_display_name (requiredby_list[0]));
					}
				}
			}
			add_infos_to_summary (listbox, pkg, infos);
		}

		void add_conflict_to_summary (Gtk.ListBox listbox, Package pkg) {
			string? infos = null;
			var alpm_pkg = pkg as AlpmPackage;
			if (alpm_pkg != null) {
				// check for conflict to display in place of installed_version
				unowned GenericArray<string> dep_list = alpm_pkg.conflicts;
				if (dep_list.length != 0) {
					// conflicts list populated in alpm_utils/get_transaction_summary, it contains only one element.
					infos = "(%s: %s)".printf (dgettext (null, "Conflicts With"), get_pkgname_display_name (dep_list[0]));
				}
			}
			add_infos_to_summary (listbox, pkg, infos);
		}

		void add_downgrade_to_summary (Gtk.ListBox listbox, Package pkg) {
			string? infos = null;
			add_infos_to_summary (listbox, pkg, infos);
		}

		void add_build_to_summary (Gtk.ListBox listbox, Package pkg) {
			string? infos = null;
			if (pkg.installed_version != null) {
				if (pkg.installed_version != pkg.version) {
					infos = "%s".printf (pkg.installed_version);
				}
			} else {
				// check for requiredby to display in place of installed_version
				var alpm_pkg = pkg as AlpmPackage;
				if (alpm_pkg != null) {
					unowned GenericArray<string> dep_list = alpm_pkg.requiredby;
					if (dep_list.length != 0) {
						// requiredby list populated in alpm_utils/get_transaction_summary, it contains only one element.
						infos = "%s: %s".printf (dgettext (null, "Required By"), dep_list[0]);
					}
				}
			}
			add_infos_to_summary (listbox, pkg, infos);
		}

		void add_install_to_summary (Gtk.ListBox listbox, Package pkg) {
			// check for requiredby/replace to display in place of installed_version
			string? infos = null;
			var alpm_pkg = pkg as AlpmPackage;
			if (alpm_pkg != null) {
				bool requiredby_found = false;
				// 1 - check for required dep
				unowned GenericArray<string> dep_list = alpm_pkg.requiredby;
				if (dep_list.length != 0) {
					requiredby_found = true;
					// requiredby list populated in alpm_utils/get_transaction_summary, it contains only one element.
					infos = "%s: %s".printf (dgettext (null, "Required By"), get_pkgname_display_name (dep_list[0]));
				}
				// 2 - check for replaces
				if (!requiredby_found) {
					dep_list = alpm_pkg.replaces;
					if (dep_list.length != 0) {
						// replaces list populated in alpm_utils/get_transaction_summary, it contains only one element.
						infos = "%s: %s".printf (dgettext (null, "Replaces"), get_pkgname_display_name (dep_list[0]));
					}
				}
			}
			add_infos_to_summary (listbox, pkg, infos);
		}

		void add_reinstall_to_summary (Gtk.ListBox listbox, Package pkg) {
			string? infos = null;
			add_infos_to_summary (listbox, pkg, infos);
		}

		void add_upgrade_to_summary (Gtk.ListBox listbox, Package pkg) {
			string? infos = null;
			add_infos_to_summary (listbox, pkg, infos);
		}

		Gtk.ListBox create_listbox (Gtk.Box box, string action, uint length) {
			string info;
			if (length > 1) {
				info = "<b>%s (%u)</b>".printf (dgettext (null, action), length);
			} else {
				info = "<b>%s</b>".printf (dgettext (null, action));
			}
			var expander = new Gtk.Expander (info);
			expander.use_markup = true;
			expander.expanded = true;
			expander.margin_top = 12;
			box.append (expander);
			var listbox = new Gtk.ListBox ();
			listbox.margin_top = 6;
			listbox.selection_mode = Gtk.SelectionMode.NONE;
			listbox.get_style_context ().add_class ("content");
			expander.set_child (listbox);
			return listbox;
		}

		async int show_summary (TransactionSummary summary) {
			uint64 dsize = 0;
			transaction_summary_remove_all ();
			var application_window = application.active_window;
			var transaction_sum_dialog = new TransactionSumDialog (application_window);
			unowned Gtk.Box box = transaction_sum_dialog.box;
			unowned GenericArray<Package> pkgs;
			unowned GenericArray<Package> conflict_pkgs;
			unowned Package pkg;
			uint i;
			uint length;
			uint conflicts_length;
			Gtk.ListBox remove_listbox = null;
			conflict_pkgs = summary.conflicts_to_remove;
			conflicts_length = conflict_pkgs.length;
			pkgs = summary.to_remove;
			length = pkgs.length;
			if (length > 0) {
				remove_listbox = create_listbox (box, "To remove", length + conflicts_length);
				pkg = pkgs[0];
				add_remove_to_summary (remove_listbox, pkg);
				i = 1;
				while (i < length) {
					pkg = pkgs[i];
					add_remove_to_summary (remove_listbox, pkg);
					i++;
				}
			}
			if (conflicts_length > 0) {
				// if length > 0, remove_listbox already created
				if (length == 0) {
					remove_listbox = create_listbox (box, "To remove", conflicts_length);
				}
				pkg = conflict_pkgs[0];
				add_conflict_to_summary (remove_listbox, pkg);
				i = 1;
				while (i < conflicts_length) {
					pkg = conflict_pkgs[i];
					add_conflict_to_summary (remove_listbox, pkg);
					i++;
				}
			}
			pkgs = summary.to_downgrade;
			length = pkgs.length;
			if (length > 0) {
				var listbox = create_listbox (box, "To downgrade", length);
				pkg = pkgs[0];
				dsize += pkg.download_size;
				add_downgrade_to_summary (listbox, pkg);
				i = 1;
				while (i < length) {
					pkg = pkgs[i];
					dsize += pkg.download_size;
					add_downgrade_to_summary (listbox, pkg);
					i++;
				}
			}
			pkgs = summary.to_build;
			length = pkgs.length;
			if (length > 0) {
				var listbox = create_listbox (box, "To build", length);
				pkg = pkgs[0];
				add_build_to_summary (listbox, pkg);
				i = 1;
				while (i < length) {
					pkg = pkgs[i];
					add_build_to_summary (listbox, pkg);
					i++;
				}
				var button = new Gtk.Button.with_label (dgettext (null, "Edit build files"));
				button.halign = Gtk.Align.END;
				button.margin_top = 6;
				button.clicked.connect (() => {
					// call reject response will edit build files
					transaction_sum_dialog.response (Gtk.ResponseType.REJECT);
				});
				box.append (button);
			}
			pkgs = summary.to_install;
			length = pkgs.length;
			if (length > 0) {
				var listbox = create_listbox (box, "To install", length);
				pkg = pkgs[0];
				dsize += pkg.download_size;
				add_install_to_summary (listbox, pkg);
				i = 1;
				while (i < length) {
					pkg = pkgs[i];
					dsize += pkg.download_size;
					add_install_to_summary (listbox, pkg);
					i++;
				}
			}
			pkgs = summary.to_reinstall;
			length = pkgs.length;
			if (length > 0) {
				var listbox = create_listbox (box, "To reinstall", length);
				pkg = pkgs[0];
				dsize += pkg.download_size;
				add_reinstall_to_summary (listbox, pkg);
				i = 1;
				while (i < length) {
					pkg = pkgs[i];
					dsize += pkg.download_size;
					add_reinstall_to_summary (listbox, pkg);
					i++;
				}
			}
			pkgs = summary.to_upgrade;
			length = pkgs.length;
			if (length > 0) {
				if (!no_confirm_upgrade) {
					var listbox = create_listbox (box, "To upgrade", length);
					pkg = pkgs[0];
					dsize += pkg.download_size;
					add_upgrade_to_summary (listbox, pkg);
					i = 1;
					while (i < length) {
						pkg = pkgs[i];
						dsize += pkg.download_size;
						add_upgrade_to_summary (listbox, pkg);
						i++;
					}
				}
			}
			if (dsize == 0) {
				transaction_sum_dialog.top_label.visible = false;
			} else {
				transaction_sum_dialog.top_label.set_markup ("<b>%s: %s</b>".printf (dgettext (null, "Total download size"), format_size (dsize)));
				transaction_sum_dialog.top_label.visible = true;
			}
			if (transaction_summary_length () == 0) {
				// empty summary comes in case of transaction preparation failure
				// with pkgs to build so we show warnings ans ask to edit build files
				var label = new Gtk.Label (null);
				label.halign = Gtk.Align.START;
				label.wrap = true;
				label.margin_top = 12;
				box.append (label);
				if (warning_textbuffer.len > 0) {
					label.label = warning_textbuffer.str;
					warning_textbuffer = new StringBuilder ();
				} else {
					label.label = dgettext (null, "Failed to prepare transaction");
				}
				var button = new Gtk.Button.with_label (dgettext (null, "Edit build files"));
				button.margin_top = 6;
				button.clicked.connect (() => {
					// call reject response will edit build files
					transaction_sum_dialog.response (Gtk.ResponseType.REJECT);
				});
				box.append (button);
			} else {
				show_warnings (true);
			}
			transaction_sum_dialog.cancel_button.grab_focus ();
			int response = Gtk.ResponseType.CANCEL;
			transaction_sum_dialog.response.connect ((res) => {
				response = res;
				Idle.add (show_summary.callback);
				transaction_sum_dialog.destroy ();
			});
			transaction_sum_dialog.show ();
			yield;
			if (response == Gtk.ResponseType.OK) {
				transaction_sum_populated ();
			}
			return response;
		}

		protected override async void edit_build_files (GenericArray<string> pkgnames) {
			foreach (unowned string pkgname in pkgnames) {
				string action = dgettext (null, "Edit %s build files".printf (pkgname));
				display_action (action);
				// populate notebook
				bool success = yield populate_build_files_async (pkgname, false, false);
				if (!success) {
					continue;
				}
				// remove noteboook from manager_window properties stack
				unowned Gtk.Box manager_box = build_files_notebook.get_parent () as Gtk.Box;
				manager_box.remove (build_files_notebook);
				// create dialog
				var flags = Gtk.DialogFlags.MODAL;
				int use_header_bar;
				Gtk.Settings.get_default ().get ("gtk-dialogs-use-header", out use_header_bar);
				if (use_header_bar == 1) {
					flags |= Gtk.DialogFlags.USE_HEADER_BAR;
				}
				var application_window = application.active_window;
				var dialog = new Gtk.Dialog.with_buttons (action,
														application_window,
														flags);
				dialog.icon_name = "system-software-install";
				dialog.margin_top = 6;
				dialog.margin_bottom = 6;
				dialog.margin_start = 6;
				dialog.margin_end = 6;
				dialog.add_button (dgettext (null, "Save"), Gtk.ResponseType.CLOSE);
				unowned Gtk.Widget widget = dialog.add_button (dgettext (null, "_Cancel"), Gtk.ResponseType.CANCEL);
				dialog.focus_widget = widget;
				unowned Gtk.Box box = dialog.get_content_area ();
				box.spacing = 6;
				box.append (build_files_notebook);
				dialog.default_width = 700;
				dialog.default_height = 500;
				// run
				int response = Gtk.ResponseType.CANCEL;
				dialog.response.connect ((res) => {
					response = res;
					Idle.add (edit_build_files.callback);
				});
				dialog.show ();
				yield;
				// re-add noteboook to manager_window properties stack
				box.remove (build_files_notebook);
				dialog.destroy ();
				manager_box.append (build_files_notebook);
				if (response == Gtk.ResponseType.CLOSE) {
					// save modifications
					yield save_build_files_async (pkgname);
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
				var scrolledwindow = new Gtk.ScrolledWindow ();
				var textview = new Gtk.TextView ();
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
				scrolledwindow.set_child (textview);
				var label =  new Gtk.Label (file.get_basename ());
				build_files_notebook.append_page (scrolledwindow, label);
			} catch (Error e) {
				warning (e.message);
			}
		}

		public async bool populate_build_files_async (string pkgname, bool clone, bool overwrite) {
			if (clone) {
				File? clone_dir = yield database.clone_build_files_async (pkgname, overwrite);
				if (clone_dir == null) {
					// error
					int num_pages = build_files_notebook.get_n_pages ();
					for (int i = 0; i < num_pages; i++) {
						build_files_notebook.remove_page (i);
					}
					return false;
				}
			}
			int num_pages = build_files_notebook.get_n_pages ();
			for (int i = 0; i < num_pages; i++) {
				build_files_notebook.remove_page (i);
			}
			GenericArray<string> file_paths = yield get_build_files_async (pkgname);
			if (file_paths.length == 0) {
				return false;
			}
			foreach (unowned string path in file_paths) {
				if ("PKGBUILD" in path) {
					yield create_build_files_tab (path);
					// add diff after PKGBUILD, do not failed if no diff
					string diff_path;
					if (database.config.aur_build_dir == "/var/tmp" || database.config.aur_build_dir == "/tmp") {
						diff_path = Path.build_filename (database.config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()), pkgname, "diff");
					} else {
						diff_path = Path.build_filename (database.config.aur_build_dir, pkgname, "diff");
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

		public async void save_build_files_async (string pkgname) {
			int num_pages = build_files_notebook.get_n_pages ();
			int index = 0;
			while (index < num_pages) {
				Gtk.Widget child = build_files_notebook.get_nth_page (index);
				var scrolled_window = child as Gtk.ScrolledWindow;
				var textview = scrolled_window.get_child () as Gtk.TextView;
				if (textview.buffer.get_modified () == true) {
					string file_name;
					if (database.config.aur_build_dir == "/var/tmp" || database.config.aur_build_dir == "/tmp") {
						file_name = Path.build_filename (database.config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()), pkgname, build_files_notebook.get_tab_label_text (child));
					} else {
						file_name = Path.build_filename (database.config.aur_build_dir, pkgname, build_files_notebook.get_tab_label_text (child));
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
					} catch (Error e) {
						warning (e.message);
					}
				}
				index++;
			}
		}

		public void clear_warnings () {
			warning_textbuffer = new StringBuilder ();
		}

		public void show_warnings (bool block) {
			if (warning_textbuffer.len > 0) {
				Gtk.DialogFlags flags = 0;
				if (block) {
					flags |= Gtk.DialogFlags.MODAL;
				}
				int use_header_bar;
				Gtk.Settings.get_default ().get ("gtk-dialogs-use-header", out use_header_bar);
				if (use_header_bar == 1) {
					flags |= Gtk.DialogFlags.USE_HEADER_BAR;
				}
				var application_window = application.active_window;
				var dialog = new Gtk.Dialog.with_buttons (dgettext (null, "Warning"),
														application_window,
														flags);
				dialog.margin_top = 3;
				dialog.margin_bottom = 3;
				dialog.margin_start = 3;
				dialog.margin_end = 3;
				dialog.icon_name = "system-software-install";
				dialog.deletable = false;
				unowned Gtk.Widget widget = dialog.add_button (dgettext (null, "_Close"), Gtk.ResponseType.CLOSE);
				var scrolledwindow = new Gtk.ScrolledWindow ();
				var label = new Gtk.Label (warning_textbuffer.str);
				label.selectable = true;
				label.margin_top = 12;
				label.margin_bottom = 12;
				label.margin_start = 12;
				label.margin_end = 12;
				scrolledwindow.set_child (label);
				scrolledwindow.hexpand = true;
				scrolledwindow.vexpand = true;
				unowned Gtk.Box box = dialog.get_content_area ();
				box.append (scrolledwindow);
				box.spacing = 12;
				if (dgettext (null, "A restart is required for the changes to take effect") in warning_textbuffer.str) {
					var button = new Gtk.Button.with_label (dgettext (null, "Restart"));
					button.margin_top = 12;
					button.margin_bottom = 12;
					button.margin_start = 12;
					button.margin_end = 12;
					button.halign = Gtk.Align.END;
					button.clicked.connect (() => {
						try {
							Process.spawn_command_line_sync ("reboot");
						} catch (SpawnError e) {
							warning (e.message);
						}
					});
					box.append (button);
				}
				dialog.focus_widget = widget;
				dialog.default_width = 600;
				dialog.default_height = 300;
				dialog.response.connect (() => {
					dialog.destroy ();
					warning_textbuffer = new StringBuilder ();
				});
				dialog.show ();
			}
		}

		public void display_error (string message, GenericArray<string> details) {
			reset_progress_box ();
			var flags = Gtk.DialogFlags.MODAL;
			int use_header_bar;
			Gtk.Settings.get_default ().get ("gtk-dialogs-use-header", out use_header_bar);
			if (use_header_bar == 1) {
				flags |= Gtk.DialogFlags.USE_HEADER_BAR;
			}
			var application_window = application.active_window;
			var dialog = new Gtk.Dialog.with_buttons (message,
													application_window,
													flags);
			dialog.margin_top = 3;
			dialog.margin_bottom = 3;
			dialog.margin_start = 3;
			dialog.margin_end = 3;
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
			dialog.focus_widget = widget;
			var scrolledwindow = new Gtk.ScrolledWindow ();
			var label = new Gtk.Label (textbuffer.str);
			label.selectable = true;
			label.margin_top = 12;
			label.margin_bottom = 12;
			label.margin_start = 12;
			label.margin_end = 12;
			scrolledwindow.set_child (label);
			scrolledwindow.hexpand = true;
			scrolledwindow.vexpand = true;
			unowned Gtk.Box box = dialog.get_content_area ();
			box.append (scrolledwindow);
			box.spacing = 6;
			dialog.default_width = 600;
			dialog.default_height = 300;
			Timeout.add (1000, () => {
				show_notification (message);
				return false;
			});
			dialog.response.connect (() => {
				dialog.destroy ();
			});
			dialog.show ();
		}

		protected override async bool ask_snap_install_classic (string name) {
			var flags = Gtk.DialogFlags.MODAL;
			int use_header_bar;
			Gtk.Settings.get_default ().get ("gtk-dialogs-use-header", out use_header_bar);
			if (use_header_bar == 1) {
				flags |= Gtk.DialogFlags.USE_HEADER_BAR;
			}
			var application_window = application.active_window;
			var dialog = new Gtk.Dialog.with_buttons (dgettext (null, "Warning"),
													application_window,
													flags);
			dialog.margin_top = 3;
			dialog.margin_bottom = 3;
			dialog.margin_start = 3;
			dialog.margin_end = 3;
			dialog.icon_name = "system-software-install";
			dialog.deletable = false;
			dialog.add_button (dgettext (null, "Install"), Gtk.ResponseType.OK);
			unowned Gtk.Widget widget = dialog.add_button (dgettext (null, "_Cancel"), Gtk.ResponseType.CANCEL);
			dialog.focus_widget = widget;
			var scrolledwindow = new Gtk.ScrolledWindow ();
			var textbuffer = new StringBuilder ();
			textbuffer.append (dgettext (null, "The snap %s was published using classic confinement").printf (name));
			textbuffer.append (".\n");
			textbuffer.append ("It thus may perform arbitrary system changes outside of the security sandbox that snaps are usually confined to, which may put your system at risk");
			textbuffer.append (".\n");
			textbuffer.append (dgettext (null, "Install %s anyway").printf (name));
			textbuffer.append (" ?");
			var label = new Gtk.Label (textbuffer.str);
			label.selectable = true;
			label.margin_top = 12;
			label.margin_bottom = 12;
			label.margin_start = 12;
			label.margin_end = 12;
			scrolledwindow.set_child (label);
			scrolledwindow.hexpand = true;
			scrolledwindow.vexpand = true;
			unowned Gtk.Box box = dialog.get_content_area ();
			box.append (scrolledwindow);
			box.spacing = 6;
			dialog.default_width = 900;
			dialog.default_height = 150;
			int response = Gtk.ResponseType.CANCEL;
			dialog.response.connect ((res) => {
				response = res;
				Idle.add (ask_snap_install_classic.callback);
				dialog.destroy ();
			});
			dialog.show ();
			yield;
			if (response == Gtk.ResponseType.OK) {
				return true;
			}
			return false;
		}

		public void show_notification (string message) {
			var notification = new Notification (dgettext (null, "Package Manager"));
			notification.set_body (message);
			application.send_notification ("pamac-manager", notification);
		}
	}
}
