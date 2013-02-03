#! /usr/bin/python
# -*-coding:utf-8 -*-

import pyalpm
from pamac import config, common
from collections import OrderedDict
syncpkgs = OrderedDict()
localpkgs = OrderedDict()
virtualdeps = {}

for repo in config.handle.get_syncdbs():
	for pkg in repo.pkgcache:
		if not pkg.name in syncpkgs.keys():
			syncpkgs[pkg.name] = pkg
for pkg in config.handle.get_localdb().pkgcache:
	if not pkg.name in localpkgs.keys():
		localpkgs[pkg.name] = pkg
#~ for pkg in syncpkgs.values():
	#~ for name in pkg.depends:
		#~ if (not name in syncpkgs.keys()) and (not '>' in name) and (not '<' in name) and (not '=' in name):
			#~ if 'module' in name:
				#~ if not virtualdeps.__contains__(name):
						#~ virtualdeps[name] = []
				#~ virtualdeps.get(name).append(pkg.name)

to_add = ['libreoffice-writer', 'anjuta']
depends = [[syncpkgs['libreoffice-writer'],syncpkgs['anjuta']]]
to_provide = []
to_remove = []
warning = ''
i = 0
while depends[i]:
	depends.append([])
	for pkg in depends[i]:
		for depend in pkg.depends:
			provide = pyalpm.find_satisfier(localpkgs.values(), depend)
			if provide:
				print(i,'local',provide)
				if provide.name != common.format_pkg_name(depend):
					if ('-module' in depend) or ('linux' in depend):
						to_provide.append(depend)
			else:
				provide = pyalpm.find_satisfier(syncpkgs.values(), depend)
				if provide:
					print(i,'sync',provide)
					if provide.name != common.format_pkg_name(depend):
						print(provide.name,common.format_pkg_name(depend))
						to_provide.append(depend)
					else:
						depends[i+1].append(provide)
		for replace in pkg.replaces:
			provide = pyalpm.find_satisfier(localpkgs.values(), replace)
			if provide:
				if not provide.name in to_remove:
					to_remove.append(provide.name)
					if warning:
						warning = warning+'\n'
					warning = warning+provide.name+' will be replaced by '+pkg.name
		for conflict in pkg.conflicts:
			provide = pyalpm.find_satisfier(localpkgs.values(), conflict)
			if provide:
				if not provide.name in to_remove:
					to_remove.append(provide.name)
					if warning:
						warning = warning+'\n'
					warning = warning+pkg.name+' conflicts with '+provide.name
			provide = pyalpm.find_satisfier(depends[0], conflict)
			if provide:
				if not common.format_pkg_name(conflict) in to_remove:
					if pkg.name in to_add and common.format_pkg_name(conflict) in to_add:
						to_add.remove(common.format_pkg_name(conflict))
						to_add.remove(pkg.name)
						if warning:
							warning = warning+'\n'
						warning = warning+pkg.name+' conflicts with '+common.format_pkg_name(conflict)+'\nNone of them will be installed'
	i = i + 1
for pkg in localpkgs.values():
	for conflict in pkg.conflicts:
		provide = pyalpm.find_satisfier(depends[0], conflict)
		if provide:
			if not provide.name in to_remove:
				to_remove.append(pkg.name)
				if warning:
					warning = warning+'\n'
				warning = warning+provide.name+' conflicts with '+pkg.name
print('depends:',depends)
print('to provide:',to_provide)
print('to add:',to_add)
print('to remove:',to_remove)
print(warning)
