/* webkitgtk-android host API — JNI bridge to WebViewHost.java */

#ifndef WEBKITGTK_ANDROID_HOST_API_H
#define WEBKITGTK_ANDROID_HOST_API_H

#include <glib.h>
#include <gtk/gtk.h>

G_BEGIN_DECLS

typedef void (*WkaLoadChangedCb) (gpointer user_data, gint load_event);
typedef void (*WkaTitleCb) (gpointer user_data);

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

gboolean wka_widget_bounds_xywh (GtkWidget *widget,
                                 int *x,
                                 int *y,
                                 int *width,
                                 int *height);

G_END_DECLS

#endif /* WEBKITGTK_ANDROID_HOST_API_H */
