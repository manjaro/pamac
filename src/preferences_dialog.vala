/*
 *  pamac-vala
 *
 *  Copyright (C) 2015-2018 Guillaume Benoit <guillaume@manjaro.org>
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

	[GtkTemplate (ui = "/org/manjaro/pamac/preferences/preferences_dialog.ui")]
	class PreferencesDialog : Gtk.Dialog {

		[GtkChild]
		Gtk.Switch remove_unrequired_deps_button;
		[GtkChild]
		Gtk.Switch check_space_button;
		[GtkChild]
		Gtk.Switch check_updates_button;
		[GtkChild]
		Gtk.Label refresh_period_label;
		[GtkChild]
		Gtk.SpinButton refresh_period_spin_button;
		[GtkChild]
		Gtk.CheckButton no_update_hide_icon_checkbutton;
		[GtkChild]
		Gtk.Box ignorepkgs_box;
		[GtkChild]
		Gtk.TreeView ignorepkgs_treeview;
		[GtkChild]
		Gtk.Box mirrors_config_box;
		[GtkChild]
		Gtk.ComboBoxText mirrors_country_comboboxtext;
		[GtkChild]
		Gtk.Button generate_mirrors_list_button;
		[GtkChild]
		Gtk.Switch enable_aur_button;
		[GtkChild]
		Gtk.Label aur_build_dir_label;
		[GtkChild]
		Gtk.FileChooserButton aur_build_dir_file_chooser;
		[GtkChild]
		Gtk.CheckButton check_aur_updates_checkbutton;
		[GtkChild]
		Gtk.Label cache_keep_nb_label;
		[GtkChild]
		Gtk.SpinButton cache_keep_nb_spin_button;
		[GtkChild]
		Gtk.CheckButton cache_only_uninstalled_checkbutton;

		Gtk.ListStore ignorepkgs_liststore;
		Transaction transaction;
		uint64 previous_refresh_period;
		string preferences_choosen_country;

		public PreferencesDialog (Transaction transaction) {
			int use_header_bar;
			Gtk.Settings.get_default ().get ("gtk-dialogs-use-header", out use_header_bar);
			Object (transient_for: transaction.application_window, use_header_bar: use_header_bar);

			this.transaction = transaction;
			refresh_period_label.set_markup (dgettext (null, "How often to check for updates, value in hours") +":");
			cache_keep_nb_label.set_markup (dgettext (null, "Number of versions of each package to keep in the cache") +":");
			aur_build_dir_label.set_markup (dgettext (null, "Build directory") +":");
			remove_unrequired_deps_button.active = transaction.recurse;
			check_space_button.active = transaction.get_checkspace ();
			if (transaction.refresh_period == 0) {
				check_updates_button.active = false;
				refresh_period_label.sensitive = false;
				// set default value
				refresh_period_spin_button.value = 6;
				previous_refresh_period = 6;
				refresh_period_spin_button.sensitive = false;
				no_update_hide_icon_checkbutton.sensitive = false;
				ignorepkgs_box.sensitive = false;
			} else {
				check_updates_button.active = true;
				refresh_period_spin_button.value = transaction.refresh_period;
				previous_refresh_period = transaction.refresh_period;
			}
			no_update_hide_icon_checkbutton.active = transaction.no_update_hide_icon;
			cache_keep_nb_spin_button.value = transaction.keep_num_pkgs;
			cache_only_uninstalled_checkbutton.active = transaction.rm_only_uninstalled;

			// populate ignorepkgs_liststore
			ignorepkgs_liststore = new Gtk.ListStore (1, typeof (string));
			ignorepkgs_treeview.set_model (ignorepkgs_liststore);
			foreach (unowned string ignorepkg in transaction.get_ignorepkgs ()) {
				ignorepkgs_liststore.insert_with_values (null, -1, 0, ignorepkg);
			}
			remove_unrequired_deps_button.state_set.connect (on_remove_unrequired_deps_button_state_set);
			check_space_button.state_set.connect (on_check_space_button_state_set);
			transaction.write_alpm_config_finished.connect (on_write_alpm_config_finished);
			check_updates_button.state_set.connect (on_check_updates_button_state_set);
			refresh_period_spin_button.value_changed.connect (on_refresh_period_spin_button_value_changed);
			no_update_hide_icon_checkbutton.toggled.connect (on_no_update_hide_icon_checkbutton_toggled);
			cache_keep_nb_spin_button.value_changed.connect (on_cache_keep_nb_spin_button_value_changed);
			cache_only_uninstalled_checkbutton.toggled.connect (on_cache_only_uninstalled_checkbutton_toggled);
			transaction.write_pamac_config_finished.connect (on_write_pamac_config_finished);

			AlpmPackage pkg = transaction.find_installed_satisfier ("pacman-mirrors");
			if (pkg.name == "") {
				mirrors_config_box.visible = false;
			} else {
				mirrors_country_comboboxtext.append_text (dgettext (null, "Worldwide"));
				mirrors_country_comboboxtext.active = 0;
				if (transaction.preferences_available_countries.length == 0) {
					transaction.preferences_available_countries = transaction.get_mirrors_countries ();
				}
				int index = 1;
				preferences_choosen_country = transaction.get_mirrors_choosen_country ();
				foreach (unowned string country in transaction.preferences_available_countries) {
					mirrors_country_comboboxtext.append_text (country);
					if (country == preferences_choosen_country) {
						mirrors_country_comboboxtext.active = index;
					}
					index += 1;
				}
				mirrors_country_comboboxtext.changed.connect (on_mirrors_country_comboboxtext_changed);
			}

			enable_aur_button.active = transaction.enable_aur;
			aur_build_dir_label.sensitive = transaction.enable_aur;
			aur_build_dir_file_chooser.sensitive = transaction.enable_aur;
			aur_build_dir_file_chooser.set_filename (transaction.aur_build_dir);
			// add /tmp choice always visible
			try {
				aur_build_dir_file_chooser.add_shortcut_folder ("/tmp");
			} catch (GLib.Error e) {
				stderr.printf ("%s\n", e.message);
			}
			check_aur_updates_checkbutton.active = transaction.check_aur_updates;
			check_aur_updates_checkbutton.sensitive = transaction.enable_aur;
			enable_aur_button.state_set.connect (on_enable_aur_button_state_set);
			aur_build_dir_file_chooser.file_set.connect (on_aur_build_dir_set);
			check_aur_updates_checkbutton.toggled.connect (on_check_aur_updates_checkbutton_toggled);
		}

		bool on_remove_unrequired_deps_button_state_set (bool new_state) {
			var new_pamac_conf = new HashTable<string,Variant> (str_hash, str_equal);
			new_pamac_conf.insert ("RemoveUnrequiredDeps", new Variant.boolean (new_state));
			transaction.start_write_pamac_config (new_pamac_conf);
			return true;
		}

		bool on_check_updates_button_state_set (bool new_state) {
			var new_pamac_conf = new HashTable<string,Variant> (str_hash, str_equal);
			refresh_period_label.sensitive = new_state;
			refresh_period_spin_button.sensitive = new_state;
			no_update_hide_icon_checkbutton.sensitive = new_state;
			ignorepkgs_box.sensitive = new_state;
			if (new_state) {
				new_pamac_conf.insert ("RefreshPeriod", new Variant.uint64 (previous_refresh_period));
			} else {
				new_pamac_conf.insert ("RefreshPeriod", new Variant.uint64 (0));
			}
			transaction.start_write_pamac_config (new_pamac_conf);
			return true;
		}

		void on_refresh_period_spin_button_value_changed () {
			var new_pamac_conf = new HashTable<string,Variant> (str_hash, str_equal);
			new_pamac_conf.insert ("RefreshPeriod", new Variant.uint64 (refresh_period_spin_button.get_value_as_int ()));
			transaction.start_write_pamac_config (new_pamac_conf);
		}

		void on_cache_keep_nb_spin_button_value_changed () {
			var new_pamac_conf = new HashTable<string,Variant> (str_hash, str_equal);
			new_pamac_conf.insert ("KeepNumPackages", new Variant.uint64 (cache_keep_nb_spin_button.get_value_as_int ()));
			transaction.start_write_pamac_config (new_pamac_conf);
		}

		void on_cache_only_uninstalled_checkbutton_toggled () {
			var new_pamac_conf = new HashTable<string,Variant> (str_hash, str_equal);
			new_pamac_conf.insert ("OnlyRmUninstalled", new Variant.boolean (cache_only_uninstalled_checkbutton.active));
			transaction.start_write_pamac_config (new_pamac_conf);
		}

		void on_no_update_hide_icon_checkbutton_toggled () {
			var new_pamac_conf = new HashTable<string,Variant> (str_hash, str_equal);
			new_pamac_conf.insert ("NoUpdateHideIcon", new Variant.boolean (no_update_hide_icon_checkbutton.active));
			transaction.start_write_pamac_config (new_pamac_conf);
		}

		bool on_enable_aur_button_state_set (bool new_state) {
			var new_pamac_conf = new HashTable<string,Variant> (str_hash, str_equal);
			new_pamac_conf.insert ("EnableAUR", new Variant.boolean (new_state));
			transaction.start_write_pamac_config (new_pamac_conf);
			return true;
		}

		void on_aur_build_dir_set () {
			var new_pamac_conf = new HashTable<string,Variant> (str_hash, str_equal);
			new_pamac_conf.insert ("BuildDirectory", new Variant.string (aur_build_dir_file_chooser.get_filename ()));
			transaction.start_write_pamac_config (new_pamac_conf);
		}

		void on_check_aur_updates_checkbutton_toggled () {
			var new_pamac_conf = new HashTable<string,Variant> (str_hash, str_equal);
			new_pamac_conf.insert ("CheckAURUpdates", new Variant.boolean (check_aur_updates_checkbutton.active));
			transaction.start_write_pamac_config (new_pamac_conf);
		}

		void on_write_pamac_config_finished (bool recurse, uint64 refresh_period, bool no_update_hide_icon,
											bool enable_aur, string aur_build_dir, bool check_aur_updates) {
			remove_unrequired_deps_button.state = recurse;
			if (refresh_period == 0) {
				check_updates_button.state = false;
				refresh_period_label.sensitive = false;
				refresh_period_spin_button.sensitive = false;
				no_update_hide_icon_checkbutton.sensitive = false;
				ignorepkgs_box.sensitive = false;
			} else {
				check_updates_button.state = true;
				refresh_period_label.sensitive = true;
				refresh_period_spin_button.value = refresh_period;
				previous_refresh_period = refresh_period;
				refresh_period_spin_button.sensitive = true;
				no_update_hide_icon_checkbutton.sensitive = true;
				ignorepkgs_box.sensitive = true;
			}
			no_update_hide_icon_checkbutton.active = no_update_hide_icon;
			enable_aur_button.state = enable_aur;
			aur_build_dir_label.sensitive = enable_aur;
			aur_build_dir_file_chooser.sensitive = enable_aur;
			check_aur_updates_checkbutton.active = check_aur_updates;
			check_aur_updates_checkbutton.sensitive = enable_aur;
		}

		bool on_check_space_button_state_set (bool new_state) {
			var new_alpm_conf = new HashTable<string,Variant> (str_hash, str_equal);
			new_alpm_conf.insert ("CheckSpace", new Variant.boolean (new_state));
			transaction.start_write_alpm_config (new_alpm_conf);
			return true;
		}

		[GtkCallback]
		void on_add_ignorepkgs_button_clicked () {
			var choose_ignorepkgs_dialog = new ChooseIgnorepkgsDialog (this);
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
			transaction.get_installed_pkgs.begin ((obj, res) => {
				var pkgs = transaction.get_installed_pkgs.end (res);
				foreach (unowned AlpmPackage pkg in pkgs) {
					if (pkg.name in transaction.get_ignorepkgs ()) {
						choose_ignorepkgs_dialog.pkgs_list.insert_with_values (null, -1, 0, true, 1, pkg.name);
					} else {
						choose_ignorepkgs_dialog.pkgs_list.insert_with_values (null, -1, 0, false, 1, pkg.name);
					}
				}
				this.get_window ().set_cursor (null);
				if (choose_ignorepkgs_dialog.run () == Gtk.ResponseType.OK) {
					var ignorepkg_string = new StringBuilder ();
					choose_ignorepkgs_dialog.pkgs_list.foreach ((model, path, iter) => {
						GLib.Value val;
						// get value at column 0 to know if it is selected
						model.get_value (iter, 0, out val);
						if ((bool) val) {
							// get value at column 1 to get the pkg name
							model.get_value (iter, 1, out val);
							if (ignorepkg_string.len != 0) {
								ignorepkg_string.append (" ");
							}
							ignorepkg_string.append ((string) val);
						}
						return false;
					});
					var new_alpm_conf = new HashTable<string,Variant> (str_hash, str_equal);
					new_alpm_conf.insert ("IgnorePkg", new Variant.string (ignorepkg_string.str));
					transaction.start_write_alpm_config (new_alpm_conf);
				}
				choose_ignorepkgs_dialog.destroy ();
				while (Gtk.events_pending ()) {
					Gtk.main_iteration ();
				}
			});
		}

		[GtkCallback]
		void on_remove_ignorepkgs_button_clicked () {
			Gtk.TreeIter? iter;
			Gtk.TreeSelection selection = ignorepkgs_treeview.get_selection ();
			if (selection.get_selected (null, out iter)) {
				ignorepkgs_liststore.remove (ref iter);
				var ignorepkg_string = new StringBuilder ();
				ignorepkgs_liststore.foreach ((model, path, iter) => {
					GLib.Value name;
					model.get_value (iter, 0, out name);
					if (ignorepkg_string.len != 0) {
						ignorepkg_string.append (" ");
					}
					ignorepkg_string.append ((string) name);
					return false;
				});
				var new_alpm_conf = new HashTable<string,Variant> (str_hash, str_equal);
				new_alpm_conf.insert ("IgnorePkg", new Variant.string (ignorepkg_string.str));
				transaction.start_write_alpm_config (new_alpm_conf);
			}
		}

		void on_write_alpm_config_finished (bool checkspace) {
			check_space_button.state = checkspace;
			ignorepkgs_liststore.clear ();
			foreach (unowned string ignorepkg in transaction.get_ignorepkgs ()) {
				ignorepkgs_liststore.insert_with_values (null, -1, 0, ignorepkg);
			}
		}

		void on_mirrors_country_comboboxtext_changed () {
			generate_mirrors_list_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
		}

		[GtkCallback]
		void on_generate_mirrors_list_button_clicked () {
			preferences_choosen_country = mirrors_country_comboboxtext.get_active_text ();
			if (preferences_choosen_country == dgettext (null, "Worldwide")) {
				preferences_choosen_country = "all";
			}
			transaction.start_generate_mirrors_list (preferences_choosen_country);
			generate_mirrors_list_button.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
		}

		[GtkCallback]
		void on_cache_clean_button_clicked () {
			transaction.clean_cache (transaction.keep_num_pkgs, transaction.rm_only_uninstalled);
		}
	}
}
