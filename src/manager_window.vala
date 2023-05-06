/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2023 Guillaume Benoit <guillaume@manjaro.org>
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
			string search_string_prefix = search_string + "-";
			if (pkg_a.name.has_prefix (search_string_prefix)) {
				if (pkg_b.name.has_prefix (search_string_prefix)) {
					return sort_pkgs_by_relevance (pkg_a, pkg_b);
				}
				return -1;
			}
			if (pkg_b.name.has_prefix (search_string_prefix)) {
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
			if (a_app_name_down != null && a_app_name_down.contains (search_string)) {
				if (b_app_name_down != null && b_app_name_down.contains (search_string)) {
					return sort_pkgs_by_relevance (pkg_a, pkg_b);
				}
				return -1;
			}
				if (b_app_name_down != null && b_app_name_down.contains (search_string)) {
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
					int compare = alpm_pkg_a.build_date.compare (alpm_pkg_b.build_date);
					if (compare == 1) {
						return -1;
					}
					if (compare == -1) {
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
		int compare = pkg_a.install_date.compare (pkg_b.install_date);
		if (compare == 1) {
			return -1;
		}
		if (compare == -1) {
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
		int compare = pkg_a.outofdate.compare (pkg_b.outofdate);
		if (compare == 1) {
			return 1;
		}
		if (compare == -1) {
			return -1;
		}
		compare = pkg_a.lastmodified.compare (pkg_b.lastmodified);
		if (compare == 1) {
			return -1;
		}
		if (compare == -1) {
			return 1;
		}
		return sort_pkgs_by_date (pkg_a, pkg_b);
	}

	[GtkTemplate (ui = "/org/manjaro/pamac/manager/manager_window.ui")]
	class ManagerWindow : Adw.ApplicationWindow {
		// icons
		Gtk.IconTheme icon_theme;
		Gtk.IconPaintable package_paintable;

		// manager objects
		[GtkChild]
		unowned Adw.HeaderBar headerbar;
		[GtkChild]
		public unowned Gtk.Stack main_stack;
		[GtkChild]
		public unowned Gtk.Button button_back;
		[GtkChild]
		public unowned Adw.Leaflet packages_leaflet;
		[GtkChild]
		unowned Gtk.FlowBox packages_listbox;
		[GtkChild]
		unowned Gtk.Revealer notification_revealer;
		[GtkChild]
		unowned Gtk.Label notification_label;
		[GtkChild]
		unowned Gtk.Button notification_button;
		[GtkChild]
		public unowned Gtk.Button search_button;
		[GtkChild]
		public unowned Gtk.SearchEntry search_entry;
		[GtkChild]
		unowned Gtk.ToggleButton reveal_sidebar_button;
		[GtkChild]
		unowned Gtk.ToggleButton reveal_details_button;
		[GtkChild]
		unowned Gtk.ScrolledWindow browse_head_box_scrolledwindow;
		[GtkChild]
		unowned Gtk.Label sortby_label;
		[GtkChild]
		public unowned Adw.Flap browse_flap;
		[GtkChild]
		unowned Gtk.ListBox filters_listbox;
		[GtkChild]
		unowned Gtk.ListBox categories_listbox;
		[GtkChild]
		unowned Gtk.ListBox groups_listbox;
		[GtkChild]
		unowned Gtk.ListBox repos_listbox;
		[GtkChild]
		unowned Gtk.ListBox installed_listbox;
		[GtkChild]
		unowned Gtk.ListBox search_listbox;
		[GtkChild]
		unowned Gtk.ListBox updates_listbox;
		[GtkChild]
		public unowned Adw.ViewStack view_stack;
		[GtkChild]
		public unowned Adw.ViewSwitcherTitle view_stack_switcher;
		[GtkChild]
		unowned Gtk.Stack packages_stack;
		[GtkChild]
		unowned Gtk.Stack browse_stack;
		[GtkChild]
		unowned Gtk.Button remove_all_button;
		[GtkChild]
		unowned Gtk.Button install_all_button;
		[GtkChild]
		unowned Gtk.Button ignore_all_button;
		[GtkChild]
		unowned Gtk.DropDown sortby_dropdown;
		[GtkChild]
		unowned Gtk.ScrolledWindow packages_scrolledwindow;
		[GtkChild]
		unowned Gtk.Label updated_label;
		[GtkChild]
		unowned Gtk.Label last_refresh_label;
		[GtkChild]
		unowned Gtk.Label no_item_label;
		[GtkChild]
		unowned Gtk.Label checking_label;
		[GtkChild]
		public unowned Gtk.Box main_details_box;
		[GtkChild]
		unowned Gtk.ScrolledWindow details_scrolledwindow;
		[GtkChild]
		unowned Gtk.Stack properties_stack;
		[GtkChild]
		unowned Gtk.StackSwitcher properties_stack_switcher;
		[GtkChild]
		unowned Gtk.StackPage files_page;
		[GtkChild]
		unowned Gtk.StackPage build_files_page;
		[GtkChild]
		unowned Gtk.Box build_files_box;
		[GtkChild]
		unowned Gtk.Box deps_box;
		[GtkChild]
		unowned Gtk.Grid details_grid;
		[GtkChild]
		unowned Gtk.Label name_label;
		[GtkChild]
		unowned Gtk.Image app_image;
		[GtkChild]
		unowned Gtk.Box screenshots_box;
		[GtkChild]
		unowned Adw.Carousel screenshots_carousel;
		[GtkChild]
		unowned Gtk.Button previous_screenshot_button;
		[GtkChild]
		unowned Gtk.Button next_screenshot_button;
		[GtkChild]
		unowned Gtk.Label desc_label;
		[GtkChild]
		unowned Gtk.Label long_desc_label;
		[GtkChild]
		unowned Gtk.Label link_label;
		[GtkChild]
		unowned Gtk.Button launch_button;
		[GtkChild]
		unowned Gtk.ToggleButton remove_togglebutton;
		[GtkChild]
		unowned Gtk.ToggleButton reinstall_togglebutton;
		[GtkChild]
		unowned Gtk.ToggleButton install_togglebutton;
		[GtkChild]
		unowned Gtk.ToggleButton build_togglebutton;
		[GtkChild]
		unowned Gtk.TextView files_textview;
		[GtkChild]
		unowned Gtk.Box transaction_infobox;
		[GtkChild]
		public unowned  Gtk.Button details_button;
		[GtkChild]
		public unowned Gtk.Button apply_button;
		[GtkChild]
		unowned Gtk.Button cancel_button;
		[GtkChild]
		public unowned Gtk.Revealer infobox_revealer;

		public Queue<Package> display_package_queue;
		Package current_package_displayed;
		string current_launchable;
		string current_files;
		string current_build_files;
		GenericSet<string?> previous_to_install;
		GenericSet<string?> previous_to_remove;
		GenericSet<string?> previous_to_build;

		public TransactionGtk transaction;
		public DatabaseGtk database { get; construct; }
		public bool mobile { get; construct; }
		public LocalConfig local_config;

		public bool important_details;
		public bool transaction_running;
		public bool generate_mirrors_list;
		bool waiting;

		public bool enable_aur { get; private set; }
		bool updates_checked;
		GenericArray<AlpmPackage> repos_updates;
		GenericArray<AURPackage> aur_updates;
		GenericArray<FlatpakPackage> flatpak_updates;
		BackRow categories_backrow;
		SimpleRow filters_pending_row;
		Gtk.ListBoxRow filters_pending_row_separator;
		SimpleRow categories_pending_row;
		SimpleRow installed_snap_row;
		SimpleRow installed_flatpak_row;
		SimpleRow search_aur_row;
		SimpleRow search_snap_row;
		SimpleRow search_flatpak_row;
		SimpleRow updates_repos_row;
		SimpleRow updates_aur_row;
		SimpleRow updates_flatpak_row;
		SimpleRow updates_ignored_row;
		int current_filters_index;
		string previous_view_stack_visible_child_name;
		string current_packages_list_name;
		GenericArray<unowned Package> current_packages_list;
		uint current_packages_list_length;
		uint current_packages_list_index;
		GenericArray<Gtk.Picture> current_screenshots;
		uint current_screenshots_index;

		bool scroll_to_top;
		uint in_app_notification_timeout_id;

		HashTable<string, SnapPackage> previous_snap_to_install;
		HashTable<string, SnapPackage> previous_snap_to_remove;
		HashTable<string, FlatpakPackage> previous_flatpak_to_install;
		HashTable<string, FlatpakPackage> previous_flatpak_to_remove;

		SimpleAction preferences_action;
		SimpleAction refresh_action;
		SimpleAction install_local_action;

		public ManagerWindow (Gtk.Application application, DatabaseGtk database, bool mobile) {
			Object (application: application, database: database, mobile: mobile);

			// load custom styling
			var css_provider = new Gtk.CssProvider ();
			css_provider.load_from_resource("/org/manjaro/pamac/manager/style.css");
			Gtk.StyleContext.add_provider_for_display (Gdk.Display.get_default (), css_provider, 500);

			unowned string? use_csd = Environment.get_variable ("GTK_CSD");
			if (use_csd == "0") {
				headerbar.set_show_end_title_buttons (false);
			}
			local_config = new LocalConfig ("%s/pamac/config".printf (Environment.get_user_config_dir ()));
			this.set_default_size ((int) local_config.width, (int) local_config.height);
			if (local_config.maximized) {
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
			generate_mirrors_list = false;

			// mobile
			if (mobile) {
				view_stack_switcher.view_switcher_enabled = false;
				main_details_box.visible = false;
				browse_head_box_scrolledwindow.hscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
				sortby_label.ellipsize = Pango.EllipsizeMode.END;
				main_details_box.width_request = 0;
				details_scrolledwindow.hscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
			}

			updated_label.set_markup ("<big><b>%s</b></big>".printf (dgettext (null, "Your system is up to date")));
			no_item_label.set_markup ("<big><b>%s</b></big>".printf (dgettext (null, "No package found")));
			checking_label.set_markup ("<big><b>%s</b></big>".printf (dgettext (null, "Checking for Updates")));

			current_screenshots = new GenericArray<Gtk.Picture> ();

			// populate filters
			create_all_listbox ();
			// check software mode
			bool software_mode_enabled = local_config.software_mode;;
			if (software_mode_enabled) {
				categories_backrow.visible = false;
				browse_stack.visible_child_name = "categories";
				details_button.visible = false;
			}
			check_aur_support ();
			check_snap_support ();
			check_flatpak_support ();

			// quit shortcut
			var action =  new SimpleAction ("quit", null);
			action.activate.connect  (() => {this.close ();});
			this.add_action (action);
			string[] accels = {"<Ctrl>Q", "<Ctrl>W"};
			application.set_accels_for_action ("win.quit", accels);
			// search action
			action = new SimpleAction ("search", null);
			action.activate.connect (() => {
				if (main_stack.visible_child_name == "browse"
					&& browse_flap.visible
					&& (view_stack.visible_child_name == "browse"
					|| view_stack.visible_child_name == "search"
					|| view_stack.visible_child_name == "installed")) {
					search_button.visible = false;
					view_stack_switcher.visible = false;
					search_entry.visible = true;
					button_back.visible = true;
					previous_view_stack_visible_child_name = view_stack.visible_child_name;
					view_stack.visible_child_name = "search";
				}
			});
			this.add_action (action);
			application.set_accels_for_action ("win.search", {"<Ctrl>F"});
			// back action
			action = new SimpleAction ("back", null);
			action.activate.connect (() => {
				switch (main_stack.visible_child_name) {
					case "browse":
						if (packages_leaflet.visible_child_name == "details") {
							Package? pkg = display_package_queue.pop_tail ();
							if (pkg != null && pkg.name != current_package_displayed.name) {
								current_package_displayed = pkg;
								refresh_details ();
							} else {
								if (!browse_flap.visible) {
									browse_flap.visible = true;
									main_details_box.visible = false;
									set_adaptative_details (false);
								} else {
									packages_leaflet.visible_child_name = "list";
								}
								if (view_stack.visible_child_name == "search") {
									search_entry.visible = true;
								} else if (view_stack.visible_child_name == "updates") {
									view_stack_switcher.visible = true;
									button_back.visible = false;
									search_button.visible = false;
								} else {
									view_stack_switcher.visible = true;
									button_back.visible = false;
									search_button.visible = true;
								}
								// in case of starting with --details arg
								if (current_packages_list_length == 0) {
									refresh_packages_list ();
								}
							}
						} else {
							button_back.visible = false;
							search_entry.visible = false;
							search_entry.set_text ("");
							search_string = null;
							view_stack.visible_child_name = previous_view_stack_visible_child_name;
							view_stack_switcher.visible = true;
							search_button.visible = true;
							refresh_packages_list ();
						}
						break;
					case "term":
						main_stack.visible_child_name = "browse";
						break;
					default:
						break;
				}
			});
			this.add_action (action);
			application.set_accels_for_action ("win.back", {"<Alt>Left"});
			// software mode action
			var software_mode_action = new SimpleAction.stateful ("software-mode", null, new Variant.boolean (software_mode_enabled));
			software_mode_action.activate.connect (() => {
				Variant state = software_mode_action.get_state ();
				bool old_state = state.get_boolean ();
				bool enabled = !old_state;
				software_mode_action.set_state (new Variant.boolean (enabled));
				local_config.software_mode = enabled;
				if (enabled) {
					enable_aur = false;
					properties_stack.visible_child_name = "details";
					categories_backrow.visible = false;
					browse_stack.visible_child_name = "categories";
					details_button.visible = false;
					installed_listbox.select_row (installed_listbox.get_row_at_index (0));
					updates_listbox.select_row (updates_listbox.get_row_at_index (0));
				} else {
					enable_aur = database.config.enable_aur;
					categories_backrow.visible = true;
					details_button.visible = true;
				}
				refresh_details ();
				refresh_packages_list ();
			});
			this.add_action (software_mode_action);
			// refresh databases action
			refresh_action = new SimpleAction ("refresh-databases", null);
			refresh_action.activate.connect (() => {
				if (!transaction_running && !generate_mirrors_list) {
					infobox_revealer.reveal_child = true;
					run_sysupgrade (true, false);
				}
			});
			// needed to further disabling it
			refresh_action.set_enabled (false);
			this.add_action (refresh_action);
			refresh_action.set_enabled (true);
			// history action
			action = new SimpleAction ("history", null);
			action.activate.connect (() => {
				this.set_cursor (new Gdk.Cursor.from_name ("progress", null));
				var history_dialog = new HistoryDialog (this);
				this.set_cursor (new Gdk.Cursor.from_name ("default", null));
				if (mobile) {
					history_dialog.maximize ();
				}
				history_dialog.show ();
			});
			this.add_action (action);
			// install local action
			install_local_action = new SimpleAction ("install-local", null);
			install_local_action.activate.connect (() => {
				var chooser = new Gtk.FileDialog ();
				chooser.title = dgettext (null, "Install Local Packages");
				var filters_list = new ListStore (typeof (Gtk.FileFilter));
				var package_filter = new Gtk.FileFilter ();
				package_filter.set_filter_name (dgettext (null, "Alpm Package"));
				package_filter.add_mime_type ("application/x-alpm-package");
				filters_list.append (package_filter);
				chooser.filters = filters_list;
				chooser.open_multiple.begin (this, null, (obj, res) => {
					try {
						ListModel packages_files = chooser.open_multiple.end (res);
						uint num_files = packages_files.get_n_items ();
						for (uint i = 0; i < num_files; i++) {
							File file = packages_files.get_item (i) as File;
							to_load.add (file.get_path ());
						}
						run_transaction ();
					} catch (Error e) {
						warning (e.message);
					}
				});
			});
			// needed to further disabling it
			install_local_action.set_enabled (false);
			this.add_action (install_local_action);
			install_local_action.set_enabled (true);
			// preferences action
			preferences_action = new SimpleAction ("preferences", null);
			preferences_action.activate.connect (() => {
				this.set_cursor (new Gdk.Cursor.from_name ("progress", null));
				transaction.get_authorization_async.begin ((obj, res) => {
					bool authorized = transaction.get_authorization_async.end (res);
					if (authorized) {
						var preferences_window = new PreferencesWindow (this);
						preferences_window.close_request.connect (() => {
							database.config.save ();
							preferences_window.destroy ();
							transaction.remove_authorization ();
							updates_checked = false;
							check_aur_support ();
							check_snap_support ();
							check_flatpak_support ();
							refresh_details ();
							refresh_packages_list ();
							return true;
						});
						if (mobile) {
							preferences_window.maximize ();
						}
						preferences_window.show ();
					} else {
						this.set_cursor (new Gdk.Cursor.from_name ("default", null));
					}
				});
			});
			// needed to further disabling it
			preferences_action.set_enabled (false);
			this.add_action (preferences_action);
			preferences_action.set_enabled (true);
			// about action
			action = new SimpleAction ("about", null);
			action.activate.connect (() => {
				var about = new Adw.AboutWindow ();
				about.transient_for = this;
				about.developer_name = "Guillaume Benoit";
				about.application_name = "Pamac";
				about.application_icon = "system-software-install";
				about.comments = dgettext (null, "A Package Manager with Alpm, AUR, Flatpak and Snap support");
				about.copyright = "Copyright © 2023 Guillaume Benoit";
				about.version = VERSION;
				about.license_type = Gtk.License.GPL_3_0;
				about.website = "https://gitlab.manjaro.org/applications/pamac";
				about.show ();
			});
			this.add_action (action);

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

			// icons
			update_icons ();
			icon_theme.changed.connect (() => {
				update_icons ();
				unowned Gtk.Widget? child = packages_listbox.get_first_child ();
				while (child != null) {
					unowned PackageRow pamac_row = child as PackageRow;
					if (pamac_row == null) {
						return;
					}
					Package? pkg = pamac_row.pkg;
					if (pkg == null) {
						return;
					}
					set_row_app_icon (pamac_row, pkg);
					child = child.get_next_sibling ();
				}
			});

			// database
			database.get_updates_progress.connect (on_get_updates_progress);
			updates_checked = false;

			// transaction
			repos_updates = new GenericArray<AlpmPackage> ();
			aur_updates = new GenericArray<AURPackage> ();
			snap_to_install = new HashTable<string, SnapPackage> (str_hash, str_equal);
			snap_to_remove = new HashTable<string, SnapPackage> (str_hash, str_equal);
			previous_snap_to_install = new HashTable<string, SnapPackage> (str_hash, str_equal);
			previous_snap_to_remove = new HashTable<string, SnapPackage> (str_hash, str_equal);
			flatpak_to_install = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			flatpak_to_remove = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			previous_flatpak_to_install = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			previous_flatpak_to_remove = new HashTable<string, FlatpakPackage> (str_hash, str_equal);
			flatpak_updates = new GenericArray<FlatpakPackage> ();
			transaction = new TransactionGtk (database, local_config, this.application, mobile);
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
			transaction_infobox.prepend (transaction.progress_box);
			// integrate build files notebook
			build_files_box.append (transaction.build_files_notebook);

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
			view_stack.notify["visible-child"].connect (on_view_stack_visible_child_changed);
			browse_stack.notify["visible-child"].connect (on_browse_stack_visible_child_changed);
			properties_stack.notify["visible-child"].connect (on_properties_stack_visible_child_changed);
			packages_leaflet.notify["folded"].connect (on_packages_leaflet_folded_changed);
			sortby_dropdown.notify["selected"].connect (on_sortby_dropdown_selected_changed);

			// enable "type to search"
			search_entry.set_key_capture_widget (this);

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

			// refresh flatpak appstream_data
			database.refresh_flatpak_appstream_data_async.begin ();
		}

		void update_icons () {
			icon_theme = Gtk.IconTheme.get_for_display (Gdk.Display.get_default ());
			package_paintable = icon_theme.lookup_icon ("package-x-generic", null, 64, 1, 0, 0);
		}

		[GtkCallback]
		bool on_window_close_request () {
			if (transaction_running || generate_mirrors_list) {
				// do not close window
				return true;
			} else {
				// save window size
				var local_conf = new HashTable<string,Variant> (str_hash, str_equal);
				if (this.maximized) {
					local_conf.insert ("maximized", new Variant.boolean (true));
				} else {
					local_conf.insert ("maximized", new Variant.boolean (false));
					local_conf.insert ("width", new Variant.uint64 (this.get_width ()));
					local_conf.insert ("height", new Variant.uint64 (this.get_height ()));
				}
				local_conf.insert ("software_mode", new Variant.boolean (local_config.software_mode));
				local_config.write (local_conf);
				// close window
				return false;
			}
		}

		void show_sidebar (bool visible) {
			if (visible) {
				if (mobile) {
					browse_flap.fold_policy = Adw.FlapFoldPolicy.AUTO;
					reveal_sidebar_button.visible = true;
				} else {
					browse_flap.fold_policy = Adw.FlapFoldPolicy.NEVER;
				}
			} else {
				browse_flap.fold_policy = Adw.FlapFoldPolicy.ALWAYS;
				reveal_sidebar_button.visible = false;
			}
		}

		void check_aur_support () {
			enable_aur = database.config.enable_aur && !local_config.software_mode;
			if (enable_aur) {
				search_aur_row.visible = true;
				updates_aur_row.visible = database.config.check_aur_updates;
			} else {
				unowned Gtk.ListBoxRow row = search_listbox.get_selected_row ();
				var simple_row = row as SimpleRow;
				if (simple_row != null && simple_row.title == dgettext (null, "AUR")) {
					search_listbox.select_row (search_listbox.get_row_at_index (0));
				}
				row = updates_listbox.get_selected_row ();
				simple_row = row as SimpleRow;
				if (simple_row != null && simple_row.title == dgettext (null, "AUR")) {
					updates_listbox.select_row (updates_listbox.get_row_at_index (0));
				}
				search_aur_row.visible = false;
				updates_aur_row.visible = false;
			}
		}

		void check_snap_support () {
			if (database.config.enable_snap) {
				installed_snap_row.visible = true;
				search_snap_row.visible = true;
			} else {
				unowned Gtk.ListBoxRow row = installed_listbox.get_selected_row ();
				var simple_row = row as SimpleRow;
				if (simple_row != null && simple_row.title == dgettext (null, "Snap")) {
					installed_listbox.select_row (installed_listbox.get_row_at_index (0));
				}
				row = search_listbox.get_selected_row ();
				simple_row = row as SimpleRow;
				if (simple_row != null && simple_row.title == dgettext (null, "Snap")) {
					search_listbox.select_row (search_listbox.get_row_at_index (0));
				}
				installed_snap_row.visible = false;
				search_snap_row.visible = false;
			}
		}

		void check_flatpak_support () {
			if (database.config.enable_flatpak) {
				installed_flatpak_row.visible = true;
				search_flatpak_row.visible = true;
				updates_flatpak_row.visible = database.config.check_flatpak_updates;
			} else {
				unowned Gtk.ListBoxRow row = installed_listbox.get_selected_row ();
				var simple_row = row as SimpleRow;
				if (simple_row != null && simple_row.title == dgettext (null, "Flatpak")) {
					installed_listbox.select_row (installed_listbox.get_row_at_index (0));
				}
				row = search_listbox.get_selected_row ();
				simple_row = row as SimpleRow;
				if (simple_row != null && simple_row.title == dgettext (null, "Flatpak")) {
					search_listbox.select_row (search_listbox.get_row_at_index (0));
				}
				row = updates_listbox.get_selected_row ();
				simple_row = row as SimpleRow;
				if (simple_row != null && simple_row.title == dgettext (null, "Flatpak")) {
					updates_listbox.select_row (updates_listbox.get_row_at_index (0));
				}
				installed_flatpak_row.visible = false;
				search_flatpak_row.visible = false;
				updates_flatpak_row.visible = false;
			}
		}

		void set_pending_operations () {
			if (!transaction_running && !generate_mirrors_list) {
				if (view_stack.visible_child_name == "updates") {
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
					if (to_update.length > 0) {
						apply_button.sensitive = true;
						apply_button.add_css_class ("suggested-action");
					} else {
						apply_button.sensitive = false;
						apply_button.remove_css_class ("suggested-action");
					}
					cancel_button.sensitive = false;
					infobox_revealer.reveal_child = true;
				} else {
					uint total_pending = to_install.length +
										snap_to_install.length +
										snap_to_remove.length +
										flatpak_to_install.length +
										flatpak_to_remove.length +
										to_remove.length +
										to_build.length;
					if (total_pending == 0) {
						transaction.progress_box.action_label.label = "";
						cancel_button.sensitive = false;
						apply_button.sensitive = false;
						apply_button.remove_css_class ("suggested-action");
						if (!important_details) {
							infobox_revealer.reveal_child = false;
						}
						// hide all in case of software_mode changed
						categories_pending_row.visible = false;
						filters_pending_row_separator.visible = false;
						filters_pending_row.visible = false;
					} else {
						string info = dngettext (null, "%u pending operation", "%u pending operations", total_pending).printf (total_pending);
						transaction.progress_box.action_label.label = info;
						cancel_button.sensitive = true;
						apply_button.sensitive = true;
						apply_button.add_css_class ("suggested-action");
						infobox_revealer.reveal_child = true;
						if (local_config.software_mode) {
							categories_pending_row.visible = true;
						} else {
							filters_pending_row_separator.visible = true;
							filters_pending_row.visible = true;
						}
					}
				}
			}
		}

		void create_all_listbox () {
			filters_pending_row_separator = new Gtk.ListBoxRow ();
			var separator = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
			filters_pending_row_separator.set_child (separator);
			filters_pending_row_separator.selectable = false;
			filters_pending_row_separator.activatable = false;
			filters_pending_row_separator.visible = false;
			filters_listbox.append (filters_pending_row_separator);
			filters_pending_row = new SimpleRow (dgettext (null, "Pending"));
			filters_pending_row.visible = false;
			filters_listbox.append (filters_pending_row);

			categories_backrow = new BackRow ();
			categories_listbox.append (categories_backrow);
			foreach (unowned string name in database.get_categories_names ()) {
				categories_listbox.append (new SimpleRow (dgettext (null, name)));
			}
			categories_pending_row = new SimpleRow (dgettext (null, "Pending"));
			categories_pending_row.visible = false;
			categories_listbox.append (categories_pending_row);

			categories_listbox.select_row (categories_listbox.get_row_at_index (1));

			repos_listbox.append (new BackRow ());
			repos_names = database.get_repos_names ();
			foreach (unowned string name in repos_names) {
				repos_listbox.append (new SimpleRow (name));
			}
			repos_listbox.select_row (repos_listbox.get_row_at_index (1));
			// use by sort_pkgs_by_repo
			repos_names.add (dgettext (null, "Snap"));
			foreach (unowned string name in database.get_flatpak_remotes_names ()) {
				repos_names.add (name);
			}
			repos_names.add (dgettext (null, "AUR"));

			groups_listbox.append (new BackRow ());
			foreach (unowned string name in database.get_groups_names ()) {
				groups_listbox.append (new SimpleRow (name));
			}
			groups_listbox.select_row (groups_listbox.get_row_at_index (1));

			var all_installed_row = new SimpleRow (dgettext (null, "All"));
			installed_snap_row = new SimpleRow (dgettext (null, "Snap"));
			installed_flatpak_row = new SimpleRow (dgettext (null, "Flatpak"));
			installed_listbox.append (all_installed_row);
			installed_listbox.append (new SimpleRow (dgettext (null, "Explicitly installed")));
			installed_listbox.append (new SimpleRow (dgettext (null, "Orphans")));
			installed_listbox.append (new SimpleRow (dgettext (null, "Foreign")));
			installed_listbox.append (installed_snap_row);
			installed_listbox.append (installed_flatpak_row);
			installed_listbox.select_row (all_installed_row);

			var all_search_row = new SimpleRow (dgettext (null, "All"));
			search_aur_row = new SimpleRow (dgettext (null, "AUR"));
			search_snap_row = new SimpleRow (dgettext (null, "Snap"));
			search_flatpak_row = new SimpleRow (dgettext (null, "Flatpak"));
			search_listbox.append (all_search_row);
			search_listbox.append (new SimpleRow (dgettext (null, "Installed")));
			search_listbox.append (new SimpleRow (dgettext (null, "Repositories")));
			search_listbox.append (search_aur_row);
			search_listbox.append (search_snap_row);
			search_listbox.append (search_flatpak_row);
			search_listbox.select_row (all_search_row);

			var all_updates_row = new SimpleRow (dgettext (null, "All"));
			updates_repos_row = new SimpleRow (dgettext (null, "Repositories"));
			updates_aur_row = new SimpleRow (dgettext (null, "AUR"));
			updates_flatpak_row = new SimpleRow (dgettext (null, "Flatpak"));
			updates_ignored_row = new SimpleRow (dgettext (null, "Ignored"));
			updates_listbox.append (all_updates_row);
			updates_listbox.append (updates_repos_row);
			updates_listbox.append (updates_aur_row);
			updates_listbox.append (updates_flatpak_row);
			updates_listbox.append (updates_ignored_row);
			updates_listbox.select_row (all_updates_row);
		}

		void clear_packages_listbox () {
			unowned Gtk.Widget? child = packages_listbox.get_first_child ();
			while (child != null) {
				packages_listbox.remove (child);
				child = packages_listbox.get_first_child ();
			}
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
				refresh_packages_list ();
			});
		}

		Gtk.Widget populate_details_grid (string detail_type, string? detail, Gtk.Widget? previous_widget) {
			var label = new Gtk.Label ("<b>%s:</b>".printf (detail_type));
			label.use_markup = true;
			label.halign = Gtk.Align.START;
			label.valign = Gtk.Align.START;
			details_grid.attach_next_to (label, previous_widget, Gtk.PositionType.BOTTOM);
			if (detail == null) {
				var label2 = new Gtk.Label (dgettext (null, "None"));
				label2.use_markup = true;
				label2.halign = Gtk.Align.START;
				details_grid.attach_next_to (label2, label, Gtk.PositionType.RIGHT);
			} else if (!transaction_running
				&& detail_type == dgettext (null, "Install Reason")
				&& detail == dgettext (null, "Installed as a dependency for another package")) {
				var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
				box.homogeneous = false;
				var label2 = new Gtk.Label (detail);
				label2.halign = Gtk.Align.START;
				box.append (label2);
				var mark_explicit_button = new Gtk.Button.with_label (dgettext (null, "Mark as explicitly installed"));
				mark_explicit_button.halign = Gtk.Align.START;
				mark_explicit_button.margin_bottom = 6;
				mark_explicit_button.clicked.connect (on_mark_explicit_button_clicked);
				box.append (mark_explicit_button);
				details_grid.attach_next_to (box, label, Gtk.PositionType.RIGHT);
			} else {
				var label2 = new Gtk.Label (detail);
				label2.use_markup = true;
				label2.halign = Gtk.Align.START;
				details_grid.attach_next_to (label2, label, Gtk.PositionType.RIGHT);
			}
			return label as Gtk.Widget;
		}

		string find_install_button_dep_name (Gtk.Button button, out Gtk.Image select_image) {
			string dep_name = "";
			unowned Gtk.Widget label = button.get_parent ().get_first_child ();
			var dep_label = label as Gtk.Label;
			if (database.has_sync_satisfier (dep_label.label)) {
				AlpmPackage pkg = database.get_sync_satisfier (dep_label.label);
				dep_name = pkg.name;
			}
			unowned Gtk.Widget image = label.get_next_sibling ();
			select_image = image as Gtk.Image;
			return dep_name;
		}

		void on_install_dep_button_toggled (Gtk.ToggleButton button) {
			Gtk.Image select_image;
			string dep_name = find_install_button_dep_name (button, out select_image);
			if (button.active) {
				to_install.add (dep_name);
				select_image.visible = true;
				button.margin_start = 0;
			} else {
				to_install.remove (dep_name);
				select_image.visible = false;
				button.margin_start = 19;
			}
			set_pending_operations ();
		}

		[GtkCallback]
		void on_next_screenshot_button_clicked () {
			unowned Gtk.Picture picture = current_screenshots[current_screenshots_index + 1];
			screenshots_carousel.scroll_to (picture, true);
		}

		[GtkCallback]
		void on_previous_screenshot_button_clicked () {
			unowned Gtk.Picture picture = current_screenshots[current_screenshots_index - 1];
			screenshots_carousel.scroll_to (picture, true);
		}

		[GtkCallback]
		void on_screenshots_carousel_page_changed (uint index) {
			current_screenshots_index = index;
			previous_screenshot_button.visible = current_screenshots_index > 0;
			next_screenshot_button.visible = current_screenshots_index < current_screenshots.length - 1;
		}

		void populate_deps_box (string dep_type, GenericArray<string> dep_list, bool add_install_button = false) {
			var label = new Gtk.Label ("<b>%s:</b>".printf (dep_type));
			label.use_markup = true;
			label.halign = Gtk.Align.START;
			label.margin_top = 12;
			deps_box.append (label);
			var listbox = new Gtk.ListBox ();
			listbox.add_css_class ("boxed-list");
			foreach (unowned string dep in dep_list) {
				if (add_install_button) {
					var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 3);
					var dep_label = new Gtk.Label (dep);
					dep_label.margin_top = 12;
					dep_label.margin_bottom = 12;
					dep_label.margin_start = 12;
					dep_label.margin_end = 12;
					dep_label.halign = Gtk.Align.START;
					dep_label.hexpand = true;
					box.append (dep_label);
					if (!database.has_installed_satisfier (dep)) {
						var select_image = new Gtk.Image.from_icon_name ("object-select-symbolic");
						select_image.pixel_size = 16;
						select_image.visible = false;
						box.append (select_image);
						var install_dep_button = new Gtk.ToggleButton ();
						install_dep_button.icon_name = "document-save-symbolic";
						install_dep_button.margin_start = 19;
						install_dep_button.margin_end = 12;
						install_dep_button.valign = Gtk.Align.CENTER;
						install_dep_button.toggled.connect (on_install_dep_button_toggled);
						box.append (install_dep_button);
						string dep_name = find_install_button_dep_name (install_dep_button, null);
						install_dep_button.active = (dep_name in to_install);
					}
					listbox.append (box);
				} else {
					var dep_label = new Gtk.Label (dep);
					dep_label.margin_top = 12;
					dep_label.margin_bottom = 12;
					dep_label.margin_start = 12;
					dep_label.margin_end = 12;
					dep_label.halign = Gtk.Align.START;
					listbox.append (dep_label);
				}
			}
			listbox.row_activated.connect (on_deps_listbox_row_activated);
			deps_box.append (listbox);
		}

		async void get_screenshots_pictures (GenericArray<string> urls) {
			foreach (unowned string url in urls) {
				Gtk.Picture? picture = null;
				var uri = File.new_for_uri (url);
				var cached_screenshot = File.new_for_path ("/tmp/pamac-app-screenshots/%s".printf (uri.get_basename ()));
				if (cached_screenshot.query_exists ()) {
					picture = new Gtk.Picture.for_file (cached_screenshot);
					picture.can_shrink = true;
					picture.halign = Gtk.Align.CENTER;
					picture.valign = Gtk.Align.CENTER;
				} else {
					// download screenshot
					try {
						var inputstream = yield database.get_url_stream (url);
						var pixbuf = yield new Gdk.Pixbuf.from_stream_at_scale_async (inputstream, -1, 300, true);
						// save scaled image in tmp
						FileOutputStream os = cached_screenshot.append_to (FileCreateFlags.NONE);
						pixbuf.save_to_stream (os, "png");
						picture = new Gtk.Picture.for_pixbuf (pixbuf);
						picture.can_shrink = true;
						picture.halign = Gtk.Align.CENTER;
						picture.valign = Gtk.Align.CENTER;
					} catch (Error e) {
						warning ("%s: %s", url, e.message);
					}
				}
				// add images when they are ready
				if (picture != null) {
					current_screenshots.add (picture);
					screenshots_carousel.append (picture);
					if (current_screenshots.length > 1) {
						next_screenshot_button.visible = true;
					}
				}
			}
			// no image found
			if (current_screenshots.length == 0) {
				screenshots_box.visible = false;
			}
		}

		void clear_details_grid () {
			details_grid.remove_column (1);
			details_grid.remove_column (0);
		}

		void clear_deps_box () {
			unowned Gtk.Widget? child = deps_box.get_first_child ();
			while (child != null) {
				deps_box.remove (child);
				child = deps_box.get_first_child ();
			}
		}

		void clear_screenshots_carousel () {
			uint num_pages = screenshots_carousel.get_n_pages ();
			for (uint i = 0; i < num_pages; i++) {
				screenshots_carousel.remove (screenshots_carousel.get_nth_page (0));
			}
		}

		void set_screenshots (Package pkg) {
			screenshots_box.visible = false;
			previous_screenshot_button.visible = false;
			next_screenshot_button.visible = false;
			current_screenshots_index = 0;
			current_screenshots = new GenericArray<Gtk.Picture> ();
			unowned GenericArray<string> urls = pkg.screenshots;
			if (urls.length != 0) {
				screenshots_box.visible = true;
				get_screenshots_pictures.begin (urls);
			}
		}

		void set_package_details (AlpmPackage pkg, AURPackage? aur_pkg) {
			on_packages_leaflet_folded_changed ();
			// download screenshot
			clear_screenshots_carousel ();
			set_screenshots (pkg);
			bool software_mode = local_config.software_mode;
			// infos
			unowned string? version = pkg.installed_version;
			if (version == null) {
				version = pkg.version;
			}
			unowned string? app_name = pkg.app_name;
			if (app_name == null) {
				name_label.set_markup ("<big><b>%s  %s</b></big>".printf (pkg.name, version));
				app_image.paintable = package_paintable;
			} else {
				if (software_mode) {
					name_label.set_markup ("<big><b>%s  %s</b></big>".printf (Markup.escape_text (app_name), version));
				} else {
					name_label.set_markup ("<big><b>%s (%s)  %s</b></big>".printf (Markup.escape_text (app_name), pkg.name, version));
				}
				unowned string? icon = pkg.icon;
				if (icon != null) {
					var file = File.new_for_path (icon);
					if (file.query_exists ()) {
						app_image.paintable = new Gtk.IconPaintable.for_file (file, 64, 1);
					} else {
						// some icons are not in the right repo
						string new_icon = icon;
						if ("extra" in icon) {
							new_icon = icon.replace ("extra", "community");
						} else if ("community" in icon) {
							new_icon = icon.replace ("community", "extra");
						}
						var new_file = File.new_for_path (new_icon);
						if (file.query_exists ()) {
							app_image.paintable = new Gtk.IconPaintable.for_file (new_file, 64, 1);
						} else {
							app_image.paintable = package_paintable;
						}
					}
				} else {
					app_image.paintable = package_paintable;
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
				string markup_long_desc = Markup.escape_text (long_desc.replace ("em>", "i>").replace ("code>", "tt>"));
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
				if (view_stack.visible_child_name == "updates") {
					remove_togglebutton.visible = true;
					remove_togglebutton.sensitive = true;
					remove_togglebutton.active = to_remove.contains (pkg.name);
				} else if (database.should_hold (pkg.name)) {
					remove_togglebutton.visible = true;
					remove_togglebutton.sensitive = false;
				} else {
					remove_togglebutton.visible = true;
					remove_togglebutton.sensitive = true;
					remove_togglebutton.active = to_remove.contains (pkg.name);
					if (aur_pkg == null) {
						if (pkg.repo != null && pkg.version == pkg.installed_version) {
							reinstall_togglebutton.visible = true;
							reinstall_togglebutton.active = to_install.contains (pkg.name);
						}
					} else {
						// always show build button
						build_togglebutton.visible = true;
						build_togglebutton.active = to_build.contains (pkg.name);
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
			clear_details_grid ();
			Gtk.Widget? previous_widget = null;
			if (pkg.license != null) {
				previous_widget = populate_details_grid (dgettext (null, "Licenses"), pkg.license, previous_widget);
			} else {
				previous_widget = populate_details_grid (dgettext (null, "Licenses"), dgettext (null, "Unknown"), previous_widget);
			}
			if (software_mode) {
				if (pkg.repo == "community" || pkg.repo == "extra" || pkg.repo == "core" || pkg.repo == "multilib") {
					previous_widget = populate_details_grid (dgettext (null, "Repository"), dgettext (null, "Official Repositories"), previous_widget);
				} else {
					previous_widget = populate_details_grid (dgettext (null, "Repository"), pkg.repo, previous_widget);
				}
			} else {
				previous_widget = populate_details_grid (dgettext (null, "Repository"), pkg.repo, previous_widget);
			}
			if (aur_pkg != null) {
				if (aur_pkg.packagebase != pkg.name) {
					previous_widget = populate_details_grid (dgettext (null, "Package Base"), aur_pkg.packagebase, previous_widget);
				}
				previous_widget = populate_details_grid (dgettext (null, "Maintainer"), aur_pkg.maintainer, previous_widget);
				if (aur_pkg.firstsubmitted != null) {
					previous_widget = populate_details_grid (dgettext (null, "First Submitted"), aur_pkg.firstsubmitted.format ("%c"), previous_widget);
				} else {
					previous_widget = populate_details_grid (dgettext (null, "First Submitted"), dgettext (null, "Unknown"), previous_widget);
				}
				if (aur_pkg.lastmodified != null) {
					previous_widget = populate_details_grid (dgettext (null, "Last Modified"), aur_pkg.lastmodified.format ("%c"), previous_widget);
				} else {
					previous_widget = populate_details_grid (dgettext (null, "First Submitted"), dgettext (null, "Unknown"), previous_widget);
				}
				if (aur_pkg.numvotes != 0) {
					previous_widget = populate_details_grid (dgettext (null, "Votes"), aur_pkg.numvotes.to_string (), previous_widget);
				}
				if (aur_pkg.outofdate != null) {
					previous_widget = populate_details_grid (dgettext (null, "Out of Date"), aur_pkg.outofdate.format ("%c"), previous_widget);
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
						box.append (label2);
					}
					details_grid.attach_next_to (box, label, Gtk.PositionType.RIGHT);
					previous_widget = label as Gtk.Widget;
				}
			}
			// make packager mail clickable
			if (pkg.packager != null) {
				string[] splitted = pkg.packager.split ("<", 2);
				unowned string packager_name = splitted[0];
				if (splitted.length > 1) {
					string packager_mail = splitted[1].split (">", 2)[0];
					string packager_detail = "%s\n <a href=\"mailto:%s\">%s</a>".printf (packager_name, packager_mail, packager_mail);
					previous_widget = populate_details_grid (dgettext (null, "Packager"), packager_detail, previous_widget);
				} else {
					previous_widget = populate_details_grid (dgettext (null, "Packager"), pkg.packager, previous_widget);
				}
			} else {
				previous_widget = populate_details_grid (dgettext (null, "Packager"), dgettext (null, "Unknown"), previous_widget);
			}
			if (!software_mode) {
				if (pkg.build_date != null) {
					previous_widget = populate_details_grid (dgettext (null, "Build Date"), pkg.build_date.format ("%c"), previous_widget);
				} else {
					previous_widget = populate_details_grid (dgettext (null, "Build Date"), dgettext (null, "Unknown"), previous_widget);
				}
			}
			if (pkg.installed_version != null) {
				if (pkg.install_date != null) {
					previous_widget = populate_details_grid (dgettext (null, "Install Date"), pkg.install_date.format ("%c"), previous_widget);
				} else {
					previous_widget = populate_details_grid (dgettext (null, "Install Date"), dgettext (null, "Unknown"), previous_widget);
				}
			}
			if (!software_mode) {
				if (pkg.installed_version != null) {
					if (pkg.reason != null) {
						previous_widget = populate_details_grid (dgettext (null, "Install Reason"), pkg.reason, previous_widget);
					} else {
						previous_widget = populate_details_grid (dgettext (null, "Install Reason"), dgettext (null, "Unknown"), previous_widget);
					}
				}
				if (pkg.validations.length != 0) {
					var label = new Gtk.Label ("<b>%s</b>".printf (dgettext (null, "Validated By") + ":"));
					label.use_markup = true;
					label.halign = Gtk.Align.START;
					label.valign = Gtk.Align.START;
					details_grid.attach_next_to (label, previous_widget, Gtk.PositionType.BOTTOM);
					var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
					foreach (unowned string name in pkg.validations) {
						var label2 = new Gtk.Label (name);
						label2.halign = Gtk.Align.START;
						box.append (label2);
					}
					details_grid.attach_next_to (box, label, Gtk.PositionType.RIGHT);
					previous_widget = label as Gtk.Widget;
				} else {
					previous_widget = populate_details_grid (dgettext (null, "Validated By"), dgettext (null, "Unknown"), previous_widget);
				}
				if (pkg.backups.length != 0) {
					var label = new Gtk.Label ("<b>%s</b>".printf (dgettext (null, "Backup files") + ":"));
					label.use_markup = true;
					label.halign = Gtk.Align.START;
					label.valign = Gtk.Align.START;
					details_grid.attach_next_to (label, previous_widget, Gtk.PositionType.BOTTOM);
					var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
					foreach (unowned string name in pkg.backups) {
						var label2 = new Gtk.Label (name);
						label2.halign = Gtk.Align.START;
						box.append (label2);
					}
					details_grid.attach_next_to (box, label, Gtk.PositionType.RIGHT);
				}
			}
			// deps
			clear_deps_box ();
			if (pkg.depends.length != 0) {
				populate_deps_box (dgettext (null, "Depends On"), pkg.depends);
			}
			if (pkg.optdepends.length != 0) {
				populate_deps_box (dgettext (null, "Optional Dependencies"), pkg.optdepends, true);
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
			// files will be populated on properties_stack switch
			if (properties_stack.visible_child_name == "files") {
				properties_stack.visible_child_name = "details";
			}
			// build_files will be populated on properties_stack switch
			if (properties_stack.visible_child_name == "build_files") {
				properties_stack.visible_child_name = "details";
			}
		}

		void set_aur_details (AURPackage aur_pkg) {
			clear_details_grid ();
			clear_deps_box ();
			on_packages_leaflet_folded_changed ();
			clear_screenshots_carousel ();
			screenshots_box.visible = false;
			previous_screenshot_button.visible = false;
			next_screenshot_button.visible = false;
			launch_button.visible = false;
			reinstall_togglebutton.visible = false;
			install_togglebutton.visible = false;
			// first infos
			name_label.set_markup ("<big><b>%s  %s</b></big>".printf (aur_pkg.name, aur_pkg.version));
			app_image.paintable = package_paintable;
			desc_label.set_text (aur_pkg.desc);
			long_desc_label.visible = false;
			if (view_stack.visible_child_name == "updates") {
				build_togglebutton.visible = false;
				remove_togglebutton.visible = false;
			} else {
				// always show build button
				build_togglebutton.visible = true;
				build_togglebutton.active = to_build.contains (aur_pkg.name);
				if (aur_pkg.installed_version != null) {
					remove_togglebutton.visible = true;
					remove_togglebutton.sensitive = true;
					remove_togglebutton.active = to_remove.contains (aur_pkg.name);
				} else {
					remove_togglebutton.visible = false;
				}
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
			previous_widget = populate_details_grid (dgettext (null, "Repository"), aur_pkg.repo, previous_widget);
			if (aur_pkg.packagebase != aur_pkg.name) {
				previous_widget = populate_details_grid (dgettext (null, "Package Base"), aur_pkg.packagebase, previous_widget);
			}
			previous_widget = populate_details_grid (dgettext (null, "Maintainer"), aur_pkg.maintainer, previous_widget);
			if (aur_pkg.firstsubmitted != null) {
				previous_widget = populate_details_grid (dgettext (null, "First Submitted"), aur_pkg.firstsubmitted.format ("%c"), previous_widget);
			} else {
				previous_widget = populate_details_grid (dgettext (null, "First Submitted"), dgettext (null, "Unknown"), previous_widget);
			}
			if (aur_pkg.lastmodified != null) {
				previous_widget = populate_details_grid (dgettext (null, "Last Modified"), aur_pkg.lastmodified.format ("%c"), previous_widget);
			} else {
				previous_widget = populate_details_grid (dgettext (null, "Last Modified"), dgettext (null, "Unknown"), previous_widget);
			}
			previous_widget = populate_details_grid (dgettext (null, "Votes"), aur_pkg.numvotes.to_string (), previous_widget);
			if (aur_pkg.outofdate != null) {
				previous_widget = populate_details_grid (dgettext (null, "Out of Date"), aur_pkg.outofdate.format ("%c"), previous_widget);
			}
			if (aur_pkg.installed_version != null) {
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
				} else {
					previous_widget = populate_details_grid (dgettext (null, "Packager"), dgettext (null, "Unknown"), previous_widget);
				}
				if (aur_pkg.build_date != null) {
					previous_widget = populate_details_grid (dgettext (null, "Build Date"), aur_pkg.build_date.format ("%c"), previous_widget);
				} else {
					previous_widget = populate_details_grid (dgettext (null, "Build Date"), dgettext (null, "Unknown"), previous_widget);
				}
				if (aur_pkg.install_date != null) {
					previous_widget = populate_details_grid (dgettext (null, "Install Date"), aur_pkg.install_date.format ("%c"), previous_widget);
				} else {
					previous_widget = populate_details_grid (dgettext (null, "Install Date"), dgettext (null, "Unknown"), previous_widget);
				}
				if (aur_pkg.reason != null) {
					previous_widget = populate_details_grid (dgettext (null, "Install Reason"), aur_pkg.reason, previous_widget);
				} else {
					previous_widget = populate_details_grid (dgettext (null, "Install Reason"), dgettext (null, "Unknown"), previous_widget);
				}
				if (aur_pkg.validations.length != 0) {
					var label = new Gtk.Label ("<b>%s</b>".printf (dgettext (null, "Validated By") + ":"));
					label.use_markup = true;
					label.halign = Gtk.Align.START;
					label.valign = Gtk.Align.START;
					details_grid.attach_next_to (label, previous_widget, Gtk.PositionType.BOTTOM);
					var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
					foreach (unowned string name in aur_pkg.validations) {
						var label2 = new Gtk.Label (name);
						label2.halign = Gtk.Align.START;
						box.append (label2);
					}
					details_grid.attach_next_to (box, label, Gtk.PositionType.RIGHT);
					previous_widget = label as Gtk.Widget;
				} else {
					previous_widget = populate_details_grid (dgettext (null, "Validated By"), dgettext (null, "Unknown"), previous_widget);
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
						box.append (label2);
					}
					details_grid.attach_next_to (box, label, Gtk.PositionType.RIGHT);
				}
			}
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
			// build files will be populated on properties_stack switch
			if (properties_stack.visible_child_name == "build_files") {
				properties_stack.visible_child_name = "details";
			}
		}

		void set_snap_details (SnapPackage snap_pkg) {
			on_packages_leaflet_folded_changed ();
			// download screenshot
			clear_screenshots_carousel ();
			set_screenshots (snap_pkg);
			// infos
			name_label.set_markup ("<big><b>%s  %s</b></big>".printf (Markup.escape_text (snap_pkg.app_name), snap_pkg.version));
			unowned string? icon = snap_pkg.icon;
			if (icon != null) {
				if (icon.has_prefix ("http")) {
					app_image.paintable = package_paintable;
					transaction.get_icon_file.begin (icon, (obj, res) => {
						var file = transaction.get_icon_file.end (res);
						if (file.query_exists ()) {
							app_image.paintable = new Gtk.IconPaintable.for_file (file, 64, 1);
						}
					});
				} else {
					var file = File.new_for_path (icon);
					if (file.query_exists ()) {
						app_image.paintable = new Gtk.IconPaintable.for_file (file, 64, 1);
					} else {
						app_image.paintable = package_paintable;
						// try to retrieve icon
						database.get_installed_snap_icon_async.begin (snap_pkg.name, (obj, res) => {
							string downloaded_image_path = database.get_installed_snap_icon_async.end (res);
							var new_file = File.new_for_path (downloaded_image_path);
							if (new_file.query_exists ()) {
								app_image.paintable = new Gtk.IconPaintable.for_file (new_file, 64, 1);
							}
						});
					}
				}
			} else {
				app_image.paintable = package_paintable;
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
			clear_details_grid ();
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
			if (snap_pkg.install_date != null) {
				previous_widget = populate_details_grid (dgettext (null, "Install Date"), snap_pkg.install_date.format ("%c"), previous_widget);
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
							box2.append (label2);
							var install_button = new Gtk.Button.with_label (dgettext (null, "Install"));
							install_button.margin_top = 3;
							install_button.margin_bottom = 3;
							install_button.margin_start = 3;
							install_button.margin_end = 3;
							if (transaction_running || generate_mirrors_list) {
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
							box2.append (install_button);
							box.append (box2);
						} else {
							var label2 = new Gtk.Label (channel);
							label2.halign = Gtk.Align.START;
							box.append (label2);
						}
					}
					details_grid.attach_next_to (box, label, Gtk.PositionType.RIGHT);
				}
			}
			// deps
			clear_deps_box ();
		}

		void set_flatpak_details (FlatpakPackage flatpak_pkg) {
			on_packages_leaflet_folded_changed ();
			// download screenshot
			clear_screenshots_carousel ();
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
				var file = File.new_for_path (icon);
				if (file.query_exists ()) {
					app_image.paintable = new Gtk.IconPaintable.for_file (file, 64, 1);
				} else {
					app_image.paintable = package_paintable;
				}
			} else {
				app_image.paintable = package_paintable;
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
				remove_togglebutton.active = flatpak_to_remove.contains (flatpak_pkg.id);
			} else {
				launch_button.visible = false;
				remove_togglebutton.visible = false;
				reinstall_togglebutton.visible = false;
				build_togglebutton.visible = false;
				install_togglebutton.visible = true;
				install_togglebutton.active = flatpak_to_install.contains (flatpak_pkg.id);
			}
			// details
			clear_details_grid ();
			Gtk.Widget? previous_widget = null;
			if (flatpak_pkg.license != null) {
				previous_widget = populate_details_grid (dgettext (null, "Licenses"), flatpak_pkg.license, previous_widget);
			} else {
				previous_widget = populate_details_grid (dgettext (null, "Licenses"), dgettext (null, "Unknown"), previous_widget);
			}
			previous_widget = populate_details_grid (dgettext (null, "Repository"), flatpak_pkg.repo, previous_widget);
			// deps
			clear_deps_box ();
		}

		void on_properties_stack_visible_child_changed () {
			switch (properties_stack.visible_child_name) {
				case "files":
					if (current_files != current_package_displayed.name) {
						this.set_cursor (new Gdk.Cursor.from_name ("progress", null));
						var alpm_pkg = current_package_displayed as AlpmPackage;
						alpm_pkg.get_files_async.begin ((obj, res) => {
							var files = alpm_pkg.get_files_async.end (res);
							StringBuilder text = new StringBuilder ();
							foreach (unowned string file in files) {
								if (text.len > 0) {
									text.append ("\n");
								}
								text.append (file);
							}
							files_textview.buffer.set_text (text.str, (int) text.len);
							this.set_cursor (new Gdk.Cursor.from_name ("default", null));
							current_files = current_package_displayed.name;
						});
						files_textview.buffer.set_text ("", 0);
						packages_scrolledwindow.vadjustment.value = 0;
					}
					break;
				case "build_files":
					if (current_build_files != current_package_displayed.name) {
						this.set_cursor (new Gdk.Cursor.from_name ("progress", null));
						database.get_aur_pkg_async.begin (current_package_displayed.name, (obj, res) => {
							AURPackage pkg = database.get_aur_pkg_async.end (res);
							if (pkg != null) {
								transaction.populate_build_files_async.begin (pkg.packagebase, true, false, () => {
									this.set_cursor (new Gdk.Cursor.from_name ("default", null));
								});
							} else {
								this.set_cursor (new Gdk.Cursor.from_name ("default", null));
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
				if (current_package_displayed is SnapPackage) {
					snap_to_install.insert (current_package_displayed.name, current_package_displayed as SnapPackage);
				} else if (current_package_displayed is FlatpakPackage) {
					flatpak_to_install.insert (current_package_displayed.id, current_package_displayed as FlatpakPackage);
				} else {
					to_install.add (current_package_displayed.name);
				}
			} else {
				if (current_package_displayed is SnapPackage) {
					snap_to_install.remove (current_package_displayed.name);
				} else if (current_package_displayed is FlatpakPackage) {
					flatpak_to_install.remove (current_package_displayed.id);
				} else {
					to_install.remove (current_package_displayed.name);
				}
			}
			set_pending_operations ();
			refresh_listbox_buttons ();
		}

		[GtkCallback]
		void on_build_togglebutton_toggled () {
			if (build_togglebutton.active) {
				to_build.add (current_package_displayed.name);
				if (properties_stack.visible_child_name == "build_files") {
					transaction.save_build_files_async.begin (current_package_displayed.name);
				}
			} else {
				to_build.remove (current_package_displayed.name);
			}
			set_pending_operations ();
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
				if (current_package_displayed is SnapPackage) {
					snap_to_install.remove (current_package_displayed.name);
					snap_to_remove.insert (current_package_displayed.name, current_package_displayed as SnapPackage);
				} else if (current_package_displayed is FlatpakPackage) {
					flatpak_to_install.remove (current_package_displayed.id);
					if (current_package_displayed.name in to_update) {
						to_update.remove (current_package_displayed.name);
						temporary_ignorepkgs.add (current_package_displayed.name);
					}
					flatpak_to_remove.insert (current_package_displayed.id, current_package_displayed as FlatpakPackage);
				} else {
					to_install.remove (current_package_displayed.name);
					if (current_package_displayed.name in to_update) {
						to_update.remove (current_package_displayed.name);
						temporary_ignorepkgs.add (current_package_displayed.name);
					}
					to_remove.add (current_package_displayed.name);
				}
			} else {
				if (current_package_displayed is SnapPackage) {
					snap_to_remove.remove (current_package_displayed.name);
				} else if (current_package_displayed is FlatpakPackage) {
					if (current_package_displayed.name in temporary_ignorepkgs) {
						to_update.add (current_package_displayed.name);
						temporary_ignorepkgs.remove (current_package_displayed.name);
					}
					flatpak_to_remove.remove (current_package_displayed.id);
				} else {
					if (current_package_displayed.name in temporary_ignorepkgs) {
						to_update.add (current_package_displayed.name);
						temporary_ignorepkgs.remove (current_package_displayed.name);
					}
					to_remove.remove (current_package_displayed.name);
				}
			}
			set_pending_operations ();
			refresh_listbox_buttons ();
		}

		[GtkCallback]
		void on_reinstall_togglebutton_toggled () {
			if (reinstall_togglebutton.active) {
				remove_togglebutton.active = false;
				to_remove.remove (current_package_displayed.name);
				if (current_package_displayed is AURPackage) {
					// availability in AUR was checked in set_package_details
					to_build.add (current_package_displayed.name);
				} else {
					to_install.add (current_package_displayed.name);
				}
			} else {
				to_install.remove (current_package_displayed.name);
				to_build.remove (current_package_displayed.name);
			}
			set_pending_operations ();
			refresh_listbox_buttons ();
		}

		void populate_listbox () {
			// populate listbox
			if (current_packages_list_length == 0) {
				packages_stack.visible_child_name = "no_item";
				this.set_cursor (new Gdk.Cursor.from_name ("default", null));
				return;
			} else {
				clear_packages_listbox ();
				packages_stack.visible_child_name = "packages";
			}
			// create os updates row
			if (view_stack.visible_child_name == "updates") {
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
			do {
				complete_packages_list ();
			} while (need_more_packages ());
			if (current_package_displayed == null) {
				// display first pkg detail
				display_details (current_packages_list[0]);
			}
			// scroll to top
			if (scroll_to_top) {
				packages_scrolledwindow.vadjustment.value = 0;
			} else {
				// don't scroll to top just once
				scroll_to_top = true;
			}
			this.set_cursor (new Gdk.Cursor.from_name ("default", null));
		}

		void sort_aur_list (ref GenericArray<unowned Package> pkgs) {
			uint index = sortby_dropdown.selected;
			switch (index) {
				case 0: // relevance
					pkgs.sort (sort_aur_by_relevance);
					break;
				case 1: // name
					pkgs.sort (sort_pkgs_by_name);
					break;
				case 2: // repository
					pkgs.sort (sort_pkgs_by_repo);
					break;
				case 3: // size
					pkgs.sort (sort_pkgs_by_installed_size);
					break;
				case 4: // date
					pkgs.sort (sort_aur_by_date);
					break;
				default:
					break;
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
			uint index = sortby_dropdown.selected;
			switch (index) {
				case 0: // relevance
					if (view_stack.visible_child_name == "search") {
						pkgs.sort (sort_search_pkgs_by_relevance);
					} else {
						pkgs.sort (sort_pkgs_by_relevance);
					}
					break;
				case 1: // name
					pkgs.sort (sort_pkgs_by_name);
					break;
				case 2: // repository
					pkgs.sort (sort_pkgs_by_repo);
					break;
				case 3: // size
					if (view_stack.visible_child_name == "updates") {
						pkgs.sort (sort_pkgs_by_download_size);
					} else {
						pkgs.sort (sort_pkgs_by_installed_size);
					}
					break;
				case 4: // date
					pkgs.sort (sort_pkgs_by_date);
					break;
				default:
					break;
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
				Gtk.Requisition natural_size;
				packages_listbox.get_preferred_size (null, out natural_size);
				if (packages_scrolledwindow.vadjustment.page_size > natural_size.height) {
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
						packages_listbox.append (row);
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

		void set_row_app_icon (PackageRow row, Package pkg) {
			Gtk.IconPaintable paintable = package_paintable;
			unowned string? icon = pkg.icon;
			if (icon != null) {
				if (icon.has_prefix ("http")) {
					transaction.get_icon_file.begin (icon, (obj, res) => {
						var file = transaction.get_icon_file.end (res);
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

		PackageRow create_packagelist_row (Package pkg) {
			bool is_update = view_stack.visible_child_name == "updates";
			var row = new PackageRow (pkg, mobile);
			// populate infos
			unowned string? app_name = pkg.app_name;
			AlpmPackage? alpm_pkg = pkg as AlpmPackage;
			bool software_mode = local_config.software_mode;
			if (app_name == null) {
				row.name_label.label = pkg.name;
			} else if (alpm_pkg != null && !software_mode) {
				row.name_label.label = "%s (%s)".printf (app_name, pkg.name);
			} else {
				row.name_label.label = app_name;
			}
			unowned string? desc = pkg.desc;
			if (desc != null) {
				row.desc_label.label = Markup.escape_text (desc);
			}
			if (is_update) {
				if (software_mode) {
					row.version_label.visible = false;
				} else if (pkg is FlatpakPackage) {
					unowned string? version = pkg.version;
					if (version != null) {
						row.version_label.label = version;
					} else {
						row.version_label.visible = false;
					}
				} else {
					row.version_label.label = pkg.version;
					row.old_version_label.label = pkg.installed_version;
					row.old_version_label.visible = true;
				}
				if (pkg.download_size > 0) {
					row.size_label.label = GLib.format_size (pkg.download_size);
				}
			} else {
				if (software_mode || pkg.version == null) {
					row.version_label.visible = false;
				} else {
					unowned string? installed_version = pkg.installed_version;
					if (installed_version == null) {
						row.version_label.label = pkg.version;
					} else {
						row.version_label.label = pkg.installed_version;
					}
				}
				if (pkg.installed_size > 0) {
					row.size_label.label = GLib.format_size (pkg.installed_size);
				}
			}
			if (pkg.repo != null) {
				if (alpm_pkg != null) {
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
			set_row_app_icon (row, pkg);
			if (transaction.transaction_summary_contains (pkg.id)) {
				row.action_togglebutton.sensitive = false;
			}
			if (is_update) {
				row.action_icon.icon_name = "software-update-symbolic";
				row.action_togglebutton.add_css_class ("suggested-action");
				if (!(pkg.id in temporary_ignorepkgs)) {
					row.action_togglebutton.active = true;
					row.action_icon.icon_name = "software-select-symbolic";
				}
				row.action_togglebutton.toggled.connect ((button) => {
					if (button.active) {
						to_update.add (pkg.id);
						temporary_ignorepkgs.remove (pkg.id);
						// remove from config.ignorepkgs to override config
						database.config.ignorepkgs.remove (pkg.id);
					} else {
						to_update.remove (pkg.id);
						temporary_ignorepkgs.add (pkg.id);
					}
					updates_ignored_row.visible = temporary_ignorepkgs.length > 0;
					refresh_listbox_buttons ();
					set_pending_operations ();
				});
			} else if (pkg.installed_version == null) {
				if (pkg is AURPackage) {
					row.action_icon.icon_name = "software-install-symbolic";
					row.action_togglebutton.add_css_class ("suggested-action");
					if (pkg.name in to_build) {
						row.action_togglebutton.active = true;
						row.action_icon.icon_name = "software-select-symbolic";
					}
					row.action_togglebutton.toggled.connect ((button) => {
						if (button.active) {
							to_build.add (pkg.name);
						} else {
							to_build.remove (pkg.name);
						}
						refresh_listbox_buttons ();
						set_pending_operations ();
					});
				} else if (pkg is SnapPackage) {
					row.action_icon.icon_name = "software-install-symbolic";
					row.action_togglebutton.add_css_class ("suggested-action");
					if (pkg.name in snap_to_install) {
						row.action_togglebutton.active = true;
						row.action_icon.icon_name = "software-select-symbolic";
					}
					row.action_togglebutton.toggled.connect ((button) => {
						if (button.active) {
							snap_to_install.insert (pkg.name, pkg as SnapPackage);
						} else {
							snap_to_install.remove (pkg.name);
						}
						refresh_listbox_buttons ();
						set_pending_operations ();
					});
				} else if (pkg is FlatpakPackage) {
					row.action_icon.icon_name = "software-install-symbolic";
					row.action_togglebutton.add_css_class ("suggested-action");
					if (pkg.id in flatpak_to_install) {
						row.action_togglebutton.active = true;
						row.action_icon.icon_name = "software-select-symbolic";
					}
					row.action_togglebutton.toggled.connect ((button) => {
						if (button.active) {
							flatpak_to_install.insert (pkg.id, pkg as FlatpakPackage);
						} else {
							flatpak_to_install.remove (pkg.id);
						}
						refresh_listbox_buttons ();
						set_pending_operations ();
					});
				} else {
					row.action_icon.icon_name = "software-install-symbolic";
					row.action_togglebutton.add_css_class ("suggested-action");
					if (pkg.name in to_install) {
						row.action_togglebutton.active = true;
						row.action_icon.icon_name = "software-select-symbolic";
					}
					row.action_togglebutton.toggled.connect ((button) => {
						if (button.active) {
							to_install.add (pkg.name);
						} else {
							to_install.remove (pkg.name);
						}
						refresh_listbox_buttons ();
						set_pending_operations ();
					});
				}
			} else if (pkg is SnapPackage) {
				row.action_icon.icon_name = "software-remove-symbolic";
				row.action_togglebutton.add_css_class ("suggested-action");
				if (pkg.name in snap_to_remove) {
					row.action_togglebutton.active = true;
					row.action_icon.icon_name = "software-select-symbolic";
				}
				row.action_togglebutton.toggled.connect ((button) => {
					if (button.active) {
						snap_to_remove.insert (pkg.name, pkg as SnapPackage);
					} else {
						snap_to_remove.remove (pkg.name);
					}
					refresh_listbox_buttons ();
					set_pending_operations ();
				});
			} else if (pkg is FlatpakPackage) {
				row.action_icon.icon_name = "software-remove-symbolic";
				row.action_togglebutton.add_css_class ("destructive-action");
				if (pkg.id in flatpak_to_remove) {
					row.action_togglebutton.active = true;
					row.action_icon.icon_name = "software-select-symbolic";
				}
				row.action_togglebutton.toggled.connect ((button) => {
					if (button.active) {
						flatpak_to_remove.insert (pkg.id, pkg as FlatpakPackage);
					} else {
						flatpak_to_remove.remove (pkg.id);
					}
					refresh_listbox_buttons ();
					set_pending_operations ();
				});
			} else {
				row.action_icon.icon_name = "software-remove-symbolic";
				row.action_togglebutton.add_css_class ("destructive-action");
				if (database.should_hold (pkg.name)) {
					row.action_togglebutton.sensitive = false;
				} else if (pkg.name in to_remove) {
					row.action_togglebutton.active = true;
					row.action_icon.icon_name = "software-select-symbolic";
				}
				row.action_togglebutton.toggled.connect ((button) => {
					if (button.active) {
						to_install.remove (pkg.name);
						if (pkg.name in to_update) {
							to_update.remove (pkg.name);
							temporary_ignorepkgs.add (pkg.name);
						}
						to_remove.add (pkg.name);
					} else {
						if (pkg.name in temporary_ignorepkgs) {
							to_update.add (pkg.name);
							temporary_ignorepkgs.remove (pkg.name);
						}
						to_remove.remove (pkg.name);
					}
					refresh_listbox_buttons ();
					set_pending_operations ();
				});
			}
			return row;
		}

		void create_os_updates_row (uint64 download_size) {
			var row = new PackageRow (null, mobile);
			// populate info
			row.name_label.label = dgettext (null, "OS Updates");
			row.desc_label.label = dgettext (null, "Includes performance, stability and security improvements");
			row.version_label.visible = false;
			if (download_size > 0) {
				row.size_label.label = GLib.format_size (download_size);
			}
			row.repo_label.label = dgettext (null, "Official Repositories");
			row.app_icon.paintable = package_paintable;
			row.action_togglebutton.active = true;
			row.action_icon.icon_name = "software-select-symbolic";
			row.action_togglebutton.sensitive = false;
			// insert
			packages_listbox.append (row);
		}

		PackageRow create_update_row (Package pkg) {
			var row = new PackageRow (pkg, mobile);
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
			set_row_app_icon (row, pkg);
			if (transaction.transaction_summary_contains (pkg.id)) {
				row.action_togglebutton.sensitive = false;
			}
			if (!(pkg.name in temporary_ignorepkgs)) {
				row.action_togglebutton.active = true;
				row.action_icon.icon_name = "software-select-symbolic";
			} else {
				row.action_icon.icon_name = "software-update-symbolic";
			}
			row.action_togglebutton.toggled.connect ((button) => {
				if (button.active) {
					row.action_togglebutton.active = true;
					row.action_icon.icon_name = "software-select-symbolic";
					to_update.add (pkg.name);
					temporary_ignorepkgs.remove (pkg.name);
					// remove from config.ignorepkgs to override config
					database.config.ignorepkgs.remove (pkg.name);
				} else {
					row.action_togglebutton.active = false;
					row.action_icon.icon_name = "software-update-symbolic";
					to_update.remove (pkg.name);
					temporary_ignorepkgs.add (pkg.name);
				}
				set_pending_operations ();
			});
			return row;
		}

		void refresh_listbox_buttons () {
			unowned Gtk.Widget? child = packages_listbox.get_first_child ();
			while (child != null) {
				unowned PackageRow pamac_row = child as PackageRow;
				if (pamac_row == null) {
					child = child.get_next_sibling ();
					continue;
				}
				Package? pkg = pamac_row.pkg;
				if (pkg == null) {
					child = child.get_next_sibling ();
					continue;
				}
				if (transaction.transaction_summary_contains (pkg.id)) {
					pamac_row.action_togglebutton.active = false;
					pamac_row.action_togglebutton.sensitive = false;
					child = child.get_next_sibling ();
					continue;
				}
				if (!database.should_hold (pkg.name)) {
					pamac_row.action_togglebutton.sensitive = true;
				}
				if (pkg is AURPackage) {
					if (pkg.name in to_build ||
						pkg.name in to_remove ||
						pkg.name in to_update) {
						pamac_row.action_togglebutton.active = true;
						pamac_row.action_icon.icon_name = "software-select-symbolic";
					} else if (pkg.installed_version == null) {
						pamac_row.action_togglebutton.active = false;
						pamac_row.action_icon.icon_name = "software-install-symbolic";
					} else if (view_stack.visible_child_name == "updates") {
						pamac_row.action_togglebutton.active = false;
						pamac_row.action_icon.icon_name = "software-update-symbolic";
					} else {
						pamac_row.action_togglebutton.active = false;
						pamac_row.action_icon.icon_name = "software-remove-symbolic";
					}
				} else if (pkg is SnapPackage) {
					if (pkg.name in snap_to_install ||
						pkg.name in snap_to_remove) {
						pamac_row.action_togglebutton.active = true;
						pamac_row.action_icon.icon_name = "software-select-symbolic";
					} else if (pkg.installed_version == null) {
						pamac_row.action_togglebutton.active = false;
						pamac_row.action_icon.icon_name = "software-install-symbolic";
					} else {
						pamac_row.action_togglebutton.active = false;
						pamac_row.action_icon.icon_name = "software-remove-symbolic";
					}
				} else if (pkg is FlatpakPackage) {
					if (pkg.id in flatpak_to_install ||
						pkg.id in flatpak_to_remove ||
						pkg.id in to_update) {
						pamac_row.action_togglebutton.active = true;
						pamac_row.action_icon.icon_name = "software-select-symbolic";
					} else if (pkg.installed_version == null) {
						pamac_row.action_togglebutton.active = false;
						pamac_row.action_icon.icon_name = "software-install-symbolic";
					} else {
						pamac_row.action_togglebutton.active = false;
						pamac_row.action_icon.icon_name = "software-remove-symbolic";
					}
				} else if (pkg is AlpmPackage){
					if (pkg.installed_version == null) {
						if (pkg.name in to_install) {
							pamac_row.action_togglebutton.active = true;
							pamac_row.action_icon.icon_name = "software-select-symbolic";
						} else {
							pamac_row.action_togglebutton.active = false;
							pamac_row.action_icon.icon_name = "software-install-symbolic";
						}
					} else if (view_stack.visible_child_name == "updates") {
						if (pkg.name in to_update) {
							pamac_row.action_togglebutton.active = true;
							pamac_row.action_icon.icon_name = "software-select-symbolic";
						} else {
							pamac_row.action_togglebutton.active = false;
							pamac_row.action_icon.icon_name = "software-update-symbolic";
						}
					} else if (pkg.name in to_remove) {
						pamac_row.action_togglebutton.active = true;
						pamac_row.action_icon.icon_name = "software-select-symbolic";
					} else {
						pamac_row.action_togglebutton.active = false;
						pamac_row.action_icon.icon_name = "software-remove-symbolic";
					}
				}
				child = child.get_next_sibling ();
			}
		}

		public void refresh_packages_list () {
			switch (view_stack.visible_child_name) {
				case "browse":
					show_sidebar (true);
					search_entry.visible = false;
					search_button.visible = browse_flap.visible;
					switch (browse_stack.visible_child_name) {
						case "filters":
							switch (current_filters_index) {
								case 0: // categories
									on_categories_listbox_row_activated (categories_listbox.get_selected_row ());
									break;
								case 1: // groups
									on_groups_listbox_row_activated (groups_listbox.get_selected_row ());
									break;
								case 2: // repos
									on_repos_listbox_row_activated (repos_listbox.get_selected_row ());
									break;
								default:
									break;
							}
							break;
						case "categories":
							on_categories_listbox_row_activated (categories_listbox.get_selected_row ());
							break;
						case "groups":
							on_groups_listbox_row_activated (groups_listbox.get_selected_row ());
							break;
						case "repos":
							on_repos_listbox_row_activated (repos_listbox.get_selected_row ());
							break;
						default:
							break;
					}
					set_pending_operations ();
					break;
				case "installed":
					show_sidebar (!local_config.software_mode);
					search_entry.visible = false;
					search_button.visible = browse_flap.visible;
					on_installed_listbox_row_activated (installed_listbox.get_selected_row ());
					set_pending_operations ();
					break;
				case "search":
					show_sidebar (!local_config.software_mode);
					on_search_listbox_row_activated (search_listbox.get_selected_row ());
					set_pending_operations ();
					break;
				case "updates":
					if (local_config.software_mode) {
						show_sidebar (false);
					}
					search_button.visible = false;
					apply_button.sensitive = false;
					cancel_button.sensitive = false;
					if (updates_checked) {
						populate_updates ();
					} else {
						refresh_updates (true);
					}
					break;
				default:
					break;
			}
		}

		public void display_details (Package pkg) {
			details_scrolledwindow.vadjustment.value = 0;
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
			if (current_package_displayed == null) {
				return;
			}
			if (current_package_displayed is AURPackage) {
				database.get_aur_pkg_async.begin (current_package_displayed.name, (obj, res) => {
					Package? pkg = database.get_aur_pkg_async.end (res);
					if (pkg != null) {
						display_details (pkg);
					} else {
						this.activate_action ("back", null);
					}
				});
			} else if (current_package_displayed is SnapPackage) {
				database.get_snap_async.begin (current_package_displayed.name, (obj, res) => {
					Package? pkg = database.get_snap_async.end (res);
					if (pkg != null) {
						display_details (pkg);
					} else {
						this.activate_action ("back", null);
					}
				});
			} else if (current_package_displayed is FlatpakPackage) {
				FlatpakPackage current_flatpak = current_package_displayed as FlatpakPackage;
				database.get_flatpak_async.begin (current_flatpak.id, (obj, res) => {
					Package? pkg = database.get_flatpak_async.end (res);
					if (pkg != null) {
						display_details (pkg);
					} else {
						this.activate_action ("back", null);
					}
				});
			} else {
				Package? pkg = database.get_installed_pkg (current_package_displayed.name);
				if (pkg == null) {
					pkg = database.get_sync_pkg (current_package_displayed.name);
				}
				if (pkg != null) {
					display_details (pkg);
				} else {
					this.activate_action ("back", null);
				}
			}
		}

		public void display_package_details (AlpmPackage pkg) {
			current_package_displayed = pkg;
			// select details if software_mode or build files was selected
			if (local_config.software_mode || properties_stack.visible_child_name == "build_files") {
				properties_stack.visible_child_name = "details";
			}
			AURPackage? aur_pkg = null;
			if (pkg.repo == dgettext (null, "AUR")) {
				aur_pkg = database.get_aur_pkg (pkg.name);
			}
			files_page.visible = true;
			build_files_page.visible = aur_pkg != null;
			properties_stack_switcher.visible = !local_config.software_mode;
			set_package_details (pkg, aur_pkg);
		}

		void display_aur_details (AURPackage aur_pkg) {
			current_package_displayed = aur_pkg;
			unowned string installed_version = aur_pkg.installed_version;
			if (installed_version == null) {
				// select details if files was selected
				if (properties_stack.visible_child_name == "files") {
					properties_stack.visible_child_name = "details";
				}
			}
			files_page.visible = false;
			build_files_page.visible = true;
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
		void on_packages_listbox_row_activated (Gtk.FlowBoxChild row) {
			unowned PackageRow pamac_row = row as PackageRow;
			if (pamac_row == null) {
				return;
			}
			Package? pkg = pamac_row.pkg;
			if (pkg != null) {
				display_details (pkg);
				if (!main_details_box.visible) {
					main_details_box.visible = true;
					browse_flap.visible = false;
					set_adaptative_details (true);
					if (packages_leaflet.folded) {
						packages_leaflet.visible_child_name = "details";
						set_adaptative_details (true);
					} else if (mobile) {
						browse_flap.visible = false;
						set_adaptative_details (true);
					}
				} else if (packages_leaflet.folded) {
					packages_leaflet.visible_child_name = "details";
				}
				if (packages_leaflet.folded || browse_flap.visible == false) {
					search_entry.visible = false;
					view_stack_switcher.visible = false;
					button_back.visible = true;
					search_button.visible = false;
				}
			} else {
				// check for OS Updates row
				if (pamac_row.name_label.label == dgettext (null, "OS Updates")) {
					var updates_dialog = new UpdatesDialog (this);
					updates_dialog.label.label = dgettext (null, "Includes performance, stability and security improvements");
					// populates updates
					foreach (unowned Package update_pkg in current_packages_list) {
						if (update_pkg.app_name == null) {
							var update_row = create_update_row (update_pkg);
							updates_dialog.listbox.append (update_row);
						}
					}
					if (!mobile) {
						updates_dialog.default_width = 500;
					}
					updates_dialog.default_height = 500;
					updates_dialog.show ();
				}
			}
		}

		void on_deps_listbox_row_activated (Gtk.ListBoxRow row) {
			if (display_package_queue.find_custom (current_package_displayed, compare_pkgs_by_name) == null) {
				display_package_queue.push_tail (current_package_displayed);
			}
			string? depstring = null;
			unowned Gtk.Widget? child = row.get_first_child ();
			while (child != null) {
				var dep_label = child as Gtk.Label;
				if (dep_label != null) {
					depstring = dep_label.label;
				}
				child = child.get_next_sibling ();
			}
			if (depstring == null) {
				return;
			}
			if (database.has_installed_satisfier (depstring)) {
				display_package_details (database.get_installed_satisfier (depstring));
			} else if (database.has_sync_satisfier (depstring)) {
				display_package_details (database.get_sync_satisfier (depstring));
			} else {
				this.set_cursor (new Gdk.Cursor.from_name ("progress", null));
				string dep_name = database.get_alpm_dep_name (depstring);
				var aur_pkg = database.get_aur_pkg (dep_name);
				this.set_cursor (new Gdk.Cursor.from_name ("default", null));
				if (aur_pkg != null) {
					display_aur_details (aur_pkg);
				}
			}
		}

		async GenericArray<unowned AURPackage> get_pending_aur_pkgs () {
			var aur_pkgs = new GenericArray<unowned AURPackage> ();
			var to_build_array = new GenericArray<string> (to_build.length);
			foreach (unowned string name in to_build)  {
				to_build_array.add (name);
			}
			var table = yield database.get_aur_pkgs_async (to_build_array);
			var iter = HashTableIter<string, unowned AURPackage?> (table);
			unowned AURPackage? aur_pkg;
			while (iter.next (null, out aur_pkg)) {
				if (aur_pkg != null) {
					aur_pkgs.add (aur_pkg);
				}
			}
			return aur_pkgs;
		}

		async GenericArray<unowned Package> get_pending_pkgs () {
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
				var aur_pkgs = yield get_pending_aur_pkgs ();
				foreach (unowned Package aur_pkg in aur_pkgs) {
					pkgs.add (aur_pkg);
				}
			}
			return pkgs;
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
			set_pending_operations ();
		}

		[GtkCallback]
		void on_install_all_button_clicked () {
			foreach (unowned Package pkg in current_packages_list) {
				if (!transaction.transaction_summary_contains (pkg.id) && pkg.installed_version == null) {
					to_install.add (pkg.name);
				}
			}
			refresh_listbox_buttons ();
			set_pending_operations ();
		}

		[GtkCallback]
		void on_ignore_all_button_clicked () {
			foreach (unowned Package pkg in current_packages_list) {
				to_update.remove (pkg.name);
				temporary_ignorepkgs.add (pkg.name);
			}
			refresh_listbox_buttons ();
			set_pending_operations ();
		}

		[GtkCallback]
		void on_search_entry_activated () {
			string tmp_search_string = search_entry.get_text ().strip ();
			if (tmp_search_string.char_count () > 1) {
				this.set_cursor (new Gdk.Cursor.from_name ("progress", null));
				search_string = tmp_search_string.down ();
				view_stack.visible_child_name = "search";
				refresh_packages_list ();
			}
		}

		[GtkCallback]
		void on_search_entry_search_changed () {
			//on_search_entry_activated ();
		}

		[GtkCallback]
		void on_search_entry_changed () {
			if (main_stack.visible_child_name != "browse") {
				return;
			}
			if (view_stack.visible_child_name == "updates") {
				return;
			}
			if (view_stack.visible_child_name == "browse"
				|| view_stack.visible_child_name == "installed") {
				search_entry.grab_focus ();
				search_button.clicked ();
			}
		}

		void on_sortby_dropdown_selected_changed () {
			uint index = sortby_dropdown.selected;
			switch (index) {
				case 0: // relevance
				case 4: // date
					// check if we need to sort aur packages
					if (view_stack.visible_child_name == "search") {
						unowned Gtk.ListBoxRow row = search_listbox.get_selected_row ();
						var simple_row = row as SimpleRow;
						if (simple_row != null && simple_row.title == dgettext (null, "AUR")) {
							populate_aur_list (current_packages_list);
						}
					} else if (view_stack.visible_child_name == "updates") {
						unowned Gtk.ListBoxRow row = updates_listbox.get_selected_row ();
						var simple_row = row as SimpleRow;
						if (simple_row != null && simple_row.title == dgettext (null, "AUR")) {
							populate_aur_list (current_packages_list);
						}
					} else {
						populate_packages_list (current_packages_list);
					}
					break;
				case 1: // name
				case 2: // repository
				case 3: // size
					populate_packages_list (current_packages_list);
					break;
				default:
					break;
			}
		}

		[GtkCallback]
		void on_filters_listbox_row_activated (Gtk.ListBoxRow row) {
			current_filters_index = row.get_index ();
			switch (current_filters_index) {
				case 0: // categories
					browse_stack.visible_child_name = "categories";
					break;
				case 1: // groups
					browse_stack.visible_child_name = "groups";
					break;
				case 2: // repos
					browse_stack.visible_child_name = "repos";
					break;
				// separator
				// case 3:
				case 4: // pending
					this.set_cursor (new Gdk.Cursor.from_name ("progress", null));
					current_packages_list_name = "Pending";
					get_pending_pkgs.begin ((obj, res) => {
						var pkgs = get_pending_pkgs.end (res);
						if (view_stack.visible_child_name == "browse" && current_packages_list_name == "Pending") {
							populate_packages_list (pkgs);
						} else {
							this.set_cursor (new Gdk.Cursor.from_name ("default", null));
						}
					});
					install_all_button.visible = false;
					remove_all_button.visible = false;
					ignore_all_button.visible = false;
					// hide sidebar in folded mode
					if (browse_flap.folded && browse_flap.reveal_flap) {
						browse_flap.reveal_flap = false;
					}
					break;
				default:
					break;
			}
		}

		void on_browse_stack_visible_child_changed () {
			if (browse_flap.folded) {
				return;
			}
			switch (browse_stack.visible_child_name) {
				case "categories":
					unowned Gtk.ListBoxRow selected_row = categories_listbox.get_selected_row ();
					if (!selected_row.visible) {
						// occurs if pending was selected and selection has been cleared
						categories_listbox.select_row (categories_listbox.get_row_at_index (1));
					}
					on_categories_listbox_row_activated (categories_listbox.get_selected_row ());
					break;
				case "groups":
					on_groups_listbox_row_activated (groups_listbox.get_selected_row ());
					break;
				case "repos":
					on_repos_listbox_row_activated (repos_listbox.get_selected_row ());
					break;
				default:
					break;
			}
		}

		[GtkCallback]
		void on_categories_listbox_row_activated (Gtk.ListBoxRow row) {
			if (row is BackRow) {
				// unselect pending row
				filters_listbox.select_row (null);
				browse_stack.visible_child_name = "filters";
				return;
			}
			var simple_row = row as SimpleRow;
			if (simple_row == null) {
				return;
			}
			unowned string category_name = simple_row.title;
			string category = "";
			if (category_name == dgettext (null, "Featured")) {
				category = "Featured";
			} else if (category_name == dgettext (null, "Photo & Video")) {
				category = "Photo & Video";
			} else if (category_name == dgettext (null, "Music & Audio")) {
				category = "Music & Audio";
			} else if (category_name == dgettext (null, "Productivity")) {
				category = "Productivity";
			} else if (category_name == dgettext (null, "Communication & News")) {
				category = "Communication & News";
			} else if (category_name == dgettext (null, "Education & Science")) {
				category = "Education & Science";
			} else if (category_name == dgettext (null, "Games")) {
				category = "Games";
			} else if (category_name == dgettext (null, "Utilities")) {
				category = "Utilities";
			} else if (category_name == dgettext (null, "Development")) {
				category = "Development";
			} else if (category_name == dgettext (null, "Pending")) {
				category = "Pending";
			}
			this.set_cursor (new Gdk.Cursor.from_name ("progress", null));
			current_packages_list_name = "category_%s".printf (category);
			get_category_pkgs.begin (category, (obj, res) => {
				var pkgs = get_category_pkgs.end (res);
				if (view_stack.visible_child_name == "browse" && current_packages_list_name == "category_%s".printf (category)) {
					view_stack_switcher.title = category_name;
					populate_packages_list (pkgs);
				} else {
					this.set_cursor (new Gdk.Cursor.from_name ("default", null));
				}
			});
			install_all_button.visible = false;
			remove_all_button.visible = false;
			ignore_all_button.visible = false;
			// hide sidebar in folded mode
			if (browse_flap.folded && browse_flap.reveal_flap) {
				browse_flap.reveal_flap = false;
			}
		}

		[GtkCallback]
		void on_groups_listbox_row_activated (Gtk.ListBoxRow row) {
			if (row is BackRow) {
				// unselect pending row
				filters_listbox.select_row (null);
				browse_stack.visible_child_name = "filters";
				return;
			}
			var simple_row = row as SimpleRow;
			if (simple_row == null) {
				return;
			}
			this.set_cursor (new Gdk.Cursor.from_name ("progress", null));
			unowned string group_name = simple_row.title;
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
				if (view_stack.visible_child_name == "browse" && current_packages_list_name == "group_%s".printf (group_name)) {
					view_stack_switcher.title = group_name;
					populate_packages_list (pkgs);
				} else {
					this.set_cursor (new Gdk.Cursor.from_name ("default", null));
				}
			});
			ignore_all_button.visible = false;
			// hide sidebar in folded mode
			if (browse_flap.folded && browse_flap.reveal_flap) {
				browse_flap.reveal_flap = false;
			}
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
		void on_installed_listbox_row_activated (Gtk.ListBoxRow row) {
			this.set_cursor (new Gdk.Cursor.from_name ("progress", null));
			int index = row.get_index ();
			switch (index) {
				case 0: // all
					current_packages_list_name = "installed_all";
					get_all_installed.begin ((obj, res) => {
						var pkgs = get_all_installed.end (res);
						if (view_stack.visible_child_name == "installed" && current_packages_list_name == "installed_all") {
							view_stack_switcher.title = dgettext (null, "Installed");
							populate_packages_list (pkgs);
						} else {
							this.set_cursor (new Gdk.Cursor.from_name ("default", null));
						}
					});
					break;
				case 1: // explicitly installed
					current_packages_list_name = "explicitly_installed";
					database.get_explicitly_installed_pkgs_async.begin ((obj, res) => {
						var pkgs = database.get_explicitly_installed_pkgs_async.end (res);
						if (view_stack.visible_child_name == "installed" && current_packages_list_name == "explicitly_installed") {
							view_stack_switcher.title = dgettext (null, "Explicitly installed");
							populate_packages_list (pkgs);
						} else {
							this.set_cursor (new Gdk.Cursor.from_name ("default", null));
						}
					});
					break;
				case 2: // orphans
					current_packages_list_name = "orphans";
					database.get_orphans_async.begin ((obj, res) => {
						var pkgs = database.get_orphans_async.end (res);
						if (view_stack.visible_child_name == "installed" && current_packages_list_name == "orphans") {
							view_stack_switcher.title = dgettext (null, "Orphans");
							populate_packages_list (pkgs);
							remove_all_button.visible = pkgs.length > 0;
						} else {
							this.set_cursor (new Gdk.Cursor.from_name ("default", null));
						}
					});
					break;
				case 3: // foreign
					current_packages_list_name = "foreign";
					database.get_foreign_pkgs_async.begin ((obj, res) => {
						var pkgs = database.get_foreign_pkgs_async.end (res);
						if (view_stack.visible_child_name == "installed" && current_packages_list_name == "foreign") {
							view_stack_switcher.title = dgettext (null, "Foreign");
							populate_packages_list (pkgs);
						} else {
							this.set_cursor (new Gdk.Cursor.from_name ("default", null));
						}
					});
					break;
				case 4: // Snap or Flatpak
				case 5:
					var simple_row = row as SimpleRow;
					if (simple_row == null) {
						this.set_cursor (new Gdk.Cursor.from_name ("default", null));
						return;
					}
					unowned string title = simple_row.title;
					if (title == dgettext (null, "Snap")) {
						current_packages_list_name = "installed_snaps";
						database.get_installed_snaps_async.begin ((obj, res) => {
							var pkgs = database.get_installed_snaps_async.end (res);
							if (view_stack.visible_child_name == "installed" && current_packages_list_name == "installed_snaps") {
								view_stack_switcher.title = dgettext (null, "Snap");
								populate_packages_list (pkgs);
							} else {
								this.set_cursor (new Gdk.Cursor.from_name ("default", null));
							}
						});
					} else if (title == dgettext (null, "Flatpak")) {
						current_packages_list_name = "installed_flatpaks";
						database.get_installed_flatpaks_async.begin ((obj, res) => {
							var pkgs = database.get_installed_flatpaks_async.end (res);
							if (view_stack.visible_child_name == "installed" && current_packages_list_name == "installed_flatpaks") {
								view_stack_switcher.title = dgettext (null, "Flatpak");
								populate_packages_list (pkgs);
							} else {
								this.set_cursor (new Gdk.Cursor.from_name ("default", null));
							}
						});
					}
					break;
				default:
					break;
			}
			install_all_button.visible = false;
			remove_all_button.visible = false;
			ignore_all_button.visible = false;
			// hide sidebar in folded mode
			if (browse_flap.folded && browse_flap.reveal_flap) {
				browse_flap.reveal_flap = false;
			}
		}

		[GtkCallback]
		void on_search_listbox_row_activated (Gtk.ListBoxRow row) {
			search_entry.grab_focus ();
			if (search_string == null) {
				return;
			}
			this.set_cursor (new Gdk.Cursor.from_name ("progress", null));
			int index = row.get_index ();
			switch (index) {
				case 0: // all
					current_packages_list_name = "search_all_%s".printf (search_string);
					search_all_pkgs.begin ((obj, res) => {
						var pkgs = search_all_pkgs.end (res);
						if (view_stack.visible_child_name == "search" && current_packages_list_name == "search_all_%s".printf (search_string)) {
							populate_packages_list (pkgs);
						} else {
							this.set_cursor (new Gdk.Cursor.from_name ("default", null));
						}
					});
					break;
				case 1: // installed
					current_packages_list_name = "search_installed_%s".printf (search_string);
					database.search_installed_pkgs_async.begin (search_string, (obj, res) => {
						var pkgs = database.search_installed_pkgs_async.end (res);
						if (view_stack.visible_child_name == "search" && current_packages_list_name == "search_installed_%s".printf (search_string)) {
							populate_packages_list (pkgs);
						} else {
							this.set_cursor (new Gdk.Cursor.from_name ("default", null));
						}
					});
					break;
				case 2: // repos
					current_packages_list_name = "search_repos_%s".printf (search_string);
					database.search_repos_pkgs_async.begin (search_string, (obj, res) => {
						if (view_stack.visible_child_name == "search" && current_packages_list_name == "search_repos_%s".printf (search_string)) {
							var pkgs = database.search_repos_pkgs_async.end (res);
							populate_packages_list (pkgs);
						} else {
							this.set_cursor (new Gdk.Cursor.from_name ("default", null));
						}
					});
					break;
				case 3: // AUR or Snap or Flatpak
				case 4:
				case 5:
					var simple_row = row as SimpleRow;
					if (simple_row == null) {
						this.set_cursor (new Gdk.Cursor.from_name ("default", null));
						return;
					}
					unowned string title = simple_row.title;
					if (title == dgettext (null, "AUR")) {
						current_packages_list_name = "search_aur_%s".printf (search_string);
						database.search_aur_pkgs_async.begin (search_string, (obj, res) => {
							if (view_stack.visible_child_name == "search" && current_packages_list_name == "search_aur_%s".printf (search_string)) {
								var pkgs = database.search_aur_pkgs_async.end (res);
								populate_aur_list (pkgs);
							} else {
								this.set_cursor (new Gdk.Cursor.from_name ("default", null));
							}
						});
					} else if (title == dgettext (null, "Snap")) {
						current_packages_list_name = "search_snap_%s".printf (search_string);
						database.search_snaps_async.begin (search_string, (obj, res) => {
							if (view_stack.visible_child_name == "search" && current_packages_list_name == "search_snap_%s".printf (search_string)) {
								var pkgs = database.search_snaps_async.end (res);
								populate_packages_list (pkgs);
							} else {
								this.set_cursor (new Gdk.Cursor.from_name ("default", null));
							}
						});
					} else if (title == dgettext (null, "Flatpak")) {
						current_packages_list_name = "search_flatpak_%s".printf (search_string);
						database.search_flatpaks_async.begin (search_string, (obj, res) => {
							if (view_stack.visible_child_name == "search" && current_packages_list_name == "search_flatpak_%s".printf (search_string)) {
								var pkgs = database.search_flatpaks_async.end (res);
								populate_packages_list (pkgs);
							} else {
								this.set_cursor (new Gdk.Cursor.from_name ("default", null));
							}
						});
					}
					break;
				default:
					break;
			}
			install_all_button.visible = false;
			remove_all_button.visible = false;
			ignore_all_button.visible = false;
		}


		[GtkCallback]
		void on_updates_listbox_row_activated (Gtk.ListBoxRow row) {
			this.set_cursor (new Gdk.Cursor.from_name ("progress", null));
			int index = row.get_index ();
			switch (index) {
				case 0: // all
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
					if (view_stack.visible_child_name == "updates" && current_packages_list_name == "all_updates") {
						view_stack_switcher.title = dgettext (null, "Updates");
						populate_packages_list (pkgs);
					} else {
						this.set_cursor (new Gdk.Cursor.from_name ("default", null));
					}
					if (!local_config.software_mode) {
						ignore_all_button.visible = true;
					}
					break;
				case 1: // repos
					current_packages_list_name = "repos_updates";
					var pkgs = new GenericArray<unowned AlpmPackage> ();
					foreach (unowned AlpmPackage pkg in repos_updates) {
						if (!temporary_ignorepkgs.contains (pkg.name)) {
							pkgs.add (pkg);
						}
					}
					if (view_stack.visible_child_name == "updates" && current_packages_list_name == "repos_updates") {
						view_stack_switcher.title = dgettext (null, "Repositories");
						populate_packages_list (pkgs);
					} else {
						this.set_cursor (new Gdk.Cursor.from_name ("default", null));
					}
					if (pkgs.length > 0) {
						ignore_all_button.visible = true;
					}
					break;
				case 2: // AUR  or Flatpak or ignored
				case 3:
				case 4:
					var simple_row = row as SimpleRow;
					if (simple_row == null) {
						this.set_cursor (new Gdk.Cursor.from_name ("default", null));
						break;
					}
					unowned string title = simple_row.title;
					if (title == dgettext (null, "AUR")) {
						current_packages_list_name = "aur_updates";
						var pkgs = new GenericArray<unowned AURPackage> ();
						foreach (unowned AURPackage pkg in aur_updates) {
							if (!temporary_ignorepkgs.contains (pkg.name)) {
								pkgs.add (pkg);
							}
						}
						if (view_stack.visible_child_name == "updates" && current_packages_list_name == "aur_updates") {
							view_stack_switcher.title = dgettext (null, "AUR");
							populate_aur_list (pkgs);
						} else {
							this.set_cursor (new Gdk.Cursor.from_name ("default", null));
						}
						if (pkgs.length > 0) {
							ignore_all_button.visible = true;
						}
					} else if (title == dgettext (null, "Flatpak")) {
						current_packages_list_name = "flatpak_updates";
						var pkgs = new GenericArray<unowned FlatpakPackage> ();
						foreach (unowned FlatpakPackage pkg in flatpak_updates) {
							if (!temporary_ignorepkgs.contains (pkg.name)) {
								pkgs.add (pkg);
							}
						}
						if (view_stack.visible_child_name == "updates" && current_packages_list_name == "flatpak_updates") {
							view_stack_switcher.title = dgettext (null, "Flatpak");
							populate_packages_list (pkgs);
						} else {
							this.set_cursor (new Gdk.Cursor.from_name ("default", null));
						}
						if (pkgs.length > 0) {
							ignore_all_button.visible = true;
						}
					} else if (title == dgettext (null, "Ignored")) {
						current_packages_list_name = "ignored_updates";
						var pkgs = new GenericArray<unowned Package> ();
						foreach (unowned AlpmPackage pkg in repos_updates) {
							if (temporary_ignorepkgs.contains (pkg.name)) {
								pkgs.add (pkg);
							}
						}
						foreach (unowned AURPackage pkg in aur_updates) {
							if (temporary_ignorepkgs.contains (pkg.name)) {
								pkgs.add (pkg);
							}
						}
						foreach (unowned FlatpakPackage pkg in flatpak_updates) {
							if (temporary_ignorepkgs.contains (pkg.name)) {
								pkgs.add (pkg);
							}
						}
						if (view_stack.visible_child_name == "updates" && current_packages_list_name == "ignored_updates") {
							if (pkgs.length > 0) {
								view_stack_switcher.title = dgettext (null, "Ignored");
								populate_packages_list (pkgs);
							} else {
								updates_listbox.select_row (updates_listbox.get_row_at_index (0));
								on_updates_listbox_row_activated (updates_listbox.get_selected_row ());
							}
						} else {
							this.set_cursor (new Gdk.Cursor.from_name ("default", null));
						}
						ignore_all_button.visible = false;
					}
					break;
				default:
					break;
			}
			install_all_button.visible = false;
			remove_all_button.visible = false;
			// hide sidebar in folded mode
			if (browse_flap.folded && browse_flap.reveal_flap) {
				browse_flap.reveal_flap = false;
			}
		}

		[GtkCallback]
		void on_repos_listbox_row_activated (Gtk.ListBoxRow row) {
			if (row is BackRow) {
				// unselect pending row
				filters_listbox.select_row (null);
				browse_stack.visible_child_name = "filters";
				return;
			}
			var simple_row = row as SimpleRow;
			if (simple_row == null) {
				return;
			}
			this.set_cursor (new Gdk.Cursor.from_name ("progress", null));
			unowned string repo = simple_row.title;
			current_packages_list_name = "repo_%s".printf (repo);
			database.get_repo_pkgs_async.begin (repo, (obj, res) => {
				var pkgs = database.get_repo_pkgs_async.end (res);
				if (view_stack.visible_child_name == "browse" && current_packages_list_name == "repo_%s".printf (repo)) {
					view_stack_switcher.title = repo;
					populate_packages_list (pkgs);
				} else {
					this.set_cursor (new Gdk.Cursor.from_name ("default", null));
				}
			});
			install_all_button.visible = false;
			remove_all_button.visible = false;
			ignore_all_button.visible = false;
			// hide sidebar in folded mode
			if (browse_flap.folded && browse_flap.reveal_flap) {
				browse_flap.reveal_flap = false;
			}
		}

		void on_main_stack_visible_child_changed () {
			switch (main_stack.visible_child_name) {
				case "browse":
					if (transaction.details_textview.buffer.get_char_count () > 0) {
						details_button.sensitive = true;
					}
					break;
				case "term":
					search_entry.visible = false;
					view_stack_switcher.visible = false;
					button_back.visible = true;
					search_button.visible = false;
					details_button.sensitive = false;
					details_button.remove_css_class ("suggested-action");
					details_button.has_frame = false;
					break;
				default:
					break;
			}
		}

		void on_view_stack_visible_child_changed () {
			refresh_packages_list ();
		}

		void on_packages_leaflet_folded_changed () {
			if (packages_leaflet.folded) {
				reveal_details_button.visible = false;
			} else if (browse_flap.visible == true && main_details_box.visible == true) {
				if (mobile) {
					reveal_details_button.visible = false;
					main_details_box.visible = false;
				} else {
					reveal_details_button.visible = true;
					set_adaptative_details (false);
				}
				packages_leaflet.visible_child_name = "list";
				if (view_stack.visible_child_name == "search") {
					search_entry.visible = true;
				} else if (view_stack.visible_child_name == "updates") {
					view_stack_switcher.visible = true;
					button_back.visible = false;
					search_button.visible = false;
				} else {
					view_stack_switcher.visible = true;
					button_back.visible = false;
					search_button.visible = true;
				}
			} else if (!mobile) {
				reveal_details_button.visible = true;
			}
		}

		public void set_adaptative_details (bool enabled) {
			if (enabled) {
				main_details_box.hexpand = true;
				main_details_box.width_request = 0;
			} else {
				main_details_box.hexpand = false;
				main_details_box.width_request = 700;
			}
		}

		[GtkCallback]
		void on_menu_popover_shown () {
			preferences_action.set_enabled (!transaction_running);
			refresh_action.set_enabled (!transaction_running);
			install_local_action.set_enabled (!transaction_running);
		}

		[GtkCallback]
		void on_details_button_clicked () {
			important_details = false;
			main_stack.visible_child_name = "term";
		}

		async GenericArray<unowned Package> get_category_pkgs (string category) {
			if (category == "Pending") {
				return yield get_pending_pkgs ();
			}
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

		[GtkCallback]
		void on_apply_button_clicked () {
			details_button.sensitive = true;
			if (view_stack.visible_child_name == "updates") {
				run_sysupgrade ();
			} else if (packages_leaflet.visible_child_name == "details" &&
				properties_stack.visible_child_name == "build_files") {
				transaction.save_build_files_async.begin (current_package_displayed.name, () => {
					run_transaction ();
				});
			} else {
				run_transaction ();
			}
		}

		void run_transaction (bool no_confirm_upgrade = false) {
			transaction.no_confirm_upgrade = no_confirm_upgrade;
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
				transaction.add_pkg_to_build (name, true, true);
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
				previous_flatpak_to_install.insert (pkg.id, pkg);
			}
			foreach (unowned FlatpakPackage pkg in flatpak_to_remove.get_values ()) {
				transaction.add_flatpak_to_remove (pkg);
				previous_flatpak_to_remove.insert (pkg.id, pkg);
			}
			clear_lists ();
			transaction.install_if_needed = false;
			transaction.run_async.begin ((obj, res) => {
				bool success = transaction.run_async.end (res);
				on_transaction_finished (success);
			});
		}

		void run_sysupgrade (bool force_refresh = false, bool no_confirm_upgrade = true) {
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
			run_transaction (no_confirm_upgrade);
		}

		[GtkCallback]
		void on_cancel_button_clicked () {
			if (waiting) {
				waiting = false;
				transaction.cancel ();
				transaction.stop_progressbar_pulse ();
				set_pending_operations ();
			} else if (transaction_running) {
				transaction_running = false;
				transaction.cancel ();
			} else {
				clear_lists ();
				set_pending_operations ();
				refresh_listbox_buttons ();
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

		[GtkCallback]
		void on_refresh_button_clicked () {
			refresh_updates (false);
		}

		void refresh_updates (bool use_timestamp) {
			packages_stack.visible_child_name = "checking";
			this.set_cursor (new Gdk.Cursor.from_name ("progress", null));
			bool check_aur_updates_backup = database.config.check_aur_updates;
			database.config.check_aur_updates = check_aur_updates_backup && !local_config.software_mode;
			database.get_updates_async.begin (use_timestamp, (obj, res) => {
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
				if (view_stack.visible_child_name == "updates") {
					populate_updates ();
				} else {
					this.set_cursor (new Gdk.Cursor.from_name ("default", null));
				}
			});
		}

		void on_get_updates_progress (uint percent) {
			checking_label.set_markup ("<big><b>%s %u %</b></big>".printf (dgettext (null, "Checking for Updates"), percent));
		}

		void populate_updates () {
			to_update.remove_all ();
			if (repos_updates.length == 0
				&& aur_updates.length == 0
				&& flatpak_updates.length == 0) {
				show_sidebar (false);
				view_stack_switcher.title = dgettext (null, "Updates");
				packages_stack.visible_child_name = "updated";
				DateTime? last_refresh_time = database.get_last_refresh_time ();
				if (last_refresh_time == null) {
					last_refresh_label.label = "";
				} else {
					// round at minute
					int64 elasped_time = last_refresh_time.to_unix ();
					int64 elasped_day = elasped_time / TimeSpan.DAY;
					string time_format;
					// check if last refresh was less than 24 hours ago
					if (elasped_day < 1) {
						// check if last refresh was the same day
						var now = new DateTime.now_local ();
						if (last_refresh_time.get_day_of_week () == now.get_day_of_week ()) {
							time_format = last_refresh_time.format ("%X");
						} else {
							time_format = last_refresh_time.format ("%c");
						}
					} else {
						time_format = last_refresh_time.format ("%x");
					}
					last_refresh_label.set_markup ("<span foreground='grey'>%s</span>".printf ("%s : %s".printf (dgettext (null, "Last refresh"), time_format)));
				}
				install_all_button.visible = false;
				remove_all_button.visible = false;
				ignore_all_button.visible = false;
				this.set_cursor (new Gdk.Cursor.from_name ("default", null));
			} else {
				if (repos_updates.length > 0) {
					foreach (unowned AlpmPackage pkg in repos_updates) {
						if (!temporary_ignorepkgs.contains (pkg.name)) {
							to_update.add (pkg.name);
						}
					}
					updates_repos_row.visible = true;
				} else {
					updates_repos_row.visible = false;
				}
				if (aur_updates.length > 0) {
					foreach (unowned AURPackage pkg in aur_updates) {
						if (!temporary_ignorepkgs.contains (pkg.name)) {
							to_update.add (pkg.name);
						}
					}
					updates_aur_row.visible = true;
				} else {
					updates_aur_row.visible = false;
				}
				if (flatpak_updates.length > 0) {
					foreach (unowned FlatpakPackage pkg in flatpak_updates) {
						if (!temporary_ignorepkgs.contains (pkg.name)) {
							to_update.add (pkg.name);
						}
					}
					updates_flatpak_row.visible = true;
				} else {
					updates_flatpak_row.visible = false;
				}
				updates_ignored_row.visible = temporary_ignorepkgs.length > 0;
				show_sidebar (!local_config.software_mode);
				on_updates_listbox_row_activated (updates_listbox.get_selected_row ());
				set_pending_operations ();
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
			this.set_cursor (new Gdk.Cursor.from_name ("progress", null));
			cancel_button.sensitive = false;
		}

		void on_stop_preparing () {
			cancel_button.sensitive = false;
			this.set_cursor (new Gdk.Cursor.from_name ("default", null));
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
			} else if (main_stack.visible_child_name != "term") {
				important_details = true;
				details_button.has_frame = true;
				details_button.add_css_class ("suggested-action");
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
				transaction.show_warnings.begin ();
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
					if (!database.is_installed_flatpak (pkg.id)) {
						flatpak_to_install.insert (pkg.id, pkg);
					}
				}
				foreach (unowned FlatpakPackage pkg in previous_flatpak_to_remove.get_values ()) {
					if (database.is_installed_flatpak (pkg.id)) {
						flatpak_to_remove.insert (pkg.id, pkg);
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
			transaction_running = false;
			generate_mirrors_list = false;
			refresh_details ();
			scroll_to_top = false;
			updates_checked = false;
			refresh_packages_list ();
		}
	}
}
