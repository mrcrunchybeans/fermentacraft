// lib/widgets/show_paywall.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../pages/paywall_page.dart';
import '../services/revenuecat_service.dart';

Future<void> showPaywall(BuildContext context) async {
  // Ensure RevenueCat is logged into the same user as Firebase (if signed in)
  final u = FirebaseAuth.instance.currentUser;
  if (u != null) {
    try {
      // Check if RevenueCat is configured before attempting login
      if (RevenueCatService.instance.isConfigured) {
        final appUserID = await Purchases.appUserID;
        if (appUserID.isNotEmpty) {
          await Purchases.logIn(u.uid);
        }
      }
    } catch (_) {
      // ignore login errors; RevenueCat might not be configured
    }
  }

  // ✅ Fix: guard context usage after the await above
  if (!context.mounted) return;

  // Show the paywall as a dialog (same UX you had before)
  await showDialog(
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
