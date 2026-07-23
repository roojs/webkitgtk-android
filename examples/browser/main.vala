/* Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * Phase 2/3 browser demo — GTK chrome + Android System WebView + a11y dump.
 * Default URL: https://roojs.com/index.php (avoids http redirect)
 *
 * A11y follows OLLMchat libocwebkit/A11y.vala:
 *   using AndroidAtspi; yield refresh_async(); get_desktop(0); …
 * Dump hidden switches a Gtk.Stack (globe-off) so WebView unmap → host hide.
 */

using Gtk;
using WebKitGtkAndroid;
using AndroidAtspi;

private WebView web;
private Gtk.Entry url_entry;
private Gtk.Stack view_stack;

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

private void a11y_collect (AndroidAtspi.Accessible acc, int parent_id, StringBuilder sb)
{
	var id = a11y_node_count;
	a11y_node_count++;
	var ext = acc.get_extents (CoordType.SCREEN);
	var name = acc.get_name () ?? "";
	var role = acc.get_role_name () ?? "";
	var value = "";
	var uri = "";
	var text = acc.get_text_iface ();
	if (text != null && text.get_character_count () > 0) {
		value = text.get_text (0, -1);
	}
	var link = acc.get_hyperlink ();
	if (link != null && link.get_n_anchors () > 0) {
		uri = link.get_uri (0);
	}
	bool can_invoke = false;
	for (var i = 0; i < acc.get_n_actions (); i++) {
		var an = acc.get_action_name (i);
		if (an == "default.activate" || an == "click") {
			can_invoke = true;
		}
	}
	bool can_set = false;
	var ifaces = acc.get_interfaces ();
	for (var i = 0; i < ifaces.length; i++) {
		if (ifaces.index (i) == "EditableText") {
			can_set = true;
			break;
		}
	}

	sb.append_printf (
		"[%d] parent=%d role=%s name=\"%s\" value=\"%s\" uri=\"%s\" "
		+ "bounds=%d,%d %dx%d invoke=%s set_value=%s\n",
		id,
		parent_id,
		role,
		name,
		value,
		uri,
		ext.x,
		ext.y,
		ext.width,
		ext.height,
		can_invoke.to_string (),
		can_set.to_string ()
	);

	var n = acc.get_child_count ();
	for (var i = 0; i < n; i++) {
		a11y_collect (acc.get_child_at_index (i), id, sb);
	}
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

/* Same handoff as OLLMchat A11y.dump on Android. */
private async string? run_a11y_dump_async (out int count) throws GLib.Error
{
	count = 0;
	a11y_node_count = 0;
	yield refresh_async ();
	var desktop = get_desktop (0);
	AndroidAtspi.Accessible? app = null;
	for (var i = 0; i < desktop.get_child_count (); i++) {
		var candidate = desktop.get_child_at_index (i);
		if (candidate.get_process_id () != (uint) Posix.getpid ()) {
			continue;
		}
		app = candidate;
		break;
	}
	if (app == null) {
		throw new GLib.IOError.FAILED ("a11y: no application for pid");
	}
	var sb = new StringBuilder ();
	a11y_collect (app, -1, sb);
	count = a11y_node_count;
	if (count <= 0) {
		print ("a11y walk failed (empty tree?)\n");
		return null;
	}
	print ("=== a11y dump ===\n%s=== end ===\n", sb.str);
	return sb.str;
}

private async void dump_a11y_async (Gtk.Window? parent)
{
	try {
		int count = 0;
		var dump = yield run_a11y_dump_async (out count);
		if (dump == null) {
			show_a11y_dialog (parent, "A11y dump", "empty tree (see logcat WebViewA11y)");
			return;
		}
		var body = "%d nodes (AndroidAtspi.refresh_async)\n\n%s".printf (
			count,
			a11y_preview (dump, 12)
		);
		show_a11y_dialog (parent, "A11y dump", body);
	} catch (GLib.Error e) {
		print ("a11y dump failed: %s\n", e.message);
		show_a11y_dialog (parent, "A11y dump", e.message);
	}
}

/* Globe-off: Stack shows chat stub → WebView unmaps → host put_is_visible(false). */
private async void dump_a11y_hidden_async (Gtk.Window? parent)
{
	print ("a11y hidden: stack → chat (unmap WebView)\n");
	view_stack.visible_child_name = "chat";
	Timeout.add (800, () => {
		dump_a11y_hidden_continue.begin (parent);
		return GLib.Source.REMOVE;
	});
}

private async void dump_a11y_hidden_continue (Gtk.Window? parent)
{
	try {
		int count = 0;
		var dump = yield run_a11y_dump_async (out count);
		view_stack.visible_child_name = "browser";
		print ("a11y hidden: stack → browser restored; nodes=%d\n", count);
		if (dump == null) {
			show_a11y_dialog (parent, "A11y dump (hidden)",
				"empty tree while hidden (see logcat WebViewA11y)");
			return;
		}
		var body = "HIDDEN dump: %d nodes\n\n%s".printf (
			count,
			a11y_preview (dump, 12)
		);
		show_a11y_dialog (parent, "A11y dump (hidden)", body);
	} catch (GLib.Error e) {
		view_stack.visible_child_name = "browser";
		print ("a11y hidden dump failed: %s\n", e.message);
		show_a11y_dialog (parent, "A11y dump (hidden)", e.message);
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
		var chrome = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
			margin_start = 4,
			margin_end = 4,
			margin_top = 4,
			margin_bottom = 4
		};
		var nav_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
		var test_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
			margin_top = 4
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
		var a11y_hid_btn = new Gtk.Button.with_label ("Dump hidden");
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

		var chat_stub = new Gtk.Label ("Chat (globe off — WebView unmapped)") {
			hexpand = true,
			vexpand = true
		};
		view_stack = new Gtk.Stack () {
			hexpand = true,
			vexpand = true,
			transition_type = Gtk.StackTransitionType.NONE
		};
		view_stack.add_named (web, "browser");
		view_stack.add_named (chat_stub, "chat");
		view_stack.visible_child_name = "browser";

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
			dump_a11y_async.begin (window);
		});
		a11y_hid_btn.clicked.connect (() => {
			dump_a11y_hidden_async.begin (window);
		});
		dl_btn.clicked.connect (() => {
			var url = url_entry.text.strip ();
			if (url == "") {
				url = web.get_uri ();
			}
			print ("download_uri %s\n", url);
			web.download_uri (url);
		});

		nav_bar.append (back_btn);
		nav_bar.append (fwd_btn);
		nav_bar.append (reload_btn);
		nav_bar.append (url_entry);
		nav_bar.append (go_btn);

		test_bar.append (a11y_btn);
		test_bar.append (a11y_hid_btn);
		test_bar.append (dl_btn);

		chrome.append (nav_bar);
		chrome.append (test_bar);
		root.append (chrome);
		root.append (view_stack);
		window.set_content (root);
		window.present ();
	}
}

int main (string[] args)
{
	var app = new BrowserApplication ();
	return app.run (args);
}
