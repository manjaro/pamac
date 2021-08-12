/*
 *  pamac-vala
 *
 *  Copyright (C) 2015-2021 Guillaume Benoit <guillaume@manjaro.org>
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
	class PreferencesWindow : Hdy.PreferencesWindow {
		[GtkChild]
		unowned Hdy.ExpanderRow check_updates_expander;
		[GtkChild]
		unowned Hdy.ComboRow refresh_period_comborow;
		[GtkChild]
		unowned Gtk.Switch no_update_hide_icon_button;
		[GtkChild]
		unowned Gtk.Switch download_updates_button;
		[GtkChild]
		unowned Hdy.ComboRow parallel_downloads_comborow;
		[GtkChild]
		unowned Hdy.PreferencesGroup mirrors_preferences_group;
		[GtkChild]
		unowned Hdy.ComboRow mirrors_country_comborow;
		[GtkChild]
		unowned Gtk.Button generate_mirrors_list_button;
		[GtkChild]
		unowned Hdy.ComboRow cache_keep_nb_comborow;
		[GtkChild]
		unowned Gtk.Switch cache_only_uninstalled_button;
		[GtkChild]
		unowned Gtk.Label clean_cache_label;
		[GtkChild]
		unowned Gtk.Button clean_cache_button;
		[GtkChild]
		unowned Hdy.PreferencesPage advanced_preferences_page;
		[GtkChild]
		unowned Gtk.Switch check_space_button;
		[GtkChild]
		unowned Gtk.Switch remove_unrequired_deps_button;
		[GtkChild]
		unowned Gtk.Switch simple_install_button;
		[GtkChild]
		unowned Gtk.Switch enable_downgrade_button;
		[GtkChild]
		unowned Gtk.ListBox ignorepkgs_listbox;
		[GtkChild]
		unowned Hdy.PreferencesPage third_party_preferences_page;
		[GtkChild]
		unowned Hdy.PreferencesGroup aur_preferences_group;
		[GtkChild]
		unowned Hdy.ExpanderRow enable_aur_expander;
		[GtkChild]
		unowned Gtk.Button aur_build_dir_file_chooser;
		[GtkChild]
		unowned Gtk.Switch keep_built_pkgs_button;
		[GtkChild]
		unowned Gtk.Switch check_aur_updates_button;
		[GtkChild]
		unowned Gtk.Switch check_aur_vcs_updates_button;
		[GtkChild]
		unowned Gtk.Button clean_build_files_button;
		[GtkChild]
		unowned Gtk.Label clean_build_files_label;
		[GtkChild]
		unowned Hdy.PreferencesGroup flatpak_preferences_group;
		[GtkChild]
		unowned Hdy.ExpanderRow enable_flatpak_expander;
		[GtkChild]
		unowned Gtk.Switch check_flatpak_updates_button;
		[GtkChild]
		unowned Hdy.PreferencesGroup snap_preferences_group;
		[GtkChild]
		unowned Gtk.Switch enable_snap_button;

		unowned LocalConfig local_config;
		unowned Config config;
		unowned Database database;
		unowned TransactionGtk transaction;
		uint64 previous_refresh_period;

		bool transaction_running;

		public PreferencesWindow (ManagerWindow window, LocalConfig local_config) {
			Object (transient_for: window);

			transaction = window.transaction;
			database = transaction.database;
			config = database.config;
			local_config = window.local_config;
			// set check updates
			var store = new GLib.ListStore (typeof (Hdy.ValueObject));
			var val = Value (typeof (string));
			string str = dgettext (null, "every 3 hours");
			val.set_string (str);
			store.append (new Hdy.ValueObject (val));
			str = dgettext (null, "every 6 hours");
			val.set_string (str);
			store.append (new Hdy.ValueObject (val));
			str = dgettext (null, "every 12 hours");
			val.set_string (str);
			store.append (new Hdy.ValueObject (val));
			str = dgettext (null, "every day");
			val.set_string (str);
			store.append (new Hdy.ValueObject (val));
			str = dgettext (null, "every week");
			val.set_string (str);
			store.append (new Hdy.ValueObject (val));
			refresh_period_comborow.bind_name_model (store, (object) => {
				unowned Hdy.ValueObject value_object = object as Hdy.ValueObject;
				return value_object.get_string ();
			});
			if (config.refresh_period == 0) {
				check_updates_expander.enable_expansion = false;
				check_updates_expander.expanded = false;
				refresh_period_comborow.selected_index = 1;
				previous_refresh_period = 6;
			} else {
				check_updates_expander.enable_expansion = true;
				check_updates_expander.expanded = true;
				uint64 refresh_period = config.refresh_period;
				if (refresh_period <= 3) {
					refresh_period_comborow.selected_index = 0;
				} else if (refresh_period <= 6) {
					refresh_period_comborow.selected_index = 1;
				} else if (refresh_period <= 12) {
					refresh_period_comborow.selected_index = 2;
				} else if (refresh_period <= 24) {
					refresh_period_comborow.selected_index = 3;
				} else {
					refresh_period_comborow.selected_index = 4;
				}
			}
			check_updates_expander.notify["enable-expansion"].connect (on_check_updates_expander_changed);
			refresh_period_comborow.notify["selected-index"].connect (on_refresh_period_comborow_changed);
			config.bind_property ("download_updates", download_updates_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			config.bind_property ("no_update_hide_icon", no_update_hide_icon_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			// set parallel downloads
			store = new GLib.ListStore (typeof (Hdy.ValueObject));
			str = dgettext (null, "1");
			val.set_string (str);
			store.append (new Hdy.ValueObject (val));
			str = dgettext (null, "2");
			val.set_string (str);
			store.append (new Hdy.ValueObject (val));
			str = dgettext (null, "4");
			val.set_string (str);
			store.append (new Hdy.ValueObject (val));
			str = dgettext (null, "6");
			val.set_string (str);
			store.append (new Hdy.ValueObject (val));
			str = dgettext (null, "8");
			val.set_string (str);
			store.append (new Hdy.ValueObject (val));
			str = dgettext (null, "10");
			val.set_string (str);
			store.append (new Hdy.ValueObject (val));
			parallel_downloads_comborow.bind_name_model (store, (object) => {
				unowned Hdy.ValueObject value_object = object as Hdy.ValueObject;
				return value_object.get_string ();
			});
			uint64 max_parallel_downloads = config.max_parallel_downloads;
			if (max_parallel_downloads <= 1) {
				parallel_downloads_comborow.selected_index = 0;
			} else if (max_parallel_downloads <= 2) {
				parallel_downloads_comborow.selected_index = 1;
			} else if (max_parallel_downloads <= 4) {
				parallel_downloads_comborow.selected_index = 2;
			} else if (max_parallel_downloads <= 6) {
				parallel_downloads_comborow.selected_index = 3;
			} else if (max_parallel_downloads <= 8) {
				parallel_downloads_comborow.selected_index = 4;
			} else {
				parallel_downloads_comborow.selected_index = 5;
			}
			parallel_downloads_comborow.notify["selected-index"].connect (on_parallel_downloads_comborow_changed);
			// set mirrors
			if (database.has_installed_satisfier ("pacman-mirrors")) {
				var mirrors_store = new GLib.ListStore (typeof (Hdy.ValueObject));
				str = dgettext (null, "Worldwide");
				val.set_string (str);
				mirrors_store.append (new Hdy.ValueObject (val));
				int index = 1;
				database.get_mirrors_choosen_country_async.begin ((obj, res) => {
					string preferences_choosen_country = database.get_mirrors_choosen_country_async.end (res);
					database.get_mirrors_countries_async.begin ((obj, res) => {
						var countries = database.get_mirrors_countries_async.end (res);
						foreach (unowned string country in countries) {
							val.set_string (country);
							mirrors_store.append (new Hdy.ValueObject (val));
							if (country == preferences_choosen_country) {
								mirrors_country_comborow.selected_index = index;
							}
							index += 1;
						}
						mirrors_country_comborow.notify["selected-index"].connect (on_mirrors_country_comborow_changed);
					});
				});
				mirrors_country_comborow.bind_name_model (mirrors_store, (object) => {
					unowned Hdy.ValueObject value_object = object as Hdy.ValueObject;
					return value_object.get_string ();
				});
			} else {
				mirrors_preferences_group.visible = false;
			}
			// set cache options
			store = new GLib.ListStore (typeof (Hdy.ValueObject));
			str = dgettext (null, "0");
			val.set_string (str);
			store.append (new Hdy.ValueObject (val));
			str = dgettext (null, "1");
			val.set_string (str);
			store.append (new Hdy.ValueObject (val));
			str = dgettext (null, "2");
			val.set_string (str);
			store.append (new Hdy.ValueObject (val));
			str = dgettext (null, "3");
			val.set_string (str);
			store.append (new Hdy.ValueObject (val));
			str = dgettext (null, "4");
			val.set_string (str);
			store.append (new Hdy.ValueObject (val));
			str = dgettext (null, "5");
			val.set_string (str);
			store.append (new Hdy.ValueObject (val));
			cache_keep_nb_comborow.bind_name_model (store, (object) => {
				unowned Hdy.ValueObject value_object = object as Hdy.ValueObject;
				return value_object.get_string ();
			});
			uint64 keep_num_pkgs = config.clean_keep_num_pkgs;
			if (keep_num_pkgs < 6) {
				cache_keep_nb_comborow.selected_index = (int) keep_num_pkgs;
			} else {
				cache_keep_nb_comborow.selected_index = 5;
			}
			cache_keep_nb_comborow.notify["selected-index"].connect (on_cache_keep_nb_comborow_changed);
			config.bind_property ("clean_rm_only_uninstalled", cache_only_uninstalled_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			cache_only_uninstalled_button.notify["active"].connect (on_cache_only_uninstalled_button_changed);
			refresh_clean_cache_button.begin ();
			// set advanced
			local_config.bind_property ("software_mode", advanced_preferences_page, "visible", BindingFlags.SYNC_CREATE | BindingFlags.INVERT_BOOLEAN);
			config.bind_property ("checkspace", check_space_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			config.bind_property ("recurse", remove_unrequired_deps_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			config.bind_property ("simple_install", simple_install_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			config.bind_property ("enable_downgrade", enable_downgrade_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			populate_ignorepkgs_list ();
			// set third party
			third_party_preferences_page.visible = !local_config.software_mode || config.support_flatpak || config.support_snap;
			local_config.notify["software-mode"].connect (on_software_mode_changed);
			local_config.bind_property ("software_mode", aur_preferences_group, "visible", BindingFlags.SYNC_CREATE | BindingFlags.INVERT_BOOLEAN);
			config.bind_property ("enable_aur", enable_aur_expander, "enable_expansion", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			config.bind_property ("enable_aur", enable_aur_expander, "expanded", BindingFlags.SYNC_CREATE);
			config.bind_property ("keep_built_pkgs", keep_built_pkgs_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			config.bind_property ("check_aur_updates", check_aur_updates_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			config.bind_property ("check_aur_vcs_updates", check_aur_vcs_updates_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			config.bind_property ("check_aur_updates", check_aur_vcs_updates_button, "sensitive", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			aur_build_dir_file_chooser.label = Path.get_basename (config.aur_build_dir);
			refresh_clean_build_files_button.begin ();
			config.bind_property ("support_flatpak", flatpak_preferences_group, "visible", BindingFlags.SYNC_CREATE);
			config.bind_property ("enable_flatpak", enable_flatpak_expander, "enable_expansion", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			config.bind_property ("enable_flatpak", enable_flatpak_expander, "expanded", BindingFlags.SYNC_CREATE);
			config.bind_property ("check_flatpak_updates", check_flatpak_updates_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			config.bind_property ("support_snap", snap_preferences_group, "visible", BindingFlags.SYNC_CREATE);
			config.bind_property ("enable_snap", enable_snap_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
		}

		async void refresh_clean_cache_button () {
			HashTable<string, uint64?> details = yield database.get_clean_cache_details_async ();
			var iter = HashTableIter<string, uint64?> (details);
			uint64 total_size = 0;
			uint files_nb = 0;
			uint64? size;
			while (iter.next (null, out size)) {
				total_size += size;
				files_nb++;
			}
			clean_cache_label.set_markup ("<b>%s:  %s  (%s)</b>".printf (dgettext (null, "To delete"), dngettext (null, "%u file", "%u files", files_nb).printf (files_nb), format_size (total_size)));
			if (files_nb++ > 0 && !transaction_running) {
				clean_cache_button.sensitive = true;
			} else {
				clean_cache_button.sensitive = false;
			}
		}

		async void refresh_clean_build_files_button () {
			HashTable<string, uint64?> details = database.get_build_files_details ();
			var iter = HashTableIter<string, uint64?> (details);
			uint64 total_size = 0;
			uint files_nb = 0;
			uint64? size;
			while (iter.next (null, out size)) {
				total_size += size;
				files_nb++;
			}
			clean_build_files_label.set_markup ("<b>%s:  %s  (%s)</b>".printf (dgettext (null, "To delete"), dngettext (null, "%u file", "%u files", files_nb).printf (files_nb), format_size (total_size)));
			if (files_nb++ > 0 && !transaction_running) {
				clean_build_files_button.sensitive = true;
			} else {
				clean_build_files_button.sensitive = false;
			}
		}

		void on_check_updates_expander_changed () {
			if (check_updates_expander.enable_expansion) {
				config.refresh_period = previous_refresh_period;
			} else {
				previous_refresh_period = config.refresh_period;
				config.refresh_period = 0;
			}
		}

		void on_refresh_period_comborow_changed () {
			int index = refresh_period_comborow.selected_index;
			if (index == 0) {
				config.refresh_period = 3;
			} else if (index == 1) {
				config.refresh_period = 6;
			} else if (index == 2) {
				config.refresh_period = 12;
			} else if (index == 3) {
				config.refresh_period = 24;
			} else {
				config.refresh_period = 168;
			}
		}

		void on_parallel_downloads_comborow_changed () {
			int index = parallel_downloads_comborow.selected_index;
			if (index == 0) {
				config.max_parallel_downloads = 1;
			} else if (index == 1) {
				config.max_parallel_downloads = 2;
			} else if (index == 2) {
				config.max_parallel_downloads = 4;
			} else if (index == 3) {
				config.max_parallel_downloads = 6;
			} else if (index == 4) {
				config.max_parallel_downloads = 8;
			} else {
				config.max_parallel_downloads = 10;
			}
		}

		void on_cache_keep_nb_comborow_changed () {
			config.clean_keep_num_pkgs = cache_keep_nb_comborow.selected_index;
			refresh_clean_cache_button.begin ();
		}

		void on_cache_only_uninstalled_button_changed () {
			refresh_clean_cache_button.begin ();
		}

		void on_software_mode_changed () {
			third_party_preferences_page.visible = !local_config.software_mode || config.support_flatpak || config.support_snap;
		}

		[GtkCallback]
		void on_aur_build_dir_file_chooser_clicked () {
			this.hide ();
			Gtk.FileChooserDialog chooser = new Gtk.FileChooserDialog (
				dgettext (null, "Select Build Directory"),
				this,
				Gtk.FileChooserAction.SELECT_FOLDER,
				dgettext (null, "_Cancel"), Gtk.ResponseType.CANCEL,
				dgettext (null, "_Choose"), Gtk.ResponseType.ACCEPT);
			chooser.icon_name = "system-software-install";
			string default_build_dir = "/var/tmp";
			unowned string config_build_dir = config.aur_build_dir;
			try {
				chooser.add_shortcut_folder (default_build_dir);
				if (config_build_dir != default_build_dir) {
					chooser.add_shortcut_folder (config_build_dir);
				}
				chooser.set_current_folder (config_build_dir);
			} catch (Error e) {
				warning (e.message);
			}
			chooser.response.connect ((response) => {
				if (response == Gtk.ResponseType.ACCEPT) {
					File choosen_dir = chooser.get_file ();
					aur_build_dir_file_chooser.label = choosen_dir.get_basename ();
					config.aur_build_dir = choosen_dir.get_path ();
					refresh_clean_build_files_button.begin ();
				}
				chooser.destroy ();
				this.show ();
			});
			chooser.show ();
		}

		void populate_ignorepkgs_list () {
			var image = new Gtk.Image.from_icon_name ("list-add-symbolic", Gtk.IconSize.BUTTON);
			image.visible = true;
			image.margin_top = 12;
			image.margin_bottom = 12;
			image.margin_start = 12;
			image.margin_end = 12;
			image.halign = Gtk.Align.CENTER;
			ignorepkgs_listbox.add (image);
			ignorepkgs_listbox.row_activated.connect (on_add_ignorepkgs_button_clicked);
			foreach (unowned string ignorepkg in config.ignorepkgs) {
				add_ignorepkg (ignorepkg);
			}
		}

		void add_ignorepkg (string pkgname) {
			var row = new Gtk.ListBoxRow ();
			row.visible = true;
			row.activatable = false;
			var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
			box.visible = true;
			var label = new Gtk.Label (pkgname);
			label.visible = true;
			label.margin_top = 12;
			label.margin_bottom = 12;
			label.margin_start = 12;
			label.halign = Gtk.Align.START;
			label.hexpand = true;
			label.ellipsize = Pango.EllipsizeMode.END;
			box.add (label);
			var button = new Gtk.Button ();
			button.visible = true;
			button.margin_end = 12;
			button.relief = Gtk.ReliefStyle.NONE;
			button.valign = Gtk.Align.CENTER;
			button.image = new Gtk.Image.from_icon_name ("list-remove-symbolic", Gtk.IconSize.BUTTON);
			button.clicked.connect (() => {
				row.destroy ();
				config.remove_ignorepkg (pkgname);
			});
			box.add (button);
			row.add (box);
			ignorepkgs_listbox.add (row);
		}

		void on_add_ignorepkgs_button_clicked () {
			var choose_pkgs_dialog = transaction.create_choose_pkgs_dialog ();
			choose_pkgs_dialog.title = dgettext (null, "Choose Ignored Upgrades");
			this.get_window ().set_cursor (new Gdk.Cursor.for_display (Gdk.Display.get_default (), Gdk.CursorType.WATCH));
			database.get_installed_pkgs_async.begin ((obj, res) => {
				var pkgs = database.get_installed_pkgs_async.end (res);
				var ignorepkgs_unique = new GenericSet<string?> (str_hash, str_equal);
				foreach (unowned Package pkg in pkgs) {
					unowned string pkgname = pkg.name;
					if (pkgname in ignorepkgs_unique) {
						continue;
					}
					if (pkgname in config.ignorepkgs) {
						continue;
					}
					ignorepkgs_unique.add (pkgname);
					choose_pkgs_dialog.add_pkg (pkgname);
				}
				choose_pkgs_dialog.cancel_button.grab_focus ();
				this.get_window ().set_cursor (null);
				choose_pkgs_dialog.response.connect ((response) => {
					if (response == Gtk.ResponseType.OK) {
						foreach (unowned string pkgname in choose_pkgs_dialog.get_selected_pkgs ()) {
							config.add_ignorepkg (pkgname);
							add_ignorepkg (pkgname);
						}
					}
					choose_pkgs_dialog.destroy ();
				});
				choose_pkgs_dialog.enable_search ();
				choose_pkgs_dialog.show ();
			});
		}

		void on_mirrors_country_comborow_changed () {
			generate_mirrors_list_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
		}

		[GtkCallback]
		void on_generate_mirrors_list_button_clicked () {
			unowned ManagerWindow manager_window = this.transient_for as ManagerWindow;
			if (manager_window.transaction_running || manager_window.generate_mirrors_list) {
				return;
			}
			unowned ListModel model = mirrors_country_comborow.get_model ();
			Object object = model.get_item (mirrors_country_comborow.selected_index);
			unowned Hdy.ValueObject value_object = object as Hdy.ValueObject;
			string preferences_choosen_country = value_object.dup_string ();
			if (preferences_choosen_country == dgettext (null, "Worldwide")) {
				preferences_choosen_country = "all";
			}
			transaction.start_progressbar_pulse ();
			manager_window.important_details = true;
			manager_window.generate_mirrors_list = true;
			manager_window.apply_button.sensitive = false;
			manager_window.details_button.sensitive = true;
			manager_window.infobox_revealer.reveal_child = true;
			transaction.generate_mirrors_list_async.begin (preferences_choosen_country, (obj, res) => {
				manager_window.generate_mirrors_list = false;
				transaction.reset_progress_box ();
				generate_mirrors_list_button.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
			});
		}

		[GtkCallback]
		void on_clean_cache_button_clicked () {
			transaction.clean_cache_async.begin (() => {
				refresh_clean_cache_button.begin ();
			});
		}

		[GtkCallback]
		void on_clean_build_files_button_clicked () {
			transaction.clean_build_files_async.begin (() => {
				refresh_clean_build_files_button.begin ();
			});
		}
	}
}
