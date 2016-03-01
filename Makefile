
prefix ?= /usr
bindir := $(prefix)/bin
libdir := $(prefix)/lib
includedir := $(prefix)/include
datadir := $(prefix)/share
localedir := $(datadir)/locale
sysconfdir ?= /etc

all:
	cd resources && make resources
	cd src && make binaries
	cd po && make gettext

clean:
	cd resources && make clean
	cd src && make clean
	cd po && make clean

install:
	mkdir -p $(prefix)/share/icons/hicolor
	cp -r data/icons/* $(prefix)/share/icons/hicolor
	mkdir -p $(localedir)
	cp -r po/locale/* $(localedir)
	install -Dm644 src/pamac.h $(includedir)/pamac.h
	install -Dm644 src/pamac.vapi $(datadir)/vala/vapi/pamac.vapi
	install -Dm755 src/libpamac.so $(libdir)/libpamac.so
	install -Dm744 src/pamac-daemon $(bindir)/pamac-daemon
	install -Dm755 src/pamac-tray $(bindir)/pamac-tray
	install -Dm755 src/pamac-manager $(bindir)/pamac-manager
	install -Dm755 src/pamac-updater $(bindir)/pamac-updater
	install -Dm755 src/pamac-install $(bindir)/pamac-install
	install -Dm755 src/pamac-refresh $(bindir)/pamac-refresh
	install -Dm644 data/applications/pamac-tray.desktop $(sysconfdir)/xdg/autostart/pamac-tray.desktop
	install -Dm644 data/applications/pamac-manager.desktop $(datadir)/applications/pamac-manager.desktop
	install -Dm644 data/applications/pamac-updater.desktop $(datadir)/applications/pamac-updater.desktop
	install -Dm644 data/applications/pamac-install.desktop $(datadir)/applications/pamac-install.desktop
	install -Dm644 data/config/pamac.conf $(sysconfdir)/pamac.conf
	install -Dm644 data/dbus/org.manjaro.pamac.conf $(sysconfdir)/dbus-1/system.d/org.manjaro.pamac.conf
	install -Dm644 data/dbus/org.manjaro.pamac.service $(datadir)/dbus-1/system-services/org.manjaro.pamac.service
	install -Dm644 data/systemd/pamac.service $(libdir)/systemd/system/pamac.service
	install -Dm744 data/networkmanager/99_update_pamac_tray $(sysconfdir)/NetworkManager/dispatcher.d/99_update_pamac_tray
	install -Dm644 data/polkit/org.manjaro.pamac.policy $(datadir)/polkit-1/actions/org.manjaro.pamac.policy
	install -Dm644 data/mime/x-alpm-package.xml $(datadir)/mime/packages/x-alpm-package.xml

uninstall:
	rm -f $(datadir)/icons/hicolor/16x16/apps/system-software-install.png
	rm -f $(datadir)/icons/hicolor/24x24/status/pamac-tray-no-update.png
	rm -f $(datadir)/icons/hicolor/24x24/status/pamac-tray-update.png
	rm -f $(datadir)/icons/hicolor/32x32/apps/system-software-install.png
	rm -f $(datadir)/locale/*/LC_MESSAGES/pamac.mo
	rm -f $(includedir)/pamac.h
	rm -f $(datadir)/vala/vapi/pamac.vapi
	rm -f $(libdir)/libpamac.so
	rm -f $(bindir)/pamac-daemon
	rm -f $(bindir)/pamac-tray
	rm -f $(bindir)/pamac-manager
	rm -f $(bindir)/pamac-updater
	rm -f $(bindir)/pamac-install
	rm -f $(bindir)/pamac-refresh
	rm -f $(sysconfdir)/xdg/autostart/pamac-tray.desktop
	rm -f $(datadir)/applications/pamac-manager.desktop
	rm -f $(datadir)/applications/pamac-updater.desktop
	rm -f $(datadir)/applications/pamac-install.desktop
	rm -f $(sysconfdir)/pamac.conf
	rm -f $(sysconfdir)/dbus-1/system.d/org.manjaro.pamac.conf
	rm -f $(datadir)/dbus-1/system-services/org.manjaro.pamac.service
	rm -f $(libdir)/systemd/system/pamac.service
	rm -f $(sysconfdir)/NetworkManager/dispatcher.d/99_update_pamac_tray
	rm -f $(datadir)/polkit-1/actions/org.manjaro.pamac.policy
	rm -f $(datadir)/mime/packages/x-alpm-package.xml
