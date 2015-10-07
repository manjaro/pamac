/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2015 Guillaume Benoit <guillaume@manjaro.org>
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

using Gtk;
using Alpm;

const string VERSION = "2.4.2";

namespace Pamac {

	public struct SortInfo {
		public int column_number;
		public Gtk.SortType sort_type;
	}

	[GtkTemplate (ui = "/org/manjaro/pamac/manager/manager_window.ui")]
	public class ManagerWindow : Gtk.ApplicationWindow {
		// icons
		public Gdk.Pixbuf? installed_icon;
		public Gdk.Pixbuf? uninstalled_icon;
		public Gdk.Pixbuf? to_install_icon;
		public Gdk.Pixbuf? to_reinstall_icon;
		public Gdk.Pixbuf? to_remove_icon;
		public Gdk.Pixbuf? locked_icon;

		// manager objects
		[GtkChild]
		public Gtk.TreeView packages_treeview;
		[GtkChild]
		public Gtk.TreeViewColumn state_column;
		[GtkChild]
		public Gtk.TreeViewColumn name_column;
		[GtkChild]
		public Gtk.TreeViewColumn version_column;
		[GtkChild]
		public Gtk.TreeViewColumn repo_column;
		[GtkChild]
		public Gtk.TreeViewColumn size_column;
		[GtkChild]
		public Gtk.Notebook filters_notebook;
		[GtkChild]
		public Gtk.SearchEntry search_entry;
		[GtkChild]
		public Gtk.TreeView search_treeview;
		[GtkChild]
		public Gtk.TreeView groups_treeview;
		[GtkChild]
		public Gtk.TreeView states_treeview;
		[GtkChild]
		public Gtk.TreeView repos_treeview;
		[GtkChild]
		public Gtk.Notebook properties_notebook;
		[GtkChild]
		public Gtk.TreeView deps_treeview;
		[GtkChild]
		public Gtk.TreeView details_treeview;
		[GtkChild]
		public Gtk.ScrolledWindow deps_scrolledwindow;
		[GtkChild]
		public Gtk.ScrolledWindow details_scrolledwindow;
		[GtkChild]
		public Gtk.ScrolledWindow files_scrolledwindow;
		[GtkChild]
		public Gtk.Label name_label;
		[GtkChild]
		public Gtk.Label desc_label;
		[GtkChild]
		public Gtk.Label link_label;
		[GtkChild]
		public Gtk.Label licenses_label;
		[GtkChild]
		public Gtk.TextView files_textview;
		[GtkChild]
		public Gtk.Box search_aur_box;
		[GtkChild]
		public Gtk.Switch search_aur_button;
		[GtkChild]
		public Gtk.Button valid_button;
		[GtkChild]
		public Gtk.Button cancel_button;

		// menu
		Gtk.Menu right_click_menu;
		Gtk.MenuItem deselect_item;
		Gtk.MenuItem install_item;
		Gtk.MenuItem remove_item;
		Gtk.SeparatorMenuItem separator_item;
		Gtk.MenuItem reinstall_item;
		Gtk.MenuItem install_optional_deps_item;
		Gtk.MenuItem explicitly_installed_item;
		Pamac.Package[] selected_pkgs;

		// liststore
		Gtk.ListStore search_list;
		Gtk.ListStore groups_list;
		Gtk.ListStore states_list;
		Gtk.ListStore repos_list;
		Gtk.ListStore deps_list;
		Gtk.ListStore details_list;

		PackagesModel packages_list;

		public Transaction transaction;

		public SortInfo sortinfo;

		public ManagerWindow (Gtk.Application application) {
			Object (application: application);

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
			separator_item = new Gtk.SeparatorMenuItem ();
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
			details_list = new Gtk.ListStore (2, typeof (string), typeof (string));
			details_treeview.set_model (details_list);;

			try {
				installed_icon = new Gdk.Pixbuf.from_resource ("/org/manjaro/pamac/manager/package-installed-updated.png");
				uninstalled_icon = new Gdk.Pixbuf.from_resource ("/org/manjaro/pamac/manager/package-available.png");
				to_install_icon = new Gdk.Pixbuf.from_resource ("/org/manjaro/pamac/manager/package-install.png");
				to_reinstall_icon = new Gdk.Pixbuf.from_resource ("/org/manjaro/pamac/manager/package-reinstall.png");
				to_remove_icon = new Gdk.Pixbuf.from_resource ("/org/manjaro/pamac/manager/package-remove.png");
				locked_icon = new Gdk.Pixbuf.from_resource ("/org/manjaro/pamac/manager/package-installed-locked.png");
			} catch (GLib.Error e) {
				stderr.printf (e.message);
			}

			transaction = new Pamac.Transaction (this as Gtk.ApplicationWindow);
			transaction.mode = Mode.MANAGER;
			transaction.finished.connect (on_transaction_finished);
			transaction.support_aur.connect (support_aur);
			transaction.daemon.set_pkgreason_finished.connect (display_package_properties);

			var pamac_config = new Pamac.Config ("/etc/pamac.conf");
			if (pamac_config.recurse) {
				transaction.flags |= Alpm.TransFlag.RECURSE;
			}
			Pamac.Package pkg = transaction.find_local_satisfier ("yaourt");
			if (pkg.name == "") {
				support_aur (false, false);
			} else {
				support_aur (pamac_config.enable_aur, pamac_config.search_aur);
			}

			set_buttons_sensitive (false);

			// sort by name by default
			sortinfo = {0, Gtk.SortType.ASCENDING};
			update_lists ();
		}

