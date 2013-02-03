#! /usr/bin/python
# -*-coding:utf-8-*-

def format_size(size):
	KiB_size = size / 1024
	if KiB_size < 1000:
		size_string = '%.1f KiB' % (KiB_size)
		return size_string
	else:
		size_string = '%.2f MiB' % (KiB_size / 1024)
		return size_string

def format_pkg_name(name):
	unwanted = ['>','<','=']
	for i in unwanted:
		index = name.find(i)
		if index != -1:
			name = name[0:index]
		return name
