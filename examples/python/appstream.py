#!/usr/bin/python

import gi
gi.require_version('Pamac', '8.0')
from gi.repository import Pamac

def print_pkg_details (details):
    print (" -Name:", details.get_name())
    print (" -Desc:", details.get_desc())
    print (" -Long Desc:", details.get_long_desc())
    print (" -Icon:", details.get_icon())
    print (" -Screenshot:", details.get_screenshot())

def print_pkg_name (pkg):
    print (" -Name:", pkg.get_name(), " -Appname:", pkg.get_app_name())

if __name__ == "__main__":
    config = Pamac.Config(conf_path="/etc/pamac.conf")
    db = Pamac.Database(config=config)

    pkgname = "libreoffice-still"
    appname = "LibreOffice Draw"

    print ("Without appstream support:")
    pkgs = db.search_pkgs (pkgname)
    for pkg in pkgs:
        print_pkg_name (pkg)
    print ("")
    details = db.get_pkg_details(pkgname, appname, False)
    print_pkg_details (details)

    print ("")
    print ("With appstream support:")
    db.enable_appstream()
    pkgs = db.search_pkgs (pkgname)
    for pkg in pkgs:
        print_pkg_name (pkg)
    print ("")
    details = db.get_pkg_details(pkgname, appname, False)
    print_pkg_details (details)
