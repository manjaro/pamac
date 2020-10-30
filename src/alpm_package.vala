/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2020 Guillaume Benoit <guillaume@manjaro.org>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a get of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

namespace Pamac {
	public abstract class AlpmPackage : Package {
		// Package
		As.App? _as_app;
		unowned string? _app_name;
		unowned string? _app_id;
		string? _long_desc;
		unowned string? _launchable;
		string? _icon;
		GenericArray<string> _screenshots;

		// Package
		public override string? app_name {
			get {
				if (_app_name == null && _as_app != null) {
					_app_name = _as_app.get_name (null);
				}
				return _app_name;
			}
		}
		public override string? app_id {
			get {
				if (_app_id == null && _as_app != null) {
					_app_id = _as_app.get_id ();
				}
				return _app_id;
			}
		}
		public override string? long_desc {
			get {
				if (_long_desc == null && _as_app != null) {
					try {
						_long_desc = As.markup_convert_simple (_as_app.get_description (null));
					} catch (Error e) {
						warning (e.message);
					}
				}
				return _long_desc;
			}
		}
		public override string? launchable {
			get {
				if (_launchable == null && _as_app != null) {
					As.Launchable? launchable = _as_app.get_launchable_by_kind (As.LaunchableKind.DESKTOP_ID);
					if (launchable != null) {
						return launchable.get_value ();
					}
				}
				return _launchable;
			}
		}
		public override string? icon {
			get {
				if (_icon == null && _as_app != null) {
					unowned GenericArray<As.Icon> icons = _as_app.get_icons ();
					for (uint i = 0; i < icons.length; i++) {
						As.Icon as_icon = icons[i];
						if (as_icon.get_kind () == As.IconKind.CACHED) {
							if (as_icon.get_height () == 64) {
								_icon = "/usr/share/app-info/icons/archlinux-arch-%s/64x64/%s".printf (repo, as_icon.get_name ());
								break;
							}
						}
					}
				}
				return _icon;
			}
		}
		public override GenericArray<string> screenshots {
			get {
				if (_screenshots == null) {
					_screenshots = new GenericArray<string> ();
					if (_as_app != null) {
						unowned GLib.GenericArray<As.Screenshot> as_screenshots = _as_app.get_screenshots ();
						foreach (unowned As.Screenshot as_screenshot in as_screenshots) {
							As.Image? as_image = as_screenshot.get_source ();
							if (as_image != null) {
								unowned string? url = as_image.get_url ();
								if (url != null) {
									_screenshots.add (url);
								}
							}
						}
					}
				}
				return _screenshots;
			}
		}
		// AlpmPackage
		public abstract uint64 build_date { get;  }
		public abstract string? packager { get; }
		public abstract string? reason { get; }
		public abstract string? has_signature { get; }
		public abstract GenericArray<string> groups { get; }
		public abstract GenericArray<string> depends { get; internal set; }
		public abstract GenericArray<string> optdepends { get; }
		public abstract GenericArray<string> makedepends { get; }
		public abstract GenericArray<string> checkdepends { get; }
		public abstract GenericArray<string> requiredby { get; }
		public abstract GenericArray<string> optionalfor { get; }
		public abstract GenericArray<string> provides { get; internal set; }
		public abstract GenericArray<string> replaces { get; internal set; }
		public abstract GenericArray<string> conflicts { get; internal set; }
		public abstract GenericArray<string> backups { get; }

		internal AlpmPackage () {}

		internal void set_as_app (As.App? as_app) {
			_as_app = as_app;
		}

		internal unowned As.App? get_as_app () {
			return _as_app;
		}
	}

	internal class AlpmPackageLinked : AlpmPackage {
		// common
		unowned Alpm.Handle? alpm_handle;
		unowned Alpm.Package? alpm_pkg;
		unowned Alpm.Package? local_pkg;
		unowned Alpm.Package? sync_pkg;
		bool local_pkg_set;
		bool sync_pkg_set;
		bool installed_version_set;
		bool repo_set;
		bool license_set;
		bool install_date_set;
		bool download_size_set;
		bool installed_size_set;
		bool reason_set;
		bool has_signature_set;
		// Package
		string _name;
		string _id;
		unowned string _version;
		unowned string? _installed_version;
		unowned string? _desc;
		unowned string? _repo;
		string? _license;
		unowned string? _url;
		uint64 _installed_size;
		uint64 _download_size;
		uint64 _install_date;
		// AlpmPackage
		uint64 _build_date;
		unowned string? _packager;
		unowned string? _reason;
		unowned string? _has_signature;
		GenericArray<string> _groups;
		GenericArray<string> _depends;
		GenericArray<string> _optdepends;
		GenericArray<string> _makedepends;
		GenericArray<string> _checkdepends;
		GenericArray<string> _requiredby;
		GenericArray<string> _optionalfor;
		GenericArray<string> _provides;
		GenericArray<string> _replaces;
		GenericArray<string> _conflicts;
		GenericArray<string> _backups;

