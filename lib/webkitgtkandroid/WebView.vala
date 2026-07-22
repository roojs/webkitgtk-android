/* Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

/**
 * GTK 4 widget embedding Android System WebView (WebKitGTK-shaped subset).
 *
 * Phase 2: navigation + load_changed.
 * Phase 3: host a11y via wka_host_a11y_* (webview2-gtk-shaped).
 */

[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern bool wka_host_create_with_xywh (
	Gtk.Widget widget,
	int x,
	int y,
	int width,
	int height,
	string url
);
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern void wka_host_set_bounds_xywh (int x, int y, int width, int height);
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern bool wka_host_navigate (string url);
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern void wka_host_go_back ();
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern void wka_host_go_forward ();
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern void wka_host_reload ();
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern void wka_host_stop ();
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern bool wka_host_can_go_back ();
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern bool wka_host_can_go_forward ();
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern void wka_host_destroy ();
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern bool wka_host_is_ready ();
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern unowned string wka_host_get_uri ();
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern unowned string wka_host_get_title ();
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern void wka_host_put_is_visible (bool visible);
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern void wka_host_use_display_size (Gtk.Widget widget);
[CCode (cheader_filename = "webkitgtk-android-host-api.h", has_target = false)]
public delegate void WkaLoadChangedCb (void* user_data, int load_event);
[CCode (cheader_filename = "webkitgtk-android-host-api.h", has_target = false)]
public delegate void WkaTitleCb (void* user_data);
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern void wka_host_set_event_handlers (
	WkaLoadChangedCb? load_changed,
	WkaTitleCb? title_changed,
	void* user_data
);
[CCode (cheader_filename = "webkitgtk-android-host-api.h", has_target = false)]
public delegate void WkaDocumentResponseCb (
	void* user_data,
	int status,
	[CCode (array_length = false)] unowned string[] header_names,
	[CCode (array_length = false)] unowned string[] header_values,
	size_t header_count
);
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern void wka_host_set_document_response_handler (
	WkaDocumentResponseCb? handler,
	void* user_data
);
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern bool wka_widget_bounds_xywh (
	Gtk.Widget widget,
	out int x,
	out int y,
	out int width,
	out int height
);

[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern bool wka_host_a11y_ensure ();
[CCode (cheader_filename = "webkitgtk-android-host-api.h", has_target = false)]
public delegate void WkaA11yForeachCb (
	int id,
	int parent_id,
	int x,
	int y,
	int w,
	int h,
	string name,
	string role,
	string value,
	string uri,
	bool can_invoke,
	bool can_set_value,
	void* user_data
);
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern bool wka_host_a11y_walk_foreach (WkaA11yForeachCb cb, void* user_data);
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern bool wka_host_a11y_invoke (int id);
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern bool wka_host_a11y_set_value (int id, string utf8);
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern bool wka_host_a11y_focus (int id);
[CCode (cheader_filename = "webkitgtk-android-host-api.h", has_target = false)]
public delegate void WkaFreezeFrameCb (GLib.Bytes? rgba, int width, int height, void* user_data);
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern void wka_host_set_freeze_frame_handler (WkaFreezeFrameCb? cb);
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern bool wka_host_freeze ();
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern bool wka_host_resume ();

namespace WebKitGtkAndroid
{
	/**
	 * Embeds Android System WebView over the GTK Android surface.
	 *
	 * Limitation (v0.1): one WebView host per process.
	 *
	 * Modal freeze: watches the same toplevel for overlay UI → auto
	 * {@link refresh_freeze}. Detects GObject type name ''AdwDialog''
	 * (string match up the type hierarchy, no Adwaita link) and transient
	 * {@link Gtk.Window}. Hooks ''parent-set'' so freeze runs when a dialog
	 * is parented — before map/present finishes. Set {@link freeze_manual} and
	 * call {@link refresh_freeze} for overlay UI the monitor does not see.
	 */
	public class WebView : Gtk.Box
	{
		private static GenericArray<WebView> freeze_watchers = new GenericArray<WebView> ();
		private static bool freeze_hooks_installed = false;
		private static uint sig_parent_set;
		private static uint sig_unmap;

		private Gtk.Overlay overlay;
		private Gtk.Widget host_area;
		/*
		 * FILL into host_area (under app toolbar). Do not paint at tex/gtk_scale —
		 * that is narrower than the density-sized host and looks horizontally
		 * scaled once the SurfaceView maps buffer→screen. Android ImageView
		 * cover (WebViewFreeze) keeps 1:1 pixels under the system nav bar.
		 */
		public Gtk.Picture freeze_picture;
		private bool attached = false;
		public bool freeze_active = false;
		public bool freeze_manual = false;
		private string pending_uri = "";
		private string uri = "about:blank";
		private string title = "";
		private bool loading_flag = false;
		private double load_progress = 0.0;
		private int last_bound_x = int.MIN;
		private int last_bound_y = int.MIN;
		private int last_bound_w = int.MIN;
		private int last_bound_h = int.MIN;
		private NetworkSession network_session = new NetworkSession ();

		public bool ready {
			get {
				return this.attached && wka_host_is_ready ();
			}
		}

		/**
		 * WebKitGTK-shaped loading flag.
		 */
		public bool is_loading {
			get {
				return this.loading_flag;
			}
		}

		/**
		 * Approximate load progress (0.0…1.0). Android has no granular
		 * progress; STARTED → 0.1, FINISHED → 1.0.
		 */
		public double estimated_load_progress {
			get {
				return this.load_progress;
			}
		}

		public signal void load_changed (LoadEvent load_event);

		/**
		 * Main-frame document HTTP response (status + headers as Soup.MessageHeaders).
		 *
		 * WebKitGTK uses decide_policy RESPONSE; webview2-gtk / Android expose this
		 * signal for Cloudflare challenge detection (OLLMchat).
		 */
		public signal void main_document_response (
			uint status,
			Soup.MessageHeaders headers
		);

		/**
		 * WebKitGTK-shaped load-failed (host does not emit yet — connect is safe).
		 */
		public signal bool load_failed (LoadEvent load_event, string failing_uri, GLib.Error error);

		public WebView ()
		{
			Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.overlay = new Gtk.Overlay ();
			this.overlay.set_hexpand (true);
			this.overlay.set_vexpand (true);
			this.host_area = new Gtk.DrawingArea ();
			this.host_area.set_hexpand (true);
			this.host_area.set_vexpand (true);
			this.freeze_picture = new Gtk.Picture () {
				content_fit = Gtk.ContentFit.FILL,
				can_shrink = true,
				hexpand = true,
				vexpand = true,
				visible = false
			};
			this.overlay.set_child (this.host_area);
			this.overlay.add_overlay (this.freeze_picture);
			this.append (this.overlay);

			wka_host_set_event_handlers ((user_data, load_event) => {
				var self = (WebView) user_data;
				switch (load_event) {
				case (int) LoadEvent.STARTED:
					self.loading_flag = true;
					self.load_progress = 0.1;
					self.load_changed (LoadEvent.STARTED);
					break;
				case (int) LoadEvent.REDIRECTED:
					self.load_changed (LoadEvent.REDIRECTED);
					break;
				case (int) LoadEvent.COMMITTED:
					self.uri = wka_host_get_uri ();
					self.load_progress = 0.7;
					self.load_changed (LoadEvent.COMMITTED);
					break;
				case (int) LoadEvent.FINISHED:
					self.loading_flag = false;
					self.load_progress = 1.0;
					self.uri = wka_host_get_uri ();
					self.title = wka_host_get_title ();
					self.load_changed (LoadEvent.FINISHED);
					break;
				}
			}, (user_data) => {
				((WebView) user_data).title = wka_host_get_title ();
			}, this);
			wka_host_set_document_response_handler (
				(void*) on_document_response_cb,
				this
			);
			wka_host_set_freeze_frame_handler ((rgba, width, height, user_data) => {
				var self = (WebView) user_data;
				if (rgba == null || width <= 0 || height <= 0) {
					self.freeze_picture.visible = false;
					self.freeze_picture.set_paintable (null);
					return;
				}
				self.freeze_picture.set_paintable (new Gdk.MemoryTexture (
					width,
					height,
					Gdk.MemoryFormat.R8G8B8A8,
					rgba,
					width * 4
				));
				self.freeze_picture.visible = true;
			});

			if (!WebView.freeze_hooks_installed) {
				WebView.freeze_hooks_installed = true;
				WebView.sig_parent_set = Signal.lookup ("parent-set", typeof (Gtk.Widget));
				WebView.sig_unmap = Signal.lookup ("unmap", typeof (Gtk.Widget));
				Signal.add_emission_hook (WebView.sig_parent_set, 0, WebView.freeze_hook);
				Signal.add_emission_hook (Signal.lookup ("map", typeof (Gtk.Widget)), 0, WebView.freeze_hook);
				Signal.add_emission_hook (WebView.sig_unmap, 0, WebView.freeze_hook);
			}
			WebView.freeze_watchers.add (this);
			this.destroy.connect (() => {
				for (var i = 0; i < WebView.freeze_watchers.length; i++) {
					if (WebView.freeze_watchers[i] == this) {
						WebView.freeze_watchers.remove_index (i);
						break;
					}
				}
			});

			this.host_area.map.connect (() => {
				if (this.attached) {
					return;
				}
				int x = 0, y = 0, width = 0, height = 0;
				if (!wka_widget_bounds_xywh (this.host_area, out x, out y, out width, out height)) {
					return;
				}
				var start_uri = this.pending_uri.length > 0 ? this.pending_uri : "about:blank";
				if (!wka_host_create_with_xywh (this.host_area, x, y, width, height, start_uri)) {
					return;
				}
				this.attached = true;
				this.pending_uri = "";
				AndroidAtspi.register_webview (this);
			});
			this.host_area.add_tick_callback (() => {
				if (!this.attached) {
					int ax = 0, ay = 0, aw = 0, ah = 0;
					if (wka_widget_bounds_xywh (this.host_area, out ax, out ay, out aw, out ah)) {
						var start_uri = this.pending_uri.length > 0 ? this.pending_uri : "about:blank";
						if (wka_host_create_with_xywh (this.host_area, ax, ay, aw, ah, start_uri)) {
							this.attached = true;
							this.pending_uri = "";
							AndroidAtspi.register_webview (this);
						}
					}
					return GLib.Source.CONTINUE;
				}
				int x = 0, y = 0, width = 0, height = 0;
				if (!wka_widget_bounds_xywh (this.host_area, out x, out y, out width, out height)) {
					return GLib.Source.CONTINUE;
				}
				if (x == this.last_bound_x && y == this.last_bound_y
					&& width == this.last_bound_w && height == this.last_bound_h) {
					return GLib.Source.CONTINUE;
				}
				this.last_bound_x = x;
				this.last_bound_y = y;
				this.last_bound_w = width;
				this.last_bound_h = height;
				wka_host_set_bounds_xywh (x, y, width, height);
				return GLib.Source.CONTINUE;
			});
		}

		~WebView ()
		{
			wka_host_set_document_response_handler (null, null);
			wka_host_set_freeze_frame_handler (null);
			wka_host_destroy ();
		}

		private void on_document_response (uint status, Soup.MessageHeaders headers)
		{
			main_document_response (status, headers);
		}

		[CCode (has_target = false)]
		private static void on_document_response_cb (
			void* user_data,
			int status,
			[CCode (array_length = false)] unowned string[] header_names,
			[CCode (array_length = false)] unowned string[] header_values,
			size_t header_count
		)
		{
			var headers = new Soup.MessageHeaders (Soup.MessageHeadersType.RESPONSE);
			for (var i = 0; i < (int) header_count; i++) {
				headers.append (header_names[i], header_values[i]);
			}
			((WebView) user_data).on_document_response ((uint) status, headers);
		}

		/**
		 * Recompute frozen state from {@link freeze_manual} and toplevel overlays.
		 * Auto-monitor calls this; apps set {@link freeze_manual} then call this.
		 */
		public void refresh_freeze ()
		{
			if (!this.attached) {
				return;
			}

			bool need = this.freeze_manual;
			var root = this.get_root () as Gtk.Window;
			if (root != null && !need) {
				var stack = new GenericArray<Gtk.Widget> ();
				stack.add (root);
				while (stack.length > 0) {
					var w = stack[stack.length - 1];
					stack.remove_index (stack.length - 1);
					for (var t = w.get_type (); t != Type.INVALID; t = t.parent ()) {
						if (t.name () != "AdwDialog" || w.get_parent () == null) {
							continue;
						}
						need = true;
						break;
					}
					if (need) {
						break;
					}
					for (var c = w.get_first_child (); c != null; c = c.get_next_sibling ()) {
						stack.add (c);
					}
				}
			}
			if (root != null && !need) {
				foreach (var top in Gtk.Window.list_toplevels ()) {
					if (top == root) {
						continue;
					}
					if (!top.get_mapped ()) {
						continue;
					}
					if (top.transient_for != root) {
						continue;
					}
					need = true;
					break;
				}
			}

			if (need) {
				if (this.freeze_active) {
					return;
				}
				this.freeze_active = true;
				wka_host_freeze ();
				return;
			}
			if (!this.freeze_active) {
				return;
			}
			this.freeze_active = false;
			this.freeze_picture.visible = false;
			this.freeze_picture.set_paintable (null);
			wka_host_resume ();
		}

		private static bool freeze_hook (SignalInvocationHint ihint, Value[] param_values)
		{
			var w = param_values[0].get_object () as Gtk.Widget;
			if (w == null) {
				return true;
			}
			bool adw_dialog = false;
			for (var t = w.get_type (); t != Type.INVALID; t = t.parent ()) {
				if (t.name () == "AdwDialog") {
					adw_dialog = true;
					break;
				}
			}
			if (!adw_dialog && !(w is Gtk.Window)) {
				return true;
			}
			/* unmap / unparent: widget may still look present — defer. parent-set+map: now. */
			if (ihint.signal_id == WebView.sig_unmap
				|| (ihint.signal_id == WebView.sig_parent_set && w.get_parent () == null)) {
				GLib.Idle.add (() => {
					for (var i = 0; i < WebView.freeze_watchers.length; i++) {
						WebView.freeze_watchers[i].refresh_freeze ();
					}
					return GLib.Source.REMOVE;
				});
				return true;
			}
			for (var i = 0; i < WebView.freeze_watchers.length; i++) {
				WebView.freeze_watchers[i].refresh_freeze ();
			}
			return true;
		}

		public unowned string get_uri ()
		{
			if (this.ready) {
				this.uri = wka_host_get_uri ();
			}
			return this.uri;
		}

		public unowned string get_title ()
		{
			if (this.ready) {
				this.title = wka_host_get_title ();
			}
			return this.title;
		}

		/**
		 * WebKitGTK-shaped network session (cookies + downloads).
		 */
		public NetworkSession get_network_session ()
		{
			return this.network_session;
		}

		/**
		 * Start a download of ''uri'' using the WebView cookie jar.
		 * Emits {@link NetworkSession.download_started} then {@link Download.decide_destination}.
		 */
		public Download download_uri (string uri)
		{
			var trimmed = uri.strip ();
			var id = wka_host_download_create (trimmed);
			var suggested = "download";
			try {
				var parsed = GLib.Uri.parse (trimmed, GLib.UriFlags.NONE);
				var path = parsed.get_path ();
				if (path != null && path != "" && path != "/") {
					var leaf = GLib.Path.get_basename (path);
					if (leaf != "" && leaf != "/" && leaf != ".") {
						suggested = leaf;
					}
				}
			} catch (GLib.Error e) {
			}
			var dl = new Download (this.network_session, id, trimmed, suggested, "", -1);
			this.network_session.register_download (dl, id);
			this.network_session.emit_download_started (dl);
			return dl;
		}

		public void load_uri (string uri)
		{
			this.pending_uri = uri;
			if (this.attached) {
				wka_host_navigate (uri);
				return;
			}
			int x = 0, y = 0, width = 0, height = 0;
			if (!wka_widget_bounds_xywh (this.host_area, out x, out y, out width, out height)) {
				return;
			}
			if (!wka_host_create_with_xywh (this.host_area, x, y, width, height, uri)) {
				return;
			}
			this.attached = true;
			this.pending_uri = "";
			AndroidAtspi.register_webview (this);
		}

		public void go_back ()
		{
			wka_host_go_back ();
		}

		public void go_forward ()
		{
			wka_host_go_forward ();
		}

		public void reload ()
		{
			wka_host_reload ();
		}

		/**
		 * WebKitGTK-shaped reload (Android System WebView has no bypass-cache API).
		 */
		public void reload_bypass_cache ()
		{
			wka_host_reload ();
		}

		public void stop_loading ()
		{
			wka_host_stop ();
		}

		/**
		 * WebKitGTK-shaped JS eval — not implemented on Android (settle probe
		 * catches the error; a11y dump must not use this).
		 *
		 * @param script JavaScript source
		 * @param length byte length or -1 for null-terminated
		 * @param world_name unused
		 * @param source_uri unused
		 * @param cancellable optional cancel
		 * @throws GLib.Error always (not supported)
		 */
		public async JavascriptResult evaluate_javascript (
			string script,
			ssize_t length = -1,
			string? world_name = null,
			string? source_uri = null,
			GLib.Cancellable? cancellable = null
		) throws GLib.Error
		{
			throw new NetworkError.FAILED ("evaluate_javascript not supported on Android");
		}

		public bool can_go_back ()
		{
			return wka_host_can_go_back ();
		}

		public bool can_go_forward ()
		{
			return wka_host_can_go_forward ();
		}

		protected override void size_allocate (int width, int height, int baseline)
		{
			base.size_allocate (width, height, baseline);
			if (!this.attached) {
				int x = 0, y = 0, w = 0, h = 0;
				if (!wka_widget_bounds_xywh (this.host_area, out x, out y, out w, out h)) {
					return;
				}
				var start_uri = this.pending_uri.length > 0 ? this.pending_uri : "about:blank";
				if (!wka_host_create_with_xywh (this.host_area, x, y, w, h, start_uri)) {
					return;
				}
				this.attached = true;
				this.pending_uri = "";
				AndroidAtspi.register_webview (this);
				return;
			}
			int x = 0, y = 0, w = 0, h = 0;
			if (!wka_widget_bounds_xywh (this.host_area, out x, out y, out w, out h)) {
				return;
			}
			if (x == this.last_bound_x && y == this.last_bound_y
				&& w == this.last_bound_w && h == this.last_bound_h) {
				return;
			}
			this.last_bound_x = x;
			this.last_bound_y = y;
			this.last_bound_w = w;
			this.last_bound_h = h;
			wka_host_set_bounds_xywh (x, y, w, h);
		}
	}
}
