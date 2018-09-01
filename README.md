Pamac is a GUI for libalpm (pacman) with AUR and Appstream support

#### Features

 - Library to access package infos and run transactions
 - Python bindings
 - CLI
 - GTK3 frontend with Dbus daemon
 - Tray icon with Updates notifications

#### Installing from source

Pamac uses [Meson](http://mesonbuild.com/index.html) build system.
In the source directory run:

`mkdir builddir && cd builddir`

`meson --prefix=/usr --sysconfdir=/etc`

`ninja`

`sudo ninja install`

#### Translation

If you want to contribute in Pamac translations, use [Transifex](https://www.transifex.com/manjarolinux/manjaro-pamac).