		// Package
		public override string name {
			get {
				if (_name == null) {
					_name = alpm_pkg.name;
				}
				return _name;
			}
			internal set { _name = value; }
		}
		public override string id {
			get {
				if (_id == null) {
					unowned As.App? as_app = get_as_app ();
					if (as_app != null) {
						_id = "%s/%s".printf (name, app_name);
					} else {
						_id = name;
					}
				}
				return _id;
			}
		}
		public override string version {
			get {
				if (_version == null) {
					_version = alpm_pkg.version;
				}
				return _version;
			}
			internal set { _version = value; }
		}
		public override string? installed_version {
			get {
				if (!installed_version_set) {
					installed_version_set = true;
					found_local_pkg ();
					_installed_version = local_pkg.version;
				}
				return _installed_version;
			}
			internal set { _installed_version = value; }
		}
		public override string? desc {
			get {
				if (_desc == null) {
					unowned As.App? as_app = get_as_app ();
					if (as_app != null) {
						unowned string? summary = as_app.get_comment (null);
						if (summary != null) {
							_desc = summary;
						}
					} else {
						_desc = alpm_pkg.desc;
					}
				}
				return _desc;
			}
			internal set { _desc = value; }
		}
		public override string? repo {
			get {
				if (!repo_set) {
					repo_set = true;
					found_sync_pkg ();
					unowned Alpm.DB? db = sync_pkg.db;
					if (db != null) {
						_repo = db.name;
					}
				}
				return _repo;
			}
			internal set { _repo = value; }
		}
		public override string? license {
			get {
				if (!license_set) {
					license_set = true;
					unowned Alpm.List<unowned string>? list = alpm_pkg.licenses;
					if (list != null) {
						var license_str = new StringBuilder (list.data);
						list.next ();
						while (list != null) {
							license_str.append (" ");
							license_str.append (list.data);
							list.next ();
						}
						_license = (owned) license_str.str;
					} else {
						_license = dgettext (null, "Unknown");
					}
				}
				return _license;
			}
		}
		public override string? url {
			get {
				if (_url == null) {
					_url = alpm_pkg.url;
				}
				return _url;
			}
		}
		public override uint64 installed_size {
			get {
				if (_installed_size == 0 && !installed_size_set) {
					installed_size_set = true;
					found_local_pkg ();
					_installed_size = local_pkg.isize;
				}
				return _installed_size;
			}
		}
		public override uint64 download_size {
			get {
				if (!download_size_set) {
					download_size_set = true;
					if (alpm_pkg != null) {
						_download_size = alpm_pkg.download_size;
					}
				}
				return _download_size;
			}
		}
		public override uint64 install_date {
			get {
				if (!install_date_set) {
					install_date_set = true;
					found_local_pkg ();
					if (local_pkg != null) {
						_install_date = local_pkg.installdate;
					}
				}
				return _install_date;
			}
		}
		// AlpmPackage
		public override uint64 build_date {
			get {
				if (_build_date == 0) {
					if (alpm_pkg != null) {
						_build_date = alpm_pkg.builddate;
					}
				}
				return _build_date;
			}
		}
		public override string? packager {
			get {
				if (_packager == null) {
					_packager = alpm_pkg.packager;
				}
				return _packager;
			}
		}
		public override string? reason {
			get {
				if (!reason_set) {
					reason_set = true;
					found_local_pkg ();
					if (local_pkg != null) {
						if (local_pkg.reason == Alpm.Package.Reason.EXPLICIT) {
							_reason = dgettext (null, "Explicitly installed");
						} else if (local_pkg.reason == Alpm.Package.Reason.DEPEND) {
							_reason = dgettext (null, "Installed as a dependency for another package");
						}
					}
				}
				return _reason;
			}
		}
		public override string? has_signature {
			get {
				if (!has_signature_set) {
					has_signature_set = true;
					found_sync_pkg ();
					if (sync_pkg != null) {
						if (sync_pkg.base64_sig != null) {
							_has_signature = dgettext (null, "Yes");
						} else {
							_has_signature = dgettext (null, "No");
						}
					}
				}
				return _has_signature;
			}
		}
		public override GenericArray<string> groups {
			get {
				if (_groups == null) {
					_groups = new GenericArray<string> ();
					unowned Alpm.List<unowned string> list = alpm_pkg.groups;
					while (list != null) {
						_groups.add (list.data);
						list.next ();
					}
				}
				return _groups;
			}
		}
		public override GenericArray<string> depends {
			get {
				if (_depends == null) {
					_depends = new GenericArray<string> ();
					unowned Alpm.List<unowned Alpm.Depend> list = alpm_pkg.depends;
					while (list != null) {
						_depends.add (list.data.compute_string ());
						list.next ();
					}
				}
				return _depends;
			}
			internal set { _depends = value; }
		}
		public override GenericArray<string> optdepends {
			get {
				if (_optdepends == null) {
					_optdepends = new GenericArray<string> ();
					unowned Alpm.List<unowned Alpm.Depend> list = alpm_pkg.optdepends;
					while (list != null) {
						_optdepends.add (list.data.compute_string ());
						list.next ();
					}
				}
				return _optdepends;
			}
		}
		public override GenericArray<string> makedepends {
			get {
				if (_makedepends == null) {
					_makedepends = new GenericArray<string> ();
					if (sync_pkg != null) {
						unowned Alpm.List<unowned Alpm.Depend> list = sync_pkg.makedepends;
						while (list != null) {
							_makedepends.add (list.data.compute_string ());
							list.next ();
						}
					}
				}
				return _makedepends;
			}
		}
		public override GenericArray<string> checkdepends {
			get {
				if (_checkdepends == null) {
					_checkdepends = new GenericArray<string> ();
					if (sync_pkg != null) {
						unowned Alpm.List<unowned Alpm.Depend> list = sync_pkg.checkdepends;
						while (list != null) {
							_checkdepends.add (list.data.compute_string ());
							list.next ();
						}
					}
				}
				return _checkdepends;
			}
		}
		public override GenericArray<string> requiredby {
			get {
				if (_requiredby == null) {
					_requiredby = new GenericArray<string> ();
					if (local_pkg != null) {
						Alpm.List<string> owned_list = local_pkg.compute_requiredby ();
						unowned Alpm.List<string> list = owned_list;
						while (list != null) {
							_requiredby.add ((owned) list.data);
							list.next ();
						}
					}
				}
				return _requiredby;
			}
		}
		public override GenericArray<string> optionalfor {
			get {
				if (_optionalfor == null) {
					_optionalfor = new GenericArray<string> ();
					if (local_pkg != null) {
						Alpm.List<string> owned_list = local_pkg.compute_optionalfor ();
						unowned Alpm.List<string> list = owned_list;
						while (list != null) {
							_optionalfor.add ((owned) list.data);
							list.next ();
						}
					}
				}
				return _optionalfor;
			}
		}
		public override GenericArray<string> provides {
			get {
				if (_provides == null) {
					_provides = new GenericArray<string> ();
					unowned Alpm.List<unowned Alpm.Depend> list = alpm_pkg.provides;
					while (list != null) {
						_provides.add (list.data.compute_string ());
						list.next ();
					}
				}
				return _provides;
			}
			internal set { _provides = value; }
		}
		public override GenericArray<string> replaces {
			get {
				if (_replaces == null) {
					_replaces = new GenericArray<string> ();
					unowned Alpm.List<unowned Alpm.Depend> list = alpm_pkg.replaces;
					while (list != null) {
						_replaces.add (list.data.compute_string ());
						list.next ();
					}
				}
				return _replaces;
			}
			internal set { _replaces = value; }
		}
		public override GenericArray<string> conflicts {
			get {
				if (_conflicts == null) {
					_conflicts = new GenericArray<string> ();
					unowned Alpm.List<unowned Alpm.Depend> list = alpm_pkg.conflicts;
					while (list != null) {
						_conflicts.add (list.data.compute_string ());
						list.next ();
					}
				}
				return _conflicts;
			}
			internal set { _conflicts = value; }
		}
		public override GenericArray<string> backups {
			get {
				if (_backups == null) {
					_backups = new GenericArray<string> ();
					if (local_pkg != null) {
						unowned Alpm.List<unowned Alpm.Backup> list = local_pkg.backups;
						while (list != null) {
							var builder = new StringBuilder ("/");
							builder.append (list.data.name);
							_backups.add ((owned) builder.str);
							list.next ();
						}
					}
				}
				return _backups;
			}
		}

