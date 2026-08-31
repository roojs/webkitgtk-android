/* Phase 0 CDP spike — Input.dispatchMouseEvent + Input.insertText via loopback bridge. */

using Soup;

const string CDP_SPIKE_FILL = "cdp-spike-fill";
const string CDP_SPIKE_HTML = """
<!DOCTYPE html>
<html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
</head><body style="margin:0;padding:24px;font-family:sans-serif">
<label for="q">Query</label><br>
<input id="q" type="text" style="width:90%%;height:56px;font-size:20px;margin-top:12px">
</body></html>
""";

public string cdp_spike_page_uri ()
{
	return "data:text/html;charset=utf-8," + Uri.escape_string (CDP_SPIKE_HTML, null);
}

public async bool run_cdp_spike_async (uint16 port, WebKitGtkAndroid.WebView web) throws GLib.Error
{
	var base_url = "http://127.0.0.1:%u".printf (port);
	var session = new Soup.Session ();
	session.set_timeout (8);

	/* DevTools may lag WebView attach — retry /json/version. */
	var version_ok = false;
	for (var attempt = 0; attempt < 40; attempt++) {
		try {
			var ver_msg = new Soup.Message ("GET", "%s/json/version".printf (base_url));
			yield session.send_and_read_async (ver_msg, GLib.Priority.DEFAULT, null);
			if (ver_msg.status_code == 200) {
				print ("cdp-spike: /json/version OK\n");
				version_ok = true;
				break;
			}
		} catch (GLib.Error e) {
			print ("cdp-spike: version wait (%d) %s\n", attempt, e.message);
		}
		yield cdp_spike_delay_ms (250);
	}
	if (!version_ok) {
		throw new GLib.IOError.FAILED ("CDP /json/version not ready on %s", base_url);
	}

	var list_msg = new Soup.Message ("GET", "%s/json/list".printf (base_url));
	var list_bytes = yield session.send_and_read_async (list_msg, GLib.Priority.DEFAULT, null);
	if (list_msg.status_code != 200) {
		throw new GLib.IOError.FAILED ("CDP /json/list HTTP %u", list_msg.status_code);
	}
	var ws_url = cdp_pick_page_ws_url ((string) list_bytes.get_data ());
	print ("cdp-spike: ws %s\n", ws_url);

	var http_ws = ws_url.replace ("ws://", "http://").replace ("wss://", "https://");
	var ws_msg = new Soup.Message ("GET", http_ws);
	var conn = yield session.websocket_connect_async (
		ws_msg, null, null, GLib.Priority.DEFAULT, null
	);

	/* Locate #q center in viewport coordinates. */
	var locate_expr = (
		"(() => {"
		+ "  const q = document.querySelector('#q');"
		+ "  if (!q) return { ok: false, err: 'no #q' };"
		+ "  const r = q.getBoundingClientRect();"
		+ "  return { ok: true, x: Math.round(r.left + r.width / 2),"
		+ "           y: Math.round(r.top + r.height / 2) };"
		+ "})()"
	);
	var locate = yield cdp_eval_object (conn, locate_expr);
	if (!cdp_json_bool (locate, "ok", false)) {
		throw new GLib.IOError.FAILED ("CDP locate #q failed");
	}
	var click_x = cdp_json_int (locate, "x", 0);
	var click_y = cdp_json_int (locate, "y", 0);
	print ("cdp-spike: click center %d,%d\n", click_x, click_y);

	yield cdp_mouse_click (conn, click_x, click_y);
	yield cdp_insert_text (conn, CDP_SPIKE_FILL);

	var verify = yield cdp_eval_object (conn,
		"(() => { const q = document.querySelector('#q');"
		+ " return { ok: !!q, value: q ? q.value : '' }; })()"
	);
	conn.close (Soup.WebsocketCloseCode.NORMAL, "done");

	var got = cdp_json_string (verify, "value", "");
	print ("cdp-spike: field value=%s\n", got);
	if (got != CDP_SPIKE_FILL) {
		throw new GLib.IOError.FAILED (
			"CDP fill did not stick (expected %s got %s)", CDP_SPIKE_FILL, got
		);
	}
	return true;
}

private async void cdp_spike_delay_ms (uint ms)
{
	Timeout.add (ms, () => {
		cdp_spike_delay_ms.callback ();
		return false;
	});
	yield;
}

