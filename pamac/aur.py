#! /usr/bin/python3
# -*- coding:utf-8 -*-

import os
import urllib
import Namcap
import requests
import tarfile

# i18n
import gettext
import locale
locale.bindtextdomain('pamac', '/usr/share/locale')
gettext.bindtextdomain('pamac', '/usr/share/locale')
gettext.textdomain('pamac')
_ = gettext.gettext

aur_url = 'http://aur.archlinux.org'
rpc_url = aur_url + '/rpc.php'
srcpkgdir = '/tmp/pamac'

class AURPkg():
	def __init__(self, pkginfo):
		self.db = FakeDB()
		self.isize = None
		self.size = None
		self.download_size = 0
		keys = pkginfo.keys()
		if 'URL' in keys:
			self.url = pkginfo['URL']
		if 'URLPath' in keys:
			self.tarpath = pkginfo['URLPath']
		if 'name' in keys:
			self.name = pkginfo['name']
		else:
			self.name = pkginfo['Name']
		if 'version' in keys:
			self.version = pkginfo['version']
		else:
			self.version = pkginfo['Version']
		if 'desc' in keys:
			self.desc = pkginfo['desc']
		else:
			self.desc = pkginfo['Description']
		if 'licenses' in keys:
			self.licenses = pkginfo['licenses']
		elif 'License' in keys:
			self.licenses = [pkginfo['License']]
		else:
			self.licenses = []
		if 'source' in keys:
			self.source = pkginfo['source']
		else:
			self.source = []
		if 'orig_depends' in keys:
			self.depends = pkginfo['orig_depends']
		else:
			self.depends = []
		if 'orig_optdepends' in keys:
			self.optdepends = pkginfo['orig_optdepends']
		else:
			self.optdepends = []
		#~ if 'orig_provides' in keys:
			#~ self.provides = pkginfo['orig_provides']
		#~ else:
			#~ self.provides = []
		if 'orig_makedepends' in keys:
			self.makedepends = pkginfo['orig_makedepends']
		else:
			self.makedepends = []
		#~ if 'replaces' in keys:
			#~ self.replaces = pkginfo['replaces']
		#~ else:
			#~ self.replaces = []
		#~ if 'conflicts' in keys:
			#~ self.conflicts = pkginfo['conflicts']
		#~ else:
			#~ self.conflicts = []
		#~ if 'groups' in keys:
			#~ self.groups = pkginfo['groups']
		#~ else:
			#~ self.groups = []

	def __repr__(self):
		return '{}-{}'.format(self.name, self.version)

	def __eq__(self, other):
		if hasattr(other, 'name') and hasattr(other, 'version'):
			if self.name == other.name and self.version == other.version:
				return True
		return False

class FakeDB():
	def __init__(self):
		self.name = 'AUR'

def get_pkgs(pkgbuild_path):
		pkgbuild_info = Namcap.package.load_from_pkgbuild(pkgbuild_path)
		pkgs = []
		if pkgbuild_info.is_split:
			for infos in pkgbuild_info.subpackages:
				pkg = AURPkg(infos)
				pkgs.append(pkg)
		else:
			pkg = AURPkg(pkgbuild_info)
			pkgs.append(pkg)
		return pkgs

def search(args):
	spec = {'type':'search', 'arg':args}
	try:
		r = requests.get(rpc_url, params = spec)
		r.raise_for_status()
	except Exception as e:
		print(e)
		return []
	else:
		results_dict = r.json()
		results = results_dict['results']
		pkgs = []
		if results:
			for result in results:
				pkgs.append(AURPkg(result))
		return pkgs

def info(pkgname):
	spec = {'type':'info', 'arg':pkgname}
	try:
		r = requests.get(rpc_url, params = spec)
		r.raise_for_status()
	except Exception as e:
		print(e)
		return []
	else:
		results_dict = r.json()
		if results_dict['type'] == 'error':
			print('failed to get infos about {} from AUR'.format(pkgname))
			return None
		else:
			result = results_dict['results']
			if result:
				pkg = AURPkg(result)
				return pkg
			else:
				print('failed to get infos about {} from AUR'.format(pkgname))
				return None

def multiinfo(pkgnames):
	spec = {'type':'multiinfo', 'arg[]':pkgnames}
	try:
		r = requests.get(rpc_url, params = spec)
		r.raise_for_status()
	except Exception as e:
		print(e)
		return []
	else:
		results_dict = r.json()
		if results_dict['type'] == 'error':
			print('failed to get infos about {} from AUR'.format(pkgnames))
			return []
		else:
			pkgs = []
			results = results_dict['results']
			if results:
				for result in results:
					pkgs.append(AURPkg(result))
			else:
				print('failed to get infos about {} from AUR'.format(pkgnames))
			return pkgs

def get_extract_tarball(pkg):
	try:
		r = requests.get(aur_url + pkg.tarpath)
		r.raise_for_status()
	except Exception as e:
		print(e)
		return None
	else:
		if not os.path.exists(srcpkgdir):
			os.makedirs(srcpkgdir)
		full_tarpath = os.path.join(srcpkgdir, os.path.basename(pkg.tarpath))
		try:
			with open(full_tarpath, 'wb') as f:
				f.write(r.content)
		except Exception as e:
			print(e)
			return None
		else:
			try:
				tar = tarfile.open(full_tarpath)
				tar.extractall(path = srcpkgdir)
			except Exception as e:
				print(e)
				return None
			else:
				return os.path.join(srcpkgdir, pkg.name)
