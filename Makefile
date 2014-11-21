
all:
	cd resources; make resources
	cd src; make binaries
	cd po; make gettext

clean:
	rm -f src/*.c  src/pamac-daemon  src/pamac-tray  src/pamac-updater  src/pamac-manager  src/pamac-install
	rm -r resources/*.c
	rm -rf po/locale
	rm -f po/*.mo
	rm -f data/polkit/org.manjaro.pamac.policy

install:
	mkdir -p /usr/share/icons/hicolor
	cp -r data/icons/* /usr/share/icons/hicolor
	cp -r po/locale /usr/share
	install -Dm744 src/pamac-daemon /usr/bin/pamac-daemon
	install -Dm755 src/pamac-tray /usr/bin/pamac-tray
	install -Dm755 src/pamac-manager /usr/bin/pamac-manager
	install -Dm755 src/pamac-updater /usr/bin/pamac-updater
	install -Dm755 src/pamac-install /usr/bin/pamac-install
	#install -Dm755 src/pamac-refresh /usr/bin/pamac-refresh
	install -Dm755 src/pamac-install /usr/bin/pamac-install
	install -Dm644 data/applications/pamac-tray.desktop /etc/xdg/autostart/pamac-tray.desktop
	install -Dm644 data/applications/pamac-manager.desktop /usr/share/applications/pamac-manager.desktop
	install -Dm644 data/applications/pamac-updater.desktop /usr/share/applications/pamac-updater.desktop
	install -Dm644 data/applications/pamac-install.desktop /usr/share/applications/pamac-install.desktop
	install -Dm644 data/config/pamac.conf /etc/pamac.conf
	install -Dm644 data/dbus/org.manjaro.pamac.conf /etc/dbus-1/system.d/org.manjaro.pamac.conf
	install -Dm644 data/dbus/org.manjaro.pamac.service /usr/share/dbus-1/system-services/org.manjaro.pamac.service
	install -Dm644 data/systemd/pamac.service /usr/lib/systemd/system/pamac.service
	#install -Dm744 data/networkmanager/99_update_pamac_tray /etc/NetworkManager/dispatcher.d/99_update_pamac_tray
	install -Dm644 data/polkit/org.manjaro.pamac.policy /usr/share/polkit-1/actions/org.manjaro.pamac.policy

uninstall:
	rm -f /usr/share/icons/16x16/apps/system-software-install.png
	rm -f /usr/share/icons/24x24/status/pamac-tray-no-update.png
	rm -f /usr/share/icons/24x24/status/pamac-tray-update.png
	rm -f /usr/share/icons/32x32/apps/system-software-install.png
	rm -f /usr/share/locale/*/LC_MESSAGES/pamac.mo
	rm -f /usr/bin/pamac-daemon /usr/bin/pamac-updater /usr/bin/pamac-tray /usr/bin/pamac-manager /usr/bin/pamac-install
	rm -f /etc/xdg/autostart/pamac-tray.desktop
	rm -f /usr/share/applications/pamac-manager.desktop /usr/share/applications/pamac-updater.desktop /usr/share/applications/pamac-install.desktop
	rm -f /etc/pamac.conf
	rm -f /etc/dbus-1/system.d/org.manjaro.pamac.conf
	rm -f /usr/share/dbus-1/system-services/org.manjaro.pamac.service
	rm -f /usr/lib/systemd/system/pamac.service
	rm -f /usr/share/polkit-1/actions/org.manjaro.pamac.policy
