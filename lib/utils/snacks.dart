import 'package:flutter/material.dart';
import 'package:fermentacraft/services/snackbar_service.dart';

class _SnacksFacade {
  void show(SnackBar bar) => SnackbarService.show(bar);
  void text(String msg, {Duration? duration}) =>
      SnackbarService.text(msg, duration: duration);
  void clear() => SnackbarService.clear();
  void hide()  => SnackbarService.hide();
}

final snacks = _SnacksFacade();
