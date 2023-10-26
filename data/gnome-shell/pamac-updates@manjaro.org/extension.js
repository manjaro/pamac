/*
 *  pamac-vala
 *
 *  Copyright 2016-2023 Raphaël Rochet
 *  Copyright (C) 2018-2023 Guillaume Benoit <guillaume@manjaro.org>
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

import Clutter from 'gi://Clutter';
import St from 'gi://St';
import GObject from 'gi://GObject';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Button} from 'resource:///org/gnome/shell/ui/panelMenu.js';

import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as MessageTray from 'resource:///org/gnome/shell/ui/messageTray.js';
import * as Util from 'resource:///org/gnome/shell/misc/util.js';
import {Extension, gettext as _, ngettext as __} from 'resource:///org/gnome/shell/extensions/extension.js';

import Pamac from 'gi://Pamac';

/* Options */
let HIDE_NO_UPDATE     = false;
let BOOT_WAIT          = 30;  // 30s
let CHECK_INTERVAL     = 1;   // 1h
let NOTIFY             = true;
let TRANSIENT          = true;
let UPDATER_CMD        = "pamac-manager --updates";
let MANAGER_CMD        = "pamac-manager";

/* Variables we want to keep when extension is disabled (eg during screen lock) */
let FIRST_BOOT         = 1;
let UPDATES_PENDING    = 0;
let UPDATES_LIST       = [];

export default class PamacUpdateIndicatorExtension extends Extension {
	constructor(metadata) {
		super(metadata);
	}
	init() {
		String.prototype.format = Format.format;
	}
	enable() {
		this.pamacupdateindicator = new PamacUpdateIndicator(this);
		Main.panel.addToStatusArea('PamacUpdateIndicator', this.pamacupdateindicator);
	}
	disable() {
		this.pamacupdateindicator.destroy();
		this.pamacupdateindicator = null;
	}
}

