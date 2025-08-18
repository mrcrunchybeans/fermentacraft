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
    final mq = MediaQuery.of(context);
    final isShort = mq.size.height < 700;

    final header = _HeroHeader(asDialog: asDialog);

    final body = SafeArea(
      bottom: false,
      child: ScrollConfiguration(
        behavior: const _NoGlow(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: mq.size.height * (asDialog ? 0.7 : 0.9)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                const SizedBox(height: 16),

                // Benefits – compact, scannable
                const _SectionTitle('Why upgrade'),
                const SizedBox(height: 10),
                const _BenefitTile(
                  icon: Icons.all_inclusive,
                  title: 'Unlimited everything',
                  subtitle: 'No caps on recipes, batches, or inventory.',
                ),
                const _BenefitTile(
                  icon: Icons.science_outlined,
                  title: 'Pro tools unlocked',
                  subtitle: 'Gravity/ABV, pH & acid, SO₂, strip readers—always available.',
                ),
                const _BenefitTile(
                  icon: Icons.cloud_sync_outlined,
                  title: 'Sync & export',
                  subtitle: 'Cross-device sync and full data export at any time.',
                ),
                const SizedBox(height: 14),
                const _Divider(),
                const SizedBox(height: 14),

                // Secondary bullets (denser)
                const _SectionTitle('Included with Premium'),
                const SizedBox(height: 10),
                const _FeatureBullet(text: 'Unlimited recipes, batches, inventory, and archives'),
                const _FeatureBullet(text: 'No soft-lock interruptions'),
                const _FeatureBullet(text: 'Directly support development'),
                const SizedBox(height: 18),

                // Plans – responsive, swipe on narrow
                const _PlansSection(),
                SizedBox(height: isShort ? 8 : 16),

                const _LegalFooter(),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );

    final bottom = asDialog ? const _BottomActionsCompact() : const _BottomActionsBar();

    if (asDialog) {
      return Material(
        color: cs.surface,
        child: Column(
          children: [
            Expanded(child: body),
            bottom,
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Go Premium'),
        scrolledUnderElevation: 0,
      ),
      body: body,
      bottomNavigationBar: bottom,
    );
  }
}

/* ============================
    HERO / HEADER (mobile-first)
   ============================ */

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.asDialog});
  final bool asDialog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primaryContainer.withOpacity(.85),
            cs.secondaryContainer.withOpacity(.75),
          ],
        ),
        border: Border.all(color: cs.outlineVariant.withOpacity(.6)),
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: cs.surface.withOpacity(.85),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(10),
            child: Icon(Icons.workspace_premium, color: cs.primary, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Unlock FermentaCraft Premium',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  'Designed for phones. Everything you need to ferment smarter.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onPrimaryContainer.withOpacity(.9),
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

        if (isLoading) return const _LoadingStrip();
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

        return _PlanCardsRow(
          cards: [
            _PlanOptionCard.compact(
              title: 'Yearly',
              price: annual?.storeProduct.priceString ?? '—',
              badge: 'Best value',
              note: 'Billed yearly',
              trialText: _buildIntroText(annual),
              enabled: annual != null,
              primary: true,
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
          ],
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
              return const _LoadingStrip();
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

            return _PlanCardsRow(
              cards: [
                _PlanOptionCard.compact(
                  title: 'Yearly',
                  price: yearly,
                  badge: 'Best value',
                  note: 'Billed yearly',
                  primary: true,
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
              ],
            );
          },
        ),
      ],
    );
  }
}

/* ============================
    Responsive plan row
   ============================ */

class _PlanCardsRow extends StatelessWidget {
  const _PlanCardsRow({required this.cards});
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 380;
        if (narrow) {
          return SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: cards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => SizedBox(width: c.maxWidth * .88, child: cards[i]),
            ),
          );
        }
        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 12),
            Expanded(child: cards[1]),
          ],
        );
      },
    );
  }
}

/* ============================
    Bottom actions (sticky)
   ============================ */

class _BottomActionsBar extends StatelessWidget {
  const _BottomActionsBar();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: const _RestoreRowContent(),
      ),
    );
  }
}

class _BottomActionsCompact extends StatelessWidget {
  const _BottomActionsCompact();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: const _RestoreRowContent(),
    );
  }
}

class _RestoreRowContent extends StatelessWidget {
  const _RestoreRowContent();

