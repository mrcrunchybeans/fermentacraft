import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/feature_gate.dart';
import '../services/revenuecat_service.dart';
import 'show_paywall.dart';

class PlanBadge extends StatelessWidget {
  const PlanBadge({super.key});

  @override
  Widget build(BuildContext context) {
    // Only rebuild when the plan enum changes.
    return Selector<FeatureGate, Plan>(
      selector: (_, gate) => gate.plan,
      builder: (context, plan, _) {
        switch (plan) {
          case Plan.proOffline:
            return _BadgeChip(
              icon: Icons.cloud_off,
              label: 'Pro-Offline',
              tooltip: 'All offline premium features unlocked.\nTap to manage / switch plans.',
              onTap: () async => _openPaywallAndMaybeRefresh(context),
            );

          case Plan.premium:
            return _BadgeChip(
              icon: Icons.verified,
              label: 'Premium',
              tooltip: 'Cloud sync + all features.\nTap to manage / switch plans.',
              onTap: () async => _openPaywallAndMaybeRefresh(context),
            );

          case Plan.free:
          return ActionChip(
              avatar: const Icon(Icons.star_border, size: 18),
              label: const Text('Free'),
              tooltip: 'Tap to see upgrade options',
              onPressed: () async {
                await showPaywall(context);
                if (!context.mounted) return;
                // Pull RC state on mobile if supported (mirrors into FeatureGate).
                if (RevenueCatService.instance.isSupported) {
                  try {
                    await RevenueCatService.instance.refreshCustomerInfo();
                  } catch (_) {}
                }
              },
            );
        }
      },
    );
  }
}

/// Small helper so Premium/Pro-Offline chips can also be tappable with a tooltip.
class _BadgeChip extends StatelessWidget {
  const _BadgeChip({
    required this.icon,
    required this.label,
    this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
    );

    final wrapped = tooltip != null
        ? Tooltip(message: tooltip!, child: chip)
        : chip;

    // If no onTap provided, just return plain chip.
    if (onTap == null) return wrapped;

    // Make chip tappable with proper semantics.
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: wrapped,
      ),
    );
  }
}

Future<void> _openPaywallAndMaybeRefresh(BuildContext context) async {
  await showPaywall(context);
  if (!context.mounted) return;

  // If the user changed plans via RC, reflect it.
  if (RevenueCatService.instance.isSupported) {
    try {
      await RevenueCatService.instance.refreshCustomerInfo();
    } catch (_) {}
  }
}
