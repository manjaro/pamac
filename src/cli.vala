/*
 *  pamac-vala
 *
 *  Copyright (C) 2018 Guillaume Benoit <guillaume@manjaro.org>
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
	[DBus (name = "org.manjaro.pamac.user")]
	interface UserDaemon : Object {
		public abstract AlpmPackage get_installed_pkg (string pkgname) throws Error;
		public abstract AlpmPackage[] get_installed_pkgs_sync () throws Error;
		public abstract AlpmPackage[] get_foreign_pkgs_sync () throws Error;
		public abstract AlpmPackage[] get_orphans_sync () throws Error;
		public abstract AlpmPackage find_installed_satisfier (string depstring) throws Error;
		public abstract AlpmPackage get_sync_pkg (string pkgname) throws Error;
		public abstract AlpmPackage find_sync_satisfier (string depstring) throws Error;
		public abstract AlpmPackage[] search_pkgs_sync (string search_string) throws Error;
		public abstract async AURPackage[] search_in_aur (string search_string) throws Error;
		public abstract string[] get_repos_names () throws Error;
		public abstract AlpmPackage[] get_repo_pkgs_sync (string repo) throws Error;
		public abstract string[] get_groups_names () throws Error;
		public abstract AlpmPackage[] get_group_pkgs_sync (string groupname) throws Error;
		public abstract AlpmPackageDetails get_pkg_details (string pkgname, string app_name) throws Error;
		public abstract string[] get_pkg_files (string pkgname) throws Error;
		public abstract HashTable<string,Variant> search_files (string[] files) throws Error;
		public abstract async AURPackageDetails get_aur_details (string pkgname) throws Error;
		public abstract void start_get_updates (bool check_aur_updates, bool refresh_files_dbs) throws Error;
		[DBus (no_reply = true)]
		public abstract void quit () throws Error;
		public signal void get_updates_finished (Updates updates);
	}
	[DBus (name = "org.manjaro.pamac.system")]
	interface SystemDaemon : Object {
		public abstract void set_environment_variables (HashTable<string,string> variables) throws Error;
		public abstract ErrorInfos get_current_error () throws Error;
		public abstract bool get_lock () throws Error;
		public abstract bool unlock () throws Error;
		public abstract void start_get_authorization () throws Error;
		public abstract void clean_cache (uint64 keep_nb, bool only_uninstalled) throws Error;
		public abstract void start_set_pkgreason (string pkgname, uint reason) throws Error;
		public abstract void start_refresh (bool force) throws Error;
		public abstract void start_sysupgrade_prepare (bool enable_downgrade, string[] temporary_ignorepkgs, string[] to_build, string[] overwrite_files) throws Error;
		public abstract void start_trans_prepare (int transflags, string[] to_install, string[] to_remove, string[] to_load, string[] to_build, string[] overwrite_files) throws Error;
		public abstract void choose_provider (int provider) throws Error;
		public abstract TransactionSummary get_transaction_summary () throws Error;
		public abstract void start_trans_commit () throws Error;
		public abstract void trans_release () throws Error;
		public abstract void trans_cancel () throws Error;
		public abstract void start_get_updates (bool check_aur_updates) throws Error;
		[DBus (no_reply = true)]
		public abstract void quit () throws Error;
		public signal void get_updates_finished (Updates updates);
		public signal void emit_event (uint primary_event, uint secondary_event, string[] details);
		public signal void emit_providers (string depend, string[] providers);
		public signal void emit_progress (uint progress, string pkgname, uint percent, uint n_targets, uint current_target);
		public signal void emit_download (string filename, uint64 xfered, uint64 total);
		public signal void emit_totaldownload (uint64 total);
		public signal void emit_log (uint level, string msg);
		public signal void set_pkgreason_finished ();
		public signal void refresh_finished (bool success);
		public signal void trans_prepare_finished (bool success);
		public signal void trans_commit_finished (bool success);
		public signal void get_authorization_finished (bool authorized);
	}

	class Cli: GLib.Application {
		enum TransType {
			STANDARD = (1 << 0),
			UPDATE = (1 << 1),
			BUILD = (1 << 2)
		}
		public ApplicationCommandLine cmd;
		UserDaemon user_daemon;
		SystemDaemon system_daemon;
		Pamac.Config pamac_config;
		int transflags;
		string[] to_install;
		string[] to_remove;
		string[] to_load;
		string[] to_build;
		uint64 total_download;
		uint64 already_downloaded;
		string previous_textbar;
		float previous_percent;
		string previous_filename;
		string current_action;
		string previous_action;
		bool enable_aur;
		bool force_refresh;
		bool enable_downgrade;
		bool sysupgrade_after_trans;
		bool no_confirm_commit;
		bool building;
		bool asking_user_input;
		uint64 previous_xfered;
		uint64 download_rate;
		uint64 rates_nb;
		Timer timer;
		string aur_build_dir;
		string[] temporary_ignorepkgs;
		string[] overwrite_files;
		Queue<string> to_build_queue;
		string[] aur_pkgs_to_install;
		string[] to_install_first;
		Cancellable build_cancellable;
		Subprocess pkttyagent;

		public Cli () {
			application_id = "org.manjaro.pamac.cli";
			flags = ApplicationFlags.HANDLES_COMMAND_LINE;
			pamac_config = new Pamac.Config ("/etc/pamac.conf");
			transflags = 0;
			to_install = {};
			to_remove = {};
			to_load = {};
			to_build = {};
			// progress data
			previous_textbar = "";
			previous_filename = "";
			previous_action = "";
			enable_aur = false;
			force_refresh = false;
			enable_downgrade = false;
			sysupgrade_after_trans = false;
			no_confirm_commit = false;
			building = false;
			asking_user_input = false;
			timer = new Timer ();
			aur_build_dir = pamac_config.aur_build_dir;
			temporary_ignorepkgs = {};
			overwrite_files = {};
			to_build_queue = new Queue<string> ();
			build_cancellable = new Cancellable ();
			try {
				user_daemon = Bus.get_proxy_sync (BusType.SESSION, "org.manjaro.pamac.user", "/org/manjaro/pamac/user");
			} catch (Error e) {
				print_error (e.message);
			}
			// watch CTRl + C
			Unix.signal_add (Posix.Signal.INT, trans_cancel);
		}

		public override void startup () {
			// i18n
			Intl.textdomain ("pamac");
			Intl.setlocale (LocaleCategory.ALL, "");
			base.startup ();
		}

		public override int command_line (ApplicationCommandLine cmd) {
			this.cmd = cmd;
			string[] args = cmd.get_arguments ();
			if (args.length == 1) {
				display_help ();
				return cmd.get_exit_status ();
			}
			if (args[1] == "--help" || args[1] == "-h") {
				if (args.length > 2) {
					if (args[2] == "search") {
						display_search_help ();
					} else if (args[2] == "info") {
						display_info_help ();
					} else if (args[2] == "list") {
						display_list_help ();
					} else if (args[2] == "build") {
						display_build_help ();
					} else if (args[2] == "install") {
						display_install_help ();
					} else if (args[2] == "reinstall") {
						display_reinstall_help ();
					} else if (args[2] == "remove") {
						display_remove_help ();
					} else if (args[2] == "checkupdates") {
						display_checkupdates_help ();
					} else if (args[2] == "upgrade" || args[2] == "update") {
						display_upgrade_help ();
					} else {
						display_help ();
					}
				} else {
					display_help ();
				}
			} else if (args[1] == "--version") {
				display_version ();
			} else if (args[1] == "search") {
				if (args.length > 2) {
					if (args[2] == "--help" || args[2] == "-h") {
						display_search_help ();
					} else if (args[2] == "--aur" || args[2] == "-a") {
						search_in_aur (concatenate_strings (args[3:args.length]));
					} else if (args[2] == "--files" || args[2] == "-f") {
						search_files (args[3:args.length]);
					} else {
						search_pkgs (concatenate_strings (args[2:args.length]));
					}
				} else {
					display_search_help ();
				}
			} else if (args[1] == "info") {
				if (args.length > 2) {
					if (args[2] == "--help" || args[2] == "-h") {
						display_info_help ();
					} else if (args[2] == "--aur" || args[2] == "-a") {
						display_aur_infos(args[3:args.length]);
					} else {
						display_pkg_infos (args[2:args.length]);
					}
				} else {
					display_info_help ();
				}
			} else if (args[1] == "list") {
				if (args.length > 2) {
					if (args[2] == "--help" || args[2] == "-h") {
						display_list_help ();
					} else if (args[2] == "--installed" || args[2] == "-i") {
						list_installed ();
					} else if (args[2] == "--orphans" || args[2] == "-o") {
						list_orphans ();
					} else if (args[2] == "--foreign" || args[2] == "-m") {
						list_foreign ();
					} else if (args[2] == "--groups" || args[2] == "-g") {
						if (args.length > 3) {
							list_groups (args[3:args.length]);
						} else {
							list_groups ({});
						}
					} else if (args[2] == "--repos" || args[2] == "-r") {
						if (args.length > 3) {
							list_repos (args[3:args.length]);
						} else {
							list_repos ({});
						}
					} else if (args[2] == "--files" || args[2] == "-f") {
						if (args.length > 3) {
							list_files (args[3:args.length]);
						} else {
							display_list_help ();
						}
					} else {
						display_list_help ();
					}
				} else {
					list_installed ();
				}
			
			} else if (args[1] == "build") {
				if (Posix.geteuid () == 0) {
					// can't build as root
					// display makepkg error and exit
					try {
						var process = new Subprocess.newv ({"makepkg"}, SubprocessFlags.NONE);
						process.wait ();
					} catch (Error e) {
						print_error (e.message);
					}
					cmd.set_exit_status (1);
					return cmd.get_exit_status ();
				}
				if (args.length > 2) {
					if (args[2] == "--help" || args[2] == "-h") {
						display_build_help ();
					} else if (args[2] == "--builddir") {
						aur_build_dir = args[3];
						build_pkgs (args[4:args.length]);
					} else {
						build_pkgs (args[2:args.length]);
					}
				} else {
					display_build_help ();
				}
			} else if (args[1] == "install") {
				if (args.length > 2) {
					string[] targets = {};
					int i = 2;
					while (i < args.length) {
						unowned string arg = args[i];
						if (arg == "--overwrite") {
							foreach (unowned string name in args[i + 1].split(",")) {
								overwrite_files += name;
							}
							i++;
						} else {
							targets += arg;
						}
						i++;
					}
					if (args[2] == "--help" || args[2] == "-h") {
						display_install_help ();
					} else {
						install_pkgs (targets);
					}
				} else {
					display_install_help ();
				}
			} else if (args[1] == "reinstall") {
				if (args.length > 2) {
					if (args[2] == "--help" || args[2] == "-h") {
						display_reinstall_help ();
					} else {
						reinstall_pkgs (args[2:args.length]);
					}
				} else {
					display_reinstall_help ();
				}
			} else if (args[1] == "remove") {
				if (args.length > 2) {
					if (args[2] == "--help" || args[2] == "-h") {
						display_remove_help ();
					} else if (args[2] == "--orphans" || args[2] == "-o") {
						if (args.length > 3) {
							remove_pkgs (args[3:args.length], true);
						} else {
							remove_orphans ();
						}
					} else {
						remove_pkgs (args[2:args.length]);
					}
				} else {
					display_remove_help ();
				}
			} else if (args[1] == "checkupdates") {
				if (args.length == 2) {
					checkupdates ();
				} else if (args.length == 3) {
					if (args[2] == "--help" || args[2] == "-h") {
						display_checkupdates_help ();
					} else if (args[2] == "--aur" || args[2] == "-a") {
						enable_aur = true;
						checkupdates ();
					} else {
						display_checkupdates_help ();
					}
				} else {
					display_checkupdates_help ();
				}
			} else if (args[1] == "update" || args[1] == "upgrade") {
				bool error = false;
				int i = 2;
				while (i < args.length) {
					unowned string arg = args[i];
					if (arg == "--help" || arg == "-h") {
						display_upgrade_help ();
						error = true;
						break;
					} else if (arg == "--aur"|| arg == "-a") {
						enable_aur = true;
					} else if (arg == "--builddir") {
						aur_build_dir = args[i+1];
						i++;
					} else if (arg == "--force-refresh") {
						force_refresh = true;
					} else if (arg == "--enable-downgrade") {
						enable_downgrade = true;
					} else if (arg == "--ignore") {
						foreach (unowned string name in args[i + 1].split(",")) {
							temporary_ignorepkgs += name;
						}
						i++;
					} else if (arg == "--overwrite") {
						foreach (unowned string name in args[i + 1].split(",")) {
							overwrite_files += name;
						}
						i++;
					} else {
						display_upgrade_help ();
						error = true;
						break;
					}
					i++;
				}
				if (!error) {
					start_refresh ();
				}
			} else {
				display_help ();
			}
			return cmd.get_exit_status ();
		}

		public override void shutdown () {
			base.shutdown ();
			try {
				user_daemon.quit ();
				if (system_daemon != null) {
					system_daemon.quit ();
					pkttyagent.force_exit ();
				}
			} catch (Error e) {
				print_error (e.message);
			}
		}

		bool trans_cancel () {
			if (building) {
				build_cancellable.cancel ();
			} else if (asking_user_input) {
				try {
					system_daemon.trans_release ();
				} catch (Error e) {
					print_error (e.message);
				}
			} else {
				try {
					system_daemon.trans_cancel ();
				} catch (Error e) {
					print_error (e.message);
				}
			}
			stdout.printf ("\n%s.\n", dgettext (null, "Transaction cancelled"));
			this.release ();
			cmd.set_exit_status (1);
			return false;
		}

		void connecting_system_daemon () {
			if (system_daemon == null) {
				try {
					system_daemon = Bus.get_proxy_sync (BusType.SYSTEM, "org.manjaro.pamac.system", "/org/manjaro/pamac/system");
					// Set environment variables
					system_daemon.set_environment_variables (pamac_config.environment_variables);
					system_daemon.emit_event.connect (on_emit_event);
					system_daemon.emit_providers.connect (on_emit_providers);
					system_daemon.emit_progress.connect (on_emit_progress);
					system_daemon.emit_download.connect (on_emit_download);
					system_daemon.emit_totaldownload.connect (on_emit_totaldownload);
					system_daemon.emit_log.connect (on_emit_log);
					system_daemon.trans_prepare_finished.connect (on_trans_prepare_finished);
					system_daemon.trans_commit_finished.connect (on_trans_commit_finished);
					// Use tty polkit authentication agent
					pkttyagent = new Subprocess.newv ({"pkttyagent"}, SubprocessFlags.NONE);
				} catch (Error e) {
					print_error (e.message);
				}
			}
		}

		int get_term_width () {
			int width = 80;
			Linux.winsize win;
			if (Linux.ioctl (Posix.STDOUT_FILENO, Linux.Termios.TIOCGWINSZ, out win) == 0) {
				width = win.ws_col;
			}
			return width;
		}

		string concatenate_strings (string[] list) {
			var str_builder = new StringBuilder ();
			foreach (unowned string str in list) {
				if (str_builder.len > 0) {
					str_builder.append (" ");
				}
				str_builder.append (str);
			}
			return str_builder.str;
		}

		string[] split_string (string str, int margin, int width = 0) {
			int term_width = get_term_width ();
			if (width == 0) {
				width = term_width;
			}
			if (width > term_width) {
				width = term_width;
			}
			int str_length = str.length;
			int available_width = width - margin;
			if (available_width >= str_length) {
				return {str};
			}
			int remain_length = str_length;
			int offset = 0;
			string[] splitted = {};
			while (remain_length >= available_width) {
				string remain_string = str.substring (offset, remain_length);
				string cutted_string = remain_string.substring (0, available_width);
				int cut_length = available_width;
				// cut at word
				int i = cutted_string.last_index_of_char (' ');
				if (i != -1) {
					cut_length = i;
					cutted_string = remain_string.substring (0, i);
				}
				splitted += cutted_string;
				offset += cut_length + 1;
				remain_length -= cut_length + 1;
			}
			if (remain_length > 0) {
				splitted += str.substring (offset, remain_length);
			}
			return splitted;
		}

		void print_aligned (string str1, string str2, int width) {
			var str_builder = new StringBuilder ();
			str_builder.append (str1);
			int diff = width - str1.char_count ();
			if (diff > 0) {
				while (diff > 0) {
					str_builder.append (" ");
					diff--;
				}
			}
			str_builder.append (str2);
			stdout.printf ("%s\n", str_builder.str);
		}

		void print_progress (string action, string state, bool new_line) {
			var str_builder = new StringBuilder ();
			str_builder.append (action);
			int width = get_term_width () - action.char_count () - 1;
			if (new_line) {
				stdout.printf ("%s %*s\n", action, width, state);
			} else {
				stdout.printf ("%s %*s\r", action, width, state);
			}
			stdout.flush ();
		}

		void print_error (string msg, string[] details = {}) {
			if (details.length > 0) {
				if (details.length == 1) {
					stdout.printf ("%s: %s: %s\n", dgettext (null, "Error"), msg, details[0]);
				} else {
					stdout.printf ("%s: %s:\n", dgettext (null, "Error"), msg);
					foreach (unowned string detail in details) {
						stdout.printf ("%s\n", detail);
					}
				}
			} else {
				stdout.printf ("%s: %s\n", dgettext (null, "Error"), msg);
			}
			cmd.set_exit_status (1);
		}

		void display_version () {
			stdout.printf ("Pamac %s\n", VERSION);
		}

		void display_help () {
			string[] actions = {"--version",
								"--help,-h",
								"checkupdates",
								"search",
								"info",
								"list",
								"install",
								"reinstall",
								"build",
								"remove",
								"update,upgrade"};
			string[] options_actions = {"checkupdates",
										"search",
										"info",
										"list",
										"install",
										"reinstall",
										"build",
										"remove",
										"update,upgrade"};
			string[] targets_actions = {"search",
										"info",
										"list",
										"install",
										"reinstall",
										"build",
										"remove",
										"update,upgrade"};
			stdout.printf (dgettext (null, "Available actions") + ":\n");
			foreach (unowned string action in actions) {
				stdout.printf ("  pamac %-14s".printf (action));
				if (action == "--help,-h") {
					stdout.printf (" [%s]".printf (dgettext (null,  "action")));
				}
				if (action in options_actions) {
					stdout.printf (" [%s]".printf (dgettext (null,  "options")));
				}
				if (action in targets_actions) {
					stdout.printf (" <%s>".printf (dgettext (null,  "package(s)")));
				}
				stdout.printf ("\n");
			}
		}

		void display_search_help () {
			stdout.printf (dgettext (null, "Search for packages or files, multiple search terms can be specified"));
			stdout.printf ("\n\n");
			stdout.printf ("pamac search [%s] <%s>".printf (dgettext (null, "options"), "%s,%s".printf (dgettext (null, "package(s)"), dgettext (null, "file(s)"))));
			stdout.printf ("\n\n");
			stdout.printf (dgettext (null, "options") + ":\n");
			int max_length = 15;
			string[] cuts = split_string ("search in AUR instead of repositories", max_length + 2);
			print_aligned ("  -a, --aur", ": %s".printf (cuts[0]), max_length);
			int i = 1;
			while (i < cuts.length) {
				print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
				i++;
			}
			cuts = split_string ("search for packages which own the given filenames (filenames can be partial)", max_length + 2);
			print_aligned ("  -f, --files", ": %s".printf (cuts[0]), max_length);
			i = 1;
			while (i < cuts.length) {
				print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
				i++;
			}
		}

		void display_info_help () {
			stdout.printf (dgettext (null, "Display package details, multiple packages can be specified"));
			stdout.printf ("\n\n");
			stdout.printf ("pamac info [%s] <%s>".printf (dgettext (null, "options"), dgettext (null, "package(s)")));
			stdout.printf ("\n\n");
			stdout.printf (dgettext (null, "options") + ":\n");
			int max_length = 12;
			string[] cuts = split_string ("search in AUR instead of repositories", max_length + 2);
			print_aligned ("  -a, --aur", ": %s".printf (cuts[0]), max_length);
			int i = 1;
			while (i < cuts.length) {
				print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
				i++;
			}
		}

		void display_list_help () {
			stdout.printf (dgettext (null, "List packages, groups, repositories or files"));
			stdout.printf ("\n\n");
			stdout.printf ("pamac list [%s]".printf (dgettext (null, "options")));
			stdout.printf ("\n\n");
			stdout.printf (dgettext (null, "options") + ":\n");
			int max_length = 30;
			string[] cuts = split_string ("list installed packages", max_length + 2);
			print_aligned ("  -i, --installed", ": %s".printf (cuts[0]), max_length);
			int i = 1;
			while (i < cuts.length) {
				print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
				i++;
			}
			cuts = split_string ("list packages that were installed as dependencies but are no longer required by any installed package", max_length + 2);
			print_aligned ("  -o, --orphans", ": %s".printf (cuts[0]), max_length);
			i = 1;
			while (i < cuts.length) {
				print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
				i++;
			}
			cuts = split_string ("list packages that were not found in the repositories", max_length + 2);
			print_aligned ("  -m, --foreign", ": %s".printf (cuts[0]), max_length);
			i = 1;
			while (i < cuts.length) {
				print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
				i++;
			}
			cuts = split_string ("list all packages that are members of the given groups, if no group is given list all groups", max_length + 2);
			print_aligned ("  %s [%s]".printf ("-g, --groups", dgettext (null, "group(s)")), ": %s".printf (cuts[0]), max_length);
			i = 1;
			while (i < cuts.length) {
				print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
				i++;
			}
			cuts = split_string ("list all packages available in the given repos, if no repo is given list all repos", max_length + 2);
			print_aligned ("  %s [%s]".printf ("-r, --repos", dgettext (null, "repo(s)")), ": %s".printf (cuts[0]), max_length);
			i = 1;
			while (i < cuts.length) {
				print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
				i++;
			}
			cuts = split_string ("list files owned by the given packages", max_length + 2);
			print_aligned ("  %s [%s]".printf ("-f, --files", dgettext (null, "file(s)")), ": %s".printf (cuts[0]), max_length);
			i = 1;
			while (i < cuts.length) {
				print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
				i++;
			}
		}

		void display_build_help () {
			stdout.printf (dgettext (null, "Build packages from AUR and install them with their dependencies"));
			stdout.printf ("\n\n");
			stdout.printf ("pamac build [%s] <%s>".printf (dgettext (null, "options"), dgettext (null, "package(s)")));
			stdout.printf ("\n\n");
			stdout.printf (dgettext (null, "options") + ":\n");
			int max_length = 25;
			string[] cuts = split_string ("build directory, if no directory is given the one specified in pamac.conf file is used", max_length + 2);
			print_aligned ("  %s <%s>".printf ("--builddir", dgettext (null, "dir")), ": %s".printf (cuts[0]), max_length);
			int i = 1;
			while (i < cuts.length) {
				print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
				i++;
			}
		}

		void display_install_help () {
			stdout.printf (dgettext (null, "Install packages from repositories, path or url"));
			stdout.printf ("\n\n");
			stdout.printf ("pamac install [%s] <%s>".printf (dgettext (null, "options"), "%s,%s".printf (dgettext (null, "package(s)"), dgettext (null, "group(s)"))));
			stdout.printf ("\n\n");
			stdout.printf (dgettext (null, "options") + ":\n");
			int max_length = 25;
			string[] cuts = split_string ("overwrite conflicting files, multiple patterns can be specified by separating them with a comma", max_length + 2);
			print_aligned ("  %s <%s>".printf ("--overwrite", dgettext (null, "glob")), ": %s".printf (cuts[0]), max_length);
			int i = 1;
			while (i < cuts.length) {
				print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
				i++;
			}
		}

		void display_reinstall_help () {
			stdout.printf (dgettext (null, "Reinstall packages"));
			stdout.printf ("\n\n");
			stdout.printf ("pamac reinstall <%s>".printf ("%s,%s".printf (dgettext (null, "package(s)"), dgettext (null, "group(s)"))));
			stdout.printf ("\n\n");
		}

		void display_remove_help () {
			stdout.printf (dgettext (null, "Remove packages"));
			stdout.printf ("\n\n");
			stdout.printf ("pamac remove [%s] [%s]".printf (dgettext (null, "options"), "%s,%s".printf (dgettext (null, "package(s)"), dgettext (null, "group(s)"))));
			stdout.printf ("\n\n");
			stdout.printf (dgettext (null, "options") + ":\n");
			int max_length = 15;
			string[] cuts = split_string ("remove dependencies that are not required by other packages, if this option is used without package name remove all orphans", max_length + 2);
			print_aligned ("-o, --orphans", ": %s".printf (cuts[0]), max_length);
			int i = 1;
			while (i < cuts.length) {
				print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
				i++;
			}
		}

		void display_checkupdates_help () {
			stdout.printf (dgettext (null, "Safely check for updates without modifiying the databases"));
			stdout.printf ("\n\n");
			stdout.printf ("pamac checkupdates [%s]".printf (dgettext (null, "options")));
			stdout.printf ("\n\n");
			stdout.printf (dgettext (null, "options") + ":\n");
			int max_length = 12;
			string[] cuts = split_string ("also check updates in AUR", max_length + 2);
			print_aligned ("  -a, --aur", ": %s".printf (cuts[0]), max_length);
			int i = 1;
			while (i < cuts.length) {
				print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
				i++;
			}
		}

		void display_upgrade_help () {
			stdout.printf (dgettext (null, "Upgrade your system"));
			stdout.printf ("\n\n");
			stdout.printf ("pamac upgrade,update [%s]".printf (dgettext (null, "options")));
			stdout.printf ("\n\n");
			stdout.printf (dgettext (null, "options") + ":\n");
			int max_length = 30;
			string[] cuts = split_string ("also upgrade packages installed from AUR", max_length + 2);
			print_aligned ("  -a, --aur", ": %s".printf (cuts[0]), max_length);
			int i = 1;
			while (i < cuts.length) {
				print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
				i++;
			}
			cuts = split_string ("build directory (use with --aur), if no directory is given the one specified in pamac.conf file is used", max_length + 2);
			print_aligned ("  %s <%s>".printf ("--builddir", dgettext (null, "dir")), ": %s".printf (cuts[0]), max_length);
			i = 1;
			while (i < cuts.length) {
				print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
				i++;
			}
			cuts = split_string ("force the refresh of the databases", max_length + 2);
			print_aligned ("  --force-refresh", ": %s".printf (cuts[0]), max_length);
			i = 1;
			while (i < cuts.length) {
				print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
				i++;
			}
			cuts = split_string ("enable package downgrades", max_length + 2);
			print_aligned ("  --enable-downgrade", ": %s".printf (cuts[0]), max_length);
			i = 1;
			while (i < cuts.length) {
				print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
				i++;
			}
			cuts = split_string ("ignore a package upgrade, multiple packages can be specified by separating them with a comma", max_length + 2);
			print_aligned ("  %s [%s]".printf ("--ignore", dgettext (null, "package(s)")), ": %s".printf (cuts[0]), max_length);
			i = 1;
			while (i < cuts.length) {
				print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
				i++;
			}
			cuts = split_string ("overwrite conflicting files, multiple patterns can be specified by separating them with a comma", max_length + 2);
			print_aligned ("  %s <%s>".printf ("--overwrite", dgettext (null, "glob")), ": %s".printf (cuts[0]), max_length);
			i = 1;
			while (i < cuts.length) {
				print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
				i++;
			}
		}

		void search_pkgs (string search_string) {
			try {
				var pkgs = user_daemon.search_pkgs_sync (search_string);
				if (pkgs.length == 0) {
					cmd.set_exit_status (1);
					return;
				}
				int version_length = 0;
				int repo_length = 0;
				foreach (unowned AlpmPackage pkg in pkgs) {
					if (pkg.version.length > version_length) {
						version_length = pkg.version.length;
					}
					if (pkg.repo.length > repo_length) {
						repo_length = pkg.repo.length;
					}
				}
				int available_width = get_term_width () - (version_length + repo_length + 3);
				foreach (unowned AlpmPackage pkg in pkgs) {
					string name = pkg.name;
					if (pkg.origin == 2) {
						name = "%s [%s]".printf (pkg.name, dgettext (null, "Installed"));
					}
					var str_builder = new StringBuilder ();
					str_builder.append (name);
					str_builder.append (" ");
					int diff = available_width - name.char_count ();
					if (diff > 0) {
						while (diff > 0) {
							str_builder.append (" ");
							diff--;
						}
					}
					str_builder.append ("%-*s %s \n".printf (version_length, pkg.version, pkg.repo));
					stdout.printf ("%s", str_builder.str);
					string[] cuts = split_string (pkg.desc, 2, available_width);
					foreach (unowned string cut in cuts) {
						print_aligned ("", cut, 2);
					}
				}
			} catch (Error e) {
				print_error (e.message);
			}
		}

		void search_in_aur (string search_string) {
			this.hold ();
			user_daemon.search_in_aur.begin (search_string, (obj,res) => {
				try {
					AURPackage[] pkgs = user_daemon.search_in_aur.end (res);
					if (pkgs.length == 0) {
						this.release ();
						cmd.set_exit_status (1);
						return;
					}
					int version_length = 0;
					foreach (unowned AURPackage pkg in pkgs) {
						if (pkg.version.length > version_length) {
							version_length = pkg.version.length;
						}
					}
					int aur_length = dgettext (null, "AUR").char_count ();
					int available_width = get_term_width () - (version_length + aur_length + 3);
					// sort aur pkgs by popularity
					var results = new List<AURPackage?> ();
					foreach (unowned AURPackage pkg in pkgs) {
						results.append (pkg);
					}
					results.sort ((pkg1, pkg2) => {
						double diff = pkg2.popularity - pkg1.popularity;
						if (diff < 0) {
							return -1;
						} else if (diff > 0) {
							return 1;
						} else {
							return 0;
						}
					});
					foreach (unowned AURPackage pkg in results) {
						var str_builder = new StringBuilder ();
						string name = pkg.name;
						if (pkg.installed_version != "") {
							name = "%s [%s]".printf (pkg.name, dgettext (null, "Installed"));
						}
						str_builder.append (name);
						str_builder.append (" ");
						int diff = available_width - name.char_count ();
						if (diff > 0) {
							while (diff > 0) {
								str_builder.append (" ");
								diff--;
							}
						}
						str_builder.append ("%-*s %s \n".printf (version_length, pkg.version, dgettext (null, "AUR")));
						stdout.printf ("%s", str_builder.str);
						string[] cuts = split_string (pkg.desc, 2, available_width);
						foreach (unowned string cut in cuts) {
							print_aligned ("", cut, 2);
						}
					}
				} catch (Error e) {
					print_error (e.message);
				}
				this.release ();
			});
		}

		void display_pkg_infos (string[] pkgnames) {
			string[] properties = {};
			properties += dgettext (null, "Name");
			properties += dgettext (null, "Version");
			properties += dgettext (null, "Description");
			properties += dgettext (null, "URL");
			properties += dgettext (null, "Licenses");
			properties += dgettext (null, "Repository");
			properties += dgettext (null, "Size");
			properties += dgettext (null, "Groups");
			properties += dgettext (null, "Depends On");
			properties += dgettext (null, "Optional Dependencies");
			properties += dgettext (null, "Required By");
			properties += dgettext (null, "Optional For");
			properties += dgettext (null, "Provides");
			properties += dgettext (null, "Replaces");
			properties += dgettext (null, "Conflicts With");
			properties += dgettext (null, "Packager");
			properties += dgettext (null, "Build Date");
			properties += dgettext (null, "Install Date");
			properties += dgettext (null, "Install Reason");
			properties += dgettext (null, "Signatures");
			properties += dgettext (null, "Backup files");
			int max_length = 0;
			foreach (unowned string prop in properties) {
				// use char_count to handle special characters
				if (prop.char_count () > max_length) {
					max_length = prop.length;
				}
			}
			foreach (unowned string pkgname in pkgnames) {
				try {
					var details =  user_daemon.get_pkg_details (pkgname, "");
					if (details.name == "") {
						print_error (dgettext (null, "target not found: %s").printf (pkgname) + "\n");
						continue;
					}
					// Name
					print_aligned (properties[0], ": %s".printf (details.name), max_length);
					// Version
					print_aligned (properties[1], ": %s".printf (details.version), max_length);
					// Description
					string[] cuts = split_string (details.desc, max_length + 2);
					print_aligned (properties[2], ": %s".printf (cuts[0]), max_length);
					int i = 1;
					while (i < cuts.length) {
						print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
						i++;
					}
					// URL
					print_aligned (properties[3], ": %s".printf (details.url), max_length);
					// Licenses
					print_aligned (properties[4], ": %s".printf (details.licenses[0]), max_length);
					i = 1;
					while (i < details.licenses.length) {
						print_aligned ("", "%s".printf (details.licenses[i]), max_length + 2);
						i++;
					}
					// Repository
					print_aligned (properties[5], ": %s".printf (details.repo), max_length);
					// Size
					print_aligned (properties[6], ": %s".printf (format_size (details.size)), max_length);
					// Groups
					if (details.groups.length > 0) {
						cuts = split_string (concatenate_strings (details.groups), max_length + 2);
						print_aligned (properties[7], ": %s".printf (cuts[0]), max_length);
						i = 1;
						while (i < cuts.length) {
							print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
							i++;
						}
					}
					// Depends
					if (details.depends.length > 0) {
						cuts = split_string (concatenate_strings (details.depends), max_length + 2);
						print_aligned (properties[8], ": %s".printf (cuts[0]), max_length);
						i = 1;
						while (i < cuts.length) {
							print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
							i++;
						}
					}
					// Opt depends
					if (details.optdepends.length > 0) {
						string depstring = details.optdepends[0];
						var satisfier = AlpmPackage ();
						try {
							satisfier = user_daemon.find_installed_satisfier (depstring);
						} catch (Error e) {
							print_error (e.message);
						}
						if (satisfier.name != "") {
							depstring = "%s [%s]".printf (depstring, dgettext (null, "Installed"));
						}
						cuts = split_string (depstring, max_length + 2);
						print_aligned (properties[9], ": %s".printf (cuts[0]), max_length);
						i = 1;
						while (i < cuts.length) {
							print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
							i++;
						}
						i = 1;
						while (i < details.optdepends.length) {
							depstring = details.optdepends[i];
							satisfier = AlpmPackage ();
							try {
								satisfier = user_daemon.find_installed_satisfier (depstring);
							} catch (Error e) {
								print_error (e.message);
							}
							if (satisfier.name != "") {
								depstring = "%s [%s]".printf (depstring, dgettext (null, "Installed"));
							}
							cuts = split_string (depstring, max_length + 2);
							int j = 0;
							while (j < cuts.length) {
								print_aligned ("", "%s".printf (cuts[j]), max_length + 2);
								j++;
							}
							i++;
						}
					}
					// Required by
					if (details.requiredby.length > 0) {
						cuts = split_string (concatenate_strings (details.requiredby), max_length + 2);
						print_aligned (properties[10], ": %s".printf (cuts[0]), max_length);
						i = 1;
						while (i < cuts.length) {
							print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
							i++;
						}
					}
					// Optional for
					if (details.optionalfor.length > 0) {
						cuts = split_string (concatenate_strings (details.optionalfor), max_length + 2);
						print_aligned (properties[11], ": %s".printf (cuts[0]), max_length);
						i = 1;
						while (i < cuts.length) {
							print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
							i++;
						}
					}
					// Provides
					if (details.provides.length > 0) {
						cuts = split_string (concatenate_strings (details.provides), max_length + 2);
						print_aligned (properties[12], ": %s".printf (cuts[0]), max_length);
						i = 1;
						while (i < cuts.length) {
							print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
							i++;
						}
					}
					// Replaces
					if (details.replaces.length > 0) {
						cuts = split_string (concatenate_strings (details.replaces), max_length + 2);
						print_aligned (properties[13], ": %s".printf (cuts[0]), max_length);
						i = 1;
						while (i < cuts.length) {
							print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
							i++;
						}
					}
					// Conflicts
					if (details.conflicts.length > 0) {
						cuts = split_string (concatenate_strings (details.conflicts), max_length + 2);
						print_aligned (properties[14], ": %s".printf (cuts[0]), max_length);
						i = 1;
						while (i < cuts.length) {
							print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
							i++;
						}
					}
					// Maintainer
					cuts = split_string (details.packager, max_length + 2);
					print_aligned (properties[15], ": %s".printf (cuts[0]), max_length);
					i = 1;
					while (i < cuts.length) {
						print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
						i++;
					}
					// Build date
					print_aligned (properties[16], ": %s".printf (details.builddate), max_length);
					// Install date
					if (details.installdate != "") {
						print_aligned (properties[17], ": %s".printf (details.installdate), max_length);
					}
					// Reason
					if (details.reason != "") {
						cuts = split_string (details.reason, max_length + 2);
						print_aligned (properties[18], ": %s".printf (cuts[0]), max_length);
						i = 1;
						while (i < cuts.length) {
							print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
							i++;
						}
					}
					// Signature
					if (details.has_signature != "") {
						print_aligned (properties[19], ": %s".printf (details.has_signature), max_length);
					}
					// Backup files
					if (details.backups.length > 0) {
						print_aligned (properties[20], ": %s".printf (details.backups[0]), max_length);
						i = 1;
						while (i < details.backups.length) {
							print_aligned ("", "%s".printf (details.backups[i]), max_length + 2);
							i++;
						}
					}
					stdout.printf ("\n");
				} catch (Error e) {
					print_error (e.message);
				}
			}
		}

		void display_aur_infos (string[] pkgnames) {
			string[] properties = {};
			properties += dgettext (null, "Name");
			properties += dgettext (null, "Package Base");
			properties += dgettext (null, "Version");
			properties += dgettext (null, "Description");
			properties += dgettext (null, "URL");
			properties += dgettext (null, "Licenses");
			properties += dgettext (null, "Depends On");
			properties += dgettext (null, "Make Dependencies");
			properties += dgettext (null, "Check Dependencies");
			properties += dgettext (null, "Optional Dependencies");
			properties += dgettext (null, "Provides");
			properties += dgettext (null, "Replaces");
			properties += dgettext (null, "Conflicts With");
			properties += dgettext (null, "Packager");
			properties += dgettext (null, "First Submitted");
			properties += dgettext (null, "Last Modified");
			properties += dgettext (null, "Votes");
			properties += dgettext (null, "Out of Date");
			int max_length = 0;
			foreach (unowned string prop in properties) {
				// use char_count to handle special characters
				if (prop.char_count () > max_length) {
					max_length = prop.length;
				}
			}
			foreach (string pkgname in pkgnames) {
				this.hold ();
				user_daemon.get_aur_details.begin (pkgname, (obj, res) => {
					try {
						var details = user_daemon.get_aur_details.end (res);
						if (details.name == "") {
							print_error (dgettext (null, "target not found: %s").printf (pkgname) + "\n");
							this.release ();
							return;
						}
						// Name
						print_aligned (properties[0], ": %s".printf (details.name), max_length);
						// Package Base
						if (details.packagebase != details.name) {
							print_aligned (properties[1], ": %s".printf (details.packagebase), max_length);
						}
						// Version
						print_aligned (properties[2], ": %s".printf (details.version), max_length);
						// Description
						string[] cuts = split_string (details.desc, max_length + 2);
						print_aligned (properties[3], ": %s".printf (cuts[0]), max_length);
						int i = 1;
						while (i < cuts.length) {
							print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
							i++;
						}
						// URL
						print_aligned (properties[4], ": %s".printf (details.url), max_length);
						// Licenses
						print_aligned (properties[5], ": %s".printf (details.licenses[0]), max_length);
						i = 1;
						while (i < details.licenses.length) {
							print_aligned ("", "%s".printf (details.licenses[i]), max_length + 2);
							i++;
						}
						// Depends
						if (details.depends.length > 0) {
							cuts = split_string (concatenate_strings (details.depends), max_length + 2);
							print_aligned (properties[6], ": %s".printf (cuts[0]), max_length);
							i = 1;
							while (i < cuts.length) {
								print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
								i++;
							}
						}
						// Make Depends
						if (details.makedepends.length > 0) {
							cuts = split_string (concatenate_strings (details.makedepends), max_length + 2);
							print_aligned (properties[7], ": %s".printf (cuts[0]), max_length);
							i = 1;
							while (i < cuts.length) {
								print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
								i++;
							}
						}
						// Check Depends
						if (details.checkdepends.length > 0) {
							cuts = split_string (concatenate_strings (details.checkdepends), max_length + 2);
							print_aligned (properties[8], ": %s".printf (cuts[0]), max_length);
							i = 1;
							while (i < cuts.length) {
								print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
								i++;
							}
						}
						// Opt depends
						if (details.optdepends.length > 0) {
							string depstring = details.optdepends[0];
							var satisfier = AlpmPackage ();
							try {
								satisfier = user_daemon.find_installed_satisfier (depstring);
							} catch (Error e) {
								print_error (e.message);
							}
							if (satisfier.name != "") {
								depstring = "%s [%s]".printf (depstring, dgettext (null, "Installed"));
							}
							cuts = split_string (depstring, max_length + 2);
							print_aligned (properties[9], ": %s".printf (cuts[0]), max_length);
							i = 1;
							while (i < cuts.length) {
								print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
								i++;
							}
							i = 1;
							while (i < details.optdepends.length) {
								depstring = details.optdepends[i];
								satisfier = AlpmPackage ();
								try {
									satisfier = user_daemon.find_installed_satisfier (depstring);
								} catch (Error e) {
									print_error (e.message);
								}
								if (satisfier.name != "") {
									depstring = "%s [%s]".printf (depstring, dgettext (null, "Installed"));
								}
								cuts = split_string (depstring, max_length + 2);
								int j = 0;
								while (j < cuts.length) {
									print_aligned ("", "%s".printf (cuts[j]), max_length + 2);
									j++;
								}
								i++;
							}
						}
						// Provides
						if (details.provides.length > 0) {
							cuts = split_string (concatenate_strings (details.provides), max_length + 2);
							print_aligned (properties[10], ": %s".printf (cuts[0]), max_length);
							i = 1;
							while (i < cuts.length) {
								print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
								i++;
							}
						}
						// Replaces
						if (details.replaces.length > 0) {
							cuts = split_string (concatenate_strings (details.replaces), max_length + 2);
							print_aligned (properties[11], ": %s".printf (cuts[0]), max_length);
							i = 1;
							while (i < cuts.length) {
								print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
								i++;
							}
						}
						// Conflicts
						if (details.conflicts.length > 0) {
							cuts = split_string (concatenate_strings (details.conflicts), max_length + 2);
							print_aligned (properties[12], ": %s".printf (cuts[0]), max_length);
							i = 1;
							while (i < cuts.length) {
								print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
								i++;
							}
						}
						// Maintainer
						if (details.maintainer != "") {
							print_aligned (properties[13], ": %s".printf (details.maintainer), max_length);
						}
						// First Submitted
						print_aligned (properties[14], ": %s".printf (details.firstsubmitted), max_length);
						// Last Modified
						print_aligned (properties[15], ": %s".printf (details.lastmodified), max_length);
						// Votes
						print_aligned (properties[16], ": %s".printf (details.numvotes.to_string ()), max_length);
						// Last Modified
						if (details.outofdate != "") {
							print_aligned (properties[17], ": %s".printf (details.outofdate), max_length);
						}
						stdout.printf ("\n");
					} catch (Error e) {
						print_error (e.message);
					}
					this.release ();
				});
			}
		}

		void print_pkgs (AlpmPackage[] pkgs, bool print_installed) {
			int name_length = 0;
			int version_length = 0;
			int repo_length = 0;
			int size_length = 0;
			foreach (unowned AlpmPackage pkg in pkgs) {
				string name = pkg.name;
				if (print_installed && pkg.origin == 2) {
					name = "%s [%s]".printf (pkg.name, dgettext (null, "Installed"));
				}
				int current_name_length = name.char_count ();
				if (current_name_length > name_length) {
					name_length = current_name_length;
				}
				if (pkg.version.length > version_length) {
					version_length = pkg.version.length;
				}
				if (pkg.repo.length > repo_length) {
					repo_length = pkg.repo.length;
				}
				string size = format_size (pkg.size);
				if (size.length > size_length) {
					size_length = size.length;
				}
			}
			int total_width = name_length + version_length + repo_length + size_length + 4;
			int margin = 0;
			if (get_term_width () > total_width) {
				// divide available space between columns
				int available_width = get_term_width () - total_width;
				margin = available_width / 4;
				// get left space to size
				size_length += available_width - (margin * 4);
			}
			foreach (unowned AlpmPackage pkg in pkgs) {
				// use this code to correctly aligned text with special characters
				var str_builder = new StringBuilder ();
				string name = pkg.name;
				if (pkg.installed_version != "") {
					name = "%s [%s]".printf (pkg.name, dgettext (null, "Installed"));
				}
				str_builder.append (name);
				str_builder.append (" ");
				int diff = name_length + margin - name.char_count ();
				if (diff > 0) {
					while (diff > 0) {
						str_builder.append (" ");
						diff--;
					}
				}
				str_builder.append ("%-*s %-*s %*s \n".printf (version_length + margin, pkg.version,
														repo_length + margin, pkg.repo,
														size_length + margin, format_size (pkg.size)));
				stdout.printf ("%s", str_builder.str);
			}
		}

		void list_installed () {
			try {
				var pkgs = user_daemon.get_installed_pkgs_sync ();
				print_pkgs (pkgs, false);
			} catch (Error e) {
				print_error (e.message);
			}
		}

		void list_orphans () {
			try {
				var pkgs = user_daemon.get_orphans_sync ();
				print_pkgs (pkgs, false);
			} catch (Error e) {
				print_error (e.message);
			}
		}

		void list_foreign () {
			try {
				var pkgs = user_daemon.get_foreign_pkgs_sync ();
				print_pkgs (pkgs, false);
			} catch (Error e) {
				print_error (e.message);
			}
		}

		void list_groups (string[] names) {
			if (names.length == 0) {
				try {
					string[] grpnames = user_daemon.get_groups_names ();
					foreach (unowned string name in grpnames) {
						stdout.printf ("%s\n", name);
					}
				} catch (Error e) {
					print_error (e.message);
				}
				return;
			}
			foreach (unowned string name in names) {
				try {
					var pkgs = user_daemon.get_group_pkgs_sync (name);
					if (pkgs.length == 0) {
						print_error (dgettext (null, "target not found: %s").printf (name));
					} else {
						print_pkgs (pkgs, true);
					}
				} catch (Error e) {
					print_error (e.message);
				}
				stdout.printf ("\n");
			}
		}

		void list_repos (string[] names) {
			if (names.length == 0) {
				try {
					string[] grpnames = user_daemon.get_repos_names ();
					foreach (unowned string name in grpnames) {
						stdout.printf ("%s\n", name);
					}
				} catch (Error e) {
					print_error (e.message);
				}
				return;
			}
			foreach (unowned string name in names) {
				try {
					var pkgs = user_daemon.get_repo_pkgs_sync (name);
					if (pkgs.length == 0) {
						print_error (dgettext (null, "target not found: %s").printf (name));
					} else {
						print_pkgs (pkgs, true);
					}
				} catch (Error e) {
					print_error (e.message);
				}
				stdout.printf ("\n");
			}
		}

		void list_files (string[] names) {
			foreach (unowned string name in names) {
				try {
					string[] files = user_daemon.get_pkg_files (name);
					if (files.length == 0) {
						print_error (dgettext (null, "target not found: %s").printf (name));
					} else {
						foreach (unowned string path in files) {
							stdout.printf ("%s\n", path);
						}
					}
				} catch (Error e) {
					print_error (e.message);
				}
				stdout.printf ("\n");
			}
		}

		void search_files (string[] files) {
			try {
				HashTable<string, Variant> result = user_daemon.search_files (files);
				if (result.size () == 0) {
					foreach (unowned string file in files) {
						stdout.printf (dgettext (null, "No package owns %s\n").printf (file));
					}
					cmd.set_exit_status (1);
					return;
				}
				var iter = HashTableIter<string, Variant> (result);
				unowned string pkgname;
				unowned Variant files_list;
				while (iter.next (out pkgname, out files_list)) {
					foreach (unowned string file in (string[]) files_list) {
						stdout.printf ("%s\n", dgettext (null, "%s is owned by %s").printf (file, pkgname));
					}
				}
			} catch (Error e) {
				print_error (e.message);
			}
		}

		AlpmPackage get_installed_pkg (string pkgname) {
			try {
				return user_daemon.get_installed_pkg (pkgname);
			} catch (Error e) {
				print_error (e.message);
				return AlpmPackage () {
					name = "",
					version = "",
					desc = "",
					repo = "",
					icon = ""
				};
			}
		}

		void checkupdates () {
			this.hold ();
			user_daemon.get_updates_finished.connect (on_get_updates_finished);
			try {
				user_daemon.start_get_updates (enable_aur, false);
			} catch (Error e) {
				print_error (e.message);
				user_daemon.get_updates_finished.disconnect (on_get_updates_finished);
				this.release ();
			}
		}

		void on_get_updates_finished (Updates updates) {
			user_daemon.get_updates_finished.disconnect (on_get_updates_for_sysupgrade_finished);
			uint updates_nb = updates.repos_updates.length + updates.aur_updates.length;
			if (updates_nb == 0) {
				stdout.printf ("%s\n", dgettext (null, "Your system is up-to-date"));
			} else {
				// special status when updates are available
				cmd.set_exit_status (100);
				// print pkgs
				int name_length = 0;
				int version_length = 0;
				int repo_length = 0;
				foreach (unowned AlpmPackage pkg in updates.repos_updates) {
					if (pkg.name.length > name_length) {
						name_length = pkg.name.length;
					}
					if (pkg.version.length > version_length) {
						version_length = pkg.version.length;
					}
					if (pkg.repo.length > repo_length) {
						repo_length = pkg.repo.length;
					}
				}
				foreach (unowned AURPackage pkg in updates.aur_updates) {
					if (pkg.name.length > name_length) {
						name_length = pkg.name.length;
					}
					if (pkg.version.length > version_length) {
						version_length = pkg.version.length;
					}
				}
				if (dgettext (null, "AUR").char_count () > repo_length) {
					repo_length = dgettext (null, "AUR").char_count ();
				}
				int total_width = name_length + version_length + repo_length + 3;
				int margin = 0;
				if (get_term_width () > total_width) {
					// divide available space between columns
					int available_width = get_term_width () - total_width;
					margin = available_width / 3;
					// get left space to repo
					repo_length += available_width - (margin * 3);
				}
				string info = ngettext ("%u available update", "%u available updates", updates_nb).printf (updates_nb);
				stdout.printf ("%s:\n", info);
				foreach (unowned AlpmPackage pkg in updates.repos_updates) {
					stdout.printf ("%-*s %-*s %s \n", name_length + margin, pkg.name,
													version_length + margin, pkg.version,
													pkg.repo);
				}
				foreach (unowned AURPackage pkg in updates.aur_updates) {
					stdout.printf ("%-*s %-*s %s \n", name_length + margin, pkg.name,
													version_length + margin, pkg.version,
													dgettext (null, "AUR"));
				}
			}
			this.release ();
		}

		void install_pkgs (string[] targets) {
			try {
				foreach (unowned string target in targets) {
					bool found = false;
					// check for local or remote path
					if (".pkg.tar" in target) {
						if ("://" in target) {
							if ("file://" in target) {
								// handle file:// uri
								var file = File.new_for_uri (target);
								string? absolute_path = file.get_path ();
								if (absolute_path != null) {
									to_load += absolute_path;
									found = true;
								}
							} else {
								// add url in to_load, pkg will be downloaded by system_daemon
								to_load += target;
								found = true;
							}
						} else {
							// handle local or absolute path
							var file = File.new_for_path (target);
							string? absolute_path = file.get_path ();
							if (absolute_path != null) {
								to_load += absolute_path;
								found = true;
							}
						}
					} else {
						var pkg = user_daemon.find_sync_satisfier (target);
						if (pkg.name != "") {
							to_install += target;
							found = true;
						} else {
							string[] groupnames = user_daemon.get_groups_names ();
							if (target in groupnames) {
								ask_group_confirmation (target);
								found = true;
							}
						}
					}
					if (!found) {
						print_error (dgettext (null, "target not found: %s").printf (target));
						return;
					}
				}
			} catch (Error e) {
				print_error (e.message);
			}
			if (to_install.length == 0 && to_load.length == 0) {
				stdout.printf (dgettext (null, "Nothing to do") + ".\n");
				return;
			}
			// do not install a package if it is already installed and up to date
			transflags = (1 << 13); //Alpm.TransFlag.NEEDED
			stdout.printf (dgettext (null, "Preparing") + "...\n");
			this.hold ();
			start_trans_prepare ();
		}

		void ask_group_confirmation (string grpname) {
			try {
				var pkgs = user_daemon.get_group_pkgs_sync (grpname);
				// print pkgs
				int name_length = 0;
				int version_length = 0;
				int repo_length = 0;
				foreach (unowned AlpmPackage pkg in pkgs) {
					if (pkg.name.length > name_length) {
						name_length = pkg.name.length;
					}
					if (pkg.version.length > version_length) {
						version_length = pkg.version.length;
					}
					if (pkg.repo.length > repo_length) {
						repo_length = pkg.repo.length;
					}
				}
				int num_length = pkgs.length.to_string ().length + 1;
				int total_width = num_length + name_length + version_length + repo_length + 4;
				int margin = 0;
				if (get_term_width () > total_width) {
					// divide available space between columns
					int available_width = get_term_width () - total_width;
					margin = available_width / 3;
					// get left space to repo
					repo_length += available_width - (margin * 3);
				}
				stdout.printf ("%s:\n".printf (dngettext (null, "There is %u member in group %s",
							"There are %u members in group %s", pkgs.length).printf (pkgs.length, grpname)));
				int num = 1;
				foreach (unowned AlpmPackage pkg in pkgs) {
					stdout.printf ("%*s %-*s %-*s %s \n", num_length, "%i:".printf (num),
															name_length + margin, pkg.name,
															version_length + margin, pkg.version,
															pkg.repo);
					num++;
				}
				// get user input
				asking_user_input = true;
				while (true) {
					stdout.printf ("%s: ", dgettext (null, "Enter a selection (default=all)"));
					string ans = stdin.read_line ();
					int64 nb;
					int64[] numbers = {};
					// remvove trailing newline
					ans = ans.replace ("\n", "");
					// just return use default
					if (ans == "") {
						foreach (unowned AlpmPackage pkg in pkgs) {
							to_install += pkg.name;
						}
						break;
					} else {
						// split ","
						string[] splitted = ans.split (",");
						foreach (unowned string part in splitted) {
							// check for range
							if ("-" in part) {
								string[] splitted2 = part.split ("-", 2);
								// get all numbers in range
								int64 beg_num, end_num;
								if (int64.try_parse (splitted2[0], out beg_num)) {
									if (int64.try_parse (splitted2[1], out end_num)) {
										nb = beg_num;
										while (nb <= end_num) {
											if (nb >= 1 && nb < pkgs.length) {
												numbers += nb;
											}
											nb++;
										}
									}
								}
							} else if (int64.try_parse (part, out nb)) {
								if (nb >= 1 && nb < pkgs.length) {
									numbers += nb;
								}
							}
						}
					}
					stdout.printf ("\n");
					if (numbers.length > 0) {
						foreach (int64 number in numbers) {
							to_install += pkgs[number -1].name;
						}
						break;
					}
				}
			} catch (Error e) {
				print_error (e.message);
			}
		}

		void reinstall_pkgs (string[] names) {
			try {
				foreach (unowned string name in names) {
					bool found = false;
					string version = "";
					var local_pkg = user_daemon.get_installed_pkg (name);
					if (local_pkg.name != "") {
						version = local_pkg.version;
						var sync_pkg = user_daemon.get_sync_pkg (name);
						if (sync_pkg.name != "") {
							if (local_pkg.version == sync_pkg.version) {
								to_install += name;
								found = true;
							}
						}
					} else {
						string[] groupnames = user_daemon.get_groups_names ();
						if (name in groupnames) {
							found = true;
							var pkgs = user_daemon.get_group_pkgs_sync (name);
							foreach (unowned AlpmPackage pkg in pkgs) {
								if (pkg.version == pkg.installed_version) {
									to_install += name;
								}
							}
						}
					}
					if (!found) {
						if (version == "") {
							print_error (dgettext (null, "target not found: %s").printf (name));
						} else {
							print_error (dgettext (null, "target not found: %s").printf (name + "-" + version));
						}
						return;
					}
				}
			} catch (Error e) {
				print_error (e.message);
			}
			if (to_install.length == 0 && to_load.length == 0) {
				stdout.printf (dgettext (null, "Nothing to do") + ".\n");
				return;
			}
			stdout.printf (dgettext (null, "Preparing") + "...\n");
			this.hold ();
			start_trans_prepare ();
		}

		void remove_pkgs (string[] names, bool recurse = false) {
			bool group_found = false;
			try {
				foreach (unowned string name in names) {
					bool found = false;
					var local_pkg = user_daemon.get_installed_pkg (name);
					if (local_pkg.name != "") {
						to_remove += name;
						found = true;
					} else {
						string[] groupnames = user_daemon.get_groups_names ();
						if (name in groupnames) {
							found = true;
							var pkgs = user_daemon.get_group_pkgs_sync (name);
							foreach (unowned AlpmPackage pkg in pkgs) {
								if (pkg.version == pkg.installed_version) {
									to_remove += pkg.name;
									group_found = true;
								}
							}
						}
					}
					if (!found) {
						print_error (dgettext (null, "target not found: %s").printf (name));
						return;
					}
				}
			} catch (Error e) {
				print_error (e.message);
			}
			if (to_remove.length == 0) {
				stdout.printf (dgettext (null, "Nothing to do") + ".\n");
				return;
			}
			if (group_found) {
				transflags |= (1 << 15); //Alpm.TransFlag.UNNEEDED
			} else {
				transflags |= (1 << 4); //Alpm.TransFlag.CASCADE
			}
			if (recurse) {
				transflags |= (1 << 5); //Alpm.TransFlag.RECURSE
			}
			stdout.printf (dgettext (null, "Preparing") + "...\n");
			this.hold ();
			start_trans_prepare ();
		}

		void remove_orphans () {
			try {
				var pkgs = user_daemon.get_orphans_sync ();
				foreach (unowned AlpmPackage pkg in pkgs) {
					to_remove += pkg.name;
				}
				stdout.printf (dgettext (null, "Preparing") + "...\n");
				transflags = (1 << 4); //Alpm.TransFlag.CASCADE
				transflags |= (1 << 5); //Alpm.TransFlag.RECURSE
				this.hold ();
				start_trans_prepare ();
			} catch (Error e) {
				print_error (e.message);
			}
		}

		void start_get_updates_for_sysupgrade () {
			if (!sysupgrade_after_trans) {
				stdout.printf (dgettext (null, "Starting full system upgrade") + "...\n");
			}
			sysupgrade_after_trans = false;
			system_daemon.get_updates_finished.connect (on_get_updates_for_sysupgrade_finished);
			try {
				system_daemon.start_get_updates (enable_aur);
			} catch (Error e) {
				print_error (e.message);
				system_daemon.get_updates_finished.disconnect (on_get_updates_for_sysupgrade_finished);
				this.release ();
			}
		}

		void on_get_updates_for_sysupgrade_finished (Updates updates) {
			system_daemon.get_updates_finished.disconnect (on_get_updates_for_sysupgrade_finished);
			to_install_first = {};
			// get syncfirst updates
			if (updates.is_syncfirst) {
				foreach (unowned AlpmPackage infos in updates.repos_updates) {
					to_install_first += infos.name;
				}
				start_sysupgrade_prepare ();
			} else {
				if (updates.aur_updates.length != 0) {
					string[] to_build = {};
					foreach (unowned AURPackage infos in updates.aur_updates) {
						if (!(infos.name in temporary_ignorepkgs)) {
							to_build += infos.name;
						}
					}
					if (updates.repos_updates.length != 0) {
						start_sysupgrade_prepare (to_build);
					} else {
						// only aur updates
						this.release ();
						build_pkgs (to_build);
					}
				} else {
					if (updates.repos_updates.length != 0) {
						start_sysupgrade_prepare ();
					} else {
						stdout.printf (dgettext (null, "Nothing to do") + ".\n");
						unlock ();
						this.release ();
					}
				}
			}
		}

		void build_pkgs (string[] to_build) {
			this.to_build = to_build;
			this.hold ();
			start_trans_prepare ();
		}

		async void build_aur_packages () {
			string pkgname = to_build_queue.pop_head ();
			stdout.printf ("%s...\n", dgettext (null, "Building %s").printf (pkgname));
			build_cancellable.reset ();
			string [] built_pkgs = {};
			int status = 1;
			string builddir;
			if (aur_build_dir == "/tmp") {
				builddir = "/tmp/pamac-build-%s".printf (Environment.get_user_name ());
			} else {
				builddir = aur_build_dir;
			}
			status = yield spawn_cmdline ({"mkdir", "-p", builddir});
			if (status == 0) {
				status = yield spawn_cmdline ({"rm", "-rf", pkgname}, builddir);
				if (!build_cancellable.is_cancelled ()) {
					if (status == 0) {
						building = true;
						status = yield spawn_cmdline ({"git", "clone", "https://aur.archlinux.org/%s.git".printf (pkgname)}, builddir);
						if (status == 0) {
							string pkgdir = "%s/%s".printf (builddir, pkgname);
							status = yield spawn_cmdline ({"makepkg", "-cf"}, pkgdir);
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
									print_error (e.message);
								}
							}
						}
					}
				} else {
					status = 1;
				}
			}
			if (status == 0 && built_pkgs.length > 0) {
				no_confirm_commit = true;
				stdout.printf ("\n");
				to_build = {};
				to_install = {};
				to_load = built_pkgs;
				start_trans_prepare ();
			} else {
				on_trans_commit_finished (false);
			}
		}

		async int spawn_cmdline (string[] args, string? working_directory = null) {
			int status = 1;
			var launcher = new SubprocessLauncher (SubprocessFlags.NONE);
			launcher.set_cwd (working_directory);
			launcher.set_environ (Environ.get ());
			try {
				Subprocess process = launcher.spawnv (args);
				try {
					yield process.wait_async (build_cancellable);
					if (process.get_if_exited ()) {
						status = process.get_exit_status ();
					}
				} catch (Error e) {
					// cancelled
					process.send_signal (Posix.Signal.INT);
					process.send_signal (Posix.Signal.KILL);
				}
			} catch (Error e) {
				print_error (e.message);
			}
			return status;
		}

		bool get_lock () {
			bool locked = false;
			connecting_system_daemon ();
			try {
				locked = system_daemon.get_lock ();
			} catch (Error e) {
				print_error (e.message);
			}
			return locked;
		}

		void unlock () {
			try {
				system_daemon.unlock ();
			} catch (Error e) {
				print_error (e.message);
			}
		}

		async bool check_authorization () {
			SourceFunc callback = check_authorization.callback;
			bool authorized = false;
			ulong handler_id = system_daemon.get_authorization_finished.connect ((authorized_) => {
				authorized = authorized_;
				Idle.add ((owned) callback);
			});
			try {
				system_daemon.start_get_authorization ();
			} catch (Error e) {
				print_error (e.message);
			}
			yield;
			system_daemon.disconnect (handler_id);
			return authorized;
		}

		void start_refresh () {
			this.hold ();
			if (get_lock ()) {
				// let's time to pkttyagent to get registred
				Timeout.add (200, () => {
					check_authorization.begin ((obj, res) => {
						bool authorized = check_authorization.end (res);
						if (authorized) {
							stdout.printf ("%s...\n", dgettext (null, "Synchronizing package databases"));
							try {
								system_daemon.refresh_finished.connect (on_refresh_finished);
								system_daemon.start_refresh (force_refresh);
							} catch (Error e) {
								print_error (e.message);
								system_daemon.refresh_finished.disconnect (on_refresh_finished);
							}
						} else {
							unlock ();
							this.release ();
							cmd.set_exit_status (1);
						}
					});
					return false;
				});
			} else {
				stdout.printf (dgettext (null, "Waiting for another package manager to quit") + "...\n");
				Timeout.add (5000, () => {
					bool locked = get_lock ();
					if (locked) {
						check_authorization.begin ((obj, res) => {
							bool authorized = check_authorization.end (res);
							if (authorized) {
								stdout.printf ("%s...\n", dgettext (null, "Synchronizing package databases"));
								try {
									system_daemon.refresh_finished.connect (on_refresh_finished);
									system_daemon.start_refresh (force_refresh);
								} catch (Error e) {
									print_error (e.message);
									system_daemon.refresh_finished.disconnect (on_refresh_finished);
								}
							} else {
								unlock ();
								this.release ();
								cmd.set_exit_status (1);
							}
						});
					}
					return !locked;
				});
			}
		}

		void on_refresh_finished (bool success) {
			previous_filename = "";
			system_daemon.refresh_finished.disconnect (on_refresh_finished);
			if (success) {
				start_get_updates_for_sysupgrade ();
			} else {
				unlock ();
				this.release ();
				cmd.set_exit_status (1);
			}
		}

		void start_trans_prepare () {
			if (get_lock ()) {
				try {
					system_daemon.start_trans_prepare (transflags, to_install, to_remove, to_load, to_build, overwrite_files);
				} catch (Error e) {
					print_error (e.message);
					on_trans_prepare_finished (false);
				}
			} else {
				stdout.printf (dgettext (null, "Waiting for another package manager to quit") + "...\n");
				Timeout.add (5000, () => {
					bool locked = get_lock ();
					if (locked) {
						try {
							system_daemon.start_trans_prepare (transflags, to_install, to_remove, to_load, to_build, overwrite_files);
						} catch (Error e) {
							print_error (e.message);
						}
					}
					return !locked;
				});
			}
		}

		void start_sysupgrade_prepare (string[] to_build = {}) {
			try {
				// this will respond with on_trans_prepare_finished signal
				system_daemon.start_sysupgrade_prepare (false, temporary_ignorepkgs, to_build, overwrite_files);
			} catch (Error e) {
				print_error (e.message);
				on_trans_prepare_finished (false);
			}
		}

		TransType set_transaction_sum () {
			// return 0 if transaction_sum is empty, 2, if there are only aur updates, 1 otherwise
			TransType type = 0;
			uint64 dsize = 0;
			int64 isize = 0;
			int max_name_length = 0;
			int max_version_length = 0;
			int max_installed_version_length = 0;
			int max_size_length = 0;
			int margin = 0;
			var summary = TransactionSummary ();
			try {
				summary = system_daemon.get_transaction_summary ();
			} catch (Error e) {
				print_error (e.message);
			}
			// first pass to compute trans type, pkgs size and strings length
			if (summary.to_remove.length > 0) {
				type |= TransType.STANDARD;
				if (!no_confirm_commit) {
					foreach (unowned AlpmPackage infos in summary.to_remove) {
						if (infos.name.length > max_name_length) {
							max_name_length = infos.name.length;
						}
						if (infos.version.length > max_version_length) {
							max_version_length = infos.version.length;
						}
					}
				}
			}
			if (summary.aur_conflicts_to_remove.length > 0) {
				if (!no_confirm_commit) {
					// do not add type enum because it is just infos
					foreach (unowned AURPackage infos in summary.aur_conflicts_to_remove) {
						if (infos.name.length > max_name_length) {
							max_name_length = infos.name.length;
						}
						if (infos.version.length > max_version_length) {
							max_version_length = infos.version.length;
						}
					}
				}
			}
			if (summary.to_downgrade.length > 0) {
				type |= TransType.STANDARD;
				if (!no_confirm_commit) {
					foreach (unowned AlpmPackage infos in summary.to_downgrade) {
						dsize += infos.download_size;
						var pkg = get_installed_pkg (infos.name);
						isize += ((int64) infos.size - (int64) pkg.size);
						if (infos.name.length > max_name_length) {
							max_name_length = infos.name.length;
						}
						if (infos.version.length > max_version_length) {
							max_version_length = infos.version.length;
						}
						if (infos.installed_version.length > max_installed_version_length) {
							max_installed_version_length = infos.installed_version.length;
						}
						string size = format_size (pkg.size);
						if (size.length > max_size_length) {
							max_size_length = size.length;
						}
					}
				}
			}
			if (summary.to_build.length > 0) {
				type |= TransType.BUILD;
				// populate build queue
				foreach (unowned string name in summary.aur_pkgbases_to_build) {
					to_build_queue.push_tail (name);
				}
				aur_pkgs_to_install = {};
				foreach (unowned AURPackage infos in summary.to_build) {
					aur_pkgs_to_install += infos.name;
					if (!no_confirm_commit) {
						if (infos.name.length > max_name_length) {
							max_name_length = infos.name.length;
						}
						if (infos.version.length > max_version_length) {
							max_version_length = infos.version.length;
						}
					}
				}
			}
			if (summary.to_install.length > 0) {
				type |= TransType.STANDARD;
				if (!no_confirm_commit) {
					foreach (unowned AlpmPackage infos in summary.to_install) {
						dsize += infos.download_size;
						var pkg = get_installed_pkg (infos.name);
						isize += ((int64) infos.size - (int64) pkg.size);
						if (infos.name.length > max_name_length) {
							max_name_length = infos.name.length;
						}
						if (infos.version.length > max_version_length) {
							max_version_length = infos.version.length;
						}
						string size = format_size (pkg.size);
						if (size.length > max_size_length) {
							max_size_length = size.length;
						}
					}
				}
			}
			if (summary.to_reinstall.length > 0) {
				type |= TransType.STANDARD;
				if (!no_confirm_commit) {
					foreach (unowned AlpmPackage infos in summary.to_reinstall) {
						dsize += infos.download_size;
						var pkg = get_installed_pkg (infos.name);
						if (infos.name.length > max_name_length) {
							max_name_length = infos.name.length;
						}
						if (infos.version.length > max_version_length) {
							max_version_length = infos.version.length;
						}
						string size = format_size (pkg.size);
						if (size.length > max_size_length) {
							max_size_length = size.length;
						}
					}
				}
			}
			if (summary.to_upgrade.length > 0) {
				type |= TransType.UPDATE;
				if (!no_confirm_commit) {
					foreach (unowned AlpmPackage infos in summary.to_upgrade) {
						dsize += infos.download_size;
						var pkg = get_installed_pkg (infos.name);
						isize += ((int64) infos.size - (int64) pkg.size);
						if (infos.name.length > max_name_length) {
							max_name_length = infos.name.length;
						}
						if (infos.version.length > max_version_length) {
							max_version_length = infos.version.length;
						}
						if (infos.installed_version.length > max_installed_version_length) {
							max_installed_version_length = infos.installed_version.length;
						}
						string size = format_size (pkg.size);
						if (size.length > max_size_length) {
							max_size_length = size.length;
						}
					}
				}
			}
			// second pass to print details
			if (!no_confirm_commit) {
				max_installed_version_length += 2; // because of (%s)
				int total_width = max_name_length + max_version_length + max_installed_version_length + max_size_length + 6;
				if (get_term_width () > total_width) {
					// divide available space between columns
					int available_width = get_term_width () - total_width;
					margin = available_width / 4;
					// get left space to size
					max_size_length += available_width - (margin * 4);
				}
				if (summary.to_upgrade.length > 0) {
					stdout.printf (dgettext (null, "To upgrade") + " (%u):\n".printf (summary.to_upgrade.length));
					foreach (unowned AlpmPackage infos in summary.to_upgrade) {
						stdout.printf ("  %-*s %-*s %-*s %*s \n", max_name_length + margin, infos.name,
															max_version_length + margin, infos.version,
															max_installed_version_length + margin, "(%s)".printf (infos.installed_version),
															max_size_length + margin, format_size (infos.size));
					}
				}
				if (summary.to_reinstall.length > 0) {
					stdout.printf (dgettext (null, "To reinstall") + " (%u):\n".printf (summary.to_reinstall.length));
					foreach (unowned AlpmPackage infos in summary.to_reinstall) {
						stdout.printf ("  %-*s %-*s %*s \n", max_name_length + margin, infos.name,
															max_version_length + margin, infos.version,
															max_size_length + margin, format_size (infos.size));
					}
				}
				if (summary.to_install.length > 0) {
					stdout.printf (dgettext (null, "To install") + " (%u):\n".printf (summary.to_install.length));
					foreach (unowned AlpmPackage infos in summary.to_install) {
						stdout.printf ("  %-*s %-*s %*s \n", max_name_length + margin, infos.name,
															max_version_length + margin, infos.version,
															max_size_length + margin, format_size (infos.size));
					}
				}
				if (summary.to_build.length > 0) {
					stdout.printf (dgettext (null, "To build") + " (%u):\n".printf (summary.to_build.length));
					foreach (unowned AURPackage infos in summary.to_build) {
						stdout.printf ("  %-*s %-*s\n", max_name_length + margin, infos.name,
														max_version_length + margin, infos.version);
					}
				}
				if (summary.to_downgrade.length > 0) {
					stdout.printf (dgettext (null, "To downgrade") + " (%u):\n".printf (summary.to_downgrade.length));
					foreach (unowned AlpmPackage infos in summary.to_downgrade) {
						stdout.printf ("  %-*s %-*s %-*s %*s \n", max_name_length + margin, infos.name,
															max_version_length + margin, infos.version,
															max_installed_version_length + margin, "(%s)".printf (infos.installed_version),
															max_size_length + margin, format_size (infos.size));
					}
				}
				bool to_remove_printed = false;
				if (summary.to_remove.length > 0) {
					stdout.printf (dgettext (null, "To remove") + " (%u):\n".printf (summary.to_remove.length));
					to_remove_printed = true;
					foreach (unowned AlpmPackage infos in summary.to_remove) {
						stdout.printf ("  %-*s %-*s\n", max_name_length + margin, infos.name,
														max_version_length + margin, infos.version);
					}
				}
				if (summary.aur_conflicts_to_remove.length > 0) {
					if (!to_remove_printed) {
						stdout.printf (dgettext (null, "To remove") + " (%u):\n".printf (summary.aur_conflicts_to_remove.length));
					}
					foreach (unowned AURPackage infos in summary.aur_conflicts_to_remove) {
						stdout.printf ("  %-*s %-*s\n", max_name_length + margin, infos.name,
														max_version_length + margin, infos.version);
					}
				}
				stdout.printf ("\n");
				if (dsize > 0) {
					stdout.printf ("%s: %s\n", dgettext (null, "Total download size"), format_size (dsize));
				}
				if (isize > 0) {
					stdout.printf ("%s: %s\n", dgettext (null, "Total installed size"), format_size (isize));
				} else if (isize < 0) {
					stdout.printf ("%s: -%s\n", dgettext (null, "Total installed size"), format_size (isize.abs ()));
				}
			}
			return type;
		}

		void on_trans_prepare_finished (bool success) {
			if (success) {
				TransType type = set_transaction_sum ();
				if (to_install_first.length != 0) {
					if (ask_confirmation ()) {
						sysupgrade_after_trans = true;
						no_confirm_commit = true;
						trans_release ();
						to_install = to_install_first;
						start_trans_prepare ();
						to_install_first = {};
					} else {
						stdout.printf (dgettext (null, "Transaction cancelled") + ".\n");
						trans_release ();
						unlock ();
						this.release ();
						cmd.set_exit_status (1);
					}
				} else if (no_confirm_commit) {
					// no_confirm_commit or only updates
					start_trans_commit ();
				} else if (type != 0) {
					if (ask_confirmation ()) {
						if (type == Type.BUILD) {
							// there only AUR packages to build
							trans_release ();
							on_trans_commit_finished (true);
						} else {
							start_trans_commit ();
						}
					} else {
						stdout.printf (dgettext (null, "Transaction cancelled") + ".\n");
						trans_release ();
						unlock ();
						this.release ();
						cmd.set_exit_status (1);
					}
				} else {
					stdout.printf (dgettext (null, "Nothing to do") + ".\n");
					trans_release ();
					unlock ();
					this.release ();
				}
			} else {
				var err = get_current_error ();
				if (err.message != "") {
					print_error (err.message, err.details);
				}
				unlock ();
				this.release ();
				cmd.set_exit_status (1);
			}
		}

		bool ask_confirmation () {
			stdout.printf ("%s ? %s ", dgettext (null, "Commit transaction"), dgettext (null, "[y/N]"));
			char buf[32];
			if (stdin.gets (buf) != null) {
				string ans = (string) buf;
				// remove trailing newline and uppercase
				ans = ans.replace ("\n", "").down ();
				// just return use default
				if (ans != "") {
					if (ans == dgettext (null, "y") ||
						ans == dgettext (null, "yes")) {
						return true;
					}
				}
			}
			return false;
		}

		void start_trans_commit () {
			try {
				asking_user_input = true;
				system_daemon.start_trans_commit ();
			} catch (Error e) {
				print_error (e.message);
				on_trans_commit_finished (false);
			}
		}

		void on_trans_commit_finished (bool success) {
			asking_user_input = false;
			// needed before build_aur_packages
			no_confirm_commit = false;
			if (success) {
				if (to_build_queue.get_length () != 0) {
					stdout.printf ("\n");
					check_authorization.begin ((obj, res) => {
						bool authorized = check_authorization.end (res);
						if (authorized) {
							build_aur_packages.begin ();
						} else {
							to_build_queue.clear ();
							on_trans_commit_finished (false);
						}
					});
				} else {
					if (sysupgrade_after_trans) {
						no_confirm_commit = true;
						start_get_updates_for_sysupgrade ();
					} else {
						stdout.printf (dgettext (null, "Transaction successfully finished") + ".\n");
						unlock ();
						this.release ();
					}
				}
			} else {
				var err = get_current_error ();
				if (err.message != "") {
					print_error (err.message, err.details);
				}
				to_build_queue.clear ();
				unlock ();
				this.release ();
				cmd.set_exit_status (1);
			}
			total_download = 0;
			already_downloaded = 0;
			previous_filename = "";
		}

		void trans_release () {
			try {
				system_daemon.trans_release ();
			} catch (Error e) {
				print_error (e.message);
			}
		}

		ErrorInfos get_current_error () {
			try {
				return system_daemon.get_current_error ();
			} catch (Error e) {
				print_error (e.message);
				return ErrorInfos ();
			}
		}

		void on_emit_event (uint primary_event, uint secondary_event, string[] details) {
			string? action = null;
			switch (primary_event) {
				case 1: //Alpm.Event.Type.CHECKDEPS_START
					action = dgettext (null, "Checking dependencies") + "...\n";
					asking_user_input = false;
					break;
				case 3: //Alpm.Event.Type.FILECONFLICTS_START
					current_action = dgettext (null, "Checking file conflicts") + "...";
					break;
				case 5: //Alpm.Event.Type.RESOLVEDEPS_START
					action = dgettext (null, "Resolving dependencies") + "...\n";
					asking_user_input = false;
					break;
				case 7: //Alpm.Event.Type.INTERCONFLICTS_START
					action = dgettext (null, "Checking inter-conflicts") + "...\n";
					break;
				case 11: //Alpm.Event.Type.PACKAGE_OPERATION_START
					switch (secondary_event) {
						// special case handle differently
						case 1: //Alpm.Package.Operation.INSTALL
							previous_filename = details[0];
							current_action = dgettext (null, "Installing %s").printf ("%s (%s)".printf (details[0], details[1])) + "...";
							break;
						case 2: //Alpm.Package.Operation.UPGRADE
							previous_filename = details[0];
							current_action = dgettext (null, "Upgrading %s").printf ("%s (%s -> %s)".printf (details[0], details[1], details[2])) + "...";
							break;
						case 3: //Alpm.Package.Operation.REINSTALL
							previous_filename = details[0];
							current_action = dgettext (null, "Reinstalling %s").printf ("%s (%s)".printf (details[0], details[1])) + "...";
							break;
						case 4: //Alpm.Package.Operation.DOWNGRADE
							previous_filename = details[0];
							current_action = dgettext (null, "Downgrading %s").printf ("%s (%s -> %s)".printf (details[0], details[1], details[2])) + "...";
							break;
						case 5: //Alpm.Package.Operation.REMOVE
							previous_filename = details[0];
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
					action = dgettext (null, "Checking delta integrity") + "...\n";
					break;
				case 19: //Alpm.Event.Type.DELTA_PATCHES_START
					action = dgettext (null, "Applying deltas") + "...\n";
					break;
				case 21: //Alpm.Event.Type.DELTA_PATCH_START
					action = dgettext (null, "Generating %s with %s").printf (details[0], details[1]) + "...\n";
					break;
				case 22: //Alpm.Event.Type.DELTA_PATCH_DONE
					action = dgettext (null, "Generation succeeded") + "...\n";
					break;
				case 23: //Alpm.Event.Type.DELTA_PATCH_FAILED
					action = dgettext (null, "Generation failed") + "...\n";
					break;
				case 24: //Alpm.Event.Type.SCRIPTLET_INFO
					// hooks output are also emitted as SCRIPTLET_INFO
					//if (previous_filename != "") {
						//stdout.printf (dgettext (null, "Configuring %s").printf (previous_filename) + "...\n");
					//}
					foreach (unowned string detail in split_string (details[0].replace ("\n", ""), 0, get_term_width ())) {
						stdout.printf ("%s\n", detail);
					}
					break;
				case 25: //Alpm.Event.Type.RETRIEVE_START
					action = dgettext (null, "Downloading") + "...\n";
					asking_user_input = false;
					break;
				case 26: //Alpm.Event.Type.RETRIEVE_DONE
				case 27: //Alpm.Event.Type.RETRIEVE_FAILED
					stdout.printf ("\n");
					break;
				case 28: //Alpm.Event.Type.PKGDOWNLOAD_START
					// special case handle differently
					string name_version_release = details[0].slice (0, details[0].last_index_of_char ('-'));
					current_action = dgettext (null, "Downloading %s").printf (name_version_release) + "...";
					break;
				case 31: //Alpm.Event.Type.DISKSPACE_START
					current_action = dgettext (null, "Checking available disk space") + "...";
					break;
				case 33: //Alpm.Event.Type.OPTDEP_REMOVAL
					action =  dgettext (null, "Warning") + ": " + dgettext (null, "%s optionally requires %s").printf (details[0], details[1]) + "\n";
					break;
				case 34: //Alpm.Event.Type.DATABASE_MISSING
					action = dgettext (null, "Database file for %s does not exist").printf (details[0]) + "\n";
					break;
				case 35: //Alpm.Event.Type.KEYRING_START
					current_action = dgettext (null, "Checking keyring") + "...";
					break;
				case 37: //Alpm.Event.Type.KEY_DOWNLOAD_START
					action = dgettext (null, "Downloading required keys") + "...\n";
					break;
				case 39: //Alpm.Event.Type.PACNEW_CREATED
					action = dgettext (null, "%s installed as %s.pacnew").printf (details[0], details[0]) + "\n";
					break;
				case 40: //Alpm.Event.Type.PACSAVE_CREATED
					action = dgettext (null, "%s installed as %s.pacsave").printf (details[0], details[0]) + "\n";
					break;
				case 41: //Alpm.Event.Type.HOOK_START
					switch (secondary_event) {
						case 1: //Alpm.HookWhen.PRE_TRANSACTION
							action = dgettext (null, "Running pre-transaction hooks") + ":\n";
							break;
						case 2: //Alpm.HookWhen.POST_TRANSACTION
							previous_filename = "";
							action = dgettext (null, "Running post-transaction hooks") + ":\n";
							break;
						default:
							break;
					}
					break;
				case 43: // Alpm.Event.Type.HOOK_RUN_START
					if (details[1] != "") {
						print_progress (details[1], "[%s/%s]".printf (details[2], details[3]), true);
					} else {
						print_progress (details[0], "[%s/%s]".printf (details[2], details[3]), true);
					}
					break;
				default:
					break;
			}
			if (action != null) {
				stdout.printf (action);
			}
		}

		void on_emit_providers (string depend, string[] providers) {
			AlpmPackage[] pkgs = {};
			foreach (unowned string pkgname in providers) {
				try {
					var pkg = user_daemon.get_sync_pkg (pkgname);
					if (pkg.name != "")  {
						pkgs += pkg;
					}
				} catch (Error e) {
					print_error (e.message);
				}
			}
			// print pkgs
			int name_length = 0;
			int version_length = 0;
			int repo_length = 0;
			foreach (unowned AlpmPackage pkg in pkgs) {
				if (pkg.name.length > name_length) {
					name_length = pkg.name.length;
				}
				if (pkg.version.length > version_length) {
					version_length = pkg.version.length;
				}
				if (pkg.repo.length > repo_length) {
					repo_length = pkg.repo.length;
				}
			}
			int num_length = providers.length.to_string ().length + 1;
			int total_width = num_length + name_length + version_length + repo_length + 4;
			int margin = 0;
			if (get_term_width () > total_width) {
				// divide available space between columns
				int available_width = get_term_width () - total_width;
				margin = available_width / 3;
				// get left space to repo
				repo_length += available_width - (margin * 3);
			}
			stdout.printf ("%s:\n".printf (dgettext (null, "Choose a provider for %s").printf (depend)));
			int num = 1;
			foreach (unowned AlpmPackage pkg in pkgs) {
				stdout.printf ("%*s %-*s %-*s %-*s \n", num_length, "%i:".printf (num),
														name_length + margin, pkg.name,
														version_length + margin, pkg.version,
														repo_length + margin, pkg.repo);
				num++;
			}
			// get user input
			asking_user_input = true;
			while (true) {
				stdout.printf ("%s: ", dgettext (null, "Enter a number (default=%d)").printf (1));
				string ans = stdin.read_line  ();
				int64 nb;
				// remvove trailing newline
				ans = ans.replace ("\n", "");
				// just return use default
				if (ans == "") {
					nb = 1;
				} else if (!int64.try_parse (ans, out nb)) {
					nb = 0;
				}
				stdout.printf ("\n");
				if (nb >= 1 && nb <= providers.length) {
					int index = (int) nb - 1;
					try {
						system_daemon.choose_provider (index);
					} catch (Error e) {
						print_error (e.message);
					}
					break;
				}
			}
		}

		void on_emit_progress (uint progress, string pkgname, uint percent, uint n_targets, uint current_target) {
			switch (progress) {
				case 0: //Alpm.Progress.ADD_START
				case 1: //Alpm.Progress.UPGRADE_START
				case 2: //Alpm.Progress.DOWNGRADE_START
				case 3: //Alpm.Progress.REINSTALL_START
				case 4: //Alpm.Progress.REMOVE_START
				case 5: //Alpm.Progress.CONFLICTS_START
				case 6: //Alpm.Progress.DISKSPACE_START
				case 7: //Alpm.Progress.INTEGRITY_START
				case 8: //Alpm.Progress.LOAD_START
				case 9: //Alpm.Progress.KEYRING_START
					if (current_action == previous_action) {
						if (percent != previous_percent) {
							previous_percent = percent;
							if (percent != 100) {
								print_progress (current_action, "[%u/%u]".printf (current_target, n_targets), false);
							} else {
								print_progress (current_action, "[%u/%u]".printf (current_target, n_targets), true);
							}
						}
					} else {
						previous_action = current_action;
						previous_percent = percent;
						if (percent != 100) {
							print_progress (current_action, "[%u/%u]".printf (current_target, n_targets), false);
						} else {
							print_progress (current_action, "[%u/%u]".printf (current_target, n_targets), true);
						}
					}
					break;
				default:
					break;
			}
		}

		void on_emit_download (string filename, uint64 xfered, uint64 total) {
			var text = new StringBuilder ();
			float fraction;
			if (total_download > 0) {
				if (xfered == 0) {
					// start download pkg is handled by Alpm.Event.Type.PKGDOWNLOAD_START
					previous_xfered = 0;
					fraction = previous_percent;
					text.append (previous_textbar);
					timer.start ();
				} else {
					if (timer.elapsed () > 0.1) {
						download_rate = ((download_rate * rates_nb) + (uint64) ((xfered - previous_xfered) / timer.elapsed ())) / (rates_nb + 1);
						rates_nb++;
					}
					previous_xfered = xfered;
					uint64 downloaded_total = xfered + already_downloaded;
					fraction = (float) downloaded_total / total_download;
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
						previous_filename = "";
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
					} else {
						// case of download pkg from url start
						string name_version_release = filename.slice (0, filename.last_index_of_char ('-'));
						current_action = dgettext (null, "Downloading %s").printf (name_version_release) + "...";
					}
				} else if (xfered == total) {
					timer.stop ();
					fraction = 1;
					previous_filename = "";
				} else {
					if (timer.elapsed () > 0.1) {
						download_rate = ((download_rate * rates_nb) + (uint64) ((xfered - previous_xfered) / timer.elapsed ())) / (rates_nb + 1);
						rates_nb++;
					}
					previous_xfered = xfered;
					fraction = (float) xfered / total;
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
			if (current_action == previous_action) {
				previous_textbar = text.str;
				// clean line
				stdout.printf ("\r%*s", get_term_width (), "");
				stdout.printf ("\r%s", text.str);
				stdout.flush ();
			} else {
				previous_action = current_action;
				// clean line
				stdout.printf ("\r%*s", get_term_width (), "");
				stdout.printf ("\r%s\n", current_action);
				stdout.printf (text.str);
				stdout.flush ();
			}
		}

		void on_emit_totaldownload (uint64 total) {
			download_rate = 0;
			rates_nb = 0;
			previous_percent = 0;
			previous_textbar = "";
			total_download = total;
			// this is emitted at the end of the total download
			// with the value 0 so stop our timer
			if (total == 0) {
				timer.stop ();
			}
		}

		void on_emit_log (uint level, string msg) {
			// msg ends with \n
			string? line = null;
			if (level == 1) { //Alpm.LogLevel.ERROR
				if (previous_filename != "") {
					line = dgettext (null, "Error") + ": " + previous_filename + ": " + msg;
				} else {
					line = dgettext (null, "Error") + ": " + msg;
				}
			} else if (level == (1 << 1)) { //Alpm.LogLevel.WARNING
				// do not show warning when manjaro-system remove db.lck
				if (previous_filename != "manjaro-system") {
					if (previous_filename != "") {
						line = dgettext (null, "Warning") + ": " + previous_filename + ": " + msg;
					} else {
						line = dgettext (null, "Warning") + ": " + msg;
					}
				}
			}
			if (line != null) {
				// keep a nice output in case of download
				stdout.printf ("\r%s", line);
				stdout.printf (previous_textbar);
				stdout.flush ();
			}
		}

		public static int main (string[] args) {
			// set dbus environment variable to allow launch in tty
			try {
				var process = new Subprocess.newv ({"dbus-launch"}, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
				var dis = new DataInputStream (process.get_stdout_pipe ());
				string? line;
				while ((line = dis.read_line ()) != null) {
					string[] splitted = line.split ("=", 2);
					unowned string key = splitted[0];
					unowned string? val = splitted[1];
					Environment.set_variable (key, val, true);
				}
			} catch (Error e) {
				stderr.printf (e.message);
			}
			var cli = new Cli();
			cli.run (args);
			return cli.cmd.get_exit_status ();
		}
	}
}

