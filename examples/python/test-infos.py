#!/usr/bin/python
"""
somes tests for python
Depends On:
    pamac
    pacman
not installed:
    ruby-yard
"""

# run only one:
# ./tests.py GetInfosCase.test_versions_search_db
# ./tests.py -v -k files

import gi
import os
import subprocess
import locale
from datetime import date
import unittest
gi.require_version('Pamac', '9.0')
from gi.repository import GLib, Pamac


def get_item_desc(file_pacman: str, key: str = "%VERSION%"):
    """
    get values in db pacman file
        /var/lib/pacman/local/***-***/{desc,files}
        key: %DEPENDS% %INSTALLDATE% %VERSION% %NAME%...
    """
    found = False
    with open(file_pacman) as f_db:
        for line in f_db:
            if line.startswith(key):
                found = True
                continue
            if found:
                if line.strip():
                    yield line.strip()
                else:
                    break


class GetInfosCase(unittest.TestCase):
    """Hieght level tests"""

    def setUp(self):
        """init tests"""
        locale.setlocale(locale.LC_ALL, '')
        config = Pamac.Config(conf_path="/etc/pamac.conf")
        config.set_enable_aur(True)  # is true
        self.db = Pamac.Database(config=config)  # view src/database.vala

    def tearDown(self):
        pass

    def test_pacman_installed(self):
        """pacman installed for tests"""
        pkg = self.db.get_pkg("pacman")
        self.assertEqual("pacman", pkg.get_name())
        self.assertIsNotNone(pkg.props.installed_version)

    def test_not_installed(self):
        """detect not installed"""
        # package not exist
        pkg = self.db.get_pkg("toto-test")
        self.assertNotEqual("toto-test", pkg.get_name())
        self.assertEqual(pkg.props.installed_version, "")
        # package exist
        pkg = self.db.get_pkg("ruby-yard")
        self.assertEqual(pkg.props.installed_version, "")

    def test_giobject_detail_name(self):
        """attrs .props are same as fonctions"""
        pkg = self.db.get_pkg("pacman")
        self.assertEqual(pkg.props.name, pkg.get_name())

    def test_giobject_search_name(self):
        """function db.search_pkgs()"""
        pkgs = self.db.search_pkgs("pacman")
        for pkg in pkgs:
            self.assertEqual(pkg.props.name, pkg.get_name())

    def test_giobject_search_version(self):
        """version install is as version"""
        #pkgs = self.db.search_pkgs("pacman")
        pkgs = self.db.get_installed_pkgs()
        for pkg in pkgs:
            if pkg.props.installed_version:
                with self.subTest(pkg=pkg):
                    self.assertEqual(pkg.props.version, pkg.props.installed_version)

    def test_count_installed(self):
        """count on disk pacman db packages installed"""
        pkgs = self.db.get_installed_pkgs()
        ldir = os.listdir("/var/lib/pacman/local/")
        ldir.remove("ALPM_DB_VERSION")
        self.assertEqual(len(ldir), len(pkgs))

    def test_all_installed(self):
        """test names/version on disk pacman db packages installed"""
        plist = []
        pkgs = self.db.get_installed_pkgs()
        plist = {f"{pkg.props.name}-{pkg.props.installed_version}" for pkg in pkgs}
        ldir = os.listdir("/var/lib/pacman/local/")
        ldir.remove("ALPM_DB_VERSION")
        for p_name_v in plist:
            self.assertIn(p_name_v, ldir)

    def test_versions_search_db(self):
        """VERSION is as pacman"""
        pkgs = self.db.search_pkgs("pacman")
        for pkg in pkgs:
            if pkg.props.installed_version:
                with self.subTest(pkg=pkg):
                    fdesc = f"/var/lib/pacman/local/{pkg.props.name}-{pkg.props.version}/desc"
                    self.assertTrue(os.path.exists(fdesc))
                    result = get_item_desc(fdesc, "%VERSION%")
                    self.assertEqual(pkg.props.version, next(result))

    def test_depends_search_db(self):
        """DEPENDS are as pacman"""
        pkgs = self.db.search_pkgs("pacman")
        for pkg in pkgs:
            if pkg.props.installed_version:
                with self.subTest(pkg=pkg):
                    fdesc = f"/var/lib/pacman/local/{pkg.props.name}-{pkg.props.version}/desc"
                    self.assertTrue(os.path.exists(fdesc))
                    package = self.db.get_pkg(pkg.props.name)
                    result = get_item_desc(fdesc, "%DEPENDS%")
                    for dep in result:
                        self.assertIn(dep, package.props.depends)

    def test_search_pacman(self):
        """compare results with pacman -Ssq"""
        result = subprocess.run(['pacman', '-Ssq', 'pacman'], capture_output=True, check=True)
        result = result.stdout.decode().split("\n")
        result.remove('')
        pkgs = self.db.search_pkgs("pacman")
        pkgs = {pkg.props.name for pkg in pkgs}
        for pkg in result:
            self.assertIn(pkg, pkgs)
        '''
        can't test if aur package installed
        for pkg in pkgs:
            self.assertIn(pkg, result)
        '''

    def test_date_detail_pacman(self):
        """valid date and locale date"""
        pkg = self.db.get_pkg("pacman")
        fdesc = f"/var/lib/pacman/local/{pkg.props.name}-{pkg.props.version}/desc"
        self.assertTrue(os.path.exists(fdesc))
        result = get_item_desc(fdesc, "%BUILDDATE%")
        d_test = int(next(result))
        d_test = date.fromtimestamp(d_test).strftime("%x")
        self.assertEqual(pkg.props.builddate, d_test)

    def test_files(self):
        """files same as pacman db"""
        pkg = self.db.get_pkg("pacman")
        fdesc = f"/var/lib/pacman/local/{pkg.props.name}-{pkg.props.version}/files"
        self.assertTrue(os.path.exists(fdesc))
        myfiles = self.db.get_pkg_files("pacman")
        result = get_item_desc(fdesc, "%FILES%")
        for f_name in result:
            if not f_name.endswith("/"):
                self.assertIn("/" + f_name, myfiles)

    def test_search_aur(self):
        """simple search in aur"""
        pkgs = self.db.search_in_aur('pamac');
        found = False
        for pkg in pkgs:
            with self.subTest(pkg=pkg):
                self.assertTrue(pkg.props.version)
                self.assertEqual(pkg.props.version, pkg.get_version())
                self.assertTrue(isinstance(
                    pkg.props.popularity, (int, float)))
                found = True
        self.assertTrue(found)

if __name__ == '__main__':
    unittest.main(verbosity=2, failfast=True)
