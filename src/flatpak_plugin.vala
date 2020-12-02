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
	public class FlatpakPackageLinked : FlatpakPackage {
		// common
		Flatpak.InstalledRef? installed_ref;
		Flatpak.RemoteRef? remote_ref;
		As.App? as_app;
		Flatpak.Installation installation;
		// Package
		string? _id;
		unowned string? _version;
		unowned string? _installed_version;
		unowned string? _app_name;
		string? _long_desc;
		unowned string? _launchable;
		string? _icon;
		GenericArray<string> _screenshots;

		// Package
		public override string name { get; internal set; }
		public override string id {
			get { return _id; }
		}
		public override string version {
			get { return _version; }
			internal set { _version = value; }
		}
		public override string? installed_version {
			get { return _installed_version; }
			internal set { _installed_version = value; }
		}
		public override string? repo {
			get {
				if (installed_ref != null) {
					return installed_ref.get_origin ();
				} else if (remote_ref != null) {
					return remote_ref.remote_name;
				}
				return null;
			}
			internal set { /* not used */ }
		}
		public override string? license {
			get {
				if (as_app != null) {
					return as_app.get_project_license ();
				}
				return null;
			}
		}
		public override string? url {
			get {
				if (as_app != null) {
					return as_app.get_url_item (As.UrlKind.HOMEPAGE);
				}
				return null;
			}
		}
		public override uint64 installed_size {
			get {
				if (installed_ref != null) {
					return installed_ref.installed_size;
				} else if (remote_ref != null) {
					return remote_ref.installed_size;
				}
				return 0;
			}
		}
		public override uint64 download_size {
			get {
				if (remote_ref != null) {
					return remote_ref.download_size;
				}
				return 0;
			}
		}
		public override uint64 install_date {
			get { return 0; }
		}
		public override string? app_name {
			get {
				if (_app_name == null) {
					if (as_app != null) {
						_app_name = as_app.get_name (null);
					}
				}
				return _app_name;
			}
		}
		public override string? app_id {
			get {
				if (as_app != null) {
					return as_app.get_id ();
				}
				return null;
			}
		}
		public override string? desc {
			get {
				if (as_app != null) {
					return as_app.get_comment (null);
				}
				return null;
			}
			internal set { /* not used */ }
		}
		public override string? long_desc {
			get {
				if (_long_desc == null) {
					if (as_app != null) {
						try {
							_long_desc = As.markup_convert_simple (as_app.get_description (null));
						} catch (Error e) {
							warning (e.message);
						}
					}
				}
				return _long_desc;
			}
		}
		public override string? launchable {
			get {
				if (_launchable == null && as_app != null) {
					unowned As.Launchable? as_launchable = as_app.get_launchable_by_kind (As.LaunchableKind.DESKTOP_ID);
					if (as_launchable != null) {
						_launchable = as_launchable.get_value ();
					}
				}
				return _launchable;
			}
		}
		public override string? icon {
			get {
				if (_icon == null && as_app != null) {
					unowned GenericArray<As.Icon> icons = as_app.get_icons ();
					foreach (unowned As.Icon as_icon in icons) {
						if (as_icon.get_kind () == As.IconKind.CACHED) {
							if (as_icon.get_height () == 64) {
								try {
									GenericArray<unowned Flatpak.Remote> remotes = installation.list_remotes ();
									foreach (unowned Flatpak.Remote remote in remotes) {
										if (remote.get_disabled ()) {
											continue;
										}
										if (remote.name == repo) {
											File appstream_dir = remote.get_appstream_dir (null);
											_icon = Path.build_path ("/", appstream_dir.get_path (), "icons", "64x64", as_icon.get_name ());
											break;
										}
									}
								} catch (Error e) {
									warning (e.message);
								}
							}
						}
					}
				}
				return _icon;
			}
		}
		public override GenericArray<string> screenshots {
			get {
				if (_screenshots == null) {
					_screenshots = new GenericArray<string> ();
					if (as_app != null) {
						unowned GenericArray<As.Screenshot> as_screenshots = as_app.get_screenshots ();
						foreach (unowned As.Screenshot as_screenshot in as_screenshots) {
							unowned As.Image? as_image = as_screenshot.get_source ();
							if (as_image != null) {
								unowned string? url = as_image.get_url ();
								if (url != null) {
									_screenshots.add (url);
								}
							}
						}
					}
				}
				return _screenshots;
			}
		}

		internal FlatpakPackageLinked (Flatpak.InstalledRef? installed_ref, Flatpak.RemoteRef? remote_ref, As.App? as_app, Flatpak.Installation installation, bool is_update = false) {
			this.installed_ref = installed_ref;
			this.remote_ref = remote_ref;
			this.as_app = as_app;
			this.installation = installation;
			if (this.installed_ref != null) {
				_id = "%s/%s".printf (installed_ref.origin, installed_ref.format_ref ());
				name = installed_ref.name;
				_installed_version = installed_ref.appdata_version;
				if (_installed_version == null) {
					// use commits
					_installed_version = installed_ref.commit;
				}
				if (is_update && this.as_app != null) {
					unowned As.Release? release = as_app.get_release_default ();
					if (release != null) {
						_version = release.get_version ();
					} else {
						_version = "";
						// do not warning here about no version found
						// to not add output lines to checkupdates -q
					}
				} else {
					_version = _installed_version;
				}
			} else if (this.remote_ref != null) {
				_id = "%s/%s".printf (remote_ref.remote_name, remote_ref.format_ref ());
				name = remote_ref.name;
				if (this.as_app != null) {
					unowned As.Release? release = as_app.get_release_default ();
					if (release != null) {
						_version = release.get_version ();
					} else {
						_version = "";
						warning ("no version found for %s", as_app.get_id_filename ());
					}
				}
			}
		}
	}

	internal class FlatPak: Object, FlatpakPlugin {
		string sender;
		Flatpak.Installation installation;
		bool appstream_data_loaded;
		HashTable<string, As.Store> stores_table;
		HashTable<string, Flatpak.RemoteRef> remote_refs_table;
		HashTable<string, FlatpakPackageLinked> pkgs_cache;
		Cancellable cancellable;

		public uint64 refresh_period { get; set; }
		public MainContext context { get; set; }

		public FlatPak (uint64 refresh_period, MainContext context) {
			Object (refresh_period: refresh_period, context: context);
		}

		construct {
			cancellable = new Cancellable ();
			appstream_data_loaded = false;
			stores_table = new HashTable<string, As.Store> (str_hash, str_equal);
			remote_refs_table = new HashTable<string, Flatpak.RemoteRef> (str_hash, str_equal);
			pkgs_cache = new HashTable<string, FlatpakPackageLinked> (str_hash, str_equal);
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
				foreach (unowned Flatpak.Remote remote in remotes) {
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
				foreach (unowned Flatpak.Remote remote in remotes) {
					if (remote.get_disabled ()) {
						continue;
					}
					int64 elapsed_time = get_file_age (remote.get_appstream_timestamp (null));
					if (elapsed_time < TimeSpan.HOUR) {
						continue;
					}
					int64 elapsed_hours = elapsed_time / TimeSpan.HOUR;
					if (elapsed_hours > refresh_period) {
						message ("last %s appstream refresh is older than %lli", remote.name, refresh_period);
						message ("refreshing %s appstream data", remote.name);
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

		unowned As.App? get_installed_ref_matching_app (Flatpak.InstalledRef installed_ref) {
			unowned As.App? matching_app = null;
			var iter = HashTableIter<string, As.Store> (stores_table);
			unowned string remote;
			As.Store app_store;
			while (iter.next (out remote, out app_store)) {
				if (remote == installed_ref.origin) {
					unowned GenericArray<As.App> apps = app_store.get_apps ();
					foreach (unowned As.App app in apps) {
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

		unowned As.App? get_remote_ref_matching_app (Flatpak.RemoteRef remote_ref) {
			unowned As.App? matching_app = null;
			unowned As.Store? app_store = stores_table.lookup (remote_ref.remote_name);
			if (app_store != null) {
				unowned GenericArray<As.App> apps = app_store.get_apps ();
				foreach (unowned As.App app in apps) {
					if (app.get_id_filename () == remote_ref.name) {
						matching_app = app;
						break;
					}
				}
			}
			return matching_app;
		}

		public void get_remotes_names (ref GenericArray<unowned string> remotes_names) {
			try {
				GenericArray<unowned Flatpak.Remote> remotes = installation.list_remotes ();
				foreach (unowned Flatpak.Remote remote in remotes) {
					if (remote.get_disabled ()) {
						continue;
					}
					remotes_names.add (remote.name);
				}
			} catch (Error e) {
				warning (e.message);
			}
		}

		public void get_installed_flatpaks (ref GenericArray<unowned FlatpakPackage> pkgs) {
			try {
				lock (pkgs_cache)  {
					GenericArray<unowned Flatpak.InstalledRef> installed_apps = installation.list_installed_refs_by_kind (Flatpak.RefKind.APP);
					foreach (unowned Flatpak.InstalledRef installed_ref in installed_apps) {
						string id =  "%s/%s".printf (installed_ref.origin, installed_ref.format_ref ());
						FlatpakPackageLinked? pkg = pkgs_cache.lookup (id);
						if (pkg == null) {
							unowned As.App? app = get_installed_ref_matching_app (installed_ref);
							pkg = new FlatpakPackageLinked (installed_ref, null, app, installation);
							pkgs_cache.insert (id, pkg);
						}
						pkgs.add (pkg);
					}
				}
			} catch (Error e) {
				warning (e.message);
			}
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

		public FlatpakPackage? get_flatpak_by_app_id (string app_id) {
			FlatpakPackage? pkg = null;
			var iter = HashTableIter<string, As.Store> (stores_table);
			unowned string remote;
			As.Store app_store;
			// remove .desktop suffix
			string real_app_id = app_id.replace (".desktop", "");
			while (iter.next (out remote, out app_store)) {
				unowned GenericArray<As.App> apps = app_store.get_apps ();
				foreach (unowned As.App app in apps) {
					if (app.get_id_filename () == real_app_id) {
						pkg = get_flatpak_from_app (remote, app);
					}
				}
			}
			return pkg;
		}

		FlatpakPackageLinked? get_flatpak_from_app (string remote, As.App app) {
			FlatpakPackageLinked? pkg = null;
			lock (pkgs_cache)  {
				try {
					Flatpak.InstalledRef? installed_ref = installation.get_installed_ref (Flatpak.RefKind.APP, app.get_id (), null, app.get_branch ());
					string id =  "%s/%s".printf (installed_ref.origin, installed_ref.format_ref ());
					pkg = pkgs_cache.lookup (id);
					if (pkg == null) {
						pkg = new FlatpakPackageLinked (installed_ref, null, app, installation);
						pkgs_cache.insert (id, pkg);
					}
				} catch (Error e) {
					if (e is Flatpak.Error.NOT_INSTALLED) {
						try {
							// try with id_filename
							Flatpak.InstalledRef? installed_ref = installation.get_installed_ref (Flatpak.RefKind.APP, app.get_id_filename (), null, app.get_branch ());
							string id =  "%s/%s".printf (installed_ref.origin, installed_ref.format_ref ());
							pkg = pkgs_cache.lookup (id);
							if (pkg == null) {
								pkg = new FlatpakPackageLinked (installed_ref, null, app, installation);
								pkgs_cache.insert (id, pkg);
							}
						} catch (Error e) {
							if (e is Flatpak.Error.NOT_INSTALLED) {
								// try remotes
								string id = "%s/%s".printf (remote, app.get_id_filename ());
								pkg = pkgs_cache.lookup (id);
								if (pkg == null) {
									Flatpak.RemoteRef? remote_ref;
									try {
										// try with id_filename
										remote_ref = remote_refs_table.lookup (id);
										if (remote_ref == null) {
											remote_ref = installation.fetch_remote_ref_sync (remote, Flatpak.RefKind.APP, app.get_id_filename (), null, app.get_branch ());
										}
										if (remote_ref != null) {
											remote_refs_table.insert (id, remote_ref);
											pkg = new FlatpakPackageLinked (null, remote_ref, app, installation);
											pkgs_cache.insert (id, pkg);
										}
									} catch (Error e) {
										if (e is Flatpak.Error.REF_NOT_FOUND) {
											try {
												// retry with id
												remote_ref = installation.fetch_remote_ref_sync (remote, Flatpak.RefKind.APP, app.get_id (), null, app.get_branch ());
												if (remote_ref != null) {
													remote_refs_table.insert (id, remote_ref);
													pkg = new FlatpakPackageLinked (null, remote_ref, app, installation);
													pkgs_cache.insert (id, pkg);
												}
											} catch (Error e) {
												warning (e.message);
											}
										} else {
											warning (e.message);
										}
									}
								}
							} else {
								warning (e.message);
							}
						}
					} else {
						warning (e.message);
					}
				}
			}
			return pkg;
		}

		public FlatpakPackage? get_flatpak (string id) {
			FlatpakPackageLinked? pkg = null;
			string[] splitted = id.split ("/", 5);
			unowned string remote = splitted[0];
			//unowned string kind = splitted[1];
			unowned string name = splitted[2];
			unowned string arch = splitted[3];
			unowned string branch = splitted[4];
			string pkg_id = "%s/%s".printf (remote, name);
			lock (pkgs_cache)  {
				pkg = pkgs_cache.lookup (pkg_id);
				if (pkg != null) {
					return pkg;
				}
				try {
					Flatpak.InstalledRef? installed_ref = installation.get_installed_ref (Flatpak.RefKind.APP, name, arch, branch);
					unowned As.App? app = get_installed_ref_matching_app (installed_ref);
					pkg = new FlatpakPackageLinked (installed_ref, null, app, installation);
					pkgs_cache.insert (pkg_id, pkg);
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
								As.App? app = get_remote_ref_matching_app (remote_ref);
								pkg = new FlatpakPackageLinked (null, remote_ref, app, installation);
								pkgs_cache.insert (pkg_id, pkg);
							}
						} catch (Error e) {
							warning (e.message);
						}
					} else {
						warning (e.message);
					}
				}
			}
			return pkg;
		}

		public void search_flatpaks (string search_string, ref GenericArray<unowned FlatpakPackage> pkgs) {
			string[]? search_terms = As.utils_search_tokenize (search_string);
			if (search_terms != null) {
				var iter = HashTableIter<string, As.Store> (stores_table);
				unowned string remote;
				As.Store app_store;
				while (iter.next (out remote, out app_store)) {
					unowned GenericArray<As.App> apps = app_store.get_apps ();
					foreach (unowned As.App app in apps) {
						uint match_score = app.search_matches_all (search_terms);
						if (match_score > 0) {
							FlatpakPackage? pkg = get_flatpak_from_app (remote, app);
							if (pkg != null) {
								pkgs.add (pkg);
							}
						}
					}
				}
			}
		}

		public void search_uninstalled_flatpaks_sync (string[] search_terms, ref GenericArray<unowned FlatpakPackage> pkgs) {
			var iter = HashTableIter<string, As.Store> (stores_table);
			unowned string remote;
			As.Store app_store;
			while (iter.next (out remote, out app_store)) {
				unowned GenericArray<As.App> apps = app_store.get_apps ();
				foreach (unowned As.App app in apps) {
					uint match_score = app.search_matches_all (search_terms);
					if (match_score > 0) {
						FlatpakPackage? pkg = get_flatpak_from_app (remote, app);
						if (pkg != null && pkg.installed_version == null) {
							pkgs.add (pkg);
						}
					}
				}
			}
		}

		public void get_category_flatpaks (string category, ref GenericArray<unowned FlatpakPackage> pkgs) {
			var names_set = new GenericSet<string> (str_hash, str_equal);
			switch (category) {
				case "Featured":
					names_set.add ("com.spotify.Client");
					names_set.add ("com.valvesoftware.Steam");
					names_set.add ("com.discordapp.Discord");
					names_set.add ("com.skype.Client");
					names_set.add ("com.mojang.Minecraft");
					names_set.add ("com.slack.Slack");
					var iter = HashTableIter<string, As.Store> (stores_table);
					unowned string remote;
					As.Store app_store;
					while (iter.next (out remote, out app_store)) {
						unowned GenericArray<As.App> apps = app_store.get_apps ();
						foreach (unowned As.App app in apps) {
							if (app.get_id_filename () in names_set) {
								FlatpakPackage? pkg = get_flatpak_from_app (remote, app);
								if (pkg != null) {
									pkgs.add (pkg);
								}
							}
						}
					}
					break;
				case "Photo & Video":
					names_set.add ("Graphics");
					names_set.add ("Video");
					break;
				case "Music & Audio":
					names_set.add ("Audio");
					names_set.add ("Music");
					break;
				case "Productivity":
					names_set.add ("WebBrowser");
					names_set.add ("Email");
					names_set.add ("Office");
					break;
				case "Communication & News":
					names_set.add ("Network");
					break;
				case "Education & Science":
					names_set.add ("Education");
					names_set.add ("Science");
					break;
				case "Games":
					names_set.add ("Game");
					break;
				case "Utilities":
					names_set.add ("Utility");
					break;
				case "Development":
					names_set.add ("Development");
					break;
				default:
					break;
			}
			if (names_set.length > 0) {
				var iter = HashTableIter<string, As.Store> (stores_table);
				unowned string remote;
				As.Store app_store;
				while (iter.next (out remote, out app_store)) {
					unowned GenericArray<As.App> apps = app_store.get_apps ();
					foreach (unowned As.App app in apps) {
						unowned GenericArray<string> categories = app.get_categories ();
						foreach (unowned string cat_name in categories) {
							if (cat_name in names_set) {
								FlatpakPackage? pkg = get_flatpak_from_app (remote, app);
								if (pkg != null) {
									pkgs.add (pkg);
								}
								break;
							}
						}
					}
				}
			}
		}

		public void get_flatpak_updates (ref GenericArray<unowned FlatpakPackage> pkgs) {
			//refresh_appstream_data ();
			try {
				lock (pkgs_cache)  {
					GenericArray<unowned Flatpak.InstalledRef> update_apps = installation.list_installed_refs_for_update ();
					foreach (unowned Flatpak.InstalledRef installed_ref in update_apps) {
						if (installed_ref.kind == Flatpak.RefKind.APP) {
							string id =  "%s/%s".printf (installed_ref.origin, installed_ref.format_ref ());
							FlatpakPackageLinked? pkg = pkgs_cache.lookup (id);
							if (pkg == null) {
								unowned As.App? app = get_installed_ref_matching_app (installed_ref);
								pkg = new FlatpakPackageLinked (installed_ref, null, app, installation, true);
								pkgs_cache.insert (id, pkg);
							}
							pkgs.add (pkg);
						}
					}
				}
			} catch (Error e) {
				warning (e.message);
			}
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
			progress.set_update_frequency (100);
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
			// won't send a signal in a thread
			return get_authorization (sender);
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
