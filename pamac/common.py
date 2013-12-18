#! /usr/bin/python3
# -*- coding:utf-8 -*-

# pamac - A Python implementation of alpm
# Copyright (C) 2013 Guillaume Benoit <guillaume@manjaro.org>
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

# i18n
import gettext
gettext.bindtextdomain('pamac', '/usr/share/locale')
gettext.textdomain('pamac')
_ = gettext.gettext

def format_size(size):
	KiB_size = size / 1024
	if KiB_size < 1000:
		size_string = _('%.1f KiB') % (KiB_size)
		return size_string
	else:
		size_string = _('%.2f MiB') % (KiB_size / 1024)
		return size_string

def format_pkg_name(name):
	unwanted = ['>','<','=']
	for i in unwanted:
		index = name.find(i)
		if index != -1:
			name = name[0:index]
	return name

from os.path import isfile, join
from os import getpid, remove

from pamac import config

pid_file = '/tmp/pamac.pid'
lock_file = join(config.pacman_conf.options['DBPath'], 'db.lck')

def lock_file_exists():
	return isfile(lock_file)

def pid_file_exists():
	return isfile(pid_file)

def write_pid_file():
	with open(pid_file, "w") as _file:
		_file.write(str(getpid()))

def rm_pid_file():
	if isfile(pid_file):
		remove(pid_file)

def rm_lock_file():
	if isfile(lock_file):
		remove(lock_file)

import time

def write_log_file(string):
	with open('/var/log/pamac.log', 'a') as logfile:
		logfile.write(time.strftime('[%Y-%m-%d %H:%M]') + ' {}\n'.format(string))
