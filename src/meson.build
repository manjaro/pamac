gobject = dependency('gobject-2.0')
gio = dependency('gio-2.0')
libsoup = dependency('libsoup-2.4')
libnotify = dependency('libnotify')
gio_unix = dependency('gio-unix-2.0')

libpamac = dependency('pamac', version : '>=11.2')

gtk3 = dependency('gtk+-3.0', version : '>=3.22')
libhandy = dependency('libhandy-1')

common_vala_args = ['--pkg=posix', '--target-glib=2.38', '--vapidir=' + join_paths(meson.source_root(), 'vapi')]
common_c_args = ['-DGETTEXT_PACKAGE="pamac"']

executable('pamac',
	sources: ['version.vala', 'transaction-cli.vala', 'cli.vala'],
	dependencies: [gio, libpamac],
	vala_args: [common_vala_args, '--pkg=linux'],
	c_args: common_c_args,
	install: true)

executable('pamac-tray',
	sources: ['tray.vala', 'tray-gtk.vala'],
	dependencies: [gtk3, libnotify, libpamac],
	vala_args: common_vala_args,
	c_args: common_c_args,
	install: true)

libpamac_gtk = library('pamac-gtk',
	sources: ['transaction-gtk.vala', 'choose_provider_dialog.vala', 'choose_pkgs_dialog.vala',
			'transaction_sum_dialog.vala', 'summary_row.vala', 'progress_box.vala', 'version.vala',
			'local_config.vala', transaction_resources],
	dependencies: [gtk3, libhandy, libpamac],
	vala_args: common_vala_args,
	c_args: common_c_args,
	install: true,
	install_dir: [true, true, true])

libpamac_gtk_dep = declare_dependency(link_with: libpamac_gtk)

executable('pamac-manager',
	sources: ['version.vala', 'history_dialog.vala', 'updates_dialog.vala', 'preferences_dialog.vala',
			'package_row.vala', 'simple_row.vala', 'back_row.vala', 'manager_window.vala', 'manager.vala',
			'search-provider.vala', manager_resources],
	dependencies: [gtk3, libhandy, gio_unix, libpamac, libpamac_gtk_dep],
	vala_args: common_vala_args,
	c_args: common_c_args,
	install: true)

if get_option('enable-fake-gnome-software')
	executable('gnome-software',
		sources: ['fake_gnome_software.vala'],
		dependencies: [gio],
		install: true)
endif

executable('pamac-installer',
	sources: ['progress_dialog.vala', 'installer.vala', installer_resources],
	dependencies: [gtk3, libhandy, gio_unix, libpamac, libpamac_gtk_dep],
	vala_args: common_vala_args,
	c_args: common_c_args,
	install: true)
