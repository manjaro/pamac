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

from os.path import isfile
from os import getpid, remove

pid_file = '/tmp/pamac.pid'

def pid_file_exists():
	return isfile(pid_file)

def write_pid_file():
	with open(pid_file, "w") as _file:
		_file.write(str(getpid()))

def rm_pid_file():
	if isfile(pid_file):
		remove(pid_file)

import time

def write_log_file(string):
	with open('/var/log/pamac.log', 'a') as logfile:
		logfile.write(time.strftime('[%Y-%m-%d %H:%M]') + ' {}\n'.format(string))
