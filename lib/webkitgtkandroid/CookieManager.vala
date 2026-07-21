/* Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern bool wka_host_get_cookies (string uri, out string? cookies_text);
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern bool wka_host_add_cookie (
	string name,
	string value,
	string domain,
	string path,
	bool http_only,
	bool secure
);

namespace WebKitGtkAndroid
{
	/**
	 * Cookie jar for the embedded WebView (android.webkit.CookieManager).
	 * Shape matches webview2-gtk / WebKitGTK CookieManager for OLLMchat site_cookies.
	 */
	public class CookieManager : GLib.Object
	{
		public void set_accept_policy (CookieAcceptPolicy policy)
		{
			/* Android CookieManager accepts all by default after attach. */
			if (policy == CookieAcceptPolicy.NEVER) {
				GLib.warning ("CookieAcceptPolicy.NEVER not mapped on Android");
			}
		}

		public void set_persistent_storage (string filename, CookiePersistentStorage storage)
		{
			/* System WebView jar is already persistent; no-op. */
		}

		/**
		 * Cookies for ''uri'' as Soup.Cookie list (from Cookie header).
		 */
		public async GLib.List<Soup.Cookie> get_cookies (
			string uri,
			GLib.Cancellable? cancellable = null
		) throws GLib.Error {
			string? raw = null;
			if (!wka_host_get_cookies (uri, out raw)) {
				throw new NetworkError.FAILED ("get_cookies failed");
			}
			var list = new GLib.List<Soup.Cookie> ();
			if (raw == null || raw.strip () == "") {
				return list;
			}
			GLib.Uri origin;
			try {
				origin = GLib.Uri.parse (uri, GLib.UriFlags.NONE);
			} catch (GLib.Error e) {
				throw e;
			}
			foreach (var part in raw.split (";")) {
				var piece = part.strip ();
				if (piece == "") {
					continue;
				}
				var cookie = Soup.Cookie.parse (piece, origin);
				if (cookie != null) {
					list.append (cookie);
				}
			}
			return list;
		}

		public async bool add_cookie (
			Soup.Cookie cookie,
			GLib.Cancellable? cancellable = null
		) throws GLib.Error {
			var domain = cookie.get_domain ();
			var path = cookie.get_path ();
			if (domain == null) {
				domain = "";
			}
			if (path == null || path == "") {
				path = "/";
			}
			if (!wka_host_add_cookie (
					cookie.get_name (),
					cookie.get_value (),
					domain,
					path,
					cookie.get_http_only (),
					cookie.get_secure ())) {
				throw new NetworkError.FAILED ("add_cookie failed");
			}
			return true;
		}
	}
}
