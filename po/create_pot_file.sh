#! /bin/sh

xgettext --from-code=UTF-8 --add-location=file \
	--package-name=Pamac --package-version=2.1 --msgid-bugs-address=guillaume@manjaro.org \
	--files-from=files_to_translate --keyword=translatable --output=pamac.pot
