/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2018 Guillaume Benoit <guillaume@manjaro.org>
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
	public class Transaction: Object {
		enum Type {
			INSTALL = (1 << 0),
			REMOVE = (1 << 1),
			UPDATE = (1 << 2),
			BUILD = (1 << 3)
		}
		TransactionInterface transaction_interface;
		// run transaction data
		string current_action;
		string current_status;
		double current_progress;
		string current_filename;
		bool sysupgrade_after_trans;
		bool no_confirm_commit;
		bool enable_downgrade;
		bool sysupgrading;
		string[] to_install_first;
		string[] temporary_ignorepkgs;
		string[] overwrite_files;
		// building data
		Queue<string> to_build_queue;
		string[] aur_pkgs_to_install;
		bool building;
		Cancellable build_cancellable;
		// download data
		Timer timer;
		uint64 total_download;
		uint64 already_downloaded;
		uint64 previous_xfered;
		uint64 download_rate;
		uint64 rates_nb;

		// transaction options
		public Database database { get; construct set; }
		public int flags { get; set; } //Alpm.TransFlag

		public signal void emit_action (string action);
		public signal void emit_action_progress (string action, string status, double progress);
		public signal void emit_hook_progress (string action, string details, string status, double progress);
		public signal void emit_script_output (string message);
		public signal void emit_warning (string message);
		public signal void emit_error (string message, string[] details);
		public signal void start_downloading ();
		public signal void stop_downloading ();
		public signal void start_building ();
		public signal void stop_building ();
		public signal void important_details_outpout (bool must_show);
		public signal void downloading_updates_finished ();
		public signal void refresh_finished (bool success);
		public signal void finished (bool success);
		public signal void sysupgrade_finished (bool success);
		public signal void set_pkgreason_finished ();
		public signal void write_pamac_config_finished (bool recurse, uint64 refresh_period, bool no_update_hide_icon,
														bool enable_aur, string aur_build_dir, bool check_aur_updates,
														bool download_updates);
		public signal void write_alpm_config_finished (bool checkspace);
		public signal void start_generating_mirrors_list ();
		public signal void generate_mirrors_list_finished ();

		public Transaction (Database database) {
			Object (database: database);
		}

		construct {
			if (Posix.geteuid () == 0) {
				// we are root
				transaction_interface = new TransactionInterfaceRoot ();
			} else {
				// use dbus daemon
				transaction_interface = new TransactionInterfaceDaemon (database.config);
			}
			// transaction options
			flags = 0;
			enable_downgrade = false;
			// run transaction data
			current_action = "";
			current_status = "";
			current_filename = "";
			sysupgrade_after_trans = false;
			no_confirm_commit = false;
			sysupgrading = false;
			to_install_first = {};
			temporary_ignorepkgs = {};
			overwrite_files = {};
			// building data
			to_build_queue = new Queue<string> ();
			build_cancellable = new Cancellable ();
			building = false;
			// download data
			timer = new Timer ();
		}

		// destruction
		~Transaction () {
			transaction_interface.quit ();
		}

		protected virtual bool ask_confirmation (TransactionSummary summary) {
			// no confirm
			return true;
		}

		protected virtual int choose_provider (string depend, string[] providers) {
			// choose first provider
			return 0;
		}

		ErrorInfos get_current_error () {
			return transaction_interface.get_current_error ();
		}

		public bool get_lock () {
			return transaction_interface.get_lock ();
		}

		public bool unlock () {
			return transaction_interface.unlock ();
		}

		public async bool check_authorization () {
			SourceFunc callback = check_authorization.callback;
			bool authorized = false;
			ulong handler_id = transaction_interface.get_authorization_finished.connect ((authorized_) => {
				authorized = authorized_;
				Idle.add ((owned) callback);
			});
			transaction_interface.start_get_authorization ();
			yield;
			transaction_interface.disconnect (handler_id);
			return authorized;
		}

		public void start_write_pamac_config (HashTable<string,Variant> new_pamac_conf) {
			transaction_interface.write_pamac_config_finished.connect (on_write_pamac_config_finished);
			transaction_interface.start_write_pamac_config (new_pamac_conf);
		}

		public void start_write_alpm_config (HashTable<string,Variant> new_alpm_conf) {
			transaction_interface.write_alpm_config_finished.connect (on_write_alpm_config_finished);
			transaction_interface.start_write_alpm_config (new_alpm_conf);
		}

		public void start_generate_mirrors_list (string country) {
			emit_action (dgettext (null, "Refreshing mirrors list") + "...");
			important_details_outpout (false);
			start_generating_mirrors_list ();
			transaction_interface.generate_mirrors_list_data.connect (on_generate_mirrors_list_data);
			transaction_interface.generate_mirrors_list_finished.connect (on_generate_mirrors_list_finished);
			transaction_interface.start_generate_mirrors_list (country);
		}

		public void clean_cache (uint64 keep_nb, bool only_uninstalled) {
			transaction_interface.clean_cache (keep_nb, only_uninstalled);
		}

		public void start_set_pkgreason (string pkgname, uint reason) {
			transaction_interface.set_pkgreason_finished.connect (on_set_pkgreason_finished);
			transaction_interface.start_set_pkgreason (pkgname, reason);
		}

		public void start_refresh (bool force) {
			// check autorization to send start_downloading signal after that
			check_authorization.begin ((obj, res) => {
				bool authorized = check_authorization.end (res);
				if (authorized) {
					emit_action (dgettext (null, "Synchronizing package databases") + "...");
					connecting_signals ();
					transaction_interface.refresh_finished.connect (on_refresh_finished);
					transaction_interface.start_refresh (force);
					start_downloading ();
				} else {
					on_refresh_finished (false);
				}
			});
		}

		public void start_downloading_updates () {
			transaction_interface.downloading_updates_finished.connect (on_downloading_updates_finished);
			transaction_interface.start_downloading_updates ();
		}

		void on_downloading_updates_finished () {
			transaction_interface.downloading_updates_finished.disconnect (on_downloading_updates_finished);
			downloading_updates_finished ();
		}

		void start_get_updates_for_sysupgrade () {
			transaction_interface.get_updates_finished.connect (on_get_updates_for_sysupgrade_finished);
			transaction_interface.start_get_updates_for_sysupgrade (database.config.check_aur_updates);
		}

		void sysupgrade_real (string[] to_build) {
			connecting_signals ();
			// this will respond with trans_prepare_finished signal
			transaction_interface.start_sysupgrade_prepare (enable_downgrade, temporary_ignorepkgs, to_build, overwrite_files);
		}

		public void start_sysupgrade (bool enable_downgrade, string[] temporary_ignorepkgs, string[] overwrite_files) {
			this.enable_downgrade = enable_downgrade;
			this.temporary_ignorepkgs = temporary_ignorepkgs;
			this.overwrite_files = overwrite_files;
			sysupgrading = true;
			emit_action (dgettext (null, "Starting full system upgrade") + "...");
			start_get_updates_for_sysupgrade ();
		}

		void on_get_updates_for_sysupgrade_finished (UpdatesStruct updates_struct) {
			transaction_interface.get_updates_finished.disconnect (on_get_updates_for_sysupgrade_finished);
			if (updates_struct.syncfirst_repos_updates.length != 0) {
				to_install_first = {};
				foreach (unowned PackageStruct infos in updates_struct.syncfirst_repos_updates) {
					to_install_first += infos.name;
				}
			}
			string[] to_build = {};
			foreach (unowned AURPackageStruct infos in updates_struct.aur_updates) {
				if (!(infos.name in temporary_ignorepkgs)) {
					to_build += infos.name;
				}
			}
			// to_install_first will be read by start_commit
			sysupgrade_real (to_build);
		}

		void start_trans_prepare (string[] to_install, string[] to_remove, string[] to_load, string[] to_build) {
			transaction_interface.start_trans_prepare (flags, to_install, to_remove, to_load, to_build, overwrite_files);
		}

		public void start (string[] to_install, string[] to_remove, string[] to_load, string[] to_build, string[] overwrite_files) {
			this.overwrite_files = overwrite_files;
			emit_action (dgettext (null, "Preparing") + "...");
			connecting_signals ();
			start_trans_prepare (to_install, to_remove, to_load, to_build);
		}

		void start_commit () {
			if (to_install_first.length > 0) {
				release ();
				to_build_queue.clear ();
				no_confirm_commit = true;
				sysupgrade_after_trans = true;
				start_trans_prepare (to_install_first, {}, {}, {});
				to_install_first = {};
			} else {
				transaction_interface.start_trans_commit ();
			}
		}

		public virtual async int run_cmd_line (string[] args, string working_directory, Cancellable cancellable) {
			int status = 1;
			var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
			launcher.set_cwd (working_directory);
			launcher.set_environ (Environ.get ());
			try {
				Subprocess process = launcher.spawnv (args);
				var dis = new DataInputStream (process.get_stdout_pipe ());
				string? line;
				while ((line = yield dis.read_line_async (Priority.DEFAULT, cancellable)) != null) {
					emit_script_output (line);
				}
				try {
					yield process.wait_async (cancellable);
					if (process.get_if_exited ()) {
						status = process.get_exit_status ();
					}
				} catch (Error e) {
					// cancelled
					process.send_signal (Posix.Signal.INT);
					process.send_signal (Posix.Signal.KILL);
				}
			} catch (Error e) {
				stderr.printf ("Error: %s\n", e.message);
			}
			return status;
		}

		async void build_next_aur_package () {
			string pkgname = to_build_queue.pop_head ();
			emit_action (dgettext (null, "Building %s").printf (pkgname) + "...");
			build_cancellable.reset ();
			important_details_outpout (false);
			string [] built_pkgs = {};
			int status = 1;
			string builddir;
			if (database.config.aur_build_dir == "/tmp") {
				builddir = "/tmp/pamac-build-%s".printf (Environment.get_user_name ());
			} else {
				builddir = database.config.aur_build_dir;
			}
			status = yield run_cmd_line ({"mkdir", "-p", builddir}, "/", build_cancellable);
			if (status == 0) {
				status = yield run_cmd_line ({"rm", "-rf", pkgname}, builddir, build_cancellable);
				if (!build_cancellable.is_cancelled ()) {
					if (status == 0) {
						building = true;
						start_building ();
						status = yield run_cmd_line ({"git", "clone", "https://aur.archlinux.org/%s.git".printf (pkgname)}, builddir, build_cancellable);
						if (status == 0) {
							string pkgdir = "%s/%s".printf (builddir, pkgname);
							status = yield run_cmd_line ({"makepkg", "-cf"}, pkgdir, build_cancellable);
							building = false;
							if (status == 0) {
								// get built pkgs path
								var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE);
								launcher.set_cwd (pkgdir);
								try {
									Subprocess process = launcher.spawnv ({"makepkg", "--packagelist"});
									yield process.wait_async (null);
									if (process.get_if_exited ()) {
										status = process.get_exit_status ();
									}
									if (status == 0) {
										var dis = new DataInputStream (process.get_stdout_pipe ());
										string? line;
										// Read lines until end of file (null) is reached
										while ((line = dis.read_line ()) != null) {
											var file = GLib.File.new_for_path (line);
											string filename = file.get_basename ();
											string name_version_release = filename.slice (0, filename.last_index_of_char ('-'));
											string name_version = name_version_release.slice (0, name_version_release.last_index_of_char ('-'));
											string name = name_version.slice (0, name_version.last_index_of_char ('-'));
											if (name in aur_pkgs_to_install) {
												if (!(line in built_pkgs)) {
													built_pkgs += line;
												}
											}
										}
									}
								} catch (Error e) {
									stderr.printf ("Error: %s\n", e.message);
									status = 1;
								}
							}
						}
						stop_building ();
					}
				} else {
					status = 1;
				}
			}
			building = false;
			if (status == 0 && built_pkgs.length > 0) {
				no_confirm_commit = true;
				emit_script_output ("");
				start_trans_prepare ({}, {}, built_pkgs, {});
			} else {
				important_details_outpout (true);
				to_build_queue.clear ();
				finish_transaction (false);
			}
		}

		public void cancel () {
			if (building) {
				build_cancellable.cancel ();
			} else {
				transaction_interface.trans_cancel ();
			}
			emit_script_output ("");
			emit_action (dgettext (null, "Transaction cancelled") + ".");
			emit_script_output ("");
		}

		public void release () {
			transaction_interface.trans_release ();
		}

		void on_emit_event (uint primary_event, uint secondary_event, string[] details) {
			switch (primary_event) {
				case 1: //Alpm.Event.Type.CHECKDEPS_START
					emit_action (dgettext (null, "Checking dependencies") + "...");
					break;
				case 3: //Alpm.Event.Type.FILECONFLICTS_START
					current_action = dgettext (null, "Checking file conflicts") + "...";
					break;
				case 5: //Alpm.Event.Type.RESOLVEDEPS_START
					emit_action (dgettext (null, "Resolving dependencies") + "...");
					break;
				case 7: //Alpm.Event.Type.INTERCONFLICTS_START
					emit_action (dgettext (null, "Checking inter-conflicts") + "...");
					break;
				case 11: //Alpm.Event.Type.PACKAGE_OPERATION_START
					switch (secondary_event) {
						// special case handle differently
						case 1: //Alpm.Package.Operation.INSTALL
							current_filename = details[0];
							current_action = dgettext (null, "Installing %s").printf ("%s (%s)".printf (details[0], details[1])) + "...";
							break;
						case 2: //Alpm.Package.Operation.UPGRADE
							current_filename = details[0];
							current_action = dgettext (null, "Upgrading %s").printf ("%s (%s -> %s)".printf (details[0], details[1], details[2])) + "...";
							break;
						case 3: //Alpm.Package.Operation.REINSTALL
							current_filename = details[0];
							current_action = dgettext (null, "Reinstalling %s").printf ("%s (%s)".printf (details[0], details[1])) + "...";
							break;
						case 4: //Alpm.Package.Operation.DOWNGRADE
							current_filename = details[0];
							current_action = dgettext (null, "Downgrading %s").printf ("%s (%s -> %s)".printf (details[0], details[1], details[2])) + "...";
							break;
						case 5: //Alpm.Package.Operation.REMOVE
							current_filename = details[0];
							current_action = dgettext (null, "Removing %s").printf ("%s (%s)".printf (details[0], details[1])) + "...";
							break;
					}
					break;
				case 13: //Alpm.Event.Type.INTEGRITY_START
					current_action = dgettext (null, "Checking integrity") + "...";
					break;
				case 15: //Alpm.Event.Type.LOAD_START
					current_action = dgettext (null, "Loading packages files") + "...";
					break;
				case 17: //Alpm.Event.Type.DELTA_INTEGRITY_START
					emit_action (dgettext (null, "Checking delta integrity") + "...");
					break;
				case 19: //Alpm.Event.Type.DELTA_PATCHES_START
					emit_action (dgettext (null, "Applying deltas") + "...");
					break;
				case 21: //Alpm.Event.Type.DELTA_PATCH_START
					emit_script_output (dgettext (null, "Generating %s with %s").printf (details[0], details[1]) + "...");
					break;
				case 22: //Alpm.Event.Type.DELTA_PATCH_DONE
					emit_script_output (dgettext (null, "Generation succeeded") + ".");
					break;
				case 23: //Alpm.Event.Type.DELTA_PATCH_FAILED
					emit_script_output (dgettext (null, "Generation failed") + ".");
					break;
				case 24: //Alpm.Event.Type.SCRIPTLET_INFO
					// hooks output are also emitted as SCRIPTLET_INFO
					if (current_filename != "") {
						emit_action (dgettext (null, "Configuring %s").printf (current_filename) + "...");
						current_filename = "";
					}
					emit_script_output (details[0].replace ("\n", ""));
					important_details_outpout (false);
					break;
				case 25: //Alpm.Event.Type.RETRIEVE_START
					start_downloading ();
					emit_action (dgettext (null, "Downloading") + "...");
					break;
				case 26: //Alpm.Event.Type.RETRIEVE_DONE
				case 27: //Alpm.Event.Type.RETRIEVE_FAILED
					stop_downloading ();
					break;
				case 28: //Alpm.Event.Type.PKGDOWNLOAD_START
					// special case handle differently
					string name_version_release = details[0].slice (0, details[0].last_index_of_char ('-'));
					string name_version = name_version_release.slice (0, name_version_release.last_index_of_char ('-'));
					string name = name_version.slice (0, name_version.last_index_of_char ('-'));
					string version_release = details[0].replace (name + "-", "").replace (".pkg.tar.xz", "");
					current_action = dgettext (null, "Downloading %s").printf ("%s (%s)".printf (name, version_release)) + "...";
					break;
				case 31: //Alpm.Event.Type.DISKSPACE_START
					current_action = dgettext (null, "Checking available disk space") + "...";
					break;
				case 33: //Alpm.Event.Type.OPTDEP_REMOVAL
					emit_warning (dgettext (null, "%s optionally requires %s").printf (details[0], details[1]));
					break;
				case 34: //Alpm.Event.Type.DATABASE_MISSING
					emit_script_output (dgettext (null, "Database file for %s does not exist").printf (details[0]) + ".");
					break;
				case 35: //Alpm.Event.Type.KEYRING_START
					current_action = dgettext (null, "Checking keyring") + "...";
					break;
				case 37: //Alpm.Event.Type.KEY_DOWNLOAD_START
					emit_action (dgettext (null, "Downloading required keys") + "...");
					break;
				case 39: //Alpm.Event.Type.PACNEW_CREATED
					emit_script_output (dgettext (null, "%s installed as %s.pacnew").printf (details[0], details[0])+ ".");
					break;
				case 40: //Alpm.Event.Type.PACSAVE_CREATED
					emit_script_output (dgettext (null, "%s installed as %s.pacsave").printf (details[0], details[0])+ ".");
					break;
				case 41: //Alpm.Event.Type.HOOK_START
					switch (secondary_event) {
						case 1: //Alpm.HookWhen.PRE_TRANSACTION
							current_action = dgettext (null, "Running pre-transaction hooks") + "...";
							break;
						case 2: //Alpm.HookWhen.POST_TRANSACTION
							current_filename = "";
							current_action = dgettext (null, "Running post-transaction hooks") + "...";
							break;
						default:
							break;
					}
					break;
				case 43: // Alpm.Event.Type.HOOK_RUN_START
					double progress = (double) int.parse (details[2]) / int.parse (details[3]);
					string status = "%s/%s".printf (details[2], details[3]);
					bool changed = false;
					if (progress != current_progress) {
						current_progress = progress;
						changed = true;
					}
					if (status != current_status) {
						current_status = status;
						changed = true;
					}
					if (changed) {
						if (details[1] != "") {
							emit_hook_progress (current_action, details[1], current_status, current_progress);
						} else {
							emit_hook_progress (current_action, details[0], current_status, current_progress);
						}
					}
					break;
				default:
					break;
			}
		}

		void on_emit_providers (string depend, string[] providers) {
			int index = choose_provider (depend, providers);
			transaction_interface.choose_provider (index);
		}

		void on_emit_progress (uint progress, string pkgname, uint percent, uint n_targets, uint current_target) {
			double fraction;
			switch (progress) {
				case 0: //Alpm.Progress.ADD_START
				case 1: //Alpm.Progress.UPGRADE_START
				case 2: //Alpm.Progress.DOWNGRADE_START
				case 3: //Alpm.Progress.REINSTALL_START
				case 4: //Alpm.Progress.REMOVE_START
					fraction = ((double) (current_target - 1) / n_targets) + ((double) percent / (100 * n_targets));
					break;
				case 5: //Alpm.Progress.CONFLICTS_START
				case 6: //Alpm.Progress.DISKSPACE_START
				case 7: //Alpm.Progress.INTEGRITY_START
				case 8: //Alpm.Progress.LOAD_START
				case 9: //Alpm.Progress.KEYRING_START
				default:
					fraction = (double) percent / 100;
					break;
			}
			string status = "%lu/%lu".printf (current_target, n_targets);
			bool changed = false;
			if (fraction != current_progress) {
				current_progress = fraction;
				changed = true;
			}
			if (status != current_status) {
				current_status = status;
				changed = true;
			}
			if (changed) {
				if (current_action != "") {
					emit_action_progress (current_action, current_status, current_progress);
				}
			}
		}

		void on_emit_download (string filename, uint64 xfered, uint64 total) {
			var text = new StringBuilder ();
			double fraction;
			if (total_download > 0) {
				if (xfered == 0) {
					// start download pkg is handled by Alpm.Event.Type.PKGDOWNLOAD_START
					previous_xfered = 0;
					fraction = current_progress;
					text.append (current_status);
					timer.start ();
				} else {
					if (timer.elapsed () > 0.1) {
						download_rate = ((download_rate * rates_nb) + (uint64) ((xfered - previous_xfered) / timer.elapsed ())) / (rates_nb + 1);
						rates_nb++;
					}
					previous_xfered = xfered;
					uint64 downloaded_total = xfered + already_downloaded;
					fraction = (double) downloaded_total / total_download;
					if (fraction <= 1) {
						text.append ("%s/%s  ".printf (format_size (xfered + already_downloaded), format_size (total_download)));
						uint64 remaining_seconds = 0;
						if (download_rate > 0) {
							remaining_seconds = (total_download - downloaded_total) / download_rate;
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
						text.append ("%s".printf (format_size (xfered + already_downloaded)));
					}
					if (xfered == total) {
						current_filename = "";
						already_downloaded += total;
					} else {
						timer.start ();
					}
				}
			} else {
				if (xfered == 0) {
					previous_xfered = 0;
					download_rate = 0;
					rates_nb = 0;
					fraction = 0;
					timer.start ();
					if (filename.has_suffix (".db") || filename.has_suffix (".files")) {
						current_action = dgettext (null, "Refreshing %s").printf (filename) + "...";
					}
				} else if (xfered == total) {
					timer.stop ();
					fraction = 1;
					current_filename = "";
				} else {
					if (timer.elapsed () > 0.1) {
						download_rate = ((download_rate * rates_nb) + (uint64) ((xfered - previous_xfered) / timer.elapsed ())) / (rates_nb + 1);
						rates_nb++;
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
					// reinitialize timer
					timer.start ();
				}
			}
			if (fraction != current_progress) {
				current_progress = fraction;
			}
			if (text.str != current_status) {
				current_status = text.str;
			}
			emit_action_progress (current_action, current_status, current_progress);
		}

		void on_emit_totaldownload (uint64 total) {
			download_rate = 0;
			rates_nb = 0;
			current_progress = 0;
			current_status = "";
			total_download = total;
			//  this is emitted at the end of the total download 
			// with the value 0 so stop our timer
			if (total == 0) {
				timer.stop ();
			}
		}

		void on_emit_log (uint level, string msg) {
			// msg ends with \n
			string? line = null;
			if (level == 1) { //Alpm.LogLevel.ERROR
				if (current_filename != "") {
					line = dgettext (null, "Error") + ": " + current_filename + ": " + msg;
				} else {
					line = dgettext (null, "Error") + ": " + msg;
				}
				important_details_outpout (false);
				emit_error (line.replace ("\n", ""), {});
			} else if (level == (1 << 1)) { //Alpm.LogLevel.WARNING
				// warnings when no_confirm_commit should already have been sent
				if (no_confirm_commit) {
					return;
				}
				// do not show warning when manjaro-system remove db.lck
				if (current_filename != "manjaro-system") {
					if (current_filename != "") {
						line = dgettext (null, "Warning") + ": " + current_filename + ": " + msg;
					} else {
						line = dgettext (null, "Warning") + ": " + msg;
					}
					emit_warning (line.replace ("\n", ""));
				}
			}
		}

		void handle_error (ErrorInfos error) {
			if (error.message != "") {
				emit_error (error.message, error.details);
			}
			finish_transaction (false);
		}

		void finish_transaction (bool success) {
			disconnecting_signals ();
			database.refresh ();
			if (sysupgrading) {
				sysupgrade_finished (success);
				sysupgrading = false;
			} else {
				finished (success);
			}
		}

		void on_refresh_finished (bool success) {
			stop_downloading ();
			if (!success) {
				var error = get_current_error ();
				if (error.message != "") {
					emit_error (error.message, error.details);
				}
			}
			current_filename = "";
			disconnecting_signals ();
			transaction_interface.refresh_finished.disconnect (on_refresh_finished);
			database.refresh ();
			refresh_finished (success);
		}

		void on_trans_prepare_finished (bool success) {
			if (success) {
				var summary_struct = transaction_interface.get_transaction_summary ();
				Type type = 0;
				if ((summary_struct.to_install.length
					+ summary_struct.to_downgrade.length
					+ summary_struct.to_reinstall.length) > 0) {
					type |= Type.INSTALL;
				}
				if (summary_struct.to_remove.length > 0) {
					type |= Type.REMOVE;
				}
				if (summary_struct.to_upgrade.length > 0) {
					type |= Type.UPDATE;
				}
				if (summary_struct.to_build.length > 0) {
					type |= Type.BUILD;
					// populate build queue
					foreach (unowned string name in summary_struct.aur_pkgbases_to_build) {
						to_build_queue.push_tail (name);
					}
					aur_pkgs_to_install = {};
					foreach (unowned AURPackageStruct infos in summary_struct.to_build) {
						aur_pkgs_to_install += infos.name;
					}
				}
				if (no_confirm_commit) {
					no_confirm_commit = false;
					start_commit ();
				} else if (type != 0) {
					var summary = new TransactionSummary (summary_struct);
					if (ask_confirmation (summary)) {
						if (type == Type.BUILD) {
							// there only AUR packages to build
							release ();
							on_trans_commit_finished (true);
						} else {
							start_commit ();
						}
					} else {
						emit_action (dgettext (null, "Transaction cancelled") + ".");
						release ();
						to_build_queue.clear ();
						sysupgrade_after_trans = false;
						finish_transaction (false);
					}
				} else {
					//var err = ErrorInfos ();
					//err.message = dgettext (null, "Nothing to do") + "\n";
					emit_action (dgettext (null, "Nothing to do") + ".");
					release ();
					finish_transaction (true);
					//handle_error (err);
				}
			} else {
				handle_error (get_current_error ());
			}
		}

		void on_trans_commit_finished (bool success) {
			if (success) {
				if (to_build_queue.get_length () != 0) {
					emit_script_output ("");
					check_authorization.begin ((obj, res) => {
						bool authorized = check_authorization.end (res);
						if (authorized) {
							build_next_aur_package.begin ();
						} else {
							to_build_queue.clear ();
							on_trans_commit_finished (false);
						}
					});
				} else {
					if (sysupgrade_after_trans) {
						sysupgrade_after_trans = false;
						no_confirm_commit = true;
						disconnecting_signals ();
						start_sysupgrade (enable_downgrade, temporary_ignorepkgs, {});
					} else {
						emit_action (dgettext (null, "Transaction successfully finished") + ".");
						finish_transaction (true);
					}
				}
			} else {
				to_build_queue.clear ();
				handle_error (get_current_error ());
			}
			total_download = 0;
			already_downloaded = 0;
			current_filename = "";
		}

		void on_set_pkgreason_finished () {
			transaction_interface.set_pkgreason_finished.disconnect (on_set_pkgreason_finished);
			database.refresh ();
			set_pkgreason_finished ();
		}

		void on_write_pamac_config_finished (bool recurse, uint64 refresh_period, bool no_update_hide_icon,
											bool enable_aur, string aur_build_dir, bool check_aur_updates,
											bool download_updates) {
			transaction_interface.write_pamac_config_finished.disconnect (on_write_pamac_config_finished);
			database.config.reload ();
			write_pamac_config_finished (recurse, refresh_period, no_update_hide_icon,
										enable_aur, aur_build_dir, check_aur_updates,
										download_updates);
		}

		void on_write_alpm_config_finished (bool checkspace) {
			transaction_interface.write_alpm_config_finished.disconnect (on_write_alpm_config_finished);
			database.refresh ();
			write_alpm_config_finished (checkspace);
		}

		void on_generate_mirrors_list_data (string line) {
			emit_script_output (line);
		}

		void on_generate_mirrors_list_finished () {
			transaction_interface.generate_mirrors_list_data.disconnect (on_generate_mirrors_list_data);
			transaction_interface.generate_mirrors_list_finished.disconnect (on_generate_mirrors_list_finished);
			generate_mirrors_list_finished ();
		}

		void connecting_signals () {
			transaction_interface.emit_event.connect (on_emit_event);
			transaction_interface.emit_providers.connect (on_emit_providers);
			transaction_interface.emit_progress.connect (on_emit_progress);
			transaction_interface.emit_download.connect (on_emit_download);
			transaction_interface.emit_totaldownload.connect (on_emit_totaldownload);
			transaction_interface.emit_log.connect (on_emit_log);
			transaction_interface.trans_prepare_finished.connect (on_trans_prepare_finished);
			transaction_interface.trans_commit_finished.connect (on_trans_commit_finished);
		}

		void disconnecting_signals () {
			transaction_interface.emit_event.disconnect (on_emit_event);
			transaction_interface.emit_providers.disconnect (on_emit_providers);
			transaction_interface.emit_progress.disconnect (on_emit_progress);
			transaction_interface.emit_download.disconnect (on_emit_download);
			transaction_interface.emit_totaldownload.disconnect (on_emit_totaldownload);
			transaction_interface.emit_log.disconnect (on_emit_log);
			transaction_interface.trans_prepare_finished.disconnect (on_trans_prepare_finished);
			transaction_interface.trans_commit_finished.disconnect (on_trans_commit_finished);
		}
	}
}
