/*
 *  pamac-vala
 *
 *  Copyright (C) 2015-2019 Guillaume Benoit <guillaume@manjaro.org>
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
		Gtk.Switch check_updates_button;
		[GtkChild]
		Gtk.Switch enable_downgrade_button;
		[GtkChild]
		Gtk.Label refresh_period_label;
		[GtkChild]
		Gtk.SpinButton refresh_period_spin_button;
		[GtkChild]
		Gtk.Label max_parallel_downloads_label;
		[GtkChild]
		Gtk.SpinButton max_parallel_downloads_spin_button;
		[GtkChild]
		Gtk.CheckButton no_update_hide_icon_checkbutton;
		[GtkChild]
		Gtk.CheckButton download_updates_checkbutton;
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
		Gtk.CheckButton keep_built_pkgs_checkbutton;
		[GtkChild]
		Gtk.CheckButton check_aur_updates_checkbutton;
		[GtkChild]
		Gtk.CheckButton check_aur_vcs_updates_checkbutton;
		[GtkChild]
		Gtk.Label cache_keep_nb_label;
		[GtkChild]
		Gtk.SpinButton cache_keep_nb_spin_button;
		[GtkChild]
		Gtk.CheckButton cache_only_uninstalled_checkbutton;
		[GtkChild]
		Gtk.Button clean_build_files_button;
		[GtkChild]
		Gtk.Label clean_build_files_label;
		[GtkChild]
		Gtk.Label clean_cache_label;
		[GtkChild]
		Gtk.Button clean_cache_button;
		[GtkChild]
		Gtk.Box snap_config_box;
		#if ENABLE_SNAP
		[GtkChild]
		Gtk.Switch enable_snap_button;
		#endif

		TransactionGtk transaction;
		uint64 previous_refresh_period;
		string preferences_choosen_country;

		public PreferencesDialog (TransactionGtk transaction) {
			int use_header_bar;
			Gtk.Settings.get_default ().get ("gtk-dialogs-use-header", out use_header_bar);
			Object (transient_for: transaction.application_window, use_header_bar: use_header_bar);

			this.transaction = transaction;
			refresh_period_label.set_markup (dgettext (null, "How often to check for updates, value in hours") +":");
			max_parallel_downloads_label.set_markup (dgettext (null, "Maximum parallel downloads") +":");
			cache_keep_nb_label.set_markup (dgettext (null, "Number of versions of each package to keep in the cache") +":");
			aur_build_dir_label.set_markup (dgettext (null, "Build directory") +":");
			remove_unrequired_deps_button.active = transaction.database.config.recurse;
			enable_downgrade_button.active = transaction.database.config.enable_downgrade;
			if (transaction.database.config.refresh_period == 0) {
				check_updates_button.active = false;
				refresh_period_label.sensitive = false;
				// set default value
				refresh_period_spin_button.value = 6;
				previous_refresh_period = 6;
				refresh_period_spin_button.sensitive = false;
				no_update_hide_icon_checkbutton.sensitive = false;
				download_updates_checkbutton.sensitive = false;
			} else {
				check_updates_button.active = true;
				refresh_period_spin_button.value = transaction.database.config.refresh_period;
				previous_refresh_period = transaction.database.config.refresh_period;
			}
			max_parallel_downloads_spin_button.value = transaction.database.config.max_parallel_downloads;
			no_update_hide_icon_checkbutton.active = transaction.database.config.no_update_hide_icon;
			download_updates_checkbutton.active = transaction.database.config.download_updates;
			cache_keep_nb_spin_button.value = transaction.database.config.clean_keep_num_pkgs;
			cache_only_uninstalled_checkbutton.active = transaction.database.config.clean_rm_only_uninstalled;
			refresh_clean_cache_button ();

			remove_unrequired_deps_button.state_set.connect (on_remove_unrequired_deps_button_state_set);
			check_updates_button.state_set.connect (on_check_updates_button_state_set);
			enable_downgrade_button.state_set.connect (on_enable_downgrade_button_state_set);
			refresh_period_spin_button.value_changed.connect (on_refresh_period_spin_button_value_changed);
			max_parallel_downloads_spin_button.value_changed.connect (on_max_parallel_downloads_spin_button_value_changed);
			no_update_hide_icon_checkbutton.toggled.connect (on_no_update_hide_icon_checkbutton_toggled);
			download_updates_checkbutton.toggled.connect (on_download_updates_checkbutton_toggled);
			cache_keep_nb_spin_button.value_changed.connect (on_cache_keep_nb_spin_button_value_changed);
			cache_only_uninstalled_checkbutton.toggled.connect (on_cache_only_uninstalled_checkbutton_toggled);

			if (!transaction.database.has_installed_satisfier ("pacman-mirrors")) {
				mirrors_config_box.visible = false;
			} else {
				mirrors_country_comboboxtext.append_text (dgettext (null, "Worldwide"));
				mirrors_country_comboboxtext.active = 0;
				int index = 1;
				preferences_choosen_country = transaction.database.get_mirrors_choosen_country ();
				foreach (unowned string country in transaction.database.get_mirrors_countries ()) {
					mirrors_country_comboboxtext.append_text (country);
					if (country == preferences_choosen_country) {
						mirrors_country_comboboxtext.active = index;
					}
					index += 1;
				}
				mirrors_country_comboboxtext.changed.connect (on_mirrors_country_comboboxtext_changed);
			}

			enable_aur_button.active = transaction.database.config.enable_aur;
			aur_build_dir_label.sensitive = transaction.database.config.enable_aur;
			aur_build_dir_file_chooser.sensitive = transaction.database.config.enable_aur;
			string default_build_dir = "var/tmp";
			string current_build_dir = Path.get_dirname (transaction.database.config.aur_build_dir);
			try {
				aur_build_dir_file_chooser.add_shortcut_folder (default_build_dir);
				if (current_build_dir != default_build_dir) {
					aur_build_dir_file_chooser.add_shortcut_folder (current_build_dir);
				}
			} catch (GLib.Error e) {
				critical ("%s\n", e.message);
			}
			aur_build_dir_file_chooser.select_filename (current_build_dir);
			refresh_clean_build_files_button ();
			keep_built_pkgs_checkbutton.active = transaction.database.config.keep_built_pkgs;
			keep_built_pkgs_checkbutton.sensitive = transaction.database.config.enable_aur;
			check_aur_updates_checkbutton.active = transaction.database.config.check_aur_updates;
			check_aur_updates_checkbutton.sensitive = transaction.database.config.enable_aur;
			check_aur_vcs_updates_checkbutton.active = transaction.database.config.check_aur_vcs_updates;
			check_aur_vcs_updates_checkbutton.sensitive = transaction.database.config.enable_aur
														&& transaction.database.config.check_aur_updates;
			enable_aur_button.state_set.connect (on_enable_aur_button_state_set);
			aur_build_dir_file_chooser.file_set.connect (on_aur_build_dir_set);
			keep_built_pkgs_checkbutton.toggled.connect (on_keep_built_pkgs_checkbutton_toggled);
			check_aur_updates_checkbutton.toggled.connect (on_check_aur_updates_checkbutton_toggled);
			check_aur_vcs_updates_checkbutton.toggled.connect (on_check_aur_vcs_updates_checkbutton_toggled);

			#if ENABLE_SNAP
			if (transaction.database.config.support_snap) {
				snap_config_box.visible = true;
				enable_snap_button.active = transaction.database.config.enable_snap;
				enable_snap_button.state_set.connect (on_enable_snap_button_state_set);
			} else {
				snap_config_box.visible = false;
			}
			#else
			snap_config_box.visible = false;
			#endif
		}

		void refresh_clean_cache_button () {
			HashTable<string, int64?> details = transaction.database.get_clean_cache_details ();
			int64 total_size = 0;
			uint files_nb = 0;
			foreach (int64 size in details.get_values ()) {
				total_size += size;
				files_nb++;
			}
			clean_cache_label.set_markup ("<b>%s:  %s  (%s)</b>".printf (dgettext (null, "To delete"), dngettext (null, "%u file", "%u files", files_nb).printf (files_nb), format_size (total_size)));
			if (files_nb++ > 0) {
				clean_cache_button.sensitive = true;
			} else {
				clean_cache_button.sensitive = false;
			}
		}

		void refresh_clean_build_files_button () {
			if (transaction.database.config.enable_aur) {
				HashTable<string, int64?> details = transaction.database.get_build_files_details ();
				int64 total_size = 0;
				uint files_nb = 0;
				foreach (int64 size in details.get_values ()) {
					total_size += size;
					files_nb++;
				}
				clean_build_files_label.set_markup ("<b>%s:  %s  (%s)</b>".printf (dgettext (null, "To delete"), dngettext (null, "%u file", "%u files", files_nb).printf (files_nb), format_size (total_size)));
				if (files_nb++ > 0) {
					clean_build_files_button.sensitive = true;
				} else {
					clean_build_files_button.sensitive = false;
				}
			} else {
				clean_build_files_label.set_markup ("");
				clean_build_files_button.sensitive = false;
			}
		}

		bool on_remove_unrequired_deps_button_state_set (bool new_state) {
			remove_unrequired_deps_button.state = new_state;
			transaction.database.config.recurse = new_state;
			transaction.set_trans_flags ();
			return true;
		}

		bool on_check_updates_button_state_set (bool new_state) {
			check_updates_button.state = new_state;
			refresh_period_label.sensitive = new_state;
			refresh_period_spin_button.sensitive = new_state;
			no_update_hide_icon_checkbutton.sensitive = new_state;
			download_updates_checkbutton.sensitive = new_state;
			if (new_state) {
				transaction.database.config.refresh_period = previous_refresh_period;
			} else {
				previous_refresh_period = transaction.database.config.refresh_period;
				transaction.database.config.refresh_period = 0;
			}
			return true;
		}

		bool on_enable_downgrade_button_state_set (bool new_state) {
			enable_downgrade_button.state = new_state;
			transaction.database.config.enable_downgrade = new_state;
			return true;
		}

		void on_refresh_period_spin_button_value_changed () {
			transaction.database.config.refresh_period = refresh_period_spin_button.get_value_as_int ();
		}

		void on_max_parallel_downloads_spin_button_value_changed () {
			transaction.database.config.max_parallel_downloads = max_parallel_downloads_spin_button.get_value_as_int ();
		}

		void on_cache_keep_nb_spin_button_value_changed () {
			transaction.database.config.clean_keep_num_pkgs = cache_keep_nb_spin_button.get_value_as_int ();
			refresh_clean_cache_button ();
		}

		void on_cache_only_uninstalled_checkbutton_toggled () {
			transaction.database.config.clean_rm_only_uninstalled = cache_only_uninstalled_checkbutton.active;
			refresh_clean_cache_button ();
		}

		void on_no_update_hide_icon_checkbutton_toggled () {
			transaction.database.config.no_update_hide_icon = no_update_hide_icon_checkbutton.active;
		}

		void on_download_updates_checkbutton_toggled () {
			transaction.database.config.download_updates = download_updates_checkbutton.active;
		}

		bool on_enable_aur_button_state_set (bool new_state) {
			enable_aur_button.state = new_state;
			aur_build_dir_label.sensitive = new_state;
			aur_build_dir_file_chooser.sensitive = new_state;
			keep_built_pkgs_checkbutton.sensitive = new_state;
			check_aur_updates_checkbutton.sensitive = new_state;
			check_aur_vcs_updates_checkbutton.sensitive = new_state && check_aur_updates_checkbutton.active;
			transaction.database.config.enable_aur = new_state;
			refresh_clean_build_files_button ();
			return true;
		}

		#if ENABLE_SNAP
		bool on_enable_snap_button_state_set (bool new_state) {
			enable_snap_button.state = new_state;
			transaction.database.config.enable_snap = new_state;
			return true;
		}
		#endif

		void on_aur_build_dir_set () {
			transaction.database.config.aur_build_dir = aur_build_dir_file_chooser.get_filename ();
			refresh_clean_build_files_button ();
		}

		void on_keep_built_pkgs_checkbutton_toggled () {
			transaction.database.config.keep_built_pkgs = keep_built_pkgs_checkbutton.active;
		}

		void on_check_aur_updates_checkbutton_toggled () {
			check_aur_vcs_updates_checkbutton.sensitive = transaction.database.config.enable_aur && check_aur_updates_checkbutton.active;
			transaction.database.config.check_aur_updates = check_aur_updates_checkbutton.active;
		}

		void on_check_aur_vcs_updates_checkbutton_toggled () {
			transaction.database.config.check_aur_vcs_updates = check_aur_vcs_updates_checkbutton.active;
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
			transaction.start_progressbar_pulse ();
			var manager_window = transaction.application_window as ManagerWindow;
			manager_window.generate_mirrors_list = true;
			manager_window.apply_button.sensitive = false;
			manager_window.details_button.sensitive = true;
			transaction.generate_mirrors_list (preferences_choosen_country);
			manager_window.generate_mirrors_list = false;
			transaction.reset_progress_box ();
			generate_mirrors_list_button.get_style_context ().remove_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
		}

		[GtkCallback]
		void on_clean_cache_button_clicked () {
			transaction.clean_cache ();
			refresh_clean_cache_button ();
		}

		[GtkCallback]
		void on_clean_build_files_button_clicked () {
			transaction.clean_build_files ();
			refresh_clean_build_files_button ();
		}
	}
}
