#! /bin/sh

for i in `ls po | sed s'|.po||'` ; do
	mkdir -p "./locale/$i/LC_MESSAGES/"
	msgfmt -c po/$i.po -o "./locale/$i/LC_MESSAGES/$i.mo"
done
itstool -j ./data/polkit/org.manjaro.pamac.policy.in -o ./data/polkit/org.manjaro.pamac.policy `find "./locale/" -name *.mo`
