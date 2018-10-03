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
	public class TransactionCli: Transaction {
		bool downloading;
		string current_line;
		string current_action;

		public TransactionCli (Database database) {
			Object (database: database);
		}

		construct {
			downloading = false;
			current_line = "";
			current_action = "";
			// connect to signal
			emit_action.connect (print_action);
			emit_action_progress.connect (print_action_progress);
			emit_hook_progress.connect (print_hook_progress);
			emit_script_output.connect (on_emit_script_output);
			emit_warning.connect (print_warning);
			emit_error.connect (print_error);
			start_downloading.connect (() => {
				downloading = true;
			});
			stop_downloading.connect (() => {
				downloading = false;
			});
		}

		protected override async int run_cmd_line (string[] args, string working_directory, Cancellable cancellable) {
			int status = 1;
			var launcher = new SubprocessLauncher (SubprocessFlags.NONE);
			launcher.set_cwd (working_directory);
			launcher.set_environ (Environ.get ());
			try {
				Subprocess process = launcher.spawnv (args);
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

		void print_action_progress (string action, string status, double progress) {
			if (downloading) {
				if (progress == 0) {
					current_action = action;
					current_line = status;
					stdout.printf (action);
					stdout.printf ("\n");
					stdout.printf (status);
				} else if (progress == 1) {
					current_line = "";
					// clean line
					stdout.printf ("\r%*s\r", get_term_width (), "");
				} else if (action == current_action) {
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
			} else {
				if (action != current_action) {
					current_action = action;
					display_current_line ();
				}
				int width = get_term_width () - action.char_count () - 1;
				string current_status = "[%s]".printf (status);
				current_line = "%s %*s".printf (action, width, current_status);
				stdout.printf (current_line);
				stdout.printf ("\r");
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

		protected override int choose_provider (string depend, string[] providers) {
			Package[] pkgs = {};
			foreach (unowned string pkgname in providers) {
				var pkg = database.get_sync_pkg (pkgname);
				if (pkg.name != "")  {
					pkgs += pkg;
				}
			}
			// print pkgs
			int name_length = 0;
			int version_length = 0;
			int repo_length = 0;
			foreach (unowned Package pkg in pkgs) {
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
			foreach (unowned Package pkg in pkgs) {
				stdout.printf ("%*s %-*s %-*s %-*s \n", num_length, "%i:".printf (num),
														name_length + margin, pkg.name,
														version_length + margin, pkg.version,
														repo_length + margin, pkg.repo);
				num++;
			}
			// get user input
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
					return index;
				}
			}
		}

		protected override bool ask_confirmation (TransactionSummary summary) {
			uint64 dsize = 0;
			uint64 rsize = 0;
			int64 isize = 0;
			int max_name_length = 0;
			int max_version_length = 0;
			int max_installed_version_length = 0;
			int max_size_length = 0;
			int margin = 0;
			// first pass to compute pkgs size and strings length
			if (summary.to_remove.length () > 0) {
				foreach (unowned Package infos in summary.to_remove) {
					rsize += infos.size;
					if (infos.name.length > max_name_length) {
						max_name_length = infos.name.length;
					}
					if (infos.version.length > max_version_length) {
						max_version_length = infos.version.length;
					}
				}
			}
			if (summary.aur_conflicts_to_remove.length () > 0) {
				foreach (unowned Package infos in summary.aur_conflicts_to_remove) {
					rsize += infos.size;
					if (infos.name.length > max_name_length) {
						max_name_length = infos.name.length;
					}
					if (infos.version.length > max_version_length) {
						max_version_length = infos.version.length;
					}
				}
			}
			if (summary.to_downgrade.length () > 0) {
				foreach (unowned Package infos in summary.to_downgrade) {
					dsize += infos.download_size;
					var pkg = database.get_installed_pkg (infos.name);
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
					string size = format_size (infos.download_size);
					if (size.length > max_size_length) {
						max_size_length = size.length;
					}
				}
			}
			if (summary.to_build.length () > 0) {
				foreach (unowned AURPackage infos in summary.to_build) {
					if (infos.name.length > max_name_length) {
						max_name_length = infos.name.length;
					}
					if (infos.version.length > max_version_length) {
						max_version_length = infos.version.length;
					}
				}
			}
			if (summary.to_install.length () > 0) {
				foreach (unowned Package infos in summary.to_install) {
					dsize += infos.download_size;
					var pkg = database.get_installed_pkg (infos.name);
					isize += ((int64) infos.size - (int64) pkg.size);
					if (infos.name.length > max_name_length) {
						max_name_length = infos.name.length;
					}
					if (infos.version.length > max_version_length) {
						max_version_length = infos.version.length;
					}
					string size = format_size (infos.download_size);
					if (size.length > max_size_length) {
						max_size_length = size.length;
					}
				}
			}
			if (summary.to_reinstall.length () > 0) {
				foreach (unowned Package infos in summary.to_reinstall) {
					dsize += infos.download_size;
					if (infos.name.length > max_name_length) {
						max_name_length = infos.name.length;
					}
					if (infos.version.length > max_version_length) {
						max_version_length = infos.version.length;
					}
					string size = format_size (infos.download_size);
					if (size.length > max_size_length) {
						max_size_length = size.length;
					}
				}
			}
			if (summary.to_upgrade.length () > 0) {
				foreach (unowned Package infos in summary.to_upgrade) {
					dsize += infos.download_size;
					var pkg = database.get_installed_pkg (infos.name);
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
					string size = format_size (infos.download_size);
					if (size.length > max_size_length) {
						max_size_length = size.length;
					}
				}
			}
			// second pass to print details
			max_installed_version_length += 2; // because of (%s)
			int total_width = max_name_length + max_version_length + max_installed_version_length + max_size_length + 6;
			if (get_term_width () > total_width) {
				// divide available space between columns
				int available_width = get_term_width () - total_width;
				margin = available_width / 4;
				// get left space to size
				max_size_length += available_width - (margin * 4);
			}
			if (summary.to_upgrade.length () > 0) {
				stdout.printf (dgettext (null, "To upgrade") + " (%u):\n".printf (summary.to_upgrade.length ()));
				foreach (unowned Package infos in summary.to_upgrade) {
					string size = infos.download_size == 0 ? "" : format_size (infos.download_size);
					stdout.printf ("  %-*s %-*s %-*s %*s \n", max_name_length + margin, infos.name,
														max_version_length + margin, infos.version,
														max_installed_version_length + margin, "(%s)".printf (infos.installed_version),
														max_size_length + margin, size);
				}
			}
			if (summary.to_reinstall.length () > 0) {
				stdout.printf (dgettext (null, "To reinstall") + " (%u):\n".printf (summary.to_reinstall.length ()));
				foreach (unowned Package infos in summary.to_reinstall) {
					string size = infos.download_size == 0 ? "" : format_size (infos.download_size);
					stdout.printf ("  %-*s %-*s %*s \n", max_name_length + margin, infos.name,
														max_version_length + margin, infos.version,
														max_size_length + margin, size);
				}
			}
			if (summary.to_install.length () > 0) {
				stdout.printf (dgettext (null, "To install") + " (%u):\n".printf (summary.to_install.length ()));
				foreach (unowned Package infos in summary.to_install) {
					string size = infos.download_size == 0 ? "" : format_size (infos.download_size);
					stdout.printf ("  %-*s %-*s %*s \n", max_name_length + margin, infos.name,
														max_version_length + margin, infos.version,
														max_size_length + margin, size);
				}
			}
			if (summary.to_build.length () > 0) {
				stdout.printf (dgettext (null, "To build") + " (%u):\n".printf (summary.to_build.length ()));
				foreach (unowned AURPackage infos in summary.to_build) {
					stdout.printf ("  %-*s %-*s\n", max_name_length + margin, infos.name,
													max_version_length + margin, infos.version);
				}
			}
			if (summary.to_downgrade.length () > 0) {
				stdout.printf (dgettext (null, "To downgrade") + " (%u):\n".printf (summary.to_downgrade.length ()));
				foreach (unowned Package infos in summary.to_downgrade) {
					string size = infos.download_size == 0 ? "" : format_size (infos.download_size);
					stdout.printf ("  %-*s %-*s %-*s %*s \n", max_name_length + margin, infos.name,
														max_version_length + margin, infos.version,
														max_installed_version_length + margin, "(%s)".printf (infos.installed_version),
														max_size_length + margin, size);
				}
			}
			bool to_remove_printed = false;
			if (summary.to_remove.length () > 0) {
				stdout.printf (dgettext (null, "To remove") + " (%u):\n".printf (summary.to_remove.length ()));
				to_remove_printed = true;
				foreach (unowned Package infos in summary.to_remove) {
					stdout.printf ("  %-*s %-*s\n", max_name_length + margin, infos.name,
													max_version_length + margin, infos.version);
				}
			}
			if (summary.aur_conflicts_to_remove.length () > 0) {
				if (!to_remove_printed) {
					stdout.printf (dgettext (null, "To remove") + " (%u):\n".printf (summary.aur_conflicts_to_remove.length ()));
				}
				foreach (unowned Package infos in summary.aur_conflicts_to_remove) {
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
			if (rsize > 0) {
				stdout.printf ("%s: %s\n", dgettext (null, "Total removed size"), format_size (rsize));
			}
			// ask user confirmation
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

		protected override async void review_build_files (string pkgname) {
			stdout.printf (dgettext (null, "Review %s build files".printf (pkgname)) + "\n");
			Posix.sleep (1);
			string builddir_name = Path.build_path ("/", database.config.aur_build_dir, "pamac-build", pkgname);
			string[] cmds = {"nano", "-S", "-w", "-i"};
			// PKGBUILD
			cmds += Path.build_path ("/", builddir_name, "PKGBUILD");
			// other file
			var build_dir = File.new_for_path (builddir_name);
			try {
				FileEnumerator enumerator = yield build_dir.enumerate_children_async ("standard::*", FileQueryInfoFlags.NONE);
				FileInfo info;
				while ((info = enumerator.next_file (null)) != null) {
					unowned string filename = info.get_name ();
					if (".install" in filename || ".patch" in filename) {
						cmds += Path.build_path ("/", builddir_name, filename);
					}
				}
				var process = new Subprocess.newv (cmds, SubprocessFlags.STDIN_INHERIT);
				yield process.wait_async ();
			} catch (Error e) {
				print ("Error: %s\n", e.message);
			}
			yield regenerate_srcinfo (pkgname);
		}
	}
}
