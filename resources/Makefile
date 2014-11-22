
MANAGER_GRESOURCE_FILE = pamac.manager.gresource.xml

MANAGER_RESOURCES_FILES = 	manager_window.ui \
							packages_chooser_dialog.ui \
							choose_dep_dialog.ui \
							history_dialog.ui \
							preferences_dialog.ui \
							progress_dialog.ui \
							choose_provider_dialog.ui \
							transaction_sum_dialog.ui \
							transaction_info_dialog.ui \
							package-available.png \
							package-install.png \
							package-installed-locked.png \
							package-installed-updated.png \
							package-reinstall.png \
							package-remove.png

UPDATER_GRESOURCE_FILE = pamac.updater.gresource.xml

UPDATER_RESOURCES_FILES = 	updater_window.ui \
							preferences_dialog.ui \
							progress_dialog.ui \
							choose_provider_dialog.ui \
							transaction_sum_dialog.ui \
							transaction_info_dialog.ui

INSTALLER_GRESOURCE_FILE = pamac.installer.gresource.xml

INSTALLER_RESOURCES_FILES = 	progress_dialog.ui \
								choose_provider_dialog.ui \
								transaction_sum_dialog.ui \
								transaction_info_dialog.ui

manager_resources.c: $(MANAGER_GRESOURCE_FILE) $(MANAGER_RESOURCES_FILES)
	glib-compile-resources $(MANAGER_GRESOURCE_FILE) --target=manager_resources.c --generate-source

updater_resources.c: $(UPDATER_GRESOURCE_FILE) $(UPDATER_RESOURCES_FILES)
	glib-compile-resources $(UPDATER_GRESOURCE_FILE) --target=updater_resources.c --generate-source

installer_resources.c: $(INSTALLER_GRESOURCE_FILE) $(INSTALLER_RESOURCES_FILES)
	glib-compile-resources $(INSTALLER_GRESOURCE_FILE) --target=installer_resources.c --generate-source

resources: manager_resources.c updater_resources.c installer_resources.c
