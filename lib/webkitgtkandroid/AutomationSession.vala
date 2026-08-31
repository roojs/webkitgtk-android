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
	 * WebKitGTK-shaped automation session (browser side).
	 *
	 * Created when automation is allowed and a controlled {@link WebView} exists.
	 * Fill/press stay in the consumer CDP client — not methods here.
	 */
	public class AutomationSession : GLib.Object
	{
		private ApplicationInfo app_info = new ApplicationInfo ();

		/** WebKitGTK-shaped — same as session id string. */
		public string id { get; private set; }

		/**
		 * Emitted when the automation client needs a view (WebKitGTK shape).
		 * Return the primary controlled {@link WebView} as Gtk.Widget to avoid
		 * GType cycles with WebView → WebContext → AutomationSession.
		 */
		public signal Gtk.Widget create_web_view ();

		internal AutomationSession ()
		{
			this.id = "wka-%u".printf ((uint) Random.next_int ());
		}

		public void set_application_info (ApplicationInfo info)
		{
			if (info != null) {
				this.app_info = info;
			}
		}

		public unowned ApplicationInfo get_application_info ()
		{
			return this.app_info;
		}
	}
}
