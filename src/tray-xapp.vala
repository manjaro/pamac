/*
 * Pamac - native XApp status icon for Cinnamon Wayland
 *
 * Copyright (C) 2026 Pamac-Fix contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 */

namespace Pamac {
	class XAppTrayIcon : TrayIcon {
		XApp.StatusIcon status_icon;

		public override void init_status_icon () {
			status_icon = new XApp.StatusIcon ();
			status_icon.set_visible (false);

			// XApp emits activate for primary clicks when there is no
			// primary menu. The context menu remains bound to right-click.
			status_icon.activate.connect ((button, event_time) => {
				if (button == 1) {
					left_clicked ();
				}
			});

			// Match the legacy GTK/X11 right-click menu exactly.
			status_icon.set_secondary_menu (create_menu ());
		}

		public override void set_tooltip (string info) {
			status_icon.set_tooltip_text (info);
		}

		public override void set_icon (string icon) {
			status_icon.set_icon_name (icon);
		}

		public override void set_icon_visible (bool visible) {
			status_icon.set_visible (visible);
		}
	}
}
