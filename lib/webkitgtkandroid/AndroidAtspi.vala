/* Android AT-SPI-shaped facade over WebView host a11y (parallel to Win32Atspi).
 * Host a11y C bindings live in WebView.vala (same library compile unit).
 *
 * From GLib/GTK: call refresh_async() before get_desktop() — sync ensure_tree /
 * walk on the GTK thread ANRs with IME blockForMain (docs/a11y.md). */

namespace AndroidAtspi
{
	public enum CoordType
	{
		SCREEN,
		WINDOW,
		PARENT
	}

	public enum ScrollType
	{
		TOP_EDGE,
		BOTTOM_EDGE,
		LEFT_EDGE,
		RIGHT_EDGE,
		ANYWHERE
	}

	public enum KeySynthType
	{
		PRESS,
		RELEASE,
		PRESSRELEASE,
		STRING
	}

	public class ComponentExtents : GLib.Object
	{
		public int x { get; set; }
		public int y { get; set; }
		public int width { get; set; }
		public int height { get; set; }
	}

	public class Text : GLib.Object
	{
		private string _text = "";

		public Text (string text)
		{
			this._text = text ?? "";
		}

		public int get_character_count ()
		{
			return (int) this._text.char_count ();
		}

		public string get_text (int start_offset, int end_offset)
		{
			return this._text;
		}
	}

	public class Hyperlink : GLib.Object
	{
		private string _uri = "";

		public Hyperlink (string uri)
		{
			this._uri = uri ?? "";
		}

		public int get_n_anchors ()
		{
			return this._uri != "" ? 1 : 0;
		}

		public string get_uri (int i)
		{
			return i == 0 ? this._uri : "";
		}
	}

	/**
	 * One node in the emulated AT-SPI tree (backed by host walk ids).
	 */
	public class Accessible : GLib.Object
	{
		internal string _name = "";
		internal string _role_name = "";
		internal string _description = "";
		internal uint _process_id = 0;
		internal int walk_id = -1;
		internal int x = 0;
		internal int y = 0;
		internal int w = 0;
		internal int h = 0;
		internal string value_text = "";
		internal string uri = "";
		internal bool can_invoke = false;
		internal bool can_set_value = false;

		private GLib.GenericArray<Accessible> children = new GLib.GenericArray<Accessible> ();
		private GLib.GenericArray<string> action_names = new GLib.GenericArray<string> ();
		private GLib.HashTable<string, string> attrs =
			new GLib.HashTable<string, string> (GLib.str_hash, GLib.str_equal);
		private GLib.GenericArray<string> ifaces = new GLib.GenericArray<string> ();

		internal void add_child (Accessible child)
		{
			this.children.add (child);
		}

		internal void add_action (string action_name)
		{
			this.action_names.add (action_name);
		}

		internal void set_attr (string key, string val)
		{
			this.attrs.set (key, val);
		}

		internal void add_iface (string name)
		{
			for (var i = 0; i < this.ifaces.length; i++) {
				if (this.ifaces.get (i) == name) {
					return;
				}
			}
			this.ifaces.add (name);
		}

		public string get_name ()
		{
			return this._name;
		}

		public string get_role_name ()
		{
			return this._role_name;
		}

		public string get_description ()
		{
			return this._description;
		}

		public uint get_process_id ()
		{
			return this._process_id;
		}

		public int get_child_count ()
		{
			return (int) this.children.length;
		}

		public Accessible get_child_at_index (int index)
		{
			return this.children.get (index);
		}

		public GLib.HashTable<string, string> get_attributes ()
		{
			var ht = new GLib.HashTable<string, string> (GLib.str_hash, GLib.str_equal);
			this.attrs.foreach ((k, v) => {
				ht.insert (k, v);
			});
			return ht;
		}

		public GLib.Array<string> get_interfaces ()
		{
			var a = new GLib.Array<string> ();
			for (var i = 0; i < this.ifaces.length; i++) {
				a.append_val (this.ifaces.get (i));
			}
			return a;
		}

		public int get_n_actions ()
		{
			return (int) this.action_names.length;
		}

		public string get_action_name (int index)
		{
			return this.action_names.get (index);
		}

		public bool do_action (int index)
		{
			if (index < 0 || index >= (int) this.action_names.length) {
				return false;
			}
			if (Bridge.host == null) {
				return this.action_names.get (index) == "default.activate";
			}
			if (this.walk_id < 0) {
				return true;
			}
			if (this.can_set_value && !this.can_invoke) {
				return wka_host_a11y_focus (this.walk_id);
			}
			if (this.can_invoke) {
				return wka_host_a11y_invoke (this.walk_id);
			}
			return wka_host_a11y_focus (this.walk_id);
		}

