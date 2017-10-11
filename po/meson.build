i18n = import('i18n')

run_command('populate_LINGUAS_file.sh')

i18n.gettext('pamac',
	args : ['--from-code=UTF-8',
		'--add-location=file',
		'--package-name=Pamac',
		'--msgid-bugs-address=guillaume@manjaro.org',
		'--keyword=translatable']
)
