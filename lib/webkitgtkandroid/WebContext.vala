/* Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern void wka_host_set_automation_allowed (bool allowed);

namespace WebKitGtkAndroid
{
	/**
	 * WebKitGTK-shaped web context — automation allow + session signal.
	 *
	 * Default singleton via {@link get_default}, matching WebKit.WebContext.
	 *
	 * On Android, {@link set_automation_allowed} notifies the host. CDP listen
	 * comes from env ''WEBKIT_INSPECTOR_SERVER'' (host:port) at WebView attach
	 * → loopback TCP proxy to {@code @webview_devtools_remote_<pid>}.
	 */
	public class WebContext : GLib.Object
	{
		private static WebContext? default_context = null;

		private bool automation_allowed = false;
		private NetworkSession? automation_network_session = null;
		private bool automation_started_emitted = false;
		private bool controlled_webview_seen = false;

		/** WebKitGTK-shaped — automation client connected / session ready. */
		public signal void automation_started (AutomationSession session);

		public WebContext ()
		{
		}

		public static unowned WebContext get_default ()
		{
			if (WebContext.default_context == null) {
				WebContext.default_context = new WebContext ();
			}
			return WebContext.default_context;
		}

		public void set_automation_allowed (bool allowed)
		{
			this.automation_allowed = allowed;
			wka_host_set_automation_allowed (allowed);
			this.maybe_emit_automation_started ();
		}

		public bool is_automation_allowed ()
		{
			return this.automation_allowed;
		}

		/**
		 * Network session for automation-controlled views (WebKitGTK shape).
		 */
		public NetworkSession? get_network_session_for_automation ()
		{
			if (this.automation_network_session == null) {
				this.automation_network_session = new NetworkSession ();
			}
			return this.automation_network_session;
		}

		/**
		 * A {@link WebView} with {@link WebView.is_controlled_by_automation} was created.
		 * Session emit is deferred so callers can connect {@link automation_started} first.
		 */
		internal void register_controlled_webview (WebView view)
		{
			this.controlled_webview_seen = true;
			Idle.add (() => {
				this.maybe_emit_automation_started ();
				return false;
			});
		}

		private void maybe_emit_automation_started ()
		{
			if (!this.automation_allowed
			    || !this.controlled_webview_seen
			    || this.automation_started_emitted) {
				return;
			}
			this.automation_started_emitted = true;
			var session = new AutomationSession ();
			this.automation_started (session);
		}
	}
}