		public void support_aur (bool enable_aur, bool search_aur) {
			if (enable_aur) {
				search_aur_button.set_active (search_aur);
				search_aur_box.set_visible (true);
			} else {
				search_aur_button.set_active (false);
				search_aur_box.set_visible (false);
			}
		}

		public void set_buttons_sensitive (bool sensitive) {
			valid_button.set_sensitive (sensitive);
			cancel_button.set_sensitive (sensitive);
		}

		public void show_all_pkgs () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			transaction.get_all_pkgs.begin ((obj, res) => {
				var pkgs = transaction.get_all_pkgs.end (res);
				populate_packages_list (pkgs);
				this.get_window ().set_cursor (null);
			});
		}

		public void update_lists () {
			Gtk.TreeIter iter;
			Gtk.TreeSelection selection;
			selection = repos_treeview.get_selection ();
			selection.changed.disconnect (on_repos_treeview_selection_changed);
			foreach (var repo in transaction.get_repos_names ()) {
				repos_list.insert_with_values (out iter, -1, 0, repo);
			}
			repos_list.insert_with_values (out iter, -1, 0, dgettext (null, "local"));
			repos_list.get_iter_first (out iter);
			selection.select_iter (iter);
			selection.changed.connect_after (on_repos_treeview_selection_changed);

			selection = groups_treeview.get_selection ();
			selection.changed.disconnect (on_groups_treeview_selection_changed);
			foreach (var grpname in transaction.get_groups_names ()) {
				groups_list.insert_with_values (out iter, -1, 0, grpname);
			}
			groups_list.set_sort_column_id (0, Gtk.SortType.ASCENDING);
			groups_list.get_iter_first (out iter);
			selection.select_iter (iter);
			selection.changed.connect_after (on_groups_treeview_selection_changed);

			selection = states_treeview.get_selection ();
			selection.changed.disconnect (on_states_treeview_selection_changed);
			states_list.insert_with_values (out iter, -1, 0, dgettext (null, "Installed"));
			//states_list.insert_with_values (out iter, -1, 0, dgettext (null, "Uninstalled"));
			states_list.insert_with_values (out iter, -1, 0, dgettext (null, "Orphans"));
			states_list.insert_with_values (out iter, -1, 0, dgettext (null, "To install"));
			states_list.insert_with_values (out iter, -1, 0, dgettext (null, "To remove"));
			states_list.get_iter_first (out iter);
			selection.select_iter (iter);
			selection.changed.connect_after (on_states_treeview_selection_changed);
		}

		public void set_infos_list (Pamac.Package pkg) {
			name_label.set_markup ("<big><b>%s  %s</b></big>".printf (pkg.name, pkg.version));
			desc_label.set_markup (Markup.escape_text (pkg.desc));
			string url = Markup.escape_text (pkg.url);
			if (pkg.repo == "AUR") {
				string aur_url = "http://aur.archlinux.org/packages/" + pkg.name;
				link_label.set_markup ("<a href=\"%s\">%s</a>\n\n<a href=\"%s\">%s</a>".printf (url, url, aur_url, aur_url));
			} else {
				link_label.set_markup ("<a href=\"%s\">%s</a>".printf (url, url));
			}
			StringBuilder licenses = new StringBuilder ();
			licenses.append (dgettext (null, "Licenses"));
			licenses.append (": ");
			licenses.append (pkg.licenses);
			licenses_label.set_markup (licenses.str);
		}

