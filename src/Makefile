
COMMON_VALA_FLAGS = 	-X -w \
						--pkg=libalpm \
						--pkg=gio-2.0 \
						--vapidir=../vapi \
						--Xcc=-I../util \
						-X -D_FILE_OFFSET_BITS=64 \
						-X -DGETTEXT_PACKAGE="pamac" \
						--target-glib=2.38

TRANSACTION_VALA_FLAGS = 	--pkg=json-glib-1.0 \
							--pkg=gtk+-3.0 \
							--pkg=gmodule-2.0 \
							--pkg=gdk-3.0 \
							--pkg=vte-2.91

COMMON_SOURCES = 	../util/alpm-util.c \
					common.vala \
					pamac_config.vala \
					package.vala \

TRANSACTION_SOURCES = 	transaction.vala \
						choose_provider_dialog.vala \
						transaction_sum_dialog.vala \
						transaction_info_dialog.vala \
						progress_dialog.vala

PREFERENCES_SOURCES = 	preferences_dialog.vala \
						choose_ignorepkgs_dialog.vala \
						mirrors_config.vala

MANAGER_GRESOURCE_FILE = ../resources/pamac.manager.gresource.xml

UPDATER_GRESOURCE_FILE = ../resources/pamac.updater.gresource.xml

INSTALLER_GRESOURCE_FILE = ../resources/pamac.installer.gresource.xml

binaries: pamac-refresh pamac-daemon  pamac-tray  pamac-updater  pamac-manager  pamac-install

clean:
	rm -f *.c pamac-refresh pamac-daemon pamac-tray pamac-updater pamac-manager pamac-install

pamac-refresh: refresh.vala
	valac 	-o pamac-refresh \
			--pkg=gio-2.0 \
			refresh.vala

pamac-tray: ../vapi/libalpm.vapi ../util/alpm-util.c common.vala alpm_config.vala pamac_config.vala tray.vala
	valac 	-o pamac-tray \
			$(COMMON_VALA_FLAGS) \
			../util/alpm-util.c \
			--pkg=posix \
			--pkg=gtk+-3.0 \
			--pkg=libnotify \
			common.vala \
			alpm_config.vala \
			pamac_config.vala \
			tray.vala

pamac-daemon: ../vapi/libalpm.vapi ../vapi/polkit-gobject-1.vapi $(COMMON_SOURCES) mirrors_config.vala alpm_config.vala alpm_utils.vala aur.vala daemon.vala
	valac 	-o pamac-daemon \
			$(COMMON_VALA_FLAGS) \
			--pkg=posix \
			--pkg=json-glib-1.0 \
			--pkg=libsoup-2.4 \
			--pkg=polkit-gobject-1 \
			--thread \
			$(COMMON_SOURCES) \
			mirrors_config.vala \
			alpm_config.vala \
			aur.vala \
			alpm_utils.vala \
			daemon.vala

pamac-manager: ../vapi/libalpm.vapi $(COMMON_SOURCES) $(TRANSACTION_SOURCES) $(PREFERENCES_SOURCES) choose_dep_dialog.vala history_dialog.vala ../resources/manager_resources.c packages_model.vala manager_window.vala manager.vala
	valac 	-o pamac-manager \
			$(COMMON_VALA_FLAGS) \
			$(TRANSACTION_VALA_FLAGS) \
			--gresources=$(MANAGER_GRESOURCE_FILE) \
			../resources/manager_resources.c \
			$(COMMON_SOURCES) \
			$(TRANSACTION_SOURCES) \
			$(PREFERENCES_SOURCES) \
			choose_dep_dialog.vala \
			history_dialog.vala \
			packages_model.vala \
			manager_window.vala \
			manager.vala

pamac-updater: ../vapi/libalpm.vapi $(COMMON_SOURCES) $(TRANSACTION_SOURCES) $(PREFERENCES_SOURCES) ../resources/updater_resources.c updater_window.vala updater.vala
	valac 	-o pamac-updater \
			$(COMMON_VALA_FLAGS) \
			$(TRANSACTION_VALA_FLAGS) \
			--gresources=$(UPDATER_GRESOURCE_FILE) \
			../resources/updater_resources.c \
			$(COMMON_SOURCES) \
			$(TRANSACTION_SOURCES) \
			$(PREFERENCES_SOURCES) \
			updater_window.vala \
			updater.vala

pamac-install: ../vapi/libalpm.vapi $(COMMON_SOURCES) $(TRANSACTION_SOURCES) ../resources/installer_resources.c installer.vala
	valac 	-o pamac-install \
			$(COMMON_VALA_FLAGS) \
			$(TRANSACTION_VALA_FLAGS) \
			--gresources=$(INSTALLER_GRESOURCE_FILE) \
			../resources/installer_resources.c \
			$(COMMON_SOURCES) \
			$(TRANSACTION_SOURCES) \
			installer.vala
