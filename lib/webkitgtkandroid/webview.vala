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
 * Phase 2: navigation + load_changed. Accessibility is Phase 3.
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
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern bool wka_widget_bounds_xywh (
	Gtk.Widget widget,
	out int x,
	out int y,
	out int width,
	out int height
);

namespace WebKitGtkAndroid
{
	/**
	 * Load lifecycle events — same names and order as WebKit.LoadEvent.
	 */
	public enum LoadEvent
	{
		STARTED,
		REDIRECTED,
		COMMITTED,
		FINISHED
	}

	/**
	 * Embeds Android System WebView over the GTK Android surface.
	 *
	 * Limitation (v0.1): one WebView host per process.
	 */
	public class WebView : Gtk.Box
	{
		private Gtk.Widget host_area;
		private bool attached = false;
		private string pending_uri = "";
		private string uri = "about:blank";
		private string title = "";
		private bool is_loading = false;
		private int last_bound_x = int.MIN;
		private int last_bound_y = int.MIN;
		private int last_bound_w = int.MIN;
		private int last_bound_h = int.MIN;

		public bool ready {
			get {
				return this.attached && wka_host_is_ready ();
			}
		}

		public bool loading {
			get {
				return this.is_loading;
			}
		}

		public signal void load_changed (LoadEvent load_event);

		public WebView ()
		{
			Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
			this.host_area = new Gtk.DrawingArea ();
			this.host_area.set_hexpand (true);
			this.host_area.set_vexpand (true);
			this.append (this.host_area);

			wka_host_set_event_handlers (
				WebView.native_load_changed,
				WebView.native_title_changed,
				this
			);

			this.host_area.map.connect (() => {
				this.try_attach ();
			});
			this.host_area.add_tick_callback (() => {
				if (!this.attached) {
					this.try_attach ();
				} else {
					this.push_bounds ();
				}
				return GLib.Source.CONTINUE;
			});
		}

		~WebView ()
		{
			wka_host_destroy ();
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

		public void load_uri (string uri)
		{
			this.pending_uri = uri;
			if (!this.attached) {
				this.try_attach ();
				return;
			}
			wka_host_navigate (uri);
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

		public void stop_loading ()
		{
			wka_host_stop ();
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
				this.try_attach ();
				return;
			}
			this.push_bounds ();
		}

		private static void native_load_changed (void* user_data, int load_event)
		{
			var self = (WebView) user_data;
			self.on_native_load_changed (load_event);
		}

		private static void native_title_changed (void* user_data)
		{
			var self = (WebView) user_data;
			self.on_native_title_changed ();
		}

		private void try_attach ()
		{
			int x = 0;
			int y = 0;
			int width = 0;
			int height = 0;
			var start_uri = this.pending_uri.length > 0 ? this.pending_uri : "about:blank";

			if (this.attached) {
				return;
			}
			/* Wait for a real allocation so the overlay matches the host area.
			 * Tick callback retries until the Activity + widget are ready. */
			if (!wka_widget_bounds_xywh (this.host_area, out x, out y, out width, out height)) {
				return;
			}
			if (!wka_host_create_with_xywh (this.host_area, x, y, width, height, start_uri)) {
				return;
			}
			this.attached = true;
			this.pending_uri = "";
		}

		private void push_bounds ()
		{
			int x = 0;
			int y = 0;
			int width = 0;
			int height = 0;

			if (!wka_widget_bounds_xywh (this.host_area, out x, out y, out width, out height)) {
				return;
			}
			if (x == this.last_bound_x && y == this.last_bound_y
				&& width == this.last_bound_w && height == this.last_bound_h) {
				return;
			}
			this.last_bound_x = x;
			this.last_bound_y = y;
			this.last_bound_w = width;
			this.last_bound_h = height;
			wka_host_set_bounds_xywh (x, y, width, height);
		}

		private void on_native_load_changed (int load_event)
		{
			switch (load_event) {
			case (int) LoadEvent.STARTED:
				this.is_loading = true;
				this.load_changed (LoadEvent.STARTED);
				break;
			case (int) LoadEvent.REDIRECTED:
				this.load_changed (LoadEvent.REDIRECTED);
				break;
			case (int) LoadEvent.COMMITTED:
				this.uri = wka_host_get_uri ();
				this.load_changed (LoadEvent.COMMITTED);
				break;
			case (int) LoadEvent.FINISHED:
				this.is_loading = false;
				this.uri = wka_host_get_uri ();
				this.title = wka_host_get_title ();
				this.load_changed (LoadEvent.FINISHED);
				break;
			}
		}

		private void on_native_title_changed ()
		{
			this.title = wka_host_get_title ();
		}
	}
}