		public void set_deps_list (string pkgname) {
			deps_list.clear ();
			Gtk.TreeIter iter;
			PackageDeps deps = transaction.get_pkg_deps (pkgname);
			int i;
			if (deps.depends.length != 0) {
				deps_list.insert_with_values (out iter, -1,
												0, dgettext (null, "Depends On") + ":",
												1, deps.depends[0]);
				i = 1;
				while (i < deps.depends.length) {
					deps_list.insert_with_values (out iter, -1,
												1, deps.depends[i]);
					i++;
				}
			}
			if (deps.optdepends.length != 0) {
				string[] uninstalled_optdeps = transaction.get_pkg_uninstalled_optdeps (pkgname);
				string optdep = deps.optdepends[0];
				if ((optdep in uninstalled_optdeps) == false) {
					optdep = optdep + " [" + dgettext (null, "Installed") + "]";
				}
				deps_list.insert_with_values (out iter, -1,
												0, dgettext (null, "Optional Dependencies") + ":",
												1, optdep);
				i = 1;
				while (i < deps.optdepends.length) {
					optdep = deps.optdepends[i];
					if ((optdep in uninstalled_optdeps) == false) {
						optdep = optdep + " [" + dgettext (null, "Installed") + "]";
					}
					deps_list.insert_with_values (out iter, -1, 1, optdep);
					i++;
				}
			}
			if (deps.repo == "local") {
				if (deps.requiredby.length != 0) {
					deps_list.insert_with_values (out iter, -1,
													0, dgettext (null, "Required By") + ":",
													1, deps.requiredby[0]);
					i = 1;
					while (i < deps.requiredby.length) {
						deps_list.insert_with_values (out iter, -1,
													1, deps.requiredby[i]);
						i++;
					}
				}
			}
			if (deps.repo == "local") {
				if (deps.optionalfor.length != 0) {
					deps_list.insert_with_values (out iter, -1,
													0, dgettext (null, "Optional For") + ":",
													1, deps.optionalfor[0]);
					i = 1;
					while (i < deps.optionalfor.length) {
						deps_list.insert_with_values (out iter, -1,
													1, deps.optionalfor[i]);
						i++;
					}
				}
			}
			if (deps.provides.length != 0) {
				deps_list.insert_with_values (out iter, -1,
												0, dgettext (null, "Provides") + ":",
												1, deps.provides[0]);
				i = 1;
				while (i < deps.provides.length) {
					deps_list.insert_with_values (out iter, -1,
												1, deps.provides[i]);
					i++;
				}
			}
			if (deps.replaces.length != 0) {
				deps_list.insert_with_values (out iter, -1,
												0, dgettext (null, "Replaces") + ":",
												1, deps.replaces[0]);
				i = 1;
				while (i < deps.replaces.length) {
					deps_list.insert_with_values (out iter, -1,
												1, deps.replaces[i]);
					i++;
				}
			}
			if (deps.conflicts.length != 0) {
				deps_list.insert_with_values (out iter, -1,
												0, dgettext (null, "Conflicts With") + ":",
												1, deps.conflicts[0]);
				i = 1;
				while (i < deps.conflicts.length) {
					deps_list.insert_with_values (out iter, -1,
												1, deps.conflicts[i]);
					i++;
				}
			}
		}

		public void set_details_list (string pkgname) {
			details_list.clear ();
			Gtk.TreeIter iter;
			PackageDetails details = transaction.get_pkg_details (pkgname);
			int i;
			if (details.repo != "local" && details.repo != "AUR") {
				details_list.insert_with_values (out iter, -1,
													0, dgettext (null, "Repository") + ":",
													1, details.repo);
			}
			if (details.groups.length != 0) {
				details_list.insert_with_values (out iter, -1,
												0, dgettext (null, "Groups") + ":",
												1, details.groups[0]);
				i = 1;
				while (i < details.groups.length) {
					details_list.insert_with_values (out iter, -1,
												1, details.groups[i]);
					i++;
				}
			}
			if (details.repo == "AUR") {
				details_list.insert_with_values (out iter, -1,
														0, dgettext (null, "Maintainer") + ":",
														1, details.packager);
				details_list.insert_with_values (out iter, -1,
														0, dgettext (null, "First Submitted") + ":",
														1, details.build_date);
				details_list.insert_with_values (out iter, -1,
														0, dgettext (null, "Last Modified") + ":",
														1, details.install_date);
			} else {
				details_list.insert_with_values (out iter, -1,
														0, dgettext (null, "Packager") + ":",
														1, details.packager);
				details_list.insert_with_values (out iter, -1,
														0, dgettext (null, "Build Date") + ":",
														1, details.build_date);
			}
			if (details.repo == "local") {
				details_list.insert_with_values (out iter, -1,
													0, dgettext (null, "Install Date") + ":",
													1, details.install_date);
				string reason;
				if (details.reason == Alpm.Package.Reason.EXPLICIT) {
					reason = dgettext (null, "Explicitly installed");
				} else if (details.reason == Alpm.Package.Reason.DEPEND) {
					reason = dgettext (null, "Installed as a dependency for another package");
				} else {
					reason = dgettext (null, "Unknown");
				}
				details_list.insert_with_values (out iter, -1,
													0, dgettext (null, "Install Reason") + ":",
													1, reason);
			}
			if (details.repo != "local" && details.repo != "AUR") {
				details_list.insert_with_values (out iter, -1,
													0, dgettext (null, "Signatures") + ":",
													1, details.has_signature);
			}
			if (details.repo == "AUR") {
				details_list.insert_with_values (out iter, -1,
													0, dgettext (null, "Votes") + ":",
													1, details.reason.to_string ());
				if (details.has_signature != "") {
					details_list.insert_with_values (out iter, -1,
														0, dgettext (null, "Out of Date") + ":",
														1, details.has_signature);
				}
			}
			if (details.repo == "local") {
				if (details.backups.length != 0) {
					details_list.insert_with_values (out iter, -1,
													0, dgettext (null, "Backup files") + ":",
													1, "/" + details.backups[0]);
					i = 1;
					while (i < details.backups.length) {
						details_list.insert_with_values (out iter, -1,
													1, "/" + details.backups[i]);
						i++;
					}
				}
			}
		}

