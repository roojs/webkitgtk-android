/* Demo-only host a11y entry points (not on WebView).
 * WkaA11yForeachCb comes from the library’s generated VAPI.
 */

[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern bool wka_host_a11y_ensure ();

[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern bool wka_host_a11y_walk_foreach (WkaA11yForeachCb cb, void* user_data);

[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern bool wka_host_a11y_invoke (int id);

[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern bool wka_host_a11y_set_value (int id, string utf8);

[CCode (cheader_filename = "webkitgtk-android-host-api.h")]
extern bool wka_host_a11y_focus (int id);
