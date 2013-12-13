#! /usr/bin/python3
# -*- coding:utf-8 -*-

# pamac - A Python implementation of alpm
# Copyright (C) 2011 Rémy Oudompheng <remy@archlinux.org>
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

import os
import glob
import argparse
import collections
import warnings

import pyalpm

class InvalidSyntax(Warning):
	def __init__(self, filename, problem, arg):
		self.filename = filename
		self.problem = problem
		self.arg = arg

	def __str__(self):
		return "unable to parse %s, %s: %r" % (self.filename, self.problem, self.arg)

# Options that may occur several times in a section. Their values should be
# accumulated in a list.
LIST_OPTIONS = (
	'CacheDir',
	'HoldPkg',
	'SyncFirst',
	'IgnoreGroup',
	'IgnorePkg',
	'NoExtract',
	'NoUpgrade',
	'Server'
)

SINGLE_OPTIONS = (
	'RootDir',
	'DBPath',
	'GPGDir',
	'LogFile',
	'UseDelta',
	'Architecture',
	'XferCommand',
	'CleanMethod',
	'SigLevel',
	'LocalFileSigLevel',
	'RemoteFileSigLevel'
)

BOOLEAN_OPTIONS = (
	'UseSyslog',
	'TotalDownload',
	'CheckSpace',
	'VerbosePkgLists',
	'ILoveCandy',
	'Color'
)

def define_siglevel(default_level, conf_string):
	for directive in conf_string.split():
		affect_package = False
		affect_database = False
		if 'Package' in directive:
			affect_package = True
		elif 'Database' in directive:
			affect_database = True
		else:
			affect_package = True
			affect_database = True
		if 'Never' in directive:
			if affect_package:
				default_level &= ~pyalpm.SIG_PACKAGE
				default_level |= pyalpm.SIG_PACKAGE_SET
			if affect_database:
				default_level &= ~pyalpm.SIG_DATABASE
		elif 'Optional' in directive:
			if affect_package:
				default_level |= pyalpm.SIG_PACKAGE
				default_level |= pyalpm.SIG_PACKAGE_OPTIONAL
				default_level |= pyalpm.SIG_PACKAGE_SET
			if affect_database:
				default_level |= pyalpm.SIG_DATABASE
				default_level |= pyalpm.SIG_DATABASE_OPTIONAL
		elif 'Required' in directive:
			if affect_package:
				default_level |= pyalpm.SIG_PACKAGE
				default_level &= ~pyalpm.SIG_PACKAGE_OPTIONAL
				default_level |= pyalpm.SIG_PACKAGE_SET
			if affect_database:
				default_level |= pyalpm.SIG_DATABASE
				default_level &= ~pyalpm.SIG_DATABASE_OPTIONAL
		elif 'TrustedOnly' in directive:
			if affect_package:
				default_level &= ~pyalpm.SIG_PACKAGE_MARGINAL_OK
				default_level &= ~pyalpm.SIG_PACKAGE_UNKNOWN_OK
				default_level |= pyalpm.SIG_PACKAGE_TRUST_SET
			if affect_database:
				default_level &= ~pyalpm.SIG_DATABASE_MARGINAL_OK
				default_level &= ~pyalpm.SIG_DATABASE_UNKNOWN_OK
		elif 'TrustAll' in directive:
			if affect_package:
				default_level |= pyalpm.SIG_PACKAGE_MARGINAL_OK
				default_level |= pyalpm.SIG_PACKAGE_UNKNOWN_OK
				default_level |= pyalpm.SIG_PACKAGE_TRUST_SET
			if affect_database:
				default_level |= pyalpm.SIG_DATABASE_MARGINAL_OK
				default_level |= pyalpm.SIG_DATABASE_UNKNOWN_OK
		else:
			print('unrecognized siglevel: {}'.format(conf_string))
	return default_level

def merge_siglevel(base_level, over_level):
	if not over_level & pyalpm.SIG_PACKAGE_SET:
		over_level |= base_level & pyalpm.SIG_PACKAGE
		over_level |= base_level & pyalpm.SIG_PACKAGE_OPTIONAL
	if not over_level & pyalpm.SIG_PACKAGE_TRUST_SET:
		over_level |= base_level & pyalpm.SIG_PACKAGE_MARGINAL_OK
		over_level |= base_level & pyalpm.SIG_PACKAGE_UNKNOWN_OK
	return over_level

def pacman_conf_enumerator(path):
	filestack = []
	current_section = None
	filestack.append(open(path))
	while len(filestack) > 0:
		f = filestack[-1]
		line = f.readline()
		if len(line) == 0:
			# end of file
			filestack.pop()
			continue

		line = line.strip()
		if len(line) == 0:
			continue
		if line[0] == '#':
			continue
		if line[0] == '[' and line[-1] == ']':
			current_section = line[1:-1]
			continue
		if not current_section:
			raise InvalidSyntax(f.name, 'statement outside of a section', line)
		# read key, value
		key, equal, value = [x.strip() for x in line.partition('=')]

		# include files
		if equal == '=' and key == 'Include':
			filestack.extend(open(f) for f in glob.glob(value))
			continue
		if current_section != 'options':
			# repos only have the Server option
			if key == 'Server' and equal == '=':
				yield (current_section, 'Server', value)
			elif key == 'SigLevel' and equal == '=':
				yield (current_section, 'SigLevel', value)
			else:
				raise InvalidSyntax(f.name, 'invalid key for repository configuration', line)
			continue
		if equal == '=':
			if key in LIST_OPTIONS:
				for val in value.split():
					yield (current_section, key, val)
			elif key in SINGLE_OPTIONS:
				yield (current_section, key, value)
			else:
				warnings.warn(InvalidSyntax(f.name, 'unrecognized option', key))
		else:
			if key in BOOLEAN_OPTIONS:
				yield (current_section, key, 1)
			else:
				warnings.warn(InvalidSyntax(f.name, 'unrecognized option', key))

