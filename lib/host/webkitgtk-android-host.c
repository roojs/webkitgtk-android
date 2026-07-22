/* JNI host for org.roojs.webkitgtk.android.WebViewHost */

#include "webkitgtk-android-host-api.h"

#include <android/log.h>
#include <jni.h>
#include <string.h>

#include <gdk/android/gdkandroid.h>

#define WKA_LOG_TAG "WebViewHost"

static JavaVM *wka_vm = NULL;
static jclass wka_host_cls_global = NULL;
static WkaLoadChangedCb wka_load_cb = NULL;
static WkaTitleCb wka_title_cb = NULL;
static WkaFreezeFrameCb wka_freeze_cb = NULL;
static WkaDocumentResponseCb wka_doc_response_cb = NULL;
static gpointer wka_cb_data = NULL;
static gpointer wka_doc_response_data = NULL;
static char wka_uri_buf[4096];
static char wka_title_buf[1024];
static GBytes *wka_freeze_bytes = NULL;
static int wka_freeze_w = 0;
static int wka_freeze_h = 0;

JNIEXPORT void JNICALL
Java_org_roojs_webkitgtk_android_WebViewHost_nativeLoadChanged (JNIEnv *env,
                                                                jclass cls,
                                                                jint load_event);
JNIEXPORT void JNICALL
Java_org_roojs_webkitgtk_android_WebViewHost_nativeTitleChanged (JNIEnv *env, jclass cls);
JNIEXPORT void JNICALL
Java_org_roojs_webkitgtk_android_WebViewHost_nativeFreezeFrame (JNIEnv *env,
                                                                jclass cls,
                                                                jbyteArray rgba,
                                                                jint width,
                                                                jint height);
JNIEXPORT void JNICALL
Java_org_roojs_webkitgtk_android_WebViewHost_nativeDocumentResponse (JNIEnv *env,
                                                                     jclass cls,
                                                                     jint status,
                                                                     jobjectArray jnames,
                                                                     jobjectArray jvalues);

JNIEXPORT jint
JNI_OnLoad (JavaVM *vm, void *reserved)
{
	(void) reserved;
	wka_vm = vm;
	return JNI_VERSION_1_6;
}

/*
 * Pixiewood loads the app .so via g_module_open (dlopen), not
 * System.loadLibrary — JNI_OnLoad usually never runs. Use GDK's
 * public JNIEnv (same one that created Activity local refs).
 */
static JNIEnv *
wka_jni_env (void)
{
	GdkDisplay *display;
	JNIEnv *env = NULL;

	display = gdk_display_get_default ();
	if (display != NULL && GDK_IS_ANDROID_DISPLAY (display)) {
		env = gdk_android_display_get_env (display);
		if (env != NULL) {
			if (wka_vm == NULL) {
				(*env)->GetJavaVM (env, &wka_vm);
			}
			return env;
		}
	}

	if (wka_vm == NULL) {
		__android_log_print (ANDROID_LOG_ERROR, WKA_LOG_TAG,
			"no JNIEnv (GDK Android display not ready)");
		return NULL;
	}
	if ((*wka_vm)->GetEnv (wka_vm, (void **) &env, JNI_VERSION_1_6) == JNI_OK) {
		return env;
	}
	if ((*wka_vm)->AttachCurrentThread (wka_vm, &env, NULL) != JNI_OK) {
		__android_log_print (ANDROID_LOG_ERROR, WKA_LOG_TAG, "AttachCurrentThread failed");
		return NULL;
	}
	return env;
}

/* Shared with webkitgtk-android-a11y.c */
JNIEnv *
wka_get_env (void)
{
	return wka_jni_env ();
}

jclass
wka_get_host_class (void)
{
	return wka_host_cls_global;
}

static jclass
wka_load_class (JNIEnv *env, jobject activity, const char *name)
{
	jclass activity_cls;
	jmethodID get_cl;
	jobject loader;
	jclass loader_cls;
	jmethodID load_class;
	jstring jname;
	jclass result;

	activity_cls = (*env)->GetObjectClass (env, activity);
	get_cl = (*env)->GetMethodID (env, activity_cls, "getClassLoader",
		"()Ljava/lang/ClassLoader;");
	loader = (*env)->CallObjectMethod (env, activity, get_cl);
	loader_cls = (*env)->GetObjectClass (env, loader);
	load_class = (*env)->GetMethodID (env, loader_cls, "loadClass",
		"(Ljava/lang/String;)Ljava/lang/Class;");
	jname = (*env)->NewStringUTF (env, name);
	result = (jclass) (*env)->CallObjectMethod (env, loader, load_class, jname);
	(*env)->DeleteLocalRef (env, jname);
	(*env)->DeleteLocalRef (env, loader_cls);
	(*env)->DeleteLocalRef (env, loader);
	(*env)->DeleteLocalRef (env, activity_cls);
	return result;
}

