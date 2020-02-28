/*
 *  pamac-vala
 *
 *  Copyright (C) 2019-2020 Guillaume Benoit <guillaume@manjaro.org>
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
	public class FlatPak: Object, FlatpakPlugin {
		string sender;
		Flatpak.Installation installation;
		bool appstream_data_loaded;
		HashTable<string, As.Store> stores_table;
		HashTable<string, Flatpak.RemoteRef> remote_refs_table;
		Cancellable cancellable;

		public uint64 refresh_period { get; construct set; }
		public MainContext context { get; construct set; }

		public FlatPak (uint64 refresh_period, MainContext context) {
			Object (refresh_period: refresh_period, context: context);
		}

		construct {
			cancellable = new Cancellable ();
			appstream_data_loaded = false;
			stores_table = new HashTable<string, As.Store> (str_hash, str_equal);
			remote_refs_table = new HashTable<string, Flatpak.RemoteRef> (str_hash, str_equal);
			try {
				installation = new Flatpak.Installation.system ();
			} catch (Error e) {
				warning (e.message);
			}
		}

		public void load_appstream_data () {
			if (refresh_appstream_data ()) {
				appstream_data_loaded = false;
			}
			if (appstream_data_loaded) {
				return;
			}
			stores_table.remove_all ();
			try {
				GenericArray<unowned Flatpak.Remote> remotes = installation.list_remotes ();
				for (uint i = 0; i < remotes.length; i++) {
					unowned Flatpak.Remote remote = remotes[i];
					if (remote.get_disabled ()) {
						continue;
					}
					// init appstream
					var app_store = new As.Store ();
					app_store.add_filter (As.AppKind.DESKTOP);
					app_store.set_add_flags (As.StoreAddFlags.USE_UNIQUE_ID
											| As.StoreAddFlags.ONLY_NATIVE_LANGS
											| As.StoreAddFlags.USE_MERGE_HEURISTIC);
					app_store.set_origin (remote.name);
					File appstream_dir = remote.get_appstream_dir (null);
					File? appstream_xml = appstream_dir.get_child ("appstream.xml");
					if (!appstream_xml.query_exists ()) {
						return;
					}
					string appstream_icons = Path.build_path ("/", appstream_dir.get_path (), "icons");
					try {
						app_store.from_file (appstream_xml, appstream_icons);
					} catch (Error e) {
						warning (e.message);
					}
					app_store.set_search_match (As.AppSearchMatch.ID
												| As.AppSearchMatch.DESCRIPTION
												| As.AppSearchMatch.NAME
												| As.AppSearchMatch.MIMETYPE
												| As.AppSearchMatch.COMMENT
												| As.AppSearchMatch.ORIGIN
												| As.AppSearchMatch.KEYWORD);
					app_store.load_search_cache ();
					stores_table.insert (remote.name, app_store);
				}
				appstream_data_loaded = true;
			} catch (Error e) {
				warning (e.message);
			}
		}

		int64 get_file_age (File file) {
			try {
				FileInfo info = file.query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
				DateTime last_modifed = info.get_modification_date_time ();
				var now = new DateTime.now_utc ();
				TimeSpan elapsed_time = now.difference (last_modifed);
				return elapsed_time;
			} catch (Error e) {
				warning (e.message);
				return int64.MAX;
			}
		}

		bool refresh_appstream_data () {
			bool modified = false;
			try {
				GenericArray<unowned Flatpak.Remote> remotes = installation.list_remotes ();
				for (uint i = 0; i < remotes.length; i++) {
					unowned Flatpak.Remote remote = remotes[i];
					if (remote.get_disabled ()) {
						continue;
					}
					int64 elapsed_time = get_file_age (remote.get_appstream_timestamp (null));
					int64 elapsed_hours = elapsed_time / TimeSpan.MINUTE;
					if (elapsed_hours > refresh_period) {
						info ("%lli hours elapsed since last appstream refresh", elapsed_hours);
						info ("refreshing appstream data");
						try {
							installation.update_appstream_sync (remote.name, null, null);
							modified = true;
						} catch (Error e) {
							warning (e.message);
						}
					}
				}
			} catch (Error e) {
				warning (e.message);
			}
			return modified;
		}

		string get_app_name (As.App app) {
			return app.get_name (null) ?? "";
		}

		string get_app_launchable (As.App app) {
			As.Launchable? launchable = app.get_launchable_by_kind (As.LaunchableKind.DESKTOP_ID);
			if (launchable != null) {
				return launchable.get_value ();
			}
			return "";
		}

		string get_app_summary (As.App app) {
			return app.get_comment (null) ?? "";
		}

		string get_app_description (As.App app) {
			return app.get_description (null) ?? "";
		}

		string get_app_icon (As.App app, string repo) {
			string icon = "";
			unowned GenericArray<As.Icon> icons = app.get_icons ();
			for (uint i = 0; i < icons.length; i++) {
				unowned As.Icon as_icon = icons[i];
				if (as_icon.get_kind () == As.IconKind.CACHED) {
					if (as_icon.get_height () == 64) {
						try {
							GenericArray<unowned Flatpak.Remote> remotes = installation.list_remotes ();
							for (uint j = 0; j < remotes.length; j++) {
								unowned Flatpak.Remote remote = remotes[j];
								if (remote.get_disabled ()) {
									continue;
								}
								if (remote.name == repo) {
									File appstream_dir = remote.get_appstream_dir (null);
									icon = Path.build_path ("/", appstream_dir.get_path (), "icons", "64x64", as_icon.get_name ());
									break;
								}
							}
						} catch (Error e) {
							warning (e.message);
						}
					}
				}
			}
			return icon;
		}

		GenericArray<string> get_app_screenshots (As.App app) {
			var screenshots = new GenericArray<string> ();
			unowned GLib.GenericArray<As.Screenshot> as_screenshots = app.get_screenshots ();
			for (uint i = 0; i < as_screenshots.length; i++) {
				unowned As.Screenshot as_screenshot = as_screenshots[i];
				As.Image? as_image = as_screenshot.get_source ();
				if (as_image != null) {
					string? url = as_image.get_url ();
					if (url != null) {
						screenshots.add ((owned) url);
					}
				}
			}
			return screenshots;
		}

		As.App? get_installed_ref_matching_app (Flatpak.InstalledRef installed_ref) {
			As.App? matching_app = null;
			var iter = HashTableIter<string, As.Store> (stores_table);
			unowned string remote;
			As.Store app_store;
			while (iter.next (out remote, out app_store)) {
				if (remote == installed_ref.origin) {
					unowned GLib.GenericArray<As.App> apps = app_store.get_apps ();
					for (uint i = 0; i < apps.length; i++) {
						unowned As.App app = apps[i];
						if (app.get_id_filename () == installed_ref.name) {
							matching_app = app;
							break;
						}
					}
					break;
				}
			}
			return matching_app;
		}

		As.App? get_remote_ref_matching_app (Flatpak.RemoteRef remote_ref) {
			As.App? matching_app = null;
			unowned As.Store? app_store = stores_table.lookup (remote_ref.remote_name);
			if (app_store != null) {
				unowned GenericArray<As.App> apps = app_store.get_apps ();
				for (uint i = 0; i < apps.length; i++) {
					unowned As.App app = apps[i];
					if (app.get_id_filename () == remote_ref.name) {
						matching_app = app;
						break;
					}
				}
			}
			return matching_app;
		}

		void initialize_app_data (As.App app, ref FlatpakPackage pkg) {
			pkg.app_name = get_app_name (app);
			pkg.launchable = get_app_launchable (app);
			try {
				pkg.long_desc = As.markup_convert_simple (get_app_description (app));
			} catch (Error e) {
				warning (e.message);
			}
			unowned string? license = app.get_project_license ();
			if (license != null) {
				pkg.license = license;
			}
			unowned string? url = app.get_url_item (As.UrlKind.HOMEPAGE);
			if (url != null) {
				pkg.url = url;
			}
			pkg.icon = get_app_icon (app, pkg.repo);
			pkg.screenshots_priv = get_app_screenshots (app);
		}

		void initialize_installed_ref (Flatpak.InstalledRef installed_ref, ref FlatpakPackage pkg) {
			pkg.id = "%s/%s".printf (installed_ref.origin, installed_ref.format_ref ());
			pkg.name = installed_ref.name;
			pkg.version = installed_ref.appdata_version;
			pkg.installed_version = installed_ref.appdata_version;
			pkg.repo = installed_ref.origin;
			pkg.installed_size = installed_ref.installed_size;
			pkg.desc = installed_ref.appdata_summary;
		}

		void initialize_remote_ref (Flatpak.RemoteRef remote_ref, ref FlatpakPackage pkg) {
			pkg.id = "%s/%s".printf (remote_ref.remote_name, remote_ref.format_ref ());
			pkg.name = remote_ref.name;
			pkg.repo = remote_ref.remote_name;
			pkg.installed_size = remote_ref.installed_size;
			pkg.download_size = remote_ref.download_size;
		}

		public GenericArray<string> get_remotes_names () {
			var result = new GenericArray<string> ();
			try {
				GenericArray<unowned Flatpak.Remote> remotes = installation.list_remotes ();
				for (uint i = 0; i < remotes.length; i++) {
					unowned Flatpak.Remote remote = remotes[i];
					if (remote.get_disabled ()) {
						continue;
					}
					result.add (remote.name);
				}
			} catch (Error e) {
				warning (e.message);
			}
			return result;
		}

		public SList<FlatpakPackage> get_installed_flatpaks () {
			var result = new SList<FlatpakPackage> ();
			try {
				GenericArray<unowned Flatpak.InstalledRef> installed_apps = installation.list_installed_refs_by_kind (Flatpak.RefKind.APP);
				for (uint i = 0; i < installed_apps.length; i++) {
					unowned Flatpak.InstalledRef installed_ref = installed_apps[i];
					var pkg = new FlatpakPackage ();
					initialize_installed_ref (installed_ref, ref pkg);
					As.App? app = get_installed_ref_matching_app (installed_ref);
					if (app != null) {
						initialize_app_data (app, ref pkg);
					}
					result.prepend (pkg);
				}
			} catch (Error e) {
				warning (e.message);
			}
			result.reverse ();
			return result;
		}

		public bool is_installed_flatpak (string name) {
			try {
				Flatpak.InstalledRef? installed_ref = installation.get_installed_ref (Flatpak.RefKind.APP, name, null, null);
				if (installed_ref != null) {
					return true;
				}
			} catch (Error e) {
				if (e is Flatpak.Error.NOT_INSTALLED) {
					return false;
				}  
				warning (e.message);
			}
			return false;
		}

		FlatpakPackage? get_flatpak_from_app (string remote, As.App app) {
			FlatpakPackage? pkg = null;
			try {
				Flatpak.InstalledRef? installed_ref = installation.get_installed_ref (Flatpak.RefKind.APP, app.get_id_filename (), null, app.get_branch ());
				pkg = new FlatpakPackage ();
				initialize_installed_ref (installed_ref, ref pkg);
				initialize_app_data (app, ref pkg);
			} catch (Error e) {
				if (e is Flatpak.Error.NOT_INSTALLED) {
					// try remotes
					try {
						string remote_id = "%s/%s".printf (remote, app.get_id_filename ());
						Flatpak.RemoteRef? remote_ref = remote_refs_table.lookup (remote_id);
						if (remote_ref == null) {
							remote_ref = installation.fetch_remote_ref_sync (remote, Flatpak.RefKind.APP, app.get_id_filename (), null, app.get_branch ());
						}
						if (remote_ref != null) {
							remote_refs_table.insert ((owned) remote_id, remote_ref);
							pkg = new FlatpakPackage ();
							initialize_remote_ref (remote_ref, ref pkg);
							As.Release? release = app.get_release_default ();
							if (release != null) {
								pkg.version = release.get_version ();
							} else {
								warning ("no version found for %s\n", app.get_id_filename ());
							}
							pkg.desc = get_app_summary (app);
							initialize_app_data (app, ref pkg);
						}
					} catch (Error e) {
						warning (e.message);
					}
				} else {
					warning (e.message);
				}
			}
			return pkg;
		}

		public FlatpakPackage? get_flatpak (string id) {
			string[] splitted = id.split ("/", 5);
			unowned string remote = splitted[0];
			//unowned string kind = splitted[1];
			unowned string name = splitted[2];
			unowned string arch = splitted[3];
			unowned string branch = splitted[4];
			FlatpakPackage? pkg = null;
			try {
				Flatpak.InstalledRef? installed_ref = installation.get_installed_ref (Flatpak.RefKind.APP, name, arch, branch);
				pkg = new FlatpakPackage ();
				initialize_installed_ref (installed_ref, ref pkg);
				As.App? app = get_installed_ref_matching_app (installed_ref);
				if (app != null) {
					initialize_app_data (app, ref pkg);
				}
			} catch (Error e) {
				if (e is Flatpak.Error.NOT_INSTALLED) {
					// try remotes
					try {
						string remote_id = "%s/%s".printf (remote, name);
						Flatpak.RemoteRef? remote_ref = remote_refs_table.lookup (remote_id);
						if (remote_ref == null) {
							remote_ref = installation.fetch_remote_ref_sync (remote, Flatpak.RefKind.APP, name, arch, branch);
						}
						if (remote_ref != null) {
							remote_refs_table.insert ((owned) remote_id, remote_ref);
							pkg = new FlatpakPackage ();
							initialize_remote_ref (remote_ref, ref pkg);
							As.App? app = get_remote_ref_matching_app (remote_ref);
							if (app != null) {
								As.Release? release = app.get_release_default ();
								if (release != null) {
									pkg.version = release.get_version ();
								} else {
									warning ("no version found for %s\n", app.get_id_filename ());
								}
								pkg.desc = get_app_summary (app);
								initialize_app_data (app, ref pkg);
							}
						}
					} catch (Error e) {
						warning (e.message);
					}
				} else {
					warning (e.message);
				}
			}
			return pkg;
		}

		public SList<FlatpakPackage> search_flatpaks (string search_string) {
			var result = new SList<FlatpakPackage> ();
			string[]? search_terms = As.utils_search_tokenize (search_string);
			if (search_terms != null) {
				var iter = HashTableIter<string, As.Store> (stores_table);
				unowned string remote;
				As.Store app_store;
				while (iter.next (out remote, out app_store)) {
					unowned GLib.GenericArray<As.App> apps = app_store.get_apps ();
					for (uint i = 0; i < apps.length; i++) {
						unowned As.App app = apps[i];
						uint match_score = app.search_matches_all (search_terms);
						if (match_score > 0) {
							FlatpakPackage? pkg = get_flatpak_from_app (remote, app);
							if (pkg != null) {
								result.prepend (pkg);
							}
						}
					}
				}
			}
			result.reverse ();
			return result;
		}

		public SList<FlatpakPackage> get_category_flatpaks (string category) {
			var result = new SList<FlatpakPackage> ();
			var appstream_categories = new GenericArray<string> ();
			switch (category) {
				case "Featured":
					var featured_pkgs = new GenericArray<string> (4);
					featured_pkgs.add ("com.spotify.Client");
					featured_pkgs.add ("com.valvesoftware.Steam");
					featured_pkgs.add ("com.discordapp.Discord");
					featured_pkgs.add ("com.skype.Client");
					featured_pkgs.add ("com.mojang.Minecraft");
					featured_pkgs.add ("com.slack.Slack");
					var iter = HashTableIter<string, As.Store> (stores_table);
					unowned string remote;
					As.Store app_store;
					while (iter.next (out remote, out app_store)) {
						unowned GenericArray<As.App> apps = app_store.get_apps ();
						for (uint i = 0; i < apps.length; i++) {
							unowned As.App app = apps[i];
							if (featured_pkgs.find_with_equal_func (app.get_id_filename (), str_equal)) {
								FlatpakPackage? pkg = get_flatpak_from_app (remote, app);
								if (pkg != null) {
									result.prepend (pkg);
								}
							}
						}
					}
					break;
				case "Photo & Video":
					appstream_categories.add ("Graphics");
					appstream_categories.add ("Video");
					break;
				case "Music & Audio":
					appstream_categories.add ("Audio");
					appstream_categories.add ("Music");
					break;
				case "Productivity":
					appstream_categories.add ("WebBrowser");
					appstream_categories.add ("Email");
					appstream_categories.add ("Office");
					break;
				case "Communication & News":
					appstream_categories.add ("Network");
					break;
				case "Education & Science":
					appstream_categories.add ("Education");
					appstream_categories.add ("Science");
					break;
				case "Games":
					appstream_categories.add ("Game");
					break;
				case "Utilities":
					appstream_categories.add ("Utility");
					break;
				case "Development":
					appstream_categories.add ("Development");
					break;
				default:
					break;
			}
			if (appstream_categories.length > 0) {
				var iter = HashTableIter<string, As.Store> (stores_table);
				unowned string remote;
				As.Store app_store;
				while (iter.next (out remote, out app_store)) {
					unowned GenericArray<As.App> apps = app_store.get_apps ();
					for (uint i = 0; i < apps.length; i++) {
						As.App app = apps[i];
						unowned GenericArray<string> categories = app.get_categories ();
						for (uint j = 0; j < categories.length; j++) {
							unowned string cat_name = categories[j];
							if (appstream_categories.find_with_equal_func (cat_name, str_equal)) {
								FlatpakPackage? pkg = get_flatpak_from_app (remote, app);
								if (pkg != null) {
									result.prepend (pkg);
								}
								break;
							}
						}
					}
				}
			}
			result.reverse ();
			return result;
		}

		public SList<FlatpakPackage> get_flatpak_updates () {
			var result = new SList<FlatpakPackage> ();
			refresh_appstream_data ();
			try {
				GenericArray<unowned Flatpak.InstalledRef> update_apps = installation.list_installed_refs_for_update ();
				for (uint i = 0; i < update_apps.length; i++) {
					unowned Flatpak.InstalledRef installed_ref = update_apps[i];
					var pkg = new FlatpakPackage ();
					initialize_installed_ref (installed_ref, ref pkg);
					As.App? app = get_installed_ref_matching_app (installed_ref);
					if (app != null) {
						initialize_app_data (app, ref pkg);
						As.Release? release = app.get_release_default ();
						if (release != null) {
							pkg.version = release.get_version ();
							result.prepend (pkg);
						} else {
							critical ("no version found for %s\n", app.get_id_filename ());
						}
					}
				}
			} catch (Error e) {
				warning (e.message);
			}
			result.reverse ();
			return result;
		}

		bool on_add_new_remote (Flatpak.TransactionRemoteReason reason, string from_id, string remote_name, string url) {
			// additional applications
			if (reason == Flatpak.TransactionRemoteReason.GENERIC_REPO) {
				do_emit_script_output ("Configuring %s as new generic remote".printf (url));
				return true;
			}
			// runtime deps always make sense
			if (reason == Flatpak.TransactionRemoteReason.RUNTIME_DEPS) {
				do_emit_script_output ("Configuring %s as new remote for deps".printf (url));
				return true;
			}
			return false;
		}

		int on_choose_remote_for_ref (string for_ref, string runtime_ref, [CCode (array_length = false, array_null_terminated = true)] string[] remotes) {
			print ("choose a provider for %s\n", runtime_ref);
			return 0;
		}

		void on_new_operation (Flatpak.TransactionOperation operation, Flatpak.TransactionProgress progress) {
			string? action = null;
			switch (operation.get_operation_type ()) {
				case Flatpak.TransactionOperationType.INSTALL:
					action =  dgettext (null, "Installing %s").printf (operation.get_ref ());
					break;
				case Flatpak.TransactionOperationType.UNINSTALL:
					action =  dgettext (null, "Removing %s").printf (operation.get_ref ());
					break;
				case Flatpak.TransactionOperationType.UPDATE:
					action =  dgettext (null, "Upgrading %s").printf (operation.get_ref ());
					break;
				default:
					break;
			}
			if (action != null) {
				do_emit_action_progress (action, progress.get_status (), 0);
			}
			progress.changed.connect (() => {
				if (progress.get_is_estimating ()) {
					return;
				}
				switch (operation.get_operation_type ()) {
					case Flatpak.TransactionOperationType.INSTALL:
						action =  dgettext (null, "Installing %s").printf (operation.get_ref ());
						break;
					case Flatpak.TransactionOperationType.UNINSTALL:
						action =  dgettext (null, "Removing %s").printf (operation.get_ref ());
						break;
					case Flatpak.TransactionOperationType.UPDATE:
						action =  dgettext (null, "Upgrading %s").printf (operation.get_ref ());
						break;
					default:
						break;
				}
				if (action != null) {
					if (progress.get_progress () == 100) {
						do_emit_script_output (progress.get_status ());
						do_emit_action_progress (action, "", 1);
					} else {
						do_emit_action_progress (action, progress.get_status (), (double) progress.get_progress () / 100);
					}
				}
			});
			progress.set_update_frequency (500);
		}

		bool on_operation_error (Flatpak.TransactionOperation operation, Error error, Flatpak.TransactionErrorDetails detail) {
			do_emit_script_output (error.message);
			return true;
		}

		void do_emit_action_progress (string action, string status, double progress) {
			context.invoke (() => {
				emit_action_progress (sender, action, status, progress);
				return false;
			});
		}

		void do_emit_script_output (string message) {
			context.invoke (() => {
				emit_script_output (sender, message);
				return false;
			});
		}

		void do_emit_error (string message, string[] details) {
			string[] details_copy = details;
			context.invoke (() => {
				emit_error (sender, message, details_copy);
				return false;
			});
		}

		bool do_get_authorization () {
			bool authorized = false;
			var loop = new MainLoop (context);
			var idle = new IdleSource ();
			idle.set_priority (Priority.DEFAULT);
			idle.set_callback (() => {
				authorized = get_authorization (sender);
				loop.quit ();
				return false;
			});
			idle.attach (context);
			loop.run ();
			return authorized;
		}

		public bool trans_run (string sender, string[] to_install, string[] to_remove, string[] to_upgrade) {
			this.sender = sender;
			cancellable.reset ();
			if (!do_get_authorization ()) {
				return false;
			}
			try {
				var transaction = new Flatpak.Transaction.for_installation (installation, cancellable);
				foreach (unowned string id in to_install) {
					string[] splitted = id.split ("/", 2);
					string remote = splitted[0];
					string name = splitted[1];
					transaction.add_install (remote, name, null);
				}
				foreach (unowned string id in to_remove) {
					string name = id.split ("/", 2)[1];
					transaction.add_uninstall (name);
				}
				foreach (unowned string id in to_upgrade) {
					string name = id.split ("/", 2)[1];
					transaction.add_update (name, null, null);
				}
				transaction.ready.connect (() => { return true; });
				transaction.add_new_remote.connect (on_add_new_remote);
				transaction.choose_remote_for_ref.connect (on_choose_remote_for_ref);
				transaction.new_operation.connect (on_new_operation);
				transaction.operation_error.connect (on_operation_error);
				return transaction.run (cancellable);
			} catch (Error e) {
				do_emit_error (dgettext (null, "Flatpak transaction failed"), {e.message});
				return false;
			}
		}

		public void trans_cancel (string sender) {
			if (sender == this.sender) {
				cancellable.cancel ();
			}
		}
	}
}

public Type register_plugin (Module module) {
	// types are registered automatically
	return typeof (Pamac.FlatPak);
}