		public bool grab_focus ()
		{
			if (this.walk_id < 0) {
				return false;
			}
			return wka_host_a11y_focus (this.walk_id);
		}

		public bool set_text_contents (string text)
		{
			if (this.walk_id < 0 || !this.can_set_value) {
				return false;
			}
			var ok = wka_host_a11y_set_value (this.walk_id, text);
			if (ok) {
				this.value_text = text;
			}
			return ok;
		}

		public ComponentExtents get_extents (CoordType coord_type)
		{
			var e = new ComponentExtents ();
			e.x = this.x;
			e.y = this.y;
			e.width = this.w;
			e.height = this.h;
			return e;
		}

		public void scroll_to (ScrollType type) throws GLib.Error
		{
			/* Host walk already includes below-fold names; no-op. */
		}

		public Text get_text_iface ()
		{
			var t = this.value_text != "" ? this.value_text : this._name;
			return new Text (t);
		}

		public Hyperlink? get_hyperlink ()
		{
			if (this.uri == "") {
				return null;
			}
			return new Hyperlink (this.uri);
		}
	}

	internal class Bridge : GLib.Object
	{
		public static WebKitGtkAndroid.WebView? host;
		public static Accessible? desktop;
		public static bool ready;

		private class WalkRow
		{
			public int id;
			public int parent_id;
			public int x;
			public int y;
			public int w;
			public int h;
			public string name = "";
			public string role = "";
			public string value = "";
			public string uri = "";
			public bool can_invoke;
			public bool can_set_value;
		}

		private static GLib.GenericArray<WalkRow>? walk_accum;
		private static GLib.SourceFunc? async_resume;
		private static bool async_ok;

		private static void walk_cb (
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
			if (walk_accum == null) {
				return;
			}
			var row = new WalkRow ();
			row.id = id;
			row.parent_id = parent_id;
			row.x = x;
			row.y = y;
			row.w = w;
			row.h = h;
			row.name = name;
			row.role = role;
			row.value = value;
			row.uri = uri;
			row.can_invoke = can_invoke;
			row.can_set_value = can_set_value;
			walk_accum.add (row);
		}

		private static void ensure_tree_async_done (bool ok, void* user_data)
		{
			async_ok = ok;
			var tree = walk_accum;
			walk_accum = null;
			if (tree == null) {
				tree = new GLib.GenericArray<WalkRow> ();
			}
			Bridge.apply_tree (tree);
			var resume = (owned) async_resume;
			async_resume = null;
			if (resume != null) {
				resume ();
			}
		}

		public static void register (WebKitGtkAndroid.WebView web)
		{
			Bridge.host = web;
			Bridge.desktop = null;
		}

		public static void ensure_tree () throws GLib.Error
		{
			if (Bridge.host == null || !Bridge.host.ready) {
				throw new GLib.IOError.FAILED ("AndroidAtspi: no WebView registered (host not ready)");
			}
			/* Sync path — Android UI only; from GTK use ensure_tree_async. */
			wka_host_a11y_ensure ();
			Bridge.rebuild ();
		}

		public static async void ensure_tree_async () throws GLib.Error
		{
			if (Bridge.host == null || !Bridge.host.ready) {
				throw new GLib.IOError.FAILED ("AndroidAtspi: no WebView registered (host not ready)");
			}
			if (async_resume != null) {
				throw new GLib.IOError.FAILED ("AndroidAtspi: refresh already in progress");
			}
			async_resume = ensure_tree_async.callback;
			async_ok = false;
			walk_accum = new GLib.GenericArray<WalkRow> ();
			wka_host_a11y_walk_foreach_async (walk_cb, ensure_tree_async_done, null);
			yield;
			if (!async_ok) {
				throw new GLib.IOError.FAILED ("AndroidAtspi: async walk failed");
			}
		}

		public static void rebuild ()
		{
			walk_accum = new GLib.GenericArray<WalkRow> ();
			var ok = wka_host_a11y_walk_foreach (walk_cb, null);
			var tree = walk_accum;
			walk_accum = null;
			if (!ok || tree == null) {
				tree = new GLib.GenericArray<WalkRow> ();
			}
			Bridge.apply_tree (tree);
		}

