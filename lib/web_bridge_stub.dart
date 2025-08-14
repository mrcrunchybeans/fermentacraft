// lib/web_bridge_stub.dart
Future<String?> saveBytesToDevice(String fileName, List<int> bytes) async => null;

void hideHtmlSplash() {}
void ensureFlutterRootCss() {}
void scrubLegacyOverlays() {}

void startSplashWatchdog({Duration timeout = const Duration(seconds: 8)}) {}
void cancelSplashWatchdog() {}
void postSplashComplete() {}
void setAuthInProgress(bool value) {}

void disableServiceWorkers() {}
void enableReloadDiagnostics({bool blockReload = true}) {}
String? lastReloadCause() => null;

void wipeNamespacedStorage({String prefix = 'fc_'}) {}
