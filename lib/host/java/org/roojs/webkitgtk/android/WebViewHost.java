package org.roojs.webkitgtk.android;

import android.app.Activity;
import android.net.Uri;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;

import org.gtk.android.ToplevelActivity;

/**
 * Singleton Android System WebView host for GTK overlay (Phase 2).
 *
 * GTK's SurfaceView defaults to setZOrderOnTop(true), which hides normal
 * content views. We lower that z-order and place the WebView as a sibling
 * content view with margins matching the GTK host-area allocation, so the
 * toolbar above stays visible on the GTK surface.
 *
 * All public entry points marshal to the UI thread.
 */
public final class WebViewHost {
	private static final String TAG = "WebViewHost";

	public static final int LOAD_STARTED = 0;
	public static final int LOAD_REDIRECTED = 1;
	public static final int LOAD_COMMITTED = 2;
	public static final int LOAD_FINISHED = 3;

	private static WebView webView;
	private static Activity activity;
	private static int virtualWidth;
	private static int virtualHeight;
	private static int lastX = Integer.MIN_VALUE;
	private static int lastY = Integer.MIN_VALUE;
	private static int lastW = Integer.MIN_VALUE;
	private static int lastH = Integer.MIN_VALUE;
	private static String currentUri = "about:blank";
	private static String currentTitle = "";
	private static boolean ready;
	private static boolean gtkSurfaceLowered;

	private WebViewHost() {
	}

	public static void attach(Activity act, int x, int y, int w, int h, String url) {
		if (act == null) {
			return;
		}
		act.runOnUiThread(() -> attachUi(act, x, y, w, h, url));
	}

	public static void setBounds(int x, int y, int w, int h) {
		Activity act = activity;
		if (act == null) {
			return;
		}
		act.runOnUiThread(() -> setBoundsUi(x, y, w, h));
	}

	public static void navigate(String url) {
		Activity act = activity;
		if (act == null || url == null) {
			return;
		}
		act.runOnUiThread(() -> {
			if (webView != null) {
				webView.loadUrl(forceHttps(url));
			}
		});
	}

	public static void goBack() {
		Activity act = activity;
		if (act == null) {
			return;
		}
		act.runOnUiThread(() -> {
			if (webView != null && webView.canGoBack()) {
				webView.goBack();
			}
		});
	}

	public static void goForward() {
		Activity act = activity;
		if (act == null) {
			return;
		}
		act.runOnUiThread(() -> {
			if (webView != null && webView.canGoForward()) {
				webView.goForward();
			}
		});
	}

	public static void reload() {
		Activity act = activity;
		if (act == null) {
			return;
		}
		act.runOnUiThread(() -> {
			if (webView != null) {
				webView.reload();
			}
		});
	}

	public static void stopLoading() {
		Activity act = activity;
		if (act == null) {
			return;
		}
		act.runOnUiThread(() -> {
			if (webView != null) {
				webView.stopLoading();
			}
		});
	}

	public static boolean canGoBack() {
		WebView wv = webView;
		return wv != null && wv.canGoBack();
	}

	public static boolean canGoForward() {
		WebView wv = webView;
		return wv != null && wv.canGoForward();
	}

	public static void setVisible(boolean visible) {
		Activity act = activity;
		if (act == null) {
			return;
		}
		act.runOnUiThread(() -> {
			if (webView == null) {
				return;
			}
			webView.setVisibility(visible ? View.VISIBLE : View.INVISIBLE);
			setGtkSurfaceOnTop(!visible);
		});
	}

	public static void setVirtualSize(int w, int h) {
		virtualWidth = Math.max(w, 1);
		virtualHeight = Math.max(h, 1);
	}

	public static void useDisplaySize(Activity act) {
		if (act == null) {
			return;
		}
		act.runOnUiThread(() -> {
			DisplayMetrics dm = act.getResources().getDisplayMetrics();
			setVirtualSize(dm.widthPixels, dm.heightPixels);
		});
	}

	public static void destroy() {
		Activity act = activity;
		if (act == null) {
			return;
		}
		act.runOnUiThread(WebViewHost::destroyUi);
	}

	public static boolean isReady() {
		return ready;
	}

	public static String getUri() {
		return currentUri;
	}

	public static String getTitle() {
		return currentTitle;
	}

