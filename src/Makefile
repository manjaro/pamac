
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
					--pkg=pamac \

COMMON_SOURCES = 	common.vala \
					package.vala \
					pamac_config.vala

TRANSACTION_SOURCES = 	transaction.vala \
						choose_provider_dialog.vala \
						transaction_sum_dialog.vala \
						progress_box.vala

PREFERENCES_SOURCES = 	preferences_dialog.vala \
						choose_ignorepkgs_dialog.vala \
						mirrors_config.vala

TRANSACTION_GRESOURCE_FILE = ../resources/pamac.transaction.gresource.xml

MANAGER_GRESOURCE_FILE = ../resources/pamac.manager.gresource.xml

INSTALLER_GRESOURCE_FILE = ../resources/pamac.installer.gresource.xml

binaries: pamac-clean-cache pamac-user-daemon pamac-system-daemon pamac-tray pamac-manager pamac-install

clean:
	rm -f *.c pamac.h pamac.vapi libpamac.so pamac-user-daemon pamac-system-daemon pamac-tray pamac-tray-appindicator pamac-manager pamac-install

pamac-clean-cache: pamac_config.vala clean_cache.vala
	valac 	-o pamac-clean-cache \
			$(COMMON_VALA_FLAGS) \
			--pkg=gio-2.0 \
			pamac_config.vala \
			clean_cache.vala

pamac-tray: $(COMMON_SOURCES) alpm_config.vala tray.vala tray-gtk.vala
	valac 	-o pamac-tray \
			$(COMMON_VALA_FLAGS) \
			--pkg=gtk+-3.0 \
			--pkg=libnotify \
			$(COMMON_SOURCES) \
			tray-gtk.vala \
			tray.vala

pamac-tray-appindicator: $(COMMON_SOURCES) alpm_config.vala tray.vala tray-appindicator.vala
	valac 	-o pamac-tray-appindicator \
			$(COMMON_VALA_FLAGS) \
			--pkg=gtk+-3.0 \
			--pkg=appindicator3-0.1 \
			--pkg=libnotify \
			$(COMMON_SOURCES) \
			tray-appindicator.vala \
			tray.vala

pamac-user-daemon: ../vapi/libalpm.vapi alpm_config.vala common.vala package.vala aur.vala user_daemon.vala
	valac 	-o pamac-user-daemon \
			$(COMMON_VALA_FLAGS) \
			$(ALPM_VALA_FLAGS) \
			--pkg=json-glib-1.0 \
			--pkg=libsoup-2.4 \
			--pkg=appstream-glib \
			--thread \
			alpm_config.vala \
			common.vala \
			package.vala \
			aur.vala \
			user_daemon.vala

pamac-system-daemon: ../vapi/libalpm.vapi ../vapi/polkit-gobject-1.vapi ../vapi/libcurl.vapi alpm_config.vala $(COMMON_SOURCES) aur.vala mirrors_config.vala system_daemon.vala
	valac 	-o pamac-system-daemon \
			$(COMMON_VALA_FLAGS) \
			$(ALPM_VALA_FLAGS) \
			--pkg=polkit-gobject-1 \
			--pkg=libcurl \
			--pkg=json-glib-1.0 \
			--pkg=libsoup-2.4 \
			--thread \
			alpm_config.vala \
			$(COMMON_SOURCES) \
			aur.vala \
			mirrors_config.vala \
			system_daemon.vala

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

pamac-manager: libpamac.so ../resources/manager_resources.c history_dialog.vala manager_window.vala manager.vala
	valac 	-o pamac-manager \
			$(COMMON_VALA_FLAGS) \
			$(PAMAC_LIB_FLAGS) \
			--pkg=gtk+-3.0 \
			--pkg=gdk-3.0 \
			--pkg=libsoup-2.4 \
			--gresources=$(MANAGER_GRESOURCE_FILE) \
			../resources/manager_resources.c \
			history_dialog.vala \
			manager_window.vala \
			manager.vala

pamac-install: libpamac.so ../resources/installer_resources.c progress_dialog.vala installer.vala
	valac 	-o pamac-install \
			$(COMMON_VALA_FLAGS) \
			$(PAMAC_LIB_FLAGS) \
			--pkg=gtk+-3.0 \
			--gresources=$(INSTALLER_GRESOURCE_FILE) \
			../resources/installer_resources.c \
			progress_dialog.vala \
			installer.vala
