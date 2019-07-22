#!/usr/bin/python

import gi
gi.require_version('Pamac', '8.0')
from gi.repository import Pamac

def list_installed_pkgs():
	pkgs = db.get_installed_pkgs()
	for pkg in pkgs:
		print(pkg.get_name(), pkg.get_version())

if __name__ == "__main__":
	config = Pamac.Config(conf_path="/etc/pamac.conf")
	db = Pamac.Database(config=config)
	list_installed_pkgs()
