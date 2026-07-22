project(
  'webkitgtk-android',
  ['c', 'vala'],
  version: '0.1.0',
  meson_version: '>= 1.8.0',
  default_options: [
    'warning_level=1',
    'c_std=gnu11',
  ],
)

is_android = host_machine.system() == 'android'
want_docs = get_option('docs')

if not is_android and not want_docs
  error('webkitgtk-android builds for Android cross only. Use -Ddocs=true for Valadoc on Linux.')
endif

if want_docs
  subdir('docs')
endif

if not is_android
  # Docs-only configure (CI / local Valadoc). Library and demos need Android.
  subdir_done()
endif

if get_option('android_hello') and get_option('android_browser')
  error('Pass only one of -Dandroid_hello=true or -Dandroid_browser=true')
endif

gtk_dep = dependency('gtk4')
adw_dep = dependency('libadwaita-1')
gio_dep = dependency('gio-2.0')
glib_dep = dependency('glib-2.0')
gobject_dep = dependency('gobject-2.0')
soup_dep = dependency(
  'libsoup-3.0',
  default_options: [
    'introspection=disabled',
    'vapi=disabled',
    'docs=disabled',
    'tests=false',
    'tls_check=false',
    'sysprof=disabled',
    'brotli=disabled',
    'gssapi=disabled',
    'ntlm=disabled',
  ],
)
log_dep = meson.get_compiler('c').find_library('log')

lib_deps = [gtk_dep, gio_dep, glib_dep, gobject_dep, soup_dep, log_dep]
lib_vala_args = [
  '--pkg=gtk4',
  '--pkg=gio-2.0',
  '--pkg=glib-2.0',
  '--pkg=gobject-2.0',
  '--pkg=libsoup-3.0',
  '--pkg=posix',
]

# Pure hello APK has no libsoup in Pixiewood — skip the WebView library there.
build_library = not get_option('android_hello') or get_option('android_browser')

if build_library
  host_inc = include_directories('lib/host')
  lib_sources = files(
    'lib/webkitgtkandroid/namespace.vala',
    'lib/webkitgtkandroid/CookieManager.vala',
    'lib/webkitgtkandroid/URIRequest.vala',
    'lib/webkitgtkandroid/Download.vala',
    'lib/webkitgtkandroid/NetworkSession.vala',
    'lib/webkitgtkandroid/WebView.vala',
    'lib/webkitgtkandroid/AndroidAtspi.vala',
    'lib/host/webkitgtk-android-host.c',
    'lib/host/webkitgtk-android-bounds.c',
    'lib/host/webkitgtk-android-a11y.c',
    'lib/host/webkitgtk-android-cookies.c',
    'lib/host/webkitgtk-android-downloads.c',
  )

  webkitgtk_android_lib = library(
    'webkitgtk-android-1',
    lib_sources,
    dependencies: lib_deps,
    include_directories: host_inc,
    vala_args: lib_vala_args,
    c_args: ['-DANDROID'],
    vala_header: 'webkitgtk-android.h',
    vala_vapi: 'webkitgtk-android-1.vapi',
    install: true,
  )

  install_headers(
    'lib/host/webkitgtk-android-host-api.h',
  )

  # Checked-in VAPI for prefix / wrap consumers. (Pixiewood APK installs often
  # stage runtime .so only; prefer Meson subproject + override_dependency.)
  install_data(
    'vapi/webkitgtk-android-1.vapi',
    install_dir: get_option('datadir') / 'vala' / 'vapi',
  )

  pkg = import('pkgconfig')
  pkg.generate(
    webkitgtk_android_lib,
    name: 'webkitgtk-android-1',
    description: 'GTK 4 widget embedding Android System WebView (WebKitGTK-shaped)',
    filebase: 'webkitgtk-android-1',
    requires: ['gtk4', 'libsoup-3.0', 'glib-2.0', 'gobject-2.0', 'gio-2.0'],
    libraries: [log_dep],
    variables: [
      'vapidir=${datadir}/vala/vapi',
    ],
  )

  # Vala-generated webkitgtk-android.h lives in this subproject's build dir.
  webkitgtk_android_dep = declare_dependency(
    link_with: webkitgtk_android_lib,
    include_directories: host_inc,
    dependencies: lib_deps,
    compile_args: ['-I' + meson.current_build_dir()],
  )
  meson.override_dependency('webkitgtk-android-1', webkitgtk_android_dep)
endif

if get_option('android_browser')
  executable(
    'webkitgtk-android-browser',
    files(
      'examples/browser/main.vala',
      'examples/browser/host-a11y.vala',
    ),
    dependencies: [webkitgtk_android_dep, adw_dep],
    vala_args: lib_vala_args + ['--pkg=libadwaita-1'],
    c_args: ['-DANDROID'],
    android_exe_type: 'application',
    install: true,
    install_dir: get_option('libdir'),
  )
elif get_option('android_hello')
  executable(
    'webkitgtk-android-hello',
    files('examples/hello/main.vala'),
    dependencies: [gtk_dep, adw_dep, gio_dep, glib_dep, gobject_dep],
    vala_args: [
      '--pkg=gtk4',
      '--pkg=libadwaita-1',
      '--pkg=gio-2.0',
      '--pkg=glib-2.0',
      '--pkg=gobject-2.0',
    ],
    android_exe_type: 'application',
    install: true,
    install_dir: get_option('libdir'),
  )
endif
