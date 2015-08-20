
MANAGER_RESOURCES_FILES = 	manager_window.ui \
							choose_dep_dialog.ui \
							history_dialog.ui \
							package-available.png \
							package-install.png \
							package-installed-locked.png \
							package-installed-updated.png \
							package-reinstall.png \
							package-remove.png

UPDATER_RESOURCES_FILES = 	updater_window.ui

TRANSACTION_RESOURCES_FILES = 	progress_dialog.ui \
								choose_provider_dialog.ui \
								transaction_sum_dialog.ui \
								transaction_info_dialog.ui

PREFERENCES_RESOURCES_FILES = 	preferences_dialog.ui \
								choose_ignorepkgs_dialog.ui

MANAGER_GRESOURCE_FILE = pamac.manager.gresource.xml

UPDATER_GRESOURCE_FILE = pamac.updater.gresource.xml

INSTALLER_GRESOURCE_FILE = pamac.installer.gresource.xml

resources: manager_resources.c updater_resources.c installer_resources.c

clean:
	rm -f *.c

manager_resources.c: $(MANAGER_GRESOURCE_FILE) $(MANAGER_RESOURCES_FILES) $(TRANSACTION_RESOURCES_FILES) $(PREFERENCES_RESOURCES_FILES)
	glib-compile-resources $(MANAGER_GRESOURCE_FILE) --target=manager_resources.c --generate-source

updater_resources.c: $(UPDATER_GRESOURCE_FILE) $(UPDATER_RESOURCES_FILES) $(TRANSACTION_RESOURCES_FILES) $(PREFERENCES_RESOURCES_FILES)
	glib-compile-resources $(UPDATER_GRESOURCE_FILE) --target=updater_resources.c --generate-source

installer_resources.c: $(INSTALLER_GRESOURCE_FILE) $(TRANSACTION_RESOURCES_FILES)
	glib-compile-resources $(INSTALLER_GRESOURCE_FILE) --target=installer_resources.c --generate-source
