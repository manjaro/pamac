Pamac is a GUI for libalpm (pacman) with AUR and Appstream support

#### Features

 - DBus daemon to perform transactions
 - GTK3 frontend
 - Tray icon
 - Updates notifications

#### Installing from source

Pamac uses [Meson](http://mesonbuild.com/index.html) build system.
In the source directory run:
`mkdir builddir && cd builddir`
`meson --prefix=/usr --sysconfdir=/etc`
`ninja`
`sudo ninja install`

#### Translation

If you want to contribute in Pamac translations, use [Transifex](https://www.transifex.com/manjarolinux/manjaro-pamac).
