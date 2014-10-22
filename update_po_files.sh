#! /bin/sh

for i in `ls po | sed s'|.po||'` ; do
	msgmerge --update --no-fuzzy-matching po/$i.po pamac.pot
done
