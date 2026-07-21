package org.roojs.webkitgtk.android;

import android.util.Log;
import android.webkit.CookieManager;
import android.webkit.DownloadListener;
import android.webkit.WebView;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * WebView download jobs — DownloadListener notify + HttpURLConnection transfer
 * with the WebView cookie jar (WebKitGTK-shaped hold until set_destination).
 */
final class WebViewDownload {
	private static final String TAG = "WebViewDownload";
	private static final Pattern FILENAME_STAR =
		Pattern.compile("filename\\*\\s*=\\s*(?:UTF-8''|utf-8'')([^;]+)", Pattern.CASE_INSENSITIVE);
	private static final Pattern FILENAME_QUOTED =
		Pattern.compile("filename\\s*=\\s*\"([^\"]+)\"", Pattern.CASE_INSENSITIVE);
	private static final Pattern FILENAME_PLAIN =
		Pattern.compile("filename\\s*=\\s*([^;\\s]+)", Pattern.CASE_INSENSITIVE);

	private static final AtomicInteger nextId = new AtomicInteger(1);
	private static final Map<Integer, Job> jobs = new ConcurrentHashMap<>();
	private static final ExecutorService executor = Executors.newCachedThreadPool(r -> {
		Thread t = new Thread(r, "wka-download");
		t.setDaemon(true);
		return t;
	});

	private WebViewDownload() {
	}

	static void install(WebView webView) {
		webView.setDownloadListener(new DownloadListener() {
			@Override
			public void onDownloadStart(String url, String userAgent,
					String contentDisposition, String mimeType, long contentLength) {
				String uri = url != null ? url : "";
				if (uri.length() == 0) {
					return;
				}
				String suggested = filenameFromDisposition(contentDisposition);
				if (suggested.length() == 0) {
					suggested = basenameFromUrl(uri);
				}
				String ua = userAgent != null ? userAgent : "";
				String mime = mimeType != null ? mimeType : "";
				int id = createJob(uri, ua, suggested, mime, contentLength);
				Log.i(TAG, "DownloadListener id=" + id + " uri=" + uri
					+ " suggested=" + suggested + " mime=" + mime);
				WebViewHost.nativeDownloadStarted(id, uri, suggested, mime, contentLength);
			}
		});
	}

	/** Tool-path download_uri — allocate job without DownloadListener. */
	static int createDownload(String url) {
		String uri = url != null ? url : "";
		if (uri.length() == 0) {
			return 0;
		}
		String ua = "";
		WebView wv = WebViewHost.getWebView();
		if (wv != null && wv.getSettings() != null) {
			String settingsUa = wv.getSettings().getUserAgentString();
			if (settingsUa != null) {
				ua = settingsUa;
			}
		}
		String suggested = basenameFromUrl(uri);
		return createJob(uri, ua, suggested, "", -1);
	}

	static boolean startDownload(int id, String destPath, boolean overwrite) {
		Job job = jobs.get(id);
		if (job == null || destPath == null || destPath.length() == 0) {
			return false;
		}
		synchronized (job) {
			if (job.started || job.cancelled.get()) {
				return false;
			}
			job.destPath = destPath;
			job.overwrite = overwrite;
			job.started = true;
		}
		executor.execute(() -> runTransfer(job));
		return true;
	}

	static void cancelDownload(int id) {
		Job job = jobs.get(id);
		if (job == null) {
			return;
		}
		job.cancelled.set(true);
		HttpURLConnection conn = job.connection;
		if (conn != null) {
			try {
				conn.disconnect();
			} catch (Throwable ignored) {
			}
		}
	}

	private static int createJob(String uri, String userAgent, String suggested,
			String mime, long contentLength) {
		int id = nextId.getAndIncrement();
		Job job = new Job();
		job.id = id;
		job.uri = uri;
		job.userAgent = userAgent;
		job.suggested = suggested != null ? suggested : "download";
		job.mime = mime != null ? mime : "";
		job.contentLength = contentLength;
		jobs.put(id, job);
		return id;
	}

