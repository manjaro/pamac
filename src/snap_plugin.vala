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
	public class SnapPackageLinked : SnapPackage {
		// common
		Snapd.Snap snap;
		Snapd.Snap? store_snap;
		Snapd.Snap? installed_snap;
		// Package
		string? _id;
		unowned string? _version;
		string? _app_id;
		string? _launchable;
		GenericArray<string> _screenshots;
		// Snap Package
		string? _channel;
		GenericArray<string> _channels;

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
			get {
				if (installed_snap != null) {
					return installed_snap.version;
				}
				return null;
			}
			internal set { /* not used */ }
		}
		public override string? repo {
			get { return dgettext (null, "Snap"); }
			internal set { /* not used */ }
		}
		public override string? url {
			get { return snap.contact; }
		}
		public override uint64 installed_size {
			get {
				if (installed_snap != null) {
					return installed_snap.installed_size;
				}
				return 0;
			}
		}
		public override uint64 download_size {
			get { return snap.download_size; }
		}
		public override uint64 install_date {
			get {
				if (installed_snap != null) {
					return installed_snap.install_date.to_unix ();
				}
				return 0;
			}
		}
		public override string? app_name { get { return snap.title; } }
		public override string? app_id { get { return _app_id; } }
		public override string? desc {
			get { return snap.summary; }
			internal set { /* not used */ }
		}
		public override string? long_desc { get { return snap.description; } }
		public override string? launchable { get { return _launchable; } }
		public override string? icon { get { return snap.icon; } }
		public override GenericArray<string> screenshots {
			get {
				if (_screenshots == null) {
					_screenshots = new GenericArray<string> ();
					if (store_snap != null) {
						unowned GenericArray<Snapd.Media> medias = store_snap.get_media ();
						foreach (unowned Snapd.Media media in medias) {
							if (media.type == "screenshot") {
								unowned string url = media.url;
								string filename = Path.get_basename (url);
								if (!is_banner_image (filename) && !is_banner_icon_image (filename)) {
									_screenshots.add (url);
								}
							}
						}
					}
				}
				return _screenshots;
			}
		}
		// Snap Package
		public override string? channel {
			get {
				if (_channel == null) {
					_channel = snap.channel.replace ("latest/", "");
				}
				return _channel;
			}
		}
		public override string? publisher { get { return snap.publisher_display_name; } }
		public override string? license { get { return snap.license; } }
		public override string? confined {
			get {
				if (snap.confinement == Snapd.Confinement.STRICT) {
					return dgettext (null, "Yes");
				} else {
					return dgettext (null, "No");
				}
			}
		}
		public override GenericArray<string> channels {
			get {
				if (_channels == null) {
					_channels = new GenericArray<string> ();
					if (store_snap != null) {
						unowned GenericArray<Snapd.Channel> channels = store_snap.get_channels ();
						foreach (unowned Snapd.Channel channel in channels) {
							_channels.add ("%s : %s".printf (channel.name.replace ("latest/", ""), channel.version));
						}
					}
				}
				return _channels;
			}
		}

		internal SnapPackageLinked (Snapd.Snap snap, Snapd.Snap? installed_snap, Snapd.Snap? store_snap) {
			this.snap = snap;
			this.store_snap = store_snap;
			this.installed_snap = installed_snap;
			name = snap.name;
			_id = snap.name;
			_version = snap.version;
			unowned Snapd.App? primary_app = Snap.get_primary_app (this.snap);
			if (primary_app != null) {
				unowned string? desktop_file = primary_app.desktop_file;
				if (desktop_file != null) {
					_launchable = Path.get_basename (desktop_file);
					_app_id = Path.get_basename (desktop_file);
				}
			} else {
				_app_id = snap.name;
			}
		}

		bool is_banner_image (string filename){
			/* Check if this screenshot was uploaded as "banner.png" or "banner.jpg".
			 * The server optionally adds a 7 character suffix onto it if it would collide with
			 * an existing name, e.g. "banner_MgEy4MI.png"
			 * See https://forum.snapcraft.io/t/improve-method-for-setting-featured-snap-banner-image-in-store/
			 */
			return Regex.match_simple ("^banner(?:_[a-zA-Z0-9]{7})?\\.(?:png|jpg)$", filename, 0, 0);
		}

		bool is_banner_icon_image (string filename) {
			/* Check if this screenshot was uploaded as "banner-icon.png" or "banner-icon.jpg".
			 * The server optionally adds a 7 character suffix onto it if it would collide with
			 * an existing name, e.g. "banner-icon_Ugn6pmj.png"
			 * See https://forum.snapcraft.io/t/improve-method-for-setting-featured-snap-banner-image-in-store/
			 */
			return Regex.match_simple ("^banner-icon(?:_[a-zA-Z0-9]{7})?\\.(?:png|jpg)$", filename, 0, 0);
		}

	}

	internal class Snap : Object, SnapPlugin {
		string sender;
		Snapd.Client client;
		HashTable<string, Snapd.Snap> store_snaps_cache;
		HashTable<string, GenericArray<unowned Snapd.Snap>> search_snaps_cache;
		HashTable<string, GenericArray<unowned Snapd.Snap>> category_snaps_cache;
		HashTable<unowned string, SnapPackageLinked> pkgs_cache;
		// download data
		Cancellable cancellable;
		Timer timer;
		bool downloading;
		GenericSet<string> download_files;
		bool init_download;
		uint64 download_total;
		uint64 previous_xfered;
		uint64 download_rate;
		uint64 rates_nb;
		string main_action;
		string current_action;
		string current_details;
		double current_progress;
		string current_status;

		public MainContext context { get; set; }

		public Snap () {
			Object ();
		}

		construct {
			client = new Snapd.Client ();
			store_snaps_cache = new HashTable<string, Snapd.Snap> (str_hash, str_equal);
			search_snaps_cache = new HashTable<string, GenericArray<unowned Snapd.Snap>> (str_hash, str_equal);
			category_snaps_cache = new HashTable<string, GenericArray<unowned Snapd.Snap>> (str_hash, str_equal);
			pkgs_cache = new HashTable<unowned string, SnapPackageLinked> (str_hash, str_equal);
			// download data
			cancellable = new Cancellable ();
			timer = new Timer ();
			downloading = false;
			download_files = new GenericSet<string> (str_hash, str_equal);
		}

		internal static bool app_name_matches_snap_name (Snapd.Snap snap, Snapd.App app) {
			return strcmp (snap.name, app.name) == 0;
		}

		internal static unowned Snapd.App? get_primary_app (Snapd.Snap snap) {
			/* Pick the "main" app from the snap.  In order of
			 * preference, we want to pick:
			 *
			 *   1. the main app, provided it has a desktop file
			 *   2. the first app with a desktop file
			 *   3. the main app
			 *   4. the first app
			 *
			 * The "main app" is one whose name matches the snap name.
			 */
			unowned Snapd.App? primary_app = null;
			unowned GenericArray<Snapd.App> apps = snap.get_apps ();
			foreach (unowned Snapd.App app in apps) {
				if (primary_app == null ||
					(primary_app.desktop_file == null && app.desktop_file != null) ||
					(!app_name_matches_snap_name (snap, primary_app) && app_name_matches_snap_name (snap, app))) {
					primary_app = app;
				}
			}
			return primary_app;
		}

		SnapPackage initialize_snap (Snapd.Snap snap) {
			SnapPackageLinked? pkg = pkgs_cache.lookup (snap.name);
			if (pkg != null) {
				return pkg;
			}
			Snapd.Snap? store_snap;
			Snapd.Snap? installed_snap;
			if (snap.install_date != null) {
				installed_snap = snap;
				store_snap = get_store_snap (snap.name);
			} else {
				installed_snap = get_local_snap (snap.name);
				store_snap = snap;
			}
			pkg = new SnapPackageLinked (snap, installed_snap, store_snap);
			pkgs_cache.insert (pkg.id, pkg); 
			return pkg;
		}

		public void search_snaps (string search_string, ref GenericArray<unowned SnapPackage> pkgs) {
			try {
				GenericArray<unowned Snapd.Snap>? found = search_snaps_cache.lookup (search_string);
				if (found == null) {
					found = client.find_sync (Snapd.FindFlags.SCOPE_WIDE, search_string, null, null);
					search_snaps_cache.insert (search_string, found);
				}
				foreach (unowned Snapd.Snap snap in found) {
					if (snap.snap_type == Snapd.SnapType.APP) {
						pkgs.add (initialize_snap (snap));
					}
				}
			} catch (Error e) {
				warning (e.message);
			}
		}

		public void search_uninstalled_snaps_sync (string search_string, ref GenericArray<unowned SnapPackage> pkgs) {
			try {
				GenericArray<unowned Snapd.Snap>? found = search_snaps_cache.lookup (search_string);
				if (found == null) {
					found = client.find_sync (Snapd.FindFlags.SCOPE_WIDE, search_string, null, null);
					search_snaps_cache.insert (search_string, found);
				}
				foreach (unowned Snapd.Snap snap in found) {
					if (snap.snap_type == Snapd.SnapType.APP && snap.install_date == null) {
						pkgs.add (initialize_snap (snap));
					}
				}
			} catch (Error e) {
				warning (e.message);
			}
		}

		public bool is_installed_snap (string name) {
			return get_local_snap (name) != null;
		}

		public SnapPackage? get_snap (string name) {
			SnapPackage? pkg = null;
			Snapd.Snap? found = get_local_snap (name);
			if (found == null) {
				found = get_store_snap (name);
			}
			if (found != null) {
				pkg = initialize_snap (found);
			}
			return pkg;
		}

		public SnapPackage? get_snap_by_app_id (string app_id) {
			SnapPackage? pkg = null;
			try {
				GenericArray<unowned Snapd.Snap> snaps = client.get_snaps_sync (Snapd.GetSnapsFlags.NONE, null, null);
				foreach (unowned Snapd.Snap snap in snaps) {
					if (snap.snap_type == Snapd.SnapType.APP) {
						Snapd.App? primary_app = get_primary_app (snap);
						if (primary_app != null) {
							unowned string? desktop_file = primary_app.desktop_file;
							if (desktop_file != null && desktop_file.has_suffix (app_id)) {
								pkg = initialize_snap (snap);
							}
						}
					}
				}
			} catch (Error e) {
				warning (e.message);
			}
			return pkg;
		}

		Snapd.Snap? get_local_snap (string name) {
			try {
				Snapd.Snap found = client.get_snap_sync (name, null);
				if (found.snap_type == Snapd.SnapType.APP) {
					return found;
				}
			} catch (Error e) {
				// an error is reported if not found
			}
			return null;
		}

		Snapd.Snap? get_store_snap (string name) {
			try {
				unowned Snapd.Snap? found = store_snaps_cache.lookup (name);
				if (found != null) {
					return found;
				}
				GenericArray<unowned Snapd.Snap> founds = client.find_sync (Snapd.FindFlags.SCOPE_WIDE | Snapd.FindFlags.MATCH_NAME, name, null, null);
				if (founds.length == 1) {
					found = founds[0];
					store_snaps_cache.insert (name, found);
					return found;
				}
			} catch (Error e) {
				// an error is reported if not found
			}
			return null;
		}

		public void get_installed_snaps (ref GenericArray<unowned SnapPackage> pkgs) {
			try {
				GenericArray<unowned Snapd.Snap> snaps = client.get_snaps_sync (Snapd.GetSnapsFlags.NONE, null, null);
				foreach (unowned Snapd.Snap snap in snaps) {
					if (snap.snap_type == Snapd.SnapType.APP) {
						pkgs.add (initialize_snap (snap));
					}
				}
			} catch (Error e) {
				warning (e.message);
			}
		}

		public string get_installed_snap_icon (string name) throws Error {
			var cached_icon = File.new_for_path ("/tmp/pamac-app-icons/%s".printf (name));
			if (!cached_icon.query_exists ()) {
				try {
					Snapd.Icon icon = client.get_icon_sync (name, null);
					var input_stream = new MemoryInputStream.from_bytes (icon.data);
					// save image in tmp
					FileOutputStream output_stream = cached_icon.append_to (FileCreateFlags.NONE);
					output_stream.splice (input_stream, OutputStreamSpliceFlags.NONE);
				} catch (Error e) {
					throw e;
				}
			}
			return cached_icon.get_path ();
		}

		public void get_category_snaps (string category, ref GenericArray<unowned SnapPackage> pkgs) {
			var snap_categories = new GenericArray<string> ();
			switch (category) {
				case "Featured":
					var featured_pkgs = new GenericArray<string> (3);
					featured_pkgs.add ("spotify");
					featured_pkgs.add ("signal-desktop");
					featured_pkgs.add ("discord");
					foreach (unowned string name in featured_pkgs) {
						Snapd.Snap? found = get_local_snap (name);
						if (found == null) {
							found = get_store_snap (name);
						}
						if (found != null) {
							pkgs.add (initialize_snap (found));
						}
					}
					break;
				case "Photo & Video":
					snap_categories.add ("photo-and-video");
					snap_categories.add ("art-and-design");
					break;
				case "Music & Audio":
					snap_categories.add ("music-and-audio");
					break;
				case "Productivity":
					snap_categories.add ("productivity");
					snap_categories.add ("finance");
					break;
				case "Communication & News":
					snap_categories.add ("social");
					snap_categories.add ("news-and-weather");
					snap_categories.add ("entertainment");
					break;
				case "Education & Science":
					snap_categories.add ("education");
					snap_categories.add ("science");
					break;
				case "Games":
					snap_categories.add ("games");
					break;
				case "Utilities":
					snap_categories.add ("utilities");
					snap_categories.add ("health-and-fitness");
					snap_categories.add ("personalisation");
					break;
				case "Development":
					snap_categories.add ("development");
					break;
				default:
					break;
			}
			if (snap_categories.length > 0) {
				foreach (unowned string snap_category in snap_categories) {
					try {
						GenericArray<unowned Snapd.Snap>? found = category_snaps_cache.lookup (snap_category);
						if (found == null) {
							found = client.find_section_sync (Snapd.FindFlags.NONE, snap_category, null, null, null);
							category_snaps_cache.insert (snap_category, found);
						}
						foreach (unowned Snapd.Snap snap in found) {
							if (snap.snap_type == Snapd.SnapType.APP) {
								pkgs.add (initialize_snap (snap));
							}
						}
					} catch (Error e) {
						warning (e.message);
					}
				}
			}
		}

		void do_start_downloading () {
			context.invoke (() => {
				start_downloading (sender);
				return false;
			});
		}

		void do_stop_downloading () {
			context.invoke (() => {
				stop_downloading (sender);
				return false;
			});
		}

		void do_emit_action_progress (string action, string status, double progress) {
			context.invoke (() => {
				emit_action_progress (sender, action, status, progress);
				return false;
			});
		}

		void do_emit_download_progress (string action, string status, double progress) {
			context.invoke (() => {
				emit_download_progress (sender, action, status, progress);
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

		public bool trans_run (string sender, string[] to_install, string[] to_remove) {
			this.sender = sender;
			cancellable.reset ();
			if (!do_get_authorization ()) {
				return false;
			}
			bool success = true;
			foreach (unowned string name in to_remove) {
				success = remove (name);
				if (cancellable.is_cancelled ()) {
					success = false;
				}
				if (!success) {
					break;
				}
			}
			if (!success) {
				return false;
			}
			foreach (unowned string name in to_install) {
				success = install (name);
				if (cancellable.is_cancelled ()) {
					success = false;
				}
				if (!success) {
					break;
				}
			}
			return success;
		}

		public void trans_cancel (string sender) {
			if (sender == this.sender) {
				cancellable.cancel ();
			}
		}

		bool install (string name, string? channel = null) {
			try {
				main_action = dgettext (null, "Installing %s").printf (name);
				init_download = true;
				client.install2_sync (Snapd.InstallFlags.NONE, name, channel, null, progress_callback, cancellable);
				return true;
			} catch (Error e) {
				if (e is Snapd.Error.NEEDS_CLASSIC) {
					try {
						// confirmation already obtained in transaction.vala
						client.install2_sync (Snapd.InstallFlags.CLASSIC, name, channel, null, progress_callback, cancellable);
						return true;
					} catch (Error e) {
						if (!cancellable.is_cancelled ()) {
							do_emit_error ("Snap install error", {e.message});
						}
					}
				} else if (!cancellable.is_cancelled ()) {
					do_emit_error ("Snap install error", {e.message});
				}
			}
			return false;
		}

		public bool switch_channel (string sender, string name, string channel) {
			this.sender = sender;
			try {
				main_action = dgettext (null, "Installing %s").printf ("%s (%s)".printf (name, channel));
				init_download = true;
				client.refresh_sync (name, channel, progress_callback, cancellable);
				return true;
			} catch (Error e) {
				if (!cancellable.is_cancelled ()) {
					do_emit_error ("Snap switch error", {e.message});
				}
			}
			return false;
		}

		bool remove (string name) {
			try {
				main_action = dgettext (null, "Removing %s").printf (name);
				client.remove_sync (name, progress_callback, cancellable);
				return true;
			} catch (Error e) {
				if (!cancellable.is_cancelled ()) {
					do_emit_error ("Snap remove error", {e.message});
				}
			}
			return false;
		}

		void emit_download (uint64 xfered, uint64 total) {
			var text = new StringBuilder ();
			double fraction;
			if (init_download) {
				do_start_downloading ();
				init_download = false;
				download_rate = 0;
				rates_nb = 0;
				current_progress = 0;
				previous_xfered = 0;
				fraction = 0;
				timer.start ();
			} else {
				if (timer.elapsed () > 0.1) {
					download_rate = ((download_rate * rates_nb) + (uint64) ((xfered - previous_xfered) / timer.elapsed ())) / (rates_nb + 1);
					rates_nb++;
				} else {
					return;
				}
				previous_xfered = xfered;
				fraction = (double) xfered / total;
				if (fraction <= 1) {
					text.append ("%s/%s  ".printf (format_size (xfered), format_size (total)));
					uint remaining_seconds = 0;
					if (download_rate > 0) {
						remaining_seconds = (uint) Math.roundf ((float) (total - xfered) / download_rate);
					}
					// display remaining time after 2s
					if (remaining_seconds > 0 && rates_nb > 19) {
						if (remaining_seconds < 60) {
							text.append (dngettext (null, "About %lu second remaining",
										"About %lu seconds remaining", remaining_seconds).printf (remaining_seconds));
						} else {
							uint remaining_minutes = (uint) Math.roundf ((float) remaining_seconds / 60);
							text.append (dngettext (null, "About %lu minute remaining",
										"About %lu minutes remaining", remaining_minutes).printf (remaining_minutes));
						}
					}
				} else {
					text.append ("%s".printf (format_size (xfered)));
				}
				timer.start ();
			}
			if (fraction != current_progress) {
				current_progress = fraction;
			}
			if (text.str != current_status) {
				current_status = text.str;
			}
			do_emit_download_progress (current_action, current_status, current_progress);
		}

		void progress_callback (Snapd.Client client, Snapd.Change change, void* deprecated) {
			uint total = 0;
			uint done = 0;
			uint64 download_progress = 0;
			unowned GenericArray<Snapd.Task> tasks = change.get_tasks ();
			foreach (unowned Snapd.Task task in tasks) {
				if ("Download" in task.summary) {
					if (task.status == "Doing") {
						// at the beginning task.progress_total = 1 because the total download size is unknonwn
						if (task.progress_total > 1 ) {
							string pkgname = task.summary.split ("\"", 3)[1];
							if (!download_files.contains (pkgname)) {
								current_action = dgettext (null, "Download of %s started").printf (pkgname);
								download_files.add ((owned) pkgname);
								download_total += task.progress_total;
							}
							downloading = true;
							download_progress += task.progress_done;
							emit_download (download_progress, download_total);
						}
					} else if (task.status == "Done") {
						string pkgname = task.summary.split ("\"", 3)[1];
						if (download_files.contains (pkgname)) {
							current_action = dgettext (null, "Download of %s finished").printf (pkgname);
							download_files.remove (pkgname);
							download_progress += task.progress_done;
							emit_download (download_progress, download_total);
						}
					}
				} else if (task.status == "Done") {
					done += 1;
				} else if (task.status == "Doing" && task.summary != current_details) {
					current_details = task.summary;
					do_emit_script_output (current_details);
				}
				total += 1;
			}
			if (downloading) {
				if (download_files.length == 0) {
					downloading = false;
					download_total = 0;
					do_stop_downloading ();
				}
			} else {
				do_emit_action_progress (main_action, "", (double) done / total);
			}
		}
	}
}

public Type register_plugin (Module module) {
	// types are registered automatically
	return typeof (Pamac.Snap);
}
