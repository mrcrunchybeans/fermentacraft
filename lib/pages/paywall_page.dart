// lib/pages/paywall_page.dart
// ignore_for_file: deprecated_member_use

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fermentacraft/utils/snacks.dart';
import '../services/feature_gate.dart';
import '../services/revenuecat_service.dart';
import '../services/stripe_billing_service.dart';
import '../services/stripe_pricing_service.dart';

class PaywallPage extends StatelessWidget {
  const PaywallPage({super.key, this.asDialog = false});
  final bool asDialog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final content = SafeArea(
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
                  child: Icon(Icons.workspace_premium, color: cs.onPrimaryContainer, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Unlock FermentaCraft Premium',
                          style: theme.textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Everything you need to ferment smarter.',
                          style: theme.textTheme.bodyMedium!.copyWith(color: cs.onSurfaceVariant)),
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

          const SizedBox(height: 12),

          // Body (scrolls): benefits → plans → legal
          Expanded(
            child: ScrollConfiguration(
              behavior: const _NoGlow(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle('Remove Free Version Limitations'),
                    SizedBox(height: 10),
                    _BenefitTile(
                      icon: Icons.all_inclusive,
                      title: 'Unlimited recipes, batches & inventory',
                      subtitle:
                          'Move past caps on recipes, active batches, and your inventory. Grow without limits.',
                    ),
                    _BenefitTile(
                      icon: Icons.lock_open,
                      title: 'Unlock all soft-locked tools',
                      subtitle: 'Gain full access to advanced calculators and tools when you need them most.',
                    ),
                    SizedBox(height: 14),
                    _Divider(),
                    SizedBox(height: 14),
                    _SectionTitle('What You Get with Premium'),
                    SizedBox(height: 10),
                    _FeatureBullet(text: 'Unlimited recipes, batches, inventory, and archives'),
                    _FeatureBullet(text: 'Advanced tools: Gravity & ABV, pH, acid, SO₂, and strip readers'),
                    _FeatureBullet(text: 'Cloud sync across devices & full data export'),
                    _FeatureBullet(text: 'No soft-lock interruptions'),
                    _FeatureBullet(text: 'Directly support development'),
                    SizedBox(height: 18),

                    _PlansSection(), // compact plans live inline in the scroll
                    SizedBox(height: 12),

                    _LegalFooter(),
                    SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),

          // Small fixed bottom action row
          const _RestoreRow(),
        ],
      ),
    );

    if (asDialog) return content;

    return Scaffold(
      appBar: AppBar(title: const Text('Go Premium')),
      body: content,
    );
  }
}

/* ============================
    Plans switcher (inline)
   ============================ */

class _PlansSection extends StatelessWidget {
  const _PlansSection();

  @override
  Widget build(BuildContext context) {
    final bool useStripe = kIsWeb || !RevenueCatService.instance.isSupported;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Choose your plan'),
        const SizedBox(height: 10),
        if (useStripe) const _StripePlans() else const _RevenueCatPlans(),
      ],
    );
  }
}

/* ============================
    RevenueCat (Android / iOS)
   ============================ */

class _RevenueCatPlans extends StatelessWidget {
  const _RevenueCatPlans();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FutureBuilder<Offerings>(
      future: RevenueCatService.instance.getOfferings(),
      builder: (context, snap) {
        final isLoading = snap.connectionState == ConnectionState.waiting;
        final hasError = snap.hasError;
        final current = snap.data?.current;

        Package? annual = _findPkg(current, idHint: 'annual');
        Package? monthly = _findPkg(current, idHint: 'monthly');

        final list = current?.availablePackages ?? const <Package>[];
        annual ??= _firstByType(list, PackageType.annual) ?? (list.isNotEmpty ? list.first : null);
        monthly ??= _firstByType(list, PackageType.monthly) ??
            (list.length >= 2 ? list[1] : (list.isNotEmpty ? list.first : null));

        final bool noProducts = !isLoading && !hasError && (current == null || current.availablePackages.isEmpty);

        if (isLoading) return const LinearProgressIndicator();
        if (hasError) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Couldn’t load products. Please try again.', style: TextStyle(color: cs.error)),
          );
        }
        if (noProducts) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('No products available yet. Please try again later.'),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 380;

