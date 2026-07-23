package org.roojs.webkitgtk.android;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Rect;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.PixelCopy;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewTreeObserver;
import android.webkit.WebView;

import java.nio.ByteBuffer;

/**
 * Modal freeze: PixelCopy → crop system-nav overlap → GTK Picture.
 * See docs/freeze.md.
 */
public final class WebViewFreeze {
	private static final String TAG = "WebViewFreeze";
	private static final long TICK_MS = 1000L;
	public static final float PARK_TRANSLATION_X = 100000f;

	private static final Handler handler = new Handler(Looper.getMainLooper());
	private static boolean frozen;
	private static boolean dirty;
	private static boolean drawHooked;
	private static boolean captureInFlight;
	private static ViewTreeObserver.OnDrawListener drawListener;
	private static final Runnable tickRunnable = WebViewFreeze::tick;

	private WebViewFreeze() {
	}

	public static void markDirty() {
		if (frozen) {
			dirty = true;
		}
	}

	public static boolean isFrozen() {
		return frozen;
	}

	public static void enter() {
		Activity act = activity();
		WebView wv = WebViewHost.getWebView();
		if (act == null || wv == null) {
			Log.w(TAG, "enter: no WebView");
			return;
		}
		runOnUi(act, () -> enterUi(wv));
	}

	public static void exit() {
		Activity act = activity();
		if (act == null) {
			return;
		}
		runOnUi(act, WebViewFreeze::exitUi);
	}

	private static void runOnUi(Activity act, Runnable r) {
		if (Looper.myLooper() == Looper.getMainLooper()) {
			r.run();
		} else {
			act.runOnUiThread(r);
		}
	}

	private static Activity activity() {
		WebView wv = WebViewHost.getWebView();
		if (wv == null) {
			return null;
		}
		android.content.Context c = wv.getContext();
		return c instanceof Activity ? (Activity) c : null;
	}

	private static void enterUi(WebView wv) {
		if (frozen) {
			return;
		}
		hookDraw(wv);
		frozen = true;
		dirty = true;
		captureAndNotify(wv, true);
	}

	private static void exitUi() {
		handler.removeCallbacks(tickRunnable);
		if (!frozen) {
			return;
		}
		frozen = false;
		dirty = false;
		captureInFlight = false;
		WebView wv = WebViewHost.getWebView();
		if (wv != null) {
			unpark(wv);
		}
		/* Stay SurfaceView-on-top while globe-off (content parked). */
		WebViewHost.setGtkSurfaceOnTopForFreeze(!WebViewHost.isContentVisible());
		WebViewHost.nativeFreezeFrame(null, 0, 0);
	}

	private static void parkOffscreen(WebView wv) {
		wv.setTranslationX(PARK_TRANSLATION_X);
		wv.setClickable(false);
		wv.setFocusable(false);
		wv.setFocusableInTouchMode(false);
		wv.setEnabled(false);
		wv.setVisibility(View.VISIBLE);
	}

	private static void unpark(WebView wv) {
		/* Globe-off keeps contentVisible=false — stay parked after freeze exit. */
		if (!WebViewHost.isContentVisible()) {
			parkOffscreen(wv);
			return;
		}
		wv.setTranslationX(0f);
		wv.setClickable(true);
		wv.setFocusable(true);
		wv.setFocusableInTouchMode(true);
		wv.setEnabled(true);
		wv.setVisibility(View.VISIBLE);
		wv.bringToFront();
	}

	private static void tick() {
		if (!frozen) {
			return;
		}
		WebView wv = WebViewHost.getWebView();
		if (wv == null) {
			return;
		}
		if (dirty && !captureInFlight) {
			dirty = false;
			captureAndNotify(wv, false);
		} else {
			handler.postDelayed(tickRunnable, TICK_MS);
		}
	}

	private static void hookDraw(WebView wv) {
		if (drawHooked) {
			return;
		}
		drawListener = () -> markDirty();
		wv.getViewTreeObserver().addOnDrawListener(drawListener);
		drawHooked = true;
	}

