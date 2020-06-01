/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2020 Guillaume Benoit <guillaume@manjaro.org>
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
	SList<string> repos_names;
	GenericSet<string?> to_install;
	GenericSet<string?> to_remove;
	GenericSet<string?> to_load;
	GenericSet<string?> to_build;
	GenericSet<string?> to_update;
	GenericSet<string?> temporary_ignorepkgs;
	#if ENABLE_SNAP
	HashTable<string, SnapPackage> snap_to_install;
	HashTable<string, SnapPackage> snap_to_remove;
	#endif
	#if ENABLE_FLATPAK
	HashTable<string, FlatpakPackage> flatpak_to_install;
	HashTable<string, FlatpakPackage> flatpak_to_remove;
	#endif

	int sort_search_pkgs_by_relevance (Pamac.Package pkg_a, Pamac.Package pkg_b) {
		if (search_string != null) {
			// display exact match first
			if (pkg_a.app_name.down () == search_string) {
				if (pkg_b.app_name.down () == search_string) {
					return sort_pkgs_by_relevance (pkg_a, pkg_b);
				}
				return -1;
			}
			if (pkg_b.app_name.down () == search_string) {
				return 1;
			}
			if (pkg_a.name == search_string) {
				if (pkg_b.name == search_string) {
					return sort_pkgs_by_relevance (pkg_a, pkg_b);
				}
				return -1;
			}
			if (pkg_b.name == search_string) {
				return 1;
			}
			if (pkg_a.app_name.down ().has_prefix (search_string)) {
				if (pkg_b.app_name.down ().has_prefix (search_string)) {
					return sort_pkgs_by_relevance (pkg_a, pkg_b);
				}
				return -1;
			}
			if (pkg_b.app_name.down ().has_prefix (search_string)) {
				return 1;
			}
			if (pkg_a.app_name.down ().contains (search_string)) {
				if (pkg_b.app_name.down ().contains (search_string)) {
					return sort_pkgs_by_relevance (pkg_a, pkg_b);
				}
				return -1;
			}
			if (pkg_b.app_name.down ().contains (search_string)) {
				return 1;
			}
			if (pkg_a.name.has_prefix (search_string + "-")) {
				if (pkg_b.name.has_prefix (search_string + "-")) {
					return sort_pkgs_by_relevance (pkg_a, pkg_b);
				}
				return -1;
			}
			if (pkg_b.name.has_prefix (search_string + "-")) {
				return 1;
			}
			if (pkg_a.name.has_prefix (search_string)) {
				if (pkg_b.name.has_prefix (search_string)) {
					return sort_pkgs_by_relevance (pkg_a, pkg_b);
				}
				return -1;
			}
			if (pkg_b.name.has_prefix (search_string)) {
				return 1;
			}
			if (pkg_a.name.contains (search_string)) {
				if (pkg_b.name.contains (search_string)) {
					return sort_pkgs_by_relevance (pkg_a, pkg_b);
				}
				return -1;
			}
			if (pkg_b.name.contains (search_string)) {
				return 1;
			}
		}
		return sort_pkgs_by_relevance (pkg_a, pkg_b);
	}

	int sort_pkgs_by_relevance (Package pkg_a, Package pkg_b) {
		if (pkg_a.installed_version == "") {
			if (pkg_b.installed_version == "") {
				return sort_pkgs_by_name (pkg_a, pkg_b);
			}
			return 1;
		}
		if (pkg_b.installed_version == "") {
			return -1;
		}
		if (pkg_a.app_name == "") {
			if (pkg_b.app_name == "") {
				return sort_pkgs_by_name (pkg_a, pkg_b);
			}
			return 1;
		}
		if (pkg_b.app_name == "") {
			return -1;
		}
		return sort_pkgs_by_name (pkg_a, pkg_b);
	}

	int sort_pkgs_by_name (Package pkg_a, Package pkg_b) {
		string str_a = pkg_a.app_name == "" ? pkg_a.name.collate_key () : pkg_a.app_name.down ().collate_key ();
		string str_b = pkg_b.app_name == "" ? pkg_b.name.collate_key () : pkg_b.app_name.down ().collate_key ();
		int cmp = strcmp (str_a, str_b);
		if (cmp == 0) {
			cmp = sort_pkgs_by_repo_real (pkg_a, pkg_b);
		}
		return cmp;
	}

	int compare_pkgs_by_name (Package pkg_a, Package pkg_b) {
		return strcmp (pkg_a.name, pkg_b.name);
	}

	int sort_pkgs_by_repo (Package pkg_a, Package pkg_b) {
		int cmp = sort_pkgs_by_repo_real (pkg_a, pkg_b);
		if (cmp == 0) {
			cmp = sort_pkgs_by_name (pkg_a, pkg_b);
		}
		return cmp;
	}

	int sort_pkgs_by_repo_real (Package pkg_a, Package pkg_b) {
		uint index_a = 10;
		if (pkg_a.repo != "") {
			uint index = 0;
			foreach (unowned string name in repos_names) {
				if (name == pkg_a.repo) {
					index_a = index;
					break;
				}
				index++;
			}
		}
		uint index_b = 10;
		if (pkg_b.repo != "") {
			uint index = 0;
			foreach (unowned string name in repos_names) {
				if (name == pkg_b.repo) {
					index_b = index;
					break;
				}
				index++;
			}
		}
		if (index_a > index_b) {
			return 1;
		}
		if (index_b > index_a) {
			return -1;
		}
		return 0;
	}

	int sort_pkgs_by_installed_size (Package pkg_a, Package pkg_b) {
		if (pkg_a.installed_size > pkg_b.installed_size) {
			return -1;
		}
		if (pkg_b.installed_size > pkg_a.installed_size) {
			return 1;
		}
		return sort_pkgs_by_name (pkg_a, pkg_b);
	}

	int sort_pkgs_by_download_size (Package pkg_a, Package pkg_b) {
		if (pkg_a.download_size > pkg_b.download_size) {
			return -1;
		}
		if (pkg_b.download_size > pkg_a.download_size) {
			return 1;
		}
		return sort_pkgs_by_name (pkg_a, pkg_b);
	}

	int sort_aur_by_relevance (AURPackage pkg_a, AURPackage pkg_b) {
		if (pkg_a.installed_version != "") {
			if (pkg_b.installed_version != "") {
				return sort_pkgs_by_name (pkg_a, pkg_b);
			}
			return -1;
		}
		if (pkg_b.installed_version != "") {
			return 1;
		}
		if (pkg_a.popularity > pkg_b.popularity) {
			return -1;
		}
		if (pkg_b.popularity > pkg_a.popularity) {
			return 1;
		}
		return sort_pkgs_by_name (pkg_a, pkg_b);
	}

	int sort_pkgs_by_date (Package pkg_a, Package pkg_b) {
		if (pkg_a.installed_version == "") {
			if (pkg_b.installed_version == "") {
				AlpmPackage ? alpm_pkg_a = pkg_a as AlpmPackage;
				AlpmPackage ? alpm_pkg_b = pkg_b as AlpmPackage;
				if (alpm_pkg_a != null && alpm_pkg_b != null) {
					if (alpm_pkg_a.builddate > alpm_pkg_b.builddate) {
						return -1;
					}
					if (alpm_pkg_b.builddate > alpm_pkg_a.builddate) {
						return 1;
					}
				}
				return sort_pkgs_by_name (pkg_a, pkg_b);
			} else {
				return 1;
			}
		}
		if (pkg_b.installed_version == "") {
			return -1;
		}
		if (pkg_a.installdate > pkg_b.installdate) {
			return -1;
		}
		if (pkg_b.installdate > pkg_a.installdate) {
			return 1;
		}
		return sort_pkgs_by_name (pkg_a, pkg_b);
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
		return sort_pkgs_by_date (pkg_a, pkg_b);
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
		Gtk.ModelButton refresh_button;
		[GtkChild]
		Gtk.ModelButton local_button;
		[GtkChild]
		Gtk.ModelButton preferences_button;
		[GtkChild]
		Gtk.Box browse_box;
		[GtkChild]
		Gtk.ListBox packages_listbox;
		[GtkChild]
		Gtk.Revealer sidebar_revealer;
		[GtkChild]
		Gtk.Revealer notification_revealer;
		[GtkChild]
		Gtk.Label notification_label;
		[GtkChild]
		Gtk.Button notification_button;
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
		Gtk.Label filters_button_label;
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
		Gtk.Button ignore_all_button;
		[GtkChild]
		Gtk.Box sort_order_box;
		[GtkChild]
		Gtk.Label sortby_button_label;
		[GtkChild]
		Gtk.ScrolledWindow packages_scrolledwindow;
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
		Gtk.Stack screenshots_stack;
		[GtkChild]
		Gtk.Spinner screenshots_spinner;
		[GtkChild]
		Gtk.Button previous_screenshot_button;
		[GtkChild]
		Gtk.Button next_screenshot_button;
		[GtkChild]
		Gtk.Label desc_label;
		[GtkChild]
		Gtk.Label long_desc_label;
		[GtkChild]
		Gtk.Label link_label;
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
		public Gtk.Button details_button;
		[GtkChild]
		public Gtk.Button apply_button;
		[GtkChild]
		Gtk.Button cancel_button;

		public Queue<Package> display_package_queue;
		Package current_package_displayed;
		string current_launchable;
		string current_files;
		string current_build_files;
		GenericSet<string?> previous_to_install;
		GenericSet<string?> previous_to_remove;
		GenericSet<string?> previous_to_build;

		public TransactionGtk transaction;
		public Database database { get; construct; }
		LocalConfig local_config;

		bool important_details;
		bool transaction_running;
		bool sysupgrade_running;
		public bool generate_mirrors_list;
		bool waiting;

		GenericArray<AlpmPackage> repos_updates;
		GenericArray<AURPackage> aur_updates;
		#if ENABLE_FLATPAK
		GenericArray<FlatpakPackage> flatpak_updates;
		#endif
		SList<Package> current_packages_list;
		unowned SList<Package> current_packages_list_pos;
		GenericArray<Gdk.Pixbuf> current_screenshots;
		int current_screenshots_index;

		uint search_entry_timeout_id;
		uint search_history_timeout_id;
		Gtk.ListBoxRow deps_row;
		Gtk.ListBoxRow files_row;
		Gtk.ListBoxRow build_files_row;
		bool scroll_to_top;
		uint in_app_notification_timeout_id;

		#if ENABLE_SNAP
		int installed_listbox_snap_index;
		int pending_listbox_snap_index;
		int search_listbox_snap_index;
		HashTable<string, SnapPackage> previous_snap_to_install;
		HashTable<string, SnapPackage> previous_snap_to_remove;
		#endif
		#if ENABLE_FLATPAK
		int installed_listbox_flatpak_index;
		int pending_listbox_flatpak_index;
		int search_listbox_flatpak_index;
		HashTable<string, FlatpakPackage> previous_flatpak_to_install;
		HashTable<string, FlatpakPackage> previous_flatpak_to_remove;
		#endif

		public ManagerWindow (Gtk.Application application, Database database) {
			Object (application: application, database: database);
		}

		construct {
			unowned string? use_csd = Environment.get_variable ("GTK_CSD");
			if (use_csd == "0") {
				headerbar.show_close_button = false;
			}
			local_config = new LocalConfig ("%s/pamac/size".printf (Environment.get_user_config_dir ()));
			this.resize ((int) local_config.width, (int) local_config.height);
			if (local_config.maximized) {
				this.set_default_size ((int) local_config.width, (int) local_config.height);
				this.maximize ();
			}

			button_back.visible = false;
			remove_all_button.visible = false;
			install_all_button.visible = false;
			ignore_all_button.visible = false;
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

			current_screenshots = new GenericArray<Gdk.Pixbuf> ();

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

			// packages listbox functions
			packages_listbox.set_header_func (set_header_func);

			// icons
			icon_theme = Gtk.IconTheme.get_default ();
			icon_theme.changed.connect (update_icons);
			update_icons ();

			// database
			database.get_updates_progress.connect (on_get_updates_progress);
			create_all_listbox ();
			check_aur_support ();

			// transaction
			repos_updates = new GenericArray<AlpmPackage> ();
			aur_updates = new GenericArray<AURPackage> ();
			#if ENABLE_SNAP
			snap_to_install = new HashTable<string, SnapPackage> (str_hash, str_equal);
			snap_to_remove = new HashTable<string, SnapPackage> (str_hash, str_equal);
			previous_snap_to_install = new HashTable<string, SnapPackage> (str_hash, str_equal);
			previous_snap_to_remove = new HashTable<string, SnapPackage> (str_hash, str_equal);
			check_snap_support ();
			#endif
			#if ENABLE_FLATPAK
			flatpak_to_install = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			flatpak_to_remove = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			previous_flatpak_to_install = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			previous_flatpak_to_remove = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			flatpak_updates = new GenericArray<FlatpakPackage> ();
			check_flatpak_support ();
			#endif
			transaction = new TransactionGtk (database, this);
			transaction.start_waiting.connect (on_start_waiting);
			transaction.stop_waiting.connect (on_stop_waiting);
			transaction.start_preparing.connect (on_start_preparing);
			transaction.stop_preparing.connect (on_stop_preparing);
			transaction.start_downloading.connect (on_start_downloading);
			transaction.stop_downloading.connect (on_stop_downloading);
			transaction.start_building.connect (on_start_building);
			transaction.stop_building.connect (on_stop_building);
			transaction.important_details_outpout.connect (on_important_details_outpout);
			transaction.transaction_sum_populated.connect (() => {
				// make buttons of pkgs in transaction unsensitive
				refresh_listbox_buttons ();
			});
			// in-app notification
			notification_button.clicked.connect (close_in_app_notification);

			// integrate progress box and term widget
			main_stack.add_named (transaction.details_window, "term");
			transaction_infobox.pack_start (transaction.progress_box);
			// integrate build files notebook
			build_files_box.add (transaction.build_files_notebook);

			display_package_queue = new Queue<AlpmPackage> ();
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
					|| browse_stack.visible_child_name == "search"
					|| browse_stack.visible_child_name == "installed")) {
					return searchbar.handle_event (event);
				}
				return false;
			});

			// create screenshots and icons tmp dir
			string[] tmp_dirs = {"/tmp/pamac-app-screenshots", "/tmp/pamac-app-icons"};
			foreach (unowned string tmp_dir in tmp_dirs) {
				var file = GLib.File.new_for_path (tmp_dir);
				if (!file.query_exists ()) {
					try {
						Process.spawn_command_line_sync ("mkdir -p %s".printf (tmp_dir));
						Process.spawn_command_line_sync ("chmod -R a+w %s".printf (tmp_dir));
					} catch (SpawnError e) {
						warning (e.message);
					}
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
			} catch (Error e) {
				warning (e.message);
			}
		}

		[GtkCallback]
		bool on_ManagerWindow_delete_event () {
			if (transaction_running || sysupgrade_running || generate_mirrors_list) {
				// do not close window
				return true;
			} else {
				// save window size
				var local_conf = new HashTable<string,Variant> (str_hash, str_equal);
				if (this.is_maximized) {
					local_conf.insert ("maximized", new Variant.boolean (true));
				} else {
					int width, height;
					this.get_size (out width, out height);
					local_conf.insert ("maximized", new Variant.boolean (false));
					local_conf.insert ("width", new Variant.uint64 (width));
					local_conf.insert ("height", new Variant.uint64 (height));
				}
				local_config.write (local_conf);
				// close window
				return false;
			}
		}

		void check_aur_support () {
			unowned Gtk.ListBoxRow updates_aur_row = updates_listbox.get_row_at_index (2);
			unowned Gtk.ListBoxRow pending_aur_row = pending_listbox.get_row_at_index (2);
			unowned Gtk.ListBoxRow search_aur_row = search_listbox.get_row_at_index (3);
			if (database.config.enable_aur) {
				updates_aur_row.visible = true;
				pending_aur_row.visible = true;
				search_aur_row.visible = true;
			} else {
				if (updates_listbox.get_selected_row ().get_index () == 2) {
					updates_listbox.select_row (updates_listbox.get_row_at_index (0));
				}
				if (pending_listbox.get_selected_row ().get_index () == 2) {
					pending_listbox.select_row (pending_listbox.get_row_at_index (0));
				}
				if (search_listbox.get_selected_row ().get_index () == 3) {
					search_listbox.select_row (search_listbox.get_row_at_index (0));
				}
				updates_aur_row.visible = false;
				pending_aur_row.visible = false;
				search_aur_row.visible = false;
			}
		}

		#if ENABLE_SNAP
		void check_snap_support () {
			unowned Gtk.ListBoxRow installed_snap_row = installed_listbox.get_row_at_index (installed_listbox_snap_index);
			unowned Gtk.ListBoxRow pending_snap_row = pending_listbox.get_row_at_index (pending_listbox_snap_index);
			unowned Gtk.ListBoxRow search_snap_row = search_listbox.get_row_at_index (search_listbox_snap_index);
			if (database.config.enable_snap) {
				installed_snap_row.visible = true;
				pending_snap_row.visible = true;
				search_snap_row.visible = true;
			} else {
				if (installed_listbox.get_selected_row ().get_index () == installed_listbox_snap_index) {
					installed_listbox.select_row (installed_listbox.get_row_at_index (0));
				}
				if (pending_listbox.get_selected_row ().get_index () == pending_listbox_snap_index) {
					pending_listbox.select_row (pending_listbox.get_row_at_index (0));
				}
				if (search_listbox.get_selected_row ().get_index () == search_listbox_snap_index) {
					search_listbox.select_row (search_listbox.get_row_at_index (0));
				}
				installed_snap_row.visible = false;
				pending_snap_row.visible = false;
				search_snap_row.visible = false;
			}
		}
		#endif

		#if ENABLE_FLATPAK
		void check_flatpak_support () {
			unowned Gtk.ListBoxRow updates_flatpak_row = updates_listbox.get_row_at_index (3);
			unowned Gtk.ListBoxRow installed_flatpak_row = installed_listbox.get_row_at_index (installed_listbox_flatpak_index);
			unowned Gtk.ListBoxRow pending_flatpak_row = pending_listbox.get_row_at_index (pending_listbox_flatpak_index);
			unowned Gtk.ListBoxRow search_flatpak_row = search_listbox.get_row_at_index (search_listbox_flatpak_index);
			if (database.config.enable_flatpak) {
				updates_flatpak_row.visible = true;
				installed_flatpak_row.visible = true;
				pending_flatpak_row.visible = true;
				search_flatpak_row.visible = true;
			} else {
				if (updates_listbox.get_selected_row ().get_index () == 3) {
					updates_listbox.select_row (updates_listbox.get_row_at_index (0));
				}
				if (installed_listbox.get_selected_row ().get_index () == installed_listbox_flatpak_index) {
					installed_listbox.select_row (installed_listbox.get_row_at_index (0));
				}
				if (pending_listbox.get_selected_row ().get_index () == pending_listbox_flatpak_index) {
					pending_listbox.select_row (pending_listbox.get_row_at_index (0));
				}
				if (search_listbox.get_selected_row ().get_index () == search_listbox_flatpak_index) {
					search_listbox.select_row (search_listbox.get_row_at_index (0));
				}
				updates_flatpak_row.visible = false;
				installed_flatpak_row.visible = false;
				pending_flatpak_row.visible = false;
				search_flatpak_row.visible = false;
			}
		}
		#endif

		void hide_sidebar () {
			sidebar_revealer.set_reveal_child (false);
		}

		void show_sidebar () {
			sidebar_revealer.set_reveal_child (true);
		}

		void set_pendings_operations () {
			if (!transaction_running && !generate_mirrors_list && !sysupgrade_running) {
				if (browse_stack.visible_child_name == "updates") {
					uint64 total_dsize = 0;
					for (uint i = 0; i < repos_updates.length; i++) {
						unowned AlpmPackage pkg = repos_updates[i];
						if (pkg.name in to_update) {
							total_dsize += pkg.download_size;
						}
					}
					if (total_dsize > 0) {
						transaction.progress_box.action_label.set_markup("<b>%s: %s</b>".printf (dgettext (null, "Total download size"), format_size (total_dsize)));
					} else {
						transaction.progress_box.action_label.label = "";
					}
					if (!transaction_running && !generate_mirrors_list && !sysupgrade_running
						&& (to_update.length > 0)) {
						apply_button.sensitive = true;
						apply_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
					} else {
						apply_button.sensitive = false;
						apply_button.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
					}
					cancel_button.sensitive = false;
				} else {
					uint total_pending = to_install.length +
										#if ENABLE_SNAP
										snap_to_install.length +
										snap_to_remove.length +
										#endif
										#if ENABLE_FLATPAK
										flatpak_to_install.length +
										flatpak_to_remove.length +
										#endif
										to_remove.length +
										to_build.length;
					if (total_pending == 0) {
						if (browse_stack.visible_child_name != "pending") {
							active_pending_stack (false);
						}
						transaction.progress_box.action_label.label = "";
						cancel_button.sensitive = false;
						apply_button.sensitive = false;
						apply_button.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
					} else {
						active_pending_stack (true);
						string info = dngettext (null, "%u pending operation", "%u pending operations", total_pending).printf (total_pending);
						transaction.progress_box.action_label.label = info;
						cancel_button.sensitive = true;
						apply_button.sensitive = true;
						apply_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
					}
				}
			}
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

		void active_pending_stack (bool active) {
			pending_listbox.visible = active;
		}

		void create_all_listbox () {
			repos_names = database.get_repos_names ();
			foreach (unowned string name in repos_names) {
				repos_listbox.add (create_list_row (name));
			}
			repos_listbox.select_row (repos_listbox.get_row_at_index (0));

			// use by sort_pkgs_by_repo
			#if ENABLE_SNAP
			repos_names.append (dgettext (null, "Snap"));
			#endif
			#if ENABLE_FLATPAK
			foreach (unowned string name in database.get_flatpak_remotes_names ()) {
				repos_names.append (name);
			}
			#endif
			repos_names.append (dgettext (null, "AUR"));

			foreach (unowned string name in database.get_groups_names ()) {
				groups_listbox.add (create_list_row (name));
			}
			groups_listbox.select_row (groups_listbox.get_row_at_index (0));

			#if ENABLE_SNAP
				installed_listbox_snap_index = 4;
				pending_listbox_snap_index = 3;
				search_listbox_snap_index = 4;
				#if ENABLE_FLATPAK
				installed_listbox_flatpak_index = 5;
				pending_listbox_flatpak_index = 4;
				search_listbox_flatpak_index = 5;
				#endif
			#elif ENABLE_FLATPAK
			installed_listbox_flatpak_index = 4;
			pending_listbox_flatpak_index = 3;
			search_listbox_flatpak_index = 4;
			#endif

			installed_listbox.add (create_list_row (dgettext (null, "All")));
			installed_listbox.add (create_list_row (dgettext (null, "Explicitly installed")));
			installed_listbox.add (create_list_row (dgettext (null, "Orphans")));
			installed_listbox.add (create_list_row (dgettext (null, "Foreign")));
			#if ENABLE_SNAP
			installed_listbox.add (create_list_row (dgettext (null, "Snap")));
			// related to #602 fix
			unowned Gtk.ListBoxRow snap_row = installed_listbox.get_row_at_index (installed_listbox_snap_index);
			snap_row.no_show_all = true;
			snap_row.get_child ().no_show_all = true;
			//
			#endif
			#if ENABLE_FLATPAK
			installed_listbox.add (create_list_row (dgettext (null, "Flatpak")));
			// related to #602 fix
			unowned Gtk.ListBoxRow flatpak_row = installed_listbox.get_row_at_index (installed_listbox_flatpak_index);
			flatpak_row.no_show_all = true;
			flatpak_row.get_child ().no_show_all = true;
			//
			#endif
			installed_listbox.select_row (installed_listbox.get_row_at_index (0));

			foreach (unowned string name in database.get_categories_names ()) {
				categories_listbox.add (create_list_row (dgettext (null, name)));
			}
			categories_listbox.select_row (categories_listbox.get_row_at_index (0));

			updates_listbox.add (create_list_row (dgettext (null, "All")));
			updates_listbox.add (create_list_row (dgettext (null, "Repositories")));
			updates_listbox.add (create_list_row (dgettext (null, "AUR")));
			// related to #602 fix
			unowned Gtk.ListBoxRow aur_row = updates_listbox.get_row_at_index (2);
			aur_row.no_show_all = true;
			aur_row.get_child ().no_show_all = true;
			//
			#if ENABLE_FLATPAK
			updates_listbox.add (create_list_row (dgettext (null, "Flatpak")));
			// related to #602 fix
			flatpak_row = updates_listbox.get_row_at_index (3);
			flatpak_row.no_show_all = true;
			flatpak_row.get_child ().no_show_all = true;
			//
			#endif
			updates_listbox.select_row (updates_listbox.get_row_at_index (0));

			pending_listbox.add (create_list_row (dgettext (null, "All")));
			pending_listbox.add (create_list_row (dgettext (null, "Repositories")));
			pending_listbox.add (create_list_row (dgettext (null, "AUR")));
			// related to #602 fix
			aur_row = pending_listbox.get_row_at_index (2);
			aur_row.no_show_all = true;
			aur_row.get_child ().no_show_all = true;
			//
			#if ENABLE_SNAP
			pending_listbox.add (create_list_row (dgettext (null, "Snap")));
			// related to #602 fix
			snap_row = pending_listbox.get_row_at_index (pending_listbox_snap_index);
			snap_row.no_show_all = true;
			snap_row.get_child ().no_show_all = true;
			//
			#endif
			#if ENABLE_FLATPAK
			pending_listbox.add (create_list_row (dgettext (null, "Flatpak")));
			// related to #602 fix
			flatpak_row = pending_listbox.get_row_at_index (pending_listbox_flatpak_index);
			flatpak_row.no_show_all = true;
			flatpak_row.get_child ().no_show_all = true;
			//
			#endif
			pending_listbox.select_row (pending_listbox.get_row_at_index (0));
			active_pending_stack (false);

			search_listbox.add (create_list_row (dgettext (null, "All")));
			search_listbox.add (create_list_row (dgettext (null, "Installed")));
			search_listbox.add (create_list_row (dgettext (null, "Repositories")));
			search_listbox.add (create_list_row (dgettext (null, "AUR")));
			// related to #602 fix
			aur_row = search_listbox.get_row_at_index (3);
			aur_row.no_show_all = true;
			aur_row.get_child ().no_show_all = true;
			//
			#if ENABLE_SNAP
			search_listbox.add (create_list_row (dgettext (null, "Snap")));
			// related to #602 fix
			snap_row = search_listbox.get_row_at_index (search_listbox_snap_index);
			snap_row.no_show_all = true;
			snap_row.get_child ().no_show_all = true;
			//
			#endif
			#if ENABLE_FLATPAK
			search_listbox.add (create_list_row (dgettext (null, "Flatpak")));
			// related to #602 fix
			flatpak_row = search_listbox.get_row_at_index (search_listbox_flatpak_index);
			flatpak_row.no_show_all = true;
			flatpak_row.get_child ().no_show_all = true;
			//
			#endif
			search_listbox.select_row (search_listbox.get_row_at_index (0));

			properties_listbox.add (create_list_row (dgettext (null, "Details")));
			deps_row = create_list_row (dgettext (null, "Dependencies"));
			properties_listbox.add (deps_row);
			files_row = create_list_row (dgettext (null, "Files"));
			properties_listbox.add (files_row);
			build_files_row = create_list_row (dgettext (null, "Build files"));
			properties_listbox.add (build_files_row);
			properties_listbox.select_row (properties_listbox.get_row_at_index (0));
		}

		void clear_packages_listbox () {
			packages_listbox.foreach (transaction.destroy_widget);
		}

		void clear_lists () {
			to_install.remove_all ();
			to_remove.remove_all ();
			to_build.remove_all ();
			to_load.remove_all ();
			#if ENABLE_SNAP
			snap_to_install.remove_all ();
			snap_to_remove.remove_all ();
			#endif
			#if ENABLE_FLATPAK
			flatpak_to_install.remove_all ();
			flatpak_to_remove.remove_all ();
			#endif
		}

		void clear_previous_lists () {
			previous_to_install.remove_all ();
			previous_to_remove.remove_all ();
			previous_to_build.remove_all ();
			#if ENABLE_SNAP
			previous_snap_to_install.remove_all ();
			previous_snap_to_remove.remove_all ();
			#endif
			#if ENABLE_FLATPAK
			previous_flatpak_to_install.remove_all ();
			previous_flatpak_to_remove.remove_all ();
			#endif
		}

		void on_mark_explicit_button_clicked (Gtk.Button button) {
			transaction.set_pkgreason (current_package_displayed.name, 0); //Alpm.Package.Reason.EXPLICIT
			refresh_details ();
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
					if (database.has_sync_satisfier (dep_button.label)) {
						AlpmPackage pkg = database.get_sync_satisfier (dep_button.label);
						dep_name = pkg.name;
					}
				}
			});
			return dep_name;
		}

		void on_install_dep_button_toggled (Gtk.ToggleButton button) {
			string dep_name = find_install_button_dep_name (button);
			if (button.active) {
				button.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
				to_install.add (dep_name);
			} else {
				button.image = null;
				to_install.remove (dep_name);
			}
			set_pendings_operations ();
		}

		[GtkCallback]
		void on_next_screenshot_button_clicked () {
			current_screenshots_index++;
			next_screenshot_button.sensitive = current_screenshots_index < current_screenshots.length - 1;
			previous_screenshot_button.sensitive = true;
			if (current_screenshots_index < current_screenshots.length) {
				screenshots_stack.visible_child_name = "%u".printf (current_screenshots_index);
			}
		}

		[GtkCallback]
		void on_previous_screenshot_button_clicked () {
			current_screenshots_index--;
			next_screenshot_button.sensitive = true;
			previous_screenshot_button.sensitive = current_screenshots_index > 0;
			if (current_screenshots_index < current_screenshots.length) {
				screenshots_stack.visible_child_name = "%u".printf (current_screenshots_index);
			}
		}

		Gtk.Widget populate_dep_grid (string dep_type, SList<string> dep_list, Gtk.Widget? previous_widget, bool add_install_button = false) {
			var label = new Gtk.Label ("<b>%s:</b>".printf (dep_type));
			label.use_markup = true;
			label.halign = Gtk.Align.START;
			label.valign = Gtk.Align.START;
			label.margin_top = 10;
			deps_grid.attach_next_to (label, previous_widget, Gtk.PositionType.BOTTOM);
			var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
			box.hexpand = true;
			foreach (unowned string dep in dep_list) {
				if (add_install_button) {
					var box2 = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
					box2.pack_start (new Gtk.Separator (Gtk.Orientation.VERTICAL));
					var box3 = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
					box3.homogeneous = false;
					var dep_button = new Gtk.Button.with_label (dep);
					dep_button.relief = Gtk.ReliefStyle.NONE;
					dep_button.valign = Gtk.Align.CENTER;
					dep_button.clicked.connect (on_dep_button_clicked);
					box3.pack_start (dep_button, false);
					if (!database.has_installed_satisfier (dep)) {
						var install_dep_button = new Gtk.ToggleButton.with_label (dgettext (null, "Install"));
						install_dep_button.always_show_image = true;
						install_dep_button.margin = 3;
						install_dep_button.toggled.connect (on_install_dep_button_toggled);
						box3.pack_end (install_dep_button, false);
						string dep_name = find_install_button_dep_name (install_dep_button);
						install_dep_button.active = (dep_name in to_install);
					}
					box2.pack_start (box3);
					box.pack_start (box2);
				} else {
					var box2 = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
					box2.pack_start (new Gtk.Separator (Gtk.Orientation.VERTICAL));
					var dep_button = new Gtk.Button.with_label (dep);
					dep_button.relief = Gtk.ReliefStyle.NONE;
					dep_button.halign = Gtk.Align.START;
					dep_button.valign = Gtk.Align.CENTER;
					dep_button.clicked.connect (on_dep_button_clicked);
					box2.pack_start (dep_button, false);
					box.pack_start (box2);
				}
			}
			deps_grid.attach_next_to (box, label, Gtk.PositionType.RIGHT);
			return label as Gtk.Widget;
		}

		async GenericArray<Gdk.Pixbuf> get_screenshots_pixbufs (SList<string> urls) {
			// keep a copy of urls because of async
			SList<string> urls_copy = urls.copy_deep (strdup);
			var pixbufs = new GenericArray<Gdk.Pixbuf> ();
			foreach (unowned string url in urls_copy) {
				var uri = File.new_for_uri (url);
				var cached_screenshot = File.new_for_path ("/tmp/pamac-app-screenshots/%s".printf (uri.get_basename ()));
				Gdk.Pixbuf pixbuf = null;
				if (cached_screenshot.query_exists ()) {
					try {
						pixbuf = new Gdk.Pixbuf.from_file (cached_screenshot.get_path ());
						pixbufs.add (pixbuf);
					} catch (Error e) {
						warning ("%s: %s", url, e.message);
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
							pixbufs.add (pixbuf);
						} catch (Error e) {
							warning ("%s: %s", url, e.message);
						}
					} catch (Error e) {
						warning ("%s: %s", url, e.message);
					}
				}
			}
			return pixbufs;
		}

		async Gdk.Pixbuf? get_icon_pixbuf (string url) {
			var uri = File.new_for_uri (url);
			var cached_icon = File.new_for_path ("/tmp/pamac-app-icons/%s".printf (uri.get_basename ()));
			Gdk.Pixbuf? pixbuf = null;
			if (cached_icon.query_exists ()) {
				try {
					pixbuf = new Gdk.Pixbuf.from_file (cached_icon.get_path ());
				} catch (Error e) {
					warning ("%s: %s", url, e.message);
				}
			} else {
				// download icon
				var session = new Soup.Session ();
				var utsname = Posix.utsname();
				session.user_agent = "pamac (%s %s)".printf (utsname.sysname, utsname.machine);
				try {
					var request = session.request (url);
					try {
						var inputstream = yield request.send_async (null);
						pixbuf = new Gdk.Pixbuf.from_stream (inputstream);
						// scale pixbux at 64 pixels
						int width = pixbuf.get_width ();
						if (width > 64) {
							pixbuf = pixbuf.scale_simple (64, 64, Gdk.InterpType.BILINEAR);
						}
						// save scaled image in tmp
						FileOutputStream os = cached_icon.append_to (FileCreateFlags.NONE);
						pixbuf.save_to_stream (os, "png");
					} catch (Error e) {
						warning ("%s: %s", url, e.message);
					}
				} catch (Error e) {
					warning ("%s: %s", url, e.message);
				}
			}
			return pixbuf;
		}

		void set_package_details (AlpmPackage pkg) {
			AURPackage? aur_pkg = null;
			if (pkg.repo == dgettext (null, "AUR")) {
				aur_pkg = database.get_aur_pkg (pkg.name);
			}
			// download screenshot
			screenshots_stack.foreach ((widget) => {
				if (widget is Gtk.Image) {
					widget.destroy ();
				}
			});
			previous_screenshot_button.visible = false;
			next_screenshot_button.visible = false;
			if (pkg.screenshots != null) {
				get_screenshots_pixbufs.begin (pkg.screenshots, (obj, res) => {
					current_screenshots = get_screenshots_pixbufs.end (res);
					current_screenshots_index = 0;
					screenshots_spinner.active = false;
					if (current_screenshots.length == 0) {
						screenshots_stack.visible = false;
						return;
					}
					uint i;
					for (i = 0; i < current_screenshots.length; i++) {
						var image = new Gtk.Image.from_pixbuf (current_screenshots[i]);
						image.visible = true;
						screenshots_stack.add_named (image, "%u".printf (i));
					}
					screenshots_spinner.active = false;
					screenshots_stack.visible_child_name = "0";
					if (current_screenshots.length > 1) {
						previous_screenshot_button.visible = true;
						previous_screenshot_button.sensitive = false;
						next_screenshot_button.visible = true;
						next_screenshot_button.sensitive = true;
					}
				});
				screenshots_stack.visible = true;
				screenshots_stack.visible_child_name = "spinner";
				screenshots_spinner.active = true;
			} else {
				screenshots_stack.visible = false;
			}
			// infos
			if (pkg.app_name == "") {
				name_label.set_markup ("<big><b>%s  %s</b></big>".printf (pkg.name, pkg.version));
				app_image.pixbuf = package_icon;
			} else {
				name_label.set_markup ("<big><b>%s (%s)  %s</b></big>".printf (Markup.escape_text (pkg.app_name), pkg.name, pkg.version));
				if (pkg.icon != "") {
					try {
						var pixbuf = new Gdk.Pixbuf.from_file (pkg.icon);
						app_image.pixbuf = pixbuf;
					} catch (Error e) {
						// some icons are not in the right repo
						string icon = pkg.icon;
						if ("extra" in pkg.icon) {
							icon = pkg.icon.replace ("extra", "community");
						} else if ("community" in pkg.icon) {
							icon = pkg.icon.replace ("community", "extra");
						}
						try {
							var pixbuf = new Gdk.Pixbuf.from_file (icon);
							app_image.pixbuf = pixbuf;
						} catch (Error e) {
							app_image.pixbuf = package_icon;
							warning ("%s: %s", pkg.icon, e.message);
						}
					}
				} else {
					app_image.pixbuf = package_icon;
				}
			}
			desc_label.set_text (pkg.desc);
			if (pkg.long_desc == "") {
				long_desc_label.visible = false;
			} else {
				long_desc_label.set_text (pkg.long_desc);
				long_desc_label.visible = true;
			}
			string escaped_url = Markup.escape_text (pkg.url);
			link_label.set_markup ("<a href=\"%s\">%s</a>".printf (escaped_url, escaped_url));
			if (pkg.installed_version != "") {
				if (pkg.launchable != "") {
					launch_button.visible = true;
					current_launchable = pkg.launchable;
				} else {
					launch_button.visible = false;
				}
				install_togglebutton.visible = false;
				build_togglebutton.visible = false;
				reset_files_button.visible = false;
				reinstall_togglebutton.visible = false;
				remove_togglebutton.visible = true;
				if (database.should_hold (pkg.name)) {
					remove_togglebutton.sensitive = false;
				} else {
					remove_togglebutton.sensitive = true;
					remove_togglebutton.active = to_remove.contains (pkg.name);
					if (aur_pkg == null) {
						if (pkg.repo != "") {
							reinstall_togglebutton.visible = true;
							reinstall_togglebutton.active = to_install.contains (pkg.name);
						}
					} else {
						// always show reinstall button for VCS package
						if (aur_pkg.name.has_suffix ("-git") ||
							aur_pkg.name.has_suffix ("-svn") ||
							aur_pkg.name.has_suffix ("-bzr") ||
							aur_pkg.name.has_suffix ("-hg") ||
							aur_pkg.version == pkg.version) {
							build_togglebutton.visible = true;
							build_togglebutton.active = to_build.contains (pkg.name);
						}
						build_files_row.visible = true;
						string aur_url = "http://aur.archlinux.org/packages/" + pkg.name;
						link_label.set_markup ("<a href=\"%s\">%s</a>\n\n<a href=\"%s\">%s</a>".printf (escaped_url, escaped_url, aur_url, aur_url));
					}
				}
			} else {
				launch_button.visible = false;
				remove_togglebutton.visible = false;
				reinstall_togglebutton.visible = false;
				build_togglebutton.visible = false;
				reset_files_button.visible = false;
				install_togglebutton.visible = true;
				install_togglebutton.active = to_install.contains (pkg.name);
			}
			// details
			details_grid.foreach (transaction.destroy_widget);
			StringBuilder licenses = new StringBuilder ();
			foreach (unowned string name in pkg.licenses) {
				if (licenses.len > 0) {
					licenses.append ("  ");
				}
				licenses.append (name);
			}
			Gtk.Widget? previous_widget = null;
			previous_widget = populate_details_grid (dgettext (null, "Licenses"), licenses.str, previous_widget);
			if (pkg.repo != "") {
				previous_widget = populate_details_grid (dgettext (null, "Repository"), pkg.repo, previous_widget);
			}
			if (aur_pkg != null) {
				if (aur_pkg.packagebase != pkg.name) {
					previous_widget = populate_details_grid (dgettext (null, "Package Base"), aur_pkg.packagebase, previous_widget);
				}
				if (aur_pkg.maintainer != "") {
					previous_widget = populate_details_grid (dgettext (null, "Maintainer"), aur_pkg.maintainer, previous_widget);
				}
				if (aur_pkg.firstsubmitted != 0) {
					var time = GLib.Time.local ((time_t) aur_pkg.firstsubmitted);
					previous_widget = populate_details_grid (dgettext (null, "First Submitted"), time.format ("%x"), previous_widget);
				}
				if (aur_pkg.lastmodified != 0) {
					var time = GLib.Time.local ((time_t) aur_pkg.lastmodified);
					previous_widget = populate_details_grid (dgettext (null, "Last Modified"), time.format ("%x"), previous_widget);
				}
				if (aur_pkg.numvotes != 0) {
					previous_widget = populate_details_grid (dgettext (null, "Votes"), aur_pkg.numvotes.to_string (), previous_widget);
				}
				if (aur_pkg.outofdate != 0) {
					var time = GLib.Time.local ((time_t) aur_pkg.outofdate);
					previous_widget = populate_details_grid (dgettext (null, "Out of Date"), time.format ("%x"), previous_widget);
				}
			}
			if (pkg.groups != null) {
				var label = new Gtk.Label ("<b>%s</b>".printf (dgettext (null, "Groups") + ":"));
				label.use_markup = true;
				label.halign = Gtk.Align.START;
				label.valign = Gtk.Align.START;
				details_grid.attach_next_to (label, previous_widget, Gtk.PositionType.BOTTOM);
				var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
				foreach (unowned string name in pkg.groups) {
					var label2 = new Gtk.Label (name);
					label2.halign = Gtk.Align.START;
					box.pack_start (label2);
				}
				details_grid.attach_next_to (box, label, Gtk.PositionType.RIGHT);
				previous_widget = label as Gtk.Widget;
			}
			// make packager mail clickable
			string[] splitted = pkg.packager.split ("<", 2);
			unowned string packager_name = splitted[0];
			if (splitted.length > 1) {
				string packager_mail = splitted[1].split (">", 2)[0];
				string packager_detail = "%s <a href=\"mailto:%s\">%s</a>".printf (packager_name, packager_mail, packager_mail);
				previous_widget = populate_details_grid (dgettext (null, "Packager"), packager_detail, previous_widget);
			} else {
				previous_widget = populate_details_grid (dgettext (null, "Packager"), pkg.packager, previous_widget);
			}
			var time = GLib.Time.local ((time_t) pkg.builddate);
			previous_widget = populate_details_grid (dgettext (null, "Build Date"), time.format ("%x"), previous_widget);
			if (pkg.installdate != 0) {
				time = GLib.Time.local ((time_t) pkg.installdate);
				previous_widget = populate_details_grid (dgettext (null, "Install Date"), time.format ("%x"), previous_widget);
			}
			if (pkg.reason != "") {
				previous_widget = populate_details_grid (dgettext (null, "Install Reason"), pkg.reason, previous_widget);
			}
			if (pkg.has_signature != "") {
				previous_widget = populate_details_grid (dgettext (null, "Signatures"), pkg.has_signature, previous_widget);
			}
			if (pkg.backups != null) {
				var label = new Gtk.Label ("<b>%s</b>".printf (dgettext (null, "Backup files") + ":"));
				label.use_markup = true;
				label.halign = Gtk.Align.START;
				label.valign = Gtk.Align.START;
				details_grid.attach_next_to (label, previous_widget, Gtk.PositionType.BOTTOM);
				var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
				foreach (unowned string name in pkg.backups) {
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
			if (pkg.depends != null) {
				previous_widget = populate_dep_grid (dgettext (null, "Depends On"), pkg.depends, previous_widget);
			}
			if (pkg.optdepends != null) {
				previous_widget = populate_dep_grid (dgettext (null, "Optional Dependencies"), pkg.optdepends, previous_widget, true);
			}
			if (pkg.requiredby != null) {
				previous_widget = populate_dep_grid (dgettext (null, "Required By"), pkg.requiredby, previous_widget);
			}
			if (pkg.optionalfor != null) {
				previous_widget = populate_dep_grid (dgettext (null, "Optional For"), pkg.optionalfor, previous_widget);
			}
			if (pkg.provides != null) {
				previous_widget = populate_dep_grid (dgettext (null, "Provides"), pkg.provides, previous_widget);
			}
			if (pkg.replaces != null) {
				previous_widget = populate_dep_grid (dgettext (null, "Replaces"), pkg.replaces, previous_widget);
			}
			if (pkg.conflicts != null) {
				previous_widget = populate_dep_grid (dgettext (null, "Conflicts With"), pkg.conflicts, previous_widget);
			}
			// add a bottom separator
			if (previous_widget != null) {
				var empty_label = new Gtk.Label ("");
				deps_grid.attach_next_to (empty_label, previous_widget, Gtk.PositionType.BOTTOM);
				var bottom_separator = new Gtk.Separator (Gtk.Orientation.VERTICAL);
				bottom_separator.valign = Gtk.Align.START;
				deps_grid.attach_next_to (bottom_separator, empty_label, Gtk.PositionType.RIGHT);
			}
			deps_grid.show_all ();
			// files
			// will be populated on properties_stack switch
			if (properties_stack.visible_child_name == "files") {
				properties_listbox.get_row_at_index (2).activate ();
			}
		}

		void set_aur_details (AURPackage aur_pkg) {
			details_grid.foreach (transaction.destroy_widget);
			deps_grid.foreach (transaction.destroy_widget);
			screenshots_stack.foreach (transaction.destroy_widget);
			previous_screenshot_button.visible = false;
			next_screenshot_button.visible = false;
			launch_button.visible = false;
			remove_togglebutton.visible = false;
			reinstall_togglebutton.visible = false;
			install_togglebutton.visible = false;
			reset_files_button.visible = false;
			// first infos
			name_label.set_markup ("<big><b>%s  %s</b></big>".printf (aur_pkg.name, aur_pkg.version));
			app_image.pixbuf = package_icon;
			desc_label.set_text (aur_pkg.desc);
			long_desc_label.visible = false;
			build_togglebutton.visible = true;
			build_togglebutton.active = to_build.contains (aur_pkg.name);
			if (database.is_installed_pkg (aur_pkg.name)) {
				remove_togglebutton.visible = true;
				remove_togglebutton.active = to_remove.contains (aur_pkg.name);
			}
			// infos
			string aur_url = "http://aur.archlinux.org/packages/" + aur_pkg.name;
			string escaped_url = Markup.escape_text (aur_pkg.url);
			link_label.set_markup ("<a href=\"%s\">%s</a>\n\n<a href=\"%s\">%s</a>".printf (escaped_url, escaped_url, aur_url, aur_url));
			// details
			properties_listbox.visible = true;
			StringBuilder licenses = new StringBuilder ();
			foreach (unowned string name in aur_pkg.licenses) {
				if (licenses.len > 0) {
					licenses.append ("  ");
				}
				licenses.append (name);
			}
			Gtk.Widget? previous_widget = null;
			previous_widget = populate_details_grid (dgettext (null, "Licenses"), licenses.str, previous_widget);
			previous_widget = populate_details_grid (dgettext (null, "Repository"), aur_pkg.repo, previous_widget);
			if (aur_pkg.packagebase != aur_pkg.name) {
				previous_widget = populate_details_grid (dgettext (null, "Package Base"), aur_pkg.packagebase, previous_widget);
			}
			if (aur_pkg.maintainer != "") {
				previous_widget = populate_details_grid (dgettext (null, "Maintainer"), aur_pkg.maintainer, previous_widget);
			}
			if (aur_pkg.firstsubmitted != 0) {
				var time = GLib.Time.local ((time_t) aur_pkg.firstsubmitted);
				previous_widget = populate_details_grid (dgettext (null, "First Submitted"), time.format ("%x"), previous_widget);
			}
			if (aur_pkg.lastmodified != 0) {
				var time = GLib.Time.local ((time_t) aur_pkg.lastmodified);
				previous_widget = populate_details_grid (dgettext (null, "Last Modified"), time.format ("%x"), previous_widget);
			}
			previous_widget = populate_details_grid (dgettext (null, "Votes"), aur_pkg.numvotes.to_string (), previous_widget);
			if (aur_pkg.outofdate != 0) {
				var time = GLib.Time.local ((time_t) aur_pkg.outofdate);
				previous_widget = populate_details_grid (dgettext (null, "Out of Date"), time.format ("%x"), previous_widget);
			}
			if (aur_pkg.packager != "") {
				// make packager mail clickable
				string[] splitted = aur_pkg.packager.split ("<", 2);
				unowned string packager_name = splitted[0];
				if (splitted.length > 1) {
					string packager_mail = splitted[1].split (">", 2)[0];
					string packager_detail = "%s <a href=\"mailto:%s\">%s</a>".printf (packager_name, packager_mail, packager_mail);
					previous_widget = populate_details_grid (dgettext (null, "Packager"), packager_detail, previous_widget);
				} else {
					previous_widget = populate_details_grid (dgettext (null, "Packager"), aur_pkg.packager, previous_widget);
				}
			}
			if (aur_pkg.builddate != 0) {
				var time = GLib.Time.local ((time_t) aur_pkg.builddate);
				previous_widget = populate_details_grid (dgettext (null, "Build Date"), time.format ("%x"), previous_widget);
			}
			if (aur_pkg.installdate != 0) {
				var time = GLib.Time.local ((time_t) aur_pkg.installdate);
				previous_widget = populate_details_grid (dgettext (null, "Install Date"), time.format ("%x"), previous_widget);
			}
			if (aur_pkg.reason != "") {
				previous_widget = populate_details_grid (dgettext (null, "Install Reason"), aur_pkg.reason, previous_widget);
			}
			if (aur_pkg.has_signature != "") {
				previous_widget = populate_details_grid (dgettext (null, "Signatures"), aur_pkg.has_signature, previous_widget);
			}
			if (aur_pkg.backups != null) {
				var label = new Gtk.Label ("<b>%s</b>".printf (dgettext (null, "Backup files") + ":"));
				label.use_markup = true;
				label.halign = Gtk.Align.START;
				label.valign = Gtk.Align.START;
				details_grid.attach_next_to (label, previous_widget, Gtk.PositionType.BOTTOM);
				var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
				foreach (unowned string name in aur_pkg.backups) {
					var label2 = new Gtk.Label (name);
					label2.halign = Gtk.Align.START;
					box.pack_start (label2);
				}
				details_grid.attach_next_to (box, label, Gtk.PositionType.RIGHT);
			}
			details_grid.show_all ();
			// deps
			previous_widget = null;
			if (aur_pkg.depends != null) {
				previous_widget = populate_dep_grid (dgettext (null, "Depends On"), aur_pkg.depends, previous_widget);
			}
			if (aur_pkg.makedepends != null) {
				previous_widget = populate_dep_grid (dgettext (null, "Make Dependencies"), aur_pkg.makedepends, previous_widget);
			}
			if (aur_pkg.checkdepends != null) {
				previous_widget = populate_dep_grid (dgettext (null, "Check Dependencies"), aur_pkg.checkdepends, previous_widget);
			}
			if (aur_pkg.optdepends != null) {
				previous_widget = populate_dep_grid (dgettext (null, "Optional Dependencies"), aur_pkg.optdepends, previous_widget);
			}
			if (aur_pkg.provides != null) {
				previous_widget = populate_dep_grid (dgettext (null, "Provides"), aur_pkg.provides, previous_widget);
			}
			if (aur_pkg.replaces != null) {
				previous_widget = populate_dep_grid (dgettext (null, "Replaces"), aur_pkg.replaces, previous_widget);
			}
			if (aur_pkg.conflicts != null) {
				previous_widget = populate_dep_grid (dgettext (null, "Conflicts With"), aur_pkg.conflicts, previous_widget);
			}
			// add a bottom separator
			if (previous_widget != null) {
				var empty_label = new Gtk.Label ("");
				deps_grid.attach_next_to (empty_label, previous_widget, Gtk.PositionType.BOTTOM);
				var bottom_separator = new Gtk.Separator (Gtk.Orientation.VERTICAL);
				bottom_separator.valign = Gtk.Align.START;
				deps_grid.attach_next_to (bottom_separator, empty_label, Gtk.PositionType.RIGHT);
			}
			deps_grid.show_all ();
			// build files
			// will be populated on properties_stack switch
			if (properties_stack.visible_child_name == "build_files") {
				properties_listbox.get_row_at_index (3).activate ();
			}
		}

		#if ENABLE_SNAP
		void set_snap_details (SnapPackage snap_pkg) {
			// download screenshot
			screenshots_stack.foreach ((widget) => {
				if (widget is Gtk.Image) {
					widget.destroy ();
				}
			});
			previous_screenshot_button.visible = false;
			next_screenshot_button.visible = false;
			if (snap_pkg.screenshots != null) {
				get_screenshots_pixbufs.begin (snap_pkg.screenshots, (obj, res) => {
					current_screenshots = get_screenshots_pixbufs.end (res);
					current_screenshots_index = 0;
					screenshots_spinner.active = false;
					if (current_screenshots.length == 0) {
						screenshots_stack.visible = false;
						return;
					}
					uint i;
					for (i = 0; i < current_screenshots.length; i++) {
						var image = new Gtk.Image.from_pixbuf (current_screenshots[i]);
						image.visible = true;
						screenshots_stack.add_named (image, "%u".printf (i));
					}
					screenshots_spinner.active = false;
					screenshots_stack.visible_child_name = "0";
					if (current_screenshots.length > 1) {
						previous_screenshot_button.visible = true;
						previous_screenshot_button.sensitive = false;
						next_screenshot_button.visible = true;
						next_screenshot_button.sensitive = true;
					}
				});
				screenshots_stack.visible = true;
				screenshots_stack.visible_child_name = "spinner";
				screenshots_spinner.active = true;
			} else {
				screenshots_stack.visible = false;
			}
			// infos
			name_label.set_markup ("<big><b>%s  %s</b></big>".printf (Markup.escape_text (snap_pkg.app_name), snap_pkg.version));
			if (snap_pkg.icon != "") {
				if ("http" in snap_pkg.icon) {
					app_image.pixbuf = package_icon;
					get_icon_pixbuf.begin (snap_pkg.icon, (obj, res) => {
						app_image.pixbuf = get_icon_pixbuf.begin.end (res);
					});
				} else {
					try {
						var pixbuf = new Gdk.Pixbuf.from_file (snap_pkg.icon);
						app_image.pixbuf = pixbuf;
					} catch (Error e) {
						app_image.pixbuf = package_icon;
						// try to retrieve icon
						try {
							string downloaded_pixbuf_path = database.get_installed_snap_icon (snap_pkg.name);
							app_image.pixbuf = new Gdk.Pixbuf.from_file_at_scale (downloaded_pixbuf_path, 64, 64, true);
						} catch (Error e) {
							warning ("%s: %s", snap_pkg.name, e.message);
						}
					}
				}
			} else {
				app_image.pixbuf = package_icon;
			}
			desc_label.set_text (snap_pkg.desc);
			if (snap_pkg.long_desc == "") {
				long_desc_label.visible = false;
			} else {
				long_desc_label.set_text (snap_pkg.long_desc);
				long_desc_label.visible = true;
			}
			string escaped_url = Markup.escape_text (snap_pkg.url);
			link_label.set_markup ("<a href=\"%s\">%s</a>".printf (escaped_url, escaped_url));
			if (snap_pkg.installed_version != "") {
				if (snap_pkg.launchable != "") {
					launch_button.visible = true;
					current_launchable = snap_pkg.launchable;
				} else {
					launch_button.visible = false;
				}
				install_togglebutton.visible = false;
				build_togglebutton.visible = false;
				reset_files_button.visible = false;
				reinstall_togglebutton.visible = false;
				remove_togglebutton.visible = true;
				remove_togglebutton.sensitive = true;
				remove_togglebutton.active = snap_to_remove.contains (snap_pkg.name);
			} else {
				launch_button.visible = false;
				remove_togglebutton.visible = false;
				reinstall_togglebutton.visible = false;
				build_togglebutton.visible = false;
				reset_files_button.visible = false;
				install_togglebutton.visible = true;
				install_togglebutton.active = snap_to_install.contains (snap_pkg.name);
			}
			// details
			details_grid.foreach (transaction.destroy_widget);
			Gtk.Widget? previous_widget = null;
			if (snap_pkg.license != "") {
				previous_widget = populate_details_grid (dgettext (null, "Licenses"), snap_pkg.license, previous_widget);
			}
			previous_widget = populate_details_grid (dgettext (null, "Repository"), snap_pkg.repo, previous_widget);
			// make packager mail clickable
			if (snap_pkg.publisher != "") {
				previous_widget = populate_details_grid (dgettext (null, "Publisher"), snap_pkg.publisher, previous_widget);
			}
			if (snap_pkg.confined != "") {
				previous_widget = populate_details_grid (dgettext (null, "Confined in a Sandbox"), snap_pkg.confined, previous_widget);
			}
			if (snap_pkg.installdate != 0) {
				var time = GLib.Time.local ((time_t) snap_pkg.installdate);
				previous_widget = populate_details_grid (dgettext (null, "Install Date"), time.format ("%x"), previous_widget);
			}
			if (snap_pkg.channels != null) {
				var label = new Gtk.Label ("<b>%s</b>".printf (dgettext (null, "Channels") + ":"));
				label.use_markup = true;
				label.halign = Gtk.Align.START;
				label.valign = Gtk.Align.START;
				details_grid.attach_next_to (label, previous_widget, Gtk.PositionType.BOTTOM);
				var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
				foreach (unowned string channel in snap_pkg.channels) {
					string[] split = channel.split (": ", 2);
					unowned string channel_name = split[0];
					if (snap_pkg.channel != channel_name) {
						var box2 = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
						box2.homogeneous = false;
						var label2 = new Gtk.Label (channel);
						label2.halign = Gtk.Align.START;
						box2.pack_start (label2);
						var install_button = new Gtk.Button.with_label (dgettext (null, "Install"));
						install_button.margin = 3;
						if (transaction_running || sysupgrade_running || generate_mirrors_list) {
							install_button.sensitive = false;
						} else {
							install_button.clicked.connect ((button) => {
								transaction_running = true;
								set_snap_details (snap_pkg);
								transaction.snap_switch_channel (snap_pkg.name, channel_name);
								transaction_running = false;
								transaction.reset_progress_box ();
								if (current_package_displayed.name == snap_pkg.name) {
									set_snap_details (database.get_snap (snap_pkg.name));
								}
							});
						}
						box2.pack_end (install_button, false);
						box.pack_start (box2);
					} else {
						var label2 = new Gtk.Label (channel);
						label2.halign = Gtk.Align.START;
						box.pack_start (label2);
					}
				}
				details_grid.attach_next_to (box, label, Gtk.PositionType.RIGHT);
			}
			details_grid.show_all ();
			// deps
			deps_grid.foreach (transaction.destroy_widget);
		}
		#endif

		#if ENABLE_FLATPAK
		void set_flatpak_details (FlatpakPackage flatpak_pkg) {
			// download screenshot
			screenshots_stack.foreach ((widget) => {
				if (widget is Gtk.Image) {
					widget.destroy ();
				}
			});
			previous_screenshot_button.visible = false;
			next_screenshot_button.visible = false;
			if (flatpak_pkg.screenshots != null) {
				get_screenshots_pixbufs.begin (flatpak_pkg.screenshots, (obj, res) => {
					current_screenshots = get_screenshots_pixbufs.end (res);
					current_screenshots_index = 0;
					screenshots_spinner.active = false;
					if (current_screenshots.length == 0) {
						screenshots_stack.visible = false;
						return;
					}
					uint i;
					for (i = 0; i < current_screenshots.length; i++) {
						var image = new Gtk.Image.from_pixbuf (current_screenshots[i]);
						image.visible = true;
						screenshots_stack.add_named (image, "%u".printf (i));
					}
					screenshots_spinner.active = false;
					screenshots_stack.visible_child_name = "0";
					if (current_screenshots.length > 1) {
						previous_screenshot_button.visible = true;
						previous_screenshot_button.sensitive = false;
						next_screenshot_button.visible = true;
						next_screenshot_button.sensitive = true;
					}
				});
				screenshots_stack.visible = true;
				screenshots_stack.visible_child_name = "spinner";
				screenshots_spinner.active = true;
			} else {
				screenshots_stack.visible = false;
			}
			// infos
			name_label.set_markup ("<big><b>%s  %s</b></big>".printf (Markup.escape_text (flatpak_pkg.app_name), flatpak_pkg.version));
			if (flatpak_pkg.icon != "") {
				try {
					var pixbuf = new Gdk.Pixbuf.from_file (flatpak_pkg.icon);
					app_image.pixbuf = pixbuf;
				} catch (Error e) {
					app_image.pixbuf = package_icon;
				}
			} else {
				app_image.pixbuf = package_icon;
			}
			desc_label.set_text (flatpak_pkg.desc);
			if (flatpak_pkg.long_desc == "") {
				long_desc_label.visible = false;
			} else {
				long_desc_label.set_text (flatpak_pkg.long_desc);
				long_desc_label.visible = true;
			}
			string escaped_url = Markup.escape_text (flatpak_pkg.url);
			link_label.set_markup ("<a href=\"%s\">%s</a>".printf (escaped_url, escaped_url));
			if (flatpak_pkg.installed_version != "") {
				if (flatpak_pkg.launchable != "") {
					launch_button.visible = true;
					current_launchable = flatpak_pkg.launchable;
				} else {
					launch_button.visible = false;
				}
				install_togglebutton.visible = false;
				build_togglebutton.visible = false;
				reset_files_button.visible = false;
				reinstall_togglebutton.visible = false;
				remove_togglebutton.visible = true;
				remove_togglebutton.sensitive = true;
				remove_togglebutton.active = flatpak_to_remove.contains (flatpak_pkg.name);
			} else {
				launch_button.visible = false;
				remove_togglebutton.visible = false;
				reinstall_togglebutton.visible = false;
				build_togglebutton.visible = false;
				reset_files_button.visible = false;
				install_togglebutton.visible = true;
				install_togglebutton.active = flatpak_to_install.contains (flatpak_pkg.name);
			}
			// details
			details_grid.foreach (transaction.destroy_widget);
			Gtk.Widget? previous_widget = null;
			if (flatpak_pkg.license != "") {
				previous_widget = populate_details_grid (dgettext (null, "Licenses"), flatpak_pkg.license, previous_widget);
			}
			previous_widget = populate_details_grid (dgettext (null, "Repository"), flatpak_pkg.repo, previous_widget);
			details_grid.show_all ();
			// deps
			deps_grid.foreach (transaction.destroy_widget);
		}
		#endif

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
					if (current_files != current_package_displayed.name) {
						this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
						var files = database.get_pkg_files (current_package_displayed.name);
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
						current_files = current_package_displayed.name;
					} else {
						properties_stack.visible_child_name = "files";
					}
					break;
				case 3: // build files
					reset_files_button.visible = true;
					if (current_build_files != current_package_displayed.name) {
						this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
						AURPackage pkg = database.get_aur_pkg (current_package_displayed.name);
						if (pkg != null) {
							transaction.populate_build_files.begin (pkg.packagebase, true, false, () => {
								this.get_window ().set_cursor (null);
							});
							properties_stack.visible_child_name = "build_files";
						} else {
							this.get_window ().set_cursor (null);
						}
						current_build_files = current_package_displayed.name;
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
				Process.spawn_command_line_async ("gtk-launch %s".printf (current_launchable));
			} catch (SpawnError e) {
				warning (e.message);
			}
		}

		[GtkCallback]
		void on_install_togglebutton_toggled () {
			if (install_togglebutton.active) {
				install_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
				#if ENABLE_SNAP
				if (current_package_displayed is SnapPackage)
					snap_to_install.insert (current_package_displayed.name, current_package_displayed as SnapPackage);
				else
				#endif
				#if ENABLE_FLATPAK
				if (current_package_displayed is FlatpakPackage)
					flatpak_to_install.insert (current_package_displayed.name, current_package_displayed as FlatpakPackage);
				else
				#endif
				to_install.add (current_package_displayed.name);
			} else {
				install_togglebutton.image = null;
				#if ENABLE_SNAP
				if (current_package_displayed is SnapPackage)
					snap_to_install.remove (current_package_displayed.name);
				else
				#endif
				#if ENABLE_FLATPAK
				if (current_package_displayed is FlatpakPackage)
					flatpak_to_install.remove (current_package_displayed.name);
				else
				#endif
				to_install.remove (current_package_displayed.name);
			}
			set_pendings_operations ();
			refresh_listbox_buttons ();
		}

		[GtkCallback]
		void on_build_togglebutton_toggled () {
			if (build_togglebutton.active) {
				build_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
				to_build.add (current_package_displayed.name);
				if (properties_stack.visible_child_name == "build_files") {
					transaction.save_build_files.begin (current_package_displayed.name);
				}
			} else {
				build_togglebutton.image = null;
				to_build.remove (current_package_displayed.name);
			}
			set_pendings_operations ();
			refresh_listbox_buttons ();
		}

		[GtkCallback]
		void on_reset_files_button_clicked () {
			var aur_pkg = current_package_displayed as AURPackage;
			transaction.populate_build_files.begin (aur_pkg.packagebase, true, true);
		}

		[GtkCallback]
		void on_remove_togglebutton_toggled () {
			if (remove_togglebutton.active) {
				reinstall_togglebutton.active = false;
				reinstall_togglebutton.image = null;
				remove_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
				#if ENABLE_SNAP
				if (current_package_displayed is SnapPackage) {
					snap_to_install.remove (current_package_displayed.name);
					snap_to_remove.insert (current_package_displayed.name, current_package_displayed as SnapPackage);
				} else
				#endif
				#if ENABLE_FLATPAK
				if (current_package_displayed is FlatpakPackage) {
					flatpak_to_install.remove (current_package_displayed.name);
					flatpak_to_remove.insert (current_package_displayed.name, current_package_displayed as FlatpakPackage);
				} else
				#endif
				#if ENABLE_SNAP || ENABLE_FLATPAK
				{
				#endif
					to_install.remove (current_package_displayed.name);
					to_remove.add (current_package_displayed.name);
				#if ENABLE_SNAP || ENABLE_FLATPAK
				}
				#endif
			} else {
				remove_togglebutton.image = null;
				#if ENABLE_SNAP
				if (current_package_displayed is SnapPackage)
					snap_to_remove.remove (current_package_displayed.name);
				else
				#endif
				#if ENABLE_FLATPAK
				if (current_package_displayed is FlatpakPackage)
					flatpak_to_remove.remove (current_package_displayed.name);
				else
				#endif
				to_remove.remove (current_package_displayed.name);
			}
			set_pendings_operations ();
			refresh_listbox_buttons ();
		}

		[GtkCallback]
		void on_reinstall_togglebutton_toggled () {
			if (reinstall_togglebutton.active) {
				remove_togglebutton.active = false;
				remove_togglebutton.image = null;
				reinstall_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
				to_remove.remove (current_package_displayed.name);
				if (current_package_displayed is AURPackage) {
					// availability in AUR was checked in set_package_details
					to_build.add (current_package_displayed.name);
				} else {
					to_install.add (current_package_displayed.name);
				}
			} else {
				reinstall_togglebutton.image = null;
				to_install.remove (current_package_displayed.name);
				to_build.remove (current_package_displayed.name);
			}
			set_pendings_operations ();
			refresh_listbox_buttons ();
		}

		void populate_listbox (owned SList<Package> pkgs) {
			// populate listbox
			if (pkgs == null) {
				origin_stack.visible_child_name = "no_item";
				this.get_window ().set_cursor (null);
				return;
			} else {
				clear_packages_listbox ();
				origin_stack.visible_child_name = "repos";
			}
			current_packages_list = (owned) pkgs;
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

		void sort_aur_list (ref SList<AURPackage> pkgs) {
			unowned string sortby = sortby_button_label.label;
			if (sortby == dgettext (null, "Relevance")) {
				pkgs.sort (sort_aur_by_relevance);
			} else if (sortby == dgettext (null, "Name")) {
				pkgs.sort (sort_pkgs_by_name);
			} else if (sortby == dgettext (null, "Repository")) {
				pkgs.sort (sort_pkgs_by_repo);
			} else if (sortby == dgettext (null, "Size")) {
				pkgs.sort (sort_pkgs_by_installed_size);
			} else if (sortby == dgettext (null, "Date")) {
				pkgs.sort (sort_aur_by_date);
			}
		}

		void populate_aur_list (owned SList<AURPackage> pkgs) {
			sort_aur_list (ref pkgs);
			populate_listbox ((owned) pkgs);
		}

		void sort_packages_list (ref SList<Package> pkgs) {
			unowned string sortby = sortby_button_label.label;
			if (sortby == dgettext (null, "Relevance")) {
				if (browse_stack.visible_child_name == "search") {
					pkgs.sort (sort_search_pkgs_by_relevance);
				} else {
					pkgs.sort (sort_pkgs_by_relevance);
				}
			} else if (sortby == dgettext (null, "Name")) {
				pkgs.sort (sort_pkgs_by_name);
			} else if (sortby == dgettext (null, "Repository")) {
				pkgs.sort (sort_pkgs_by_repo);
			} else if (sortby == dgettext (null, "Size")) {
				if (browse_stack.visible_child_name == "updates") {
					pkgs.sort (sort_pkgs_by_download_size);
				} else {
					pkgs.sort (sort_pkgs_by_installed_size);
				}
			} else if (sortby == dgettext (null, "Date")) {
				pkgs.sort (sort_pkgs_by_date);
			}
		}

		void populate_packages_list (owned SList<Package> pkgs) {
			sort_packages_list (ref pkgs);
			populate_listbox ((owned) pkgs);
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
			}
		}

		void create_packagelist_row (Package pkg) {
			bool is_update = browse_stack.visible_child_name == "updates";
			var row = new PackageRow (pkg);
			//populate info
			if (pkg.app_name == "") {
				row.name_label.set_markup ("<b>%s</b>".printf (pkg.name));
			} else {
				row.name_label.set_markup ("<b>%s (%s)</b>".printf (Markup.escape_text (pkg.app_name), pkg.name));
			}
			row.desc_label.label = pkg.desc;
			if (is_update) {
				#if ENABLE_FLATPAK
				if (pkg is FlatpakPackage)
					row.version_label.set_markup ("<b>%s</b>".printf (pkg.version));
				else
				#endif
				row.version_label.set_markup ("<b>%s  (%s)</b>".printf (pkg.version, pkg.installed_version));
				if (pkg.download_size == 0) {
					row.size_label.label = "";
				} else {
					row.size_label.set_markup ("<span foreground='grey'>%s</span>".printf (GLib.format_size (pkg.download_size)));
				}
			} else {
				row.version_label.set_markup ("<b>%s</b>".printf (pkg.version));
				if (pkg.installed_size == 0) {
					row.size_label.label = "";
				} else {
					row.size_label.set_markup ("<span foreground='grey'>%s</span>".printf (GLib.format_size (pkg.installed_size)));
				}
			}
			if (pkg is AlpmPackage) {
				if (pkg.repo == "community" || pkg.repo == "extra" || pkg.repo == "core" || pkg.repo == "multilib") {
					row.repo_label.set_markup ("<span foreground='grey'>%s</span>".printf (dgettext (null, "Official Repositories")));
				} else if (pkg.repo == dgettext (null, "AUR")) {
					row.repo_label.set_markup ("<span foreground='grey'>%s</span>".printf (pkg.repo));
				} else if (pkg.repo != "") {
					row.repo_label.set_markup ("<span foreground='grey'>%s (%s)</span>".printf (dgettext (null, "Repository"), pkg.repo));
				}
			#if ENABLE_FLATPAK
			} else if (pkg is FlatpakPackage) {
				row.repo_label.set_markup ("<span foreground='grey'>%s (%s)</span>".printf (dgettext (null, "Flatpak"), pkg.repo));
			#endif
			} else {
				row.repo_label.set_markup ("<span foreground='grey'>%s</span>".printf (pkg.repo));
			}
			Gdk.Pixbuf pixbuf;
			if (pkg.icon != "") {
				if ("http" in pkg.icon) {
					pixbuf = package_icon.scale_simple (48, 48, Gdk.InterpType.BILINEAR);
					get_icon_pixbuf.begin (pkg.icon, (obj, res) => {
						var downloaded_pixbuf = get_icon_pixbuf.end (res);
						if (downloaded_pixbuf != null) {
							row.app_icon.pixbuf = downloaded_pixbuf.scale_simple (48, 48, Gdk.InterpType.BILINEAR);
						}
					});
				} else {
					try {
						pixbuf = new Gdk.Pixbuf.from_file_at_scale (pkg.icon, 48, 48, true);
					} catch (Error e) {
						#if ENABLE_SNAP
						if (pkg is SnapPackage && pkg.installed_version != "") {
							pixbuf = package_icon.scale_simple (48, 48, Gdk.InterpType.BILINEAR);
							// try to retrieve icon
							try {
								string downloaded_pixbuf_path = database.get_installed_snap_icon (pkg.name);
								row.app_icon.pixbuf = new Gdk.Pixbuf.from_file_at_scale (downloaded_pixbuf_path, 48, 48, true);
							} catch (Error e) {
								warning ("%s: %s", pkg.name, e.message);
							}
						} else {
						#endif
							// some icons are not in the right repo
							string icon = pkg.icon;
							if ("extra" in pkg.icon) {
								icon = pkg.icon.replace ("extra", "community");
							} else if ("community" in pkg.icon) {
								icon = pkg.icon.replace ("community", "extra");
							}
							try {
								pixbuf = new Gdk.Pixbuf.from_file_at_scale (icon, 48, 48, true);
							} catch (Error e) {
								pixbuf = package_icon.scale_simple (48, 48, Gdk.InterpType.BILINEAR);
								warning ("%s: %s", pkg.icon, e.message);
							}
						#if ENABLE_SNAP
						}
						#endif
					}
				}
			} else {
				pixbuf = package_icon.scale_simple (48, 48, Gdk.InterpType.BILINEAR);
			}
			row.app_icon.pixbuf = pixbuf;
			if (transaction.transaction_summary_contains (pkg.name)) {
				row.action_togglebutton.sensitive = false;
			}
			if (is_update) {
				row.action_togglebutton.label = dgettext (null, "Upgrade");
				row.action_togglebutton.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				if (!(pkg.name in temporary_ignorepkgs)) {
					row.action_togglebutton.active = true;
					row.action_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
				}
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
			} else if (pkg.installed_version == "") {
				if (pkg is AURPackage) {
					row.action_togglebutton.label = dgettext (null, "Build");
					row.action_togglebutton.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
					if (pkg.name in to_build) {
						row.action_togglebutton.active = true;
						row.action_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
					}
					row.action_togglebutton.toggled.connect ((button) => {
						if (button.active) {
							to_build.add (pkg.name);
						} else {
							to_build.remove (pkg.name);
						}
						refresh_listbox_buttons ();
						set_pendings_operations ();
					});
				#if ENABLE_SNAP
				} else if (pkg is SnapPackage) {
					row.action_togglebutton.label = dgettext (null, "Install");
					row.action_togglebutton.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
					if (pkg.name in snap_to_install) {
						row.action_togglebutton.active = true;
						row.action_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
					}
					row.action_togglebutton.toggled.connect ((button) => {
						if (button.active) {
							snap_to_install.insert (pkg.name, pkg as SnapPackage);
						} else {
							snap_to_install.remove (pkg.name);
						}
						refresh_listbox_buttons ();
						set_pendings_operations ();
					});
				#endif
				#if ENABLE_FLATPAK
				} else if (pkg is FlatpakPackage) {
					row.action_togglebutton.label = dgettext (null, "Install");
					row.action_togglebutton.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
					if (pkg.name in flatpak_to_install) {
						row.action_togglebutton.active = true;
						row.action_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
					}
					row.action_togglebutton.toggled.connect ((button) => {
						if (button.active) {
							flatpak_to_install.insert (pkg.name, pkg as FlatpakPackage);
						} else {
							flatpak_to_install.remove (pkg.name);
						}
						refresh_listbox_buttons ();
						set_pendings_operations ();
					});
				#endif
				} else {
					row.action_togglebutton.label = dgettext (null, "Install");
					row.action_togglebutton.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
					if (pkg.name in to_install) {
						row.action_togglebutton.active = true;
						row.action_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
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
				}
			#if ENABLE_SNAP
			} else if (pkg is SnapPackage) {
				row.action_togglebutton.label = dgettext (null, "Remove");
				row.action_togglebutton.get_style_context ().add_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
				if (pkg.name in snap_to_remove) {
					row.action_togglebutton.active = true;
					row.action_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
				}
				row.action_togglebutton.toggled.connect ((button) => {
					if (button.active) {
						snap_to_remove.insert (pkg.name, pkg as SnapPackage);
					} else {
						snap_to_remove.remove (pkg.name);
					}
					refresh_listbox_buttons ();
					set_pendings_operations ();
				});
			#endif
			#if ENABLE_FLATPAK
			} else if (pkg is FlatpakPackage) {
				row.action_togglebutton.label = dgettext (null, "Remove");
				row.action_togglebutton.get_style_context ().add_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
				if (pkg.name in flatpak_to_remove) {
					row.action_togglebutton.active = true;
					row.action_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
				}
				row.action_togglebutton.toggled.connect ((button) => {
					if (button.active) {
						flatpak_to_remove.insert (pkg.name, pkg as FlatpakPackage);
					} else {
						flatpak_to_remove.remove (pkg.name);
					}
					refresh_listbox_buttons ();
					set_pendings_operations ();
				});
			#endif
			} else {
				row.action_togglebutton.label = dgettext (null, "Remove");
				row.action_togglebutton.get_style_context ().add_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
				if (database.should_hold (pkg.name)) {
					row.action_togglebutton.sensitive = false;
				} else if (pkg.name in to_remove) {
					row.action_togglebutton.active = true;
					row.action_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
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
				Package pkg = pamac_row.pkg;
				if (transaction.transaction_summary_contains (pkg.name)) {
					pamac_row.action_togglebutton.active = false;
					pamac_row.action_togglebutton.sensitive = false;
					return;
				}
				if (!database.should_hold (pkg.name)) {
					pamac_row.action_togglebutton.sensitive = true;
				}
				if (pkg is AURPackage) {
					if (pkg.name in to_build ||
						pkg.name in to_remove ||
						pkg.name in to_update) {
						pamac_row.action_togglebutton.active = true;
						pamac_row.action_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
					} else {
						pamac_row.action_togglebutton.active = false;
						pamac_row.action_togglebutton.image = null;
					}
				#if ENABLE_SNAP
				} else if (pkg is SnapPackage) {
					if (pkg.name in snap_to_install ||
						pkg.name in snap_to_remove) {
						pamac_row.action_togglebutton.active = true;
						pamac_row.action_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
					} else {
						pamac_row.action_togglebutton.active = false;
						pamac_row.action_togglebutton.image = null;
					}
				#endif
				#if ENABLE_FLATPAK
				} else if (pkg is FlatpakPackage) {
					if (pkg.name in flatpak_to_install ||
						pkg.name in flatpak_to_remove ||
						pkg.name in to_update) {
						pamac_row.action_togglebutton.active = true;
						pamac_row.action_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
					} else {
						pamac_row.action_togglebutton.active = false;
						pamac_row.action_togglebutton.image = null;
					}
				#endif
				} else if (pkg is AlpmPackage){
					if (pkg.name in to_install && pkg.installed_version == "") {
						pamac_row.action_togglebutton.active = true;
						pamac_row.action_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
					} else if (pkg.name in to_update ||
						pkg.name in to_remove) {
						pamac_row.action_togglebutton.active = true;
						pamac_row.action_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
					} else {
						pamac_row.action_togglebutton.active = false;
						pamac_row.action_togglebutton.image = null;
					}
				}
			});
		}

		public void refresh_packages_list () {
			button_back.visible = main_stack.visible_child_name != "browse";
			if (browse_stack.visible_child_name == "browse") {
				show_sidebar ();
				search_button.visible = true;
				switch (filters_stack.visible_child_name) {
					case "categories":
						search_button.active = false;
						remove_all_button.visible = false;
						install_all_button.visible = false;
						ignore_all_button.visible = false;
						set_pendings_operations ();
						on_categories_listbox_row_activated (categories_listbox.get_selected_row ());
						break;
					case "groups":
						search_button.active = false;
						ignore_all_button.visible = false;
						set_pendings_operations ();
						on_groups_listbox_row_activated (groups_listbox.get_selected_row ());
						break;
					case "repos":
						search_button.active = false;
						remove_all_button.visible = false;
						install_all_button.visible = false;
						ignore_all_button.visible = false;
						set_pendings_operations ();
						on_repos_listbox_row_activated (repos_listbox.get_selected_row ());
						break;
					default:
						break;
				}
			} else if (browse_stack.visible_child_name == "installed") {
				show_sidebar ();
				search_button.active = false;
				search_button.visible = true;
				install_all_button.visible = false;
				ignore_all_button.visible = false;
				set_pendings_operations ();
				on_installed_listbox_row_activated (installed_listbox.get_selected_row ());
			} else if (browse_stack.visible_child_name == "updates") {
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				hide_sidebar ();
				origin_stack.visible_child_name = "checking";
				search_button.active = false;
				search_button.visible = false;
				remove_all_button.visible = false;
				install_all_button.visible = false;
				ignore_all_button.visible = false;
				apply_button.sensitive = false;
				var updates = database.get_updates ();
				// copy updates in lists
				repos_updates = new GenericArray<AlpmPackage> ();
				foreach (unowned AlpmPackage pkg in updates.repos_updates) {
					repos_updates.add (pkg);
				}
				aur_updates = new GenericArray<AURPackage> ();
				foreach (unowned AURPackage pkg in updates.aur_updates) {
					aur_updates.add (pkg);
				}
				#if ENABLE_FLATPAK
				flatpak_updates = new GenericArray<FlatpakPackage> ();
				foreach (unowned FlatpakPackage pkg in updates.flatpak_updates) {
					flatpak_updates.add (pkg);
				}
				#endif
				if (browse_stack.visible_child_name == "updates") {
					populate_updates ();
				} else {
					this.get_window ().set_cursor (null);
				}
			} else if (browse_stack.visible_child_name == "pending") {
				if (to_build.length == 0
					#if ENABLE_SNAP
					&& snap_to_install.length == 0
					&& snap_to_remove.length == 0
					#endif
					#if ENABLE_FLATPAK
					&& flatpak_to_install.length == 0
					&& flatpak_to_remove.length == 0
					#endif
					) {
					hide_sidebar ();
				}
				search_button.active = false;
				search_button.visible = false;
				remove_all_button.visible = false;
				install_all_button.visible = false;
				ignore_all_button.visible = false;
				on_pending_listbox_row_activated (pending_listbox.get_selected_row ());
			} else if (browse_stack.visible_child_name == "search") {
				remove_all_button.visible = false;
				install_all_button.visible = false;
				ignore_all_button.visible = false;
				set_pendings_operations ();
				on_search_comboboxtext_changed ();
				if (!searchbar.search_mode_enabled) {
					searchbar.search_mode_enabled = true;
				}
			}
		}

		public void display_details (Package pkg) {
			if (pkg is AURPackage) {
				display_aur_details (pkg as AURPackage);
			} else if (pkg is AlpmPackage) {
				display_package_details (pkg as AlpmPackage);
			}
			#if ENABLE_SNAP
			else if (pkg is SnapPackage) {
				display_snap_details (pkg as SnapPackage);
			}
			#endif
			#if ENABLE_FLATPAK
			else if (pkg is FlatpakPackage) {
				display_flatpak_details (pkg as FlatpakPackage);
			}
			#endif
		}

		void refresh_details () {
			if (current_package_displayed is AURPackage) {
				Package? pkg = database.get_aur_pkg (current_package_displayed.name);
				if (pkg != null) {
					current_package_displayed = pkg;
				}
			#if ENABLE_SNAP
			} else if (current_package_displayed is SnapPackage) {
				Package? pkg = database.get_snap (current_package_displayed.name);
				if (pkg != null) {
					current_package_displayed = pkg;
				}
			#endif
			#if ENABLE_FLATPAK
			} else if (current_package_displayed is FlatpakPackage) {
				FlatpakPackage current_flatpak = current_package_displayed as FlatpakPackage;
				Package? pkg = database.get_flatpak (current_flatpak.id);
				if (pkg != null) {
					current_package_displayed = pkg;
				}
			#endif
			} else {
				Package? pkg = database.get_installed_pkg (current_package_displayed.name);
				if (pkg == null) {
					pkg = database.get_sync_pkg (current_package_displayed.name);
				}
				if (pkg != null) {
					current_package_displayed = pkg;
				}
			}
			display_details (current_package_displayed);
		}

		public void display_package_details (AlpmPackage pkg) {
			current_package_displayed = pkg;
			// select details if build files was selected
			if (properties_listbox.get_selected_row ().get_index () == 3) {
				properties_listbox.get_row_at_index (0).activate ();
			}
			deps_row.visible = true;
			files_row.visible = true;
			build_files_row.visible = false;
			properties_listbox.visible = true;
			set_package_details (pkg);
		}

		void display_aur_details (AURPackage aur_pkg) {
			current_package_displayed = aur_pkg;
			// select details if files was selected
			if (properties_listbox.get_selected_row ().get_index () == 2) {
				properties_listbox.get_row_at_index (0).activate ();
			}
			deps_row.visible = true;
			files_row.visible = false;
			build_files_row.visible = true;
			properties_listbox.visible = true;
			set_aur_details (aur_pkg);
		}

		#if ENABLE_SNAP
		public void display_snap_details (SnapPackage snap_pkg) {
			current_package_displayed = snap_pkg;
			// select details if files or build files was selected
			if (properties_listbox.get_selected_row ().get_index () == 2) {
				properties_listbox.get_row_at_index (0).activate ();
			} else if (properties_listbox.get_selected_row ().get_index () == 3) {
				properties_listbox.get_row_at_index (0).activate ();
			}
			deps_row.visible = false;
			files_row.visible = false;
			build_files_row.visible = false;
			properties_listbox.visible = false;
			set_snap_details (snap_pkg);
		}
		#endif

		#if ENABLE_FLATPAK
		public void display_flatpak_details (FlatpakPackage flatpak_pkg) {
			current_package_displayed = flatpak_pkg;
			// select details if files or build files was selected
			if (properties_listbox.get_selected_row ().get_index () == 2) {
				properties_listbox.get_row_at_index (0).activate ();
			} else if (properties_listbox.get_selected_row ().get_index () == 3) {
				properties_listbox.get_row_at_index (0).activate ();
			}
			deps_row.visible = false;
			files_row.visible = false;
			build_files_row.visible = false;
			properties_listbox.visible = false;
			set_flatpak_details (flatpak_pkg);
		}
		#endif

		[GtkCallback]
		void on_packages_listbox_row_activated (Gtk.ListBoxRow row) {
			unowned PackageRow pamac_row = row as PackageRow;
			if (pamac_row == null) {
				return;
			}
			display_details (pamac_row.pkg);
			main_stack.visible_child_name = "details";
		}

		void on_dep_button_clicked (Gtk.Button button) {
			if (display_package_queue.find_custom (current_package_displayed, compare_pkgs_by_name) == null) {
				display_package_queue.push_tail (current_package_displayed);
			}
			string depstring = button.label;
			if (database.has_installed_satisfier (depstring)) {
				display_package_details (database.get_installed_satisfier (depstring));
			} else if (database.has_sync_satisfier (depstring)) {
				display_package_details (database.get_sync_satisfier (depstring));
			} else {
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				string dep_name = database.get_alpm_dep_name (depstring);
				var aur_pkg = database.get_aur_pkg (dep_name);
				this.get_window ().set_cursor (null);
				if (aur_pkg != null) {
					display_aur_details (aur_pkg);
				}
			}
		}

		[GtkCallback]
		public void on_button_back_clicked () {
			switch (main_stack.visible_child_name) {
				case "browse":
					search_entry.set_text ("");
					break;
				case "details":
					Package? pkg = display_package_queue.pop_tail ();
					if (pkg != null && pkg.name != current_package_displayed.name) {
						current_package_displayed = pkg;
						refresh_details ();
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
				case 0: // all
					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
					ignore_all_button.visible = false;
					var pkgs = new SList<Package> ();
					uint i;
					for (i = 0; i < repos_updates.length; i++) {
						pkgs.prepend (repos_updates[i]);
					}
					for (i = 0; i < aur_updates.length; i++) {
						pkgs.prepend (aur_updates[i]);
					}
					#if ENABLE_FLATPAK
					for (i = 0; i < flatpak_updates.length; i++) {
						pkgs.prepend (flatpak_updates[i]);
					}
					#endif
					populate_packages_list ((owned) pkgs);
					unowned Gtk.ListBoxRow repos_row = updates_listbox.get_row_at_index (1);
					if (repos_updates.length > 0) {
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
					break;
				case 1: // repos
					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
					row.activatable = true;
					row.selectable = true;
					row.can_focus = true;
					row.get_child ().sensitive = true;
					ignore_all_button.visible = false;
					var pkgs = new SList<AlpmPackage> ();
					for (uint i = 0; i < repos_updates.length; i++) {
						pkgs.prepend (repos_updates[i]);
					}
					populate_packages_list ((owned) pkgs);
					break;
				case 2: // aur
					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
					var pkgs = new SList<AURPackage> ();
					for (uint i = 0; i < aur_updates.length; i++) {
						pkgs.prepend (aur_updates[i]);
					}
					populate_aur_list ((owned) pkgs);
					if (aur_updates.length > 0) {
						ignore_all_button.visible = true;
					}
					unowned Gtk.ListBoxRow repos_row = updates_listbox.get_row_at_index (1);
					if (repos_updates.length > 0) {
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
					break;
				#if ENABLE_FLATPAK
				case 3: // Flatpak
					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
					var pkgs = new SList<FlatpakPackage> ();
					for (uint i = 0; i < flatpak_updates.length; i++) {
						pkgs.prepend (flatpak_updates[i]);
					}
					populate_packages_list ((owned) pkgs);
					if (flatpak_updates.length > 0) {
						ignore_all_button.visible = true;
					}
					unowned Gtk.ListBoxRow repos_row = updates_listbox.get_row_at_index (1);
					if (repos_updates.length > 0) {
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
					break;
				#endif
				default:
					break;
			}
		}

		[GtkCallback]
		void on_pending_listbox_row_activated (Gtk.ListBoxRow row) {
			int index = row.get_index ();
			if (index == 0) { // all
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				var pkgs = new SList<Package> ();
				foreach (unowned string pkgname in to_install) {
					var pkg = database.get_installed_pkg (pkgname);
					if (pkg == null) {
						pkg = database.get_sync_pkg (pkgname);
					}
					if (pkg != null) {
						pkgs.prepend (pkg);
					}
				}
				foreach (unowned string pkgname in to_remove) {
					var pkg = database.get_installed_pkg (pkgname);
					if (pkg != null) {
						pkgs.prepend (pkg);
					}
				}
				#if ENABLE_SNAP
				var snap_iter = HashTableIter<string, SnapPackage?> (snap_to_install);
				unowned SnapPackage? snap_pkg;
				while (snap_iter.next (null, out snap_pkg)) {
					pkgs.prepend (snap_pkg);
				}
				snap_iter = HashTableIter<string, SnapPackage?> (snap_to_remove);
				while (snap_iter.next (null, out snap_pkg)) {
					pkgs.prepend (snap_pkg);
				}
				unowned Gtk.ListBoxRow snap_row = pending_listbox.get_row_at_index (pending_listbox_snap_index);
				if ((snap_to_install.length + snap_to_remove.length) > 0) {
					snap_row.activatable = true;
					snap_row.selectable = true;
					snap_row.can_focus = true;
					snap_row.get_child ().sensitive = true;
				} else {
					snap_row.activatable = false;
					snap_row.selectable = false;
					snap_row.has_focus = false;
					snap_row.can_focus = false;
					snap_row.get_child ().sensitive = false;
				}
				#endif
				#if ENABLE_FLATPAK
				var flatpak_iter = HashTableIter<string, FlatpakPackage?> (flatpak_to_install);
				unowned FlatpakPackage? flatpak_pkg;
				while (flatpak_iter.next (null, out flatpak_pkg)) {
					pkgs.prepend (flatpak_pkg);
				}
				flatpak_iter = HashTableIter<string, FlatpakPackage?> (flatpak_to_remove);
				while (flatpak_iter.next (null, out flatpak_pkg)) {
					pkgs.prepend (flatpak_pkg);
				}
				unowned Gtk.ListBoxRow flatpak_row = pending_listbox.get_row_at_index (pending_listbox_flatpak_index);
				if ((flatpak_to_install.length + flatpak_to_remove.length) > 0) {
					flatpak_row.activatable = true;
					flatpak_row.selectable = true;
					flatpak_row.can_focus = true;
					flatpak_row.get_child ().sensitive = true;
				} else {
					flatpak_row.activatable = false;
					flatpak_row.selectable = false;
					flatpak_row.has_focus = false;
					flatpak_row.can_focus = false;
					flatpak_row.get_child ().sensitive = false;
				}
				#endif
				if (to_build.length > 0) {
					var aur_pkgs = get_pendings_aur_pkgs ();
					foreach (unowned AURPackage pkg in aur_pkgs) {
						pkgs.prepend (pkg);
					}
				}
				populate_packages_list ((owned) pkgs);
				unowned Gtk.ListBoxRow repos_row = pending_listbox.get_row_at_index (1);
				if ((to_install.length + to_remove.length) > 0) {
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
				unowned Gtk.ListBoxRow aur_row = pending_listbox.get_row_at_index (2);
				if (to_build.length > 0) {
					aur_row.activatable = true;
					aur_row.selectable = true;
					aur_row.can_focus = true;
					aur_row.get_child ().sensitive = true;
				} else {
					aur_row.activatable = false;
					aur_row.selectable = false;
					aur_row.has_focus = false;
					aur_row.can_focus = false;
					aur_row.get_child ().sensitive = false;
				}
			} else if (index == 1) { // repos
				if ((to_install.length + to_remove.length) > 0) {
					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
					row.activatable = true;
					row.selectable = true;
					row.can_focus = true;
					row.get_child ().sensitive = true;
					var pkgs = new SList<AlpmPackage> ();
					foreach (unowned string pkgname in to_install) {
						var pkg = database.get_installed_pkg (pkgname);
						if (pkg == null) {
							pkg = database.get_sync_pkg (pkgname);
						}
						if (pkg != null) {
							pkgs.prepend (pkg);
						}
					}
					foreach (unowned string pkgname in to_remove) {
						var pkg = database.get_installed_pkg (pkgname);
						if (pkg != null) {
							pkgs.prepend (pkg);
						}
					}
					populate_packages_list ((owned) pkgs);
				}
				unowned Gtk.ListBoxRow aur_row = pending_listbox.get_row_at_index (2);
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
				#if ENABLE_SNAP
				unowned Gtk.ListBoxRow snap_row = pending_listbox.get_row_at_index (pending_listbox_snap_index);
				if ((snap_to_install.length + snap_to_remove.length) > 0) {
					snap_row.activatable = true;
					snap_row.selectable = true;
					snap_row.can_focus = true;
					snap_row.get_child ().sensitive = true;
				} else {
					snap_row.activatable = false;
					snap_row.selectable = false;
					snap_row.has_focus = false;
					snap_row.can_focus = false;
					snap_row.get_child ().sensitive = false;
				}
				#endif
				#if ENABLE_FLATPAK
				unowned Gtk.ListBoxRow flatpak_row = pending_listbox.get_row_at_index (pending_listbox_flatpak_index);
				if ((flatpak_to_install.length + flatpak_to_remove.length) > 0) {
					flatpak_row.activatable = true;
					flatpak_row.selectable = true;
					flatpak_row.can_focus = true;
					flatpak_row.get_child ().sensitive = true;
				} else {
					flatpak_row.activatable = false;
					flatpak_row.selectable = false;
					flatpak_row.has_focus = false;
					flatpak_row.can_focus = false;
					flatpak_row.get_child ().sensitive = false;
				}
				#endif
			} else if (index == 2) { // aur
				if (to_build.length > 0) {
					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
					row.activatable = true;
					row.selectable = true;
					row.can_focus = true;
					row.get_child ().sensitive = true;
					populate_aur_list (get_pendings_aur_pkgs ());
				}
				unowned Gtk.ListBoxRow repos_row = pending_listbox.get_row_at_index (1);
				if ((to_install.length + to_remove.length) > 0) {
					repos_row.activatable = true;
					repos_row.selectable = true;
					repos_row.can_focus = true;
					repos_row.get_child ().sensitive = true;
					if (to_build.length == 0) {
						row.activatable = false;
						row.selectable = false;
						row.has_focus = false;
						row.can_focus = false;
						row.get_child ().sensitive = false;
						pending_listbox.select_row (repos_row);
						on_pending_listbox_row_activated (pending_listbox.get_selected_row ());
					}
				} else {
					repos_row.activatable = false;
					repos_row.selectable = false;
					repos_row.has_focus = false;
					repos_row.can_focus = false;
					repos_row.get_child ().sensitive = false;
				}
				#if ENABLE_SNAP
				unowned Gtk.ListBoxRow snap_row = pending_listbox.get_row_at_index (pending_listbox_snap_index);
				if ((snap_to_install.length + snap_to_remove.length) > 0) {
					snap_row.activatable = true;
					snap_row.selectable = true;
					snap_row.can_focus = true;
					snap_row.get_child ().sensitive = true;
				} else {
					snap_row.activatable = false;
					snap_row.selectable = false;
					snap_row.has_focus = false;
					snap_row.can_focus = false;
					snap_row.get_child ().sensitive = false;
				}
				#endif
				#if ENABLE_FLATPAK
				unowned Gtk.ListBoxRow flatpak_row = pending_listbox.get_row_at_index (pending_listbox_flatpak_index);
				if ((flatpak_to_install.length + flatpak_to_remove.length) > 0) {
					flatpak_row.activatable = true;
					flatpak_row.selectable = true;
					flatpak_row.can_focus = true;
					flatpak_row.get_child ().sensitive = true;
				} else {
					flatpak_row.activatable = false;
					flatpak_row.selectable = false;
					flatpak_row.has_focus = false;
					flatpak_row.can_focus = false;
					flatpak_row.get_child ().sensitive = false;
				}
				#endif
			#if ENABLE_SNAP
			} else if (index == pending_listbox_snap_index) { // Snap
				var pkgs = new SList<Package> ();
				var snap_iter = HashTableIter<string, SnapPackage?> (snap_to_install);
				unowned SnapPackage? pkg;
				while (snap_iter.next (null, out pkg)) {
					pkgs.prepend (pkg);
				}
				snap_iter = HashTableIter<string, SnapPackage?> (snap_to_remove);
				while (snap_iter.next (null, out pkg)) {
					pkgs.prepend (pkg);
				}
				populate_packages_list ((owned) pkgs);
			#endif
			#if ENABLE_FLATPAK
			} else if (index == pending_listbox_flatpak_index) { // Flatpak
				var pkgs = new SList<Package> ();
				var flatpak_iter = HashTableIter<string, FlatpakPackage?> (flatpak_to_install);
				unowned FlatpakPackage? pkg;
				while (flatpak_iter.next (null, out pkg)) {
					pkgs.prepend (pkg);
				}
				flatpak_iter = HashTableIter<string, FlatpakPackage?> (flatpak_to_remove);
				while (flatpak_iter.next (null, out pkg)) {
					pkgs.prepend (pkg);
				}
				populate_packages_list ((owned) pkgs);
			#endif
			}
		}

		SList<AURPackage> get_pendings_aur_pkgs () {
			var aur_pkgs = new SList<AURPackage> ();
			var to_build_array = new GenericArray<string> (to_build.length);
			foreach (unowned string name in to_build)  {
				to_build_array.add (name);
			}
			var table = database.get_aur_pkgs (to_build_array.data);
			var iter = HashTableIter<string, AURPackage?> (table);
			unowned AURPackage? aur_pkg;
			while (iter.next (null, out aur_pkg)) {
				if (aur_pkg != null) {
					aur_pkgs.prepend (aur_pkg);
				}
			}
			return aur_pkgs;
		}

		[GtkCallback]
		void on_search_listbox_row_activated (Gtk.ListBoxRow row) {
			int index = row.get_index ();
			if (index == 0) { // all
				search_entry.grab_focus_without_selecting ();
				search_entry.set_position (-1);
				if (search_string == null) {
					return;
				}
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				SList<Package> pkgs = database.search_pkgs (search_string);
				if (database.config.enable_aur) {
					var aur_pkgs = database.search_aur_pkgs (search_string);
					foreach (unowned AURPackage pkg in aur_pkgs) {
						if (pkg.installed_version == "") {
							pkgs.prepend (pkg);
						}
					}
				}
				#if ENABLE_SNAP
				if (database.config.enable_snap) {
					var snaps = database.search_snaps (search_string);
					foreach (unowned SnapPackage pkg in snaps) {
						pkgs.prepend (pkg);
					}
				}
				#endif
				#if ENABLE_FLATPAK
				if (database.config.enable_flatpak) {
					var flatpaks = database.search_flatpaks (search_string);
					foreach (unowned FlatpakPackage pkg in flatpaks) {
						pkgs.prepend (pkg);
					}
				}
				#endif
				populate_packages_list ((owned) pkgs);
				var installed_pkgs = database.search_installed_pkgs (search_string);
				unowned Gtk.ListBoxRow installed_row = search_listbox.get_row_at_index (1);
				if (installed_pkgs != null) {
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
				var repos_pkgs = database.search_repos_pkgs (search_string);
				unowned Gtk.ListBoxRow repos_row = search_listbox.get_row_at_index (2);
				if (repos_pkgs != null) {
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
			} else if (index == 1) { // installed
				search_entry.grab_focus_without_selecting ();
				search_entry.set_position (-1);
				if (search_string == null) {
					return;
				}
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				var pkgs = database.search_installed_pkgs (search_string);
				if (pkgs == null) {
					var repos_pkgs = database.search_repos_pkgs (search_string);
					if (repos_pkgs != null) {
						row.activatable = false;
						row.selectable = false;
						row.has_focus = false;
						row.can_focus = false;
						row.get_child ().sensitive = false;
						unowned Gtk.ListBoxRow all_row = search_listbox.get_row_at_index (0);
						search_listbox.select_row (all_row);
						on_search_listbox_row_activated (search_listbox.get_selected_row ());
					} else if (database.config.enable_aur) {
						var aur_pkgs = database.search_aur_pkgs (search_string);
						if (aur_pkgs != null) {
							row.activatable = false;
							row.selectable = false;
							row.has_focus = false;
							row.can_focus = false;
							row.get_child ().sensitive = false;
							unowned Gtk.ListBoxRow aur_row = search_listbox.get_row_at_index (3);
							aur_row.activatable = true;
							aur_row.selectable = true;
							aur_row.can_focus = true;
							aur_row.get_child ().sensitive = true;
							search_listbox.select_row (aur_row);
							on_search_listbox_row_activated (search_listbox.get_selected_row ());
						} else {
							populate_packages_list ((owned) pkgs);
						}
					} else {
						populate_packages_list ((owned) pkgs);
					}
				} else {
					populate_packages_list ((owned) pkgs);
					var repos_pkgs = database.search_repos_pkgs (search_string);
					unowned Gtk.ListBoxRow repos_row = search_listbox.get_row_at_index (2);
					if (repos_pkgs != null) {
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
				}
			} else if (index == 2) { // repos
				search_entry.grab_focus_without_selecting ();
				search_entry.set_position (-1);
				if (search_string == null) {
					return;
				}
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				var pkgs = database.search_repos_pkgs (search_string);
				if (pkgs == null) {
					if (database.config.enable_aur) {
						var aur_pkgs = database.search_aur_pkgs (search_string);
						if (aur_pkgs != null) {
							row.activatable = false;
							row.selectable = false;
							row.has_focus = false;
							row.can_focus = false;
							row.get_child ().sensitive = false;
							unowned Gtk.ListBoxRow aur_row = search_listbox.get_row_at_index (3);
							aur_row.activatable = true;
							aur_row.selectable = true;
							aur_row.can_focus = true;
							aur_row.get_child ().sensitive = true;
							search_listbox.select_row (aur_row);
							on_search_listbox_row_activated (search_listbox.get_selected_row ());
						} else {
							populate_packages_list ((owned) pkgs);
						}
					} else {
						populate_packages_list ((owned) pkgs);
					}
				} else {
					populate_packages_list ((owned) pkgs);
					var installed_pkgs = database.search_installed_pkgs (search_string);
					unowned Gtk.ListBoxRow installed_row = search_listbox.get_row_at_index (1);
					if (installed_pkgs != null) {
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
				}
			} else if (index == 3) { // aur
				search_entry.grab_focus_without_selecting ();
				search_entry.set_position (-1);
				if (search_string == null) {
					return;
				}
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				populate_aur_list (database.search_aur_pkgs (search_string));
				var installed_pkgs = database.search_installed_pkgs (search_string);
				unowned Gtk.ListBoxRow installed_row = search_listbox.get_row_at_index (1);
				if (installed_pkgs != null) {
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
				var repos_pkgs = database.search_repos_pkgs (search_string);
				unowned Gtk.ListBoxRow repos_row = search_listbox.get_row_at_index (2);
				if (repos_pkgs != null) {
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
			#if ENABLE_SNAP
			} else if (index == search_listbox_snap_index) { // Snap
				search_entry.grab_focus_without_selecting ();
				search_entry.set_position (-1);
				if (search_string == null) {
					return;
				}
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				populate_packages_list (database.search_snaps (search_string));
			#endif
			#if ENABLE_FLATPAK
			} else if (index == search_listbox_flatpak_index) { // Flatpak
				search_entry.grab_focus_without_selecting ();
				search_entry.set_position (-1);
				if (search_string == null) {
					return;
				}
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				populate_packages_list (database.search_flatpaks (search_string));
			#endif
			}
		}

		[GtkCallback]
		void on_remove_all_button_clicked () {
			foreach (unowned Package pkg in current_packages_list) {
				if (!transaction.transaction_summary_contains (pkg.name) && pkg.installed_version != ""
					&& !database.should_hold (pkg.name)) {
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
				if (!transaction.transaction_summary_contains (pkg.name) && pkg.installed_version == "") {
					to_install.add (pkg.name);
				}
			}
			refresh_listbox_buttons ();
			set_pendings_operations ();
		}

		[GtkCallback]
		void on_ignore_all_button_clicked () {
			foreach (unowned Package pkg in current_packages_list) {
				to_update.remove (pkg.name);
				temporary_ignorepkgs.add (pkg.name);
			}
			refresh_listbox_buttons ();
			set_pendings_operations ();
		}

		void on_search_mode_enabled () {
			if (searchbar.search_mode_enabled) {
				search_button.active = true;
				browse_stack.visible_child_name = "search";
			}
		}

		[GtkCallback]
		void on_search_button_toggled () {
			if (search_button.active) {
				searchbar.search_mode_enabled = true;
			} else {
				searchbar.search_mode_enabled = false;
			}
			// fix #602
			install_all_button.no_show_all = true;
			remove_all_button.no_show_all = true;
			ignore_all_button.no_show_all = true;
			pending_listbox.no_show_all = true;
			browse_box.show_all ();
			//
		}

		bool search_history_timeout_callback () {
			bool found = false;
			// check if search string exists in search list
			search_comboboxtext.get_model ().foreach ((model, path, iter) => {
				string line;
				model.get (iter, 0, out line);
				if (line == search_string) {
					found = true;
				}
				return found;
			});
			// add search string in history if needed
			if (!found) {
				Gtk.TreeIter iter;
				unowned Gtk.ListStore store = search_comboboxtext.get_model () as Gtk.ListStore;
				store.insert_with_values (out iter, -1, 0, search_string);
			}
			search_history_timeout_id = 0;
			return false;
		}

		bool search_entry_timeout_callback () {
			string tmp_search_string = search_comboboxtext.get_active_text ().strip ();
			if (tmp_search_string == "" || tmp_search_string.char_count () < 2) {
				search_entry_timeout_id = 0;
				return false;
			}
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			search_string = (owned) tmp_search_string;
			on_search_listbox_row_activated (search_listbox.get_selected_row ());
			search_entry_timeout_id = 0;
			// wait 1s before adding the search in history
			if (search_history_timeout_id != 0) {
				Source.remove (search_history_timeout_id);
			}
			search_history_timeout_id = Timeout.add (1000, search_history_timeout_callback);
			return false;
		}

		[GtkCallback]
		void on_search_comboboxtext_changed () {
			if (search_comboboxtext.get_active () == -1) {
				// entry was edited
				string tmp_search_string = search_comboboxtext.get_active_text ().strip ();
				if (tmp_search_string != "" && tmp_search_string.char_count () > 1) {
					if (search_entry_timeout_id != 0) {
						Source.remove (search_entry_timeout_id);
					}
					search_entry_timeout_id = Timeout.add (500, search_entry_timeout_callback);
				}
			} else {
				// a history line was choosen
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				search_string = search_comboboxtext.get_active_text ().strip ();
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
		void on_relevance_button_clicked () {
			sortby_button_label.label = dgettext (null, "Relevance");
			populate_packages_list ((owned) current_packages_list);
		}

		[GtkCallback]
		void on_name_button_clicked () {
			sortby_button_label.label = dgettext (null, "Name");
			populate_packages_list ((owned) current_packages_list);
		}

		[GtkCallback]
		void on_repository_button_clicked () {
			sortby_button_label.label = dgettext (null, "Repository");
			populate_packages_list ((owned) current_packages_list);
		}

		[GtkCallback]
		void on_size_button_clicked () {
			sortby_button_label.label = dgettext (null, "Size");
			populate_packages_list ((owned) current_packages_list);
		}

		[GtkCallback]
		void on_date_button_clicked () {
			sortby_button_label.label = dgettext (null, "Date");
			populate_packages_list ((owned) current_packages_list);
		}

		SList<Package> get_category_pkgs (string category) {
			SList<Package> pkgs = database.get_category_pkgs (category);
			#if ENABLE_SNAP
			if (database.config.enable_snap) {
				foreach (unowned Package pkg in database.get_category_snaps (category)) {
					pkgs.prepend (pkg);
				}
			}
			#endif
			#if ENABLE_FLATPAK
			if (database.config.enable_flatpak) {
				foreach (unowned Package pkg in database.get_category_flatpaks (category)) {
					pkgs.prepend (pkg);
				}
			}
			#endif
			return pkgs;
		}

		[GtkCallback]
		void on_categories_listbox_row_activated (Gtk.ListBoxRow row) {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			unowned Gtk.Label label = row.get_child () as Gtk.Label;
			string matching_cat = "";
			unowned string category = label.label;
			if (category == dgettext (null, "Featured")) {
				matching_cat = "Featured";
			} else if (category == dgettext (null, "Photo & Video")) {
				matching_cat = "Photo & Video";
			} else if (category == dgettext (null, "Music & Audio")) {
				matching_cat = "Music & Audio";
			} else if (category == dgettext (null, "Productivity")) {
				matching_cat = "Productivity";
			} else if (category == dgettext (null, "Communication & News")) {
				matching_cat = "Communication & News";
			} else if (category == dgettext (null, "Education & Science")) {
				matching_cat = "Education & Science";
			} else if (category == dgettext (null, "Games")) {
				matching_cat = "Games";
			} else if (category == dgettext (null, "Utilities")) {
				matching_cat = "Utilities";
			} else if (category == dgettext (null, "Development")) {
				matching_cat = "Development";
			}
			populate_packages_list (get_category_pkgs (matching_cat));
		}

		[GtkCallback]
		void on_groups_listbox_row_activated (Gtk.ListBoxRow row) {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			unowned Gtk.Label label = row.get_child () as Gtk.Label;
			unowned string group_name = label.label;
			var pkgs = database.get_group_pkgs (group_name);
			bool found = false;
			foreach (unowned AlpmPackage pkg in pkgs) {
				if (pkg.installed_version == "") {
					found = true;
					break;
				}
			}
			install_all_button.visible = found;
			found = false;
			foreach (unowned AlpmPackage pkg in pkgs) {
				if (pkg.installed_version != "") {
					found = true;
					break;
				}
			}
			remove_all_button.visible = found;
			populate_packages_list ((owned) pkgs);
		}

		[GtkCallback]
		void on_installed_listbox_row_activated (Gtk.ListBoxRow row) {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			int index = row.get_index ();
			if (index == 0) { // All
				SList<Package> pkgs = database.get_installed_pkgs ();
				remove_all_button.visible = false;
				#if ENABLE_SNAP
				if (database.config.enable_snap) {
					foreach (unowned Package pkg in database.get_installed_snaps ()) {
						pkgs.prepend (pkg);
					}
				}
				#endif
				#if ENABLE_FLATPAK
				if (database.config.enable_flatpak) {
					foreach (unowned Package pkg in database.get_installed_flatpaks ()) {
						pkgs.prepend (pkg);
					}
				}
				#endif
				populate_packages_list ((owned) pkgs);
			} else if (index == 1) { // Explicitly installed
				populate_packages_list (database.get_explicitly_installed_pkgs ());
				remove_all_button.visible = false;
			} else if (index == 2) { // Orphans
				var pkgs = database.get_orphans ();
				remove_all_button.visible = pkgs != null;
				populate_packages_list ((owned) pkgs);
			} else if (index == 3) { // Foreign
				populate_packages_list (database.get_foreign_pkgs ());
				remove_all_button.visible = false;
			#if ENABLE_SNAP
			} else if (index == installed_listbox_snap_index) { // Snap
				populate_packages_list (database.get_installed_snaps ());
				remove_all_button.visible = false;
			#endif
			#if ENABLE_FLATPAK
			} else if (index == installed_listbox_flatpak_index) { // Flatpak
				populate_packages_list (database.get_installed_flatpaks ());
				remove_all_button.visible = false;
			#endif
			}
		}

		[GtkCallback]
		void on_repos_listbox_row_activated (Gtk.ListBoxRow row) {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			unowned Gtk.Label label = row.get_child () as Gtk.Label;
			unowned string repo = label.label;
			populate_packages_list (database.get_repo_pkgs (repo));
		}

		void on_main_stack_visible_child_changed () {
			switch (main_stack.visible_child_name) {
				case "browse":
					main_stack_switcher.visible = true;
					button_back.visible = false;
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
					search_button.visible = false;
					if (transaction.details_textview.buffer.get_char_count () > 0) {
						details_button.sensitive = true;
					}
					break;
				case "term":
					main_stack_switcher.visible = false;
					button_back.visible = true;
					search_button.visible = false;
					details_button.sensitive = false;
					details_button.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
					details_button.relief = Gtk.ReliefStyle.NONE;
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
			if (origin_stack.visible_child_name == "repos") {
				sort_order_box.visible = true;
			} else {
				sort_order_box.visible = false;
			}
		}

		[GtkCallback]
		void on_menu_button_toggled () {
			preferences_button.sensitive = !(transaction_running || sysupgrade_running);
			refresh_button.sensitive = !(transaction_running || sysupgrade_running);
			local_button.sensitive = !(transaction_running || sysupgrade_running);
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
			package_filter.add_mime_type ("application/x-alpm-package");
			chooser.add_filter (package_filter);
			if (chooser.run () == Gtk.ResponseType.ACCEPT) {
				SList<string> packages_paths = chooser.get_filenames ();
				if (packages_paths != null) {
					foreach (unowned string path in packages_paths) {
						to_load.add (path);
					}
					chooser.destroy ();
					run_transaction ();
				}
			} else {
				chooser.destroy ();
			}
		}

		[GtkCallback]
		void on_preferences_button_clicked () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
			bool authorized = transaction.get_authorization ();
			if (authorized) {
				var preferences_dialog = new PreferencesDialog (transaction);
				preferences_dialog.run ();
				database.config.save ();
				preferences_dialog.destroy ();
				transaction.remove_authorization ();
				check_aur_support ();
				#if ENABLE_SNAP
				check_snap_support ();
				#endif
				#if ENABLE_FLATPAK
				check_flatpak_support ();
				#endif
				if (main_stack.visible_child_name == "details") {
					refresh_details ();
				}
				refresh_packages_list ();
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
				"comments", dgettext (null, "A Package Manager with Alpm, AUR, Flatpak and Snap support"),
				"copyright", "Copyright © 2020 Guillaume Benoit",
				"authors", authors,
				"version", VERSION,
				"license_type", Gtk.License.GPL_3_0,
				"website", "https://gitlab.manjaro.org/applications/pamac");
		}

		[GtkCallback]
		void on_categories_button_clicked () {
			filters_stack.visible_child_name = "categories";
			filters_button_label.label = dgettext (null, "Categories");
		}

		[GtkCallback]
		void on_groups_button_clicked () {
			filters_stack.visible_child_name = "groups";
			filters_button_label.label = dgettext (null, "Groups");
		}

		[GtkCallback]
		void on_repositories_button_clicked () {
			filters_stack.visible_child_name = "repos";
			filters_button_label.label = dgettext (null, "Repositories");
		}

		[GtkCallback]
		void on_details_button_clicked () {
			important_details = false;
			main_stack.visible_child_name = "term";
		}

		[GtkCallback]
		void on_apply_button_clicked () {
			details_button.sensitive = true;
			if (browse_stack.visible_child_name == "updates") {
				transaction.no_confirm_upgrade = true;
				run_sysupgrade (false);
			} else if (main_stack.visible_child_name == "details" &&
				properties_stack.visible_child_name == "build_files") {
				transaction.save_build_files.begin (current_package_displayed.name, () => {
					run_transaction ();
				});
			} else {
				run_transaction ();
			}
		}

		void run_transaction () {
			transaction.no_confirm_upgrade = false;
			transaction_running = true;
			apply_button.sensitive = false;
			cancel_button.sensitive = false;
			foreach (unowned string name in to_install) {
				transaction.add_pkg_to_install (name);
				previous_to_install.add (name);
			}
			foreach (unowned string name in to_remove) {
				transaction.add_pkg_to_remove (name);
				previous_to_remove.add (name);
			}
			foreach (unowned string path in to_load) {
				transaction.add_path_to_load (path);
			}
			foreach (unowned string name in to_build) {
				transaction.add_aur_pkg_to_build (name);
				previous_to_build.add (name);
			}
			#if ENABLE_SNAP
			foreach (unowned SnapPackage pkg in snap_to_install.get_values ()) {
				transaction.add_snap_to_install (pkg);
				previous_snap_to_install.insert (pkg.name, pkg);
			}
			foreach (unowned SnapPackage pkg in snap_to_remove.get_values ()) {
				transaction.add_snap_to_remove (pkg);
				previous_snap_to_remove.insert (pkg.name, pkg);
			}
			#endif
			#if ENABLE_FLATPAK
			foreach (unowned FlatpakPackage pkg in flatpak_to_install.get_values ()) {
				transaction.add_flatpak_to_install (pkg);
				previous_flatpak_to_install.insert (pkg.name, pkg);
			}
			foreach (unowned FlatpakPackage pkg in flatpak_to_remove.get_values ()) {
				transaction.add_flatpak_to_remove (pkg);
				previous_flatpak_to_remove.insert (pkg.name, pkg);
			}
			#endif
			clear_lists ();
			active_pending_stack (false);
			bool success = transaction.run ();
			on_transaction_finished (success);
		}

		void run_sysupgrade (bool force_refresh) {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			sysupgrade_running = true;
			apply_button.sensitive = false;
			cancel_button.sensitive = false;
			if (force_refresh
				|| repos_updates.length > 0
				|| aur_updates.length > 0) {
				foreach (unowned string name in temporary_ignorepkgs) {
					transaction.add_temporary_ignore_pkg (name);
				}
				transaction.add_pkgs_to_upgrade (force_refresh);
			}
			#if ENABLE_FLATPAK
			for (uint i = 0; i < flatpak_updates.length; i++) {
				unowned FlatpakPackage pkg = flatpak_updates[i];
				if (!temporary_ignorepkgs.contains (pkg.name)) {
					transaction.add_flatpak_to_upgrade (pkg);
				}
			}
			#endif
			bool success = transaction.run ();
			on_transaction_finished (success);
		}

		[GtkCallback]
		void on_cancel_button_clicked () {
			if (waiting) {
				waiting = false;
				transaction.cancel ();
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
					refresh_details ();
				}
			}
		}

		[GtkCallback]
		void on_refresh_button_clicked () {
			transaction.no_confirm_upgrade = false;
			run_sysupgrade (true);
		}

		void on_get_updates_progress (uint percent) {
			checking_label.set_markup ("<big><b>%s %u %</b></big>".printf (dgettext (null, "Checking for Updates"), percent));
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
		}

		void populate_updates () {
			to_update.remove_all ();
			if (repos_updates.length == 0
				&& aur_updates.length == 0
				#if ENABLE_FLATPAK
				&& flatpak_updates.length == 0
				#endif
				) {
				hide_sidebar ();
				origin_stack.visible_child_name = "updated";
				this.get_window ().set_cursor (null);
			} else {
				unowned Gtk.ListBoxRow repos_row = updates_listbox.get_row_at_index (1);
				if (repos_updates.length > 0) {
					for (uint i = 0; i < repos_updates.length; i++) {
						unowned AlpmPackage pkg = repos_updates[i];
						if (!temporary_ignorepkgs.contains (pkg.name)) {
							to_update.add (pkg.name);
						}
					}
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
				unowned Gtk.ListBoxRow aur_row = updates_listbox.get_row_at_index (2);
				if (aur_updates.length > 0) {
					for (uint i = 0; i < aur_updates.length; i++) {
						unowned AURPackage pkg = aur_updates[i];
						if (!temporary_ignorepkgs.contains (pkg.name)) {
							to_update.add (pkg.name);
						}
					}
					aur_row.activatable = true;
					aur_row.selectable = true;
					aur_row.can_focus = true;
					aur_row.get_child ().sensitive = true;
					show_sidebar ();
				} else {
					aur_row.activatable = false;
					aur_row.selectable = false;
					aur_row.has_focus = false;
					aur_row.can_focus = false;
					aur_row.get_child ().sensitive = false;
				}
				#if ENABLE_FLATPAK
				unowned Gtk.ListBoxRow flatpak_row = updates_listbox.get_row_at_index (3);
				if (flatpak_updates.length > 0) {
					for (uint i = 0; i < flatpak_updates.length; i++) {
						unowned FlatpakPackage pkg = flatpak_updates[i];
						if (!temporary_ignorepkgs.contains (pkg.name)) {
							to_update.add (pkg.name);
						}
					}
					flatpak_row.activatable = true;
					flatpak_row.selectable = true;
					flatpak_row.can_focus = true;
					flatpak_row.get_child ().sensitive = true;
					show_sidebar ();
				} else {
					flatpak_row.activatable = false;
					flatpak_row.selectable = false;
					flatpak_row.has_focus = false;
					flatpak_row.can_focus = false;
					flatpak_row.get_child ().sensitive = false;
				}
				#endif
				updates_listbox.get_row_at_index (0).activate ();
				set_pendings_operations ();
			}
		}

		void on_start_waiting () {
			waiting = true;
			cancel_button.sensitive = true;
		}

		void on_stop_waiting () {
			waiting = false;
			cancel_button.sensitive = false;
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
				details_button.relief = Gtk.ReliefStyle.NORMAL;
				details_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
			}
		}

		void show_in_app_notification (string message) {
			if (in_app_notification_timeout_id != 0) {
				Source.remove (in_app_notification_timeout_id);
				in_app_notification_timeout_id = 0;
			}
			notification_label.label = message;
			notification_revealer.reveal_child = true;
			in_app_notification_timeout_id = Timeout.add (3000, () => {
				notification_revealer.reveal_child = false;
				in_app_notification_timeout_id = 0;
				return false;
			});
		}

		void close_in_app_notification () {
			notification_revealer.reveal_child = false;
			Source.remove (in_app_notification_timeout_id);
			in_app_notification_timeout_id = 0;
		}

		void on_transaction_finished (bool success) {
			if (success) {
				if (this.is_active) {
					show_in_app_notification (dgettext (null, "Transaction successfully finished"));
				} else {
					transaction.show_notification (dgettext (null, "Transaction successfully finished"));
				}
				transaction.show_warnings (false);
			} else {
				transaction.clear_warnings ();
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
				#if ENABLE_SNAP
				foreach (unowned SnapPackage pkg in previous_snap_to_install.get_values ()) {
					if (!database.is_installed_snap (pkg.name)) {
						snap_to_install.insert (pkg.name, pkg);
					}
				}
				foreach (unowned SnapPackage pkg in previous_snap_to_remove.get_values ()) {
					if (database.is_installed_snap (pkg.name)) {
						snap_to_remove.insert (pkg.name, pkg);
					}
				}
				#endif
				#if ENABLE_FLATPAK
				foreach (unowned FlatpakPackage pkg in previous_flatpak_to_install.get_values ()) {
					if (!database.is_installed_flatpak (pkg.name)) {
						flatpak_to_install.insert (pkg.name, pkg);
					}
				}
				foreach (unowned FlatpakPackage pkg in previous_flatpak_to_remove.get_values ()) {
					if (database.is_installed_flatpak (pkg.name)) {
						flatpak_to_remove.insert (pkg.name, pkg);
					}
				}
				#endif
			}
			transaction.reset_progress_box ();
			transaction.show_details ("");
			transaction.transaction_summary_remove_all ();
			clear_previous_lists ();
			if (main_stack.visible_child_name == "term") {
				button_back.visible = true;
			}
			if (sysupgrade_running) {
				sysupgrade_running = false;
			} else {
				transaction_running = false;
				generate_mirrors_list = false;
			}
			if (main_stack.visible_child_name == "details") {
				refresh_details ();
			}
			scroll_to_top = false;
			refresh_packages_list ();
			set_pendings_operations ();
		}
	}
}
