import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class FirestoreBoot {
  static bool _done = false;
  static void ensure() {
    if (_done) return;

    if (kIsWeb) {
      // Force-create the default instance early; don't set settings on web.
      FirebaseFirestore.instance;
    } else {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    }

    // Optional: if you want to be extra safe, only enable logging off-web.
    // FirebaseFirestore.setLoggingEnabled(true);

    _done = true;
  }
}
