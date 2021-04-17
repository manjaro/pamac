/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2021 Guillaume Benoit <guillaume@manjaro.org>
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
	class ManagerWindow : Hdy.ApplicationWindow {
		// icons
		Gtk.IconTheme icon_theme;
		Gdk.Pixbuf? package_icon;

		// manager objects
		[GtkChild]
		unowned Hdy.HeaderBar headerbar;
		[GtkChild]
		public unowned Gtk.Stack main_stack;
		[GtkChild]
		unowned Gtk.Button button_back;
		[GtkChild]
		unowned Gtk.ListBox packages_listbox;
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
		unowned Hdy.Flap browse_flap;
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
		public unowned Gtk.Stack view_stack;
		[GtkChild]
		unowned Hdy.ViewSwitcherTitle view_stack_switcher;
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
		unowned Gtk.ComboBoxText sortby_combobox;
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
		unowned Gtk.ScrolledWindow details_scrolledwindow;
		[GtkChild]
		unowned Gtk.Stack properties_stack;
		[GtkChild]
		unowned Gtk.StackSwitcher properties_stack_switcher;
		[GtkChild]
		unowned Gtk.ScrolledWindow files_scrolledwindow;
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
		unowned Hdy.Carousel screenshots_carousel;
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
		unowned Gtk.Revealer infobox_revealer;

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
		public LocalConfig local_config;
		Soup.Session soup_session;

		bool important_details;
		bool transaction_running;
		public bool generate_mirrors_list;
		bool waiting;

		public bool enable_aur { get; private set; }
		bool updates_checked;
		GenericArray<AlpmPackage> repos_updates;
		GenericArray<AURPackage> aur_updates;
		GenericArray<FlatpakPackage> flatpak_updates;
		BackRow categories_backrow;
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
		GenericArray<Gtk.Image> current_screenshots;
		uint current_screenshots_index;
		uint screenshots_overlay_timeout_id;

		uint search_entry_timeout_id;
		bool scroll_to_top;
		uint in_app_notification_timeout_id;

		HashTable<string, SnapPackage> previous_snap_to_install;
		HashTable<string, SnapPackage> previous_snap_to_remove;
		HashTable<string, FlatpakPackage> previous_flatpak_to_install;
		HashTable<string, FlatpakPackage> previous_flatpak_to_remove;

		PreferencesWindow preferences_window;

		public ManagerWindow (Gtk.Application application, Database database) {
			Object (application: application, database: database);

			// load custom styling
			var css_provider = new Gtk.CssProvider ();
			css_provider.load_from_resource("/org/manjaro/pamac/manager/style.css");
			Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), css_provider, 500);

			unowned string? use_csd = Environment.get_variable ("GTK_CSD");
			if (use_csd == "0") {
				headerbar.set_show_close_button (false);
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

			updated_label.set_markup ("<big><b>%s</b></big>".printf (dgettext (null, "Your system is up-to-date")));
			no_item_label.set_markup ("<big><b>%s</b></big>".printf (dgettext (null, "No package found")));
			checking_label.set_markup ("<big><b>%s</b></big>".printf (dgettext (null, "Checking for Updates")));

			current_screenshots = new GenericArray<Gtk.Image> ();
			var screenshots_pointer_controller = new Gtk.EventControllerMotion (screenshots_carousel);
			screenshots_pointer_controller.enter.connect (on_screenshots_carousel_enter);
			screenshots_pointer_controller.leave.connect (on_screenshots_carousel_leave);

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
			application.set_accels_for_action ("app.quit", accels);
			// search action
			action = new SimpleAction ("search", null);
			action.activate.connect (() => {
				search_button.visible = false;
				view_stack_switcher.visible = false;
				button_back.visible = true;
				search_entry.visible = true;
				previous_view_stack_visible_child_name = view_stack.visible_child_name;
				view_stack.visible_child_name = "search";
				search_entry.grab_focus_without_selecting ();
				packages_stack.visible_child_name = "no_item";
			});
			this.add_action (action);
			application.set_accels_for_action ("win.search", {"<Ctrl>F"});
			// back action
			action = new SimpleAction ("back", null);
			action.activate.connect (() => {
				switch (main_stack.visible_child_name) {
					case "browse":
						button_back.visible = false;
						search_entry.visible = false;
						search_entry.set_text ("");
						search_string = null;
						view_stack.visible_child_name = previous_view_stack_visible_child_name;
						view_stack_switcher.visible = true;
						search_button.visible = true;
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
				if (main_stack.visible_child_name == "details") {
					refresh_details ();
				}
				refresh_packages_list ();
			});
			this.add_action (software_mode_action);
			// refresh databases action
			action = new SimpleAction ("refresh-databases", null);
			action.activate.connect (() => {
				run_sysupgrade (true, false);
			});
			this.add_action (action);
			// history action
			action = new SimpleAction ("history", null);
			action.activate.connect (() => {
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				var history_dialog = new HistoryDialog (this);
				this.get_window ().set_cursor (null);
				history_dialog.response.connect (() => {
					history_dialog.destroy ();
				});
				history_dialog.show ();
			});
			this.add_action (action);
			// install local action
			action = new SimpleAction ("install-local", null);
			action.activate.connect (() => {
				Gtk.FileChooserDialog chooser = new Gtk.FileChooserDialog (
					dgettext (null, "Install Local Packages"), this, Gtk.FileChooserAction.OPEN,
					dgettext (null, "_Cancel"), Gtk.ResponseType.CANCEL,
					dgettext (null, "_Open"),Gtk.ResponseType.ACCEPT);
				chooser.icon_name = "system-software-install";
				chooser.select_multiple = true;
				chooser.create_folders = false;
				Gtk.FileFilter package_filter = new Gtk.FileFilter ();
				package_filter.set_filter_name (dgettext (null, "Alpm Package"));
				package_filter.add_mime_type ("application/x-alpm-package");
				chooser.add_filter (package_filter);
				chooser.response.connect ((res) => {
					if (res == Gtk.ResponseType.ACCEPT) {
						SList<string> packages_paths = chooser.get_filenames ();
						if (packages_paths != null) {
							foreach (unowned string path in packages_paths) {
								to_load.add (path);
							}
							run_transaction ();
						}
					}
					chooser.destroy ();
				});
				chooser.show ();
			});
			this.add_action (action);
			// preferences action
			action = new SimpleAction ("preferences", null);
			action.activate.connect (() => {
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				transaction.get_authorization_async.begin ((obj, res) => {
					bool authorized = transaction.get_authorization_async.end (res);
					if (authorized) {
						if (preferences_window == null) {
							preferences_window = new PreferencesWindow (this, local_config);
							preferences_window.set_transient_for (this);
							preferences_window.delete_event.connect (() => {
								database.config.save ();
								preferences_window.hide ();
							transaction.remove_authorization ();
							check_aur_support ();
							check_snap_support ();
							check_flatpak_support ();
							if (main_stack.visible_child_name == "details") {
								refresh_details ();
							}
							refresh_packages_list ();
								return true;
							});
						}
						preferences_window.show ();
					} else {
						this.get_window ().set_cursor (null);
					}
				});
			});
			this.add_action (action);
			// about action
			action = new SimpleAction ("about", null);
			action.activate.connect (() => {
				string[] authors = {"Guillaume Benoit"};
				Gtk.show_about_dialog (
					this,
					"program_name", "Pamac",
					"icon_name", "system-software-install",
					"logo_icon_name", "system-software-install",
					"comments", dgettext (null, "A Package Manager with Alpm, AUR, Flatpak and Snap support"),
					"copyright", "Copyright © 2021 Guillaume Benoit",
					"authors", authors,
					"version", VERSION,
					"license_type", Gtk.License.GPL_3_0,
					"website", "https://gitlab.manjaro.org/applications/pamac");
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
				packages_listbox.foreach ((child) => {
					unowned PackageRow pamac_row = child as PackageRow;
					if (pamac_row == null) {
						return;
					}
					Package? pkg = pamac_row.pkg;
					if (pkg == null) {
						return;
					}
					set_row_app_icon (pamac_row, pkg);
				});
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
			transaction = new TransactionGtk (database, local_config, this.application);
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
			transaction_infobox.add (transaction.progress_box);
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
			view_stack.notify["visible-child"].connect (on_view_stack_visible_child_changed);
			browse_stack.notify["visible-child"].connect (on_browse_stack_visible_child_changed);
			properties_stack.notify["visible-child"].connect (on_properties_stack_visible_child_changed);

			// enable "type to search"
			this.key_press_event.connect ((event) => {
				if (main_stack.visible_child_name == "browse"
					&& (view_stack.visible_child_name == "browse"
					|| view_stack.visible_child_name == "search"
					|| view_stack.visible_child_name == "installed")) {
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

			// soup session to download icons and screenshots
			soup_session = new Soup.Session ();
			soup_session.user_agent = "Pamac/%s".printf (VERSION);
			soup_session.timeout = 30;

			// refresh flatpak appstream_data
			database.refresh_flatpak_appstream_data_async.begin ();
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
		bool on_window_delete_event () {
			if (transaction_running || generate_mirrors_list) {
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
				local_conf.insert ("software_mode", new Variant.boolean (local_config.software_mode));
				local_config.write (local_conf);
				// close window
				return false;
			}
		}

		void show_sidebar (bool visible) {
			if (visible) {
				browse_flap.fold_policy = Hdy.FlapFoldPolicy.AUTO;
			} else {
				browse_flap.fold_policy = Hdy.FlapFoldPolicy.ALWAYS;
			}
			reveal_sidebar_button.visible = visible;
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

		void set_pendings_operations () {
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
					if (!transaction_running && !generate_mirrors_list
						&& (to_update.length > 0)) {
						apply_button.sensitive = true;
						apply_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
					} else {
						apply_button.sensitive = false;
						apply_button.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
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
						apply_button.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
						infobox_revealer.reveal_child = false;
					} else {
						string info = dngettext (null, "%u pending operation", "%u pending operations", total_pending).printf (total_pending);
						transaction.progress_box.action_label.label = info;
						cancel_button.sensitive = true;
						apply_button.sensitive = true;
						apply_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
						infobox_revealer.reveal_child = true;
					}
				}
			}
		}

		void create_all_listbox () {
			categories_backrow = new BackRow ();
			categories_listbox.add (categories_backrow);
			foreach (unowned string name in database.get_categories_names ()) {
				categories_listbox.add (new SimpleRow (dgettext (null, name)));
			}
			categories_listbox.select_row (categories_listbox.get_row_at_index (1));

			repos_listbox.add (new BackRow ());
			repos_names = database.get_repos_names ();
			foreach (unowned string name in repos_names) {
				repos_listbox.add (new SimpleRow (name));
			}
			repos_listbox.select_row (repos_listbox.get_row_at_index (1));
			// use by sort_pkgs_by_repo
			repos_names.add (dgettext (null, "Snap"));
			foreach (unowned string name in database.get_flatpak_remotes_names ()) {
				repos_names.add (name);
			}
			repos_names.add (dgettext (null, "AUR"));

			groups_listbox.add (new BackRow ());
			foreach (unowned string name in database.get_groups_names ()) {
				groups_listbox.add (new SimpleRow (name));
			}
			groups_listbox.select_row (groups_listbox.get_row_at_index (1));

			var all_installed_row = new SimpleRow (dgettext (null, "All"));
			installed_snap_row = new SimpleRow (dgettext (null, "Snap"));
			installed_flatpak_row = new SimpleRow (dgettext (null, "Flatpak"));
			installed_listbox.add (all_installed_row);
			installed_listbox.add (new SimpleRow (dgettext (null, "Explicitly installed")));
			installed_listbox.add (new SimpleRow (dgettext (null, "Orphans")));
			installed_listbox.add (new SimpleRow (dgettext (null, "Foreign")));
			installed_listbox.add (installed_snap_row);
			installed_listbox.add (installed_flatpak_row);
			installed_listbox.select_row (all_installed_row);

			var all_search_row = new SimpleRow (dgettext (null, "All"));
			search_aur_row = new SimpleRow (dgettext (null, "AUR"));
			search_snap_row = new SimpleRow (dgettext (null, "Snap"));
			search_flatpak_row = new SimpleRow (dgettext (null, "Flatpak"));
			search_listbox.add (all_search_row);
			search_listbox.add (new SimpleRow (dgettext (null, "Installed")));
			search_listbox.add (new SimpleRow (dgettext (null, "Repositories")));
			search_listbox.add (search_aur_row);
			search_listbox.add (search_snap_row);
			search_listbox.add (search_flatpak_row);
			search_listbox.select_row (all_search_row);

			var all_updates_row = new SimpleRow (dgettext (null, "All"));
			updates_repos_row = new SimpleRow (dgettext (null, "Repositories"));
			updates_aur_row = new SimpleRow (dgettext (null, "AUR"));
			updates_flatpak_row = new SimpleRow (dgettext (null, "Flatpak"));
			updates_ignored_row = new SimpleRow (dgettext (null, "Ignored"));
			updates_listbox.add (all_updates_row);
			updates_listbox.add (updates_repos_row);
			updates_listbox.add (updates_aur_row);
			updates_listbox.add (updates_flatpak_row);
			updates_listbox.add (updates_ignored_row);
			updates_listbox.select_row (all_updates_row);
		}

		void clear_packages_listbox () {
			packages_listbox.foreach ((child) => {
				packages_listbox.remove (child);
			});
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

		Gtk.Widget populate_details_grid (string detail_type, string detail, Gtk.Widget? previous_widget) {
			var label = new Gtk.Label ("<b>%s:</b>".printf (detail_type));
			label.visible = true;
			label.use_markup = true;
			label.halign = Gtk.Align.START;
			label.valign = Gtk.Align.START;
			label.ellipsize = Pango.EllipsizeMode.END;
			details_grid.attach_next_to (label, previous_widget, Gtk.PositionType.BOTTOM);
			if (!transaction_running
				&& detail_type == dgettext (null, "Install Reason")
				&& detail == dgettext (null, "Installed as a dependency for another package")) {
				var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
				box.visible = true;
				box.homogeneous = false;
				var label2 = new Gtk.Label (detail);
				label2.visible = true;
				label2.halign = Gtk.Align.START;
				label2.ellipsize = Pango.EllipsizeMode.END;
				box.add (label2);
				var mark_explicit_button = new Gtk.Button.with_label (dgettext (null, "Mark as explicitly installed"));
				mark_explicit_button.visible = true;
				mark_explicit_button.halign = Gtk.Align.START;
				mark_explicit_button.margin_bottom = 6;
				mark_explicit_button.clicked.connect (on_mark_explicit_button_clicked);
				var scrolledwindow = new Gtk.ScrolledWindow (null, null);
				scrolledwindow.visible = true;
				scrolledwindow.vscrollbar_policy = Gtk.PolicyType.NEVER;
				scrolledwindow.add (mark_explicit_button);
				box.add (scrolledwindow);
				details_grid.attach_next_to (box, label, Gtk.PositionType.RIGHT);
			} else {
				var label2 = new Gtk.Label (detail);
				label2.visible = true;
				label2.use_markup = true;
				label2.halign = Gtk.Align.START;
				label2.ellipsize = Pango.EllipsizeMode.END;
				details_grid.attach_next_to (label2, label, Gtk.PositionType.RIGHT);
			}
			return label as Gtk.Widget;
		}

		string find_install_button_dep_name (Gtk.Button button, out Gtk.Image select_image) {
			string dep_name = "";
			select_image = null;
			List<unowned Gtk.Widget> list = button.get_parent ().get_children ();
			foreach (unowned Gtk.Widget widget in list) {
				if (widget.name == "GtkLabel") {
					unowned Gtk.Label dep_label = widget as Gtk.Label;
					if (database.has_sync_satisfier (dep_label.label)) {
						AlpmPackage pkg = database.get_sync_satisfier (dep_label.label);
						dep_name = pkg.name;
					}
				}
				if (widget.name == "GtkImage") {
					unowned Gtk.Image image = widget as Gtk.Image;
					select_image = image;
				}
			}
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
			set_pendings_operations ();
		}

		[GtkCallback]
		void on_next_screenshot_button_clicked () {
			unowned Gtk.Image image = current_screenshots[current_screenshots_index + 1];
			screenshots_carousel.scroll_to (image);
		}

		[GtkCallback]
		void on_previous_screenshot_button_clicked () {
			unowned Gtk.Image image = current_screenshots[current_screenshots_index - 1];
			screenshots_carousel.scroll_to (image);
		}

		[GtkCallback]
		void on_screenshots_carousel_page_changed (uint index) {
			current_screenshots_index = index;
			previous_screenshot_button.visible = current_screenshots_index > 0;
			next_screenshot_button.visible = current_screenshots_index < current_screenshots.length - 1;
		}

		bool remove_screenshots_overlay_timeout () {
			if (screenshots_overlay_timeout_id != 0) {
				Source.remove (screenshots_overlay_timeout_id);
				screenshots_overlay_timeout_id = 0;
				return true;
			}
			return false;
		}

		void on_screenshots_carousel_enter () {
			if (!remove_screenshots_overlay_timeout ()) {
				previous_screenshot_button.visible = current_screenshots_index > 0;
				next_screenshot_button.visible = current_screenshots_index < current_screenshots.length - 1;
			}
		}

		void on_screenshots_carousel_leave () {
			screenshots_overlay_timeout_id = Timeout.add (1000, screenshots_overlay_timeout_callback);
		}

		bool screenshots_overlay_timeout_callback () {
			previous_screenshot_button.visible = false;
			next_screenshot_button.visible = false;
			screenshots_overlay_timeout_id = 0;
			return false;
		}

		void populate_deps_box (string dep_type, GenericArray<string> dep_list, bool add_install_button = false) {
			var label = new Gtk.Label ("<b>%s:</b>".printf (dep_type));
			label.visible = true;
			label.use_markup = true;
			label.halign = Gtk.Align.START;
			label.ellipsize = Pango.EllipsizeMode.END;
			label.margin_top = 12;
			deps_box.add (label);
			var listbox = new Gtk.ListBox ();
			listbox.visible = true;
			listbox.get_style_context ().add_class ("content");
			foreach (unowned string dep in dep_list) {
				if (add_install_button) {
					var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 3);
					box.visible = true;
					var dep_label = new Gtk.Label (dep);
					dep_label.visible = true;
					dep_label.margin_top = 12;
					dep_label.margin_bottom = 12;
					dep_label.margin_start = 12;
					dep_label.margin_end = 12;
					dep_label.halign = Gtk.Align.START;
					dep_label.hexpand = true;
					dep_label.ellipsize = Pango.EllipsizeMode.END;
					box.add (dep_label);
					if (!database.has_installed_satisfier (dep)) {
						var select_image = new Gtk.Image.from_icon_name ("object-select-symbolic", Gtk.IconSize.BUTTON);
						select_image.visible = true;
						select_image.pixel_size = 16;
						select_image.visible = false;
						box.add (select_image);
						var install_dep_button = new Gtk.ToggleButton ();
						install_dep_button.visible = true;
						install_dep_button.image = new Gtk.Image.from_icon_name ("document-save-symbolic", Gtk.IconSize.BUTTON);
						install_dep_button.margin_start = 19;
						install_dep_button.margin_end = 12;
						install_dep_button.valign = Gtk.Align.CENTER;
						install_dep_button.toggled.connect (on_install_dep_button_toggled);
						box.add (install_dep_button);
						string dep_name = find_install_button_dep_name (install_dep_button, null);
						install_dep_button.active = (dep_name in to_install);
					}
					listbox.add (box);
				} else {
					var dep_label = new Gtk.Label (dep);
					dep_label.visible = true;
					dep_label.margin_top = 12;
					dep_label.margin_bottom = 12;
					dep_label.margin_start = 12;
					dep_label.margin_end = 12;
					dep_label.halign = Gtk.Align.START;
					dep_label.ellipsize = Pango.EllipsizeMode.END;
					listbox.add (dep_label);
				}
			}
			listbox.row_activated.connect (on_deps_listbox_row_activated);
			deps_box.add (listbox);
		}

		async void get_screenshots_images (GenericArray<string> urls) {
			// keep a copy of urls because of async
			GenericArray<string> urls_copy = urls.copy (strdup);
			foreach (unowned string url in urls_copy) {
				Gtk.Image image = null;
				var uri = File.new_for_uri (url);
				var cached_screenshot = File.new_for_path ("/tmp/pamac-app-screenshots/%s".printf (uri.get_basename ()));
				if (cached_screenshot.query_exists ()) {
					image = new Gtk.Image.from_file (cached_screenshot.get_path ());
					image.visible = true;
				} else {
					// download screenshot
					try {
						var request = soup_session.request (url);
						var inputstream = yield request.send_async (null);
						var pixbuf = yield new Gdk.Pixbuf.from_stream_at_scale_async (inputstream, -1, 300, true);
						// save scaled image in tmp
						FileOutputStream os = cached_screenshot.append_to (FileCreateFlags.NONE);
						pixbuf.save_to_stream (os, "png");
						image = new Gtk.Image.from_pixbuf (pixbuf);
						image.visible = true;
					} catch (Error e) {
						warning ("%s: %s", url, e.message);
					}
				}
				// add images when they are ready
				if (image != null) {
					current_screenshots.add (image);
					screenshots_carousel.add (image);
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
			deps_box.foreach ((child) => {
				deps_box.remove (child);
			});
		}

		void clear_screenshots_carousel () {
			screenshots_carousel.foreach ((child) => {
				screenshots_carousel.remove (child);
			});
		}

		void set_screenshots (Package pkg) {
			remove_screenshots_overlay_timeout ();
			screenshots_box.visible = false;
			previous_screenshot_button.visible = false;
			next_screenshot_button.visible = false;
			current_screenshots_index = 0;
			current_screenshots = new GenericArray<Gtk.Image> ();
			unowned GenericArray<string> urls = pkg.screenshots;
			if (urls.length != 0) {
				screenshots_box.visible = true;
				get_screenshots_images.begin (urls);
			}
		}

		void set_package_details (AlpmPackage pkg, AURPackage? aur_pkg) {
			// download screenshot
			clear_screenshots_carousel ();
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
			clear_details_grid ();
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
					label.visible = true;
					label.use_markup = true;
					label.halign = Gtk.Align.START;
					label.valign = Gtk.Align.START;
					label.ellipsize = Pango.EllipsizeMode.END;
					details_grid.attach_next_to (label, previous_widget, Gtk.PositionType.BOTTOM);
					var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
					box.visible = true;
					foreach (unowned string name in pkg.groups) {
						var label2 = new Gtk.Label (name);
						label2.visible = true;
						label2.halign = Gtk.Align.START;
						label2.ellipsize = Pango.EllipsizeMode.END;
						box.add (label2);
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
					label.visible = true;
					label.use_markup = true;
					label.halign = Gtk.Align.START;
					label.valign = Gtk.Align.START;
					label.ellipsize = Pango.EllipsizeMode.END;
					details_grid.attach_next_to (label, previous_widget, Gtk.PositionType.BOTTOM);
					var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
					box.visible = true;
					foreach (unowned string name in pkg.backups) {
						var label2 = new Gtk.Label (name);
						label2.visible = true;
						label2.halign = Gtk.Align.START;
						label2.ellipsize = Pango.EllipsizeMode.END;
						box.add (label2);
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
			clear_screenshots_carousel ();
			screenshots_box.visible = false;
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
			if (view_stack.visible_child_name == "updates") {
				build_togglebutton.visible = false;
				remove_togglebutton.visible = false;
			} else {
				build_togglebutton.visible = true;
				build_togglebutton.active = to_build.contains (aur_pkg.name);
				if (database.is_installed_pkg (aur_pkg.name)) {
					remove_togglebutton.visible = true;
					remove_togglebutton.active = to_remove.contains (aur_pkg.name);
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
				label.visible = true;
				label.use_markup = true;
				label.halign = Gtk.Align.START;
				label.valign = Gtk.Align.START;
				label.ellipsize = Pango.EllipsizeMode.END;
				details_grid.attach_next_to (label, previous_widget, Gtk.PositionType.BOTTOM);
				var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
				box.visible = true;
				foreach (unowned string name in aur_pkg.backups) {
					var label2 = new Gtk.Label (name);
					label2.visible = true;
					label2.halign = Gtk.Align.START;
					label2.ellipsize = Pango.EllipsizeMode.END;
					box.add (label2);
				}
				details_grid.attach_next_to (box, label, Gtk.PositionType.RIGHT);
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
			// download screenshot
			clear_screenshots_carousel ();
			set_screenshots (snap_pkg);
			// infos
			name_label.set_markup ("<big><b>%s  %s</b></big>".printf (Markup.escape_text (snap_pkg.app_name), snap_pkg.version));
			unowned string? icon = snap_pkg.icon;
			if (icon != null) {
				if ("http" in icon) {
					app_image.pixbuf = package_icon;
					transaction.get_icon_pixbuf.begin (icon, (obj, res) => {
						app_image.pixbuf = transaction.get_icon_pixbuf.end (res);
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
			if (snap_pkg.install_date != 0) {
				var time = GLib.Time.local ((time_t) snap_pkg.install_date);
				previous_widget = populate_details_grid (dgettext (null, "Install Date"), time.format ("%x"), previous_widget);
				if (snap_pkg.channels.length != 0) {
					var label = new Gtk.Label ("<b>%s</b>".printf (dgettext (null, "Channels") + ":"));
					label.visible = true;
					label.use_markup = true;
					label.halign = Gtk.Align.START;
					label.valign = Gtk.Align.START;
					label.ellipsize = Pango.EllipsizeMode.END;
					details_grid.attach_next_to (label, previous_widget, Gtk.PositionType.BOTTOM);
					var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
					box.visible = true;
					foreach (unowned string channel in snap_pkg.channels) {
						string[] split = channel.split (" : ", 2);
						string channel_name = split[0];
						if (snap_pkg.channel != channel_name) {
							var box2 = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
							box2.visible = true;
							box2.homogeneous = false;
							var label2 = new Gtk.Label (channel);
							label2.visible = true;
							label2.halign = Gtk.Align.START;
							label2.ellipsize = Pango.EllipsizeMode.END;
							box2.add (label2);
							var install_button = new Gtk.Button.with_label (dgettext (null, "Install"));
							install_button.visible = true;
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
							box2.add (install_button);
							box.add (box2);
						} else {
							var label2 = new Gtk.Label (channel);
							label2.visible = true;
							label2.halign = Gtk.Align.START;
							label2.ellipsize = Pango.EllipsizeMode.END;
							box.add (label2);
						}
					}
					details_grid.attach_next_to (box, label, Gtk.PositionType.RIGHT);
				}
			}
			// deps
			clear_deps_box ();
		}

		void set_flatpak_details (FlatpakPackage flatpak_pkg) {
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
				if (current_package_displayed is SnapPackage) {
					snap_to_install.insert (current_package_displayed.name, current_package_displayed as SnapPackage);
				} else if (current_package_displayed is FlatpakPackage) {
					flatpak_to_install.insert (current_package_displayed.name, current_package_displayed as FlatpakPackage);
				} else {
					to_install.add (current_package_displayed.name);
				}
			} else {
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
				to_build.add (current_package_displayed.name);
				if (properties_stack.visible_child_name == "build_files") {
					transaction.save_build_files_async.begin (current_package_displayed.name);
				}
			} else {
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
				if (current_package_displayed is SnapPackage) {
					snap_to_install.remove (current_package_displayed.name);
					snap_to_remove.insert (current_package_displayed.name, current_package_displayed as SnapPackage);
				} else if (current_package_displayed is FlatpakPackage) {
					flatpak_to_install.remove (current_package_displayed.name);
					if (current_package_displayed.name in to_update) {
						to_update.remove (current_package_displayed.name);
						temporary_ignorepkgs.add (current_package_displayed.name);
					}
					flatpak_to_remove.insert (current_package_displayed.name, current_package_displayed as FlatpakPackage);
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
					flatpak_to_remove.remove (current_package_displayed.name);
				} else {
					if (current_package_displayed.name in temporary_ignorepkgs) {
						to_update.add (current_package_displayed.name);
						temporary_ignorepkgs.remove (current_package_displayed.name);
					}
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
			set_pendings_operations ();
			refresh_listbox_buttons ();
		}

		void populate_listbox () {
			// populate listbox
			if (current_packages_list_length == 0) {
				packages_stack.visible_child_name = "no_item";
				this.get_window ().set_cursor (null);
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
			// scroll to top
			if (scroll_to_top) {
				packages_scrolledwindow.vadjustment.value = 0;
			} else {
				// don't scroll to top just once
				scroll_to_top = true;
			}
			this.get_window ().set_cursor (null);
		}

		void sort_aur_list (ref GenericArray<unowned Package> pkgs) {
			int index = sortby_combobox.active;
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
			int index = sortby_combobox.active;
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

		void set_row_app_icon (PackageRow row, Package pkg) {
			Gdk.Pixbuf pixbuf;
			unowned string? icon = pkg.icon;
			if (icon != null) {
				if ("http" in icon) {
					pixbuf = package_icon;
					transaction.get_icon_pixbuf.begin (icon, (obj, res) => {
						var downloaded_pixbuf = transaction.get_icon_pixbuf.end (res);
						if (downloaded_pixbuf != null) {
							row.app_icon.pixbuf = downloaded_pixbuf.scale_simple (64, 64, Gdk.InterpType.BILINEAR);
						}
					});
				} else {
					try {
						pixbuf = new Gdk.Pixbuf.from_file_at_scale (icon, 64, 64, true);
					} catch (Error e) {
						if (pkg is SnapPackage && pkg.installed_version != null) {
							pixbuf = package_icon;
							// try to retrieve icon
							database.get_installed_snap_icon_async.begin (pkg.name, (obj, res) => {
								string downloaded_pixbuf_path = database.get_installed_snap_icon_async.end (res);
								try {
									pixbuf = new Gdk.Pixbuf.from_file_at_scale (downloaded_pixbuf_path, 64, 64, true);
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
								pixbuf = new Gdk.Pixbuf.from_file_at_scale (new_icon, 64, 64, true);
							} catch (Error e) {
								pixbuf = package_icon;
								warning ("%s: %s", icon, e.message);
							}
						}
					}
				}
			} else {
				pixbuf = package_icon;
			}
			row.app_icon.pixbuf = pixbuf;
		}

		PackageRow create_packagelist_row (Package pkg) {
			bool is_update = view_stack.visible_child_name == "updates";
			var row = new PackageRow (pkg);
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
					row.version_label.label = pkg.version;
				} else {
					row.version_label.label = pkg.version;
					row.old_version_label.label = pkg.installed_version;
					row.old_version_label.visible = true;
				}
				if (pkg.download_size > 0) {
					row.size_label.label = GLib.format_size (pkg.download_size);
				}
			} else {
				if (software_mode) {
					row.version_label.visible = false;
				} else {
					row.version_label.label = pkg.version;
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
				row.action_togglebutton.image = new Gtk.Image.from_icon_name ("emblem-synchronizing-symbolic", Gtk.IconSize.BUTTON);
				if (!(pkg.name in temporary_ignorepkgs)) {
					row.action_togglebutton.active = true;
					row.action_togglebutton.margin_start = 0;
					row.action_icon.visible = true;
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
					updates_ignored_row.visible = temporary_ignorepkgs.length > 0;
					refresh_listbox_buttons ();
					set_pendings_operations ();
				});
			} else if (pkg.installed_version == null) {
				if (pkg is AURPackage) {
					row.action_togglebutton.image = new Gtk.Image.from_icon_name ("document-save-symbolic", Gtk.IconSize.BUTTON);
					if (pkg.name in to_build) {
						row.action_togglebutton.active = true;
						row.action_togglebutton.margin_start = 0;
						row.action_icon.visible = true;
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
					row.action_togglebutton.image = new Gtk.Image.from_icon_name ("document-save-symbolic", Gtk.IconSize.BUTTON);
					if (pkg.name in snap_to_install) {
						row.action_togglebutton.active = true;
						row.action_togglebutton.margin_start = 0;
						row.action_icon.visible = true;
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
					row.action_togglebutton.image = new Gtk.Image.from_icon_name ("document-save-symbolic", Gtk.IconSize.BUTTON);
					if (pkg.name in flatpak_to_install) {
						row.action_togglebutton.active = true;
						row.action_togglebutton.margin_start = 0;
						row.action_icon.visible = true;
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
					row.action_togglebutton.image = new Gtk.Image.from_icon_name ("document-save-symbolic", Gtk.IconSize.BUTTON);
					if (pkg.name in to_install) {
						row.action_togglebutton.active = true;
						row.action_togglebutton.margin_start = 0;
						row.action_icon.visible = true;
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
				row.action_togglebutton.image = new Gtk.Image.from_icon_name ("user-trash-symbolic", Gtk.IconSize.BUTTON);
				if (pkg.name in snap_to_remove) {
					row.action_togglebutton.active = true;
					row.action_togglebutton.margin_start = 0;
					row.action_icon.visible = true;
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
				row.action_togglebutton.image = new Gtk.Image.from_icon_name ("user-trash-symbolic", Gtk.IconSize.BUTTON);
				if (pkg.name in flatpak_to_remove) {
					row.action_togglebutton.active = true;
					row.action_togglebutton.margin_start = 0;
					row.action_icon.visible = true;
				}
				row.action_togglebutton.toggled.connect ((button) => {
					if (button.active) {
						if (pkg.name in to_update) {
							to_update.remove (pkg.name);
							temporary_ignorepkgs.add (pkg.name);
						}
						flatpak_to_remove.insert (pkg.name, pkg as FlatpakPackage);
					} else {
						if (pkg.name in temporary_ignorepkgs) {
							to_update.add (pkg.name);
							temporary_ignorepkgs.remove (pkg.name);
						}
						flatpak_to_remove.remove (pkg.name);
					}
					refresh_listbox_buttons ();
					set_pendings_operations ();
				});
			} else {
				row.action_togglebutton.image = new Gtk.Image.from_icon_name ("user-trash-symbolic", Gtk.IconSize.BUTTON);
				if (database.should_hold (pkg.name)) {
					row.action_togglebutton.sensitive = false;
				} else if (pkg.name in to_remove) {
					row.action_togglebutton.active = true;
					row.action_togglebutton.margin_start = 0;
					row.action_icon.visible = true;
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
					set_pendings_operations ();
				});
			}
			return row;
		}

		void create_os_updates_row (uint64 download_size) {
			var row = new PackageRow (null);
			// populate info
			row.name_label.label = dgettext (null, "OS Updates");
			row.desc_label.label = dgettext (null, "Includes performance, stability and security improvements");
			row.version_label.visible = false;
			if (download_size > 0) {
				row.size_label.label = GLib.format_size (download_size);
			}
			row.repo_label.label = dgettext (null, "Official Repositories");
			row.app_icon.pixbuf = package_icon;
			row.action_togglebutton.image = new Gtk.Image.from_icon_name ("emblem-synchronizing-symbolic", Gtk.IconSize.BUTTON);
			row.action_togglebutton.active = true;
			row.action_togglebutton.margin_start = 0;
			row.action_icon.visible = true;
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
			set_row_app_icon (row, pkg);
			if (transaction.transaction_summary_contains (pkg.id)) {
				row.action_togglebutton.sensitive = false;
			}
			row.action_togglebutton.image = new Gtk.Image.from_icon_name ("emblem-synchronizing-symbolic", Gtk.IconSize.BUTTON);
			if (!(pkg.name in temporary_ignorepkgs)) {
				row.action_togglebutton.active = true;
				row.action_togglebutton.margin_start = 0;
				row.action_icon.visible = true;
			}
			row.action_togglebutton.toggled.connect ((button) => {
				if (button.active) {
					row.action_togglebutton.active = true;
					row.action_togglebutton.margin_start = 0;
					row.action_icon.visible = true;
					to_update.add (pkg.name);
					temporary_ignorepkgs.remove (pkg.name);
					// remove from config.ignorepkgs to override config
					database.config.ignorepkgs.remove (pkg.name);
				} else {
					row.action_togglebutton.active = false;
					row.action_togglebutton.margin_start = 19;
					row.action_icon.visible = false;
					to_update.remove (pkg.name);
					temporary_ignorepkgs.add (pkg.name);
				}
				set_pendings_operations ();
			});
			return row;
		}

		void refresh_listbox_buttons () {
			packages_listbox.foreach ((child) => {
				unowned PackageRow pamac_row = child as PackageRow;
				if (pamac_row == null) {
					return;
				}
				Package? pkg = pamac_row.pkg;
				if (pkg == null) {
					return;
				}
				if (transaction.transaction_summary_contains (pkg.id)) {
					pamac_row.action_togglebutton.active = false;
					pamac_row.action_togglebutton.margin_start = 19;
					pamac_row.action_icon.visible = false;
					pamac_row.action_togglebutton.sensitive = false;
					return;
				}
				if (!database.should_hold (pkg.name)) {
					pamac_row.action_togglebutton.sensitive = true;
					pamac_row.action_togglebutton.margin_start = 0;
					pamac_row.action_icon.visible = true;
				}
				if (pkg is AURPackage) {
					if (pkg.name in to_build ||
						pkg.name in to_remove ||
						pkg.name in to_update) {
						pamac_row.action_togglebutton.active = true;
						pamac_row.action_togglebutton.margin_start = 0;
						pamac_row.action_icon.visible = true;
					} else {
						pamac_row.action_togglebutton.active = false;
						pamac_row.action_togglebutton.margin_start = 19;
						pamac_row.action_icon.visible = false;
					}
				} else if (pkg is SnapPackage) {
					if (pkg.name in snap_to_install ||
						pkg.name in snap_to_remove) {
						pamac_row.action_togglebutton.active = true;
						pamac_row.action_togglebutton.margin_start = 0;
						pamac_row.action_icon.visible = true;
					} else {
						pamac_row.action_togglebutton.active = false;
						pamac_row.action_togglebutton.margin_start = 19;
						pamac_row.action_icon.visible = false;
					}
				} else if (pkg is FlatpakPackage) {
					if (pkg.name in flatpak_to_install ||
						pkg.name in flatpak_to_remove ||
						pkg.name in to_update) {
						pamac_row.action_togglebutton.active = true;
						pamac_row.action_togglebutton.margin_start = 0;
						pamac_row.action_icon.visible = true;
					} else {
						pamac_row.action_togglebutton.active = false;
						pamac_row.action_togglebutton.margin_start = 19;
						pamac_row.action_icon.visible = false;
					}
				} else if (pkg is AlpmPackage){
					if (pkg.installed_version == null) {
						if (pkg.name in to_install) {
							pamac_row.action_togglebutton.active = true;
							pamac_row.action_togglebutton.margin_start = 0;
							pamac_row.action_icon.visible = true;
						} else {
							pamac_row.action_togglebutton.active = false;
							pamac_row.action_togglebutton.margin_start = 19;
							pamac_row.action_icon.visible = false;
						}
					} else if (view_stack.visible_child_name == "updates") {
						if (pkg.name in to_update) {
							pamac_row.action_togglebutton.active = true;
							pamac_row.action_togglebutton.margin_start = 0;
							pamac_row.action_icon.visible = true;
						} else {
							pamac_row.action_togglebutton.active = false;
							pamac_row.action_togglebutton.margin_start = 19;
							pamac_row.action_icon.visible = false;
						}
					} else if (pkg.name in to_remove) {
						pamac_row.action_togglebutton.active = true;
						pamac_row.action_togglebutton.margin_start = 0;
						pamac_row.action_icon.visible = true;
					} else {
						pamac_row.action_togglebutton.active = false;
						pamac_row.action_togglebutton.margin_start = 19;
						pamac_row.action_icon.visible = false;
					}
				}
			});
		}

		public void refresh_packages_list () {
			switch (view_stack.visible_child_name) {
				case "browse":
					show_sidebar (true);
					search_button.visible = main_stack.visible_child_name == "browse";
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
					set_pendings_operations ();
					break;
				case "installed":
					show_sidebar (!local_config.software_mode);
					search_button.visible = main_stack.visible_child_name == "browse";
					on_installed_listbox_row_activated (installed_listbox.get_selected_row ());
					set_pendings_operations ();
					break;
				case "search":
					show_sidebar (!local_config.software_mode);
					on_search_listbox_row_activated (search_listbox.get_selected_row ());
					set_pendings_operations ();
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
						on_refresh_button_clicked ();
					}
					break;
				default:
					break;
			}
			// old pending code
//~ 			if (view_stack.visible_child_name == "pending") {
//~ 				remove_all_button.visible = false;
//~ 				install_all_button.visible = false;
//~ 				ignore_all_button.visible = false;
//~ 				if (local_config.software_mode) {
//~ 				} else {
//~ 					view_installed_button.visible = false;
//~ 					view_explicitly_installed_button.visible = false;
//~ 					view_orphans_button.visible = false;
//~ 					view_foreign_button.visible = false;
//~ 					view_repositories_button.visible = true;
//~ 					if ((to_install.length + to_remove.length) > 0) {
//~ 						view_repositories_button.sensitive = true;
//~ 					} else {
//~ 						view_repositories_button.sensitive = false;
//~ 					}
//~ 					view_aur_button.visible = enable_aur;
//~ 					if (to_build.length > 0) {
//~ 						view_aur_button.sensitive = true;
//~ 					} else {
//~ 						view_aur_button.sensitive = false;
//~ 					}
//~ 					if (database.config.enable_snap) {
//~ 						view_snap_button.visible = true;
//~ 						if ((snap_to_install.length + snap_to_remove.length) > 0) {
//~ 							view_snap_button.sensitive = true;
//~ 						} else {
//~ 							view_snap_button.sensitive = false;
//~ 						}
//~ 					} else {
//~ 						view_snap_button.visible = false;
//~ 					}
//~ 					if (database.config.enable_flatpak) {
//~ 						view_flatpak_button.visible = true;
//~ 						if ((flatpak_to_install.length + flatpak_to_remove.length) > 0) {
//~ 							view_flatpak_button.sensitive = true;
//~ 						} else {
//~ 							view_flatpak_button.sensitive = false;
//~ 						}
//~ 					} else {
//~ 						view_flatpak_button.visible = false;
//~ 					}
//~ 				}
//~ 				browse_head_box.visible = true;
//~ 				browse_separator.visible = true;
//~ 				unowned string filter = view_button_label.label;
//~ 				if (filter == dgettext (null, "All")) {
//~ 					on_view_all_button_clicked ();
//~ 				} else if (filter == dgettext (null, "Repositories")) {
//~ 					on_view_repositories_button_clicked ();
//~ 				} else if (filter == dgettext (null, "AUR")) {
//~ 					on_view_aur_button_clicked ();
//~ 				} else if (filter == dgettext (null, "Snap")) {
//~ 					on_view_snap_button_clicked ();
//~ 				} else if (filter == dgettext (null, "Flatpak")) {
//~ 					on_view_flatpak_button_clicked ();
//~ 				}
//~ 			}
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
			files_scrolledwindow.visible = true;
			build_files_box.visible = aur_pkg != null;
			properties_stack_switcher.visible = !local_config.software_mode;
			set_package_details (pkg, aur_pkg);
		}

		void display_aur_details (AURPackage aur_pkg) {
			current_package_displayed = aur_pkg;
			// select details if files was selected
			if (properties_stack.visible_child_name == "files") {
				properties_stack.visible_child_name = "details";
			}
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
				if (pamac_row.name_label.label == dgettext (null, "OS Updates")) {
					var updates_dialog = new UpdatesDialog (this);
					updates_dialog.label.label = dgettext (null, "Includes performance, stability and security improvements");
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
			row.foreach ((child) => {
				var dep_label = child as Gtk.Label;
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

//~ 		async GenericArray<unowned AURPackage> get_pendings_aur_pkgs () {
//~ 			var aur_pkgs = new GenericArray<unowned AURPackage> ();
//~ 			var to_build_array = new GenericArray<string> (to_build.length);
//~ 			foreach (unowned string name in to_build)  {
//~ 				to_build_array.add (name);
//~ 			}
//~ 			var table = yield database.get_aur_pkgs_async (to_build_array.data);
//~ 			var iter = HashTableIter<string, unowned AURPackage?> (table);
//~ 			unowned AURPackage? aur_pkg;
//~ 			while (iter.next (null, out aur_pkg)) {
//~ 				if (aur_pkg != null) {
//~ 					aur_pkgs.add (aur_pkg);
//~ 				}
//~ 			}
//~ 			return aur_pkgs;
//~ 		}

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

		bool search_entry_timeout_callback () {
			string tmp_search_string = search_entry.get_text ().strip ();
			if (tmp_search_string.char_count () > 1) {
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				search_string = (owned) tmp_search_string;
				view_stack.visible_child_name = "search";
				refresh_packages_list ();
			}
			search_entry_timeout_id = 0;
			return false;
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
				search_button.clicked ();
			}
			if (search_entry_timeout_id != 0) {
				Source.remove (search_entry_timeout_id);
			}
			search_entry_timeout_id = Timeout.add (300, search_entry_timeout_callback);
		}

		[GtkCallback]
		void on_sortby_combobox_changed () {
			int index = sortby_combobox.active;
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
			}
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			current_packages_list_name = "category_%s".printf (category);
			get_category_pkgs.begin (category, (obj, res) => {
				var pkgs = get_category_pkgs.end (res);
				if (view_stack.visible_child_name == "browse" && current_packages_list_name == "category_%s".printf (category)) {
					populate_packages_list (pkgs);
				} else {
					this.get_window ().set_cursor (null);
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
				browse_stack.visible_child_name = "filters";
				return;
			}
			var simple_row = row as SimpleRow;
			if (simple_row == null) {
				return;
			}
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
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
					populate_packages_list (pkgs);
				} else {
					this.get_window ().set_cursor (null);
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
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			int index = row.get_index ();
			switch (index) {
				case 0: // all
					current_packages_list_name = "installed_all";
					get_all_installed.begin ((obj, res) => {
						var pkgs = get_all_installed.end (res);
						if (view_stack.visible_child_name == "installed" && current_packages_list_name == "installed_all") {
							populate_packages_list (pkgs);
						} else {
							this.get_window ().set_cursor (null);
						}
					});
					break;
				case 1: // explicitly installed
					current_packages_list_name = "explicitly_installed";
					database.get_explicitly_installed_pkgs_async.begin ((obj, res) => {
						var pkgs = database.get_explicitly_installed_pkgs_async.end (res);
						if (view_stack.visible_child_name == "installed" && current_packages_list_name == "explicitly_installed") {
							populate_packages_list (pkgs);
						} else {
							this.get_window ().set_cursor (null);
						}
					});
					break;
				case 2: // orphans
					current_packages_list_name = "orphans";
					database.get_orphans_async.begin ((obj, res) => {
						var pkgs = database.get_orphans_async.end (res);
						if (view_stack.visible_child_name == "installed" && current_packages_list_name == "orphans") {
							populate_packages_list (pkgs);
							remove_all_button.visible = pkgs.length > 0;
						} else {
							this.get_window ().set_cursor (null);
						}
					});
					break;
				case 3: // foreign
					current_packages_list_name = "foreign";
					database.get_foreign_pkgs_async.begin ((obj, res) => {
						var pkgs = database.get_foreign_pkgs_async.end (res);
						if (view_stack.visible_child_name == "installed" && current_packages_list_name == "foreign") {
							populate_packages_list (pkgs);
						} else {
							this.get_window ().set_cursor (null);
						}
					});
					break;
				case 4: // Snap or Flatpak
				case 5:
					var simple_row = row as SimpleRow;
					if (simple_row == null) {
						this.get_window ().set_cursor (null);
						return;
					}
					unowned string title = simple_row.title;
					if (title == dgettext (null, "Snap")) {
						current_packages_list_name = "installed_snaps";
						database.get_installed_snaps_async.begin ((obj, res) => {
							var pkgs = database.get_installed_snaps_async.end (res);
							if (view_stack.visible_child_name == "installed" && current_packages_list_name == "installed_snaps") {
								populate_packages_list (pkgs);
							} else {
								this.get_window ().set_cursor (null);
							}
						});
					} else if (title == dgettext (null, "Flatpak")) {
						current_packages_list_name = "installed_flatpaks";
						database.get_installed_flatpaks_async.begin ((obj, res) => {
							var pkgs = database.get_installed_flatpaks_async.end (res);
							if (view_stack.visible_child_name == "installed" && current_packages_list_name == "installed_flatpaks") {
								populate_packages_list (pkgs);
							} else {
								this.get_window ().set_cursor (null);
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
			search_entry.grab_focus_without_selecting ();
			if (search_string == null) {
				return;
			}
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			int index = row.get_index ();
			switch (index) {
				case 0: // all
					current_packages_list_name = "search_all_%s".printf (search_string);
					search_all_pkgs.begin ((obj, res) => {
						var pkgs = search_all_pkgs.end (res);
						if (view_stack.visible_child_name == "search" && current_packages_list_name == "search_all_%s".printf (search_string)) {
							populate_packages_list (pkgs);
						} else {
							this.get_window ().set_cursor (null);
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
							this.get_window ().set_cursor (null);
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
							this.get_window ().set_cursor (null);
						}
					});
					break;
				case 3: // AUR or Snap or Flatpak
				case 4:
				case 5:
					var simple_row = row as SimpleRow;
					if (simple_row == null) {
						this.get_window ().set_cursor (null);
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
								this.get_window ().set_cursor (null);
							}
						});
					} else if (title == dgettext (null, "Snap")) {
						current_packages_list_name = "search_snap_%s".printf (search_string);
						database.search_snaps_async.begin (search_string, (obj, res) => {
							if (view_stack.visible_child_name == "search" && current_packages_list_name == "search_snap_%s".printf (search_string)) {
								var pkgs = database.search_snaps_async.end (res);
								populate_packages_list (pkgs);
							} else {
								this.get_window ().set_cursor (null);
							}
						});
					} else if (title == dgettext (null, "Flatpak")) {
						current_packages_list_name = "search_flatpak_%s".printf (search_string);
						database.search_flatpaks_async.begin (search_string, (obj, res) => {
							if (view_stack.visible_child_name == "search" && current_packages_list_name == "search_flatpak_%s".printf (search_string)) {
								var pkgs = database.search_flatpaks_async.end (res);
								populate_packages_list (pkgs);
							} else {
								this.get_window ().set_cursor (null);
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
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
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
						populate_packages_list (pkgs);
					} else {
						this.get_window ().set_cursor (null);
					}
					if (!local_config.software_mode) {
						ignore_all_button.visible = true;
					}
					break;
				case 1: // repos
					current_packages_list_name = "repos_updates";
					var pkgs = new GenericArray<unowned AlpmPackage> ();
					foreach (unowned AlpmPackage pkg in repos_updates) {
						pkgs.add (pkg);
					}
					if (view_stack.visible_child_name == "updates" && current_packages_list_name == "repos_updates") {
						populate_packages_list (pkgs);
					} else {
						this.get_window ().set_cursor (null);
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
						this.get_window ().set_cursor (null);
						break;
					}
					unowned string title = simple_row.title;
					if (title == dgettext (null, "AUR")) {
						current_packages_list_name = "aur_updates";
						var pkgs = new GenericArray<unowned AURPackage> ();
						foreach (unowned AURPackage pkg in aur_updates) {
							pkgs.add (pkg);
						}
						if (view_stack.visible_child_name == "updates" && current_packages_list_name == "aur_updates") {
							populate_aur_list (pkgs);
						} else {
							this.get_window ().set_cursor (null);
						}
						if (pkgs.length > 0) {
							ignore_all_button.visible = true;
						}
					} else if (title == dgettext (null, "Flatpak")) {
						current_packages_list_name = "flatpak_updates";
						var pkgs = new GenericArray<unowned FlatpakPackage> ();
						foreach (unowned FlatpakPackage pkg in flatpak_updates) {
							pkgs.add (pkg);
						}
						if (view_stack.visible_child_name == "updates" && current_packages_list_name == "flatpak_updates") {
							populate_packages_list (pkgs);
						} else {
							this.get_window ().set_cursor (null);
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
								populate_packages_list (pkgs);
							} else {
								updates_listbox.select_row (updates_listbox.get_row_at_index (0));
								on_updates_listbox_row_activated (updates_listbox.get_selected_row ());
							}
						} else {
							this.get_window ().set_cursor (null);
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

//~ 		[GtkCallback]
//~ 		void on_view_all_button_clicked () {
//~ 			if (view_stack.visible_child_name == "pending") { // pending
//~ 				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
//~ 				current_packages_list_name = "all_pending";
//~ 				var pkgs = new GenericArray<unowned Package> ();
//~ 				foreach (unowned string pkgname in to_install) {
//~ 					var pkg = database.get_installed_pkg (pkgname);
//~ 					if (pkg == null) {
//~ 						pkg = database.get_sync_pkg (pkgname);
//~ 					}
//~ 					if (pkg != null) {
//~ 						pkgs.add (pkg);
//~ 					}
//~ 				}
//~ 				foreach (unowned string pkgname in to_remove) {
//~ 					var pkg = database.get_installed_pkg (pkgname);
//~ 					if (pkg != null) {
//~ 						pkgs.add (pkg);
//~ 					} else {
//~ 					}
//~ 				}
//~ 				var snap_iter = HashTableIter<string, SnapPackage?> (snap_to_install);
//~ 				unowned SnapPackage? snap_pkg;
//~ 				while (snap_iter.next (null, out snap_pkg)) {
//~ 					pkgs.add (snap_pkg);
//~ 				}
//~ 				snap_iter = HashTableIter<string, SnapPackage?> (snap_to_remove);
//~ 				while (snap_iter.next (null, out snap_pkg)) {
//~ 					pkgs.add (snap_pkg);
//~ 				}
//~ 				var flatpak_iter = HashTableIter<string, FlatpakPackage?> (flatpak_to_install);
//~ 				unowned FlatpakPackage? flatpak_pkg;
//~ 				while (flatpak_iter.next (null, out flatpak_pkg)) {
//~ 					pkgs.add (flatpak_pkg);
//~ 				}
//~ 				flatpak_iter = HashTableIter<string, FlatpakPackage?> (flatpak_to_remove);
//~ 				while (flatpak_iter.next (null, out flatpak_pkg)) {
//~ 					pkgs.add (flatpak_pkg);
//~ 				}
//~ 				if (to_build.length > 0) {
//~ 					get_pendings_aur_pkgs.begin ((obj, res) => {
//~ 						var aur_pkgs = get_pendings_aur_pkgs.end (res);
//~ 						foreach (unowned AURPackage pkg in aur_pkgs) {
//~ 							pkgs.add (pkg);
//~ 						}
//~ 						if (view_stack.visible_child_name == "pending" && current_packages_list_name == "all_pending") {
//~ 							populate_packages_list (pkgs);
//~ 						} else {
//~ 							this.get_window ().set_cursor (null);
//~ 						}
//~ 					});
//~ 				} else {
//~ 					if (view_stack.visible_child_name == "pending" && current_packages_list_name == "all_pending") {
//~ 						populate_packages_list (pkgs);
//~ 					} else {
//~ 						this.get_window ().set_cursor (null);
//~ 					}
//~ 				}
//~ 			}
//~ 		}

//~ 		[GtkCallback]
//~ 		void on_view_repositories_button_clicked () {
//~ 			if (view_stack.visible_child_name == "pending") { //pending
//~ 				if ((to_install.length + to_remove.length) > 0) {
//~ 					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
//~ 					current_packages_list_name = "repos_pending";
//~ 					var pkgs = new GenericArray<unowned AlpmPackage> ();
//~ 					foreach (unowned string pkgname in to_install) {
//~ 						var pkg = database.get_installed_pkg (pkgname);
//~ 						if (pkg == null) {
//~ 							pkg = database.get_sync_pkg (pkgname);
//~ 						}
//~ 						if (pkg != null) {
//~ 							pkgs.add (pkg);
//~ 						}
//~ 					}
//~ 					foreach (unowned string pkgname in to_remove) {
//~ 						var pkg = database.get_installed_pkg (pkgname);
//~ 						if (pkg != null) {
//~ 							pkgs.add (pkg);
//~ 						}
//~ 					}
//~ 					if (view_stack.visible_child_name == "pending" && current_packages_list_name == "repos_pending") {
//~ 						populate_packages_list (pkgs);
//~ 					} else {
//~ 						this.get_window ().set_cursor (null);
//~ 					}
//~ 				}
//~ 			}
//~ 		}

//~ 		[GtkCallback]
//~ 		void on_view_aur_button_clicked () {
//~ 			if (view_stack.visible_child_name == "pending") { // pending
//~ 				if (to_build.length > 0) {
//~ 					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
//~ 					current_packages_list_name = "aur_pending";
//~ 					get_pendings_aur_pkgs.begin ((obj, res) => {
//~ 						var pkgs = get_pendings_aur_pkgs.end (res);
//~ 						if (view_stack.visible_child_name == "pending" && current_packages_list_name == "aur_pending") {
//~ 							populate_aur_list (pkgs);
//~ 						} else {
//~ 							this.get_window ().set_cursor (null);
//~ 						}
//~ 					});
//~ 				}
//~ 			}
//~ 		}

//~ 		[GtkCallback]
//~ 		void on_view_snap_button_clicked () {
//~ 			if (view_stack.visible_child_name == "pending") { // pending
//~ 				current_packages_list_name = "snap_pending";
//~ 				var pkgs = new GenericArray<unowned Package> ();
//~ 				var snap_iter = HashTableIter<string, SnapPackage?> (snap_to_install);
//~ 				unowned SnapPackage? pkg;
//~ 				while (snap_iter.next (null, out pkg)) {
//~ 					pkgs.add (pkg);
//~ 				}
//~ 				snap_iter = HashTableIter<string, SnapPackage?> (snap_to_remove);
//~ 				while (snap_iter.next (null, out pkg)) {
//~ 					pkgs.add (pkg);
//~ 				}
//~ 				if (view_stack.visible_child_name == "pending" && current_packages_list_name == "snap_pending") {
//~ 					populate_packages_list (pkgs);
//~ 				} else {
//~ 					this.get_window ().set_cursor (null);
//~ 				}
//~ 			}
//~ 		}

//~ 		[GtkCallback]
//~ 		void on_view_flatpak_button_clicked () {
//~ 			if (view_stack.visible_child_name == "pending") { // pending
//~ 				current_packages_list_name = "flatpak_pending";
//~ 				var pkgs = new GenericArray<unowned Package> ();
//~ 				var flatpak_iter = HashTableIter<string, FlatpakPackage?> (flatpak_to_install);
//~ 				unowned FlatpakPackage? pkg;
//~ 				while (flatpak_iter.next (null, out pkg)) {
//~ 					pkgs.add (pkg);
//~ 				}
//~ 				flatpak_iter = HashTableIter<string, FlatpakPackage?> (flatpak_to_remove);
//~ 				while (flatpak_iter.next (null, out pkg)) {
//~ 					pkgs.add (pkg);
//~ 				}
//~ 				if (view_stack.visible_child_name == "pending" && current_packages_list_name == "flatpak_pending") {
//~ 					populate_packages_list (pkgs);
//~ 				} else {
//~ 					this.get_window ().set_cursor (null);
//~ 				}
//~ 			}
//~ 		}

		[GtkCallback]
		void on_repos_listbox_row_activated (Gtk.ListBoxRow row) {
			if (row is BackRow) {
				browse_stack.visible_child_name = "filters";
				return;
			}
			var simple_row = row as SimpleRow;
			if (simple_row == null) {
				return;
			}
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			unowned string repo = simple_row.title;
			current_packages_list_name = "repo_%s".printf (repo);
			database.get_repo_pkgs_async.begin (repo, (obj, res) => {
				var pkgs = database.get_repo_pkgs_async.end (res);
				if (view_stack.visible_child_name == "browse" && current_packages_list_name == "repo_%s".printf (repo)) {
					populate_packages_list (pkgs);
				} else {
					this.get_window ().set_cursor (null);
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
					properties_stack_switcher.visible = false;
					if (view_stack.visible_child_name == "search") {
						search_entry.visible = true;
					} else if (view_stack.visible_child_name == "updates"
						|| view_stack.visible_child_name == "pending") {
						view_stack_switcher.visible = true;
						button_back.visible = false;
						search_button.visible = false;
					} else {
						view_stack_switcher.visible = true;
						button_back.visible = false;
						search_button.visible = true;
					}
					if (transaction.details_textview.buffer.get_char_count () > 0) {
						details_button.sensitive = true;
					}
					break;
				case "details":
					search_entry.visible = false;
					view_stack_switcher.visible = false;
					button_back.visible = true;
					search_button.visible = false;
					if (transaction.details_textview.buffer.get_char_count () > 0) {
						details_button.sensitive = true;
					}
					break;
				case "term":
					search_entry.visible = false;
					view_stack_switcher.visible = false;
					properties_stack_switcher.visible = false;
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

		void on_view_stack_visible_child_changed () {
			refresh_packages_list ();
		}

//~ 		[GtkCallback]
//~ 		void on_menu_button_toggled () {
//~ 			preferences_button.sensitive = !(transaction_running);
//~ 			refresh_databases_button.sensitive = !(transaction_running);
//~ 			local_button.sensitive = !(transaction_running);
//~ 		}

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

		[GtkCallback]
		void on_apply_button_clicked () {
			details_button.sensitive = true;
			if (view_stack.visible_child_name == "updates") {
				run_sysupgrade ();
			} else if (main_stack.visible_child_name == "details" &&
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
				set_pendings_operations ();
			} else if (transaction_running) {
				transaction_running = false;
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
		void on_refresh_button_clicked () {
			packages_stack.visible_child_name = "checking";
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
				if (view_stack.visible_child_name == "updates") {
					populate_updates ();
				} else {
					this.get_window ().set_cursor (null);
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
				packages_stack.visible_child_name = "updated";
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
				install_all_button.visible = false;
				remove_all_button.visible = false;
				ignore_all_button.visible = false;
				this.get_window ().set_cursor (null);
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
				details_button.relief = Gtk.ReliefStyle.NONE;
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
				transaction.show_warnings (true);
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
			transaction_running = false;
			generate_mirrors_list = false;
			if (main_stack.visible_child_name == "details") {
				refresh_details ();
			}
			scroll_to_top = false;
			updates_checked = false;
			refresh_packages_list ();
		}
	}
}
