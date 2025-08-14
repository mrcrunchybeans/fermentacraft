import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/feature_gate.dart';
import '../services/revenuecat_service.dart';
import 'show_paywall.dart';

class PlanBadge extends StatelessWidget {
  const PlanBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final gate = context.watch<FeatureGate>(); // 👈 reactive
    if (gate.isPremium) {
      return const Chip(
        avatar: Icon(Icons.verified, size: 18),
        label: Text('Premium'),
      );
    }
    return ActionChip(
      avatar: const Icon(Icons.star_border, size: 18),
      label: const Text('Free'),
      onPressed: () async {
        await showPaywall(context);
        if (!context.mounted) return;
        // Ensure RC state is pulled in, which mirrors into FeatureGate
        try {
          await RevenueCatService.instance.refreshCustomerInfo();
        } catch (_) {}
      },
    );
  }
}
