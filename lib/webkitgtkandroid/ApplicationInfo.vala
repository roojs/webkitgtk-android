/* Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace WebKitGtkAndroid
{
	/**
	 * WebKitGTK-shaped application info for an {@link AutomationSession}.
	 */
	public class ApplicationInfo : GLib.Object
	{
		private string name = "";
		private uint64 ver_major = 0;
		private uint64 ver_minor = 0;
		private uint64 ver_micro = 0;

		public ApplicationInfo ()
		{
		}

		public void set_name (string name)
		{
			this.name = name ?? "";
		}

		public unowned string get_name ()
		{
			return this.name;
		}

		public void set_version (uint64 major, uint64 minor, uint64 micro)
		{
			this.ver_major = major;
			this.ver_minor = minor;
			this.ver_micro = micro;
		}

		public void get_version (out uint64 major, out uint64 minor, out uint64 micro)
		{
			major = this.ver_major;
			minor = this.ver_minor;
			micro = this.ver_micro;
		}
	}
}
