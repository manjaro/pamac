/*
 *  pamac-vala
 *
 *  Copyright (C) 2015-2023 Guillaume Benoit <guillaume@manjaro.org>
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
	class PreferencesWindow : Adw.PreferencesWindow {
		[GtkChild]
		unowned Adw.PreferencesGroup updates_preferences_group;
		[GtkChild]
		unowned Adw.ExpanderRow check_updates_expander;
		[GtkChild]
		unowned Adw.ComboRow refresh_period_comborow;
		[GtkChild]
		unowned Gtk.Switch no_update_hide_icon_button;
		[GtkChild]
		unowned Gtk.Switch download_updates_button;
		[GtkChild]
		unowned Gtk.Switch offline_upgrade_button;
		[GtkChild]
		unowned Adw.ComboRow parallel_downloads_comborow;
		[GtkChild]
		unowned Adw.PreferencesGroup mirrors_preferences_group;
		[GtkChild]
		unowned Adw.ComboRow mirrors_country_comborow;
		[GtkChild]
		unowned Gtk.Button generate_mirrors_list_button;
		[GtkChild]
		unowned Adw.ComboRow cache_keep_nb_comborow;
		[GtkChild]
		unowned Gtk.Switch cache_only_uninstalled_button;
		[GtkChild]
		unowned Gtk.Label clean_cache_label;
		[GtkChild]
		unowned Gtk.Button clean_cache_button;
		[GtkChild]
		unowned Adw.PreferencesPage advanced_preferences_page;
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
		unowned Adw.PreferencesPage third_party_preferences_page;
		[GtkChild]
		unowned Adw.PreferencesGroup aur_preferences_group;
		[GtkChild]
		unowned Adw.ExpanderRow enable_aur_expander;
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
		unowned Adw.PreferencesGroup flatpak_preferences_group;
		[GtkChild]
		unowned Adw.ExpanderRow enable_flatpak_expander;
		[GtkChild]
		unowned Gtk.Switch check_flatpak_updates_button;
		[GtkChild]
		unowned Adw.PreferencesGroup snap_preferences_group;
		[GtkChild]
		unowned Gtk.Switch enable_snap_button;

		unowned LocalConfig local_config;
		unowned Config config;
		unowned Database database;
		unowned TransactionGtk transaction;
		uint64 previous_refresh_period;

		bool transaction_running;

		public PreferencesWindow (ManagerWindow window) {
			Object (transient_for: window);

			transaction = window.transaction;
			database = transaction.database;
			config = database.config;
			local_config = window.local_config;
			// set check updates
			var store = new GLib.ListStore (typeof (Gtk.StringObject));
			var obj = new Gtk.StringObject (dgettext (null, "every 3 hours"));
			store.append (obj);
			obj = new Gtk.StringObject (dgettext (null, "every 6 hours"));
			store.append (obj);
			obj = new Gtk.StringObject (dgettext (null, "every 12 hours"));
			store.append (obj);
			obj = new Gtk.StringObject (dgettext (null, "every day"));
			store.append (obj);
			obj = new Gtk.StringObject (dgettext (null, "every week"));
			store.append (obj);
			refresh_period_comborow.set_model (store);
			var factory = new Gtk.SignalListItemFactory ();
			factory.setup.connect ((listitem) => {
				var label = new Gtk.Label (null);
				listitem.set_child (label);
			});
			factory.bind.connect ((listitem) => {
				unowned Gtk.Widget child = listitem.child;
				unowned Gtk.Label label = child as Gtk.Label;
				unowned Object object = listitem.item;
				unowned Gtk.StringObject string_object = object as Gtk.StringObject;
				label.label = string_object.get_string ();
			});
			refresh_period_comborow.set_factory (factory);
			if (config.refresh_period == 0) {
				check_updates_expander.enable_expansion = false;
				check_updates_expander.expanded = false;
				refresh_period_comborow.selected = 1;
				previous_refresh_period = 6;
			} else {
				check_updates_expander.enable_expansion = true;
				check_updates_expander.expanded = true;
				uint64 refresh_period = config.refresh_period;
				if (refresh_period <= 3) {
					refresh_period_comborow.selected = 0;
				} else if (refresh_period <= 6) {
					refresh_period_comborow.selected = 1;
				} else if (refresh_period <= 12) {
					refresh_period_comborow.selected = 2;
				} else if (refresh_period <= 24) {
					refresh_period_comborow.selected = 3;
				} else {
					refresh_period_comborow.selected = 4;
				}
			}
			check_updates_expander.notify["enable-expansion"].connect (on_check_updates_expander_changed);
			refresh_period_comborow.notify["selected"].connect (on_refresh_period_comborow_changed);
			config.bind_property ("download_updates", download_updates_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			config.bind_property ("offline_upgrade", offline_upgrade_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			config.bind_property ("download_updates", offline_upgrade_button, "sensitive", BindingFlags.SYNC_CREATE);
			config.bind_property ("no_update_hide_icon", no_update_hide_icon_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			// set parallel downloads
			store = new GLib.ListStore (typeof (Gtk.StringObject));
			obj = new Gtk.StringObject (dgettext (null, "1"));
			store.append (obj);
			obj = new Gtk.StringObject (dgettext (null, "2"));
			store.append (obj);
			obj = new Gtk.StringObject (dgettext (null, "4"));
			store.append (obj);
			obj = new Gtk.StringObject (dgettext (null, "6"));
			store.append (obj);
			obj = new Gtk.StringObject (dgettext (null, "8"));
			store.append (obj);
			obj = new Gtk.StringObject (dgettext (null, "10"));
			store.append (obj);
			parallel_downloads_comborow.set_model (store);
			parallel_downloads_comborow.set_factory (factory);
			uint64 max_parallel_downloads = config.max_parallel_downloads;
			if (max_parallel_downloads <= 1) {
				parallel_downloads_comborow.selected = 0;
			} else if (max_parallel_downloads <= 2) {
				parallel_downloads_comborow.selected = 1;
			} else if (max_parallel_downloads <= 4) {
				parallel_downloads_comborow.selected = 2;
			} else if (max_parallel_downloads <= 6) {
				parallel_downloads_comborow.selected = 3;
			} else if (max_parallel_downloads <= 8) {
				parallel_downloads_comborow.selected = 4;
			} else {
				parallel_downloads_comborow.selected = 5;
			}
			parallel_downloads_comborow.notify["selected"].connect (on_parallel_downloads_comborow_changed);
			// set mirrors
			if (database.has_installed_satisfier ("pacman-mirrors")) {
				var mirrors_store = new GLib.ListStore (typeof (Gtk.StringObject));
				obj = new Gtk.StringObject (dgettext (null, "Worldwide"));
				mirrors_store.append (obj);
				int index = 1;
				database.get_mirrors_choosen_country_async.begin ((obj, res) => {
					string preferences_choosen_country = database.get_mirrors_choosen_country_async.end (res);
					database.get_mirrors_countries_async.begin ((obj, res) => {
						var countries = database.get_mirrors_countries_async.end (res);
						foreach (unowned string country in countries) {
							var country_obj = new Gtk.StringObject (country);
							mirrors_store.append (country_obj);
							if (country == preferences_choosen_country) {
								mirrors_country_comborow.selected = index;
							}
							index += 1;
						}
						mirrors_country_comborow.notify["selected"].connect (on_mirrors_country_comborow_changed);
					});
				});
				mirrors_country_comborow.set_model (mirrors_store);
				mirrors_country_comborow.set_factory (factory);
			} else {
				mirrors_preferences_group.visible = false;
			}
			// set cache options
			store = new GLib.ListStore (typeof (Gtk.StringObject));
			obj = new Gtk.StringObject (dgettext (null, "0"));
			store.append (obj);
			obj = new Gtk.StringObject (dgettext (null, "1"));
			store.append (obj);
			obj = new Gtk.StringObject (dgettext (null, "2"));
			store.append (obj);
			obj = new Gtk.StringObject (dgettext (null, "3"));
			store.append (obj);
			obj = new Gtk.StringObject (dgettext (null, "4"));
			store.append (obj);
			obj = new Gtk.StringObject (dgettext (null, "5"));
			store.append (obj);
			cache_keep_nb_comborow.set_model (store);
			cache_keep_nb_comborow.set_factory (factory);
			uint64 keep_num_pkgs = config.clean_keep_num_pkgs;
			if (keep_num_pkgs < 6) {
				cache_keep_nb_comborow.selected = (int) keep_num_pkgs;
			} else {
				cache_keep_nb_comborow.selected = 5;
			}
			cache_keep_nb_comborow.notify["selected"].connect (on_cache_keep_nb_comborow_changed);
			config.bind_property ("clean_rm_only_uninstalled", cache_only_uninstalled_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			cache_only_uninstalled_button.notify["active"].connect (on_cache_only_uninstalled_button_changed);
			refresh_clean_cache_button.begin ();
			// set advanced
			if (local_config.software_mode) {
				this.remove (advanced_preferences_page);
			}
			config.bind_property ("checkspace", check_space_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			config.bind_property ("recurse", remove_unrequired_deps_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			config.bind_property ("simple_install", simple_install_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			config.bind_property ("enable_downgrade", enable_downgrade_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			populate_ignorepkgs_list ();
			// set third party
			if (local_config.software_mode && !config.support_flatpak && !config.support_snap) {
				this.remove (third_party_preferences_page);
			}
			local_config.bind_property ("software_mode", aur_preferences_group, "visible", BindingFlags.SYNC_CREATE | BindingFlags.INVERT_BOOLEAN);
			config.bind_property ("support_aur", aur_preferences_group, "visible", BindingFlags.SYNC_CREATE);
			config.bind_property ("enable_aur", enable_aur_expander, "enable_expansion", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			config.bind_property ("enable_aur", enable_aur_expander, "expanded", BindingFlags.SYNC_CREATE);
			config.bind_property ("keep_built_pkgs", keep_built_pkgs_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			config.bind_property ("check_aur_updates", check_aur_updates_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			config.bind_property ("check_aur_vcs_updates", check_aur_vcs_updates_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			config.bind_property ("check_aur_updates", check_aur_vcs_updates_button, "sensitive", BindingFlags.SYNC_CREATE);
			if (config.support_aur) {
				aur_build_dir_file_chooser.label = Path.get_basename (config.aur_build_dir);
				refresh_clean_build_files_button.begin ();
			}
			config.bind_property ("support_flatpak", flatpak_preferences_group, "visible", BindingFlags.SYNC_CREATE);
			config.bind_property ("enable_flatpak", enable_flatpak_expander, "enable_expansion", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			config.bind_property ("enable_flatpak", enable_flatpak_expander, "expanded", BindingFlags.SYNC_CREATE);
			config.bind_property ("check_flatpak_updates", check_flatpak_updates_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			config.bind_property ("support_snap", snap_preferences_group, "visible", BindingFlags.SYNC_CREATE);
			config.bind_property ("enable_snap", enable_snap_button, "active", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
			// set_correct_focus
			updates_preferences_group.grab_focus ();
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
			uint index = refresh_period_comborow.selected;
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
			uint index = parallel_downloads_comborow.selected;
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
			config.clean_keep_num_pkgs = cache_keep_nb_comborow.selected;
			refresh_clean_cache_button.begin ();
		}

		void on_cache_only_uninstalled_button_changed () {
			refresh_clean_cache_button.begin ();
		}

		[GtkCallback]
		void on_aur_build_dir_file_chooser_clicked () {
			var chooser = new Gtk.FileDialog ();
			chooser.title = dgettext (null, "Select Build Directory");
			var default_build_dir_file = File.new_for_path ("/var/tmp");
			chooser.initial_folder = default_build_dir_file;
			chooser.select_folder.begin (this, null, (obj, res) => {
				try {
					File choosen_dir = chooser.select_folder.end (res);
					aur_build_dir_file_chooser.label = choosen_dir.get_basename ();
					config.aur_build_dir = choosen_dir.get_path ();
					refresh_clean_build_files_button.begin ();
				} catch (Error e) {
					warning (e.message);
				}
			});
		}

		void populate_ignorepkgs_list () {
			var image = new Gtk.Image.from_icon_name ("list-add-symbolic");
			image.margin_top = 12;
			image.margin_bottom = 12;
			image.margin_start = 12;
			image.margin_end = 12;
			image.halign = Gtk.Align.CENTER;
			ignorepkgs_listbox.append (image);
			ignorepkgs_listbox.row_activated.connect (on_add_ignorepkgs_button_clicked);
			foreach (unowned string ignorepkg in config.ignorepkgs) {
				add_ignorepkg (ignorepkg);
			}
		}

		void add_ignorepkg (string pkgname) {
			var row = new Gtk.ListBoxRow ();
			row.activatable = false;
			var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
			var label = new Gtk.Label (pkgname);
			label.margin_top = 12;
			label.margin_bottom = 12;
			label.margin_start = 12;
			label.halign = Gtk.Align.START;
			label.hexpand = true;
			label.ellipsize = Pango.EllipsizeMode.END;
			box.append (label);
			var button = new Gtk.Button ();
			button.margin_end = 12;
			button.has_frame = false;
			button.valign = Gtk.Align.CENTER;
			button.icon_name  = "list-remove-symbolic";
			button.clicked.connect (() => {
				ignorepkgs_listbox.remove (row);
				config.remove_ignorepkg (pkgname);
			});
			box.append (button);
			row.set_child (box);
			ignorepkgs_listbox.append (row);
		}

		void on_add_ignorepkgs_button_clicked () {
			var choose_pkgs_dialog = transaction.create_choose_pkgs_dialog ();
			choose_pkgs_dialog.heading = dgettext (null, "Choose Ignored Upgrades");
			this.set_cursor (new Gdk.Cursor.from_name ("progress", null));
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
				this.set_cursor (new Gdk.Cursor.from_name ("default", null));
				choose_pkgs_dialog.response.connect ((response) => {
					if (response == "choose") {
						foreach (unowned string pkgname in choose_pkgs_dialog.get_selected_pkgs ()) {
							config.add_ignorepkg (pkgname);
							add_ignorepkg (pkgname);
						}
					}
				});
				choose_pkgs_dialog.enable_search ();
				choose_pkgs_dialog.present ();
			});
		}

		void on_mirrors_country_comborow_changed () {
			generate_mirrors_list_button.add_css_class ("suggested-action");
		}

		[GtkCallback]
		void on_generate_mirrors_list_button_clicked () {
			unowned ManagerWindow manager_window = this.transient_for as ManagerWindow;
			if (manager_window.transaction_running || manager_window.generate_mirrors_list) {
				return;
			}
			Object object = mirrors_country_comborow.selected_item;
			unowned Gtk.StringObject string_object = object as Gtk.StringObject;
			string preferences_choosen_country = string_object.get_string ();
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
				generate_mirrors_list_button.remove_css_class ("suggested-action");
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
