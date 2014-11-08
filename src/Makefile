COMMON_VALA_FLAGS = 	--pkg=libalpm \
						--pkg=gio-2.0 \
						--pkg=posix \
						--pkg=json-glib-1.0 \
						--pkg=libsoup-2.4 \
						--vapidir=../vapi \
						--Xcc=-I../util \
						-X -D_FILE_OFFSET_BITS=64 \
						-X -DGETTEXT_PACKAGE="pamac" \
						--target-glib=2.38

COMMON_SOURCES = 	../util/alpm-util.c \
					alpm_config.vala \
					pamac_config.vala \
					aur.vala \
					common.vala

MANAGER_GRESOURCE_FILE = ../resources/pamac.manager.gresource.xml

MANAGER_RESOURCES_FILES = 	../resources/manager_window.ui \
					../resources/packages_chooser_dialog.ui \
					../resources/choose_dep_dialog.ui \
					../resources/history_dialog.ui \
					../resources/preferences_dialog.ui \
					../resources/progress_dialog.ui \
					../resources/choose_provider_dialog.ui \
					../resources/transaction_sum_dialog.ui \
					../resources/transaction_info_dialog.ui \
					../resources/package-available.png \
					../resources/package-install.png \
					../resources/package-installed-locked.png \
					../resources/package-installed-updated.png \
					../resources/package-reinstall.png \
					../resources/package-remove.png

UPDATER_GRESOURCE_FILE = ../resources/pamac.updater.gresource.xml

UPDATER_RESOURCES_FILES = 	../resources/updater_window.ui \
					../resources/preferences_dialog.ui \
					../resources/progress_dialog.ui \
					../resources/choose_provider_dialog.ui \
					../resources/transaction_sum_dialog.ui \
					../resources/transaction_info_dialog.ui

INSTALLER_GRESOURCE_FILE = ../resources/pamac.installer.gresource.xml

INSTALLER_RESOURCES_FILES = 	../resources/progress_dialog.ui \
					../resources/choose_provider_dialog.ui \
					../resources/transaction_sum_dialog.ui \
					../resources/transaction_info_dialog.ui

DIALOGS_FILES = 	choose_provider_dialog.vala \
					transaction_sum_dialog.vala \
					transaction_info_dialog.vala \
					progress_dialog.vala

pamac-daemon: ../vapi/libalpm.vapi ../vapi/polkit-gobject-1.vapi $(COMMON_SOURCES) daemon.vala
	valac 	-o pamac-daemon \
			$(COMMON_VALA_FLAGS) \
			--pkg=polkit-gobject-1 \
			--thread \
			$(COMMON_SOURCES) \
			daemon.vala

pamac-tray: ../vapi/libalpm.vapi $(COMMON_SOURCES) tray.vala
	valac 	-o pamac-tray \
			$(COMMON_VALA_FLAGS) \
			--pkg=gtk+-3.0 \
			--pkg=libnotify \
			$(COMMON_SOURCES) \
			tray.vala

manager_resources.c: $(MANAGER_GRESOURCE_FILE) $(MANAGER_RESOURCES_FILES)
	glib-compile-resources $(MANAGER_GRESOURCE_FILE) --sourcedir=../resources --target=manager_resources.c --generate-source

updater_resources.c: $(UPDATER_GRESOURCE_FILE) $(UPDATER_RESOURCES_FILES)
	glib-compile-resources $(UPDATER_GRESOURCE_FILE) --sourcedir=../resources --target=updater_resources.c --generate-source

installer_resources.c: $(INSTALLER_GRESOURCE_FILE) $(INSTALLER_RESOURCES_FILES)
	glib-compile-resources $(INSTALLER_GRESOURCE_FILE) --sourcedir=../resources --target=installer_resources.c --generate-source

pamac-manager: ../vapi/libalpm.vapi $(COMMON_SOURCES) $(DIALOGS_FILES) choose_dep_dialog.vala preferences_dialog.vala history_dialog.vala packages_chooser_dialog.vala manager_resources.c package.vala transaction.vala packages_model.vala manager_window.vala manager.vala
	valac 	-o pamac-manager \
			$(COMMON_VALA_FLAGS) \
			--pkg=gtk+-3.0 \
			--pkg=gmodule-2.0 \
			--pkg=gdk-3.0 \
			--pkg=vte-2.91 \
			--gresources=$(MANAGER_GRESOURCE_FILE) \
			$(COMMON_SOURCES) \
			$(DIALOGS_FILES) \
			choose_dep_dialog.vala \
			preferences_dialog.vala \
			history_dialog.vala \
			packages_chooser_dialog.vala \
			manager_resources.c \
			package.vala \
			transaction.vala \
			packages_model.vala \
			manager_window.vala \
			manager.vala

pamac-updater: ../vapi/libalpm.vapi $(COMMON_SOURCES) $(DIALOGS_FILES) preferences_dialog.vala updater_resources.c transaction.vala updater_window.vala updater.vala
	valac 	-o pamac-updater \
			$(COMMON_VALA_FLAGS) \
			--pkg=gtk+-3.0 \
			--pkg=gmodule-2.0 \
			--pkg=vte-2.91 \
			--gresources=$(UPDATER_GRESOURCE_FILE) \
			$(COMMON_SOURCES) \
			$(DIALOGS_FILES) \
			preferences_dialog.vala \
			updater_resources.c \
			transaction.vala \
			updater_window.vala \
			updater.vala

pamac-install: ../vapi/libalpm.vapi $(COMMON_SOURCES) $(DIALOGS_FILES) installer_resources.c transaction.vala installer.vala
	valac 	-o pamac-install \
			$(COMMON_VALA_FLAGS) \
			--pkg=gtk+-3.0 \
			--pkg=gmodule-2.0 \
			--pkg=vte-2.91 \
			--gresources=$(INSTALLER_GRESOURCE_FILE) \
			$(COMMON_SOURCES) \
			$(DIALOGS_FILES) \
			installer_resources.c \
			transaction.vala \
			installer.vala

all: pamac-daemon pamac-tray pamac-updater pamac-manager pamac-install

clean:
	rm -f *.c pamac-daemon pamac-tray pamac-updater pamac-manager pamac-install

install:
	install -Dm744 pamac-daemon /usr/bin/pamac-daemon
	install -Dm755 pamac-tray /usr/bin/pamac-tray
	install -Dm755 pamac-manager /usr/bin/pamac-manager
	install -Dm755 pamac-updater /usr/bin/pamac-updater
	install -Dm755 pamac-install /usr/bin/pamac-install

uninstall:
	rm -f /usr/bin/pamac-daemon /usr/bin/pamac-updater /usr/bin/pamac-tray /usr/bin/pamac-manager /usr/bin/pamac-install
