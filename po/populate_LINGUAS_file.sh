#! /bin/sh

find . -name "*.po" -printf "%f\\n" | sed "s/\.po//g" | sort > LINGUAS