static jobject
wka_activity_for_widget (GtkWidget *widget)
{
	GtkWidget *root;
	GdkSurface *surface;

	if (widget == NULL) {
		return NULL;
	}
	root = gtk_widget_get_root (widget);
	if (root == NULL || !GTK_IS_NATIVE (root)) {
		return NULL;
	}
	surface = gtk_native_get_surface (GTK_NATIVE (root));
	if (surface == NULL || !GDK_IS_ANDROID_TOPLEVEL (surface)) {
		return NULL;
	}
	return gdk_android_toplevel_get_activity (GDK_ANDROID_TOPLEVEL (surface));
}

static gboolean
wka_cache_host_class (JNIEnv *env, jobject activity)
{
	jclass local;
	JNINativeMethod natives[4];

	if (wka_host_cls_global != NULL) {
		return TRUE;
	}
	local = wka_load_class (env, activity, "org.roojs.webkitgtk.android.WebViewHost");
	if (local == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return FALSE;
	}

	natives[0].name = "nativeLoadChanged";
	natives[0].signature = "(I)V";
	natives[0].fnPtr = (void *) Java_org_roojs_webkitgtk_android_WebViewHost_nativeLoadChanged;
	natives[1].name = "nativeTitleChanged";
	natives[1].signature = "()V";
	natives[1].fnPtr = (void *) Java_org_roojs_webkitgtk_android_WebViewHost_nativeTitleChanged;
	natives[2].name = "nativeFreezeFrame";
	natives[2].signature = "([BII)V";
	natives[2].fnPtr = (void *) Java_org_roojs_webkitgtk_android_WebViewHost_nativeFreezeFrame;
	natives[3].name = "nativeDocumentResponse";
	natives[3].signature = "(I[Ljava/lang/String;[Ljava/lang/String;)V";
	natives[3].fnPtr = (void *) Java_org_roojs_webkitgtk_android_WebViewHost_nativeDocumentResponse;
	if ((*env)->RegisterNatives (env, local, natives, 4) != 0) {
		(*env)->ExceptionClear (env);
		(*env)->DeleteLocalRef (env, local);
		return FALSE;
	}

	wka_host_cls_global = (jclass) (*env)->NewGlobalRef (env, local);
	(*env)->DeleteLocalRef (env, local);
	return wka_host_cls_global != NULL;
}

static jclass
wka_host_cls (JNIEnv *env)
{
	return wka_host_cls_global;
}

static gboolean
wka_emit_load_idle (gpointer data)
{
	gint event = GPOINTER_TO_INT (data);

	if (wka_load_cb != NULL) {
		wka_load_cb (wka_cb_data, event);
	}
	return G_SOURCE_REMOVE;
}

static gboolean
wka_emit_title_idle (gpointer data)
{
	(void) data;
	if (wka_title_cb != NULL) {
		wka_title_cb (wka_cb_data);
	}
	return G_SOURCE_REMOVE;
}

JNIEXPORT void JNICALL
Java_org_roojs_webkitgtk_android_WebViewHost_nativeLoadChanged (JNIEnv *env,
                                                                jclass cls,
                                                                jint load_event)
{
	(void) env;
	(void) cls;
	g_idle_add (wka_emit_load_idle, GINT_TO_POINTER ((gint) load_event));
}

JNIEXPORT void JNICALL
Java_org_roojs_webkitgtk_android_WebViewHost_nativeTitleChanged (JNIEnv *env, jclass cls)
{
	(void) env;
	(void) cls;
	g_idle_add (wka_emit_title_idle, NULL);
}

static gboolean
wka_emit_freeze_idle (gpointer data)
{
	(void) data;
	if (wka_freeze_cb != NULL) {
		wka_freeze_cb (wka_freeze_bytes, wka_freeze_w, wka_freeze_h, wka_cb_data);
	}
	g_clear_pointer (&wka_freeze_bytes, g_bytes_unref);
	wka_freeze_w = 0;
	wka_freeze_h = 0;
	return G_SOURCE_REMOVE;
}