private async string cdp_eval_object (Soup.WebsocketConnection conn, string expression) throws GLib.Error
{
	var req_id = cdp_next_id ();
	var payload = (
		"{\"id\":%d,\"method\":\"Runtime.evaluate\",\"params\":{"
		+ "\"expression\":%s,\"returnByValue\":true}}"
	).printf (req_id, cdp_json_quote (expression));
	var reply = yield cdp_wait_reply_async (conn, payload, req_id);
	if (cdp_json_has_key (reply, "error")) {
		throw new GLib.IOError.FAILED ("CDP Runtime.evaluate error");
	}
	var result = cdp_json_extract_object (reply, "result");
	if (result == null) {
		throw new GLib.IOError.FAILED ("CDP evaluate missing result");
	}
	var inner = cdp_json_extract_object (result, "result");
	if (inner == null) {
		throw new GLib.IOError.FAILED ("CDP evaluate missing inner result");
	}
	var val = cdp_json_extract_object (inner, "value");
	if (val == null) {
		throw new GLib.IOError.FAILED ("CDP evaluate missing value object");
	}
	return val;
}

private async void cdp_mouse_click (
	Soup.WebsocketConnection conn,
	int x,
	int y
) throws GLib.Error {
	yield cdp_send_ok (conn, "Input.dispatchMouseEvent", """
		{"type":"mouseMoved","x":%d,"y":%d,"button":"none","pointerType":"mouse"}
		""".printf (x, y));
	yield cdp_send_ok (conn, "Input.dispatchMouseEvent", """
		{"type":"mousePressed","x":%d,"y":%d,"button":"left","buttons":1,"clickCount":1,"pointerType":"mouse"}
		""".printf (x, y));
	yield cdp_send_ok (conn, "Input.dispatchMouseEvent", """
		{"type":"mouseReleased","x":%d,"y":%d,"button":"left","clickCount":1,"pointerType":"mouse"}
		""".printf (x, y));
}

private async void cdp_insert_text (Soup.WebsocketConnection conn, string text) throws GLib.Error
{
	yield cdp_send_ok (conn, "Input.insertText", "{\"text\":%s}".printf (cdp_json_quote (text)));
}

private string cdp_json_quote (string s)
{
	var sb = new StringBuilder ("\"");
	foreach (unowned var c in s.to_utf8 ()) {
		if (c == '\\') {
			sb.append ("\\\\");
		} else if (c == '"') {
			sb.append ("\\\"");
		} else if (c == '\n') {
			sb.append ("\\n");
		} else if (c == '\r') {
			sb.append ("\\r");
		} else if (c == '\t') {
			sb.append ("\\t");
		} else {
			sb.append_unichar (c);
		}
	}
	sb.append_c ('"');
	return sb.str;
}

private int cdp_msg_id = 0;

private int cdp_next_id ()
{
	cdp_msg_id++;
	return cdp_msg_id;
}

private async void cdp_send_ok (
	Soup.WebsocketConnection conn,
	string method,
	string params_json
) throws GLib.Error {
	var id = cdp_next_id ();
	var body = "{\"id\":%d,\"method\":\"%s\",\"params\":%s}".printf (id, method, params_json);
	var reply = yield cdp_wait_reply_async (conn, body, id);
	if (cdp_json_has_key (reply, "error")) {
		var msg = cdp_json_string (cdp_json_extract_object (reply, "error") ?? "", "message", "unknown");
		throw new GLib.IOError.FAILED ("CDP %s failed: %s", method, msg);
	}
}

private async string cdp_wait_reply_async (
	Soup.WebsocketConnection conn,
	string request_text,
	int expect_id
) throws GLib.Error {
	GLib.SourceFunc resume = cdp_wait_reply_async.callback;
	string? reply = null;
	GLib.Error? err = null;
	ulong mid = 0;
	ulong eid = 0;
	uint tid = 0;

	mid = conn.message.connect ((type, message) => {
		if (type != Soup.WebsocketDataType.TEXT) {
			return;
		}
		var text = (string) message.get_data ();
		if (!cdp_reply_matches_id (text, expect_id)) {
			return;
		}
		reply = text;
		Idle.add (() => {
			resume ();
			return false;
		});
	});
	eid = conn.error.connect ((e) => {
		err = e;
		Idle.add (() => {
			resume ();
			return false;
		});
	});
	tid = Timeout.add_seconds (12, () => {
		if (reply == null && err == null) {
			err = new GLib.IOError.TIMED_OUT ("CDP reply timeout");
			resume ();
		}
		return false;
	});

	conn.send_text (request_text);
	yield;

	conn.disconnect (mid);
	conn.disconnect (eid);
	if (tid != 0) {
		Source.remove (tid);
	}
	if (err != null) {
		throw err;
	}
	if (reply == null) {
		throw new GLib.IOError.FAILED ("CDP no reply");
	}
	return reply;
}

