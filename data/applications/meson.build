install_data('pamac-installer.desktop', install_dir: join_paths(get_option('datadir'), 'applications'))

install_data('org.manjaro.pamac.manager.desktop', install_dir: join_paths(get_option('datadir'), 'applications'))

if get_option('enable-fake-gnome-software')
	install_data('org.gnome.Software.desktop', install_dir: join_paths(get_option('datadir'), 'applications'))
endif

install_data('pamac-tray.desktop', install_dir: join_paths(get_option('sysconfdir'), 'xdg', 'autostart'))

install_data('pamac-tray-budgie.desktop', install_dir: join_paths(get_option('sysconfdir'), 'xdg', 'autostart'))
