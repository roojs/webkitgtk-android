/* JNI bridge for WebViewA11y — mirrors webview2-gtk a11y_walk shape.
 * Sync walk is Android-UI only; GLib/GTK use walk_foreach_async (docs/a11y.md). */

#include "webkitgtk-android-host-api.h"

#include <android/log.h>
#include <jni.h>
#include <stdlib.h>
#include <string.h>

#define WKA_A11Y_LOG_TAG "WebViewA11y"

/* From webkitgtk-android-host.c */
JNIEnv *wka_get_env (void);
jclass wka_get_host_class (void);

static jclass wka_a11y_cls = NULL;
static guint wka_walk_cookie_seq = 1;
static GHashTable *wka_walk_pending = NULL; /* cookie → WkaWalkPending* */

typedef struct {
	WkaA11yForeachCb row_cb;
	WkaA11yWalkDoneCb done_cb;
	gpointer user_data;
} WkaWalkPending;

typedef struct {
	guint cookie;
	wka_a11y_node *nodes;
	gsize count;
	gboolean ok;
} WkaWalkIdle;

static void
wka_a11y_register_natives (JNIEnv *env, jclass cls);

JNIEXPORT void JNICALL
Java_org_roojs_webkitgtk_android_WebViewA11y_nativeWalkDone (JNIEnv *env,
                                                             jclass cls,
                                                             jobjectArray arr,
                                                             jlong cookie);

static jclass
wka_a11y_class (JNIEnv *env)
{
	jclass host;
	jobject loader;
	jclass loader_cls;
	jmethodID load_class;
	jstring jname;
	jclass local;

	if (wka_a11y_cls != NULL) {
		return wka_a11y_cls;
	}
	host = wka_get_host_class ();
	if (host == NULL) {
		return NULL;
	}

	/* Load via host ClassLoader (same APK as WebViewHost). */
	{
		jclass cls_class = (*env)->FindClass (env, "java/lang/Class");
		jmethodID get_cl = (*env)->GetMethodID (env, cls_class, "getClassLoader",
			"()Ljava/lang/ClassLoader;");
		loader = (*env)->CallObjectMethod (env, host, get_cl);
		loader_cls = (*env)->GetObjectClass (env, loader);
		load_class = (*env)->GetMethodID (env, loader_cls, "loadClass",
			"(Ljava/lang/String;)Ljava/lang/Class;");
		jname = (*env)->NewStringUTF (env, "org.roojs.webkitgtk.android.WebViewA11y");
		local = (jclass) (*env)->CallObjectMethod (env, loader, load_class, jname);
		(*env)->DeleteLocalRef (env, jname);
		(*env)->DeleteLocalRef (env, loader_cls);
		(*env)->DeleteLocalRef (env, loader);
		(*env)->DeleteLocalRef (env, cls_class);
	}
	if (local == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return NULL;
	}
	wka_a11y_register_natives (env, local);
	wka_a11y_cls = (jclass) (*env)->NewGlobalRef (env, local);
	(*env)->DeleteLocalRef (env, local);
	return wka_a11y_cls;
}

static void
wka_a11y_register_natives (JNIEnv *env, jclass cls)
{
	JNINativeMethod natives[1];

	natives[0].name = "nativeWalkDone";
	natives[0].signature = "([Lorg/roojs/webkitgtk/android/WebViewA11y$Node;J)V";
	natives[0].fnPtr = (void *) Java_org_roojs_webkitgtk_android_WebViewA11y_nativeWalkDone;
	if ((*env)->RegisterNatives (env, cls, natives, 1) != 0) {
		(*env)->ExceptionClear (env);
		__android_log_print (ANDROID_LOG_ERROR, WKA_A11Y_LOG_TAG,
			"RegisterNatives nativeWalkDone failed");
	}
}

static char *
wka_jstring_dup (JNIEnv *env, jstring js)
{
	const char *utf;
	char *out;

	if (js == NULL) {
		return g_strdup ("");
	}
	utf = (*env)->GetStringUTFChars (env, js, NULL);
	out = g_strdup (utf != NULL ? utf : "");
	if (utf != NULL) {
		(*env)->ReleaseStringUTFChars (env, js, utf);
	}
	return out;
}