private bool cdp_reply_matches_id (string json, int expect_id)
{
	var needle = "\"id\":%d".printf (expect_id);
	var alt = "\"id\": %d".printf (expect_id);
	return json.contains (needle) || json.contains (alt);
}

private string cdp_pick_page_ws_url (string list_json) throws GLib.Error
{
	var idx = 0;
	while (true) {
		var key = list_json.index_of ("\"webSocketDebuggerUrl\"", idx);
		if (key < 0) {
			break;
		}
		var colon = list_json.index_of (":", key);
		var q1 = list_json.index_of ("\"", colon + 1);
		var q2 = list_json.index_of ("\"", q1 + 1);
		if (q1 >= 0 && q2 > q1) {
			var ws = list_json.substring (q1 + 1, q2 - q1 - 1);
			if (ws.has_prefix ("ws://") || ws.has_prefix ("wss://")) {
				return ws;
			}
		}
		idx = key + 1;
	}
	throw new GLib.IOError.FAILED ("CDP no page webSocketDebuggerUrl in /json/list");
}

private bool cdp_json_has_key (string json, string key)
{
	return json.index_of ("\"%s\"".printf (key)) >= 0;
}

private string? cdp_json_extract_object (string json, string key)
{
	var key_pos = json.index_of ("\"%s\"".printf (key));
	if (key_pos < 0) {
		return null;
	}
	var colon = json.index_of (":", key_pos);
	if (colon < 0) {
		return null;
	}
	var i = colon + 1;
	while (i < json.length && (json[i] == ' ' || json[i] == '\t' || json[i] == '\n')) {
		i++;
	}
	if (i >= json.length) {
		return null;
	}
	if (json[i] == '"') {
		var end = json.index_of ("\"", i + 1);
		return end > i ? json.substring (i + 1, end - i - 1) : null;
	}
	if (json[i] == '{') {
		return cdp_json_slice_balanced (json, i, '{', '}');
	}
	return cdp_json_extract_literal (json, i);
}

private string cdp_json_extract_literal (string json, int start)
{
	var sb = new StringBuilder ();
	for (var i = start; i < json.length; i++) {
		var c = json[i];
		if (c == ',' || c == '}' || c == ']' || c == ' ' || c == '\t' || c == '\n') {
			break;
		}
		sb.append_c (c);
	}
	return sb.str;
}

private string? cdp_json_slice_balanced (string json, int start, unichar open, unichar close)
{
	var depth = 0;
	for (var i = start; i < json.length; i++) {
		var c = json[i];
		if (c == open) {
			depth++;
		} else if (c == close) {
			depth--;
			if (depth == 0) {
				return json.substring (start, i - start + 1);
			}
		} else if (c == '"') {
			i = cdp_json_skip_string (json, i);
		}
	}
	return null;
}

private int cdp_json_skip_string (string json, int start)
{
	for (var i = start + 1; i < json.length; i++) {
		if (json[i] == '\\') {
			i++;
			continue;
		}
		if (json[i] == '"') {
			return i;
		}
	}
	return json.length - 1;
}

private bool cdp_json_bool (string json, string key, bool fallback)
{
	var obj = cdp_json_extract_object (json, key);
	if (obj == null) {
		return fallback;
	}
	if (obj == "true") {
		return true;
	}
	if (obj == "false") {
		return false;
	}
	return fallback;
}

private int cdp_json_int (string json, string key, int fallback)
{
	var raw = cdp_json_extract_object (json, key);
	if (raw == null) {
		return fallback;
	}
	int val = fallback;
	if (int.try_parse (raw, out val)) {
		return val;
	}
	return fallback;
}

private string cdp_json_string (string json, string key, string fallback)
{
	var raw = cdp_json_extract_object (json, key);
	return raw ?? fallback;
}

public uint16 cdp_spike_prepare_port () throws GLib.Error
{
	var probe = new GLib.Socket (GLib.SocketFamily.IPV4, GLib.SocketType.STREAM, GLib.SocketProtocol.TCP);
	probe.bind (new GLib.InetSocketAddress (new GLib.InetAddress.loopback (GLib.SocketFamily.IPV4), 0), true);
	var port = (uint16) ((GLib.InetSocketAddress) probe.get_local_address ()).get_port ();
	probe.close ();
	Environment.set_variable ("WEBKIT_INSPECTOR_SERVER", "127.0.0.1:%u".printf (port), true);
	print ("cdp-spike: WEBKIT_INSPECTOR_SERVER=127.0.0.1:%u\n", port);
	return port;
}
