/*
 *  pamac-vala
 *
 *  Copyright 2016 Raphaël Rochet
 *  Copyright (C) 2018-2020 Guillaume Benoit <guillaume@manjaro.org>
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

const Clutter = imports.gi.Clutter;
const Lang = imports.lang;

const St = imports.gi.St;
const GObject = imports.gi.GObject;
const GLib = imports.gi.GLib;
//const Gtk = imports.gi.Gtk;
const Gio = imports.gi.Gio;

const Main = imports.ui.main;
const Panel = imports.ui.panel;
const PanelMenu = imports.ui.panelMenu;
const PopupMenu = imports.ui.popupMenu;
const MessageTray = imports.ui.messageTray;

const Util = imports.misc.util;
const ExtensionUtils = imports.misc.extensionUtils;
const Me = ExtensionUtils.getCurrentExtension();

const Gettext = imports.gettext.domain("pamac");
const _ = Gettext.gettext;

const Pamac = imports.gi.Pamac;

/* Options */
let HIDE_NO_UPDATE     = false;
let SHOW_COUNT         = true;
let BOOT_WAIT          = 30;  // 30s
let CHECK_INTERVAL     = 1;   // 1h
let NOTIFY             = true;
let TRANSIENT          = false;
let UPDATER_CMD        = "pamac-manager --updates";
let MANAGER_CMD        = "pamac-manager";
let PACMAN_DIR         = "/var/lib/pacman/local";
let STRIP_VERSIONS     = false;

/* Variables we want to keep when extension is disabled (eg during screen lock) */
let FIRST_BOOT         = 1;
let UPDATES_PENDING    = 0;
let UPDATES_LIST       = [];


function init() {
}

