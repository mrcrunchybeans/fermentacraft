// lib/pages/paywall_page.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../services/feature_gate.dart';
import '../services/revenuecat_service.dart';

class PaywallPage extends StatelessWidget {
  const PaywallPage({super.key, this.asDialog = false});

  /// When true, renders without a Scaffold/AppBar so it can live inside a dialog.
  final bool asDialog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final Widget content = SafeArea(
      child: Column(
        children: [
          // Header / hero
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    Icons.workspace_premium,
                    color: cs.onPrimaryContainer,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Unlock FermentaCraft Premium',
                        style: theme.textTheme.headlineSmall!.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Everything you need to ferment smarter.',
                        style: theme.textTheme.bodyMedium!.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (asDialog)
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context, false),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Body scroll
          Expanded(
            child: ScrollConfiguration(
              behavior: const _NoGlow(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Remove Free Version Limitations',
                      style: theme.textTheme.titleLarge!.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const _BenefitTile(
                      icon: Icons.all_inclusive,
                      title: 'Unlimited recipes, batches & inventory',
                      subtitle:
                          'Move past caps on recipes, active batches, and your inventory. Grow without limits.',
                    ),
                    const _BenefitTile(
                      icon: Icons.lock_open,
                      title: 'Unlock all soft-locked tools',
                      subtitle:
                          'Gain full access to advanced calculators and tools when you need them most.',
                    ),
                    const SizedBox(height: 16),
                    Divider(color: cs.outlineVariant),
                    const SizedBox(height: 16),
                    Text(
                      'What You Get with Premium',
                      style: theme.textTheme.titleLarge!.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const _FeatureBullet(
                      text: 'Unlimited recipes, batches, inventory, and archives',
                    ),
                    const _FeatureBullet(
                      text: 'Advanced tools: Gravity & ABV, pH, acid, SO₂, and strip readers',
                    ),
                    const _FeatureBullet(
                      text: 'Cloud sync across devices & full data export',
                    ),
                    const _FeatureBullet(text: 'No soft-lock interruptions'),
                    const _FeatureBullet(text: 'Directly support development'),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),

          // CTA area (sticky)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              boxShadow: const [
                BoxShadow(
                  blurRadius: 12,
                  offset: Offset(0, -2),
                  color: Color(0x33000000),
                ),
              ],
            ),
            child: FutureBuilder<Offerings>(
              future: RevenueCatService.instance.getOfferings(),
              builder: (context, snap) {
                final isLoading = snap.connectionState == ConnectionState.waiting;
                final hasError = snap.hasError;
                final offerings = snap.data;
                final current = offerings?.current;

                Package? annualPkg = _findPkg(current, idHint: 'annual');
                Package? monthlyPkg = _findPkg(current, idHint: 'monthly');

                final list = current?.availablePackages ?? const <Package>[];
                annualPkg ??= _firstByType(list, PackageType.annual) ?? (list.isNotEmpty ? list.first : null);
                monthlyPkg ??= _firstByType(list, PackageType.monthly) ??
                    (list.length >= 2 ? list[1] : (list.isNotEmpty ? list.first : null));

                final isMobile = !kIsWeb &&
                    (Theme.of(context).platform == TargetPlatform.android ||
                        Theme.of(context).platform == TargetPlatform.iOS);

                final String? monthlyIntroText = _buildIntroText(monthlyPkg);
                final String? annualIntroText = _buildIntroText(annualPkg);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: LinearProgressIndicator(),
                      ),
                    if (hasError)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Couldn’t load products. Please try again.',
                          style: TextStyle(color: cs.error),
                        ),
                      ),
                    if (!isLoading && !hasError && annualPkg == null && monthlyPkg == null)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text('No products available yet. Please try again later.'),
                      ),

                    if (!isMobile) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Purchases are only available on mobile. Sign in here, then buy on Android to unlock on Windows.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: _PlanOptionCard(
                              title: 'Yearly',
                              price: annualPkg?.storeProduct.priceString ?? '—',
                              subtitle: 'Best Value',
                              savings: 'Save vs monthly',
                              trialText: annualIntroText,
                              enabled: annualPkg != null && !isLoading && !hasError,
                              onPressed: () async {
                                if (annualPkg == null) return;
                                await _purchase(context, annualPkg);
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _PlanOptionCard(
                              title: 'Monthly',
                              price: monthlyPkg?.storeProduct.priceString ?? '—',
                              subtitle: 'Flexible',
                              trialText: monthlyIntroText,
                              enabled: monthlyPkg != null && !isLoading && !hasError,
                              onPressed: () async {
                                if (monthlyPkg == null) return;
                                await _purchase(context, monthlyPkg);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () async {
                        // Show quick feedback
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Restoring purchases...')),
                        );

                        try {
                          // 1) Ask RC/Play to re-sync receipts
                          final info = await Purchases.restorePurchases();

                          // 2) Trust only RevenueCat entitlements (not local flags)
                          final hasPremium = info.entitlements.active.containsKey('premium');

                          if (hasPremium) {
                            // Optional: update your own gate after the fact
                            FeatureGate.instance.refreshFromCustomerInfo(info);

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Purchases restored.')),
                              );
                              Navigator.of(context).maybePop(true);
                            }
                          } else {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('No previous purchases found.')),
                              );
                            }
                          }
                        } on PlatformException catch (e) {
                          final code = PurchasesErrorHelper.getErrorCode(e);
                          if (code == PurchasesErrorCode.purchaseCancelledError) {
                            return; // user backed out
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Restore failed: ${e.message ?? code.name}')),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Restore error: $e')),
                            );
                          }
                        }
                      },
                      child: const Text('Restore Purchases'),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );

    if (asDialog) return content;

    return Scaffold(
      appBar: AppBar(title: const Text('Go Premium')),
      body: content,
    );
  }

  static Package? _findPkg(Offering? current, {required String idHint}) {
    if (current == null) return null;
    try {
      return current.availablePackages.firstWhere(
        (p) =>
            p.identifier.toLowerCase().contains(idHint) ||
            p.storeProduct.title.toLowerCase().contains(idHint),
      );
    } catch (_) {
      return null;
    }
  }

  static Package? _firstByType(List<Package> list, PackageType type) {
    for (final p in list) {
      if (p.packageType == type) return p;
    }
    return null;
  }

  /// Build dynamic intro/trial text from RevenueCat StoreProduct.introductoryPrice.
  static String? _buildIntroText(Package? pkg) {
    final sp = pkg?.storeProduct;
    if (sp == null) return null;

    final intro = sp.introductoryPrice;
    if (intro == null) return null;

    final String periodIso = intro.period;
    final int cycles = intro.cycles;
    final String introPriceString = intro.priceString;
    final double introPrice = intro.price;

    final bool isFree = introPrice == 0.0;
    final String? periodLabel = _formatPeriod(periodIso);
    if (periodLabel == null) return null;

    if (isFree) {
      return 'Free for $periodLabel';
    } else {
      final String regular = sp.priceString;
      final String unit = _baseUnit(periodIso) ?? 'period';
      final String cyclesLabel =
          cycles > 1 ? ' for $cycles ${_pluralize(unit, cycles)}' : ' for 1 $unit';
      final String billingUnit = _billingUnit(sp.subscriptionPeriod ?? '');
      return 'Intro: $introPriceString$cyclesLabel, then $regular/$billingUnit';
    }
  }

  static String _billingUnit(String iso) {
    final unit = _baseUnit(iso);
    return unit ?? 'period';
  }

  static String? _baseUnit(String? iso) {
    if (iso == null) return null;
    if (iso.contains('D')) return 'day';
    if (iso.contains('W')) return 'week';
    if (iso.contains('M')) return 'month';
    if (iso.contains('Y')) return 'year';
    return null;
  }

  static String _pluralize(String unit, int n) => n == 1 ? unit : '${unit}s';

  static String? _formatPeriod(String? iso) {
    if (iso == null) return null;

    int value = 0;
    String unit = '';
    final dIdx = iso.indexOf('D');
    final wIdx = iso.indexOf('W');
    final mIdx = iso.indexOf('M');
    final yIdx = iso.indexOf('Y');

    if (dIdx != -1) {
      value = int.tryParse(iso.substring(1, dIdx)) ?? 0;
      unit = 'day';
    } else if (wIdx != -1) {
      value = int.tryParse(iso.substring(1, wIdx)) ?? 0;
      unit = 'week';
    } else if (mIdx != -1) {
      value = int.tryParse(iso.substring(1, mIdx)) ?? 0;
      unit = 'month';
    } else if (yIdx != -1) {
      value = int.tryParse(iso.substring(1, yIdx)) ?? 0;
      unit = 'year';
    }

    if (value <= 0) return null;
    return '$value ${value == 1 ? unit : '${unit}s'}';
  }

  static Future<void> _purchase(BuildContext context, Package pkg) async {
    try {
      await RevenueCatService.instance.purchasePackage(pkg);
      if (FeatureGate.instance.isPremium && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks for upgrading!')),
        );
        Navigator.of(context).maybePop(true);
      }
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Purchase failed: ${e.message ?? code.name}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Purchase error: $e')),
        );
      }
    }
  }
}

