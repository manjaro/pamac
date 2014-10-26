#! /bin/sh

for i in `ls po | sed s'|.po||'` ; do
	msgmerge --update po/$i.po pamac.pot
done
