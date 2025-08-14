// lib/utils/money.dart
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:fermentacraft/models/settings_model.dart';

/// Formats an amount using the user's selected currency symbol.
/// Rebuilds automatically when the user changes the symbol.
String moneyText(BuildContext context, num? amount, {int decimals = 2}) {
  if (amount == null) return '—';
  final symbol = context.select<SettingsModel, String>((s) => s.currencySymbol);
  final neg = amount.isNegative;
  final abs = amount.abs().toDouble().toStringAsFixed(decimals);
  return neg ? '-$symbol$abs' : '$symbol$abs';
}

/// If you are **outside** the widget tree (e.g., in a service) or in an
/// event handler where you can't subscribe to Provider, pass the symbol in.
String moneyWithSymbol(String symbol, num? amount, {int decimals = 2}) {
  if (amount == null) return '—';
  final neg = amount.isNegative;
  final abs = amount.abs().toDouble().toStringAsFixed(decimals);
  return neg ? '-$symbol$abs' : '$symbol$abs';
}
