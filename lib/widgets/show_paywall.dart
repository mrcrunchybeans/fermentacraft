import 'package:flutter/material.dart';
import 'package:fermentacraft/pages/paywall_page.dart';

Future<void> showPaywall(BuildContext context) {
  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Material(
          color: Theme.of(ctx).colorScheme.surface,
          elevation: 8,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: const PaywallPage(asDialog: true),
        ),
      ),
    ),
  );
}
