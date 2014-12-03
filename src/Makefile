
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

UPDATER_GRESOURCE_FILE = ../resources/pamac.updater.gresource.xml

INSTALLER_GRESOURCE_FILE = ../resources/pamac.installer.gresource.xml

DIALOGS_FILES = 	choose_provider_dialog.vala \
					transaction_sum_dialog.vala \
					transaction_info_dialog.vala \
					progress_dialog.vala

pamac-refresh: refresh.vala
	valac 	-o pamac-refresh \
			--pkg=gio-2.0 \
			refresh.vala

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

pamac-manager: ../vapi/libalpm.vapi $(COMMON_SOURCES) $(DIALOGS_FILES) choose_dep_dialog.vala preferences_dialog.vala history_dialog.vala packages_chooser_dialog.vala ../resources/manager_resources.c package.vala transaction.vala packages_model.vala manager_window.vala manager.vala
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
			../resources/manager_resources.c \
			package.vala \
			transaction.vala \
			packages_model.vala \
			manager_window.vala \
			manager.vala

pamac-updater: ../vapi/libalpm.vapi $(COMMON_SOURCES) $(DIALOGS_FILES) preferences_dialog.vala ../resources/updater_resources.c transaction.vala updater_window.vala updater.vala
	valac 	-o pamac-updater \
			$(COMMON_VALA_FLAGS) \
			--pkg=gtk+-3.0 \
			--pkg=gmodule-2.0 \
			--pkg=vte-2.91 \
			--gresources=$(UPDATER_GRESOURCE_FILE) \
			$(COMMON_SOURCES) \
			$(DIALOGS_FILES) \
			preferences_dialog.vala \
			../resources/updater_resources.c \
			transaction.vala \
			updater_window.vala \
			updater.vala

pamac-install: ../vapi/libalpm.vapi $(COMMON_SOURCES) $(DIALOGS_FILES) ../resources/installer_resources.c transaction.vala installer.vala
	valac 	-o pamac-install \
			$(COMMON_VALA_FLAGS) \
			--pkg=gtk+-3.0 \
			--pkg=gmodule-2.0 \
			--pkg=vte-2.91 \
			--gresources=$(INSTALLER_GRESOURCE_FILE) \
			$(COMMON_SOURCES) \
			$(DIALOGS_FILES) \
			../resources/installer_resources.c \
			transaction.vala \
			installer.vala

binaries: pamac-refresh pamac-daemon  pamac-tray  pamac-updater  pamac-manager  pamac-install