	private static void runTransfer(Job job) {
		File dest = new File(job.destPath);
		File parent = dest.getParentFile();
		if (parent != null && !parent.exists() && !parent.mkdirs()) {
			fail(job, "Cannot create directory: " + parent.getAbsolutePath());
			return;
		}
		if (dest.exists() && !job.overwrite) {
			fail(job, "File exists: " + job.destPath);
			return;
		}

		HttpURLConnection conn = null;
		InputStream in = null;
		FileOutputStream out = null;
		try {
			URL url = new URL(job.uri);
			conn = (HttpURLConnection) url.openConnection();
			job.connection = conn;
			conn.setInstanceFollowRedirects(true);
			conn.setConnectTimeout(30000);
			conn.setReadTimeout(60000);
			conn.setRequestMethod("GET");
			if (job.userAgent != null && job.userAgent.length() > 0) {
				conn.setRequestProperty("User-Agent", job.userAgent);
			}
			String cookies = CookieManager.getInstance().getCookie(job.uri);
			if (cookies != null && cookies.length() > 0) {
				conn.setRequestProperty("Cookie", cookies);
			}
			conn.connect();
			if (job.cancelled.get()) {
				fail(job, "Download cancelled");
				return;
			}
			int code = conn.getResponseCode();
			if (code < 200 || code >= 300) {
				fail(job, "HTTP " + code);
				return;
			}
			in = conn.getInputStream();
			out = new FileOutputStream(dest);
			byte[] buf = new byte[64 * 1024];
			long received = 0;
			long lastReport = 0;
			int n;
			while ((n = in.read(buf)) >= 0) {
				if (job.cancelled.get()) {
					fail(job, "Download cancelled");
					try {
						out.close();
					} catch (Throwable ignored) {
					}
					//noinspection ResultOfMethodCallIgnored
					dest.delete();
					return;
				}
				out.write(buf, 0, n);
				received += n;
				if (received - lastReport >= 64 * 1024 || n == 0) {
					lastReport = received;
					final long report = received;
					WebViewHost.nativeDownloadProgress(job.id, report);
				}
			}
			out.flush();
			WebViewHost.nativeDownloadProgress(job.id, received);
			if (job.cancelled.get()) {
				fail(job, "Download cancelled");
				//noinspection ResultOfMethodCallIgnored
				dest.delete();
				return;
			}
			Log.i(TAG, "finished id=" + job.id + " bytes=" + received + " path=" + job.destPath);
			WebViewHost.nativeDownloadFinished(job.id);
			jobs.remove(job.id);
		} catch (Throwable t) {
			if (job.cancelled.get()) {
				fail(job, "Download cancelled");
			} else {
				fail(job, t.getMessage() != null ? t.getMessage() : t.toString());
			}
			if (dest.exists()) {
				//noinspection ResultOfMethodCallIgnored
				dest.delete();
			}
		} finally {
			try {
				if (out != null) {
					out.close();
				}
			} catch (Throwable ignored) {
			}
			try {
				if (in != null) {
					in.close();
				}
			} catch (Throwable ignored) {
			}
			if (conn != null) {
				conn.disconnect();
			}
			job.connection = null;
		}
	}

	private static void fail(Job job, String message) {
		Log.w(TAG, "failed id=" + job.id + ": " + message);
		WebViewHost.nativeDownloadFailed(job.id, message != null ? message : "download failed");
		jobs.remove(job.id);
	}

	static String filenameFromDisposition(String disposition) {
		if (disposition == null || disposition.length() == 0) {
			return "";
		}
		Matcher star = FILENAME_STAR.matcher(disposition);
		if (star.find()) {
			return sanitizeFilename(star.group(1).trim());
		}
		Matcher quoted = FILENAME_QUOTED.matcher(disposition);
		if (quoted.find()) {
			return sanitizeFilename(quoted.group(1).trim());
		}
		Matcher plain = FILENAME_PLAIN.matcher(disposition);
		if (plain.find()) {
			return sanitizeFilename(plain.group(1).trim());
		}
		return "";
	}

	static String basenameFromUrl(String url) {
		if (url == null || url.length() == 0) {
			return "download";
		}
		try {
			String path = new URL(url).getPath();
			if (path == null || path.length() == 0 || path.equals("/")) {
				return "download";
			}
			int slash = path.lastIndexOf('/');
			String base = slash >= 0 ? path.substring(slash + 1) : path;
			base = sanitizeFilename(base);
			return base.length() > 0 ? base : "download";
		} catch (Throwable t) {
			return "download";
		}
	}

	private static String sanitizeFilename(String name) {
		if (name == null) {
			return "";
		}
		String cleaned = name.replaceAll("[\\\\/:*?\"<>|]", "_").trim();
		if (cleaned.equals(".") || cleaned.equals("..")) {
			return "download";
		}
		return cleaned;
	}

	private static final class Job {
		int id;
		String uri;
		String userAgent;
		String suggested;
		String mime;
		long contentLength;
		String destPath;
		boolean overwrite;
		boolean started;
		final AtomicBoolean cancelled = new AtomicBoolean(false);
		volatile HttpURLConnection connection;
	}
}
