Pamac is a Package Manager with Alpm, AUR, Appstream, Flatpak and Snap support

#### Features

 - libpamac: Library to access package infos and run transactions
 - Python bindings for libpamac
 - pamac: an easy CLI
 - pamac-manager: a Gtk3 GUI
 - pamac-tray: a Gtk3 tray icon with updates notifications
 - pamac-tray-appindicator: a AppIndicator tray icon with updates notifications
 - pamac updates indicator: a gnome-shell extension with updates notifications

#### Installing from source

Pamac uses [Meson](http://mesonbuild.com/index.html) build system.
In the source directory run:

`mkdir builddir && cd builddir`

`meson --prefix=/usr --sysconfdir=/etc -Denable-snap=true -Denable-flatpak=true --buildtype=release`

`ninja`

`sudo ninja install`

#### Translation

If you want to contribute in Pamac translations, use [Transifex](https://www.transifex.com/manjarolinux/manjaro-pamac).
