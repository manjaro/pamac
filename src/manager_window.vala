/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2018 Guillaume Benoit <guillaume@manjaro.org>
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

	class ActivableCellRendererPixbuf : Gtk.CellRendererPixbuf {
		public signal void activated (Gtk.TreePath path);

		public ActivableCellRendererPixbuf () {
			Object ();
			this.mode = Gtk.CellRendererMode.ACTIVATABLE;
		}

		public override bool activate (Gdk.Event event, Gtk.Widget widget, string path, Gdk.Rectangle background_area,
										Gdk.Rectangle cell_area, Gtk.CellRendererState flags) {
			activated (new Gtk.TreePath.from_string (path));
			return true;
		}
	}

	[GtkTemplate (ui = "/org/manjaro/pamac/manager/manager_window.ui")]
	class ManagerWindow : Gtk.ApplicationWindow {
		// icons
		Gdk.Pixbuf? installed_icon;
		Gdk.Pixbuf? uninstalled_icon;
		Gdk.Pixbuf? to_install_icon;
		Gdk.Pixbuf? to_reinstall_icon;
		Gdk.Pixbuf? to_remove_icon;
		Gdk.Pixbuf? to_upgrade_icon;
		Gdk.Pixbuf? installed_locked_icon;
		Gdk.Pixbuf? available_locked_icon;
		Gdk.Pixbuf? package_icon;

		// manager objects
		[GtkChild]
		Gtk.HeaderBar headerbar;
		[GtkChild]
		public Gtk.Stack main_stack;
		[GtkChild]
		Gtk.Button button_back;
		[GtkChild]
		Gtk.Button select_all_button;
		[GtkChild]
		Gtk.Label header_filter_label;
		[GtkChild]
		Gtk.ModelButton preferences_button;
		[GtkChild]
		Gtk.TreeView packages_treeview;
		[GtkChild]
		Gtk.TreeViewColumn packages_state_column;
		[GtkChild]
		Gtk.TreeView aur_treeview;
		[GtkChild]
		Gtk.TreeViewColumn aur_state_column;
		[GtkChild]
		Gtk.Revealer sidebar_revealer;
		[GtkChild]
		public Gtk.Stack filters_stack;
		[GtkChild]
		public Gtk.ToggleButton search_button;
		[GtkChild]
		Gtk.SearchBar searchbar;
		[GtkChild]
		public Gtk.ComboBoxText search_comboboxtext;
		[GtkChild]
		Gtk.Entry search_entry;
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
		Gtk.Spinner checking_spinner;
		[GtkChild]
		Gtk.Stack properties_stack;
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
		Gtk.ToggleButton remove_togglebutton;
		[GtkChild]
		Gtk.ToggleButton reinstall_togglebutton;
		[GtkChild]
		Gtk.ToggleButton install_togglebutton;
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

		// menu
		Gtk.Menu right_click_menu;
		Gtk.MenuItem deselect_item;
		Gtk.MenuItem upgrade_item;
		Gtk.MenuItem install_item;
		Gtk.MenuItem remove_item;
		Gtk.MenuItem details_item;
		GLib.List<string> selected_pkgs;
		GLib.List<string> selected_aur;

		// liststores
		Gtk.ListStore packages_list;
		Gtk.ListStore aur_list;
		int sort_column_id;
		Gtk.SortType sort_order;
		bool restore_sort_order;

		public Queue<string> display_package_queue;
		string current_package_displayed;
		public GenericSet<string?> to_install;
		public GenericSet<string?> to_remove;
		public GenericSet<string?> to_load;
		public GenericSet<string?> to_build;
		public GenericSet<string?> to_update;
		public GenericSet<string?> temporary_ignorepkgs;
		public GenericSet<string?> previous_to_install;
		public GenericSet<string?> previous_to_remove;
		public GenericSet<string?> previous_to_build;

		public TransactionGtk transaction;
		public Database database;
		bool intern_lock;
		GLib.File lockfile;
		delegate void TransactionAction ();

		bool refreshing;
		bool important_details;
		bool transaction_running;
		bool sysupgrade_running;
		bool generate_mirrors_list;
		bool waiting;
		bool force_refresh;

		List<Package> repos_updates;
		List<AURPackage> aur_updates;

		uint search_entry_timeout_id;
		string search_string;
		Gtk.Label pending_label;
		Gtk.ListBoxRow pending_row;
		Gtk.ListBoxRow files_row;
		bool scroll_to_top;

		public ManagerWindow (Gtk.Application application) {
			Object (application: application);
		}

		construct {
			unowned string? use_csd = Environment.get_variable ("GTK_CSD");
			if (use_csd == "0") {
				headerbar.show_close_button = false;
			}

			button_back.visible = false;
			select_all_button.visible = false;
			scroll_to_top = true;
			searchbar.connect_entry (search_entry);
			refreshing = false;
			important_details = false;
			transaction_running = false;
			sysupgrade_running  = false;
			generate_mirrors_list = false;

			updated_label.set_markup ("<big><b>%s</b></big>".printf (dgettext (null, "Your system is up-to-date")));
			no_item_label.set_markup ("<big><b>%s</b></big>".printf (dgettext (null, "No package found")));
			checking_label.set_markup ("<big><b>%s</b></big>".printf (dgettext (null, "Checking for Updates")));
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
			right_click_menu = new Gtk.Menu ();
			deselect_item = new Gtk.MenuItem.with_label (dgettext (null, "Deselect"));
			deselect_item.activate.connect (on_deselect_item_activate);
			right_click_menu.append (deselect_item);
			upgrade_item = new Gtk.MenuItem.with_label (dgettext (null, "Upgrade"));
			upgrade_item.activate.connect (on_upgrade_item_activate);
			right_click_menu.append (upgrade_item);
			install_item = new Gtk.MenuItem.with_label (dgettext (null, "Install"));
			install_item.activate.connect (on_install_item_activate);
			right_click_menu.append (install_item);
			remove_item = new Gtk.MenuItem.with_label (dgettext (null, "Remove"));
			remove_item.activate.connect (on_remove_item_activate);
			right_click_menu.append (remove_item);
			var separator_item = new Gtk.SeparatorMenuItem ();
			right_click_menu.append (separator_item);
			details_item = new Gtk.MenuItem.with_label (dgettext (null, "Details"));
			details_item.activate.connect (on_details_item_activate);
			right_click_menu.append (details_item);
			right_click_menu.show_all ();

			packages_list = new Gtk.ListStore (9,
											typeof (uint), //origin
											typeof (string), //pkgname
											typeof (string), //name+desc
											typeof (string), //version
											typeof (string), //repo
											typeof (uint64), //isize
											typeof (string), //GLib.format (isize)
											typeof (string), //app_name
											typeof (Gdk.Pixbuf)); //icon
			// sort packages by app_name by default
			packages_list.set_sort_column_id (2,  Gtk.SortType.ASCENDING);
			restore_sort_order = false;
			packages_treeview.set_model (packages_list);
			// add custom cellrenderer to packages_treeview and aur_treewiew
			var packages_state_renderer = new ActivableCellRendererPixbuf ();
			packages_state_column.pack_start (packages_state_renderer, false);
			packages_state_column.set_cell_data_func (packages_state_renderer, (celllayout, cellrenderer, treemodel, treeiter) => {
				Gdk.Pixbuf pixbuf;
				uint origin;
				string pkgname;
				treemodel.get (treeiter, 0, out origin, 1, out pkgname);
				if (filters_stack.visible_child_name == "updates") {
					if (unlikely (temporary_ignorepkgs.contains (pkgname))) {
						pixbuf = uninstalled_icon;
					} else {
						pixbuf = to_upgrade_icon;
					}
				} else if (origin == 0) { // installed
					if (unlikely (transaction.transaction_summary.contains (pkgname))) {
						pixbuf = installed_locked_icon;
					} else if (unlikely (database.should_hold (pkgname))) {
						pixbuf = installed_locked_icon;
					} else if (unlikely (to_install.contains (pkgname))) {
						pixbuf = to_reinstall_icon;
					} else if (unlikely (to_remove.contains (pkgname))) {
						pixbuf = to_remove_icon;
					} else {
						pixbuf = installed_icon;
					}
				} else if (unlikely (transaction.transaction_summary.contains (pkgname))) {
					pixbuf = available_locked_icon;
				} else if (unlikely (to_install.contains (pkgname))) {
					pixbuf = to_install_icon;
				} else {
					pixbuf = uninstalled_icon;
				}
				cellrenderer.set ("pixbuf", pixbuf);
			});
			packages_state_renderer.activated.connect (on_packages_state_icon_activated);

			aur_list = new Gtk.ListStore (7,
											typeof (uint), //origin
											typeof (string), //name
											typeof (string), //name+desc
											typeof (string), //version
											typeof (double), //popularity
											typeof (string), //populariy to string
											typeof (Gdk.Pixbuf)); //icon
			// sort packages by popularity by default
			aur_list.set_sort_column_id (4, Gtk.SortType.DESCENDING);
			aur_treeview.set_model (aur_list);
			// add custom cellrenderer to aur_treewiew
			var aur_state_renderer = new ActivableCellRendererPixbuf ();
			aur_state_column.pack_start (aur_state_renderer, false);
			aur_state_column.set_cell_data_func (aur_state_renderer, (celllayout, cellrenderer, treemodel, treeiter) => {
				Gdk.Pixbuf pixbuf;
				uint origin;
				string pkgname;
				treemodel.get (treeiter, 0, out origin, 1, out pkgname);
				if (filters_stack.visible_child_name == "updates") {
					if (unlikely (temporary_ignorepkgs.contains (pkgname))) {
						pixbuf = uninstalled_icon;
					} else {
						pixbuf = to_upgrade_icon;
					}
				} else if ((uint) origin == 0) { // installed
					if (unlikely (transaction.transaction_summary.contains (pkgname))) {
						pixbuf = installed_locked_icon;
					} else if (unlikely (database.should_hold (pkgname))) {
						pixbuf = installed_locked_icon;
					} else if (unlikely (to_install.contains (pkgname))) {
						pixbuf = to_reinstall_icon;
					} else if (unlikely (to_remove.contains (pkgname))) {
						pixbuf = to_remove_icon;
					} else {
						pixbuf = installed_icon;
					}
				} else if (unlikely (to_build.contains (pkgname))) {
					pixbuf = to_install_icon;
				} else {
					pixbuf = uninstalled_icon;
				}
				cellrenderer.set ("pixbuf", pixbuf);
			});
			aur_state_renderer.activated.connect (on_aur_state_icon_activated);

			try {
				installed_icon = new Gdk.Pixbuf.from_resource ("/org/manjaro/pamac/manager/package-installed-updated.png");
				uninstalled_icon = new Gdk.Pixbuf.from_resource ("/org/manjaro/pamac/manager/package-available.png");
				to_install_icon = new Gdk.Pixbuf.from_resource ("/org/manjaro/pamac/manager/package-install.png");
				to_reinstall_icon = new Gdk.Pixbuf.from_resource ("/org/manjaro/pamac/manager/package-reinstall.png");
				to_remove_icon = new Gdk.Pixbuf.from_resource ("/org/manjaro/pamac/manager/package-remove.png");
				to_upgrade_icon = new Gdk.Pixbuf.from_resource ("/org/manjaro/pamac/manager/package-upgrade.png");
				installed_locked_icon = new Gdk.Pixbuf.from_resource ("/org/manjaro/pamac/manager/package-installed-locked.png");
				available_locked_icon = new Gdk.Pixbuf.from_resource ("/org/manjaro/pamac/manager/package-available-locked.png");
				package_icon = new Gdk.Pixbuf.from_resource ("/org/manjaro/pamac/manager/package-generic.png");
			} catch (GLib.Error e) {
				stderr.printf ("%s\n", e.message);
			}

			var config = new Config ("/etc/pamac.conf");
			database = new Database (config);
			database.enable_appstream ();
			database.get_updates_progress.connect (on_get_updates_progress);

			// check extern lock
			lockfile = GLib.File.new_for_path (database.get_lockfile ());
			intern_lock = false;
			Timeout.add (200, check_extern_lock);

			transaction = new TransactionGtk (database, this as Gtk.ApplicationWindow);
			transaction.no_confirm_upgrade = true;
			transaction.start_downloading.connect (on_start_downloading);
			transaction.stop_downloading.connect (on_stop_downloading);
			transaction.start_building.connect (on_start_building);
			transaction.stop_building.connect (on_stop_building);
			transaction.important_details_outpout.connect (on_important_details_outpout);
			transaction.refresh_finished.connect (on_refresh_finished);
			transaction.sysupgrade_finished.connect (on_transaction_finished);
			transaction.finished.connect (on_transaction_finished);
			transaction.write_pamac_config_finished.connect (on_write_pamac_config_finished);
			transaction.set_pkgreason_finished.connect (on_set_pkgreason_finished);
			transaction.start_generating_mirrors_list.connect (on_start_generating_mirrors_list);
			transaction.generate_mirrors_list_finished.connect (on_generate_mirrors_list_finished);

			// integrate progress box and term widget
			main_stack.add_named (transaction.term_window, "term");
			transaction_infobox.pack_start (transaction.progress_box);

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
			filters_stack.notify["visible-child"].connect (on_filters_stack_visible_child_changed);
			properties_stack.notify["visible-child"].connect (on_properties_stack_visible_child_changed);

			searchbar.notify["search-mode-enabled"].connect (on_search_mode_enabled);
			// enable "type to search"
			this.key_press_event.connect ((event) => {
				if (main_stack.visible_child_name == "browse") {
					return searchbar.handle_event (event);
				}
				return false;
			});

			// create screenshots tmp dir
			string screenshots_tmp_dir = "/tmp/pamac-app-screenshots";
			try {
				Process.spawn_command_line_sync ("mkdir -p %s".printf (screenshots_tmp_dir));
				Process.spawn_command_line_sync ("chmod -R 777 %s".printf (screenshots_tmp_dir));
			} catch (SpawnError e) {
				stderr.printf ("SpawnError: %s\n", e.message);
			}
		}

		[GtkCallback]
		bool on_ManagerWindow_delete_event () {
			if (transaction_running || sysupgrade_running || refreshing || generate_mirrors_list) {
				// do not close window
				return true;
			} else {
				// close window
				return false;
			}
		}

		bool check_lock_and_updates () {
			if (!lockfile.query_exists ()) {
				database.refresh ();
				refresh_packages_list ();
				Timeout.add (200, check_extern_lock);
				return false;
			}
			return true;
		}

		bool check_extern_lock () {
			if (!intern_lock && lockfile.query_exists ()) {
				Timeout.add (1000, check_lock_and_updates);
				return false;
			}
			return true;
		}

		void on_write_pamac_config_finished (bool recurse, uint64 refresh_period, bool no_update_hide_icon,
											bool enable_aur) {
			support_aur (enable_aur);
		}

		void on_set_pkgreason_finished () {
			transaction.unlock ();
			intern_lock = false;
			scroll_to_top = false;
			refresh_packages_list ();
			if (main_stack.visible_child_name == "details") {
				if (database.get_installed_pkg (current_package_displayed).name != ""
					|| database.get_sync_pkg (current_package_displayed).name != "") {
					display_package_properties (current_package_displayed);
				} else {
					display_aur_properties (current_package_displayed);
				}
			}
	}

		void support_aur (bool enable_aur) {
			if (filters_stack.visible_child_name == "search") {
				if (enable_aur) {
					show_sidebar ();
				} else {
					hide_sidebar ();
					unowned Gtk.ListBoxRow repo_row = search_listbox.get_row_at_index (0);
					repo_row.activatable = true;
					repo_row.selectable = true;
					repo_row.can_focus = true;
					repo_row.get_child ().sensitive = true;
					search_listbox.select_row (repo_row);
					on_search_listbox_row_activated (search_listbox.get_selected_row ());
					origin_stack.visible_child_name = "repos";
				}
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
				intern_lock = true;
				action ();
			} else {
				waiting = true;
				transaction.progress_box.action_label.label = dgettext (null, "Waiting for another package manager to quit") + "...";
				transaction.start_progressbar_pulse ();
				cancel_button.sensitive = true;
				show_transaction_infobox ();
				Timeout.add (5000, () => {
					if (!waiting) {
						return false;
					}
					bool locked = transaction.get_lock ();
					if (locked) {
						waiting = false;
						intern_lock = true;
						transaction.stop_progressbar_pulse ();
						action ();
					}
					return !locked;
				});
			}
		}

		void set_pendings_operations () {
			refresh_state_icons ();
			if (!transaction_running && !generate_mirrors_list && !refreshing && !sysupgrade_running) {
				if (filters_stack.visible_child_name == "updates") {
					uint64 total_dsize = 0;
					packages_list.foreach ((model, path, iter) => {
						string name;
						uint64 dsize;
						packages_list.get (iter, 1, out name, 5, out dsize);
						if (to_update.contains (name)) {
							total_dsize += dsize;
						}
						return false;
					});
					if (total_dsize > 0) {
						transaction.progress_box.action_label.set_markup("<b>%s: %s</b>".printf (dgettext (null, "Total download size"), format_size (total_dsize)));
					} else {
						transaction.progress_box.action_label.label = "";
					}
					if (!transaction_running && !generate_mirrors_list && !refreshing && !sysupgrade_running
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
						if (filters_stack.visible_child_name != "pending") {
							active_pending_row (false);
						}
						transaction.progress_box.action_label.label = "";
						cancel_button.sensitive = false;
						apply_button.sensitive = false;
						if (important_details) {
							show_transaction_infobox ();
						}
					} else {
						active_pending_row (true);
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
			origin_stack.visible_child_name = "repos";
			database.get_installed_apps_async.begin ((obj, res) => {
				populate_packages_list (database.get_installed_apps_async.end (res));
			});
		}

		Gtk.Label create_list_label (string str) {
			var label = new Gtk.Label (str);
			label.visible = true;
			label.margin = 12;
			label.xalign = 0;
			return label;
		}

		int sort_list_row (Gtk.ListBoxRow row1, Gtk.ListBoxRow row2) {
			var label1 = row1.get_child () as Gtk.Label;
			var label2 = row2.get_child () as Gtk.Label;
			return strcmp (label1.label, label2.label);
		}

		void active_pending_row (bool active) {
			pending_row.activatable = active;
			pending_label.sensitive = active;
		}

		public void update_lists () {
			Gtk.Label label;
			label = create_list_label (dgettext (null, "Categories"));
			filters_listbox.add (label);
			label = create_list_label (dgettext (null, "Groups"));
			filters_listbox.add (label);
			label = create_list_label (dgettext (null, "Repositories"));
			filters_listbox.add (label);
			label = create_list_label (dgettext (null, "Installed"));
			filters_listbox.add (label);
			label = create_list_label (dgettext (null, "Updates"));
			filters_listbox.add (label);
			pending_label = create_list_label (dgettext (null, "Pending"));
			pending_row = new Gtk.ListBoxRow ();
			pending_row.visible = true;
			pending_row.add (pending_label);
			filters_listbox.add (pending_row);
			active_pending_row (false);
			filters_listbox.select_row (filters_listbox.get_row_at_index (0));

			foreach (unowned string repo in database.get_repos_names ()) {
				label = create_list_label (repo);
				repos_listbox.add (label);
			}
			repos_listbox.select_row (repos_listbox.get_row_at_index (0));

			foreach (unowned string group in database.get_groups_names ()) {
				label = create_list_label (group);
				groups_listbox.add (label);
			}
			groups_listbox.set_sort_func (sort_list_row);
			groups_listbox.select_row (groups_listbox.get_row_at_index (0));

			label = create_list_label (dgettext (null, "Installed"));
			installed_listbox.add (label);
			label = create_list_label (dgettext (null, "Explicitly installed"));
			installed_listbox.add (label);
			label = create_list_label (dgettext (null, "Orphans"));
			installed_listbox.add (label);
			label = create_list_label (dgettext (null, "Foreign"));
			installed_listbox.add (label);
			installed_listbox.select_row (installed_listbox.get_row_at_index (0));

			label = create_list_label (dgettext (null, "Accessories"));
			categories_listbox.add (label);
			label = create_list_label (dgettext (null, "Audio & Video"));
			categories_listbox.add (label);
			label = create_list_label (dgettext (null, "Development"));
			categories_listbox.add (label);
			label = create_list_label (dgettext (null, "Education"));
			categories_listbox.add (label);
			label = create_list_label (dgettext (null, "Games"));
			categories_listbox.add (label);
			label = create_list_label (dgettext (null, "Graphics"));
			categories_listbox.add (label);
			label = create_list_label (dgettext (null, "Internet"));
			categories_listbox.add (label);
			label = create_list_label (dgettext (null, "Office"));
			categories_listbox.add (label);
			label = create_list_label (dgettext (null, "Science"));
			categories_listbox.add (label);
			label = create_list_label (dgettext (null, "Settings"));
			categories_listbox.add (label);
			label = create_list_label (dgettext (null, "System Tools"));
			categories_listbox.add (label);
			categories_listbox.set_sort_func (sort_list_row);
			categories_listbox.select_row (categories_listbox.get_row_at_index (0));

			label = create_list_label (dgettext (null, "Repositories"));
			updates_listbox.add (label);
			label = create_list_label (dgettext (null, "AUR"));
			updates_listbox.add (label);
			updates_listbox.select_row (updates_listbox.get_row_at_index (0));
			label = create_list_label (dgettext (null, "Repositories"));
			pending_listbox.add (label);
			label = create_list_label (dgettext (null, "AUR"));
			pending_listbox.add (label);
			pending_listbox.select_row (pending_listbox.get_row_at_index (0));
			label = create_list_label (dgettext (null, "Repositories"));
			search_listbox.add (label);
			label = create_list_label (dgettext (null, "AUR"));
			search_listbox.add (label);
			search_listbox.select_row (search_listbox.get_row_at_index (0));

			label = create_list_label (dgettext (null, "Details"));
			properties_listbox.add (label);
			label = create_list_label (dgettext (null, "Dependencies"));
			properties_listbox.add (label);
			label = create_list_label (dgettext (null, "Files"));
			files_row = new Gtk.ListBoxRow ();
			files_row.visible = true;
			files_row.add (label);
			properties_listbox.add (files_row);
			properties_listbox.select_row (properties_listbox.get_row_at_index (0));
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
				intern_lock = true;
				transaction.start_set_pkgreason (current_package_displayed, 0); //Alpm.Package.Reason.EXPLICIT
			}
		}

		Gtk.Widget populate_details_grid (string detail_type, string detail, Gtk.Widget? previous_widget) {
			var label = new Gtk.Label ("<b>%s</b>".printf (detail_type + ":"));
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
					var dep_button = widget as Gtk.Button;
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
			var label = new Gtk.Label ("<b>%s</b>".printf (dep_type + ":"));
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
					dep_button.clicked.connect (on_dep_button_clicked);
					box.pack_start (dep_button, false);
				}
			}
			deps_grid.attach_next_to (box, label, Gtk.PositionType.RIGHT);
			return label as Gtk.Widget;
		}

		void destroy_widget (Gtk.Widget widget) {
			widget.destroy ();
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

		void set_package_details (string pkgname, string app_name) {
			PackageDetails details = database.get_pkg_details (pkgname, app_name);
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
				install_togglebutton.visible = false;
				remove_togglebutton.visible = true;
				remove_togglebutton.active = to_remove.contains (details.name);
				reinstall_togglebutton.visible = false;
				Package find_pkg = database.get_sync_pkg (details.name);
				if (find_pkg.name != "") {
					if (find_pkg.version == details.version) {
						reinstall_togglebutton.visible = true;
						reinstall_togglebutton.active = to_install.contains (details.name);
					}
				} else {
					database.get_aur_pkg_details_async.begin (details.name, (obj, res) => {
						AURPackageDetails aur_details = database.get_aur_pkg_details_async.end (res);
						if (aur_details.name != "") {
							// always show reinstall button for VCS package
							if (aur_details.name.has_suffix ("-git") ||
								aur_details.name.has_suffix ("-svn") ||
								aur_details.name.has_suffix ("-bzr") ||
								aur_details.name.has_suffix ("-hg") ||
								aur_details.version == details.version) {
								reinstall_togglebutton.visible = true;
								reinstall_togglebutton.active = to_build.contains (details.name);
							}
						}
					});
				}
			} else {
				remove_togglebutton.visible = false;
				reinstall_togglebutton.visible = false;
				install_togglebutton.visible = true;
				install_togglebutton.active = to_install.contains (details.name);
			}
			// details
			details_grid.foreach (destroy_widget);
			Gtk.Widget? previous_widget = null;
			if (details.repo != "") {
				previous_widget = populate_details_grid (dgettext (null, "Repository"), details.repo, previous_widget);
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
			previous_widget = populate_details_grid (dgettext (null, "Build Date"), details.builddate, previous_widget);
			if (details.installdate != "") {
				previous_widget = populate_details_grid (dgettext (null, "Install Date"), details.installdate, previous_widget);
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
			deps_grid.foreach (destroy_widget);
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
				on_properties_stack_visible_child_changed ();
			}
		}

		void set_aur_details (string pkgname) {
			app_image.pixbuf = null;
			app_screenshot.pixbuf = null;
			name_label.set_text ("");
			desc_label.set_text ("");
			link_label.set_text ("");
			licenses_label.set_text ("");
			long_desc_label.visible = false;
			remove_togglebutton.visible = false;
			reinstall_togglebutton.visible = false;
			install_togglebutton.visible = false;
			properties_listbox.visible = false;
			details_grid.foreach (destroy_widget);
			deps_grid.foreach (destroy_widget);
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
			database.get_aur_pkg_details_async.begin (pkgname, (obj, res) => {
				AURPackageDetails details = database.get_aur_pkg_details_async.end (res);
				// infos
				name_label.set_markup ("<big><b>%s  %s</b></big>".printf (details.name, details.version));
				app_image.pixbuf = package_icon;
				desc_label.set_text (details.desc);
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
				install_togglebutton.visible = true;
				install_togglebutton.active = to_build.contains (details.name);
				Package pkg = database.get_installed_pkg (details.name);
				if (pkg.name != "") {
					remove_togglebutton.visible = true;
					remove_togglebutton.active = to_remove.contains (pkg.name);
				}
				// details
				properties_listbox.visible = true;
				details_grid.foreach (destroy_widget);
				Gtk.Widget? previous_widget = null;
				if (details.packagebase != details.name) {
					previous_widget = populate_details_grid (dgettext (null, "Package Base"), details.packagebase, previous_widget);
				}
				if (details.maintainer != "") {
					previous_widget = populate_details_grid (dgettext (null, "Maintainer"), details.maintainer, previous_widget);
				}
				previous_widget = populate_details_grid (dgettext (null, "First Submitted"), details.firstsubmitted, previous_widget);
				previous_widget = populate_details_grid (dgettext (null, "Last Modified"), details.lastmodified, previous_widget);
				previous_widget = populate_details_grid (dgettext (null, "Votes"), details.numvotes.to_string (), previous_widget);
				if (details.outofdate != "") {
					previous_widget = populate_details_grid (dgettext (null, "Out of Date"), details.outofdate, previous_widget);
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
			});
		}

		[GtkCallback]
		void on_properties_listbox_row_activated (Gtk.ListBoxRow row) {
			int index = row.get_index ();
			switch (index) {
				case 0: // details
					properties_stack.visible_child_name = "details";
					break;
				case 1: // deps
					properties_stack.visible_child_name = "deps";
					break;
				case 2: // files
					properties_stack.visible_child_name = "files";
					break;
				default:
					break;
			}
		}

		[GtkCallback]
		void on_install_togglebutton_toggled () {
			if (install_togglebutton.active) {
				install_togglebutton.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				Package find_pkg = database.get_sync_pkg (current_package_displayed);
				if (find_pkg.name != "") {
					to_install.add (current_package_displayed);
				} else {
					to_build.add (current_package_displayed);
				}
			} else {
				install_togglebutton.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				if (to_install.remove (current_package_displayed)) {
				} else {
					to_build.remove (current_package_displayed);
				}
			}
			set_pendings_operations ();
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
				Package find_pkg = database.get_sync_pkg (current_package_displayed);
				if (find_pkg.name != "") {
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

		void populate_packages_list (List<Package> pkgs) {
			// populate liststore
			packages_treeview.freeze_notify ();
			packages_treeview.freeze_child_notify ();
			packages_list.clear ();
			// scroll to top
			if (scroll_to_top) {
				packages_scrolledwindow.vadjustment.value = 0;
			} else {
				// don't scroll to top just once
				scroll_to_top = true;
			}
			if (pkgs.length () == 0) {
				origin_stack.visible_child_name = "no_item";
				packages_treeview.thaw_child_notify ();
				packages_treeview.thaw_notify ();
				select_all_button.visible = false;
				this.get_window ().set_cursor (null);
				return;
			} else {
				if (main_stack.visible_child_name == "browse") {
					select_all_button.visible = filters_stack.visible_child_name != "filters";
				}
			}
			foreach (unowned Package pkg in pkgs) {
				uint origin = 0;
				string version;
				uint64 size;
				string size_str;
				string summary;
				Gdk.Pixbuf pixbuf = null;
				if (pkg.app_name == "") {
					summary = "<b>%s</b>\n%s".printf (pkg.name, Markup.escape_text (pkg.desc));
				} else {
					summary = "<b>%s  (%s)</b>\n%s".printf (Markup.escape_text (pkg.app_name), pkg.name, Markup.escape_text (pkg.desc));
				}
				if (filters_stack.visible_child_name == "updates") {
					version = "<b>%s</b>\n(%s)".printf (pkg.version, pkg.installed_version);
					size = pkg.download_size;
					size_str = pkg.download_size == 0 ? "" : GLib.format_size (pkg.download_size);
				} else {
					version = pkg.version;
					size = pkg.size;
					size_str = GLib.format_size (pkg.size);
				}
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
				if (pkg.installed_version == "") {
					origin = 1;
				}
				packages_list.insert_with_values (null, -1,
												0, origin,
												1, pkg.name,
												2, summary,
												3, version,
												4, pkg.repo,
												5, size,
												6, size_str,
												7, pkg.app_name,
												8, pixbuf);
			}
			packages_treeview.thaw_child_notify ();
			packages_treeview.thaw_notify ();
			this.get_window ().set_cursor (null);
		}

		void populate_aur_list (List<AURPackage> pkgs) {
			// populate liststore
			aur_treeview.freeze_notify ();
			aur_treeview.freeze_child_notify ();
			aur_list.clear ();
			// scroll to top
			if (scroll_to_top) {
				aur_scrolledwindow.vadjustment.value = 0;
			} else {
				// don't scroll to top just once
				scroll_to_top = true;
			}
			if (pkgs.length () == 0) {
				origin_stack.visible_child_name = "no_item";
				aur_treeview.thaw_child_notify ();
				aur_treeview.thaw_notify ();
				select_all_button.visible = false;
				this.get_window ().set_cursor (null);
				return;
			} else {
				if (main_stack.visible_child_name == "browse") {
					select_all_button.visible = filters_stack.visible_child_name != "filters";
				}
			}
			foreach (unowned AURPackage aur_pkg in pkgs) {
				string version;
				if (filters_stack.visible_child_name == "updates") {
					version = "<b>%s</b>\n(%s)".printf (aur_pkg.version, aur_pkg.installed_version);
				} else if (aur_pkg.installed_version == "") {
					version = aur_pkg.version;
				} else {
					version = aur_pkg.installed_version;
				}
				aur_list.insert_with_values (null, -1,
											0, aur_pkg.installed_version == "" ? 1 : 0, // installed
											1, aur_pkg.name,
											2, "<b>%s</b>\n%s".printf (aur_pkg.name, Markup.escape_text (aur_pkg.desc)),
											3, version,
											4, aur_pkg.popularity,
											5, "%.2f".printf (aur_pkg.popularity),
											6, package_icon.scale_simple (32, 32, Gdk.InterpType.BILINEAR));
			}
			aur_treeview.thaw_child_notify ();
			aur_treeview.thaw_notify ();
			this.get_window ().set_cursor (null);
		}

		void save_packages_sort_order () {
			if (restore_sort_order == false) {
				packages_list.get_sort_column_id (out sort_column_id, out sort_order);
				restore_sort_order = true;
			}
		}

		void restore_packages_sort_order () {
			if (restore_sort_order == true) {
				packages_list.set_sort_column_id (sort_column_id, sort_order);
				restore_sort_order = false;
			}
		}

		public void refresh_packages_list () {
			button_back.visible = (main_stack.visible_child_name != "browse" || filters_stack.visible_child_name != "filters");
			if (filters_stack.visible_child_name != "pending") {
				uint total_pending = to_install.length + to_remove.length + to_build.length;
				if (total_pending == 0) {
					active_pending_row (false);
				}
			}
			switch (filters_stack.visible_child_name) {
				case "filters":
					this.title = dgettext (null, "Package Manager");
					filters_listbox.select_row (null);
					header_filter_label.set_markup ("");
					search_button.active = false;
					restore_packages_sort_order ();
					show_sidebar ();
					set_pendings_operations ();
					// let time to show_sidebar
					Timeout.add (200, () => {
						show_default_pkgs ();
						return false;
					});
					break;
				case "categories":
					header_filter_label.label = dgettext (null, "Categories");
					search_button.active = false;
					restore_packages_sort_order ();
					show_sidebar ();
					set_pendings_operations ();
					// let time to show_sidebar
					Timeout.add (200, () => {
						on_categories_listbox_row_activated (categories_listbox.get_selected_row ());
						return false;
					});
					break;
				case "search":
					this.title = dgettext (null, "Search");
					header_filter_label.set_markup ("");
					save_packages_sort_order ();
					set_pendings_operations ();
					// pkgs are ordered by relevance so keep this
					packages_list.set_sort_column_id (Gtk.TREE_SORTABLE_UNSORTED_SORT_COLUMN_ID, 0);
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
					break;
				case "groups":
					header_filter_label.label = dgettext (null, "Groups");
					search_button.active = false;
					restore_packages_sort_order ();
					show_sidebar ();
					set_pendings_operations ();
					// let time to show_sidebar
					Timeout.add (200, () => {
						on_groups_listbox_row_activated (groups_listbox.get_selected_row ());
						return false;
					});
					break;
				case "installed":
					header_filter_label.label = dgettext (null, "Installed");
					search_button.active = false;
					restore_packages_sort_order ();
					show_sidebar ();
					set_pendings_operations ();
					// let time to show_sidebar
					Timeout.add (200, () => {
						on_installed_listbox_row_activated (installed_listbox.get_selected_row ());
						return false;
					});
					break;
				case "repos":
					header_filter_label.label = dgettext (null, "Repositories");
					search_button.active = false;
					restore_packages_sort_order ();
					show_sidebar ();
					set_pendings_operations ();
					// let time to show_sidebar
					Timeout.add (200, () => {
						on_repos_listbox_row_activated (repos_listbox.get_selected_row ());
						return false;
					});
					break;
				case "updates":
					this.title = dgettext (null, "Updates");
					header_filter_label.set_markup ("");
					search_button.active = false;
					save_packages_sort_order ();
					// order updates by name
					packages_list.set_sort_column_id (2, Gtk.SortType.ASCENDING);
					hide_sidebar ();
					origin_stack.visible_child_name = "checking";
					checking_spinner.active = true;
					packages_list.clear ();
					aur_list.clear ();
					select_all_button.visible = false;
					apply_button.sensitive = false;
					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
					// let time to hide_sidebar
					Timeout.add (200, () => {
						database.get_updates_async.begin (on_get_updates_finished);
						return false;
					});
					break;
				case "pending":
					this.title = dgettext (null, "Pending");
					header_filter_label.set_markup ("");
					search_button.active = false;
					save_packages_sort_order ();
					// order pending by name
					packages_list.set_sort_column_id (2, Gtk.SortType.ASCENDING);
					if (to_build.length != 0) {
						show_sidebar ();
					} else {
						hide_sidebar ();
					}
					// let time to show/hide_sidebar
					Timeout.add (200, () => {
						on_pending_listbox_row_activated (pending_listbox.get_selected_row ());
						return false;
					});
					break;
				default:
					break;
			}
		}

		void display_package_properties (string pkgname, string app_name = "") {
			current_package_displayed = pkgname;
			files_row.visible = true;
			set_package_details (current_package_displayed, app_name);
		}

		void display_aur_properties (string pkgname) {
			current_package_displayed = pkgname;
			// select details if files was selected
			if (properties_listbox.get_selected_row ().get_index () == 2) {
				properties_listbox.get_row_at_index (0).activate ();
			}
			files_row.visible = false;
			set_aur_details (current_package_displayed);
		}

		[GtkCallback]
		void on_packages_treeview_row_activated (Gtk.TreeView treeview, Gtk.TreePath path, Gtk.TreeViewColumn column) {
			if (column.title == dgettext (null, "Name")) {
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				while (Gtk.events_pending ()) {
					Gtk.main_iteration ();
				}
				main_stack.visible_child_name = "details";
				Gtk.TreeIter iter;
				packages_list.get_iter (out iter, path);
				string pkgname;
				string app_name;
				packages_list.get (iter, 1, out pkgname, 7, out app_name);
				display_package_properties (pkgname, app_name);
				this.get_window ().set_cursor (null);
			}
		}

		void on_dep_button_clicked (Gtk.Button button) {
				if (display_package_queue.find_custom (current_package_displayed, strcmp) == null) {
					display_package_queue.push_tail (current_package_displayed);
				}
				string depstring = button.label;
				// if depstring contains a version restriction search a satisfier directly
				if (">" in depstring || "=" in depstring || "<" in depstring) {
					var pkg = database.find_installed_satisfier (depstring);
					if (pkg.name != "") {
						display_package_properties (pkg.name);
					} else {
						pkg = database.find_sync_satisfier (depstring);
						if (pkg.name != "") {
							display_package_properties (pkg.name);
						}
					}
				} else {
					// just search for the name first to search for AUR after
					if (database.get_installed_pkg (depstring).name != "") {
						display_package_properties (depstring);
					} else if (database.get_sync_pkg (depstring).name != "") {
						display_package_properties (depstring);
					} else {
						this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
						while (Gtk.events_pending ()) {
							Gtk.main_iteration ();
						}
						database.get_aur_pkg_details_async.begin (depstring, (obj, res) => {
							this.get_window ().set_cursor (null);
							if (database.get_aur_pkg_details_async.end (res).name != "") {
								display_aur_properties (depstring);
							} else {
								var pkg = database.find_installed_satisfier (depstring);
								if (pkg.name != "") {
									display_package_properties (pkg.name);
								} else {
									pkg = database.find_sync_satisfier (depstring);
									if (pkg.name != "") {
										display_package_properties (pkg.name);
									}
								}
							}
						});
					}
				}
		}

		void on_properties_stack_visible_child_changed () {
			switch (properties_stack.visible_child_name) {
				case "files":
					files_textview.buffer.set_text ("", -1);
					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
					while (Gtk.events_pending ()) {
						Gtk.main_iteration ();
					}
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
						this.get_window ().set_cursor (null);
					});
					break;
				default:
					break;
			}
		}

		void on_packages_state_icon_activated (Gtk.TreePath path) {
			Gtk.TreeIter iter;
			packages_list.get_iter (out iter, path);
			uint origin;
			string pkgname;
			packages_list.get (iter, 0, out origin, 1, out pkgname);
			if (!transaction.transaction_summary.contains (pkgname)) {
				if (to_install.remove (pkgname)) {
				} else if (to_remove.remove (pkgname)) {
				} else {
					if (origin == 0) { // installed
						if (to_update.remove (pkgname)) {
							temporary_ignorepkgs.add (pkgname);
						} else if (temporary_ignorepkgs.remove (pkgname)) {
							to_update.add (pkgname);
						} else if (!database.should_hold (pkgname)) {
							to_remove.add (pkgname);
						}
					} else {
						to_install.add (pkgname);
					}
				}
			}
			set_pendings_operations ();
		}

		[GtkCallback]
		void on_aur_treeview_row_activated (Gtk.TreeView treeview, Gtk.TreePath path, Gtk.TreeViewColumn column) {
			if (column.title == dgettext (null, "Name")) {
				main_stack.visible_child_name = "details";
				Gtk.TreeIter iter;
				aur_list.get_iter (out iter, path);
				uint origin;
				string pkgname;
				aur_list.get (iter, 0, out origin, 1, out pkgname);
				if (filters_stack.visible_child_name == "updates") {
					display_aur_properties (pkgname);
				} else if (origin == 0) { // installed
					display_package_properties (pkgname);
				} else {
					display_aur_properties (pkgname);
				}
			}
		}

		void on_aur_state_icon_activated (Gtk.TreePath path) {
			Gtk.TreeIter iter;
			aur_list.get_iter (out iter, path);
			uint origin;
			string pkgname;
			aur_list.get (iter, 0, out origin, 1, out pkgname);
			if (filters_stack.visible_child_name == "updates") {
				if (to_update.remove (pkgname)) {
					temporary_ignorepkgs.add (pkgname);
				} else if (temporary_ignorepkgs.remove (pkgname)) {
					to_update.add (pkgname);
				}
			} else if (origin == 0) { // installed
				if (!transaction.transaction_summary.contains (pkgname)) {
					if (to_remove.remove (pkgname)) {
					} else if (!database.should_hold (pkgname)) {
						to_remove.add (pkgname);
					}
				}
			} else if (to_build.remove (pkgname)) {
			} else {
				to_build.add (pkgname);
			}
			set_pendings_operations ();
		}

		[GtkCallback]
		public void on_button_back_clicked () {
			switch (main_stack.visible_child_name) {
				case "browse":
					filters_stack.visible_child_name = "filters";
					break;
				case "details":
					string? pkgname = display_package_queue.pop_tail ();
					if (pkgname != null) {
						Package pkg = database.get_installed_pkg (pkgname);
						if (pkg.name == "") {
							pkg = database.get_sync_pkg (pkgname);
						}
						if (pkg.name == "") {
							database.get_aur_pkg_details_async.begin (pkgname, (obj, res) => {
								if (database.get_aur_pkg_details_async.end (res).name != "") {
									display_aur_properties (pkgname);
								} else {
									pkg = database.find_installed_satisfier (pkgname);
									if (pkg.name == "") {
										pkg = database.find_sync_satisfier (pkgname);
									}
									if (pkg.name != "") {
										display_package_properties (pkgname);
									}
								}
							});
						} else {
							display_package_properties (pkgname);
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

		void on_install_item_activate () {
			foreach (unowned string pkgname in selected_pkgs) {
				if (database.get_installed_pkg (pkgname).name == "") {
					to_install.add (pkgname);
				}
			}
			foreach (unowned string pkgname in selected_aur) {
				to_build.add (pkgname);
			}
			set_pendings_operations ();
		}

		void on_details_item_activate () {
			// show details for the first selected package
			if (selected_pkgs.length () == 1) {
				display_package_properties (selected_pkgs.data);
				main_stack.visible_child_name = "details";
			} else if (selected_aur.length () == 1) {
				display_aur_properties (selected_aur.data);
				main_stack.visible_child_name = "details";
			}
		}

		void on_remove_item_activate () {
			foreach (unowned string pkgname in selected_pkgs) {
				to_install.remove (pkgname);
				if (!database.should_hold (pkgname)) {
					if (database.get_installed_pkg (pkgname).name != "") {
						to_remove.add (pkgname);
					}
				}
			}
			set_pendings_operations ();
		}

		void on_deselect_item_activate () {
			foreach (unowned string pkgname in selected_pkgs) {
				if (to_install.remove (pkgname)) {
				} else if (to_update.remove (pkgname)) {
					temporary_ignorepkgs.add (pkgname);
				} else {
					to_remove.remove (pkgname);
				}
			}
			foreach (unowned string pkgname in selected_aur) {
				if (to_build.remove (pkgname)) {
				} else {
					to_update.remove (pkgname);
					temporary_ignorepkgs.add (pkgname);
				}
			}
			set_pendings_operations ();
		}

		void on_upgrade_item_activate () {
			foreach (unowned string pkgname in selected_pkgs) {
				temporary_ignorepkgs.remove (pkgname);
				to_update.add (pkgname);
			}
			foreach (unowned string pkgname in selected_aur) {
				temporary_ignorepkgs.remove (pkgname);
				to_update.add (pkgname);
			}
			set_pendings_operations ();
		}

		[GtkCallback]
		void on_updates_listbox_row_activated (Gtk.ListBoxRow row) {
			int index = row.get_index ();
			switch (index) {
				case 0: // repos
					origin_stack.visible_child_name = "repos";
					populate_packages_list (repos_updates);
					break;
				case 1: // aur
					origin_stack.visible_child_name = "aur";
					populate_aur_list (aur_updates);
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
						origin_stack.visible_child_name = "repos";
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
						populate_packages_list (pkgs);
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
			foreach (unowned string pkgname in to_build) {
				var aur_pkg = yield database.get_aur_pkg_async (pkgname);
				if (aur_pkg.name != "") {
					aur_pkgs.append (aur_pkg);
				}
			}
			origin_stack.visible_child_name = "aur";
			populate_aur_list (aur_pkgs);
		}

		[GtkCallback]
		void on_search_listbox_row_activated (Gtk.ListBoxRow row) {
			int index = row.get_index ();
			switch (index) {
				case 0: // repos
					Timeout.add (200, () => {
						search_entry.grab_focus_without_selecting ();
						return false;
					});
					if (search_string == null) {
						return;
					}
					origin_stack.visible_child_name = "repos";
					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
					while (Gtk.events_pending ()) {
						Gtk.main_iteration ();
					}
					database.search_pkgs_async.begin (search_string, (obj, res) => {
						if (database.config.enable_aur) {
							show_sidebar ();
						} else {
							hide_sidebar ();
						}
						var pkgs = database.search_pkgs_async.end (res);
						if (pkgs.length () == 0 && database.config.enable_aur) {
							database.search_in_aur_async.begin (search_string, (obj, res) => {
								unowned Gtk.ListBoxRow aur_row = search_listbox.get_row_at_index (1);
								if (database.search_in_aur_async.end (res).length () > 0) {
									row.activatable = false;
									row.selectable = false;
									row.has_focus = false;
									row.can_focus = false;
									row.get_child ().sensitive = false;
									search_listbox.select_row (aur_row);
									on_search_listbox_row_activated (search_listbox.get_selected_row ());
								} else {
									populate_packages_list (pkgs);
								}
							});
						} else {
							populate_packages_list (pkgs);
						}
					});
					aur_list.clear ();
					break;
				case 1: // aur
					Timeout.add (200, () => {
						search_entry.grab_focus_without_selecting ();
						return false;
					});
					if (search_string == null) {
						origin_stack.visible_child_name = "no_item";
						return;
					}
					origin_stack.visible_child_name = "aur";
					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
					while (Gtk.events_pending ()) {
						Gtk.main_iteration ();
					}
					database.search_in_aur_async.begin (search_string, (obj, res) => {
						populate_aur_list (database.search_in_aur_async.end (res));
					});
					database.search_pkgs_async.begin (search_string, (obj, res) => {
						unowned Gtk.ListBoxRow repo_row = search_listbox.get_row_at_index (0);
						if (database.search_pkgs_async.end (res).length () > 0 ) {
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
					});
					packages_list.clear ();
					break;
				default:
					break;
			}
		}

		[GtkCallback]
		void on_select_all_button_clicked () {
			if (origin_stack.visible_child_name == "repos") {
				packages_treeview.get_selection ().select_all ();
			} else if (origin_stack.visible_child_name == "aur") {
				aur_treeview.get_selection ().select_all ();
			}
		}

		[GtkCallback]
		bool on_packages_treeview_button_press_event (Gdk.EventButton event) {
			// Check if right mouse button was clicked
			if (event.type == Gdk.EventType.BUTTON_PRESS && event.button == 3) {
				Gtk.TreePath treepath;
				if (packages_treeview.get_path_at_pos ((int) event.x, (int) event.y, out treepath, null, null, null)) {
					packages_treeview.grab_focus ();
					Gtk.TreeSelection selection = packages_treeview.get_selection ();
					if (!selection.path_is_selected (treepath)) {
						selection.unselect_all ();
						selection.select_path (treepath);
					}
					GLib.List<Gtk.TreePath> selected_paths = selection.get_selected_rows (null);
					selected_pkgs = new GLib.List<string> ();
					selected_aur = new GLib.List<string> ();
					deselect_item.sensitive = false;
					upgrade_item.sensitive = false;
					install_item.sensitive = false;
					remove_item.sensitive = false;
					if (selected_paths.length () == 1) {
						Gtk.TreePath path = selected_paths.data;
						Gtk.TreeIter iter;
						packages_list.get_iter (out iter, path);
						uint origin;
						string pkgname;
						string pkgversion;
						packages_list.get (iter, 0, out origin, 1, out pkgname, 3, out pkgversion);
						selected_pkgs.append (pkgname);
						details_item.sensitive = true;
						if (to_install.contains (pkgname)
							|| to_remove.contains (pkgname)
							|| to_update.contains (pkgname)) {
							deselect_item.sensitive = true;
						} else if (temporary_ignorepkgs.contains (pkgname)) {
							upgrade_item.sensitive = true;
						} else if (origin == 0) { // installed
							remove_item.sensitive = true;
						} else if (origin == 1) {
							install_item.sensitive = true;
						}
					} else {
						details_item.sensitive = false;
						foreach (unowned Gtk.TreePath path in selected_paths) {
							Gtk.TreeIter iter;
							packages_list.get_iter (out iter, path);
							uint origin;
							string pkgname;
							packages_list.get (iter, 0, out origin, 1, out pkgname);
							selected_pkgs.append (pkgname);
							if (!deselect_item.sensitive) {
								if (to_install.contains (pkgname)
									|| to_remove.contains (pkgname)
									|| to_update.contains (pkgname)) {
									deselect_item.sensitive = true;
								}
							}
							if (origin == 1) {
								if (temporary_ignorepkgs.contains (pkgname)) {
									upgrade_item.sensitive = true;
								} else {
									install_item.sensitive = true;
								}
							}
							if (filters_stack.visible_child_name != "updates" && origin == 0) { // installed
								remove_item.sensitive = true;
							}
						}
					}
					right_click_menu.popup_at_pointer (event);
					return true;
				}
			}
			return false;
		}

		[GtkCallback]
		bool on_packages_treeview_query_tooltip (int x, int y, bool keyboard_tooltip, Gtk.Tooltip tooltip) {
			Gtk.TreePath path;
			Gtk.TreeIter iter;
			if (packages_treeview.get_tooltip_context (ref x, ref y, keyboard_tooltip, null, out path, out iter)) {
				string desc;
				packages_list.get (iter, 2, out desc);
				tooltip.set_markup (desc);
				packages_treeview.set_tooltip_row (tooltip, path);
				return true;
			}
			return false;
		}

		[GtkCallback]
		bool on_aur_treeview_button_press_event (Gdk.EventButton event) {
			aur_treeview.grab_focus ();
			// Check if right mouse button was clicked
			if (event.type == Gdk.EventType.BUTTON_PRESS && event.button == 3) {
				Gtk.TreePath? treepath;
				Gtk.TreeSelection selection = aur_treeview.get_selection ();
				if (aur_treeview.get_path_at_pos ((int) event.x, (int) event.y, out treepath, null, null, null)) {
					if (!selection.path_is_selected (treepath)) {
						selection.unselect_all ();
						selection.select_path (treepath);
					}
					GLib.List<Gtk.TreePath> selected_paths = selection.get_selected_rows (null);
					selected_pkgs = new GLib.List<string> ();
					selected_aur = new GLib.List<string> ();
					deselect_item.sensitive = false;
					upgrade_item.sensitive = false;
					install_item.sensitive = false;
					remove_item.sensitive = false;
					if (selected_paths.length () == 1) {
						details_item.sensitive = true;
					} else {
						details_item.sensitive = false;
					}
					foreach (unowned Gtk.TreePath path in selected_paths) {
						Gtk.TreeIter iter;
						aur_list.get_iter (out iter, path);
						string pkgname;
						aur_list.get (iter, 1, out pkgname);
						Package pkg = database.get_installed_pkg (pkgname);
						if (pkg.name != "") {
							selected_pkgs.append (pkgname);
							if (filters_stack.visible_child_name != "updates") {
								// there is for sure a pkg to remove
								remove_item.sensitive = true;
							}
						} else {
							selected_aur.append (pkgname);
						}
					}
					foreach (unowned string pkgname in selected_aur) {
						if (to_build.contains (pkgname)) {
							deselect_item.sensitive = true;
						} else {
							install_item.sensitive = true;
						}
					}
					foreach (unowned string pkgname in selected_pkgs) {
						if (to_remove.contains (pkgname)
							|| to_update.contains (pkgname)) {
							deselect_item.sensitive = true;
						} else if (temporary_ignorepkgs.contains (pkgname)) {
							upgrade_item.sensitive = true;
						}
					}
					right_click_menu.popup_at_pointer (event);
					return true;
				}
			}
			return false;
		}

		[GtkCallback]
		bool on_aur_treeview_query_tooltip (int x, int y, bool keyboard_tooltip, Gtk.Tooltip tooltip) {
			Gtk.TreePath path;
			Gtk.TreeIter iter;
			if (aur_treeview.get_tooltip_context (ref x, ref y, keyboard_tooltip, null, out path, out iter)) {
				string desc;
				aur_list.get (iter, 2, out desc);
				tooltip.set_markup (desc);
				aur_treeview.set_tooltip_row (tooltip, path);
				return true;
			}
			return false;
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
				var store = search_comboboxtext.get_model () as Gtk.ListStore;
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
				search_string = search_comboboxtext.get_active_text ();
				if (filters_stack.visible_child_name != "search") {
					// this function will be recalled when refresh_packages_list
					filters_stack.visible_child_name = "search";
					return;
				}
				Timeout.add (200, () => {
					if (!search_entry.has_focus) {
						search_entry.grab_focus_without_selecting ();
						search_entry.set_position (-1);
					}
					return false;
				});
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
				case 3: // installed
					filters_stack.visible_child_name = "installed";
					break;
				case 4: // updates
					filters_stack.visible_child_name = "updates";
					break;
				case 5: // pending
					filters_stack.visible_child_name = "pending";
					break;
				default:
					break;
			}
		}

		[GtkCallback]
		void on_categories_listbox_row_activated (Gtk.ListBoxRow row) {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			origin_stack.visible_child_name = "repos";
			var label = row.get_child () as Gtk.Label;
			string matching_cat = "";
			string category = label.label;
			this.title = category;
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
			database.get_category_pkgs_async.begin (matching_cat, (obj, res) => {
				populate_packages_list (database.get_category_pkgs_async.end (res));
			});
		}

		[GtkCallback]
		void on_groups_listbox_row_activated (Gtk.ListBoxRow row) {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			origin_stack.visible_child_name = "repos";
			var label = row.get_child () as Gtk.Label;
			string group_name = label.label;
			this.title = group_name;
			database.get_group_pkgs_async.begin (group_name, (obj, res) => {
				populate_packages_list (database.get_group_pkgs_async.end (res));
			});
		}

		[GtkCallback]
		void on_installed_listbox_row_activated (Gtk.ListBoxRow row) {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			origin_stack.visible_child_name = "repos";
			var label = row.get_child () as Gtk.Label;
			this.title = label.label;
			int index = row.get_index ();
			switch (index) {
				case 0: // Installed
					database.get_installed_pkgs_async.begin ((obj, res) => {
						populate_packages_list (database.get_installed_pkgs_async.end (res));
					});
					break;
				case 1: // Explicitly installed
					database.get_explicitly_installed_pkgs_async.begin ((obj, res) => {
						populate_packages_list (database.get_explicitly_installed_pkgs_async.end (res));
					});
					break;
				case 2: // Orphans
					database.get_orphans_async.begin ((obj, res) => {
						populate_packages_list (database.get_orphans_async.end (res));
					});
					break;
				case 3: // Foreign
					database.get_foreign_pkgs_async.begin ((obj, res) => {
						populate_packages_list (database.get_foreign_pkgs_async.end (res));
					});
					break;
				default:
					break;
			}
		}

		[GtkCallback]
		void on_repos_listbox_row_activated (Gtk.ListBoxRow row) {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			origin_stack.visible_child_name = "repos";
			var label = row.get_child () as Gtk.Label;
			string repo = label.label;
			this.title = repo;
			database.get_repo_pkgs_async.begin (repo, (obj, res) => {
				populate_packages_list (database.get_repo_pkgs_async.end (res));
			});
		}

		void on_main_stack_visible_child_changed () {
			switch (main_stack.visible_child_name) {
				case "browse":
					button_back.visible = filters_stack.visible_child_name != "filters";
					if (filters_stack.visible_child_name == "categories") {
						header_filter_label.set_markup ("<b>%s</b>".printf (dgettext (null, "Categories")));
					} else if (filters_stack.visible_child_name == "groups") {
						header_filter_label.set_markup ("<b>%s</b>".printf (dgettext (null, "Groups")));
					} else if (filters_stack.visible_child_name == "installed") {
						header_filter_label.set_markup ("<b>%s</b>".printf (dgettext (null, "Installed")));
					} else if (filters_stack.visible_child_name == "repos") {
						header_filter_label.set_markup ("<b>%s</b>".printf (dgettext (null, "Repositories")));
					} else {
						header_filter_label.set_markup ("");
					}
					select_all_button.visible = filters_stack.visible_child_name != "filters"
												&& origin_stack.visible_child_name != "updated";
					search_button.visible = true;
					details_button.sensitive = true;
					break;
				case "details":
					button_back.visible = true;
					header_filter_label.set_markup ("");
					select_all_button.visible = false;
					search_button.visible = false;
					details_button.sensitive = true;
					break;
				case "term":
					button_back.visible = true;
					header_filter_label.set_markup ("");
					select_all_button.visible = false;
					search_button.visible = false;
					details_button.sensitive = false;
					details_button.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
					break;
				default:
					break;
			}
		}

		void on_filters_stack_visible_child_changed () {
			refresh_packages_list ();
		}

		[GtkCallback]
		void on_menu_button_toggled () {
			preferences_button.sensitive = !(transaction_running || sysupgrade_running);
		}

		[GtkCallback]
		void on_history_button_clicked () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
			var file = GLib.File.new_for_path ("/var/log/pacman.log");
			if (!file.query_exists ()) {
				GLib.stderr.printf ("File '%s' doesn't exist.\n", file.get_path ());
			} else {
				StringBuilder text = new StringBuilder ();
				try {
					// Open file for reading and wrap returned FileInputStream into a
					// DataInputStream, so we can read line by line
					var dis = new DataInputStream (file.read ());
					string line;
					// Read lines until end of file (null) is reached
					while ((line = dis.read_line ()) != null) {
						// construct text in reverse order
						text.prepend (line + "\n");
					}
				} catch (GLib.Error e) {
					stderr.printf ("%s\n", e.message);
				}
				var history_dialog = new HistoryDialog (this);
				history_dialog.textview.buffer.set_text (text.str, (int) text.len);
				this.get_window ().set_cursor (null);
				history_dialog.show ();
				history_dialog.response.connect (() => {
					history_dialog.destroy ();
				});
				while (Gtk.events_pending ()) {
					Gtk.main_iteration ();
				}
			}
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
				while (Gtk.events_pending ()) {
					Gtk.main_iteration ();
				}
			}
		}

		[GtkCallback]
		void on_preferences_button_clicked () {
			if (transaction.get_lock ()) {
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				run_preferences_dialog ();
			} else {
				transaction.display_error (dgettext (null, "Waiting for another package manager to quit"), {});
			}
		}

		public void run_preferences_dialog () {
			transaction.check_authorization.begin ((obj, res) => {
				bool authorized = transaction.check_authorization.end (res);
				if (authorized) {
					var preferences_dialog = new PreferencesDialog (transaction);
					preferences_dialog.run ();
					preferences_dialog.destroy ();
					while (Gtk.events_pending ()) {
						Gtk.main_iteration ();
					}
				}
				on_run_preferences_dialog_finished ();
			});
		}

		void on_run_preferences_dialog_finished () {
			transaction.unlock ();
			if (filters_stack.visible_child_name == "updates") {
				origin_stack.visible_child_name = "checking";
				checking_spinner.active = true;
				database.get_updates_async.begin (on_get_updates_finished);
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
				"copyright", "Copyright © 2018 Guillaume Benoit",
				"authors", authors,
				"version", VERSION,
				"license_type", Gtk.License.GPL_3_0,
				"website", "https://gitlab.manjaro.org/applications/pamac");
		}

		[GtkCallback]
		void on_details_button_clicked () {
			important_details = false;
			if (transaction_running || sysupgrade_running) {
				main_stack.visible_child_name = "term";
			} else {
				uint total_pending = to_install.length + to_remove.length + to_build.length;
				if (total_pending == 0) {
					main_stack.visible_child_name = "term";
				}
			}
		}

		[GtkCallback]
		void on_apply_button_clicked () {
			if (filters_stack.visible_child_name == "updates") {
				force_refresh = false;
				refreshing = true;
				sysupgrade_running = true;
				try_lock_and_run (run_refresh);
			} else {
				try_lock_and_run (run_transaction);
			}
		}

		bool refresh_row (Gtk.TreeModel model, Gtk.TreePath path, Gtk.TreeIter iter) {
			model.row_changed (path, iter);
			return false;
		}

		void refresh_state_icons () {
			packages_list.foreach (refresh_row);
			aur_list.foreach (refresh_row);
		}

		void run_transaction () {
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
			transaction.start (to_install_, to_remove_, to_load_, to_build_, {});
			clear_lists ();
			// let time to update packages states
			Timeout.add (500, () => {
				refresh_state_icons ();
				return false;
			});
		}

		void run_sysupgrade () {
			sysupgrade_running = true;
			apply_button.sensitive = false;
			cancel_button.sensitive = false;
			string[] temp_ign_pkgs = {};
			foreach (unowned string name in temporary_ignorepkgs) {
				temp_ign_pkgs += name;
			}
			transaction.start_sysupgrade (false, temp_ign_pkgs, {});
			// let time to update packages states
			Timeout.add (500, () => {
				refresh_state_icons ();
				return false;
			});
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
			} else if (refreshing) {
				refreshing = false;
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
					if (database.get_installed_pkg (current_package_displayed).name != ""
						|| database.get_sync_pkg (current_package_displayed).name != "") {
						display_package_properties (current_package_displayed);
					} else {
						display_aur_properties (current_package_displayed);
					}
				}
				while (Gtk.events_pending ()) {
					Gtk.main_iteration ();
				}
			}
		}

		[GtkCallback]
		void on_refresh_button_clicked () {
			force_refresh = true;
			refreshing = true;
			try_lock_and_run (run_refresh);
		}

		void run_refresh () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			apply_button.sensitive = false;
			cancel_button.sensitive = true;
			show_transaction_infobox ();
			transaction.start_refresh (force_refresh);
		}

		void on_get_updates_progress (uint percent) {
			checking_label.set_markup ("<big><b>%s %u %</b></big>".printf (dgettext (null, "Checking for Updates"), percent));
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
		}

		void on_get_updates_finished (Object? source_object, AsyncResult res) {
			var updates = database.get_updates_async.end (res);
			// copy updates in lists (keep a ref of them)
			repos_updates = new List<Package> ();
			foreach (unowned Package pkg in updates.repos_updates) {
				repos_updates.append (pkg);
			}
			aur_updates = new List<AURPackage> ();
			foreach (unowned AURPackage pkg in updates.aur_updates) {
				aur_updates.append (pkg);
			}
			origin_stack.visible_child_name = "repos";
			checking_spinner.active = false;
			if (filters_stack.visible_child_name == "updates") {
				populate_updates ();
			} else {
				this.get_window ().set_cursor (null);
			}
		}

		void populate_updates () {
			to_update.remove_all ();
			if ((repos_updates.length () + aur_updates.length ()) == 0) {
				if (!refreshing && !transaction_running && !sysupgrade_running) {
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
					on_updates_listbox_row_activated (updates_listbox.get_selected_row ());
				} else {
					updates_listbox.select_row (updates_listbox.get_row_at_index (1));
					on_updates_listbox_row_activated (updates_listbox.get_selected_row ());
				}
				if (main_stack.visible_child_name == "browse") {
					select_all_button.visible = filters_stack.visible_child_name != "filters";
				}
				set_pendings_operations ();
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
			show_transaction_infobox ();
		}

		void on_generate_mirrors_list_finished () {
			generate_mirrors_list = false;
		}

		void on_refresh_finished (bool success) {
			refreshing = false;
			if (sysupgrade_running) {
				run_sysupgrade ();
			} else {
				scroll_to_top = false;
				refresh_packages_list ();
				if (main_stack.visible_child_name == "details") {
					if (database.get_installed_pkg (current_package_displayed).name != ""
						|| database.get_sync_pkg (current_package_displayed).name != "") {
						display_package_properties (current_package_displayed);
					} else {
						display_aur_properties (current_package_displayed);
					}
				} else if (main_stack.visible_child_name == "term") {
					button_back.visible = true;
				}
			}
		}

		void on_transaction_finished (bool success) {
			transaction.unlock ();
			intern_lock = false;
			if (!success) {
				foreach (unowned string name in previous_to_install) {
					if (database.get_installed_pkg (name).name == "") {
						to_install.add (name);
					}
				}
				foreach (unowned string name in previous_to_remove) {
					if (database.get_installed_pkg (name).name != "") {
						to_remove.add (name);
					}
				}
				foreach (unowned string name in previous_to_build) {
					if (database.get_installed_pkg (name).name == "") {
						to_build.add (name);
					}
				}
			}
			clear_previous_lists ();
			scroll_to_top = false;
			refresh_packages_list ();
			if (main_stack.visible_child_name == "details") {
				if (database.get_installed_pkg (current_package_displayed).name != ""
					|| database.get_sync_pkg (current_package_displayed).name != "") {
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
			set_pendings_operations ();
		}
	}
}