class _BenefitTile extends StatelessWidget {
  const _BenefitTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureBullet extends StatelessWidget {
  const _FeatureBullet({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline,
              size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _PlanOptionCard extends StatelessWidget {
  const _PlanOptionCard({
    required this.title,
    required this.price,
    required this.subtitle,
    required this.onPressed,
    this.savings,
    this.trialText,
    this.enabled = true,
  });

  final String title;
  final String price;
  final String subtitle;
  final String? savings;
  final String? trialText;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isBestValue = savings != null;

    return Semantics(
      container: true,
      label: '$title plan',
      child: Opacity(
        opacity: enabled ? 1.0 : 0.6,
        child: IgnorePointer(
          ignoring: !enabled,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isBestValue ? cs.primaryContainer.withValues(alpha: 0.2) : cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isBestValue ? cs.primary : cs.outlineVariant,
                width: isBestValue ? 2.0 : 1.0,
              ),
            ),
            child: Column(
              children: [
                if (isBestValue)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'BEST VALUE',
                      style: theme.textTheme.labelSmall!.copyWith(
                        color: cs.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium!.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (trialText != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    trialText!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  price == '—' ? 'Loading...' : '$price / ${title.toLowerCase()}',
                  style: theme.textTheme.titleLarge!.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (savings != null)
                  Text(
                    savings!,
                    style: theme.textTheme.labelMedium!.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onPressed,
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          isBestValue ? cs.primary : cs.surfaceContainerHigh,
                      foregroundColor: isBestValue ? cs.onPrimary : cs.onSurface,
                    ),
                    child: Text(isBestValue ? 'Go Yearly' : 'Go Monthly'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoGlow extends ScrollBehavior {
  const _NoGlow();
  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}
