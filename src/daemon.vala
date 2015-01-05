/*
 *  pamac-vala
 *
 *  Copyright (C) 2014  Guillaume Benoit <guillaume@manjaro.org>
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

using Alpm;
using Polkit;

// i18n
const string GETTEXT_PACKAGE = "pamac";

Pamac.Daemon pamac_daemon;
MainLoop loop;

namespace Pamac {
	[DBus (name = "org.manjaro.pamac")]
	public class Daemon : Object {
		Alpm.Config alpm_config;
		public uint64 previous_percent;
		int force_refresh;
		bool emit_refreshed_signal;
		public Cond provider_cond;
		public Mutex provider_mutex;
		public int? choosen_provider;

		public signal void emit_event (uint primary_event, uint secondary_event, string[] details);
		public signal void emit_providers (string depend, string[] providers);
		public signal void emit_progress (uint progress, string pkgname, int percent, uint n_targets, uint current_target);
		public signal void emit_download (string filename, uint64 xfered, uint64 total);
		public signal void emit_totaldownload (uint64 total);
		public signal void emit_log (uint level, string msg);
		public signal void emit_refreshed (ErrorInfos error);
		public signal void emit_trans_prepared (ErrorInfos error);
		public signal void emit_trans_committed (ErrorInfos error);
		public signal void emit_generate_mirrorlist_start ();
		public signal void emit_generate_mirrorlist_data (string line);
		public signal void emit_generate_mirrorlist_finished ();

		public Daemon () {
			alpm_config = new Alpm.Config ("/etc/pacman.conf");
		}

		private void refresh_handle () {
			alpm_config.get_handle ();
			if (alpm_config.handle == null) {
				ErrorInfos err = ErrorInfos ();
				err.str = _("Failed to initialize alpm library");
				emit_trans_committed (err);
			} else {
				alpm_config.handle.eventcb = (EventCallBack) cb_event;
				alpm_config.handle.progresscb = (ProgressCallBack) cb_progress;
				alpm_config.handle.questioncb = (QuestionCallBack) cb_question;
				alpm_config.handle.dlcb = (DownloadCallBack) cb_download;
				alpm_config.handle.totaldlcb = (TotalDownloadCallBack) cb_totaldownload;
				alpm_config.handle.logcb = (LogCallBack) cb_log;
			}
			previous_percent = 0;
		}

		public void write_pamac_config (HashTable<string,Variant> new_pamac_conf, GLib.BusName sender) {
			var pamac_config = new Pamac.Config ("/etc/pamac.conf");
			try {
				Polkit.Authority authority = Polkit.Authority.get_sync (null);
				Polkit.Subject subject = Polkit.SystemBusName.new (sender);
				Polkit.AuthorizationResult result = authority.check_authorization_sync (
					subject,
					"org.manjaro.pamac.commit",
					null,
					Polkit.CheckAuthorizationFlags.ALLOW_USER_INTERACTION,
					null
				);
				if (result.get_is_authorized ()) {
					pamac_config.write (new_pamac_conf);
				}
			} catch (GLib.Error e) {
				stderr.printf ("%s\n", e.message);
			}
		}

		public void write_alpm_config (HashTable<string,Variant> new_alpm_conf, GLib.BusName sender) {
			try {
				Polkit.Authority authority = Polkit.Authority.get_sync (null);
				Polkit.Subject subject = Polkit.SystemBusName.new (sender);
				Polkit.AuthorizationResult result = authority.check_authorization_sync (
					subject,
					"org.manjaro.pamac.commit",
					null,
					Polkit.CheckAuthorizationFlags.ALLOW_USER_INTERACTION,
					null
				);
				if (result.get_is_authorized ()) {
					alpm_config.write (new_alpm_conf);
				}
			} catch (GLib.Error e) {
				stderr.printf ("%s\n", e.message);
			}
		}

		private bool process_line (IOChannel channel, IOCondition condition, string stream_name) {
			if (condition == IOCondition.HUP) {
				stdout.printf ("%s: The fd has been closed.\n", stream_name);
				return false;
			}
			try {
				string line;
				channel.read_line (out line, null, null);
				emit_generate_mirrorlist_data (line);
			} catch (IOChannelError e) {
				stdout.printf ("%s: IOChannelError: %s\n", stream_name, e.message);
				return false;
			} catch (ConvertError e) {
				stdout.printf ("%s: ConvertError: %s\n", stream_name, e.message);
				return false;
			}
			return true;
		}

		private void generate_mirrorlist () {
			emit_generate_mirrorlist_start ();

			int standard_output;
			int standard_error;
			Pid child_pid;

			try {
				Process.spawn_async_with_pipes (null,
					{"pacman-mirrors", "-g"},
					null,
					SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
					null,
					out child_pid,
					null,
					out standard_output,
					out standard_error);
			} catch (SpawnError e) {
				stdout.printf ("SpawnError: %s\n", e.message);
			}

			// stdout:
			IOChannel output = new IOChannel.unix_new (standard_output);
			output.add_watch (IOCondition.IN | IOCondition.HUP, (channel, condition) => {
				return process_line (channel, condition, "stdout");
			});

			// stderr:
			IOChannel error = new IOChannel.unix_new (standard_error);
			error.add_watch (IOCondition.IN | IOCondition.HUP, (channel, condition) => {
				return process_line (channel, condition, "stderr");
			});

			ChildWatch.add (child_pid, (pid, status) => {
				// Triggered when the child indicated by child_pid exits
				Process.close_pid (pid);
				alpm_config.reload ();
				refresh_handle ();
				emit_generate_mirrorlist_finished ();
			});
		}

		public void write_mirrors_config (HashTable<string,Variant> new_mirrors_conf, GLib.BusName sender) {
			var mirrors_config = new Alpm.MirrorsConfig ("/etc/pacman-mirrors.conf");
			try {
				Polkit.Authority authority = Polkit.Authority.get_sync (null);
				Polkit.Subject subject = Polkit.SystemBusName.new (sender);
				Polkit.AuthorizationResult result = authority.check_authorization_sync (
					subject,
					"org.manjaro.pamac.commit",
					null,
					Polkit.CheckAuthorizationFlags.ALLOW_USER_INTERACTION,
					null
				);
				if (result.get_is_authorized ()) {
					mirrors_config.write (new_mirrors_conf);
					generate_mirrorlist ();
				}
			} catch (GLib.Error e) {
				stderr.printf ("%s\n", e.message);
			}
		}

		public void set_pkgreason (string pkgname, uint reason, GLib.BusName sender) {
			try {
				Polkit.Authority authority = Polkit.Authority.get_sync (null);
				Polkit.Subject subject = Polkit.SystemBusName.new (sender);
				Polkit.AuthorizationResult result = authority.check_authorization_sync (
					subject,
					"org.manjaro.pamac.commit",
					null,
					Polkit.CheckAuthorizationFlags.ALLOW_USER_INTERACTION,
					null
				);
				if (result.get_is_authorized ()) {
					refresh_handle ();
					unowned Package? pkg = alpm_config.handle.localdb.get_pkg (pkgname);
					if (pkg != null)
						pkg.reason = (Package.Reason) reason;
				}
			} catch (GLib.Error e) {
				stderr.printf ("%s\n", e.message);
			}
		}

		private int refresh_real () {
			refresh_handle ();
			ErrorInfos err = ErrorInfos ();
			string[] details = {};
			int success = 0;
			int ret;
			foreach (var db in alpm_config.handle.syncdbs) {
				ret = db.update (force_refresh);
				if (ret >= 0) {
					success++;
				}
			}
			// We should always succeed if at least one DB was upgraded - we may possibly
			// fail later with unresolved deps, but that should be rare, and would be expected
			if (success == 0) {
				err.str = _("Failed to synchronize any databases");
				details += Alpm.strerror (alpm_config.handle.errno ());
				err.details = details;
			}
			if (emit_refreshed_signal)
				emit_refreshed (err);
			return success;
		}

		public void refresh (int force, bool emit_signal) {
			force_refresh = force;
			emit_refreshed_signal = emit_signal;
			try {
				new Thread<int>.try ("refresh thread", (ThreadFunc) refresh_real);
			} catch (GLib.Error e) {
				stderr.printf ("%s\n", e.message);
			}
		}

		public UpdatesInfos[] get_updates () {
			refresh_handle ();
			var pamac_config = new Pamac.Config ("/etc/pamac.conf");
			UpdatesInfos[] updates = {};
			updates = get_syncfirst_updates (alpm_config.handle, alpm_config.syncfirsts);
			if (updates.length != 0) {
				return updates;
			} else {
				updates = get_repos_updates (alpm_config.handle);
				if (pamac_config.enable_aur) {
					UpdatesInfos[] aur_updates = get_aur_updates (alpm_config.handle);
					foreach (var infos in aur_updates)
						updates += infos;
				}
				return updates;
			}
		}

		public ErrorInfos trans_init (TransFlag transflags) {
			refresh_handle ();
			ErrorInfos err = ErrorInfos ();
			string[] details = {};
			int ret = alpm_config.handle.trans_init (transflags);
			if (ret == -1) {
				err.str = _("Failed to init transaction");
				details += Alpm.strerror (alpm_config.handle.errno ());
				err.details = details;
			}
			return err;
		}

		public ErrorInfos trans_sysupgrade (int enable_downgrade) {
			ErrorInfos err = ErrorInfos ();
			string[] details = {};
			int ret = alpm_config.handle.trans_sysupgrade (enable_downgrade);
			if (ret == -1) {;
				err.str = _("Failed to prepare transaction");
				details += Alpm.strerror (alpm_config.handle.errno ());
				err.details = details;
			}
			return err;
		}

		public ErrorInfos trans_add_pkg (string pkgname) {
			ErrorInfos err = ErrorInfos ();
			string[] details = {};
			unowned Package? pkg = null;
			pkg =  alpm_config.handle.find_dbs_satisfier (alpm_config.handle.syncdbs, pkgname);
			//foreach (var db in alpm_config.handle.syncdbs) {
				//pkg = find_satisfier (db.pkgcache, pkgname);
				//if (pkg != null)
					//break;
			//}
			if (pkg == null)  {
				err.str = _("Failed to prepare transaction");
				details += _("target not found: %s").printf (pkgname);
				err.details = details;
				return err;
			}
			int ret = alpm_config.handle.trans_add_pkg (pkg);
			if (ret == -1) {
				Alpm.Errno errno = alpm_config.handle.errno ();
				if (errno == Errno.TRANS_DUP_TARGET || errno == Errno.PKG_IGNORED)
					// just skip duplicate or ignored targets
					return err;
				else {
					err.str = _("Failed to prepare transaction");
					details += "%s: %s".printf (pkg.name, Alpm.strerror (errno));
					err.details = details;
					return err;
				}
			}
			return err;
	}

		public ErrorInfos trans_load_pkg (string pkgpath) {
			ErrorInfos err = ErrorInfos ();
			string[] details = {};
			Package* pkg = alpm_config.handle.load_file (pkgpath, 1, alpm_config.handle.localfilesiglevel);
			if (pkg == null) {
				err.str = _("Failed to prepare transaction");
				details += "%s: %s".printf (pkgpath, Alpm.strerror (alpm_config.handle.errno ()));
				err.details = details;
				return err;
			} else {
				int ret = alpm_config.handle.trans_add_pkg (pkg);
				if (ret == -1) {
					Alpm.Errno errno = alpm_config.handle.errno ();
					if (errno == Errno.TRANS_DUP_TARGET || errno == Errno.PKG_IGNORED)
						// just skip duplicate or ignored targets
						return err;
					else {
						err.str = _("Failed to prepare transaction");
						details += "%s: %s".printf (pkg->name, Alpm.strerror (errno));
						err.details = details;
						return err;
					}
					// free the package because it will not be used
					delete pkg;
				}
			}
			return err;
		}

		public ErrorInfos trans_remove_pkg (string pkgname) {
			ErrorInfos err = ErrorInfos ();
			string[] details = {};
			unowned Package? pkg =  alpm_config.handle.localdb.get_pkg (pkgname);
			if (pkg == null) {
				err.str = _("Failed to prepare transaction");
				details += _("target not found: %s").printf (pkgname);
				err.details = details;
				return err;
			}
			int ret = alpm_config.handle.trans_remove_pkg (pkg);
			if (ret == -1) {
				err.str = _("Failed to prepare transaction");
				details += "%s: %s".printf (pkg.name, Alpm.strerror (alpm_config.handle.errno ()));
				err.details = details;
			}
			return err;
		}

		private int trans_prepare_real () {
			ErrorInfos err = ErrorInfos ();
			string[] details = {};
			Alpm.List<void*> err_data = null;
			int ret = alpm_config.handle.trans_prepare (out err_data);
			if (ret == -1) {
				Alpm.Errno errno = alpm_config.handle.errno ();
				err.str = _("Failed to prepare transaction");
				string detail = Alpm.strerror (errno);
				switch (errno) {
					case Errno.PKG_INVALID_ARCH:
						detail += ":";
						details += detail;
						foreach (void *i in err_data) {
							char *pkgname = i;
							details += _("package %s does not have a valid architecture").printf (pkgname);
							delete pkgname;
						}
						break;
					case Errno.UNSATISFIED_DEPS:
						detail += ":";
						details += detail;
						foreach (void *i in err_data) {
							DepMissing *miss = i;
							string depstring = miss->depend.compute_string ();
							details += _("%s: requires %s").printf (miss->target, depstring);
							delete miss;
						}
						break;
					case Errno.CONFLICTING_DEPS:
						detail += ":";
						details += detail;
						foreach (void *i in err_data) {
							Conflict *conflict = i;
							detail = _("%s and %s are in conflict").printf (conflict->package1, conflict->package2);
							// only print reason if it contains new information
							if (conflict->reason.mod != Depend.Mode.ANY) {
								detail += " (%s)".printf (conflict->reason.compute_string ());
							}
							details += detail;
							delete conflict;
						}
						break;
					default:
						details += detail;
						break;
				}
				err.details = details;
				trans_release ();
			} else {
				// Search for holdpkg in target list
				bool found_locked_pkg = false;
				foreach (var pkg in alpm_config.handle.trans_to_remove ()) {
					if (alpm_config.holdpkgs.find_custom (pkg.name, strcmp) != null) {
						details += _("%s needs to be removed but it is a locked package").printf (pkg.name);
						found_locked_pkg = true;
						break;
					}
				}
				if (found_locked_pkg) {
					err.str = _("Failed to prepare transaction");
					err.details = details;
					trans_release ();
				}
			}
			emit_trans_prepared (err);
			return ret;
		}

		public void trans_prepare () {
			try {
				new Thread<int>.try ("prepare thread", (ThreadFunc) trans_prepare_real);
			} catch (GLib.Error e) {
				stderr.printf ("%s\n", e.message);
			}
		}

		public void choose_provider (int provider) {
			provider_mutex.lock ();
			choosen_provider = provider;
			provider_cond.signal ();
			provider_mutex.unlock ();
		}

		public UpdatesInfos[] trans_to_add () {
			UpdatesInfos info = UpdatesInfos ();
			UpdatesInfos[] infos = {};
			foreach (var pkg in alpm_config.handle.trans_to_add ()) {
				info.name = pkg.name;
				info.version = pkg.version;
				// if pkg was load from a file, pkg.db is null
				if (pkg.db != null)
					info.db_name = pkg.db.name;
				else
					info.db_name = "";
				info.tarpath = "";
				info.download_size = pkg.download_size;
				infos += info;
			}
			return infos;
		}

		public UpdatesInfos[] trans_to_remove () {
			UpdatesInfos info = UpdatesInfos ();
			UpdatesInfos[] infos = {};
			foreach (var pkg in alpm_config.handle.trans_to_remove ()) {
				info.name = pkg.name;
				info.version = pkg.version;
				info.db_name = pkg.db.name;
				info.tarpath = "";
				info.download_size = pkg.download_size;
				infos += info;
			}
			return infos;
		}

		private int trans_commit_real () {
			ErrorInfos err = ErrorInfos ();
			string[] details = {};
			Alpm.List<void*> err_data = null;
			int ret = alpm_config.handle.trans_commit (out err_data);
			if (ret == -1) {
				Alpm.Errno errno = alpm_config.handle.errno ();
				err.str = _("Failed to commit transaction");
				string detail = Alpm.strerror (errno);
				switch (errno) {
					case Alpm.Errno.FILE_CONFLICTS:
						detail += ":";
						details += detail;
						//TransFlag flags = alpm_config.handle.trans_get_flags ();
						//if ((flags & TransFlag.FORCE) != 0) {
							//details += _("unable to %s directory-file conflicts").printf ("--force");
						//}
						foreach (void *i in err_data) {
							FileConflict *conflict = i;
							switch (conflict->type) {
								case FileConflict.Type.TARGET:
									details += _("%s exists in both %s and %s").printf (conflict->file, conflict->target, conflict->ctarget);
									break;
								case FileConflict.Type.FILESYSTEM:
									details += _("%s: %s already exists in filesystem").printf (conflict->target, conflict->file);
									break;
							}
							delete conflict;
						}
						break;
					case Alpm.Errno.PKG_INVALID:
					case Alpm.Errno.PKG_INVALID_CHECKSUM:
					case Alpm.Errno.PKG_INVALID_SIG:
					case Alpm.Errno.DLT_INVALID:
						detail += ":";
						details += detail;
						foreach (void *i in err_data) {
							char *filename = i;
							details += _("%s is invalid or corrupted").printf (filename);
							delete filename;
						}
						break;
					default:
						details += detail;
						break;
				}
				err.details = details;
			}
			trans_release ();
			emit_trans_committed (err);
			return ret;
		}

		public void trans_commit (GLib.BusName sender) {
			try {
				Polkit.Authority authority = Polkit.Authority.get_sync (null);
				Polkit.Subject subject = Polkit.SystemBusName.new (sender);
				var result = new Polkit.AuthorizationResult (false, false, null);
				authority.check_authorization.begin (
					subject,
					"org.manjaro.pamac.commit",
					null,
					Polkit.CheckAuthorizationFlags.ALLOW_USER_INTERACTION,
					null,
					(obj, res) => {
						try {
							result = authority.check_authorization.end (res);
							if (result.get_is_authorized ()) {
								new Thread<int>.try ("commit thread", (ThreadFunc) trans_commit_real);
							} else {
								ErrorInfos err = ErrorInfos ();
								err.str = _("Authentication failed");
								emit_trans_committed (err);
								trans_release ();
							}
						} catch (GLib.Error e) {
							stderr.printf ("Polkit Error: %s\n", e.message);
						}
					}
				);
			} catch (GLib.Error e) {
				stderr.printf ("Polkit Error: %s\n", e.message);
			}
		}

		public int trans_release () {
			return alpm_config.handle.trans_release ();
		}

		public void trans_cancel () {
			alpm_config.handle.trans_interrupt ();
			alpm_config.handle.trans_release ();
			refresh_handle ();
		}

		[DBus (no_reply = true)]
		public void quit () {
			GLib.File lockfile = GLib.File.new_for_path ("/var/lib/pacman/db.lck");
			if (lockfile.query_exists () == false)
				loop.quit ();
		}
	// End of Daemon Object
	}
}

private void write_log_file (string event) {
	var now = new DateTime.now_local ();
	string log = "%s %s".printf (now.format ("[%Y-%m-%d %H:%M]"), event);
	var file = GLib.File.new_for_path ("/var/log/pamac.log");
	try {
		// creating a DataOutputStream to the file
		var dos = new DataOutputStream (file.append_to (FileCreateFlags.NONE));
		// writing a short string to the stream
		dos.put_string (log);
	} catch (GLib.Error e) {
		stderr.printf("%s\n", e.message);
	}
}

private void cb_event (Event.Data data) {
	string[] details = {};
	uint secondary_type = 0;
	switch (data.type) {
		case Event.Type.PACKAGE_OPERATION_START:
			switch (data.package_operation_operation) {
				case Package.Operation.REMOVE:
					details += data.package_operation_oldpkg.name;
					details += data.package_operation_oldpkg.version;
					secondary_type = (uint) Package.Operation.REMOVE;
					break;
				case Package.Operation.INSTALL:
					details += data.package_operation_newpkg.name;
					details += data.package_operation_newpkg.version;
					secondary_type = (uint) Package.Operation.INSTALL;
					break;
				case Package.Operation.REINSTALL:
					details += data.package_operation_newpkg.name;
					details += data.package_operation_newpkg.version;
					secondary_type = (uint) Package.Operation.REINSTALL;
					break;
				case Package.Operation.UPGRADE:
					details += data.package_operation_oldpkg.name;
					details += data.package_operation_oldpkg.version;
					details += data.package_operation_newpkg.version;
					secondary_type = (uint) Package.Operation.UPGRADE;
					break;
				case Package.Operation.DOWNGRADE:
					details += data.package_operation_oldpkg.name;
					details += data.package_operation_oldpkg.version;
					details += data.package_operation_newpkg.version;
					secondary_type = (uint) Package.Operation.DOWNGRADE;
					break;
			}
			break;
		case Event.Type.PACKAGE_OPERATION_DONE:
			switch (data.package_operation_operation) {
				case Package.Operation.INSTALL:
					string log = "Installed %s (%s)\n".printf (data.package_operation_newpkg.name, data.package_operation_newpkg.version);
					write_log_file (log);
					break;
				case Package.Operation.REMOVE:
					string log = "Removed %s (%s)\n".printf (data.package_operation_oldpkg.name, data.package_operation_oldpkg.version);
					write_log_file (log);
					break;
				case Package.Operation.REINSTALL:
					string log = "Reinstalled %s (%s)\n".printf (data.package_operation_newpkg.name, data.package_operation_newpkg.version);
					write_log_file (log);
					break;
				case Package.Operation.UPGRADE:
					string log = "Upgraded %s (%s -> %s)\n".printf (data.package_operation_oldpkg.name, data.package_operation_oldpkg.version, data.package_operation_newpkg.version);
					write_log_file (log);
					break;
				case Package.Operation.DOWNGRADE:
					string log = "Downgraded %s (%s -> %s)\n".printf (data.package_operation_oldpkg.name, data.package_operation_oldpkg.version, data.package_operation_newpkg.version);
					write_log_file (log);
					break;
			}
			break;
		case Event.Type.DELTA_PATCH_START:
			details += data.delta_patch_delta.to;
			details += data.delta_patch_delta.delta;
			break;
		case Event.Type.SCRIPTLET_INFO:
			details += data.scriptlet_info_line;
			write_log_file (data.scriptlet_info_line);
			break;
		case Event.Type.PKGDOWNLOAD_START:
			details += data.pkgdownload_file;
			break;
		case Event.Type.OPTDEP_REMOVAL:
			details += data.optdep_removal_pkg.name;
			details += data.optdep_removal_optdep.compute_string ();
			break;
		case Event.Type.DATABASE_MISSING:
			details += data.database_missing_dbname;
			break;
		case Event.Type.PACNEW_CREATED:
			details += data.pacnew_created_file;
			break;
		case Event.Type.PACSAVE_CREATED:
			details += data.pacsave_created_file;
			break;
		case Event.Type.PACORIG_CREATED:
			details += data.pacorig_created_file;
			break;
		default:
			break;
	}
	pamac_daemon.emit_event ((uint) data.type, secondary_type, details);
}

private void cb_question (Question.Data data) {
	switch (data.type) {
		case Question.Type.INSTALL_IGNOREPKG:
			// Do not install package in IgnorePkg/IgnoreGroup
			data.install_ignorepkg_install = 0;
			break;
		case Question.Type.REPLACE_PKG:
			// Auto-remove conflicts in case of replaces
			data.replace_replace = 1;
			break;
		case Question.Type.CONFLICT_PKG:
			// Auto-remove conflicts
			data.conflict_remove = 1;
			break;
		case Question.Type.REMOVE_PKGS:
			// Do not upgrade packages which have unresolvable dependencies
			data.remove_pkgs_skip = 1;
			break;
		case Question.Type.SELECT_PROVIDER:
			string depend_str = data.select_provider_depend.compute_string ();
			string[] providers_str = {};
			foreach (unowned Package pkg in data.select_provider_providers) {
				providers_str += pkg.name;
			}
			pamac_daemon.provider_cond = Cond ();
			pamac_daemon.provider_mutex = Mutex ();
			pamac_daemon.choosen_provider = null;
			pamac_daemon.emit_providers (depend_str, providers_str);
			pamac_daemon.provider_mutex.lock ();
			while (pamac_daemon.choosen_provider == null) {
				pamac_daemon.provider_cond.wait (pamac_daemon.provider_mutex);
			}
			data.select_provider_use_index = pamac_daemon.choosen_provider;
			pamac_daemon.provider_mutex.unlock ();
			break;
		case Question.Type.CORRUPTED_PKG:
			// Auto-remove corrupted pkgs in cache
			data.corrupted_remove = 1;
			break;
		case Question.Type.IMPORT_KEY:
			// Do not get revoked key
			if (data.import_key_key.revoked == 1)
				data.import_key_import = 0;
			// Auto get not revoked key
			else
				data.import_key_import = 1;
			break;
		default:
			data.any_answer = 0;
			break;
	}
}

private void cb_progress (Progress progress, string pkgname, int percent, uint n_targets, uint current_target) {
	if ((uint64) percent != pamac_daemon.previous_percent) {
		pamac_daemon.previous_percent = (uint64) percent;
		pamac_daemon.emit_progress ((uint) progress, pkgname, percent, n_targets, current_target);
	}
}

private void cb_download (string filename, uint64 xfered, uint64 total) {
	if (xfered != pamac_daemon.previous_percent) {
		pamac_daemon.previous_percent = xfered;
		pamac_daemon.emit_download (filename, xfered, total);
	}
}

private void cb_totaldownload (uint64 total) {
	pamac_daemon.emit_totaldownload (total);
}

private void cb_log (LogLevel level, string fmt, va_list args) {
	LogLevel logmask = LogLevel.ERROR | LogLevel.WARNING;
	if ((level & logmask) == 0)
		return;
	string? log = null;
	log = fmt.vprintf (args);
	if (log != null)
		pamac_daemon.emit_log ((uint) level, log);
}

void on_bus_acquired (DBusConnection conn) {
	pamac_daemon = new Pamac.Daemon ();
	try {
		conn.register_object ("/org/manjaro/pamac", pamac_daemon);
	}
	catch (IOError e) {
		stderr.printf ("Could not register service\n");
	}
}

void main () {
	// i18n
	Intl.setlocale (LocaleCategory.ALL, "");
	Intl.textdomain (GETTEXT_PACKAGE);

	Bus.own_name (BusType.SYSTEM, "org.manjaro.pamac", BusNameOwnerFlags.NONE,
				on_bus_acquired,
				() => {},
				() => stderr.printf("Could not acquire name\n"));

	loop = new MainLoop ();
	loop.run ();
}