const PamacUpdateIndicator = GObject.registerClass(
	{
		_TimeoutId: null,
		_FirstTimeoutId: null,
		_updateProcess_sourceId: null,
		_updateProcess_stream: null,
		_updateProcess_pid: null,
		_updateList: [],
	},
class PamacUpdateIndicator extends Button {

	_init(ext) {
		super._init(0);

		this.updateIcon = new St.Icon({icon_name: "pamac-tray-no-update", style_class: 'system-status-icon'});

		let box = new St.BoxLayout({ vertical: false, style_class: 'panel-status-menu-box' });

		box.add_child(this.updateIcon);
		this.add_child(box);

		// Prepare the special menu : a submenu for updates list that will look like a regular menu item when disabled
		// Scrollability will also be taken care of by the popupmenu
		this.menuExpander = new PopupMenu.PopupSubMenuMenuItem('');
		this.menuExpander.menu.box.style_class = 'pamac-updates-list';

		// Other standard menu items
		this.managerMenuItem = new PopupMenu.PopupMenuItem(_("Package Manager"));

		// Assemble all menu items into the popup menu
		this.menu.addMenuItem(this.menuExpander);
		this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
		this.menu.addMenuItem(this.managerMenuItem);

		// Bind some events
		this.menu.connect('open-state-changed', this._onMenuOpened.bind(this));
		this.managerMenuItem.connect('activate', this._openManager.bind(this));

		if (FIRST_BOOT && CHECK_INTERVAL > 0) {
			// This won't be run again if extension is disabled/enabled (like when screen is locked)
			this._updatesChecker = new Pamac.UpdatesChecker();
			this._updatesChecker.connect('updates-available', this._onUpdatesAvailable.bind(this));
			this._applyConfig();
			this._updateMenuExpander(false, _("Your system is up to date"));
			let that = this;
			this._FirstTimeoutId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, BOOT_WAIT, function () {
				that._checkUpdates();
				that._FirstTimeoutId = null;
				FIRST_BOOT = 0;
				return false; // Run once
			});
		} else {
			// Restore previous state
			this._updateList = UPDATES_LIST;
			this._updateStatus(UPDATES_PENDING);
		}
	}

	_openManager() {
		if (UPDATES_PENDING > 0) {
			Util.spawnCommandLine(UPDATER_CMD);
		} else {
			Util.spawnCommandLine(MANAGER_CMD);
		}
	}

	_applyConfig() {
		HIDE_NO_UPDATE = this._updatesChecker.no_update_hide_icon;
		this._checkShowHide();
		let that = this;
		if (this._TimeoutId) GLib.source_remove(this._TimeoutId);
		if (this._updatesChecker.refresh_period > 0) {
			// check every hour if refresh_timestamp is older than config.refresh_period
			this._TimeoutId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 3600 * CHECK_INTERVAL, function () {
				that._checkUpdates();
				return true;
			});
		}
	}

	destroy() {
		if (this._notifSource) {
			// Delete the notification source, which lay still have a notification shown
			this._notifSource.destroy();
			this._notifSource = null;
		}
		if (this._FirstTimeoutId) {
			GLib.source_remove(this._FirstTimeoutId);
			this._FirstTimeoutId = null;
		}
		if (this._TimeoutId) {
			GLib.source_remove(this._TimeoutId);
			this._TimeoutId = null;
		}
		super.destroy();
	}

	_checkShowHide() {
		if (HIDE_NO_UPDATE && UPDATES_PENDING < 1) {
			this.visible = false;
		} else {
			this.visible = true;
		}
	}

	_onMenuOpened() {
		// This event is fired when menu is shown or hidden
		// Close the submenu
		this.menuExpander.setSubmenuShown(false);
	}

	_updateStatus(updatesCount) {
		updatesCount = typeof updatesCount === 'number' ? updatesCount : UPDATES_PENDING;
		if (updatesCount > 0) {
			// Updates pending
			this.updateIcon.set_icon_name("pamac-tray-update");
			this._updateMenuExpander(true, __( "%u available update", "%u available updates", updatesCount ).replace("%u", updatesCount.toString()));
			if (NOTIFY && UPDATES_PENDING < updatesCount) {
				this._showNotification(
					_("Updates Available")
				);
			}
			// Store the new list
			UPDATES_LIST = this._updateList;
		} else {
			// Up to date
			this.updateIcon.set_icon_name("pamac-tray-no-update");
			this._updateMenuExpander(false, _("Your system is up to date"));
			UPDATES_LIST = []; // Reset stored list
		}
		UPDATES_PENDING = updatesCount;
		this._checkShowHide();
	}

	_updateMenuExpander(enabled, label) {
		this.menuExpander.menu.box.destroy_all_children();
		if (label == "") {
			// No text, hide the menuitem
			this.menuExpander.actor.visible = false;
		} else {
		// We make our expander look like a regular menu label if disabled
			this.menuExpander.actor.reactive = enabled;
			this.menuExpander._triangle.visible = enabled;
			this.menuExpander.label.set_text(label);
			this.menuExpander.actor.visible = true;
			if (enabled && this._updateList.length > 0) {
				this._updateList.forEach( item => {
					this.menuExpander.menu.box.add( this._createPackageLabel(item) );
				} );
			}
		}
	}

	_createPackageLabel(name) {
		return new St.Label({
			text: name,
			x_expand: true,
			style_class: 'pamac-updates-update-name'
		});
	}

	_checkUpdates() {
		this._updatesChecker.check_updates();
	}

	_onUpdatesAvailable(obj, updatesCount) {
		this._updateList = this._updatesChecker.updates_list;
		this._updateStatus(updatesCount);
	}

	_showNotification(message) {
		if (this._notifSource == null) {
			// We have to prepare this only once
			this._notifSource = new MessageTray.SystemNotificationSource();
			this._notifSource.createIcon = function() {
				return new St.Icon({ icon_name: "system-software-install-symbolic" });
			};
			// Take care of note leaving unneeded sources
			this._notifSource.connect('destroy', ()=>{this._notifSource = null;});
			Main.messageTray.add(this._notifSource);
		}
		let notification = null;
		// We do not want to have multiple notifications stacked
		// instead we will update previous
		if (this._notifSource.notifications.length == 0) {
			notification = new MessageTray.Notification(this._notifSource, _("Package Manager"), message);
			notification.addAction( _("Details") , ()=>{this._openManager();} );
		} else {
			notification = this._notifSource.notifications[0];
			notification.update(_("Package Manager"), message, { clear: true });
		}
		notification.setTransient(TRANSIENT);
		this._notifSource.showNotification(notification);
	}

});
