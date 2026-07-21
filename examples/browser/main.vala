/* Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Phase 2 browser demo — GTK chrome + Android System WebView.
 * Default URL: https://roojs.com/index.php (avoids http redirect)
 */

using Gtk;
using WebKitGtkAndroid;

private WebView web;
private Gtk.Entry url_entry;

private void sync_url_entry ()
{
	if (web.ready) {
		var u = web.get_uri ();
		if (u.length > 0) {
			url_entry.text = u;
		}
	}
}

public class BrowserApplication : Adw.Application
{
	public BrowserApplication ()
	{
		Object (
			application_id: "org.roojs.webkitgtk.androidbrowser",
			flags: GLib.ApplicationFlags.DEFAULT_FLAGS
		);
		this.activate.connect (() => {
			this.open_window ();
		});
	}

	private void open_window ()
	{
		var start = "https://roojs.com/index.php";
		var window = new Adw.ApplicationWindow (this) {
			title = "webkitgtk-android browser"
		};
		window.set_default_size (420, 720);

		var root = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
		var bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
			margin_start = 4,
			margin_end = 4,
			margin_top = 4,
			margin_bottom = 4
		};

		var back_btn = new Gtk.Button.from_icon_name ("go-previous-symbolic");
		var fwd_btn = new Gtk.Button.from_icon_name ("go-next-symbolic");
		var reload_btn = new Gtk.Button.from_icon_name ("view-refresh-symbolic");
		url_entry = new Gtk.Entry () {
			text = start,
			hexpand = true
		};
		var go_btn = new Gtk.Button.with_label ("Go");

		web = new WebView ();
		web.set_hexpand (true);
		web.set_vexpand (true);
		/* Prefer a solid placeholder so the GTK chrome/layout is obvious
		 * around the native WebView overlay. */
		web.add_css_class ("view");
		web.load_uri (start);
		web.load_changed.connect ((ev) => {
			if (ev == LoadEvent.COMMITTED || ev == LoadEvent.FINISHED) {
				sync_url_entry ();
			}
		});

		back_btn.clicked.connect (() => {
			web.go_back ();
			sync_url_entry ();
		});
		fwd_btn.clicked.connect (() => {
			web.go_forward ();
			sync_url_entry ();
		});
		reload_btn.clicked.connect (() => {
			web.reload ();
		});
		go_btn.clicked.connect (() => {
			web.load_uri (url_entry.text);
		});
		url_entry.activate.connect (() => {
			web.load_uri (url_entry.text);
		});

		bar.append (back_btn);
		bar.append (fwd_btn);
		bar.append (reload_btn);
		bar.append (url_entry);
		bar.append (go_btn);

		root.append (bar);
		root.append (web);
		window.set_content (root);
		window.present ();
	}
}

int main (string[] args)
{
	var app = new BrowserApplication ();
	return app.run (args);
}
