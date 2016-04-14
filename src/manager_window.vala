/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2016 Guillaume Benoit <guillaume@manjaro.org>
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

const string VERSION = "4.0.0";

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
		public Gdk.Pixbuf? installed_icon;
		public Gdk.Pixbuf? uninstalled_icon;
		public Gdk.Pixbuf? to_install_icon;
		public Gdk.Pixbuf? to_reinstall_icon;
		public Gdk.Pixbuf? to_remove_icon;
		public Gdk.Pixbuf? installed_locked_icon;
		public Gdk.Pixbuf? available_locked_icon;

		// manager objects
		[GtkChild]
		Gtk.Stack main_stack;
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
		Gtk.TreeView deps_treeview;
		[GtkChild]
		Gtk.TreeViewColumn deps_treeview_column;
		[GtkChild]
		Gtk.TreeView details_treeview;
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
		Gtk.TextView files_textview;
		[GtkChild]
		Gtk.Box search_aur_box;
		[GtkChild]
		Gtk.Switch search_aur_button;
		[GtkChild]
		Gtk.Box transaction_infobox;
		[GtkChild]
		Gtk.Label transaction_infos_label;
		[GtkChild]
		Gtk.Button transaction_infos_apply_button;
		[GtkChild]
		Gtk.Button transaction_infos_cancel_button;

		// menu
		Gtk.Menu right_click_menu;
		Gtk.MenuItem deselect_item;
		Gtk.MenuItem install_item;
		Gtk.MenuItem remove_item;
		Gtk.MenuItem reinstall_item;
		Gtk.MenuItem install_optional_deps_item;
		Gtk.MenuItem explicitly_installed_item;
		GLib.List<string> selected_pkgs;
		GLib.List<string> selected_aur;

		// liststores
		Gtk.ListStore search_list;
		Gtk.ListStore groups_list;
		Gtk.ListStore states_list;
		Gtk.ListStore repos_list;
		Gtk.ListStore deps_list;
		Gtk.ListStore details_list;
		Gtk.ListStore packages_list;
		Gtk.ListStore aur_list;

		Queue<string> display_package_queue;
		string current_package_displayed;

		public Transaction transaction;

		bool refreshing;
		public bool transaction_running;

		uint search_entry_timeout_id;

		public ManagerWindow (Gtk.Application application) {
			Object (application: application);

			support_aur (false, false);
			transaction_infobox.visible = false;;
			refreshing = false;
			transaction_running = false;

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
			reinstall_item = new Gtk.MenuItem.with_label (dgettext (null, "Reinstall"));
			reinstall_item.activate.connect (on_reinstall_item_activate);
			right_click_menu.append (reinstall_item);
			install_optional_deps_item = new Gtk.MenuItem.with_label (dgettext (null, "Install optional dependencies"));
			install_optional_deps_item.activate.connect (on_install_optional_deps_item_activate);
			right_click_menu.append (install_optional_deps_item);
			explicitly_installed_item = new Gtk.MenuItem.with_label (dgettext (null, "Mark as explicitly installed"));
			explicitly_installed_item.activate.connect (on_explicitly_installed_item_activate);
			right_click_menu.append (explicitly_installed_item);
			right_click_menu.show_all ();

			search_list = new Gtk.ListStore (1, typeof (string));
			search_treeview.set_model (search_list);
			groups_list = new Gtk.ListStore (1, typeof (string));
			groups_treeview.set_model (groups_list);
			states_list = new Gtk.ListStore (1, typeof (string));
			states_treeview.set_model (states_list);
			repos_list = new Gtk.ListStore (1, typeof (string));
			repos_treeview.set_model (repos_list);
			deps_list = new Gtk.ListStore (2, typeof (string), typeof (string));
			deps_treeview.set_model (deps_list);
			// title is not visible, it is just defined to find it
			deps_treeview_column.title = "deps";
			details_list = new Gtk.ListStore (2, typeof (string), typeof (string));
			details_treeview.set_model (details_list);

			packages_list = new Gtk.ListStore (7, 
											typeof (uint), //origin
											typeof (string), //name
											typeof (string), //name+desc
											typeof (string), //version
											typeof (string), //repo
											typeof (uint64), //isize
											typeof (string)); //GLib.format (isize)
			// sort packages by name by default
			packages_list.set_sort_column_id (1, Gtk.SortType.ASCENDING);
			packages_treeview.set_model (packages_list);
			// add custom cellrenderer to packages_treeview and aur_treewiew
			var packages_state_renderer = new ActivableCellRendererPixbuf ();
			packages_state_column.pack_start (packages_state_renderer, true);
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
			aur_state_column.pack_start (aur_state_renderer, true);
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
			transaction.start_transaction.connect (on_start_transaction);
			transaction.emit_action.connect (on_emit_action);
			transaction.finished.connect (on_transaction_finished);
			transaction.write_pamac_config_finished.connect (on_write_pamac_config_finished);
			transaction.set_pkgreason_finished.connect (on_set_pkgreason_finished);

			AlpmPackage pkg = transaction.find_installed_satisfier ("yaourt");
			if (pkg.name != "") {
				support_aur (transaction.enable_aur, transaction.search_aur);
			}

			display_package_queue = new Queue<string> ();

			update_lists ();
			show_default_pkgs ();
			search_entry.grab_focus ();

			filters_stack.notify["visible-child"].connect (on_filters_stack_visible_child_changed);
			packages_stack.notify["visible-child"].connect (on_packages_stack_visible_child_changed);

			return false;
		}

		void on_write_pamac_config_finished (bool recurse, uint64 refresh_period, bool no_update_hide_icon,
											bool enable_aur, bool search_aur) {
			AlpmPackage pkg = transaction.find_installed_satisfier ("yaourt");
			if (pkg.name != "") {
				support_aur (enable_aur, search_aur);
			}
		}

		void on_set_pkgreason_finished () {
			refresh_packages_list ();
		}

		void support_aur (bool enable_aur, bool search_aur) {
			if (enable_aur) {
				search_aur_button.active = search_aur;
				search_aur_box.visible = true;
				if (filters_stack.visible_child_name == "search") {
					packages_stackswitcher.visible = true;
				}
			} else {
				search_aur_button.active  = false;
				search_aur_box.visible = false;
				packages_stackswitcher.visible = false;
			}
		}

		void set_pendings_operations () {
			if (!transaction_running) {
				uint total_pending = transaction.to_install.length + transaction.to_remove.length + transaction.to_build.length;
				if (total_pending == 0) {
					transaction_infobox.visible = false;
				} else {
					string info = dngettext (null, "%u pending operation", "%u pending operations", total_pending).printf (total_pending);
					transaction_infos_label.label = info;
					transaction_infobox.visible = true;
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
			states_list.insert_with_values (null, -1, 0, dgettext (null, "Orphans"));
			states_list.insert_with_values (null, -1, 0, dgettext (null, "Foreign"));
			states_list.insert_with_values (null, -1, 0, dgettext (null, "Pending"));
			states_list.get_iter_first (out iter);
			selection.select_iter (iter);
			selection.changed.connect_after (on_states_treeview_selection_changed);
		}

		void set_package_details (string pkgname) {
			AlpmPackageDetails details = transaction.get_pkg_details (pkgname);
			// infos
			name_label.set_markup ("<big><b>%s  %s</b></big>".printf (details.name, details.version));
			desc_label.set_markup (details.desc);
			link_label.set_markup ("<a href=\"%s\">%s</a>".printf (details.url, details.url));
			StringBuilder licenses = new StringBuilder ();
			licenses.append (dgettext (null, "Licenses"));
			licenses.append (":");
			foreach (unowned string license in details.licenses) {
				licenses.append (" ");
				licenses.append (license);
			}
			licenses_label.set_markup (licenses.str);
			// details
			details_list.clear ();
			details_list.insert_with_values (null, -1,
												0, "<b>%s</b>".printf (dgettext (null, "Repository") + ":"),
												1, details.repo);
			var iter = Gtk.TreeIter ();
			if (details.groups.length > 0) {
				foreach (unowned string name in details.groups) {
					details_list.insert_with_values (out iter, -1,
												1, name);
				}
				Gtk.TreePath path = details_list.get_path (iter);
				int pos = (path.get_indices ()[0]) - (details.groups.length - 1);
				details_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				details_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "Groups") + ":"));
			}
			details_list.insert_with_values (null, -1,
												0, "<b>%s</b>".printf (dgettext (null, "Packager") + ":"),
												1, details.packager);
			details_list.insert_with_values (null, -1,
												0, "<b>%s</b>".printf (dgettext (null, "Build Date") + ":"),
												1, details.builddate);
			if (details.installdate != "") {
				details_list.insert_with_values (null, -1,
												0, "<b>%s</b>".printf (dgettext (null, "Install Date") + ":"),
												1, details.installdate);
			}
			if (details.reason != "") {
				details_list.insert_with_values (null, -1,
												0, "<b>%s</b>".printf (dgettext (null, "Install Reason") + ":"),
												1, details.reason);
			}
			if (details.has_signature != "") {
				details_list.insert_with_values (null, -1,
												0, "<b>%s</b>".printf (dgettext (null, "Signatures") + ":"),
												1, details.has_signature);
			}
			if (details.backups.length > 0) {
				foreach (unowned string name in details.backups) {
					details_list.insert_with_values (out iter, -1,
												1, name);
				}
				Gtk.TreePath path = details_list.get_path (iter);
				int pos = (path.get_indices ()[0]) - (details.backups.length - 1);
				details_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				details_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "Backup files") + ":"));
			}
			// deps
			deps_list.clear ();
			if (details.depends.length > 0) {
				foreach (unowned string name in details.depends) {
					deps_list.insert_with_values (out iter, -1,
												1, name);
				}
				Gtk.TreePath path = deps_list.get_path (iter);
				int pos = (path.get_indices ()[0]) - (details.depends.length - 1);
				deps_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				deps_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "Depends On") + ":"));
			}
			if (details.optdepends.length > 0) {
				foreach (unowned string name in details.optdepends) {
					var optdep = new StringBuilder (name);
					if (transaction.find_installed_satisfier (optdep.str).name != "") {
						optdep.append (" [");
						optdep.append (dgettext (null, "Installed"));
						optdep.append ("]");
					}
					deps_list.insert_with_values (out iter, -1,
												1, optdep.str);
				}
				Gtk.TreePath path = deps_list.get_path (iter);
				int pos = (path.get_indices ()[0]) - (details.optdepends.length - 1);
				deps_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				deps_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "Optional Dependencies") + ":"));
			}
			if (details.requiredby.length > 0) {
				foreach (unowned string name in details.requiredby) {
					deps_list.insert_with_values (out iter, -1,
												1, name);
				}
				Gtk.TreePath path = deps_list.get_path (iter);
				int pos = (path.get_indices ()[0]) - (details.requiredby.length - 1);
				deps_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				deps_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "Required By") + ":"));
			}
			if (details.optionalfor.length > 0) {
				foreach (unowned string name in details.optionalfor) {
					deps_list.insert_with_values (out iter, -1,
												1, name);
				}
				Gtk.TreePath path = deps_list.get_path (iter);
				int pos = (path.get_indices ()[0]) - (details.optionalfor.length - 1);
				deps_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				deps_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "Optional For") + ":"));
			}
			if (details.provides.length > 0) {
				foreach (unowned string name in details.provides) {
					deps_list.insert_with_values (out iter, -1,
												1, name);
				}
				Gtk.TreePath path = deps_list.get_path (iter);
				int pos = (path.get_indices ()[0]) - (details.provides.length - 1);
				deps_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				deps_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "Provides") + ":"));
			}
			if (details.replaces.length > 0) {
				foreach (unowned string name in details.replaces) {
					deps_list.insert_with_values (out iter, -1,
												1, name);
				}
				Gtk.TreePath path = deps_list.get_path (iter);
				int pos = (path.get_indices ()[0]) - (details.replaces.length - 1);
				deps_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				deps_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "Replaces") + ":"));
			}
			if (details.conflicts.length > 0) {
				foreach (unowned string name in details.conflicts) {
					deps_list.insert_with_values (out iter, -1,
												1, name);
				}
				Gtk.TreePath path = deps_list.get_path (iter);
				int pos = (path.get_indices ()[0]) - (details.conflicts.length - 1);
				deps_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
				deps_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "Conflicts With") + ":"));
			}
			// files
			if (details.files.length > 0) {
				files_scrolledwindow.visible = true;
				StringBuilder text = new StringBuilder ();
				foreach (unowned string file in details.files) {
					text.append (file);
					text.append ("\n");
				}
				files_textview.buffer.set_text (text.str, (int) text.len);
			} else {
				files_scrolledwindow.visible = false;
			}
		}

		void set_aur_details (string pkgname) {
			name_label.set_text ("");
			desc_label.set_text ("");
			link_label.set_text ("");
			licenses_label.set_text ("");
			details_list.clear ();
			deps_list.clear ();
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
				link_label.set_markup ("<a href=\"%s\">%s</a>\n\n<a href=\"%s\">%s</a>".printf (details.url, details.url, aur_url, aur_url));
				StringBuilder licenses = new StringBuilder ();
				licenses.append (dgettext (null, "Licenses"));
				licenses.append (":");
				foreach (unowned string license in details.licenses) {
					licenses.append (" ");
					licenses.append (license);
				}
				licenses_label.set_text (licenses.str);
				// details
				details_list.clear ();
				if (details.packagebase != details.name) {
					details_list.insert_with_values (null, -1,
													0, "<b>%s</b>".printf (dgettext (null, "Package Base") + ":"),
													1, details.packagebase);
				}
				if (details.maintainer != "") {
					details_list.insert_with_values (null, -1,
													0, "<b>%s</b>".printf (dgettext (null, "Maintainer") + ":"),
													1, details.maintainer);
				}
				GLib.Time time = GLib.Time.local ((time_t) details.firstsubmitted);
				details_list.insert_with_values (null, -1,
													0, "<b>%s</b>".printf (dgettext (null, "First Submitted") + ":"),
													1, time.format ("%a %d %b %Y %X %Z"));
				time = GLib.Time.local ((time_t) details.lastmodified);
				details_list.insert_with_values (null, -1,
													0, "<b>%s</b>".printf (dgettext (null, "Last Modified") + ":"),
													1, time.format ("%a %d %b %Y %X %Z"));
				details_list.insert_with_values (null, -1,
													0, "<b>%s</b>".printf (dgettext (null, "Votes") + ":"),
													1, details.numvotes.to_string ());
				if (details.outofdate != 0) {
					time = GLib.Time.local ((time_t) details.outofdate);
					details_list.insert_with_values (null, -1,
													0, "<b>%s</b>".printf (dgettext (null, "Out of Date") + ":"),
													1, time.format ("%a %d %b %Y %X %Z"));
				}
				// deps
				deps_list.clear ();
				var iter = Gtk.TreeIter ();
				if (details.depends.length > 0) {
					foreach (unowned string name in details.depends) {
						deps_list.insert_with_values (out iter, -1,
													1, name);
					}
					Gtk.TreePath path = deps_list.get_path (iter);
					int pos = (path.get_indices ()[0]) - (details.depends.length - 1);
					deps_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
					deps_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "Depends On") + ":"));
				}
				if (details.optdepends.length > 0) {
					foreach (unowned string name in details.optdepends) {
						var optdep = new StringBuilder (name);
						if (transaction.find_installed_satisfier (optdep.str).name != "") {
							optdep.append (" [");
							optdep.append (dgettext (null, "Installed"));
							optdep.append ("]");
						}
						deps_list.insert_with_values (out iter, -1,
													1, optdep.str);
					}
					Gtk.TreePath path = deps_list.get_path (iter);
					int pos = (path.get_indices ()[0]) - (details.optdepends.length - 1);
					deps_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
					deps_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "Optional Dependencies") + ":"));
				}
				if (details.provides.length > 0) {
					foreach (unowned string name in details.provides) {
						deps_list.insert_with_values (out iter, -1,
													1, name);
					}
					Gtk.TreePath path = deps_list.get_path (iter);
					int pos = (path.get_indices ()[0]) - (details.provides.length - 1);
					deps_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
					deps_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "Provides") + ":"));
				}
				if (details.replaces.length > 0) {
					foreach (unowned string name in details.replaces) {
						deps_list.insert_with_values (out iter, -1,
													1, name);
					}
					Gtk.TreePath path = deps_list.get_path (iter);
					int pos = (path.get_indices ()[0]) - (details.replaces.length - 1);
					deps_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
					deps_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "Replaces") + ":"));
				}
				if (details.conflicts.length > 0) {
					foreach (unowned string name in details.conflicts) {
						deps_list.insert_with_values (out iter, -1,
													1, name);
					}
					Gtk.TreePath path = deps_list.get_path (iter);
					int pos = (path.get_indices ()[0]) - (details.conflicts.length - 1);
					deps_list.get_iter (out iter, new Gtk.TreePath.from_indices (pos));
					deps_list.set (iter, 0, "<b>%s</b>".printf (dgettext (null, "Conflicts With") + ":"));
				}
				this.get_window ().set_cursor (null);
			});
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
												2, "<b>%s</b>\n%s".printf (pkg.name, pkg.desc),
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
													2, "<b>%s</b>\n%s".printf (alpm_pkg.name, alpm_pkg.desc),
													3, alpm_pkg.version,
													4, aur_pkg.popularity,
													5, "%.2f".printf (aur_pkg.popularity));
				} else {
					aur_list.insert_with_values (null, -1,
													0, 0,
													1, aur_pkg.name,
													2, "<b>%s</b>\n%s".printf (aur_pkg.name, aur_pkg.desc),
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
					if (search_aur_box.visible) {
						packages_stackswitcher.visible = true;
					}
					Gtk.TreeSelection selection = search_treeview.get_selection ();
					if (selection.get_selected (null, null)) {
						on_search_treeview_selection_changed ();
					} else {
						show_default_pkgs ();
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
			set_package_details (pkgname);
		}

		void display_aur_properties (string pkgname) {
			current_package_displayed = pkgname;
			files_scrolledwindow.visible = false;
			set_aur_details (pkgname);
		}

		[GtkCallback]
		void on_packages_treeview_row_activated (Gtk.TreeView treeview, Gtk.TreePath path, Gtk.TreeViewColumn column) {
			if (column.title == dgettext (null, "Name")) {
				main_stack.visible_child_name = "details";
				Gtk.TreeIter iter;
				packages_list.get_iter (out iter, path);
				string pkgname;
				packages_list.get (iter, 1, out pkgname);
				display_package_properties (pkgname);
			}
		}

		[GtkCallback]
		void on_deps_treeview_row_activated (Gtk.TreeView treeview, Gtk.TreePath path, Gtk.TreeViewColumn column) {
			if (column.title == "deps") {
				if (display_package_queue.find_custom (current_package_displayed, strcmp) == null) {
					display_package_queue.push_tail (current_package_displayed);
				}
				var treemodel = treeview.get_model ();
				Gtk.TreeIter iter;
				treemodel.get_iter (out iter, path);
				string val;
				treemodel.get (iter, 1, out val);
				string pkgname = val.split (":", 2)[0].replace (" [" + dgettext (null, "Installed") + "]", "");
				// just search for the name first to search for AUR after
				AlpmPackage pkg = transaction.get_installed_pkg (pkgname);
				if (pkg.name == "") {
					pkg = transaction.get_sync_pkg (pkgname);
				}
				if (pkg.name == "") {
					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
					while (Gtk.events_pending ()) {
						Gtk.main_iteration ();
					}
					transaction.get_aur_details.begin (pkgname, (obj, res) => {
						this.get_window ().set_cursor (null);
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

		void on_reinstall_item_activate () {
			foreach (unowned string pkgname in selected_pkgs) {
				transaction.to_remove.remove (pkgname);
				if (transaction.get_pkg_origin (pkgname) == 2) { //Alpm.Package.From.LOCALDB
					transaction.to_install.add (pkgname);
				}
			}
			set_pendings_operations ();
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

		void choose_opt_dep (GLib.List<string> pkgnames) {
			foreach (unowned string pkgname in pkgnames) {
				var choose_dep_dialog = new ChooseDependenciesDialog (this);
				int length = 0;
				foreach (unowned string optdep in transaction.get_pkg_uninstalled_optdeps (pkgname)) {
					length++;
					choose_dep_dialog.deps_list.insert_with_values (null, -1,
																	0, false,
																	1, optdep);
				}
				choose_dep_dialog.label.set_markup ("<b>%s</b>".printf (
					ngettext ("%s has %u uninstalled optional dependency.\nChoose if you would like to install it",
							"%s has %u uninstalled optional dependencies.\nChoose those you would like to install", length).printf (pkgname, length)));
				if (choose_dep_dialog.run () == Gtk.ResponseType.OK) {
					choose_dep_dialog.deps_list.foreach ((model, path, iter) => {
						bool selected;
						string name;
						// get value at column 0 to know if it is selected
						choose_dep_dialog.deps_list.get (iter, 0, out selected, 1, out name);
						if (selected) {
							// get value at column 1 to get the pkgname
							AlpmPackage sync_pkg = transaction.get_sync_pkg (name);
							if (sync_pkg.name != "") {
								transaction.to_install.add (sync_pkg.name);
							}
						}
						return false;
					});
				}
				choose_dep_dialog.destroy ();
				while (Gtk.events_pending ()) {
					Gtk.main_iteration ();
				}
			}
		}

		void on_install_optional_deps_item_activate () {
			choose_opt_dep (selected_pkgs);
			set_pendings_operations ();
		}

		void on_explicitly_installed_item_activate () {
			foreach (unowned string pkgname in selected_pkgs) {
				transaction.start_set_pkgreason (pkgname, 0); //Alpm.Package.Reason.EXPLICIT
			}
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
					deselect_item.sensitive = false;
					install_item.sensitive = false;
					remove_item.sensitive = false;
					reinstall_item.sensitive = false;
					install_optional_deps_item.sensitive = false;
					explicitly_installed_item.sensitive = false;
					if (selected_paths.length () == 1) {
						Gtk.TreePath path = selected_paths.data;
						Gtk.TreeIter iter;
						packages_list.get_iter (out iter, path);
						uint origin;
						string pkgname;
						string pkgversion;
						packages_list.get (iter, 0, out origin, 1, out pkgname, 3, out pkgversion);
						selected_pkgs.append (pkgname);
						if (transaction.to_install.contains (pkgname)
								|| transaction.to_remove.contains (pkgname)) {
							deselect_item.sensitive = true;
						} else if (origin == 2) { //Alpm.Package.From.LOCALDB
							remove_item.sensitive = true;
							foreach (unowned string optdep in transaction.get_pkg_uninstalled_optdeps (pkgname)) {
								if (transaction.find_installed_satisfier (optdep).name == "") {
									install_optional_deps_item.sensitive = true;
									break;
								}
							}
							if (transaction.get_pkg_reason (pkgname) == 1) { //Alpm.Package.Reason.DEPEND
								explicitly_installed_item.sensitive = true;
							}
							AlpmPackage find_pkg = transaction.get_sync_pkg (pkgname);
							if (find_pkg.name != "") {
								if (find_pkg.version == pkgversion) {
									reinstall_item.sensitive = true;
								}
							}
						} else if (origin == 3) { //Alpm.Package.From.SYNCDB
							install_item.sensitive = true;
						}
					} else {
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
					reinstall_item.sensitive = false;
					install_optional_deps_item.sensitive = false;
					explicitly_installed_item.sensitive = false;
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
		void on_search_entry_activate () {
			unowned string search_string = search_entry.get_text ();
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
			if (search_entry.get_text () != "") {
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
				switch (packages_stack.visible_child_name) {
					case "repos":
						transaction.search_pkgs.begin (search_string, (obj, res) => {
							var pkgs = transaction.search_pkgs.end (res);
							populate_packages_list (pkgs);
							if (search_aur_button.get_active ()) {
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

		void on_filters_stack_visible_child_changed () {
			refresh_packages_list ();
		}

		[GtkCallback]
		void on_history_item_activate () {
			var file = GLib.File.new_for_path ("/var/log/pamac.log");
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
					GLib.stderr.printf ("%s\n", e.message);
				}
				var history_dialog = new HistoryDialog (this);
				history_dialog.textview.buffer.set_text (text.str, (int) text.len);
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
		void on_local_item_activate () {
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
		void on_preferences_item_activate () {
			transaction.run_preferences_dialog.begin ();
		}

		[GtkCallback]
		void on_about_item_activate () {
			Gtk.show_about_dialog (
				this,
				"program_name", "Pamac",
				"logo_icon_name", "system-software-install",
				"comments", dgettext (null, "A Gtk3 frontend for libalpm"),
				"copyright", "Copyright © 2016 Guillaume Benoit",
				"version", VERSION,
				"license_type", Gtk.License.GPL_3_0,
				"website", "http://manjaro.org");
		}

		[GtkCallback]
		void on_transaction_infos_details_button_clicked () {
			if (transaction_running) {
				transaction.show_progress ();
			} else {
				Gtk.TreeIter iter;
				// show "Pending" in states_list
				// "Pending" is at indice 3
				states_list.get_iter (out iter, new Gtk.TreePath.from_indices (3));
				Gtk.TreeSelection selection = states_treeview.get_selection ();
				selection.changed.disconnect (on_states_treeview_selection_changed);
				selection.select_iter (iter);
				selection.changed.connect_after (on_states_treeview_selection_changed);
				filters_stack.visible_child_name = "states";
			}
		}

		[GtkCallback]
		void on_transaction_infos_apply_button_clicked () {
			//this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			transaction_running = true;
			transaction.run ();
		}

		[GtkCallback]
		void on_transaction_infos_cancel_button_clicked () {
			if (transaction_running) {
				transaction.cancel ();
			} else {
				transaction.clear_lists ();
				set_pendings_operations ();
				refresh_packages_list ();
			}
		}

		[GtkCallback]
		void on_refresh_button_clicked () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			refreshing = true;
			transaction.start_refresh (false);
			transaction_infos_apply_button.visible = false;
			transaction_infobox.visible = true;
		}

		void on_start_transaction () {
			transaction_infos_cancel_button.visible = false;
			transaction_infos_apply_button.visible = false;
		}

		void on_emit_action (string action) {
			transaction_infos_label.label = action;
		}

		void on_transaction_finished (bool success) {
			refresh_packages_list ();
			transaction.to_load.remove_all ();
			if (refreshing) {
				if (success) {
					transaction_running = true;
					transaction.sysupgrade (false);
				}
				refreshing = false;
			} else {
				transaction_running = false;
				transaction_infos_cancel_button.visible = true;
				transaction_infos_apply_button.visible = true;
			}
			set_pendings_operations ();
		}
	}
}
