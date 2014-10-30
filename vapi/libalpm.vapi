/*
 *  libalpm-vala
 *  Vala bindings for libalpm
 *
 *  Copyright (C) 2014 Guillaume Benoit <guillaume@manjaro.org>
 *  Copyright (c) 2011 Rémy Oudompheng <remy@archlinux.org>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
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

[CCode (cprefix = "alpm_", cheader_filename="alpm.h")]
namespace Alpm {

	[SimpleType]
	[CCode (cname = "alpm_time_t", has_type_id = false)]
	public struct Time : uint64 {}

	/**
	* Library
	*/
	public string version();

	public unowned Package? find_satisfier(Alpm.List<Package> pkgs, string depstring);
	public unowned Package? pkg_find(Alpm.List<Package> haystack, string needle);
	public int pkg_vercmp(string a, string b);
	public unowned Alpm.List<Package?> find_group_pkgs(Alpm.List<DB> dbs, string name);
	public unowned Package? sync_newversion(Package pkg, Alpm.List<DB> dbs);
	/** Returns the string corresponding to an error number. */
	public unowned string strerror(Errno err);

	/** Package install reasons. */
	[CCode (cname = "alpm_pkgreason_t", cprefix = "ALPM_PKG_REASON_")]
	public enum PkgReason {
		/** Explicitly requested by the user. */
		EXPLICIT = 0,
		/** Installed as a dependency for another package. */
		DEPEND = 1
	}

	/** Location a package object was loaded from. */
	[CCode (cname = "alpm_pkgfrom_t", cprefix = "ALPM_PKG_FROM_")]
	public enum PkgFrom {
		FILE = 1,
		LOCALDB,
		SYNCDB
	}

	/** Method used to validate a package. */
	[CCode (cname = "alpm_pkgvalidation_t", cprefix = "ALPM_PKG_VALIDATION_")]
	public enum PkgValidation {
		UNKNOWN = 0,
		NONE = (1 << 0),
		MD5SUM = (1 << 1),
		SHA256SUM = (1 << 2),
		SIGNATURE = (1 << 3)
	}

	/** Types of version constraints in dependency specs. */
	[CCode (cname = "alpm_depmod_t", cprefix = "ALPM_DEP_MOD_")]
	public enum DepMod {
		/** No version constraint */
		ANY = 1,
		/** Test version equality (package=x.y.z) */
		EQ,
		/** Test for at least a version (package>=x.y.z) */
		GE,
		/** Test for at most a version (package<=x.y.z) */
		LE,
		/** Test for greater than some version (package>x.y.z) */
		GT,
		/** Test for less than some version (package<x.y.z) */
		LT
	}

	/**
	* File conflict type.
	* Whether the conflict results from a file existing on the filesystem, or with
	* another target in the transaction.
	*/
	[CCode (cname = "alpm_fileconflicttype_t", cprefix = "ALPM_FILECONFLICT_")]
	public enum FileConflictType {
		TARGET = 1,
		FILESYSTEM
	}

	/** PGP signature verification options */
	[CCode (cname = "alpm_siglevel_t", cprefix = "ALPM_SIG_")]
	public enum SigLevel {
		PACKAGE = (1 << 0),
		PACKAGE_OPTIONAL = (1 << 1),
		PACKAGE_MARGINAL_OK = (1 << 2),
		PACKAGE_UNKNOWN_OK = (1 << 3),

		DATABASE = (1 << 10),
		DATABASE_OPTIONAL = (1 << 11),
		DATABASE_MARGINAL_OK = (1 << 12),
		DATABASE_UNKNOWN_OK = (1 << 13),

		PACKAGE_SET = (1 << 27),
		PACKAGE_TRUST_SET = (1 << 28),

		USE_DEFAULT = (1 << 31)
	}

	/** PGP signature verification status return codes */
	[CCode (cname = "alpm_sigstatus_t", cprefix = "ALPM_SIGSTATUS_")]
	public enum SigStatus {
		VALID,
		KEY_EXPIRED,
		SIG_EXPIRED,
		KEY_UNKNOWN,
		KEY_DISABLED,
		INVALID
	}

	/** PGP signature verification status return codes */
	[CCode (cname = "alpm_sigvalidity_t", cprefix = "ALPM_SIGVALIDITY_")]
	public enum SigValidity {
		FULL,
		MARGINAL,
		NEVER,
		UNKNOWN
	}

	/**
	 * Handle
	 */
	[CCode (cname = "alpm_handle_t", free_function = "alpm_release")]
	[Compact]
	public class Handle {
		[CCode (cname = "alpm_initialize")]
		public Handle (string root, string dbpath, out Alpm.Errno error);

		public unowned string root {
			[CCode (cname = "alpm_option_get_root")] get;
		}
		public unowned string dbpath {
			[CCode (cname = "alpm_option_get_dbpath")] get;
		}
		public unowned string arch {
			[CCode (cname = "alpm_option_get_arch")] get;
			[CCode (cname = "alpm_option_set_arch")] set;
		}
		public unowned Alpm.List<unowned string?> cachedirs {
			[CCode (cname = "alpm_option_get_cachedirs")] get;
			[CCode (cname = "alpm_option_set_cachedirs")] set;
		}
		[CCode (cname = "alpm_option_add_cachedir")]
		public int add_cachedir(string cachedir);
		[CCode (cname = "alpm_option_remove_cachedir")]
		public int remove_cachedir(string cachedir);

		public unowned string logfile {
			[CCode (cname = "alpm_option_get_logfile")] get;
			[CCode (cname = "alpm_option_set_logfile")] set;
		}
		public unowned string lockfile {
			[CCode (cname = "alpm_option_get_lockfile")] get;
		}
		public unowned string gpgdir {
			[CCode (cname = "alpm_option_get_gpgdir")] get;
			[CCode (cname = "alpm_option_set_gpgdir")] set;
		}
		public int usesyslog {
			[CCode (cname = "alpm_option_get_usesyslog")] get;
			/** Sets whether to use syslog (0 is FALSE, TRUE otherwise). */
			[CCode (cname = "alpm_option_set_usesyslog")] set;
		}
		public unowned Alpm.List<unowned string?> noupgrades {
			[CCode (cname = "alpm_option_get_noupgrades")] get;
			[CCode (cname = "alpm_option_set_noupgrades")] set;
		}
		[CCode (cname = "alpm_option_add_noupgrade")]
		public int add_noupgrade(string pkg);
		[CCode (cname = "alpm_option_remove_noupgrade")]
		public int remove_noupgrade(string pkg);

		public unowned Alpm.List<unowned string?> noextracts {
			[CCode (cname = "alpm_option_get_noextracts")] get;
			[CCode (cname = "alpm_option_set_noextracts")] set;
		}
		[CCode (cname = "alpm_option_add_noextract")]
		public int add_noextract(string pkg);
		[CCode (cname = "alpm_option_remove_noextract")]
		public int remove_noextract(string pkg);

		public unowned Alpm.List<unowned string?> ignorepkgs {
			[CCode (cname = "alpm_option_get_ignorepkgs")] get;
			[CCode (cname = "alpm_option_set_ignorepkgs")] set;
		}
		[CCode (cname = "alpm_option_add_ignorepkg")]
		public int add_ignorepkg(string pkg);
		[CCode (cname = "alpm_option_remove_ignorepkg")]
		public int remove_ignorepkg(string pkg);

		public unowned Alpm.List<unowned string?> ignoregroups {
			[CCode (cname = "alpm_option_get_ignoregroups")] get;
			[CCode (cname = "alpm_option_set_ignoregroups")] set;
		}
		[CCode (cname = "alpm_option_add_ignoregroup")]
		public int add_ignoregroup(string grp);
		[CCode (cname = "alpm_option_remove_ignorepkg")]
		public int remove_ignoregroup(string grp);

		public double deltaratio {
			[CCode (cname = "alpm_option_get_deltaratio")] get;
			[CCode (cname = "alpm_option_set_deltaratio")] set;
		}

		public int checkspace {
			[CCode (cname = "alpm_option_get_checkspace")] get;
			[CCode (cname = "alpm_option_set_checkspace")] set;
		}

		public SigLevel defaultsiglevel {
			[CCode (cname = "alpm_option_get_default_siglevel")] get;
			[CCode (cname = "alpm_option_set_default_siglevel")] set;
		}
		public SigLevel localfilesiglevel {
			[CCode (cname = "alpm_option_get_local_file_siglevel")] get;
			[CCode (cname = "alpm_option_set_local_file_siglevel")] set;
		}

		public SigLevel remotefilesiglevel {
			[CCode (cname = "alpm_option_get_remote_file_siglevel")] get;
			[CCode (cname = "alpm_option_set_remote_file_siglevel")] set;
		}

		[CCode (cname = "alpm_register_syncdb")]
		public unowned DB? register_syncdb(string treename, SigLevel level);
		[CCode (cname = "alpm_unregister_all_syncdbs")]
		public int unregister_all_syncdbs();


		public unowned DB? localdb {
				[CCode (cname = "alpm_get_localdb")] get;
		}

		public unowned Alpm.List<DB?> syncdbs {
				[CCode (cname = "alpm_get_syncdbs")] get;
		}

		// the return package can be freed except if it is added to a transaction,
		// it will be freed upon Handle.trans_release() invocation.
		[CCode (cname = "alpm_pkg_load_file")]
		public Package? load_file(string filename, int full, SigLevel level);

//~ 		/** Test if a package should be ignored.
//~ 		* Checks if the package is ignored via IgnorePkg, or if the package is
//~ 		* in a group ignored via IgnoreGroup.
//~ 		* @param pkg the package to test
//~ 		* @return 1 if the package should be ignored, 0 otherwise
//~ 		*/
//~ 		[CCode (cname = "alpm_pkg_should_ignore")]
//~ 		public int should_ignore(Package pkg);

		[CCode (cname = "alpm_fetch_pkgurl")]
		public string? fetch_pkgurl(string url);

		[CCode (cname = "alpm_find_dbs_satisfier")]
		public unowned Package? find_dbs_satisfier(Alpm.List<DB> dbs, string depstring);

		/** Returns the current error code from the handle. */
		[CCode (cname = "alpm_errno")]
		public Errno errno();

		/** Returns the bitfield of flags for the current transaction.*/
		[CCode (cname = "alpm_trans_get_flags")]
		public TransFlag trans_get_flags();

		/** Returns a list of packages added by the transaction.*/
		[CCode (cname = "alpm_trans_get_add")]
		public unowned Alpm.List<Package?> trans_to_add();

		/** Returns the list of packages removed by the transaction.*/
		[CCode (cname = "alpm_trans_get_remove")]
		public unowned Alpm.List<Package?> trans_to_remove();

		public LogCallBack logcb {
			[CCode (cname = "alpm_option_get_logcb")] get;
			[CCode (cname = "alpm_option_set_logcb")] set;
		}

		public DownloadCallBack dlcb {
			[CCode (cname = "alpm_option_get_dlcb")] get;
			[CCode (cname = "alpm_option_set_dlcb")] set;
		}

		public FetchCallBack fetchcb {
			[CCode (cname = "alpm_option_get_fetchcb")] get;
			[CCode (cname = "alpm_option_set_fetchcb")] set;
		}

		public TotalDownloadCallBack totaldlcb {
			[CCode (cname = "alpm_option_get_totaldlcb")] get;
			[CCode (cname = "alpm_option_set_totaldlcb")] set;
		}

		public EventCallBack eventcb {
			[CCode (cname = "alpm_option_get_eventcb")] get;
			[CCode (cname = "alpm_option_set_eventcb")] set;
		}

		public QuestionCallBack questioncb {
			[CCode (cname = "alpm_option_get_questioncb")] get;
			[CCode (cname = "alpm_option_set_questioncb")] set;
		}

		public ProgressCallBack progresscb {
			[CCode (cname = "alpm_option_get_progresscb")] get;
			[CCode (cname = "alpm_option_set_progresscb")] set;
		}

		/** Initialize the transaction.
		* @param flags flags of the transaction (like nodeps, etc)
		* @return 0 on success, -1 on error (Errno is set accordingly)
		*/
		[CCode (cname = "alpm_trans_init")]
		public int trans_init(TransFlag transflags);

		/** Prepare a transaction.
		* @param an alpm_list where detailed description of an error
		* can be dumped (i.e. list of conflicting packages)
		* @return 0 on success, -1 on error (Errno is set accordingly)
		*/
		[CCode (cname = "alpm_trans_prepare")]
		public int trans_prepare(out Alpm.List<void*> data);

		/** Commit a transaction.
		* @param an alpm_list where detailed description of an error
		* can be dumped (i.e. list of conflicting files)
		* @return 0 on success, -1 on error (Errno is set accordingly)
		*/
		[CCode (cname = "alpm_trans_commit")]
		public int trans_commit(out Alpm.List<void*> data);

		/** Interrupt a transaction.
		* @return 0 on success, -1 on error (Errno is set accordingly)
		*/
		[CCode (cname = "alpm_trans_interrupt")]
		public int trans_interrupt();
		
		/** Release a transaction.
		* @return 0 on success, -1 on error (Errno is set accordingly)
		*/
		[CCode (cname = "alpm_trans_release")]
		public int trans_release();

		/** Search for packages to upgrade and add them to the transaction.
		* @param enable_downgrade allow downgrading of packages if the remote version is lower
		* @return 0 on success, -1 on error (Errno is set accordingly)
		*/
		[CCode (cname = "alpm_sync_sysupgrade")]
		public int trans_sysupgrade(int enable_downgrade);

		/** Add a package to the transaction.
		* If the package was loaded by load_file(), it will be freed upon
		* trans_release() invocation.
		* @param pkg the package to add
		* @return 0 on success, -1 on error (Errno is set accordingly)
		*/
		[CCode (cname = "alpm_add_pkg")]
		public int trans_add_pkg(Package pkg);

		/** Add a package removal action to the transaction.
		* @param pkg the package to uninstall
		* @return 0 on success, -1 on error (Errno is set accordingly)
		*/
		[CCode (cname = "alpm_remove_pkg")]
		public int trans_remove_pkg(Package pkg);
	}

	/**
	 * Databases
	 */
	[CCode (cname = "alpm_db_t", cprefix = "alpm_db_")]//,free_function = "alpm_db_unregister")]
	[Compact]
	public class DB {
		public int unregister();

		public unowned string name {
			[CCode (cname = "alpm_db_get_name")] get;
		}

		public SigLevel siglevel {
			[CCode (cname = "alpm_db_get_siglevel")] get;
		}

//~ 		public unowned string url {
//~ 			[CCode (cname = "alpm_db_get_url")] get;
//~ 		}

		public unowned Alpm.List<unowned string?> servers {
			[CCode (cname = "alpm_db_get_servers")] get;
			[CCode (cname = "alpm_db_set_servers")] set;
		}

		public unowned Alpm.List<Package?> pkgcache {
			[CCode (cname = "alpm_db_get_pkgcache")] get;
		}

		public unowned Alpm.List<Group?> groupcache {
			[CCode (cname = "alpm_db_get_groupcache")] get;
		}

		public int add_server(string url);
		public int remove_server(string url);

		[CCode (instance_pos = 1.1)]
		public int update(int force);

		public unowned Package? get_pkg(string name);
		public unowned Group? get_group(string name);
		public unowned Alpm.List<Package?> search(Alpm.List<string> needles);
	}

	/**
	 * Packages
	 */
	[CCode (cname = "alpm_pkg_t", cprefix = "alpm_pkg_", free_function = "alpm_pkg_free")]
	[Compact]
	public class Package {
		public static int checkmd5sum();

		public Alpm.List<string?> compute_requiredby();
		public Alpm.List<string?> compute_optionalfor();

		/* properties */
		[CCode (array_length = false)]
		public unowned string filename {
			[CCode (cname = "alpm_pkg_get_filename")] get;
		}
		[CCode (array_length = false)]
		public unowned string name {
			[CCode (cname = "alpm_pkg_get_name")] get;
		}
		[CCode (array_length = false)]
		public unowned string version {
			[CCode (cname = "alpm_pkg_get_version")] get;
		}
		public PkgFrom origin {
			[CCode (cname = "alpm_pkg_get_origin")] get;
		}
		[CCode (array_length = false)]
		public unowned string desc {
			[CCode (cname = "alpm_pkg_get_desc")] get;
		}
		[CCode (array_length = false)]
		public unowned string url {
			[CCode (cname = "alpm_pkg_get_url")] get;
		}
		public Time builddate {
			[CCode (cname = "alpm_pkg_get_builddate")] get;
		}
		public Time installdate {
			[CCode (cname = "alpm_pkg_get_installdate")] get;
		}
		[CCode (array_length = false)]
		public unowned string packager {
			[CCode (cname = "alpm_pkg_get_packager")] get;
		}
		[CCode (array_length = false)]
		public unowned string md5sum {
			[CCode (cname = "alpm_pkg_get_md5sum")] get;
		}
		[CCode (array_length = false)]
		public unowned string arch {
			[CCode (cname = "alpm_pkg_get_arch")] get;
		}

		/** Returns the size of the package. This is only available for sync database
		 * packages and package files, not those loaded from the local database.
		 */
		public uint64 size {
			[CCode (cname = "alpm_pkg_get_size")] get;
		}

		public uint64 isize {
			[CCode (cname = "alpm_pkg_get_isize")] get;
		}
		public uint64 download_size {
			[CCode (cname = "alpm_pkg_download_size")] get;
		}
		public PkgReason reason {
			[CCode (cname = "alpm_pkg_get_reason")] get;
			/** The provided package object must be from the local database
			 * or this method will fail (Errno is set accordingly).
			 */
			[CCode (cname = "alpm_pkg_set_reason")] set;
		}
		public unowned Alpm.List<unowned string?> licenses {
			[CCode (cname = "alpm_pkg_get_licenses")] get;
		}
		public unowned Alpm.List<unowned string?> groups {
			[CCode (cname = "alpm_pkg_get_groups")] get;
		}
		public unowned Alpm.List<Depend?> depends {
			[CCode (cname = "alpm_pkg_get_depends")] get;
		}
		public unowned Alpm.List<Depend?> optdepends {
			[CCode (cname = "alpm_pkg_get_optdepends")] get;
		}
		public unowned Alpm.List<Depend?> conflicts {
			[CCode (cname = "alpm_pkg_get_conflicts")] get;
		}
		public unowned Alpm.List<Depend?> provides {
			[CCode (cname = "alpm_pkg_get_provides")] get;
		}
		public unowned Alpm.List<Depend?> replaces {
			[CCode (cname = "alpm_pkg_get_replaces")] get;
		}
		public unowned Alpm.List<File?> files {
			[CCode (cname = "alpm_pkg_get_files_list")] get;
		}
		public unowned Alpm.List<Backup?> backup {
			[CCode (cname = "alpm_pkg_get_backup")] get;
		}
		public unowned DB? db {
			[CCode (cname = "alpm_pkg_get_db")] get;
		}
		public unowned string base64_sig {
			[CCode (cname = "alpm_pkg_get_base64_sig")] get;
		}
		/* TODO: changelog functions */
	}

	/** Dependency */
	[CCode (cname = "alpm_depend_t", has_type_id = false)]
	public class Depend {
		public string name;
		public string version;
		public string desc;
		public ulong name_hash;
		public DepMod mod;
		[CCode (cname = "alpm_dep_compute_string")]
		public string compute_string();
	}

	/** Missing dependency */
	[CCode (cname = "alpm_depmissing_t", has_type_id = false)]
	public class DepMissing {
		public string target;
		public unowned Depend depend;
		/* this is used only in the case of a remove dependency error */
		public string causingpkg;
	}

	/** Conflict */
	[CCode (cname = "alpm_conflict_t", has_type_id = false)]
	public class Conflict {
		public ulong package1_hash;
		public ulong package2_hash;
		public string package1;
		public string package2;
		public unowned Depend reason;
	}

	/** File conflict */
	[CCode (cname = "alpm_fileconflict_t", has_type_id = false)]
	public class FileConflict {
		public string target;
		public FileConflictType type;
		public string file;
		public string ctarget;
	}

	/** Package group */
	[CCode (cname = "alpm_group_t", has_type_id = false)]
	public class Group {
		public string name;
		public unowned Alpm.List<Package?> packages;
	}

	/** Package upgrade delta */
	[CCode (cname = "alpm_delta_t", has_type_id = false)]
	public class Delta {
		/** filename of the delta patch */
		public string delta;
		/** md5sum of the delta file */
		public string delta_md5;
		/** filename of the 'before' file */
		public string from;
		/** filename of the 'after' file */
		public string to;
		/** filesize of the delta file */
		public uint64 delta_size;
		/** download filesize of the delta file */
		public uint64 download_size;
	}

	/** File in a package */
	[CCode (cname = "alpm_file_t", has_type_id = false)]
	public class File {
		public string name;
		public uint64 size;
		public uint64 mode;
	}

	/** Package filelist container */
	/*[CCode (cname = "alpm_filelist_t", has_type_id = false)]
	public class FileList {
		public size_t count;
		public Alpm.File *files;
		public char **resolved_path;
	}*/

	/** Local package or package file backup entry */
	[CCode (cname = "alpm_backup_t", has_type_id = false)]
	public class Backup {
		public string name;
		public string hash;
	}

	[CCode (cname = "alpm_pgpkey_t", has_type_id = false)]
	public class PGPKey {
		public void *data;
		public string fingerprint;
		public string uid;
		public string name;
		public string email;
		public Time created;
		public Time expires;
		public uint length;
		public uint revoked;
		public string pubkey_algo;
	}

	/**
	* Signature result. Contains the key, status, and validity of a given
	* signature.
	*/
	[CCode (cname = "alpm_sigresult_t", has_type_id = false)]
	public class SigResult {
		public PGPKey key;
		public SigStatus status;
		public SigValidity validity;
	}

	/**
	* Signature list. Contains the number of signatures found and a pointer to an
	* array of results. The array is of size count.
	*/
	[CCode (cname = "alpm_siglist_t", has_type_id = false)]
	public class SigList {
		public size_t count;
		public SigResult results;
	}

	/** Logging Levels */
	[CCode (cname = "alpm_loglevel_t", cprefix = "ALPM_LOG_")]
	public enum LogLevel {
		ERROR    = 1,
		WARNING  = (1 << 1),
		DEBUG    = (1 << 2),
		FUNCTION = (1 << 3)
	}

	/** Log callback */
	[CCode (cname = "alpm_cb_log", has_type_id = false, has_target = false)]
	public delegate void LogCallBack(LogLevel level, string fmt, va_list args);

	/**
	* Events.
	* NULL parameters are passed to in all events unless specified otherwise.
	*/
	[CCode (cname = "alpm_event_t", cprefix = "ALPM_EVENT_")]
	public enum Event {
		/** Dependencies will be computed for a package. */
		CHECKDEPS_START = 1,
		/** Dependencies were computed for a package. */
		CHECKDEPS_DONE,
		/** File conflicts will be computed for a package. */
		FILECONFLICTS_START,
		/** File conflicts were computed for a package. */
		FILECONFLICTS_DONE,
		/** Dependencies will be resolved for target package. */
		RESOLVEDEPS_START,
		/** Dependencies were resolved for target package. */
		RESOLVEDEPS_DONE,
		/** Inter-conflicts will be checked for target package. */
		INTERCONFLICTS_START,
		/** Inter-conflicts were checked for target package. */
		INTERCONFLICTS_DONE,
		/** Package will be installed.
		 * A pointer to the target package is passed to the callback.
		 */
		ADD_START,
		/** Package was installed.
		 * A pointer to the new package is passed to the callback.
		 */
		ADD_DONE,
		/** Package will be removed.
		 * A pointer to the target package is passed to the callback.
		 */
		REMOVE_START,
		/** Package was removed.
		 * A pointer to the removed package is passed to the callback.
		 */
		REMOVE_DONE,
		/** Package will be upgraded.
		 * A pointer to the upgraded package is passed to the callback.
		 */
		UPGRADE_START,
		/** Package was upgraded.
		 * A pointer to the new package, and a pointer to the old package is passed
		 * to the callback, respectively.
		 */
		UPGRADE_DONE,
		/** Package will be downgraded.
		 * A pointer to the downgraded package is passed to the callback.
		 */
		DOWNGRADE_START,
		/** Package was downgraded.
		 * A pointer to the new package, and a pointer to the old package is passed
		 * to the callback, respectively.
		 */
		DOWNGRADE_DONE,
		/** Package will be reinstalled.
		 * A pointer to the reinstalled package is passed to the callback.
		 */
		REINSTALL_START,
		/** Package was reinstalled.
		 * A pointer to the new package, and a pointer to the old package is passed
		 * to the callback, respectively.
		 */
		REINSTALL_DONE,
		/** Target package's integrity will be checked. */
		INTEGRITY_START,
		/** Target package's integrity was checked. */
		INTEGRITY_DONE,
		/** Target package will be loaded. */
		LOAD_START,
		/** Target package is finished loading. */
		LOAD_DONE,
		/** Target delta's integrity will be checked. */
		DELTA_INTEGRITY_START,
		/** Target delta's integrity was checked. */
		DELTA_INTEGRITY_DONE,
		/** Deltas will be applied to packages. */
		DELTA_PATCHES_START,
		/** Deltas were applied to packages. */
		DELTA_PATCHES_DONE,
		/** Delta patch will be applied to target package.
		 * The filename of the package and the filename of the patch is passed to the
		 * callback.
		 */
		DELTA_PATCH_START,
		/** Delta patch was applied to target package. */
		DELTA_PATCH_DONE,
		/** Delta patch failed to apply to target package. */
		DELTA_PATCH_FAILED,
		/** Scriptlet has printed information.
		 * A line of text is passed to the callback.
		 */
		SCRIPTLET_INFO,
		/** Files will be downloaded from a repository.
		 * The repository's tree name is passed to the callback.
		 */
		RETRIEVE_START,
		/** Disk space usage will be computed for a package */
		DISKSPACE_START,
		/** Disk space usage was computed for a package */
		DISKSPACE_DONE,
		/** An optdepend for another package is being removed
		 * The requiring package and its dependency are passed to the callback */
		OPTDEP_REQUIRED,
		/** A configured repository database is missing */
		DATABASE_MISSING,
		/** Checking keys used to create signatures are in keyring. */
		KEYRING_START,
		/** Keyring checking is finished. */
		KEYRING_DONE,
		/** Downloading missing keys into keyring. */
		KEY_DOWNLOAD_START,
		/** Key downloading is finished. */
		KEY_DOWNLOAD_DONE
	}

	/** Event callback */
	[CCode (cname = "alpm_cb_event", has_type_id = false, has_target = false)]
	public delegate void EventCallBack (Event event, void *data1, void *data2);

	/**
	* Questions.
	* Unlike the events or progress enumerations, this enum has bitmask values
	* so a frontend can use a bitmask map to supply preselected answers to the
	* different types of questions.
	*/
	[CCode (cname = "alpm_question_t", cprefix = "ALPM_QUESTION_")]
	public enum Question {
		INSTALL_IGNOREPKG = 1,
		REPLACE_PKG = (1 << 1),
		CONFLICT_PKG = (1 << 2),
		CORRUPTED_PKG = (1 << 3),
		REMOVE_PKGS = (1 << 4),
		SELECT_PROVIDER = (1 << 5),
		IMPORT_KEY = (1 << 6)
	}

	/** Question callback */
	[CCode (cname = "alpm_cb_question", has_type_id = false, has_target = false)]
	public delegate void QuestionCallBack (Question question, void *data1, void *data2, void *data3,  out int response);

	/** Progress */
	[CCode (cname = "alpm_progress_t", cprefix = "ALPM_PROGRESS_")]
	public enum Progress {
		ADD_START,
		UPGRADE_START,
		DOWNGRADE_START,
		REINSTALL_START,
		REMOVE_START,
		CONFLICTS_START,
		DISKSPACE_START,
		INTEGRITY_START,
		LOAD_START,
		KEYRING_START
	}

	/** Progress callback */
	[CCode (cname = "alpm_cb_progress", has_type_id = false, has_target = false)]
	public delegate void ProgressCallBack (Progress progress, string pkgname, int percent, uint n_targets, uint current_target);

	/** Type of download progress callbacks.
	* @param filename the name of the file being downloaded
	* @param xfered the number of transferred bytes
	* @param total the total number of bytes to transfer
	*/
	[CCode (cname = "alpm_cb_download", has_type_id = false, has_target = false)]
	public delegate void DownloadCallBack (string filename, uint64 xfered, uint64 total);

	[CCode (cname = "alpm_cb_totaldl", has_type_id = false, has_target = false)]
	public delegate void TotalDownloadCallBack (uint64 total);

	/** A callback for downloading files
	* @param url the URL of the file to be downloaded
	* @param localpath the directory to which the file should be downloaded
	* @param force whether to force an update, even if the file is the same
	* @return 0 on success, 1 if the file exists and is identical, -1 on
	* error.
	*/
	[CCode (cname = "alpm_cb_fetch", has_type_id = false, has_target = false)]
	public delegate int FetchCallBack (string url, string localpath, int force);

	/** Transaction flags */
	[CCode (cname = "alpm_transflag_t", cprefix = "ALPM_TRANS_FLAG_")]
	public enum TransFlag {
		/** Ignore dependency checks. */
		NODEPS = 1,
		/** Ignore file conflicts and overwrite files. */
		FORCE = (1 << 1),
		/** Delete files even if they are tagged as backup. */
		NOSAVE = (1 << 2),
		/** Ignore version numbers when checking dependencies. */
		NODEPVERSION = (1 << 3),
		/** Remove also any packages depending on a package being removed. */
		CASCADE = (1 << 4),
		/** Remove packages and their unneeded deps (not explicitly installed). */
		RECURSE = (1 << 5),
		/** Modify database but do not commit changes to the filesystem. */
		DBONLY = (1 << 6),
		/** Use ALPM_PKG_REASON_DEPEND when installing packages. */
		ALLDEPS = (1 << 8),
		/** Only download packages and do not actually install. */
		DOWNLOADONLY = (1 << 9),
		/** Do not execute install scriptlets after installing. */
		NOSCRIPTLET = (1 << 10),
		/** Ignore dependency conflicts. */
		NOCONFLICTS = (1 << 11),
		/** Do not install a package if it is already installed and up to date. */
		NEEDED = (1 << 13),
		/** Use ALPM_PKG_REASON_EXPLICIT when installing packages. */
		ALLEXPLICIT = (1 << 14),
		/** Do not remove a package if it is needed by another one. */
		UNNEEDED = (1 << 15),
		/** Remove also explicitly installed unneeded deps (use with ALPM_TRANS_FLAG_RECURSE). */
		RECURSEALL = (1 << 16),
		/** Do not lock the database during the operation. */
		NOLOCK = (1 << 17)
	}

	/**
	 * Errnos
	 */
	[CCode (cname = "alpm_errno_t", cprefix = "ALPM_ERR_")]
	public enum Errno {
		MEMORY = 1,
		SYSTEM,
		BADPERMS,
		NOT_A_FILE,
		NOT_A_DIR,
		WRONG_ARGS,
		DISK_SPACE,
		/* Interface */
		HANDLE_NULL,
		HANDLE_NOT_NULL,
		HANDLE_LOCK,
		/* Databases */
		DB_OPEN,
		DB_CREATE,
		DB_NULL,
		DB_NOT_NULL,
		DB_NOT_FOUND,
		DB_INVALID,
		DB_INVALID_SIG,
		DB_VERSION,
		DB_WRITE,
		DB_REMOVE,
		/* Servers */
		SERVER_BAD_URL,
		SERVER_NONE,
		/* Transactions */
		TRANS_NOT_NULL,
		TRANS_NULL,
		TRANS_DUP_TARGET,
		TRANS_NOT_INITIALIZED,
		TRANS_NOT_PREPARED,
		TRANS_ABORT,
		TRANS_TYPE,
		TRANS_NOT_LOCKED,
		/* Packages */
		PKG_NOT_FOUND,
		PKG_IGNORED,
		PKG_INVALID,
		PKG_INVALID_CHECKSUM,
		PKG_INVALID_SIG,
		PKG_OPEN,
		PKG_CANT_REMOVE,
		PKG_INVALID_NAME,
		PKG_INVALID_ARCH,
		PKG_REPO_NOT_FOUND,
		/* Signatures */
		SIG_MISSING,
		SIG_INVALID,
		/* Deltas */
		DLT_INVALID,
		DLT_PATCHFAILED,
		/* Dependencies */
		UNSATISFIED_DEPS,
		CONFLICTING_DEPS,
		FILE_CONFLICTS,
		/* Misc */
		RETRIEVE,
		INVALID_REGEX,
		/* External library errors */
		LIBARCHIVE,
		LIBCURL,
		EXTERNAL_DOWNLOAD,
		GPGME
	}

