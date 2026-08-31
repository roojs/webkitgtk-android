/* Automation setup smoke — WebKitGTK-shaped APIs on webkitgtk-android (plan 1.4 Phase 1).
 *
 * Setup only: no WebDriver, no click/type.
 *
 * Android host is one System WebView per process — smoke uses a single controlled
 * WebView (Windows twin can host two). Verifies automation_started + a11y dump.
 *
 * Build with -Dandroid_automation=true (and optionally -Dandroid_automation_smoke=true
 * for auto-quit without argv — Android GTK only gets argv[0]).
 */

using Gtk;
using WebKitGtkAndroid;
using AndroidAtspi;

private int smoke_status = 1;
private bool smoke_mode = false;
private bool automation_started_seen = false;
private string automation_session_id;
private class WebViewAuto : WebView
{
	public WebViewAuto (WebContext context, NetworkSession session)
	{
		Object (
			orientation: Gtk.Orientation.VERTICAL,
			spacing: 0,
			web_context: context,
			is_controlled_by_automation: true,
			network_session: session
		);
		get_settings ().enable_developer_extras = true;
	}
}

private async int a11y_dump_count_async () throws GLib.Error
{
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
	return count_accessible (app);
}

private int count_accessible (AndroidAtspi.Accessible acc)
{
	var n = 1;
	var children = acc.get_child_count ();
	for (var i = 0; i < children; i++) {
		n += count_accessible (acc.get_child_at_index (i));
	}
	return n;
}

private void finish_quit (Adw.ApplicationWindow window, Adw.Application app)
{
	Timeout.add (400, () => {
		window.close ();
		Idle.add (() => {
			app.quit ();
			return false;
		});
		return Source.REMOVE;
	});
}

public class AutomationApplication : Adw.Application
{
	private bool smoke;

	public AutomationApplication (bool smoke = false)
	{
		Object (
			application_id: "org.roojs.webkitgtk.androidautomation",
			flags: GLib.ApplicationFlags.DEFAULT_FLAGS
		);
		this.smoke = smoke;
		this.activate.connect (() => {
			this.open_window ();
		});
	}

	private void open_window ()
	{
		var window = new Adw.ApplicationWindow (this) {
			title = "webkitgtk-android automation"
		};
		window.set_default_size (420, 720);

		var context = WebContext.get_default ();
		context.set_automation_allowed (true);

		var ns = context.get_network_session_for_automation ();
		if (ns == null) {
			print ("AUTOMATION_SMOKE_FAIL: get_network_session_for_automation null\n");
			smoke_status = 1;
			this.quit ();
			return;
		}

		WebView view = new WebViewAuto (context, ns);
		view.set_hexpand (true);
		view.set_vexpand (true);

		context.automation_started.connect ((session) => {
			var info = new ApplicationInfo ();
			info.set_name ("WebKitGtkAndroidAutomation");
			info.set_version (0, 1, 0);
			session.set_application_info (info);
			session.create_web_view.connect (() => {
				return view;
			});
			automation_started_seen = true;
			automation_session_id = session.id;
			print ("automation-started session=%s app=%s\n",
				session.id, session.get_application_info ().get_name ());
		});

		var start = (
			"data:text/html;charset=utf-8,"
			+ Uri.escape_string (
				"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>automation smoke</title></head>
<body style="margin:24px;font-family:sans-serif">
<h1>Automation setup</h1>
<p>Primary controlled WebView</p>
<input id="q" type="text" style="width:90%;height:48px;font-size:18px">
</body></html>""",
				null
			)
		);
		view.load_uri (start);
		window.set_content (view);
		window.present ();

		if (this.smoke) {
			run_smoke.begin (window, view);
		}
	}

	private async void run_smoke (Adw.ApplicationWindow window, WebView view)
	{
		var tries = 0;
		while (!view.ready && tries < 40) {
			tries++;
			Timeout.add (250, () => {
				run_smoke.callback ();
				return false;
			});
			yield;
		}
		if (!view.ready) {
			print ("AUTOMATION_SMOKE_FAIL: view not ready tries=%d\n", tries);
			smoke_status = 1;
			finish_quit (window, this);
			return;
		}

		/* Wait for load + deferred automation_started Idle. */
		tries = 0;
		while ((!automation_started_seen || view.is_loading) && tries < 40) {
			tries++;
			Timeout.add (250, () => {
				run_smoke.callback ();
				return false;
			});
			yield;
		}
		if (!automation_started_seen) {
			print ("AUTOMATION_SMOKE_FAIL: automation_started not emitted\n");
			smoke_status = 1;
			finish_quit (window, this);
			return;
		}

		Timeout.add (800, () => {
			run_smoke.callback ();
			return false;
		});
		yield;

		try {
			var count = yield a11y_dump_count_async ();
			print ("a11y_nodes=%d session=%s controlled=%s\n",
				count,
				automation_session_id,
				view.is_controlled_by_automation.to_string ());
			if (count <= 0) {
				print ("AUTOMATION_SMOKE_FAIL: empty a11y tree\n");
				smoke_status = 1;
			} else {
				print ("AUTOMATION_SMOKE_PASS\n");
				smoke_status = 0;
			}
		} catch (GLib.Error e) {
			print ("AUTOMATION_SMOKE_FAIL: a11y %s\n", e.message);
			smoke_status = 1;
		}
		finish_quit (window, this);
	}
}

int main (string[] args)
{
	automation_session_id = "";
#if ANDROID_AUTOMATION_SMOKE
	smoke_mode = true;
#else
	smoke_mode = "--smoke" in args;
#endif
	var gtk_args = new string[] { args[0] };
	foreach (var arg in args[1:]) {
		if (arg != "--smoke") {
			gtk_args += arg;
		}
	}

	/* Same prepare order as OLLMchat / webview2-gtk — env before first WebView. */
	try {
		var probe = new GLib.Socket (
			GLib.SocketFamily.IPV4,
			GLib.SocketType.STREAM,
			GLib.SocketProtocol.TCP
		);
		probe.bind (
			new GLib.InetSocketAddress (
				new GLib.InetAddress.loopback (GLib.SocketFamily.IPV4),
				0
			),
			true
		);
		var port = (uint16) ((GLib.InetSocketAddress) probe.get_local_address ()).get_port ();
		probe.close ();
		Environment.set_variable ("WEBKIT_INSPECTOR_SERVER", "127.0.0.1:%u".printf (port), true);
		print ("inspector WEBKIT_INSPECTOR_SERVER=127.0.0.1:%u\n", port);
	} catch (GLib.Error e) {
		print ("AUTOMATION_SMOKE_FAIL: prepare %s\n", e.message);
		return 1;
	}

	var app = new AutomationApplication (smoke_mode);
	var status = app.run (gtk_args);
	if (status != 0) {
		return status;
	}
	if (smoke_mode) {
		return smoke_status;
	}
	return 0;
}