		public void set_files_list (string pkgname) {
			StringBuilder text = new StringBuilder (); 
			foreach (var file in transaction.get_pkg_files (pkgname)) {
				if (text.len != 0) {
					text.append ("\n");
				}
				text.append ("/");
				text.append (file);
			}
			files_textview.buffer.set_text (text.str, (int) text.len);
		}

		public void populate_packages_list (Pamac.Package[] pkgs) {
			packages_treeview.freeze_child_notify ();
			packages_treeview.set_model (null);

			// populate liststore
			packages_list = new PackagesModel (pkgs, this);

			// sort liststore
			int column = sortinfo.column_number;
			switch (column) {
				case 0:
					packages_list.sort_by_name (sortinfo.sort_type);
					break;
				case 1:
					packages_list.sort_by_state (sortinfo.sort_type);
					break;
				case 2:
					packages_list.sort_by_version (sortinfo.sort_type);
					break;
				case 3:
					packages_list.sort_by_repo (sortinfo.sort_type);
					break;
				case 4:
					packages_list.sort_by_size (sortinfo.sort_type);
					break;
				default:
					break;
			}

			packages_treeview.set_model (packages_list);
			packages_treeview.thaw_child_notify ();

			this.get_window ().set_cursor (null);
		}

		public void refresh_packages_list () {
			int current_page = filters_notebook.get_current_page ();
			if (current_page == 0) {
				Gtk.TreeSelection selection = search_treeview.get_selection ();
				if (selection.get_selected (null, null)) {
					on_search_treeview_selection_changed ();
				} else {
					show_all_pkgs ();
				}
			} else if (current_page == 1) {
				on_groups_treeview_selection_changed ();
			} else if (current_page == 2) {
				on_states_treeview_selection_changed ();
			} else if (current_page == 3) {
				on_repos_treeview_selection_changed ();
			}
		}

		public void display_package_properties () {
			Gtk.TreeSelection selection = packages_treeview.get_selection ();
			GLib.List<Gtk.TreePath> selected = selection.get_selected_rows (null);
			if (selected.length () > 0) {
				// display info for the first package of the selection
				Pamac.Package pkg = packages_list.get_pkg_at_path (selected.nth_data (0));
				if (pkg.name == dgettext (null, "No package found")) {
					return;
				}
				if (pkg.repo == "local") {
					deps_scrolledwindow.visible = true;
					files_scrolledwindow.visible = true;
				} else if (pkg.repo == "AUR") {
					deps_scrolledwindow.visible = false;
					files_scrolledwindow.visible = false;
				} else {
					deps_scrolledwindow.visible = true;
					files_scrolledwindow.visible = false;
				}
				switch (properties_notebook.get_current_page ()) {
					case 0:
						set_infos_list (pkg);
						break;
					case 1:
						set_deps_list (pkg.name);
						break;
					case 2:
						set_details_list (pkg.name);
						break;
					case 3:
						set_files_list (pkg.name);
						break;
					default:
						break;
				}
			}
		}

		[GtkCallback]
		public void on_packages_treeview_selection_changed () {
			display_package_properties ();
		}