	/**
	 * Cookie header for ''uri'' ({@code name=value; name2=value2}), or empty.
	 * Same jar the WebView uses (android.webkit.CookieManager).
	 */
	public static String getCookies(String uri) {
		if (uri == null || uri.length() == 0) {
			return "";
		}
		try {
			String raw = CookieManager.getInstance().getCookie(uri);
			return raw != null ? raw : "";
		} catch (Throwable t) {
			Log.w(TAG, "getCookies failed", t);
			return "";
		}
	}

	/**
	 * Add/update one cookie in the WebView jar (Set-Cookie style attributes).
	 *
	 * @return true if setCookie was called
	 */
	public static boolean addCookie(String name, String value, String domain,
			String path, boolean httpOnly, boolean secure) {
		if (name == null || name.length() == 0 || value == null) {
			return false;
		}
		String host = domain != null ? domain : "";
		if (host.startsWith(".")) {
			host = host.substring(1);
		}
		if (host.length() == 0) {
			Log.w(TAG, "addCookie: empty domain");
			return false;
		}
		String p = (path == null || path.length() == 0) ? "/" : path;
		String scheme = secure ? "https" : "http";
		String url = scheme + "://" + host + p;
		StringBuilder sb = new StringBuilder();
		sb.append(name).append("=").append(value);
		sb.append("; Path=").append(p);
		if (domain != null && domain.length() > 0) {
			sb.append("; Domain=").append(domain);
		}
		if (secure) {
			sb.append("; Secure");
		}
		if (httpOnly) {
			sb.append("; HttpOnly");
		}
		try {
			CookieManager cm = CookieManager.getInstance();
			cm.setAcceptCookie(true);
			cm.setCookie(url, sb.toString());
			cm.flush();
			Log.i(TAG, "addCookie " + name + " for " + url);
			return true;
		} catch (Throwable t) {
			Log.w(TAG, "addCookie failed", t);
			return false;
		}
	}

	/** For WebViewA11y — may be null before attach. */
	public static WebView getWebView() {
		return webView;
	}

	/** Modal freeze — see WebViewFreeze / docs/freeze.md. */
	public static void freeze() {
		WebViewFreeze.enter();
	}

	public static void resume() {
		WebViewFreeze.exit();
	}

	/** Package: raise/lower GTK SurfaceView during freeze. */
	static void setGtkSurfaceOnTopForFreeze(boolean onTop) {
		setGtkSurfaceOnTop(onTop);
		if (!onTop && webView != null) {
			webView.setVisibility(View.VISIBLE);
			webView.bringToFront();
			gtkSurfaceLowered = true;
		} else if (onTop) {
			gtkSurfaceLowered = false;
		}
	}

	/** Upgrade http:// to https:// — Android blocks cleartext by default. */
	private static String forceHttps(String url) {
		if (url == null || url.length() == 0) {
			return url;
		}
		Uri uri = Uri.parse(url);
		if ("http".equalsIgnoreCase(uri.getScheme())) {
			String https = uri.buildUpon().scheme("https").build().toString();
			Log.i(TAG, "forceHttps " + url + " → " + https);
			return https;
		}
		return url;
	}