JNIEXPORT void JNICALL
Java_org_roojs_webkitgtk_android_WebViewHost_nativeFreezeFrame (JNIEnv *env,
                                                                jclass cls,
                                                                jbyteArray rgba,
                                                                jint width,
                                                                jint height)
{
	jbyte *elems;
	jsize len;

	(void) cls;
	g_clear_pointer (&wka_freeze_bytes, g_bytes_unref);
	wka_freeze_w = 0;
	wka_freeze_h = 0;

	if (rgba != NULL && width > 0 && height > 0) {
		len = (*env)->GetArrayLength (env, rgba);
		if (len >= (jsize) width * (jsize) height * 4) {
			elems = (*env)->GetByteArrayElements (env, rgba, NULL);
			if (elems != NULL) {
				wka_freeze_bytes = g_bytes_new (elems, (gsize) width * (gsize) height * 4);
				(*env)->ReleaseByteArrayElements (env, rgba, elems, JNI_ABORT);
				wka_freeze_w = width;
				wka_freeze_h = height;
			}
		}
	}

	if (g_main_context_is_owner (g_main_context_default ())) {
		wka_emit_freeze_idle (NULL);
	} else {
		g_idle_add (wka_emit_freeze_idle, NULL);
	}
}

typedef struct {
	gint status;
	char **names;
	char **values;
	gsize count;
} WkaDocResponseData;

static void
wka_doc_response_data_free (WkaDocResponseData *d)
{
	gsize i;

	if (d == NULL) {
		return;
	}
	for (i = 0; i < d->count; i++) {
		g_free (d->names[i]);
		g_free (d->values[i]);
	}
	g_free (d->names);
	g_free (d->values);
	g_free (d);
}

static gboolean
wka_emit_doc_response_idle (gpointer data)
{
	WkaDocResponseData *d = data;

	if (wka_doc_response_cb != NULL) {
		wka_doc_response_cb (wka_doc_response_data,
			d->status,
			d->names,
			d->values,
			d->count);
	}
	wka_doc_response_data_free (d);
	return G_SOURCE_REMOVE;
}

JNIEXPORT void JNICALL
Java_org_roojs_webkitgtk_android_WebViewHost_nativeDocumentResponse (JNIEnv *env,
                                                                     jclass cls,
                                                                     jint status,
                                                                     jobjectArray jnames,
                                                                     jobjectArray jvalues)
{
	WkaDocResponseData *d;
	jsize n = 0;
	jsize i;

	(void) cls;
	if (wka_doc_response_cb == NULL) {
		return;
	}

	d = g_new0 (WkaDocResponseData, 1);
	d->status = (gint) status;

	if (jnames != NULL && jvalues != NULL) {
		n = (*env)->GetArrayLength (env, jnames);
		if (n > (*env)->GetArrayLength (env, jvalues)) {
			n = (*env)->GetArrayLength (env, jvalues);
		}
	}
	d->count = (gsize) n;
	if (n > 0) {
		d->names = g_new0 (char *, (gsize) n);
		d->values = g_new0 (char *, (gsize) n);
		for (i = 0; i < n; i++) {
			jstring jn = (jstring) (*env)->GetObjectArrayElement (env, jnames, i);
			jstring jv = (jstring) (*env)->GetObjectArrayElement (env, jvalues, i);
			const char *cn = "";
			const char *cv = "";
			if (jn != NULL) {
				cn = (*env)->GetStringUTFChars (env, jn, NULL);
			}
			if (jv != NULL) {
				cv = (*env)->GetStringUTFChars (env, jv, NULL);
			}
			d->names[i] = g_strdup (cn != NULL ? cn : "");
			d->values[i] = g_strdup (cv != NULL ? cv : "");
			if (jn != NULL && cn != NULL) {
				(*env)->ReleaseStringUTFChars (env, jn, cn);
			}
			if (jv != NULL && cv != NULL) {
				(*env)->ReleaseStringUTFChars (env, jv, cv);
			}
			if (jn != NULL) {
				(*env)->DeleteLocalRef (env, jn);
			}
			if (jv != NULL) {
				(*env)->DeleteLocalRef (env, jv);
			}
		}
	}

	g_idle_add (wka_emit_doc_response_idle, d);
}

void
wka_host_set_event_handlers (WkaLoadChangedCb load_changed,
                             WkaTitleCb title_changed,
                             gpointer user_data)
{
	wka_load_cb = load_changed;
	wka_title_cb = title_changed;
	wka_cb_data = user_data;
}

