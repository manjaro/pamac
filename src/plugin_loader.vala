/*
 *  pamac-vala
 *
 *  Copyright (C) 2019-2020 Guillaume Benoit <guillaume@manjaro.org>
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
	internal class PluginLoader<T> : Object {
		public string path { get; private set; }
		Type type;
		Module module;

		delegate Type RegisterPluginFunction (Module module);

		public PluginLoader (string name) {
			assert (Module.supported ());
			this.path = Module.build_path (null, name);
		}

		public bool load () {
			module = Module.open (path, ModuleFlags.LAZY);
			if (module == null) {
				return false;
			}

			void* function;
			module.symbol ("register_plugin", out function);
			unowned RegisterPluginFunction register_plugin = (RegisterPluginFunction) function;
			type = register_plugin (module);
			return true;
		}

		public T new_object () {
			return Object.new (type);
		}
	}
}
