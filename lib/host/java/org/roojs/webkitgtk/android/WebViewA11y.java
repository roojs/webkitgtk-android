package org.roojs.webkitgtk.android;

import android.content.Context;
import android.graphics.Rect;
import android.os.Build;
import android.os.Bundle;
import android.os.Looper;
import android.util.Log;
import android.util.SparseArray;
import android.view.View;
import android.view.accessibility.AccessibilityManager;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityNodeProvider;
import android.webkit.WebView;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Structured AccessibilityNodeInfo walk — field-compatible with
 * webview2gtk_a11y_node / wka_a11y_node.
 *
 * Ids are dense walk indices, valid until the next walk().
 *
 * Force-on (no TalkBack / no AccessibilityService): API 34+
 * {@link AccessibilityNodeInfo#setQueryFromAppProcessEnabled} installs a
 * ViewRootImpl DirectConnection so {@link AccessibilityManager#isEnabled()}
 * is true in-process. Chromium still gates on its state listener — we notify
 * those listeners after the DirectConnection is up.
 *
 * Threading: ensure/walk/provider APIs must run on the Android UI thread.
 * Sync {@link #walk()} from the GTK thread deadlocks with
 * {@code GlibContext.blockForMain} (IME). GLib callers use
 * {@link #walkAsync(long)} → nativeWalkDone → GLib idle (see docs/a11y.md).
 */
public final class WebViewA11y {
	private static final String TAG = "WebViewA11y";
	private static final int MAX_DEPTH = 20;
	private static final int MAX_NODES = 400;

	public static final class Node {
		public int id;
		public int parentId;
		public int x;
		public int y;
		public int w;
		public int h;
		public String name = "";
		public String role = "";
		public String value = "";
		public String uri = "";
		public boolean canInvoke;
		public boolean canSetValue;
		/** HTML form name= (from ViewStructure HtmlInfo). */
		public String htmlName = "";
		/** HTML id= (ViewStructure HtmlInfo or viewIdResourceName). */
		public String htmlId = "";
		/** HTML tag (from ViewStructure HtmlInfo). */
		public String htmlTag = "";
	}

	private static final class HtmlAttrs {
		String name = "";
		String id = "";
		String tag = "";
		int left;
		int top;
		int width;
		int height;
	}

	private static final List<AccessibilityNodeInfo> cache = new ArrayList<>();
	private static final List<Node> lastWalk = new ArrayList<>();
	private static boolean forceOnDone;
	/** Autofill virtual id → HTML attrs from last ViewStructure capture. */
	private static final SparseArray<HtmlAttrs> htmlByVirtualId = new SparseArray<>();
	private static final Map<String, HtmlAttrs> htmlById = new HashMap<>();
	private static final List<HtmlAttrs> htmlAll = new ArrayList<>();
	/** Temp verify (1.3): auto-load name/id fixture once. */
	private static final boolean SPIKE_FIXTURE = false;
	private static boolean spikeFixtureScheduled;

	private WebViewA11y() {
	}

	private static boolean onUiThread() {
		return Looper.myLooper() == Looper.getMainLooper();
	}

	/**
	 * App-process force-on for Chromium WebView a11y (no AccessibilityService).
	 * Must run on the Android UI thread after the WebView is attached.
	 * Off-UI callers get false (use {@link #ensureAsync} or walkAsync).
	 */
	public static boolean ensure() {
		WebView wv = WebViewHost.getWebView();
		if (wv == null) {
			Log.w(TAG, "ensure: no WebView");
			return false;
		}
		if (!onUiThread()) {
			Log.e(TAG, "ensure: called off UI thread — refusing (deadlock risk)");
			return false;
		}
		if (wv.getWindowToken() == null) {
			Log.w(TAG, "ensure: WebView not attached to window yet");
			return false;
		}

		wv.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_YES);

		Context ctx = wv.getContext();
		AccessibilityManager am = (AccessibilityManager)
			ctx.getSystemService(Context.ACCESSIBILITY_SERVICE);

		/* 1) DirectConnection via setQueryFromAppProcessEnabled (API 34+).
		 *    Must use an unsealed node — obtain()+onInitialize…, not create…. */
		boolean linked = linkDirectConnection(wv);
		boolean a11yOn = am != null && am.isEnabled();
		Log.i(TAG, "ensure: linked=" + linked + " AccessibilityManager.isEnabled=" + a11yOn
			+ " vis=" + wv.getVisibility()
			+ " wh=" + wv.getWidth() + "x" + wv.getHeight()
			+ " tx=" + wv.getTranslationX());

		/* 2) Chromium listens for AccessibilityStateChange — DirectConnection
		 *    flips isEnabled() but does not always fire the listener. */
		if (a11yOn) {
			notifyAccessibilityStateChanged(am, true);
		}

		/* 3) Touch the provider (first call may only native-enable). */
		AccessibilityNodeProvider provider = wv.getAccessibilityNodeProvider();
		if (provider == null) {
			provider = wv.getAccessibilityNodeProvider();
		}
		Log.i(TAG, "ensure: provider=" + (provider != null ? "ok" : "null"));

		AccessibilityNodeInfo root = obtainRoot(wv, provider);
		if (root == null) {
			Log.w(TAG, "ensure: no root node");
			return false;
		}
		/* Keep DirectConnection on the live tree root too. */
		if (Build.VERSION.SDK_INT >= 34) {
			try {
				root.setQueryFromAppProcessEnabled(wv, true);
			} catch (Throwable t) {
				Log.w(TAG, "ensure: setQuery on root failed", t);
			}
		}
		int children = root.getChildCount();
		root.recycle();
		forceOnDone = linked && (provider != null || children > 0);
		Log.i(TAG, "ensure: ok rootChildren=" + children + " forceOnDone=" + forceOnDone);
		return forceOnDone || children > 0;
	}

	/** Call once after attach / after load so the DirectConnection stays warm. */
	public static void ensureAsync(WebView wv) {
		if (wv == null) {
			return;
		}
		wv.post(() -> {
			try {
				ensure();
				maybeSpikeFixture(wv);
			} catch (Throwable t) {
				Log.w(TAG, "ensureAsync failed", t);
			}
		});
	}

	/** Temp 1.3 verify — remove when SPIKE_FIXTURE is false. */
	private static void maybeSpikeFixture(WebView wv) {
		if (!SPIKE_FIXTURE || spikeFixtureScheduled || wv == null) {
			return;
		}
		spikeFixtureScheduled = true;
		String html = "<!DOCTYPE html><html><head><meta charset=utf-8>"
			+ "<meta name=viewport content=\"width=device-width, initial-scale=1\">"
			+ "<title>a11y html name spike</title></head><body>"
			+ "<h1>Fill-key fixture</h1>"
			+ "<label>Email <input name=\"email\" id=\"email-id\" type=\"text\"></label>"
			+ "<label>Search <input name=\"q\" type=\"search\"></label>"
			+ "<button type=\"submit\">Go</button></body></html>";
		Log.i(TAG, "spikeFixture: loadDataWithBaseURL");
		wv.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null);
		wv.postDelayed(() -> {
			try {
				walkOnUiThreadAsync(nodes -> {
					for (Node n : nodes) {
						if (n.htmlName.length() > 0 || n.htmlId.length() > 0
								|| n.htmlTag.length() > 0) {
							Log.i(TAG, "spikeNode id=" + n.id
								+ " role=" + n.role
								+ " htmlName=" + n.htmlName
								+ " htmlId=" + n.htmlId
								+ " htmlTag=" + n.htmlTag);
						}
					}
				});
			} catch (Throwable t) {
				Log.w(TAG, "spikeFixture walk failed", t);
			}
		}, 2500);
	}

	private static boolean linkDirectConnection(WebView wv) {
		if (Build.VERSION.SDK_INT < 34) {
			Log.w(TAG, "linkDirectConnection: need API 34+");
			return false;
		}
		AccessibilityNodeInfo info = AccessibilityNodeInfo.obtain(wv);
		try {
			wv.onInitializeAccessibilityNodeInfo(info);
			info.setQueryFromAppProcessEnabled(wv, true);
			Log.i(TAG, "linkDirectConnection: setQueryFromAppProcessEnabled(true)");
			return true;
		} catch (Throwable t) {
			Log.w(TAG, "linkDirectConnection failed", t);
			return false;
		} finally {
			info.recycle();
		}
	}

	/**
	 * Tell registered AccessibilityStateChangeListeners that a11y is on.
	 * Chromium WebView uses this to set mNativeAccessibilityAllowed.
	 */
	@SuppressWarnings("unchecked")
	private static void notifyAccessibilityStateChanged(AccessibilityManager am, boolean enabled) {
		if (am == null) {
			return;
		}
		try {
			Method notify = AccessibilityManager.class.getDeclaredMethod(
				"notifyAccessibilityStateChanged");
			notify.setAccessible(true);
			notify.invoke(am);
			Log.i(TAG, "notifyAccessibilityStateChanged() via reflection");
			return;
		} catch (Throwable ignored) {
			/* fall through — field shape varies by API */
		}
		try {
			Field f = AccessibilityManager.class.getDeclaredField(
				"mAccessibilityStateChangeListeners");
			f.setAccessible(true);
			Object mapObj = f.get(am);
			if (!(mapObj instanceof Map)) {
				Log.w(TAG, "notify: listeners field not a Map");
				return;
			}
			Map<?, ?> map = (Map<?, ?>) mapObj;
			int n = 0;
			for (Object key : map.keySet()) {
				if (key instanceof AccessibilityManager.AccessibilityStateChangeListener) {
					((AccessibilityManager.AccessibilityStateChangeListener) key)
						.onAccessibilityStateChanged(enabled);
					n++;
				}
			}
			Log.i(TAG, "notify: called " + n + " AccessibilityStateChangeListeners");
		} catch (Throwable t) {
			Log.w(TAG, "notifyAccessibilityStateChanged failed", t);
		}
	}

	/**
	 * Sync walk — Android UI thread only. From GTK/GLib use {@link #walkAsync}.
	 * HTML attrs use the last AssistStructure capture (may be empty on first sync call).
	 */
	public static synchronized Node[] walk() {
		if (!onUiThread()) {
			Log.e(TAG, "walk: called off UI thread — refusing sync WebView a11y (deadlock risk)");
			return new Node[0];
		}
		return walkNodeInfoOnUiThread();
	}

	/**
	 * Schedule walk on the WebView looper; delivers via {@link #nativeWalkDone}.
	 * Waits for Chromium AssistStructure snapshot (HTML name/id/tag) then NodeInfo walk.
	 * Does not block the caller — safe from the GTK thread.
	 */
	public static void walkAsync(final long cookie) {
		WebView wv = WebViewHost.getWebView();
		if (wv == null) {
			Log.w(TAG, "walkAsync: no WebView cookie=" + cookie);
			nativeWalkDone(new Node[0], cookie);
			return;
		}
		wv.post(() -> walkOnUiThreadAsync(nodes -> {
			Log.i(TAG, "walkAsync: " + nodes.length + " nodes cookie=" + cookie);
			nativeWalkDone(nodes, cookie);
		}));
	}

	private static native void nativeWalkDone(Node[] nodes, long cookie);

	private interface WalkDone {
		void onDone(Node[] nodes);
	}

	/**
	 * UI thread: AssistStructure snapshot (async) → NodeInfo walk → {@code done}.
	 */
	private static void walkOnUiThreadAsync(WalkDone done) {
		WebView wv = WebViewHost.getWebView();
		if (wv == null) {
			done.onDone(new Node[0]);
			return;
		}
		ensure();
		captureHtmlAttrsAsync(wv, () -> {
			Node[] nodes;
			synchronized (WebViewA11y.class) {
				nodes = walkNodeInfoOnUiThread();
			}
			done.onDone(nodes);
		});
	}

	/** NodeInfo tree only — uses {@link #htmlAll} from the last capture. */
	private static Node[] walkNodeInfoOnUiThread() {
		clearCache();
		lastWalk.clear();
		WebView wv = WebViewHost.getWebView();
		if (wv == null) {
			return new Node[0];
		}
		ensure();
		AccessibilityNodeProvider provider = wv.getAccessibilityNodeProvider();
		AccessibilityNodeInfo root = obtainRoot(wv, provider);
		if (root == null) {
			Log.w(TAG, "walk: no root node");
			return new Node[0];
		}
		if (Build.VERSION.SDK_INT >= 34) {
			try {
				root.setQueryFromAppProcessEnabled(wv, true);
			} catch (Throwable ignored) {
			}
		}
		collect(root, -1, 0);
		root.recycle();
		mergeHtmlByEditOrder();
		Log.i(TAG, "walk: " + lastWalk.size() + " nodes htmlAttrs=" + htmlAll.size());
		return lastWalk.toArray(new Node[0]);
	}

	/**
	 * Pair editable NodeInfo rows with ViewStructure inputs in document order.
	 * Needed when Autofill virtual ids are absent (common on System WebView).
	 */
	private static void mergeHtmlByEditOrder() {
		List<HtmlAttrs> fields = new ArrayList<>();
		for (HtmlAttrs ha : htmlAll) {
			if (ha.name.length() == 0 && ha.id.length() == 0) {
				continue;
			}
			String tag = ha.tag != null ? ha.tag : "";
			if (tag.length() > 0
					&& !tag.equals("input")
					&& !tag.equals("textarea")
					&& !tag.equals("select")
					&& !tag.equals("button")) {
				continue;
			}
			fields.add(ha);
		}
		List<Node> edits = new ArrayList<>();
		for (Node n : lastWalk) {
			if (n.canSetValue) {
				edits.add(n);
			}
		}
		int n = Math.min(fields.size(), edits.size());
		for (int i = 0; i < n; i++) {
			Node node = edits.get(i);
			HtmlAttrs ha = fields.get(i);
			if (node.htmlName.length() == 0 && ha.name.length() > 0) {
				node.htmlName = ha.name;
			}
			if (node.htmlTag.length() == 0 && ha.tag.length() > 0) {
				node.htmlTag = ha.tag;
			}
			if (node.htmlId.length() == 0 && ha.id.length() > 0) {
				node.htmlId = ha.id;
			}
		}
	}

	/**
	 * Chromium AssistStructure side door (async): HTML tag + attrs via
	 * {@link WebView#onProvideVirtualStructure}. Invokes {@code whenDone} on the
	 * UI thread after {@code asyncCommit} or a timeout.
	 */
	private static void captureHtmlAttrsAsync(WebView wv, Runnable whenDone) {
		if (wv == null) {
			whenDone.run();
			return;
		}
		htmlByVirtualId.clear();
		htmlById.clear();
		htmlAll.clear();
		final boolean[] finished = { false };
		Runnable finish = () -> {
			if (finished[0]) {
				return;
			}
			finished[0] = true;
			whenDone.run();
		};
		try {
			CaptureViewStructure root = new CaptureViewStructure();
			root.pendingChildCommit = () -> {
				indexHtmlTree(root);
				Log.i(TAG, "captureHtmlAttrs: commit htmlAttrs=" + htmlAll.size());
				finish.run();
			};
			wv.onProvideVirtualStructure(root);
			/* Snapshot is async (renderer); don't hang forever. */
			wv.postDelayed(() -> {
				if (!finished[0]) {
					Log.w(TAG, "captureHtmlAttrs: timeout — indexing partial tree");
					indexHtmlTree(root);
					finish.run();
				}
			}, 3000);
		} catch (Throwable t) {
			Log.w(TAG, "captureHtmlAttrs failed", t);
			finish.run();
		}
	}

	private static void indexHtmlTree(CaptureViewStructure root) {
		htmlByVirtualId.clear();
		htmlById.clear();
		htmlAll.clear();
		List<CaptureViewStructure> flat = new ArrayList<>();
		root.flatten(flat);
		for (CaptureViewStructure vs : flat) {
			if (vs.htmlInfo == null) {
				continue;
			}
			HtmlAttrs ha = new HtmlAttrs();
			ha.tag = vs.htmlTag();
			ha.name = vs.htmlAttr("name");
			ha.id = vs.htmlAttr("id");
			if (ha.id.length() == 0 && vs.idEntryName != null && vs.idEntryName.length() > 0) {
				ha.id = vs.idEntryName;
			}
			ha.left = vs.left;
			ha.top = vs.top;
			ha.width = vs.width;
			ha.height = vs.height;
			htmlAll.add(ha);
			if (vs.autofillVirtualId >= 0) {
				htmlByVirtualId.put(vs.autofillVirtualId, ha);
			}
			if (ha.id.length() > 0 && !htmlById.containsKey(ha.id)) {
				htmlById.put(ha.id, ha);
			}
			if (ha.name.length() > 0 || ha.id.length() > 0) {
				Log.d(TAG, "htmlAttr tag=" + ha.tag
					+ " name=" + ha.name
					+ " id=" + ha.id
					+ " virt=" + vs.autofillVirtualId);
			}
		}
	}

	private static void applyHtmlAttrs(AccessibilityNodeInfo el, Node n) {
		HtmlAttrs ha = null;
		if (Build.VERSION.SDK_INT >= 33) {
			String uid = el.getUniqueId();
			if (uid != null && uid.length() > 0) {
				try {
					ha = htmlByVirtualId.get(Integer.parseInt(uid));
				} catch (NumberFormatException ignored) {
				}
			}
		}
		if (ha == null) {
			String viewId = el.getViewIdResourceName();
			if (viewId != null && viewId.length() > 0) {
				ha = htmlById.get(viewId);
			}
		}
		if (ha == null && n.canSetValue) {
			ha = matchHtmlByBounds(n);
		}
		if (ha == null) {
			String viewId = el.getViewIdResourceName();
			if (viewId != null) {
				n.htmlId = viewId;
			}
			return;
		}
		n.htmlName = ha.name != null ? ha.name : "";
		n.htmlId = ha.id != null ? ha.id : "";
		n.htmlTag = ha.tag != null ? ha.tag : "";
		if (n.htmlId.length() == 0) {
			String viewId = el.getViewIdResourceName();
			if (viewId != null) {
				n.htmlId = viewId;
			}
		}
	}

	/** Last-resort match for name-only inputs (no id / virt id miss). */
	private static HtmlAttrs matchHtmlByBounds(Node n) {
		HtmlAttrs best = null;
		int bestDist = Integer.MAX_VALUE;
		for (HtmlAttrs ha : htmlAll) {
			if (ha.name.length() == 0 && ha.id.length() == 0) {
				continue;
			}
			if (ha.width <= 0 || ha.height <= 0) {
				continue;
			}
			int cx = ha.left + ha.width / 2;
			int cy = ha.top + ha.height / 2;
			int nx = n.x + n.w / 2;
			int ny = n.y + n.h / 2;
			int dist = Math.abs(cx - nx) + Math.abs(cy - ny);
			if (dist < bestDist && dist < 120) {
				bestDist = dist;
				best = ha;
			}
		}
		return best;
	}

	private static void runOnUi(WebView wv, Runnable r) {
		if (onUiThread()) {
			r.run();
		} else {
			wv.post(r);
		}
	}

	private static AccessibilityNodeInfo obtainRoot(
		WebView wv,
		AccessibilityNodeProvider provider
	) {
		if (provider != null) {
			AccessibilityNodeInfo fromProvider =
				provider.createAccessibilityNodeInfo(
					AccessibilityNodeProvider.HOST_VIEW_ID);
			if (fromProvider != null) {
				return fromProvider;
			}
		}
		return wv.createAccessibilityNodeInfo();
	}

	public static boolean invoke(int id) {
		WebView wv = WebViewHost.getWebView();
		if (wv == null) {
			return false;
		}
		if (onUiThread()) {
			return invokeOnUi(id);
		}
		/* Fire-and-forget on UI — do not block GTK (ANR with blockForMain). */
		runOnUi(wv, () -> invokeOnUi(id));
		return true;
	}

	private static synchronized boolean invokeOnUi(int id) {
		AccessibilityNodeInfo n = cacheGet(id);
		if (n == null) {
			return false;
		}
		boolean ok = n.performAction(AccessibilityNodeInfo.ACTION_CLICK);
		Log.i(TAG, "invoke id=" + id + " → " + ok);
		return ok;
	}

	public static boolean setValue(int id, String utf8) {
		WebView wv = WebViewHost.getWebView();
		if (wv == null) {
			return false;
		}
		final String text = utf8;
		if (onUiThread()) {
			return setValueOnUi(id, text);
		}
		runOnUi(wv, () -> setValueOnUi(id, text));
		return true;
	}

	private static synchronized boolean setValueOnUi(int id, String utf8) {
		AccessibilityNodeInfo n = cacheGet(id);
		if (n == null) {
			return false;
		}
		Bundle args = new Bundle();
		args.putCharSequence(
			AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
			utf8 != null ? utf8 : ""
		);
		boolean ok = n.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args);
		if (!ok) {
			n.performAction(AccessibilityNodeInfo.ACTION_FOCUS);
			ok = n.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args);
		}
		Log.i(TAG, "setValue id=" + id + " → " + ok);
		return ok;
	}

	public static boolean focus(int id) {
		WebView wv = WebViewHost.getWebView();
		if (wv == null) {
			return false;
		}
		if (onUiThread()) {
			return focusOnUi(id);
		}
		runOnUi(wv, () -> focusOnUi(id));
		return true;
	}

	private static synchronized boolean focusOnUi(int id) {
		AccessibilityNodeInfo n = cacheGet(id);
		if (n == null) {
			return false;
		}
		boolean ok = n.performAction(AccessibilityNodeInfo.ACTION_FOCUS);
		Log.i(TAG, "focus id=" + id + " → " + ok);
		return ok;
	}

	private static void collect(AccessibilityNodeInfo el, int parentId, int depth) {
		if (el == null || lastWalk.size() >= MAX_NODES || depth > MAX_DEPTH) {
			return;
		}
		int myId = lastWalk.size();
		Node node = fillNode(el, myId, parentId);
		lastWalk.add(node);
		cache.add(AccessibilityNodeInfo.obtain(el));

		if (depth >= MAX_DEPTH) {
			return;
		}
		int childCount = el.getChildCount();
		for (int i = 0; i < childCount && lastWalk.size() < MAX_NODES; i++) {
			AccessibilityNodeInfo child = el.getChild(i);
			if (child == null) {
				continue;
			}
			collect(child, myId, depth + 1);
			child.recycle();
		}
	}

	private static Node fillNode(AccessibilityNodeInfo el, int id, int parentId) {
		Node n = new Node();
		n.id = id;
		n.parentId = parentId;
		Rect r = new Rect();
		el.getBoundsInScreen(r);
		/* Globe-off parks via translationX — report layout-space bounds so
		 * markdown {x,y} and size stay phone-relative (not 100000+). */
		WebView wv = WebViewHost.getWebView();
		int tx = wv != null ? Math.round(wv.getTranslationX()) : 0;
		int ty = wv != null ? Math.round(wv.getTranslationY()) : 0;
		n.x = r.left - tx;
		n.y = r.top - ty;
		n.w = r.width();
		n.h = r.height();
		if (n.w < 0) {
			n.w = 0;
		}
		if (n.h < 0) {
			n.h = 0;
		}

		CharSequence nameCs = el.getContentDescription();
		if (nameCs == null || nameCs.length() == 0) {
			nameCs = el.getText();
		}
		n.name = nameCs != null ? nameCs.toString() : "";

		n.role = roleOf(el);

		CharSequence valueCs = el.getText();
		n.value = valueCs != null ? valueCs.toString() : "";
		n.uri = httpUri(n.value);
		if (n.uri.length() == 0 && Build.VERSION.SDK_INT >= 26) {
			CharSequence hint = el.getHintText();
			if (hint != null) {
				n.uri = httpUri(hint.toString());
			}
		}

		n.canInvoke = el.isClickable()
			|| el.getActionList().contains(
				AccessibilityNodeInfo.AccessibilityAction.ACTION_CLICK);
		n.canSetValue = el.isEditable()
			|| el.getActionList().contains(
				AccessibilityNodeInfo.AccessibilityAction.ACTION_SET_TEXT);
		applyHtmlAttrs(el, n);
		return n;
	}

	private static String roleOf(AccessibilityNodeInfo el) {
		String cls = el.getClassName() != null ? el.getClassName().toString() : "";
		if (cls.contains("EditText") || el.isEditable()) {
			return "Edit";
		}
		if (cls.contains("Button") || (el.isClickable() && !el.isEditable())) {
			return "Button";
		}
		if (cls.contains("WebView")) {
			return "Document";
		}
		if (el.isHeading()) {
			return "Text";
		}
		if (cls.length() > 0) {
			int dot = cls.lastIndexOf('.');
			return dot >= 0 ? cls.substring(dot + 1) : cls;
		}
		return "Group";
	}

	private static String httpUri(String value) {
		if (value == null) {
			return "";
		}
		if (value.startsWith("http://") || value.startsWith("https://")) {
			return value;
		}
		return "";
	}

	private static AccessibilityNodeInfo cacheGet(int id) {
		if (id < 0 || id >= cache.size()) {
			return null;
		}
		return cache.get(id);
	}

	private static void clearCache() {
		for (AccessibilityNodeInfo n : cache) {
			try {
				n.recycle();
			} catch (Throwable ignored) {
			}
		}
		cache.clear();
	}
}