gboolean
wka_host_a11y_ensure (void)
{
	JNIEnv *env;
	jclass cls;
	jmethodID mid;
	jboolean ok;

	env = wka_get_env ();
	if (env == NULL) {
		return FALSE;
	}
	cls = wka_a11y_class (env);
	if (cls == NULL) {
		__android_log_print (ANDROID_LOG_ERROR, WKA_A11Y_LOG_TAG, "ensure: no class");
		return FALSE;
	}
	mid = (*env)->GetStaticMethodID (env, cls, "ensure", "()Z");
	if (mid == NULL) {
		(*env)->ExceptionClear (env);
		return FALSE;
	}
	ok = (*env)->CallStaticBooleanMethod (env, cls, mid);
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionDescribe (env);
		(*env)->ExceptionClear (env);
		return FALSE;
	}
	return ok == JNI_TRUE;
}

static gboolean
wka_fill_node_from_java (JNIEnv *env, jobject jnode, wka_a11y_node *n)
{
	jclass nc;
	jfieldID f;

	memset (n, 0, sizeof (*n));
	nc = (*env)->GetObjectClass (env, jnode);
	f = (*env)->GetFieldID (env, nc, "id", "I");
	n->id = (*env)->GetIntField (env, jnode, f);
	f = (*env)->GetFieldID (env, nc, "parentId", "I");
	n->parent_id = (*env)->GetIntField (env, jnode, f);
	f = (*env)->GetFieldID (env, nc, "x", "I");
	n->x = (*env)->GetIntField (env, jnode, f);
	f = (*env)->GetFieldID (env, nc, "y", "I");
	n->y = (*env)->GetIntField (env, jnode, f);
	f = (*env)->GetFieldID (env, nc, "w", "I");
	n->w = (*env)->GetIntField (env, jnode, f);
	f = (*env)->GetFieldID (env, nc, "h", "I");
	n->h = (*env)->GetIntField (env, jnode, f);
	f = (*env)->GetFieldID (env, nc, "name", "Ljava/lang/String;");
	n->name = wka_jstring_dup (env, (jstring) (*env)->GetObjectField (env, jnode, f));
	f = (*env)->GetFieldID (env, nc, "role", "Ljava/lang/String;");
	n->role = wka_jstring_dup (env, (jstring) (*env)->GetObjectField (env, jnode, f));
	f = (*env)->GetFieldID (env, nc, "value", "Ljava/lang/String;");
	n->value = wka_jstring_dup (env, (jstring) (*env)->GetObjectField (env, jnode, f));
	f = (*env)->GetFieldID (env, nc, "uri", "Ljava/lang/String;");
	n->uri = wka_jstring_dup (env, (jstring) (*env)->GetObjectField (env, jnode, f));
	f = (*env)->GetFieldID (env, nc, "canInvoke", "Z");
	n->can_invoke = (*env)->GetBooleanField (env, jnode, f) == JNI_TRUE;
	f = (*env)->GetFieldID (env, nc, "canSetValue", "Z");
	n->can_set_value = (*env)->GetBooleanField (env, jnode, f) == JNI_TRUE;
	(*env)->DeleteLocalRef (env, nc);
	return TRUE;
}

void
wka_host_a11y_nodes_free (wka_a11y_node *nodes, gsize count)
{
	gsize i;

	if (nodes == NULL) {
		return;
	}
	for (i = 0; i < count; i++) {
		g_free (nodes[i].name);
		g_free (nodes[i].role);
		g_free (nodes[i].value);
		g_free (nodes[i].uri);
	}
	g_free (nodes);
}

