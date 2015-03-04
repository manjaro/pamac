/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2015 Guillaume Benoit <guillaume@manjaro.org>
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

	public class PackagesModel : Object, Gtk.TreeModel {
		private GLib.List<Pamac.Package?> all_pkgs;
		public ManagerWindow manager_window;

		public PackagesModel (Pamac.Package[] pkgs, ManagerWindow manager_window) {
			this.manager_window = manager_window;
			all_pkgs = new GLib.List<Pamac.Package?> ();
			foreach (var pkg in pkgs) {
				all_pkgs.append (pkg);
			}
			if (all_pkgs.length () == 0) {
				// create a fake "No package found" package
				var fake_pkg = Pamac.Package (null, null);
				fake_pkg.name = dgettext (null, "No package found");
				all_pkgs.append (fake_pkg);
			}
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

		public Gtk.TreeModelFlags get_flags () {
			return Gtk.TreeModelFlags.LIST_ONLY | Gtk.TreeModelFlags.ITERS_PERSIST;
		}

		public void get_value (Gtk.TreeIter iter, int column, out Value val) {
			Pamac.Package pkg = all_pkgs.nth_data (iter.stamp);
			switch (column) {
				case 0:
					val = Value (typeof (string));
					val.set_string (pkg.name);
					break;
				case 1:
					val = Value (typeof (Object));
						if (pkg.repo == "local") {
							if (manager_window.transaction.should_hold (pkg.name)) {
								val.set_object (manager_window.locked_icon);
							} else if (manager_window.transaction.to_add.contains (pkg.name)) {
								val.set_object (manager_window.to_reinstall_icon);
							} else if (manager_window.transaction.to_remove.contains (pkg.name)) {
								val.set_object (manager_window.to_remove_icon);
							} else {
								val.set_object (manager_window.installed_icon);
							}
						} else if (pkg.repo == "AUR") {
							if (manager_window.transaction.to_build.contains (pkg.name)) {
								val.set_object (manager_window.to_install_icon);
							} else {
								val.set_object (manager_window.uninstalled_icon);
							}
						} else if (pkg.name == dgettext (null, "No package found")) {
							Object? object = null;
							val.set_object (object);
						} else if (manager_window.transaction.to_add.contains (pkg.name)) {
							val.set_object (manager_window.to_install_icon);
						} else {
							val.set_object (manager_window.uninstalled_icon);
						}
					break;
				case 2:
					val = Value (typeof (string));
					val.set_string (pkg.version);
					break;
				case 3:
					val = Value (typeof (string));
					val.set_string (pkg.repo);
					break;
				case 4:
					val = Value (typeof (string));
					val.set_string (pkg.size_string);
					break;
				default:
					val = Value (Type.INVALID);
					break;
			}
		}

		public bool get_iter (out Gtk.TreeIter iter, Gtk.TreePath path) {;
			if (path.get_depth () != 1 || all_pkgs.length () == 0) {
				return invalid_iter (out iter);
			}
			iter = Gtk.TreeIter ();
			int pos = path.get_indices ()[0];
			iter.stamp = pos;
			return true;
		}

		public int get_n_columns () {
			// name, icon, version, repo, isize
			return 5;
		}

		public Gtk.TreePath? get_path (Gtk.TreeIter iter) {
			return new Gtk.TreePath.from_indices (iter.stamp);
		}

		public int iter_n_children (Gtk.TreeIter? iter) {
			return 0;
		}

		public bool iter_next (ref Gtk.TreeIter iter) {
			int pos = (iter.stamp) + 1;
			if (pos >= all_pkgs.length ()) {
				return false;
			}
			iter.stamp = pos;
			return true;
		}

		public bool iter_previous (ref Gtk.TreeIter iter) {
			int pos = iter.stamp;
			if (pos >= 0) {
				return false;
			}
			iter.stamp = (--pos);
			return true;
		}

		public bool iter_nth_child (out Gtk.TreeIter iter, Gtk.TreeIter? parent, int n) {
			return invalid_iter (out iter);
		}

		public bool iter_children (out Gtk.TreeIter iter, Gtk.TreeIter? parent) {
			return invalid_iter (out iter);
		}

		public bool iter_has_child (Gtk.TreeIter iter) {
			return false;
		}

		public bool iter_parent (out Gtk.TreeIter iter, Gtk.TreeIter child) {
			return invalid_iter (out iter);
		}

		private bool invalid_iter (out Gtk.TreeIter iter) {
			iter = Gtk.TreeIter ();
			iter.stamp = -1;
			return false;
		}

		// custom get pkg function
		public Pamac.Package get_pkg_at_path (Gtk.TreePath path) {
			return all_pkgs.nth_data (path.get_indices ()[0]);
		}

		// custom sort functions
		public void sort_by_name (Gtk.SortType order) {
			CompareFunc<Pamac.Package?> namecmp = (pkg_a, pkg_b) => {
				return strcmp (pkg_a.name, pkg_b.name);
			};
			all_pkgs.sort (namecmp);
			if (order == Gtk.SortType.DESCENDING) {
				all_pkgs.reverse ();
			}
			manager_window.name_column.sort_order = order;
			manager_window.state_column.sort_indicator = false;
			manager_window.name_column.sort_indicator = true;
			manager_window.version_column.sort_indicator = false;
			manager_window.repo_column.sort_indicator = false;
			manager_window.size_column.sort_indicator = false;
			manager_window.sortinfo.column_number = 0;
			manager_window.sortinfo.sort_type = order;
		}

		public void sort_by_state (Gtk.SortType order) {
			CompareFunc<Pamac.Package?> statecmp = (pkg_a, pkg_b) => {
				int state_a;
				int state_b;
					if (pkg_a.repo == "local") {
						state_a = 0;
					} else {
						state_a = 1;
					}
					if (pkg_b.repo == "local") {
						state_b = 0;
					} else {
						state_b = 1;
					}
				return (int) (state_a > state_b) - (int) (state_a < state_b);
			};
			all_pkgs.sort (statecmp);
			if (order == Gtk.SortType.DESCENDING) {
				all_pkgs.reverse ();
			}
			manager_window.state_column.sort_order = order;
			manager_window.state_column.sort_indicator = true;
			manager_window.name_column.sort_indicator = false;
			manager_window.version_column.sort_indicator = false;
			manager_window.repo_column.sort_indicator = false;
			manager_window.size_column.sort_indicator = false;
			manager_window.sortinfo.column_number = 1;
			manager_window.sortinfo.sort_type = order;
		}

		public void sort_by_version (Gtk.SortType order) {
			CompareFunc<Pamac.Package?> versioncmp = (pkg_a, pkg_b) => {
				return Alpm.pkg_vercmp (pkg_a.version, pkg_b.version);
			};
			all_pkgs.sort (versioncmp);
			if (order == Gtk.SortType.DESCENDING) {
				all_pkgs.reverse ();
			}
			manager_window.version_column.sort_order = order;
			manager_window.state_column.sort_indicator = false;
			manager_window.name_column.sort_indicator = false;
			manager_window.version_column.sort_indicator = true;
			manager_window.repo_column.sort_indicator = false;
			manager_window.size_column.sort_indicator = false;
			manager_window.sortinfo.column_number = 2;
			manager_window.sortinfo.sort_type = order;
		}

		public void sort_by_repo (Gtk.SortType order) {
			CompareFunc<Pamac.Package?> repocmp = (pkg_a, pkg_b) => {
				return strcmp (pkg_a.repo, pkg_b.repo);
			};
			all_pkgs.sort (repocmp);
			if (order == Gtk.SortType.DESCENDING) {
				all_pkgs.reverse ();
			}
			manager_window.repo_column.sort_order = order;
			manager_window.state_column.sort_indicator = false;
			manager_window.name_column.sort_indicator = false;
			manager_window.version_column.sort_indicator = false;
			manager_window.repo_column.sort_indicator = true;
			manager_window.size_column.sort_indicator = false;
			manager_window.sortinfo.column_number = 3;
			manager_window.sortinfo.sort_type = order;
		}

		public void sort_by_size (Gtk.SortType order) {
			CompareFunc<Pamac.Package?> sizecmp = (pkg_a, pkg_b) => {
				return (int) (pkg_a.size > pkg_b.size) - (int) (pkg_a.size < pkg_b.size);
			};
			all_pkgs.sort (sizecmp);
			if (order == Gtk.SortType.DESCENDING) {
				all_pkgs.reverse ();
			}
			manager_window.size_column.sort_order = order;
			manager_window.state_column.sort_indicator = false;
			manager_window.name_column.sort_indicator = false;
			manager_window.version_column.sort_indicator = false;
			manager_window.repo_column.sort_indicator = false;
			manager_window.size_column.sort_indicator = true;
			manager_window.sortinfo.column_number = 4;
			manager_window.sortinfo.sort_type = order;
		}
	}
}