		internal AlpmPackageLinked () {}

		internal AlpmPackageLinked.from_alpm (Alpm.Package? alpm_pkg, Alpm.Handle? alpm_handle) {
			this.alpm_pkg = alpm_pkg;
			this.alpm_handle = alpm_handle;
		}

		internal void set_alpm_pkg (Alpm.Package? alpm_pkg) {
			this.alpm_pkg = alpm_pkg;
		}

		internal void set_local_pkg (Alpm.Package? local_pkg) {
			this.local_pkg = local_pkg;
			local_pkg_set = true;
		}

		internal void set_sync_pkg (Alpm.Package? sync_pkg) {
			this.sync_pkg = sync_pkg;
			sync_pkg_set = true;
		}

		void found_local_pkg () {
			if  (!local_pkg_set) {
				local_pkg_set = true;
				if (alpm_pkg != null) {
					if (alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
						local_pkg = alpm_pkg;
					} else if (alpm_pkg.origin == Alpm.Package.From.SYNCDB && alpm_handle != null) {
						local_pkg = alpm_handle.localdb.get_pkg (alpm_pkg.name);
					}
				}
			}
		}

		void found_sync_pkg () {
			if  (!sync_pkg_set) {
				sync_pkg_set = true;
				if (alpm_pkg != null) {
					if (alpm_pkg.origin == Alpm.Package.From.LOCALDB) {
						sync_pkg = get_sync_pkg (alpm_pkg.name);
					} else if (alpm_pkg.origin == Alpm.Package.From.SYNCDB) {
						sync_pkg = alpm_pkg;
					}
				}
			}
		}

