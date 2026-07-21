/* Download bridge — DownloadListener + HttpURLConnection via WebViewHost */

#include "webkitgtk-android-host-api.h"

#include <android/log.h>
#include <jni.h>
#include <string.h>

#define WKA_LOG_TAG "WebViewDownload"

JNIEnv *wka_get_env (void);
jclass wka_get_host_class (void);

static WkaDownloadStartedCb wka_dl_started_cb = NULL;
static WkaDownloadProgressCb wka_dl_progress_cb = NULL;
static WkaDownloadFinishedCb wka_dl_finished_cb = NULL;
static WkaDownloadFailedCb wka_dl_failed_cb = NULL;
static gpointer wka_dl_user_data = NULL;

typedef struct {
	gint id;
	char *uri;
	char *suggested;
	char *mime;
	gint64 content_length;
} WkaDlStartedData;

typedef struct {
	gint id;
	guint64 received;
} WkaDlProgressData;

typedef struct {
	gint id;
	char *message;
} WkaDlFailedData;

void
wka_host_set_download_handlers (WkaDownloadStartedCb started,
                                WkaDownloadProgressCb progress,
                                WkaDownloadFinishedCb finished,
                                WkaDownloadFailedCb failed,
                                gpointer user_data)
{
	wka_dl_started_cb = started;
	wka_dl_progress_cb = progress;
	wka_dl_finished_cb = finished;
	wka_dl_failed_cb = failed;
	wka_dl_user_data = user_data;
}

static gboolean
wka_emit_dl_started_idle (gpointer data)
{
	WkaDlStartedData *d = data;
	if (wka_dl_started_cb != NULL) {
		wka_dl_started_cb (d->id, d->uri, d->suggested, d->mime,
			d->content_length, wka_dl_user_data);
	}
	g_free (d->uri);
	g_free (d->suggested);
	g_free (d->mime);
	g_free (d);
	return G_SOURCE_REMOVE;
}

static gboolean
wka_emit_dl_progress_idle (gpointer data)
{
	WkaDlProgressData *d = data;
	if (wka_dl_progress_cb != NULL) {
		wka_dl_progress_cb (d->id, d->received, wka_dl_user_data);
	}
	g_free (d);
	return G_SOURCE_REMOVE;
}

static gboolean
wka_emit_dl_finished_idle (gpointer data)
{
	gint id = GPOINTER_TO_INT (data);
	if (wka_dl_finished_cb != NULL) {
		wka_dl_finished_cb (id, wka_dl_user_data);
	}
	return G_SOURCE_REMOVE;
}

static gboolean
wka_emit_dl_failed_idle (gpointer data)
{
	WkaDlFailedData *d = data;
	if (wka_dl_failed_cb != NULL) {
		wka_dl_failed_cb (d->id, d->message != NULL ? d->message : "download failed",
			wka_dl_user_data);
	}
	g_free (d->message);
	g_free (d);
	return G_SOURCE_REMOVE;
}

JNIEXPORT void JNICALL
Java_org_roojs_webkitgtk_android_WebViewHost_nativeDownloadStarted (JNIEnv *env,
                                                                    jclass cls,
                                                                    jint id,
                                                                    jstring juri,
                                                                    jstring jsuggested,
                                                                    jstring jmime,
                                                                    jlong content_length)
{
	WkaDlStartedData *d;
	const char *uri;
	const char *suggested;
	const char *mime;

	(void) cls;
	d = g_new0 (WkaDlStartedData, 1);
	d->id = id;
	d->content_length = (gint64) content_length;

	if (juri != NULL) {
		uri = (*env)->GetStringUTFChars (env, juri, NULL);
		if (uri != NULL) {
			d->uri = g_strdup (uri);
			(*env)->ReleaseStringUTFChars (env, juri, uri);
		}
	}
	if (jsuggested != NULL) {
		suggested = (*env)->GetStringUTFChars (env, jsuggested, NULL);
		if (suggested != NULL) {
			d->suggested = g_strdup (suggested);
			(*env)->ReleaseStringUTFChars (env, jsuggested, suggested);
		}
	}
	if (jmime != NULL) {
		mime = (*env)->GetStringUTFChars (env, jmime, NULL);
		if (mime != NULL) {
			d->mime = g_strdup (mime);
			(*env)->ReleaseStringUTFChars (env, jmime, mime);
		}
	}
	if (d->uri == NULL) {
		d->uri = g_strdup ("");
	}
	if (d->suggested == NULL) {
		d->suggested = g_strdup ("download");
	}
	if (d->mime == NULL) {
		d->mime = g_strdup ("");
	}
	g_idle_add (wka_emit_dl_started_idle, d);
}

