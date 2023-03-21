Pamac is a Gtk and CLI front ends of [libpamac](https://gitlab.manjaro.org/applications/libpamac)

#### Features

 - pamac: an easy CLI
 - pamac-manager: a Gtk4 GUI
 - pamac-tray: a Gtk3 tray icon with updates notifications
 - pamac updates indicator: a gnome-shell extension with updates notifications

#### Installing from source

Pamac uses [Meson](http://mesonbuild.com/index.html) build system.
In the source directory run:

`mkdir builddir && cd builddir`

`meson setup --prefix=/usr --sysconfdir=/etc --buildtype=release`

`meson compile`

`sudo meson install`

#### Translation

If you want to contribute in Pamac translations, use [Transifex](https://www.transifex.com/manjarolinux/manjaro-pamac).
