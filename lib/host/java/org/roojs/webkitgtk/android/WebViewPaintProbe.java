package org.roojs.webkitgtk.android;

import android.graphics.Picture;
import android.os.SystemClock;
import android.util.Log;
import android.view.ViewTreeObserver;
import android.webkit.WebView;

/**
 * Temporary probe: which signals fire when the WebView's pixels change?
 * Used to pick a freeze-refresh trigger (see docs/freeze.md).
 *
 * Log tag: {@code WebViewPaint}
 *
 * <pre>
 * adb logcat -s WebViewPaint:I
 * </pre>
 */
public final class WebViewPaintProbe {
	private static final String TAG = "WebViewPaint";
	/** Re-arm VisualStateCallback after this delay (ms) to avoid a tight loop. */
	private static final long VISUAL_REARM_MS = 300;

	private static boolean installed;
	private static long visualId;
	private static int drawCount;
	private static int pictureCount;
	private static int visualCount;
	private static long windowStartMs;
	private static ViewTreeObserver.OnDrawListener drawListener;

	private WebViewPaintProbe() {
	}

	public static void install(WebView wv) {
		if (wv == null || installed) {
			return;
		}
		installed = true;
		windowStartMs = SystemClock.uptimeMillis();
		Log.i(TAG, "install: probing onDraw / VisualStateCallback / PictureListener");

		drawListener = () -> {
			drawCount++;
			maybeSummary();
		};
		wv.getViewTreeObserver().addOnDrawListener(drawListener);

		try {
			/* Deprecated — still log if Chromium fires it. */
			wv.setPictureListener(new WebView.PictureListener() {
				@Override
				public void onNewPicture(WebView view, Picture picture) {
					pictureCount++;
					Log.i(TAG, "onNewPicture pictureNull=" + (picture == null)
						+ " n=" + pictureCount);
					maybeSummary();
				}
			});
			Log.i(TAG, "PictureListener registered (deprecated API)");
		} catch (Throwable t) {
			Log.w(TAG, "PictureListener failed", t);
		}

		armVisualState(wv);
	}

	public static void logClient(String event, String detail) {
		Log.i(TAG, "client " + event + (detail != null ? " " + detail : ""));
	}

	private static void armVisualState(WebView wv) {
		if (wv == null) {
			return;
		}
		final long id = ++visualId;
		final long postedAt = SystemClock.uptimeMillis();
		try {
			wv.postVisualStateCallback(id, new WebView.VisualStateCallback() {
				@Override
				public void onComplete(long requestId) {
					visualCount++;
					long dt = SystemClock.uptimeMillis() - postedAt;
					Log.i(TAG, "VisualStateCallback id=" + requestId
						+ " dtMs=" + dt + " n=" + visualCount);
					maybeSummary();
					/* Re-arm: next completion ≈ next time DOM is ready to draw. */
					wv.postDelayed(() -> armVisualState(wv), VISUAL_REARM_MS);
				}
			});
		} catch (Throwable t) {
			Log.w(TAG, "postVisualStateCallback failed", t);
		}
	}

	private static void maybeSummary() {
		long now = SystemClock.uptimeMillis();
		if (now - windowStartMs < 1000) {
			return;
		}
		Log.i(TAG, "summary/s draws=" + drawCount
			+ " visuals=" + visualCount
			+ " pictures=" + pictureCount);
		drawCount = 0;
		/* visuals/pictures are cumulative lifetime — reset rate window only for draws */
		windowStartMs = now;
	}
}
