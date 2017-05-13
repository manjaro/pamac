/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2017 Guillaume Benoit <guillaume@manjaro.org>
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
		Gdk.Pixbuf? installed_locked_icon;
		Gdk.Pixbuf? available_locked_icon;

		// manager objects
		[GtkChild]
		Gtk.Stack main_stack;
		[GtkChild]
		Gtk.Button button_back;
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
		Gtk.Stack filters_stack;
		[GtkChild]
		Gtk.StackSwitcher filters_stackswitcher;
		[GtkChild]
		Gtk.SearchEntry search_entry;
		[GtkChild]
		Gtk.TreeView search_treeview;
		[GtkChild]
		Gtk.TreeView groups_treeview;
		[GtkChild]
		Gtk.TreeView states_treeview;
		[GtkChild]
		Gtk.TreeView repos_treeview;
		[GtkChild]
		Gtk.Stack packages_stack;
		[GtkChild]
		Gtk.StackSwitcher packages_stackswitcher;
		[GtkChild]
		Gtk.Stack properties_stack;
		[GtkChild]
		Gtk.StackSwitcher properties_stackswitcher;
		[GtkChild]
		Gtk.Grid deps_grid;
		[GtkChild]
		Gtk.Grid details_grid;
		[GtkChild]
		Gtk.ScrolledWindow files_scrolledwindow;
		[GtkChild]
		Gtk.Label name_label;
		[GtkChild]
		Gtk.Label desc_label;
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
		Gtk.Button details_button;
		[GtkChild]
		Gtk.Button apply_button;
		[GtkChild]
		Gtk.Button cancel_button;

		// menu
		Gtk.Menu right_click_menu;
		Gtk.MenuItem deselect_item;
		Gtk.MenuItem install_item;
		Gtk.MenuItem remove_item;
		Gtk.MenuItem details_item;
		GLib.List<string> selected_pkgs;
		GLib.List<string> selected_aur;

		// liststores
		Gtk.ListStore search_list;
		Gtk.ListStore groups_list;
		Gtk.ListStore states_list;
		Gtk.ListStore repos_list;
		Gtk.ListStore packages_list;
		Gtk.ListStore aur_list;

		Queue<string> display_package_queue;
		string current_package_displayed;

		public Transaction transaction;

		bool refreshing;
		bool important_details;
		bool transaction_running;
		bool generate_mirrors_list;

		uint search_entry_timeout_id;

		public ManagerWindow (Gtk.Application application) {
			Object (application: application);

			support_aur (false);
			button_back.visible = false;
			transaction_infobox.visible = false;
			refreshing = false;
			important_details = false;
			transaction_running = false;
			generate_mirrors_list = false;

			this.title = dgettext (null, "Package Manager");
			Timeout.add (100, populate_window);
		}

		bool populate_window () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));

			right_click_menu = new Gtk.Menu ();
			deselect_item = new Gtk.MenuItem.with_label (dgettext (null, "Deselect"));
			deselect_item.activate.connect (on_deselect_item_activate);
			right_click_menu.append (deselect_item);
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

			search_list = new Gtk.ListStore (1, typeof (string));
			search_treeview.set_model (search_list);
			groups_list = new Gtk.ListStore (1, typeof (string));
			groups_treeview.set_model (groups_list);
			states_list = new Gtk.ListStore (1, typeof (string));
			states_treeview.set_model (states_list);
			repos_list = new Gtk.ListStore (1, typeof (string));
			repos_treeview.set_model (repos_list);

			packages_list = new Gtk.ListStore (7, 
											typeof (uint), //origin
											typeof (string), //name
											typeof (string), //name+desc
											typeof (string), //version
											typeof (string), //repo
											typeof (uint64), //isize
											typeof (string)); //GLib.format (isize)
			packages_treeview.set_model (packages_list);
			// add custom cellrenderer to packages_treeview and aur_treewiew
			var packages_state_renderer = new ActivableCellRendererPixbuf ();
			packages_state_column.pack_start (packages_state_renderer, false);
			packages_state_column.set_cell_data_func (packages_state_renderer, (celllayout, cellrenderer, treemodel, treeiter) => {
				Gdk.Pixbuf pixbuf;
				uint origin;
				string pkgname;
				treemodel.get (treeiter, 0, out origin, 1, out pkgname);
				if (origin == 2 ) { //origin == Alpm.Package.From.LOCALDB)
					if (unlikely (transaction.transaction_summary.contains (pkgname))) {
						pixbuf = installed_locked_icon;
					} else if (unlikely (transaction.should_hold (pkgname))) {
						pixbuf = installed_locked_icon;
					} else if (unlikely (transaction.to_install.contains (pkgname))) {
						pixbuf = to_reinstall_icon;
					} else if (unlikely (transaction.to_remove.contains (pkgname))) {
						pixbuf = to_remove_icon;
					} else {
						pixbuf = installed_icon;
					}
				} else if (unlikely (transaction.transaction_summary.contains (pkgname))) {
					pixbuf = available_locked_icon;
				} else if (unlikely (transaction.to_install.contains (pkgname))) {
					pixbuf = to_install_icon;
				} else {
					pixbuf = uninstalled_icon;
				}
				cellrenderer.set ("pixbuf", pixbuf);
			});
			packages_state_renderer.activated.connect (on_packages_state_icon_activated);

			aur_list = new Gtk.ListStore (6, 
											typeof (uint), //origin
											typeof (string), //name
											typeof (string), //name+desc
											typeof (string), //version
											typeof (double), //popularity
											typeof (string)); //populariy to string
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
				if ((uint) origin == 2 ) { //origin == Alpm.Package.From.LOCALDB)
					if (unlikely (transaction.transaction_summary.contains (pkgname))) {
						pixbuf = installed_locked_icon;
					} else if (unlikely (transaction.should_hold (pkgname))) {
						pixbuf = installed_locked_icon;
					} else if (unlikely (transaction.to_install.contains (pkgname))) {
						pixbuf = to_reinstall_icon;
					} else if (unlikely (transaction.to_remove.contains (pkgname))) {
						pixbuf = to_remove_icon;
					} else {
						pixbuf = installed_icon;
					}
				} else if (unlikely (transaction.to_build.contains (pkgname))) {
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
				installed_locked_icon = new Gdk.Pixbuf.from_resource ("/org/manjaro/pamac/manager/package-installed-locked.png");
				available_locked_icon = new Gdk.Pixbuf.from_resource ("/org/manjaro/pamac/manager/package-available-locked.png");
			} catch (GLib.Error e) {
				stderr.printf (e.message);
			}

			transaction = new Transaction (this as Gtk.ApplicationWindow);
			transaction.mode = Mode.MANAGER;
			transaction.start_waiting.connect (on_start_waiting);
			transaction.stop_waiting.connect (on_stop_waiting);
			transaction.start_downloading.connect (on_start_downloading);
			transaction.stop_downloading.connect (on_stop_downloading);
			transaction.start_building.connect (on_start_building);
			transaction.stop_building.connect (on_stop_building);
			transaction.important_details_outpout.connect (on_important_details_outpout);
			transaction.finished.connect (on_transaction_finished);
			transaction.write_pamac_config_finished.connect (on_write_pamac_config_finished);
			transaction.set_pkgreason_finished.connect (on_set_pkgreason_finished);
			transaction.generate_mirrors_list.connect (on_generate_mirrors_list);

			// integrate progress box and term widget
			main_stack.add_named (transaction.term_window, "term");
			transaction_infobox.pack_start (transaction.progress_box);

			support_aur (transaction.enable_aur);

			display_package_queue = new Queue<string> ();

			update_lists ();
			show_default_pkgs ();
			search_entry.grab_focus ();

			main_stack.notify["visible-child"].connect (on_main_stack_visible_child_changed);
			filters_stack.notify["visible-child"].connect (on_filters_stack_visible_child_changed);
			packages_stack.notify["visible-child"].connect (on_packages_stack_visible_child_changed);
			properties_stack.notify["visible-child"].connect (on_properties_stack_visible_child_changed);

			return false;
		}

		void on_write_pamac_config_finished (bool recurse, uint64 refresh_period, bool no_update_hide_icon,
											bool enable_aur, bool search_aur) {
			support_aur (enable_aur);
		}

		void on_set_pkgreason_finished () {
			refresh_packages_list ();
			if (main_stack.visible_child_name == "details") {
				if (transaction.get_installed_pkg (current_package_displayed).name != ""
					|| transaction.get_sync_pkg (current_package_displayed).name != "") {
					display_package_properties (current_package_displayed);
				} else {
					display_aur_properties (current_package_displayed);
				}
			}
		}

		void support_aur (bool enable_aur) {
			if (enable_aur) {
				if (filters_stack.visible_child_name == "search") {
					packages_stackswitcher.visible = true;
				}
			} else {
				packages_stackswitcher.visible = false;
			}
		}

		void set_pendings_operations () {
			if (!transaction_running && !generate_mirrors_list) {
				uint total_pending = transaction.to_install.length + transaction.to_remove.length + transaction.to_build.length;
				if (total_pending == 0) {
					transaction.progress_box.action_label.label = "";
					cancel_button.sensitive = false;
					apply_button.sensitive = false;
					if (important_details) {
						transaction_infobox.show_all ();
					}
				} else {
					string info = dngettext (null, "%u pending operation", "%u pending operations", total_pending).printf (total_pending);
					transaction.progress_box.action_label.label = info;
					cancel_button.sensitive = true;
					apply_button.sensitive = true;
					// fix an possible visibility issue
					transaction_infobox.show_all ();
				}
			}
		}

		void show_default_pkgs () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			transaction.get_installed_pkgs.begin ((obj, res) => {
				populate_packages_list (transaction.get_installed_pkgs.end (res));
			});
		}

		void update_lists () {
			Gtk.TreeIter iter;
			Gtk.TreeSelection selection = repos_treeview.get_selection ();
			selection.changed.disconnect (on_repos_treeview_selection_changed);
			foreach (unowned string repo in transaction.get_repos_names ()) {
				repos_list.insert_with_values (null, -1, 0, repo);
			}
			repos_list.get_iter_first (out iter);
			selection.select_iter (iter);
			selection.changed.connect_after (on_repos_treeview_selection_changed);

			selection = groups_treeview.get_selection ();
			selection.changed.disconnect (on_groups_treeview_selection_changed);
			foreach (unowned string group in transaction.get_groups_names ()) {
				groups_list.insert_with_values (null, -1, 0, group);
			}
			groups_list.set_sort_column_id (0, Gtk.SortType.ASCENDING);
			groups_list.get_iter_first (out iter);
			selection.select_iter (iter);
			selection.changed.connect_after (on_groups_treeview_selection_changed);

			selection = states_treeview.get_selection ();
			selection.changed.disconnect (on_states_treeview_selection_changed);
			states_list.insert_with_values (null, -1, 0, dgettext (null, "Installed"));
			states_list.insert_with_values (null, -1, 0, dgettext (null, "Explicitly installed"));
			states_list.insert_with_values (null, -1, 0, dgettext (null, "Orphans"));
			states_list.insert_with_values (null, -1, 0, dgettext (null, "Foreign"));
			states_list.insert_with_values (null, -1, 0, dgettext (null, "Pending"));
			states_list.get_iter_first (out iter);
			selection.select_iter (iter);
			selection.changed.connect_after (on_states_treeview_selection_changed);
		}

		void on_mark_explicit_button_clicked (Gtk.Button button) {
			transaction.start_set_pkgreason (current_package_displayed, 0); //Alpm.Package.Reason.EXPLICIT
		}

		Gtk.Widget populate_details_grid (string detail_type, string detail, Gtk.Widget? previous_widget) {
			var label = new Gtk.Label ("<b>%s</b>".printf (detail_type + ":"));
			label.use_markup = true;
			label.halign = Gtk.Align.START;
			details_grid.attach_next_to (label, previous_widget, Gtk.PositionType.BOTTOM);
			if (!transaction_running
				&& detail_type == dgettext (null, "Install Reason")
				&& detail == dgettext (null, "Installed as a dependency for another package")) {
				var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
				box.homogeneous = false;
				box.hexpand = true;
				var label2 = new Gtk.Label (detail);
				label2.halign = Gtk.Align.START;
				box.pack_start (label2, false);
				var mark_explicit_button = new Gtk.Button.with_label (dgettext (null, "Mark as explicitly installed"));
				mark_explicit_button.margin = 3;
				mark_explicit_button.clicked.connect (on_mark_explicit_button_clicked);
				box.pack_end (mark_explicit_button, false);
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
					AlpmPackage pkg = transaction.find_sync_satisfier (dep_button.label);
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
				transaction.to_install.add (dep_name);
			} else {
				button.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				transaction.to_install.remove (dep_name);
			}
			set_pendings_operations ();
		}

		Gtk.Widget populate_dep_grid (string dep_type, string[] dep_list, Gtk.Widget? previous_widget, bool add_install_button = false) {
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
					if (transaction.find_installed_satisfier (dep).name == "") {
						var install_dep_button = new Gtk.ToggleButton.with_label (dgettext (null, "Install"));
						install_dep_button.margin = 3;
						install_dep_button.toggled.connect (on_install_dep_button_toggled);
						box2.pack_end (install_dep_button, false);
						string dep_name = find_install_button_dep_name (install_dep_button);
						install_dep_button.active = (dep_name in transaction.to_install); 
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

		void set_package_details (string pkgname) {
			AlpmPackageDetails details = transaction.get_pkg_details (pkgname);
			// infos
			name_label.set_markup ("<big><b>%s  %s</b></big>".printf (details.name, details.version));
			desc_label.set_text (details.desc);
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
			if (details.origin == 2) { //Alpm.Package.From.LOCALDB
				install_togglebutton.visible = false;
				remove_togglebutton.visible = true;
				remove_togglebutton.active = transaction.to_remove.contains (details.name);
				reinstall_togglebutton.visible = false;
				AlpmPackage find_pkg = transaction.get_sync_pkg (details.name);
				if (find_pkg.name != "") {
					if (find_pkg.version == details.version) {
						reinstall_togglebutton.visible = true;
						reinstall_togglebutton.active = transaction.to_install.contains (details.name);
					}
				} else {
					transaction.get_aur_details.begin (details.name, (obj, res) => {
						AURPackageDetails aur_details = transaction.get_aur_details.end (res);
						if (aur_details.name != "") {
							if (aur_details.version == details.version) {
								reinstall_togglebutton.visible = true;
								reinstall_togglebutton.active = transaction.to_build.contains (details.name);
							}
						}
					});
				}
			} else if (details.origin == 3) { //Alpm.Package.From.SYNCDB
				remove_togglebutton.visible = false;
				reinstall_togglebutton.visible = false;
				install_togglebutton.visible = true;
				install_togglebutton.active = transaction.to_install.contains (details.name);
			}
			// details
			details_grid.foreach (destroy_widget);
			Gtk.Widget? previous_widget = null;
			if (details.repo != "") {
				previous_widget = populate_details_grid (dgettext (null, "Repository"), details.repo, previous_widget);
			}
			if (details.groups.length > 0) {
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
			if (details.backups.length > 0) {
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
			if (details.depends.length > 0) {
				previous_widget = populate_dep_grid (dgettext (null, "Depends On"), details.depends, previous_widget);
			}
			if (details.optdepends.length > 0) {
				previous_widget = populate_dep_grid (dgettext (null, "Optional Dependencies"), details.optdepends, previous_widget, true);
			}
			if (details.requiredby.length > 0) {
				previous_widget = populate_dep_grid (dgettext (null, "Required By"), details.requiredby, previous_widget);
			}
			if (details.optionalfor.length > 0) {
				previous_widget = populate_dep_grid (dgettext (null, "Optional For"), details.optionalfor, previous_widget);
			}
			if (details.provides.length > 0) {
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
			if (details.replaces.length > 0) {
				previous_widget = populate_dep_grid (dgettext (null, "Replaces"), details.replaces, previous_widget);
			}
			if (details.conflicts.length > 0) {
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
			name_label.set_text ("");
			desc_label.set_text ("");
			link_label.set_text ("");
			licenses_label.set_text ("");
			remove_togglebutton.visible = false;
			reinstall_togglebutton.visible = false;
			install_togglebutton.visible = false;
			properties_stackswitcher.visible = false;
			details_grid.foreach (destroy_widget);
			deps_grid.foreach (destroy_widget);
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
			transaction.get_aur_details.begin (pkgname, (obj, res) => {
				AURPackageDetails details = transaction.get_aur_details.end (res);
				// infos
				name_label.set_markup ("<big><b>%s  %s</b></big>".printf (details.name, details.version));
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
				install_togglebutton.active = transaction.to_build.contains (details.name);
				AlpmPackage pkg = transaction.get_installed_pkg (details.name);
				if (pkg.name != "") {
					remove_togglebutton.visible = true;
					remove_togglebutton.active = transaction.to_remove.contains (pkg.name);
				}
				// details
				properties_stackswitcher.visible = true;
				details_grid.foreach (destroy_widget);
				Gtk.Widget? previous_widget = null;
				if (details.packagebase != details.name) {
					previous_widget = populate_details_grid (dgettext (null, "Package Base"), details.packagebase, previous_widget);
				}
				if (details.maintainer != "") {
					previous_widget = populate_details_grid (dgettext (null, "Maintainer"), details.maintainer, previous_widget);
				}
				GLib.Time time = GLib.Time.local ((time_t) details.firstsubmitted);
				previous_widget = populate_details_grid (dgettext (null, "First Submitted"), time.format ("%a %d %b %Y %X %Z"), previous_widget);
				time = GLib.Time.local ((time_t) details.lastmodified);
				previous_widget = populate_details_grid (dgettext (null, "Last Modified"), time.format ("%a %d %b %Y %X %Z"), previous_widget);
				previous_widget = populate_details_grid (dgettext (null, "Votes"), details.numvotes.to_string (), previous_widget);
				if (details.outofdate != 0) {
					time = GLib.Time.local ((time_t) details.outofdate);
					previous_widget = populate_details_grid (dgettext (null, "Out of Date"), time.format ("%a %d %b %Y %X %Z"), previous_widget);
				}
				details_grid.show_all ();
				// deps
				previous_widget = null;
				if (details.depends.length > 0) {
					previous_widget = populate_dep_grid (dgettext (null, "Depends On"), details.depends, previous_widget);
				}
				if (details.makedepends.length > 0) {
					previous_widget = populate_dep_grid (dgettext (null, "Make Dependencies"), details.makedepends, previous_widget);
				}
				if (details.checkdepends.length > 0) {
					previous_widget = populate_dep_grid (dgettext (null, "Check Dependencies"), details.checkdepends, previous_widget);
				}
				if (details.optdepends.length > 0) {
					previous_widget = populate_dep_grid (dgettext (null, "Optional Dependencies"), details.optdepends, previous_widget);
				}
				if (details.provides.length > 0) {
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
				if (details.replaces.length > 0) {
					previous_widget = populate_dep_grid (dgettext (null, "Replaces"), details.replaces, previous_widget);
				}
				if (details.conflicts.length > 0) {
					previous_widget = populate_dep_grid (dgettext (null, "Conflicts With"), details.conflicts, previous_widget);
				}
				deps_grid.show_all ();
				this.get_window ().set_cursor (null);
			});
		}

		[GtkCallback]
		void on_install_togglebutton_toggled () {
			if (install_togglebutton.active) {
				install_togglebutton.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				if (transaction.get_pkg_origin (current_package_displayed) == 3) { //Alpm.Package.From.SYNCDB
					transaction.to_install.add (current_package_displayed);
				} else {
					transaction.to_build.add (current_package_displayed);
				}
			} else {
				install_togglebutton.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				if (transaction.to_install.remove (current_package_displayed)) {
				} else {
					transaction.to_build.remove (current_package_displayed);
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
				transaction.to_install.remove (current_package_displayed);
				transaction.to_remove.add (current_package_displayed);
			} else {
				remove_togglebutton.get_style_context ().remove_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
				transaction.to_remove.remove (current_package_displayed);
			}
			set_pendings_operations ();
		}

		[GtkCallback]
		void on_reinstall_togglebutton_toggled () {
			if (reinstall_togglebutton.active) {
				remove_togglebutton.active = false;
				remove_togglebutton.get_style_context ().remove_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
				reinstall_togglebutton.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				transaction.to_remove.remove (current_package_displayed);
				AlpmPackage find_pkg = transaction.get_sync_pkg (current_package_displayed);
				if (find_pkg.name != "") {
					transaction.to_install.add (current_package_displayed);
				} else {
					// availability in AUR was checked in set_package_details
					transaction.to_build.add (current_package_displayed);
				}
			} else {
				reinstall_togglebutton.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
				transaction.to_install.remove (current_package_displayed);
				transaction.to_build.remove (current_package_displayed);
			}
			set_pendings_operations ();
		}

		void populate_packages_list (AlpmPackage[] pkgs) {
			// populate liststore
			packages_treeview.freeze_notify ();
			packages_treeview.freeze_child_notify ();
			packages_list.clear ();
			foreach (unowned AlpmPackage pkg in pkgs) {
				packages_list.insert_with_values (null, -1,
												0, pkg.origin,
												1, pkg.name,
												2, "<b>%s</b>\n%s".printf (pkg.name, Markup.escape_text (pkg.desc)),
												3, pkg.version,
												4, pkg.repo,
												5, pkg.size,
												6, GLib.format_size (pkg.size));
			}
			packages_treeview.thaw_child_notify ();
			packages_treeview.thaw_notify ();
			this.get_window ().set_cursor (null);
		}

		void populate_aur_list (AURPackage[] pkgs) {
			// populate liststore
			aur_treeview.freeze_notify ();
			aur_treeview.freeze_child_notify ();
			aur_list.clear ();
			foreach (unowned AURPackage aur_pkg in pkgs) {
				AlpmPackage alpm_pkg = transaction.get_installed_pkg (aur_pkg.name);
				if (alpm_pkg.name != "") {
					aur_list.insert_with_values (null, -1,
													0, alpm_pkg.origin,
													1, alpm_pkg.name,
													2, "<b>%s</b>\n%s".printf (alpm_pkg.name, Markup.escape_text (alpm_pkg.desc)),
													3, alpm_pkg.version,
													4, aur_pkg.popularity,
													5, "%.2f".printf (aur_pkg.popularity));
				} else {
					aur_list.insert_with_values (null, -1,
													0, 0,
													1, aur_pkg.name,
													2, "<b>%s</b>\n%s".printf (aur_pkg.name, Markup.escape_text (aur_pkg.desc)),
													3, aur_pkg.version,
													4, aur_pkg.popularity,
													5, "%.2f".printf (aur_pkg.popularity));
				}
			}
			aur_treeview.thaw_child_notify ();
			aur_treeview.thaw_notify ();
			this.get_window ().set_cursor (null);
		}

		void refresh_packages_list () {
			switch (filters_stack.visible_child_name) {
				case "search":
					packages_stackswitcher.visible = transaction.enable_aur;
					Gtk.TreeSelection selection = search_treeview.get_selection ();
					if (selection.get_selected (null, null)) {
						on_search_treeview_selection_changed ();
					} else {
						show_default_pkgs ();
						search_entry.grab_focus ();
					}
					break;
				case "groups":
					packages_stack.visible_child_name = "repos";
					packages_stackswitcher.visible = false;
					on_groups_treeview_selection_changed ();
					break;
				case "states":
					packages_stack.visible_child_name = "repos";
					packages_stackswitcher.visible = false;
					on_states_treeview_selection_changed ();
					break;
				case "repos":
					packages_stack.visible_child_name = "repos";
					packages_stackswitcher.visible = false;
					on_repos_treeview_selection_changed ();
					break;
				default:
					break;
			}
		}

		void display_package_properties (string pkgname) {
			current_package_displayed = pkgname;
			files_scrolledwindow.visible = true;
			set_package_details (current_package_displayed);
		}

		void display_aur_properties (string pkgname) {
			current_package_displayed = pkgname;
			files_scrolledwindow.visible = false;
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
				packages_list.get (iter, 1, out pkgname);
				display_package_properties (pkgname);
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
					var pkg = transaction.find_installed_satisfier (depstring);
					if (pkg.name != "") {
						display_package_properties (pkg.name);
					} else {
						pkg = transaction.find_sync_satisfier (depstring);
						if (pkg.name != "") {
							display_package_properties (pkg.name);
						}
					}
				} else {
					// just search for the name first to search for AUR after
					if (transaction.get_installed_pkg (depstring).name != "") {
						display_package_properties (depstring);
					} else if (transaction.get_sync_pkg (depstring).name != "") {
						display_package_properties (depstring);
					} else {
						this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
						while (Gtk.events_pending ()) {
							Gtk.main_iteration ();
						}
						transaction.get_aur_details.begin (depstring, (obj, res) => {
							this.get_window ().set_cursor (null);
							if (transaction.get_aur_details.end (res).name != "") {
								display_aur_properties (depstring);
							} else {
								var pkg = transaction.find_installed_satisfier (depstring);
								if (pkg.name != "") {
									display_package_properties (pkg.name);
								} else {
									pkg = transaction.find_sync_satisfier (depstring);
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
					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
					while (Gtk.events_pending ()) {
						Gtk.main_iteration ();
					}
					string[] files = transaction.get_pkg_files (current_package_displayed);
					StringBuilder text = new StringBuilder ();
					foreach (unowned string file in files) {
						if (text.len > 0) {
							text.append ("\n");
						}
						text.append (file);
					}
					files_textview.buffer.set_text (text.str, (int) text.len);
					this.get_window ().set_cursor (null);
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
				if (transaction.to_install.remove (pkgname)) {
				} else if (transaction.to_remove.remove (pkgname)) {
				} else {
					if (origin == 2) { //Alpm.Package.From.LOCALDB
						if (!transaction.should_hold (pkgname)) {
							transaction.to_remove.add (pkgname);
						}
					} else {
						transaction.to_install.add (pkgname);
					}
				}
			}
			packages_treeview.queue_draw ();
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
				if (origin == 2) { //Alpm.Package.From.LOCALDB
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
			if (origin == 2) { //Alpm.Package.From.LOCALDB
				if (!transaction.transaction_summary.contains (pkgname)) {
					if (transaction.to_remove.remove (pkgname)) {
					} else if (!transaction.should_hold (pkgname)) {
						transaction.to_remove.add (pkgname);
					}
				}
			} else if (transaction.to_build.remove (pkgname)) {
			} else {
				transaction.to_build.add (pkgname);
			}
			set_pendings_operations ();
		}

		[GtkCallback]
		void on_button_back_clicked () {
			string? pkgname = display_package_queue.pop_tail ();
			if (pkgname != null) {
				AlpmPackage pkg = transaction.get_installed_pkg (pkgname);
				if (pkg.name == "") {
					pkg = transaction.get_sync_pkg (pkgname);
				}
				if (pkg.name == "") {
					transaction.get_aur_details.begin (pkgname, (obj, res) => {
						if (transaction.get_aur_details.end (res).name != "") {
							display_aur_properties (pkgname);
						} else {
							pkg = transaction.find_installed_satisfier (pkgname);
							if (pkg.name == "") {
								pkg = transaction.find_sync_satisfier (pkgname);
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
		}

		void on_install_item_activate () {
			foreach (unowned string pkgname in selected_pkgs) {
				if (transaction.get_pkg_origin (pkgname) == 3) { //Alpm.Package.From.SYNCDB
					transaction.to_install.add (pkgname);
				}
			}
			foreach (unowned string pkgname in selected_aur) {
				transaction.to_build.add (pkgname);
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
				transaction.to_install.remove (pkgname);
				if (!transaction.should_hold (pkgname)) {
					if (transaction.get_pkg_origin (pkgname) == 2) { //Alpm.Package.From.LOCALDB
						transaction.to_remove.add (pkgname);
					}
				}
			}
			set_pendings_operations ();
		}

		void on_deselect_item_activate () {
			foreach (unowned string pkgname in selected_pkgs) {
				if (transaction.to_install.remove (pkgname)) {
				} else {
					transaction.to_remove.remove (pkgname);
				}
			}
			foreach (unowned string pkgname in selected_aur) {
				transaction.to_build.remove (pkgname);
			}
			set_pendings_operations ();
		}

		void on_packages_stack_visible_child_changed () {
			// do nothing if it we want to see pendings AUR operations
			switch (filters_stack.visible_child_name) {
				case "search":
					Gtk.TreeIter iter;
					Gtk.TreeSelection selection = search_treeview.get_selection ();
					if (selection.get_selected (null, out iter)) {
						this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
						while (Gtk.events_pending ()) {
							Gtk.main_iteration ();
						}
						string search_string;
						search_list.get (iter, 0, out search_string);
						switch (packages_stack.visible_child_name) {
							case "repos":
								transaction.search_pkgs.begin (search_string, (obj, res) => {
									// get custom sort by relevance
									packages_list.set_sort_column_id (Gtk.TREE_SORTABLE_UNSORTED_SORT_COLUMN_ID, 0);
									populate_packages_list (transaction.search_pkgs.end (res));
								});
								break;
							case "aur":
								transaction.search_in_aur.begin (search_string, (obj, res) => {
									populate_aur_list (transaction.search_in_aur.end (res));
								});
								break;
							default:
								break;
						}
					}
					break;
				default:
					break;
			}
			if (packages_stack.visible_child_name == "aur") {
				var attention_val = GLib.Value (typeof (bool));
				attention_val.set_boolean (false);
				packages_stack.child_set_property (packages_stack.get_child_by_name ("aur"),
													"needs-attention",
													attention_val);
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
						if (transaction.to_install.contains (pkgname)
								|| transaction.to_remove.contains (pkgname)) {
							deselect_item.sensitive = true;
						} else if (origin == 2) { //Alpm.Package.From.LOCALDB
							remove_item.sensitive = true;
						} else if (origin == 3) { //Alpm.Package.From.SYNCDB
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
								if (transaction.to_install.contains (pkgname)
										|| transaction.to_remove.contains (pkgname)) {
									deselect_item.sensitive = true;
								}
							}
							if (origin == 3) { //Alpm.Package.From.SYNCDB
								install_item.sensitive = true;
							}
							if (origin == 2) { //Alpm.Package.From.LOCALDB
								remove_item.sensitive = true;
							}
						}
					}
					right_click_menu.popup (null, null, null, event.button, event.time);
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
						AlpmPackage pkg = transaction.get_installed_pkg (pkgname);
						if (pkg.name != "") {
							selected_pkgs.append (pkgname);
							// there is for sure a pkg to remove
							remove_item.sensitive = true;
						} else {
							selected_aur.append (pkgname);
						}
					}
					foreach (unowned string pkgname in selected_aur) {
						if (transaction.to_build.contains (pkgname)) {
							deselect_item.sensitive = true;
						} else {
							install_item.sensitive = true;
						}
					}
					foreach (unowned string pkgname in selected_pkgs) {
						if (transaction.to_remove.contains (pkgname)) {
							deselect_item.sensitive = true;
							break;
						}
					}
					right_click_menu.popup (null, null, null, event.button, event.time);
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

		[GtkCallback]
		void on_search_entry_activate () {
			string search_string = search_entry.get_text ().strip ();
			if (search_string != "") {
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				Gtk.TreeModel model;
				Gtk.TreeIter iter;
				Gtk.TreeSelection selection = search_treeview.get_selection ();
				// add search string in search_list if needed
				bool found = false;
				// check if search string is already selected in search list
				if (selection.get_selected (out model, out iter)) {
					string selected_string;
					model.get (iter, 0, out selected_string);
					if (selected_string == search_string) {
						on_search_treeview_selection_changed ();
						found = true;
					}
				}
				// check if search string exists in search list
				if (!found) {
					search_list.foreach ((_model, _path, _iter) => {
						string line;
						_model.get (_iter, 0, out line);
						if (line == search_string) {
							found = true;
							// we select the iter in search_list
							// it will populate the list with the selection changed signal
							selection.select_iter (_iter);
						}
						return found;
					});
				}
				if (!found) {
					search_list.insert_with_values (out iter, -1, 0, search_string);
					// we select the iter in search_list
					// it will populate the list with the selection changed signal
					selection.select_iter (iter);
				}
			}
		}

		bool search_entry_timeout_callback () {
			on_search_entry_activate ();
			search_entry_timeout_id = 0;
			return false;
		}

		[GtkCallback]
		void on_search_entry_changed () {
			if (search_entry.get_text ().strip () != "") {
				if (search_entry_timeout_id != 0) {
					Source.remove (search_entry_timeout_id);
				}
				search_entry_timeout_id = Timeout.add (750, search_entry_timeout_callback);
			}
		}

		[GtkCallback]
		void on_search_treeview_selection_changed () {
			Gtk.TreeIter iter;
			Gtk.TreeSelection selection = search_treeview.get_selection ();
			if (selection.get_selected (null, out iter)) {
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				string search_string;
				search_list.get (iter, 0, out search_string);
				// change search entry text to the selected one
				search_entry.changed.disconnect (on_search_entry_changed);
				search_entry.set_text (search_string);
				search_entry.changed.connect (on_search_entry_changed);
				Timeout.add (200, () => {
					search_entry.grab_focus_without_selecting ();
					return false;
				});
				search_entry.set_position (-1);
				switch (packages_stack.visible_child_name) {
					case "repos":
						transaction.search_pkgs.begin (search_string, (obj, res) => {
							var pkgs = transaction.search_pkgs.end (res);
							// get custom sort by relevance
							packages_list.set_sort_column_id (Gtk.TREE_SORTABLE_UNSORTED_SORT_COLUMN_ID, 0);
							populate_packages_list (pkgs);
							if (transaction.search_aur) {
								if (pkgs.length == 0) {
									transaction.search_in_aur.begin (search_string, (obj, res) => {
										if (transaction.search_in_aur.end (res).length != 0) {
											packages_stack.visible_child_name = "aur";
										}
									});
								} else {
									transaction.search_in_aur.begin (search_string, (obj, res) => {
										if (transaction.search_in_aur.end (res).length != 0) {
											var attention_val = GLib.Value (typeof (bool));
											attention_val.set_boolean (true);
											packages_stack.child_set_property (packages_stack.get_child_by_name ("aur"),
																				"needs-attention",
																				attention_val);
										}
									});
								}
							}
						});
						aur_list.clear ();
						break;
					case "aur":
						transaction.search_in_aur.begin (search_string, (obj, res) => {
							populate_aur_list (transaction.search_in_aur.end (res));
						});
						packages_list.clear ();
						break;
					default:
						break;
				}
			}
		}

		[GtkCallback]
		void on_groups_treeview_selection_changed () {
			Gtk.TreeIter iter;
			Gtk.TreeSelection selection = groups_treeview.get_selection ();
			if (selection.get_selected (null, out iter)) {
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				string group_name;
				groups_list.get (iter, 0, out group_name);
				transaction.get_group_pkgs.begin (group_name, (obj, res) => {
					populate_packages_list (transaction.get_group_pkgs.end (res));
				});
			}
		}

		[GtkCallback]
		void on_states_treeview_selection_changed () {
			Gtk.TreeIter iter;
			Gtk.TreeSelection selection = states_treeview.get_selection ();
			if (selection.get_selected (null, out iter)) {
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				packages_stackswitcher.visible = false;
				string state;
				states_list.get (iter, 0, out state);
				if (state == dgettext (null, "Installed")) {
					transaction.get_installed_pkgs.begin ((obj, res) => {
						populate_packages_list (transaction.get_installed_pkgs.end (res));
					});
				} else if (state == dgettext (null, "Explicitly installed")) {
					transaction.get_explicitly_installed_pkgs.begin ((obj, res) => {
						populate_packages_list (transaction.get_explicitly_installed_pkgs.end (res));
					});
				} else if (state == dgettext (null, "Orphans")) {
					transaction.get_orphans.begin ((obj, res) => {
						populate_packages_list (transaction.get_orphans.end (res));
					});
				} else if (state == dgettext (null, "Foreign")) {
					transaction.get_foreign_pkgs.begin ((obj, res) => {
						populate_packages_list (transaction.get_foreign_pkgs.end (res));
					});
				} else if (state == dgettext (null, "Pending")) {
					AlpmPackage[] pkgs = {};
					foreach (unowned string pkgname in transaction.to_install) {
						AlpmPackage pkg = transaction.get_installed_pkg (pkgname);
						if (pkg.name == "") {
							pkg = transaction.get_sync_pkg (pkgname);
						}
						if (pkg.name != "") {
							pkgs += pkg;
						}
					}
					foreach (unowned string pkgname in transaction.to_remove) {
						AlpmPackage pkg = transaction.get_installed_pkg (pkgname);
						if (pkg.name != "") {
							pkgs += pkg;
						}
					}
					populate_packages_list (pkgs);
					if (transaction.to_build.length != 0) {
						packages_stackswitcher.visible = true;
						AURPackage[] aur_pkgs = {};
						foreach (unowned string pkgname in transaction.to_build) {
							transaction.get_aur_details.begin (pkgname, (obj, res) => {
								AURPackageDetails details_pkg = transaction.get_aur_details.end (res);
								if (details_pkg.name != "") {
									var aur_pkg = AURPackage () {
										name = details_pkg.name,
										version = details_pkg.version,
										desc = details_pkg.desc,
										popularity = details_pkg.popularity
									};
									aur_pkgs += aur_pkg;
									populate_aur_list (aur_pkgs);
									if (aur_pkgs.length > 0 ) {
										if (pkgs.length == 0) {
											packages_stack.visible_child_name = "aur";
										} else {
											var attention_val = GLib.Value (typeof (bool));
											attention_val.set_boolean (true);
											packages_stack.child_set_property (packages_stack.get_child_by_name ("aur"),
																				"needs-attention",
																				attention_val);
										}
									}
								}
							});
						}
					}
				}
			}
		}

		[GtkCallback]
		void on_repos_treeview_selection_changed () {
			Gtk.TreeIter iter;
			Gtk.TreeSelection selection = repos_treeview.get_selection ();
			if (selection.get_selected (null, out iter)) {
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				string repo;
				repos_list.get (iter, 0, out repo);
				transaction.get_repo_pkgs.begin (repo, (obj, res) => {
					populate_packages_list (transaction.get_repo_pkgs.end (res));
				});
			}
		}

		void on_main_stack_visible_child_changed () {
			switch (main_stack.visible_child_name) {
				case "browse":
					button_back.visible = false;
					filters_stackswitcher.visible = true;
					details_button.sensitive = true;
					break;
				case "details":
					button_back.visible = true;
					filters_stackswitcher.visible = false;
					details_button.sensitive = true;
					break;
				case "term":
					filters_stackswitcher.visible = false;
					button_back.visible = true;
					details_button.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
					details_button.sensitive = false;
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
			preferences_button.sensitive = !transaction_running;
		}

		[GtkCallback]
		void on_history_button_clicked () {
			transaction.run_history_dialog ();
		}

		[GtkCallback]
		void on_local_button_clicked () {
			Gtk.FileChooserDialog chooser = new Gtk.FileChooserDialog (
					dgettext (null, "Install Local Packages"), this, Gtk.FileChooserAction.OPEN,
					dgettext (null, "_Cancel"), Gtk.ResponseType.CANCEL,
					dgettext (null, "_Open"),Gtk.ResponseType.ACCEPT);
			chooser.window_position = Gtk.WindowPosition.CENTER_ON_PARENT;
			chooser.icon_name = "system-software-install";
			chooser.default_width = 900;
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
						transaction.to_load.add (path);
					}
					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
					chooser.destroy ();
					while (Gtk.events_pending ()) {
						Gtk.main_iteration ();
					}
					transaction_running = true;
					transaction.run ();
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
			transaction.run_preferences_dialog.begin ();
		}

		[GtkCallback]
		void on_about_button_clicked () {
			transaction.run_about_dialog ();
		}

		[GtkCallback]
		void on_details_button_clicked () {
			important_details = false;
			if (transaction_running) {
				main_stack.visible_child_name = "term";
			} else {
				uint total_pending = transaction.to_install.length + transaction.to_remove.length + transaction.to_build.length;
				if (total_pending == 0) {
					main_stack.visible_child_name = "term";
				} else {
					main_stack.visible_child_name = "browse";
					filters_stack.notify["visible-child"].disconnect (on_filters_stack_visible_child_changed);
					filters_stack.visible_child_name = "states";
					filters_stack.notify["visible-child"].connect (on_filters_stack_visible_child_changed);
					Gtk.TreeIter iter;
					// show "Pending" in states_list
					// "Pending" is at indice 4
					states_list.get_iter (out iter, new Gtk.TreePath.from_indices (4));
					Gtk.TreeSelection selection = states_treeview.get_selection ();
					selection.changed.disconnect (on_states_treeview_selection_changed);
					selection.select_iter (iter);
					selection.changed.connect_after (on_states_treeview_selection_changed);
					refresh_packages_list ();
				}
			}
		}

		[GtkCallback]
		void on_apply_button_clicked () {
			transaction_running = true;
			apply_button.sensitive = false;
			cancel_button.sensitive = false;
			transaction.run ();
		}

		[GtkCallback]
		void on_cancel_button_clicked () {
			if (transaction_running || refreshing) {
				transaction_running = false;
				transaction.cancel ();
			} else {
				transaction.clear_lists ();
				set_pendings_operations ();
				refresh_packages_list ();
				if (main_stack.visible_child_name == "details") {
					if (transaction.get_installed_pkg (current_package_displayed).name != ""
						|| transaction.get_sync_pkg (current_package_displayed).name != "") {
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
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			refreshing = true;
			transaction.start_refresh (true);
			apply_button.sensitive = false;
			transaction_infobox.show_all ();
		}

		void on_start_waiting () {
			cancel_button.sensitive = true;
		}

		void on_stop_waiting () {
			set_pendings_operations ();
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

		void on_generate_mirrors_list () {
			generate_mirrors_list = true;
			apply_button.sensitive = false;
			transaction_infobox.show_all ();
		}

		void on_transaction_finished (bool success) {
			refresh_packages_list ();
			if (main_stack.visible_child_name == "details") {
				if (transaction.get_installed_pkg (current_package_displayed).name != ""
					|| transaction.get_sync_pkg (current_package_displayed).name != "") {
					display_package_properties (current_package_displayed);
				} else {
					display_aur_properties (current_package_displayed);
				}
			} else if (main_stack.visible_child_name == "term") {
				button_back.visible = true;
			}
			transaction.to_load.remove_all ();
			if (refreshing) {
				if (success) {
					transaction_running = true;
					transaction.sysupgrade (false);
				}
				refreshing = false;
			} else {
				transaction_running = false;
				generate_mirrors_list = false;
			}
			set_pendings_operations ();
		}
	}
}
