gobject = dependency('gobject-2.0')
gio = dependency('gio-2.0')
gthread = dependency('gthread-2.0')
libalpm = dependency('libalpm')
json = dependency('json-glib-1.0')
libsoup = dependency('libsoup-2.4')
polkit = dependency('polkit-gobject-1')
libcurl = dependency('libcurl')
libnotify = dependency('libnotify')
appstream = dependency('appstream-glib')

if get_option('enable-appindicator')
	appindicator = dependency('appindicator3-0.1')
endif

gtk3 = dependency('gtk+-3.0', version : '>=3.22')
gdk3 = dependency('gdk-3.0')
gdk_pixbuf2 = dependency('gdk-pixbuf-2.0')
vte3 = dependency('vte-2.91')

posix = meson.get_compiler('vala').find_library('posix')
math = meson.get_compiler('c').find_library('m')

vala_deps = [gobject]
alpm_deps = [libalpm, gio, posix]

alpm_vala_args = ['--vapidir=../vapi']
alpm_c_args = ['-D_FILE_OFFSET_BITS=64']

common_vala_args = ['--pkg=posix', '--target-glib=2.38']
common_c_args = ['-DGETTEXT_PACKAGE="pamac"']

common_sources = ['common.vala', 'package.vala', 'pamac_config.vala']
transaction_sources = ['transaction.vala', 'choose_provider_dialog.vala', 'transaction_sum_dialog.vala', 'progress_box.vala']
preferences_sources = ['preferences_dialog.vala', 'choose_ignorepkgs_dialog.vala', 'mirrors_config.vala']

executable('pamac-clean-cache',
	sources: ['pamac_config.vala', 'clean_cache.vala'],
	dependencies: [gio],
	vala_args: common_vala_args,
	c_args: common_c_args,
	install: true)

executable('pamac-tray',
	sources: [common_sources, 'tray.vala', 'tray-gtk.vala'],
	dependencies: [gtk3, libnotify],
	vala_args: common_vala_args,
	c_args: common_c_args,
	install: true)

if get_option('enable-appindicator')
	executable('pamac-tray-appindicator',
		sources: [common_sources, 'tray.vala', 'tray-appindicator.vala'],
		dependencies: [gtk3, libnotify, appindicator],
		vala_args: common_vala_args,
		c_args: common_c_args,
		install: true)
endif

executable('pamac-user-daemon',
	sources: ['alpm_config.vala', 'common.vala', 'package.vala', 'aur.vala', 'user_daemon.vala'],
	dependencies: [vala_deps, alpm_deps, json, libsoup, appstream],
	vala_args: [common_vala_args, alpm_vala_args, '--thread'],
	c_args: [common_c_args, alpm_c_args],
	install : true)

executable('pamac-system-daemon',
	sources: [common_sources, 'alpm_config.vala', 'aur.vala', 'mirrors_config.vala', 'system_daemon.vala'],
	dependencies: [vala_deps, alpm_deps, json, libsoup, polkit, libcurl, appstream],
	vala_args: [common_vala_args, alpm_vala_args, '--thread'],
	c_args: [common_c_args, alpm_c_args],
	install : true)

libpamac = library('pamac',
	sources: [common_sources, transaction_sources, preferences_sources, transaction_resources],
	dependencies: [gtk3, gdk3, vte3, posix, math],
	vala_args: common_vala_args,
	c_args: common_c_args,
	install: true,
	install_dir: [true, true, true])

libpamac_dep = declare_dependency(link_with: libpamac)

executable('pamac-manager',
	sources: ['history_dialog.vala', 'manager_window.vala', 'manager.vala', manager_resources],
	dependencies: [vala_deps, gtk3, gdk3, gdk_pixbuf2, libsoup, libpamac_dep],
	vala_args: common_vala_args,
	c_args: common_c_args,
	install: true)

# create pamac-updater symlink
meson.add_install_script('sh', '-c',
	'ln -sf pamac-manager ${DESTDIR}/${MESON_INSTALL_PREFIX}/@0@/pamac-updater'.format(get_option('bindir')))
 
executable('pamac-installer',
	sources: ['progress_dialog.vala', 'installer.vala', installer_resources],
	dependencies: [gtk3, libpamac_dep],
	vala_args: common_vala_args,
	c_args: common_c_args,
	install: true)
