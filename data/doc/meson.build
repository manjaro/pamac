A2X = find_program('a2x')
GZIP = find_program('gzip')

pamac_8 = custom_target('pamac.8 manpage',
	input: 'pamac.8.asciidoc',
	command: [A2X, '-f', 'manpage', '-D', '@OUTDIR@', '@INPUT@'],
	output: 'pamac.8')

pamac_conf_5 = custom_target('pamac.conf.5 manpage',
	input: 'pamac.conf.5.asciidoc',
	command: [A2X, '-f', 'manpage', '-D', '@OUTDIR@', '@INPUT@'],
	output: 'pamac.conf.5')

custom_target('gzip pamac.8 manpage',
	depends: pamac_8,
	command: [GZIP, '-k', '-f', join_paths(meson.current_build_dir(), 'pamac.8')],
	output: 'pamac.8.gz',
	install: true,
	install_dir : join_paths(get_option('mandir'), 'man8'))

custom_target('gzip pamac.conf.5 manpage',
	depends: pamac_conf_5,
	command: [GZIP, '-k', '-f', join_paths(meson.current_build_dir(), 'pamac.conf.5')],
	output: 'pamac.conf.5.gz',
	install: true,
	install_dir : join_paths(get_option('mandir'), 'man5'))