void
wka_host_set_document_response_handler (WkaDocumentResponseCb handler,
                                        gpointer user_data)
{
	wka_doc_response_cb = handler;
	wka_doc_response_data = user_data;
}

void
wka_host_set_freeze_frame_handler (WkaFreezeFrameCb cb)
{
	wka_freeze_cb = cb;
}

gboolean
wka_host_freeze (void)
{
	JNIEnv *env;
	jclass cls;
	jmethodID mid;

	env = wka_jni_env ();
	if (env == NULL || wka_host_cls_global == NULL) {
		return FALSE;
	}
	cls = wka_host_cls_global;
	mid = (*env)->GetStaticMethodID (env, cls, "freeze", "()V");
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return FALSE;
	}
	(*env)->CallStaticVoidMethod (env, cls, mid);
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionDescribe (env);
		(*env)->ExceptionClear (env);
		return FALSE;
	}
	return TRUE;
}

gboolean
wka_host_resume (void)
{
	JNIEnv *env;
	jclass cls;
	jmethodID mid;

	env = wka_jni_env ();
	if (env == NULL || wka_host_cls_global == NULL) {
		return FALSE;
	}
	cls = wka_host_cls_global;
	mid = (*env)->GetStaticMethodID (env, cls, "resume", "()V");
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return FALSE;
	}
	(*env)->CallStaticVoidMethod (env, cls, mid);
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionDescribe (env);
		(*env)->ExceptionClear (env);
		return FALSE;
	}
	return TRUE;
}

gboolean
wka_host_create_with_xywh (GtkWidget *widget,
                           int x,
                           int y,
                           int width,
                           int height,
                           const char *url)
{
	JNIEnv *env;
	jobject activity;
	jclass host_cls;
	jmethodID mid;
	jstring jurl;

	activity = wka_activity_for_widget (widget);
	if (activity == NULL) {
		__android_log_print (ANDROID_LOG_WARN, WKA_LOG_TAG,
			"create: no Activity yet (widget not realized)");
		return FALSE;
	}
	env = wka_jni_env ();
	if (env == NULL) {
		__android_log_print (ANDROID_LOG_ERROR, WKA_LOG_TAG, "create: no JNIEnv");
		return FALSE;
	}
	if (!wka_cache_host_class (env, activity)) {
		__android_log_print (ANDROID_LOG_ERROR, WKA_LOG_TAG,
			"create: failed to load WebViewHost class");
		(*env)->DeleteLocalRef (env, activity);
		return FALSE;
	}
	host_cls = wka_host_cls (env);
	mid = (*env)->GetStaticMethodID (env, host_cls, "attach",
		"(Landroid/app/Activity;IIIILjava/lang/String;)V");
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		__android_log_print (ANDROID_LOG_ERROR, WKA_LOG_TAG, "create: attach method missing");
		(*env)->ExceptionClear (env);
		(*env)->DeleteLocalRef (env, activity);
		return FALSE;
	}
	jurl = (*env)->NewStringUTF (env, url != NULL ? url : "about:blank");
	__android_log_print (ANDROID_LOG_INFO, WKA_LOG_TAG,
		"create: calling attach %d,%d %dx%d url=%s",
		x, y, width, height, url != NULL ? url : "(null)");
	(*env)->CallStaticVoidMethod (env, host_cls, mid, activity, x, y, width, height, jurl);
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionDescribe (env);
		(*env)->ExceptionClear (env);
		(*env)->DeleteLocalRef (env, jurl);
		(*env)->DeleteLocalRef (env, activity);
		return FALSE;
	}
	(*env)->DeleteLocalRef (env, jurl);
	(*env)->DeleteLocalRef (env, activity);
	return TRUE;
}

void
wka_host_set_bounds_xywh (int x, int y, int width, int height)
{
	JNIEnv *env;
	jclass host_cls;
	jmethodID mid;

	env = wka_jni_env ();
	if (env == NULL || wka_host_cls_global == NULL) {
		return;
	}
	host_cls = wka_host_cls (env);
	mid = (*env)->GetStaticMethodID (env, host_cls, "setBounds", "(IIII)V");
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return;
	}
	(*env)->CallStaticVoidMethod (env, host_cls, mid, x, y, width, height);
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
	}
}

