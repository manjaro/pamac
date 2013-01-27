#! /usr/bin/python
# -*-coding:utf-8 -*-

from pamac import config

syncpkgs = {}
virtualdeps = {}

for repo in config.handle.get_syncdbs():
	for pkg in repo.pkgcache:
		if not pkg.name in syncpkgs.keys():
			syncpkgs[pkg.name] = pkg
for pkg in syncpkgs.values():
	for name in pkg.depends:
		if (not name in syncpkgs.keys()) and (not '>' in name) and (not '<' in name) and (not '=' in name):
				if not virtualdeps.__contains__(name):
						virtualdeps[name] = []
				virtualdeps.get(name).append(pkg.name)
print(virtualdeps)