		unowned Alpm.Package? get_sync_pkg (string pkgname) {
			unowned Alpm.Package? pkg = null;
			if (alpm_handle != null) {
				unowned Alpm.List<unowned Alpm.DB> syncdbs = alpm_handle.syncdbs;
				while (syncdbs != null) {
					unowned Alpm.DB db = syncdbs.data;
					pkg = db.get_pkg (pkgname);
					if (pkg != null) {
						break;
					}
					syncdbs.next ();
				}
			}
			return pkg;
		}
	}

	internal class AlpmPackageData : AlpmPackageLinked {
		// Package
		string _version;
		string? _installed_version;
		string? _desc;
		string? _repo;
		string? _url;
		// AlpmPackage
		string? _packager;

		// Package
		public override string version {
			get { return _version; }
			internal set { _version = value; }
		}
		public override string? installed_version {
			get { return _installed_version; }
			internal set { _installed_version = value; }
		}
		public override string? desc {
			get { return _desc; }
			internal set { _desc = value; }
		}
		public override string? repo {
			get { return _repo; }
			internal set { _repo = value; }
		}
		public override string? url { get { return _url; } }
		// AlpmPackage
		public override string? packager { get { return _packager; } }

		internal AlpmPackageData (Alpm.Package alpm_pkg, Alpm.Package? local_pkg, Alpm.Package? sync_pkg) {
			// version
			_version = alpm_pkg.version;
			// desc
			_desc = alpm_pkg.desc;
			// packager
			_packager = alpm_pkg.packager;
			// set pkgs
			set_alpm_pkg (alpm_pkg);
			set_local_pkg (local_pkg);
			set_sync_pkg (sync_pkg);
			// name
			unowned string str = name;
			// id
			str = id;
			// license
			str = license;
			// installed size
			uint64 val = installed_size;
			// download size
			val = download_size;
			// build date
			val = build_date;
			if (local_pkg != null) {
				// installed version
				_installed_version = local_pkg.version;
				// installed date
				val = install_date;
				// reason
				str = reason;
				// requiredby
				unowned GenericArray<string> list = requiredby;
				// optionalfor
				list = optionalfor;
				// backups
				list = backups;
			}
			if (sync_pkg != null) {
				// repo
				_repo = sync_pkg.db.name;
				// signature
				str = has_signature;
				// makedepends
				unowned GenericArray<string> list =  makedepends;
				// checkdepends
				list = checkdepends;
			}
			// groups
			unowned GenericArray<string> list = groups;
			// depends
			list = depends;
			// optdepends
			list = optdepends;
			// provides
			list = provides;
			// replaces
			list = replaces;
			// conflicts
			list = conflicts;
			// unset pkgs
			set_alpm_pkg (null);
			set_local_pkg (null);
			set_sync_pkg (null);
		}

