/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2016 Guillaume Benoit <guillaume@manjaro.org>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 3 of the License, or
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

	class PackagesModel : Object, Gtk.TreeModel {
		private Alpm.List<unowned Alpm.Package?>? pkgs;
		private ManagerWindow manager_window;

		public PackagesModel (owned Alpm.List<unowned Alpm.Package?>? pkgs, ManagerWindow manager_window) {
			this.manager_window = manager_window;
			this.pkgs = (owned) pkgs;
		}

		// TreeModel interface
		public Type get_column_type (int index) {
			switch (index) {
				case 0: // name
				case 2: // version
				case 3: // repo
				case 4: // installed size
					return typeof (string);
				case 1: // icon
					return typeof (Gdk.Pixbuf);
				default:
					return Type.INVALID;
			}
		}

		Gtk.TreeModelFlags get_flags () {
			return Gtk.TreeModelFlags.LIST_ONLY | Gtk.TreeModelFlags.ITERS_PERSIST;
		}

		void get_value (Gtk.TreeIter iter, int column, out Value val) {
			unowned Alpm.Package? pkg = pkgs.nth (iter.stamp).data;
			switch (column) {
				case 0:
					val = Value (typeof (string));
					if (pkg == null) {
						val.set_string (dgettext (null, "No package found"));
					} else {
						val.set_string (pkg.name);
					}
					break;
				case 1:
					val = Value (typeof (Object));
					if (pkg != null) {
						if (pkg.origin == Alpm.Package.From.LOCALDB) {
							if (manager_window.transaction.alpm_config.holdpkgs.find_custom (pkg.name, strcmp) != null) {
								val.set_object (manager_window.locked_icon);
							} else if (manager_window.transaction.to_add.contains (pkg.name)) {
								val.set_object (manager_window.to_reinstall_icon);
							} else if (manager_window.transaction.to_remove.contains (pkg.name)) {
								val.set_object (manager_window.to_remove_icon);
							} else {
								val.set_object (manager_window.installed_icon);
							}
						} else if (manager_window.transaction.to_add.contains (pkg.name)) {
							val.set_object (manager_window.to_install_icon);
						} else {
							val.set_object (manager_window.uninstalled_icon);
						}
					}
					break;
				case 2:
					val = Value (typeof (string));
					if (pkg != null) {
						val.set_string (pkg.version);
					}
					break;
				case 3:
					val = Value (typeof (string));
					if (pkg != null) {
						val.set_string (pkg.db.name);
					}
					break;
				case 4:
					val = Value (typeof (string));
					if (pkg != null) {
						val.set_string (format_size (pkg.isize));
					}
					break;
				default:
					val = Value (Type.INVALID);
					break;
			}
		}

		bool get_iter (out Gtk.TreeIter iter, Gtk.TreePath path) {
			if (path.get_depth () == 1) {
				int pos = path.get_indices ()[0];
				// return a valid iter for pos == 0 to display "No package found"
				if (pos < pkgs.length || pos == 0) {
					iter = Gtk.TreeIter ();
					iter.stamp = pos;
					return true;
				}
			}
			return invalid_iter (out iter);
		}

		int get_n_columns () {
			// name, icon, version, repo, isize
			return 5;
		}

		Gtk.TreePath? get_path (Gtk.TreeIter iter) {
			int pos = iter.stamp;
			// return a valid path for pos == 0 to display "No package found"
			if (pos < pkgs.length || pos == 0) {
				return new Gtk.TreePath.from_indices (pos);
			}
			return null;
		}

		int iter_n_children (Gtk.TreeIter? iter) {
			return 0;
		}

		bool iter_next (ref Gtk.TreeIter iter) {
			int pos = (iter.stamp) + 1;
			if (pos >= pkgs.length) {
				return false;
			}
			iter.stamp = pos;
			return true;
		}

		bool iter_previous (ref Gtk.TreeIter iter) {
			int pos = iter.stamp;
			if (pos >= 0) {
				return false;
			}
			iter.stamp = (--pos);
			return true;
		}

		bool iter_nth_child (out Gtk.TreeIter iter, Gtk.TreeIter? parent, int n) {
			return invalid_iter (out iter);
		}

		bool iter_children (out Gtk.TreeIter iter, Gtk.TreeIter? parent) {
			return invalid_iter (out iter);
		}

		bool iter_has_child (Gtk.TreeIter iter) {
			return false;
		}

		bool iter_parent (out Gtk.TreeIter iter, Gtk.TreeIter child) {
			return invalid_iter (out iter);
		}

		bool invalid_iter (out Gtk.TreeIter iter) {
			iter = Gtk.TreeIter ();
			iter.stamp = -1;
			return false;
		}

		// custom get pkg function
		public unowned Alpm.Package? get_pkg_at_path (Gtk.TreePath path) {
			int pos = path.get_indices ()[0];
			if (pos < pkgs.length) {
				return pkgs.nth (pos).data;
			}
			return null;
		}

		// custom sort functions
		public void sort_by_name (Gtk.SortType order) {
			pkgs.sort ((Alpm.List.CompareFunc) compare_name);
			if (order == Gtk.SortType.DESCENDING) {
				pkgs.reverse ();
			}
			manager_window.packages_name_column.sort_order = order;
			manager_window.packages_state_column.sort_indicator = false;
			manager_window.packages_name_column.sort_indicator = true;
			manager_window.packages_version_column.sort_indicator = false;
			manager_window.packages_repo_column.sort_indicator = false;
			manager_window.packages_size_column.sort_indicator = false;
			manager_window.sortinfo.column_number = 0;
			manager_window.sortinfo.sort_type = order;
		}

		public void sort_by_state (Gtk.SortType order) {
			pkgs.sort ((Alpm.List.CompareFunc) compare_state);
			if (order == Gtk.SortType.DESCENDING) {
				pkgs.reverse ();
			}
			manager_window.packages_state_column.sort_order = order;
			manager_window.packages_state_column.sort_indicator = true;
			manager_window.packages_name_column.sort_indicator = false;
			manager_window.packages_version_column.sort_indicator = false;
			manager_window.packages_repo_column.sort_indicator = false;
			manager_window.packages_size_column.sort_indicator = false;
			manager_window.sortinfo.column_number = 1;
			manager_window.sortinfo.sort_type = order;
		}

		public void sort_by_version (Gtk.SortType order) {
			pkgs.sort ((Alpm.List.CompareFunc) compare_version);
			if (order == Gtk.SortType.DESCENDING) {
				pkgs.reverse ();
			}
			manager_window.packages_version_column.sort_order = order;
			manager_window.packages_state_column.sort_indicator = false;
			manager_window.packages_name_column.sort_indicator = false;
			manager_window.packages_version_column.sort_indicator = true;
			manager_window.packages_repo_column.sort_indicator = false;
			manager_window.packages_size_column.sort_indicator = false;
			manager_window.sortinfo.column_number = 2;
			manager_window.sortinfo.sort_type = order;
		}

		public void sort_by_repo (Gtk.SortType order) {
			pkgs.sort ((Alpm.List.CompareFunc) compare_repo);
			if (order == Gtk.SortType.DESCENDING) {
				pkgs.reverse ();
			}
			manager_window.packages_repo_column.sort_order = order;
			manager_window.packages_state_column.sort_indicator = false;
			manager_window.packages_name_column.sort_indicator = false;
			manager_window.packages_version_column.sort_indicator = false;
			manager_window.packages_repo_column.sort_indicator = true;
			manager_window.packages_size_column.sort_indicator = false;
			manager_window.sortinfo.column_number = 3;
			manager_window.sortinfo.sort_type = order;
		}

		public void sort_by_size (Gtk.SortType order) {
			pkgs.sort ((Alpm.List.CompareFunc) compare_size);
			if (order == Gtk.SortType.DESCENDING) {
				pkgs.reverse ();
			}
			manager_window.packages_size_column.sort_order = order;
			manager_window.packages_state_column.sort_indicator = false;
			manager_window.packages_name_column.sort_indicator = false;
			manager_window.packages_version_column.sort_indicator = false;
			manager_window.packages_repo_column.sort_indicator = false;
			manager_window.packages_size_column.sort_indicator = true;
			manager_window.sortinfo.column_number = 4;
			manager_window.sortinfo.sort_type = order;
		}
	}
}