class PacmanConfig:
	def __init__(self, conf = None, options = None):
		self.options = {}
		self.repos = collections.OrderedDict()
		self.options["RootDir"] = "/"
		self.options["DBPath"]  = "/var/lib/pacman"
		self.options["GPGDir"]  = "/etc/pacman.d/gnupg/"
		self.options["LogFile"] = "/var/log/pacman.log"
		self.options["Architecture"] = os.uname()[-1]
		self.default_siglevel = pyalpm.SIG_PACKAGE | pyalpm.SIG_PACKAGE_OPTIONAL | pyalpm.SIG_DATABASE | pyalpm.SIG_DATABASE_OPTIONAL
		if conf:
			self.load_from_file(conf)
		if options:
			self.load_from_options(options)

	def load_from_file(self, filename):
		for section, key, value in pacman_conf_enumerator(filename):
			if section == 'options':
				if key == 'Architecture' and value == 'auto':
					continue
				if key in LIST_OPTIONS:
					self.options.setdefault(key, []).append(value)
				else:
					self.options[key] = value
					# define here default_siglevel to make it usable for servers
					if key == 'SigLevel':
						self.default_siglevel = define_siglevel(self.default_siglevel, self.options["SigLevel"])
			else:
				if not self.repos.get(section):
					self.repos[section] = ([], self.default_siglevel)
				if key == 'Server':
					self.repos[section][0].append(value)
				elif key == 'SigLevel':
					urls = self.repos[section][0].copy()
					new_siglevel = define_siglevel(self.repos[section][1], value)
					self.repos[section] = (urls, new_siglevel)
		if not "CacheDir" in self.options:
			self.options["CacheDir"]= ["/var/cache/pacman/pkg"]

	def load_from_options(self, options):
		global _logmask
		if options.root:
			self.options["RootDir"] = options.root
		if options.dbpath:
			self.options["DBPath"] = options.dbpath
		if options.gpgdir:
			self.options["GPGDir"] = options.gpgdir
		if options.arch:
			self.options["Architecture"] = options.arch
		if options.logfile:
			self.options["LogFile"] = options.logfile
		if options.cachedir:
			self.options["CacheDir"] = [option.cachedir]
		if options.debug:
			_logmask = 0xffff

	def initialize_alpm(self):
		h = pyalpm.Handle(self.options["RootDir"], self.options["DBPath"])
		h.arch = self.options["Architecture"]
		h.logfile = self.options["LogFile"]
		h.gpgdir = self.options["GPGDir"]
		h.cachedirs = self.options["CacheDir"]
		if "IgnoreGroup" in self.options:
			h.ignoregrps = self.options["IgnoreGroup"]
		if "IgnorePkg" in self.options:
			h.ignorepkgs = self.options["IgnorePkg"]
		if "NoExtract" in self.options:
			h.noextracts = self.options["NoExtract"]
		if "NoUpgrade" in self.options:
			h.noupgrades = self.options["NoUpgrade"]
		if "UseSyslog" in self.options:
			h.usesyslog = self.options["UseSyslog"]
		if "CheckSpace" in self.options:
			h.checkspace = self.options["CheckSpace"]
		# register default siglevel, it should have been updated previously
		h.siglevel = self.default_siglevel
		# update localsiglevel
		if "LocalFileSigLevel" in self.options:
			localsiglevel = define_siglevel(self.default_siglevel, self.options["LocalFileSigLevel"])
			localsiglevel = merge_siglevel(self.default_siglevel, localsiglevel)
		else:
			localsiglevel = self.default_siglevel
		# define localsiglevel
		h.localsiglevel = localsiglevel
		# update remotesiglevel
		if "RemoteFileSigLevel" in self.options:
			remotesiglevel = define_siglevel(self.default_siglevel, self.options["RemoteFileSigLevel"])
			remotesiglevel = merge_siglevel(self.default_siglevel, remotesiglevel)
		else:
			remotesiglevel = self.default_siglevel
		# define remotesiglevel
		h.remotesiglevel = remotesiglevel
		# set sync databases
		for repo, servers in self.repos.items():
			db = h.register_syncdb(repo, servers[1])
			db_servers = []
			for rawurl in servers[0]:
				url = rawurl.replace("$repo", repo)
				url = url.replace("$arch", self.options["Architecture"])
				db_servers.append(url)
			db.servers = db_servers
		return h

	def __str__(self):
		return("PacmanConfig(options={}, repos={})".format(self.options, self.repos))

pacman_conf = PacmanConfig(conf = "/etc/pacman.conf")
handle = pacman_conf.initialize_alpm
holdpkg = []
syncfirst = []
if 'HoldPkg' in pacman_conf.options:
	holdpkg = pacman_conf.options['HoldPkg']
if 'SyncFirst' in pacman_conf.options:
	syncfirst = pacman_conf.options['SyncFirst']