JNIEXPORT void JNICALL
Java_org_roojs_webkitgtk_android_WebViewHost_nativeDownloadProgress (JNIEnv *env,
                                                                     jclass cls,
                                                                     jint id,
                                                                     jlong received)
{
	WkaDlProgressData *d;

	(void) env;
	(void) cls;
	d = g_new0 (WkaDlProgressData, 1);
	d->id = id;
	d->received = (guint64) received;
	g_idle_add (wka_emit_dl_progress_idle, d);
}

JNIEXPORT void JNICALL
Java_org_roojs_webkitgtk_android_WebViewHost_nativeDownloadFinished (JNIEnv *env,
                                                                     jclass cls,
                                                                     jint id)
{
	(void) env;
	(void) cls;
	g_idle_add (wka_emit_dl_finished_idle, GINT_TO_POINTER ((gint) id));
}

JNIEXPORT void JNICALL
Java_org_roojs_webkitgtk_android_WebViewHost_nativeDownloadFailed (JNIEnv *env,
                                                                   jclass cls,
                                                                   jint id,
                                                                   jstring jmsg)
{
	WkaDlFailedData *d;
	const char *msg;

	(void) cls;
	d = g_new0 (WkaDlFailedData, 1);
	d->id = id;
	if (jmsg != NULL) {
		msg = (*env)->GetStringUTFChars (env, jmsg, NULL);
		if (msg != NULL) {
			d->message = g_strdup (msg);
			(*env)->ReleaseStringUTFChars (env, jmsg, msg);
		}
	}
	g_idle_add (wka_emit_dl_failed_idle, d);
}

int
wka_host_download_create (const char *uri)
{
	JNIEnv *env;
	jclass cls;
	jmethodID mid;
	jstring juri;
	jint id = 0;

	if (uri == NULL || uri[0] == '\0') {
		return 0;
	}
	env = wka_get_env ();
	cls = wka_get_host_class ();
	if (env == NULL || cls == NULL) {
		return 0;
	}
	mid = (*env)->GetStaticMethodID (env, cls, "createDownload",
		"(Ljava/lang/String;)I");
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return 0;
	}
	juri = (*env)->NewStringUTF (env, uri);
	if (juri == NULL) {
		(*env)->ExceptionClear (env);
		return 0;
	}
	id = (*env)->CallStaticIntMethod (env, cls, mid, juri);
	(*env)->DeleteLocalRef (env, juri);
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return 0;
	}
	return (int) id;
}

gboolean
wka_host_download_start (int id, const char *dest_path, gboolean overwrite)
{
	JNIEnv *env;
	jclass cls;
	jmethodID mid;
	jstring jpath;
	jboolean ok = JNI_FALSE;

	if (id <= 0 || dest_path == NULL || dest_path[0] == '\0') {
		return FALSE;
	}
	env = wka_get_env ();
	cls = wka_get_host_class ();
	if (env == NULL || cls == NULL) {
		return FALSE;
	}
	mid = (*env)->GetStaticMethodID (env, cls, "startDownload",
		"(ILjava/lang/String;Z)Z");
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		__android_log_print (ANDROID_LOG_ERROR, WKA_LOG_TAG,
			"startDownload method not found");
		return FALSE;
	}
	jpath = (*env)->NewStringUTF (env, dest_path);
	if (jpath == NULL) {
		(*env)->ExceptionClear (env);
		return FALSE;
	}
	ok = (*env)->CallStaticBooleanMethod (env, cls, mid, (jint) id, jpath,
		overwrite ? JNI_TRUE : JNI_FALSE);
	(*env)->DeleteLocalRef (env, jpath);
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return FALSE;
	}
	return ok == JNI_TRUE;
}

void
wka_host_download_cancel (int id)
{
	JNIEnv *env;
	jclass cls;
	jmethodID mid;

	if (id <= 0) {
		return;
	}
	env = wka_get_env ();
	cls = wka_get_host_class ();
	if (env == NULL || cls == NULL) {
		return;
	}
	mid = (*env)->GetStaticMethodID (env, cls, "cancelDownload", "(I)V");
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return;
	}
	(*env)->CallStaticVoidMethod (env, cls, mid, (jint) id);
	(*env)->ExceptionClear (env);
}
