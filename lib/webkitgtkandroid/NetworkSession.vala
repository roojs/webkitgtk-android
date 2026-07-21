/* Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

[CCode (cheader_filename = "webkitgtk-android-host-api.h", has_target = false)]
public delegate void WkaDownloadStartedCb (
	int id,
	string uri,
	string suggested_filename,
	string mime_type,
	int64 content_length,
	void* user_data
);
[CCode (cheader_filename = "webkitgtk-android-host-api.h", has_target = false)]
public delegate void WkaDownloadProgressCb (int id, uint64 received, void* user_data);
[CCode (cheader_filename = "webkitgtk-android-host-api.h", has_target = false)]
public delegate void WkaDownloadFinishedCb (int id, void* user_data);
[CCode (cheader_filename = "webkitgtk-android-host-api.h", has_target = false)]
public delegate void WkaDownloadFailedCb (int id, string message, void* user_data);
[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern void wka_host_set_download_handlers (
	WkaDownloadStartedCb? started,
	WkaDownloadProgressCb? progress,
	WkaDownloadFinishedCb? finished,
	WkaDownloadFailedCb? failed,
	void* user_data
);

namespace WebKitGtkAndroid
{
	/**
	 * WebKitGTK-shaped network session — cookies + download_started.
	 */
	public class NetworkSession : GLib.Object
	{
		private static bool handlers_installed = false;
		private static weak NetworkSession? active_session = null;

		private CookieManager _cookie_manager = new CookieManager ();
		private GenericArray<Download> downloads = new GenericArray<Download> ();

		public signal void download_started (Download download);

		public NetworkSession ()
		{
			NetworkSession.active_session = this;
			NetworkSession.ensure_handlers ();
		}

		public CookieManager get_cookie_manager ()
		{
			return this._cookie_manager;
		}

		internal void register_download (Download download, int host_id)
		{
			this.downloads.add (download);
		}

		internal void unregister_download (int host_id)
		{
			for (var i = 0; i < this.downloads.length; i++) {
				if (this.downloads[i].host_id_internal () == host_id) {
					this.downloads.remove_index (i);
					return;
				}
			}
		}

		internal Download? lookup_download (int host_id)
		{
			for (var i = 0; i < this.downloads.length; i++) {
				if (this.downloads[i].host_id_internal () == host_id) {
					return this.downloads[i];
				}
			}
			return null;
		}

		internal void emit_download_started (Download download)
		{
			this.download_started (download);
			download.schedule_decide_destination ();
		}

		private static void ensure_handlers ()
		{
			if (NetworkSession.handlers_installed) {
				return;
			}
			NetworkSession.handlers_installed = true;
			wka_host_set_download_handlers (
				NetworkSession.on_host_started,
				NetworkSession.on_host_progress,
				NetworkSession.on_host_finished,
				NetworkSession.on_host_failed,
				null
			);
		}

		private static void on_host_started (
			int id,
			string uri,
			string suggested_filename,
			string mime_type,
			int64 content_length,
			void* user_data
		)
		{
			var session = NetworkSession.active_session;
			if (session == null) {
				wka_host_download_cancel (id);
				return;
			}
			var dl = new Download (
				session,
				id,
				uri,
				suggested_filename,
				mime_type,
				content_length
			);
			session.register_download (dl, id);
			session.emit_download_started (dl);
		}

		private static void on_host_progress (int id, uint64 received, void* user_data)
		{
			var session = NetworkSession.active_session;
			if (session == null) {
				return;
			}
			var dl = session.lookup_download (id);
			if (dl != null) {
				dl.on_progress (received);
			}
		}

		private static void on_host_finished (int id, void* user_data)
		{
			var session = NetworkSession.active_session;
			if (session == null) {
				return;
			}
			var dl = session.lookup_download (id);
			if (dl != null) {
				dl.on_finished ();
			}
		}

		private static void on_host_failed (int id, string message, void* user_data)
		{
			var session = NetworkSession.active_session;
			if (session == null) {
				return;
			}
			var dl = session.lookup_download (id);
			if (dl != null) {
				dl.on_failed_message (message);
			}
		}
	}
}
