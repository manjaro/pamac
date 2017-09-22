
prefix ?= /usr
bindir := $(prefix)/bin
libdir := $(prefix)/lib
includedir := $(prefix)/include
datadir := $(prefix)/share
localedir := $(datadir)/locale
sysconfdir ?= /etc

use_appindicator ?= false

all:
	cd resources && make resources
	cd src && make binaries
	[ $(use_appindicator) = true ] && cd src && make pamac-tray-appindicator || echo "no appindicator support"
	cd po && make gettext

clean:
	cd resources && make clean
	cd src && make clean
	cd po && make clean

install: install_pamac-tray-appindicator
	mkdir -p $(prefix)/share/icons/hicolor
	cp -r data/icons/* $(prefix)/share/icons/hicolor
	mkdir -p $(localedir)
	cp -r po/locale/* $(localedir)
	install -Dm644 src/pamac.h $(includedir)/pamac.h
	install -Dm644 src/pamac.vapi $(datadir)/vala/vapi/pamac.vapi
	install -Dm755 src/libpamac.so $(libdir)/libpamac.so
	install -Dm755 src/pamac-clean-cache $(bindir)/pamac-clean-cache
	install -Dm755 src/pamac-user-daemon $(bindir)/pamac-user-daemon
	install -Dm744 src/pamac-system-daemon $(bindir)/pamac-system-daemon
	install -Dm755 src/pamac-tray $(bindir)/pamac-tray
	install -Dm755 src/pamac-manager $(bindir)/pamac-manager
	ln -srf $(bindir)/pamac-manager $(bindir)/pamac-updater
	install -Dm755 src/pamac-install $(bindir)/pamac-install
	install -Dm644 data/applications/pamac-tray.desktop $(sysconfdir)/xdg/autostart/pamac-tray.desktop
	install -Dm644 data/applications/pamac-manager.desktop $(datadir)/applications/pamac-manager.desktop
	install -Dm644 data/applications/pamac-updater.desktop $(datadir)/applications/pamac-updater.desktop
	install -Dm644 data/applications/pamac-install.desktop $(datadir)/applications/pamac-install.desktop
	install -Dm644 data/config/pamac.conf $(sysconfdir)/pamac.conf
	install -Dm644 data/dbus/org.manjaro.pamac.system.conf $(sysconfdir)/dbus-1/system.d/org.manjaro.pamac.system.conf
	install -Dm644 data/dbus/org.manjaro.pamac.user.service $(datadir)/dbus-1/services/org.manjaro.pamac.user.service
	install -Dm644 data/dbus/org.manjaro.pamac.system.service $(datadir)/dbus-1/system-services/org.manjaro.pamac.system.service
	install -Dm644 data/systemd/pamac-system.service $(libdir)/systemd/system/pamac-system.service
	install -Dm644 data/systemd/pamac-cleancache.service $(libdir)/systemd/system/pamac-cleancache.service
	install -Dm644 data/systemd/pamac-cleancache.timer $(libdir)/systemd/system/pamac-cleancache.timer
	install -Dm644 data/systemd/pamac-mirrorlist.service $(libdir)/systemd/system/pamac-mirrorlist.service
	install -Dm644 data/systemd/pamac-mirrorlist.timer $(libdir)/systemd/system/pamac-mirrorlist.timer
	mkdir -p $(libdir)/systemd/system/multi-user.target.wants
	ln -srf $(libdir)/systemd/system/pamac-cleancache.timer $(sysconfdir)/systemd/system/multi-user.target.wants
	ln -srf $(libdir)/systemd/system/pamac-mirrorlist.timer $(sysconfdir)/systemd/system/multi-user.target.wants
	install -Dm644 data/polkit/org.manjaro.pamac.policy $(datadir)/polkit-1/actions/org.manjaro.pamac.policy
	install -Dm644 data/mime/x-alpm-package.xml $(datadir)/mime/packages/x-alpm-package.xml

install_pamac-tray-appindicator:
	install -Dm755 src/pamac-tray-appindicator $(bindir)/pamac-tray-appindicator &> /dev/null && \
	install -Dm644 data/applications/pamac-tray-appindicator.desktop $(sysconfdir)/xdg/autostart/pamac-tray-appindicator.desktop  &> /dev/null || echo no appindicator support

uninstall:
	rm -f $(datadir)/icons/hicolor/16x16/apps/system-software-install.png
	rm -f $(datadir)/icons/hicolor/24x24/status/pamac-tray-no-update.png
	rm -f $(datadir)/icons/hicolor/24x24/status/pamac-tray-update.png
	rm -f $(datadir)/icons/hicolor/32x32/apps/system-software-install.png
	rm -f $(datadir)/locale/*/LC_MESSAGES/pamac.mo
	rm -f $(includedir)/pamac.h
	rm -f $(datadir)/vala/vapi/pamac.vapi
	rm -f $(libdir)/libpamac.so
	rm -f $(bindir)/pamac-clean-cache
	rm -f $(bindir)/pamac-user-daemon
	rm -f $(bindir)/pamac-system-daemon
	rm -f $(bindir)/pamac-tray
	rm -f $(bindir)/pamac-tray-appindicator
	rm -f $(bindir)/pamac-manager
	rm -f $(bindir)/pamac-updater
	rm -f $(bindir)/pamac-install
	rm -f $(sysconfdir)/xdg/autostart/pamac-tray.desktop
	rm -f $(sysconfdir)/xdg/autostart/pamac-tray-appindicator.desktop
	rm -f $(datadir)/applications/pamac-manager.desktop
	rm -f $(datadir)/applications/pamac-updater.desktop
	rm -f $(datadir)/applications/pamac-install.desktop
	rm -f $(sysconfdir)/pamac.conf
	rm -f $(sysconfdir)/dbus-1/system.d/org.manjaro.pamac.system.conf
	rm -f $(datadir)/dbus-1/services/org.manjaro.pamac.user.service
	rm -f $(datadir)/dbus-1/system-services/org.manjaro.pamac.system.service
	rm -f $(libdir)/systemd/system/pamac-system.service
	rm -f $(libdir)/systemd/system/pamac-cleancache.service
	rm -f $(libdir)/systemd/system/pamac-cleancache.timer
	rm -f $(libdir)/systemd/system/pamac-mirrorlist.service
	rm -f $(libdir)/systemd/system/pamac-mirrorlist.timer
	rm -f $(sysconfdir)/systemd/system/multi-user.target.wants/pamac-cleancache.timer
	rm -f $(sysconfdir)/systemd/system/multi-user.target.wants/pamac-mirrorlist.timer
	rm -f $(datadir)/polkit-1/actions/org.manjaro.pamac.policy
	rm -f $(datadir)/mime/packages/x-alpm-package.xml
