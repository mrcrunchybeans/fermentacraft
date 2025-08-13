// lib/main.dart
import 'dart:async';
import 'dart:js_interop';                    // for .dartify()
import 'package:web/web.dart' as web;        // modern web APIs

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';
import 'utils/cache_keys.dart';
import 'pages/splash_page.dart';
import 'home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Firestore settings (safe across platforms)
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);

  if (kIsWeb) {
    // Start watchdog BEFORE runApp so the splash page hang is recoverable.
    _startSplashWatchdog();
  }

  runApp(const MyApp());
}

/// Splash watchdog: if we don't see a 'splash_complete' message within N seconds,
/// wipe ONLY our fc_-scoped keys and reload the page.
void _startSplashWatchdog() {
  const splashTimeout = Duration(seconds: 8);

  var splashLoaded = false;

  // Listen for the completion signal from your SplashPage.
  // Make sure SplashPage posts: window.postMessage('splash_complete', '*');
  web.window.onMessage.listen((evt) {
    // evt is web.MessageEvent; evt.data is a JS value (JSAny).
    final jsAny = evt.data;
    final dartData = jsAny?.dartify(); // -> dart String/num/bool/map/list/etc
    if (dartData == 'splash_complete') {
      splashLoaded = true;
    }
  });

  // After a timeout, if still not loaded, nuke fc_-scoped caches & hard reload.
  Future.delayed(splashTimeout, () {
    if (!splashLoaded) {
      _clearAppScopedCache();
      web.window.location.reload();
    }
  });
}

void _clearAppScopedCache() {
  try {
    // localStorage
    final ls = web.window.localStorage;
    final toRemove = <String>[];
    for (var i = 0; i < ls.length; i++) {
      final key = ls.key(i);
      if (key != null && CacheKeys.hasPrefix(key)) {
        toRemove.add(key);
      }
    }
    for (final k in toRemove) {
      ls.removeItem(k);
    }

    // sessionStorage (optional)
    final ss = web.window.sessionStorage;
    final sRemove = <String>[];
    for (var i = 0; i < ss.length; i++) {
      final key = ss.key(i);
      if (key != null && CacheKeys.hasPrefix(key)) {
        sRemove.add(key);
      }
    }
    for (final k in sRemove) {
      ss.removeItem(k);
    }
  } catch (e) {
    // Non-fatal: worst case we just fail to clean and the user can hard-refresh.
    // Avoid spamming logs; this only runs when something is already broken.
    // ignore: avoid_print
    print('App-scoped cache wipe failed: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FermentaCraft',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.green),
      home: const SplashPage(nextPage: HomePage()),
    );
  }
}