gboolean
wka_host_navigate (const char *url)
{
	JNIEnv *env;
	jclass host_cls;
	jmethodID mid;
	jstring jurl;

	if (url == NULL || wka_host_cls_global == NULL) {
		return FALSE;
	}
	env = wka_jni_env ();
	if (env == NULL) {
		return FALSE;
	}
	host_cls = wka_host_cls (env);
	mid = (*env)->GetStaticMethodID (env, host_cls, "navigate", "(Ljava/lang/String;)V");
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return FALSE;
	}
	jurl = (*env)->NewStringUTF (env, url);
	(*env)->CallStaticVoidMethod (env, host_cls, mid, jurl);
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		(*env)->DeleteLocalRef (env, jurl);
		return FALSE;
	}
	(*env)->DeleteLocalRef (env, jurl);
	return TRUE;
}

void
wka_host_go_back (void)
{
	JNIEnv *env;
	jmethodID mid;

	env = wka_jni_env ();
	if (env == NULL || wka_host_cls_global == NULL) {
		return;
	}
	mid = (*env)->GetStaticMethodID (env, wka_host_cls_global, "goBack", "()V");
	if (mid != NULL) {
		(*env)->CallStaticVoidMethod (env, wka_host_cls_global, mid);
	}
	(*env)->ExceptionClear (env);
}

void
wka_host_go_forward (void)
{
	JNIEnv *env;
	jmethodID mid;

	env = wka_jni_env ();
	if (env == NULL || wka_host_cls_global == NULL) {
		return;
	}
	mid = (*env)->GetStaticMethodID (env, wka_host_cls_global, "goForward", "()V");
	if (mid != NULL) {
		(*env)->CallStaticVoidMethod (env, wka_host_cls_global, mid);
	}
	(*env)->ExceptionClear (env);
}

void
wka_host_reload (void)
{
	JNIEnv *env;
	jmethodID mid;

	env = wka_jni_env ();
	if (env == NULL || wka_host_cls_global == NULL) {
		return;
	}
	mid = (*env)->GetStaticMethodID (env, wka_host_cls_global, "reload", "()V");
	if (mid != NULL) {
		(*env)->CallStaticVoidMethod (env, wka_host_cls_global, mid);
	}
	(*env)->ExceptionClear (env);
}

void
wka_host_stop (void)
{
	JNIEnv *env;
	jmethodID mid;

	env = wka_jni_env ();
	if (env == NULL || wka_host_cls_global == NULL) {
		return;
	}
	mid = (*env)->GetStaticMethodID (env, wka_host_cls_global, "stopLoading", "()V");
	if (mid != NULL) {
		(*env)->CallStaticVoidMethod (env, wka_host_cls_global, mid);
	}
	(*env)->ExceptionClear (env);
}

gboolean
wka_host_can_go_back (void)
{
	JNIEnv *env;
	jmethodID mid;
	jboolean result = JNI_FALSE;

	env = wka_jni_env ();
	if (env == NULL || wka_host_cls_global == NULL) {
		return FALSE;
	}
	mid = (*env)->GetStaticMethodID (env, wka_host_cls_global, "canGoBack", "()Z");
	if (mid != NULL) {
		result = (*env)->CallStaticBooleanMethod (env, wka_host_cls_global, mid);
	}
	(*env)->ExceptionClear (env);
	return result == JNI_TRUE;
}

gboolean
wka_host_can_go_forward (void)
{
	JNIEnv *env;
	jmethodID mid;
	jboolean result = JNI_FALSE;

	env = wka_jni_env ();
	if (env == NULL || wka_host_cls_global == NULL) {
		return FALSE;
	}
	mid = (*env)->GetStaticMethodID (env, wka_host_cls_global, "canGoForward", "()Z");
	if (mid != NULL) {
		result = (*env)->CallStaticBooleanMethod (env, wka_host_cls_global, mid);
	}
	(*env)->ExceptionClear (env);
	return result == JNI_TRUE;
}

void
wka_host_destroy (void)
{
	JNIEnv *env;
	jmethodID mid;

	env = wka_jni_env ();
	if (env == NULL || wka_host_cls_global == NULL) {
		return;
	}
	mid = (*env)->GetStaticMethodID (env, wka_host_cls_global, "destroy", "()V");
	if (mid != NULL) {
		(*env)->CallStaticVoidMethod (env, wka_host_cls_global, mid);
	}
	(*env)->ExceptionClear (env);
}

