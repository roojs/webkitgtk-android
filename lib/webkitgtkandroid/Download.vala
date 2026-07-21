/* Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern int wka_host_download_create (string uri);
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern bool wka_host_download_start (int id, string dest_path, bool overwrite);
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern void wka_host_download_cancel (int id);

namespace WebKitGtkAndroid
{
	/**
	 * WebKitGTK-shaped download — hold until {@link set_destination} / {@link cancel}.
	 */
	public class Download : GLib.Object
	{
		private weak NetworkSession session;
		private int host_id;
		private URIRequest request;
		private string suggested_filename;
		private string mime_type;
		private int64 content_length;
		private uint64 received_length;
		private bool allow_overwrite;
		private bool destination_set;
		private bool terminal;
		private bool decide_scheduled;

		internal Download (NetworkSession session,
			int host_id,
			string uri,
			string suggested_filename,
			string mime_type,
			int64 content_length)
		{
			this.session = session;
			this.host_id = host_id;
			this.request = new URIRequest (uri);
			this.suggested_filename = suggested_filename != null && suggested_filename != ""
				? suggested_filename : "download";
			this.mime_type = mime_type != null ? mime_type : "";
			this.content_length = content_length;
		}

		public URIRequest get_request ()
		{
			return this.request;
		}

		public string get_uri ()
		{
			return this.request.uri;
		}

		public string? get_mime_type ()
		{
			return this.mime_type != "" ? this.mime_type : null;
		}

		public int64 get_estimated_content_length ()
		{
			return this.content_length;
		}

		public uint64 get_received_data_length ()
		{
			return this.received_length;
		}

		/**
		 * Return true to own destination (may call {@link set_destination} later).
		 */
		public signal bool decide_destination (string? suggested_filename);

		public signal void received_data (uint64 data_length);

		public signal void finished ();

		public signal void failed (GLib.Error error);

		public void set_allow_overwrite (bool allow)
		{
			this.allow_overwrite = allow;
		}

		public void set_destination (string destination_uri_or_path)
		{
			if (this.terminal || this.destination_set) {
				return;
			}
			var path = destination_uri_or_path.strip ();
			if (path == "") {
				this.emit_failed (new NetworkError.FAILED ("empty destination"));
				return;
			}
			this.destination_set = true;
			if (this.host_id <= 0
					|| !wka_host_download_start (this.host_id, path, this.allow_overwrite)) {
				this.emit_failed (new NetworkError.FAILED ("download start failed"));
			}
		}

		public void cancel ()
		{
			if (this.terminal) {
				return;
			}
			if (this.host_id > 0) {
				wka_host_download_cancel (this.host_id);
			}
			this.emit_failed (new NetworkError.CANCELLED ("Download cancelled"));
		}

		internal int host_id_internal ()
		{
			return this.host_id;
		}

		internal void schedule_decide_destination ()
		{
			if (this.decide_scheduled || this.terminal) {
				return;
			}
			this.decide_scheduled = true;
			Idle.add (() => {
				if (this.terminal || this.destination_set) {
					return false;
				}
				var handled = this.decide_destination (this.suggested_filename);
				if (!handled && !this.destination_set && !this.terminal) {
					this.cancel ();
				}
				return false;
			});
		}

		internal void on_progress (uint64 received)
		{
			if (this.terminal) {
				return;
			}
			var delta = received >= this.received_length
				? received - this.received_length : 0;
			this.received_length = received;
			this.received_data (delta);
		}

		internal void on_finished ()
		{
			if (this.terminal) {
				return;
			}
			this.terminal = true;
			this.session.unregister_download (this.host_id);
			this.finished ();
		}

		internal void on_failed_message (string message)
		{
			this.emit_failed (new NetworkError.FAILED ("%s", message));
		}

		private void emit_failed (GLib.Error error)
		{
			if (this.terminal) {
				return;
			}
			this.terminal = true;
			this.session.unregister_download (this.host_id);
			this.failed (error);
		}
	}
}
