/*
 *  pamac-vala
 *
 *  Copyright (C) 2014, 2015 Guillaume Benoit <guillaume@manjaro.org>
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

const string VERSION = "2.1.1";

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
		public TreeView packages_treeview;
		[GtkChild]
		public TreeViewColumn state_column;
		[GtkChild]
		public TreeViewColumn name_column;
		[GtkChild]
		public TreeViewColumn version_column;
		[GtkChild]
		public TreeViewColumn repo_column;
		[GtkChild]
		public TreeViewColumn size_column;
		[GtkChild]
		public Notebook filters_notebook;
		[GtkChild]
		public SearchEntry search_entry;
		[GtkChild]
		public TreeView search_treeview;
		[GtkChild]
		public TreeView groups_treeview;
		[GtkChild]
		public TreeView states_treeview;
		[GtkChild]
		public TreeView repos_treeview;
		[GtkChild]
		public TreeView deps_treeview;
		[GtkChild]
		public TreeView details_treeview;
		[GtkChild]
		public ScrolledWindow deps_scrolledwindow;
		[GtkChild]
		public ScrolledWindow details_scrolledwindow;
		[GtkChild]
		public ScrolledWindow files_scrolledwindow;
		[GtkChild]
		public Label name_label;
		[GtkChild]
		public Label desc_label;
		[GtkChild]
		public Label link_label;
		[GtkChild]
		public Label licenses_label;
		[GtkChild]
		public TextView files_textview;
		[GtkChild]
		public Switch search_aur_button;
		[GtkChild]
		public Button valid_button;
		[GtkChild]
		public Button cancel_button;

		// menu
		Gtk.Menu right_click_menu;
		Gtk.MenuItem deselect_item;
		Gtk.MenuItem install_item;
		Gtk.MenuItem remove_item;
		Gtk.SeparatorMenuItem separator_item;
		Gtk.MenuItem reinstall_item;
		Gtk.MenuItem install_optional_deps_item;
		Gtk.MenuItem explicitly_installed_item;
		GLib.List<Pamac.Package> selected_pkgs;

		// liststore
		ListStore search_list;
		ListStore groups_list;
		ListStore states_list;
		ListStore repos_list;
		ListStore deps_list;
		ListStore details_list;

		PackagesModel packages_list;
		HashTable<string, Json.Array> aur_results;

		Pamac.Config pamac_config;
		public Transaction transaction;

		public SortInfo sortinfo;

		//dialogs
		HistoryDialog history_dialog;
		PackagesChooserDialog packages_chooser_dialog;

		public ManagerWindow (Gtk.Application application) {
			Object (application: application);

			aur_results = new HashTable<string, Json.Array> (str_hash, str_equal);

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

			pamac_config = new Pamac.Config ("/etc/pamac.conf");

			transaction = new Pamac.Transaction (this as ApplicationWindow);
			transaction.check_aur = pamac_config.enable_aur;
			transaction.finished.connect (on_emit_trans_finished);

			history_dialog = new HistoryDialog (this);
			packages_chooser_dialog = new PackagesChooserDialog (this, transaction);

			set_buttons_sensitive (false);
			search_aur_button.set_active (pamac_config.enable_aur);

			// sort by name by default
			sortinfo = {0, SortType.ASCENDING};
			update_lists ();
		}

		public void enable_aur (bool enable) {
			search_aur_button.set_active (enable);
		}

		public void set_buttons_sensitive (bool sensitive) {
			valid_button.set_sensitive (sensitive);
			cancel_button.set_sensitive (sensitive);
		}

		public void show_all_pkgs () {
			this.get_window ().set_cursor (new Gdk.Cursor (Gdk.CursorType.WATCH));
			populate_packages_list (get_all_pkgs (transaction.alpm_config.handle));
			this.get_window ().set_cursor (null);
		}

		public void update_lists () {
			string[] grps = {};
			TreeIter iter;
			TreeSelection selection;
			selection = repos_treeview.get_selection ();
			selection.changed.disconnect (on_repos_treeview_selection_changed);
			foreach (var db in transaction.alpm_config.handle.syncdbs) {
				repos_list.insert_with_values (out iter, -1, 0, db.name);
				foreach (var grp in db.groupcache) {
					if ((grp.name in grps) == false) {
						grps += grp.name;
					}
				}
			}
			repos_list.insert_with_values (out iter, -1, 0, dgettext (null, "local"));
			repos_list.get_iter_first (out iter);
			selection.select_iter (iter);
			selection.changed.connect_after (on_repos_treeview_selection_changed);

			selection = groups_treeview.get_selection ();
			selection.changed.disconnect (on_groups_treeview_selection_changed);
			foreach (string name in grps)
				groups_list.insert_with_values (out iter, -1, 0, name);
			groups_list.set_sort_column_id (0, SortType.ASCENDING);
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
			string desc;
			if (pkg.alpm_pkg != null)
				desc = Markup.escape_text (pkg.alpm_pkg.desc);
			else
				desc = Markup.escape_text (pkg.aur_json.get_string_member ("Description"));
			desc_label.set_markup (desc);
			string url;
			if (pkg.alpm_pkg != null)
				url = Markup.escape_text (pkg.alpm_pkg.url);
			else
				url = Markup.escape_text (pkg.aur_json.get_string_member ("URL"));
			link_label.set_markup ("<a href=\"%s\">%s</a>".printf (url, url));
			StringBuilder licenses = new StringBuilder ();
			licenses.append (dgettext (null, "Licenses"));
			licenses.append (":");
			if (pkg.alpm_pkg != null) {
				foreach (var license in pkg.alpm_pkg.licenses) {
					licenses.append (" ");
					licenses.append (license);
				}
			} else {
				licenses.append (" ");
				licenses.append (pkg.aur_json.get_string_member ("License"));
			}
			licenses_label.set_markup (licenses.str);
		}

		public void set_deps_list (Alpm.Package pkg) {
			deps_list.clear ();
			TreeIter iter;
			unowned Alpm.List<Depend?> list = pkg.depends;
			size_t len = list.length;
			size_t i;
			if (len != 0) {
				deps_list.insert_with_values (out iter, -1,
												0, dgettext (null, "Depends On") + ":",
												1, list.nth_data (0).compute_string ());
				i = 1;
				while (i < len) {
					deps_list.insert_with_values (out iter, -1,
												1, list.nth_data (i).compute_string ());
					i++;
				}
			}
			list = pkg.optdepends;
			len = list.length;
			if (len != 0) {
				unowned Depend optdep = list.nth_data (0);
				unowned Alpm.Package? satisfier = find_satisfier (
											transaction.alpm_config.handle.localdb.pkgcache,
											optdep.name);
				string optdep_str = optdep.compute_string ();
				if (satisfier != null)
					optdep_str = optdep_str + " [" + dgettext (null, "Installed") + "]";
				deps_list.insert_with_values (out iter, -1,
												0, dgettext (null, "Optional Dependencies") + ":",
												1, optdep_str);
				i = 1;
				while (i < len) {
					optdep = list.nth_data (i);
					satisfier = find_satisfier (
											transaction.alpm_config.handle.localdb.pkgcache,
											optdep.name);
					optdep_str = optdep.compute_string ();
					if (satisfier != null)
						optdep_str = optdep_str + " [" + dgettext (null, "Installed") + "]";
					deps_list.insert_with_values (out iter, -1, 1, optdep_str);
					i++;
				}
			}
			if (pkg.origin == Alpm.Package.From.LOCALDB) {
				Alpm.List<string?> *str_list = pkg.compute_requiredby ();
				len = str_list->length;
				if (len != 0) {
					deps_list.insert_with_values (out iter, -1,
													0, dgettext (null, "Required By") + ":",
													1, str_list->nth_data (0));
					i = 1;
					while (i < len) {
						deps_list.insert_with_values (out iter, -1,
													1, str_list->nth_data (i));
						i++;
					}
				}
				Alpm.List.free_all (str_list);
			}
			list = pkg.provides;
			len = list.length;
			if (len != 0) {
				deps_list.insert_with_values (out iter, -1,
												0, dgettext (null, "Provides") + ":",
												1, list.nth_data (0).compute_string ());
				i = 1;
				while (i < len) {
					deps_list.insert_with_values (out iter, -1,
												1, list.nth_data (i).compute_string ());
					i++;
				}
			}
			list = pkg.replaces;
			len = list.length;
			if (len != 0) {
				deps_list.insert_with_values (out iter, -1,
												0, dgettext (null, "Replaces") + ":",
												1, list.nth_data (0).compute_string ());
				i = 1;
				while (i < len) {
					deps_list.insert_with_values (out iter, -1,
												1, list.nth_data (i).compute_string ());
					i++;
				}
			}
			list = pkg.conflicts;
			len = list.length;
			if (len != 0) {
				deps_list.insert_with_values (out iter, -1,
												0, dgettext (null, "Conflicts With") + ":",
												1, list.nth_data (0).compute_string ());
				i = 1;
				while (i < len) {
					deps_list.insert_with_values (out iter, -1,
												1, list.nth_data (i).compute_string ());
					i++;
				}
			}
		}

		public void set_details_list (Alpm.Package pkg) {
			details_list.clear ();
			TreeIter iter;
			if (pkg.origin == Alpm.Package.From.SYNCDB) {
				details_list.insert_with_values (out iter, -1,
													0, dgettext (null, "Repository") + ":",
													1, pkg.db.name);
			}
			unowned Alpm.List<string?> list = pkg.groups;
			size_t len = list.length;
			size_t i;
			if (len != 0) {
				details_list.insert_with_values (out iter, -1,
												0, dgettext (null, "Groups") + ":",
												1, list.nth_data (0));
				i = 1;
				while (i < len) {
					details_list.insert_with_values (out iter, -1,
												1, list.nth_data (i));
					i++;
				}
			}
			details_list.insert_with_values (out iter, -1,
													0, dgettext (null, "Packager") + ":",
													1, pkg.packager);
			if (pkg.origin == Alpm.Package.From.LOCALDB) {
				GLib.Time time = GLib.Time.local ((time_t) pkg.installdate);
				string strtime = time.format ("%a %d %b %Y %X %Z");
				details_list.insert_with_values (out iter, -1,
													0, dgettext (null, "Install Date") + ":",
													1, strtime);
				string reason;
				if (pkg.reason == Alpm.Package.Reason.EXPLICIT)
					reason = dgettext (null, "Explicitly installed");
				else if (pkg.reason == Alpm.Package.Reason.DEPEND)
					reason = dgettext (null, "Installed as a dependency for another package");
				else
					reason = dgettext (null, "Unknown");
				details_list.insert_with_values (out iter, -1,
													0, dgettext (null, "Install Reason") + ":",
													1, reason);
			}
			if (pkg.origin == Alpm.Package.From.SYNCDB) {
				details_list.insert_with_values (out iter, -1,
													0, dgettext (null, "Signatures") + ":",
													1, pkg.base64_sig != null ? "Yes" : "No");
			}
			if (pkg.origin == Alpm.Package.From.LOCALDB) {
				unowned Alpm.List<Backup?> backup_list = pkg.backup;
				len = backup_list.length;
				if (len != 0) {
					details_list.insert_with_values (out iter, -1,
													0, dgettext (null, "Backup files") + ":",
													1, "/" + backup_list.nth_data (0).name);
					i = 1;
					while (i < len) {
						details_list.insert_with_values (out iter, -1,
													1, "/" + backup_list.nth_data (i).name);
						i++;
					}
				}
			}
		}

		public void set_files_list (Alpm.Package pkg) {
			StringBuilder text = new StringBuilder (); 
			foreach (var file in pkg.files) {
				if (text.len != 0)
					text.append ("\n");
				text.append ("/");
				text.append (file.name);
			}
			files_textview.buffer.set_text (text.str, (int) text.len);
		}

		public async Alpm.List<Alpm.Package?> search_pkgs (string search_string, out Json.Array aur_pkgs) {
			var needles = new Alpm.List<string> ();
			string[] splitted = search_string.split (" ");
			foreach (unowned string part in splitted)
				needles.add (part);
			Alpm.List<unowned Alpm.Package?> pkgs = search_all_dbs (transaction.alpm_config.handle, needles);
			if (search_aur_button.get_active()) {
				if (aur_results.contains (search_string)) {
					aur_pkgs = aur_results.get (search_string);
				} else {
					aur_pkgs = AUR.search (splitted);
					aur_results.insert (search_string, aur_pkgs);
				}
			} else {
				aur_pkgs = new Json.Array ();
			}
			return pkgs;
		}

		public void populate_packages_list (Alpm.List<Alpm.Package?>? pkgs, Json.Array? aur_pkgs = new Json.Array ()) {
			packages_treeview.freeze_child_notify ();
			packages_treeview.set_model (null);

			// populate liststore
			packages_list = new PackagesModel (pkgs, aur_pkgs, this);

			// sort liststore
			int column = sortinfo.column_number;
			if (column == 0)
				packages_list.sort_by_name (sortinfo.sort_type);
			else if (column == 1)
				packages_list.sort_by_state (sortinfo.sort_type);
			else if (column == 2)
				packages_list.sort_by_version (sortinfo.sort_type);
			else if (column == 3)
				packages_list.sort_by_repo (sortinfo.sort_type);
			else if (column == 4)
				packages_list.sort_by_size (sortinfo.sort_type);

			packages_treeview.set_model (packages_list);
			packages_treeview.thaw_child_notify ();

			this.get_window ().set_cursor (null);
		}

		public void refresh_packages_list () {
			int current_page = filters_notebook.get_current_page ();
			if (current_page == 0) {
				TreeModel model;
				TreeIter? iter;
				TreeSelection selection = search_treeview.get_selection ();
				if (selection.get_selected (out model, out iter)) {
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

		[GtkCallback]
		public void on_packages_treeview_selection_changed () {
			TreeModel model;
			TreeSelection selection = packages_treeview.get_selection ();
			GLib.List<TreePath> selected = selection.get_selected_rows (out model);
			if (selected.length () == 1) {
				TreeIter iter;
				model.get_iter (out iter, selected.nth_data (0));
				Pamac.Package pkg = (Pamac.Package) iter.user_data;
				if (pkg.alpm_pkg != null) {
					set_infos_list (pkg);
					set_deps_list (pkg.alpm_pkg);
					set_details_list (pkg.alpm_pkg);
					deps_scrolledwindow.visible = true;
					details_scrolledwindow.visible =  true;
					if (pkg.alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
						set_files_list (pkg.alpm_pkg);
						files_scrolledwindow.visible = true;
					} else {
						files_scrolledwindow.visible = false;
					}
				} else if (pkg.aur_json != null) {
					set_infos_list (pkg);
					deps_scrolledwindow.visible = false;
					details_scrolledwindow.visible = false;
					files_scrolledwindow.visible = false;
				}
			}
		}

		[GtkCallback]
		public void on_packages_treeview_row_activated (TreeView treeview, TreePath path, TreeViewColumn column) {
			TreeIter iter;
			if (packages_list.get_iter (out iter, path)) {
				GLib.Value val;
				packages_list.get_value (iter, 0, out val);
				string name = val.get_string ();
				if (name != dgettext (null, "No package found")) {
					if (transaction.to_add.steal (name)) {
					} else if (transaction.to_remove.steal (name)) {
					} else if (transaction.to_build.steal (name)) {
					} else {
						packages_list.get_value (iter, 3, out val);
						string db_name = val.get_string ();
						if (db_name == "local") {
							if (transaction.alpm_config.holdpkgs.find_custom (name, strcmp) == null) {
								transaction.to_remove.insert (name, name);
							}
						} else if (db_name == "AUR") {
							transaction.to_build.insert (name, name);
						} else {
							transaction.to_add.insert (name, name);
						}
					}
				}
			}
			if (transaction.to_add.size () + transaction.to_remove.size () + transaction.to_build.size () == 0) {
				set_buttons_sensitive (false);
			} else {
				set_buttons_sensitive (true);
			}
			// force a display refresh
			packages_treeview.queue_draw ();
		}

		void on_install_item_activate () {
			unowned Alpm.Package? find_pkg = null;
			foreach (Pamac.Package pkg in selected_pkgs) {
				if (pkg.repo == "AUR")
					transaction.to_build.insert (pkg.name, pkg.name);
				else {
					find_pkg = transaction.alpm_config.handle.localdb.get_pkg (pkg.name);
					if (find_pkg == null)
						transaction.to_add.insert (pkg.name, pkg.name);
				}
			}
			if (transaction.to_add.size () != 0 || transaction.to_build.size () != 0) {
				set_buttons_sensitive (true);
			}
		}

		void on_reinstall_item_activate () {
			foreach (Pamac.Package pkg in selected_pkgs) {
				transaction.to_remove.steal (pkg.name);
				if (pkg.repo == "local")
					transaction.to_add.insert (pkg.name, pkg.name);
			}
			if (transaction.to_add.size () != 0)
				set_buttons_sensitive (true);
		}

		void on_remove_item_activate () {
			foreach (Pamac.Package pkg in selected_pkgs) {
				transaction.to_add.steal (pkg.name);
				if (transaction.alpm_config.holdpkgs.find_custom (pkg.name, strcmp) == null) {
					if (pkg.repo == "local")
						transaction.to_remove.insert (pkg.name, pkg.name);
				}
			}
			if (transaction.to_remove.size () != 0)
				set_buttons_sensitive (true);
		}

		void on_deselect_item_activate () {
			foreach (Pamac.Package pkg in selected_pkgs) {
				if (transaction.to_add.steal (pkg.name)) {
				} else if (transaction.to_remove.steal (pkg.name)) {
				} else if (transaction.to_build.steal (pkg.name)) {
				}
			}
			if (transaction.to_add.size () == 0 && transaction.to_remove.size () == 0
					&& transaction.to_load.size () == 0 && transaction.to_build.size () == 0) {
				set_buttons_sensitive (false);
			}
		}

		public void choose_opt_dep (GLib.List<Pamac.Package> pkgs) {
			uint nb;
			TreeIter iter;
			unowned Alpm.Package? found;
			foreach (Pamac.Package pkg in pkgs) {
				var choose_dep_dialog = new ChooseDependenciesDialog (this);
				nb = 0;
				foreach (var opt_dep in pkg.alpm_pkg.optdepends) {
					found = find_satisfier (transaction.alpm_config.handle.localdb.pkgcache, opt_dep.compute_string ());
					if (found == null) {
						choose_dep_dialog.deps_list.insert_with_values (out iter, -1,
												0, false,
												1, opt_dep.name,
												2, opt_dep.desc);
						nb += 1;
					}
				}
				choose_dep_dialog.label.set_markup ("<b>%s</b>".printf (
						dngettext (null, "%s has %u uninstalled optional dependency.\nChoose if you would like to install it:",
								"%s has %u uninstalled optional dependencies.\nChoose those you would like to install:", nb).printf (pkg.name, nb)));
				choose_dep_dialog.run ();
				choose_dep_dialog.hide ();
				while (Gtk.events_pending ())
					Gtk.main_iteration ();
				choose_dep_dialog.deps_list.foreach ((model, path, iter) => {
					GLib.Value val;
					bool selected;
					string name;
					choose_dep_dialog.deps_list.get_value (iter, 0, out val);
					selected = val.get_boolean ();
					if (selected) {
						choose_dep_dialog.deps_list.get_value (iter, 1, out val);
						name = val.get_string ();
						transaction.to_add.insert (name, name);
					}
					return false;
				}); 
			}
		}

		void on_install_optional_deps_item_activate () {
			choose_opt_dep (selected_pkgs);
			if (transaction.to_add.size () != 0)
				set_buttons_sensitive (true);
		}

		void on_explicitly_installed_item_activate () {
			foreach (Pamac.Package pkg in selected_pkgs) {
				transaction.set_pkgreason (pkg.name, Alpm.Package.Reason.EXPLICIT);
			}
			refresh_packages_list ();
		}

		[GtkCallback]
		public bool on_packages_treeview_button_press_event (Gdk.EventButton event) {
			packages_treeview.grab_focus ();
			// Check if right mouse button was clicked
			if (event.type == Gdk.EventType.BUTTON_PRESS && event.button == 3) {
				TreeIter iter;
				TreePath? treepath;
				Pamac.Package clicked_pkg;
				TreeSelection selection = packages_treeview.get_selection ();
				packages_treeview.get_path_at_pos ((int) event.x, (int) event.y, out treepath, null, null, null);
				packages_list.get_iter (out iter, treepath);
				clicked_pkg = (Pamac.Package) iter.user_data;
				if (clicked_pkg.name == dgettext (null, "No package found"))
					return true;
				if (selection.path_is_selected (treepath) == false) {
					selection.unselect_all ();
					selection.select_path (treepath);
				}
				GLib.List<TreePath> selected_paths = selection.get_selected_rows (null);
				deselect_item.set_sensitive (false);
				install_item.set_sensitive (false);
				remove_item.set_sensitive (false);
				reinstall_item.set_sensitive (false);
				install_optional_deps_item.set_sensitive (false);
				explicitly_installed_item.set_sensitive (false);
				selected_pkgs = new GLib.List<Pamac.Package> ();
				foreach (TreePath path in selected_paths) {
					packages_list.get_iter (out iter, path);
					clicked_pkg = (Pamac.Package) iter.user_data;
					selected_pkgs.append (clicked_pkg);
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
				if (selected_pkgs.length () == 1) {
					unowned Alpm.Package? find_pkg = null;
					clicked_pkg = selected_pkgs.nth_data (0);
					if (clicked_pkg.repo == "local") {
						unowned Alpm.List<Depend?> optdepends = clicked_pkg.alpm_pkg.optdepends;
						if (optdepends.length != 0) {
							uint nb = 0;
							unowned Alpm.Package? found;
							foreach (var opt_dep in optdepends) {
								found = find_satisfier (transaction.alpm_config.handle.localdb.pkgcache, opt_dep.compute_string ());
								if (found == null)
									nb += 1;
							}
							if (nb != 0)
								install_optional_deps_item.set_sensitive (true);
						}
						if (clicked_pkg.alpm_pkg.reason == Alpm.Package.Reason.DEPEND)
							explicitly_installed_item.set_sensitive (true);
						find_pkg = get_syncpkg (transaction.alpm_config.handle, clicked_pkg.name);
						if (find_pkg != null) {
							if (pkg_vercmp (find_pkg.version, clicked_pkg.version) == 0)
								reinstall_item.set_sensitive (true);
						}
					}
				}
				right_click_menu.popup (null, null, null, event.button, event.time);
				return true;
			} else
				return false;
		}

		[GtkCallback]
		public void on_name_column_clicked () {
			SortType new_order;
			if (name_column.sort_indicator == false)
				new_order = SortType.ASCENDING;
			else {
				if (sortinfo.sort_type == SortType.ASCENDING)
					new_order =  SortType.DESCENDING;
				else
					new_order =  SortType.ASCENDING;
			}
			packages_list.sort_by_name (new_order);
			// force a display refresh
			packages_treeview.queue_draw ();
		}

		[GtkCallback]
		public void on_state_column_clicked () {
			SortType new_order;
			if (state_column.sort_indicator == false)
				new_order = SortType.ASCENDING;
			else {
				if (sortinfo.sort_type == SortType.ASCENDING)
					new_order =  SortType.DESCENDING;
				else
					new_order =  SortType.ASCENDING;
			}
			packages_list.sort_by_state (new_order);
			// force a display refresh
			packages_treeview.queue_draw ();
		}

		[GtkCallback]
		public void on_version_column_clicked () {
			SortType new_order;
			if (version_column.sort_indicator == false)
				new_order = SortType.ASCENDING;
			else {
				if (sortinfo.sort_type == SortType.ASCENDING)
					new_order =  SortType.DESCENDING;
				else
					new_order =  SortType.ASCENDING;
			}
			packages_list.sort_by_version (new_order);
			// force a display refresh
			packages_treeview.queue_draw ();
		}

		[GtkCallback]
		public void on_repo_column_clicked () {
			SortType new_order;
			if (repo_column.sort_indicator == false)
				new_order = SortType.ASCENDING;
			else {
				if (sortinfo.sort_type == SortType.ASCENDING)
					new_order =  SortType.DESCENDING;
				else
					new_order =  SortType.ASCENDING;
			}
			packages_list.sort_by_repo (new_order);
			// force a display refresh
			packages_treeview.queue_draw ();
		}

		[GtkCallback]
		public void on_size_column_clicked () {
			SortType new_order;
			if (size_column.sort_indicator == false)
				new_order = SortType.ASCENDING;
			else {
				if (sortinfo.sort_type == SortType.ASCENDING)
					new_order =  SortType.DESCENDING;
				else
					new_order =  SortType.ASCENDING;
			}
			packages_list.sort_by_size (new_order);
			// force a display refresh
			packages_treeview.queue_draw ();
		}

		[GtkCallback]
		public void on_search_entry_activate () {
			string search_string = search_entry.get_text ();
			if (search_string != "") {
				this.get_window ().set_cursor (new Gdk.Cursor (Gdk.CursorType.WATCH));
				while (Gtk.events_pending ())
					Gtk.main_iteration ();
				search_pkgs.begin (search_string, (obj, res) => {
					Json.Array aur_pkgs;
					Alpm.List<Alpm.Package?> pkgs = search_pkgs.end (res, out aur_pkgs);
					if (pkgs.length != 0 || aur_pkgs.get_length () != 0) {
						// add search string in search_list if needed
						bool found = false;
						TreeIter? iter;
						TreeModel model;
						TreeSelection selection = search_treeview.get_selection ();
						// check if search string is already selected in search list
						if (selection.get_selected (out model, out iter)) {
							GLib.Value val;
							model.get_value (iter, 0, out val);
							string selected_string = val.get_string ();
							if (selected_string == search_string) {
								found = true;
								// we need to populate packages_list
								populate_packages_list (pkgs, aur_pkgs);
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
										populate_packages_list (pkgs, aur_pkgs);
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
							populate_packages_list (pkgs, aur_pkgs);
						}
					} else {
						// populate with empty lists
						populate_packages_list (pkgs, aur_pkgs);
					}
				});
			}
		}

		[GtkCallback]
		public void  on_search_entry_icon_press (EntryIconPosition p0, Gdk.Event? p1) {
			on_search_entry_activate ();
		}

		[GtkCallback]
		public void on_search_treeview_selection_changed () {
			TreeModel model;
			TreeIter? iter;
			TreeSelection selection = search_treeview.get_selection ();
			if (selection.get_selected (out model, out iter)) {
				this.get_window ().set_cursor (new Gdk.Cursor (Gdk.CursorType.WATCH));
				while (Gtk.events_pending ())
					Gtk.main_iteration ();
				GLib.Value val;
				model.get_value (iter, 0, out val);
				string search_string = val.get_string ();
				search_pkgs.begin (search_string, (obj, res) => {
					Json.Array aur_pkgs;
					Alpm.List<Alpm.Package?> pkgs = search_pkgs.end (res, out aur_pkgs);
					populate_packages_list (pkgs, aur_pkgs);
				});
			}
		}

		[GtkCallback]
		public void on_groups_treeview_selection_changed () {
			TreeModel model;
			TreeIter? iter;
			TreeSelection selection = groups_treeview.get_selection ();
			if (selection.get_selected (out model, out iter)) {
				this.get_window ().set_cursor (new Gdk.Cursor (Gdk.CursorType.WATCH));
				while (Gtk.events_pending ())
					Gtk.main_iteration ();
				GLib.Value val;
				model.get_value (iter, 0, out val);
				string grp_name = val.get_string ();
				Alpm.List<Alpm.Package?> pkgs = group_pkgs_all_dbs (transaction.alpm_config.handle, grp_name);
				populate_packages_list (pkgs);
			}
		}

		[GtkCallback]
		public void on_states_treeview_selection_changed () {
			TreeModel model;
			TreeIter? iter;
			TreeSelection selection = states_treeview.get_selection ();
			if (selection.get_selected (out model, out iter)) {
				this.get_window ().set_cursor (new Gdk.Cursor (Gdk.CursorType.WATCH));
				while (Gtk.events_pending ())
					Gtk.main_iteration ();
				GLib.Value val;
				model.get_value (iter, 0, out val);
				string state = val.get_string ();
				var pkgs = new Alpm.List<unowned Alpm.Package?> ();
				unowned Alpm.Package? find_pkg = null;
				if (state == dgettext (null, "To install")) {
					foreach (string name in transaction.to_add.get_keys ()) {
						find_pkg = transaction.alpm_config.handle.localdb.get_pkg (name);
						if (find_pkg != null)
							pkgs.add (find_pkg);
						else {
							find_pkg = get_syncpkg (transaction.alpm_config.handle, name);
							if (find_pkg != null)
								pkgs.add (find_pkg);
						}
					}
				} else if (state == dgettext (null, "To remove")) {
					foreach (string name in transaction.to_remove.get_keys ()) {
						find_pkg = transaction.alpm_config.handle.localdb.get_pkg (name);
						if (find_pkg != null)
							pkgs.add (find_pkg);
					}
				} else if (state == dgettext (null, "Installed")) {
					pkgs = transaction.alpm_config.handle.localdb.pkgcache.copy ();
				} else if (state == dgettext (null, "Uninstalled")) {
					foreach (var db in transaction.alpm_config.handle.syncdbs) {
						if (pkgs.length == 0)
							pkgs = db.pkgcache.copy ();
						else {
							pkgs.join (db.pkgcache.diff (pkgs, (Alpm.List.CompareFunc) pkgcmp));
						}
					}
				} else if (state == dgettext (null, "Orphans")) {
					foreach (var pkg in transaction.alpm_config.handle.localdb.pkgcache) {
						if (pkg.reason == Alpm.Package.Reason.DEPEND) {
							if (pkg.compute_requiredby().length == 0)
								pkgs.add (pkg);
						}
					}
				}
			populate_packages_list (pkgs);
			}
		}

		[GtkCallback]
		public void on_repos_treeview_selection_changed () {
			TreeModel model;
			TreeIter? iter;
			TreeSelection selection = repos_treeview.get_selection ();
			if (selection.get_selected (out model, out iter)) {
				this.get_window ().set_cursor (new Gdk.Cursor (Gdk.CursorType.WATCH));
				while (Gtk.events_pending ())
					Gtk.main_iteration ();
				GLib.Value val;
				model.get_value (iter, 0, out val);
				string repo = val.get_string ();
				var pkgs = new Alpm.List<unowned Alpm.Package?> ();
				unowned Alpm.Package? find_pkg = null;
				if (repo == dgettext (null, "local")) {
					foreach (var pkg in transaction.alpm_config.handle.localdb.pkgcache) {
						find_pkg = get_syncpkg (transaction.alpm_config.handle, pkg.name);
						if (find_pkg == null)
							pkgs.add (pkg);
					}
				} else {
					foreach (var db in transaction.alpm_config.handle.syncdbs) {
						if (db.name == repo) {
							foreach (var pkg in db.pkgcache) {
								find_pkg = transaction.alpm_config.handle.localdb.get_pkg (pkg.name);
								if (find_pkg != null)
									pkgs.add (find_pkg);
								else
									pkgs.add (pkg);
							}
						}
					}
				}
				populate_packages_list (pkgs);
			}
		}

		[GtkCallback]
		public void on_filters_notebook_switch_page (Widget page, uint page_num) {
			refresh_packages_list ();
		}

		[GtkCallback]
		public void  on_history_item_activate () {
			var file = GLib.File.new_for_path ("/var/log/pamac.log");
			if (!file.query_exists ())
				GLib.stderr.printf ("File '%s' doesn't exist.\n", file.get_path ());
			else {
				StringBuilder text = new StringBuilder ();
				try {
					// Open file for reading and wrap returned FileInputStream into a
					// DataInputStream, so we can read line by line
					var dis = new DataInputStream (file.read ());
					string line;
					// Read lines until end of file (null) is reached
					while ((line = dis.read_line (null)) != null) {
						text.append (line);
						text.append ("\n");
					}
				} catch (GLib.Error e) {
					GLib.stderr.printf ("%s\n", e.message);
				}
				history_dialog.textview.buffer.set_text (text.str, (int) text.len);
				history_dialog.run ();
				history_dialog.hide ();
				while (Gtk.events_pending ())
					Gtk.main_iteration ();
			}
		}

		[GtkCallback]
		public void on_local_item_activate () {
			int response = packages_chooser_dialog.run ();
			if (response== ResponseType.ACCEPT) {
				SList<string> packages_paths = packages_chooser_dialog.get_filenames ();
				if (packages_paths.length () != 0) {
					foreach (string path in packages_paths) {
						transaction.to_load.insert (path, path);
					}
					this.get_window ().set_cursor (new Gdk.Cursor (Gdk.CursorType.WATCH));
					packages_chooser_dialog.hide ();
					while (Gtk.events_pending ())
						Gtk.main_iteration ();
					transaction.run ();
				}
			} else
				packages_chooser_dialog.hide ();
				while (Gtk.events_pending ())
					Gtk.main_iteration ();
		}

		[GtkCallback]
		public void on_preferences_item_activate () {
			bool changes = transaction.run_preferences_dialog (pamac_config);
			if (changes)
				search_aur_button.set_active (pamac_config.enable_aur);
		}

		[GtkCallback]
		public void on_about_item_activate () {
			Gtk.show_about_dialog (
				this,
				"program_name", "Pamac",
				"logo_icon_name", "system-software-install",
				"comments", dgettext (null, "A Gtk3 frontend for libalpm"),
				"copyright", "Copyright © 2015 Guillaume Benoit",
				"version", VERSION,
				"license_type", License.GPL_3_0,
				"website", "http://manjaro.org");
		}

		[GtkCallback]
		public void on_valid_button_clicked () {
			this.get_window ().set_cursor (new Gdk.Cursor (Gdk.CursorType.WATCH));
			while (Gtk.events_pending ())
				Gtk.main_iteration ();
			if (pamac_config.recurse)
				transaction.flags |= Alpm.TransFlag.RECURSE;
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
			transaction.refresh (0);
		}

		public void on_emit_trans_finished (bool error) {
			print ("transaction finished\n");
			if (error == false) {
				set_buttons_sensitive (false);
				refresh_packages_list ();
			}
			transaction.to_load.steal_all ();
			this.get_window ().set_cursor (null);
		}
	}
}