gboolean
wka_host_a11y_walk (wka_a11y_node **nodes_out, gsize *count_out)
{
	JNIEnv *env;
	jclass cls;
	jmethodID mid;
	jobjectArray arr;
	jsize n;
	jsize i;
	wka_a11y_node *nodes;

	if (nodes_out == NULL || count_out == NULL) {
		return FALSE;
	}
	*nodes_out = NULL;
	*count_out = 0;

	env = wka_get_env ();
	if (env == NULL) {
		return FALSE;
	}
	cls = wka_a11y_class (env);
	if (cls == NULL) {
		return FALSE;
	}
	mid = (*env)->GetStaticMethodID (env, cls, "walk",
		"()[Lorg/roojs/webkitgtk/android/WebViewA11y$Node;");
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return FALSE;
	}
	arr = (jobjectArray) (*env)->CallStaticObjectMethod (env, cls, mid);
	if ((*env)->ExceptionCheck (env) || arr == NULL) {
		(*env)->ExceptionClear (env);
		return FALSE;
	}
	n = (*env)->GetArrayLength (env, arr);
	if (n <= 0) {
		(*env)->DeleteLocalRef (env, arr);
		return FALSE;
	}
	nodes = g_new0 (wka_a11y_node, (gsize) n);
	for (i = 0; i < n; i++) {
		jobject jn = (*env)->GetObjectArrayElement (env, arr, i);
		wka_fill_node_from_java (env, jn, &nodes[i]);
		(*env)->DeleteLocalRef (env, jn);
	}
	(*env)->DeleteLocalRef (env, arr);
	*nodes_out = nodes;
	*count_out = (gsize) n;
	return TRUE;
}

gboolean
wka_host_a11y_walk_foreach (WkaA11yForeachCb cb, gpointer user_data)
{
	wka_a11y_node *nodes = NULL;
	gsize count = 0;
	gsize i;

	if (cb == NULL) {
		return FALSE;
	}
	if (!wka_host_a11y_walk (&nodes, &count)) {
		return FALSE;
	}
	for (i = 0; i < count; i++) {
		wka_a11y_node *n = &nodes[i];
		cb (
			n->id,
			n->parent_id,
			n->x,
			n->y,
			n->w,
			n->h,
			n->name != NULL ? n->name : "",
			n->role != NULL ? n->role : "",
			n->value != NULL ? n->value : "",
			n->uri != NULL ? n->uri : "",
			n->can_invoke,
			n->can_set_value,
			user_data
		);
	}
	wka_host_a11y_nodes_free (nodes, count);
	return TRUE;
}

static gboolean
wka_walk_idle (gpointer data)
{
	WkaWalkIdle *idle = data;
	WkaWalkPending *pending = NULL;
	gsize i;

	if (wka_walk_pending != NULL) {
		pending = g_hash_table_lookup (wka_walk_pending,
			GUINT_TO_POINTER (idle->cookie));
		if (pending != NULL) {
			g_hash_table_remove (wka_walk_pending,
				GUINT_TO_POINTER (idle->cookie));
		}
	}

	if (pending != NULL && idle->ok && pending->row_cb != NULL && idle->nodes != NULL) {
		for (i = 0; i < idle->count; i++) {
			wka_a11y_node *n = &idle->nodes[i];
			pending->row_cb (
				n->id,
				n->parent_id,
				n->x,
				n->y,
				n->w,
				n->h,
				n->name != NULL ? n->name : "",
				n->role != NULL ? n->role : "",
				n->value != NULL ? n->value : "",
				n->uri != NULL ? n->uri : "",
				n->can_invoke,
				n->can_set_value,
				pending->user_data
			);
		}
	}
	if (pending != NULL && pending->done_cb != NULL) {
		pending->done_cb (idle->ok, pending->user_data);
	}
	g_free (pending);
	wka_host_a11y_nodes_free (idle->nodes, idle->count);
	g_free (idle);
	return G_SOURCE_REMOVE;
}

static void
wka_walk_schedule_fail (guint cookie)
{
	WkaWalkIdle *idle;

	idle = g_new0 (WkaWalkIdle, 1);
	idle->cookie = cookie;
	idle->ok = FALSE;
	g_idle_add (wka_walk_idle, idle);
}

JNIEXPORT void JNICALL
Java_org_roojs_webkitgtk_android_WebViewA11y_nativeWalkDone (JNIEnv *env,
                                                             jclass cls,
                                                             jobjectArray arr,
                                                             jlong cookie)
{
	WkaWalkIdle *idle;
	jsize n = 0;
	jsize i;

	(void) cls;
	idle = g_new0 (WkaWalkIdle, 1);
	idle->cookie = (guint) cookie;
	idle->ok = TRUE;
	if (arr != NULL) {
		n = (*env)->GetArrayLength (env, arr);
	}
	if (n > 0) {
		idle->nodes = g_new0 (wka_a11y_node, (gsize) n);
		idle->count = (gsize) n;
		for (i = 0; i < n; i++) {
			jobject jn = (*env)->GetObjectArrayElement (env, arr, i);
			wka_fill_node_from_java (env, jn, &idle->nodes[i]);
			(*env)->DeleteLocalRef (env, jn);
		}
	}
	g_idle_add (wka_walk_idle, idle);
}

