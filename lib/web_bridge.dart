// Picks the web implementation on Flutter Web and a no-op stub elsewhere.
export 'web_bridge_stub.dart'
  if (dart.library.js_interop) 'web_bridge_web.dart';