	private static void attachUi(Activity act, int x, int y, int w, int h, String url) {
		if (webView != null) {
			setBoundsUi(x, y, w, h);
			if (url != null && url.length() > 0) {
				webView.loadUrl(forceHttps(url));
			}
			return;
		}

		activity = act;
		useDisplaySizeLocked(act);

		webView = new WebView(act);
		WebSettings settings = webView.getSettings();
		settings.setJavaScriptEnabled(true);
		settings.setDomStorageEnabled(true);
		CookieManager cookieManager = CookieManager.getInstance();
		cookieManager.setAcceptCookie(true);
		cookieManager.setAcceptThirdPartyCookies(webView, true);
		WebViewDownload.install(webView);

		webView.setWebViewClient(new WebViewClient() {
			@Override
			public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
				String forced = forceHttps(url);
				if (url != null && !url.equals(forced)) {
					view.stopLoading();
					view.loadUrl(forced);
					return;
				}
				currentUri = url != null ? url : "";
				Log.i(TAG, "onPageStarted " + currentUri);
				WebViewPaintProbe.logClient("onPageStarted", currentUri);
				nativeLoadChanged(LOAD_STARTED);
				nativeLoadChanged(LOAD_COMMITTED);
			}

			@Override
			public void onPageCommitVisible(WebView view, String url) {
				WebViewPaintProbe.logClient("onPageCommitVisible", url);
			}

			@Override
			public void onPageFinished(WebView view, String url) {
				currentUri = url != null ? url : "";
				if (view.getTitle() != null) {
					currentTitle = view.getTitle();
					nativeTitleChanged();
				}
				Log.i(TAG, "onPageFinished " + currentUri);
				WebViewPaintProbe.logClient("onPageFinished", currentUri);
				nativeLoadChanged(LOAD_FINISHED);
				WebViewA11y.ensureAsync(view);
			}

			@Override
			public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
				Uri uri = request.getUrl();
				if (uri != null && "http".equalsIgnoreCase(uri.getScheme())) {
					view.loadUrl(forceHttps(uri.toString()));
					return true;
				}
				return false;
			}

			@Override
			public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
				if (request == null || !request.isForMainFrame() || request.getUrl() == null) {
					return;
				}
				Uri uri = request.getUrl();
				if ("http".equalsIgnoreCase(uri.getScheme())) {
					Log.w(TAG, "cleartext/error on " + uri + " — retry https");
					view.loadUrl(forceHttps(uri.toString()));
				}
			}
		});
		webView.setWebChromeClient(new WebChromeClient() {
			@Override
			public void onReceivedTitle(WebView view, String title) {
				currentTitle = title != null ? title : "";
				nativeTitleChanged();
			}

			@Override
			public void onProgressChanged(WebView view, int newProgress) {
				if (newProgress == 0 || newProgress == 100 || newProgress % 25 == 0) {
					WebViewPaintProbe.logClient("onProgressChanged", String.valueOf(newProgress));
				}
			}
		});

		FrameLayout.LayoutParams lp = layoutParams(act, x, y, w, h);
		act.addContentView(webView, lp);
		webView.setVisibility(View.VISIBLE);
		webView.bringToFront();
		setGtkSurfaceOnTop(false);
		gtkSurfaceLowered = true;

		lastX = lp.leftMargin;
		lastY = lp.topMargin;
		lastW = lp.width;
		lastH = lp.height;
		ready = true;
		Log.i(TAG, "attach contentView " + lp.leftMargin + "," + lp.topMargin
			+ " " + lp.width + "x" + lp.height + " url=" + url);

		WebViewPaintProbe.install(webView);

		if (url != null && url.length() > 0) {
			webView.loadUrl(forceHttps(url));
		}
		/* App-process a11y DirectConnection — no AccessibilityService. */
		WebViewA11y.ensureAsync(webView);
	}

	private static void setBoundsUi(int x, int y, int w, int h) {
		if (webView == null || activity == null) {
			return;
		}
		FrameLayout.LayoutParams lp = layoutParams(activity, x, y, w, h);
		if (lp.leftMargin == lastX && lp.topMargin == lastY
			&& lp.width == lastW && lp.height == lastH) {
			return;
		}
		lastX = lp.leftMargin;
		lastY = lp.topMargin;
		lastW = lp.width;
		lastH = lp.height;
		webView.setLayoutParams(lp);
		webView.setVisibility(View.VISIBLE);
		if (WebViewFreeze.isFrozen()) {
			/* Keep parked off-screen — do not steal touches from GTK dialogs. */
			webView.setTranslationX(WebViewFreeze.PARK_TRANSLATION_X);
		} else {
			webView.setTranslationX(0f);
			webView.bringToFront();
			if (!gtkSurfaceLowered) {
				setGtkSurfaceOnTop(false);
				gtkSurfaceLowered = true;
			}
		}
		Log.i(TAG, "setBounds contentView " + lp.leftMargin + "," + lp.topMargin
			+ " " + lp.width + "x" + lp.height);
	}

	/**
	 * GTK host-area is surface-local; add SurfaceView window origin so margins
	 * line up under the toolbar inside the activity content FrameLayout.
	 */
	private static FrameLayout.LayoutParams layoutParams(Activity act, int x, int y, int w, int h) {
		int useW = w;
		int useH = h;
		int useX = x;
		int useY = y;
		if (useW <= 0 || useH <= 0) {
			useW = virtualWidth > 0 ? virtualWidth : 1;
			useH = virtualHeight > 0 ? virtualHeight : 1;
			useX = 0;
			useY = 0;
		}

		int[] origin = gtkSurfaceOriginInContent(act);
		useX += origin[0];
		useY += origin[1];

		DisplayMetrics dm = act.getResources().getDisplayMetrics();
		if (useX < 0) {
			useX = 0;
		}
		if (useY < 0) {
			useY = 0;
		}
		int maxW = Math.max(dm.widthPixels - useX, 1);
		int maxH = Math.max(dm.heightPixels - useY, 1);
		if (useW > maxW) {
			useW = maxW;
		}
		if (useH > maxH) {
			useH = maxH;
		}

		FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(useW, useH);
		lp.leftMargin = useX;
		lp.topMargin = useY;
		return lp;
	}

	/**
	 * SurfaceView position relative to android.R.id.content (addContentView parent).
	 */
	private static int[] gtkSurfaceOriginInContent(Activity act) {
		int[] loc = new int[] { 0, 0 };
		ViewGroup content = act.findViewById(android.R.id.content);
		if (content == null || content.getChildCount() < 1) {
			return loc;
		}
		View child = content.getChildAt(0);
		if (!(child instanceof ToplevelActivity.ToplevelView)) {
			return loc;
		}
		ToplevelActivity.ToplevelView tv = (ToplevelActivity.ToplevelView) child;
		if (tv.toplevel == null) {
			return loc;
		}
		int[] surfaceLoc = new int[2];
		int[] contentLoc = new int[2];
		tv.toplevel.getLocationInWindow(surfaceLoc);
		content.getLocationInWindow(contentLoc);
		loc[0] = surfaceLoc[0] - contentLoc[0];
		loc[1] = surfaceLoc[1] - contentLoc[1];
		return loc;
	}

	private static void useDisplaySizeLocked(Activity act) {
		DisplayMetrics dm = act.getResources().getDisplayMetrics();
		virtualWidth = Math.max(dm.widthPixels, 1);
		virtualHeight = Math.max(dm.heightPixels, 1);
	}

	private static void setGtkSurfaceOnTop(boolean onTop) {
		Activity act = activity;
		if (act == null) {
			return;
		}
		ViewGroup content = act.findViewById(android.R.id.content);
		if (content == null || content.getChildCount() < 1) {
			return;
		}
		View child = content.getChildAt(0);
		if (!(child instanceof ToplevelActivity.ToplevelView)) {
			return;
		}
		ToplevelActivity.ToplevelView tv = (ToplevelActivity.ToplevelView) child;
		if (tv.toplevel != null) {
			tv.toplevel.setZOrderOnTop(onTop);
			Log.i(TAG, "GTK SurfaceView setZOrderOnTop(" + onTop + ")");
		}
	}

	private static void destroyUi() {
		WebViewFreeze.exit();
		if (webView != null) {
			ViewGroup parent = (ViewGroup) webView.getParent();
			if (parent != null) {
				parent.removeView(webView);
			}
			webView.destroy();
			webView = null;
		}
		if (gtkSurfaceLowered) {
			setGtkSurfaceOnTop(true);
			gtkSurfaceLowered = false;
		}
		ready = false;
		activity = null;
		lastX = lastY = lastW = lastH = Integer.MIN_VALUE;
		currentUri = "about:blank";
		currentTitle = "";
	}

	private static native void nativeLoadChanged(int loadEvent);

	private static native void nativeTitleChanged();

	/** RGBA bytes + size; null/0 clears the GTK freeze picture. */
	static native void nativeFreezeFrame(byte[] rgba, int width, int height);

	/**
	 * Allocate a download job for tool-path {@code download_uri} (no listener).
	 *
	 * @return job id, or 0 on failure
	 */
	public static int createDownload(String url) {
		return WebViewDownload.createDownload(url);
	}

	public static boolean startDownload(int id, String destPath, boolean overwrite) {
		return WebViewDownload.startDownload(id, destPath, overwrite);
	}

	public static void cancelDownload(int id) {
		WebViewDownload.cancelDownload(id);
	}

	static native void nativeDownloadStarted(int id, String uri, String suggested,
			String mime, long contentLength);

	static native void nativeDownloadProgress(int id, long received);

	static native void nativeDownloadFinished(int id);

	static native void nativeDownloadFailed(int id, String message);
}