  @override
  Widget build(BuildContext context) {
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final restoreLabel = isAndroid ? 'Refresh Google Play purchases' : 'Restore Purchases';
    final inProgress = isAndroid ? 'Refreshing purchases…' : 'Restoring purchases…';

    return LayoutBuilder(
      builder: (context, c) {
        final stack = c.maxWidth < 380;
        final children = <Widget>[
          _SmallTonalButton(
            label: restoreLabel,
            onPressed: () async {
              try {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(inProgress)));

                if (isAndroid) {
                  await RevenueCatService.instance.sync();
                } else {
                  await RevenueCatService.instance.restore();
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No previous purchases found.')),
                  );
                }
              } on PlatformException catch (e) {
                if (!context.mounted) return;
                final code = PurchasesErrorHelper.getErrorCode(e);
                if (code == PurchasesErrorCode.purchaseCancelledError) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Restore failed: ${e.message ?? code.name}')),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restore error: $e')));
              }
            },
          ),
          _SmallTextButton(
            label: 'Already upgraded? Refresh status',
            onPressed: () async {
              final messenger = snacks;
              try {
                final active = await refreshPremiumStatusUnified();
                messenger.show(SnackBar(content: Text(active ? 'Premium active ✅' : 'No premium found')));
              } catch (e) {
                messenger.show(SnackBar(content: Text('Couldn’t refresh: $e')));
              }
            },
          ),
        ];

        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              children[0],
              const SizedBox(height: 8),
              Center(child: children[1]),
            ],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: children[0]),
            const SizedBox(width: 10),
            children[1],
          ],
        );
      },
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

  final fn = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('syncPremiumFromRC');
  await fn.call(<String, dynamic>{});

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
    UI bits (polished for mobile)
   ============================ */

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleLarge!.copyWith(fontWeight: FontWeight.bold),
      ),
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
      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: cs.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
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
      padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
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
    this.primary = false,
  });

  factory _PlanOptionCard.compact({
    required String title,
    required String price,
    required VoidCallback onPressed,
    String? note,
    String? badge,
    String? trialText,
    bool enabled = true,
    bool primary = false,
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
        primary: primary,
      );

  final String title;
  final String price; // e.g. "$29.99"
  final String? trialText;
  final String? billingNote;
  final String? badge;
  final VoidCallback onPressed;
  final bool enabled;
  final bool compact;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final bg = primary ? cs.primaryContainer : cs.surface;
    final stroke = cs.outlineVariant;
    final titleStyle = theme.textTheme.titleMedium!.copyWith(
      fontWeight: FontWeight.w800,
      color: primary ? cs.onPrimaryContainer : null,
    );
    final priceStyle = theme.textTheme.titleLarge!.copyWith(
      fontWeight: FontWeight.w900,
      color: primary ? cs.onPrimaryContainer : null,
    );
    final noteStyle =
        theme.textTheme.labelSmall!.copyWith(color: primary ? cs.onPrimaryContainer.withOpacity(.9) : cs.onSurfaceVariant);

    return Opacity(
      opacity: enabled ? 1.0 : 0.6,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Container(
          padding: EdgeInsets.all(compact ? 12 : 16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: stroke),
            boxShadow: [
              BoxShadow(
                blurRadius: 18,
                spreadRadius: 0,
                offset: const Offset(0, 8),
                color: Colors.black.withOpacity(0.06),
              ),
            ],
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
                      color: (primary ? cs.onPrimaryContainer : cs.primary).withOpacity(.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badge!,
                      style: theme.textTheme.labelSmall!.copyWith(
                        color: primary ? cs.onPrimaryContainer : cs.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Text(title, style: titleStyle),
              if (trialText != null) ...[
                const SizedBox(height: 2),
                Text(
                  trialText!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: primary ? cs.onPrimaryContainer : cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(price, style: priceStyle),
              if (billingNote != null)
                Text(billingNote!, style: noteStyle),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    minimumSize: const Size.fromHeight(42),
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

class _SmallTonalButton extends StatelessWidget {
  const _SmallTonalButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        minimumSize: const Size(0, 40),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

class _SmallTextButton extends StatelessWidget {
  const _SmallTextButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
      onPressed: onPressed,
      child: Text(label),
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
        const SizedBox(height: 8),
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

class _LoadingStrip extends StatelessWidget {
  const _LoadingStrip();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(),
      );
}

class _NoGlow extends ScrollBehavior {
  const _NoGlow();
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}
