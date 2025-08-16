// lib/web_bridge_web.dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:js_interop'; // ← needed for .toJS and .dartify()
import 'package:web/web.dart' as web;

Timer? _splashWatchdog;
const _kSplashKey = 'fc_splash_done';
const _kAuthKey   = 'fc_auth_in_progress';

void hideHtmlSplash() {
  try {
    web.document.getElementById('splash')?.remove();
    web.document.getElementById('splash-branding')?.remove();
    final body = web.document.body;
    if (body != null) {
      body.style.background = 'transparent';
      body.style.removeProperty('background-image');
      body.style.removeProperty('background-size');
      body.style.removeProperty('background-color');
    }
  } catch (_) {}
}

void ensureFlutterRootCss() {
  try {
    const styleId = 'fc-flutter-root-css';
    if (web.document.getElementById(styleId) != null) return;

    final style = web.HTMLStyleElement()..id = styleId;
    style.textContent = '''
      html, body { height: 100%; margin: 0; padding: 0; }
      #flutter, #flutter-root {
        position: fixed; inset: 0;
        width: 100vw; height: 100vh;
        background: transparent !important;
      }
    ''';
    web.document.head?.append(style);
  } catch (_) {}
}

void scrubLegacyOverlays() {
  try {
    for (final id in const ['splash-screen-style', 'splash-screen-script']) {
      web.document.getElementById(id)?.remove();
    }
  } catch (_) {}
}

/// Arms a watchdog that reloads the page if splash never completes.
/// No side effects on import; call this explicitly.
void startSplashWatchdog({Duration timeout = const Duration(seconds: 8)}) {
  // If splash already done or auth is happening, don't arm.
  if (_sessionGet(_kSplashKey) == '1') return;
  if (_sessionGet(_kAuthKey) == '1') return;

  // Listen for legacy 'splash_complete' message as well.
StreamSubscription<web.MessageEvent>? sub;
  sub = web.window.onMessage.listen((evt) {
    final data = evt.data?.dartify(); // JSAny? → Dart
    if (data == 'splash_complete') {
      _markSplashDone();
      sub?.cancel();
    }
  });

  _splashWatchdog?.cancel();
  _splashWatchdog = Timer(timeout, () {
    sub?.cancel();
    if (_sessionGet(_kSplashKey) != '1' && _sessionGet(_kAuthKey) != '1') {
      try { web.window.location.reload(); } catch (_) {}
    }
  });
}

void cancelSplashWatchdog() {
  _splashWatchdog?.cancel();
  _splashWatchdog = null;
}

/// Marks splash complete persistently, cancels timers, and hides splash.
void postSplashComplete() {
  _markSplashDone();
  // Also send the legacy message (must be JS values).
  try { web.window.postMessage('splash_complete'.toJS, '*'.toJS); } catch (_) {}
  hideHtmlSplash();
}

void setAuthInProgress(bool value) {
  _sessionSet(_kAuthKey, value ? '1' : '0');
  if (value) cancelSplashWatchdog();
}

void _markSplashDone() {
  _sessionSet(_kSplashKey, '1');
  cancelSplashWatchdog();
}

String? _sessionGet(String key) {
  try { return web.window.sessionStorage.getItem(key); } catch (_) { return null; }
}
void _sessionSet(String key, String value) {
  try { web.window.sessionStorage.setItem(key, value); } catch (_) {}
}

void wipeNamespacedStorage({String prefix = 'fc_'}) {
  try {
    final ls = web.window.localStorage;
    final toRemove = <String>[];
    for (var i = 0; i < ls.length; i++) {
      final k = ls.key(i);
      if (k != null && k.startsWith(prefix)) toRemove.add(k);
    }
    for (final k in toRemove) {
      ls.removeItem(k);
    }

    final ss = web.window.sessionStorage;
    final sRemove = <String>[];
    for (var i = 0; i < ss.length; i++) {
      final k = ss.key(i);
      if (k != null && k.startsWith(prefix)) sRemove.add(k);
    }
    for (final k in sRemove) {
      ss.removeItem(k);
    }
  } catch (_) {}
}

// Optional: keep your file-save helper for web downloads.
Future<String?> saveBytesToDevice(String fileName, List<int> bytes) async {
  try {
    final data = Uint8List.fromList(bytes);
    final blob = web.Blob([data.toJS].toJS,
        web.BlobPropertyBag(type: 'application/octet-stream'));
    final url = web.URL.createObjectURL(blob);
    final a = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName;
    web.document.body?.append(a);
    a.click();
    a.remove();
    web.URL.revokeObjectURL(url);
  } catch (_) {}
  return null;
}
void enableReloadDiagnostics({bool blockReload = true}) {
  try {
    final w = web.window;
    final dynW = w as dynamic;
    if (dynW.__fcReloadPatched__ == true) return;
    dynW.__fcReloadPatched__ = true;

    final loc = w.location as dynamic;
    final origReload  = loc.reload;
    final origAssign  = loc.assign;
    final origReplace = loc.replace;

    // Record cause in sessionStorage so you can read it after a refresh.
    void mark(String cause) {
      try { w.sessionStorage.setItem('fc_reload_cause', cause); } catch (_) {}
    }

    loc.reload = ([arg]) {
      mark('location.reload');
      if (!blockReload) return origReload.call(loc, arg);
      // block, but you can watch the console and storage to see who tried
      return null;
    };
    loc.assign = (url) {
      mark('location.assign:$url');
      return origAssign.call(loc, url);
    };
    loc.replace = (url) {
      mark('location.replace:$url');
      return origReplace.call(loc, url);
    };

    dynW.onbeforeunload = (e) => mark('beforeunload');
  } catch (_) {}
}

/// Optional: nuke any registered service workers (sometimes they force updates)
void disableServiceWorkers() {
  try {
    final sw = (web.window.navigator.serviceWorker as dynamic);
    sw?.getRegistrations()?.then((regs) {
      for (final reg in regs as List<dynamic>) {
        try { reg.unregister(); } catch (_) {}
      }
    });
  } catch (_) {}
}

/// Read what triggered the last reload/navigation.
String? lastReloadCause() {
  try { return web.window.sessionStorage.getItem('fc_reload_cause'); } catch (_) { return null; }
}