gboolean
wka_host_is_ready (void)
{
	JNIEnv *env;
	jmethodID mid;
	jboolean result = JNI_FALSE;

	env = wka_jni_env ();
	if (env == NULL || wka_host_cls_global == NULL) {
		return FALSE;
	}
	mid = (*env)->GetStaticMethodID (env, wka_host_cls_global, "isReady", "()Z");
	if (mid != NULL) {
		result = (*env)->CallStaticBooleanMethod (env, wka_host_cls_global, mid);
	}
	(*env)->ExceptionClear (env);
	return result == JNI_TRUE;
}

const char *
wka_host_get_uri (void)
{
	JNIEnv *env;
	jmethodID mid;
	jstring jstr;
	const char *utf;

	wka_uri_buf[0] = '\0';
	env = wka_jni_env ();
	if (env == NULL || wka_host_cls_global == NULL) {
		return wka_uri_buf;
	}
	mid = (*env)->GetStaticMethodID (env, wka_host_cls_global, "getUri",
		"()Ljava/lang/String;");
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return wka_uri_buf;
	}
	jstr = (jstring) (*env)->CallStaticObjectMethod (env, wka_host_cls_global, mid);
	if (jstr != NULL) {
		utf = (*env)->GetStringUTFChars (env, jstr, NULL);
		if (utf != NULL) {
			g_strlcpy (wka_uri_buf, utf, sizeof (wka_uri_buf));
			(*env)->ReleaseStringUTFChars (env, jstr, utf);
		}
		(*env)->DeleteLocalRef (env, jstr);
	}
	return wka_uri_buf;
}

const char *
wka_host_get_title (void)
{
	JNIEnv *env;
	jmethodID mid;
	jstring jstr;
	const char *utf;

	wka_title_buf[0] = '\0';
	env = wka_jni_env ();
	if (env == NULL || wka_host_cls_global == NULL) {
		return wka_title_buf;
	}
	mid = (*env)->GetStaticMethodID (env, wka_host_cls_global, "getTitle",
		"()Ljava/lang/String;");
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return wka_title_buf;
	}
	jstr = (jstring) (*env)->CallStaticObjectMethod (env, wka_host_cls_global, mid);
	if (jstr != NULL) {
		utf = (*env)->GetStringUTFChars (env, jstr, NULL);
		if (utf != NULL) {
			g_strlcpy (wka_title_buf, utf, sizeof (wka_title_buf));
			(*env)->ReleaseStringUTFChars (env, jstr, utf);
		}
		(*env)->DeleteLocalRef (env, jstr);
	}
	return wka_title_buf;
}

void
wka_host_put_is_visible (gboolean visible)
{
	JNIEnv *env;
	jmethodID mid;

	env = wka_jni_env ();
	if (env == NULL || wka_host_cls_global == NULL) {
		return;
	}
	mid = (*env)->GetStaticMethodID (env, wka_host_cls_global, "setVisible", "(Z)V");
	if (mid != NULL) {
		(*env)->CallStaticVoidMethod (env, wka_host_cls_global, mid,
			visible ? JNI_TRUE : JNI_FALSE);
	}
	(*env)->ExceptionClear (env);
}

void
wka_host_set_virtual_size (int width, int height)
{
	JNIEnv *env;
	jmethodID mid;

	env = wka_jni_env ();
	if (env == NULL || wka_host_cls_global == NULL) {
		return;
	}
	mid = (*env)->GetStaticMethodID (env, wka_host_cls_global, "setVirtualSize", "(II)V");
	if (mid != NULL) {
		(*env)->CallStaticVoidMethod (env, wka_host_cls_global, mid, width, height);
	}
	(*env)->ExceptionClear (env);
}

void
wka_host_use_display_size (GtkWidget *widget)
{
	JNIEnv *env;
	jobject activity;
	jmethodID mid;

	activity = wka_activity_for_widget (widget);
	if (activity == NULL) {
		return;
	}
	env = wka_jni_env ();
	if (env == NULL) {
		return;
	}
	if (!wka_cache_host_class (env, activity)) {
		(*env)->DeleteLocalRef (env, activity);
		return;
	}
	mid = (*env)->GetStaticMethodID (env, wka_host_cls_global, "useDisplaySize",
		"(Landroid/app/Activity;)V");
	if (mid != NULL) {
		(*env)->CallStaticVoidMethod (env, wka_host_cls_global, mid, activity);
	}
	(*env)->ExceptionClear (env);
	(*env)->DeleteLocalRef (env, activity);
}