		internal AlpmPackageData.transaction (Alpm.Package alpm_pkg, Alpm.Package? local_pkg, Alpm.Package? sync_pkg) {
			// set pkgs
			set_alpm_pkg (alpm_pkg);
			set_local_pkg (local_pkg);
			set_sync_pkg (sync_pkg);
			// name
			unowned string str = name;
			str = null;
			// version
			_version = alpm_pkg.version;
			// desc
			_desc = alpm_pkg.desc;
			uint64 val = installed_size;
			val = download_size;
			if (local_pkg != null) {
				// installed version
				_installed_version = local_pkg.version;
				// installed date
				val = install_date;
			}
			if (sync_pkg != null) {
				// repo
				// transaction pkg
				if (sync_pkg.db.name == "pamac_aur") {
					_repo = dgettext (null, "AUR");
				} else {
					_repo = sync_pkg.db.name;
				}
			}
			// unset pkgs
			set_alpm_pkg (null);
			set_local_pkg (null);
			set_sync_pkg (null);
		}
	}

	public abstract class AURPackage : AlpmPackage {
		public abstract string? packagebase { get; internal set; }
		public abstract string? maintainer { get; }
		public abstract double popularity { get; }
		public abstract uint64 lastmodified { get; }
		public abstract uint64 outofdate { get; }
		public abstract uint64 firstsubmitted { get; }
		public abstract uint64 numvotes  { get; }

		internal AURPackage () {}
	}

	internal class AURPackageLinked : AURPackage {
		// common
		Json.Object? json_object;
		unowned Alpm.Package? local_pkg;
		bool is_update;
		bool installed_version_set;
		bool install_date_set;
		bool installed_size_set;
		bool download_size_set;
		bool license_set;
		bool reason_set;
		bool packager_set;
		bool build_date_set;
		// Package
		string _name;
		string _id;
		unowned string _version;
		unowned string? _installed_version;
		unowned string? _desc;
		unowned string? _repo;
		string? _license;
		unowned string? _url;
		uint64 _installed_size;
		uint64 _download_size;
		uint64 _install_date;
		// AlpmPackage
		uint64 _build_date;
		unowned string? _packager;
		unowned string? _reason;
		GenericArray<string> _groups;
		GenericArray<string> _depends;
		GenericArray<string> _optdepends;
		GenericArray<string> _makedepends;
		GenericArray<string> _checkdepends;
		GenericArray<string> _requiredby;
		GenericArray<string> _optionalfor;
		GenericArray<string> _provides;
		GenericArray<string> _replaces;
		GenericArray<string> _conflicts;
		GenericArray<string> _backups;
		// AURPackage
		unowned string? _packagebase;
		unowned string? _maintainer;
		double _popularity;
		uint64 _lastmodified;
		uint64 _outofdate;
		uint64 _firstsubmitted;
		uint64 _numvotes;

