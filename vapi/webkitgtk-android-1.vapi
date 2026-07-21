/* webkitgtk-android-1.vapi — consumer Vala API (one file, like webview2gtk-1.vapi).
 *
 * WebKitGtkAndroid.* = WebKitGTK-shaped widget API.
 * Top-level wka_host_a11y_* = host a11y (not on WebView; Windows keeps these
 * off WebView2Gtk.WebView too — see Win32Atspi / wv2_a11y_*).
 */

namespace WebKitGtkAndroid {
	[CCode (cheader_filename = "webkitgtk-android.h")]
	public enum LoadEvent {
		STARTED,
		REDIRECTED,
		COMMITTED,
		FINISHED
	}

	[CCode (cheader_filename = "webkitgtk-android.h")]
	public enum CookieAcceptPolicy {
		ALWAYS,
		NEVER,
		NO_THIRD_PARTY
	}

	[CCode (cheader_filename = "webkitgtk-android.h")]
	public enum CookiePersistentStorage {
		TEXT,
		SQLITE
	}

	[CCode (cheader_filename = "webkitgtk-android.h")]
	public errordomain NetworkError {
		FAILED,
		TRANSPORT,
		UNKNOWN_PROTOCOL,
		CANCELLED,
		FILE_DOES_NOT_EXIST
	}

	[CCode (cheader_filename = "webkitgtk-android.h")]
	public class URIRequest : GLib.Object {
		public string uri { get; construct; }
		public URIRequest (string uri);
	}

	[CCode (cheader_filename = "webkitgtk-android.h")]
	public class CookieManager : GLib.Object {
		public CookieManager ();
		public void set_accept_policy (CookieAcceptPolicy policy);
		public void set_persistent_storage (string filename, CookiePersistentStorage storage);
		public async GLib.List<Soup.Cookie> get_cookies (
			string uri,
			GLib.Cancellable? cancellable = null
		) throws GLib.Error;
		public async bool add_cookie (
			Soup.Cookie cookie,
			GLib.Cancellable? cancellable = null
		) throws GLib.Error;
	}

	[CCode (cheader_filename = "webkitgtk-android.h")]
	public class Download : GLib.Object {
		public URIRequest get_request ();
		public string get_uri ();
		public string? get_mime_type ();
		public int64 get_estimated_content_length ();
		public uint64 get_received_data_length ();
		public signal bool decide_destination (string? suggested_filename);
		public signal void received_data (uint64 data_length);
		public signal void finished ();
		public signal void failed (GLib.Error error);
		public void set_allow_overwrite (bool allow);
		public void set_destination (string destination_uri_or_path);
		public void cancel ();
	}

	[CCode (cheader_filename = "webkitgtk-android.h")]
	public class NetworkSession : GLib.Object {
		public NetworkSession ();
		public signal void download_started (Download download);
		public CookieManager get_cookie_manager ();
	}

	[CCode (cheader_filename = "webkitgtk-android.h")]
	public class WebView : Gtk.Box {
		public bool freeze_active;
		public bool freeze_manual;
		public Gtk.Picture freeze_picture;
		public WebView ();
		public signal void load_changed (LoadEvent load_event);
		public bool ready { get; }
		public bool loading { get; }
		public unowned string get_uri ();
		public unowned string get_title ();
		public NetworkSession get_network_session ();
		public Download download_uri (string uri);
		public void load_uri (string uri);
		public void go_back ();
		public void go_forward ();
		public void reload ();
		public void stop_loading ();
		public bool can_go_back ();
		public bool can_go_forward ();
		public void refresh_freeze ();
		protected override void size_allocate (int width, int height, int baseline);
	}
}

/* Host a11y — not methods on WebView (webview2-gtk split). */
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
public bool wka_host_a11y_ensure ();

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
public bool wka_host_a11y_walk_foreach (WkaA11yForeachCb cb, void* user_data);

[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
public bool wka_host_a11y_invoke (int id);

[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
public bool wka_host_a11y_set_value (int id, string utf8);

[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
public bool wka_host_a11y_focus (int id);
