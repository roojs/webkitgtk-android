# Valadoc API docs (webview2-gtk / OLLMchat pattern).
#
# When adding/removing public .vala under lib/webkitgtkandroid/, update the list.
# Local: meson setup build-docs -Ddocs=true && ninja -C build-docs docs/valadoc
#
valadoc = find_program('valadoc', required: true)
valadoc_runner = find_program(meson.current_source_dir() / 'run-valadoc.sh')

valadoc_dir = meson.project_build_root() / 'valadoc'
valadoc_clean = custom_target(
  'valadoc-clean',
  output: 'valadoc-clean',
  command: [
    find_program('sh'),
    '-c',
    'if [ -d "@0@" ]; then rm -rf "@0@"; fi'.format(valadoc_dir),
  ],
  build_by_default: false,
)

valadoc_docs = custom_target(
  'valadoc',
  input: files(
    '../lib/webkitgtkandroid/namespace.vala',
    '../lib/webkitgtkandroid/URIRequest.vala',
    '../lib/webkitgtkandroid/CookieManager.vala',
    '../lib/webkitgtkandroid/Download.vala',
    '../lib/webkitgtkandroid/NetworkSession.vala',
    '../lib/webkitgtkandroid/WebView.vala',
  ),
  output: ['valadoc'],
  depends: [valadoc_clean],
  command: [
    valadoc_runner,
    valadoc_dir,
    '--package-name=webkitgtk-android',
    '--package-version=@0@'.format(meson.project_version()),
    '--vapidir', meson.current_source_dir() / '../vapi',
    '--vapidir', '/usr/share/vala/vapi',
    '--pkg=glib-2.0',
    '--pkg=gobject-2.0',
    '--pkg=gio-2.0',
    '--pkg=gtk4',
    '--pkg=libsoup-3.0',
    '--doclet=html',
    '--wiki=@0@'.format(meson.current_source_dir() / 'valadoc-wiki'),
    '--directory=' + valadoc_dir,
    '@INPUT@',
  ],
  build_by_default: false,
  install: false,
)
