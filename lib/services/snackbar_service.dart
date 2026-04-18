import 'dart:async';

import 'package:flutter/material.dart';

class SnackbarService {
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();
  static ScaffoldMessengerState? get _m => messengerKey.currentState;

  static void show(SnackBar bar, {Duration? explicitDuration}) {
    final effectiveDuration = explicitDuration ?? bar.duration;
    _m?.hideCurrentSnackBar();
    _m?.showSnackBar(bar);

    Timer(effectiveDuration, hide);
  }

  static void text(String msg, {Duration? duration}) =>
      show(SnackBar(content: Text(msg), duration: duration ?? const Duration(seconds: 3)));

  static void clear() => _m?..clearSnackBars();
  static void hide()  => _m?..hideCurrentSnackBar();
}

/// Clears snackbars on route transitions so they never get stuck under overlays.
class ClearSnackbarsOnNavigate extends NavigatorObserver {
  void _clear() => SnackbarService.clear();

  @override
  void didPush(Route route, Route<dynamic>? previousRoute) => _clear();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _clear();

  @override
  void didPop(Route route, Route<dynamic>? previousRoute) => _clear();
}
