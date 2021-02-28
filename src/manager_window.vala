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
	GenericArray<string> repos_names;
	GenericSet<string?> to_install;
	GenericSet<string?> to_remove;
	GenericSet<string?> to_load;
	GenericSet<string?> to_build;
	GenericSet<string?> to_update;
	GenericSet<string?> temporary_ignorepkgs;
	HashTable<string, SnapPackage> snap_to_install;
	HashTable<string, SnapPackage> snap_to_remove;
	HashTable<string, FlatpakPackage> flatpak_to_install;
	HashTable<string, FlatpakPackage> flatpak_to_remove;

	int sort_search_pkgs_by_relevance (Package pkg_a, Package pkg_b) {
		if (pkg_a is AURPackage) {
			if (pkg_b is AURPackage) {
				sort_aur_by_relevance (pkg_a, pkg_b);
			} else {
				return 1;
			}
		}
		if (pkg_b is AURPackage) {
			return -1;
		}
		if (search_string != null) {
			// display exact match first
			unowned string? a_app_name = pkg_a.app_name;
			string? a_app_name_down = null;
			if (a_app_name != null) {
				a_app_name_down = a_app_name.down ();
			}
			unowned string? b_app_name = pkg_b.app_name;
			string? b_app_name_down = null;
			if (b_app_name != null) {
				b_app_name_down = b_app_name.down ();
			}
			if (a_app_name_down != null && a_app_name_down == search_string) {
				if (b_app_name_down != null && b_app_name_down == search_string) {
					return sort_pkgs_by_relevance (pkg_a, pkg_b);
				}
				return -1;
			}
			if (b_app_name_down != null && b_app_name_down == search_string) {
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
			if (a_app_name_down != null && a_app_name_down.has_prefix (search_string)) {
				if (b_app_name_down != null && b_app_name_down.has_prefix (search_string)) {
					return sort_pkgs_by_relevance (pkg_a, pkg_b);
				}
				return -1;
			}
				if (b_app_name_down != null && b_app_name_down.has_prefix (search_string)) {
				return 1;
			}
			if (a_app_name_down != null && a_app_name_down.contains (search_string)) {
				if (b_app_name_down != null && b_app_name_down.contains (search_string)) {
					return sort_pkgs_by_relevance (pkg_a, pkg_b);
				}
				return -1;
			}
				if (b_app_name_down != null && b_app_name_down.contains (search_string)) {
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
		if (pkg_a.name in to_remove) {
			if (pkg_b.name in to_remove) {
				return sort_pkgs_by_name (pkg_a, pkg_b);
			}
			return -1;
		}
		if (pkg_b.name in to_remove) {
			return 1;
		}
		if (pkg_a.name in to_install ||
			pkg_a.name in to_build ||
			pkg_a.name in temporary_ignorepkgs) {
			if (pkg_b.name in to_install ||
				pkg_b.name in to_build ||
				pkg_b.name in temporary_ignorepkgs) {
				return sort_pkgs_by_name (pkg_a, pkg_b);
			}
			return -1;
		}
		if (pkg_b.name in to_install ||
			pkg_b.name in to_build ||
			pkg_b.name in temporary_ignorepkgs) {
			return 1;
		}
		if (pkg_a.installed_version == null) {
			if (pkg_b.installed_version == null) {
				return sort_pkgs_by_name (pkg_a, pkg_b);
			}
			return 1;
		}
		if (pkg_b.installed_version == null) {
			return -1;
		}
		if (pkg_a.app_name == null) {
			if (pkg_b.app_name == null) {
				return sort_pkgs_by_name (pkg_a, pkg_b);
			}
			return 1;
		}
		if (pkg_b.app_name == null) {
			return -1;
		}
		return sort_pkgs_by_name (pkg_a, pkg_b);
	}

	int sort_pkgs_by_name (Package pkg_a, Package pkg_b) {
		unowned string? a_app_name = pkg_a.app_name;
		unowned string? b_app_name = pkg_b.app_name;
		string str_a = a_app_name == null ? pkg_a.name.collate_key () : a_app_name.down ().collate_key ();
		string str_b = b_app_name == null ? pkg_b.name.collate_key () : b_app_name.down ().collate_key ();
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
		if (pkg_a.repo != null) {
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
		if (pkg_b.repo != null) {
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

	int sort_aur_by_relevance (Package pkg_1, Package pkg_2) {
		var pkg_a = pkg_1 as AURPackage;
		if (pkg_a == null) {
			return 1;
		}
		var pkg_b = pkg_2 as AURPackage;
		if (pkg_b == null) {
			return -1;
		}
		if (pkg_a.installed_version != null) {
			if (pkg_b.installed_version != null) {
				return sort_pkgs_by_name (pkg_a, pkg_b);
			}
			return -1;
		}
		if (pkg_b.installed_version != null) {
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
		if (pkg_a.installed_version == null) {
			if (pkg_b.installed_version == null) {
				AlpmPackage ? alpm_pkg_a = pkg_a as AlpmPackage;
				AlpmPackage ? alpm_pkg_b = pkg_b as AlpmPackage;
				if (alpm_pkg_a != null && alpm_pkg_b != null) {
					if (alpm_pkg_a.build_date > alpm_pkg_b.build_date) {
						return -1;
					}
					if (alpm_pkg_b.build_date > alpm_pkg_a.build_date) {
						return 1;
					}
				}
				return sort_pkgs_by_name (pkg_a, pkg_b);
			} else {
				return 1;
			}
		}
		if (pkg_b.installed_version == null) {
			return -1;
		}
		if (pkg_a.install_date > pkg_b.install_date) {
			return -1;
		}
		if (pkg_b.install_date > pkg_a.install_date) {
			return 1;
		}
		return sort_pkgs_by_name (pkg_a, pkg_b);
	}

	int sort_aur_by_date (Package pkg_1, Package pkg_2) {
		var pkg_a = pkg_1 as AURPackage;
		if (pkg_a == null) {
			return 1;
		}
		var pkg_b = pkg_2 as AURPackage;
		if (pkg_b == null) {
			return -1;
		}
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
		Gtk.Box main_button_box;
		[GtkChild]
		Gtk.ToggleButton main_browse_togglebutton;
		[GtkChild]
		Gtk.ToggleButton main_installed_togglebutton;
		[GtkChild]
		Gtk.ToggleButton main_pending_togglebutton;
		[GtkChild]
		public Gtk.ToggleButton main_updates_togglebutton;
		[GtkChild]
		Gtk.Button button_back;
		[GtkChild]
		Gtk.CheckButton software_mode_checkbutton;
		[GtkChild]
		Gtk.ModelButton refresh_databases_button;
		[GtkChild]
		Gtk.ModelButton local_button;
		[GtkChild]
		Gtk.ModelButton preferences_button;
		[GtkChild]
		Gtk.ListBox packages_listbox;
		[GtkChild]
		Gtk.Revealer notification_revealer;
		[GtkChild]
		Gtk.Label notification_label;
		[GtkChild]
		Gtk.Button notification_button;
		[GtkChild]
		public Gtk.ToggleButton search_togglebutton;
		[GtkChild]
		public Gtk.SearchEntry search_entry;
		[GtkChild]
		Gtk.Box view_box;
		[GtkChild]
		Gtk.MenuButton view_button;
		[GtkChild]
		Gtk.Label view_button_label;
		[GtkChild]
		Gtk.Box browseby_box;
		[GtkChild]
		Gtk.Label browseby_button_label;
		[GtkChild]
		Gtk.Box browse_head_box;
		[GtkChild]
		Gtk.Separator browse_separator;
		[GtkChild]
		Gtk.ModelButton view_installed_button;
		[GtkChild]
		Gtk.ModelButton view_explicitly_installed_button;
		[GtkChild]
		Gtk.ModelButton view_orphans_button;
		[GtkChild]
		Gtk.ModelButton view_foreign_button;
		[GtkChild]
		Gtk.ModelButton view_repositories_button;
		[GtkChild]
		Gtk.ModelButton view_aur_button;
		[GtkChild]
		Gtk.ModelButton view_snap_button;
		[GtkChild]
		Gtk.ModelButton view_flatpak_button;
		[GtkChild]
		Gtk.PopoverMenu groups_popovermenu;
		[GtkChild]
		Gtk.PopoverMenu repos_popovermenu;
		[GtkChild]
		Gtk.PopoverMenu categories_popovermenu;
		[GtkChild]
		Gtk.PopoverMenu view_popovermenu;
		[GtkChild]
		Gtk.ListBox groups_listbox;
		[GtkChild]
		Gtk.ListBox repos_listbox;
		[GtkChild]
		Gtk.Stack browse_stack;
		[GtkChild]
		Gtk.Button remove_all_button;
		[GtkChild]
		Gtk.Button install_all_button;
		[GtkChild]
		Gtk.Button ignore_all_button;
		[GtkChild]
		Gtk.Label sortby_button_label;
		[GtkChild]
		Gtk.ScrolledWindow packages_scrolledwindow;
		[GtkChild]
		Gtk.Label updated_label;
		[GtkChild]
		Gtk.Label last_refresh_label;
		[GtkChild]
		Gtk.Label no_item_label;
		[GtkChild]
		Gtk.Label checking_label;
		[GtkChild]
		Gtk.ScrolledWindow main_details_scrolledwindow;
		[GtkChild]
		Gtk.Stack properties_stack;
		[GtkChild]
		Gtk.StackSwitcher properties_stack_switcher;
		[GtkChild]
		Gtk.Box build_files_box;
		[GtkChild]
		Gtk.ScrolledWindow files_scrolledwindow;
		[GtkChild]
		Gtk.Box deps_box;
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
		Soup.Session soup_session;

		bool important_details;
		bool transaction_running;
		bool sysupgrade_running;
		public bool generate_mirrors_list;
		bool waiting;

		bool enable_aur;
		bool updates_checked;
		GenericArray<AlpmPackage> repos_updates;
		GenericArray<AURPackage> aur_updates;
		GenericArray<FlatpakPackage> flatpak_updates;
		string current_category_view;
		string current_installed_view;
		string current_updates_view;
		string current_search_view;
		string current_packages_list_name;
		GenericArray<unowned Package> current_packages_list;
		uint current_packages_list_length;
		uint current_packages_list_index;
		GenericArray<Gdk.Pixbuf> current_screenshots;
		int current_screenshots_index;

		uint search_entry_timeout_id;
		bool scroll_to_top;
		uint in_app_notification_timeout_id;

		HashTable<string, SnapPackage> previous_snap_to_install;
		HashTable<string, SnapPackage> previous_snap_to_remove;
		HashTable<string, FlatpakPackage> previous_flatpak_to_install;
		HashTable<string, FlatpakPackage> previous_flatpak_to_remove;

		public ManagerWindow (Gtk.Application application, Database database) {
			Object (application: application, database: database);
		}

		construct {
			unowned string? use_csd = Environment.get_variable ("GTK_CSD");
			if (use_csd == "0") {
				headerbar.show_close_button = false;
			}
			local_config = new LocalConfig ("%s/pamac/config".printf (Environment.get_user_config_dir ()));
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
			updates_checked = false;
			database.get_updates_progress.connect (on_get_updates_progress);
			create_all_listbox ();
			check_aur_support ();

			// set default views
			current_category_view = dgettext (null, "Featured");
			current_installed_view = dgettext (null, "All");
			current_updates_view = dgettext (null, "All");
			current_search_view = dgettext (null, "All");

			// transaction
			repos_updates = new GenericArray<AlpmPackage> ();
			aur_updates = new GenericArray<AURPackage> ();
			snap_to_install = new HashTable<string, SnapPackage> (str_hash, str_equal);
			snap_to_remove = new HashTable<string, SnapPackage> (str_hash, str_equal);
			previous_snap_to_install = new HashTable<string, SnapPackage> (str_hash, str_equal);
			previous_snap_to_remove = new HashTable<string, SnapPackage> (str_hash, str_equal);
			check_snap_support ();
			flatpak_to_install = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			flatpak_to_remove = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			previous_flatpak_to_install = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			previous_flatpak_to_remove = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			flatpak_updates = new GenericArray<FlatpakPackage> ();
			check_flatpak_support ();
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
			transaction_infobox.reorder_child (transaction.progress_box, 0);
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
			properties_stack.notify["visible-child"].connect (on_properties_stack_visible_child_changed);

			// enable "type to search"
			this.key_press_event.connect ((event) => {
				if (main_stack.visible_child_name == "browse"
					&& (main_browse_togglebutton.active
					|| search_togglebutton.active
					|| main_installed_togglebutton.active)) {
					search_string = "";
					search_togglebutton.active = true;
					return search_entry.handle_event (event);
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

			// soup session to dwonload icons and screenshots
			soup_session = new Soup.Session ();
			soup_session.user_agent = "Pamac/%s".printf (VERSION);
			soup_session.timeout = 30;

			// check software mode
			check_software_mode ();
			// connect after check_software_mode to not refresh packages twice
			software_mode_checkbutton.toggled.connect (on_software_mode_checkbutton_toggled);

			// refresh flatpak appstream_data
			database.refresh_flatpak_appstream_data_async.begin ();
		}

		void set_header_func (Gtk.ListBoxRow row, Gtk.ListBoxRow? row_before) {
			if (row_before != null) {
				row.set_header (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
			}
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
				local_conf.insert ("software_mode", new Variant.boolean (software_mode_checkbutton.active));
				local_config.write (local_conf);
				// close window
				return false;
			}
		}

		void on_software_mode_checkbutton_toggled () {
			bool enabled = software_mode_checkbutton.active;
			local_config.software_mode = enabled;
			if (enabled) {
				enable_aur = false;
				browseby_box.visible = false;
				browseby_button_label.label = dgettext (null, "Categories");
				current_updates_view = dgettext (null, "All");
				current_installed_view = dgettext (null, "All");
				properties_stack.visible_child_name = "details";
				details_button.visible = false;
			} else {
				enable_aur = database.config.enable_aur;
				if (main_browse_togglebutton.active) {
					browseby_box.visible = true;
				}
				details_button.visible = true;
			}
			if (main_stack.visible_child_name == "details") {
				refresh_details ();
			}
			refresh_packages_list ();
		}

		void check_software_mode () {
			// will run on_software_mode_checkbutton_toggled
			software_mode_checkbutton.active = local_config.software_mode;
		}

		void check_aur_support () {
			enable_aur = database.config.enable_aur && !local_config.software_mode;
			if (enable_aur) {
				view_aur_button.visible = true;
			} else {
				if (current_updates_view == dgettext (null, "AUR")) {
					current_updates_view = dgettext (null, "All");
				}
				view_aur_button.visible = false;
			}
		}

		void check_snap_support () {
			if (database.config.enable_snap) {
				view_snap_button.visible = true;
			} else {
				if (current_installed_view == dgettext (null, "Snap")) {
					current_installed_view = dgettext (null, "All");
				}
				view_snap_button.visible = false;
			}
		}

		void check_flatpak_support () {
			if (database.config.enable_flatpak) {
				view_flatpak_button.visible = true;
			} else {
				if (current_updates_view == dgettext (null, "Flatpak")) {
					current_updates_view = dgettext (null, "All");
				}
				if (current_installed_view == dgettext (null, "Flatpak")) {
					current_installed_view = dgettext (null, "All");
				}
				view_flatpak_button.visible = false;
			}
		}

		void set_pendings_operations () {
			if (!transaction_running && !generate_mirrors_list && !sysupgrade_running) {
				if (main_updates_togglebutton.active) {
					uint64 total_dsize = 0;
					foreach (unowned AlpmPackage pkg in repos_updates) {
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
										snap_to_install.length +
										snap_to_remove.length +
										flatpak_to_install.length +
										flatpak_to_remove.length +
										to_remove.length +
										to_build.length;
					if (total_pending == 0) {
						if (!main_pending_togglebutton.active) {
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
			label.margin = 6;
			label.xalign = 0;
			var row = new Gtk.ListBoxRow ();
			row.visible = true;
			row.add (label);
			return row;
		}

		void active_pending_stack (bool active) {
			main_pending_togglebutton.visible = active;
		}

		void create_all_listbox () {
			repos_names = database.get_repos_names ();
			foreach (unowned string name in repos_names) {
				repos_listbox.add (create_list_row (name));
			}
			repos_listbox.select_row (repos_listbox.get_row_at_index (0));

			// use by sort_pkgs_by_repo
			repos_names.add (dgettext (null, "Snap"));
			foreach (unowned string name in database.get_flatpak_remotes_names ()) {
				repos_names.add (name);
			}
			repos_names.add (dgettext (null, "AUR"));

			foreach (unowned string name in database.get_groups_names ()) {
				groups_listbox.add (create_list_row (name));
			}
			groups_listbox.select_row (groups_listbox.get_row_at_index (0));

			active_pending_stack (false);
		}

		void clear_packages_listbox () {
			packages_listbox.foreach (transaction.destroy_widget);
		}

		void clear_lists () {
			to_install.remove_all ();
			to_remove.remove_all ();
			to_build.remove_all ();
			to_load.remove_all ();
			snap_to_install.remove_all ();
			snap_to_remove.remove_all ();
			flatpak_to_install.remove_all ();
			flatpak_to_remove.remove_all ();
		}

		void clear_previous_lists () {
			previous_to_install.remove_all ();
			previous_to_remove.remove_all ();
			previous_to_build.remove_all ();
			previous_snap_to_install.remove_all ();
			previous_snap_to_remove.remove_all ();
			previous_flatpak_to_install.remove_all ();
			previous_flatpak_to_remove.remove_all ();
		}

		void on_mark_explicit_button_clicked (Gtk.Button button) {
			transaction.set_pkgreason_async.begin (current_package_displayed.name, 0, //Alpm.Package.Reason.EXPLICIT
													() => { 
				refresh_details ();
			});
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
			uint current_screenshots_length = current_screenshots.length;
			next_screenshot_button.sensitive = current_screenshots_index < current_screenshots_length - 1;
			previous_screenshot_button.sensitive = true;
			if (current_screenshots_index < current_screenshots_length) {
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

		void populate_deps_box (string dep_type, GenericArray<string> dep_list, bool add_install_button = false) {
			var label = new Gtk.Label ("<b>%s:</b>".printf (dep_type));
			label.use_markup = true;
			label.halign = Gtk.Align.START;
			label.margin_top = 12;
			deps_box.pack_start (label);
			var listbox = new Gtk.ListBox ();
			listbox.set_header_func (set_header_func);
			foreach (unowned string dep in dep_list) {
				if (add_install_button) {
					var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
					var dep_label = new Gtk.Label (dep);
					dep_label.margin = 12;
					dep_label.halign = Gtk.Align.START;
					box.pack_start (dep_label, false);
					if (!database.has_installed_satisfier (dep)) {
						var install_dep_button = new Gtk.ToggleButton.with_label (dgettext (null, "Install"));
						install_dep_button.always_show_image = true;
						install_dep_button.margin = 12;
						install_dep_button.toggled.connect (on_install_dep_button_toggled);
						box.pack_end (install_dep_button, false);
						string dep_name = find_install_button_dep_name (install_dep_button);
						install_dep_button.active = (dep_name in to_install);
					}
					listbox.add (box);
				} else {
					var dep_label = new Gtk.Label (dep);
					dep_label.margin = 12;
					dep_label.halign = Gtk.Align.START;
					listbox.add (dep_label);
				}
			}
			listbox.row_activated.connect (on_deps_listbox_row_activated);
			var frame = new Gtk.Frame (null);
			frame.add (listbox);
			deps_box.pack_start (frame);
		}

		async GenericArray<Gdk.Pixbuf> get_screenshots_pixbufs (GenericArray<string> urls) {
			// keep a copy of urls because of async
			GenericArray<string> urls_copy = urls.copy (strdup);
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
					try {
						var request = soup_session.request (url);
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
				try {
					var request = soup_session.request (url);
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

		void set_screenshots (Package pkg) {
			previous_screenshot_button.visible = false;
			next_screenshot_button.visible = false;
			unowned GenericArray<string> screenshots = pkg.screenshots;
			if (screenshots.length != 0) {
				get_screenshots_pixbufs.begin (screenshots, (obj, res) => {
					current_screenshots = get_screenshots_pixbufs.end (res);
					current_screenshots_index = 0;
					screenshots_spinner.active = false;
					uint current_screenshots_length = current_screenshots.length;
					if (current_screenshots_length == 0) {
						screenshots_stack.visible = false;
						return;
					}
					int i = 0;
					foreach (unowned Gdk.Pixbuf current_screenshot in current_screenshots) {
						var image = new Gtk.Image.from_pixbuf (current_screenshot);
						image.visible = true;
						screenshots_stack.add_named (image, "%u".printf (i));
						i++;
					}
					screenshots_spinner.active = false;
					screenshots_stack.visible_child_name = "0";
					if (current_screenshots_length > 1) {
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
			set_screenshots (pkg);
			bool software_mode = local_config.software_mode;
			// infos
			unowned string? app_name = pkg.app_name;
			if (app_name == null) {
				name_label.set_markup ("<big><b>%s  %s</b></big>".printf (pkg.name, pkg.version));
				app_image.pixbuf = package_icon;
			} else {
				if (software_mode) {
					name_label.set_markup ("<big><b>%s  %s</b></big>".printf (Markup.escape_text (app_name), pkg.version));
				} else {
					name_label.set_markup ("<big><b>%s (%s)  %s</b></big>".printf (Markup.escape_text (app_name), pkg.name, pkg.version));
				}
				unowned string? icon = pkg.icon;
				if (icon != null) {
					try {
						var pixbuf = new Gdk.Pixbuf.from_file (icon);
						app_image.pixbuf = pixbuf;
					} catch (Error e) {
						// some icons are not in the right repo
						string new_icon = icon;
						if ("extra" in icon) {
							new_icon = icon.replace ("extra", "community");
						} else if ("community" in icon) {
							new_icon = icon.replace ("community", "extra");
						}
						try {
							var pixbuf = new Gdk.Pixbuf.from_file (new_icon);
							app_image.pixbuf = pixbuf;
						} catch (Error e) {
							app_image.pixbuf = package_icon;
							warning ("%s: %s", icon, e.message);
						}
					}
				} else {
					app_image.pixbuf = package_icon;
				}
			}
			unowned string? desc = pkg.desc;
			if (desc != null) {
				desc_label.set_text (pkg.desc);
			}
			unowned string? long_desc = pkg.long_desc;
			if (long_desc == null) {
				long_desc_label.visible = false;
			} else {
				string markup_long_desc = long_desc.replace ("em>", "i>").replace ("code>", "tt>");
				long_desc_label.set_markup (markup_long_desc);
				long_desc_label.visible = true;
			}
			unowned string? url = pkg.url;
			string? escaped_url = null;
			if (url != null) {
				escaped_url = Markup.escape_text (url);
				link_label.set_markup ("<a href=\"%s\">%s</a>".printf (escaped_url, escaped_url));
			} else {
				link_label.label = "";
			}
			if (pkg.installed_version != null) {
				unowned string? launchable = pkg.launchable;
				if (launchable != null) {
					launch_button.visible = true;
					current_launchable = launchable;
				} else {
					launch_button.visible = false;
				}
				install_togglebutton.visible = false;
				build_togglebutton.visible = false;
				reinstall_togglebutton.visible = false;
				remove_togglebutton.visible = true;
				if (database.should_hold (pkg.name)) {
					remove_togglebutton.sensitive = false;
				} else {
					remove_togglebutton.sensitive = true;
					remove_togglebutton.active = to_remove.contains (pkg.name);
					if (aur_pkg == null) {
						if (pkg.repo != null) {
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
						string aur_url = "http://aur.archlinux.org/packages/" + pkg.name;
						if (escaped_url != null) {
							link_label.set_markup ("<a href=\"%s\">%s</a>\n\n<a href=\"%s\">%s</a>".printf (escaped_url, escaped_url, aur_url, aur_url));
						} else {
							link_label.set_markup ("<a href=\"%s\">%s</a>".printf (aur_url, aur_url));
						}
					}
				}
			} else {
				launch_button.visible = false;
				remove_togglebutton.visible = false;
				reinstall_togglebutton.visible = false;
				build_togglebutton.visible = false;
				install_togglebutton.visible = true;
				install_togglebutton.active = to_install.contains (pkg.name);
			}
			// details
			details_grid.foreach (transaction.destroy_widget);
			Gtk.Widget? previous_widget = null;
			if (pkg.license != null) {
				previous_widget = populate_details_grid (dgettext (null, "Licenses"), pkg.license, previous_widget);
			} else {
				previous_widget = populate_details_grid (dgettext (null, "Licenses"), dgettext (null, "Unknown"), previous_widget);
			}
			if (pkg.repo != null) {
				if (software_mode) {
					if (pkg.repo == "community" || pkg.repo == "extra" || pkg.repo == "core" || pkg.repo == "multilib") {
						previous_widget = populate_details_grid (dgettext (null, "Repository"), dgettext (null, "Official Repositories"), previous_widget);
					} else {
						previous_widget = populate_details_grid (dgettext (null, "Repository"), pkg.repo, previous_widget);
					}
				} else {
					previous_widget = populate_details_grid (dgettext (null, "Repository"), pkg.repo, previous_widget);
				}
			}
			if (aur_pkg != null) {
				if (aur_pkg.packagebase != pkg.name) {
					previous_widget = populate_details_grid (dgettext (null, "Package Base"), aur_pkg.packagebase, previous_widget);
				}
				if (aur_pkg.maintainer != null) {
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
			if (!software_mode) {
				if (pkg.groups.length != 0) {
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
			if (!software_mode) {
				var time = GLib.Time.local ((time_t) pkg.build_date);
				previous_widget = populate_details_grid (dgettext (null, "Build Date"), time.format ("%x"), previous_widget);
			}
			if (pkg.install_date != 0) {
				var time = GLib.Time.local ((time_t) pkg.install_date);
				previous_widget = populate_details_grid (dgettext (null, "Install Date"), time.format ("%x"), previous_widget);
			}
			if (!software_mode) {
				if (pkg.reason != null) {
					previous_widget = populate_details_grid (dgettext (null, "Install Reason"), pkg.reason, previous_widget);
				}
				if (pkg.has_signature != null) {
					previous_widget = populate_details_grid (dgettext (null, "Signatures"), pkg.has_signature, previous_widget);
				}
				if (pkg.backups.length != 0) {
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
			}
			details_grid.show_all ();
			// deps
			deps_box.foreach (transaction.destroy_widget);
			if (pkg.depends.length != 0) {
				populate_deps_box (dgettext (null, "Depends On"), pkg.depends);
			}
			if (pkg.optdepends.length != 0) {
				populate_deps_box (dgettext (null, "Optional Dependencies"), pkg.optdepends, true);
			}
			if (pkg.makedepends.length != 0) {
				populate_deps_box (dgettext (null, "Make Dependencies"), pkg.makedepends);
			}
			if (pkg.checkdepends.length != 0) {
				populate_deps_box (dgettext (null, "Check Dependencies"), pkg.checkdepends);
			}
			if (pkg.requiredby.length != 0) {
				populate_deps_box (dgettext (null, "Required By"), pkg.requiredby);
			}
			if (pkg.optionalfor.length != 0) {
				populate_deps_box (dgettext (null, "Optional For"), pkg.optionalfor);
			}
			if (pkg.provides.length != 0) {
				populate_deps_box (dgettext (null, "Provides"), pkg.provides);
			}
			if (pkg.replaces.length != 0) {
				populate_deps_box (dgettext (null, "Replaces"), pkg.replaces);
			}
			if (pkg.conflicts.length != 0) {
				populate_deps_box (dgettext (null, "Conflicts With"), pkg.conflicts);
			}
			deps_box.show_all ();
			// files
			files_scrolledwindow.visible = true;
			// will be populated on properties_stack switch
			if (properties_stack.visible_child_name == "files") {
				properties_stack.visible_child_name = "details";
			}
			// build_files
			build_files_box.visible = aur_pkg != null;
			// will be populated on properties_stack switch
			if (properties_stack.visible_child_name == "build_files") {
				properties_stack.visible_child_name = "details";
			}
		}

		void set_aur_details (AURPackage aur_pkg) {
			details_grid.foreach (transaction.destroy_widget);
			deps_box.foreach (transaction.destroy_widget);
			screenshots_stack.foreach (transaction.destroy_widget);
			previous_screenshot_button.visible = false;
			next_screenshot_button.visible = false;
			launch_button.visible = false;
			remove_togglebutton.visible = false;
			reinstall_togglebutton.visible = false;
			install_togglebutton.visible = false;
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
			unowned string? url = aur_pkg.url;
			if (url != null) {
				string escaped_url = Markup.escape_text (url);
				link_label.set_markup ("<a href=\"%s\">%s</a>\n\n<a href=\"%s\">%s</a>".printf (escaped_url, escaped_url, aur_url, aur_url));
			} else {
				link_label.set_markup ("<a href=\"%s\">%s</a>".printf (aur_url, aur_url));
			}
			// details
			Gtk.Widget? previous_widget = null;
			if (aur_pkg.license != null) {
				previous_widget = populate_details_grid (dgettext (null, "Licenses"), aur_pkg.license, previous_widget);
			} else {
				previous_widget = populate_details_grid (dgettext (null, "Licenses"), dgettext (null, "Unknown"), previous_widget);
			}
			if (aur_pkg.repo != null) {
				previous_widget = populate_details_grid (dgettext (null, "Repository"), aur_pkg.repo, previous_widget);
			}
			if (aur_pkg.packagebase != aur_pkg.name) {
				previous_widget = populate_details_grid (dgettext (null, "Package Base"), aur_pkg.packagebase, previous_widget);
			}
			if (aur_pkg.maintainer != null) {
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
			if (aur_pkg.packager != null) {
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
			if (aur_pkg.build_date != 0) {
				var time = GLib.Time.local ((time_t) aur_pkg.build_date);
				previous_widget = populate_details_grid (dgettext (null, "Build Date"), time.format ("%x"), previous_widget);
			}
			if (aur_pkg.install_date != 0) {
				var time = GLib.Time.local ((time_t) aur_pkg.install_date);
				previous_widget = populate_details_grid (dgettext (null, "Install Date"), time.format ("%x"), previous_widget);
			}
			if (aur_pkg.reason != null) {
				previous_widget = populate_details_grid (dgettext (null, "Install Reason"), aur_pkg.reason, previous_widget);
			}
			if (aur_pkg.has_signature != null) {
				previous_widget = populate_details_grid (dgettext (null, "Signatures"), aur_pkg.has_signature, previous_widget);
			}
			if (aur_pkg.backups.length != 0) {
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
			if (aur_pkg.depends.length != 0) {
				populate_deps_box (dgettext (null, "Depends On"), aur_pkg.depends);
			}
			if (aur_pkg.makedepends.length != 0) {
				populate_deps_box (dgettext (null, "Make Dependencies"), aur_pkg.makedepends);
			}
			if (aur_pkg.checkdepends.length != 0) {
				populate_deps_box (dgettext (null, "Check Dependencies"), aur_pkg.checkdepends);
			}
			if (aur_pkg.optdepends.length != 0) {
				populate_deps_box (dgettext (null, "Optional Dependencies"), aur_pkg.optdepends);
			}
			if (aur_pkg.provides.length != 0) {
				populate_deps_box (dgettext (null, "Provides"), aur_pkg.provides);
			}
			if (aur_pkg.replaces.length != 0) {
				populate_deps_box (dgettext (null, "Replaces"), aur_pkg.replaces);
			}
			if (aur_pkg.conflicts.length != 0) {
				populate_deps_box (dgettext (null, "Conflicts With"), aur_pkg.conflicts);
			}
			deps_box.show_all ();
			// build files
			build_files_box.visible = true;
			// will be populated on properties_stack switch
			if (properties_stack.visible_child_name == "build_files") {
				properties_stack.visible_child_name = "details";
			}
		}

		void set_snap_details (SnapPackage snap_pkg) {
			// download screenshot
			screenshots_stack.foreach ((widget) => {
				if (widget is Gtk.Image) {
					widget.destroy ();
				}
			});
			set_screenshots (snap_pkg);
			// infos
			name_label.set_markup ("<big><b>%s  %s</b></big>".printf (Markup.escape_text (snap_pkg.app_name), snap_pkg.version));
			unowned string? icon = snap_pkg.icon;
			if (icon != null) {
				if ("http" in icon) {
					app_image.pixbuf = package_icon;
					get_icon_pixbuf.begin (icon, (obj, res) => {
						app_image.pixbuf = get_icon_pixbuf.end (res);
					});
				} else {
					try {
						var pixbuf = new Gdk.Pixbuf.from_file (icon);
						app_image.pixbuf = pixbuf;
					} catch (Error e) {
						app_image.pixbuf = package_icon;
						// try to retrieve icon
						database.get_installed_snap_icon_async.begin (snap_pkg.name, (obj, res) => {
							string downloaded_pixbuf_path = database.get_installed_snap_icon_async.end (res);
							try {
								app_image.pixbuf = new Gdk.Pixbuf.from_file_at_scale (downloaded_pixbuf_path, 64, 64, true);
							} catch (Error e) {
								warning ("%s: %s", snap_pkg.name, e.message);
							}
						});
					}
				}
			} else {
				app_image.pixbuf = package_icon;
			}
			desc_label.set_text (snap_pkg.desc);
			long_desc_label.set_text (snap_pkg.long_desc);
			long_desc_label.visible = true;
			string escaped_url = Markup.escape_text (snap_pkg.url);
			link_label.set_markup ("<a href=\"%s\">%s</a>".printf (escaped_url, escaped_url));
			if (snap_pkg.installed_version != null) {
				unowned string? launchable = snap_pkg.launchable;
				if (launchable != null) {
					launch_button.visible = true;
					current_launchable = launchable;
				} else {
					launch_button.visible = false;
				}
				install_togglebutton.visible = false;
				build_togglebutton.visible = false;
				reinstall_togglebutton.visible = false;
				remove_togglebutton.visible = true;
				remove_togglebutton.sensitive = true;
				remove_togglebutton.active = snap_to_remove.contains (snap_pkg.name);
			} else {
				launch_button.visible = false;
				remove_togglebutton.visible = false;
				reinstall_togglebutton.visible = false;
				build_togglebutton.visible = false;
				install_togglebutton.visible = true;
				install_togglebutton.active = snap_to_install.contains (snap_pkg.name);
			}
			// details
			details_grid.foreach (transaction.destroy_widget);
			Gtk.Widget? previous_widget = null;
			if (snap_pkg.license != null) {
				previous_widget = populate_details_grid (dgettext (null, "Licenses"), snap_pkg.license, previous_widget);
			} else {
				previous_widget = populate_details_grid (dgettext (null, "Licenses"), dgettext (null, "Unknown"), previous_widget);
			}
			previous_widget = populate_details_grid (dgettext (null, "Repository"), snap_pkg.repo, previous_widget);
			// make packager mail clickable
			if (snap_pkg.publisher != null) {
				previous_widget = populate_details_grid (dgettext (null, "Publisher"), snap_pkg.publisher, previous_widget);
			}
			if (snap_pkg.confined != null) {
				previous_widget = populate_details_grid (dgettext (null, "Confined in a Sandbox"), snap_pkg.confined, previous_widget);
			}
			if (snap_pkg.install_date != 0) {
				var time = GLib.Time.local ((time_t) snap_pkg.install_date);
				previous_widget = populate_details_grid (dgettext (null, "Install Date"), time.format ("%x"), previous_widget);
				if (snap_pkg.channels.length != 0) {
					var label = new Gtk.Label ("<b>%s</b>".printf (dgettext (null, "Channels") + ":"));
					label.use_markup = true;
					label.halign = Gtk.Align.START;
					label.valign = Gtk.Align.START;
					details_grid.attach_next_to (label, previous_widget, Gtk.PositionType.BOTTOM);
					var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
					foreach (unowned string channel in snap_pkg.channels) {
						string[] split = channel.split (" : ", 2);
						string channel_name = split[0];
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
									transaction.snap_switch_channel_async.begin (snap_pkg.name, channel_name, () => {
										transaction_running = false;
										transaction.reset_progress_box ();
										if (current_package_displayed.name == snap_pkg.name) {
											database.get_snap_async.begin (snap_pkg.name, (obj, res) => {
												var new_snap_pkg = database.get_snap_async.end (res);
												set_snap_details (new_snap_pkg);
											});
										}
									});
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
			}
			details_grid.show_all ();
			// deps
			deps_box.foreach (transaction.destroy_widget);
		}

		void set_flatpak_details (FlatpakPackage flatpak_pkg) {
			// download screenshot
			screenshots_stack.foreach ((widget) => {
				if (widget is Gtk.Image) {
					widget.destroy ();
				}
			});
			set_screenshots (flatpak_pkg);
			// infos
			unowned string? app_name = flatpak_pkg.app_name;
			if (app_name == null) {
				name_label.set_markup ("<big><b>%s  %s</b></big>".printf (flatpak_pkg.name, flatpak_pkg.version));
			} else {
				name_label.set_markup ("<big><b>%s  %s</b></big>".printf (Markup.escape_text (app_name), flatpak_pkg.version));
			}
			unowned string? icon = flatpak_pkg.icon;
			if (icon != null) {
				try {
					var pixbuf = new Gdk.Pixbuf.from_file (icon);
					app_image.pixbuf = pixbuf;
				} catch (Error e) {
					app_image.pixbuf = package_icon;
				}
			} else {
				app_image.pixbuf = package_icon;
			}
			desc_label.set_text (flatpak_pkg.desc);
			unowned string? long_desc = flatpak_pkg.long_desc;
			if (long_desc == null) {
				long_desc_label.visible = false;
			} else {
				long_desc_label.set_text (long_desc);
				long_desc_label.visible = true;
			}
			unowned string? url = flatpak_pkg.url;
			if (url != null) {
				string escaped_url = Markup.escape_text (flatpak_pkg.url);
				link_label.set_markup ("<a href=\"%s\">%s</a>".printf (escaped_url, escaped_url));
			}
			if (flatpak_pkg.installed_version != null) {
				unowned string? launchable = flatpak_pkg.launchable;
				if (launchable != null) {
					launch_button.visible = true;
					current_launchable = launchable;
				} else {
					launch_button.visible = false;
				}
				install_togglebutton.visible = false;
				build_togglebutton.visible = false;
				reinstall_togglebutton.visible = false;
				remove_togglebutton.visible = true;
				remove_togglebutton.sensitive = true;
				remove_togglebutton.active = flatpak_to_remove.contains (flatpak_pkg.name);
			} else {
				launch_button.visible = false;
				remove_togglebutton.visible = false;
				reinstall_togglebutton.visible = false;
				build_togglebutton.visible = false;
				install_togglebutton.visible = true;
				install_togglebutton.active = flatpak_to_install.contains (flatpak_pkg.name);
			}
			// details
			details_grid.foreach (transaction.destroy_widget);
			Gtk.Widget? previous_widget = null;
			if (flatpak_pkg.license != null) {
				previous_widget = populate_details_grid (dgettext (null, "Licenses"), flatpak_pkg.license, previous_widget);
			} else {
				previous_widget = populate_details_grid (dgettext (null, "Licenses"), dgettext (null, "Unknown"), previous_widget);
			}
			previous_widget = populate_details_grid (dgettext (null, "Repository"), flatpak_pkg.repo, previous_widget);
			details_grid.show_all ();
			// deps
			deps_box.foreach (transaction.destroy_widget);
		}

		void on_properties_stack_visible_child_changed () {
			switch (properties_stack.visible_child_name) {
				case "files":
					if (current_files != current_package_displayed.name) {
						this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
						database.get_pkg_files_async.begin (current_package_displayed.name, (obj, res) => {
							var files = database.get_pkg_files_async.end (res);
							StringBuilder text = new StringBuilder ();
							foreach (unowned string file in files) {
								if (text.len > 0) {
									text.append ("\n");
								}
								text.append (file);
							}
							files_textview.buffer.set_text (text.str, (int) text.len);
							this.get_window ().set_cursor (null);
							current_files = current_package_displayed.name;
						});
						files_textview.buffer.set_text ("", 0);
						packages_scrolledwindow.vadjustment.value = 0;
					}
					break;
				case "build_files":
					if (current_build_files != current_package_displayed.name) {
						this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
						database.get_aur_pkg_async.begin (current_package_displayed.name, (obj, res) => {
							AURPackage pkg = database.get_aur_pkg_async.end (res);
							if (pkg != null) {
								transaction.populate_build_files_async.begin (pkg.packagebase, true, false, () => {
									this.get_window ().set_cursor (null);
								});
							} else {
								this.get_window ().set_cursor (null);
							}
							current_build_files = current_package_displayed.name;
						});
					}
					break;
				default:
					break;
			}
		}

		[GtkCallback]
		void on_launch_button_clicked () {
			try {
				new Subprocess.newv ({"gtk-launch", current_launchable}, SubprocessFlags.NONE);
			} catch (Error e) {
				warning (e.message);
			}
		}

		[GtkCallback]
		void on_install_togglebutton_toggled () {
			if (install_togglebutton.active) {
				install_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
				if (current_package_displayed is SnapPackage) {
					snap_to_install.insert (current_package_displayed.name, current_package_displayed as SnapPackage);
				} else if (current_package_displayed is FlatpakPackage) {
					flatpak_to_install.insert (current_package_displayed.name, current_package_displayed as FlatpakPackage);
				} else {
					to_install.add (current_package_displayed.name);
				}
			} else {
				install_togglebutton.image = null;
				if (current_package_displayed is SnapPackage) {
					snap_to_install.remove (current_package_displayed.name);
				} else if (current_package_displayed is FlatpakPackage) {
					flatpak_to_install.remove (current_package_displayed.name);
				} else {
					to_install.remove (current_package_displayed.name);
				}
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
					transaction.save_build_files_async.begin (current_package_displayed.name);
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
			transaction.populate_build_files_async.begin (aur_pkg.packagebase, true, true);
		}

		[GtkCallback]
		void on_remove_togglebutton_toggled () {
			if (remove_togglebutton.active) {
				reinstall_togglebutton.active = false;
				reinstall_togglebutton.image = null;
				remove_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
				if (current_package_displayed is SnapPackage) {
					snap_to_install.remove (current_package_displayed.name);
					snap_to_remove.insert (current_package_displayed.name, current_package_displayed as SnapPackage);
				} else if (current_package_displayed is FlatpakPackage) {
					flatpak_to_install.remove (current_package_displayed.name);
					flatpak_to_remove.insert (current_package_displayed.name, current_package_displayed as FlatpakPackage);
				} else {
					to_install.remove (current_package_displayed.name);
					to_remove.add (current_package_displayed.name);
				}
			} else {
				remove_togglebutton.image = null;
				if (current_package_displayed is SnapPackage) {
					snap_to_remove.remove (current_package_displayed.name);
				} else if (current_package_displayed is FlatpakPackage) {
					flatpak_to_remove.remove (current_package_displayed.name);
				} else {
					to_remove.remove (current_package_displayed.name);
				}
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

		void populate_listbox () {
			// populate listbox
			if (current_packages_list_length == 0) {
				browse_stack.visible_child_name = "no_item";
				this.get_window ().set_cursor (null);
				return;
			} else {
				clear_packages_listbox ();
				browse_stack.visible_child_name = "packages";
			}
			// create os updates row
			if (main_updates_togglebutton.active) {
				bool software_mode = false;
				uint64 download_size = 0;
				if (local_config.software_mode) {
					foreach (unowned Package pkg in current_packages_list) {
						if (pkg.app_name == null) {
							download_size += pkg.download_size;
							software_mode = true;
						}
					}
				}
				if (software_mode) {
					create_os_updates_row (download_size);
				}
			}
			bool populated = false;
			do {
				populated = complete_packages_list ();
			} while (need_more_packages ());
			// scroll to top
			if (scroll_to_top) {
				packages_scrolledwindow.vadjustment.value = 0;
			} else {
				// don't scroll to top just once
				scroll_to_top = true;
			}
			if (local_config.software_mode && !populated) {
				browse_stack.visible_child_name = "no_item";
			}
			this.get_window ().set_cursor (null);
		}

		void sort_aur_list (ref GenericArray<unowned Package> pkgs) {
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

		void populate_aur_list (GenericArray<unowned Package> pkgs) {
			current_packages_list = pkgs;
			current_packages_list_index = 0;
			current_packages_list_length = current_packages_list.length;
			sort_aur_list (ref current_packages_list);
			populate_listbox ();
		}

		void sort_packages_list (ref GenericArray<unowned Package> pkgs) {
			unowned string sortby = sortby_button_label.label;
			if (sortby == dgettext (null, "Relevance")) {
				if (search_togglebutton.active) {
					pkgs.sort (sort_search_pkgs_by_relevance);
				} else {
					pkgs.sort (sort_pkgs_by_relevance);
				}
			} else if (sortby == dgettext (null, "Name")) {
				pkgs.sort (sort_pkgs_by_name);
			} else if (sortby == dgettext (null, "Repository")) {
				pkgs.sort (sort_pkgs_by_repo);
			} else if (sortby == dgettext (null, "Size")) {
				if (main_updates_togglebutton.active) {
					pkgs.sort (sort_pkgs_by_download_size);
				} else {
					pkgs.sort (sort_pkgs_by_installed_size);
				}
			} else if (sortby == dgettext (null, "Date")) {
				pkgs.sort (sort_pkgs_by_date);
			}
		}

		void populate_packages_list (GenericArray<unowned Package> pkgs) {
			current_packages_list = pkgs;
			current_packages_list_index = 0;
			current_packages_list_length = current_packages_list.length;
			sort_packages_list (ref current_packages_list);
			populate_listbox ();
		}

		bool need_more_packages () {
			if (current_packages_list_index < current_packages_list_length) {
				int natural_height;
				packages_listbox.get_preferred_height (null, out natural_height);
				if (packages_scrolledwindow.vadjustment.page_size > natural_height) {
					return true;
				}
			}
			return false;
		}

		bool complete_packages_list () {
			bool populated = false;
			if (current_packages_list_index < current_packages_list_length) {
				uint i = 0;
				// display the next 20 packages
				while (i < 20) {
					unowned Package pkg = current_packages_list[current_packages_list_index];
					if (!local_config.software_mode || pkg.app_name != null) {
						var row = create_packagelist_row (pkg);
						packages_listbox.add (row);
						populated = true;
						i++;
					}
					current_packages_list_index++;
					if (current_packages_list_index == current_packages_list_length) {
						break;
					}
				}
			}
			return populated;
		}

		PackageRow create_packagelist_row (Package pkg) {
			bool is_update = main_updates_togglebutton.active;
			var row = new PackageRow (pkg);
			//populate info
			unowned string? app_name = pkg.app_name;
			AlpmPackage? alpm_pkg = pkg as AlpmPackage;
			bool software_mode = local_config.software_mode;
			if (app_name == null) {
				row.name_label.set_markup ("<b>%s</b>".printf (pkg.name));
			} else if (alpm_pkg != null && !software_mode) {
				row.name_label.set_markup ("<b>%s (%s)</b>".printf (Markup.escape_text (app_name), pkg.name));
			} else {
				row.name_label.set_markup ("<b>%s</b>".printf (Markup.escape_text (app_name)));
			}
			unowned string? desc = pkg.desc;
			if (desc != null) {
				row.desc_label.label = Markup.escape_text (desc);
			} else {
				row.desc_label.label = "";
			}
			if (is_update) {
				if (pkg is FlatpakPackage) {
					row.version_label.set_markup ("<b>%s</b>".printf (pkg.version));
				} else {
					row.version_label.set_markup ("<b>%s  (%s)</b>".printf (pkg.version, pkg.installed_version));
				}
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
			if (pkg.repo != null) {
				if (alpm_pkg != null) {
					if (pkg.repo == "community" || pkg.repo == "extra" || pkg.repo == "core" || pkg.repo == "multilib") {
						if (software_mode) {
							row.repo_label.set_markup ("<span foreground='grey'>%s</span>".printf (dgettext (null, "Official Repositories")));
						} else {
							row.repo_label.set_markup ("<span foreground='grey'>%s (%s)</span>".printf (dgettext (null, "Official Repositories"), pkg.repo));
						}
					} else if (pkg.repo == dgettext (null, "AUR")) {
						row.repo_label.set_markup ("<span foreground='grey'>%s</span>".printf (pkg.repo));
					} else {
						row.repo_label.set_markup ("<span foreground='grey'>%s (%s)</span>".printf (dgettext (null, "Repositories"), pkg.repo));
					}
				} else if (pkg is FlatpakPackage) {
					row.repo_label.set_markup ("<span foreground='grey'>%s (%s)</span>".printf (dgettext (null, "Flatpak"), pkg.repo));
				} else {
					row.repo_label.set_markup ("<span foreground='grey'>%s</span>".printf (pkg.repo));
				}
			}
			Gdk.Pixbuf pixbuf;
			unowned string? icon = pkg.icon;
			if (icon != null) {
				if ("http" in icon) {
					pixbuf = package_icon.scale_simple (48, 48, Gdk.InterpType.BILINEAR);
					get_icon_pixbuf.begin (icon, (obj, res) => {
						var downloaded_pixbuf = get_icon_pixbuf.end (res);
						if (downloaded_pixbuf != null) {
							row.app_icon.pixbuf = downloaded_pixbuf.scale_simple (48, 48, Gdk.InterpType.BILINEAR);
						}
					});
				} else {
					try {
						pixbuf = new Gdk.Pixbuf.from_file_at_scale (icon, 48, 48, true);
					} catch (Error e) {
						if (pkg is SnapPackage && pkg.installed_version != null) {
							pixbuf = package_icon.scale_simple (48, 48, Gdk.InterpType.BILINEAR);
							// try to retrieve icon
							database.get_installed_snap_icon_async.begin (pkg.name, (obj, res) => {
								string downloaded_pixbuf_path = database.get_installed_snap_icon_async.end (res);
								try {
									pixbuf = new Gdk.Pixbuf.from_file_at_scale (downloaded_pixbuf_path, 48, 48, true);
								} catch (Error e) {
									warning ("%s: %s", pkg.name, e.message);
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
							try {
								pixbuf = new Gdk.Pixbuf.from_file_at_scale (new_icon, 48, 48, true);
							} catch (Error e) {
								pixbuf = package_icon.scale_simple (48, 48, Gdk.InterpType.BILINEAR);
								warning ("%s: %s", icon, e.message);
							}
						}
					}
				}
			} else {
				pixbuf = package_icon.scale_simple (48, 48, Gdk.InterpType.BILINEAR);
			}
			row.app_icon.pixbuf = pixbuf;
			if (transaction.transaction_summary_contains (pkg.id)) {
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
						// remove from config.ignorepkgs to override config
						database.config.ignorepkgs.remove (pkg.name);
					} else {
						to_update.remove (pkg.name);
						temporary_ignorepkgs.add (pkg.name);
					}
					refresh_listbox_buttons ();
					set_pendings_operations ();
				});
			} else if (pkg.installed_version == null) {
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
			return row;
		}

		void create_os_updates_row (uint64 download_size) {
			var row = new PackageRow (null);
			// populate info
			row.name_label.set_markup ("<b>%s</b>".printf (dgettext (null, "OS Updates")));
			row.desc_label.label = dgettext (null, "Includes performance, stability and security improvements");
			row.version_label.label = "";
			if (download_size == 0) {
				row.size_label.label = "";
			} else {
				row.size_label.set_markup ("<span foreground='grey'>%s</span>".printf (GLib.format_size (download_size)));
			}
			row.repo_label.set_markup ("<span foreground='grey'>%s</span>".printf (dgettext (null, "Official Repositories")));
			row.app_icon.pixbuf = package_icon.scale_simple (48, 48, Gdk.InterpType.BILINEAR);
			row.action_togglebutton.label = dgettext (null, "Upgrade");
			row.action_togglebutton.active = true;
			row.action_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
			row.action_togglebutton.sensitive = false;
			// insert
			packages_listbox.add (row);
		}

		PackageRow create_update_row (Package pkg) {
			var row = new PackageRow (pkg);
			//populate info
			unowned string? app_name = pkg.app_name;
			AlpmPackage? alpm_pkg = pkg as AlpmPackage;
			bool software_mode = local_config.software_mode;
			if (app_name == null) {
				row.name_label.set_markup ("<b>%s</b>".printf (pkg.name));
			} else if (alpm_pkg != null && !software_mode) {
				row.name_label.set_markup ("<b>%s (%s)</b>".printf (Markup.escape_text (app_name), pkg.name));
			} else {
				row.name_label.set_markup ("<b>%s</b>".printf (Markup.escape_text (app_name)));
			}
			unowned string? desc = pkg.desc;
			if (desc != null) {
				row.desc_label.label = Markup.escape_text (desc);
			} else {
				row.desc_label.label = "";
			}
			if (pkg is FlatpakPackage) {
				row.version_label.set_markup ("<b>%s</b>".printf (pkg.version));
			} else {
				row.version_label.set_markup ("<b>%s  (%s)</b>".printf (pkg.version, pkg.installed_version));
			}
			if (pkg.download_size == 0) {
				row.size_label.label = "";
			} else {
				row.size_label.set_markup ("<span foreground='grey'>%s</span>".printf (GLib.format_size (pkg.download_size)));
			}
			if (alpm_pkg != null && pkg.repo != null) {
				if (pkg.repo == "community" || pkg.repo == "extra" || pkg.repo == "core" || pkg.repo == "multilib") {
					if (software_mode) {
						row.repo_label.set_markup ("<span foreground='grey'>%s</span>".printf (dgettext (null, "Official Repositories")));
					} else {
						row.repo_label.set_markup ("<span foreground='grey'>%s (%s)</span>".printf (dgettext (null, "Official Repositories"), pkg.repo));
					}
				} else if (pkg.repo == dgettext (null, "AUR")) {
					row.repo_label.set_markup ("<span foreground='grey'>%s</span>".printf (pkg.repo));
				} else if (pkg.repo != null) {
					row.repo_label.set_markup ("<span foreground='grey'>%s (%s)</span>".printf (dgettext (null, "Repositories"), pkg.repo));
				}
			} else if (pkg is FlatpakPackage) {
				row.repo_label.set_markup ("<span foreground='grey'>%s (%s)</span>".printf (dgettext (null, "Flatpak"), pkg.repo));
			} else {
				row.repo_label.set_markup ("<span foreground='grey'>%s</span>".printf (pkg.repo));
			}
			Gdk.Pixbuf pixbuf;
			unowned string? icon = pkg.icon;
			if (icon != null) {
				if ("http" in icon) {
					pixbuf = package_icon.scale_simple (48, 48, Gdk.InterpType.BILINEAR);
					get_icon_pixbuf.begin (icon, (obj, res) => {
						var downloaded_pixbuf = get_icon_pixbuf.end (res);
						if (downloaded_pixbuf != null) {
							row.app_icon.pixbuf = downloaded_pixbuf.scale_simple (48, 48, Gdk.InterpType.BILINEAR);
						}
					});
				} else {
					try {
						pixbuf = new Gdk.Pixbuf.from_file_at_scale (icon, 48, 48, true);
					} catch (Error e) {
						// some icons are not in the right repo
						string new_icon = icon;
						if ("extra" in icon) {
							new_icon = icon.replace ("extra", "community");
						} else if ("community" in icon) {
							new_icon = icon.replace ("community", "extra");
						}
						try {
							pixbuf = new Gdk.Pixbuf.from_file_at_scale (new_icon, 48, 48, true);
						} catch (Error e) {
							pixbuf = package_icon.scale_simple (48, 48, Gdk.InterpType.BILINEAR);
							warning ("%s: %s", icon, e.message);
						}
					}
				}
			} else {
				pixbuf = package_icon.scale_simple (48, 48, Gdk.InterpType.BILINEAR);
			}
			row.app_icon.pixbuf = pixbuf;
			if (transaction.transaction_summary_contains (pkg.id)) {
				row.action_togglebutton.sensitive = false;
			}
			row.action_togglebutton.label = dgettext (null, "Upgrade");
			row.action_togglebutton.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
			if (!(pkg.name in temporary_ignorepkgs)) {
				row.action_togglebutton.active = true;
				row.action_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
			}
			row.action_togglebutton.toggled.connect ((button) => {
				if (button.active) {
					row.action_togglebutton.active = true;
					row.action_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
					to_update.add (pkg.name);
					temporary_ignorepkgs.remove (pkg.name);
					// remove from config.ignorepkgs to override config
					database.config.ignorepkgs.remove (pkg.name);
				} else {
					row.action_togglebutton.active = false;
					row.action_togglebutton.image = null;
					to_update.remove (pkg.name);
					temporary_ignorepkgs.add (pkg.name);
				}
				set_pendings_operations ();
			});
			return row;
		}

		void refresh_listbox_buttons () {
			packages_listbox.foreach ((row) => {
				unowned PackageRow pamac_row = row as PackageRow;
				if (pamac_row == null) {
					return;
				}
				Package? pkg = pamac_row.pkg;
				if (pkg == null) {
					return;
				}
				if (transaction.transaction_summary_contains (pkg.id)) {
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
				} else if (pkg is SnapPackage) {
					if (pkg.name in snap_to_install ||
						pkg.name in snap_to_remove) {
						pamac_row.action_togglebutton.active = true;
						pamac_row.action_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
					} else {
						pamac_row.action_togglebutton.active = false;
						pamac_row.action_togglebutton.image = null;
					}
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
				} else if (pkg is AlpmPackage){
					if (pkg.installed_version == null) {
						if (pkg.name in to_install) {
							pamac_row.action_togglebutton.active = true;
							pamac_row.action_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
						} else {
							pamac_row.action_togglebutton.active = false;
							pamac_row.action_togglebutton.image = null;
						}
						return;
					}
					if (main_updates_togglebutton.active) {
						if (pkg.name in to_update) {
							pamac_row.action_togglebutton.active = true;
							pamac_row.action_togglebutton.image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
						} else {
							pamac_row.action_togglebutton.active = false;
							pamac_row.action_togglebutton.image = null;
						}
						return;
					}
					if (pkg.name in to_remove) {
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
			if (search_togglebutton.active) {
				view_button_label.label = current_search_view;
				browseby_box.visible = false;
				remove_all_button.visible = false;
				install_all_button.visible = false;
				ignore_all_button.visible = false;
				if (local_config.software_mode) {
					view_box.visible = false;
				} else {
					view_button.popover = view_popovermenu;
					view_installed_button.visible = true;
					view_explicitly_installed_button.visible = false;
					view_orphans_button.visible = false;
					view_foreign_button.visible = false;
					view_repositories_button.visible = true;
					view_aur_button.visible = enable_aur;
					view_snap_button.visible = database.config.enable_snap;
					view_flatpak_button.visible = database.config.enable_flatpak;
					view_box.visible = true;
				}
				browse_head_box.visible = true;
				browse_separator.visible = true;
				unowned string filter = view_button_label.label;
				if (filter == dgettext (null, "All")) {
					on_view_all_button_clicked ();
				} else if (filter == dgettext (null, "Installed")) {
					on_view_installed_button_clicked ();
				} else if (filter == dgettext (null, "Repositories")) {
					on_view_repositories_button_clicked ();
				} else if (filter == dgettext (null, "AUR")) {
					on_view_aur_button_clicked ();
				} else if (filter == dgettext (null, "Snap")) {
					on_view_snap_button_clicked ();
				} else if (filter == dgettext (null, "Flatpak")) {
					on_view_flatpak_button_clicked ();
				}
				set_pendings_operations ();
			} else if (main_browse_togglebutton.active) {
				view_button_label.label = current_category_view;
				browseby_box.visible = !local_config.software_mode;
				ignore_all_button.visible = false;
				if (browseby_button_label.label == dgettext (null, "Categories")) {
					remove_all_button.visible = false;
					install_all_button.visible = false;
					view_button.popover = categories_popovermenu;
				} else if (browseby_button_label.label == dgettext (null, "Groups")) {
					view_button.popover = groups_popovermenu;
				} else if (browseby_button_label.label == dgettext (null, "Repositories")) {
					remove_all_button.visible = false;
					install_all_button.visible = false;
					view_button.popover = repos_popovermenu;
				}
				browse_head_box.visible = true;
				browse_separator.visible = true;
				view_box.visible = true;
				if (browseby_button_label.label == dgettext (null, "Categories")) {
					unowned string category = view_button_label.label;
					if (category == dgettext (null, "Featured")) {
						on_featured_button_clicked ();
					} else if (category == dgettext (null, "Photo & Video")) {
						on_photo_video_button_clicked ();
					} else if (category == dgettext (null, "Music & Audio")) {
						on_music_audio_button_clicked ();
					} else if (category == dgettext (null, "Productivity")) {
						on_productivity_button_clicked ();
					} else if (category == dgettext (null, "Communication & News")) {
						on_communication_news_button_clicked ();
					} else if (category == dgettext (null, "Education & Science")) {
						on_education_science_button_button_clicked ();
					} else if (category == dgettext (null, "Games")) {
						on_games_button_clicked ();
					} else if (category == dgettext (null, "Utilities")) {
						on_utilities_button_clicked ();
					} else if (category == dgettext (null, "Development")) {
						on_development_button_clicked ();
					}
					set_pendings_operations ();
				} else if (browseby_button_label.label == dgettext (null, "Groups")) {
					set_pendings_operations ();
					on_groups_listbox_row_activated (groups_listbox.get_selected_row ());
				} else if (browseby_button_label.label == dgettext (null, "Repositories")) {
					set_pendings_operations ();
					on_repos_listbox_row_activated (repos_listbox.get_selected_row ());
				}
			} else if (main_installed_togglebutton.active) {
				view_button_label.label = current_installed_view;
				browseby_box.visible = false;
				install_all_button.visible = false;
				remove_all_button.visible = false;
				ignore_all_button.visible = false;
				if (local_config.software_mode) {
					view_box.visible = false;
				} else {
					view_button.popover = view_popovermenu;
					view_installed_button.visible = false;
					view_explicitly_installed_button.visible = true;
					view_orphans_button.visible = true;
					view_foreign_button.visible = true;
					view_repositories_button.visible = false;
					view_aur_button.visible = false;
					view_snap_button.sensitive = true;
					view_snap_button.visible = database.config.enable_snap;
					view_flatpak_button.sensitive = true;
					view_flatpak_button.visible = database.config.enable_flatpak;
					view_box.visible = true;
				}
				browse_head_box.visible = true;
				browse_separator.visible = true;
				unowned string filter = view_button_label.label;
				if (filter == dgettext (null, "All")) {
					on_view_all_button_clicked ();
				} else if (filter == dgettext (null, "Explicitly installed")) {
					on_view_explicitly_installed_button_clicked ();
				} else if (filter == dgettext (null, "Orphans")) {
					on_view_orphans_button_clicked ();
				} else if (filter == dgettext (null, "Foreign")) {
					on_view_foreign_button_clicked ();
				} else if (filter == dgettext (null, "Snap")) {
					on_view_snap_button_clicked ();
				} else if (filter == dgettext (null, "Flatpak")) {
					on_view_flatpak_button_clicked ();
				}
				set_pendings_operations ();
			} else if (main_updates_togglebutton.active) {
				view_button_label.label = current_updates_view;
				browseby_box.visible = false;
				search_togglebutton.visible = false;
				remove_all_button.visible = false;
				install_all_button.visible = false;
				ignore_all_button.visible = false;
				view_box.visible = false;
				view_button.popover = view_popovermenu;
				view_installed_button.visible = false;
				view_explicitly_installed_button.visible = false;
				view_orphans_button.visible = false;
				view_foreign_button.visible = false;
				view_repositories_button.visible = true;
				view_aur_button.visible = enable_aur;
				view_flatpak_button.visible = database.config.enable_flatpak;
				apply_button.sensitive = false;
				cancel_button.sensitive = false;
				if (updates_checked) {
					populate_updates ();
				} else {
					on_refresh_button_clicked ();
				}
			} else if (main_pending_togglebutton.active) {
				view_button_label.label = dgettext (null, "All");
				browseby_box.visible = false;
				remove_all_button.visible = false;
				install_all_button.visible = false;
				ignore_all_button.visible = false;
				if (local_config.software_mode) {
					view_box.visible = false;
				} else {
					view_button.popover = view_popovermenu;
					view_installed_button.visible = false;
					view_explicitly_installed_button.visible = false;
					view_orphans_button.visible = false;
					view_foreign_button.visible = false;
					view_repositories_button.visible = true;
					if ((to_install.length + to_remove.length) > 0) {
						view_repositories_button.sensitive = true;
					} else {
						view_repositories_button.sensitive = false;
					}
					view_aur_button.visible = enable_aur;
					if (to_build.length > 0) {
						view_aur_button.sensitive = true;
					} else {
						view_aur_button.sensitive = false;
					}
					if (database.config.enable_snap) {
						view_snap_button.visible = true;
						if ((snap_to_install.length + snap_to_remove.length) > 0) {
							view_snap_button.sensitive = true;
						} else {
							view_snap_button.sensitive = false;
						}
					} else {
						view_snap_button.visible = false;
					}
					if (database.config.enable_flatpak) {
						view_flatpak_button.visible = true;
						if ((flatpak_to_install.length + flatpak_to_remove.length) > 0) {
							view_flatpak_button.sensitive = true;
						} else {
							view_flatpak_button.sensitive = false;
						}
					} else {
						view_flatpak_button.visible = false;
					}
					view_box.visible = true;
				}
				browse_head_box.visible = true;
				browse_separator.visible = true;
				unowned string filter = view_button_label.label;
				if (filter == dgettext (null, "All")) {
					on_view_all_button_clicked ();
				} else if (filter == dgettext (null, "Repositories")) {
					on_view_repositories_button_clicked ();
				} else if (filter == dgettext (null, "AUR")) {
					on_view_aur_button_clicked ();
				} else if (filter == dgettext (null, "Snap")) {
					on_view_snap_button_clicked ();
				} else if (filter == dgettext (null, "Flatpak")) {
					on_view_flatpak_button_clicked ();
				}
			}
		}

		public void display_details (Package pkg) {
			main_details_scrolledwindow.vadjustment.value = 0;
			if (pkg is AURPackage) {
				display_aur_details (pkg as AURPackage);
			} else if (pkg is AlpmPackage) {
				display_package_details (pkg as AlpmPackage);
			} else if (pkg is SnapPackage) {
				display_snap_details (pkg as SnapPackage);
			} else if (pkg is FlatpakPackage) {
				display_flatpak_details (pkg as FlatpakPackage);
			}
		}

		void refresh_details () {
			if (current_package_displayed is AURPackage) {
				database.get_aur_pkg_async.begin (current_package_displayed.name, (obj, res) => {
					Package? pkg = database.get_aur_pkg_async.end (res);
					if (pkg != null) {
						current_package_displayed = pkg;
					}
				});
			} else if (current_package_displayed is SnapPackage) {
				database.get_snap_async.begin (current_package_displayed.name, (obj, res) => {
					Package? pkg = database.get_snap_async.end (res);
					if (pkg != null) {
						current_package_displayed = pkg;
					}
				});
			} else if (current_package_displayed is FlatpakPackage) {
				FlatpakPackage current_flatpak = current_package_displayed as FlatpakPackage;
				database.get_flatpak_async.begin (current_flatpak.id, (obj, res) => {
					Package? pkg = database.get_flatpak_async.end (res);
					if (pkg != null) {
						current_package_displayed = pkg;
					}
				});
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
			if (properties_stack.visible_child_name == "build_files") {
				properties_stack.visible_child_name = "details";
			}
			deps_box.visible = true;
			files_scrolledwindow.visible = true;
			properties_stack_switcher.visible = !local_config.software_mode;
			set_package_details (pkg);
		}

		void display_aur_details (AURPackage aur_pkg) {
			current_package_displayed = aur_pkg;
			// select details if files was selected
			if (properties_stack.visible_child_name == "files") {
				properties_stack.visible_child_name = "details";
			}
			deps_box.visible = true;
			files_scrolledwindow.visible = false;
			build_files_box.visible = true;
			properties_stack_switcher.visible = true;
			set_aur_details (aur_pkg);
		}

		public void display_snap_details (SnapPackage snap_pkg) {
			current_package_displayed = snap_pkg;
			// select details if files or build files was selected
			if (properties_stack.visible_child_name == "files" ||
				properties_stack.visible_child_name == "build_files") {
				properties_stack.visible_child_name = "details";
			}
			properties_stack_switcher.visible = false;
			set_snap_details (snap_pkg);
		}

		public void display_flatpak_details (FlatpakPackage flatpak_pkg) {
			current_package_displayed = flatpak_pkg;
			// select details if files or build files was selected
			if (properties_stack.visible_child_name == "files" ||
				properties_stack.visible_child_name == "build_files") {
				properties_stack.visible_child_name = "details";
			}
			properties_stack_switcher.visible = false;
			set_flatpak_details (flatpak_pkg);
		}

		[GtkCallback]
		void on_packages_listbox_row_activated (Gtk.ListBoxRow row) {
			unowned PackageRow pamac_row = row as PackageRow;
			if (pamac_row == null) {
				return;
			}
			Package? pkg = pamac_row.pkg;
			if (pkg != null) {
				display_details (pkg);
				main_stack.visible_child_name = "details";
			} else {
				// check for OS Updates row
				if (pamac_row.name_label.label == "<b>%s</b>".printf (dgettext (null, "OS Updates"))) {
					var updates_dialog = new UpdatesDialog (this);
					updates_dialog.label.label = dgettext (null, "Includes performance, stability and security improvements");
					updates_dialog.listbox.set_header_func (set_header_func);
					// populates updates
					foreach (unowned Package update_pkg in current_packages_list) {
						if (update_pkg.app_name == null) {
							var update_row = create_update_row (update_pkg);
							updates_dialog.listbox.add (update_row);
						}
					}
					updates_dialog.show ();
					updates_dialog.response.connect (() => {
						updates_dialog.destroy ();
					});
				}
			}
		}

		void on_deps_listbox_row_activated (Gtk.ListBoxRow row) {
			if (display_package_queue.find_custom (current_package_displayed, compare_pkgs_by_name) == null) {
				display_package_queue.push_tail (current_package_displayed);
			}
			string? depstring = null;
			row.foreach ((widget) => {
				var dep_label = widget as Gtk.Label;
				if (dep_label != null) {
					depstring = dep_label.label;
				}
			});
			if (depstring == null) {
				return;
			}
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
					button_back.visible = false;
					search_entry.visible = false;
					main_button_box.visible = true;
					search_togglebutton.active = false;
					search_togglebutton.visible = true;
					refresh_packages_list ();
					break;
				case "details":
					Package? pkg = display_package_queue.pop_tail ();
					if (pkg != null && pkg.name != current_package_displayed.name) {
						current_package_displayed = pkg;
						refresh_details ();
					} else {
						main_stack.visible_child_name = "browse";
						// in case of starting with --details arg
						if (current_packages_list_length == 0) {
							refresh_packages_list ();
						}
					}
					break;
				case "term":
					main_stack.visible_child_name = "browse";
					break;
				default:
					break;
			}
		}

		async GenericArray<unowned AURPackage> get_pendings_aur_pkgs () {
			var aur_pkgs = new GenericArray<unowned AURPackage> ();
			var to_build_array = new GenericArray<string> (to_build.length);
			foreach (unowned string name in to_build)  {
				to_build_array.add (name);
			}
			var table = yield database.get_aur_pkgs_async (to_build_array.data);
			var iter = HashTableIter<string, unowned AURPackage?> (table);
			unowned AURPackage? aur_pkg;
			while (iter.next (null, out aur_pkg)) {
				if (aur_pkg != null) {
					aur_pkgs.add (aur_pkg);
				}
			}
			return aur_pkgs;
		}

		async GenericArray<unowned Package> search_all_pkgs () {
			var pkgs = new GenericArray<unowned Package> ();
			var aur_pkgs = new GenericArray<unowned AURPackage> ();
			var snaps = new GenericArray<unowned SnapPackage> ();
			var flatpaks = new GenericArray<unowned FlatpakPackage> ();
			database.search_pkgs_async.begin (search_string, (obj, res) => {
				pkgs = database.search_pkgs_async.end (res);
				search_all_pkgs.callback ();
			});
			if (enable_aur) {
				database.search_aur_pkgs_async.begin (search_string, (obj, res) => {
					aur_pkgs = database.search_aur_pkgs_async.end (res);
					search_all_pkgs.callback ();
				});
			}
			if (database.config.enable_snap) {
				database.search_snaps_async.begin (search_string, (obj, res) => {
					snaps = database.search_snaps_async.end (res);
					search_all_pkgs.callback ();
				});
			}
			if (database.config.enable_flatpak) {
				database.search_flatpaks_async.begin (search_string, (obj, res) => {
					flatpaks = database.search_flatpaks_async.end (res);
					search_all_pkgs.callback ();
				});
			}
			yield;
			if (enable_aur) {
				yield;
			}
			if (database.config.enable_snap) {
				yield;
			}
			if (database.config.enable_flatpak) {
				yield;
			}
			foreach (unowned AURPackage pkg in aur_pkgs) {
				if (pkg.installed_version == null) {
					pkgs.add (pkg);
				}
			}
			pkgs.extend (snaps, null);
			pkgs.extend (flatpaks, null);
			return pkgs;
		}

		[GtkCallback]
		void on_remove_all_button_clicked () {
			foreach (unowned Package pkg in current_packages_list) {
				if (!transaction.transaction_summary_contains (pkg.id) && pkg.installed_version != null
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
				if (!transaction.transaction_summary_contains (pkg.id) && pkg.installed_version == null) {
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

		[GtkCallback]
		void on_search_togglebutton_toggled () {
			if (search_togglebutton.active) {
				search_togglebutton.visible = false;
				main_button_box.visible = false;
				button_back.visible = true;
				search_entry.visible = true;
				if (search_string != null) {
					search_entry.set_text (search_string);
					search_entry.set_position (-1);
					on_search_entry_changed ();
				}
				search_entry.grab_focus_without_selecting ();
			}
		}

		bool search_entry_timeout_callback () {
			string tmp_search_string = search_entry.get_text ().strip ();
			if (tmp_search_string != "" && tmp_search_string.char_count () > 1) {
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				search_string = (owned) tmp_search_string;
				refresh_packages_list ();
			}
			search_entry_timeout_id = 0;
			return false;
		}

		[GtkCallback]
		void on_search_entry_changed () {
			if (search_entry_timeout_id != 0) {
				Source.remove (search_entry_timeout_id);
			}
			search_entry_timeout_id = Timeout.add (300, search_entry_timeout_callback);
		}

		[GtkCallback]
		void on_relevance_button_clicked () {
			sortby_button_label.label = dgettext (null, "Relevance");
			// check if we need to sort aur packages
			if (view_button_label.label == dgettext (null, "AUR")) {
				populate_aur_list (current_packages_list);
			} else {
				populate_packages_list (current_packages_list);
			}
		}

		[GtkCallback]
		void on_name_button_clicked () {
			sortby_button_label.label = dgettext (null, "Name");
			populate_packages_list (current_packages_list);
		}

		[GtkCallback]
		void on_repository_button_clicked () {
			sortby_button_label.label = dgettext (null, "Repository");
			populate_packages_list (current_packages_list);
		}

		[GtkCallback]
		void on_size_button_clicked () {
			sortby_button_label.label = dgettext (null, "Size");
			populate_packages_list (current_packages_list);
		}

		[GtkCallback]
		void on_date_button_clicked () {
			sortby_button_label.label = dgettext (null, "Date");
			// check if we need to sort aur packages
			if (view_button_label.label == dgettext (null, "AUR")) {
				populate_aur_list (current_packages_list);
			} else {
				populate_packages_list (current_packages_list);
			}
		}

		[GtkCallback]
		void on_groups_listbox_row_activated (Gtk.ListBoxRow row) {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			unowned Gtk.Label label = row.get_child () as Gtk.Label;
			unowned string group_name = label.label;
			view_button_label.label = group_name;
			groups_popovermenu.closed ();
			current_packages_list_name = "group_%s".printf (group_name);
			database.get_group_pkgs_async.begin (group_name, (obj, res) => {
				var pkgs = database.get_group_pkgs_async.end (res);
				bool found = false;
				foreach (unowned AlpmPackage pkg in pkgs) {
					if (pkg.installed_version == null) {
						found = true;
						break;
					}
				}
				install_all_button.visible = found;
				found = false;
				foreach (unowned AlpmPackage pkg in pkgs) {
					if (pkg.installed_version != null) {
						found = true;
						break;
					}
				}
				remove_all_button.visible = found;
				if (main_browse_togglebutton.active && current_packages_list_name == "group_%s".printf (group_name)) {
					populate_packages_list (pkgs);
				} else {
					this.get_window ().set_cursor (null);
				}
			});
		}

		async GenericArray<unowned Package> get_all_installed () {
			var pkgs = new GenericArray<unowned Package> ();
			var snaps = new GenericArray<unowned SnapPackage> ();
			var flatpaks = new GenericArray<unowned FlatpakPackage> ();
			database.get_installed_pkgs_async.begin ((obj, res) => {
				pkgs = database.get_installed_pkgs_async.end (res);
				get_all_installed.callback ();
			});
			if (database.config.enable_snap) {
				database.get_installed_snaps_async.begin ((obj, res) => {
					snaps = database.get_installed_snaps_async.end (res);
					get_all_installed.callback ();
				});
			}
			if (database.config.enable_flatpak) {
				database.get_installed_flatpaks_async.begin ((obj, res) => {
					flatpaks = database.get_installed_flatpaks_async.end (res);
					get_all_installed.callback ();
				});
			}
			yield;
			if (database.config.enable_snap) {
				yield;
			}
			if (database.config.enable_flatpak) {
				yield;
			}
			pkgs.extend (snaps, null);
			pkgs.extend (flatpaks, null);
			return pkgs;
		}

		[GtkCallback]
		void on_view_all_button_clicked () {
			view_button_label.label = dgettext (null, "All");
			if (search_togglebutton.active) { // search
				current_search_view = view_button_label.label;
				search_entry.grab_focus_without_selecting ();
				if (search_string == null) {
					return;
				}
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				current_packages_list_name = "search_all_%s".printf (search_string);
				search_all_pkgs.begin ((obj, res) => {
					var pkgs = search_all_pkgs.end (res);
					if (search_togglebutton.active && current_packages_list_name == "search_all_%s".printf (search_string)) {
						populate_packages_list (pkgs);
					} else {
						this.get_window ().set_cursor (null);
					}
				});
			} else if (main_installed_togglebutton.active) { // installed
				remove_all_button.visible = false;
				current_installed_view = view_button_label.label;
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				current_packages_list_name = "installed_all";
				get_all_installed.begin ((obj, res) => {
					var pkgs = get_all_installed.end (res);
					if (main_installed_togglebutton.active && current_packages_list_name == "installed_all") {
						populate_packages_list (pkgs);
					} else {
						this.get_window ().set_cursor (null);
					}
				});
			} else if (main_updates_togglebutton.active) { // updates
				current_updates_view = view_button_label.label;
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				ignore_all_button.visible = !local_config.software_mode;
				current_packages_list_name = "all_updates";
				var pkgs = new GenericArray<unowned Package> ();
				foreach (unowned AlpmPackage pkg in repos_updates) {
					pkgs.add (pkg);
				}
				foreach (unowned Package pkg in aur_updates) {
					pkgs.add (pkg);
				}
				foreach (unowned Package pkg in flatpak_updates) {
					pkgs.add (pkg);
				}
				if (main_updates_togglebutton.active && current_packages_list_name == "all_updates") {
					populate_packages_list (pkgs);
				} else {
					this.get_window ().set_cursor (null);
				}
			} else if (main_pending_togglebutton.active) { // pending
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				current_packages_list_name = "all_pending";
				var pkgs = new GenericArray<unowned Package> ();
				foreach (unowned string pkgname in to_install) {
					var pkg = database.get_installed_pkg (pkgname);
					if (pkg == null) {
						pkg = database.get_sync_pkg (pkgname);
					}
					if (pkg != null) {
						pkgs.add (pkg);
					}
				}
				foreach (unowned string pkgname in to_remove) {
					var pkg = database.get_installed_pkg (pkgname);
					if (pkg != null) {
						pkgs.add (pkg);
					} else {
					}
				}
				var snap_iter = HashTableIter<string, SnapPackage?> (snap_to_install);
				unowned SnapPackage? snap_pkg;
				while (snap_iter.next (null, out snap_pkg)) {
					pkgs.add (snap_pkg);
				}
				snap_iter = HashTableIter<string, SnapPackage?> (snap_to_remove);
				while (snap_iter.next (null, out snap_pkg)) {
					pkgs.add (snap_pkg);
				}
				var flatpak_iter = HashTableIter<string, FlatpakPackage?> (flatpak_to_install);
				unowned FlatpakPackage? flatpak_pkg;
				while (flatpak_iter.next (null, out flatpak_pkg)) {
					pkgs.add (flatpak_pkg);
				}
				flatpak_iter = HashTableIter<string, FlatpakPackage?> (flatpak_to_remove);
				while (flatpak_iter.next (null, out flatpak_pkg)) {
					pkgs.add (flatpak_pkg);
				}
				if (to_build.length > 0) {
					get_pendings_aur_pkgs.begin ((obj, res) => {
						var aur_pkgs = get_pendings_aur_pkgs.end (res);
						foreach (unowned AURPackage pkg in aur_pkgs) {
							pkgs.add (pkg);
						}
						if (main_pending_togglebutton.active && current_packages_list_name == "all_pending") {
							populate_packages_list (pkgs);
						} else {
							this.get_window ().set_cursor (null);
						}
					});
				} else {
					if (main_pending_togglebutton.active && current_packages_list_name == "all_pending") {
						populate_packages_list (pkgs);
					} else {
						this.get_window ().set_cursor (null);
					}
				}
			}
		}

		[GtkCallback]
		void on_view_installed_button_clicked () {
			view_button_label.label = dgettext (null, "Installed");
			current_search_view = view_button_label.label;
			search_entry.grab_focus_without_selecting ();
			if (search_string == null) {
				return;
			}
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			current_packages_list_name = "search_installed_%s".printf (search_string);
			database.search_installed_pkgs_async.begin (search_string, (obj, res) => {
				var pkgs = database.search_installed_pkgs_async.end (res);
				if (search_togglebutton.active && current_packages_list_name == "search_installed_%s".printf (search_string)) {
					populate_packages_list (pkgs);
				} else {
					this.get_window ().set_cursor (null);
				}
			});
		}

		[GtkCallback]
		void on_view_explicitly_installed_button_clicked () {
			view_button_label.label = dgettext (null, "Explicitly installed");
			current_packages_list_name = "explicitly_installed";
			database.get_explicitly_installed_pkgs_async.begin ((obj, res) => {
				var pkgs = database.get_explicitly_installed_pkgs_async.end (res);
				if (main_installed_togglebutton.active && current_packages_list_name == "explicitly_installed") {
					populate_packages_list (pkgs);
				} else {
					this.get_window ().set_cursor (null);
				}
			});
			current_installed_view = view_button_label.label;
		}

		[GtkCallback]
		void on_view_orphans_button_clicked () {
			view_button_label.label = dgettext (null, "Orphans");
			current_packages_list_name = "orphans";
			database.get_orphans_async.begin ((obj, res) => {
				var pkgs = database.get_orphans_async.end (res);
				if (main_installed_togglebutton.active && current_packages_list_name == "orphans") {
					populate_packages_list (pkgs);
					remove_all_button.visible = pkgs != null;
				} else {
					this.get_window ().set_cursor (null);
				}
			});
			remove_all_button.visible = true;
			current_installed_view = view_button_label.label;
		}

		[GtkCallback]
		void on_view_foreign_button_clicked () {
			view_button_label.label = dgettext (null, "Foreign");
			current_packages_list_name = "foreign";
			database.get_foreign_pkgs_async.begin ((obj, res) => {
				var pkgs = database.get_foreign_pkgs_async.end (res);
				if (main_installed_togglebutton.active && current_packages_list_name == "foreign") {
					populate_packages_list (pkgs);
				} else {
					this.get_window ().set_cursor (null);
				}
			});
			current_installed_view = view_button_label.label;
		}

		[GtkCallback]
		void on_view_repositories_button_clicked () {
			view_button_label.label = dgettext (null, "Repositories");
			if (search_togglebutton.active) { // search
				current_search_view = view_button_label.label;
				search_entry.grab_focus_without_selecting ();
				if (search_string == null) {
					return;
				}
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				current_packages_list_name = "search_repos_%s".printf (search_string);
				database.search_repos_pkgs_async.begin (search_string, (obj, res) => {
					if (search_togglebutton.active && current_packages_list_name == "search_repos_%s".printf (search_string)) {
						var pkgs = database.search_repos_pkgs_async.end (res);
						populate_packages_list (pkgs);
					} else {
						this.get_window ().set_cursor (null);
					}
				});
			} else if (main_updates_togglebutton.active) { // updates
				current_updates_view = view_button_label.label;
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				ignore_all_button.visible = true;
				current_packages_list_name = "repos_updates";
				var pkgs = new GenericArray<unowned AlpmPackage> ();
				foreach (unowned AlpmPackage pkg in repos_updates) {
					pkgs.add (pkg);
				}
				if (main_updates_togglebutton.active && current_packages_list_name == "repos_updates") {
					populate_packages_list (pkgs);
				} else {
					this.get_window ().set_cursor (null);
				}
			} else if (main_pending_togglebutton.active) { //pending
				if ((to_install.length + to_remove.length) > 0) {
					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
					current_packages_list_name = "repos_pending";
					var pkgs = new GenericArray<unowned AlpmPackage> ();
					foreach (unowned string pkgname in to_install) {
						var pkg = database.get_installed_pkg (pkgname);
						if (pkg == null) {
							pkg = database.get_sync_pkg (pkgname);
						}
						if (pkg != null) {
							pkgs.add (pkg);
						}
					}
					foreach (unowned string pkgname in to_remove) {
						var pkg = database.get_installed_pkg (pkgname);
						if (pkg != null) {
							pkgs.add (pkg);
						}
					}
					if (main_pending_togglebutton.active && current_packages_list_name == "repos_pending") {
						populate_packages_list (pkgs);
					} else {
						this.get_window ().set_cursor (null);
					}
				}
			}
		}

		[GtkCallback]
		void on_view_aur_button_clicked () {
			view_button_label.label = dgettext (null, "AUR");
			if (search_togglebutton.active) { // search
				current_search_view = view_button_label.label;
				search_entry.grab_focus_without_selecting ();
				if (search_string == null) {
					return;
				}
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				current_packages_list_name = "search_aur_%s".printf (search_string);
				database.search_aur_pkgs_async.begin (search_string, (obj, res) => {
					if (search_togglebutton.active && current_packages_list_name == "search_aur_%s".printf (search_string)) {
						var pkgs = database.search_aur_pkgs_async.end (res);
						populate_aur_list (pkgs);
					} else {
						this.get_window ().set_cursor (null);
					}
				});
			} else if (main_updates_togglebutton.active) { // updates
				current_updates_view = view_button_label.label;
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				current_packages_list_name = "aur_updates";
				var pkgs = new GenericArray<unowned AURPackage> ();
				foreach (unowned AURPackage pkg in aur_updates) {
					pkgs.add (pkg);
				}
				if (main_updates_togglebutton.active && current_packages_list_name == "aur_updates") {
					populate_aur_list (pkgs);
				} else {
					this.get_window ().set_cursor (null);
				}
				if (aur_updates.length > 0) {
					ignore_all_button.visible = true;
				}
			} else if (main_pending_togglebutton.active) { // pending
				if (to_build.length > 0) {
					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
					current_packages_list_name = "aur_pending";
					get_pendings_aur_pkgs.begin ((obj, res) => {
						var pkgs = get_pendings_aur_pkgs.end (res);
						if (main_pending_togglebutton.active && current_packages_list_name == "aur_pending") {
							populate_aur_list (pkgs);
						} else {
							this.get_window ().set_cursor (null);
						}
					});
				}
			}
		}

		[GtkCallback]
		void on_view_snap_button_clicked () {
			view_button_label.label = dgettext (null, "Snap");
			if (search_togglebutton.active) { // search
				current_search_view = view_button_label.label;
				search_entry.grab_focus_without_selecting ();
				if (search_string == null) {
					return;
				}
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				current_packages_list_name = "search_snap_%s".printf (search_string);
				database.search_snaps_async.begin (search_string, (obj, res) => {
					if (search_togglebutton.active && current_packages_list_name == "search_snap_%s".printf (search_string)) {
						var pkgs = database.search_snaps_async.end (res);
						populate_packages_list (pkgs);
					} else {
						this.get_window ().set_cursor (null);
					}
				});
			} else if (main_installed_togglebutton.active) { // installed
				current_packages_list_name = "installed_snaps";
				database.get_installed_snaps_async.begin ((obj, res) => {
					var pkgs = database.get_installed_snaps_async.end (res);
					if (main_installed_togglebutton.active && current_packages_list_name == "installed_snaps") {
						populate_packages_list (pkgs);
					} else {
						this.get_window ().set_cursor (null);
					}
				});
				current_installed_view = view_button_label.label;
			} else if (main_pending_togglebutton.active) { // pending
				current_packages_list_name = "snap_pending";
				var pkgs = new GenericArray<unowned Package> ();
				var snap_iter = HashTableIter<string, SnapPackage?> (snap_to_install);
				unowned SnapPackage? pkg;
				while (snap_iter.next (null, out pkg)) {
					pkgs.add (pkg);
				}
				snap_iter = HashTableIter<string, SnapPackage?> (snap_to_remove);
				while (snap_iter.next (null, out pkg)) {
					pkgs.add (pkg);
				}
				if (main_pending_togglebutton.active && current_packages_list_name == "snap_pending") {
					populate_packages_list (pkgs);
				} else {
					this.get_window ().set_cursor (null);
				}
			}
		}

		[GtkCallback]
		void on_view_flatpak_button_clicked () {
			view_button_label.label = dgettext (null, "Flatpak");
			if (search_togglebutton.active) { // search
				current_search_view = view_button_label.label;
				search_entry.grab_focus_without_selecting ();
				if (search_string == null) {
					return;
				}
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				current_packages_list_name = "search_flatpak_%s".printf (search_string);
				database.search_flatpaks_async.begin (search_string, (obj, res) => {
					if (search_togglebutton.active && current_packages_list_name == "search_flatpak_%s".printf (search_string)) {
						var pkgs = database.search_flatpaks_async.end (res);
						populate_packages_list (pkgs);
					} else {
						this.get_window ().set_cursor (null);
					}
				});
			} else if (main_updates_togglebutton.active) { // updates
				current_updates_view = view_button_label.label;
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				current_packages_list_name = "flatpak_updates";
				var pkgs = new GenericArray<unowned FlatpakPackage> ();
				foreach (unowned FlatpakPackage pkg in flatpak_updates) {
					pkgs.add (pkg);
				}
				if (main_updates_togglebutton.active && current_packages_list_name == "flatpak_updates") {
					populate_packages_list (pkgs);
				} else {
					this.get_window ().set_cursor (null);
				}
				if (flatpak_updates.length > 0) {
					ignore_all_button.visible = true;
				}
			} else if (main_installed_togglebutton.active) { // installed
				current_packages_list_name = "installed_flatpaks";
				database.get_installed_flatpaks_async.begin ((obj, res) => {
					var pkgs = database.get_installed_flatpaks_async.end (res);
					if (main_installed_togglebutton.active && current_packages_list_name == "installed_flatpaks") {
						populate_packages_list (pkgs);
					} else {
						this.get_window ().set_cursor (null);
					}
				});
				current_installed_view = view_button_label.label;
			} else if (main_pending_togglebutton.active) { // pending
				current_packages_list_name = "flatpak_pending";
				var pkgs = new GenericArray<unowned Package> ();
				var flatpak_iter = HashTableIter<string, FlatpakPackage?> (flatpak_to_install);
				unowned FlatpakPackage? pkg;
				while (flatpak_iter.next (null, out pkg)) {
					pkgs.add (pkg);
				}
				flatpak_iter = HashTableIter<string, FlatpakPackage?> (flatpak_to_remove);
				while (flatpak_iter.next (null, out pkg)) {
					pkgs.add (pkg);
				}
				if (main_pending_togglebutton.active && current_packages_list_name == "flatpak_pending") {
					populate_packages_list (pkgs);
				} else {
					this.get_window ().set_cursor (null);
				}
			}
		}

		[GtkCallback]
		void on_repos_listbox_row_activated (Gtk.ListBoxRow row) {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			unowned Gtk.Label label = row.get_child () as Gtk.Label;
			unowned string repo = label.label;
			view_button_label.label = repo;
			repos_popovermenu.closed ();
			current_packages_list_name = "repo_%s".printf (repo);
			database.get_repo_pkgs_async.begin (repo, (obj, res) => {
				var pkgs = database.get_repo_pkgs_async.end (res);
				if (main_browse_togglebutton.active && current_packages_list_name == "repo_%s".printf (repo)) {
					populate_packages_list (pkgs);
				} else {
					this.get_window ().set_cursor (null);
				}
			});
		}

		void on_main_stack_visible_child_changed () {
			switch (main_stack.visible_child_name) {
				case "browse":
					properties_stack_switcher.visible = false;
					if (search_togglebutton.active) {
						search_entry.visible = true;
					} else if (main_updates_togglebutton.active
						|| main_pending_togglebutton.active) {
						main_button_box.visible = true;
						button_back.visible = false;
						search_togglebutton.visible = false;
					} else {
						main_button_box.visible = true;
						button_back.visible = false;
						search_togglebutton.visible = true;
					}
					if (transaction.details_textview.buffer.get_char_count () > 0) {
						details_button.sensitive = true;
					}
					break;
				case "details":
					search_entry.visible = false;
					main_button_box.visible = false;
					button_back.visible = true;
					search_togglebutton.visible = false;
					if (transaction.details_textview.buffer.get_char_count () > 0) {
						details_button.sensitive = true;
					}
					break;
				case "term":
					search_entry.visible = false;
					main_button_box.visible = false;
					properties_stack_switcher.visible = false;
					button_back.visible = true;
					search_togglebutton.visible = false;
					details_button.sensitive = false;
					details_button.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
					details_button.relief = Gtk.ReliefStyle.NONE;
					break;
				default:
					break;
			}
		}

		[GtkCallback]
		void on_main_browse_togglebutton_toggled () {
			if (main_browse_togglebutton.active) {
				main_installed_togglebutton.active = false;
				main_pending_togglebutton.active = false;
				main_updates_togglebutton.active = false;
				search_togglebutton.visible = true;
				refresh_packages_list ();
			}
		}

		[GtkCallback]
		void on_main_installed_togglebutton_toggled () {
			if (main_installed_togglebutton.active) {
				main_browse_togglebutton.active = false;
				main_pending_togglebutton.active = false;
				main_updates_togglebutton.active = false;
				search_togglebutton.visible = true;
				refresh_packages_list ();
			}
		}

		[GtkCallback]
		void on_main_pending_togglebutton_toggled () {
			if (main_pending_togglebutton.active) {
				main_browse_togglebutton.active = false;
				main_installed_togglebutton.active = false;
				main_updates_togglebutton.active = false;
				search_togglebutton.visible = false;
				refresh_packages_list ();
			}
		}

		[GtkCallback]
		void on_main_updates_togglebutton_toggled () {
			if (main_updates_togglebutton.active) {
				main_browse_togglebutton.active = false;
				main_installed_togglebutton.active = false;
				main_pending_togglebutton.active = false;
				refresh_packages_list ();
			}
		}

		[GtkCallback]
		void on_menu_button_toggled () {
			preferences_button.sensitive = !(transaction_running || sysupgrade_running);
			refresh_databases_button.sensitive = !(transaction_running || sysupgrade_running);
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
			transaction.get_authorization_async.begin ((obj, res) => {
				bool authorized = transaction.get_authorization_async.end (res);
				if (authorized) {
					var preferences_dialog = new PreferencesDialog (transaction, local_config);
					preferences_dialog.run ();
					database.config.save ();
					preferences_dialog.destroy ();
					transaction.remove_authorization ();
					check_aur_support ();
					check_snap_support ();
					check_flatpak_support ();
					if (main_stack.visible_child_name == "details") {
						refresh_details ();
					}
					refresh_packages_list ();
				} else {
					this.get_window ().set_cursor (null);
				}
			});
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
			browseby_button_label.label = dgettext (null, "Categories");
			view_button.popover = categories_popovermenu;
			view_button_label.label = current_category_view;
			refresh_packages_list ();
		}

		[GtkCallback]
		void on_groups_button_clicked () {
			browseby_button_label.label = dgettext (null, "Groups");
			view_button.popover = groups_popovermenu;
			refresh_packages_list ();
		}

		[GtkCallback]
		void on_repositories_button_clicked () {
			browseby_button_label.label = dgettext (null, "Repositories");
			view_button.popover = repos_popovermenu;
			refresh_packages_list ();
		}

		[GtkCallback]
		void on_details_button_clicked () {
			important_details = false;
			main_stack.visible_child_name = "term";
		}

		async GenericArray<unowned Package> get_category_pkgs (string category) {
			var pkgs = new GenericArray<unowned Package> ();
			var snaps = new GenericArray<unowned SnapPackage> ();
			var flatpaks = new GenericArray<unowned FlatpakPackage> ();
			database.get_category_pkgs_async.begin (category, (obj, res) => {
				pkgs = database.get_category_pkgs_async.end (res);
				get_category_pkgs.callback ();
			});
			if (database.config.enable_snap) {
				database.get_category_snaps_async.begin (category, (obj, res) => {
					snaps = database.get_category_snaps_async.end (res);
					get_category_pkgs.callback ();
				});
			}
			if (database.config.enable_flatpak) {
				database.get_category_flatpaks_async.begin (category, (obj, res) => {
					flatpaks = database.get_category_flatpaks_async.end (res);
					get_category_pkgs.callback ();
				});
			}
			yield;
			if (database.config.enable_snap) {
				yield;
			}
			if (database.config.enable_flatpak) {
				yield;
			}
			pkgs.extend (snaps, null);
			pkgs.extend (flatpaks, null);
			return pkgs;
		}

		void populate_category_pkgs (string category) {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			current_packages_list_name = "category_%s".printf (category);
			get_category_pkgs.begin (category, (obj, res) => {
				var pkgs = get_category_pkgs.end (res);
				if (main_browse_togglebutton.active && current_packages_list_name == "category_%s".printf (category)) {
					populate_packages_list (pkgs);
				} else {
					this.get_window ().set_cursor (null);
				}
			});
			view_button_label.label = dgettext (null, category);
			current_category_view = view_button_label.label;
		}

		[GtkCallback]
		void on_featured_button_clicked () {
			populate_category_pkgs ("Featured");
		}

		[GtkCallback]
		void on_photo_video_button_clicked () {
			populate_category_pkgs ("Photo & Video");
		}

		[GtkCallback]
		void on_music_audio_button_clicked () {
			populate_category_pkgs ("Music & Audio");
		}

		[GtkCallback]
		void on_productivity_button_clicked () {
			populate_category_pkgs ("Productivity");
		}

		[GtkCallback]
		void on_communication_news_button_clicked () {
			populate_category_pkgs ("Communication & News");
		}

		[GtkCallback]
		void on_education_science_button_button_clicked () {
			populate_category_pkgs ("Education & Science");
		}

		[GtkCallback]
		void on_games_button_clicked () {
			populate_category_pkgs ("Games");
		}

		[GtkCallback]
		void on_utilities_button_clicked () {
			populate_category_pkgs ("Utilities");
		}

		[GtkCallback]
		void on_development_button_clicked () {
			populate_category_pkgs ("Development");
		}

		[GtkCallback]
		void on_apply_button_clicked () {
			details_button.sensitive = true;
			if (main_updates_togglebutton.active) {
				transaction.no_confirm_upgrade = true;
				run_sysupgrade (false);
			} else if (main_stack.visible_child_name == "details" &&
				properties_stack.visible_child_name == "build_files") {
				transaction.save_build_files_async.begin (current_package_displayed.name, () => {
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
			foreach (unowned SnapPackage pkg in snap_to_install.get_values ()) {
				transaction.add_snap_to_install (pkg);
				previous_snap_to_install.insert (pkg.name, pkg);
			}
			foreach (unowned SnapPackage pkg in snap_to_remove.get_values ()) {
				transaction.add_snap_to_remove (pkg);
				previous_snap_to_remove.insert (pkg.name, pkg);
			}
			foreach (unowned FlatpakPackage pkg in flatpak_to_install.get_values ()) {
				transaction.add_flatpak_to_install (pkg);
				previous_flatpak_to_install.insert (pkg.name, pkg);
			}
			foreach (unowned FlatpakPackage pkg in flatpak_to_remove.get_values ()) {
				transaction.add_flatpak_to_remove (pkg);
				previous_flatpak_to_remove.insert (pkg.name, pkg);
			}
			clear_lists ();
			active_pending_stack (false);
			transaction.run_async.begin ((obj, res) => {
				bool success = transaction.run_async.end (res);
				on_transaction_finished (success);
			});
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
			foreach (unowned FlatpakPackage pkg in flatpak_updates) {
				if (!temporary_ignorepkgs.contains (pkg.name)) {
					transaction.add_flatpak_to_upgrade (pkg);
				}
			}
			transaction.run_async.begin ((obj, res) => {
				bool success = transaction.run_async.end (res);
				on_transaction_finished (success);
			});
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
				refresh_listbox_buttons ();
				if (main_stack.visible_child_name == "details") {
					if (install_togglebutton.active) {
						install_togglebutton.active = false;
					} else if (remove_togglebutton.active) {
						remove_togglebutton.active = false;
					} else if (build_togglebutton.active) {
						build_togglebutton.active = false;
					} else if (reinstall_togglebutton.active) {
						reinstall_togglebutton.active = false;
					}
				}
			}
		}

		[GtkCallback]
		void on_refresh_databases_button_clicked () {
			transaction.no_confirm_upgrade = false;
			run_sysupgrade (true);
		}

		[GtkCallback]
		void on_refresh_button_clicked () {
			browse_stack.visible_child_name = "checking";
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			bool check_aur_updates_backup = database.config.check_aur_updates;
			database.config.check_aur_updates = check_aur_updates_backup && !local_config.software_mode;
			database.get_updates_async.begin (false, (obj, res) => {
				database.config.check_aur_updates = check_aur_updates_backup;
				var updates = database.get_updates_async.end (res);
				// copy updates in lists
				repos_updates = new GenericArray<AlpmPackage> ();
				foreach (unowned AlpmPackage pkg in updates.repos_updates) {
					repos_updates.add (pkg);
				}
				foreach (unowned AlpmPackage pkg in updates.ignored_repos_updates) {
					repos_updates.add (pkg);
					temporary_ignorepkgs.add (pkg.name);
				}
				aur_updates = new GenericArray<AURPackage> ();
				foreach (unowned AURPackage pkg in updates.aur_updates) {
					aur_updates.add (pkg);
				}
				foreach (unowned AURPackage pkg in updates.ignored_aur_updates) {
					aur_updates.add (pkg);
					temporary_ignorepkgs.add (pkg.name);
				}
				flatpak_updates = new GenericArray<FlatpakPackage> ();
				foreach (unowned FlatpakPackage pkg in updates.flatpak_updates) {
					flatpak_updates.add (pkg);
				}
				updates_checked = true;
				if (main_updates_togglebutton.active) {
					populate_updates ();
				} else {
					this.get_window ().set_cursor (null);
				}
			});
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
				&& flatpak_updates.length == 0) {
				browse_head_box.visible = false;
				browse_separator.visible = false;
				browse_stack.visible_child_name = "updated";
				DateTime? last_refresh_time = database.get_last_refresh_time ();
				if (last_refresh_time == null) {
					last_refresh_label.label = "";
				} else {
					// round at minute
					int64 elasped_time = last_refresh_time.to_unix ();
					int64 elasped_day = elasped_time / TimeSpan.DAY;
					string time_format;
					if (elasped_day < 1) {
						time_format = last_refresh_time.format ("%R");
					} else {
						time_format = last_refresh_time.format ("%x");
					}
					last_refresh_label.set_markup ("<span foreground='grey'>%s</span>".printf ("%s : %s".printf (dgettext (null, "Last refresh"), time_format)));
				}
				this.get_window ().set_cursor (null);
			} else {
				if (repos_updates.length > 0) {
					foreach (unowned AlpmPackage pkg in repos_updates) {
						if (!temporary_ignorepkgs.contains (pkg.name)) {
							to_update.add (pkg.name);
						}
					}
					view_repositories_button.sensitive = true;
				} else {
					view_repositories_button.sensitive = false;
				}
				if (aur_updates.length > 0) {
					foreach (unowned AURPackage pkg in aur_updates) {
						if (!temporary_ignorepkgs.contains (pkg.name)) {
							to_update.add (pkg.name);
						}
					}
					view_aur_button.sensitive = true;
					view_box.visible = true;
				} else {
					view_aur_button.sensitive = false;
				}
				if (flatpak_updates.length > 0) {
					foreach (unowned FlatpakPackage pkg in flatpak_updates) {
						if (!temporary_ignorepkgs.contains (pkg.name)) {
							to_update.add (pkg.name);
						}
					}
					view_flatpak_button.sensitive = true;
					view_box.visible = true;
				} else {
					view_flatpak_button.sensitive = false;
				}
				unowned string filter = view_button_label.label;
				if (filter == dgettext (null, "All")) {
					on_view_all_button_clicked ();
				} else if (filter == dgettext (null, "Repositories")) {
					on_view_repositories_button_clicked ();
				} else if (filter == dgettext (null, "AUR")) {
					on_view_aur_button_clicked ();
				} else if (filter == dgettext (null, "Flatpak")) {
					on_view_flatpak_button_clicked ();
				}
				browse_head_box.visible = true;
				browse_separator.visible = true;
				this.get_window ().set_cursor (null);
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
		}
	}
}
