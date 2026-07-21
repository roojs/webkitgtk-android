/* Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 */

/**
 * Minimal WebKit URIRequest stand-in (uri only — enough for OLLMchat).
 */

namespace WebKitGtkAndroid
{
	public class URIRequest : GLib.Object
	{
		public string uri { get; construct; }

		public URIRequest (string uri)
		{
			Object (uri: uri);
		}
	}
}