            final cards = [
              _PlanOptionCard.compact(
                title: 'Yearly',
                price: annual?.storeProduct.priceString ?? '—',
                badge: 'Best value',
                note: 'Billed yearly',
                trialText: _buildIntroText(annual),
                enabled: annual != null,
                onPressed: () async {
                  if (annual != null) await _purchase(context, annual);
                },
              ),
              _PlanOptionCard.compact(
                title: 'Monthly',
                price: monthly?.storeProduct.priceString ?? '—',
                note: 'Billed monthly',
                trialText: _buildIntroText(monthly),
                enabled: monthly != null,
                onPressed: () async {
                  if (monthly != null) await _purchase(context, monthly);
                },
              ),
            ];

            if (narrow) {
              // Horizontal swipe on phones (shorter vertical footprint)
              return SizedBox(
                height: 168,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: cards.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => SizedBox(width: constraints.maxWidth * .88, child: cards[i]),
                ),
              );
            } else {
              // Side-by-side on wider devices
              return Row(
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 12),
                  Expanded(child: cards[1]),
                ],
              );
            }
          },
        );
      },
    );
  }
}

/* ============================
    Stripe (Web / Desktop)
   ============================ */

class _StripePlans extends StatelessWidget {
  const _StripePlans();

  // Replace with your real Price IDs
  static const _yearlyPriceId = 'price_1RuoNRE9CXcdIoFtbE2wYOZj';
  static const _monthlyPriceId = 'price_1RuoNTE9CXcdIoFtrLcI8ujI';

  // Where Stripe redirects after success/cancel (must be HTTPS & yours)
  static final _successUrl = Uri.parse('https://app.fermentacraft.com/checkout/success');
  static final _cancelUrl = Uri.parse('https://app.fermentacraft.com/checkout/cancel');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 4),
        Text('Buy Premium securely via Stripe Checkout.',
            textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 10),

        FutureBuilder<Map<String, StripePrice>>(
          future: StripePricingService.instance.fetchPrices([
            _yearlyPriceId,
            _monthlyPriceId,
          ]),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              );
            }

            String yearly = '—';
            String monthly = '—';

            if (snap.hasData) {
              final map = snap.data!;
              yearly = map[_yearlyPriceId]?.toMoney() ?? '—';
              monthly = map[_monthlyPriceId]?.toMoney() ?? '—';
            }

            if (snap.hasError) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  snacks.show(SnackBar(content: Text('Pricing unavailable: ${snap.error}')));
                }
              });
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 380;

                final cards = [
                  _PlanOptionCard.compact(
                    title: 'Yearly',
                    price: yearly,
                    badge: 'Best value',
                    note: 'Billed yearly',
                    onPressed: () async {
                      final messenger = snacks;
                      try {
                        await StripeBillingService.instance.startCheckout(
                          priceId: _yearlyPriceId,
                          successUrl: _successUrl,
                          cancelUrl: _cancelUrl,
                        );
                      } catch (e) {
                        messenger.show(SnackBar(content: Text('Checkout error: $e')));
                      }
                    },
                  ),
                  _PlanOptionCard.compact(
                    title: 'Monthly',
                    price: monthly,
                    note: 'Billed monthly',
                    onPressed: () async {
                      final messenger = snacks;
                      try {
                        await StripeBillingService.instance.startCheckout(
                          priceId: _monthlyPriceId,
                          successUrl: _successUrl,
                          cancelUrl: _cancelUrl,
                        );
                      } catch (e) {
                        messenger.show(SnackBar(content: Text('Checkout error: $e')));
                      }
                    },
                  ),
                ];

                if (narrow) {
                  return SizedBox(
                    height: 168,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      itemCount: cards.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => SizedBox(width: constraints.maxWidth * .88, child: cards[i]),
                    ),
                  );
                } else {
                  return Row(
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 12),
                      Expanded(child: cards[1]),
                    ],
                  );
                }
              },
            );
          },
        ),
      ],
    );
  }
}

