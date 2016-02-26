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

Pamac.ManagerWindow manager_window;

// custom sort functions
int aur_compare_name (Json.Object pkg_a, Json.Object pkg_b) {
	return strcmp (pkg_a.get_string_member ("Name"), pkg_b.get_string_member ("Name"));
}

int aur_compare_state (Json.Object pkg_a, Json.Object pkg_b) {
	unowned Alpm.Package? alpm_pkg_a = manager_window.transaction.alpm_config.handle.localdb.get_pkg (pkg_a.get_string_member ("Name"));
	unowned Alpm.Package? alpm_pkg_b = manager_window.transaction.alpm_config.handle.localdb.get_pkg (pkg_b.get_string_member ("Name"));
	if (pkg_a != null) {
		if (pkg_b != null) {
			return (int) (alpm_pkg_a.origin > alpm_pkg_b.origin) - (int) (alpm_pkg_a.origin < alpm_pkg_b.origin);
		} else {
			return 1;
		}
	} else {
		if (pkg_b != null) {
			return -1;
		} else {
			return 0;
		}
	}
}

int aur_compare_version (Json.Object pkg_a, Json.Object pkg_b) {
	return Alpm.pkg_vercmp (pkg_a.get_string_member ("Version"), pkg_b.get_string_member ("Version"));
}

int aur_compare_votes (Json.Object pkg_a, Json.Object pkg_b) {
	return (int) (pkg_a.get_int_member ("NumVotes") > pkg_b.get_int_member ("NumVotes")) - (int) (pkg_a.get_int_member ("NumVotes") < pkg_b.get_int_member ("NumVotes"));
}

namespace Pamac {

	class AURModel : Object, Gtk.TreeModel {
		private Json.Array pkgs_infos;
		private GLib.List<Json.Object?> pkgs;

		public AURModel (Json.Array? pkgs_infos, ManagerWindow _manager_window) {
			manager_window = _manager_window;
			this.pkgs_infos = pkgs_infos;
			pkgs = new GLib.List<Json.Object?> ();
			if (pkgs_infos != null) {
				pkgs_infos.foreach_element ((array, index, node) => {
					pkgs.append (node.get_object ());
				});
			}
		}

