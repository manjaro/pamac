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
	public class TransactionCli: Transaction {
		string current_line;
		string current_action;
		bool summary_shown;
		public bool no_confirm { get; set; }

		public TransactionCli (Database database) {
			Object (database: database);
		}

		construct {
			current_line = "";
			current_action = "";
			summary_shown = false;
			no_confirm = false;
			// connect to signal
			emit_action.connect (print_action);
			emit_action_progress.connect (print_action_progress);
			emit_download_progress.connect (print_download_progress);
			emit_hook_progress.connect (print_hook_progress);
			emit_script_output.connect (on_emit_script_output);
			emit_warning.connect (print_warning);
			emit_error.connect (print_error);
		}

		protected override int run_cmd_line (string[] args, string? working_directory, Cancellable cancellable) {
			int status = 1;
			var launcher = new SubprocessLauncher (SubprocessFlags.STDIN_INHERIT);
			if (working_directory != null) {
				launcher.set_cwd (working_directory);
			}
			launcher.set_environ (Environ.get ());
			try {
				Subprocess process = launcher.spawnv (args);
				try {
					process.wait (cancellable);
					if (process.get_if_exited ()) {
						status = process.get_exit_status ();
					}
				} catch (Error e) {
					// cancelled
					process.send_signal (Posix.Signal.INT);
					process.send_signal (Posix.Signal.KILL);
				}
			} catch (Error e) {
				print_error (e.message, {});
			}
			return status;
		}

		public int get_term_width () {
			int width = 80;
			Linux.winsize win;
			if (Linux.ioctl (Posix.STDOUT_FILENO, Linux.Termios.TIOCGWINSZ, out win) == 0) {
				width = win.ws_col;
			}
			return width;
		}

		void display_current_line () {
			if (current_line != "") {
				// clean line
				stdout.printf ("\r%*s\r", get_term_width (), "");
				stdout.printf (current_line);
				stdout.printf ("\n");
				current_line = "";
			}
		}

		void on_emit_script_output (string line) {
			display_current_line ();
			stdout.printf (line);
			stdout.printf ("\n");
		}

		void print_action (string action) {
			display_current_line ();
			current_line = "";
			stdout.printf (action);
			stdout.printf ("\n");
		}

		void print_download_progress (string action, string status, double progress) {
			if (action == current_action) {
				current_line = status;
				// clean line
				stdout.printf ("\r%*s\r", get_term_width (), "");
				stdout.printf (status);
			} else {
				current_action = action;
				current_line = status;
				// clean line
				stdout.printf ("\r%*s\r", get_term_width (), "");
				stdout.printf (action);
				stdout.printf ("\n");
				stdout.printf (status);
			}
			if (progress == 1) {
				current_line = "";
				// clean line
				stdout.printf ("\r%*s\r", get_term_width (), "");
			}
			stdout.flush ();
		}

		void print_action_progress (string action, string status, double progress) {
			if (action != current_action) {
				current_action = action;
				display_current_line ();
			}
			int width = get_term_width () - action.char_count () - 1;
			string current_status = "[%s]".printf (status);
			if (width > current_status.length) {
				if (progress == 1) {
					current_line = "";
					stdout.printf ("%s %*s\n".printf (action, width, current_status));
				} else {
					current_line = "%s %*s".printf (action, width, current_status);
					stdout.printf (current_line);
					stdout.printf ("\r");
				}
			} else {
				current_line = "%s %s".printf (action, current_status);
				stdout.printf (current_line);
				stdout.printf ("\n");
			}
			stdout.flush ();
		}

		void print_hook_progress (string action, string details, string status, double progress) {
			if (action != current_action) {
				current_action = action;
				display_current_line ();
				stdout.printf (action);
				stdout.printf ("\n");
			}
			int width = get_term_width () - details.char_count () - 1;
			string current_status = "[%s]".printf (status);
			stdout.printf ("%s %*s\n".printf (details, width, current_status));
		}

		void print_warning (string line) {
			display_current_line ();
			stdout.printf (line);
			stdout.printf ("\n");
		}

		void print_error (string message, string[] details) {
			display_current_line ();
			if (details.length > 0) {
				if (details.length == 1) {
					stdout.printf ("%s: %s: %s\n", dgettext (null, "Error"), message, details[0]);
				} else {
					stdout.printf ("%s: %s:\n", dgettext (null, "Error"), message);
					foreach (unowned string detail in details) {
						stdout.printf ("%s\n", detail);
					}
				}
			} else {
				stdout.printf ("%s: %s\n", dgettext (null, "Error"), message);
			}
		}

		protected override string[] choose_optdeps (string pkgname, string[] optdeps) {
			if (no_confirm) {
				return {};
			}
			// print pkgs
			int num_length = optdeps.length.to_string ().length + 1;
			stdout.printf ("%s:\n".printf (dgettext (null, "Choose optional dependencies for %s").printf (pkgname)));
			int num = 1;
			foreach (unowned string name in optdeps) {
				stdout.printf ("%*s  %s\n",
								num_length, "%i:".printf (num),
								name);
				num++;
			}
			var optdeps_to_install = new GenericArray<string> ();
			// get user input
			while (true) {
				stdout.printf ("\n");
				stdout.printf ("%s: ", dgettext (null, "Enter a selection (default=%s)").printf (dgettext (null, "none")));
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
										if (nb >= 1 && nb <= optdeps.length) {
											numbers += nb;
										}
										nb++;
									}
								}
							}
						} else if (uint64.try_parse (part, out nb)) {
							if (nb >= 1 && nb <= optdeps.length) {
								numbers += nb;
							}
						}
					}
				}
				if (numbers.length > 0) {
					foreach (uint64 number in numbers) {
						optdeps_to_install.add (optdeps[number -1]);
					}
					break;
				}
			}
			stdout.printf ("\n");
			return optdeps_to_install.data;
		}

		protected override int choose_provider (string depend, string[] providers) {
			if (no_confirm) {
				// choose first provider
				return 0;
			}
			var pkgs = new SList<Package> ();
			foreach (unowned string pkgname in providers) {
				var pkg = database.get_sync_pkg (pkgname);
				if (pkg != null)  {
					pkgs.append (pkg);
				}
			}
			// print pkgs
			int name_length = 0;
			int version_length = 0;
			foreach (unowned Package pkg in pkgs) {
				if (pkg.name.length > name_length) {
					name_length = pkg.name.length;
				}
				if (pkg.version.length > version_length) {
					version_length = pkg.version.length;
				}
			}
			int num_length = providers.length.to_string ().length + 1;
			stdout.printf ("%s:\n".printf (dgettext (null, "Choose a provider for %s").printf (depend)));
			int num = 1;
			foreach (unowned Package pkg in pkgs) {
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
				stdout.printf ("%s: ", dgettext (null, "Enter a number (default=%d)").printf (1));
				string? ans = stdin.read_line  ();
				if (ans == null) {
					stdout.printf ("\n");
					return 1;
				}
				int64 nb;
				// remvove trailing newline
				ans = ans.replace ("\n", "");
				// just return use default
				if (ans == "") {
					nb = 1;
				} else if (!int64.try_parse (ans, out nb)) {
					nb = 0;
				}
				if (nb >= 1 && nb <= providers.length) {
					int index = (int) nb - 1;
					stdout.printf ("\n");
					return index;
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
			stdout.printf ("\n");
			return false;
		}

		protected override bool ask_import_key (string pkgname, string key, string owner) {
			stdout.printf ("%s.\n".printf (dgettext (null, "The PGP key %s is needed to verify %s source files").printf (key, pkgname)));
			if (no_confirm) {
				return true;
			}
			return ask_user ("%s ?".printf (dgettext (null, "Trust %s and import the PGP key").printf (owner)));
		}

		protected override bool ask_edit_build_files (TransactionSummary summary) {
			show_summary (summary);
			summary_shown = true;
			if (no_confirm) {
				return false;
			}
			return ask_user ("%s ?".printf (dgettext (null, "Edit build files")));
		}

		void show_summary (TransactionSummary summary) {
			uint64 dsize = 0;
			uint64 rsize = 0;
			int64 isize = 0;
			int name_length = 0;
			int version_length = 0;
			int installed_version_length = 0;
			int repo_length = 0;
			// first pass to compute pkgs size and strings length
			if (summary.to_remove.length () > 0) {
				foreach (unowned Package pkg in summary.to_remove) {
					rsize += pkg.installed_size;
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
			}
			if (summary.to_downgrade.length () > 0) {
				foreach (unowned Package pkg in summary.to_downgrade) {
					dsize += pkg.download_size;
					var installed_pkg = database.get_installed_pkg (pkg.name);
					isize += ((int64) pkg.installed_size - (int64) installed_pkg.installed_size);
					if (pkg.name.length > name_length) {
						name_length = pkg.name.length;
					}
					if (pkg.version.length > version_length) {
						version_length = pkg.version.length;
					}
					if (pkg.installed_version.length > installed_version_length) {
						installed_version_length = pkg.installed_version.length;
					}
					if (pkg.repo.length > repo_length) {
						repo_length = pkg.repo.length;
					}
				}
			}
			if (summary.to_build.length () > 0) {
				foreach (unowned Package pkg in summary.to_build) {
					if (pkg.name.length > name_length) {
						name_length = pkg.name.length;
					}
					if (pkg.version.length > version_length) {
						version_length = pkg.version.length;
					}
					if (pkg.installed_version.length > installed_version_length) {
						installed_version_length = pkg.installed_version.length;
					}
					if (pkg.repo.length > repo_length) {
						repo_length = pkg.repo.length;
					}
				}
			}
			if (summary.to_install.length () > 0) {
				foreach (unowned Package pkg in summary.to_install) {
					dsize += pkg.download_size;
					isize += (int64) pkg.installed_size;
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
			}
			if (summary.to_reinstall.length () > 0) {
				foreach (unowned Package pkg in summary.to_reinstall) {
					dsize += pkg.download_size;
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
			}
			if (summary.to_upgrade.length () > 0) {
				foreach (unowned Package pkg in summary.to_upgrade) {
					dsize += pkg.download_size;
					var installed_pkg = database.get_installed_pkg (pkg.name);
					isize += ((int64) pkg.installed_size - (int64) installed_pkg.installed_size);
					if (pkg.name.length > name_length) {
						name_length = pkg.name.length;
					}
					if (pkg.version.length > version_length) {
						version_length = pkg.version.length;
					}
					if (pkg.installed_version.length > installed_version_length) {
						installed_version_length = pkg.installed_version.length;
					}
					if (pkg.repo.length > repo_length) {
						repo_length = pkg.repo.length;
					}
				}
			}
			// second pass to print details
			if (installed_version_length > 0) {
				installed_version_length += 2; // because of (%s)
			}
			if (summary.to_upgrade.length () > 0) {
				stdout.printf (dgettext (null, "To upgrade") + " (%u):\n".printf (summary.to_upgrade.length ()));
				foreach (unowned Package pkg in summary.to_upgrade) {
					string size = pkg.download_size == 0 ? "" : format_size (pkg.download_size);
					stdout.printf ("  %-*s  %-*s  %-*s  %-*s  %s\n",
									name_length, pkg.name,
									version_length, pkg.version,
									installed_version_length, "(%s)".printf (pkg.installed_version),
									repo_length, pkg.repo,
									size);
				}
			}
			if (summary.to_reinstall.length () > 0) {
				stdout.printf (dgettext (null, "To reinstall") + " (%u):\n".printf (summary.to_reinstall.length ()));
				foreach (unowned Package pkg in summary.to_reinstall) {
					string size = pkg.download_size == 0 ? "" : format_size (pkg.download_size);
					stdout.printf ("  %-*s  %-*s  %-*s  %-*s  %s\n",
									name_length, pkg.name,
									version_length , pkg.version,
									installed_version_length, "",
									repo_length, pkg.repo,
									size);
				}
			}
			if (summary.to_install.length () > 0) {
				stdout.printf (dgettext (null, "To install") + " (%u):\n".printf (summary.to_install.length ()));
				foreach (unowned Package pkg in summary.to_install) {
					string size = pkg.download_size == 0 ? "" : format_size (pkg.download_size);
					stdout.printf ("  %-*s  %-*s  %-*s  %-*s  %s\n",
									name_length, pkg.name,
									version_length , pkg.version,
									installed_version_length, "",
									repo_length, pkg.repo,
									size);
				}
			}
			if (summary.to_build.length () > 0) {
				stdout.printf (dgettext (null, "To build") + " (%u):\n".printf (summary.to_build.length ()));
				foreach (unowned Package pkg in summary.to_build) {
					string installed_version = "";
					if (pkg.installed_version != "" && pkg.installed_version != pkg.version) {
						installed_version = "(%s)".printf (pkg.installed_version);
					}
					stdout.printf ("  %-*s  %-*s  %-*s  %s\n",
									name_length, pkg.name,
									version_length , pkg.version,
									installed_version_length, installed_version,
									pkg.repo);
				}
			}
			if (summary.to_downgrade.length () > 0) {
				stdout.printf (dgettext (null, "To downgrade") + " (%u):\n".printf (summary.to_downgrade.length ()));
				foreach (unowned Package pkg in summary.to_downgrade) {
					string size = pkg.download_size == 0 ? "" : format_size (pkg.download_size);
					stdout.printf ("  %-*s  %-*s  %-*s  %-*s  %s\n",
									name_length, pkg.name,
									version_length, pkg.version,
									installed_version_length, "(%s)".printf (pkg.installed_version),
									repo_length, pkg.repo,
									size);
				}
			}
			if (summary.to_remove.length () > 0) {
				stdout.printf (dgettext (null, "To remove") + " (%u):\n".printf (summary.to_remove.length ()));
				foreach (unowned Package pkg in summary.to_remove) {
					stdout.printf ("  %-*s  %-*s  %-*s  %s\n",
									name_length, pkg.name,
									version_length , pkg.version,
									installed_version_length, "",
									pkg.repo);
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
			if (rsize > 0) {
				stdout.printf ("%s: %s\n", dgettext (null, "Total removed size"), format_size (rsize));
			}
		}

		protected override bool ask_commit (TransactionSummary summary) {
			if (!summary_shown) {
				show_summary (summary);
			}
			if (no_confirm) {
				return true;
			}
			return ask_user ("%s ?".printf (dgettext (null, "Apply transaction")));
		}

		void ask_view_diff (string pkgname) {
			string diff_path;
			if (database.config.aur_build_dir == "/var/tmp") {
				diff_path = Path.build_path ("/", database.config.aur_build_dir, "pamac-build-%s".printf (Environment.get_user_name ()), pkgname, "diff");
			} else {
				diff_path = Path.build_path ("/", database.config.aur_build_dir, "pamac-build", pkgname, "diff");
			}
			var diff_file = File.new_for_path (diff_path);
			if (diff_file.query_exists ()) {
				if (ask_user ("%s ?".printf (dgettext (null, "View %s build files diff").printf (pkgname)))) {
					string[] cmds = {};
					unowned string? editor = Environment.get_variable ("EDITOR");
					if (editor == null || editor == "nano") {
						cmds += "nano";
						cmds += "-v";
					} else {
						// support args in EDITOR
						foreach (unowned string str in editor.split (" ")) {
							cmds += str;
						}
					}
					cmds += diff_path;
					try {
						var process = new Subprocess.newv (cmds, SubprocessFlags.STDIN_INHERIT);
						process.wait ();
					} catch (Error e) {
						warning (e.message);
					}
				}
			}
		}

		void edit_single_build_files (string pkgname) {
			get_build_files.begin (pkgname, (obj, res) => {
				GenericArray<string> files = get_build_files.end (res);
				if (files.length > 0) {
					string[] cmds = {};
					unowned string? editor = Environment.get_variable ("EDITOR");
					if (editor == null || editor == "nano") {
						cmds += "nano";
						cmds += "-i";
					} else {
						// support args in EDITOR
						foreach (unowned string str in editor.split (" ")) {
							cmds += str;
						}
					}
					for (uint i = 0; i < files.length; i++) {
						unowned string file = files[i];
						cmds += file;
					}
					try {
						var process = new Subprocess.newv (cmds, SubprocessFlags.STDIN_INHERIT);
						process.wait ();
						if (process.get_if_exited ()) {
							if (process.get_exit_status () == 0) {
								database.regenerate_srcinfo (pkgname);
							}
						}
					} catch (Error e) {
						warning (e.message);
					}
				}
				loop.quit ();
			});
			loop.run ();
		}

		protected override void edit_build_files (string[] pkgnames) {
			if (pkgnames.length == 1) {
				ask_view_diff (pkgnames[0]);
				edit_single_build_files (pkgnames[0]);
			} else {
				foreach (unowned string pkgname in pkgnames) {
					ask_view_diff (pkgname);
					if (ask_user ("%s ?".printf (dgettext (null, "Edit %s build files".printf (pkgname))))) {
						edit_single_build_files (pkgname);
					}
				}
			}
		}
	}
}
