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

if host_machine.system() != 'android'
  error('This project currently builds for Android cross only')
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

common_deps = [gtk_dep, adw_dep, gio_dep, glib_dep, gobject_dep, soup_dep]
common_vala_args = [
  '--pkg=gtk4',
  '--pkg=libadwaita-1',
  '--pkg=gio-2.0',
  '--pkg=glib-2.0',
  '--pkg=gobject-2.0',
  '--pkg=libsoup-3.0',
]

if get_option('android_browser')
  host_inc = include_directories('lib/host')
  log_dep = meson.get_compiler('c').find_library('log')
  browser_sources = files(
    'examples/browser/main.vala',
    'lib/webkitgtkandroid/webview.vala',
    'lib/webkitgtkandroid/network-session.vala',
    'lib/host/webkitgtk-android-host.c',
    'lib/host/webkitgtk-android-bounds.c',
    'lib/host/webkitgtk-android-a11y.c',
    'lib/host/webkitgtk-android-cookies.c',
  )
  executable(
    'webkitgtk-android-browser',
    browser_sources,
    dependencies: common_deps + [log_dep],
    include_directories: host_inc,
    vala_args: common_vala_args,
    c_args: ['-DANDROID'],
    android_exe_type: 'application',
    install: true,
    install_dir: get_option('libdir'),
  )
elif get_option('android_hello')
  executable(
    'webkitgtk-android-hello',
    files('examples/hello/main.vala'),
    dependencies: common_deps,
    vala_args: common_vala_args,
    android_exe_type: 'application',
    install: true,
    install_dir: get_option('libdir'),
  )
else
  error('Pass -Dandroid_browser=true (Phase 2) or -Dandroid_hello=true (Phase 1)')
endif