		[GtkCallback]
		public void on_properties_notebook_switch_page (Gtk.Widget page, uint page_num) {
			display_package_properties ();
		}

		[GtkCallback]
		public void on_packages_treeview_row_activated (Gtk.TreeView treeview, Gtk.TreePath path, Gtk.TreeViewColumn column) {
			Gtk.TreeIter iter;
			if (packages_list.get_iter (out iter, path)) {
				GLib.Value val;
				packages_list.get_value (iter, 0, out val);
				string name = val.get_string ();
				if (name != dgettext (null, "No package found")) {
					if (transaction.to_add.remove (name)) {
					} else if (transaction.to_remove.remove (name)) {
					} else if (transaction.to_build.remove (name)) {
					} else {
						packages_list.get_value (iter, 3, out val);
						string db_name = val.get_string ();
						if (db_name == "local") {
							if (transaction.should_hold (name) == false) {
								transaction.to_remove.add ((owned) name);
							}
						} else if (db_name == "AUR") {
							transaction.to_build.add ((owned) name);
						} else {
							transaction.to_add.add ((owned) name);
						}
					}
				}
			}
			if (transaction.to_add.length + transaction.to_remove.length + transaction.to_build.length == 0) {
				set_buttons_sensitive (false);
			} else {
				set_buttons_sensitive (true);
			}
			// force a display refresh
			packages_treeview.queue_draw ();
		}

		void on_install_item_activate () {
			Pamac.Package find_pkg;
			foreach (Pamac.Package pkg in selected_pkgs) {
				if (pkg.repo == "AUR") {
					transaction.to_build.add (pkg.name);
				} else {
					find_pkg = transaction.find_local_pkg (pkg.name);
					if (find_pkg.name == "") {
						transaction.to_add.add (pkg.name);
					}
				}
			}
			if (transaction.to_add.length != 0 || transaction.to_build.length != 0) {
				set_buttons_sensitive (true);
			}
		}

		void on_reinstall_item_activate () {
			foreach (Pamac.Package pkg in selected_pkgs) {
				transaction.to_remove.remove (pkg.name);
				if (pkg.repo == "local") {
					transaction.to_add.add (pkg.name);
				}
			}
			if (transaction.to_add.length != 0) {
				set_buttons_sensitive (true);
			}
		}

		void on_remove_item_activate () {
			foreach (Pamac.Package pkg in selected_pkgs) {
				transaction.to_add.remove (pkg.name);
				if (transaction.should_hold (pkg.name) == false) {
					if (pkg.repo == "local") {
						transaction.to_remove.add (pkg.name);
					}
				}
			}
			if (transaction.to_remove.length != 0) {
				set_buttons_sensitive (true);
			}
		}

		void on_deselect_item_activate () {
			foreach (Pamac.Package pkg in selected_pkgs) {
				if (transaction.to_add.remove (pkg.name)) {
				} else if (transaction.to_remove.remove (pkg.name)) {
				} else if (transaction.to_build.remove (pkg.name)) {
				}
			}
			if (transaction.to_add.length == 0 && transaction.to_remove.length == 0
					&& transaction.to_load.length == 0 && transaction.to_build.length == 0) {
				set_buttons_sensitive (false);
			}
		}

