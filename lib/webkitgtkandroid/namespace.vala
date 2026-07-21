/* Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

namespace WebKitGtkAndroid
{
	/**
	 * Load lifecycle events — same names and order as WebKit.LoadEvent.
	 */
	public enum LoadEvent
	{
		STARTED,
		REDIRECTED,
		COMMITTED,
		FINISHED
	}

	public enum CookieAcceptPolicy
	{
		ALWAYS,
		NEVER,
		NO_THIRD_PARTY
	}

	public enum CookiePersistentStorage
	{
		TEXT,
		SQLITE
	}

	/** WebKitGTK-shaped subset — used by cookie / network / download failures. */
	public errordomain NetworkError
	{
		FAILED,
		TRANSPORT,
		UNKNOWN_PROTOCOL,
		CANCELLED,
		FILE_DOES_NOT_EXIST
	}
}
