/*
 *  pamac-vala
 *
 *  Copyright (C) 2020-2021 Guillaume Benoit <guillaume@manjaro.org>
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

class Software : Application {
	string? details;
	OptionEntry[] options;

	public Software () {
		Object (application_id: "org.gnome.Software", flags: ApplicationFlags.FLAGS_NONE);
		details = null;
		options = new OptionEntry[1];
		options[0] = { "details", 0, 0, OptionArg.STRING, ref details, "Display package details", "ID" };
		add_main_option_entries (options);
	}

	public override void startup () {
		base.startup ();
		var action =  new SimpleAction ("details", new VariantType ("(ss)"));
		action.activate.connect  ((parameter) => {
			unowned string details = parameter.get_child_value (0).get_string ();
			try {
				Process.spawn_command_line_async ("pamac-manager --details-id=%s".printf (details));
			} catch (SpawnError e) {
				warning (e.message);
			}
		});
		this.add_action (action);
	}

	protected override void activate () {
		base.activate ();
	}

	protected override int handle_local_options (VariantDict options) {
		if (details != null) {
			try {
				this.register (null);
			} catch (Error e) {
				warning (e.message);
				return 0;
			}
			this.activate_action ("details", new Variant ("(ss)", details, ""));
		}
		return -1;
	}
}

int main (string[] args) {
	var software = new Software ();
	return software.run (args);
}
