Pamac is a Gtk and CLI front ends of [libpamac](https://github.com/manjaro/libpamac)

#### Features

 - pamac: an easy [CLI](https://github.com/manjaro/pamac-cli)
 - pamac-manager: a Gtk4 GUI
 - pamac-tray: a Gtk3 tray icon with updates notifications
 - pamac updates indicator: a gnome-shell extension with updates notifications

#### Installing from source

Pamac uses [Meson](http://mesonbuild.com/index.html) build system.

Build dependencies:

 - meson
 - vala
 - [libpamac](https://github.com/manjaro/libpamac) >= 11.7
 - gtk3 >= 3.24
 - gtk4 >= 4.10
 - libadwaita >= 1.4
 - libnotify

Optional: xapp (native tray icon on Cinnamon), jemalloc (memory allocator, disable it with `-Djemalloc=false`).

In the source directory run:

`mkdir builddir && cd builddir`

`meson setup --prefix=/usr --sysconfdir=/etc --buildtype=release`

`meson compile`

`sudo meson install`

#### Translation

If you want to contribute in Pamac translations, use [Transifex](https://app.transifex.com/manjarolinux/manjaro-pamac).
