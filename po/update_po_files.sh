#! /bin/sh

for i in `ls po | sed s'|.po||'` ; do
	msgmerge --update ./$i.po pamac.pot
done