		// Package
		public override string name {
			get {
				if (_name == null && json_object != null) {
					_name = json_object.get_string_member ("Name");
				}
				return _name;
			}
			internal set { _name = value; }
		}
		public override string id {
			get {
				if (_id == null && json_object != null) {
					_id = json_object.get_string_member ("Name");
				}
				return _id;
			}
		}
		public override string version {
			get {
				if (_version == null) {
					if (!is_update && local_pkg != null) {
						_version = local_pkg.version;
					} else {
						_version = json_object.get_string_member ("Version");
					}
				}
				return _version;
			}
			internal set { _version = value; }
		}
		public override string? installed_version {
			get {
				if (!installed_version_set) {
					installed_version_set = true;
					if (local_pkg != null) {
						_installed_version = local_pkg.version;
					}
				}
				return _installed_version;
			}
			internal set { _installed_version = value; }
		}
		public override string? desc {
			get {
				if (_desc == null) {
					if (!is_update && local_pkg != null) {
						_desc = local_pkg.desc;
					} else {
						unowned Json.Node? node = json_object.get_member ("Description");
						if (!node.is_null ()) {
							_desc = node.get_string ();
						}
					}
				}
				return _desc;
			}
			internal set { _desc = value; }
		}
		public override string? repo {
			get {
				if (_repo == null) {
					_repo = dgettext (null, "AUR");
				}
				return _repo;
			}
			internal set { _repo = value; }
		}
		public override string? license {
			get {
				if (_license == null && !license_set) {
					license_set = true;
					if (!is_update && local_pkg != null) {
						unowned Alpm.List<unowned string>? list = local_pkg.licenses;
						if (list != null) {
							var license_str = new StringBuilder (list.data);
							list.next ();
							while (list != null) {
								license_str.append (" ");
								license_str.append (list.data);
								list.next ();
							}
							_license = (owned) license_str.str;
						}
					} else if (json_object != null) {
						unowned Json.Node? node = json_object.get_member ("License");
						if (node != null) {
							unowned Json.Array json_array = node.get_array ();
							var license_str = new StringBuilder (json_array.get_string_element (0));
							uint json_array_length = json_array.get_length ();
							for (uint i = 1; i < json_array_length; i++) {
								license_str.append (" ");
								license_str.append (json_array.get_string_element (i));
							}
							_license = (owned) license_str.str;
						} else {
							_license = dgettext (null, "Unknown");
						}
					}
					
				}
				return _license;
			}
		}
		public override string? url {
			get {
				if (_url == null) {
					if (!is_update && local_pkg != null) {
						_url = local_pkg.url;
					} else if (json_object != null) {
						unowned Json.Node? node = json_object.get_member ("URL");
						if (!node.is_null ()) {
							_url = node.get_string ();
						}
					}
				}
				return _url;
			}
		}
		public override uint64 installed_size {
			get {
				if (!installed_size_set) {
					installed_size_set = true;
					if (local_pkg != null) {
						_installed_size = local_pkg.isize;
					}
				}
				return _installed_size;
			}
		}
		public override uint64 download_size {
			get {
				if (!download_size_set) {
					download_size_set = true;
					if (local_pkg != null) {
						_download_size = local_pkg.download_size;
					}
				}
				return _download_size;
			}
		}
		public override uint64 install_date {
			get {
				if (!install_date_set) {
					install_date_set = true;
					if (local_pkg != null) {
						_install_date = local_pkg.installdate;
					}
				}
				return _install_date;
			}
		}
		// AlpmPackage
		public override uint64 build_date {
			get {
				if (!build_date_set) {
					build_date_set = true;
					if (local_pkg != null) {
						_build_date = local_pkg.builddate;
					}
				}
				return _build_date;
			}
		}
		public override string? packager {
			get {
				if (!packager_set) {
					packager_set = true;
					if (local_pkg != null) {
						_packager = local_pkg.packager;
					}
				}
				return _packager;
			}
		}
		public override string? reason {
			get {
				if (!reason_set) {
					reason_set = true;
					if (local_pkg != null) {
						if (local_pkg.reason == Alpm.Package.Reason.EXPLICIT) {
							_reason = dgettext (null, "Explicitly installed");
						} else if (local_pkg.reason == Alpm.Package.Reason.DEPEND) {
							_reason = dgettext (null, "Installed as a dependency for another package");
						}
					}
				}
				return _reason;
			}
		}
		public override string? has_signature { get { return null; } }
		public override GenericArray<string> groups {
			get {
				if (_groups == null) {
					_groups = new GenericArray<string> ();
					if (local_pkg != null) {
						unowned Alpm.List<unowned string> list = local_pkg.groups;
						while (list != null) {
							_groups.add (list.data);
							list.next ();
						}
					}
				}
				return _groups;
			}
		}
		public override GenericArray<string> depends {
			get {
				if (_depends == null) {
					_depends = new GenericArray<string> ();
					if (!is_update && local_pkg != null) {
						unowned Alpm.List<unowned Alpm.Depend> list = local_pkg.depends;
						while (list != null) {
							_depends.add (list.data.compute_string ());
							list.next ();
						}
					} else if (json_object != null) {
						unowned Json.Node? node = json_object.get_member ("Depends");
						if (node != null) {
							unowned Json.Array json_array = node.get_array ();
							populate_array (json_array, ref _depends);
						}
					}
				}
				return _depends;
			}
			internal set { _depends = value; }
		}
		public override GenericArray<string> optdepends {
			get {
				if (_optdepends == null) {
					_optdepends = new GenericArray<string> ();
					if (!is_update && local_pkg != null) {
						unowned Alpm.List<unowned Alpm.Depend> list = local_pkg.optdepends;
						while (list != null) {
							_optdepends.add (list.data.compute_string ());
							list.next ();
						}
					} else if (json_object != null) {
						unowned Json.Node? node = json_object.get_member ("OptDepends");
						if (node != null) {
							unowned Json.Array json_array = node.get_array ();
							populate_array (json_array, ref _optdepends);
						}
					}
				}
				return _optdepends;
			}
		}
		public override GenericArray<string> makedepends {
			get {
				if (_makedepends == null) {
					_makedepends = new GenericArray<string> ();
					if (json_object != null) {
						unowned Json.Node? node = json_object.get_member ("MakeDepends");
						if (node != null) {
							unowned Json.Array json_array = node.get_array ();
							populate_array (json_array, ref _makedepends);
						}
					}
				}
				return _makedepends;
			}
		}
		public override GenericArray<string> checkdepends {
			get {
				if (_checkdepends == null) {
					_checkdepends = new GenericArray<string> ();
					if (json_object != null) {
						unowned Json.Node? node = json_object.get_member ("CheckDepends");
						if (node != null) {
							unowned Json.Array json_array = node.get_array ();
							populate_array (json_array, ref _checkdepends);
						}
					}
				}
				return _checkdepends;
			}
		}
		public override GenericArray<string> requiredby {
			get {
				if (_requiredby == null) {
					_requiredby = new GenericArray<string> ();
					if (!is_update && local_pkg != null) {
						Alpm.List<string> owned_list = local_pkg.compute_requiredby ();
						unowned Alpm.List<string> list = owned_list;
						while (list != null) {
							_requiredby.add ((owned) list.data);
							list.next ();
						}
					}
				}
				return _requiredby;
			}
		}
		public override GenericArray<string> optionalfor {
			get {
				if (_optionalfor == null) {
					_optionalfor = new GenericArray<string> ();
					if (!is_update && local_pkg != null) {
						Alpm.List<string> owned_list = local_pkg.compute_optionalfor ();
						unowned Alpm.List<string> list = owned_list;
						while (list != null) {
							_optionalfor.add ((owned) list.data);
							list.next ();
						}
					}
				}
				return _optionalfor;
			}
		}
		public override GenericArray<string> provides {
			get {
				if (_provides == null) {
					_provides = new GenericArray<string> ();
					if (!is_update && local_pkg != null) {
						unowned Alpm.List<unowned Alpm.Depend> list = local_pkg.provides;
						while (list != null) {
							_provides.add (list.data.compute_string ());
							list.next ();
						}
					} else if (json_object != null) {
						unowned Json.Node? node = json_object.get_member ("Provides");
						if (node != null) {
							unowned Json.Array json_array = node.get_array ();
							populate_array (json_array, ref _provides);
						}
					}
				}
				return _provides;
			}
			internal set { _provides = value; }
		}
		public override GenericArray<string> replaces {
			get {
				if (_replaces == null) {
					_replaces = new GenericArray<string> ();
					if (!is_update && local_pkg != null) {
						unowned Alpm.List<unowned Alpm.Depend> list = local_pkg.replaces;
						while (list != null) {
							_replaces.add (list.data.compute_string ());
							list.next ();
						}
					} else if (json_object != null) {
						unowned Json.Node? node = json_object.get_member ("Replaces");
						if (node != null) {
							unowned Json.Array json_array = node.get_array ();
							populate_array (json_array, ref _replaces);
						}
					}
				}
				return _replaces;
			}
			internal set { _replaces = value; }
		}
		public override GenericArray<string> conflicts {
			get {
				if (_conflicts == null) {
					_conflicts = new GenericArray<string> ();
					if (!is_update && local_pkg != null) {
						unowned Alpm.List<unowned Alpm.Depend> list = local_pkg.conflicts;
						while (list != null) {
							_conflicts.add (list.data.compute_string ());
							list.next ();
						}
					} else if (json_object != null) {
						unowned Json.Node? node = json_object.get_member ("Conflicts");
						if (node != null) {
							unowned Json.Array json_array = node.get_array ();
							populate_array (json_array, ref _conflicts);
						}
					}
				}
				return _conflicts;
			}
			internal set { _conflicts = value; }
		}
		public override GenericArray<string> backups {
			get {
				if (_backups == null) {
					_backups = new GenericArray<string> ();
					if (local_pkg != null) {
						unowned Alpm.List<unowned Alpm.Backup> list = local_pkg.backups;
						while (list != null) {
							var builder = new StringBuilder ("/");
							builder.append (list.data.name);
							_backups.add ((owned) builder.str);
							list.next ();
						}
					}
				}
				return _backups;
			}
		}
		// AURPackage
		public override string? packagebase {
			get {
				if (_packagebase == null) {
					_packagebase = json_object.get_string_member ("PackageBase");
				}
				return _packagebase;
			}
			internal set { _packagebase = value; }
		}
		public override string? maintainer {
			get {
				if (_maintainer == null) {
					_maintainer = json_object.get_string_member ("Maintainer");
				}
				return _maintainer;
			}
		}
		public override double popularity {
			get {
				if (_popularity == 0) {
					_popularity = json_object.get_double_member ("Popularity");
				}
				return _popularity;
			}
		}
		public override uint64 lastmodified {
			get {
				if (_lastmodified == 0) {
					_lastmodified = (uint64) json_object.get_int_member ("LastModified");
				}
				return _lastmodified;
			}
		}
		public override uint64 outofdate {
			get {
				if (_outofdate == 0) {
					unowned Json.Node? node = json_object.get_member ("OutOfDate");
					if (!node.is_null ()) {
						_outofdate = (uint64) node.get_int ();
					}
				}
				return _outofdate;
			}
		}
		public override uint64 firstsubmitted {
			get {
				if (_firstsubmitted == 0) {
					_firstsubmitted = (uint64) json_object.get_int_member ("FirstSubmitted");
				}
				return _firstsubmitted;
			}
		}
		public override uint64 numvotes {
			get {
				if (_numvotes == 0) {
					_numvotes = (uint64) json_object.get_int_member ("NumVotes");
				}
				return _numvotes;
			}
		}

