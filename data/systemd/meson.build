configure_file(
	input: 'pamac-daemon.service.in',
	output: 'pamac-daemon.service',
	configuration: conf,
	install: true,
	install_dir: join_paths(get_option('libdir'), 'systemd/system'),
)

configure_file(
	input: 'pamac-cleancache.service.in',
	output: 'pamac-cleancache.service',
	configuration: conf,
	install: true,
	install_dir: join_paths(get_option('libdir'), 'systemd/system'),
)

install_data('pamac-cleancache.timer', install_dir: join_paths(get_option('libdir'), 'systemd/system'))
if (find_program('pacman-mirrors', required: false).found())
	install_data('pamac-mirrorlist.service', install_dir: join_paths(get_option('libdir'), 'systemd/system'))
	install_data('pamac-mirrorlist.timer', install_dir: join_paths(get_option('libdir'), 'systemd/system'))
endif
