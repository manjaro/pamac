/*
 *  pamac-vala
 *
 *  Copyright (C) 2014 Guillaume Benoit <guillaume@manjaro.org>
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
	public class PreferencesDialog : Gtk.Dialog {

		[GtkChild]
		public Gtk.Switch remove_unrequired_deps_button;
		[GtkChild]
		public Gtk.Switch check_space_button;
		[GtkChild]
		public Gtk.Switch check_updates_button;
		[GtkChild]
		public Gtk.Label refresh_period_label;
		[GtkChild]
		public Gtk.SpinButton refresh_period_spin_button;
		[GtkChild]
		public Gtk.CheckButton no_update_hide_icon_checkbutton;
		[GtkChild]
		public Gtk.Box ignorepkgs_box;
		[GtkChild]
		public Gtk.ListStore ignorepkgs_liststore;
		[GtkChild]
		public Gtk.TreeView ignorepkgs_treeview;
		[GtkChild]
		public Gtk.Box mirrors_config_box;
		[GtkChild]
		public Gtk.ComboBoxText mirrors_country_comboboxtext;
		[GtkChild]
		public Gtk.ComboBoxText mirrors_list_generation_method_comboboxtext;
		[GtkChild]
		public Gtk.Button generate_mirrors_list_button;
		[GtkChild]
		public Gtk.Box aur_config_box;
		[GtkChild]
		public Gtk.Switch enable_aur_button;
		[GtkChild]
		public Gtk.CheckButton search_aur_checkbutton;
		[GtkChild]
		public Gtk.CheckButton check_aur_updates_checkbutton;
		[GtkChild]
		public Gtk.CheckButton no_confirm_build_checkbutton;

		Transaction transaction;
		int previous_refresh_period;

		public PreferencesDialog (Transaction transaction, Gtk.ApplicationWindow? window) {
			Object (transient_for: window, use_header_bar: 0);

			this.transaction = transaction;
			refresh_period_label.set_markup (dgettext (null, "How often to check for updates, value in hours") +":");
			var pamac_config = new Pamac.Config ("/etc/pamac.conf");
			remove_unrequired_deps_button.active = pamac_config.recurse;
			check_space_button.active = transaction.get_checkspace ();
			if (pamac_config.refresh_period == 0) {
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
				refresh_period_spin_button.value = pamac_config.refresh_period;
				previous_refresh_period = pamac_config.refresh_period;
			}
			no_update_hide_icon_checkbutton.active = pamac_config.no_update_hide_icon;

			// populate ignorepkgs_liststore
			Gtk.TreeIter iter;
			foreach (var name in transaction.get_ignorepkgs ()) {
				ignorepkgs_liststore.insert_with_values (out iter, -1, 0, name);
			}
			remove_unrequired_deps_button.state_set.connect (on_remove_unrequired_deps_button_state_set);
			check_space_button.state_set.connect (on_check_space_button_state_set);
			check_updates_button.state_set.connect (on_check_updates_button_state_set);
			refresh_period_spin_button.value_changed.connect (on_refresh_period_spin_button_value_changed);
			no_update_hide_icon_checkbutton.toggled.connect (on_no_update_hide_icon_checkbutton_toggled);
			transaction.daemon.write_pamac_config_finished.connect (on_write_pamac_config_finished);

			Pamac.Package pkg = this.transaction.find_local_satisfier ("pacman-mirrorlist");
			if (pkg.name == "") {
				mirrors_config_box.visible = false;
			} else {
				var mirrors_config = new Alpm.MirrorsConfig ("/etc/pacman-mirrors.conf");
				mirrors_country_comboboxtext.append_text (dgettext (null, "Worldwide"));
				mirrors_country_comboboxtext.active = 0;
				int index = 1;
				mirrors_config.get_countrys ();
				foreach (string country in mirrors_config.countrys) {
					mirrors_country_comboboxtext.append_text (country);
					if (country == mirrors_config.choosen_country) {
						mirrors_country_comboboxtext.active = index;
					}
					index += 1;
				}
				mirrors_list_generation_method_comboboxtext.append_text (dgettext (null, "Speed"));
				mirrors_list_generation_method_comboboxtext.append_text (dgettext (null, "Random"));
				if (mirrors_config.choosen_generation_method == "rank") {
					mirrors_list_generation_method_comboboxtext.active = 0;
				} else {
					mirrors_list_generation_method_comboboxtext.active = 1;
				}
				mirrors_country_comboboxtext.changed.connect (on_mirrors_country_comboboxtext_changed);
				mirrors_list_generation_method_comboboxtext.changed.connect (on_mirrors_list_generation_method_comboboxtext_changed);
				transaction.daemon.write_mirrors_config_finished.connect (on_write_mirrors_config_finished);
			}

			pkg = this.transaction.find_local_satisfier ("yaourt");
			if (pkg.name == "") {
				aur_config_box.visible = false;
			} else {
				enable_aur_button.active = pamac_config.enable_aur;
				search_aur_checkbutton.active = pamac_config.search_aur;
				search_aur_checkbutton.sensitive = pamac_config.enable_aur;
				check_aur_updates_checkbutton.active = pamac_config.check_aur_updates;
				check_aur_updates_checkbutton.sensitive = pamac_config.enable_aur;
				no_confirm_build_checkbutton.active = pamac_config.no_confirm_build;
				no_confirm_build_checkbutton.sensitive = pamac_config.enable_aur;
				enable_aur_button.state_set.connect (on_enable_aur_button_state_set);
				search_aur_checkbutton.toggled.connect (on_search_aur_checkbutton_toggled);
				check_aur_updates_checkbutton.toggled.connect (on_check_aur_updates_checkbutton_toggled);
				no_confirm_build_checkbutton.toggled.connect (on_no_confirm_build_checkbutton_toggled);
				transaction.daemon.write_alpm_config_finished.connect (on_write_alpm_config_finished);
			}
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
			if (new_state == true) {
				new_pamac_conf.insert ("RefreshPeriod", new Variant.int32 (previous_refresh_period));
			} else {
				new_pamac_conf.insert ("RefreshPeriod", new Variant.int32 (0));
			}
			transaction.start_write_pamac_config (new_pamac_conf);
			return true;
		}

		void on_refresh_period_spin_button_value_changed () {
			var new_pamac_conf = new HashTable<string,Variant> (str_hash, str_equal);
			new_pamac_conf.insert ("RefreshPeriod", new Variant.int32 (refresh_period_spin_button.get_value_as_int ()));
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

		void on_search_aur_checkbutton_toggled () {
			var new_pamac_conf = new HashTable<string,Variant> (str_hash, str_equal);
			new_pamac_conf.insert ("SearchInAURByDefault", new Variant.boolean (search_aur_checkbutton.active));
			transaction.start_write_pamac_config (new_pamac_conf);
		}

		void on_check_aur_updates_checkbutton_toggled () {
			var new_pamac_conf = new HashTable<string,Variant> (str_hash, str_equal);
			new_pamac_conf.insert ("CheckAURUpdates", new Variant.boolean (check_aur_updates_checkbutton.active));
			transaction.start_write_pamac_config (new_pamac_conf);
		}

		void on_no_confirm_build_checkbutton_toggled () {
			var new_pamac_conf = new HashTable<string,Variant> (str_hash, str_equal);
			new_pamac_conf.insert ("NoConfirmBuild", new Variant.boolean (no_confirm_build_checkbutton.active));
			transaction.start_write_pamac_config (new_pamac_conf);
		}

		void on_write_pamac_config_finished (bool recurse, int refresh_period, bool no_update_hide_icon,
											bool enable_aur, bool search_aur, bool check_aur_updates,
											bool no_confirm_build) {
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
				// launch pamac-tray if needed 
				try {
					Process.spawn_command_line_async ("pamac-tray");
				} catch (SpawnError e) {
					stderr.printf ("SpawnError: %s\n", e.message);
				}
			}
			no_update_hide_icon_checkbutton.active = no_update_hide_icon;
			enable_aur_button.state = enable_aur;
			search_aur_checkbutton.active = search_aur;
			search_aur_checkbutton.sensitive = enable_aur;
			check_aur_updates_checkbutton.active = check_aur_updates;
			check_aur_updates_checkbutton.sensitive = enable_aur;
			no_confirm_build_checkbutton.active = no_confirm_build;
			no_confirm_build_checkbutton.sensitive = enable_aur;
		}

		bool on_check_space_button_state_set (bool new_state) {
			var new_alpm_conf = new HashTable<string,Variant> (str_hash, str_equal);
			new_alpm_conf.insert ("CheckSpace", new Variant.boolean (new_state));
			transaction.start_write_alpm_config (new_alpm_conf);
			return true;
		}

		[GtkCallback]
		void on_add_ignorepkgs_button_clicked () {
			var choose_ignorepkgs_dialog = new ChooseIgnorepkgsDialog (this, transaction);
			if (choose_ignorepkgs_dialog.run () == Gtk.ResponseType.OK) {
				var ignorepkg_string = new StringBuilder ();
				choose_ignorepkgs_dialog.pkgs_list.foreach ((model, path, iter) => {
					GLib.Value val;
					choose_ignorepkgs_dialog.pkgs_list.get_value (iter, 0, out val);
					bool selected = val.get_boolean ();
					if (selected) {
						choose_ignorepkgs_dialog.pkgs_list.get_value (iter, 1, out val);
						string name = val.get_string ();
						if (ignorepkg_string.len != 0) {
							ignorepkg_string.append (" ");
						}
						ignorepkg_string.append (name);
					}
					return false;
				});
				if (ignorepkg_string.len != 0) {
					var new_alpm_conf = new HashTable<string,Variant> (str_hash, str_equal);
					new_alpm_conf.insert ("IgnorePkg", new Variant.string (ignorepkg_string.str));
					transaction.start_write_alpm_config (new_alpm_conf);
				}
			}
			choose_ignorepkgs_dialog.destroy ();
			while (Gtk.events_pending ()) {
				Gtk.main_iteration ();
			}
		}

		[GtkCallback]
		void on_remove_ignorepkgs_button_clicked () {
			Gtk.TreeIter? iter;
			Gtk.TreeSelection selection = ignorepkgs_treeview.get_selection ();
			if (selection.get_selected (null, out iter)) {
				ignorepkgs_liststore.remove (iter);
				var ignorepkg_string = new StringBuilder ();
				ignorepkgs_liststore.foreach ((model, path, iter) => {
					GLib.Value val;
					ignorepkgs_liststore.get_value (iter, 0, out val);
					string name = val.get_string ();
					if (ignorepkg_string.len != 0) {
						ignorepkg_string.append (" ");
					}
					ignorepkg_string.append (name);
					return false;
				});
				var new_alpm_conf = new HashTable<string,Variant> (str_hash, str_equal);
				new_alpm_conf.insert ("IgnorePkg", new Variant.string (ignorepkg_string.str));
				transaction.start_write_alpm_config (new_alpm_conf);
			}
		}

		void on_write_alpm_config_finished (bool checkspace) {
			check_space_button.state = checkspace;
			// re-populate ignorepkgs_liststore
			Gtk.TreeIter iter;
			ignorepkgs_liststore.clear ();
			foreach (var name in transaction.get_ignorepkgs ()) {
				ignorepkgs_liststore.insert_with_values (out iter, -1, 0, name);
			}
		}

		void on_mirrors_country_comboboxtext_changed () {
			var new_mirrors_conf = new HashTable<string,Variant> (str_hash, str_equal);
			new_mirrors_conf.insert ("OnlyCountry", new Variant.string (mirrors_country_comboboxtext.get_active_text ()));
			transaction.start_write_mirrors_config (new_mirrors_conf);
		}

		void on_mirrors_list_generation_method_comboboxtext_changed () {
			var new_mirrors_conf = new HashTable<string,Variant> (str_hash, str_equal);
			if (mirrors_list_generation_method_comboboxtext.get_active_text () == dgettext (null, "Speed")){
				new_mirrors_conf.insert ("Method", new Variant.string ("rank"));
			} else {
				new_mirrors_conf.insert ("Method", new Variant.string ("random"));
			}
			transaction.start_write_mirrors_config (new_mirrors_conf);
		}

		void on_write_mirrors_config_finished (string choosen_country, string choosen_generation_method) {
			int index = 0;
			mirrors_country_comboboxtext.model.foreach ((model, path, iter) => {
				GLib.Value val;
				model.get_value (iter, 0, out val);
				string country = val.get_string ();
				if (choosen_country == country) {
					return true;
				}
				index += 1;
				return false;
			});
			mirrors_country_comboboxtext.active = index;
			if (choosen_generation_method == "rank") {
				mirrors_list_generation_method_comboboxtext.active = 0;
			} else {
				mirrors_list_generation_method_comboboxtext.active = 1;
			}
			generate_mirrors_list_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
		}

		[GtkCallback]
		void on_generate_mirrors_list_button_clicked () {
			transaction.start_generate_mirrors_list ();
			generate_mirrors_list_button.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
		}
	}
}
