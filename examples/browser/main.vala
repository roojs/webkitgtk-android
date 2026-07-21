/* Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Phase 2/3 browser demo — GTK chrome + Android System WebView + a11y dump.
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

private int a11y_node_count;

private void a11y_dump_line (
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
)
{
	unowned StringBuilder sb = (StringBuilder) user_data;
	a11y_node_count++;
	sb.append_printf (
		"[%d] parent=%d role=%s name=\"%s\" value=\"%s\" uri=\"%s\" "
		+ "bounds=%d,%d %dx%d invoke=%s set_value=%s\n",
		id,
		parent_id,
		role,
		name,
		value,
		uri,
		x,
		y,
		w,
		h,
		can_invoke.to_string (),
		can_set_value.to_string ()
	);
}

private string a11y_preview (string full, int max_lines)
{
	var out = new StringBuilder ();
	int lines = 0;
	foreach (unowned string line in full.split ("\n")) {
		if (line.length == 0) {
			continue;
		}
		if (lines >= max_lines) {
			out.append ("…\n");
			break;
		}
		out.append (line);
		out.append_c ('\n');
		lines++;
	}
	return out.str;
}

private void show_a11y_dialog (Gtk.Window? parent, string title, string body)
{
	/* WebView auto-freezes when this dialog maps on the same toplevel. */
	var dialog = new Adw.AlertDialog (title, body);
	dialog.add_response ("ok", "OK");
	dialog.present (parent);
}

private void dump_a11y (Gtk.Window? parent)
{
	var sb = new StringBuilder ();
	a11y_node_count = 0;
	if (!wka_host_a11y_ensure ()) {
		print ("a11y ensure failed\n");
		show_a11y_dialog (parent, "A11y dump", "ensure failed (see logcat WebViewA11y)");
		return;
	}
	if (!wka_host_a11y_walk_foreach (a11y_dump_line, sb)) {
		print ("a11y walk failed (empty tree?)\n");
		show_a11y_dialog (parent, "A11y dump", "walk failed — empty tree?");
		return;
	}
	print ("=== a11y dump ===\n%s=== end ===\n", sb.str);
	var body = "%d nodes (also in logcat: print / WebViewA11y)\n\n%s".printf (
		a11y_node_count,
		a11y_preview (sb.str, 12)
	);
	show_a11y_dialog (parent, "A11y dump", body);
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
		var a11y_btn = new Gtk.Button.with_label ("Dump a11y");
		var dl_btn = new Gtk.Button.with_label ("Download");

		web = new WebView ();
		web.set_hexpand (true);
		web.set_vexpand (true);
		web.add_css_class ("view");
		web.load_uri (start);
		web.load_changed.connect ((ev) => {
			if (ev == LoadEvent.COMMITTED || ev == LoadEvent.FINISHED) {
				sync_url_entry ();
			}
		});
		web.get_network_session ().download_started.connect ((download) => {
			download.decide_destination.connect ((suggested) => {
				var name = suggested != null && suggested != "" ? suggested : "download";
				var dir = GLib.Environment.get_user_special_dir (GLib.UserDirectory.DOWNLOAD);
				if (dir == null || dir == "") {
					dir = GLib.Environment.get_tmp_dir ();
				}
				var dest = GLib.Path.build_filename (dir, name);
				print ("download decide → %s\n", dest);
				download.set_allow_overwrite (true);
				download.set_destination (dest);
				return true;
			});
			download.received_data.connect (() => {
				print ("download progress %s bytes=%llu\n",
					download.get_uri (),
					download.get_received_data_length ());
			});
			download.finished.connect (() => {
				print ("download finished %s\n", download.get_uri ());
				show_a11y_dialog (window, "Download", "Finished:\n" + download.get_uri ());
			});
			download.failed.connect ((err) => {
				print ("download failed: %s\n", err.message);
				show_a11y_dialog (window, "Download failed", err.message);
			});
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
		a11y_btn.clicked.connect (() => {
			dump_a11y (window);
		});
		dl_btn.clicked.connect (() => {
			var url = url_entry.text.strip ();
			if (url == "") {
				url = web.get_uri ();
			}
			print ("download_uri %s\n", url);
			web.download_uri (url);
		});

		bar.append (back_btn);
		bar.append (fwd_btn);
		bar.append (reload_btn);
		bar.append (url_entry);
		bar.append (go_btn);
		bar.append (a11y_btn);
		bar.append (dl_btn);

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