	private static void captureAndNotify(WebView wv, boolean isEnter) {
		Activity act = activity();
		if (act == null) {
			return;
		}
		int w = wv.getWidth();
		int h = wv.getHeight();
		if (w <= 0 || h <= 0) {
			Log.w(TAG, "capture: empty WebView size");
			if (isEnter) {
				finishEnterAfterCapture(wv);
			} else if (frozen) {
				finishRefreshAfterCapture(wv);
			}
			return;
		}
		if (captureInFlight) {
			dirty = true;
			return;
		}

		int[] locWin = new int[2];
		wv.getLocationInWindow(locWin);
		Bitmap bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
		Rect src = new Rect(locWin[0], locWin[1], locWin[0] + w, locWin[1] + h);
		View decor = act.getWindow().getDecorView();
		if (!src.intersect(0, 0, decor.getWidth(), decor.getHeight()) || src.isEmpty()) {
			Log.w(TAG, "capture: empty window rect");
			bmp.recycle();
			if (isEnter) {
				finishEnterAfterCapture(wv);
			} else if (frozen) {
				finishRefreshAfterCapture(wv);
			}
			return;
		}
		if (src.width() != w || src.height() != h) {
			bmp.recycle();
			bmp = Bitmap.createBitmap(src.width(), src.height(), Bitmap.Config.ARGB_8888);
		}

		captureInFlight = true;
		final Bitmap out = bmp;
		try {
			PixelCopy.request(act.getWindow(), src, out, copyResult -> {
				captureInFlight = false;
				if (!frozen && !isEnter) {
					out.recycle();
					return;
				}
				if (copyResult != PixelCopy.SUCCESS) {
					Log.w(TAG, "PixelCopy failed result=" + copyResult);
					fallbackDraw(wv, out);
				}
				int cropBottom = bottomOverlapBehindSystemNav(wv);
				Log.i(TAG, "publish " + out.getWidth() + "x" + out.getHeight()
						+ " cropBottom=" + cropBottom);
				publishBitmap(out, cropBottom);
				out.recycle();
				if (isEnter) {
					finishEnterAfterCapture(wv);
				} else if (frozen) {
					finishRefreshAfterCapture(wv);
				}
			}, handler);
		} catch (Throwable t) {
			captureInFlight = false;
			Log.w(TAG, "PixelCopy threw", t);
			fallbackDraw(wv, out);
			int cropBottom = bottomOverlapBehindSystemNav(wv);
			Log.i(TAG, "publish " + out.getWidth() + "x" + out.getHeight()
					+ " cropBottom=" + cropBottom);
			publishBitmap(out, cropBottom);
			out.recycle();
			if (isEnter) {
				finishEnterAfterCapture(wv);
			} else if (frozen) {
				finishRefreshAfterCapture(wv);
			}
		}
	}

	private static void finishEnterAfterCapture(WebView wv) {
		dirty = false;
		parkOffscreen(wv);
		WebViewHost.setGtkSurfaceOnTopForFreeze(true);
		handler.removeCallbacks(tickRunnable);
		handler.postDelayed(tickRunnable, TICK_MS);
	}

	private static void finishRefreshAfterCapture(WebView wv) {
		parkOffscreen(wv);
		WebViewHost.setGtkSurfaceOnTopForFreeze(true);
		handler.postDelayed(tickRunnable, TICK_MS);
	}

	/**
	 * Rows of the WebView that extend past the GTK SurfaceView bottom
	 * (behind the system nav). Only crop that overlap — do not use nav
	 * inset as a fallback: after density-correct margins the WebView already
	 * matches host_area, and inset crop would shorten the texture so FILL
	 * stretches the bottom.
	 */
	private static int bottomOverlapBehindSystemNav(WebView wv) {
		Activity act = activity();
		if (act == null) {
			return 0;
		}
		ViewGroup content = act.findViewById(android.R.id.content);
		if (content == null || content.getChildCount() < 1) {
			return 0;
		}
		View surf = findSurfaceView(content.getChildAt(0));
		if (surf == null) {
			return 0;
		}
		int[] wvScreen = new int[2];
		int[] sv = new int[2];
		wv.getLocationOnScreen(wvScreen);
		surf.getLocationOnScreen(sv);
		int wvBottom = wvScreen[1] + wv.getHeight();
		int surfBottom = sv[1] + surf.getHeight();
		return Math.max(0, wvBottom - surfBottom);
	}

	private static View findSurfaceView(View root) {
		if (root instanceof android.view.SurfaceView) {
			return root;
		}
		if (root instanceof ViewGroup) {
			ViewGroup g = (ViewGroup) root;
			for (int i = 0; i < g.getChildCount(); i++) {
				View found = findSurfaceView(g.getChildAt(i));
				if (found != null) {
					return found;
				}
			}
		}
		return null;
	}

	private static void fallbackDraw(WebView wv, Bitmap bmp) {
		Canvas canvas = new Canvas(bmp);
		wv.draw(canvas);
	}

	/** Chop only the system-nav overlap; placement comes from WebView margins. */
	private static void publishBitmap(Bitmap bmp, int cropBottom) {
		int w = bmp.getWidth();
		int h = bmp.getHeight();
		Bitmap cropped = null;
		try {
			if (cropBottom < 0) {
				cropBottom = 0;
			}
			int useH = h - cropBottom;
			if (useH < 1) {
				cropBottom = 0;
				useH = h;
			}
			Bitmap forGtk = bmp;
			if (cropBottom > 0) {
				cropped = Bitmap.createBitmap(bmp, 0, 0, w, useH);
				forGtk = cropped;
			}
			int gw = forGtk.getWidth();
			int gh = forGtk.getHeight();
			ByteBuffer buf = ByteBuffer.allocate(gw * gh * 4);
			forGtk.copyPixelsToBuffer(buf);
			WebViewHost.nativeFreezeFrame(buf.array(), gw, gh);
		} catch (Throwable t) {
			Log.w(TAG, "publish failed", t);
		} finally {
			if (cropped != null) {
				cropped.recycle();
			}
		}
	}
}
