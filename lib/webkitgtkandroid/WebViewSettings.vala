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
	 * WebKitGTK / webview2-gtk shaped settings stub.
	 *
	 * Android System WebView has no separate DevTools window; CDP listen is
	 * via {@code WEBKIT_INSPECTOR_SERVER} + {@link WebContext.set_automation_allowed}.
	 * {@link enable_developer_extras} is accepted for API parity.
	 */
	public class WebViewSettings : GLib.Object
	{
		public bool enable_javascript { get; set; default = true; }
		public bool enable_developer_extras { get; set; default = false; }

		/**
		 * WebKit-shaped — whether page JS sees navigator.webdriver on automation.
		 * Default AUTO (stock). DISABLED is opt-in; Android host is a no-op
		 * (no WebView2-style blink boot args; stock System WebView already
		 * reports navigator.webdriver === false under CDP).
		 */
		public NavigatorWebDriverActivePolicy navigator_webdriver_active_policy {
			get;
			set;
			default = NavigatorWebDriverActivePolicy.AUTO;
		}

		public WebViewSettings ()
		{
		}
	}
}
