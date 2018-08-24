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
	class Cli: GLib.Application {
		public ApplicationCommandLine cmd;
		public TransactionCli transaction;
		public Database database;
		delegate void TransactionAction ();
		string[] to_install;
		string[] to_remove;
		string[] to_load;
		string[] to_build;
		bool force_refresh;
		bool enable_downgrade;
		string[] temporary_ignorepkgs;
		string[] overwrite_files;
		Subprocess pkttyagent;

		public Cli () {
			application_id = "org.manjaro.pamac.cli";
			flags = ApplicationFlags.HANDLES_COMMAND_LINE;
			to_install = {};
			to_remove = {};
			to_load = {};
			to_build = {};
			force_refresh = false;
			enable_downgrade = false;
			overwrite_files = {};
			var config = new Config ("/etc/pamac.conf");
			database = new Database (config);
			transaction = new TransactionCli (database);
			transaction.finished.connect (on_transaction_finished);
			transaction.sysupgrade_finished.connect (on_transaction_finished);
			transaction.refresh_finished.connect (on_refresh_finished);
			// Use tty polkit authentication agent
			try {
				pkttyagent = new Subprocess.newv ({"pkttyagent"}, SubprocessFlags.NONE);
			} catch (Error e) {
				stdout.printf ("%s: %s\n", dgettext (null, "Error"), e.message);
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
						transaction.database.config.aur_build_dir = args[3];
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
						transaction.database.config.enable_aur = true;
						transaction.database.config.check_aur_updates = true;
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
						transaction.database.config.enable_aur = true;
						transaction.database.config.check_aur_updates = true;
					} else if (arg == "--builddir") {
						transaction.database.config.aur_build_dir = args[i+1];
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
					try_lock_and_run (start_refresh);
				}
			} else {
				display_help ();
			}
			return cmd.get_exit_status ();
		}

		public override void shutdown () {
			base.shutdown ();
			database.stop_daemon ();
			transaction.stop_daemon ();
			pkttyagent.force_exit ();
		}

		bool trans_cancel () {
			if (transaction.asking_user_input) {
				transaction.release ();
			} else {
				transaction.cancel ();
			}
			stdout.printf ("\n");
			this.release ();
			cmd.set_exit_status (1);
			return false;
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
			int term_width = transaction.get_term_width ();
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

		void print_error (string message) {
			stdout.printf ("%s: %s\n", dgettext (null, "Error"), message);
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
			var pkgs = database.search_pkgs (search_string);
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
			int available_width = transaction.get_term_width () - (version_length + repo_length + 3);
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
		}

		void search_in_aur (string search_string) {
			this.hold ();
			database.search_in_aur_async.begin (search_string, (obj,res) => {
				AURPackage[] pkgs = database.search_in_aur_async.end (res);
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
				int available_width = transaction.get_term_width () - (version_length + aur_length + 3);
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
				var details =  database.get_pkg_details (pkgname, "");
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
					satisfier = database.find_installed_satisfier (depstring);
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
						satisfier = database.find_installed_satisfier (depstring);
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
				database.get_aur_details_async.begin (pkgname, (obj, res) => {
					var details = database.get_aur_details_async.end (res);
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
						satisfier = database.find_installed_satisfier (depstring);
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
							satisfier = database.find_installed_satisfier (depstring);
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
			if (transaction.get_term_width () > total_width) {
				// divide available space between columns
				int available_width = transaction.get_term_width () - total_width;
				margin = available_width / 4;
				// get left space to size
				size_length += available_width - (margin * 4);
			}
			foreach (unowned AlpmPackage pkg in pkgs) {
				// use this code to correctly aligned text with special characters
				var str_builder = new StringBuilder ();
				string name = pkg.name;
				if (print_installed && pkg.installed_version != "") {
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
			var pkgs = database.get_installed_pkgs ();
			print_pkgs (pkgs, false);
		}

		void list_orphans () {
			var pkgs = database.get_orphans ();
			print_pkgs (pkgs, false);
		}

		void list_foreign () {
			var pkgs = database.get_foreign_pkgs ();
			print_pkgs (pkgs, false);
		}

		void list_groups (string[] names) {
			if (names.length == 0) {
				string[] grpnames = database.get_groups_names ();
				foreach (unowned string name in grpnames) {
					stdout.printf ("%s\n", name);
				}
				return;
			}
			foreach (unowned string name in names) {
				var pkgs = database.get_group_pkgs (name);
				if (pkgs.length == 0) {
					print_error (dgettext (null, "target not found: %s").printf (name));
				} else {
					print_pkgs (pkgs, true);
				}
				stdout.printf ("\n");
			}
		}

		void list_repos (string[] names) {
			if (names.length == 0) {
				string[] grpnames = database.get_repos_names ();
				foreach (unowned string name in grpnames) {
					stdout.printf ("%s\n", name);
				}
				return;
			}
			foreach (unowned string name in names) {
				var pkgs = database.get_repo_pkgs (name);
				if (pkgs.length == 0) {
					print_error (dgettext (null, "target not found: %s").printf (name));
				} else {
					print_pkgs (pkgs, true);
				}
				stdout.printf ("\n");
			}
		}

		void list_files (string[] names) {
			foreach (unowned string name in names) {
				string[] files = database.get_pkg_files (name);
				if (files.length == 0) {
					print_error (dgettext (null, "target not found: %s").printf (name));
				} else {
					foreach (unowned string path in files) {
						stdout.printf ("%s\n", path);
					}
				}
				stdout.printf ("\n");
			}
		}

		void search_files (string[] files) {
			HashTable<string, Variant> result = database.search_files (files);
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
		}

		void checkupdates () {
			this.hold ();
			database.start_get_updates ();
			database.get_updates_finished.connect (on_get_updates_finished);
		}

		void on_get_updates_finished (Updates updates) {
			database.get_updates_finished.disconnect (on_get_updates_finished);
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
				if (transaction.get_term_width () > total_width) {
					// divide available space between columns
					int available_width = transaction.get_term_width () - total_width;
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
					var pkg = database.find_sync_satisfier (target);
					if (pkg.name != "") {
						to_install += target;
						found = true;
					} else {
						string[] groupnames = database.get_groups_names ();
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
			if (to_install.length == 0 && to_load.length == 0) {
				stdout.printf (dgettext (null, "Nothing to do") + ".\n");
				return;
			}
			// do not install a package if it is already installed and up to date
			transaction.flags = (1 << 13); //Alpm.TransFlag.NEEDED
			try_lock_and_run (start_transaction);
		}

		void ask_group_confirmation (string grpname) {
			var pkgs = database.get_group_pkgs (grpname);
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
			if (transaction.get_term_width () > total_width) {
				// divide available space between columns
				int available_width = transaction.get_term_width () - total_width;
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
			transaction.asking_user_input = true;
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
		}

		void reinstall_pkgs (string[] names) {
			foreach (unowned string name in names) {
				bool found = false;
				string version = "";
				var local_pkg = database.get_installed_pkg (name);
				if (local_pkg.name != "") {
					version = local_pkg.version;
					var sync_pkg = database.get_sync_pkg (name);
					if (sync_pkg.name != "") {
						if (local_pkg.version == sync_pkg.version) {
							to_install += name;
							found = true;
						}
					}
				} else {
					string[] groupnames = database.get_groups_names ();
					if (name in groupnames) {
						found = true;
						var pkgs = database.get_group_pkgs (name);
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
			if (to_install.length == 0) {
				stdout.printf (dgettext (null, "Nothing to do") + ".\n");
				return;
			}
			try_lock_and_run (start_transaction);
		}

		void remove_pkgs (string[] names, bool recurse = false) {
			bool group_found = false;
			foreach (unowned string name in names) {
				bool found = false;
				var local_pkg = database.get_installed_pkg (name);
				if (local_pkg.name != "") {
					to_remove += name;
					found = true;
				} else {
					string[] groupnames = database.get_groups_names ();
					if (name in groupnames) {
						found = true;
						var pkgs = database.get_group_pkgs (name);
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
			if (to_remove.length == 0) {
				stdout.printf (dgettext (null, "Nothing to do") + ".\n");
				return;
			}
			if (group_found) {
				transaction.flags = (1 << 15); //Alpm.TransFlag.UNNEEDED
			} else {
				transaction.flags = (1 << 4); //Alpm.TransFlag.CASCADE
			}
			if (recurse) {
				transaction.flags |= (1 << 5); //Alpm.TransFlag.RECURSE
			}
			try_lock_and_run (start_transaction);
		}

		void remove_orphans () {
			var pkgs = database.get_orphans ();
			foreach (unowned AlpmPackage pkg in pkgs) {
				to_remove += pkg.name;
			}
			transaction.flags = (1 << 4); //Alpm.TransFlag.CASCADE
			transaction.flags |= (1 << 5); //Alpm.TransFlag.RECURSE
			try_lock_and_run (start_transaction);
		}

		void build_pkgs (string[] to_build) {
			this.to_build = to_build;
			try_lock_and_run (start_transaction);
		}

		void start_transaction () {
			this.hold ();
			transaction.start (to_install, to_remove, to_load, to_build, overwrite_files);
		}

		void try_lock_and_run (TransactionAction action) {
			if (transaction.get_lock ()) {
				action ();
			} else {
				stdout.printf (dgettext (null, "Waiting for another package manager to quit") + "...\n");
				this.hold ();
				Timeout.add (5000, () => {
					bool locked = transaction.get_lock ();
					if (locked) {
						this.release ();
						action ();
					}
					return !locked;
				});
			}
		}

		void start_refresh () {
			this.hold ();
			// let's time to pkttyagent to get registred
			Timeout.add (200, () => {
				transaction.start_refresh (force_refresh);
				return false;
			});
		}

		void on_refresh_finished (bool success) {
			if (success) {
				transaction.start_sysupgrade (enable_downgrade, temporary_ignorepkgs, overwrite_files);
			} else {
				transaction.unlock ();
				this.release ();
				cmd.set_exit_status (1);
			}
		}

		void on_transaction_finished (bool success) {
			transaction.unlock ();
			this.release ();
			if (!success) {
				cmd.set_exit_status (1);
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

