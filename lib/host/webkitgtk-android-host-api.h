/* webkitgtk-android host API — JNI bridge to WebViewHost.java */

#ifndef WEBKITGTK_ANDROID_HOST_API_H
#define WEBKITGTK_ANDROID_HOST_API_H

#include <glib.h>
#include <gtk/gtk.h>

G_BEGIN_DECLS

typedef void (*WkaLoadChangedCb) (gpointer user_data, gint load_event);
typedef void (*WkaTitleCb) (gpointer user_data);
/* rgba NULL / width<=0 clears freeze picture. Bytes are R8G8B8A8, stride = width*4. */
typedef void (*WkaFreezeFrameCb) (GBytes *rgba, int width, int height, gpointer user_data);

gboolean wka_host_create_with_xywh (GtkWidget *widget,
                                    int x,
                                    int y,
                                    int width,
                                    int height,
                                    const char *url);
void wka_host_set_bounds_xywh (int x, int y, int width, int height);
gboolean wka_host_navigate (const char *url);
void wka_host_go_back (void);
void wka_host_go_forward (void);
void wka_host_reload (void);
void wka_host_stop (void);
gboolean wka_host_can_go_back (void);
gboolean wka_host_can_go_forward (void);
void wka_host_destroy (void);
gboolean wka_host_is_ready (void);
const char *wka_host_get_uri (void);
const char *wka_host_get_title (void);
void wka_host_put_is_visible (gboolean visible);
void wka_host_set_virtual_size (int width, int height);
void wka_host_use_display_size (GtkWidget *widget);
void wka_host_set_event_handlers (WkaLoadChangedCb load_changed,
                                  WkaTitleCb title_changed,
                                  gpointer user_data);
void wka_host_set_freeze_frame_handler (WkaFreezeFrameCb cb);
gboolean wka_host_freeze (void);
gboolean wka_host_resume (void);

gboolean wka_widget_bounds_xywh (GtkWidget *widget,
                                 int *x,
                                 int *y,
                                 int *width,
                                 int *height);

/* ---- Accessibility (mirror webview2-gtk host a11y) ----
 * Coordinates: screen pixels. Call from GTK/UI thread.
 * Node ids valid until the next a11y_walk (cache replaced).
 */
typedef struct wka_a11y_node {
	int id;
	int parent_id;
	int x;
	int y;
	int w;
	int h;
	char *name;
	char *role;
	char *value;
	char *uri; /* http(s) when exposed; else empty */
	gboolean can_invoke;
	gboolean can_set_value;
} wka_a11y_node;

typedef void (*WkaA11yForeachCb) (
	int id,
	int parent_id,
	int x,
	int y,
	int w,
	int h,
	const char *name,
	const char *role,
	const char *value,
	const char *uri,
	gboolean can_invoke,
	gboolean can_set_value,
	gpointer user_data
);

/* Android-only: wake Chromium a11y provider without TalkBack. */
gboolean wka_host_a11y_ensure (void);
gboolean wka_host_a11y_walk (wka_a11y_node **nodes_out, gsize *count_out);
void wka_host_a11y_nodes_free (wka_a11y_node *nodes, gsize count);
gboolean wka_host_a11y_walk_foreach (WkaA11yForeachCb cb, gpointer user_data);
gboolean wka_host_a11y_invoke (int id);
gboolean wka_host_a11y_set_value (int id, const char *utf8);
gboolean wka_host_a11y_focus (int id);

/* ---- Cookies (android.webkit.CookieManager; WebKitGTK-shaped Vala) ----
 * get: Cookie header "name=value; name2=value2" (caller g_free).
 * add: name/value/domain/path + flags → setCookie + flush.
 */
gboolean wka_host_get_cookies (const char *uri, char **cookies_text_out);
gboolean wka_host_add_cookie (const char *name,
                              const char *value,
                              const char *domain,
                              const char *path,
                              gboolean http_only,
                              gboolean secure);

G_END_DECLS

#endif /* WEBKITGTK_ANDROID_HOST_API_H */