const PamacUpdateIndicator = new Lang.Class({
	Name: 'PamacUpdateIndicator',
	Extends: PanelMenu.Button,

	_TimeoutId: null,
	_FirstTimeoutId: null,
	_updateProcess_sourceId: null,
	_updateProcess_stream: null,
	_updateProcess_pid: null,
	_updateList: [],
	_config: null,
	_pacman_lock: null,
	//_icon_theme: null,

	_init: function() {
		this.parent(0.0, "PamacUpdateIndicator");
		// Set icon theme
		//let that = this;
		//this._icon_theme = Gtk.IconTheme.get_default();
		//this._icon_theme.connect('changed', function () {
			//that._icon_theme = Gtk.IconTheme.get_default();
		//});

		this.updateIcon = new St.Icon({icon_name: "pamac-tray-no-update", style_class: 'system-status-icon'});

		let box = new St.BoxLayout({ vertical: false, style_class: 'panel-status-menu-box' });
		this.label = new St.Label({ text: '',
			y_expand: true,
			y_align: Clutter.ActorAlign.CENTER });

		box.add_child(this.updateIcon);
		box.add_child(this.label);
		this.add_child(box);

		// Prepare the special menu : a submenu for updates list that will look like a regular menu item when disabled
		// Scrollability will also be taken care of by the popupmenu
		this.menuExpander = new PopupMenu.PopupSubMenuMenuItem('');
		this.updatesListMenuLabel = new St.Label();
		this.menuExpander.menu.box.add(this.updatesListMenuLabel);
		this.menuExpander.menu.box.style_class = 'pamac-updates-list';

		// Other standard menu items
		this.managerMenuItem = new PopupMenu.PopupMenuItem(_("Package Manager"));

		// Assemble all menu items into the popup menu
		this.menu.addMenuItem(this.menuExpander);
		this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
		this.menu.addMenuItem(this.managerMenuItem);

		// Bind some events
		this.menu.connect('open-state-changed', Lang.bind(this, this._onMenuOpened));
		this.managerMenuItem.connect('activate', Lang.bind(this, this._openManager));

		// Load config
		this._config = new Pamac.Config({conf_path: "/etc/pamac.conf"});
		this._applyConfig();
		this._updateMenuExpander(false, _("Your system is up-to-date"));

		if (FIRST_BOOT && CHECK_INTERVAL > 0) {
			// Schedule first check only if this is the first extension load
			// This won't be run again if extension is disabled/enabled (like when screen is locked)
			let that = this;
			this._FirstTimeoutId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, BOOT_WAIT, function () {
				that._checkUpdates();
				that._FirstTimeoutId = null;
				FIRST_BOOT = 0;
				that._startFolderMonitor();
				return false; // Run once
			});
		} else {
			// Restore previous state
			this._updateList = UPDATES_LIST;
			this._updateStatus(UPDATES_PENDING);
			this._startFolderMonitor();
		}
	},

	_openManager: function () {
		if (UPDATES_PENDING > 0) {
			Util.spawnCommandLine(UPDATER_CMD);
		} else {
			Util.spawnCommandLine(MANAGER_CMD);
		}
	},

	_applyConfig: function() {
		HIDE_NO_UPDATE = this._config.no_update_hide_icon;
		PACMAN_DIR = this._config.db_path + "local";
		this._checkShowHide();
		let that = this;
		if (this._TimeoutId) GLib.source_remove(this._TimeoutId);
		if (this._config.refresh_period > 0) {
			// check every hour if refresh_timestamp is older than config.refresh_period
			this._TimeoutId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 3600 * CHECK_INTERVAL, function () {
				that._checkUpdates();
				return true;
			});
		}
	},

	destroy: function() {
		if (this._notifSource) {
			// Delete the notification source, which lay still have a notification shown
			this._notifSource.destroy();
			this._notifSource = null;
		};
		if (this.monitor) {
			// Stop spying on pacman local dir
			this.monitor.cancel();
			this.monitor = null;
		}
		if (this._updateProcess_sourceId) {
			// We leave the checkupdate process end by itself but undef handles to avoid zombies
			GLib.source_remove(this._updateProcess_sourceId);
			this._updateProcess_sourceId = null;
			this._updateProcess_stream = null;
		}
		if (this._FirstTimeoutId) {
			GLib.source_remove(this._FirstTimeoutId);
			this._FirstTimeoutId = null;
		}
		if (this._TimeoutId) {
			GLib.source_remove(this._TimeoutId);
			this._TimeoutId = null;
		}
		this.parent();
	},

	_checkShowHide: function() {
		if (HIDE_NO_UPDATE && UPDATES_PENDING < 1) {
			this.visible = false;
		} else {
			this.visible = true;
		}
		this.label.visible = SHOW_COUNT && UPDATES_PENDING > 0;
	},

	_onMenuOpened: function() {
		// This event is fired when menu is shown or hidden
		// Close the submenu
		this.menuExpander.setSubmenuShown(false);
	},

	_startFolderMonitor: function() {
		if (PACMAN_DIR) {
			this.pacman_dir = Gio.file_new_for_path(PACMAN_DIR);
			this.monitor = this.pacman_dir.monitor_directory(0, null);
			this.monitor.connect('changed', Lang.bind(this, this._onFolderChanged));
		}
	},
	_onFolderChanged: function() {
		// Folder have changed ! Let's schedule a check in a few seconds
		let that = this;
		if (this._FirstTimeoutId) GLib.source_remove(this._FirstTimeoutId);
		this._FirstTimeoutId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 5, function () {
			that._checkUpdates();
			that._FirstTimeoutId = null;
			return false;
		});
	},

	_updateStatus: function(updatesCount) {
		updatesCount = typeof updatesCount === 'number' ? updatesCount : UPDATES_PENDING;
		if (updatesCount > 0) {
			// Updates pending
			this.updateIcon.set_icon_name("pamac-tray-update");
			this._updateMenuExpander(true, Gettext.ngettext( "%u available update", "%u available updates", updatesCount ).replace("%u", updatesCount.toString()));
			this.updatesListMenuLabel.set_text( this._updateList.join("\n") );
			this.label.set_text(updatesCount.toString());
			if (NOTIFY && UPDATES_PENDING < updatesCount) {
				this._showNotification(
					Gettext.ngettext( "%u available update", "%u available updates", updatesCount ).replace("%u", updatesCount.toString())
				);
			}
			// Store the new list
			UPDATES_LIST = this._updateList;
		} else {
			this.updatesListMenuLabel.set_text("");
			this.label.set_text("");
			// Up to date
			this.updateIcon.set_icon_name("pamac-tray-no-update");
			this._updateMenuExpander(false, _("Your system is up-to-date"));
			UPDATES_LIST = []; // Reset stored list
		}
		UPDATES_PENDING = updatesCount;
		this._checkShowHide();
	},

	_updateMenuExpander: function(enabled, label) {
		if (label == "") {
			// No text, hide the menuitem
			this.menuExpander.visible = false;
		} else {
		// We make our expander look like a regular menu label if disabled
			this.menuExpander.reactive = enabled;
			this.menuExpander._triangle.visible = enabled;
			this.menuExpander.label.set_text(label);
			this.menuExpander.visible = true;
		}
	},

	_checkUpdates: function() {
		if(this._updateProcess_sourceId) {
			// A check is already running ! Maybe we should kill it and run another one ?
			return;
		}
		// Run asynchronously, to avoid  shell freeze - even for a 1s check
		try {
			let check_cmd = ["pamac", "checkupdates", "-q", "--refresh-tmp-files-dbs", "--use-timestamp"];
			if (this._config.download_updates) {
				check_cmd.push ("--download-updates");
			}
			let [res, pid, in_fd, out_fd, err_fd]  = GLib.spawn_async_with_pipes(null, check_cmd, null, GLib.SpawnFlags.DO_NOT_REAP_CHILD | GLib.SpawnFlags.SEARCH_PATH, null);
			// Let's buffer the command's output - that's a input for us !
			this._updateProcess_stream = new Gio.DataInputStream({
				base_stream: new Gio.UnixInputStream({fd: out_fd})
			});
			// We will process the output at once when it's done
			this._updateProcess_sourceId = GLib.child_watch_add(0, pid, Lang.bind(this, function() {this._checkUpdatesRead()}));
			this._updateProcess_pid = pid;
		} catch (err) {
			this._updateMenuExpander(false, _("Your system is up-to-date"));
			this._updateStatus(0);
		}
	},

	_cancelCheck: function() {
		if (this._updateProcess_pid == null) { return; };
		Util.spawnCommandLine( "kill " + this._updateProcess_pid );
		this._updateProcess_pid = null; // Prevent double kill
		this._checkUpdatesEnd();
	},

	_checkUpdatesRead: function() {
		// Read the buffered output
		let updateList = [];
		let out, size;
		do {
			[out, size] = this._updateProcess_stream.read_line_utf8(null);
			if (out) updateList.push(out);
		} while (out);
		// If version numbers should be stripped, do it
		if (STRIP_VERSIONS == true) {
			updateList = updateList.map(function(p) {
				// Try to keep only what's before the first space
				var chunks = p.split(" ",2);
				return chunks[0];
			});
		}
		this._updateList = updateList;
		this._checkUpdatesEnd();
	},

	_checkUpdatesEnd: function() {
		// Free resources
		this._updateProcess_stream.close(null);
		this._updateProcess_stream = null;
		GLib.source_remove(this._updateProcess_sourceId);
		this._updateProcess_sourceId = null;
		this._updateProcess_pid = null;
		// Update indicator
		this._updateStatus(this._updateList.length);
		if (UPDATES_PENDING > 0) {
			// Refresh files dbs in tmp
			let database = new Pamac.Database({config: this._config});
			database.start_refresh_tmp_files_dbs ();
		}
	},

	_showNotification: function(message) {
		if (this._notifSource == null) {
			// We have to prepare this only once
			this._notifSource = new MessageTray.SystemNotificationSource();
			this._notifSource.createIcon = function() {
				return new St.Icon({ icon_name: "system-software-install-symbolic" });
			};
			// Take care of note leaving unneeded sources
			this._notifSource.connect('destroy', Lang.bind(this, function() {this._notifSource = null;}));
			Main.messageTray.add(this._notifSource);
		}
		let notification = null;
		// We do not want to have multiple notifications stacked
		// instead we will update previous
		if (this._notifSource.notifications.length == 0) {
			notification = new MessageTray.Notification(this._notifSource, _("Package Manager"), message);
			notification.addAction( _("Details") , Lang.bind(this, function() {this._openManager()}) );
		} else {
			notification = this._notifSource.notifications[0];
			notification.update(_("Package Manager"), message, { clear: true });
		}
		notification.setTransient(TRANSIENT);
		this._notifSource.showNotification(notification);
	},


});

let pamacupdateindicator;

function enable() {
	pamacupdateindicator = new PamacUpdateIndicator();
	Main.panel.addToStatusArea('PamacUpdateIndicator', pamacupdateindicator);
}

function disable() {
	pamacupdateindicator.destroy();
}
