#! /bin/sh

<<<<<<< HEAD
for i in `ls ./ | sed s'|.po||'` ; do
	msgmerge --update --no-fuzzy-matching --add-location=file --backup=none ./$i.po pamac.pot
=======
for i in `ls po | sed s'|.po||'` ; do
	msgmerge --update ./$i.po pamac.pot
>>>>>>> b8153ea47435633a8eb825f30c0976245b417a7e
done
