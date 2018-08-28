#!/usr/bin/python

import gi
gi.require_version('Pamac', '1.0')
from gi.repository import GLib, Pamac

def on_installed_pkgs_ready_callback(source_object, result, user_data):
	try:
		pkgs = source_object.get_installed_pkgs_finish(result)
	except GLib.GError as e:
		print("Error: ", e.message)
	else:
		for pkg in pkgs:
			print(pkg.get_name(), pkg.get_version())
	finally:
		loop.quit()

def list_installed_pkgs_async():
	pkgs = db.get_installed_pkgs_async(on_installed_pkgs_ready_callback, None)
	# launch a loop to wait for the callback to be called
	loop.run()

if __name__ == "__main__":
	loop = GLib.MainLoop()
	config = Pamac.Config(conf_path="/etc/pamac.conf")
	db = Pamac.Database(config=config)
	list_installed_pkgs_async()

