/* Map GTK widget bounds to Android surface-local pixels for WebViewHost.
 * Caller (Java) adds the GTK SurfaceView's window origin. */

#include "webkitgtk-android-host-api.h"

#include <math.h>

gboolean
wka_widget_bounds_xywh (GtkWidget *widget, int *x, int *y, int *width, int *height)
{
	GtkWidget *root;
	GdkSurface *surface;
	graphene_rect_t bounds;
	int scale;
	int w;
	int h;

	g_return_val_if_fail (GTK_IS_WIDGET (widget), FALSE);
	g_return_val_if_fail (x != NULL && y != NULL && width != NULL && height != NULL, FALSE);

	root = gtk_widget_get_root (widget);
	if (root == NULL || !GTK_IS_NATIVE (root)) {
		return FALSE;
	}

	/* Bounds relative to the native root (= Android SurfaceView content). */
	if (!gtk_widget_compute_bounds (widget, root, &bounds)) {
		return FALSE;
	}

	surface = gtk_native_get_surface (GTK_NATIVE (root));
	scale = surface != NULL ? gdk_surface_get_scale_factor (surface) : 1;

	*x = (int) round (bounds.origin.x * (double) scale);
	*y = (int) round (bounds.origin.y * (double) scale);
	w = (int) round (bounds.size.width * (double) scale);
	h = (int) round (bounds.size.height * (double) scale);

	if (w <= 0 || h <= 0) {
		return FALSE;
	}

	*width = w;
	*height = h;
	return TRUE;
}
