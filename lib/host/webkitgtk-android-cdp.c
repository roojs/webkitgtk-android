/* CDP loopback bridge — JNI to WebViewCdpBridge.java */

#include "webkitgtk-android-host-api.h"

#include <android/log.h>
#include <jni.h>

#define WKA_CDP_LOG_TAG "WebViewCdp"

extern JNIEnv *wka_get_env (void);
extern jclass wka_get_host_class (void);

static jclass wka_cdp_cls = NULL;
static gboolean wka_automation_allowed = FALSE;
/* 0=AUTO, 1=ENABLED, 2=DISABLED — match NavigatorWebDriverActivePolicy */
static int g_navigator_webdriver_policy = 0;

static jclass
wka_cdp_class (JNIEnv *env)
{
	jclass host;
	jobject loader;
	jclass loader_cls;
	jmethodID load_class;
	jstring jname;
	jclass local;

	if (wka_cdp_cls != NULL) {
		return wka_cdp_cls;
	}
	host = wka_get_host_class ();
	if (host == NULL) {
		return NULL;
	}

	{
		jclass cls_class = (*env)->FindClass (env, "java/lang/Class");
		jmethodID get_cl = (*env)->GetMethodID (env, cls_class, "getClassLoader",
			"()Ljava/lang/ClassLoader;");
		loader = (*env)->CallObjectMethod (env, host, get_cl);
		loader_cls = (*env)->GetObjectClass (env, loader);
		load_class = (*env)->GetMethodID (env, loader_cls, "loadClass",
			"(Ljava/lang/String;)Ljava/lang/Class;");
		jname = (*env)->NewStringUTF (env, "org.roojs.webkitgtk.android.WebViewCdpBridge");
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
	wka_cdp_cls = (jclass) (*env)->NewGlobalRef (env, local);
	(*env)->DeleteLocalRef (env, local);
	return wka_cdp_cls;
}

static void
wka_cdp_enable_debugging (JNIEnv *env)
{
	jclass cls;
	jmethodID mid;

	cls = wka_cdp_class (env);
	if (cls == NULL) {
		return;
	}
	mid = (*env)->GetStaticMethodID (env, cls, "enableDebugging", "()V");
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return;
	}
	(*env)->CallStaticVoidMethod (env, cls, mid);
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
	}
}

static void
wka_cdp_set_automation_allowed_java (JNIEnv *env, gboolean allowed)
{
	jclass cls;
	jmethodID mid;

	cls = wka_cdp_class (env);
	if (cls == NULL) {
		return;
	}
	mid = (*env)->GetStaticMethodID (env, cls, "setAutomationAllowed", "(Z)V");
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return;
	}
	(*env)->CallStaticVoidMethod (env, cls, mid, allowed ? JNI_TRUE : JNI_FALSE);
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
	}
}

static int
wka_cdp_call_start (JNIEnv *env, int preferred_port)
{
	jclass cls;
	jmethodID mid;
	jint port;

	cls = wka_cdp_class (env);
	if (cls == NULL) {
		return -1;
	}
	mid = (*env)->GetStaticMethodID (env, cls, "startLoopbackProxy", "(I)I");
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return -1;
	}
	port = (*env)->CallStaticIntMethod (env, cls, mid, (jint) preferred_port);
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return -1;
	}
	return (int) port;
}

void
wka_host_set_automation_allowed (gboolean allowed)
{
	JNIEnv *env;

	wka_automation_allowed = allowed;
	env = wka_get_env ();
	if (env == NULL) {
		return;
	}
	wka_cdp_set_automation_allowed_java (env, allowed);
	if (allowed) {
		wka_cdp_enable_debugging (env);
	}
	__android_log_print (ANDROID_LOG_INFO, WKA_CDP_LOG_TAG,
		"set_automation_allowed=%d", allowed ? 1 : 0);
}

gboolean
wka_host_get_automation_allowed (void)
{
	return wka_automation_allowed;
}

void
wka_host_set_navigator_webdriver_active_policy (int policy)
{
	g_navigator_webdriver_policy = policy;
	if (policy == 2) { /* DISABLED */
		__android_log_print (ANDROID_LOG_INFO, WKA_CDP_LOG_TAG,
			"navigator_webdriver_active_policy=DISABLED stored (no-op: System WebView has no AutomationControlled blink switch)");
	}
}

gboolean
wka_host_cdp_start (int preferred_port)
{
	JNIEnv *env = wka_get_env ();
	int port;

	if (env == NULL) {
		return FALSE;
	}
	port = wka_cdp_call_start (env, preferred_port);
	if (port <= 0) {
		__android_log_print (ANDROID_LOG_ERROR, WKA_CDP_LOG_TAG,
			"startLoopbackProxy failed (preferred=%d)", preferred_port);
		return FALSE;
	}
	__android_log_print (ANDROID_LOG_INFO, WKA_CDP_LOG_TAG,
		"CDP bridge listening 127.0.0.1:%d", port);
	return TRUE;
}

int
wka_host_cdp_inspector_port_from_env (void)
{
	JNIEnv *env = wka_get_env ();
	jclass cls;
	jmethodID mid;
	jint port;

	if (env == NULL) {
		return 0;
	}
	cls = wka_cdp_class (env);
	if (cls == NULL) {
		return 0;
	}
	mid = (*env)->GetStaticMethodID (env, cls, "inspectorPortFromEnv", "()I");
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return 0;
	}
	port = (*env)->CallStaticIntMethod (env, cls, mid);
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return 0;
	}
	return (int) port;
}