/* ============================
    Small bottom action row
   ============================ */

class _RestoreRow extends StatelessWidget {
  const _RestoreRow();

  @override
  Widget build(BuildContext context) {
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final actionLabel = isAndroid ? 'Refresh Google Play purchases' : 'Restore Purchases';
    final inProgress = isAndroid ? 'Refreshing purchases…' : 'Restoring purchases...';

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 6,
          children: [
            TextButton(
              onPressed: () async {
                try {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(inProgress)));

                  if (isAndroid) {
                    await RevenueCatService.instance.sync();     // Android-safe refresh
                  } else {
                    await RevenueCatService.instance.restore();  // iOS restore
                  }

                  final refreshed = await RevenueCatService.instance.refreshCustomerInfo();
                  final hasPremium = (refreshed.entitlements
                          .all[RevenueCatService.entitlementId]
                          ?.isActive ??
                      false);

                  if (!context.mounted) return;

                  if (hasPremium) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Purchases restored.')));
                    Navigator.of(context).maybePop(true);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No previous purchases found.')));
                  }
                } on PlatformException catch (e) {
                  if (!context.mounted) return;
                  final code = PurchasesErrorHelper.getErrorCode(e);
                  if (code == PurchasesErrorCode.purchaseCancelledError) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Restore failed: ${e.message ?? code.name}')));
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restore error: $e')));
                }
              },
              child: Text(actionLabel),
            ),
            TextButton(
              onPressed: () async {
                final messenger = snacks;
                try {
                  final active = await refreshPremiumStatusUnified();
                  messenger.show(SnackBar(content: Text(active ? 'Premium active ✅' : 'No premium found')));
                } catch (e) {
                  messenger.show(SnackBar(content: Text('Couldn’t refresh: $e')));
                }
              },
              child: const Text('Already upgraded? Refresh status'),
            ),
          ],
        ),
      ),
    );
  }
}

/* ============================
    Shared helpers / widgets
   ============================ */

/// Unified refresh:
/// - Calls `syncPremiumFromRC` (checks RC; if allowlisted, grants promo; mirrors Firestore)
/// - Reads Firestore mirror and updates FeatureGate
Future<bool> refreshPremiumStatusUnified() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) throw Exception('Not signed in');

  // 1) Ask backend to sync with RevenueCat & tester_allowlist, and mirror Firestore
  final fn = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('syncPremiumFromRC');
  await fn.call(<String, dynamic>{});

  // 2) Read the mirrored doc the UI trusts
  final snap = await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('premium')
      .doc('status')
      .get();

  final active = (snap.data()?['active'] as bool?) ?? false;
  FeatureGate.instance.setFromBackend(active);
  return active;
}

Package? _findPkg(Offering? current, {required String idHint}) {
  if (current == null) return null;
  try {
    final hint = idHint.toLowerCase();
    return current.availablePackages.firstWhere(
      (p) =>
          p.identifier.toLowerCase().contains(hint) ||
          p.storeProduct.title.toLowerCase().contains(hint),
    );
  } catch (_) {
    return null;
  }
}

Package? _firstByType(List<Package> list, PackageType type) {
  for (final p in list) {
    if (p.packageType == type) return p;
  }
  return null;
}

