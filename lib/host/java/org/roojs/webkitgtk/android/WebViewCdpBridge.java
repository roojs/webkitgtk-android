package org.roojs.webkitgtk.android;

import android.os.Build;
import android.os.Process;
import android.util.Log;
import android.webkit.WebView;

import java.io.Closeable;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Loopback TCP proxy to Chromium WebView devtools ({@code @webview_devtools_remote_<pid>}).
 * Lets same-process clients use {@code WEBKIT_INSPECTOR_SERVER} / CDP on {@code 127.0.0.1:port}.
 */
public final class WebViewCdpBridge {
	private static final String TAG = "WebViewCdpBridge";

	private static final AtomicBoolean running = new AtomicBoolean(false);
	private static volatile int boundPort = -1;
	private static volatile boolean automationAllowed = false;
	private static Thread acceptThread;
	private static ServerSocket serverSocket;

	private WebViewCdpBridge() {
	}

	public static void setAutomationAllowed(boolean allowed) {
		automationAllowed = allowed;
		Log.i(TAG, "setAutomationAllowed=" + allowed);
		if (allowed) {
			enableDebugging();
		}
	}

	public static boolean isAutomationAllowed() {
		return automationAllowed;
	}

	public static void enableDebugging() {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
			WebView.setWebContentsDebuggingEnabled(true);
			Log.i(TAG, "setWebContentsDebuggingEnabled(true)");
		}
	}

	/**
	 * Parse {@code WEBKIT_INSPECTOR_SERVER} (host:port or bare port). Returns 0 when unset.
	 */
	public static int inspectorPortFromEnv() {
		String env = System.getenv("WEBKIT_INSPECTOR_SERVER");
		if (env == null || env.isEmpty()) {
			return 0;
		}
		int colon = env.lastIndexOf(':');
		String portStr = colon >= 0 ? env.substring(colon + 1) : env;
		try {
			int port = Integer.parseInt(portStr.trim());
			return port > 0 && port <= 65535 ? port : 0;
		} catch (NumberFormatException e) {
			return 0;
		}
	}

	/**
	 * Start {@code 127.0.0.1:<port>} → abstract devtools socket. Idempotent.
	 *
	 * @param preferredPort from env or 0 for ephemeral
	 * @return bound port, or -1 on failure
	 */
	public static int startLoopbackProxy(int preferredPort) {
		if (running.get()) {
			return boundPort;
		}
		enableDebugging();
		try {
			ServerSocket server;
			if (preferredPort > 0) {
				server = new ServerSocket(preferredPort, 50, InetAddress.getByName("127.0.0.1"));
			} else {
				server = new ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"));
			}
			serverSocket = server;
			boundPort = server.getLocalPort();
			running.set(true);
			acceptThread = new Thread(WebViewCdpBridge::acceptLoop, "wka-cdp-proxy");
			acceptThread.setDaemon(true);
			acceptThread.start();
			Log.i(TAG, "CDP loopback proxy 127.0.0.1:" + boundPort);
			return boundPort;
		} catch (IOException e) {
			Log.e(TAG, "startLoopbackProxy failed", e);
			running.set(false);
			boundPort = -1;
			return -1;
		}
	}

	public static int getBoundPort() {
		return boundPort;
	}

	private static void acceptLoop() {
		try {
			while (running.get() && serverSocket != null && !serverSocket.isClosed()) {
				final Socket client = serverSocket.accept();
				Thread t = new Thread(() -> proxyOne(client), "wka-cdp-proxy-client");
				t.setDaemon(true);
				t.start();
			}
		} catch (IOException e) {
			if (running.get()) {
				Log.w(TAG, "acceptLoop ended", e);
			}
		}
	}

	private static void proxyOne(Socket client) {
		LocalSocket devtools = null;
		try {
			devtools = connectDevtoolsSocket();
			final InputStream cin = client.getInputStream();
			final OutputStream cout = client.getOutputStream();
			final InputStream din = devtools.getInputStream();
			final OutputStream dout = devtools.getOutputStream();
			Thread up = new Thread(() -> pump(cin, dout), "wka-cdp-up");
			Thread down = new Thread(() -> pump(din, cout), "wka-cdp-down");
			up.start();
			down.start();
			up.join();
			down.join();
		} catch (Exception e) {
			Log.w(TAG, "proxyOne failed", e);
		} finally {
			closeQuietly(client);
			closeQuietly(devtools);
		}
	}

	private static LocalSocket connectDevtoolsSocket() throws IOException {
		int pid = Process.myPid();
		String[] names = {
			"webview_devtools_remote_" + pid,
			"webview_devtools_remote",
		};
		IOException last = null;
		for (String name : names) {
			LocalSocket sock = new LocalSocket();
			try {
				sock.connect(new LocalSocketAddress(name, LocalSocketAddress.Namespace.ABSTRACT));
				Log.d(TAG, "connected devtools @" + name);
				return sock;
			} catch (IOException e) {
				last = e;
				closeQuietly(sock);
			}
		}
		throw last != null ? last : new IOException("no devtools abstract socket");
	}

	private static void pump(InputStream in, OutputStream out) {
		byte[] buf = new byte[8192];
		try {
			int n;
			while ((n = in.read(buf)) >= 0) {
				if (n == 0) {
					continue;
				}
				out.write(buf, 0, n);
				out.flush();
			}
		} catch (IOException ignored) {
		}
	}

	private static void closeQuietly(Closeable c) {
		if (c == null) {
			return;
		}
		try {
			c.close();
		} catch (IOException ignored) {
		}
	}
}
