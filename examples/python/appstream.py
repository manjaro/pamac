#!/usr/bin/python

import gi
gi.require_version('Pamac', '9.0')
from gi.repository import Pamac

def print_pkg_details (details):
    print (" -Name:", details.get_name())
    print (" -Desc:", details.get_desc())
    print (" -Long Desc:", details.get_long_desc())
    print (" -Icon:", details.get_icon())
    print (" -Screenshots:", details.get_screenshots())

if __name__ == "__main__":
    config = Pamac.Config(conf_path="/etc/pamac.conf")
    db = Pamac.Database(config=config)

    pkgname = "gimp"

    print ("Without appstream support:")
    pkgs = db.search_pkgs (pkgname)
    for pkg in pkgs:
        print_pkg_details (pkg)

    print ("")
    print ("With appstream support:")
    db.enable_appstream()
    pkgs = db.search_pkgs (pkgname)
    for pkg in pkgs:
        print_pkg_details (pkg)