		// TreeModel interface
		Type get_column_type (int index) {
			switch (index) {
				case 0: // name
				case 2: // version
					return typeof (string);
				case 3: // votes
					return typeof (int64);
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
			unowned Json.Object? pkg_info = pkgs.nth_data (iter.stamp);
			switch (column) {
				case 0:
					val = Value (typeof (string));
					if (pkg_info == null) {
						val.set_string (dgettext (null, "No package found"));
					} else {
						val.set_string (pkg_info.get_string_member ("Name"));
					}
					break;
				case 1:
					val = Value (typeof (Object));
					if (pkg_info != null) {
						unowned Alpm.Package? pkg = manager_window.transaction.alpm_config.handle.localdb.get_pkg (pkg_info.get_string_member ("Name"));
						if (pkg != null) {
							if (manager_window.transaction.alpm_config.holdpkgs.find_custom (pkg.name, strcmp) != null) {
								val.set_object (manager_window.locked_icon);
							} else if (manager_window.transaction.to_add.contains (pkg.name)) {
								val.set_object (manager_window.to_reinstall_icon);
							} else if (manager_window.transaction.to_remove.contains (pkg.name)) {
								val.set_object (manager_window.to_remove_icon);
							} else {
								val.set_object (manager_window.installed_icon);
							}
						} else if (manager_window.transaction.to_build.contains (pkg_info.get_string_member ("Name"))) {
							val.set_object (manager_window.to_install_icon);
						} else {
							val.set_object (manager_window.uninstalled_icon);
						}
					}
					break;
				case 2:
					val = Value (typeof (string));
					if (pkg_info != null) {
						unowned Alpm.Package? pkg = manager_window.transaction.alpm_config.handle.localdb.get_pkg (pkg_info.get_string_member ("Name"));
						if (pkg != null) {
							val.set_string (pkg.version);
						} else {
							val.set_string (pkg_info.get_string_member ("Version"));
						}
					}
					break;
				case 3:
					if (pkg_info != null) {
						val = Value (typeof (int64));
						val.set_int64 (pkg_info.get_int_member ("NumVotes"));
					} else {
						// if pkg_info is null, set val to an empty string to not display "0"
						val = Value (typeof (string));
					}
					break;
				default:
					val = Value (Type.INVALID);
					break;
			}
		}

		bool get_iter (out Gtk.TreeIter iter, Gtk.TreePath path) {;
			if (path.get_depth () != 1) {
				return invalid_iter (out iter);
			}
			iter = Gtk.TreeIter ();
			int pos = path.get_indices ()[0];
			iter.stamp = pos;
			return true;
		}

		int get_n_columns () {
			// name, icon, version, votes
			return 4;
		}

		Gtk.TreePath? get_path (Gtk.TreeIter iter) {
			return new Gtk.TreePath.from_indices (iter.stamp);
		}

		int iter_n_children (Gtk.TreeIter? iter) {
			return 0;
		}

		bool iter_next (ref Gtk.TreeIter iter) {
			int pos = (iter.stamp) + 1;
			if (pos >= pkgs.length ()) {
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
		public unowned Json.Object? get_pkg_at_path (Gtk.TreePath path) {
			return pkgs.nth_data (path.get_indices ()[0]);
		}

		public void sort_by_name (Gtk.SortType order) {
			pkgs.sort ((GLib.CompareFunc) aur_compare_name);
			if (order == Gtk.SortType.DESCENDING) {
				pkgs.reverse ();
			}
			manager_window.aur_name_column.sort_order = order;
			manager_window.aur_state_column.sort_indicator = false;
			manager_window.aur_name_column.sort_indicator = true;
			manager_window.aur_version_column.sort_indicator = false;
			manager_window.aur_votes_column.sort_indicator = false;
			manager_window.sortinfo.column_number = 0;
			manager_window.sortinfo.sort_type = order;
		}

		public void sort_by_state (Gtk.SortType order) {
			pkgs.sort ((GLib.CompareFunc) aur_compare_state);
			if (order == Gtk.SortType.DESCENDING) {
				pkgs.reverse ();
			}
			manager_window.aur_state_column.sort_order = order;
			manager_window.aur_state_column.sort_indicator = true;
			manager_window.aur_name_column.sort_indicator = false;
			manager_window.aur_version_column.sort_indicator = false;
			manager_window.aur_votes_column.sort_indicator = false;
			manager_window.sortinfo.column_number = 1;
			manager_window.sortinfo.sort_type = order;
		}

		public void sort_by_version (Gtk.SortType order) {
			pkgs.sort ((GLib.CompareFunc) aur_compare_version);
			if (order == Gtk.SortType.DESCENDING) {
				pkgs.reverse ();
			}
			manager_window.aur_version_column.sort_order = order;
			manager_window.aur_state_column.sort_indicator = false;
			manager_window.aur_name_column.sort_indicator = false;
			manager_window.aur_version_column.sort_indicator = true;
			manager_window.aur_votes_column.sort_indicator = false;
			manager_window.sortinfo.column_number = 2;
			manager_window.sortinfo.sort_type = order;
		}

		public void sort_by_votes (Gtk.SortType order) {
			pkgs.sort ((GLib.CompareFunc) aur_compare_votes);
			if (order == Gtk.SortType.DESCENDING) {
				pkgs.reverse ();
			}
			manager_window.aur_votes_column.sort_order = order;
			manager_window.aur_state_column.sort_indicator = false;
			manager_window.aur_name_column.sort_indicator = false;
			manager_window.aur_version_column.sort_indicator = false;
			manager_window.aur_votes_column.sort_indicator = true;
			manager_window.sortinfo.column_number = 3;
			manager_window.sortinfo.sort_type = order;
		}
	}
}