		private static void apply_tree (GLib.GenericArray<WalkRow> tree)
		{
			var pid = (uint) Posix.getpid ();

			var desktop = new Accessible ();
			desktop._name = "Desktop";
			desktop._role_name = "desktop frame";
			desktop._process_id = 0;

			var app = new Accessible ();
			app._name = "Application";
			app._role_name = "application";
			app._process_id = pid;
			desktop.add_child (app);

			var frame = new Accessible ();
			frame._name = "Frame";
			frame._role_name = "frame";
			frame._process_id = pid;
			frame.add_action ("default.activate");
			app.add_child (frame);

			var by_id = new GLib.HashTable<int, Accessible> (GLib.direct_hash, GLib.direct_equal);
			Accessible? doc = null;

			for (var i = 0; i < tree.length; i++) {
				var n = tree.get (i);
				var acc = accessible_from_tree_node (n, pid);
				by_id.set (n.id, acc);
				if (n.role == "Document") {
					doc = acc;
				} else if (doc == null && n.parent_id < 0) {
					doc = acc;
				}
			}

			for (var i = 0; i < tree.length; i++) {
				var n = tree.get (i);
				if (!by_id.contains (n.id)) {
					continue;
				}
				var acc = by_id.get (n.id);
				if (n.parent_id < 0) {
					continue;
				}
				if (by_id.contains (n.parent_id)) {
					by_id.get (n.parent_id).add_child (acc);
				}
			}

			if (doc == null && tree.length > 0 && by_id.contains (tree.get (0).id)) {
				doc = by_id.get (tree.get (0).id);
			}
			if (doc != null) {
				if (doc._role_name != "document text" && doc._role_name != "document frame") {
					doc._role_name = "document frame";
				}
				frame.add_child (doc);
			}

			Bridge.desktop = desktop;
		}

		private static Accessible accessible_from_tree_node (WalkRow n, uint pid)
		{
			var role = atspi_role (n.role);
			var acc = new Accessible ();
			acc._name = n.name;
			acc._role_name = role;
			acc._process_id = pid;
			acc.walk_id = n.id;
			acc.x = n.x;
			acc.y = n.y;
			acc.w = n.w;
			acc.h = n.h;
			acc.value_text = n.value;
			acc.uri = n.uri != "" ? n.uri : (n.value.has_prefix ("http") ? n.value : "");
			acc.can_invoke = n.can_invoke;
			acc.can_set_value = n.can_set_value;
			if (n.can_invoke || n.can_set_value) {
				acc.add_action ("click");
				acc.add_iface ("Action");
			}
			if (n.can_set_value || n.value != "" || role == "entry" || role == "combo box"
					|| role == "password text") {
				acc.add_iface ("Text");
			}
			if (acc.uri != "" || role == "link") {
				acc.add_iface ("Hyperlink");
				if (acc.uri != "") {
					acc.set_attr ("computed-role", "link");
				}
			}
			switch (n.role) {
			case "Hyperlink":
				acc.set_attr ("computed-role", "link");
				break;
			case "Button":
				acc.set_attr ("computed-role", "button");
				break;
			case "ComboBox":
				acc.set_attr ("computed-role", "combobox");
				break;
			case "Edit":
				acc.set_attr ("computed-role", "textbox");
				break;
			case "Text":
				acc.set_attr ("computed-role", "text");
				break;
			}
			return acc;
		}

		private static string atspi_role (string uia)
		{
			switch (uia) {
			case "Document":
				return "document frame";
			case "Hyperlink":
				return "link";
			case "Button":
				return "push button";
			case "ComboBox":
				return "combo box";
			case "Edit":
				return "entry";
			case "Text":
				return "text";
			case "Group":
				return "panel";
			case "List":
				return "list";
			case "ListItem":
				return "list item";
			case "Image":
				return "image";
			case "TabItem":
				return "page tab";
			default:
				return uia.down ();
			}
		}
	}

	public void init ()
	{
		Bridge.ready = true;
		Bridge.desktop = null;
	}

	/**
	 * Return the last refreshed AT-SPI-shaped tree.
	 *
	 * Prefer {@link refresh_async} first when calling from GLib/GTK. A sync
	 * rebuild here is Android-UI only and refuses off-UI (empty / shell).
	 */
	public Accessible get_desktop (int index)
	{
		if (Bridge.desktop == null) {
			try {
				Bridge.ensure_tree ();
			} catch (GLib.Error e) {
				Bridge.desktop = new Accessible ();
				Bridge.desktop._name = "Desktop";
				Bridge.desktop._role_name = "desktop frame";
			}
		}
		return Bridge.desktop;
	}

	/**
	 * Refresh the host a11y tree on the Android UI thread (async).
	 * Call this from GLib/GTK before {@link get_desktop} / dump / fill / press.
	 */
	public async void refresh_async () throws GLib.Error
	{
		yield Bridge.ensure_tree_async ();
	}

	/**
	 * Register the WebView that backs this process's AT-SPI tree.
	 */
	public void register_webview (WebKitGtkAndroid.WebView web)
	{
		Bridge.register (web);
	}

	/**
	 * Keyboard synth — not wired on Android yet (fill prefers set_text_contents).
	 */
	public void generate_keyboard_event (long keyval, string? keystring, KeySynthType synth)
	{
	}
}
