/*
 *  pamac-vala
 *
 *  Copyright (C) 2019 Guillaume Benoit <guillaume@manjaro.org>
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
	public class Snap: Object, SnapPlugin {
		Snapd.Client client;
		// download data
		Cancellable cancellable;
		Timer timer;
		bool emit_download;
		bool init_download;
		uint64 previous_xfered;
		uint64 download_rate;
		uint64 rates_nb;
		string current_action;
		string current_details;
		string current_pkgname;
		double current_progress;
		string current_status;

		public Snap () {
			Object ();
		}

		construct {
			client = new Snapd.Client ();
			// download data
			cancellable = new Cancellable ();
			timer = new Timer ();
		}

		bool app_name_matches_snap_name (Snapd.Snap snap, Snapd.App app) {
			return strcmp (snap.name, app.name) == 0;
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

		Snapd.App? get_primary_app (Snapd.Snap snap) {
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
			Snapd.App? primary_app = null;
			snap.get_apps ().foreach ((app) => {
				if (primary_app == null ||
					(primary_app.desktop_file == null && app.desktop_file != null) ||
					(!app_name_matches_snap_name (snap, primary_app) && app_name_matches_snap_name (snap, app))) {
					primary_app = app;
				}
			});
			return primary_app;
		}

		SnapPackage initialize_snap (Snapd.Snap snap) {
			var snap_pkg = new SnapPackage ();
			Snapd.Snap? store_snap;
			Snapd.Snap? installed_snap;
			if (snap.install_date != null) {
				installed_snap = snap;
				store_snap = get_store_snap (snap.name);
				if (store_snap.icon != null) {
					snap_pkg.icon = store_snap.icon;
				}
			} else {
				installed_snap = get_local_snap (snap.name);
				store_snap = snap;
			}
			snap_pkg.name = snap.name;
			snap_pkg.app_name = snap.title;
			snap_pkg.repo = dgettext (null, "Snap");
			snap_pkg.channel = snap.channel;
			//snap_pkg.download_size = snap.download_size;
			Snapd.App? primary_app = get_primary_app (snap);
			if (primary_app != null) {
				snap_pkg.launchable = Path.get_basename (primary_app.desktop_file);
			}
			if (installed_snap != null) {
				snap_pkg.installed_version = installed_snap.version;
				snap_pkg.installed_size = installed_snap.installed_size;
				snap_pkg.installdate = installed_snap.install_date.to_unix ();
			}
			if (store_snap != null) {
				if (store_snap.icon != null) {
					snap_pkg.icon = store_snap.icon;
				}
				snap_pkg.version = store_snap.version;
				snap_pkg.desc = store_snap.summary;
				snap_pkg.long_desc = store_snap.description;
				snap_pkg.url = store_snap.contact;
				snap_pkg.publisher = store_snap.publisher_display_name;
				snap_pkg.license = store_snap.license;
				store_snap.get_media ().foreach ((media) => {
					if (media.type == "screenshot") {
						unowned string url = media.url;
						string filename = Path.get_basename (url);
						if (!is_banner_image (filename) && !is_banner_icon_image (filename)) {
							snap_pkg.screenshots_priv.append (url);
						}
					}
				});
				store_snap.get_channels ().foreach ((channel) => {
					snap_pkg.channels_priv.append ("%s:  %s".printf (channel.name, channel.version));
				});
			} else {
				if (snap.icon != null) {
					snap_pkg.icon = snap.icon;
				}
				snap_pkg.version = snap.version;
				snap_pkg.desc = snap.summary;
				snap_pkg.long_desc = snap.description;
				snap_pkg.url = snap.contact;
				snap_pkg.publisher = snap.publisher_display_name;
				if (snap.license != null) {
					snap_pkg.license = snap.license;
				}
			}
			return snap_pkg;
		}

		public List<SnapPackage> search_snaps (string search_string) {
			string search_string_down = search_string.down ();
			var result = new List <SnapPackage> ();
			try {
				GenericArray<unowned Snapd.Snap> found = client.find_sync (Snapd.FindFlags.SCOPE_WIDE, search_string_down, null, null);
				found.foreach ((snap) => {
					if (snap.snap_type == Snapd.SnapType.APP) {
						result.append (initialize_snap (snap));
					}
				});
				global_search_string = (owned) search_string_down;
				result.sort (pkg_sort_search_by_relevance);
			} catch (Error e) {
				critical ("Search snaps: %s\n", e.message);
			}
			return (owned) result;
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
				GenericArray<unowned Snapd.Snap> founds = client.find_section_sync (Snapd.FindFlags.SCOPE_WIDE | Snapd.FindFlags.MATCH_NAME, null, name, null);
				if (founds.length == 1) {
					return founds[0];
				}
			} catch (Error e) {
				// an error is reported if not found
			}
			return null;
		}

		public List<SnapPackage> get_installed_snaps () {
			var result = new List <SnapPackage> ();
			try {
				GenericArray<unowned Snapd.Snap> found = client.get_snaps_sync (Snapd.GetSnapsFlags.NONE, null, null);
				found.foreach ((snap) => {
					if (snap.snap_type == Snapd.SnapType.APP) {
						result.append (initialize_snap (snap));
					}
				});
			} catch (Error e) {
				critical ("Get installed snaps: %s\n", e.message);
			}
			return (owned) result;
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

		public List<SnapPackage> get_category_snaps (string category) {
			var result = new List <SnapPackage> ();
			string[] snap_categories = {};
			switch (category) {
				case "Featured":
					string[] featured_pkgs = {"spotify"};
					foreach (unowned string name in featured_pkgs) {
						Snapd.Snap? found = get_local_snap (name);
						if (found == null) {
							found = get_store_snap (name);
							if (found != null) {
								result.append (initialize_snap (found));
							}
						}
					}
					break;
				case "Photo & Video":
					snap_categories = {"photo-and-video", "art-and-design"};
					break;
				case "Music & Audio":
					snap_categories = {"music-and-audio"};
					break;
				case "Productivity":
					snap_categories = {"productivity", "finance"};
					break;
				case "Communication & News":
					snap_categories = {"social", "news-and-weather", "entertainment"};
					break;
				case "Education & Science":
					snap_categories = {"education", "science"};
					break;
				case "Games":
					snap_categories = {"games"};
					break;
				case "Utilities":
					snap_categories = {"utilities", "health-and-fitness", "personalisation"};
					break;
				case "Development":
					snap_categories = {"development"};
					break;
				default:
					snap_categories = {};
					break;
			}
			if (snap_categories.length > 0) {
				foreach (unowned string snap_category in snap_categories) {
					try {
						GenericArray<unowned Snapd.Snap> found = client.find_section_sync (Snapd.FindFlags.NONE, snap_category, null, null, null);
						found.foreach ((snap) => {
							if (snap.snap_type == Snapd.SnapType.APP) {
								result.append (initialize_snap (snap));
							}
						});
					} catch (Error e) {
						critical ("Get category snaps: %s\n", e.message);
					}
				}
			}
			return (owned) result;
		}

		public bool trans_run (string[] to_install, string[] to_remove) {
			cancellable.reset ();
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

		public void trans_cancel () {
			cancellable.cancel ();
		}

		bool install (string name, string? channel = null) {
			try {
				current_pkgname = name;
				current_action = dgettext (null, "Installing %s").printf (name);
				emit_download = false;
				init_download = true;
				client.install2_sync (Snapd.InstallFlags.NONE, name, channel, null, progress_callback, cancellable);
				return true;
			} catch (Error e) {
				if (!cancellable.is_cancelled ()) {
					emit_error ("Snap install error", {e.message});
				}
			}
			return false;
		}

		bool remove (string name) {
			try {
				current_action = dgettext (null, "Removing %s").printf (name);
				client.remove_sync (name, progress_callback, cancellable);
				return true;
			} catch (Error e) {
				if (!cancellable.is_cancelled ()) {
					emit_error ("Snap remove error", {e.message});
				}
			}
			return false;
		}

		void on_emit_download (string pkgname, uint64 xfered, uint64 total) {
			var text = new StringBuilder ();
			double fraction;
			if (init_download) {
				start_downloading ();
				init_download = false;
				download_rate = 0;
				rates_nb = 0;
				current_progress = 0;
				previous_xfered = 0;
				fraction = 0;
				timer.start ();
			} else {
				if (timer.elapsed () > 0.5) {
					download_rate = ((download_rate * rates_nb) + (uint64) ((xfered - previous_xfered) / timer.elapsed ())) / (rates_nb + 1);
					rates_nb++;
				} else {
					return;
				}
				previous_xfered = xfered;
				fraction = (double) xfered / total;
				if (fraction <= 1) {
					text.append ("%s/%s  ".printf (format_size (xfered), format_size (total)));
					uint64 remaining_seconds = 0;
					if (download_rate > 0) {
						remaining_seconds = (total - xfered) / download_rate;
					}
					// display remaining time after 5s and only if more than 10s are remaining
					if (remaining_seconds > 9 && rates_nb > 9) {
						if (remaining_seconds <= 50) {
							text.append (dgettext (null, "About %u seconds remaining").printf ((uint) Math.ceilf ((float) remaining_seconds / 10) * 10));
						} else {
							uint remaining_minutes = (uint) Math.ceilf ((float) remaining_seconds / 60);
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
			emit_download_progress (dgettext (null, "Downloading %s").printf (pkgname), current_status, current_progress);
		}

		void progress_callback (Snapd.Client client, Snapd.Change change, void* deprecated) {
			int64 total = 0;
			int64 done = 0;
			change.get_tasks ().foreach ((task) => {
				if (task.status == "Doing") {
					if ("Download" in task.summary) {
						emit_download = true;
						on_emit_download (current_pkgname, task.progress_done, task.progress_total);
					} else if (task.summary != current_details) {
						current_details = task.summary;
						emit_script_output (current_details);
					}
				} else if (emit_download && "Download" in task.summary && task.status == "Done") {
					emit_download = false;
					stop_downloading ();
				} else if (task.status == "Done") {
					done += 1;
				}
				if (!emit_download) {
					total += 1;
				}
			});
			if (!emit_download) {
				emit_action_progress (current_action, "", (double) done / total);
			}
		}
	}
}

public Type register_plugin (Module module) {
	// types are registered automatically
	return typeof (Pamac.Snap);
}

string global_search_string;

int pkg_sort_search_by_relevance (Pamac.Package pkg_a, Pamac.Package pkg_b) {
	if (global_search_string != null) {
		// display exact match first
		if (pkg_a.app_name.down () == global_search_string) {
			return 0;
		}
		if (pkg_b.app_name.down () == global_search_string) {
			return 1;
		}
		if (pkg_a.name == global_search_string) {
			return 0;
		}
		if (pkg_b.name == global_search_string) {
			return 1;
		}
		if (pkg_a.name.has_prefix (global_search_string + "-")) {
			if (pkg_b.name.has_prefix (global_search_string + "-")) {
				return strcmp (pkg_a.name, pkg_b.name);
			}
			return 0;
		}
		if (pkg_b.name.has_prefix (global_search_string + "-")) {
			if (pkg_a.name.has_prefix (global_search_string + "-")) {
				return strcmp (pkg_a.name, pkg_b.name);
			}
			return 1;
		}
		if (pkg_a.app_name.has_prefix (global_search_string)) {
			if (pkg_b.app_name.has_prefix (global_search_string)) {
				return strcmp (pkg_a.app_name, pkg_b.app_name);
			}
			return 0;
		}
		if (pkg_b.app_name.has_prefix (global_search_string)) {
			if (pkg_a.app_name.has_prefix (global_search_string)) {
				return strcmp (pkg_a.app_name, pkg_b.app_name);
			}
			return 1;
		}
		if (pkg_a.app_name.contains (global_search_string)) {
			if (pkg_b.app_name.contains (global_search_string)) {
				return strcmp (pkg_a.app_name, pkg_b.app_name);
			}
			return 0;
		}
		if (pkg_b.app_name.contains (global_search_string)) {
			if (pkg_a.app_name.contains (global_search_string)) {
				return strcmp (pkg_a.app_name, pkg_b.app_name);
			}
			return 1;
		}
		if (pkg_a.name.has_prefix (global_search_string)) {
			if (pkg_b.name.has_prefix (global_search_string)) {
				return strcmp (pkg_a.name, pkg_b.name);
			}
			return 0;
		}
		if (pkg_b.name.has_prefix (global_search_string)) {
			if (pkg_a.name.has_prefix (global_search_string)) {
				return strcmp (pkg_a.name, pkg_b.name);
			}
			return 1;
		}
		if (pkg_a.name.contains (global_search_string)) {
			if (pkg_b.name.contains (global_search_string)) {
				return strcmp (pkg_a.name, pkg_b.name);
			}
			return 0;
		}
		if (pkg_b.name.contains (global_search_string)) {
			if (pkg_a.name.contains (global_search_string)) {
				return strcmp (pkg_a.name, pkg_b.name);
			}
			return 1;
		}
	}
	return strcmp (pkg_a.name, pkg_b.name);
}

