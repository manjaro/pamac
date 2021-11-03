/*
 *  pamac-vala
 *
 *  Copyright (C) 2019-2021 Guillaume Benoit <guillaume@manjaro.org>
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
	class Cli: Object {
		public int exit_status;
		public TransactionCli transaction;
		Database database;
		bool trans_cancellable;
		bool cloning;
		Cancellable cancellable;
		GenericSet<string?> already_checked_aur_dep;
		public Subprocess pkttyagent;

		public Cli () {
			exit_status = 0;
			trans_cancellable = false;
			cloning = false;
			cancellable = new Cancellable ();
			// watch CTRl + C
			Unix.signal_add (Posix.Signal.INT, trans_cancel, Priority.HIGH);
		}

		public void parse_command_line (string[] args) {
			if (args.length == 1) {
				display_help ();
				return;
			}
			bool help = false;
			bool version = false;
			try {
				var options = new OptionEntry[2];
				options[0] = { "version", 'V', 0, OptionArg.NONE, ref version, null, null };
				options[1] = { "help", 'h', 0, OptionArg.NONE, ref help, null, null };
				var opt_context = new OptionContext (null);
				opt_context.set_help_enabled (false);
				opt_context.set_strict_posix (true);
				opt_context.add_main_entries (options, null);
				opt_context.parse (ref args);
			} catch (OptionError e) {
				display_help ();
				return;
			}
			if (help) {
				if (args.length == 2) {
					if (args[1] == "search") {
						display_search_help ();
					} else if (args[1] == "info") {
						display_info_help ();
					} else if (args[1] == "list") {
						display_list_help ();
					} else if (args[1] == "clone") {
						display_clone_help ();
					} else if (args[1] == "build") {
						display_build_help ();
					} else if (args[1] == "install") {
						display_install_help ();
					} else if (args[1] == "reinstall") {
						display_reinstall_help ();
					} else if (args[1] == "remove") {
						display_remove_help ();
					} else if (args[1] == "checkupdates") {
						display_checkupdates_help ();
					} else if (args[1] == "upgrade" || args[2] == "update") {
						display_upgrade_help ();
					} else if (args[1] == "clean") {
						display_clean_help ();
					} else {
						display_help ();
					}
				} else {
					display_help ();
				}
				return;
			}
			if (version) {
				display_version ();
				return;
			}
			if (args[1] == "search") {
				if (args.length > 2) {
					bool installed = false;
					bool repos = false;
					bool aur = false;
					bool no_aur = false;
					bool files = false;
					bool quiet = false;
					try {
						var options = new OptionEntry[7];
						options[0] = { "help", 'h', 0, OptionArg.NONE, ref help, null, null };
						options[1] = { "installed", 'i', 0, OptionArg.NONE, ref installed, null, null };
						options[2] = { "repos", 'r', 0, OptionArg.NONE, ref repos, null, null };
						options[3] = { "aur", 'a', 0, OptionArg.NONE, ref aur, null, null };
						options[4] = { "no-aur", 0, 0, OptionArg.NONE, ref no_aur, null, null };
						options[5] = { "files", 'f', 0, OptionArg.NONE, ref files, null, null };
						options[6] = { "quiet", 'q', 0, OptionArg.NONE, ref quiet, null, null };
						var opt_context = new OptionContext (null);
						opt_context.set_help_enabled (false);
						opt_context.add_main_entries (options, null);
						opt_context.parse (ref args);
					} catch (OptionError e) {
						display_search_help ();
						return;
					}
					if (help) {
						display_search_help ();
						return;
					}
					if (args.length == 2) {
						// no target
						display_search_help ();
						return;
					}
					init_database ();
					if (files) {
						search_files (args[2:args.length], quiet);
						return;
					}
					if (aur) {
						if (no_aur) {
							display_search_help ();
							return;
						}
						database.config.enable_aur = true;
					}
					if (no_aur) {
						database.config.enable_aur = false;
					}
					if (installed) {
						if (repos) {
							display_search_help ();
							return;
						} else {
							search_string = concatenate_strings (args[2:args.length]);
							search_installed_pkgs (quiet);
						}
					} else if (repos) {
						if (installed) {
							display_search_help ();
							return;
						} else {
							search_string = concatenate_strings (args[2:args.length]);
							search_repos_pkgs (quiet);
						}
					} else {
						search_string = concatenate_strings (args[2:args.length]);
						search_pkgs (quiet);
					}
				} else {
					display_search_help ();
				}
			} else if (args[1] == "info") {
				if (args.length > 2) {
					bool aur = false;
					bool no_aur = false;
					try {
						var options = new OptionEntry[3];
						options[0] = { "help", 'h', 0, OptionArg.NONE, ref help, null, null };
						options[1] = { "aur", 'a', 0, OptionArg.NONE, ref aur, null, null };
						options[2] = { "no-aur", 0, 0, OptionArg.NONE, ref no_aur, null, null };
						var opt_context = new OptionContext (null);
						opt_context.set_help_enabled (false);
						opt_context.add_main_entries (options, null);
						opt_context.parse (ref args);
					} catch (OptionError e) {
						display_info_help ();
						return;
					}
					if (help) {
						display_info_help ();
						return;
					}
					if (args.length == 2) {
						// no target
						display_info_help ();
						return;
					}
					init_database ();
					if (aur) {
						if (no_aur) {
							display_info_help ();
							return;
						}
						database.config.enable_aur = true;
					}
					if (no_aur) {
						database.config.enable_aur = false;
					}
					display_pkgs_infos (args[2:args.length]);
				} else {
					display_info_help ();
				}
			} else if (args[1] == "list") {
				if (args.length > 2) {
					bool installed = false;
					bool explicitly_installed = false;
					bool orphans = false;
					bool foreign = false;
					bool groups = false;
					bool repos = false;
					bool files = false;
					bool quiet = false;
					try {
						var options = new OptionEntry[9];
						options[0] = { "help", 'h', 0, OptionArg.NONE, ref help, null, null };
						options[1] = { "installed", 'i', 0, OptionArg.NONE, ref installed, null, null };
						options[2] = { "explicitly-installed", 'e', 0, OptionArg.NONE, ref explicitly_installed, null, null };
						options[3] = { "orphans", 'o', 0, OptionArg.NONE, ref orphans, null, null };
						options[4] = { "foreign", 'm', 0, OptionArg.NONE, ref foreign, null, null };
						options[5] = { "groups", 'g', 0, OptionArg.NONE, ref groups, null, null };
						options[6] = { "repos", 'r', 0, OptionArg.NONE, ref repos, null, null };
						options[7] = { "files", 'f', 0, OptionArg.NONE, ref files, null, null };
						options[8] = { "quiet", 'q', 0, OptionArg.NONE, ref quiet, null, null };
						var opt_context = new OptionContext (null);
						opt_context.set_help_enabled (false);
						opt_context.add_main_entries (options, null);
						opt_context.parse (ref args);
					} catch (OptionError e) {
						display_list_help ();
						return;
					}
					if (help) {
						display_list_help ();
						return;
					}
					init_database ();
					if (installed) {
						if (orphans) {
							list_orphans (quiet);
						} else if (foreign || groups || repos || files) {
							display_list_help ();
						} else {
							list_installed (quiet);
						}
					} else if (explicitly_installed) {
						if (orphans || foreign || groups || repos || files) {
							display_list_help ();
						} else {
							list_explicitly_installed (quiet);
						}
					} else if (orphans) {
						if (foreign || groups || repos || files) {
							display_list_help ();
						} else {
							list_orphans (quiet);
						}
					} else if (foreign) {
						if (orphans || groups || repos || files) {
							display_list_help ();
						} else {
							list_foreign (quiet);
						}
					} else if (groups) {
						if (installed || orphans || foreign || repos || files) {
							display_list_help ();
						} else if (args.length > 2) {
							list_groups (args[2:args.length], quiet);
						} else {
							list_groups ({}, quiet);
						}
					} else if (repos) {
						if (installed || orphans || foreign || groups || files) {
							display_list_help ();
						} else if (args.length > 2) {
							list_repos (args[2:args.length], quiet);
						} else {
							list_repos ({}, quiet);
						}
					} else if (files) {
						if (installed || orphans || foreign || groups || repos) {
							display_list_help ();
						} else if (args.length > 2) {
							list_files (args[2:args.length], quiet);
						} else {
							display_list_help ();
						}
					} else {
						stdout.printf ("%s\n",  dgettext (null, "Error"));
						display_list_help ();
					}
				} else {
					init_database ();
					list_installed (false);
				}
			} else if (args[1] == "clone") {
				if (args.length > 2) {
					bool overwrite = false;
					bool recurse = false;
					bool quiet = false;
					string? builddir = null;
					try {
						var options = new OptionEntry[5];
						options[0] = { "help", 'h', 0, OptionArg.NONE, ref help, null, null };
						options[1] = { "overwrite", 0, 0, OptionArg.NONE, ref overwrite, null, null };
						options[2] = { "recurse", 'r', 0, OptionArg.NONE, ref recurse, null, null };
						options[3] = { "builddir", 0, 0, OptionArg.STRING, ref builddir, null, null };
						options[4] = { "quiet", 'q', 0, OptionArg.NONE, ref quiet, null, null };
						var opt_context = new OptionContext (null);
						opt_context.set_help_enabled (false);
						opt_context.add_main_entries (options, null);
						opt_context.parse (ref args);
					} catch (OptionError e) {
						display_clone_help ();
						return;
					}
					if (help) {
						display_clone_help ();
						return;
					}
					if (args.length == 2) {
						// no target
						display_clone_help ();
						return;
					}
					init_database ();
					database.config.enable_aur = true;
					get_aur_dest_variable ();
					if (builddir != null) {
						database.config.aur_build_dir = builddir;
					}
					clone_build_files (args[2:args.length], overwrite, recurse, quiet);
				} else {
					display_clone_help ();
				}
			} else if (args[1] == "build") {
				bool no_clone = false;
				bool no_confirm = false;
				bool keep = false;
				bool no_keep = false;
				bool dry_run = false;
				string? builddir = null;
				if (args.length > 2) {
					try {
						var options = new OptionEntry[7];
						options[0] = { "help", 'h', 0, OptionArg.NONE, ref help, null, null };
						options[1] = { "no-clone", 0, 0, OptionArg.NONE, ref no_clone, null, null };
						options[2] = { "no-confirm", 0, 0, OptionArg.NONE, ref no_confirm, null, null };
						options[3] = { "keep", 'k', 0, OptionArg.NONE, ref keep, null, null };
						options[4] = { "no-keep", 0, 0, OptionArg.NONE, ref no_keep, null, null };
						options[5] = { "builddir", 0, 0, OptionArg.STRING, ref builddir, null, null };
						options[6] = { "dry-run", 'd', 0, OptionArg.NONE, ref dry_run, null, null };
						var opt_context = new OptionContext (null);
						opt_context.set_help_enabled (false);
						opt_context.add_main_entries (options, null);
						opt_context.parse (ref args);
					} catch (OptionError e) {
						display_build_help ();
						return;
					}
					if (help) {
						display_build_help ();
						return;
					}
				}
				init_transaction ();
				database.config.enable_aur = true;
				if (no_confirm) {
					transaction.no_confirm = true;
				}
				if (dry_run) {
					transaction.dry_run = true;
				}
				if (keep) {
					if (no_keep) {
						display_build_help ();
						return;
					}
					database.config.keep_built_pkgs = true;
				}
				if (no_keep) {
					database.config.keep_built_pkgs = false;
				}
				if (Posix.geteuid () == 0) {
					// building as root
					stdout.printf ("%s: %s\n", dgettext (null, "Warning"), dgettext (null, "Building packages as root"));
					stdout.printf ("%s: %s\n", dgettext (null, "Warning"), dgettext (null, "Setting build directory to %s").printf ("/var/cache/pamac"));
				} else {
					get_aur_dest_variable ();
					if (builddir != null) {
						database.config.aur_build_dir = builddir;
						// keep built pkgs in the custom build dir
						database.config.keep_built_pkgs = true;
					}
				}
				if (args.length == 2) {
					// no target
					var targets = new GenericArray<string> ();
					var current_dir = File.new_for_path (Environment.get_current_dir ());
					var pkgbuild = current_dir.get_child ("PKGBUILD");
					if (!pkgbuild.query_exists ()) {
						stdout.printf (dgettext (null, "No PKGBUILD file found in current directory"));
						stdout.printf ("\n");
						return;
					}
					// set buildir to the parent dir
					File? parent = current_dir.get_parent ();
					if (parent != null) {
						database.config.aur_build_dir = parent.get_path ();
						// keep built pkgs in the custom build dir
						database.config.keep_built_pkgs = true;
					}
					string? pkgbase = current_dir.get_basename ();
					if (pkgbase != null) {
						// add pkgnames of srcinfo to targets
						bool success = database.regenerate_srcinfo (pkgbase, null);
						if (success) {
							var pkgnames = new GenericArray<string> ();
							var srcinfo = current_dir.get_child (".SRCINFO");
							try {
								// read .SRCINFO
								var dis = new DataInputStream (srcinfo.read ());
								string line;
								while ((line = dis.read_line ()) != null) {
									if ("pkgname = " in line) {
										string pkgname = line.split (" = ", 2)[1];
										pkgnames.add ((owned) pkgname);
									}
								}
								foreach (unowned string name in pkgnames) {
									targets.add (name);
								}
								build_pkgs (targets.data, false, !no_clone);
							} catch (Error e) {
								warning (e.message);
							}
						}
					}
				} else if (!no_clone) {
					// check if targets exist
					var checked_targets = new GenericArray<string> ();
					bool success = check_build_pkgs (args[2:args.length], no_confirm, ref checked_targets);
					if (success) {
						build_pkgs (checked_targets.data, true, true);
					}
				} else {
					build_pkgs (args[2:args.length], false, false);
				}
			} else if (args[1] == "install") {
				if (args.length > 2) {
					bool no_confirm = false;
					bool upgrade = false;
					bool no_upgrade = false;
					bool download_only = false;
					bool as_deps = false;
					bool as_explicit = false;
					bool dry_run = false;
					string? overwrite = null;
					string? ignore = null;
					try {
						var options = new OptionEntry[10];
						options[0] = { "help", 'h', 0, OptionArg.NONE, ref help, null, null };
						options[1] = { "no-confirm", 0, 0, OptionArg.NONE, ref no_confirm, null, null };
						options[2] = { "upgrade", 0, 0, OptionArg.NONE, ref upgrade, null, null };
						options[3] = { "no-upgrade", 0, 0, OptionArg.NONE, ref no_upgrade, null, null };
						options[4] = { "download-only", 'w', 0, OptionArg.NONE, ref download_only, null, null };
						options[5] = { "as-deps", 0, 0, OptionArg.NONE, ref as_deps, null, null };
						options[6] = { "as-explicit", 0, 0, OptionArg.NONE, ref as_explicit, null, null };
						options[7] = { "overwrite", 0, 0, OptionArg.STRING, ref overwrite, null, null };
						options[8] = { "ignore", 0, 0, OptionArg.STRING, ref ignore, null, null };
						options[9] = { "dry-run", 'd', 0, OptionArg.NONE, ref dry_run, null, null };
						var opt_context = new OptionContext (null);
						opt_context.set_help_enabled (false);
						opt_context.add_main_entries (options, null);
						opt_context.parse (ref args);
					} catch (OptionError e) {
						display_install_help ();
						return;
					}
					if (help) {
						display_install_help ();
						return;
					}
					if (as_deps && as_explicit) {
						display_install_help ();
						return;
					}
					if (args.length == 2) {
						// no target
						display_install_help ();
						return;
					}
					init_transaction ();
					get_aur_dest_variable ();
					if (overwrite != null) {
						foreach (unowned string glob in overwrite.split(",")) {
							transaction.add_overwrite_file (glob);
						}
					}
					if (ignore != null) {
						foreach (unowned string name in ignore.split(",")) {
							transaction.add_temporary_ignore_pkg (name);
						}
					}
					if (no_confirm) {
						transaction.no_confirm = true;
					}
					if (dry_run) {
						transaction.dry_run = true;
					}
					if (upgrade) {
						if (no_upgrade) {
							display_install_help ();
							return;
						}
						transaction.database.config.simple_install = false;
					}
					if (no_upgrade) {
						transaction.database.config.simple_install = true;
					}
					if (download_only) {
						transaction.download_only = true;
					}
					if (as_deps) {
						transaction.install_as_dep = true;
					}
					if (as_explicit) {
						transaction.install_as_explicit = true;
					}
					install_pkgs (args[2:args.length]);
				} else {
					display_install_help ();
				}
			} else if (args[1] == "reinstall") {
				if (args.length > 2) {
					bool no_confirm = false;
					bool download_only = false;
					bool as_deps = false;
					bool as_explicit = false;
					string? overwrite = null;
					try {
						var options = new OptionEntry[6];
						options[0] = { "help", 'h', 0, OptionArg.NONE, ref help, null, null };
						options[1] = { "no-confirm", 0, 0, OptionArg.NONE, ref no_confirm, null, null };
						options[2] = { "download-only", 'w', 0, OptionArg.NONE, ref download_only, null, null };
						options[3] = { "as-deps", 0, 0, OptionArg.NONE, ref as_deps, null, null };
						options[4] = { "as-explicit", 0, 0, OptionArg.NONE, ref as_explicit, null, null };
						options[5] = { "overwrite", 0, 0, OptionArg.STRING, ref overwrite, null, null };
						var opt_context = new OptionContext (null);
						opt_context.set_help_enabled (false);
						opt_context.add_main_entries (options, null);
						opt_context.parse (ref args);
					} catch (OptionError e) {
						display_reinstall_help ();
						return;
					}
					if (help) {
						display_reinstall_help ();
						return;
					}
					if (as_deps && as_explicit) {
						display_reinstall_help ();
						return;
					}
					if (args.length == 2) {
						// no target
						display_reinstall_help ();
						return;
					}
					init_transaction ();
					if (overwrite != null) {
						foreach (unowned string glob in overwrite.split(",")) {
							transaction.add_overwrite_file (glob);
						}
					}
					if (no_confirm) {
						transaction.no_confirm = true;
					}
					if (download_only) {
						transaction.download_only = true;
					}
					if (as_deps) {
						transaction.install_as_dep = true;
					}
					if (as_explicit) {
						transaction.install_as_explicit = true;
					}
					// no upgrade because version will be checked
					transaction.database.config.simple_install = true;
					reinstall_pkgs (args[2:args.length]);
				} else {
					display_reinstall_help ();
				}
			} else if (args[1] == "remove") {
				if (args.length > 2) {
					bool no_confirm = false;
					bool no_save = false;
					bool orphans = false;
					bool no_orphans = false;
					bool unneeded = false;
					bool dry_run = false;
					try {
						var options = new OptionEntry[7];
						options[0] = { "help", 'h', 0, OptionArg.NONE, ref help, null, null };
						options[1] = { "no-confirm", 0, 0, OptionArg.NONE, ref no_confirm, null, null };
						options[2] = { "orphans", 'o', 0, OptionArg.NONE, ref orphans, null, null };
						options[3] = { "no-orphans", 0, 0, OptionArg.NONE, ref no_orphans, null, null };
						options[4] = { "unneeded", 'u', 0, OptionArg.NONE, ref unneeded, null, null };
						options[5] = { "no-save", 'n', 0, OptionArg.NONE, ref no_save, null, null };
						options[6] = { "dry-run", 'd', 0, OptionArg.NONE, ref dry_run, null, null };
						var opt_context = new OptionContext (null);
						opt_context.set_help_enabled (false);
						opt_context.add_main_entries (options, null);
						opt_context.parse (ref args);
					} catch (OptionError e) {
						display_remove_help ();
						return;
					}
					if (help) {
						display_remove_help ();
						return;
					}
					if (args.length == 2) {
						// no target
						if (orphans) {
							if (no_orphans) {
								display_remove_help ();
								return;
							}
							init_transaction ();
							if (no_confirm) {
								transaction.no_confirm = true;
							}
							remove_orphans ();
						} else {
							display_remove_help ();
						}
					} else {
						init_transaction ();
						if (no_confirm) {
							transaction.no_confirm = true;
						}
						if (dry_run) {
							transaction.dry_run = true;
						}
						if (orphans) {
							if (no_orphans) {
								display_remove_help ();
								return;
							}
							database.config.recurse = true;
						}
						if (no_orphans) {
							database.config.recurse = false;
						}
						if (unneeded) {
							transaction.remove_if_unneeded = true;
						}
						if (no_save) {
							transaction.keep_config_files = false;
						}
						remove_pkgs (args[2:args.length]);
					}
				} else {
					display_remove_help ();
				}
			} else if (args[1] == "checkupdates") {
				bool quiet = false;
				bool aur = false;
				bool no_aur = false;
				bool devel = false;
				bool no_devel = false;
				bool refresh_tmp_files_dbs = false;
				bool download_updates = false;
				bool use_timestamp = false;
				string? builddir = null;
				try {
					var options = new OptionEntry[10];
					options[0] = { "help", 'h', 0, OptionArg.NONE, ref help, null, null };
					options[1] = { "quiet", 'q', 0, OptionArg.NONE, ref quiet, null, null };
					options[2] = { "aur", 'a', 0, OptionArg.NONE, ref aur, null, null };
					options[3] = { "no-aur", 0, 0, OptionArg.NONE, ref no_aur, null, null };
					options[4] = { "devel", 0, 0, OptionArg.NONE, ref devel, null, null };
					options[5] = { "no-devel", 0, 0, OptionArg.NONE, ref no_devel, null, null };
					options[6] = { "builddir", 0, 0, OptionArg.STRING, ref builddir, null, null };
					options[7] = { "refresh-tmp-files-dbs", 0, 0, OptionArg.NONE, ref refresh_tmp_files_dbs, null, null };
					options[8] = { "download-updates", 0, 0, OptionArg.NONE, ref download_updates, null, null };
					options[9] = { "use-timestamp", 0, 0, OptionArg.NONE, ref use_timestamp, null, null };
					var opt_context = new OptionContext (null);
					opt_context.set_help_enabled (false);
					opt_context.add_main_entries (options, null);
					opt_context.parse (ref args);
				} catch (OptionError e) {
					display_checkupdates_help ();
					return;
				}
				if (help) {
					display_checkupdates_help ();
					return;
				}
				init_database ();
				if (aur) {
					if (no_aur) {
						display_checkupdates_help ();
						return;
					}
					database.config.enable_aur = true;
					database.config.check_aur_updates = true;
				}
				if (no_aur) {
					if (devel) {
						display_checkupdates_help ();
						return;
					}
					database.config.enable_aur = false;
					database.config.check_aur_updates = false;
					database.config.check_aur_vcs_updates = false;
				}
				if (devel) {
					if (no_devel) {
						display_checkupdates_help ();
						return;
					}
					database.config.check_aur_vcs_updates = true;
				}
				if (no_devel) {
					database.config.check_aur_vcs_updates = false;
				}
				if (database.config.check_aur_vcs_updates) {
					if (Posix.geteuid () == 0) {
						// checking as root
						stdout.printf ("%s: %s\n", dgettext (null, "Warning"), dgettext (null, "Checking development packages updates as root"));
						stdout.printf ("%s: %s\n", dgettext (null, "Warning"), dgettext (null, "Setting build directory to %s").printf ("/var/cache/pamac"));
					} else {
						get_aur_dest_variable ();
						if (builddir != null) {
							database.config.aur_build_dir = builddir;
						}
					}
				}
				checkupdates (quiet, refresh_tmp_files_dbs, download_updates, use_timestamp);
			} else if (args[1] == "update" || args[1] == "upgrade") {
				bool aur = false;
				bool no_aur = false;
				bool devel = false;
				bool no_devel = false;
				bool no_confirm = false;
				bool download_only = false;
				bool force_refresh = false;
				bool enable_downgrade = false;
				bool disable_downgrade = false;
				string? builddir = null;
				string? overwrite = null;
				string? ignore = null;
				try {
					var options = new OptionEntry[13];
					options[0] = { "help", 'h', 0, OptionArg.NONE, ref help, null, null };
					options[1] = { "aur", 'a', 0, OptionArg.NONE, ref aur, null, null };
					options[2] = { "no-aur", 0, 0, OptionArg.NONE, ref no_aur, null, null };
					options[3] = { "devel", 0, 0, OptionArg.NONE, ref devel, null, null };
					options[4] = { "no-devel", 0, 0, OptionArg.NONE, ref no_devel, null, null };
					options[5] = { "builddir", 0, 0, OptionArg.STRING, ref builddir, null, null };
					options[6] = { "no-confirm", 0, 0, OptionArg.NONE, ref no_confirm, null, null };
					options[7] = { "force-refresh", 0, 0, OptionArg.NONE, ref force_refresh, null, null };
					options[8] = { "enable-downgrade", 0, 0, OptionArg.NONE, ref enable_downgrade, null, null };
					options[9] = { "disable-downgrade", 0, 0, OptionArg.NONE, ref disable_downgrade, null, null };
					options[10] = { "overwrite", 0, 0, OptionArg.STRING, ref overwrite, null, null };
					options[11] = { "ignore", 0, 0, OptionArg.STRING, ref ignore, null, null };
					options[12] = { "download-only", 'w', 0, OptionArg.NONE, ref download_only, null, null };
					var opt_context = new OptionContext (null);
					opt_context.set_help_enabled (false);
					opt_context.add_main_entries (options, null);
					opt_context.parse (ref args);
				} catch (OptionError e) {
					display_upgrade_help ();
					return;
				}
				if (help) {
					display_upgrade_help ();
					return;
				}
				init_transaction ();
				if (aur) {
					if (no_aur) {
						display_upgrade_help ();
						return;
					}
					database.config.enable_aur = true;
					database.config.check_aur_updates = true;
				}
				if (no_aur) {
					if (devel) {
						display_upgrade_help ();
						return;
					}
					database.config.enable_aur = false;
					database.config.check_aur_updates = false;
					database.config.check_aur_vcs_updates = false;
				}
				if (devel) {
					if (no_devel) {
						display_upgrade_help ();
						return;
					}
					database.config.check_aur_vcs_updates = true;
				}
				if (no_devel) {
					database.config.check_aur_vcs_updates = false;
				}
				if (database.config.check_aur_updates) {
					if (Posix.geteuid () == 0) {
						// building as root
						stdout.printf ("%s: %s\n", dgettext (null, "Warning"), dgettext (null, "Building packages as root"));
						stdout.printf ("%s: %s\n", dgettext (null, "Warning"), dgettext (null, "Setting build directory to %s").printf ("/var/cache/pamac"));
					} else {
						get_aur_dest_variable ();
						if (builddir != null) {
							database.config.aur_build_dir = builddir;
						}
					}
				}
				if (enable_downgrade) {
					if (disable_downgrade) {
						display_upgrade_help ();
						return;
					}
					database.config.enable_downgrade = true;
				}
				if (disable_downgrade) {
					database.config.enable_downgrade = false;
				}
				if (ignore != null) {
					foreach (unowned string name in ignore.split(",")) {
						transaction.add_temporary_ignore_pkg (name);
					}
				}
				if (overwrite != null) {
					foreach (unowned string glob in overwrite.split(",")) {
						transaction.add_overwrite_file (glob);
					}
				}
				if (no_confirm) {
					transaction.no_confirm = true;
				}
				run_sysupgrade (force_refresh, download_only);
			} else if (args[1] == "clean") {
				bool verbose = false;
				bool build_files = false;
				bool uninstalled = false;
				bool dry_run = false;
				bool no_confirm = false;
				int64 keep = -1;
				try {
					var options = new OptionEntry[7];
					options[0] = { "help", 'h', 0, OptionArg.NONE, ref help, null, null };
					options[1] = { "verbose", 'v', 0, OptionArg.NONE, ref verbose, null, null };
					options[2] = { "build-files", 'b', 0, OptionArg.NONE, ref build_files, null, null };
					options[3] = { "no-confirm", 0, 0, OptionArg.NONE, ref no_confirm, null, null };
					options[4] = { "uninstalled", 'u', 0, OptionArg.NONE, ref uninstalled, null, null };
					options[5] = { "dry-run", 'd', 0, OptionArg.NONE, ref dry_run, null, null };
					options[6] = { "keep", 'k', 0, OptionArg.INT64, ref keep, null, null };
					var opt_context = new OptionContext (null);
					opt_context.set_help_enabled (false);
					opt_context.add_main_entries (options, null);
					opt_context.parse (ref args);
				} catch (OptionError e) {
					display_clean_help ();
					return;
				}
				if (help) {
					display_clean_help ();
					return;
				}
				init_transaction ();
				get_aur_dest_variable ();
				if (keep >= 0) {
					database.config.clean_keep_num_pkgs = keep;
				}
				if (uninstalled) {
					database.config.clean_rm_only_uninstalled = true;
				}
				if (build_files) {
					clean_build_files (dry_run, verbose, no_confirm);
				} else {
					clean_cache (dry_run, verbose, no_confirm);
				}
			} else {
				display_help ();
			}
		}

		void init_database () {
			var config = new Config ("/etc/pamac.conf");
			// not supported yet
			config.enable_snap = false;
			config.enable_flatpak = false;
			database = new Database (config);
		}

		void get_aur_dest_variable () {
			unowned string? aurdest = Environment.get_variable ("AURDEST");
			if (aurdest != null) {
				//compute absolute file path
				var aurdest_file = File.new_for_path (aurdest);
				database.config.aur_build_dir = aurdest_file.get_path ();
				database.config.keep_built_pkgs = true;
			}
		}

		void init_transaction () {
			if (database == null) {
				init_database ();
			}
			transaction = new TransactionCli (database);
			transaction.start_waiting.connect (() => {
				trans_cancellable = true;
			});
			transaction.stop_waiting.connect (() => {
				trans_cancellable = false;
			});
			transaction.start_downloading.connect (() => {
				trans_cancellable = true;
			});
			transaction.stop_downloading.connect (() => {
				trans_cancellable = false;
			});
			transaction.start_building.connect (() => {
				trans_cancellable = true;
			});
			transaction.stop_building.connect (() => {
				trans_cancellable = false;
			});
			if (Posix.geteuid () != 0) {
				// Use tty polkit authentication agent if needed
				try {
					pkttyagent = new Subprocess.newv ({"pkttyagent", "--fallback"}, SubprocessFlags.NONE);
				} catch (Error e) {
					stdout.printf ("%s: %s\n", dgettext (null, "Error"), e.message);
				}
			}
		}

		bool trans_cancel () {
			if (cloning) {
				cloning = false;
				cancellable.cancel ();
				stdout.printf ("\n");
			} else if (trans_cancellable) {
				transaction.cancel ();
			} else {
				stdout.printf ("\n");
			}
			return true;
		}

		int get_term_width () {
			int width = 80;
			Linux.winsize win;
			if (Linux.ioctl (Posix.STDOUT_FILENO, Linux.Termios.TIOCGWINSZ, out win) == 0) {
				width = win.ws_col;
			}
			return width;
		}

		string concatenate_strings_list (GenericArray<string> list) {
			var str_builder = new StringBuilder ();
			foreach (unowned string name in list) {
				if (str_builder.len > 0) {
					str_builder.append (" ");
				}
				str_builder.append (name);
			}
			return str_builder.str;
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

		GenericArray<string> split_string (string? str, int margin, int width = 0) {
			var splitted = new GenericArray<string> ();
			if (str == null)  {
				return splitted;
			}
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
				splitted.add (str);
				return splitted;
			}
			int remain_length = str_length;
			int offset = 0;
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
				splitted.add ((owned) cutted_string);
				offset += cut_length + 1;
				remain_length -= cut_length + 1;
			}
			if (remain_length > 0) {
				splitted.add (str.substring (offset, remain_length));
			}
			return splitted;
		}

		void print_aligned (string str1, string str2, int width) {
			var str_builder = new StringBuilder (str1);
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

		void print_property (string property, string val, int width) {
			GenericArray<string> cuts = split_string (val, width + 3);
			uint length = cuts.length;
			if (length > 0) {
				print_aligned (property, " : %s".printf (cuts[0]), width);
				uint i = 1;
				while (i < length) {
					print_aligned ("", cuts[i], width + 3);
					i++;
				}
			}
		}

		void print_property_list (string property, GenericArray<string> list, int width) {
			if (list.length > 0) {
				print_property (property, concatenate_strings_list (list), width);
			}
		}

		void print_error (string message) {
			stdout.printf ("%s: %s\n", dgettext (null, "Error"), message);
			exit_status = 1;
		}

		void display_version () {
			stdout.printf ("Pamac %s  -  libpamac %s\n", VERSION, Pamac.get_version ());
			stdout.printf ("Copyright © 2019-2021 Guillaume Benoit\n");
			stdout.printf ("This program is free software, you can redistribute it under the terms of the GNU GPL.\n");
		}

		void display_help () {
			string[] actions = {"--version",
								"--help, -h",
								"search",
								"list",
								"info",
								"install",
								"reinstall",
								"remove",
								"checkupdates",
								"update,upgrade",
								"clone",
								"build",
								"clean"};
			string[] options_actions = {"clean",
										"checkupdates",
										"update,upgrade",
										"search",
										"info",
										"list",
										"install",
										"reinstall",
										"build",
										"clone",
										"remove"};
			string[] targets_actions = {"search",
										"info",
										"list",
										"install",
										"reinstall",
										"build",
										"clone",
										"remove"};
			stdout.printf (dgettext (null, "Available actions") + ":\n");
			foreach (unowned string action in actions) {
				stdout.printf ("  pamac %-14s".printf (action));
				if (action == "--help, -h") {
					stdout.printf (" [%s]".printf (dgettext (null,  "action")));
				}
				if (action in options_actions) {
					stdout.printf (" [%s]".printf (dgettext (null,  "options")));
				}
				if (action in targets_actions) {
					if (action == "remove" || action == "build") {
						stdout.printf (" [%s]".printf (dgettext (null,  "package(s)")));
					} else {
						stdout.printf (" <%s>".printf (dgettext (null,  "package(s)")));
					}
				}
				stdout.printf ("\n");
			}
		}

		void display_search_help () {
			stdout.printf (dgettext (null, "Search for packages or files, multiple search terms can be specified"));
			stdout.printf ("\n\n");
			stdout.printf ("pamac search [%s] <%s>".printf (dgettext (null, "options"), "%s/%s".printf (dgettext (null, "package(s)"), dgettext (null, "file(s)"))));
			stdout.printf ("\n\n");
			stdout.printf (dgettext (null, "options") + ":\n");
			int max_length = 0;
			string[] options = {"  --installed, -i",
								"  --repos, -r",
								"  --aur, -a",
								"  --no-aur",
								"  --files, -f",
								"  --quiet, -q"};
			foreach (unowned string option in options) {
				int length = option.char_count ();
				if (length > max_length) {
					max_length = length;
				}
			}
			string[] details = {dgettext (null, "only search for installed packages"),
								dgettext (null, "only search for packages in repositories"),
								dgettext (null, "also search in AUR"),
								dgettext (null, "do not search in AUR"),
								dgettext (null, "search for packages which own the given filenames (filenames can be partial)"),
								dgettext (null, "only print names")};
			int i = 0;
			foreach (unowned string option in options) {
				print_property (option, details[i], max_length);
				i++;
			}
		}

		void display_info_help () {
			stdout.printf (dgettext (null, "Display package details, multiple packages can be specified"));
			stdout.printf ("\n\n");
			stdout.printf ("pamac info [%s] <%s>".printf (dgettext (null, "options"), dgettext (null, "package(s)")));
			stdout.printf ("\n\n");
			stdout.printf (dgettext (null, "options") + ":\n");
			int max_length = 0;
			string[] options = {"  --aur, -a",
								"  --no-aur",};
			foreach (unowned string option in options) {
				int length = option.char_count ();
				if (length > max_length) {
					max_length = length;
				}
			}
			string[] details = {dgettext (null, "also search in AUR"),
								dgettext (null, "do not search in AUR")};
			int i = 0;
			foreach (unowned string option in options) {
				print_property (option, details[i], max_length);
				i++;
			}
		}

		void display_list_help () {
			stdout.printf (dgettext (null, "List packages, groups, repositories or files"));
			stdout.printf ("\n\n");
			stdout.printf ("pamac list [%s]".printf (dgettext (null, "options")));
			stdout.printf ("\n\n");
			stdout.printf (dgettext (null, "options") + ":\n");
			int max_length = 0;
			string[] options = {"  --installed, -i",
								"  --explicitly-installed, -e",
								"  --orphans, -o",
								"  --foreign, -m",
								"  --groups, -g [%s]".printf (dgettext (null, "group(s)")),
								"  --repos, -r [%s]".printf (dgettext (null, "repo(s)")),
								"  --files, -f <%s>".printf (dgettext (null, "package(s)")),
								"  --quiet, -q"};
			foreach (unowned string option in options) {
				int length = option.char_count ();
				if (length > max_length) {
					max_length = length;
				}
			}
			string[] details = {dgettext (null, "list installed packages"),
								dgettext (null, "list explicitly installed packages"),
								dgettext (null, "list packages that were installed as dependencies but are no longer required by any installed package"),
								dgettext (null, "list packages that were not found in the repositories"),
								dgettext (null, "list all packages that are members of the given groups, if no group is given list all groups"),
								dgettext (null, "list all packages available in the given repos, if no repo is given list all repos"),
								dgettext (null, "list files owned by the given packages"),
								dgettext (null, "only print names")};
			int i = 0;
			foreach (unowned string option in options) {
				print_property (option, details[i], max_length);
				i++;
			}
		}

		void display_clone_help () {
			stdout.printf (dgettext (null, "Clone or sync packages build files from AUR"));
			stdout.printf ("\n\n");
			stdout.printf ("pamac clone [%s] <%s>".printf (dgettext (null, "options"), dgettext (null, "package(s)")));
			stdout.printf ("\n\n");
			stdout.printf (dgettext (null, "options") + ":\n");
			int max_length = 0;
			string[] options = {"  --builddir <%s>".printf (dgettext (null, "dir")),
								"  --recurse, -r",
								"  --quiet, -q",
								"  --overwrite"};
			foreach (unowned string option in options) {
				int length = option.char_count ();
				if (length > max_length) {
					max_length = length;
				}
			}
			string[] details = {dgettext (null, "build directory, if no directory is given the one specified in pamac.conf file is used"),
								dgettext (null, "also clone needed dependencies"),
								dgettext (null, "do not print any output"),
								dgettext (null, "overwrite existing files")};
			int i = 0;
			foreach (unowned string option in options) {
				print_property (option, details[i], max_length);
				i++;
			}
		}

		void display_build_help () {
			stdout.printf (dgettext (null, "Build packages from AUR and install them with their dependencies"));
			stdout.printf ("\n\n");
			stdout.printf (dgettext (null, "If no package name is given, use the PKGBUILD file in the current directory"));
			stdout.printf ("\n");
			stdout.printf (dgettext (null, "The build directory will be the parent directory, --builddir option will be ignored"));
			stdout.printf ("\n");
			stdout.printf (dgettext (null, "and --no-clone option will be enforced"));
			stdout.printf ("\n\n");
			stdout.printf ("pamac build [%s] [%s]".printf (dgettext (null, "options"), dgettext (null, "package(s)")));
			stdout.printf ("\n\n");
			stdout.printf (dgettext (null, "options") + ":\n");
			int max_length = 0;
			string[] options = {"  --builddir <%s>".printf (dgettext (null, "dir")),
								"  --keep, -k",
								"  --no-keep",
								"  --dry-run, -d",
								"  --no-clone",
								"  --no-confirm"};
			foreach (unowned string option in options) {
				int length = option.char_count ();
				if (length > max_length) {
					max_length = length;
				}
			}
			string[] details = {dgettext (null, "build directory, if no directory is given the one specified in pamac.conf file is used"),
								dgettext (null, "keep built packages in cache after installation"),
								dgettext (null, "do not keep built packages in cache after installation"),
								dgettext (null, "only print what would be done but do not run the transaction"),
								dgettext (null, "do not clone build files from AUR, only use local files"),
								dgettext (null, "bypass any and all confirmation messages")};
			int i = 0;
			foreach (unowned string option in options) {
				print_property (option, details[i], max_length);
				i++;
			}
		}

		void display_install_help () {
			stdout.printf (dgettext (null, "Install packages from repositories, path or url"));
			stdout.printf ("\n\n");
			stdout.printf ("pamac install [%s] <%s>".printf (dgettext (null, "options"), "%s,%s".printf (dgettext (null, "package(s)"), dgettext (null, "group(s)"))));
			stdout.printf ("\n\n");
			stdout.printf (dgettext (null, "options") + ":\n");
			int max_length = 0;
			string[] options = {"  --ignore <%s>".printf (dgettext (null, "package(s)")),
								"  --overwrite <%s>".printf (dgettext (null, "glob")),
								"  --download-only, -w",
								"  --dry-run, -d",
								"  --as-deps",
								"  --as-explicit",
								"  --upgrade",
								"  --no-upgrade",
								"  --no-confirm"};
			foreach (unowned string option in options) {
				int length = option.char_count ();
				if (length > max_length) {
					max_length = length;
				}
			}
			string[] details = {dgettext (null, "ignore a package upgrade, multiple packages can be specified by separating them with a comma"),
								dgettext (null, "overwrite conflicting files, multiple patterns can be specified by separating them with a comma"),
								dgettext (null, "download all packages but do not install/upgrade anything"),
								dgettext (null, "only print what would be done but do not run the transaction"),
								dgettext (null, "mark all packages installed as a dependency"),
								dgettext (null, "mark all packages explicitly installed"),
								dgettext (null, "check for updates"),
								dgettext (null, "do not check for updates"),
								dgettext (null, "bypass any and all confirmation messages")};
			int i = 0;
			foreach (unowned string option in options) {
				print_property (option, details[i], max_length);
				i++;
			}
		}

		void display_reinstall_help () {
			stdout.printf (dgettext (null, "Reinstall packages"));
			stdout.printf ("\n\n");
			stdout.printf ("pamac reinstall <%s>".printf ("%s,%s".printf (dgettext (null, "package(s)"), dgettext (null, "group(s)"))));
			stdout.printf ("\n\n");
			stdout.printf (dgettext (null, "options") + ":\n");
			int max_length = 0;
			string[] options = {"  --overwrite <%s>".printf (dgettext (null, "glob")),
								"  --download-only, -w",
								"  --as-deps",
								"  --as-explicit",
								"  --no-confirm"};
			foreach (unowned string option in options) {
				int length = option.char_count ();
				if (length > max_length) {
					max_length = length;
				}
			}
			string[] details = {dgettext (null, "overwrite conflicting files, multiple patterns can be specified by separating them with a comma"),
								dgettext (null, "download all packages but do not install/upgrade anything"),
								dgettext (null, "mark all packages installed as a dependency"),
								dgettext (null, "mark all packages explicitly installed"),
								dgettext (null, "bypass any and all confirmation messages")};
			int i = 0;
			foreach (unowned string option in options) {
				print_property (option, details[i], max_length);
				i++;
			}
		}

		void display_remove_help () {
			stdout.printf (dgettext (null, "Remove packages"));
			stdout.printf ("\n\n");
			stdout.printf ("pamac remove [%s] [%s]".printf (dgettext (null, "options"), "%s,%s".printf (dgettext (null, "package(s)"), dgettext (null, "group(s)"))));
			stdout.printf ("\n\n");
			stdout.printf (dgettext (null, "options") + ":\n");
			int max_length = 0;
			string[] options = {"  --unneeded, -u",
								"  --orphans, -o",
								"  --no-orphans",
								"  --no-save, -n",
								"  --dry-run, -d",
								"  --no-confirm"};
			foreach (unowned string option in options) {
				int length = option.char_count ();
				if (length > max_length) {
					max_length = length;
				}
			}
			string[] details = {dgettext (null, "remove packages only if they are not required by any other packages"),
								dgettext (null, "remove dependencies that are not required by other packages, if this option is used without package name remove all orphans"),
								dgettext (null, "do not remove dependencies that are not required by other packages"),
								dgettext (null, "ignore files backup"),
								dgettext (null, "only print what would be done but do not run the transaction"),
								dgettext (null, "bypass any and all confirmation messages")};
			int i = 0;
			foreach (unowned string option in options) {
				print_property (option, details[i], max_length);
				i++;
			}
		}

		void display_checkupdates_help () {
			stdout.printf (dgettext (null, "Safely check for updates without modifiying the databases"));
			stdout.printf ("\n");
			stdout.printf ("(%s)".printf (dgettext (null, "Exit code is 100 if updates are available")));
			stdout.printf ("\n\n");
			stdout.printf ("pamac checkupdates [%s]".printf (dgettext (null, "options")));
			stdout.printf ("\n\n");
			stdout.printf (dgettext (null, "options") + ":\n");
			int max_length = 0;
			string[] options = {"  --builddir <%s>".printf (dgettext (null, "dir")),
								"  --aur, -a",
								"  --no-aur",
								"  --quiet, -q",
								"  --devel",
								"  --no-devel"};
			foreach (unowned string option in options) {
				int length = option.char_count ();
				if (length > max_length) {
					max_length = length;
				}
			}
			string[] details = {dgettext (null, "build directory (use with --devel), if no directory is given the one specified in pamac.conf file is used"),
								dgettext (null, "also check updates in AUR"),
								dgettext (null, "do not check updates in AUR"),
								dgettext (null, "only print one line per update"),
								dgettext (null, "also check development packages updates (use with --aur)"),
								dgettext (null, "do not check development packages updates")};
			int i = 0;
			foreach (unowned string option in options) {
				print_property (option, details[i], max_length);
				i++;
			}
		}

		void display_upgrade_help () {
			stdout.printf (dgettext (null, "Upgrade your system"));
			stdout.printf ("\n\n");
			stdout.printf ("pamac upgrade,update [%s]".printf (dgettext (null, "options")));
			stdout.printf ("\n\n");
			stdout.printf (dgettext (null, "options") + ":\n");
			int max_length = 0;
			string[] options = {"  --force-refresh",
								"  --enable-downgrade",
								"  --disable-downgrade",
								"  --download-only, -w",
								"  --ignore <%s>".printf (dgettext (null, "package(s)")),
								"  --overwrite <%s>".printf (dgettext (null, "glob")),
								"  --no-confirm",
								"  --aur, -a",
								"  --no-aur",
								"  --devel",
								"  --no-devel",
								"  --builddir <%s>".printf (dgettext (null, "dir"))};
			foreach (unowned string option in options) {
				int length = option.char_count ();
				if (length > max_length) {
					max_length = length;
				}
			}
			string[] details = {dgettext (null, "force the refresh of the databases"),
								dgettext (null, "enable package downgrades"),
								dgettext (null, "disable package downgrades"),
								dgettext (null, "download all packages but do not install/upgrade anything"),
								dgettext (null, "ignore a package upgrade, multiple packages can be specified by separating them with a comma"),
								dgettext (null, "overwrite conflicting files, multiple patterns can be specified by separating them with a comma"),
								dgettext (null, "bypass any and all confirmation messages"),
								dgettext (null, "also upgrade packages installed from AUR"),
								dgettext (null, "do not upgrade packages installed from AUR"),
								dgettext (null, "also upgrade development packages (use with --aur)"),
								dgettext (null, "do not upgrade development packages"),
								dgettext (null, "build directory (use with --aur), if no directory is given the one specified in pamac.conf file is used")};
			int i = 0;
			foreach (unowned string option in options) {
				print_property (option, details[i], max_length);
				i++;
			}
		}

		void display_clean_help () {
			stdout.printf (dgettext (null, "Clean packages cache or build files"));
			stdout.printf ("\n\n");
			stdout.printf ("pamac clean [%s]".printf (dgettext (null, "options")));
			stdout.printf ("\n\n");
			stdout.printf (dgettext (null, "options") + ":\n");
			int max_length = 0;
			string[] options = {"  --keep, -k <%s>".printf (dgettext (null, "number")),
								"  --uninstalled, -u",
								"  --build-files, -b",
								"  --dry-run, -d",
								"  --verbose, -v",
								"  --no-confirm"};
			foreach (unowned string option in options) {
				int length = option.char_count ();
				if (length > max_length) {
					max_length = length;
				}
			}
			string[] details = {dgettext (null, "specify how many versions of each package are kept in the cache directory"),
								dgettext (null, "only target uninstalled packages"),
								dgettext (null, "remove all build files, the build directory is the one specified in pamac.conf"),
								dgettext (null, "do not remove files, only find candidate packages"),
								dgettext (null, "also display all files names"),
								dgettext (null, "bypass any and all confirmation messages")};
			int i = 0;
			foreach (unowned string option in options) {
				print_property (option, details[i], max_length);
				i++;
			}
		}

		void search_pkgs (bool quiet) {
			var pkgs = database.search_pkgs (search_string);
			if (database.config.enable_aur) {
				var aur_pkgs = database.search_aur_pkgs (search_string);
				foreach (unowned AURPackage aur_pkg in aur_pkgs) {
						pkgs.add (aur_pkg);
				}
			}
			pkgs.sort (sort_search_pkgs_by_relevance);
			print_search_pkgs (pkgs, true, quiet);
		}

		void search_installed_pkgs (bool quiet) {
			var pkgs = database.search_installed_pkgs (search_string);
			pkgs.sort (sort_search_pkgs_by_relevance);
			print_search_pkgs (pkgs, false, quiet);
		}

		void search_repos_pkgs (bool quiet) {
			var pkgs = database.search_repos_pkgs (search_string);
			pkgs.sort (sort_search_pkgs_by_relevance);
			print_search_pkgs (pkgs, true, quiet);
		}

		void print_search_pkgs (GenericArray<unowned AlpmPackage> pkgs, bool print_installed, bool quiet) {
			if (quiet) {
				// print in reverse order
				uint length = pkgs.length;
				for (uint i = 0; i < length; i++) {
					unowned AlpmPackage pkg = pkgs[i];
					stdout.printf ("%s\n", pkg.name);
				}
				return;
			}
			int version_length = 0;
			int repo_length = 0;
			foreach (unowned AlpmPackage pkg in pkgs) {
				int pkg_version_length = pkg.version.length;
				if (pkg_version_length > version_length) {
					version_length = pkg_version_length;
				}
				unowned string? repo = pkg.repo;
				if (repo != null) {
					int pkg_repo_length = repo.length;
					if (pkg_repo_length > repo_length) {
						repo_length = pkg_repo_length;
					}
				}
			}
			int available_width = get_term_width () - (version_length + repo_length + 4);
			int installed_available_width = 0;
			string installed = null;
			if (print_installed) {
				installed = "[%s]".printf (dgettext (null, "Installed"));
				installed_available_width = available_width - (installed.char_count () + 1);
			}
			// print in reverse order
			int length = pkgs.length;
			for (int i = length - 1; i >= 0; i--) {
				unowned AlpmPackage pkg = pkgs[i];
				var str_builder = new StringBuilder (pkg.name);
				str_builder.append (" ");
				int diff = 0;
				if (print_installed && pkg.installed_version != null) {
					diff = installed_available_width - pkg.name.length;
				} else {
					diff = available_width - pkg.name.length;
				}
				if (diff > 0) {
					while (diff > 0) {
						str_builder.append (" ");
						diff--;
					}
				}
				if (print_installed && pkg.installed_version != null) {
					str_builder.append (installed);
					str_builder.append (" ");
				}
				string repo = pkg.repo ?? "";
				str_builder.append ("%-*s  %s \n".printf (version_length, pkg.version, repo));
				stdout.printf (str_builder.str);
				GenericArray<string> cuts = split_string (pkg.desc, 4, available_width);
				foreach (unowned string cut in cuts) {
					print_aligned ("", cut, 4);
				}
			}
		}

		void display_pkgs_infos (string[] pkgnames) {
			string[] properties = { dgettext (null, "Name"),
									dgettext (null, "Version"),
									dgettext (null, "Description"),
									dgettext (null, "URL"),
									dgettext (null, "Licenses"),
									dgettext (null, "Repository"),
									dgettext (null, "Installed Size"),
									dgettext (null, "Groups"),
									dgettext (null, "Depends On"),
									dgettext (null, "Optional Dependencies"),
									dgettext (null, "Make Dependencies"),
									dgettext (null, "Check Dependencies"),
									dgettext (null, "Required By"),
									dgettext (null, "Optional For"),
									dgettext (null, "Provides"),
									dgettext (null, "Replaces"),
									dgettext (null, "Conflicts With"),
									dgettext (null, "Packager"),
									dgettext (null, "Build Date"),
									dgettext (null, "Install Date"),
									dgettext (null, "Install Reason"),
									dgettext (null, "Signatures"),
									dgettext (null, "Backup files"),
									dgettext (null, "Package Base"),
									dgettext (null, "Maintainer"),
									dgettext (null, "First Submitted"),
									dgettext (null, "Last Modified"),
									dgettext (null, "Votes"),
									dgettext (null, "Out of Date")};
			int max_length = 0;
			foreach (unowned string prop in properties) {
				// use char_count to handle special characters
				int char_count = prop.char_count ();
				if (char_count > max_length) {
					max_length = char_count;
				}
			}
			foreach (unowned string pkgname in pkgnames) {
				unowned AURPackage? aur_pkg = database.get_aur_pkg (pkgname);
				unowned AlpmPackage? pkg;
				if (aur_pkg == null) {
					pkg = database.get_pkg (pkgname);
					if (pkg == null) {
						print_error (dgettext (null, "target not found: %s").printf (pkgname));
					} else {
						display_pkg_infos (pkg, null, properties, max_length);
					}
				} else {
					if (aur_pkg.installed_version == null) {
						// check if pkg is available from repos
						pkg = database.get_sync_pkg (pkgname);
						if (pkg != null) {
							// we need to also display pkg
							display_pkg_infos (pkg, null, properties, max_length);
						}
						pkg = aur_pkg as AlpmPackage;
						display_pkg_infos (pkg, aur_pkg, properties, max_length);
					} else {
						// check if pkg is available from repos
						if (database.is_sync_pkg (pkgname)) {
							pkg = database.get_pkg (pkgname);
							// we only display pkg because we can't know if it was installed from repos or from AUR
							display_pkg_infos (pkg, null, properties, max_length);
						} else {
							pkg = aur_pkg as AlpmPackage;
							display_pkg_infos (pkg, aur_pkg, properties, max_length);
						}
					}
				}
			}
		}

		void display_pkg_infos (AlpmPackage? pkg, AURPackage? aur_pkg, string[] properties, int max_length) {
				// Name
				print_property (properties[0], pkg.name, max_length);
				if (aur_pkg != null) {
					// Package Base
					if (aur_pkg.packagebase != pkg.name) {
						print_property (properties[23], aur_pkg.packagebase, max_length);
					}
				}
				// Version
				unowned string installed_version = pkg.installed_version;
				if (installed_version != null) {
					print_property (properties[1], installed_version, max_length);
				} else {
					print_property (properties[1], pkg.version, max_length);
				}
				// Description
				print_property (properties[2], pkg.desc, max_length);
				// URL
				print_property (properties[3], pkg.url, max_length);
				// Licenses
				print_property (properties[4], pkg.license, max_length);
				// Repository
				if (pkg.repo != null) {
					print_property (properties[5], pkg.repo, max_length);
				}
				if (pkg.installed_size != 0){
					// Size
					print_property (properties[6], format_size (pkg.installed_size), max_length);
				}
				// Groups
				print_property_list (properties[7], pkg.groups, max_length);
				// Depends
				print_property_list (properties[8], pkg.depends, max_length);
				// Opt depends
				unowned GenericArray<string> list = pkg.optdepends;
				uint list_length = list.length;
				if (list_length != 0) {
					string depstring = list[0];
					if (database.has_installed_satisfier (depstring)) {
						depstring = "%s [%s]".printf (depstring, dgettext (null, "Installed"));
					}
					print_aligned (properties[9], " : %s".printf (depstring) , max_length);
					uint i = 1;
					while (i < list_length) {
						depstring = list[i];
						if (database.has_installed_satisfier (depstring)) {
							depstring = "%s [%s]".printf (depstring, dgettext (null, "Installed"));
						}
						print_aligned ("", depstring, max_length + 3);
						i++;
					}
				}
				// Make Depends
				if (pkg.makedepends.length != 0) {
					print_property_list (properties[10], pkg.makedepends, max_length);
				} else if (aur_pkg != null && aur_pkg.makedepends.length != 0) {
					print_property_list (properties[10], aur_pkg.makedepends, max_length);
				}
				// Check Depends
				if (pkg.checkdepends.length != 0) {
					print_property_list (properties[11], pkg.checkdepends, max_length);
				} else if (aur_pkg != null && aur_pkg.checkdepends.length != 0) {
					print_property_list (properties[11], aur_pkg.checkdepends, max_length);
				}
				// Required by
				print_property_list (properties[12], pkg.requiredby, max_length);
				// Optional for
				print_property_list (properties[13], pkg.optionalfor, max_length);
				// Provides
				print_property_list (properties[14], pkg.provides, max_length);
				// Replaces
				print_property_list (properties[15], pkg.replaces, max_length);
				// Conflicts
				print_property_list (properties[16], pkg.conflicts, max_length);
				if (pkg.packager != null) {
					// Packager
					print_property (properties[17], pkg.packager, max_length);
				}
				if (aur_pkg != null) {
					// Maintainer
					if (aur_pkg.maintainer != null) {
						print_property (properties[24], aur_pkg.maintainer, max_length);
					}
					// First Submitted
					if (aur_pkg.firstsubmitted != null) {
						print_property (properties[25], aur_pkg.firstsubmitted.format ("%x"), max_length);
					}
					// Last Modified
					if (aur_pkg.lastmodified != null) {
						print_property (properties[26], aur_pkg.lastmodified.format ("%x"), max_length);
					}
					// Votes
					if (aur_pkg.numvotes != 0) {
						print_property (properties[27], aur_pkg.numvotes.to_string (), max_length);
					}
					// Out of Date
					if (aur_pkg.outofdate != null) {
						print_property (properties[28], aur_pkg.outofdate.format ("%x"), max_length);
					}
				}
				// Build date
				if (pkg.build_date != null) {
					print_property (properties[18], pkg.build_date.format ("%x"), max_length);
				}
				// Install date
				if (pkg.install_date != null) {
					print_property (properties[19], pkg.install_date.format ("%x"), max_length);
				}
				// Reason
				if (pkg.reason != null) {
					print_property (properties[20], pkg.reason, max_length);
				}
				// Signature
				if (pkg.has_signature != null) {
					print_property (properties[21], pkg.has_signature, max_length);
				}
				// Backup files
				print_property_list (properties[22], pkg.backups, max_length);
				stdout.printf ("\n");
		}

		void print_pkgs (GenericArray<unowned AlpmPackage> pkgs, bool print_installed, bool quiet) {
			if (quiet) {
				foreach (unowned AlpmPackage pkg in pkgs) {
					stdout.printf ("%s\n", pkg.name);
				}
				return;
			}
			int name_length = 0;
			int version_length = 0;
			int repo_length = 0;
			foreach (unowned AlpmPackage pkg in pkgs) {
				int pkg_name_length = pkg.name.length;
				if (pkg_name_length > name_length) {
					name_length = pkg_name_length;
				}
				int pkg_version_length = pkg.version.length;
				if (pkg_version_length > version_length) {
					version_length = pkg_version_length;
				}
				unowned string? repo = pkg.repo;
				if (repo != null) {
					int pkg_repo_length = repo.length;
					if (pkg_repo_length > repo_length) {
						repo_length = pkg_repo_length;
					}
				}
			}
			int installed_width = 0;
			string installed = null;
			if (print_installed) {
				installed = "[%s]".printf (dgettext (null, "Installed"));
				installed_width = installed.char_count () + 1;
			}
			foreach (unowned AlpmPackage pkg in pkgs) {
				var str_builder = new StringBuilder (pkg.name);
				str_builder.append (" ");
				int diff = 0;
				if (print_installed && pkg.installed_version == null) {
					diff = name_length + installed_width - pkg.name.length;
				} else {
					diff = name_length - pkg.name.length;
				}
				if (diff > 0) {
					while (diff > 0) {
						str_builder.append (" ");
						diff--;
					}
				}
				if (print_installed && pkg.installed_version != null) {
					str_builder.append (installed);
					str_builder.append (" ");
				}
				string repo = pkg.repo ?? "";
				string installed_size;
				if (pkg.installed_size == 0) {
					installed_size = "";
				} else {
					installed_size = format_size (pkg.installed_size);
				}
				str_builder.append ("%-*s  %-*s  %s\n".printf (
									version_length, pkg.version,
									repo_length, repo,
									installed_size));
				stdout.printf (str_builder.str);
			}
		}

		void list_installed (bool quiet) {
			var pkgs = database.get_installed_pkgs ();
			print_pkgs (pkgs, false, quiet);
		}

		void list_explicitly_installed (bool quiet) {
			var pkgs = database.get_explicitly_installed_pkgs ();
			print_pkgs (pkgs, false, quiet);
		}

		void list_orphans (bool quiet) {
			var pkgs = database.get_orphans ();
			print_pkgs (pkgs, false, quiet);
		}

		void list_foreign (bool quiet) {
			var pkgs = database.get_foreign_pkgs ();
			print_pkgs (pkgs, false, quiet);
		}

		void list_groups (string[] names, bool quiet) {
			if (names.length == 0) {
				var group_names = database.get_groups_names ();
				foreach (unowned string name in group_names) {
					stdout.printf ("%s\n", name);
				}
				return;
			}
			foreach (unowned string name in names) {
				var pkgs = database.get_group_pkgs (name);
				if (pkgs == null) {
					if (!quiet) {
						print_error (dgettext (null, "target not found: %s").printf (name));
					}
				} else {
					print_pkgs (pkgs, true, quiet);
				}
				stdout.printf ("\n");
			}
		}

		void list_repos (string[] names, bool quiet) {
			if (names.length == 0) {
				var repos_names = database.get_repos_names ();
				foreach (unowned string name in repos_names) {
					stdout.printf ("%s\n", name);
				}
				return;
			}
			foreach (unowned string name in names) {
				var pkgs = database.get_repo_pkgs (name);
				if (pkgs == null) {
					if (!quiet) {
						print_error (dgettext (null, "target not found: %s").printf (name));
					}
				} else {
					print_pkgs (pkgs, true, quiet);
				}
				stdout.printf ("\n");
			}
		}

		void list_files (string[] names, bool quiet) {
			foreach (unowned string name in names) {
				var pkg = database.get_pkg (name);
				if (pkg == null) {
					if (!quiet) {
						print_error (dgettext (null, "target not found: %s").printf (name));
					}
				} else {
					var files = pkg.get_files ();
					foreach (unowned string path in files) {
						stdout.printf ("%s\n", path);
					}
					stdout.printf ("\n");
				}
			}
		}

		void search_files (string[] files, bool quiet) {
			var files_array = new GenericArray<string> ();
			foreach (unowned string file in files) {
				files_array.add (file);
			}
			HashTable<string, GenericArray<string>> result = database.search_files (files_array);
			if (result.size () == 0) {
				if (!quiet) {
					foreach (unowned string file in files) {
						stdout.printf ("%s\n", dgettext (null, "No package owns %s").printf (file));
					}
				}
				exit_status = 1;
				return;
			}
			var iter = HashTableIter<string, GenericArray<string>> (result);
			unowned string pkgname;
			unowned GenericArray<string> files_list;
			while (iter.next (out pkgname, out files_list)) {
				if (quiet) {
					stdout.printf ("%s\n", pkgname);
				} else {
					foreach (unowned string file in files_list) {
						stdout.printf ("%s\n", dgettext (null, "%s is owned by %s").printf (file, pkgname));
					}
				}
			}
		}

		void checkupdates (bool quiet, bool refresh_tmp_files_dbs, bool download_updates, bool use_timestamp) {
			var updates = database.get_updates (use_timestamp);
			uint updates_nb = updates.repos_updates.length + updates.aur_updates.length + updates.flatpak_updates.length;
			if (updates_nb == 0) {
				if (quiet) {
					return;
				}
				stdout.printf ("%s.\n", dgettext (null, "Your system is up-to-date"));
				// check if we have ignored pkgs or out of date
				uint ignored_updates_nb = updates.ignored_repos_updates.length + updates.ignored_aur_updates.length;
				if (ignored_updates_nb > 0 || updates.outofdate.length != 0) {
					int name_length = 0;
					int installed_version_length = 0;
					int version_length = 0;
					foreach (unowned AlpmPackage pkg in updates.ignored_repos_updates) {
						int pkg_name_length = pkg.name.length;
						if (pkg_name_length > name_length) {
							name_length = pkg_name_length;
						}
						int pkg_installed_version_length = pkg.installed_version.length;
						if (pkg_installed_version_length > installed_version_length) {
							installed_version_length = pkg_installed_version_length;
						}
						int pkg_version_length = pkg.version.length;
						if (pkg_version_length > version_length) {
							version_length = pkg_version_length;
						}
					}
					foreach (unowned AURPackage pkg in updates.ignored_aur_updates) {
						int pkg_name_length = pkg.name.length;
						if (pkg_name_length > name_length) {
							name_length = pkg_name_length;
						}
						int pkg_installed_version_length = pkg.installed_version.length;
						if (pkg_installed_version_length > installed_version_length) {
							installed_version_length = pkg_installed_version_length;
						}
						int pkg_version_length = pkg.version.length;
						if (pkg_version_length > version_length) {
							version_length = pkg_version_length;
						}
					}
					foreach (unowned AURPackage pkg in updates.outofdate) {
						int pkg_name_length = pkg.name.length;
						if (pkg_name_length > name_length) {
							name_length = pkg_name_length;
						}
						int pkg_version_length = pkg.version.length;
						if (pkg_version_length > version_length) {
							version_length = pkg_version_length;
						}
					}
					if (ignored_updates_nb > 0) {
						// print ignored pkgs
						string info = ngettext ("%u ignored update", "%u ignored updates", ignored_updates_nb).printf (ignored_updates_nb);
						stdout.printf ("\n%s:\n", info);
						foreach (unowned AlpmPackage pkg in updates.ignored_repos_updates) {
							stdout.printf ("%-*s  %-*s -> %-*s  %s\n",
											name_length, pkg.name,
											installed_version_length, pkg.installed_version,
											version_length, pkg.version,
											pkg.repo);
						}
						foreach (unowned AURPackage pkg in updates.ignored_aur_updates) {
							stdout.printf ("%-*s  %-*s -> %-*s  %s\n",
											name_length, pkg.name,
											installed_version_length, pkg.installed_version,
											version_length, pkg.version,
											pkg.repo);
						}
					}
					if (updates.outofdate.length != 0) {
						// print out of date pkgs
						stdout.printf ("\n%s:\n", dgettext (null, "Out of Date"));
						foreach (unowned AURPackage pkg in updates.outofdate) {
							stdout.printf ("%-*s  %-*s  %s\n",
											name_length, pkg.name,
											version_length, pkg.version,
											dgettext (null, "AUR"));
						}
					}
				}
			} else {
				// special status when updates are available
				exit_status = 100;
				// refresh tmp files dbs
				if (refresh_tmp_files_dbs) {
					database.refresh_tmp_files_dbs ();
				}
				// download updates
				if (download_updates) {
					transaction = new TransactionCli (database);
					var loop = new MainLoop ();
					transaction.download_updates_async.begin (() => {
						loop.quit ();
					});
					loop.run ();
				}
				if (quiet) {
					foreach (unowned AlpmPackage pkg in updates.repos_updates) {
						if (pkg.installed_version != null) {
							stdout.printf ("%s  %s -> %s\n", pkg.name, pkg.installed_version, pkg.version);
						} else {
							// it's a replacer
							stdout.printf ("%s  %s\n", pkg.name, pkg.version);
						}
					}
					foreach (unowned AURPackage pkg in updates.aur_updates) {
						stdout.printf ("%s  %s -> %s\n", pkg.name, pkg.installed_version, pkg.version);
					}
					foreach (unowned FlatpakPackage pkg in updates.flatpak_updates) {
						unowned string? app_name = pkg.app_name;
						if (app_name == null) {
							stdout.printf ("%s  %s\n", pkg.name, pkg.version);
						} else {
							stdout.printf ("%s  %s\n", app_name, pkg.version);
						}
					}
					return;
				}
				// print pkgs
				int name_length = 0;
				int installed_version_length = 0;
				int version_length = 0;
				foreach (unowned AlpmPackage pkg in updates.repos_updates) {
					int pkg_name_length = pkg.name.length;
					if (pkg_name_length > name_length) {
						name_length = pkg_name_length;
					}
					int pkg_installed_version_length = pkg.installed_version.length;
					if (pkg_installed_version_length > installed_version_length) {
						installed_version_length = pkg_installed_version_length;
					}
					int pkg_version_length = pkg.version.length;
					if (pkg_version_length > version_length) {
						version_length = pkg_version_length;
					}
				}
				foreach (unowned AlpmPackage pkg in updates.ignored_repos_updates) {
					int pkg_name_length = pkg.name.length;
					if (pkg_name_length > name_length) {
						name_length = pkg_name_length;
					}
					int pkg_installed_version_length = pkg.installed_version.length;
					if (pkg_installed_version_length > installed_version_length) {
						installed_version_length = pkg_installed_version_length;
					}
					int pkg_version_length = pkg.version.length;
					if (pkg_version_length > version_length) {
						version_length = pkg_version_length;
					}
				}
				foreach (unowned AURPackage pkg in updates.aur_updates) {
					int pkg_name_length = pkg.name.length;
					if (pkg_name_length > name_length) {
						name_length = pkg_name_length;
					}
					int pkg_installed_version_length = pkg.installed_version.length;
					if (pkg_installed_version_length > installed_version_length) {
						installed_version_length = pkg_installed_version_length;
					}
					int pkg_version_length = pkg.version.length;
					if (pkg_version_length > version_length) {
						version_length = pkg_version_length;
					}
				}
				foreach (unowned AURPackage pkg in updates.ignored_aur_updates) {
					int pkg_name_length = pkg.name.length;
					if (pkg_name_length > name_length) {
						name_length = pkg_name_length;
					}
					int pkg_installed_version_length = pkg.installed_version.length;
					if (pkg_installed_version_length > installed_version_length) {
						installed_version_length = pkg_installed_version_length;
					}
					int pkg_version_length = pkg.version.length;
					if (pkg_version_length > version_length) {
						version_length = pkg_version_length;
					}
				}
				foreach (unowned AURPackage pkg in updates.outofdate) {
					int pkg_name_length = pkg.name.length;
					if (pkg_name_length > name_length) {
						name_length = pkg_name_length;
					}
					int pkg_version_length = pkg.version.length;
					if (pkg_version_length > version_length) {
						version_length = pkg_version_length;
					}
				}
				foreach (unowned FlatpakPackage pkg in updates.flatpak_updates) {
					int pkg_app_name_length;
					unowned string? app_name = pkg.app_name;
					if (app_name == null) {
						pkg_app_name_length = pkg.name.length;
					} else {
						pkg_app_name_length = pkg.app_name.length;
					}
					if (pkg_app_name_length > name_length) {
						name_length = pkg_app_name_length;
					}
					int pkg_version_length = pkg.version.length;
					if (pkg_version_length > version_length) {
						version_length = pkg_version_length;
					}
				}
				string info = ngettext ("%u available update", "%u available updates", updates_nb).printf (updates_nb);
				stdout.printf ("%s:\n", info);
				foreach (unowned AlpmPackage pkg in updates.repos_updates) {
					stdout.printf ("%-*s  %-*s -> %-*s  %s\n",
									name_length, pkg.name,
									installed_version_length, pkg.installed_version,
									version_length, pkg.version,
									pkg.repo);
				}
				foreach (unowned AURPackage pkg in updates.aur_updates) {
					stdout.printf ("%-*s  %-*s -> %-*s  %s\n",
									name_length, pkg.name,
									installed_version_length, pkg.installed_version,
									version_length, pkg.version,
									dgettext (null, "AUR"));
				}
				foreach (unowned FlatpakPackage pkg in updates.flatpak_updates) {
					unowned string? app_name = pkg.app_name;
					if (app_name == null) {
						app_name = pkg.name;
					}
					stdout.printf ("%-*s  %-*s    %-*s  %s\n",
									name_length, pkg.app_name,
									installed_version_length, "",
									version_length, pkg.version,
									pkg.repo);
				}
				uint ignored_updates_nb = updates.ignored_repos_updates.length + updates.ignored_aur_updates.length;
				if (ignored_updates_nb > 0) {
					// print ignored pkgs
					info = ngettext ("%u ignored update", "%u ignored updates", ignored_updates_nb).printf (ignored_updates_nb);
					stdout.printf ("\n%s:\n", info);
					foreach (unowned AlpmPackage pkg in updates.ignored_repos_updates) {
						stdout.printf ("%-*s  %-*s -> %-*s  %s\n",
										name_length, pkg.name,
										installed_version_length, pkg.installed_version,
										version_length, pkg.version,
										pkg.repo);
					}
					foreach (unowned AURPackage pkg in updates.ignored_aur_updates) {
						stdout.printf ("%-*s  %-*s -> %-*s  %s\n",
										name_length, pkg.name,
										installed_version_length, pkg.installed_version,
										version_length, pkg.version,
										pkg.repo);
					}
				}
				if (updates.outofdate.length != 0) {
					// print out of date pkgs
					stdout.printf ("\n%s:\n", dgettext (null, "Out of Date"));
					foreach (unowned AURPackage pkg in updates.outofdate) {
						stdout.printf ("%-*s  %-*s  %s\n",
										name_length, pkg.name,
										version_length, pkg.version,
										dgettext (null, "AUR"));
					}
				}
			}
		}

		void clean_cache (bool dry_run, bool verbose, bool no_confirm) {
			HashTable<string, uint64?> details = database.get_clean_cache_details ();
			uint length = details.size ();
			if (database.config.clean_rm_only_uninstalled) {
				stdout.printf ("%s\n", dgettext (null, "Remove only the versions of uninstalled packages"));
			}
			stdout.printf ("%s: %llu\n\n", dgettext (null, "Number of versions of each package to keep in the cache"), database.config.clean_keep_num_pkgs);
			if (length == 0) {
				stdout.printf ("%s: %s\n".printf (dgettext (null, "To delete"), dngettext (null, "%u file", "%u files", length).printf (length)));
			} else {
				uint64 total_size = 0;
				var filenames = new GenericArray<unowned string> ();
				var iter = HashTableIter<string, uint64?> (details);
				unowned string filename;
				uint64? size;
				while (iter.next (out filename, out size)) {
					total_size += size;
					if (verbose) {
						filenames.add (filename);
					}
				}
				if (verbose) {
					filenames.sort (database.vercmp);
					foreach (unowned string name in filenames) {
						stdout.printf ("%s\n", name);
					}
					stdout.printf ("\n");
				}
				stdout.printf ("%s: %s  (%s)\n".printf (dgettext (null, "To delete"), dngettext (null, "%u file", "%u files", length).printf (length), format_size (total_size)));
				if (dry_run) {
					return;
				}
				if (no_confirm || transaction.ask_user (dgettext (null, "Clean cache"))) {
					var loop = new MainLoop ();
					transaction.clean_cache_async.begin (() => {
						loop.quit ();
					});
					loop.run ();
				}
			}
		}

		void clean_build_files (bool dry_run, bool verbose, bool no_confirm) {
			HashTable<string, uint64?> details = database.get_build_files_details ();
			uint length = details.size ();
			if (length == 0) {
				stdout.printf ("%s: %s\n".printf (dgettext (null, "To delete"), dngettext (null, "%u file", "%u files", length).printf (length)));
			} else {
				uint64 total_size = 0;
				var filenames = new GenericArray<unowned string> ();
				var iter = HashTableIter<string, uint64?> (details);
				unowned string filename;
				uint64? size;
				while (iter.next (out filename, out size)) {
					total_size += size;
					if (verbose) {
						filenames.add (filename);
					}
				}
				if (verbose) {
					filenames.sort (database.vercmp);
					foreach (unowned string name in filenames) {
						stdout.printf ("%s\n", name);
					}
					stdout.printf ("\n");
				}
				stdout.printf ("%s: %s  (%s)\n".printf (dgettext (null, "To delete"), dngettext (null, "%u file", "%u files", length).printf (length), format_size (total_size)));
				if (dry_run) {
					return;
				}
				if (no_confirm || transaction.ask_user (dgettext (null, "Clean build files"))) {
					var loop = new MainLoop ();
					transaction.clean_build_files_async.begin (() => {
						loop.quit ();
					});
					loop.run ();
				}
			}
		}

		void install_pkgs (string[] targets) {
			var to_install = new GenericArray<string> ();
			var to_load = new GenericArray<string> ();
			var to_build = new GenericArray<string> ();
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
								to_load.add ((owned) absolute_path);
								found = true;
							}
						} else {
							// add url in to_load, pkg will be downloaded by system_daemon
							to_load.add (target);
							found = true;
						}
					} else {
						// handle local or absolute path
						var file = File.new_for_path (target);
						string? absolute_path = file.get_path ();
						if (absolute_path != null) {
							to_load.add ((owned) absolute_path);
							found = true;
						}
					}
				} else {
					if (database.has_sync_satisfier (target)) {
						to_install.add (target);
						found = true;
					} else {
						var groupnames = database.get_groups_names ();
						if (groupnames.find_with_equal_func (target, str_equal)) {
							ask_group_confirmation (target, ref to_install);
							found = true;
						} else {
							// try glob
							GenericArray<unowned AlpmPackage> pkgs = database.get_sync_pkgs_by_glob (target);
							if (pkgs.length != 0) {
								found = true;
								foreach (unowned AlpmPackage pkg in pkgs) {
									stdout.printf ("%s\n".printf (dgettext (null, "Add %s to install").printf (pkg.name)));
									to_install.add (pkg.name);
								}
							}
						}
					}
				}
				if (!found) {
					// enable_aur is checked in database.get_aur_pkg
					AURPackage? aur_pkg = database.get_aur_pkg (target);
					if (aur_pkg != null) {
						stdout.printf ("%s: %s\n", dgettext (null, "Warning"), dgettext (null, "%s is only available from AUR").printf (target));
						to_build.add (target);
						found = true;
					}
				}
				if (!found) {
					print_error (dgettext (null, "target not found: %s").printf (target));
					return;
				}
			}
			uint to_install_length = to_install.length;
			uint to_load_length = to_load.length;
			uint to_build_length = to_build.length;
			if (to_install_length == 0 && to_load_length == 0 && to_build_length == 0) {
				stdout.printf (dgettext (null, "Nothing to do") + ".\n");
				return;
			}
			foreach (unowned string name in to_install) {
				transaction.add_pkg_to_install (name);
			}
			foreach (unowned string path in to_load) {
				transaction.add_path_to_load (path);
			}
			foreach (unowned string name in to_build) {
				transaction.add_pkg_to_build (name, true, true);
			}
			run_transaction ();
		}

		void ask_group_confirmation (string grpname, ref GenericArray<string> to_install) {
			var pkgs = database.get_group_pkgs (grpname);
			if (transaction.no_confirm) {
				foreach (unowned AlpmPackage pkg in pkgs) {
					to_install.add (pkg.name);
				}
				return;
			}
			// print pkgs
			int name_length = 0;
			int version_length = 0;
			foreach (unowned AlpmPackage pkg in pkgs) {
				int pkg_name_length = pkg.name.length;
				if (pkg_name_length > name_length) {
					name_length = pkg_name_length;
				}
				int pkg_version_length = pkg.version.length;
				if (pkg_version_length > version_length) {
					version_length = pkg_version_length;
				}
			}
			uint pkgs_length = pkgs.length;
			int num_length = pkgs_length.to_string ().length + 1;
			stdout.printf ("%s:\n".printf (dngettext (null, "There is %1$u member in group %2$s",
						"There are %1$u members in group %2$s", pkgs_length).printf (pkgs_length, grpname)));
			int num = 1;
			foreach (unowned AlpmPackage pkg in pkgs) {
				stdout.printf ("%*s  %-*s  %-*s  %s\n",
								num_length, "%i:".printf (num),
								name_length, pkg.name,
								version_length, pkg.version,
								pkg.repo);
				num++;
			}
			// get user input
			while (true) {
				stdout.printf ("\n");
				stdout.printf ("%s: ", dgettext (null, "Enter a selection (default=%s)").printf (dgettext (null, "all")));
				stdout.flush ();
				Posix.tcflush (stdin.fileno (), Posix.TCIFLUSH);
				string? ans = stdin.read_line ();
				if (ans == null) {
					break;
				}
				uint nb;
				var numbers = new GenericArray<uint> ();
				// remvove trailing newline
				ans = ans.replace ("\n", "");
				// just return use default
				if (ans == "") {
					foreach (unowned AlpmPackage pkg in pkgs) {
						to_install.add (pkg.name);
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
							uint beg_num, end_num;
							if (uint.try_parse (splitted2[0], out beg_num)) {
								if (uint.try_parse (splitted2[1], out end_num)) {
									nb = beg_num;
									while (nb <= end_num) {
										if (nb >= 1 && nb <= pkgs_length) {
											numbers.add (nb);
										}
										nb++;
									}
								}
							}
						} else if (uint.try_parse (part, out nb)) {
							if (nb >= 1 && nb <= pkgs_length) {
								numbers.add (nb);
							}
						}
					}
				}
				if (numbers.length > 0) {
					foreach (unowned uint number in numbers) {
						to_install.add (pkgs[number - 1].name);
					}
					break;
				}
			}
			stdout.printf ("\n");
		}

		void reinstall_pkgs (string[] names) {
			var to_install = new GenericArray<string> ();
			foreach (unowned string name in names) {
				bool found = false;
				unowned string? version = null;
				var local_pkg = database.get_installed_pkg (name);
				if (local_pkg != null) {
					version = local_pkg.version;
					var sync_pkg = database.get_sync_pkg (name);
					if (sync_pkg != null) {
						if (local_pkg.version == sync_pkg.version) {
							to_install.add (name);
							found = true;
						}
					}
				} else {
					var groupnames = database.get_groups_names ();
					if (groupnames.find_with_equal_func (name, str_equal)) {
						found = true;
						var pkgs = database.get_group_pkgs (name);
						foreach (unowned AlpmPackage pkg in pkgs) {
							if (pkg.version == pkg.installed_version) {
								to_install.add (pkg.name);
							}
						}
					} else {
						// try glob
						GenericArray<unowned AlpmPackage> pkgs = database.get_installed_pkgs_by_glob (name);
						if (pkgs.length != 0) {
							found = true;
							foreach (unowned AlpmPackage pkg in pkgs) {
								var sync_pkg = database.get_sync_pkg (pkg.name);
								if (sync_pkg != null) {
									if (pkg.version == sync_pkg.version) {
										stdout.printf ("%s\n".printf (dgettext (null, "Add %s to reinstall").printf (pkg.name)));
										to_install.add (pkg.name);
										found = true;
									}
								}
							}
						}
					}
				}
				if (!found) {
					if (version == null) {
						print_error (dgettext (null, "target not found: %s").printf (name));
					} else {
						print_error (dgettext (null, "target not found: %s").printf (name + "-" + version));
					}
					return;
				}
			}
			uint to_install_length = to_install.length;
			if (to_install_length == 0) {
				stdout.printf (dgettext (null, "Nothing to do") + ".\n");
				return;
			}
			foreach (unowned string name in to_install) {
				transaction.add_pkg_to_install (name);
			}
			transaction.install_if_needed = false;
			run_transaction ();
		}

		void remove_pkgs (string[] names) {
			var to_remove = new GenericArray<string> ();
			bool group_found = false;
			foreach (unowned string name in names) {
				bool found = false;
				if (database.is_installed_pkg (name)) {
					to_remove.add (name);
					found = true;
				} else {
					var groupnames = database.get_groups_names ();
					if (groupnames.find_with_equal_func (name, str_equal)) {
						found = true;
						var pkgs = database.get_group_pkgs (name);
						foreach (unowned AlpmPackage pkg in pkgs) {
							if (pkg.version == pkg.installed_version) {
								to_remove.add (pkg.name);
								group_found = true;
							}
						}
					} else {
						// try glob
						GenericArray<unowned AlpmPackage> pkgs = database.get_installed_pkgs_by_glob (name);
						if (pkgs.length != 0) {
							found = true;
							foreach (unowned AlpmPackage pkg in pkgs) {
								stdout.printf ("%s\n".printf (dgettext (null, "Add %s to remove").printf (pkg.name)));
								to_remove.add (pkg.name);
							}
						}
					}
				}
				if (!found) {
					print_error (dgettext (null, "target not found: %s").printf (name));
					return;
				}
			}
			uint to_remove_length = to_remove.length;
			if (to_remove_length == 0) {
				stdout.printf (dgettext (null, "Nothing to do") + ".\n");
				return;
			}
			if (group_found) {
				transaction.remove_if_unneeded = true;
			}
			foreach (unowned string name in to_remove) {
				transaction.add_pkg_to_remove (name);
			}
			run_transaction ();
		}

		void remove_orphans () {
			var pkgs = database.get_orphans ();
			foreach (unowned AlpmPackage pkg in pkgs) {
				transaction.add_pkg_to_remove (pkg.name);
			}
			database.config.recurse = true;
			run_transaction ();
		}

		void clone_build_files (string[] pkgnames, bool overwrite, bool recurse, bool quiet) {
			already_checked_aur_dep = new GenericSet<string?> (str_hash, str_equal);
			var pkgnames_array = new GenericArray<string> ();
			foreach (unowned string pkgname in pkgnames) {
				pkgnames_array.add (pkgname);
			}
			cloning = true;
			clone_build_files_real (pkgnames_array, overwrite, recurse, quiet);
			cloning = false;
		}

		void clone_build_files_real (GenericArray<string> pkgnames, bool overwrite, bool recurse, bool quiet) {
			var dep_to_check = new GenericArray<string> ();
			var aur_pkgs = database.get_aur_pkgs (pkgnames);
			var iter = HashTableIter<string, unowned AURPackage?> (aur_pkgs);
			unowned string pkgname;
			unowned AURPackage? aur_pkg;
			while (iter.next (out pkgname, out aur_pkg)) {
				if (aur_pkg == null) {
					if (!quiet) {
						print_error (dgettext (null, "target not found: %s").printf (pkgname));
					}
					continue;
				} else {
					// clone build files
					if (!quiet) {
						stdout.printf (dgettext (null, "Cloning %s build files".printf (pkgname)) + "...\n");
					}
					// use packagebase in case of split package
					File? clone_dir = database.clone_build_files (aur_pkg.packagebase, overwrite, cancellable);
					if (clone_dir == null) {
						// error
						return;
					} else if (cancellable.is_cancelled ()) {
						return;
					} else if (recurse) {
						// check deps
						foreach (unowned string dep_string in aur_pkg.depends) {
							AlpmPackage? pkg = null;
							if (database.has_installed_satisfier (dep_string)) {
								pkg = database.get_installed_satisfier (dep_string);
							} else if (database.has_sync_satisfier (dep_string)) {
								pkg = database.get_sync_satisfier (dep_string);
							}
							if (pkg == null) {
								string dep_name = database.get_alpm_dep_name (dep_string);
								if (!(dep_name in already_checked_aur_dep)) {
									already_checked_aur_dep.add (dep_name);
									dep_to_check.add ((owned) dep_name);
								}
							}
						}
						foreach (unowned string dep_string in aur_pkg.makedepends) {
							AlpmPackage? pkg = null;
							if (database.has_installed_satisfier (dep_string)) {
								pkg = database.get_installed_satisfier (dep_string);
							} else if (database.has_sync_satisfier (dep_string)) {
								pkg = database.get_sync_satisfier (dep_string);
							}
							if (pkg == null) {
								string dep_name = database.get_alpm_dep_name (dep_string);
								if (!(dep_name in already_checked_aur_dep)) {
									already_checked_aur_dep.add (dep_name);
									dep_to_check.add ((owned) dep_name);
								}
							}
						}
						foreach (unowned string dep_string in aur_pkg.checkdepends) {
							AlpmPackage? pkg = null;
							if (database.has_installed_satisfier (dep_string)) {
								pkg = database.get_installed_satisfier (dep_string);
							} else if (database.has_sync_satisfier (dep_string)) {
								pkg = database.get_sync_satisfier (dep_string);
							}
							if (pkg == null) {
								string dep_name = database.get_alpm_dep_name (dep_string);
								if (!(dep_name in already_checked_aur_dep)) {
									already_checked_aur_dep.add (dep_name);
									dep_to_check.add ((owned) dep_name);
								}
							}
						}
					}
				}
			}
			if (cancellable.is_cancelled ()) {
				return;
			}
			if (dep_to_check.length > 0) {
				clone_build_files_real (dep_to_check, overwrite, recurse, quiet);
			}
		}

		bool check_build_pkgs (string[] targets, bool no_confirm, ref GenericArray<string> checked_targets) {
			var real_targets = new GenericArray<string> ();
			var not_found = new HashTable<unowned string, unowned string?> (str_hash, str_equal);
			foreach (unowned string target in targets) {
				if (!no_confirm) {
					var sync_pkg = database.get_sync_pkg (target);
					if (sync_pkg != null) {
						if (transaction.ask_user (dgettext (null, "Install %s from %s").printf (target, sync_pkg.repo))) {
							transaction.add_pkg_to_install (sync_pkg.name);
							continue;
						}
					}
				}
				real_targets.add (target);
				// populate not found and remove them when found
				not_found.replace (target, target);
			}
			var aur_pkgs = database.get_aur_pkgs (real_targets);
			var aur_pkgs_iter = HashTableIter<string, unowned AURPackage?> (aur_pkgs);
			unowned string pkgname;
			unowned AURPackage? aur_pkg;
			while (aur_pkgs_iter.next (out pkgname, out aur_pkg)) {
				if (aur_pkg != null) {
					checked_targets.add (pkgname);
					not_found.remove (pkgname);
				}
			}
			if (not_found.length > 0) {
				var not_found_iter = HashTableIter<unowned string, unowned string?> (not_found);
				unowned string target;
				while (not_found_iter.next (out target, null)) {
					// may be a virtual package
					// use search and add results
					var search_aur_pkgs = database.search_aur_pkgs (target);
					bool iter_removed = false;
					foreach (unowned AURPackage found_pkg in search_aur_pkgs) {
						foreach (unowned string dep_string in found_pkg.provides) {
							string dep_name = database.get_alpm_dep_name (dep_string);
							if (dep_name == target) {
								checked_targets.add (target);
								if (!iter_removed) {
									not_found_iter.remove ();
									iter_removed = true;
								}
							}
							break;
						}
					}
				}
			}
			if (not_found.length > 0) {
				var not_found_iter = HashTableIter<unowned string, unowned string?> (not_found);
				unowned string target;
				while (not_found_iter.next (out target, null)) {
					print_error (dgettext (null, "target not found: %s").printf (target));
				}
				return false;
			}
			return true;
		}

		void build_pkgs (string[] names, bool clone_build_files, bool clone_deps_build_files) {
			foreach (unowned string name in names) {
				transaction.add_pkg_to_build (name, clone_build_files, clone_deps_build_files);
			}
			transaction.install_if_needed = false;
			run_transaction ();
		}

		void run_transaction () {
			var loop = new MainLoop ();
			if (Posix.geteuid () != 0) {
				// let's time to pkttyagent to get registred
				Timeout.add (200, () => {
					transaction.run_async.begin ((obj, res) => {
						bool success = transaction.run_async.end (res);
						if (!success) {
							exit_status = 1;
						}
						loop.quit ();
					});
					return false;
				});
			} else {
				transaction.run_async.begin ((obj, res) => {
					bool success = transaction.run_async.end (res);
					if (!success) {
						exit_status = 1;
					}
					loop.quit ();
				});
			}
			loop.run ();
		}

		void run_sysupgrade (bool force_refresh, bool download_only) {
			if (download_only) {
				transaction.download_only = true; //Alpm.TransFlag.DOWNLOADONLY
			}
			transaction.add_pkgs_to_upgrade (force_refresh);
			run_transaction ();
		}

		public static int main (string[] args) {
			// i18n
			Intl.textdomain ("pamac");
			Intl.setlocale (LocaleCategory.ALL, "");
			// run
			var cli = new Cli();
			cli.parse_command_line (args);
			// stop system_daemon
			if (cli.transaction != null) {
				cli.transaction.quit_daemon ();
			}
			if (cli.pkttyagent != null) {
				cli.pkttyagent.force_exit ();
			}
			return cli.exit_status;
		}
	}

	string search_string;

	int sort_search_pkgs_by_relevance (Pamac.Package pkg_a, Pamac.Package pkg_b) {
		if (search_string != null) {
			// display exact match first
			if (pkg_a.name == search_string) {
				if (pkg_b.name == search_string) {
					return sort_pkgs_by_relevance (pkg_a, pkg_b);
				}
				return -1;
			}
			if (pkg_b.name == search_string) {
				return 1;
			}
			if (pkg_a.name.has_prefix (search_string + "-")) {
				if (pkg_b.name.has_prefix (search_string + "-")) {
					return sort_pkgs_by_relevance (pkg_a, pkg_b);
				}
				return -1;
			}
			if (pkg_b.name.has_prefix (search_string + "-")) {
				return 1;
			}
			if (pkg_a.name.has_prefix (search_string)) {
				if (pkg_b.name.has_prefix (search_string)) {
					return sort_pkgs_by_relevance (pkg_a, pkg_b);
				}
				return -1;
			}
			if (pkg_b.name.has_prefix (search_string)) {
				return 1;
			}
			if (pkg_a.name.contains (search_string)) {
				if (pkg_b.name.contains (search_string)) {
					return sort_pkgs_by_relevance (pkg_a, pkg_b);
				}
				return -1;
			}
			if (pkg_b.name.contains (search_string)) {
				return 1;
			}
		}
		return sort_pkgs_by_relevance (pkg_a, pkg_b);
	}

	int sort_pkgs_by_relevance (Package pkg_a, Package pkg_b) {
		if (pkg_a.installed_version == null) {
			if (pkg_b.installed_version == null) {
				return sort_pkgs_by_name (pkg_a, pkg_b);
			}
			return 1;
		}
		if (pkg_b.installed_version == null) {
			return -1;
		}
		return sort_pkgs_by_name (pkg_a, pkg_b);
	}

	int sort_pkgs_by_name (Package pkg_a, Package pkg_b) {
		string str_a = pkg_a.name.collate_key ();
		string str_b = pkg_b.name.collate_key ();
		return strcmp (str_a, str_b);
	}
}

