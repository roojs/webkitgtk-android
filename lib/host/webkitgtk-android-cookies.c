/* Cookie jar bridge — android.webkit.CookieManager via WebViewHost */

#include "webkitgtk-android-host-api.h"

#include <android/log.h>
#include <jni.h>
#include <string.h>

#define WKA_LOG_TAG "WebViewHost"

JNIEnv *wka_get_env (void);
jclass wka_get_host_class (void);

gboolean
wka_host_get_cookies (const char *uri, char **cookies_text_out)
{
	JNIEnv *env;
	jclass cls;
	jmethodID mid;
	jstring juri;
	jstring jstr;
	const char *utf;

	if (cookies_text_out != NULL) {
		*cookies_text_out = NULL;
	}
	if (uri == NULL || uri[0] == '\0') {
		return FALSE;
	}

	env = wka_get_env ();
	cls = wka_get_host_class ();
	if (env == NULL || cls == NULL) {
		return FALSE;
	}

	mid = (*env)->GetStaticMethodID (env, cls, "getCookies",
		"(Ljava/lang/String;)Ljava/lang/String;");
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return FALSE;
	}

	juri = (*env)->NewStringUTF (env, uri);
	if (juri == NULL) {
		(*env)->ExceptionClear (env);
		return FALSE;
	}

	jstr = (jstring) (*env)->CallStaticObjectMethod (env, cls, mid, juri);
	(*env)->DeleteLocalRef (env, juri);
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		if (jstr != NULL) {
			(*env)->DeleteLocalRef (env, jstr);
		}
		return FALSE;
	}

	if (jstr == NULL) {
		if (cookies_text_out != NULL) {
			*cookies_text_out = g_strdup ("");
		}
		return TRUE;
	}

	utf = (*env)->GetStringUTFChars (env, jstr, NULL);
	if (utf == NULL) {
		(*env)->DeleteLocalRef (env, jstr);
		return FALSE;
	}
	if (cookies_text_out != NULL) {
		*cookies_text_out = g_strdup (utf);
	}
	(*env)->ReleaseStringUTFChars (env, jstr, utf);
	(*env)->DeleteLocalRef (env, jstr);
	return TRUE;
}

gboolean
wka_host_add_cookie (const char *name,
                     const char *value,
                     const char *domain,
                     const char *path,
                     gboolean http_only,
                     gboolean secure)
{
	JNIEnv *env;
	jclass cls;
	jmethodID mid;
	jstring jname;
	jstring jvalue;
	jstring jdomain;
	jstring jpath;
	jboolean ok = JNI_FALSE;
	const char *dom;
	const char *pth;

	if (name == NULL || name[0] == '\0' || value == NULL) {
		return FALSE;
	}

	env = wka_get_env ();
	cls = wka_get_host_class ();
	if (env == NULL || cls == NULL) {
		return FALSE;
	}

	mid = (*env)->GetStaticMethodID (env, cls, "addCookie",
		"(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;"
		"Ljava/lang/String;ZZ)Z");
	if (mid == NULL || (*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		__android_log_print (ANDROID_LOG_ERROR, WKA_LOG_TAG,
			"addCookie: method not found");
		return FALSE;
	}

	dom = (domain != NULL) ? domain : "";
	pth = (path != NULL && path[0] != '\0') ? path : "/";

	jname = (*env)->NewStringUTF (env, name);
	jvalue = (*env)->NewStringUTF (env, value);
	jdomain = (*env)->NewStringUTF (env, dom);
	jpath = (*env)->NewStringUTF (env, pth);
	if (jname == NULL || jvalue == NULL || jdomain == NULL || jpath == NULL) {
		(*env)->ExceptionClear (env);
		if (jname != NULL) {
			(*env)->DeleteLocalRef (env, jname);
		}
		if (jvalue != NULL) {
			(*env)->DeleteLocalRef (env, jvalue);
		}
		if (jdomain != NULL) {
			(*env)->DeleteLocalRef (env, jdomain);
		}
		if (jpath != NULL) {
			(*env)->DeleteLocalRef (env, jpath);
		}
		return FALSE;
	}

	ok = (*env)->CallStaticBooleanMethod (env, cls, mid,
		jname, jvalue, jdomain, jpath,
		http_only ? JNI_TRUE : JNI_FALSE,
		secure ? JNI_TRUE : JNI_FALSE);
	(*env)->DeleteLocalRef (env, jname);
	(*env)->DeleteLocalRef (env, jvalue);
	(*env)->DeleteLocalRef (env, jdomain);
	(*env)->DeleteLocalRef (env, jpath);
	if ((*env)->ExceptionCheck (env)) {
		(*env)->ExceptionClear (env);
		return FALSE;
	}
	return ok == JNI_TRUE;
}