/// Build dynamic intro/trial text from RevenueCat StoreProduct.introductoryPrice.
String? _buildIntroText(Package? pkg) {
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
    final String cyclesLabel = cycles > 1 ? ' for $cycles ${_pluralize(unit, cycles)}' : ' for 1 $unit';
    final String billingUnit = _billingUnit(sp.subscriptionPeriod ?? '');
    return 'Intro: $introPriceString$cyclesLabel, then $regular/$billingUnit';
  }
}

String _billingUnit(String iso) => _baseUnit(iso) ?? 'period';

String? _baseUnit(String? iso) {
  if (iso == null) return null;
  if (iso.contains('D')) return 'day';
  if (iso.contains('W')) return 'week';
  if (iso.contains('M')) return 'month';
  if (iso.contains('Y')) return 'year';
  return null;
}

String _pluralize(String unit, int n) => n == 1 ? unit : '${unit}s';

String? _formatPeriod(String? iso) {
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

Future<void> _purchase(BuildContext context, Package pkg) async {
  try {
    await RevenueCatService.instance.purchasePackage(pkg);
    if (FeatureGate.instance.isPremium && context.mounted) {
      snacks.show(const SnackBar(content: Text('Thanks for upgrading!')));
      Navigator.of(context).maybePop(true);
    }
  } on PlatformException catch (e) {
    final code = PurchasesErrorHelper.getErrorCode(e);
    if (code == PurchasesErrorCode.purchaseCancelledError) return;
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Purchase failed: ${e.message ?? code.name}')));
    }
  } catch (e) {
    if (context.mounted) {
      snacks.show(SnackBar(content: Text('Purchase error: $e')));
    }
  }
}

/* ============================
    UI bits
   ============================ */

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.bold),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      Divider(color: Theme.of(context).colorScheme.outlineVariant);
}

class _BenefitTile extends StatelessWidget {
  const _BenefitTile({required this.icon, required this.title, required this.subtitle});
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
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
          Icon(Icons.check_circle_outline, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
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
    required this.onPressed,
    this.trialText,
    this.billingNote,
    this.enabled = true,
    this.badge,
    this.compact = false,
  });

  factory _PlanOptionCard.compact({
    required String title,
    required String price,
    required VoidCallback onPressed,
    String? note,
    String? badge,
    String? trialText,
    bool enabled = true,
  }) =>
      _PlanOptionCard(
        title: title,
        price: price,
        onPressed: onPressed,
        billingNote: note,
        trialText: trialText,
        enabled: enabled,
        badge: badge,
        compact: true,
      );

  final String title;
  final String price; // money only, e.g. "$29.99"
  final String? trialText;
  final String? billingNote;
  final String? badge;
  final VoidCallback onPressed;
  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Opacity(
      opacity: enabled ? 1.0 : 0.6,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Container(
          padding: EdgeInsets.all(compact ? 12 : 16),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badge != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badge!,
                      style: theme.textTheme.labelSmall!.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Text(title, style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w700)),
              if (trialText != null) ...[
                const SizedBox(height: 2),
                Text(
                  trialText!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall!.copyWith(color: cs.primary, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 6),
              Text(price, style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.bold)),
              if (billingNote != null)
                Text(billingNote!, style: theme.textTheme.labelSmall!.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    minimumSize: const Size.fromHeight(36),
                  ),
                  onPressed: onPressed,
                  child: Text('Continue', style: theme.textTheme.labelLarge),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegalFooter extends StatelessWidget {
  const _LegalFooter();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      children: [
        Text(
          'Subscriptions auto-renew unless canceled at least 24 hours before the end of the period.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall!.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          children: [
            TextButton(
              onPressed: () => launchUrl(Uri.parse('https://fermentacraft.com/terms.html')),
              child: const Text('Terms'),
            ),
            TextButton(
              onPressed: () => launchUrl(Uri.parse('https://fermentacraft.com/privacy.html')),
              child: const Text('Privacy'),
            ),
          ],
        ),
      ],
    );
  }
}

class _NoGlow extends ScrollBehavior {
  const _NoGlow();
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}