		internal AURPackageLinked () {}

		internal void initialise_from_json (Json.Object? json_object, Alpm.Package? local_pkg, bool is_update = false) {
			this.json_object = json_object;
			this.is_update = is_update;
			if (local_pkg != null) {
				set_local_pkg (local_pkg);
			}
		}

		void set_local_pkg (Alpm.Package? local_pkg) {
			this.local_pkg = local_pkg;
		}

		void populate_array (Json.Array? json_array, ref GenericArray<string> array) {
			if (json_array != null) {
				uint json_array_length = json_array.get_length ();
				for (uint i = 0; i < json_array_length; i++) {
					array.add (json_array.get_string_element (i));
				}
			}
		}
	}

	internal class AURPackageData : AURPackageLinked {
		// Package
		string _version;
		string? _installed_version;
		string? _desc;
		// AURPackage
		string? _packagebase;

		// Package
		public override string version {
			get { return _version; }
			internal set { _version = value; }
		}
		public override string? installed_version {
			get { return _installed_version; }
			internal set { _installed_version = value; }
		}
		public override string? desc {
			get { return _desc; }
			internal set { _desc = value; }
		}
		// AURPackage
		public override string? packagebase {
			get { return _packagebase; }
			internal set { _packagebase = value; }
		}

		internal AURPackageData () {}
	}