void
wka_host_a11y_walk_foreach_async (WkaA11yForeachCb row_cb,
                                  WkaA11yWalkDoneCb done_cb,
                                  gpointer user_data)
{
	JNIEnv *env;
	jclass cls;
	jmethodID mid;
	WkaWalkPending *pending;
	guint cookie;

	if (wka_walk_pending == NULL) {
		wka_walk_pending = g_hash_table_new (g_direct_hash, g_direct_equal);
	}

	cookie = wka_walk_cookie_seq++;
	if (cookie == 0) {
		cookie = wka_walk_cookie_seq++;
	}
	pending = g_new0 (WkaWalkPending, 1);
	pending->row_cb = row_cb;
	pending->done_cb = done_cb;
	pending->user_data = user_data;
	g_hash_table_insert (wka_walk_pending, GUINT_TO_POINTER (cookie), pending);

	env = wka_get_env ();
	if (env == NULL) {
		wka_walk_schedule_fail (cookie);
		return;
	}
	cls = wka_a11y_class (env);
	if (cls == NULL) {
		wka_walk_schedule_fail (cookie);
		return;
	}
	mid = (*env)->GetStaticMethodID (env, cls, "walkAsync", "(J)V");
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		wka_walk_schedule_fail (cookie);
		return;
	}
	(*env)->CallStaticVoidMethod (env, cls, mid, (jlong) cookie);
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionDescribe (env);
		(*env)->ExceptionClear (env);
		wka_walk_schedule_fail (cookie);
	}
}

gboolean
wka_host_a11y_invoke (int id)
{
	JNIEnv *env;
	jclass cls;
	jmethodID mid;
	jboolean ok;

	env = wka_get_env ();
	if (env == NULL) {
		return FALSE;
	}
	cls = wka_a11y_class (env);
	if (cls == NULL) {
		return FALSE;
	}
	mid = (*env)->GetStaticMethodID (env, cls, "invoke", "(I)Z");
	if (mid == NULL) {
		(*env)->ExceptionClear (env);
		return FALSE;
	}
	ok = (*env)->CallStaticBooleanMethod (env, cls, mid, (jint) id);
	(*env)->ExceptionClear (env);
	return ok == JNI_TRUE;
}

gboolean
wka_host_a11y_set_value (int id, const char *utf8)
{
	JNIEnv *env;
	jclass cls;
	jmethodID mid;
	jstring jstr;
	jboolean ok;

	env = wka_get_env ();
	if (env == NULL) {
		return FALSE;
	}
	cls = wka_a11y_class (env);
	if (cls == NULL) {
		return FALSE;
	}
	mid = (*env)->GetStaticMethodID (env, cls, "setValue", "(ILjava/lang/String;)Z");
	if (mid == NULL) {
		(*env)->ExceptionClear (env);
		return FALSE;
	}
	jstr = (*env)->NewStringUTF (env, utf8 != NULL ? utf8 : "");
	ok = (*env)->CallStaticBooleanMethod (env, cls, mid, (jint) id, jstr);
	(*env)->DeleteLocalRef (env, jstr);
	(*env)->ExceptionClear (env);
	return ok == JNI_TRUE;
}

gboolean
wka_host_a11y_focus (int id)
{
	JNIEnv *env;
	jclass cls;
	jmethodID mid;
	jboolean ok;

	env = wka_get_env ();
	if (env == NULL) {
		return FALSE;
	}
	cls = wka_a11y_class (env);
	if (cls == NULL) {
		return FALSE;
	}
	mid = (*env)->GetStaticMethodID (env, cls, "focus", "(I)Z");
	if (mid == NULL) {
		(*env)->ExceptionClear (env);
		return FALSE;
	}
	ok = (*env)->CallStaticBooleanMethod (env, cls, mid, (jint) id);
	(*env)->ExceptionClear (env);
	return ok == JNI_TRUE;
}
