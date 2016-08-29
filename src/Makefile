
ALPM_VALA_FLAGS = 		--pkg=libalpm \
						--pkg=gio-2.0 \
						--vapidir=../vapi \
						-X -D_FILE_OFFSET_BITS=64

COMMON_VALA_FLAGS = 	-X -w \
						--pkg=posix \
						-X -DGETTEXT_PACKAGE="pamac" \
						--target-glib=2.38

TRANSACTION_VALA_FLAGS = 	--pkg=gtk+-3.0 \
							--pkg=gdk-3.0 \
							--pkg=vte-2.91 \
							-X -lm

PAMAC_LIB_FLAGS = 	-X -I. \
					-X -L. \
					-X -lpamac \
					--vapidir=./ \
					--pkg=pamac

PAMAC_TRAY_PKG_FLAGS := 	--pkg=gtk+-3.0 \
							--pkg=libnotify

HAS_AI = `pkg-config --exists appindicator3-0.1 && echo 0`

ifeq ($(HAS_AI),0)
	PAMAC_TRAY_PKG_FLAGS += --pkg=appindicator3-0.1 \
							-D_HAS_AI=true
endif

COMMON_SOURCES = 	common.vala \
					pamac_config.vala

TRANSACTION_SOURCES = 	package.vala \
						transaction.vala \
						history_dialog.vala \
						choose_provider_dialog.vala \
						transaction_sum_dialog.vala \
						progress_box.vala

PREFERENCES_SOURCES = 	preferences_dialog.vala \
						choose_ignorepkgs_dialog.vala \
						mirrors_config.vala

TRANSACTION_GRESOURCE_FILE = ../resources/pamac.transaction.gresource.xml

MANAGER_GRESOURCE_FILE = ../resources/pamac.manager.gresource.xml

UPDATER_GRESOURCE_FILE = ../resources/pamac.updater.gresource.xml

INSTALLER_GRESOURCE_FILE = ../resources/pamac.installer.gresource.xml

binaries: pamac-refresh pamac-daemon pamac-tray pamac-updater pamac-manager pamac-install

clean:
	rm -f *.c pamac.h pamac.vapi libpamac.so pamac-refresh pamac-daemon pamac-tray pamac-updater pamac-manager pamac-install

pamac-refresh: pamac_config.vala refresh.vala
	valac 	-o pamac-refresh \
			-X -w \
			--pkg=gio-2.0 \
			--pkg=posix \
			pamac_config.vala \
			refresh.vala

pamac-tray: $(COMMON_SOURCES) alpm_config.vala tray.vala
	valac 	-o pamac-tray \
			$(COMMON_VALA_FLAGS) \
			$(PAMAC_TRAY_PKG_FLAGS) \
			$(COMMON_SOURCES) \
			tray.vala

pamac-daemon: ../vapi/libalpm.vapi ../vapi/polkit-gobject-1.vapi ../vapi/libcurl.vapi alpm_config.vala $(COMMON_SOURCES) package.vala aur.vala mirrors_config.vala daemon.vala
	valac 	-o pamac-daemon \
			$(COMMON_VALA_FLAGS) \
			$(ALPM_VALA_FLAGS) \
			--pkg=polkit-gobject-1 \
			--pkg=libcurl \
			--pkg=json-glib-1.0 \
			--pkg=libsoup-2.4 \
			--thread \
			alpm_config.vala \
			$(COMMON_SOURCES) \
			package.vala \
			aur.vala \
			mirrors_config.vala \
			daemon.vala

libpamac.so: $(COMMON_SOURCES) $(TRANSACTION_SOURCES) $(PREFERENCES_SOURCES) ../resources/transaction_resources.c
	valac	-o libpamac.so \
			-X -fPIC \
			-X --shared \
			-H pamac.h \
			--vapi=pamac.vapi \
			--library=libpamac \
			$(COMMON_VALA_FLAGS) \
			$(TRANSACTION_VALA_FLAGS) \
			--gresources=$(TRANSACTION_GRESOURCE_FILE) \
			../resources/transaction_resources.c \
			$(COMMON_SOURCES) \
			$(TRANSACTION_SOURCES) \
			$(PREFERENCES_SOURCES)

pamac-manager: libpamac.so ../resources/manager_resources.c manager_window.vala manager.vala
	valac 	-o pamac-manager \
			$(COMMON_VALA_FLAGS) \
			$(PAMAC_LIB_FLAGS) \
			--pkg=json-glib-1.0 \
			--pkg=gtk+-3.0 \
			--pkg=gdk-3.0 \
			--gresources=$(MANAGER_GRESOURCE_FILE) \
			../resources/manager_resources.c \
			manager_window.vala \
			manager.vala

pamac-updater: libpamac.so ../resources/updater_resources.c updater_window.vala updater.vala
	valac 	-o pamac-updater \
			$(COMMON_VALA_FLAGS) \
			$(PAMAC_LIB_FLAGS) \
			--pkg=json-glib-1.0 \
			--pkg=gtk+-3.0 \
			--pkg=gdk-3.0 \
			--gresources=$(UPDATER_GRESOURCE_FILE) \
			../resources/updater_resources.c \
			updater_window.vala \
			updater.vala

pamac-install: libpamac.so ../resources/installer_resources.c progress_dialog.vala installer.vala
	valac 	-o pamac-install \
			$(COMMON_VALA_FLAGS) \
			$(PAMAC_LIB_FLAGS) \
			--pkg=json-glib-1.0 \
			--pkg=gtk+-3.0 \
			--gresources=$(INSTALLER_GRESOURCE_FILE) \
			../resources/installer_resources.c \
			progress_dialog.vala \
			installer.vala