		public void choose_opt_dep (Pamac.Package[] pkgs) {
			foreach (Pamac.Package pkg in pkgs) {
				var choose_dep_dialog = new ChooseDependenciesDialog (transaction, pkg.name, this);
				if (choose_dep_dialog.run () == Gtk.ResponseType.OK) {
					choose_dep_dialog.deps_list.foreach ((model, path, iter) => {
						GLib.Value val;
						choose_dep_dialog.deps_list.get_value (iter, 0, out val);
						bool selected = val.get_boolean ();
						if (selected) {
							choose_dep_dialog.deps_list.get_value (iter, 1, out val);
							string name = val.get_string ();
							transaction.to_add.add ((owned) name);
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
			if (transaction.to_add.length != 0) {
				set_buttons_sensitive (true);
			}
		}

		void on_explicitly_installed_item_activate () {
			foreach (Pamac.Package pkg in selected_pkgs) {
				transaction.start_set_pkgreason (pkg.name, Alpm.Package.Reason.EXPLICIT);
			}
			refresh_packages_list ();
		}

		[GtkCallback]
		public bool on_packages_treeview_button_press_event (Gdk.EventButton event) {
			packages_treeview.grab_focus ();
			// Check if right mouse button was clicked
			if (event.type == Gdk.EventType.BUTTON_PRESS && event.button == 3) {
				Gtk.TreePath? treepath;
				Pamac.Package clicked_pkg;
				Gtk.TreeSelection selection = packages_treeview.get_selection ();
				packages_treeview.get_path_at_pos ((int) event.x, (int) event.y, out treepath, null, null, null);
				clicked_pkg = packages_list.get_pkg_at_path (treepath);;
				if (clicked_pkg.name == dgettext (null, "No package found")) {
					return true;
				}
				if (selection.path_is_selected (treepath) == false) {
					selection.unselect_all ();
					selection.select_path (treepath);
				}
				GLib.List<Gtk.TreePath> selected_paths = selection.get_selected_rows (null);
				deselect_item.set_sensitive (false);
				install_item.set_sensitive (false);
				remove_item.set_sensitive (false);
				reinstall_item.set_sensitive (false);
				install_optional_deps_item.set_sensitive (false);
				explicitly_installed_item.set_sensitive (false);
				selected_pkgs = {};
				foreach (Gtk.TreePath path in selected_paths) {
					selected_pkgs += packages_list.get_pkg_at_path (path);
				}
				foreach (Pamac.Package pkg in selected_pkgs) {
					if (transaction.to_add.contains (pkg.name)
							|| transaction.to_remove.contains (pkg.name)
							|| transaction.to_build.contains (pkg.name)) {
						deselect_item.set_sensitive (true);
						break;
					}
				}
				foreach (Pamac.Package pkg in selected_pkgs) {
					if (pkg.repo != "local") {
						install_item.set_sensitive (true);
						break;
					}
				}
				foreach (Pamac.Package pkg in selected_pkgs) {
					if (pkg.repo == "local") {
						remove_item.set_sensitive (true);
						break;
					}
				}
				if (selected_pkgs.length == 1) {
					clicked_pkg = selected_pkgs[0];
					if (clicked_pkg.repo == "local") {
						if (transaction.get_pkg_uninstalled_optdeps (clicked_pkg.name).length != 0) {
							install_optional_deps_item.set_sensitive (true);
						}
						if (clicked_pkg.reason == Alpm.Package.Reason.DEPEND) {
							explicitly_installed_item.set_sensitive (true);
						}
						Pamac.Package find_pkg = transaction.find_sync_pkg (clicked_pkg.name);
						if (find_pkg.name != "") {
							if (Alpm.pkg_vercmp (find_pkg.version, clicked_pkg.version) == 0) {
								reinstall_item.set_sensitive (true);
							}
						}
					}
				}
				right_click_menu.popup (null, null, null, event.button, event.time);
				return true;
			} else {
				return false;
			}
		}

		[GtkCallback]
		public void on_name_column_clicked () {
			Gtk.SortType new_order;
			if (name_column.sort_indicator == false) {
				new_order = Gtk.SortType.ASCENDING;
			} else {
				if (sortinfo.sort_type == Gtk.SortType.ASCENDING) {
					new_order =  Gtk.SortType.DESCENDING;
				} else {
					new_order =  Gtk.SortType.ASCENDING;
				}
			}
			packages_list.sort_by_name (new_order);
			// force a display refresh
			packages_treeview.queue_draw ();
		}

		[GtkCallback]
		public void on_state_column_clicked () {
			Gtk.SortType new_order;
			if (state_column.sort_indicator == false) {
				new_order = Gtk.SortType.ASCENDING;
			} else {
				if (sortinfo.sort_type == Gtk.SortType.ASCENDING) {
					new_order =  Gtk.SortType.DESCENDING;
				} else {
					new_order =  Gtk.SortType.ASCENDING;
				}
			}
			packages_list.sort_by_state (new_order);
			// force a display refresh
			packages_treeview.queue_draw ();
		}

		[GtkCallback]
		public void on_version_column_clicked () {
			Gtk.SortType new_order;
			if (version_column.sort_indicator == false) {
				new_order = Gtk.SortType.ASCENDING;
			} else {
				if (sortinfo.sort_type == Gtk.SortType.ASCENDING) {
					new_order =  Gtk.SortType.DESCENDING;
				} else {
					new_order =  Gtk.SortType.ASCENDING;
				}
			}
			packages_list.sort_by_version (new_order);
			// force a display refresh
			packages_treeview.queue_draw ();
		}

		[GtkCallback]
		public void on_repo_column_clicked () {
			Gtk.SortType new_order;
			if (repo_column.sort_indicator == false) {
				new_order = Gtk.SortType.ASCENDING;
			} else {
				if (sortinfo.sort_type == Gtk.SortType.ASCENDING) {
					new_order =  Gtk.SortType.DESCENDING;
				} else {
					new_order =  Gtk.SortType.ASCENDING;
				}
			}
			packages_list.sort_by_repo (new_order);
			// force a display refresh
			packages_treeview.queue_draw ();
		}

		[GtkCallback]
		public void on_size_column_clicked () {
			Gtk.SortType new_order;
			if (size_column.sort_indicator == false) {
				new_order = Gtk.SortType.ASCENDING;
			} else {
				if (sortinfo.sort_type == Gtk.SortType.ASCENDING) {
					new_order =  Gtk.SortType.DESCENDING;
				} else {
					new_order =  Gtk.SortType.ASCENDING;
				}
			}
			packages_list.sort_by_size (new_order);
			// force a display refresh
			packages_treeview.queue_draw ();
		}

		[GtkCallback]
		public void on_search_entry_activate () {
			string search_string = search_entry.get_text ();
			if (search_string != "") {
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				transaction.search_pkgs.begin (search_string, search_aur_button.get_active (), (obj, res) => {
					var pkgs = transaction.search_pkgs.end (res);
					if (pkgs.length != 0) {
						// add search string in search_list if needed
						bool found = false;
						Gtk.TreeIter? iter;
						Gtk.TreeModel model;
						Gtk.TreeSelection selection = search_treeview.get_selection ();
						// check if search string is already selected in search list
						if (selection.get_selected (out model, out iter)) {
							GLib.Value val;
							model.get_value (iter, 0, out val);
							string selected_string = val.get_string ();
							if (selected_string == search_string) {
								found = true;
								// we need to populate packages_list
								populate_packages_list (pkgs);
							} else {
								search_list.foreach ((_model, _path, _iter) => {
									GLib.Value line;
									model.get_value (_iter, 0, out line);
									if ((string) line == search_string) {
										found = true;
										// block the signal to not populate when we select the iter in search_list
										selection.changed.disconnect (on_search_treeview_selection_changed);
										selection.select_iter (_iter);
										selection.changed.connect_after (on_search_treeview_selection_changed);
										populate_packages_list (pkgs);
									}
									return found;
								});
							}
						}
						if (found == false) {
							search_list.insert_with_values (out iter, -1, 0, search_string);
							// block the signal to not populate when we select the iter in search_list
							selection.changed.disconnect (on_search_treeview_selection_changed);
							selection.select_iter (iter);
							selection.changed.connect_after (on_search_treeview_selection_changed);
							populate_packages_list (pkgs);
						}
					} else {
						// populate with empty lists
						populate_packages_list (pkgs);
					}
				});
			}
		}

		[GtkCallback]
		public void  on_search_entry_icon_press (Gtk.EntryIconPosition p0, Gdk.Event? p1) {
			on_search_entry_activate ();
		}

		[GtkCallback]
		public void on_search_treeview_selection_changed () {
			Gtk.TreeModel model;
			Gtk.TreeIter? iter;
			Gtk.TreeSelection selection = search_treeview.get_selection ();
			if (selection.get_selected (out model, out iter)) {
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				GLib.Value val;
				model.get_value (iter, 0, out val);
				string search_string = val.get_string ();
				transaction.search_pkgs.begin (search_string, search_aur_button.get_active (), (obj, res) => {
					var pkgs = transaction.search_pkgs.end (res);
					populate_packages_list (pkgs);
				});
			}
		}

		[GtkCallback]
		public void on_groups_treeview_selection_changed () {
			Gtk.TreeModel model;
			Gtk.TreeIter? iter;
			Gtk.TreeSelection selection = groups_treeview.get_selection ();
			if (selection.get_selected (out model, out iter)) {
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				GLib.Value val;
				model.get_value (iter, 0, out val);
				string grp_name = val.get_string ();
				transaction.get_group_pkgs.begin (grp_name, (obj, res) => {
					var pkgs = transaction.get_group_pkgs.end (res);
					populate_packages_list (pkgs);
				});
			}
		}

		[GtkCallback]
		public void on_states_treeview_selection_changed () {
			Gtk.TreeModel model;
			Gtk.TreeIter? iter;
			Gtk.TreeSelection selection = states_treeview.get_selection ();
			if (selection.get_selected (out model, out iter)) {
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				GLib.Value val;
				model.get_value (iter, 0, out val);
				string state = val.get_string ();
				Pamac.Package[] pkgs = {};
				Pamac.Package find_pkg;
				if (state == dgettext (null, "To install")) {
					foreach (string name in transaction.to_add) {
						find_pkg = transaction.find_local_pkg (name);
						if (find_pkg.name != "") {
							pkgs += find_pkg;
						} else {
							find_pkg = transaction.find_sync_pkg (name);
							if (find_pkg.name != "") {
								pkgs += find_pkg;
							}
						}
					}
					populate_packages_list (pkgs);
				} else if (state == dgettext (null, "To remove")) {
					foreach (string name in transaction.to_remove) {
						find_pkg = transaction.find_local_pkg (name);
						if (find_pkg.name != "") {
							pkgs += find_pkg;
						}
					}
					populate_packages_list (pkgs);
				} else if (state == dgettext (null, "Installed")) {
					transaction.get_installed_pkgs.begin ((obj, res) => {
						pkgs = transaction.get_installed_pkgs.end (res);
						populate_packages_list (pkgs);
					});
				} else if (state == dgettext (null, "Uninstalled")) {
					//transaction.get_sync_pkgs.begin ((obj, res) => {
						//pkgs = transaction.get_sync_pkgs.end (res);
						//populate_packages_list (pkgs);
					//});
				} else if (state == dgettext (null, "Orphans")) {
					transaction.get_orphans.begin ((obj, res) => {
						pkgs = transaction.get_orphans.end (res);
						populate_packages_list (pkgs);
					});
				}
			}
		}

		[GtkCallback]
		public void on_repos_treeview_selection_changed () {
			Gtk.TreeModel model;
			Gtk.TreeIter? iter;
			Gtk.TreeSelection selection = repos_treeview.get_selection ();
			if (selection.get_selected (out model, out iter)) {
				this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
				GLib.Value val;
				model.get_value (iter, 0, out val);
				string repo = val.get_string ();
				if (repo == dgettext (null, "local")) {
					transaction.get_local_pkgs.begin ((obj, res) => {
						var pkgs = transaction.get_local_pkgs.end (res);
						populate_packages_list (pkgs);
					});
				} else {
					transaction.get_repo_pkgs.begin (repo, (obj, res) => {
						var pkgs = transaction.get_repo_pkgs.end (res);
						populate_packages_list (pkgs);
					});
				}
			}
		}

		[GtkCallback]
		public void on_filters_notebook_switch_page (Gtk.Widget page, uint page_num) {
			refresh_packages_list ();
		}

		[GtkCallback]
		public void on_history_item_activate () {
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
				history_dialog.run ();
				history_dialog.destroy ();
				while (Gtk.events_pending ()) {
					Gtk.main_iteration ();
				}
			}
		}

		[GtkCallback]
		public void on_local_item_activate () {
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
					foreach (string path in packages_paths) {
						transaction.to_load.add (path);
					}
					this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
					chooser.destroy ();
					while (Gtk.events_pending ()) {
						Gtk.main_iteration ();
					}
					transaction.run ();
				}
			} else {
				chooser.destroy ();
				while (Gtk.events_pending ()) {
					Gtk.main_iteration ();
				}
			}
		}

		public async void run_preferences_dialog () {
			SourceFunc callback = run_preferences_dialog.callback;
			ulong handler_id = transaction.daemon.get_authorization_finished.connect ((authorized) => {
				if (authorized) {
					var preferences_dialog = new PreferencesDialog (transaction, this);
					preferences_dialog.run ();
					preferences_dialog.destroy ();
					while (Gtk.events_pending ()) {
						Gtk.main_iteration ();
					}
				}
				Idle.add((owned) callback);
			});
			transaction.start_get_authorization ();
			yield;
			transaction.daemon.disconnect (handler_id);
		}

		[GtkCallback]
		public void on_preferences_item_activate () {
			run_preferences_dialog.begin ();
		}

		[GtkCallback]
		public void on_about_item_activate () {
			Gtk.show_about_dialog (
				this,
				"program_name", "Pamac",
				"logo_icon_name", "system-software-install",
				"comments", dgettext (null, "A Gtk3 frontend for libalpm"),
				"copyright", dgettext (null, "Copyright © 2015 Guillaume Benoit"),
				"version", VERSION,
				"license_type", Gtk.License.GPL_3_0,
				"website", "http://manjaro.org");
		}

		[GtkCallback]
		public void on_valid_button_clicked () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			transaction.run ();
		}

		[GtkCallback]
		public void on_cancel_button_clicked () {
			transaction.clear_lists ();
			set_buttons_sensitive (false);
			// force a display refresh
			packages_treeview.queue_draw ();
		}

		[GtkCallback]
		public void on_refresh_button_clicked () {
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			transaction.start_refresh (0);
		}

		public void on_transaction_finished (bool error) {
			if (error == false) {
				set_buttons_sensitive (false);
				refresh_packages_list ();
			}
			transaction.to_load.remove_all ();
			this.get_window ().set_cursor (null);
		}
	}
}
