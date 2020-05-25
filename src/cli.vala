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
					display_pkg_infos (args[2:args.length]);
				} else {
					display_info_help ();
				}
			} else if (args[1] == "list") {
				if (args.length > 2) {
					bool installed = false;
					bool orphans = false;
					bool foreign = false;
					bool groups = false;
					bool repos = false;
					bool files = false;
					bool quiet = false;
					try {
						var options = new OptionEntry[8];
						options[0] = { "help", 'h', 0, OptionArg.NONE, ref help, null, null };
						options[1] = { "installed", 'i', 0, OptionArg.NONE, ref installed, null, null };
						options[2] = { "orphans", 'o', 0, OptionArg.NONE, ref orphans, null, null };
						options[3] = { "foreign", 'm', 0, OptionArg.NONE, ref foreign, null, null };
						options[4] = { "groups", 'g', 0, OptionArg.NONE, ref groups, null, null };
						options[5] = { "repos", 'r', 0, OptionArg.NONE, ref repos, null, null };
						options[6] = { "files", 'f', 0, OptionArg.NONE, ref files, null, null };
						options[7] = { "quiet", 'q', 0, OptionArg.NONE, ref quiet, null, null };
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
				if (Posix.geteuid () == 0) {
					// can't build as root
					stdout.printf ("%s: %s\n", dgettext (null, "Error"), dgettext (null, "Building packages as root is not allowed"));
					exit_status = 1;
					return;
				}
				init_transaction ();
				database.config.enable_aur = true;
				if (no_clone) {
					transaction.clone_build_files = false;
				}
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
				if (builddir != null) {
					database.config.aur_build_dir = builddir;
					// keep built pkgs in the custom build dir
					database.config.keep_built_pkgs = true;
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
					// set no clone is required
					transaction.clone_build_files = false;
					// set buildir to the parent dir
					File? parent = current_dir.get_parent ();
					if (parent != null) {
						database.config.aur_build_dir = parent.get_path ();
					}
					string? pkgbase = current_dir.get_basename ();
					if (pkgbase != null) {
						// add pkgnames of srcinfo to targets
						bool success = database.regenerate_srcinfo (pkgbase, null);
						if (success) {
							var srcinfo_pkgnames = database.get_srcinfo_pkgnames (pkgbase);
							foreach (unowned string name in srcinfo_pkgnames) {
								targets.add (name);
							}
						}
					}
					build_pkgs (targets.data);
					return;
				} else if (transaction.clone_build_files) {
					// check if targets exist
					bool success = check_build_pkgs (args[2:args.length]);
					if (!success) {
						return;
					}
				}
				build_pkgs (args[2:args.length]);
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
					install_pkgs (args[2:args.length], download_only, as_deps, as_explicit);
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
					// no upgrade because version will be checked
					transaction.database.config.simple_install = true;
					reinstall_pkgs (args[2:args.length], download_only, as_deps, as_explicit);
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
						remove_pkgs (args[2:args.length], unneeded, no_save);
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
				string? builddir = null;
				try {
					var options = new OptionEntry[9];
					options[0] = { "help", 'h', 0, OptionArg.NONE, ref help, null, null };
					options[1] = { "quiet", 'q', 0, OptionArg.NONE, ref quiet, null, null };
					options[2] = { "aur", 'a', 0, OptionArg.NONE, ref aur, null, null };
					options[3] = { "no-aur", 0, 0, OptionArg.NONE, ref no_aur, null, null };
					options[4] = { "devel", 0, 0, OptionArg.NONE, ref devel, null, null };
					options[5] = { "no-devel", 0, 0, OptionArg.NONE, ref no_devel, null, null };
					options[6] = { "builddir", 0, 0, OptionArg.STRING, ref builddir, null, null };
					options[7] = { "refresh-tmp-files-dbs", 0, 0, OptionArg.NONE, ref refresh_tmp_files_dbs, null, null };
					options[8] = { "download-updates", 0, 0, OptionArg.NONE, ref download_updates, null, null };
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
						// can't check as root
						stdout.printf ("%s: %s\n", dgettext (null, "Warning"), dgettext (null, "Check development packages updates as root is not allowed"));
						database.config.check_aur_vcs_updates = false;
					} else {
						if (builddir != null) {
							database.config.aur_build_dir = builddir;
						}
					}
				}
				checkupdates (quiet, refresh_tmp_files_dbs, download_updates);
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
						// can't build as root
						stdout.printf ("%s: %s\n", dgettext (null, "Warning"), dgettext (null, "Building packages as root is not allowed") + "\n");
						database.config.enable_aur = false;
						database.config.check_aur_updates = false;
						database.config.check_aur_vcs_updates = false;
					} else {
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
					options[4] = { "uninstalled", 0, 0, OptionArg.NONE, ref uninstalled, null, null };
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
			#if ENABLE_SNAP
			config.enable_snap = false;
			#endif
			database = new Database (config);
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
				// Use tty polkit authentication agent
				try {
					pkttyagent = new Subprocess.newv ({"pkttyagent"}, SubprocessFlags.NONE);
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

		string concatenate_strings_list (SList<string> list) {
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

		GenericArray<string> split_string (string str, int margin, int width = 0) {
			var splitted = new GenericArray<string> ();
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

		void print_error (string message) {
			stdout.printf ("%s: %s\n", dgettext (null, "Error"), message);
			exit_status = 1;
		}

		void display_version () {
			stdout.printf ("Pamac  %s\n", VERSION);
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
				GenericArray<string> cuts = split_string (details[i], max_length + 3);
				print_aligned (option, " : %s".printf (cuts[0]), max_length);
				int j = 1;
				uint cuts_length = cuts.length;
				while (j < cuts_length) {
					print_aligned ("", "%s".printf (cuts[j]), max_length + 3);
					j++;
				}
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
				GenericArray<string> cuts = split_string (details[i], max_length + 3);
				print_aligned (option, " : %s".printf (cuts[0]), max_length);
				int j = 1;
				uint cuts_length = cuts.length;
				while (j < cuts_length) {
					print_aligned ("", "%s".printf (cuts[j]), max_length + 3);
					j++;
				}
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
								dgettext (null, "list packages that were installed as dependencies but are no longer required by any installed package"),
								dgettext (null, "list packages that were not found in the repositories"),
								dgettext (null, "list all packages that are members of the given groups, if no group is given list all groups"),
								dgettext (null, "list all packages available in the given repos, if no repo is given list all repos"),
								dgettext (null, "list files owned by the given packages"),
								dgettext (null, "only print names")};
			int i = 0;
			foreach (unowned string option in options) {
				GenericArray<string> cuts = split_string (details[i], max_length + 3);
				print_aligned (option, " : %s".printf (cuts[0]), max_length);
				int j = 1;
				uint cuts_length = cuts.length;
				while (j < cuts_length) {
					print_aligned ("", "%s".printf (cuts[j]), max_length + 3);
					j++;
				}
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
				GenericArray<string> cuts = split_string (details[i], max_length + 3);
				print_aligned (option, " : %s".printf (cuts[0]), max_length);
				int j = 1;
				uint cuts_length = cuts.length;
				while (j < cuts_length) {
					print_aligned ("", "%s".printf (cuts[j]), max_length + 3);
					j++;
				}
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
				GenericArray<string> cuts = split_string (details[i], max_length + 3);
				print_aligned (option, " : %s".printf (cuts[0]), max_length);
				int j = 1;
				uint cuts_length = cuts.length;
				while (j < cuts_length) {
					print_aligned ("", "%s".printf (cuts[j]), max_length + 3);
					j++;
				}
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
				GenericArray<string> cuts = split_string (details[i], max_length + 3);
				print_aligned (option, " : %s".printf (cuts[0]), max_length);
				int j = 1;
				uint cuts_length = cuts.length;
				while (j < cuts_length) {
					print_aligned ("", "%s".printf (cuts[j]), max_length + 3);
					j++;
				}
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
				GenericArray<string> cuts = split_string (details[i], max_length + 3);
				print_aligned (option, " : %s".printf (cuts[0]), max_length);
				int j = 1;
				uint cuts_length = cuts.length;
				while (j < cuts_length) {
					print_aligned ("", "%s".printf (cuts[j]), max_length + 3);
					j++;
				}
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
				GenericArray<string> cuts = split_string (details[i], max_length + 3);
				print_aligned (option, " : %s".printf (cuts[0]), max_length);
				int j = 1;
				uint cuts_length = cuts.length;
				while (j < cuts_length) {
					print_aligned ("", "%s".printf (cuts[j]), max_length + 3);
					j++;
				}
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
				GenericArray<string> cuts = split_string (details[i], max_length + 3);
				print_aligned (option, " : %s".printf (cuts[0]), max_length);
				int j = 1;
				uint cuts_length = cuts.length;
				while (j < cuts_length) {
					print_aligned ("", "%s".printf (cuts[j]), max_length + 3);
					j++;
				}
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
				GenericArray<string> cuts = split_string (details[i], max_length + 3);
				print_aligned (option, " : %s".printf (cuts[0]), max_length);
				int j = 1;
				uint cuts_length = cuts.length;
				while (j < cuts_length) {
					print_aligned ("", "%s".printf (cuts[j]), max_length + 3);
					j++;
				}
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
				GenericArray<string> cuts = split_string (details[i], max_length + 3);
				print_aligned (option, " : %s".printf (cuts[0]), max_length);
				int j = 1;
				uint cuts_length = cuts.length;
				while (j < cuts_length) {
					print_aligned ("", "%s".printf (cuts[j]), max_length + 3);
					j++;
				}
				i++;
			}
		}

		void search_pkgs (bool quiet) {
			var pkgs = database.search_pkgs (search_string);
			// pkgs are already sorted by relevance
			if (database.config.enable_aur) {
				var aur_pkgs = database.search_aur_pkgs (search_string);
				foreach (unowned AURPackage aur_pkg in aur_pkgs) {
					if (aur_pkg.installed_version == "") {
						pkgs.prepend (aur_pkg);
					}
				}
				// sort here with AUR packages
				pkgs.sort (sort_search_pkgs_by_relevance);
			}
			print_search_pkgs (pkgs, true, quiet);
		}

		void search_installed_pkgs (bool quiet) {
			var pkgs = database.search_installed_pkgs (search_string);
			// pkgs are already sorted by relevance
			pkgs.reverse ();
			print_search_pkgs (pkgs, false, quiet);
		}

		void search_repos_pkgs (bool quiet) {
			var pkgs = database.search_repos_pkgs (search_string);
			// pkgs are already sorted by relevance
			pkgs.reverse ();
			print_search_pkgs (pkgs, true, quiet);
		}

		void print_search_pkgs (SList<Package> pkgs, bool print_installed, bool quiet) {
			if (quiet) {
				foreach (unowned Package pkg in pkgs) {
					stdout.printf ("%s\n", pkg.name);
				}
				return;
			}
			int version_length = 0;
			int repo_length = 0;
			foreach (unowned Package pkg in pkgs) {
				int pkg_version_length = pkg.version.length;
				if (pkg_version_length > version_length) {
					version_length = pkg_version_length;
				}
				int pkg_repo_length = pkg.repo.length;
				if (pkg_repo_length > repo_length) {
					repo_length = pkg_repo_length;
				}
			}
			int available_width = get_term_width () - (version_length + repo_length + 4);
			int installed_available_width = 0;
			string installed = null;
			if (print_installed) {
				installed = "[%s]".printf (dgettext (null, "Installed"));
				installed_available_width = available_width - (installed.char_count () + 1);
			}
			foreach (unowned Package pkg in pkgs) {
				var str_builder = new StringBuilder (pkg.name);
				str_builder.append (" ");
				int diff = 0;
				if (print_installed && pkg.installed_version != "") {
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
				if (print_installed && pkg.installed_version != "") {
					str_builder.append (installed);
					str_builder.append (" ");
				}
				str_builder.append ("%-*s  %s \n".printf (version_length, pkg.version, pkg.repo));
				stdout.printf (str_builder.str);
				GenericArray<string> cuts = split_string (pkg.desc, 4, available_width);
				uint cuts_length = cuts.length;
				for (uint j = 0; j < cuts_length; j++) {
					print_aligned ("", cuts[j], 4);
				}
			}
		}

		void display_pkg_infos (string[] pkgnames) {
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
				AURPackage? aur_pkg = database.get_aur_pkg (pkgname);
				AlpmPackage? pkg;
				if (aur_pkg == null) {
					pkg = database.get_pkg (pkgname);
				} else {
					pkg = aur_pkg as AlpmPackage;
				}
				if (pkg == null) {
					print_error (dgettext (null, "target not found: %s").printf (pkgname));
					continue;
				}
				// Name
				print_aligned (properties[0], ": %s".printf (pkg.name), max_length);
				if (aur_pkg != null) {
					// Package Base
					if (aur_pkg.packagebase != pkg.name) {
						print_aligned (properties[23], ": %s".printf (aur_pkg.packagebase), max_length);
					}
				}
				// Version
				print_aligned (properties[1], ": %s".printf (pkg.version), max_length);
				// Description
				GenericArray<string> cuts = split_string (pkg.desc, max_length + 2);
				print_aligned (properties[2], ": %s".printf (cuts[0]), max_length);
				int i = 1;
				uint cuts_length = cuts.length;
				while (i < cuts_length) {
					print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
					i++;
				}
				// URL
				print_aligned (properties[3], ": %s".printf (pkg.url), max_length);
				// Licenses
				unowned SList<string> list;
				if (pkg.licenses != null) {
					list = pkg.licenses;
					print_aligned (properties[4], ": %s".printf (list.data), max_length);
					list = list.next;
					while (list != null) {
						print_aligned ("", "%s".printf (list.data), max_length + 2);
						list = list.next;
					}
				}
				// Repository
				if (pkg.repo != "") {
					print_aligned (properties[5], ": %s".printf (pkg.repo), max_length);
				}
				if (pkg.installed_size != 0){
					// Size
					print_aligned (properties[6], ": %s".printf (format_size (pkg.installed_size)), max_length);
				}
				// Groups
				if (pkg.groups != null) {
					cuts = split_string (concatenate_strings_list (pkg.groups), max_length + 2);
					print_aligned (properties[7], ": %s".printf (cuts[0]), max_length);
					i = 1;
					cuts_length = cuts.length;
					while (i < cuts_length) {
						print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
						i++;
					}
				}
				// Depends
				if (pkg.depends != null) {
					cuts = split_string (concatenate_strings_list (pkg.depends), max_length + 2);
					print_aligned (properties[8], ": %s".printf (cuts[0]), max_length);
					i = 1;
					cuts_length = cuts.length;
					while (i < cuts_length) {
						print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
						i++;
					}
				}
				// Opt depends
				if (pkg.optdepends != null) {
					list = pkg.optdepends;
					string depstring = list.data;
					if (database.has_installed_satisfier (depstring)) {
						depstring = "%s [%s]".printf (depstring, dgettext (null, "Installed"));
					}
					cuts = split_string (depstring, max_length + 2);
					print_aligned (properties[9], ": %s".printf (cuts[0]), max_length);
					i = 1;
					cuts_length = cuts.length;
					while (i < cuts_length) {
						print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
						i++;
					}
					list = list.next;
					while (list != null) {
						depstring = list.data;
						if (database.has_installed_satisfier (depstring)) {
							depstring = "%s [%s]".printf (depstring, dgettext (null, "Installed"));
						}
						cuts = split_string (depstring, max_length + 2);
						i = 0;
						cuts_length = cuts.length;
						while (i < cuts_length) {
							print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
							i++;
						}
						list = list.next;
					}
				}
				if (aur_pkg != null) {
					// Make Depends
					if (aur_pkg.makedepends != null) {
						cuts = split_string (concatenate_strings_list (aur_pkg.makedepends), max_length + 2);
						print_aligned (properties[10], ": %s".printf (cuts[0]), max_length);
						i = 1;
						cuts_length = cuts.length;
						while (i < cuts_length) {
							print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
							i++;
						}
					}
					// Check Depends
					if (aur_pkg.checkdepends != null) {
						cuts = split_string (concatenate_strings_list (aur_pkg.checkdepends), max_length + 2);
						print_aligned (properties[11], ": %s".printf (cuts[0]), max_length);
						i = 1;
						cuts_length = cuts.length;
						while (i < cuts_length) {
							print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
							i++;
						}
					}
				}
				// Required by
				if (pkg.requiredby != null) {
					cuts = split_string (concatenate_strings_list (pkg.requiredby), max_length + 2);
					print_aligned (properties[12], ": %s".printf (cuts[0]), max_length);
					i = 1;
					cuts_length = cuts.length;
					while (i < cuts_length) {
						print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
						i++;
					}
				}
				// Optional for
				if (pkg.optionalfor != null) {
					cuts = split_string (concatenate_strings_list (pkg.optionalfor), max_length + 2);
					print_aligned (properties[13], ": %s".printf (cuts[0]), max_length);
					i = 1;
					cuts_length = cuts.length;
					while (i < cuts_length) {
						print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
						i++;
					}
				}
				// Provides
				if (pkg.provides != null) {
					cuts = split_string (concatenate_strings_list (pkg.provides), max_length + 2);
					print_aligned (properties[14], ": %s".printf (cuts[0]), max_length);
					i = 1;
					cuts_length = cuts.length;
					while (i < cuts_length) {
						print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
						i++;
					}
				}
				// Replaces
				if (pkg.replaces != null) {
					cuts = split_string (concatenate_strings_list (pkg.replaces), max_length + 2);
					print_aligned (properties[15], ": %s".printf (cuts[0]), max_length);
					i = 1;
					cuts_length = cuts.length;
					while (i < cuts_length) {
						print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
						i++;
					}
				}
				// Conflicts
				if (pkg.conflicts != null) {
					cuts = split_string (concatenate_strings_list (pkg.conflicts), max_length + 2);
					print_aligned (properties[16], ": %s".printf (cuts[0]), max_length);
					i = 1;
					cuts_length = cuts.length;
					while (i < cuts_length) {
						print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
						i++;
					}
				}
				if (pkg.packager != "") {
					// Packager
					cuts = split_string (pkg.packager, max_length + 2);
					print_aligned (properties[17], ": %s".printf (cuts[0]), max_length);
					i = 1;
					cuts_length = cuts.length;
					while (i < cuts_length) {
						print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
						i++;
					}
				}
				if (aur_pkg != null) {
					// Maintainer
					if (aur_pkg.maintainer != "") {
						print_aligned (properties[24], ": %s".printf (aur_pkg.maintainer), max_length);
					}
					// First Submitted
					if (aur_pkg.firstsubmitted != 0) {
						var time = GLib.Time.local ((time_t) aur_pkg.firstsubmitted);
						print_aligned (properties[25], ": %s".printf (time.format ("%x")), max_length);
					}
					// Last Modified
					if (aur_pkg.lastmodified != 0) {
						var time = GLib.Time.local ((time_t) aur_pkg.lastmodified);
						print_aligned (properties[26], ": %s".printf (time.format ("%x")), max_length);
					}
					// Votes
					if (aur_pkg.numvotes != 0) {
						print_aligned (properties[27], ": %s".printf (aur_pkg.numvotes.to_string ()), max_length);
					}
					// Out of Date
					if (aur_pkg.outofdate != 0) {
						var time = GLib.Time.local ((time_t) aur_pkg.outofdate);
						print_aligned (properties[28], ": %s".printf (time.format ("%x")), max_length);
					}
				}
				// Build date
				if (pkg.builddate != 0) {
					var time = GLib.Time.local ((time_t) pkg.builddate);
					print_aligned (properties[18], ": %s".printf (time.format ("%x")), max_length);
				}
				// Install date
				if (pkg.installdate != 0) {
					var time = GLib.Time.local ((time_t) pkg.installdate);
					print_aligned (properties[19], ": %s".printf (time.format ("%x")), max_length);
				}
				// Reason
				if (pkg.reason != "") {
					cuts = split_string (pkg.reason, max_length + 2);
					print_aligned (properties[20], ": %s".printf (cuts[0]), max_length);
					i = 1;
					cuts_length = cuts.length;
					while (i < cuts_length) {
						print_aligned ("", "%s".printf (cuts[i]), max_length + 2);
						i++;
					}
				}
				// Signature
				if (pkg.has_signature != "") {
					print_aligned (properties[21], ": %s".printf (pkg.has_signature), max_length);
				}
				// Backup files
				if (pkg.backups != null) {
					list = pkg.backups;
					print_aligned (properties[22], ": %s".printf (list.data), max_length);
					list = list.next;
					while (list != null) {
						print_aligned ("", "%s".printf (list.data), max_length + 2);
						list = list.next;
					}
				}
				stdout.printf ("\n");
			}
		}

		void print_pkgs (SList<AlpmPackage> pkgs, bool print_installed, bool quiet) {
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
				int pkg_repo_length = pkg.repo.length;
				if (pkg_repo_length > repo_length) {
					repo_length = pkg_repo_length;
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
				if (print_installed && pkg.installed_version == "") {
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
				if (print_installed && pkg.installed_version != "") {
					str_builder.append (installed);
					str_builder.append (" ");
				}
				str_builder.append ("%-*s  %-*s  %s\n".printf (
									version_length, pkg.version,
									repo_length, pkg.repo,
									format_size (pkg.installed_size)));
				stdout.printf (str_builder.str);
			}
		}

		void list_installed (bool quiet) {
			var pkgs = database.get_installed_pkgs ();
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
				var files = database.get_pkg_files (name);
				if (files == null) {
					if (!quiet) {
						print_error (dgettext (null, "target not found: %s").printf (name));
					}
				} else {
					foreach (unowned string path in files) {
						stdout.printf ("%s\n", path);
					}
				}
				stdout.printf ("\n");
			}
		}

		void search_files (string[] files, bool quiet) {
			HashTable<string, SList<string>> result = database.search_files (files);
			if (result.size () == 0) {
				if (!quiet) {
					foreach (unowned string file in files) {
						stdout.printf ("%s\n", dgettext (null, "No package owns %s").printf (file));
					}
				}
				exit_status = 1;
				return;
			}
			var iter = HashTableIter<string, SList<string>> (result);
			unowned string pkgname;
			unowned SList<string> files_list;
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

		void checkupdates (bool quiet, bool refresh_tmp_files_dbs, bool download_updates) {
			var updates = database.get_updates ();
			uint updates_nb = updates.repos_updates.length () + updates.aur_updates.length ();
			#if ENABLE_FLATPAK
			updates_nb += updates.flatpak_updates.length ();
			#endif
			if (updates_nb == 0) {
				if (quiet) {
					return;
				}
				stdout.printf ("%s.\n", dgettext (null, "Your system is up-to-date"));
				if (updates.outofdate != null) {
					// print out of date pkgs
					stdout.printf ("\n%s:\n", dgettext (null, "Out of Date"));
					int name_length = 0;
					int version_length = 0;
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
					foreach (unowned AURPackage pkg in updates.outofdate) {
						stdout.printf ("%-*s  %-*s  %s\n",
										name_length, pkg.name,
										version_length, pkg.version,
										dgettext (null, "AUR"));
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
					transaction.download_updates ();
				}
				if (quiet) {
					foreach (unowned AlpmPackage pkg in updates.repos_updates) {
						if (pkg.installed_version != "") {
							stdout.printf ("%s  %s -> %s\n", pkg.name, pkg.installed_version, pkg.version);
						} else {
							// it's a replacer
							stdout.printf ("%s  %s\n", pkg.name, pkg.version);
						}
					}
					foreach (unowned AURPackage pkg in updates.aur_updates) {
						stdout.printf ("%s  %s -> %s\n", pkg.name, pkg.installed_version, pkg.version);
					}
					#if ENABLE_FLATPAK
					foreach (unowned FlatpakPackage pkg in updates.flatpak_updates) {
						stdout.printf ("%s  %s\n", pkg.app_name, pkg.version);
					}
					#endif
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
				#if ENABLE_FLATPAK
				foreach (unowned FlatpakPackage pkg in updates.flatpak_updates) {
					int pkg_app_name_length = pkg.app_name.length;
					if (pkg_app_name_length > name_length) {
						name_length = pkg_app_name_length;
					}
					int pkg_version_length = pkg.version.length;
					if (pkg_version_length > version_length) {
						version_length = pkg_version_length;
					}
				}
				#endif
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
				#if ENABLE_FLATPAK
				foreach (unowned FlatpakPackage pkg in updates.flatpak_updates) {
					stdout.printf ("%-*s  %-*s    %-*s  %s\n",
									name_length, pkg.app_name,
									installed_version_length, "",
									version_length, pkg.version,
									pkg.repo);
				}
				#endif
				uint ignored_updates_nb = updates.ignored_repos_updates.length () + updates.ignored_aur_updates.length ();
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
				if (updates.outofdate != null) {
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

		bool ask_user (string question) {
			// ask user confirmation
			stdout.printf ("%s %s ", question, dgettext (null, "[y/N]"));
			char buf[32];
			if (stdin.gets (buf) != null) {
				string ans = (string) buf;
				// remove trailing newline and uppercase
				ans = ans.replace ("\n", "").down ();
				// just return use default
				if (ans != "") {
					if (ans == dgettext (null, "y") ||
						ans == dgettext (null, "yes") ||
						ans == "y" ||
						ans == "yes") {
						return true;
					}
				}
			}
			return false;
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
					uint filenames_length = filenames.length;
					for (uint i = 0; i < filenames_length; i++) {
						stdout.printf ("%s\n", filenames[i]);
					}
					stdout.printf ("\n");
				}
				stdout.printf ("%s: %s  (%s)\n".printf (dgettext (null, "To delete"), dngettext (null, "%u file", "%u files", length).printf (length), format_size (total_size)));
				if (dry_run) {
					return;
				}
				if (no_confirm || ask_user ("%s ?".printf (dgettext (null, "Clean cache")))) {
					transaction.clean_cache ();
				}
			}
		}

		void clean_build_files (bool dry_run, bool verbose, bool no_confirm) {
			HashTable<string, uint64?> details = database.get_build_files_details ();
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
					uint filenames_length = filenames.length;
					for (uint i = 0; i < filenames_length; i++) {
						stdout.printf ("%s\n", filenames[i]);
					}
					stdout.printf ("\n");
				}
				stdout.printf ("%s: %s  (%s)\n".printf (dgettext (null, "To delete"), dngettext (null, "%u file", "%u files", length).printf (length), format_size (total_size)));
				if (dry_run) {
					return;
				}
				if (no_confirm || ask_user ("%s ?".printf (dgettext (null, "Clean build files")))) {
					transaction.clean_build_files ();
				}
			}
		}

		void install_pkgs (string[] targets, bool download_only, bool as_deps, bool as_explicit) {
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
						if (groupnames.find_custom (target, strcmp) != null) {
							ask_group_confirmation (target, ref to_install);
							found = true;
						} else {
							// try glob
							SList<AlpmPackage> pkgs = database.get_sync_pkgs_by_glob (target);
							if (pkgs != null) {
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
						if (!transaction.no_confirm && ask_user ("%s ?".printf (dgettext (null, "Build %s from AUR").printf (target)))) {
							stdout.printf ("\n");
							to_build.add (target);
							found = true;
						}
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
			// do not install a package if it is already installed and up to date
			int flags = (1 << 13); //Alpm.TransFlag.NEEDED
			if (download_only) {
				flags |= (1 << 9); //Alpm.TransFlag.DOWNLOADONLY
			}
			if (as_deps) {
				flags |= (1 << 8); //Alpm.TransFlag.ALLDEPS
			} else if (as_explicit) {
				flags |= (1 << 14); //Alpm.TransFlag.ALLEXPLICIT
			}
			transaction.set_flags (flags);
			uint i;
			for (i = 0; i < to_install_length; i++) {
				transaction.add_pkg_to_install (to_install[i]);
			}
			for (i = 0; i < to_load_length; i++) {
				transaction.add_path_to_load (to_load[i]);
			}
			for (i = 0; i < to_build_length; i++) {
				transaction.add_aur_pkg_to_build (to_build[i]);
			}
			if (Posix.geteuid () != 0) {
				var loop = new MainLoop ();
				// let's time to pkttyagent to get registred
				Timeout.add (200, () => {
					run_transaction ();
					loop.quit ();
					return false;
				});
				loop.run ();
			} else {
				run_transaction ();
			}
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
			uint pkgs_length = pkgs.length ();
			int num_length = pkgs_length.to_string ().length + 1;
			stdout.printf ("%s:\n".printf (dngettext (null, "There is %u member in group %s",
						"There are %u members in group %s", pkgs_length).printf (pkgs_length, grpname)));
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
				string? ans = stdin.read_line ();
				if (ans == null) {
					break;
				}
				uint64 nb;
				uint64[] numbers = {};
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
							int64 beg_num, end_num;
							if (int64.try_parse (splitted2[0], out beg_num)) {
								if (int64.try_parse (splitted2[1], out end_num)) {
									nb = beg_num;
									while (nb <= end_num) {
										if (nb >= 1 && nb <= pkgs_length) {
											numbers += nb;
										}
										nb++;
									}
								}
							}
						} else if (uint64.try_parse (part, out nb)) {
							if (nb >= 1 && nb <= pkgs_length) {
								numbers += nb;
							}
						}
					}
				}
				if (numbers.length > 0) {
					uint64 index = 1;
					foreach (unowned AlpmPackage pkg in pkgs) {
						if (index in numbers) {
							to_install.add (pkg.name);
						}
						index++;
					}
					break;
				}
			}
			stdout.printf ("\n");
		}

		void reinstall_pkgs (string[] names, bool download_only, bool as_deps, bool as_explicit) {
			var to_install = new GenericArray<string> ();
			foreach (unowned string name in names) {
				bool found = false;
				string version = "";
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
					if (groupnames.find_custom (name, strcmp) != null) {
						found = true;
						var pkgs = database.get_group_pkgs (name);
						foreach (unowned AlpmPackage pkg in pkgs) {
							if (pkg.version == pkg.installed_version) {
								to_install.add (pkg.name);
							}
						}
					} else {
						// try glob
						SList<AlpmPackage> pkgs = database.get_installed_pkgs_by_glob (name);
						if (pkgs != null) {
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
					if (version == "") {
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
			for (uint i = 0; i < to_install_length; i++) {
				transaction.add_pkg_to_install (to_install[i]);
			}
			int flags = 0;
			if (download_only) {
				flags |= (1 << 9); //Alpm.TransFlag.DOWNLOADONLY
			}
			if (as_deps) {
				flags |= (1 << 8); //Alpm.TransFlag.ALLDEPS
			} else if (as_explicit) {
				flags |= (1 << 14); //Alpm.TransFlag.ALLEXPLICIT
			}
			transaction.set_flags (flags);
			if (Posix.geteuid () != 0) {
				var loop = new MainLoop ();
				// let's time to pkttyagent to get registred
				Timeout.add (200, () => {
					run_transaction ();
					loop.quit ();
					return false;
				});
				loop.run ();
			} else {
				run_transaction ();
			}
		}

		void remove_pkgs (string[] names, bool unneeded, bool no_save) {
			var to_remove = new GenericArray<string> ();
			bool group_found = false;
			foreach (unowned string name in names) {
				bool found = false;
				if (database.is_installed_pkg (name)) {
					to_remove.add (name);
					found = true;
				} else {
					var groupnames = database.get_groups_names ();
					if (groupnames.find_custom (name, strcmp) != null) {
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
						SList<AlpmPackage> pkgs = database.get_installed_pkgs_by_glob (name);
						if (pkgs != null) {
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
			int flags;
			if (group_found || unneeded) {
				flags = (1 << 15); //Alpm.TransFlag.UNNEEDED
			} else {
				flags = (1 << 4); //Alpm.TransFlag.CASCADE
			}
			if (database.config.recurse) {
				flags |= (1 << 5); //Alpm.TransFlag.RECURSE
			}
			if (no_save) {
				flags |= (1 << 2); //Alpm.TransFlag.NOSAVE
			}
			transaction.set_flags (flags);
			for (uint i = 0; i < to_remove_length; i++) {
				transaction.add_pkg_to_remove (to_remove[i]);
			}
			run_transaction ();
		}

		void remove_orphans () {
			var pkgs = database.get_orphans ();
			foreach (unowned AlpmPackage pkg in pkgs) {
				transaction.add_pkg_to_remove (pkg.name);
			}
			int flags = (1 << 4); //Alpm.TransFlag.CASCADE
			flags |= (1 << 5); //Alpm.TransFlag.RECURSE
			transaction.set_flags (flags);
			run_transaction ();
		}

		void clone_build_files (string[] pkgnames, bool overwrite, bool recurse, bool quiet) {
			already_checked_aur_dep = new GenericSet<string?> (str_hash, str_equal);
			cloning = true;
			clone_build_files_real (pkgnames, overwrite, recurse, quiet);
			cloning = false;
		}

		void clone_build_files_real (string[] pkgnames, bool overwrite, bool recurse, bool quiet) {
			var dep_to_check = new GenericArray<string> ();
			var aur_pkgs = database.get_aur_pkgs (pkgnames);
			var iter = HashTableIter<string, AURPackage?> (aur_pkgs);
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
				clone_build_files_real (dep_to_check.data, overwrite, recurse, quiet);
			}
		}

		bool check_build_pkgs (string[] targets) {
			var aur_pkgs = database.get_aur_pkgs (targets);
			var iter = HashTableIter<string, AURPackage?> (aur_pkgs);
			unowned string pkgname;
			unowned AURPackage? aur_pkg;
			while (iter.next (out pkgname, out aur_pkg)) {
				if (aur_pkg == null) {
					print_error (dgettext (null, "target not found: %s").printf (pkgname));
					return false;
				}
			}
			return true;
		}

		void build_pkgs (string[] names) {
			foreach (unowned string name in names) {
				transaction.add_aur_pkg_to_build (name);
			}
			run_transaction ();
		}

		void run_transaction () {
			bool success = transaction.run ();
			if (!success) {
				exit_status = 1;
			}
		}

		void run_sysupgrade (bool force_refresh, bool download_only) {
			if (download_only) {
				transaction.set_flags ((1 << 9)); //Alpm.TransFlag.DOWNLOADONLY
			}
			transaction.add_pkgs_to_upgrade (force_refresh);
			if (Posix.geteuid () != 0) {
				var loop = new MainLoop ();
				// let's time to pkttyagent to get registred
				Timeout.add (200, () => {
					run_transaction ();
					loop.quit ();
					return false;
				});
				loop.run ();
			} else {
				run_transaction ();
			}
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
		// intentionally reversed
		if (search_string != null) {
			// display exact match first
			if (pkg_a.app_name.down () == search_string) {
				if (pkg_b.app_name.down () == search_string) {
					return sort_pkgs_by_relevance (pkg_a, pkg_b);
				}
				return 1;
			}
			if (pkg_b.app_name.down () == search_string) {
				return -1;
			}
			if (pkg_a.name == search_string) {
				if (pkg_b.name == search_string) {
					return sort_pkgs_by_relevance (pkg_a, pkg_b);
				}
				return 1;
			}
			if (pkg_b.name == search_string) {
				return -1;
			}
			if (pkg_a.app_name.down ().has_prefix (search_string)) {
				if (pkg_b.app_name.down ().has_prefix (search_string)) {
					return sort_pkgs_by_relevance (pkg_a, pkg_b);
				}
				return 1;
			}
			if (pkg_b.app_name.down ().has_prefix (search_string)) {
				return -1;
			}
			if (pkg_a.app_name.down ().contains (search_string)) {
				if (pkg_b.app_name.down ().contains (search_string)) {
					return sort_pkgs_by_relevance (pkg_a, pkg_b);
				}
				return 1;
			}
			if (pkg_b.app_name.down ().contains (search_string)) {
				return -1;
			}
			if (pkg_a.name.has_prefix (search_string + "-")) {
				if (pkg_b.name.has_prefix (search_string + "-")) {
					return sort_pkgs_by_relevance (pkg_a, pkg_b);
				}
				return 1;
			}
			if (pkg_b.name.has_prefix (search_string + "-")) {
				return -1;
			}
			if (pkg_a.name.has_prefix (search_string)) {
				if (pkg_b.name.has_prefix (search_string)) {
					return sort_pkgs_by_relevance (pkg_a, pkg_b);
				}
				return 1;
			}
			if (pkg_b.name.has_prefix (search_string)) {
				return -1;
			}
			if (pkg_a.name.contains (search_string)) {
				if (pkg_b.name.contains (search_string)) {
					return sort_pkgs_by_relevance (pkg_a, pkg_b);
				}
				return 1;
			}
			if (pkg_b.name.contains (search_string)) {
				return -1;
			}
		}
		return sort_pkgs_by_relevance (pkg_a, pkg_b);
	}

	int sort_pkgs_by_relevance (Package pkg_a, Package pkg_b) {
		// intentionally reversed
		if (pkg_a.installed_version == "") {
			if (pkg_b.installed_version == "") {
				return sort_pkgs_by_name (pkg_a, pkg_b);
			}
			return -1;
		}
		if (pkg_b.installed_version == "") {
			return 1;
		}
		if (pkg_a.app_name == "") {
			if (pkg_b.app_name == "") {
				return sort_pkgs_by_name (pkg_a, pkg_b);
			}
			return -1;
		}
		if (pkg_b.app_name == "") {
			return 1;
		}
		return sort_pkgs_by_name (pkg_a, pkg_b);
	}

	int sort_pkgs_by_name (Package pkg_a, Package pkg_b) {
		// intentionally reversed
		string str_a = pkg_a.app_name == "" ? pkg_a.name.collate_key () : pkg_a.app_name.down ().collate_key ();
		string str_b = pkg_b.app_name == "" ? pkg_b.name.collate_key () : pkg_b.app_name.down ().collate_key ();
		return strcmp (str_b, str_a);
	}
}

