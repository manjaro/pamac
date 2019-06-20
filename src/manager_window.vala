/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2019 Guillaume Benoit <guillaume@manjaro.org>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
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

	string search_string;
	List<string> repos_names;
	GenericSet<string?> to_install;
	GenericSet<string?> to_remove;
	GenericSet<string?> to_load;
	GenericSet<string?> to_build;
	GenericSet<string?> to_update;
	GenericSet<string?> temporary_ignorepkgs;

	int sort_pkgs_by_relevance (Package pkg_a, Package pkg_b) {
		if (pkg_a.name in to_remove) {
			if (pkg_b.name in to_remove) {
				return sort_pkgs_by_name (pkg_a, pkg_b);
			} else {
				return -1;
			}
		}
		if (pkg_b.name in to_remove) {
			if (pkg_a.name in to_remove) {
				return sort_pkgs_by_name (pkg_a, pkg_b);
			} else {
				return 1;
			}
		}
		if (pkg_a.name in to_install) {
			if (pkg_b.name in to_install) {
				return sort_pkgs_by_name (pkg_a, pkg_b);
			} else {
				return -1;
			}
		}
		if (pkg_b.name in to_install) {
			if (pkg_a.name in to_install) {
				return sort_pkgs_by_name (pkg_a, pkg_b);
			} else {
				return 1;
			}
		}
		if (pkg_a.name in temporary_ignorepkgs) {
			if (pkg_b.name in temporary_ignorepkgs) {
				return sort_pkgs_by_name (pkg_a, pkg_b);
			} else {
				return -1;
			}
		}
		if (pkg_b.name in temporary_ignorepkgs) {
			if (pkg_a.name in temporary_ignorepkgs) {
				return sort_pkgs_by_name (pkg_a, pkg_b);
			} else {
				return 1;
			}
		}
		if (pkg_a.installed_version == "") {
			if (pkg_b.installed_version == "") {
				return sort_pkgs_by_name (pkg_a, pkg_b);
			} else {
				return 1;
			}
		}
		if (pkg_b.installed_version == "") {
			if (pkg_a.installed_version == "") {
				return sort_pkgs_by_name (pkg_a, pkg_b);
			} else {
				return -1;
			}
		}
		if (pkg_a.app_name == "") {
			if (pkg_b.app_name == "") {
				return sort_pkgs_by_name (pkg_a, pkg_b);
			} else {
				return 1;
			}
		}
		if (pkg_b.app_name == "") {
			if (pkg_a.app_name == "") {
				return sort_pkgs_by_name (pkg_a, pkg_b);
			} else {
				return -1;
			}
		}
		return sort_pkgs_by_name (pkg_a, pkg_b);
	}

	int sort_pkgs_by_name (Package pkg_a, Package pkg_b) {
		string str_a = "%s%s".printf (pkg_a.app_name, pkg_a.name);
		string str_b = "%s%s".printf (pkg_b.app_name, pkg_b.name);
		return strcmp (str_a, str_b);
	}

	int sort_pkgs_by_date (Package pkg_a, Package pkg_b) {
		if (pkg_a.installed_version == "") {
			if (pkg_b.installed_version == "") {
				if (pkg_a.builddate > pkg_b.builddate) {
					return -1;
				}
				if (pkg_b.builddate > pkg_a.builddate) {
					return 1;
				}
				return sort_pkgs_by_name (pkg_a, pkg_b);
			} else {
				return 1;
			}
		}
		if (pkg_b.installed_version == "") {
			if (pkg_a.installed_version == "") {
				if (pkg_a.builddate > pkg_b.builddate) {
					return -1;
				}
				if (pkg_b.builddate > pkg_a.builddate) {
					return 1;
				}
				return sort_pkgs_by_name (pkg_a, pkg_b);
			} else {
				return -1;
			}
		}
		if (pkg_a.installdate > pkg_b.installdate) {
			return -1;
		}
		if (pkg_b.installdate > pkg_a.installdate) {
			return 1;
		}
		return sort_pkgs_by_name (pkg_a, pkg_b);
	}

	int sort_pkgs_by_repo (Package pkg_a, Package pkg_b) {
		int index_a = -2;
		if (pkg_a.repo == dgettext (null, "AUR")) {
			index_a = -1;
		} else if (pkg_a.repo != "") {
			unowned List<string>? element = repos_names.find_custom (pkg_a.repo, strcmp);
			if (element != null) {
				index_a = repos_names.index (element.data);
			}
		}
		int index_b = -2;
		if (pkg_b.repo == dgettext (null, "AUR")) {
			index_b = -1;
		} else if (pkg_b.repo != "") {
			unowned List<string>? element = repos_names.find_custom (pkg_b.repo, strcmp);
			if (element != null) {
				index_b = repos_names.index (element.data);
			}
		}
		if (index_a > index_b) {
			return 1;
		}
		if (index_b > index_a) {
			return -1;
		}
		return sort_pkgs_by_name (pkg_a, pkg_b);
	}

	int sort_pkgs_by_size (Package pkg_a, Package pkg_b) {
		if (pkg_a.installed_size > pkg_b.installed_size) {
			return -1;
		}
		if (pkg_b.installed_size > pkg_a.installed_size) {
			return 1;
		}
		return sort_pkgs_by_name (pkg_a, pkg_b);
	}

	int sort_aur_by_relevance (AURPackage pkg_a, AURPackage pkg_b) {
		if (pkg_a.name in to_build) {
			if (pkg_b.name in to_build) {
				return sort_aur_by_name (pkg_a, pkg_b);
			} else {
				return -1;
			}
		}
		if (pkg_b.name in to_build) {
			if (pkg_a.name in to_build) {
				return sort_aur_by_name (pkg_a, pkg_b);
			} else {
				return 1;
			}
		}
		if (pkg_a.popularity > pkg_b.popularity) {
			return -1;
		}
		if (pkg_b.popularity > pkg_a.popularity) {
			return 1;
		}
		return sort_aur_by_name (pkg_a, pkg_b);
	}

	int sort_aur_by_name (AURPackage pkg_a, AURPackage pkg_b) {
		return strcmp (pkg_a.name, pkg_b.name);
	}

	int sort_aur_by_date (AURPackage pkg_a, AURPackage pkg_b) {
		if (pkg_a.outofdate > pkg_b.outofdate) {
			return 1;
		}
		if (pkg_b.outofdate > pkg_a.outofdate) {
			return -1;
		}
		if (pkg_a.lastmodified > pkg_b.lastmodified) {
			return -1;
		}
		if (pkg_b.lastmodified > pkg_a.lastmodified) {
			return 1;
		}
		return sort_aur_by_name (pkg_a, pkg_b);
	}

	[GtkTemplate (ui = "/org/manjaro/pamac/manager/manager_window.ui")]
	class ManagerWindow : Gtk.ApplicationWindow {
		// icons
		Gtk.IconTheme icon_theme;
		Gdk.Pixbuf? package_icon;

		// manager objects
		[GtkChild]
		Gtk.HeaderBar headerbar;
		[GtkChild]
		public Gtk.Stack main_stack;
		[GtkChild]
		Gtk.StackSwitcher main_stack_switcher;
		[GtkChild]
		Gtk.Button button_back;
		[GtkChild]
		Gtk.Label header_filter_label;
		[GtkChild]
		Gtk.ModelButton preferences_button;
		[GtkChild]
		Gtk.ListBox packages_listbox;
		[GtkChild]
		Gtk.ListBox aur_listbox;
		[GtkChild]
		Gtk.Revealer sidebar_revealer;
		[GtkChild]
		Gtk.Stack filters_stack;
		[GtkChild]
		public Gtk.Stack browse_stack;
		[GtkChild]
		public Gtk.ToggleButton search_button;
		[GtkChild]
		Gtk.SearchBar searchbar;
		[GtkChild]
		public Gtk.ComboBoxText search_comboboxtext;
		[GtkChild]
		public Gtk.Entry search_entry;
		[GtkChild]
		Gtk.ListBox filters_listbox;
		[GtkChild]
		Gtk.ListBox categories_listbox;
		[GtkChild]
		Gtk.ListBox groups_listbox;
		[GtkChild]
		Gtk.ListBox installed_listbox;
		[GtkChild]
		Gtk.ListBox repos_listbox;
		[GtkChild]
		Gtk.Stack origin_stack;
		[GtkChild]
		Gtk.ListBox updates_listbox;
		[GtkChild]
		Gtk.ListBox pending_listbox;
		[GtkChild]
		Gtk.ListBox search_listbox;
		[GtkChild]
		Gtk.Button remove_all_button;
		[GtkChild]
		Gtk.Button install_all_button;
		[GtkChild]
		Gtk.Box sort_order_box;
		[GtkChild]
		Gtk.ComboBoxText sort_comboboxtext;
		[GtkChild]
		Gtk.ScrolledWindow packages_scrolledwindow;
		[GtkChild]
		Gtk.ScrolledWindow aur_scrolledwindow;
		[GtkChild]
		Gtk.Label updated_label;
		[GtkChild]
		Gtk.Label no_item_label;
		[GtkChild]
		Gtk.Label checking_label;
		[GtkChild]
		Gtk.Stack properties_stack;
		[GtkChild]
		Gtk.Box build_files_box;
		[GtkChild]
		Gtk.ListBox properties_listbox;
		[GtkChild]
		Gtk.Grid deps_grid;
		[GtkChild]
		Gtk.Grid details_grid;
		[GtkChild]
		Gtk.Label name_label;
		[GtkChild]
		Gtk.Image app_image;
		[GtkChild]
		Gtk.Image app_screenshot;
		[GtkChild]
		Gtk.Label desc_label;
		[GtkChild]
		Gtk.Label long_desc_label;
		[GtkChild]
		Gtk.Label link_label;
		[GtkChild]
		Gtk.Label licenses_label;
		[GtkChild]
		Gtk.Button launch_button;
		[GtkChild]
		Gtk.ToggleButton remove_togglebutton;
		[GtkChild]
		Gtk.ToggleButton reinstall_togglebutton;
		[GtkChild]
		Gtk.ToggleButton install_togglebutton;
		[GtkChild]
		Gtk.ToggleButton build_togglebutton;
		[GtkChild]
		Gtk.Button reset_files_button;
		[GtkChild]
		Gtk.TextView files_textview;
		[GtkChild]
		Gtk.Box transaction_infobox;
		[GtkChild]
		Gtk.Revealer transaction_infobox_revealer;
		[GtkChild]
		Gtk.Button details_button;
		[GtkChild]
		Gtk.Button apply_button;
		[GtkChild]
		Gtk.Button cancel_button;

		public Queue<string> display_package_queue;
		string current_package_displayed;
		string current_launchable;
		string current_files;
		string current_build_files;
		GenericSet<string?> previous_to_install;
		GenericSet<string?> previous_to_remove;
		GenericSet<string?> previous_to_build;

		public TransactionGtk transaction;
		public Database database { get; construct; }
		delegate void TransactionAction ();

		bool important_details;
		bool transaction_running;
		bool sysupgrade_running;
		bool generate_mirrors_list;
		bool waiting;
		bool force_refresh;

		List<Package> repos_updates;
		List<AURPackage> aur_updates;
		List<Package> current_packages_list;
		unowned List<Package> current_packages_list_pos;
		List<AURPackage> current_aur_list;
		unowned List<AURPackage> current_aur_list_pos;

		uint search_entry_timeout_id;
		Gtk.ListBoxRow files_row;
		Gtk.ListBoxRow build_files_row;
		bool scroll_to_top;
		string current_filter;

		public ManagerWindow (Gtk.Application application, Database database) {
			Object (application: application, database: database);
		}

		construct {
			unowned string? use_csd = Environment.get_variable ("GTK_CSD");
			if (use_csd == "0") {
				headerbar.show_close_button = false;
			}

			button_back.visible = false;
			remove_all_button.visible = false;
			install_all_button.visible = false;
			details_button.sensitive = false;
			scroll_to_top = true;
			searchbar.connect_entry (search_entry);
			important_details = false;
			transaction_running = false;
			sysupgrade_running  = false;
			generate_mirrors_list = false;

			updated_label.set_markup ("<big><b>%s</b></big>".printf (dgettext (null, "Your system is up-to-date")));
			no_item_label.set_markup ("<big><b>%s</b></big>".printf (dgettext (null, "No package found")));
			checking_label.set_markup ("<big><b>%s</b></big>".printf (dgettext (null, "Checking for Updates")));

			// auto complete list
			packages_scrolledwindow.vadjustment.value_changed.connect (() => {
				double max_value = (packages_scrolledwindow.vadjustment.upper - packages_scrolledwindow.vadjustment.page_size) * 0.8;
				if (packages_scrolledwindow.vadjustment.value >= max_value) {
					complete_packages_list ();
				}
			});
			packages_scrolledwindow.vadjustment.changed.connect (() => {
				while (need_more_packages ()) {
					complete_packages_list ();
				}
			});
			aur_scrolledwindow.vadjustment.value_changed.connect (() => {
				double max_value = (aur_scrolledwindow.vadjustment.upper - aur_scrolledwindow.vadjustment.page_size) * 0.8;
				if (aur_scrolledwindow.vadjustment.value >= max_value) {
					complete_aur_list ();
				}
			});
			aur_scrolledwindow.vadjustment.changed.connect (() => {
				while (need_more_aur ()) {
					complete_aur_list ();
				}
			});

			// packages listbox functions
			packages_listbox.set_header_func (set_header_func);
			aur_listbox.set_header_func (set_header_func);

			// icons
			icon_theme = Gtk.IconTheme.get_default ();
			icon_theme.changed.connect (update_icons);
			update_icons ();

			// database
			database.get_updates_progress.connect (on_get_updates_progress);
			database.refreshed.connect (() => {
				scroll_to_top = false;
				refresh_packages_list ();
			});
			create_all_listbox ();

			// transaction
			transaction = new TransactionGtk (database, this);
			transaction.start_preparing.connect (on_start_preparing);
			transaction.stop_preparing.connect (on_stop_preparing);
			transaction.start_downloading.connect (on_start_downloading);
			transaction.stop_downloading.connect (on_stop_downloading);
			transaction.start_building.connect (on_start_building);
			transaction.stop_building.connect (on_stop_building);
			transaction.important_details_outpout.connect (on_important_details_outpout);
			transaction.sysupgrade_finished.connect (on_transaction_finished);
			transaction.finished.connect (on_transaction_finished);
			transaction.write_pamac_config_finished.connect (on_write_pamac_config_finished);
			transaction.set_pkgreason_finished.connect (on_set_pkgreason_finished);
			transaction.start_generating_mirrors_list.connect (on_start_generating_mirrors_list);
			transaction.generate_mirrors_list_finished.connect (on_generate_mirrors_list_finished);
			transaction.transaction_sum_populated.connect (() => {
				// make buttons of pkgs in transaction unsensitive
				packages_listbox.foreach ((row) => {
					unowned PackageRow pamac_row = row as PackageRow;
					if (pamac_row == null) {
						return;
					}
					if (transaction.transaction_summary.contains (pamac_row.pkg.name)) {
						pamac_row.action_togglebutton.active = false;
						pamac_row.action_togglebutton.sensitive = false;
						pamac_row.action_togglebutton.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
						pamac_row.action_togglebutton.get_style_context ().remove_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
					}
				});
				aur_listbox.foreach ((row) => {
					unowned AURRow pamac_row = row as AURRow;
					if (pamac_row == null) {
						return;
					}
					if (transaction.transaction_summary.contains (pamac_row.aur_pkg.name)) {
						pamac_row.action_togglebutton.active = false;
						pamac_row.action_togglebutton.sensitive = false;
						pamac_row.action_togglebutton.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
						pamac_row.action_togglebutton.get_style_context ().remove_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
					}
				});
			});

			// integrate progress box and term widget
			main_stack.add_named (transaction.details_window, "term");
			transaction_infobox.pack_start (transaction.progress_box);
			// integrate build files notebook
			build_files_box.add (transaction.build_files_notebook);

			display_package_queue = new Queue<string> ();
			to_install = new GenericSet<string?> (str_hash, str_equal);
			to_remove = new GenericSet<string?> (str_hash, str_equal);
			to_load = new GenericSet<string?> (str_hash, str_equal);
			to_build = new GenericSet<string?> (str_hash, str_equal);
			previous_to_install = new GenericSet<string?> (str_hash, str_equal);
			previous_to_remove = new GenericSet<string?> (str_hash, str_equal);
			previous_to_build = new GenericSet<string?> (str_hash, str_equal);
			to_update = new GenericSet<string?> (str_hash, str_equal);
			temporary_ignorepkgs = new GenericSet<string?> (str_hash, str_equal);

			main_stack.notify["visible-child"].connect (on_main_stack_visible_child_changed);
			browse_stack.notify["visible-child"].connect (on_browse_stack_visible_child_changed);
			filters_stack.notify["visible-child"].connect (on_filters_stack_visible_child_changed);
			origin_stack.notify["visible-child"].connect (on_origin_stack_visible_child_changed);

			searchbar.notify["search-mode-enabled"].connect (on_search_mode_enabled);
			// enable "type to search"
			this.key_press_event.connect ((event) => {
				if (main_stack.visible_child_name == "browse"
					&& (browse_stack.visible_child_name == "browse"
					|| browse_stack.visible_child_name == "installed")) {
					return searchbar.handle_event (event);
				}
				return false;
			});

			// create screenshots tmp dir
			string screenshots_tmp_dir = "/tmp/pamac-app-screenshots";
			var file = GLib.File.new_for_path (screenshots_tmp_dir);
			if (!file.query_exists ()) {
				try {
					Process.spawn_command_line_sync ("mkdir -p %s".printf (screenshots_tmp_dir));
					Process.spawn_command_line_sync ("chmod -R a+w %s".printf (screenshots_tmp_dir));
				} catch (SpawnError e) {
					stderr.printf ("SpawnError: %s\n", e.message);
				}
			}
		}

		void set_header_func (Gtk.ListBoxRow row, Gtk.ListBoxRow? row_before) {
			row.set_header (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
		}

		void update_icons () {
			icon_theme = Gtk.IconTheme.get_default ();
			try {
				package_icon = icon_theme.load_icon ("package-x-generic", 64, 0);
			} catch (GLib.Error e) {
				stderr.printf ("%s\n", e.message);
			}
		}

		[GtkCallback]
		bool on_ManagerWindow_delete_event () {
			if (transaction_running || sysupgrade_running || generate_mirrors_list) {
				// do not close window
				return true;
			} else {
				// close window
				return false;
			}
		}

		void on_write_pamac_config_finished (bool recurse, uint64 refresh_period, bool no_update_hide_icon,
											bool enable_aur) {
			support_aur (enable_aur);
		}

		void on_set_pkgreason_finished () {
			transaction.unlock ();
			if (main_stack.visible_child_name == "details") {
				if (database.is_installed_pkg (current_package_displayed)
					|| database.is_sync_pkg (current_package_displayed)) {
					display_package_properties (current_package_displayed);
				} else {
					display_aur_properties (current_package_displayed);
				}
			}
		}

		void support_aur (bool enable_aur) {
			unowned Gtk.ListBoxRow aur_row = search_listbox.get_row_at_index (2);
			if (enable_aur) {
				aur_row.visible = true;
			} else {
				aur_row.visible = false;
				unowned Gtk.ListBoxRow installed_row = search_listbox.get_row_at_index (0);
				installed_row.activatable = true;
				installed_row.selectable = true;
				installed_row.can_focus = true;
				installed_row.get_child ().sensitive = true;
				search_listbox.select_row (installed_row);
				on_search_listbox_row_activated (search_listbox.get_selected_row ());
				unowned Gtk.ListBoxRow repos_row = search_listbox.get_row_at_index (1);
				repos_row.activatable = true;
				repos_row.selectable = true;
				repos_row.can_focus = true;
				repos_row.get_child ().sensitive = true;
			}
		}

		void hide_sidebar () {
			sidebar_revealer.set_reveal_child (false);
		}

		void show_sidebar () {
			sidebar_revealer.set_reveal_child (true);
		}

		void hide_transaction_infobox () {
			transaction_infobox_revealer.set_reveal_child (false);
		}

		void show_transaction_infobox () {
			transaction_infobox_revealer.set_reveal_child (true);
		}

		void try_lock_and_run (TransactionAction action) {
			if (transaction.get_lock ()) {
				action ();
			} else {
				waiting = true;
				transaction.progress_box.action_label.label = dgettext (null, "Waiting for another package manager to quit") + "...";
				transaction.start_progressbar_pulse ();
				apply_button.sensitive = false;
				cancel_button.sensitive = true;
				show_transaction_infobox ();
				Timeout.add (5000, () => {
					if (!waiting) {
						return false;
					}
					bool locked = transaction.get_lock ();
					if (locked) {
						waiting = false;
						transaction.stop_progressbar_pulse ();
						action ();
					}
					return !locked;
				});
			}
		}

		void set_pendings_operations () {
			if (!transaction_running && !generate_mirrors_list && !sysupgrade_running) {
				if (browse_stack.visible_child_name == "updates") {
					uint64 total_dsize = 0;
					packages_listbox.foreach ((row) => {
						unowned PackageRow pamac_row = row as PackageRow;
						if (pamac_row == null) {
							return;
						}
						if (to_update.contains (pamac_row.pkg.name)) {
							total_dsize += pamac_row.pkg.download_size;
						}
					});
					if (total_dsize > 0) {
						transaction.progress_box.action_label.set_markup("<b>%s: %s</b>".printf (dgettext (null, "Total download size"), format_size (total_dsize)));
					} else {
						transaction.progress_box.action_label.label = "";
					}
					if (!transaction_running && !generate_mirrors_list && !sysupgrade_running
						&& (to_update.length > 0)) {
						apply_button.sensitive = true;
					} else {
						apply_button.sensitive = false;
					}
					cancel_button.sensitive = false;
					show_transaction_infobox ();
				} else {
					uint total_pending = to_install.length + to_remove.length + to_build.length;
					if (total_pending == 0) {
						if (browse_stack.visible_child_name != "pending") {
							active_pending_stack (false);
						}
						transaction.progress_box.action_label.label = "";
						cancel_button.sensitive = false;
						apply_button.sensitive = false;
						if (important_details) {
							show_transaction_infobox ();
						}
					} else {
						active_pending_stack (true);
						string info = dngettext (null, "%u pending operation", "%u pending operations", total_pending).printf (total_pending);
						transaction.progress_box.action_label.label = info;
						cancel_button.sensitive = true;
						apply_button.sensitive = true;
						show_transaction_infobox ();
					}
				}
			}
		}

		void show_default_pkgs () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			current_filter = "installed_apps";
			database.get_installed_apps_async.begin ((obj, res) => {
				if (current_filter != "installed_apps") {
					return;
				}
				populate_packages_list (database.get_installed_apps_async.end (res));
			});
		}

		Gtk.ListBoxRow create_list_row (string str) {
			var label = new Gtk.Label (str);
			label.visible = true;
			label.margin = 12;
			label.xalign = 0;
			var row = new Gtk.ListBoxRow ();
			row.visible = true;
			row.add (label);
			return row;
		}

		int sort_list_row (Gtk.ListBoxRow row1, Gtk.ListBoxRow row2) {
			unowned Gtk.Label label1 = row1.get_child () as Gtk.Label;
			unowned Gtk.Label label2 = row2.get_child () as Gtk.Label;
			return strcmp (label1.label, label2.label);
		}

		void active_pending_stack (bool active) {
			pending_listbox.visible = active;
		}

		void create_all_listbox () {
			filters_listbox.add (create_list_row (dgettext (null, "Categories")));
			filters_listbox.add (create_list_row (dgettext (null, "Groups")));
			filters_listbox.add (create_list_row (dgettext (null, "Repositories")));

			repos_names = database.get_repos_names ();
			foreach (unowned string repo in repos_names) {
				repos_listbox.add (create_list_row (repo));
			}
			repos_listbox.select_row (repos_listbox.get_row_at_index (0));

			foreach (unowned string group in database.get_groups_names ()) {
				groups_listbox.add (create_list_row (group));
			}
			groups_listbox.set_sort_func (sort_list_row);
			groups_listbox.select_row (groups_listbox.get_row_at_index (0));

			installed_listbox.add (create_list_row (dgettext (null, "Installed")));
			installed_listbox.add (create_list_row (dgettext (null, "Explicitly installed")));
			installed_listbox.add (create_list_row (dgettext (null, "Orphans")));
			installed_listbox.add (create_list_row (dgettext (null, "Foreign")));
			installed_listbox.select_row (installed_listbox.get_row_at_index (0));

			categories_listbox.add (create_list_row (dgettext (null, "Accessories")));
			categories_listbox.add (create_list_row (dgettext (null, "Audio & Video")));
			categories_listbox.add (create_list_row (dgettext (null, "Development")));
			categories_listbox.add (create_list_row (dgettext (null, "Education")));
			categories_listbox.add (create_list_row (dgettext (null, "Games")));
			categories_listbox.add (create_list_row (dgettext (null, "Graphics")));
			categories_listbox.add (create_list_row (dgettext (null, "Internet")));
			categories_listbox.add (create_list_row (dgettext (null, "Office")));
			categories_listbox.add (create_list_row (dgettext (null, "Science")));
			categories_listbox.add (create_list_row (dgettext (null, "Settings")));
			categories_listbox.add (create_list_row (dgettext (null, "System Tools")));
			categories_listbox.set_sort_func (sort_list_row);
			categories_listbox.select_row (categories_listbox.get_row_at_index (0));

			updates_listbox.add (create_list_row (dgettext (null, "Repositories")));
			updates_listbox.add (create_list_row (dgettext (null, "AUR")));
			updates_listbox.select_row (updates_listbox.get_row_at_index (0));

			pending_listbox.add (create_list_row (dgettext (null, "Repositories")));
			pending_listbox.add (create_list_row (dgettext (null, "AUR")));
			pending_listbox.select_row (pending_listbox.get_row_at_index (0));
			active_pending_stack (false);

			search_listbox.add (create_list_row (dgettext (null, "Installed")));
			search_listbox.add (create_list_row (dgettext (null, "Repositories")));
			search_listbox.add (create_list_row (dgettext (null, "AUR")));
			search_listbox.select_row (search_listbox.get_row_at_index (0));
			if (database.config.enable_aur == false) {
				search_listbox.get_row_at_index (2).visible = false;
			}

			properties_listbox.add (create_list_row (dgettext (null, "Details")));
			properties_listbox.add (create_list_row (dgettext (null, "Dependencies")));
			files_row = create_list_row (dgettext (null, "Files"));
			properties_listbox.add (files_row);
			build_files_row = create_list_row (dgettext (null, "Build files"));
			properties_listbox.add (build_files_row);
			properties_listbox.select_row (properties_listbox.get_row_at_index (0));
		}

		void clear_packages_listbox () {
			packages_listbox.foreach (transaction.destroy_widget);
		}

		void clear_aur_listbox () {
			aur_listbox.foreach (transaction.destroy_widget);
		}

		void clear_lists () {
			to_install.remove_all ();
			to_remove.remove_all ();
			to_build.remove_all ();
			to_load.remove_all ();
		}

		void clear_previous_lists () {
			previous_to_install.remove_all ();
			previous_to_remove.remove_all ();
			previous_to_build.remove_all ();
		}

		void on_mark_explicit_button_clicked (Gtk.Button button) {
			if (transaction.get_lock ()) {
				transaction.start_set_pkgreason (current_package_displayed, 0); //Alpm.Package.Reason.EXPLICIT
			}
		}

		Gtk.Widget populate_details_grid (string detail_type, string detail, Gtk.Widget? previous_widget) {
			var label = new Gtk.Label ("<b>%s:</b>".printf (detail_type));
			label.use_markup = true;
			label.halign = Gtk.Align.START;
			label.valign = Gtk.Align.START;
			details_grid.attach_next_to (label, previous_widget, Gtk.PositionType.BOTTOM);
			if (!transaction_running
				&& !sysupgrade_running
				&& detail_type == dgettext (null, "Install Reason")
				&& detail == dgettext (null, "Installed as a dependency for another package")) {
				var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
				box.homogeneous = false;
				var label2 = new Gtk.Label (detail);
				label2.halign = Gtk.Align.START;
				box.pack_start (label2, false);
				var mark_explicit_button = new Gtk.Button.with_label (dgettext (null, "Mark as explicitly installed"));
				mark_explicit_button.halign = Gtk.Align.START;
				mark_explicit_button.clicked.connect (on_mark_explicit_button_clicked);
				box.pack_start (mark_explicit_button, false);
				details_grid.attach_next_to (box, label, Gtk.PositionType.RIGHT);
			} else {
				var label2 = new Gtk.Label (detail);
				label2.use_markup = true;
				label2.halign = Gtk.Align.START;
				details_grid.attach_next_to (label2, label, Gtk.PositionType.RIGHT);
			}
			return label as Gtk.Widget;
		}

		string find_install_button_dep_name (Gtk.Button button) {
			string dep_name = "";
			Gtk.Container container = button.get_parent ();
			container.foreach ((widget) => {
				if (widget.name == "GtkButton") {
					unowned Gtk.Button dep_button = widget as Gtk.Button;
					Package pkg = database.find_sync_satisfier (dep_button.label);
					if (pkg.name != "") {
						dep_name = pkg.name;
					}
				}
			});
			return dep_name;
		}

		void on_install_dep_button_toggled (Gtk.ToggleButton button) {
			string dep_name = find_install_button_dep_name (button);
			if (button.active) {
				button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				to_install.add (dep_name);
			} else {
				button.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				to_install.remove (dep_name);
			}
			set_pendings_operations ();
		}

		Gtk.Widget populate_dep_grid (string dep_type, List<string> dep_list, Gtk.Widget? previous_widget, bool add_install_button = false) {
			var label = new Gtk.Label ("<b>%s:</b>".printf (dep_type));
			label.use_markup = true;
			label.halign = Gtk.Align.START;
			label.valign = Gtk.Align.START;
			label.margin_top = 6;
			deps_grid.attach_next_to (label, previous_widget, Gtk.PositionType.BOTTOM);
			var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
			box.hexpand = true;
			foreach (unowned string dep in dep_list) {
				if (add_install_button) {
					var box2 = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
					box2.homogeneous = false;
					var dep_button = new Gtk.Button.with_label (dep);
					dep_button.relief = Gtk.ReliefStyle.NONE;
					dep_button.valign = Gtk.Align.CENTER;
					dep_button.clicked.connect (on_dep_button_clicked);
					box2.pack_start (dep_button, false);
					if (database.find_installed_satisfier (dep).name == "") {
						var install_dep_button = new Gtk.ToggleButton.with_label (dgettext (null, "Install"));
						install_dep_button.margin = 3;
						install_dep_button.toggled.connect (on_install_dep_button_toggled);
						box2.pack_end (install_dep_button, false);
						string dep_name = find_install_button_dep_name (install_dep_button);
						install_dep_button.active = (dep_name in to_install); 
					}
					box.pack_start (box2);
				} else {
					var dep_button = new Gtk.Button.with_label (dep);
					dep_button.relief = Gtk.ReliefStyle.NONE;
					dep_button.halign = Gtk.Align.START;
					dep_button.valign = Gtk.Align.CENTER;
					dep_button.clicked.connect (on_dep_button_clicked);
					box.pack_start (dep_button, false);
				}
			}
			deps_grid.attach_next_to (box, label, Gtk.PositionType.RIGHT);
			return label as Gtk.Widget;
		}

		async Gdk.Pixbuf get_screenshot_pixbuf (string url) {
			var uri = File.new_for_uri (url);
			var cached_screenshot = File.new_for_path ("/tmp/pamac-app-screenshots/%s".printf (uri.get_basename ()));
			Gdk.Pixbuf pixbuf = null;
			if (cached_screenshot.query_exists ()) {
				try {
					pixbuf = new Gdk.Pixbuf.from_file (cached_screenshot.get_path ());
				} catch (GLib.Error e) {
					stderr.printf ("%s: %s\n", url, e.message);
				}
			} else {
				// download screenshot
				var session = new Soup.Session ();
				var utsname = Posix.utsname();
				session.user_agent = "pamac (%s %s)".printf (utsname.sysname, utsname.machine);
				try {
					var request = session.request (url);
					try {
						var inputstream = yield request.send_async (null);
						pixbuf = new Gdk.Pixbuf.from_stream (inputstream);
						// scale pixbux at a width of 600 pixels
						int width = pixbuf.get_width ();
						if (width > 600) {
							float ratio = (float) width / (float) pixbuf.get_height ();
							int new_height = (int) (600 / ratio);
							pixbuf = pixbuf.scale_simple (600, new_height, Gdk.InterpType.BILINEAR);
						}
						// save scaled image in tmp
						FileOutputStream os = cached_screenshot.append_to (FileCreateFlags.NONE);
						pixbuf.save_to_stream (os, "png");
					} catch (GLib.Error e) {
						stderr.printf ("%s: %s\n", url, e.message);
					}
				} catch (GLib.Error e) {
					stderr.printf ("%s: %s\n", url, e.message);
				}
			}
			return pixbuf;
		}

		async void set_package_details (string pkgname, string app_name, bool sync_pkg) {
			PackageDetails details = database.get_pkg_details (pkgname, app_name, sync_pkg);
			// download screenshot
			app_screenshot.pixbuf = null;
			if (details.screenshot != "") {
				get_screenshot_pixbuf.begin (details.screenshot, (obj, res) => {
					var pixbuf = get_screenshot_pixbuf.end (res);
					app_screenshot.pixbuf = pixbuf;
				});
			}
			// infos
			if (details.app_name == "") {
				name_label.set_markup ("<big><b>%s  %s</b></big>".printf (details.name, details.version));
				app_image.pixbuf = package_icon;
			} else {
				name_label.set_markup ("<big><b>%s (%s)  %s</b></big>".printf (Markup.escape_text (details.app_name), details.name, details.version));
				if (details.icon != "") {
					try {
						var pixbuf = new Gdk.Pixbuf.from_file (details.icon);
						app_image.pixbuf = pixbuf;
					} catch (GLib.Error e) {
						// some icons are not in the right repo
						string icon = details.icon;
						if ("extra" in details.icon) {
							icon = details.icon.replace ("extra", "community");
						} else if ("community" in details.icon) {
							icon = details.icon.replace ("community", "extra");
						}
						try {
							var pixbuf = new Gdk.Pixbuf.from_file (icon);
							app_image.pixbuf = pixbuf;
						} catch (GLib.Error e) {
							app_image.pixbuf = package_icon;
							stderr.printf ("%s: %s\n", details.icon, e.message);
						}
					}
				} else {
					app_image.pixbuf = package_icon;
				}
			}
			desc_label.set_text (details.desc);
			if (details.long_desc == "") {
				long_desc_label.visible = false;
			} else {
				long_desc_label.set_text (details.long_desc);
				long_desc_label.visible = true;
			}
			string escaped_url = Markup.escape_text (details.url);
			link_label.set_markup ("<a href=\"%s\">%s</a>".printf (escaped_url, escaped_url));
			StringBuilder licenses = new StringBuilder ();
			licenses.append (dgettext (null, "Licenses"));
			licenses.append (":");
			foreach (unowned string license in details.licenses) {
				licenses.append (" ");
				licenses.append (license);
			}
			licenses_label.set_text (licenses.str);
			if (details.installed_version != "") {
				if (details.launchable != "") {
					launch_button.visible = true;
					current_launchable = details.launchable;
				}
				install_togglebutton.visible = false;
				build_togglebutton.visible = false;
				reset_files_button.visible = false;
				reinstall_togglebutton.visible = false;
				remove_togglebutton.visible = true;
				if (database.should_hold (pkgname)) {
					remove_togglebutton.sensitive = false;
				} else {
					remove_togglebutton.sensitive = true;
					remove_togglebutton.active = to_remove.contains (details.name);
					Package find_pkg = database.get_sync_pkg (details.name);
					if (find_pkg.name != "") {
						if (find_pkg.version == details.version) {
							reinstall_togglebutton.visible = true;
							reinstall_togglebutton.active = to_install.contains (details.name);
						}
					} else {
						AURPackage aur_pkg = yield database.get_aur_pkg (details.name);
						if (aur_pkg.name != "") {
							// always show reinstall button for VCS package
							if (aur_pkg.name.has_suffix ("-git") ||
								aur_pkg.name.has_suffix ("-svn") ||
								aur_pkg.name.has_suffix ("-bzr") ||
								aur_pkg.name.has_suffix ("-hg") ||
								aur_pkg.version == details.version) {
								build_togglebutton.visible = true;
								build_togglebutton.active = to_build.contains (details.name);
							}
							build_files_row.visible = true;
							string aur_url = "http://aur.archlinux.org/packages/" + details.name;
							link_label.set_markup ("<a href=\"%s\">%s</a>\n\n<a href=\"%s\">%s</a>".printf (escaped_url, escaped_url, aur_url, aur_url));
						}
					}
				}
			} else {
				launch_button.visible = false;
				remove_togglebutton.visible = false;
				reinstall_togglebutton.visible = false;
				build_togglebutton.visible = false;
				reset_files_button.visible = false;
				install_togglebutton.visible = true;
				install_togglebutton.active = to_install.contains (details.name);
			}
			// details
			details_grid.foreach (transaction.destroy_widget);
			Gtk.Widget? previous_widget = null;
			if (details.repo != "") {
				previous_widget = populate_details_grid (dgettext (null, "Repository"), details.repo, previous_widget);
			}
			if (details.repo == dgettext (null, "AUR")) {
				AURPackageDetails aur_pkg_details = yield database.get_aur_pkg_details (details.name);
				if (aur_pkg_details.packagebase != details.name) {
					previous_widget = populate_details_grid (dgettext (null, "Package Base"), aur_pkg_details.packagebase, previous_widget);
				}
				if (aur_pkg_details.maintainer != "") {
					previous_widget = populate_details_grid (dgettext (null, "Maintainer"), aur_pkg_details.maintainer, previous_widget);
				}
				if (aur_pkg_details.firstsubmitted != 0) {
					var time = GLib.Time.local ((time_t) aur_pkg_details.firstsubmitted);
					previous_widget = populate_details_grid (dgettext (null, "First Submitted"), time.format ("%x"), previous_widget);
				}
				if (aur_pkg_details.lastmodified != 0) {
					var time = GLib.Time.local ((time_t) aur_pkg_details.lastmodified);
					previous_widget = populate_details_grid (dgettext (null, "Last Modified"), time.format ("%x"), previous_widget);
				}
				if (aur_pkg_details.numvotes != 0) {
					previous_widget = populate_details_grid (dgettext (null, "Votes"), aur_pkg_details.numvotes.to_string (), previous_widget);
				}
				if (aur_pkg_details.outofdate != 0) {
					var time = GLib.Time.local ((time_t) aur_pkg_details.outofdate);
					previous_widget = populate_details_grid (dgettext (null, "Out of Date"), time.format ("%x"), previous_widget);
				}
			}
			if (details.groups.length () > 0) {
				var label = new Gtk.Label ("<b>%s</b>".printf (dgettext (null, "Groups") + ":"));
				label.use_markup = true;
				label.halign = Gtk.Align.START;
				label.valign = Gtk.Align.START;
				details_grid.attach_next_to (label, previous_widget, Gtk.PositionType.BOTTOM);
				var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
				foreach (unowned string name in details.groups) {
					var label2 = new Gtk.Label (name);
					label2.halign = Gtk.Align.START;
					box.pack_start (label2);
				}
				details_grid.attach_next_to (box, label, Gtk.PositionType.RIGHT);
				previous_widget = label as Gtk.Widget;
			}
			// make packager mail clickable
			string[] splitted = details.packager.split ("<", 2);
			string packager_name = splitted[0];
			if (splitted.length > 1) {
				string packager_mail = splitted[1].split (">", 2)[0];
				string packager_detail = "%s <a href=\"mailto:%s\">%s</a>".printf (packager_name, packager_mail, packager_mail);
				previous_widget = populate_details_grid (dgettext (null, "Packager"), packager_detail, previous_widget);
			} else {
				previous_widget = populate_details_grid (dgettext (null, "Packager"), details.packager, previous_widget);
			}
			var time = GLib.Time.local ((time_t) details.builddate);
			previous_widget = populate_details_grid (dgettext (null, "Build Date"), time.format ("%x"), previous_widget);
			if (details.installdate != 0) {
				time = GLib.Time.local ((time_t) details.installdate);
				previous_widget = populate_details_grid (dgettext (null, "Install Date"), time.format ("%x"), previous_widget);
			}
			if (details.reason != "") {
				previous_widget = populate_details_grid (dgettext (null, "Install Reason"), details.reason, previous_widget);
			}
			if (details.has_signature != "") {
				previous_widget = populate_details_grid (dgettext (null, "Signatures"), details.has_signature, previous_widget);
			}
			if (details.backups.length () > 0) {
				var label = new Gtk.Label ("<b>%s</b>".printf (dgettext (null, "Backup files") + ":"));
				label.use_markup = true;
				label.halign = Gtk.Align.START;
				label.valign = Gtk.Align.START;
				details_grid.attach_next_to (label, previous_widget, Gtk.PositionType.BOTTOM);
				var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
				foreach (unowned string name in details.backups) {
					var label2 = new Gtk.Label (name);
					label2.halign = Gtk.Align.START;
					box.pack_start (label2);
				}
				details_grid.attach_next_to (box, label, Gtk.PositionType.RIGHT);
			}
			details_grid.show_all ();
			// deps
			deps_grid.foreach (transaction.destroy_widget);
			previous_widget = null;
			if (details.depends.length () > 0) {
				previous_widget = populate_dep_grid (dgettext (null, "Depends On"), details.depends, previous_widget);
			}
			if (details.optdepends.length () > 0) {
				previous_widget = populate_dep_grid (dgettext (null, "Optional Dependencies"), details.optdepends, previous_widget, true);
			}
			if (details.requiredby.length () > 0) {
				previous_widget = populate_dep_grid (dgettext (null, "Required By"), details.requiredby, previous_widget);
			}
			if (details.optionalfor.length () > 0) {
				previous_widget = populate_dep_grid (dgettext (null, "Optional For"), details.optionalfor, previous_widget);
			}
			if (details.provides.length () > 0) {
				var label = new Gtk.Label ("<b>%s</b>".printf (dgettext (null, "Provides") + ":"));
				label.use_markup = true;
				label.halign = Gtk.Align.START;
				label.valign = Gtk.Align.START;
				label.margin_top = 6;
				deps_grid.attach_next_to (label, previous_widget, Gtk.PositionType.BOTTOM);
				var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
				box.margin = 3;
				foreach (unowned string name in details.provides) {
					var label2 = new Gtk.Label (name);
					label2.halign = Gtk.Align.START;
					label2.margin_start = 12;
					box.pack_start (label2);
				}
				deps_grid.attach_next_to (box, label, Gtk.PositionType.RIGHT);
				previous_widget = label as Gtk.Widget;
			}
			if (details.replaces.length () > 0) {
				previous_widget = populate_dep_grid (dgettext (null, "Replaces"), details.replaces, previous_widget);
			}
			if (details.conflicts.length () > 0) {
				previous_widget = populate_dep_grid (dgettext (null, "Conflicts With"), details.conflicts, previous_widget);
			}
			deps_grid.show_all ();
			// files
			// will be populated on properties_stack switch
			if (properties_stack.visible_child_name == "files") {
				properties_listbox.get_row_at_index (2).activate ();
			}
		}

		async void set_aur_details (string pkgname) {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			AURPackageDetails details = yield database.get_aur_pkg_details (pkgname);
			app_screenshot.pixbuf = null;
			reinstall_togglebutton.visible = false;
			install_togglebutton.visible = false;
			reset_files_button.visible = false;
			// infos
			name_label.set_markup ("<big><b>%s  %s</b></big>".printf (details.name, details.version));
			app_image.pixbuf = package_icon;
			desc_label.set_text (details.desc);
			long_desc_label.visible = false;
			string aur_url = "http://aur.archlinux.org/packages/" + details.name;
			string escaped_url = Markup.escape_text (details.url);
			link_label.set_markup ("<a href=\"%s\">%s</a>\n\n<a href=\"%s\">%s</a>".printf (escaped_url, escaped_url, aur_url, aur_url));
			StringBuilder licenses = new StringBuilder ();
			licenses.append (dgettext (null, "Licenses"));
			licenses.append (":");
			foreach (unowned string license in details.licenses) {
				licenses.append (" ");
				licenses.append (license);
			}
			licenses_label.set_text (licenses.str);
			build_togglebutton.visible = true;
			build_togglebutton.active = to_build.contains (details.name);
			if (database.is_installed_pkg (details.name)) {
				remove_togglebutton.visible = true;
				remove_togglebutton.active = to_remove.contains (details.name);
			}
			// details
			properties_listbox.visible = true;
			details_grid.foreach (transaction.destroy_widget);
			Gtk.Widget? previous_widget = null;
			if (details.packagebase != details.name) {
				previous_widget = populate_details_grid (dgettext (null, "Package Base"), details.packagebase, previous_widget);
			}
			if (details.maintainer != "") {
				previous_widget = populate_details_grid (dgettext (null, "Maintainer"), details.maintainer, previous_widget);
			}
			var time = GLib.Time.local ((time_t) details.firstsubmitted);
			previous_widget = populate_details_grid (dgettext (null, "First Submitted"), time.format ("%x"), previous_widget);
			time = GLib.Time.local ((time_t) details.lastmodified);
			previous_widget = populate_details_grid (dgettext (null, "Last Modified"), time.format ("%x"), previous_widget);
			previous_widget = populate_details_grid (dgettext (null, "Votes"), details.numvotes.to_string (), previous_widget);
			if (details.outofdate != 0) {
				time = GLib.Time.local ((time_t) details.outofdate);
				previous_widget = populate_details_grid (dgettext (null, "Out of Date"), time.format ("%x"), previous_widget);
			}
			details_grid.show_all ();
			// deps
			previous_widget = null;
			if (details.depends.length () > 0) {
				previous_widget = populate_dep_grid (dgettext (null, "Depends On"), details.depends, previous_widget);
			}
			if (details.makedepends.length () > 0) {
				previous_widget = populate_dep_grid (dgettext (null, "Make Dependencies"), details.makedepends, previous_widget);
			}
			if (details.checkdepends.length () > 0) {
				previous_widget = populate_dep_grid (dgettext (null, "Check Dependencies"), details.checkdepends, previous_widget);
			}
			if (details.optdepends.length () > 0) {
				previous_widget = populate_dep_grid (dgettext (null, "Optional Dependencies"), details.optdepends, previous_widget);
			}
			if (details.provides.length () > 0) {
				var label = new Gtk.Label ("<b>%s</b>".printf (dgettext (null, "Provides") + ":"));
				label.use_markup = true;
				label.halign = Gtk.Align.START;
				label.valign = Gtk.Align.START;
				label.margin_top = 6;
				deps_grid.attach_next_to (label, previous_widget, Gtk.PositionType.BOTTOM);
				var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
				box.margin = 3;
				foreach (unowned string name in details.provides) {
					var label2 = new Gtk.Label (name);
					label2.halign = Gtk.Align.START;
					label2.margin_start = 12;
					box.pack_start (label2);
				}
				deps_grid.attach_next_to (box, label, Gtk.PositionType.RIGHT);
				previous_widget = label as Gtk.Widget;
			}
			if (details.replaces.length () > 0) {
				previous_widget = populate_dep_grid (dgettext (null, "Replaces"), details.replaces, previous_widget);
			}
			if (details.conflicts.length () > 0) {
				previous_widget = populate_dep_grid (dgettext (null, "Conflicts With"), details.conflicts, previous_widget);
			}
			deps_grid.show_all ();
			this.get_window ().set_cursor (null);
			// build files
			// will be populated on properties_stack switch
			if (properties_stack.visible_child_name == "build_files") {
				properties_listbox.get_row_at_index (3).activate ();
			}
		}

		[GtkCallback]
		void on_properties_listbox_row_activated (Gtk.ListBoxRow row) {
			int index = row.get_index ();
			switch (index) {
				case 0: // details
					reset_files_button.visible = false;
					properties_stack.visible_child_name = "details";
					break;
				case 1: // deps
					reset_files_button.visible = false;
					properties_stack.visible_child_name = "deps";
					break;
				case 2: // files
					reset_files_button.visible = false;
					if (current_files != current_package_displayed) {
						this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
						database.get_pkg_files_async.begin (current_package_displayed, (obj, res) => {
							var files = database.get_pkg_files_async.end (res);
							StringBuilder text = new StringBuilder ();
							foreach (unowned string file in files) {
								if (text.len > 0) {
									text.append ("\n");
								}
								text.append (file);
							}
							files_textview.buffer.set_text (text.str, (int) text.len);
							properties_stack.visible_child_name = "files";
							this.get_window ().set_cursor (null);
						});
						current_files = current_package_displayed;
					} else {
						properties_stack.visible_child_name = "files";
					}
					break;
				case 3: // build files
					reset_files_button.visible = true;
					if (current_build_files != current_package_displayed) {
						this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
						database.get_aur_pkg.begin (current_package_displayed, (obj, res) => {
							AURPackage pkg = database.get_aur_pkg.end (res);
							transaction.populate_build_files.begin (pkg.packagebase, true, false, () => {
								properties_stack.visible_child_name = "build_files";
							});
							this.get_window ().set_cursor (null);
						});
						current_build_files = current_package_displayed;
					} else {
						properties_stack.visible_child_name = "build_files";
					}
					break;
				default:
					break;
			}
		}

		[GtkCallback]
		void on_launch_button_clicked () {
			try {
				Process.spawn_command_line_sync ("gtk-launch %s".printf (current_launchable));
			} catch (SpawnError e) {
				stderr.printf ("SpawnError: %s\n", e.message);
			}
		}

		[GtkCallback]
		void on_install_togglebutton_toggled () {
			if (install_togglebutton.active) {
				install_togglebutton.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				to_install.add (current_package_displayed);
			} else {
				install_togglebutton.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				to_install.remove (current_package_displayed);
			}
			set_pendings_operations ();
		}

		[GtkCallback]
		void on_build_togglebutton_toggled () {
			if (build_togglebutton.active) {
				build_togglebutton.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				to_build.add (current_package_displayed);
				if (properties_stack.visible_child_name == "build_files") {
					transaction.save_build_files.begin (current_package_displayed);
				}
			} else {
				build_togglebutton.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				to_build.remove (current_package_displayed);
			}
			set_pendings_operations ();
		}

		[GtkCallback]
		void on_reset_files_button_clicked () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			database.get_aur_pkg.begin (current_package_displayed, (obj, res) => {
				AURPackage pkg = database.get_aur_pkg.end (res);
				transaction.populate_build_files.begin (pkg.packagebase, true, true);
				this.get_window ().set_cursor (null);
			});
		}

		[GtkCallback]
		void on_remove_togglebutton_toggled () {
			if (remove_togglebutton.active) {
				reinstall_togglebutton.active = false;
				reinstall_togglebutton.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				remove_togglebutton.get_style_context ().add_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
				to_install.remove (current_package_displayed);
				to_remove.add (current_package_displayed);
			} else {
				remove_togglebutton.get_style_context ().remove_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
				to_remove.remove (current_package_displayed);
			}
			set_pendings_operations ();
		}

		[GtkCallback]
		void on_reinstall_togglebutton_toggled () {
			if (reinstall_togglebutton.active) {
				remove_togglebutton.active = false;
				remove_togglebutton.get_style_context ().remove_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
				reinstall_togglebutton.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				to_remove.remove (current_package_displayed);
				if (database.is_sync_pkg (current_package_displayed)) {
					to_install.add (current_package_displayed);
				} else {
					// availability in AUR was checked in set_package_details
					to_build.add (current_package_displayed);
				}
			} else {
				reinstall_togglebutton.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				to_install.remove (current_package_displayed);
				to_build.remove (current_package_displayed);
			}
			set_pendings_operations ();
		}

		void sort_packages_list () {
			int sort_index = sort_comboboxtext.active;
			switch (sort_index) {
				case 0: // relevance
					if (browse_stack.visible_child_name != "search") {
						current_packages_list.sort (sort_pkgs_by_relevance);
					}
					break;
				case 1: // name
					current_packages_list.sort (sort_pkgs_by_name);
					break;
				case 2: // date
					current_packages_list.sort (sort_pkgs_by_date);
					break;
				case 3: // repository
					current_packages_list.sort (sort_pkgs_by_repo);
					break;
				case 4: // size
					current_packages_list.sort (sort_pkgs_by_size);
					break;
				default:
					break;
			}
		}

		void populate_packages_list (owned List<Package> pkgs) {
			// populate listbox
			if (pkgs.length () == 0) {
				origin_stack.visible_child_name = "no_item";
				this.get_window ().set_cursor (null);
				return;
			} else {
				packages_listbox.freeze_child_notify ();
				clear_packages_listbox ();
				packages_listbox.thaw_child_notify ();
				origin_stack.visible_child_name = "repos";
			}
			current_packages_list = (owned) pkgs;
			sort_packages_list ();
			current_packages_list_pos = current_packages_list;
			do {
				complete_packages_list ();
			} while (need_more_packages ());
			// scroll to top
			if (scroll_to_top) {
				packages_scrolledwindow.vadjustment.value = 0;
			} else {
				// don't scroll to top just once
				scroll_to_top = true;
			}
			this.get_window ().set_cursor (null);
		}

		bool need_more_packages () {
			if (current_packages_list_pos != null) {
				int natural_height;
				packages_listbox.get_preferred_height (null, out natural_height);
				if (packages_scrolledwindow.vadjustment.page_size > natural_height) {
					return true;
				}
			}
			return false;
		}

		void complete_packages_list () {
			if (current_packages_list_pos != null) {
				packages_listbox.freeze_child_notify ();
				uint i = 0;
				// display the next 20 packages
				while (i < 20) {
					var pkg = current_packages_list_pos.data;
					create_packagelist_row (pkg);
					i++;
					current_packages_list_pos = current_packages_list_pos.next;
					if (current_packages_list_pos == null) {
						// add an empty row to have an ending separator
						var row = new Gtk.ListBoxRow ();
						row.visible = true;
						packages_listbox.add (row);
						break;
					}
				}
				packages_listbox.thaw_child_notify ();
			}
		}

		void create_packagelist_row (Package pkg) {
			bool is_update = browse_stack.visible_child_name == "updates";
			var row = new PackageRow (pkg);
			//populate info
			if (pkg.app_name == "") {
				row.name_label.set_markup ("<b>%s</b>".printf (pkg.name));
			} else {
				row.name_label.set_markup ("<b>%s  (%s)</b>".printf (Markup.escape_text (pkg.app_name), pkg.name));
			}
			row.desc_label.label = pkg.desc;
			if (is_update) {
				var label = new Gtk.Label (pkg.version);
				label.visible = true;
				label.width_chars = 10;
				label.max_width_chars = 10;
				label.ellipsize = Pango.EllipsizeMode.END;
				label.xalign = 0;
				row.version_box.pack_start (label);
				label = new Gtk.Label ("(%s)".printf (pkg.installed_version));
				label.visible = true;
				label.width_chars = 10;
				label.max_width_chars = 10;
				label.ellipsize = Pango.EllipsizeMode.END;
				label.xalign = 0;
				row.version_box.pack_start (label);
				row.size_label.label = pkg.download_size == 0 ? "" : GLib.format_size (pkg.download_size);
			} else {
				var label = new Gtk.Label (pkg.version);
				label.visible = true;
				label.width_chars = 10;
				label.max_width_chars = 10;
				label.ellipsize = Pango.EllipsizeMode.END;
				label.xalign = 0;
				row.version_box.pack_start (label);
				row.size_label.label = GLib.format_size (pkg.installed_size);
			}
			row.repo_label.label = pkg.repo;
			Gdk.Pixbuf pixbuf;
			if (pkg.icon != "") {
				try {
					pixbuf = new Gdk.Pixbuf.from_file_at_scale (pkg.icon, 32, 32, true);
				} catch (GLib.Error e) {
					// some icons are not in the right repo
					string icon = pkg.icon;
					if ("extra" in pkg.icon) {
						icon = pkg.icon.replace ("extra", "community");
					} else if ("community" in pkg.icon) {
						icon = pkg.icon.replace ("community", "extra");
					}
					try {
						pixbuf = new Gdk.Pixbuf.from_file_at_scale (icon, 32, 32, true);
					} catch (GLib.Error e) {
						pixbuf = package_icon.scale_simple (32, 32, Gdk.InterpType.BILINEAR);
						stderr.printf ("%s: %s\n", pkg.icon, e.message);
					}
				}
			} else {
				pixbuf = package_icon.scale_simple (32, 32, Gdk.InterpType.BILINEAR);
			}
			row.app_icon.pixbuf = pixbuf;
			row.details_button.clicked.connect (() => {
				on_packages_listbox_row_activated (row);
			});
			if (transaction.transaction_summary.contains (pkg.name)) {
				row.action_togglebutton.sensitive = false;
			}
			if (pkg.installed_version == "") {
				row.action_togglebutton.label = dgettext (null, "Install");
				if (pkg.name in to_install) {
					row.action_togglebutton.active = true;
					row.action_togglebutton.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				}
				row.action_togglebutton.toggled.connect ((button) => {
					if (button.active) {
						to_install.add (pkg.name);
					} else {
						to_install.remove (pkg.name);
					}
					refresh_listbox_buttons ();
					set_pendings_operations ();
				});
			} else if (is_update) {
				row.action_togglebutton.label = dgettext (null, "Upgrade");
				row.action_togglebutton.active = true;
				row.action_togglebutton.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				row.action_togglebutton.toggled.connect ((button) => {
					if (button.active) {
						to_update.add (pkg.name);
						temporary_ignorepkgs.remove (pkg.name);
					} else {
						to_update.remove (pkg.name);
						temporary_ignorepkgs.add (pkg.name);
					}
					refresh_listbox_buttons ();
					set_pendings_operations ();
				});
			} else {
				row.action_togglebutton.label = dgettext (null, "Remove");
				if (database.should_hold (pkg.name)) {
					row.action_togglebutton.sensitive = false;
				} else if (pkg.name in to_remove) {
					row.action_togglebutton.get_style_context ().add_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
					row.action_togglebutton.active = true;
				}
				row.action_togglebutton.toggled.connect ((button) => {
					if (button.active) {
						to_install.remove (pkg.name);
						to_remove.add (pkg.name);
					} else {
						to_remove.remove (pkg.name);
					}
					refresh_listbox_buttons ();
					set_pendings_operations ();
				});
			}
			// insert
			packages_listbox.add (row);
		}

		void refresh_listbox_buttons () {
			packages_listbox.foreach ((row) => {
				unowned PackageRow pamac_row = row as PackageRow;
				if (pamac_row == null) {
					return;
				}
				unowned string pkgname = pamac_row.pkg.name;
				if (!database.should_hold (pkgname)) {
					pamac_row.action_togglebutton.sensitive = true;
				}
				if (pkgname in to_install) {
					pamac_row.action_togglebutton.active = true;
					pamac_row.action_togglebutton.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				} else if (pkgname in to_remove) {
					pamac_row.action_togglebutton.active = true;
					pamac_row.action_togglebutton.get_style_context ().add_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
				} else if (pkgname in to_update) {
					pamac_row.action_togglebutton.active = true;
					pamac_row.action_togglebutton.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				} else if (pkgname in temporary_ignorepkgs) {
					pamac_row.action_togglebutton.active = false;
					pamac_row.action_togglebutton.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				} else {
					pamac_row.action_togglebutton.active = false;
					pamac_row.action_togglebutton.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
					pamac_row.action_togglebutton.get_style_context ().remove_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
				}
			});
		}

		void sort_aur_list () {
			int sort_index = sort_comboboxtext.active;
			switch (sort_index) {
				case 0: // relevance
					current_aur_list.sort (sort_aur_by_relevance);
					break;
				case 1: // name
					current_aur_list.sort (sort_aur_by_name);
					break;
				case 2: // date
					current_aur_list.sort (sort_aur_by_date);
					break;
				default:
					break;
			}
		}

		async void populate_aur_list (owned List<AURPackage> pkgs) {
			// populate listbox
			if (pkgs.length () == 0) {
				origin_stack.visible_child_name = "no_item";
				this.get_window ().set_cursor (null);
				return;
			} else {
				aur_listbox.freeze_child_notify ();
				clear_aur_listbox ();
				aur_listbox.thaw_child_notify ();
				origin_stack.visible_child_name = "aur";
			}
			current_aur_list = (owned) pkgs;
			sort_aur_list ();
			current_aur_list_pos = current_aur_list;
			do {
				complete_aur_list ();
			} while (need_more_aur ());
			// scroll to top
			if (scroll_to_top) {
				aur_scrolledwindow.vadjustment.value = 0;
			} else {
				// don't scroll to top just once
				scroll_to_top = true;
			}
			this.get_window ().set_cursor (null);
			// get aur details to save time
			string[] pkgnames = {};
			foreach (unowned AURPackage pkg in current_aur_list) {
				pkgnames += pkg.name;
			}
			yield database.get_aur_pkgs_details (pkgnames);
		}

		bool need_more_aur () {
			if (current_aur_list_pos != null) {
				int natural_height;
				aur_listbox.get_preferred_height (null, out natural_height);
				if (aur_scrolledwindow.vadjustment.page_size > natural_height) {
					return true;
				}
			}
			return false;
		}

		void complete_aur_list () {
			if (current_aur_list_pos != null) {
				aur_listbox.freeze_child_notify ();
				uint i = 0;
				// display the next 20 packages
				while (i < 20) {
					var pkg = current_aur_list_pos.data;
					create_aurlist_row (pkg);
					i++;
					current_aur_list_pos = current_aur_list_pos.next;
					if (current_aur_list_pos == null) {
						// add an empty row to have an ending separator
						var row = new Gtk.ListBoxRow ();
						row.visible = true;
						aur_listbox.add (row);
						break;
					}
				}
				aur_listbox.thaw_child_notify ();
			}
		}

		void create_aurlist_row (AURPackage aur_pkg) {
			var row = new AURRow (aur_pkg);
			//populate info
			row.name_label.set_markup ("<b>%s</b>".printf (aur_pkg.name));
			if (browse_stack.visible_child_name == "updates") {
				row.version_label.set_markup ("<b>%s</b>\n(%s)".printf (aur_pkg.version, aur_pkg.installed_version));
			} else if (aur_pkg.installed_version == "") {
				row.version_label.label = aur_pkg.version;
			} else {
				row.version_label.label = aur_pkg.installed_version;
			}
			row.desc_label.label = aur_pkg.desc;
			row.app_icon.pixbuf = package_icon.scale_simple (32, 32, Gdk.InterpType.BILINEAR);
			row.details_button.clicked.connect (() => {
				on_aur_listbox_row_activated (row);
			});
			if (aur_pkg.name in to_build) {
				row.action_togglebutton.active = true;
				row.action_togglebutton.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
			}
			row.action_togglebutton.toggled.connect ((button) => {
				if (button.active) {
					button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
					to_build.add (aur_pkg.name);
				} else {
					button.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
					to_build.remove (aur_pkg.name);
				}
				set_pendings_operations ();
			});
			// insert
			aur_listbox.add (row);
		}

		public void refresh_packages_list () {
			button_back.visible = (main_stack.visible_child_name != "browse" || filters_stack.visible_child_name != "filters");
			if (browse_stack.visible_child_name == "browse") {
				show_sidebar ();
				search_button.visible = true;
				switch (filters_stack.visible_child_name) {
					case "filters":
						show_default_pkgs ();
						header_filter_label.label = "";
						search_button.active = false;
						remove_all_button.visible = false;
						install_all_button.visible = false;
						set_pendings_operations ();
						break;
					case "categories":
						on_categories_listbox_row_activated (categories_listbox.get_selected_row ());
						header_filter_label.set_markup ("<b>%s</b>".printf (dgettext (null, "Categories")));
						search_button.active = false;
						remove_all_button.visible = false;
						install_all_button.visible = false;
						set_pendings_operations ();
						break;
					case "groups":
						on_groups_listbox_row_activated (groups_listbox.get_selected_row ());
						header_filter_label.set_markup ("<b>%s</b>".printf (dgettext (null, "Groups")));
						search_button.active = false;
						set_pendings_operations ();
						break;
					case "repos":
						on_repos_listbox_row_activated (repos_listbox.get_selected_row ());
						header_filter_label.set_markup ("<b>%s</b>".printf (dgettext (null, "Repositories")));
						search_button.active = false;
						remove_all_button.visible = false;
						install_all_button.visible = false;
						set_pendings_operations ();
						break;
					default:
						break;
				}
			} else if (browse_stack.visible_child_name == "installed") {
				on_installed_listbox_row_activated (installed_listbox.get_selected_row ());
				show_sidebar ();
				header_filter_label.label = "";
				search_button.active = false;
				search_button.visible = true;
				install_all_button.visible = false;
				set_pendings_operations ();
			} else if (browse_stack.visible_child_name == "updates") {
				database.get_updates.begin (on_get_updates_finished);
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				hide_sidebar ();
				origin_stack.visible_child_name = "checking";
				header_filter_label.label = "";
				search_button.active = false;
				search_button.visible = false;
				remove_all_button.visible = false;
				install_all_button.visible = false;
				apply_button.sensitive = false;;
			} else if (browse_stack.visible_child_name == "pending") {
				on_pending_listbox_row_activated (pending_listbox.get_selected_row ());
				if (to_build.length == 0) {
					hide_sidebar ();
				}
				header_filter_label.label = "";
				search_button.active = false;
				search_button.visible = false;
				remove_all_button.visible = false;
				install_all_button.visible = false;
			} else if (browse_stack.visible_child_name == "search") {
				if (search_string != null) {
					// select last search_string
					bool found = false;
					search_comboboxtext.get_model ().foreach ((model, path, iter) => {
						string line;
						model.get (iter, 0, out line);
						if (line == search_string) {
							found = true;
							// we select the iter in search list
							// it will populate the packages list with the comboboxtext changed signal
							search_comboboxtext.set_active_iter (null);
							search_comboboxtext.set_active_iter (iter);
						}
						return found;
					});
					if (!searchbar.search_mode_enabled) {
						searchbar.search_mode_enabled = true;
					}
				}
				header_filter_label.label = "";
				remove_all_button.visible = false;
				install_all_button.visible = false;
				set_pendings_operations ();
			}
		}

		public void display_package_properties (string pkgname, string app_name = "", bool sync_pkg = false) {
			current_package_displayed = pkgname;
			// select details if build files was selected
			if (properties_listbox.get_selected_row ().get_index () == 3) {
				properties_listbox.get_row_at_index (0).activate ();
			}
			files_row.visible = true;
			build_files_row.visible = false;
			set_package_details.begin (current_package_displayed, app_name, sync_pkg);
		}

		void display_aur_properties (string pkgname) {
			current_package_displayed = pkgname;
			// select details if files was selected
			if (properties_listbox.get_selected_row ().get_index () == 2) {
				properties_listbox.get_row_at_index (0).activate ();
			}
			files_row.visible = false;
			build_files_row.visible = true;
			set_aur_details.begin (current_package_displayed);
		}

		[GtkCallback]
		void on_packages_listbox_row_activated (Gtk.ListBoxRow row) {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			main_stack.visible_child_name = "details";
			bool sync_pkg = browse_stack.visible_child_name == "updates";
			unowned PackageRow pamac_row = row as PackageRow;
			display_package_properties (pamac_row.pkg.name, pamac_row.pkg.app_name, sync_pkg);
			this.get_window ().set_cursor (null);
		}

		void on_dep_button_clicked (Gtk.Button button) {
			bool sync_pkg = false;
			if (browse_stack.visible_child_name == "updates") {
				sync_pkg = true;
			}
			if (display_package_queue.find_custom (current_package_displayed, strcmp) == null) {
				display_package_queue.push_tail (current_package_displayed);
			}
			string depstring = button.label;
			var pkg = database.find_installed_satisfier (depstring);
			if (pkg.name != "") {
				display_package_properties (pkg.name, "", sync_pkg);
			} else {
				pkg = database.find_sync_satisfier (depstring);
				if (pkg.name != "") {
					display_package_properties (pkg.name, "", sync_pkg);
				} else {
					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
					string dep_name = database.get_alpm_dep_name (depstring);
					database.get_aur_pkg.begin (dep_name, (obj, res) => {
						this.get_window ().set_cursor (null);
						if (database.get_aur_pkg.end (res).name != "") {
							display_aur_properties (dep_name);
						}
					});
				}
			}
		}

		[GtkCallback]
		void on_aur_listbox_row_activated (Gtk.ListBoxRow row) {
			unowned AURRow pamac_row = row as AURRow;
			if (browse_stack.visible_child_name == "updates") {
				display_aur_properties (pamac_row.aur_pkg.name);
			} else if (pamac_row.aur_pkg.installed_version != "") {
				display_package_properties (pamac_row.aur_pkg.name);
			} else {
				display_aur_properties (pamac_row.aur_pkg.name);
			}
			main_stack.visible_child_name = "details";
		}

		[GtkCallback]
		public void on_button_back_clicked () {
			switch (main_stack.visible_child_name) {
				case "browse":
					filters_stack.visible_child_name = "filters";
					search_entry.set_text ("");
					break;
				case "details":
					bool sync_pkg = false;
					if (browse_stack.visible_child_name == "updates") {
						sync_pkg = true;
					}
					string? pkgname = display_package_queue.pop_tail ();
					if (pkgname != null) {
						if (database.is_installed_pkg (pkgname) || database.is_sync_pkg (pkgname)) {
							display_package_properties (pkgname, "", sync_pkg);
						} else {
							database.get_aur_pkg.begin (pkgname, (obj, res) => {
								if (database.get_aur_pkg.end (res).name != "") {
									display_aur_properties (pkgname);
								} else {
									var pkg = database.find_installed_satisfier (pkgname);
									if (pkg.name == "") {
										pkg = database.find_sync_satisfier (pkgname);
									}
									if (pkg.name != "") {
										display_package_properties (pkgname, "", sync_pkg);
									}
								}
							});
						}
					} else {
						main_stack.visible_child_name = "browse";
					}
					break;
				case "term":
					main_stack.visible_child_name = "browse";
					break;
				default:
					break;
			}
		}

		[GtkCallback]
		void on_updates_listbox_row_activated (Gtk.ListBoxRow row) {
			int index = row.get_index ();
			switch (index) {
				case 0: // repos
					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
					row.activatable = true;
					row.selectable = true;
					row.can_focus = true;
					row.get_child ().sensitive = true;
					var pkgs = new List<Package> ();
					foreach (unowned Package pkg in repos_updates) {
						pkgs.append (pkg);
					}
					populate_packages_list ((owned) pkgs);
					break;
				case 1: // aur
					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
					var pkgs = new List<AURPackage> ();
					foreach (unowned AURPackage pkg in aur_updates) {
						pkgs.append (pkg);
					}
					populate_aur_list.begin ((owned) pkgs);
					unowned Gtk.ListBoxRow repo_row = updates_listbox.get_row_at_index (0);
					if (repos_updates.length () > 0) {
						repo_row.activatable = true;
						repo_row.selectable = true;
						repo_row.can_focus = true;
						repo_row.get_child ().sensitive = true;
					} else {
						repo_row.activatable = false;
						repo_row.selectable = false;
						repo_row.has_focus = false;
						repo_row.can_focus = false;
						repo_row.get_child ().sensitive = false;
					}
					break;
				default:
					break;
			}
		}

		[GtkCallback]
		void on_pending_listbox_row_activated (Gtk.ListBoxRow row) {
			int index = row.get_index ();
			switch (index) {
				case 0: // repos
					if ((to_install.length + to_remove.length) > 0) {
						this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
						row.activatable = true;
						row.selectable = true;
						row.can_focus = true;
						row.get_child ().sensitive = true;
						var pkgs = new List<Package> ();
						foreach (unowned string pkgname in to_install) {
							var pkg = database.get_installed_pkg (pkgname);
							if (pkg.name == "") {
								pkg = database.get_sync_pkg (pkgname);
							}
							if (pkg.name != "") {
								pkgs.append (pkg);
							}
						}
						foreach (unowned string pkgname in to_remove) {
							var pkg = database.get_installed_pkg (pkgname);
							if (pkg.name != "") {
								pkgs.append (pkg);
							}
						}
						populate_packages_list ((owned) pkgs);
					}
					unowned Gtk.ListBoxRow aur_row = pending_listbox.get_row_at_index (1);
					if (to_build.length > 0) {
						aur_row.activatable = true;
						aur_row.selectable = true;
						aur_row.can_focus = true;
						aur_row.get_child ().sensitive = true;
						if ((to_install.length + to_remove.length) == 0) {
							row.activatable = false;
							row.selectable = false;
							row.has_focus = false;
							row.can_focus = false;
							row.get_child ().sensitive = false;
							pending_listbox.select_row (aur_row);
							on_pending_listbox_row_activated (pending_listbox.get_selected_row ());
						}
					} else {
						aur_row.activatable = false;
						aur_row.selectable = false;
						aur_row.has_focus = false;
						aur_row.can_focus = false;
						aur_row.get_child ().sensitive = false;
					}
					break;
				case 1: // aur
					if (to_build.length > 0) {
						this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
						row.activatable = true;
						row.selectable = true;
						row.can_focus = true;
						row.get_child ().sensitive = true;
						populate_pendings_aur_pkgs.begin ();
					}
					unowned Gtk.ListBoxRow repo_row = pending_listbox.get_row_at_index (0);
					if ((to_install.length + to_remove.length) > 0) {
						repo_row.activatable = true;
						repo_row.selectable = true;
						repo_row.can_focus = true;
						repo_row.get_child ().sensitive = true;
						if (to_build.length == 0) {
							row.activatable = false;
							row.selectable = false;
							row.has_focus = false;
							row.can_focus = false;
							row.get_child ().sensitive = false;
							pending_listbox.select_row (repo_row);
							on_pending_listbox_row_activated (pending_listbox.get_selected_row ());
						}
					} else {
						repo_row.activatable = false;
						repo_row.selectable = false;
						repo_row.has_focus = false;
						repo_row.can_focus = false;
						repo_row.get_child ().sensitive = false;
					}
					break;
				default:
					break;
			}
		}

		async void populate_pendings_aur_pkgs () {
			var aur_pkgs = new List<AURPackage> ();
			string[] to_build_array = {};
			foreach (unowned string name in to_build)  {
				to_build_array += name;
			}
			var table = yield database.get_aur_pkgs (to_build_array);
			foreach (unowned AURPackage aur_pkg in table.get_values ())  {
				if (aur_pkg.name != "") {
					aur_pkgs.append (aur_pkg);
				}
			}
			populate_aur_list.begin ((owned) aur_pkgs);
		}

		[GtkCallback]
		void on_search_listbox_row_activated (Gtk.ListBoxRow row) {
			int index = row.get_index ();
			switch (index) {
				case 0: // installed
					search_entry.grab_focus_without_selecting ();
					search_entry.set_position (-1);
					if (search_string == null) {
						return;
					}
					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
					current_filter = "search_installed_pkgs_%s".printf (search_string);
					database.search_installed_pkgs_async.begin (search_string, (obj, res) => {
						if (current_filter != "search_installed_pkgs_%s".printf (search_string)) {
							return;
						}
						var pkgs = database.search_installed_pkgs_async.end (res);
						if (pkgs.length () == 0) {
							database.search_repos_pkgs_async.begin (search_string, (obj, res) => {
								if (database.search_repos_pkgs_async.end (res).length () > 0) {
									row.activatable = false;
									row.selectable = false;
									row.has_focus = false;
									row.can_focus = false;
									row.get_child ().sensitive = false;
									unowned Gtk.ListBoxRow repos_row = search_listbox.get_row_at_index (1);
									repos_row.activatable = true;
									repos_row.selectable = true;
									repos_row.can_focus = true;
									repos_row.get_child ().sensitive = true;
									search_listbox.select_row (repos_row);
									on_search_listbox_row_activated (search_listbox.get_selected_row ());
								} else if (database.config.enable_aur) {
									database.search_in_aur.begin (search_string, (obj, res) => {
										if (database.search_in_aur.end (res).length () > 0) {
											row.activatable = false;
											row.selectable = false;
											row.has_focus = false;
											row.can_focus = false;
											row.get_child ().sensitive = false;
											unowned Gtk.ListBoxRow repos_row = search_listbox.get_row_at_index (1);
											repos_row.activatable = false;
											repos_row.selectable = false;
											repos_row.has_focus = false;
											repos_row.can_focus = false;
											repos_row.get_child ().sensitive = false;
											unowned Gtk.ListBoxRow aur_row = search_listbox.get_row_at_index (2);
											aur_row.activatable = true;
											aur_row.selectable = true;
											aur_row.can_focus = true;
											aur_row.get_child ().sensitive = true;
											search_listbox.select_row (aur_row);
											on_search_listbox_row_activated (search_listbox.get_selected_row ());
										} else {
											populate_packages_list ((owned) pkgs);
										}
									});
								} else {
									populate_packages_list ((owned) pkgs);
								}
							});
						} else {
							populate_packages_list ((owned) pkgs);
							database.search_repos_pkgs_async.begin (search_string, (obj, res) => {
								if (database.search_repos_pkgs_async.end (res).length () > 0) {
									unowned Gtk.ListBoxRow repos_row = search_listbox.get_row_at_index (1);
									repos_row.activatable = true;
									repos_row.selectable = true;
									repos_row.can_focus = true;
									repos_row.get_child ().sensitive = true;
								}
							});
						}
					});
					break;
				case 1: // repos
					search_entry.grab_focus_without_selecting ();
					search_entry.set_position (-1);
					if (search_string == null) {
						return;
					}
					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
					current_filter = "search_repos_pkgs_%s".printf (search_string);
					database.search_repos_pkgs_async.begin (search_string, (obj, res) => {
						if (current_filter != "search_repos_pkgs_%s".printf (search_string)) {
							return;
						}
						var pkgs = database.search_repos_pkgs_async.end (res);
						if (pkgs.length () == 0) {
							database.search_installed_pkgs_async.begin (search_string, (obj, res) => {
								if (database.search_installed_pkgs_async.end (res).length () > 0) {
									row.activatable = false;
									row.selectable = false;
									row.has_focus = false;
									row.can_focus = false;
									row.get_child ().sensitive = false;
									unowned Gtk.ListBoxRow installed_row = search_listbox.get_row_at_index (0);
									installed_row.activatable = true;
									installed_row.selectable = true;
									installed_row.can_focus = true;
									installed_row.get_child ().sensitive = true;
									search_listbox.select_row (installed_row);
									on_search_listbox_row_activated (search_listbox.get_selected_row ());
								} else if (database.config.enable_aur) {
									database.search_in_aur.begin (search_string, (obj, res) => {
										if (database.search_in_aur.end (res).length () > 0) {
											row.activatable = false;
											row.selectable = false;
											row.has_focus = false;
											row.can_focus = false;
											row.get_child ().sensitive = false;
											unowned Gtk.ListBoxRow installed_row = search_listbox.get_row_at_index (0);
											installed_row.activatable = false;
											installed_row.selectable = false;
											installed_row.has_focus = false;
											installed_row.can_focus = false;
											installed_row.get_child ().sensitive = false;
											unowned Gtk.ListBoxRow aur_row = search_listbox.get_row_at_index (2);
											aur_row.activatable = true;
											aur_row.selectable = true;
											aur_row.can_focus = true;
											aur_row.get_child ().sensitive = true;
											search_listbox.select_row (aur_row);
											on_search_listbox_row_activated (search_listbox.get_selected_row ());
										} else {
											populate_packages_list ((owned) pkgs);
										}
									});
								} else {
									populate_packages_list ((owned) pkgs);
								}
							});
						} else {
							populate_packages_list ((owned) pkgs);
							database.search_installed_pkgs_async.begin (search_string, (obj, res) => {
								if (database.search_installed_pkgs_async.end (res).length () > 0) {
									unowned Gtk.ListBoxRow installed_row = search_listbox.get_row_at_index (0);
									installed_row.activatable = true;
									installed_row.selectable = true;
									installed_row.can_focus = true;
									installed_row.get_child ().sensitive = true;
								}
							});
						}
					});
					break;
				case 2: // aur
					search_entry.grab_focus_without_selecting ();
					search_entry.set_position (-1);
					if (search_string == null) {
						origin_stack.visible_child_name = "no_item";
						return;
					}
					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
					current_filter = "search_in_aur";
					database.search_in_aur.begin (search_string, (obj, res) => {
						if (current_filter != "search_in_aur") {
							return;
						}
						populate_aur_list.begin (database.search_in_aur.end (res));
					});
					database.search_installed_pkgs_async.begin (search_string, (obj, res) => {
						unowned Gtk.ListBoxRow installed_row = search_listbox.get_row_at_index (0);
						if (database.search_installed_pkgs_async.end (res).length () > 0 ) {
							installed_row.activatable = true;
							installed_row.selectable = true;
							installed_row.can_focus = true;
							installed_row.get_child ().sensitive = true;
						} else {
							installed_row.activatable = false;
							installed_row.selectable = false;
							installed_row.has_focus = false;
							installed_row.can_focus = false;
							installed_row.get_child ().sensitive = false;
						}
					});
					database.search_repos_pkgs_async.begin (search_string, (obj, res) => {
						unowned Gtk.ListBoxRow repos_row = search_listbox.get_row_at_index (1);
						if (database.search_repos_pkgs_async.end (res).length () > 0 ) {
							repos_row.activatable = true;
							repos_row.selectable = true;
							repos_row.can_focus = true;
							repos_row.get_child ().sensitive = true;
						} else {
							repos_row.activatable = false;
							repos_row.selectable = false;
							repos_row.has_focus = false;
							repos_row.can_focus = false;
							repos_row.get_child ().sensitive = false;
						}
					});
					break;
				default:
					break;
			}
		}

		[GtkCallback]
		void on_remove_all_button_clicked () {
			foreach (unowned Package pkg in current_packages_list) {
				if (!transaction.transaction_summary.contains (pkg.name) && pkg.installed_version != "") {
					to_install.remove (pkg.name);
					to_remove.add (pkg.name);
				}
			}
			refresh_listbox_buttons ();
			set_pendings_operations ();
		}

		[GtkCallback]
		void on_install_all_button_clicked () {
			foreach (unowned Package pkg in current_packages_list) {
				if (!transaction.transaction_summary.contains (pkg.name) && pkg.installed_version == "") {
					to_install.add (pkg.name);
				}
			}
			refresh_listbox_buttons ();
			set_pendings_operations ();
		}

		void on_search_mode_enabled () {
			if (searchbar.search_mode_enabled) {
				search_button.active = true;
			}
		}

		[GtkCallback]
		void on_search_button_toggled () {
			if (search_button.active) {
				searchbar.search_mode_enabled = true;
			} else {
				searchbar.search_mode_enabled = false;
			}
		}

		bool search_entry_timeout_callback () {
			// add search string in search_list if needed
			string tmp_search_string = search_comboboxtext.get_active_text ().strip ();
			if (tmp_search_string == "") {
				search_entry_timeout_id = 0;
				return false;
			}
			bool found = false;
			// check if search string exists in search list
			search_comboboxtext.get_model ().foreach ((model, path, iter) => {
				string line;
				model.get (iter, 0, out line);
				if (line == tmp_search_string) {
					found = true;
					// we select the iter in search list
					// it will populate the packages list with the comboboxtext changed signal
					search_comboboxtext.set_active_iter (iter);
				}
				return found;
			});
			if (!found) {
				Gtk.TreeIter iter;
				unowned Gtk.ListStore store = search_comboboxtext.get_model () as Gtk.ListStore;
				store.insert_with_values (out iter, -1, 0, tmp_search_string);
				// we select the iter in search list
				// it will populate the packages list with the comboboxtext changed signal
				search_comboboxtext.set_active_iter (iter);
			}
			search_entry_timeout_id = 0;
			return false;
		}

		[GtkCallback]
		void on_search_comboboxtext_changed () {
			if (search_comboboxtext.get_active () == -1) {
				// entry was edited
				if (search_comboboxtext.get_active_text ().strip () != "") {
					if (search_entry_timeout_id != 0) {
						Source.remove (search_entry_timeout_id);
					}
					search_entry_timeout_id = Timeout.add (1000, search_entry_timeout_callback);
				}
			} else {
				// a history line was choosen
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				search_string = search_comboboxtext.get_active_text ().strip ();
				if (browse_stack.visible_child_name != "search") {
					// this function will be recalled when refresh_packages_list
					browse_stack.visible_child_name = "search";
					return;
				}
				on_search_listbox_row_activated (search_listbox.get_selected_row ());
			}
		}

		[GtkCallback]
		void on_search_entry_icon_press (Gtk.EntryIconPosition pos, Gdk.Event event) {
			if (pos == Gtk.EntryIconPosition.SECONDARY) {
				search_entry.set_text ("");
			}
		}

		[GtkCallback]
		void on_sort_comboboxtext_changed () {
			refresh_packages_list ();
		}

		[GtkCallback]
		void on_filters_listbox_row_activated (Gtk.ListBoxRow row) {
			int index = row.get_index ();
			switch (index) {
				case 0: // categories
					filters_stack.visible_child_name = "categories";
					break;
				case 1: // groups
					filters_stack.visible_child_name = "groups";
					break;
				case 2: // repos
					filters_stack.visible_child_name = "repos";
					break;
				default:
					break;
			}
		}

		[GtkCallback]
		void on_categories_listbox_row_activated (Gtk.ListBoxRow row) {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			unowned Gtk.Label label = row.get_child () as Gtk.Label;
			string matching_cat = "";
			unowned string category = label.label;
			if (category == dgettext (null, "Accessories")) {
				matching_cat = "Utility";
			} else if (category == dgettext (null, "Audio & Video")) {
				matching_cat = "AudioVideo";
			} else if (category == dgettext (null, "Development")) {
				matching_cat = "Development";
			} else if (category == dgettext (null, "Education")) {
				matching_cat = "Education";
			} else if (category == dgettext (null, "Games")) {
				matching_cat = "Game";
			} else if (category == dgettext (null, "Graphics")) {
				matching_cat = "Graphics";
			} else if (category == dgettext (null, "Internet")) {
				matching_cat = "Network";
			} else if (category == dgettext (null, "Office")) {
				matching_cat = "Office";
			} else if (category == dgettext (null, "Science")) {
				matching_cat = "Science";
				} else if (category == dgettext (null, "Settings")) {
				matching_cat = "Settings";
			} else if (category == dgettext (null, "System Tools")) {
				matching_cat = "System";
			}
			Timeout.add (200, () => {
				current_filter = "category_pkgs_%s".printf (matching_cat);
				database.get_category_pkgs_async.begin (matching_cat, (obj, res) => {
					if (current_filter != "category_pkgs_%s".printf (matching_cat)) {
						return;
					}
					populate_packages_list (database.get_category_pkgs_async.end (res));
				});
				return false;
			});
		}

		[GtkCallback]
		void on_groups_listbox_row_activated (Gtk.ListBoxRow row) {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			unowned Gtk.Label label = row.get_child () as Gtk.Label;
			unowned string group_name = label.label;
			Timeout.add (200, () => {
				current_filter = "group_pkgs_%s".printf (group_name);
				database.get_group_pkgs_async.begin (group_name, (obj, res) => {
					if (current_filter != "group_pkgs_%s".printf (group_name)) {
						return;
					}
					var pkgs = database.get_group_pkgs_async.end (res);
					bool found = false;
					foreach (unowned Package pkg in pkgs) {
						if (pkg.installed_version == "") {
							found = true;
							break;
						}
					}
					install_all_button.visible = found;
					found = false;
					foreach (unowned Package pkg in pkgs) {
						if (pkg.installed_version != "") {
							found = true;
							break;
						}
					}
					remove_all_button.visible = found;
					populate_packages_list ((owned) pkgs);
				});
				return false;
			});
		}

		[GtkCallback]
		void on_installed_listbox_row_activated (Gtk.ListBoxRow row) {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			int index = row.get_index ();
			switch (index) {
				case 0: // Installed
					Timeout.add (200, () => {
						current_filter = "installed_pkgs";
						database.get_installed_pkgs_async.begin ((obj, res) => {
							if (current_filter != "installed_pkgs") {
								return;
							}
							remove_all_button.visible = false;
							populate_packages_list (database.get_installed_pkgs_async.end (res));
						});
						return false;
					});
					break;
				case 1: // Explicitly installed
					Timeout.add (200, () => {
						current_filter = "explicitly_installed_pkgs";
						database.get_explicitly_installed_pkgs_async.begin ((obj, res) => {
							if (current_filter != "explicitly_installed_pkgs") {
								return;
							}
							remove_all_button.visible = false;
							populate_packages_list (database.get_explicitly_installed_pkgs_async.end (res));
						});
						return false;
					});
					break;
				case 2: // Orphans
					Timeout.add (200, () => {
						current_filter = "orphans";
						database.get_orphans_async.begin ((obj, res) => {
							if (current_filter != "orphans") {
								return;
							}
							var pkgs = database.get_orphans_async.end (res);
							remove_all_button.visible = pkgs.length () > 0;
							populate_packages_list ((owned) pkgs);
						});
						return false;
					});
					break;
				case 3: // Foreign
					Timeout.add (200, () => {
						current_filter = "foreign_pkgs";
						database.get_foreign_pkgs_async.begin ((obj, res) => {
							if (current_filter != "foreign_pkgs") {
								return;
							}
							remove_all_button.visible = false;
							populate_packages_list (database.get_foreign_pkgs_async.end (res));
						});
						return false;
					});
					break;
				default:
					break;
			}
		}

		[GtkCallback]
		void on_repos_listbox_row_activated (Gtk.ListBoxRow row) {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			unowned Gtk.Label label = row.get_child () as Gtk.Label;
			unowned string repo = label.label;
			Timeout.add (200, () => {
				current_filter = "repo_pkgs_%s".printf (repo);
				database.get_repo_pkgs_async.begin (repo, (obj, res) => {
					if (current_filter != "repo_pkgs_%s".printf (repo)) {
						return;
					}
					populate_packages_list (database.get_repo_pkgs_async.end (res));
				});
				return false;
			});
		}

		void on_main_stack_visible_child_changed () {
			switch (main_stack.visible_child_name) {
				case "browse":
					main_stack_switcher.visible = true;
					button_back.visible = filters_stack.visible_child_name != "filters";
					if (filters_stack.visible_child_name == "categories") {
						header_filter_label.set_markup ("<b>%s</b>".printf (dgettext (null, "Categories")));
					} else if (filters_stack.visible_child_name == "groups") {
						header_filter_label.set_markup ("<b>%s</b>".printf (dgettext (null, "Groups")));
					} else if (filters_stack.visible_child_name == "repos") {
						header_filter_label.set_markup ("<b>%s</b>".printf (dgettext (null, "Repositories")));
					} else {
						header_filter_label.label = "";
					}
					if (browse_stack.visible_child_name == "updates"
						|| browse_stack.visible_child_name == "pending") {
						search_button.visible = false;
					} else {
						search_button.visible = true;
					}
					if (transaction.details_textview.buffer.get_char_count () > 0) {
						details_button.sensitive = true;
					}
					break;
				case "details":
					main_stack_switcher.visible = false;
					button_back.visible = true;
					header_filter_label.label = "";
					search_button.visible = false;
					if (transaction.details_textview.buffer.get_char_count () > 0) {
						details_button.sensitive = true;
					}
					break;
				case "term":
					main_stack_switcher.visible = false;
					button_back.visible = true;
					header_filter_label.label = "";
					search_button.visible = false;
					details_button.sensitive = false;
					details_button.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
					break;
				default:
					break;
			}
		}

		void on_browse_stack_visible_child_changed () {
			refresh_packages_list ();
		}

		void on_filters_stack_visible_child_changed () {
			refresh_packages_list ();
		}

		void on_origin_stack_visible_child_changed () {
			switch (origin_stack.visible_child_name) {
				case "repos":
					sort_order_box.visible = true;
					// check if aur was used
					Gtk.TreeIter iter;
					if (!sort_comboboxtext.get_model ().get_iter (out iter, new Gtk.TreePath.from_indices (3, -1))) {
						sort_comboboxtext.append_text (dgettext (null, "Repository"));
						sort_comboboxtext.append_text (dgettext (null, "Size"));
					}
					break;
				case "aur":
					sort_order_box.visible = true;
					Gtk.TreeIter iter;
					// check if packages was used
					if (sort_comboboxtext.get_model ().get_iter (out iter, new Gtk.TreePath.from_indices (3, -1))) {
						if (sort_comboboxtext.active == 3
							|| sort_comboboxtext.active == 4) {
							sort_comboboxtext.active = 0;
						}
						sort_comboboxtext.remove (3);
						sort_comboboxtext.remove (3);
					}
					break;
				default:
					sort_order_box.visible = false;
					break;
			}
		}

		[GtkCallback]
		void on_menu_button_toggled () {
			preferences_button.sensitive = !(transaction_running || sysupgrade_running);
		}

		[GtkCallback]
		void on_history_button_clicked () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			var history_dialog = new HistoryDialog (this);
			this.get_window ().set_cursor (null);
			history_dialog.show ();
			history_dialog.response.connect (() => {
				history_dialog.destroy ();
			});
		}

		[GtkCallback]
		void on_local_button_clicked () {
			Gtk.FileChooserDialog chooser = new Gtk.FileChooserDialog (
					dgettext (null, "Install Local Packages"), this, Gtk.FileChooserAction.OPEN,
					dgettext (null, "_Cancel"), Gtk.ResponseType.CANCEL,
					dgettext (null, "_Open"),Gtk.ResponseType.ACCEPT);
			chooser.window_position = Gtk.WindowPosition.CENTER_ON_PARENT;
			chooser.icon_name = "system-software-install";
			chooser.select_multiple = true;
			chooser.local_only = false;
			chooser.create_folders = false;
			Gtk.FileFilter package_filter = new Gtk.FileFilter ();
			package_filter.set_filter_name (dgettext (null, "Alpm Package"));
			package_filter.add_pattern ("*.pkg.tar.xz");
			chooser.add_filter (package_filter);
			if (chooser.run () == Gtk.ResponseType.ACCEPT) {
				SList<string> packages_paths = chooser.get_filenames ();
				if (packages_paths.length () != 0) {
					foreach (unowned string path in packages_paths) {
						to_load.add (path);
					}
					chooser.destroy ();
					try_lock_and_run (run_transaction);
				}
			} else {
				chooser.destroy ();
			}
		}

		[GtkCallback]
		void on_preferences_button_clicked () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			run_preferences_dialog ();
		}

		public void run_preferences_dialog () {
			transaction.get_authorization_finished.connect (launch_preferences_dialog);
			transaction.start_get_authorization ();
		}

		void launch_preferences_dialog (bool authorized) {
			transaction.get_authorization_finished.disconnect (launch_preferences_dialog);
			if (authorized) {
				var preferences_dialog = new PreferencesDialog (transaction);
				preferences_dialog.run ();
				preferences_dialog.destroy ();
			}
			on_run_preferences_dialog_finished ();
		}

		void on_run_preferences_dialog_finished () {
			if (browse_stack.visible_child_name == "updates") {
				database.get_updates.begin (on_get_updates_finished);
				origin_stack.visible_child_name = "checking";
			} else {
				this.get_window ().set_cursor (null);
			}
		}

		[GtkCallback]
		void on_about_button_clicked () {
			string[] authors = {"Guillaume Benoit"};
			Gtk.show_about_dialog (
				this,
				"program_name", "Pamac",
				"icon_name", "system-software-install",
				"logo_icon_name", "system-software-install",
				"comments", dgettext (null, "A Gtk3 frontend for libalpm"),
				"copyright", "Copyright © 2019 Guillaume Benoit",
				"authors", authors,
				"version", VERSION,
				"license_type", Gtk.License.GPL_3_0,
				"website", "https://gitlab.manjaro.org/applications/pamac");
		}

		[GtkCallback]
		void on_details_button_clicked () {
			important_details = false;
			main_stack.visible_child_name = "term";
		}

		[GtkCallback]
		void on_apply_button_clicked () {
			if (browse_stack.visible_child_name == "updates" &&
				main_stack.visible_child_name == "browse") {
				force_refresh = false;
				transaction.no_confirm_upgrade = true;
				try_lock_and_run (run_sysupgrade);
			} else if (main_stack.visible_child_name == "details" &&
					properties_stack.visible_child_name == "build_files") {
					transaction.save_build_files.begin (current_package_displayed, () => {
						try_lock_and_run (run_transaction);
					});
			} else {
				try_lock_and_run (run_transaction);
			}
			details_button.sensitive = true;
		}

		void run_transaction () {
			transaction.no_confirm_upgrade = false;
			transaction_running = true;
			apply_button.sensitive = false;
			cancel_button.sensitive = false;
			show_transaction_infobox ();
			string[] to_install_ = {};
			string[] to_remove_ = {};
			string[] to_load_ = {};
			string[] to_build_ = {};
			foreach (unowned string name in to_install) {
				to_install_ += name;
				previous_to_install.add (name);
			}
			foreach (unowned string name in to_remove) {
				to_remove_ += name;
				previous_to_remove.add (name);
			}
			foreach (unowned string path in to_load) {
				to_load_ += path;
			}
			foreach (unowned string name in to_build) {
				to_build_ += name;
				previous_to_build.add (name);
			}
			transaction.start (to_install_, to_remove_, to_load_, to_build_, {}, {});
			clear_lists ();
		}

		void run_sysupgrade () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			sysupgrade_running = true;
			apply_button.sensitive = false;
			cancel_button.sensitive = false;
			string[] temp_ign_pkgs = {};
			foreach (unowned string name in temporary_ignorepkgs) {
				temp_ign_pkgs += name;
			}
			show_transaction_infobox ();
			transaction.start_sysupgrade (force_refresh, database.config.enable_downgrade, temp_ign_pkgs, {});
		}

		[GtkCallback]
		void on_cancel_button_clicked () {
			if (waiting) {
				waiting = false;
				transaction.stop_progressbar_pulse ();
				set_pendings_operations ();
			} else if (transaction_running) {
				transaction_running = false;
				transaction.cancel ();
			} else if (sysupgrade_running) {
				sysupgrade_running = false;
				transaction.cancel ();
			} else {
				clear_lists ();
				set_pendings_operations ();
				scroll_to_top = false;
				refresh_packages_list ();
				if (main_stack.visible_child_name == "details") {
					if (database.is_installed_pkg (current_package_displayed)
						|| database.is_sync_pkg (current_package_displayed)) {
						display_package_properties (current_package_displayed);
					} else {
						display_aur_properties (current_package_displayed);
					}
				}
			}
		}

		[GtkCallback]
		void on_refresh_button_clicked () {
			force_refresh = true;
			transaction.no_confirm_upgrade = false;
			try_lock_and_run (run_sysupgrade);
		}

		void on_get_updates_progress (uint percent) {
			checking_label.set_markup ("<big><b>%s %u %</b></big>".printf (dgettext (null, "Checking for Updates"), percent));
		}

		void on_get_updates_finished (Object? source_object, AsyncResult res) {
			var updates = database.get_updates.end (res);
			// copy updates in lists (keep a ref of them)
			repos_updates = new List<Package> ();
			foreach (unowned Package pkg in updates.repos_updates) {
				repos_updates.append (pkg);
			}
			aur_updates = new List<AURPackage> ();
			foreach (unowned AURPackage pkg in updates.aur_updates) {
				aur_updates.append (pkg);
			}
			if (browse_stack.visible_child_name == "updates") {
				populate_updates ();
			} else {
				this.get_window ().set_cursor (null);
			}
		}

		void populate_updates () {
			to_update.remove_all ();
			if ((repos_updates.length () + aur_updates.length ()) == 0) {
				if (!transaction_running && !sysupgrade_running) {
					hide_transaction_infobox ();
				}
				hide_sidebar ();
				origin_stack.visible_child_name = "updated";
				this.get_window ().set_cursor (null);
			} else {
				if (repos_updates.length () > 0) {
					foreach (unowned Package pkg in repos_updates) {
						if (!temporary_ignorepkgs.contains (pkg.name)) {
							to_update.add (pkg.name);
						}
					}
				}
				if (aur_updates.length () > 0) {
					foreach (unowned AURPackage pkg in aur_updates) {
						if (!temporary_ignorepkgs.contains (pkg.name)) {
							to_update.add (pkg.name);
						}
					}
					show_sidebar ();
				}
				if (repos_updates.length () > 0) {
					updates_listbox.get_row_at_index (0).activate ();
				} else {
					updates_listbox.get_row_at_index (1).activate ();
				}
				set_pendings_operations ();
			}
		}

		void on_start_preparing () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			cancel_button.sensitive = false;
		}

		void on_stop_preparing () {
			cancel_button.sensitive = false;
			this.get_window ().set_cursor (null);
			// restore build_files_notebook
			if (properties_listbox.get_selected_row ().get_index () == 3) {
				properties_stack.visible_child_name = "build_files";
			}
		}

		void on_start_downloading () {
			cancel_button.sensitive = true;
		}

		void on_stop_downloading () {
			cancel_button.sensitive = false;
		}

		void on_start_building () {
			cancel_button.sensitive = true;
		}

		void on_stop_building () {
			cancel_button.sensitive = false;
		}

		void on_important_details_outpout (bool must_show) {
			if (must_show) {
				main_stack.visible_child_name = "term";
				button_back.visible = false;
			} else if (main_stack.visible_child_name != "term") {
				important_details = true;
				details_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
			}
		}

		void on_start_generating_mirrors_list () {
			generate_mirrors_list = true;
			apply_button.sensitive = false;
			details_button.sensitive = true;
			show_transaction_infobox ();
		}

		void on_generate_mirrors_list_finished () {
			generate_mirrors_list = false;
		}

		void on_transaction_finished (bool success) {
			transaction.unlock ();
			if (!success) {
				foreach (unowned string name in previous_to_install) {
					if (!database.is_installed_pkg (name)) {
						to_install.add (name);
					}
				}
				foreach (unowned string name in previous_to_remove) {
					if (database.is_installed_pkg (name)) {
						to_remove.add (name);
					}
				}
				foreach (unowned string name in previous_to_build) {
					if (!database.is_installed_pkg (name)) {
						to_build.add (name);
					}
				}
			}
			transaction.transaction_summary.remove_all ();
			clear_previous_lists ();
			scroll_to_top = false;
			if (main_stack.visible_child_name == "details") {
				if (database.is_installed_pkg (current_package_displayed)
					|| database.is_sync_pkg (current_package_displayed)) {
					display_package_properties (current_package_displayed);
				} else {
					display_aur_properties (current_package_displayed);
				}
			} else if (main_stack.visible_child_name == "term") {
				button_back.visible = true;
			}
			if (sysupgrade_running) {
				sysupgrade_running = false;
			} else {
				transaction_running = false;
				generate_mirrors_list = false;
			}
			refresh_listbox_buttons ();
			set_pendings_operations ();
		}
	}
}