[CCode (cprefix = "alpm_list_", cheader_filename = "alpm_list.h,alpm-util.h",
		cname = "alpm_list_t", type_parameters = "G", free_function = "alpm_list_free_all")]
	[Compact]
	public class List<G> {
		/* Comparator*/
		[CCode (cname = "alpm_list_fn_cmp", has_target = false)]
		public delegate int CompareFunc<G>(G a, G b);

		/* properties */
		public size_t length {
		[CCode (cname = "alpm_list_count")] get;
		}
		public unowned G? data {
		[CCode (cname = "alpm_list_get_data")] get;
		}

		/* item mutators */
		[ReturnsModifiedPointer ()]
		public unowned void add(G data);

		[ReturnsModifiedPointer ()]
		public unowned void join(List<G> list);

		[CCode (cname = "alpm_list_sort_data"), ReturnsModifiedPointer ()]
		public unowned void sort(CompareFunc fn);

		[CCode (cname = "alpm_list_remove_data"), ReturnsModifiedPointer ()]
		public unowned void? remove(G data, CompareFunc fn);

		public List<G> copy();

		[ReturnsModifiedPointer ()]
		public unowned void reverse ();

		/* item accessors */
		public unowned List<G>? first();
		public unowned List<G>? last();
		public unowned List<G>? nth(size_t index);
		public unowned List<G>? next();
		public unowned List<G>? previous();

		public unowned G? nth_data(size_t index);

		/* misc */
		public unowned string? find_str(string needle);

		/** @return a list containing all items in `this` not present in `list` */
		public unowned List<G>? diff(List<G>? list, CompareFunc fn);

		/* iterator */
		public Iterator<G> iterator();

		[CCode (cname = "alpm_list_iterator_t", cprefix = "alpm_list_iterator_")]
		public struct Iterator<G> {
			public unowned G? next_value();
		}
	}
}

/* vim: set ts=2 sw=2 noet: */
