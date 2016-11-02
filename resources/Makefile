
MANAGER_RESOURCES_FILES = 	manager_window.ui \
							history_dialog.ui \
							package-available.png \
							package-available-locked.png \
							package-install.png \
							package-installed-locked.png \
							package-installed-updated.png \
							package-reinstall.png \
							package-remove.png

UPDATER_RESOURCES_FILES = 	updater_window.ui

INSTALLER_RESOURCES_FILES = 	progress_dialog.ui

TRANSACTION_RESOURCES_FILES = 	progress_box.ui \
								choose_provider_dialog.ui \
								transaction_sum_dialog.ui \
								preferences_dialog.ui \
								choose_ignorepkgs_dialog.ui

TRANSACTION_GRESOURCE_FILE = pamac.transaction.gresource.xml

MANAGER_GRESOURCE_FILE = pamac.manager.gresource.xml

UPDATER_GRESOURCE_FILE = pamac.updater.gresource.xml

INSTALLER_GRESOURCE_FILE = pamac.installer.gresource.xml

resources: transaction_resources.c manager_resources.c updater_resources.c installer_resources.c

clean:
	rm -f *.c

transaction_resources.c: $(TRANSACTION_GRESOURCE_FILE) $(TRANSACTION_RESOURCES_FILES)
	glib-compile-resources $(TRANSACTION_GRESOURCE_FILE) --target=transaction_resources.c --generate-source

manager_resources.c: $(MANAGER_GRESOURCE_FILE) $(MANAGER_RESOURCES_FILES)
	glib-compile-resources $(MANAGER_GRESOURCE_FILE) --target=manager_resources.c --generate-source

updater_resources.c: $(UPDATER_GRESOURCE_FILE) $(UPDATER_RESOURCES_FILES)
	glib-compile-resources $(UPDATER_GRESOURCE_FILE) --target=updater_resources.c --generate-source

installer_resources.c: $(INSTALLER_GRESOURCE_FILE) $(INSTALLER_RESOURCES_FILES)
	glib-compile-resources $(INSTALLER_GRESOURCE_FILE) --target=installer_resources.c --generate-source
