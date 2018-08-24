/*
 *  pamac-vala
 *
 *  Copyright (C) 2014-2018 Guillaume Benoit <guillaume@manjaro.org>
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
	public struct TransactionSummary {
		public AlpmPackage[] to_install;
		public AlpmPackage[] to_upgrade;
		public AlpmPackage[] to_downgrade;
		public AlpmPackage[] to_reinstall;
		public AlpmPackage[] to_remove;
		public AURPackage[] to_build;
		public AlpmPackage[] aur_conflicts_to_remove;
		public string[] aur_pkgbases_to_build;
	}

	public struct Updates {
		public AlpmPackage[] repos_updates;
		public AURPackage[] aur_updates;
	}

	public struct UpdatesPriv {
		public bool syncfirst;
		public AlpmPackage[] repos_updates;
		public AURPackage[] aur_updates;
	}

	public struct ErrorInfos {
		public uint no;
		public string message;
		public string[] details;
		public ErrorInfos () {
			message = "";
		}
	}
}