	public class TransactionSummary : Object {
		public GenericArray<Package> to_install { get; internal set; default = new GenericArray<Package> (); }
		public GenericArray<Package> to_upgrade { get; internal set; default = new GenericArray<Package> (); }
		public GenericArray<Package> to_downgrade { get; internal set; default = new GenericArray<Package> (); }
		public GenericArray<Package> to_reinstall { get; internal set; default = new GenericArray<Package> (); }
		public GenericArray<Package> to_remove { get; internal set; default = new GenericArray<Package> (); }
		public GenericArray<Package> conflicts_to_remove { get; internal set; default = new GenericArray<Package> (); }
		public GenericArray<Package> to_build { get; internal set; default = new GenericArray<Package> (); }
		public GenericArray<string> aur_pkgbases_to_build { get; internal set; default = new GenericArray<string> (); }
		public GenericArray<string> to_load { internal get; internal set; default = new GenericArray<string> (); }

		internal TransactionSummary () {}
	}

	public class Updates : Object {
		public GenericArray<AlpmPackage> repos_updates { get; internal set; default = new GenericArray<AlpmPackage> (); }
		public GenericArray<AlpmPackage> ignored_repos_updates { get; internal set; default = new GenericArray<AlpmPackage> (); }
		public GenericArray<AURPackage> aur_updates { get; internal set; default = new GenericArray<AURPackage> (); }
		public GenericArray<AURPackage> ignored_aur_updates { get; internal set; default = new GenericArray<AURPackage> (); }
		public GenericArray<AURPackage> outofdate { get; internal set; default = new GenericArray<AURPackage> (); }
		#if ENABLE_FLATPAK
		public GenericArray<unowned FlatpakPackage> flatpak_updates { get; internal set; default = new GenericArray<unowned FlatpakPackage> (); }
		#endif

		internal Updates () {}
	}
}
