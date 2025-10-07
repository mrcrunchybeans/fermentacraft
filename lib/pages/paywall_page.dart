// lib/pages/paywall_page.dart
// ignore_for_file: deprecated_member_use

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, kDebugMode, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fermentacraft/utils/platforms.dart';
import 'package:fermentacraft/utils/snacks.dart';

import '../services/feature_gate.dart';
import '../services/revenuecat_service.dart';
import '../services/stripe_billing_service.dart';
import '../services/stripe_pricing_service.dart';

/* ============================================================
   PAYWALL (Premium + Pro-Offline)
   - Pro-Offline unlocks all OFFLINE premium features locally
   - Premium unlocks everything, including cloud/sync
   - Users can switch both ways
   ============================================================ */

class PaywallPage extends StatefulWidget {
  const PaywallPage({super.key, this.asDialog = false});
  final bool asDialog;

  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends State<PaywallPage> {
  // Anchor for the plans section
  final GlobalKey _plansKey = GlobalKey();

  // Smooth scroll to the plans section
  Future<void> _scrollToPlans() async {
    final ctx = _plansKey.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: 0.05,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    final isShort = mq.size.height < 700;

    final header = _HeroHeader(asDialog: widget.asDialog);

    // Debug-only: quick RC diagnostics button
    final rcDiagButton = kDebugMode
        ? Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                await RevenueCatService.instance.debugPrintDiagnostics();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('RC diagnostics printed to console')),
                  );
                }
              },
              icon: const Icon(Icons.info_outline_rounded, size: 18),
              label: const Text('RC diagnostics'),
            ),
          )
        : const SizedBox.shrink();

    final body = SafeArea(
      bottom: false,
      child: ScrollConfiguration(
        behavior: const _NoGlow(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minHeight: mq.size.height * (widget.asDialog ? 0.7 : 0.9)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                rcDiagButton,
                const SizedBox(height: 16),

                // Dynamic status + switcher
                _CurrentPlanNotice(
                    onUpgradeTap: () => _onUpgradeTap(context, _scrollToPlans)),

                const SizedBox(height: 12),

                // Why upgrade (generic)
                const Center(
                  child: _SectionTitle('Why upgrade?'),
                ),
                const SizedBox(height: 12),
                const _BenefitsGrid(),
                const SizedBox(height: 18),

                // Plans
                _PlansSection(key: _plansKey),

                SizedBox(height: isShort ? 8 : 16),

                // Legal
                const _LegalFooter(),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );

    final bottom = widget.asDialog
        ? const _BottomActionsCompact()
        : const _BottomActionsBar();

    if (widget.asDialog) {
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
        title: const Text('Upgrade options'),
        scrolledUnderElevation: 0,
      ),
      body: body,
      bottomNavigationBar: bottom,
    );
  }
}

/* ============================
   Plan comparison (vertical)
   ============================ */

enum _Avail { yes, no, limited }

/// Row model for the table
class _RowSpec {
  const _RowSpec(
    this.title, {
    required this.free,
    required this.pro,
    required this.premium,
    this.tooltip,
    this.freeSymbol,
    this.proSymbol,
    this.premiumSymbol,
    this.freeLabelOverride,
    this.proLabelOverride,
    this.premiumLabelOverride,
  });

  final String title;
  final _Avail free;
  final _Avail pro;
  final _Avail premium;
  final String? tooltip;

  // Optional tiny symbols per cell (e.g., "1×", "↻", "—")
  final String? freeSymbol;
  final String? proSymbol;
  final String? premiumSymbol;

  // Optional full label overrides per cell (e.g., "One-time", "Subscription")
  final String? freeLabelOverride;
  final String? proLabelOverride;
  final String? premiumLabelOverride;
}

/// The little “Included / Not included / Limited” pill
class _AvailMark extends StatelessWidget {
  const _AvailMark({
    required this.value,
    this.tooltip,
    this.symbol, // optional per-cell symbol like "1×" or "↻"
    this.labelOverride, // optional full text label (overrides icon & symbol)
  });

  final _Avail value;
  final String? tooltip;
  final String? symbol;
  final String? labelOverride;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Use Material 3 container roles so contrast is correct in dark & light.
    // - YES      → primaryContainer / onPrimaryContainer
    // - NO       → errorContainer / onErrorContainer
    // - LIMITED  → secondaryContainer / onSecondaryContainer (softer than orange)
    late Color bg;
    late Color fg;
    late IconData icon;
    switch (value) {
      case _Avail.yes:
        bg = cs.primaryContainer;
        fg = cs.onPrimaryContainer;
        icon = Icons.check_rounded;
        break;
      case _Avail.no:
        bg = cs.errorContainer;
        fg = cs.onErrorContainer;
        icon = Icons.close_rounded;
        break;
      case _Avail.limited:
        bg = cs.secondaryContainer;
        fg = cs.onSecondaryContainer;
        icon = Icons.remove_rounded;
        break;
    }

    // Shape
    final BorderRadius radius = switch (value) {
      _Avail.yes => BorderRadius.circular(999),
      _Avail.no => BorderRadius.circular(8),
      _Avail.limited => BorderRadius.circular(999),
    };

    // Symbol logic (unchanged)
    const String limitedAutoSymbol = '≈';
    final bool hasLabel =
        (labelOverride != null && labelOverride!.trim().isNotEmpty);
    final String? effectiveSymbol =
        (symbol != null && symbol!.trim().isNotEmpty)
            ? symbol
            : (value == _Avail.limited && !hasLabel ? limitedAutoSymbol : null);

    // Build UI
    Widget pillContent;
    if (hasLabel) {
      pillContent = Container(
        constraints: const BoxConstraints(minHeight: 28, maxWidth: 96),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radius,
          border: Border.all(color: cs.outlineVariant.withOpacity(.5)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            labelOverride!.trim(),
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            // Use the FG we computed so it’s legible on bg in dark & light
            style: theme.textTheme.labelMedium!.copyWith(
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ),
      );
    } else {
      pillContent = Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radius,
          border: Border.all(color: cs.outlineVariant.withOpacity(.5)),
        ),
        child: (effectiveSymbol != null)
            ? Text(
                effectiveSymbol,
                style: theme.textTheme.labelMedium!.copyWith(
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: fg, // make the symbol readable on both themes
                ),
              )
            : Icon(icon, size: 18, color: fg),
      );
    }

    final semanticsLabel = hasLabel
        ? labelOverride!.trim()
        : (effectiveSymbol ??
            (value == _Avail.yes
                ? 'Included'
                : value == _Avail.no
                    ? 'Not included'
                    : 'Limited'));

    final result = Semantics(label: semanticsLabel, child: pillContent);

    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(
        message: tooltip!,
        waitDuration: const Duration(milliseconds: 250),
        child: result,
      );
    }
    return result;
  }
}

/// Legend chips under the table
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget chip(_Avail value, String label, {String? symbol}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          // neutral surface to avoid color-on-color clashes in dark mode
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _AvailMark(
                value: value,
                symbol: symbol, // keep the explicit symbols in the legend
              ),
            ),
            Text(label, style: TextStyle(color: cs.onSurface)),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        chip(_Avail.yes, 'Included', symbol: _kYesSymbol),
        chip(_Avail.no, 'Not included', symbol: _kNoSymbol),
        chip(_Avail.limited, 'Limited*', symbol: _kLimitedSymbol),
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text(
            '* Free is limited to 3 active batches, 5 recipes, 12 inventory items, and a limited toolset.',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
          ),
        ),
      ],
    );
  }
}

const String _kYesSymbol = '✓'; // Included
const String _kNoSymbol = '✕'; // Not included
const String _kLimitedSymbol = '≈'; // Limited / partial

/// Shared spacing used by header and rows so columns always line up
const double _kColGap = 10.0;

/// Breakpoint where we switch to vertical cards (tweak to taste)
const double _kStackBp = 380.0;

class _BenefitsGrid extends StatelessWidget {
  const _BenefitsGrid();

  @override
  Widget build(BuildContext context) {
    final benefits = [
      (
        icon: Icons.all_inclusive_rounded,
        title: 'Unlimited recipes, batches & inventory'
      ),
      (icon: Icons.tune_rounded, title: 'All Pro-Tools enabled'),
      (icon: Icons.backup_rounded, title: 'Cloud sync & backup'),
      (icon: Icons.devices_rounded, title: 'Cross-device access & streaming'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Show as a grid on wide screens, a column on narrow ones
        final isNarrow = constraints.maxWidth < 600;

        return isNarrow
            ? Column(
                children: [
                  for (final b in benefits)
                    _BenefitTile(icon: b.icon, title: b.title),
                ],
              )
            : GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 3, // Adjust for tile height
                ),
                itemCount: benefits.length,
                itemBuilder: (context, index) {
                  final b = benefits[index];
                  return _BenefitTile(icon: b.icon, title: b.title);
                },
              );
      },
    );
  }
}

class _PlanComparison extends StatelessWidget {
  const _PlanComparison();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final gate = FeatureGate.instance;

    String currentPlan() {
      if (gate.isPremium) return 'Premium';
      if (gate.isProOffline) return 'Pro-Offline';
      return 'Free';
    }

    // Compact symbol defaults for common labels (used if you don't set explicit symbols)
    String? symbolForLabel(String? label) {
      if (label == null) return null;
      final l = label.toLowerCase().trim();
      if (l == 'n/a' || l == 'na') return '—';
      if (l.contains('one-time')) return '1×';
      if (l.contains('subscription')) return 'S';
      return null;
    }

    final rows = <_RowSpec>[
      const _RowSpec(
        'Unlimited recipes, batches, inventory, shopping list',
        free: _Avail.limited,
        pro: _Avail.yes,
        premium: _Avail.yes,
        tooltip:
            'Free has limit of 3 active batches, 5 recipes, and 12 inventory items. Pro-Offline and Premium remove all caps.',
      ),
      const _RowSpec(
        'Pro tools (Gravity adjuster, SO₂, TA, strip reader, etc.)',
        free: _Avail.limited,
        pro: _Avail.yes,
        premium: _Avail.yes,
        tooltip:
            'Free includes only basic tools. Full toolset requires Pro-Offline or Premium.',
      ),
      const _RowSpec('Local backup & restore',
          free: _Avail.yes, pro: _Avail.yes, premium: _Avail.yes),
      const _RowSpec('Cloud sync & cross-device access',
          free: _Avail.no, pro: _Avail.no, premium: _Avail.yes),
      const _RowSpec('Online backup & restore',
          free: _Avail.no, pro: _Avail.no, premium: _Avail.yes),
      const _RowSpec('Live device streaming & cloud exports (iSpindel/Tilt)',
          free: _Avail.no, pro: _Avail.no, premium: _Avail.yes),
      const _RowSpec(
        'Billing type',
        free: _Avail.limited,
        pro: _Avail.yes,
        premium: _Avail.yes,
        tooltip:
            'Pro-Offline is a one-time purchase. Premium is a subscription. Free is limited.',
        freeLabelOverride: 'Free',
        proLabelOverride: 'Lifetime',
        premiumLabelOverride: 'Subscription',
        freeSymbol: '—',
        proSymbol: '1×',
        premiumSymbol: 'S',
      ),
    ];

    // Breakpoint: below this we use vertical stacks
    final bool stack = MediaQuery.of(context).size.width < _kStackBp;

    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Compare plans'),
          const SizedBox(height: 10),
          for (final r in rows) _verticalRow(context, r),
          const SizedBox(height: 8),
          const _Legend(),
        ],
      );
    }

    // ==== Horizontal grid version =====

    Widget headCell(String text, {bool highlight = false}) {
      // Keep “Pro-Offline” unbroken; auto-shrink to fit
      final label = text.replaceAll('Pro-Offline', 'Pro\u2011Offline');
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: theme.textTheme.labelLarge!.copyWith(
            fontWeight: FontWeight.w800,
            color: highlight ? cs.primary : null,
          ),
        ),
      );
    }

    Widget planCell({
      required bool tight,
      required _Avail value,
      required String? tooltip,
      required String? labelOverride,
      required String? symbol,
    }) {
      final effectiveSymbol = symbol ??
          symbolForLabel(labelOverride) ??
          (value == _Avail.yes
              ? _kYesSymbol
              : value == _Avail.no
                  ? _kNoSymbol
                  : _kLimitedSymbol);

      final child = _AvailMark(
        value: value,
        tooltip: tooltip,
        symbol: tight ? effectiveSymbol : null, // symbols on tight screens
        labelOverride: tight ? null : labelOverride, // labels on wide screens
      );

      return Align(
          alignment: Alignment.center,
          child: tight ? FittedBox(child: child) : child);
    }

    Widget row(_RowSpec r) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant.withOpacity(.6)),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final tight = c.maxWidth < 460; // allow icons on compact widths
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    flex: 3,
                    child: Text(r.title, style: theme.textTheme.bodyMedium)),
                const SizedBox(width: _kColGap),
                Expanded(
                  flex: 1,
                  child: planCell(
                    tight: tight,
                    value: r.free,
                    tooltip: r.tooltip,
                    labelOverride: r.freeLabelOverride,
                    symbol: r.freeSymbol,
                  ),
                ),
                const SizedBox(width: _kColGap),
                Expanded(
                  flex: 1,
                  child: planCell(
                    tight: tight,
                    value: r.pro,
                    tooltip: r.tooltip,
                    labelOverride: r.proLabelOverride,
                    symbol: r.proSymbol,
                  ),
                ),
                const SizedBox(width: _kColGap),
                Expanded(
                  flex: 1,
                  child: planCell(
                    tight: tight,
                    value: r.premium,
                    tooltip: r.tooltip,
                    labelOverride: r.premiumLabelOverride,
                    symbol: r.premiumSymbol,
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    final header = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: headCell('Feature')),
          const SizedBox(width: _kColGap),
          Expanded(
              flex: 1,
              child: headCell('Free', highlight: currentPlan() == 'Free')),
          const SizedBox(width: _kColGap),
          Expanded(
              flex: 1,
              child: headCell('Pro-Offline',
                  highlight: currentPlan() == 'Pro-Offline')),
          const SizedBox(width: _kColGap),
          Expanded(
              flex: 1,
              child:
                  headCell('Premium', highlight: currentPlan() == 'Premium')),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Compare plans'),
        const SizedBox(height: 10),
        header,
        for (final r in rows) row(r),
        const SizedBox(height: 8),
        const _Legend(),
      ],
    );
  }

  // ---------- Vertical (stacked) card row ----------
  Widget _verticalRow(BuildContext context, _RowSpec r) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    Widget status(
        String planName, _Avail status, String? label, String? tooltip) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(planName,
              style: theme.textTheme.labelSmall!
                  .copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          _AvailMark(value: status, labelOverride: label, tooltip: tooltip),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.title,
              style: theme.textTheme.titleSmall!
                  .copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              status('Free', r.free, r.freeLabelOverride, r.tooltip),
              status('Pro\u2011Offline', r.pro, r.proLabelOverride, r.tooltip),
              status('Premium', r.premium, r.premiumLabelOverride, r.tooltip),
            ],
          ),
        ],
      ),
    );
  }
}

/* ============================
   Header
   ============================ */

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.asDialog});
  final bool asDialog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(
          8, 12, 8, 0), // Adjusted margin for smaller screens
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
                Text('Choose Premium or Pro-Offline',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  'Premium adds cloud/sync. Pro-Offline unlocks everything offline as a one-time purchase.',
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
   Current plan notice + switches
   ============================ */

class _CurrentPlanNotice extends StatefulWidget {
  const _CurrentPlanNotice({required this.onUpgradeTap});
  final VoidCallback onUpgradeTap;

  @override
  State<_CurrentPlanNotice> createState() => _CurrentPlanNoticeState();
}

class _CurrentPlanNoticeState extends State<_CurrentPlanNotice> {
  @override
  Widget build(BuildContext context) {
    final gate = FeatureGate.instance;
    final bool isiOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final bool isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    Widget banner(
      IconData icon,
      String title,
      String subtitle,
      List<Widget> actions,
    ) {
      final cs = Theme.of(context).colorScheme;
      final theme = Theme.of(context);

      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceVariant, // 👈 works in dark & light
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium!.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface, // always legible
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium!
                  .copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      );
    }

    if (gate.isPremium) {
      // PREMIUM → allow switching to Pro-Offline
      return banner(
        Icons.verified,
        'You have Premium',
        'Cloud sync, backup, device streaming enabled. Prefer local-only? Switch to Pro-Offline (you can switch back anytime).',
        [
          OutlinedButton.icon(
            // Changed from FilledButton.tonalIcon to OutlinedButton.icon
            icon: const Icon(Icons.cloud_off),
            onPressed: () async {
              final ok = await _confirm(
                context,
                title: 'Switch to Pro-Offline?',
                msg:
                    'This disables cloud sync/backup and live device streaming in the app. '
                    'If you have an active subscription, you must cancel it in the App Store/Google Play or Stripe to stop future charges.\n\nProceed?',
                confirmLabel: 'Switch',
              );
              if (ok != true) return;
              await FeatureGate.instance.activateProOffline();
              if (!context.mounted) return;
              snacks.show(const SnackBar(
                  content: Text('Switched to Pro-Offline on this device.')));
              setState(() {});
            },
            label: const Text('Switch to Pro-Offline'),
          ),
        ],
      );
    }

    if (gate.isProOffline) {
      return banner(
        Icons.cloud_off,
        'You have Pro-Offline',
        'All offline premium features are unlocked. Need cloud sync, device streaming, or cross-platform? Upgrade to Premium.',
        [
          FilledButton.icon(
            // Changed from OutlinedButton to FilledButton for primary action
            icon: const Icon(Icons.cloud_done),
            onPressed: widget.onUpgradeTap, // 👈 use it here
            label: const Text('See Premium plans'),
          ),
        ],
      );
    }

    return banner(
      Icons.star_border,
      'Free plan',
      'Unlock Pro tools and unlimited everything offline with Pro-Offline, or add cloud sync with Premium.',
      [
        FilledButton.tonalIcon(
          // Kept FilledButton.tonalIcon but ensure it uses primary color tonal
          icon: const Icon(Icons.cloud_off),
          onPressed: () async {
            if (RevenueCatService.instance.isSupported) {
              await _purchaseProOffline(context);
            } else if (!isiOS && !isAndroid) {
              try {
                await StripeBillingService.instance.startCheckout(
                  priceId: _StripeProOfflineCard
                      ._proOfflinePriceId, // keep as a public const or re-declare here
                  successUrl:
                      Uri.parse('https://fermentacraft.com/checkout-success'),
                  cancelUrl:
                      Uri.parse('https://fermentacraft.com/checkout-cancel'),
                );
              } catch (e) {
                snacks.show(SnackBar(content: Text('Checkout error: $e')));
              }
            } else {
              // On iOS/Android without RC configured, avoid Stripe (store policy) and inform the user.
              snacks.show(const SnackBar(
                content: Text(
                    'In‑app purchases aren’t available in this build. Tip: pass your RevenueCat API key (RC_API_KEY_IOS/ANDROID) via --dart-define to enable store products.'),
              ));
            }
          },
          label: const Text('Buy Pro-Offline'),
        ),
        FilledButton.tonalIcon(
          // Changed from FilledButton to OutlinedButton
          icon: const Icon(Icons.cloud_sync),
          label: const Text('Upgrade to Premium'),
          onPressed: widget.onUpgradeTap, // 👈 use it here
        ),
      ],
    );
  }
}

/* ============================
   Plans section
   ============================ */

class _PlansSection extends StatelessWidget {
  const _PlansSection({super.key});

  @override
  Widget build(BuildContext context) {
    final gate = FeatureGate.instance;
    // Platform routing:
    // - iOS/Android: use RevenueCat/StoreKit/Play Billing when configured
    // - Web/Desktop: use Stripe
    // If RC isn’t configured on iOS/Android, do NOT show Stripe; show a helpful note.
    final bool isiOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final bool isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final bool rcConfigured =
        RevenueCatService.instance.isSupported; // requires platform + API key

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Choose your plan'),
        const SizedBox(height: 10),

        // Pro-Offline (only show if not already owned)
        if (!gate.isProOffline) ...[
          if (isiOS || isAndroid) ...[
            if (rcConfigured)
              _ProOfflineCard(
                onBuyProOffline: () async => _purchaseProOffline(context),
              )
            else
              const _RCUnavailableNote(),
          ] else ...[
            const _StripeProOfflineCard(),
          ],
          const SizedBox(height: 12),
        ],

        // Premium subscription
        if (isiOS || isAndroid) ...[
          if (rcConfigured)
            const _RevenueCatPlans()
          else
            const _RCUnavailableNote(),
        ] else ...[
          const _StripePlans(),
        ],
        const SizedBox(height: 18),

        // Detailed comparison table (re-added here)
        const _PlanComparison(),
      ],
    );
  }
}

/// Displayed on iOS/Android when RevenueCat isn’t configured for this build.
class _RCUnavailableNote extends StatelessWidget {
  const _RCUnavailableNote();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded),
              SizedBox(width: 8),
              Text('In‑app purchases unavailable'),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'This build isn’t configured with RevenueCat. On iOS/Android, purchases must use the App Store/Google Play.\nTip: pass RC_API_KEY_IOS/RC_API_KEY_ANDROID via --dart-define to enable store products.',
          ),
        ],
      ),
    );
  }
}

/* ============================
   Pro-Offline card (local / RC on mobile)
   ============================ */

// Helper to get the Pro-Offline price from RevenueCat offerings
Future<String?> _getProOfflinePrice() async {
  if (!RevenueCatService.instance.isSupported) return null;
  final offerings = await RevenueCatService.instance.getOfferings();
  final pkg = _pickProOfflinePackage(offerings);
  return pkg?.storeProduct.priceString;
}

class _ProOfflineCard extends StatelessWidget {
  const _ProOfflineCard({
    required this.onBuyProOffline,
  });

  final VoidCallback onBuyProOffline;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _getProOfflinePrice(),
      builder: (context, snap) {
        final priceText = snap.data ?? '';
        return _PlanCardsRow(
          cards: [
            _PlanOptionCard.compact(
              title: 'Pro-Offline',
              price: priceText.isEmpty ? '—' : priceText,
              badge: 'One-time purchase',
              note: 'All offline premium features',
              primary: true,
              onPressed: onBuyProOffline,
            ),
          ],
        );
      },
    );
  }
}

/* ============================
   RevenueCat (Android / iOS)  Premium
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
        annual ??= _firstByType(list, PackageType.annual) ??
            (list.isNotEmpty ? list.first : null);
        monthly ??= _firstByType(list, PackageType.monthly) ??
            (list.length >= 2
                ? list[1]
                : (list.isNotEmpty ? list.first : null));

        final bool noProducts = !isLoading &&
            !hasError &&
            (current == null || current.availablePackages.isEmpty);

        if (isLoading) return const _LoadingStrip();
        if (hasError) {
          // Log detailed error to help diagnose env/setup issues
          debugPrint(
              '[Paywall] RevenueCat getOfferings() error: ${snap.error}');
          if (snap.error is PlatformException) {
            final e = snap.error as PlatformException;
            final mapped = PurchasesErrorHelper.getErrorCode(e);
            debugPrint('[Paywall] RC PlatformException mapped: ${mapped.name}');
            debugPrint('[Paywall] RC PlatformException code: ${e.code}');
            if (e.details != null) {
              debugPrint(
                  '[Paywall] RC PlatformException details: ${e.details}');
            }
          }
          if (snap.stackTrace != null) {
            debugPrint('[Paywall] Offerings stack: ${snap.stackTrace}');
          }

          // Show a concise message to users; include raw error in debug only
          final msg = kDebugMode
              ? 'Couldn’t load products: ${snap.error}'
              : 'Couldn’t load products. Please try again.';

          // In debug builds, add hints for the most common root causes
          final List<Widget> children = [
            Text(msg, style: TextStyle(color: cs.error)),
          ];
          if (kDebugMode) {
            children.addAll([
              const SizedBox(height: 6),
              const Text(
                'Tips: \n• Verify RC_API_KEY_IOS is passed when running.\n• Ensure a Current offering is set in RevenueCat with valid product IDs.\n• Check App Store Connect products exist for this bundle id, are Cleared for Sale, and agreements are accepted.\n• On Simulator/device, use a Sandbox Apple ID in App Store settings.',
                style: TextStyle(fontSize: 12),
              ),
            ]);
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
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
              title: 'Premium Yearly',
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
              title: 'Premium Monthly',
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
   Stripe (Web / Desktop) – Premium
   ============================ */

class _StripePlans extends StatelessWidget {
  const _StripePlans();

  // Premium subscription Price IDs (replace with your real ones if needed)
  static const _yearlyPriceId = 'price_1RuoNRE9CXcdIoFtbE2wYOZj';
  static const _monthlyPriceId = 'price_1RuoNTE9CXcdIoFtrLcI8ujI';

  // Where Stripe redirects after success/cancel (must be HTTPS & yours)
  static final _successUrl =
      Uri.parse('https://fermentacraft.com/checkout-success');
  static final _cancelUrl =
      Uri.parse('https://fermentacraft.com/checkout-cancel');

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
          future: StripePricingService.instance
              .fetchPrices([_yearlyPriceId, _monthlyPriceId]),
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
                  snacks.show(SnackBar(
                      content: Text('Pricing unavailable: ${snap.error}')));
                }
              });
            }

            return _PlanCardsRow(
              cards: [
                _PlanOptionCard.compact(
                  title: 'Premium Yearly',
                  price: yearly,
                  badge: 'Best value',
                  note: 'Billed yearly',
                  primary: true,
                  onPressed: () async {
                    try {
                      await StripeBillingService.instance.startCheckout(
                        priceId: _yearlyPriceId,
                        successUrl: _successUrl,
                        cancelUrl: _cancelUrl,
                      );
                    } catch (e) {
                      snacks
                          .show(SnackBar(content: Text('Checkout error: $e')));
                    }
                  },
                ),
                _PlanOptionCard.compact(
                  title: 'Premium Monthly',
                  price: monthly,
                  note: 'Billed monthly',
                  onPressed: () async {
                    try {
                      await StripeBillingService.instance.startCheckout(
                        priceId: _monthlyPriceId,
                        successUrl: _successUrl,
                        cancelUrl: _cancelUrl,
                      );
                    } catch (e) {
                      snacks
                          .show(SnackBar(content: Text('Checkout error: $e')));
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
   Stripe (Web / Desktop) – Pro-Offline Lifetime
   ============================ */

class _StripeProOfflineCard extends StatelessWidget {
  const _StripeProOfflineCard();

  static const _proOfflinePriceId = 'price_1S4n7wE9CXcdIoFtyl8t9cMZ';
  static final _successUrl =
      Uri.parse('https://fermentacraft.com/checkout-success');
  static final _cancelUrl =
      Uri.parse('https://fermentacraft.com/checkout-cancel');

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, StripePrice>>(
      future: StripePricingService.instance.fetchPrices([_proOfflinePriceId]),
      builder: (context, snap) {
        final priceText = (snap.hasData)
            ? (snap.data![_proOfflinePriceId]?.toMoney() ?? '—')
            : (snap.connectionState == ConnectionState.waiting ? '—' : '—');

        if (snap.connectionState == ConnectionState.waiting) {
          return const _LoadingStrip();
        }

        return _PlanCardsRow(
          cards: [
            _PlanOptionCard.compact(
              title: 'Pro-Offline (Lifetime)',
              price: priceText,
              badge: 'No subscription',
              note: 'All offline premium features',
              primary: true,
              onPressed: () async {
                try {
                  await StripeBillingService.instance.startCheckout(
                    priceId: _proOfflinePriceId,
                    successUrl: _successUrl,
                    cancelUrl: _cancelUrl,
                    // Server must use mode: 'payment' for one-time
                  );
                } catch (e) {
                  snacks.show(SnackBar(content: Text('Checkout error: $e')));
                }
              },
            ),
          ],
        );
      },
    );
  }
}

/* ============================
   Responsive plan cards row
   ============================ */

class _PlanCardsRow extends StatelessWidget {
  const _PlanCardsRow({required this.cards});
  final List<Widget> cards;

  // Tweak to taste
  static const double _kStackBreakpoint = 450.0;
  static const double _kRowGap = 12.0;
  static const double _kColGap = 12.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final isNarrow = c.maxWidth < _kStackBreakpoint;

        if (isNarrow) {
          // Vertical stack for small widths (easier to read & tap)
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                cards[i],
                if (i != cards.length - 1) const SizedBox(height: _kColGap),
              ],
            ],
          );
        }

        // Row for wider widths
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              Expanded(child: cards[i]),
              if (i != cards.length - 1) const SizedBox(width: _kRowGap),
            ],
          ],
        );
      },
    );
  }
}

/* ============================
   Bottom actions
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
    return const Padding(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: _RestoreRowContent(),
    );
  }
}

class _RestoreRowContent extends StatelessWidget {
  const _RestoreRowContent();

  @override
  Widget build(BuildContext context) {
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    final canUseRevenueCat = isAndroid || isIOS;
    final restoreLabel = canUseRevenueCat
        ? (isAndroid ? 'Refresh Google Play purchases' : 'Restore Purchases')
        : 'Restore purchases (mobile only)';
    final inProgress = canUseRevenueCat
        ? (isAndroid ? 'Refreshing purchases…' : 'Restoring purchases…')
        : 'Checking account…';

    return LayoutBuilder(
      builder: (context, c) {
        final stack = c.maxWidth < 380;
        final children = <Widget>[
          OutlinedButton(
            // Changed from _SmallTonalButton to OutlinedButton
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              minimumSize: const Size(0, 40),
            ),
            onPressed: () async {
              try {
                if (!context.mounted) return;

                // Capture up front
                final messenger = ScaffoldMessenger.of(context);
                final nav = Navigator.of(context);

                if (!canUseRevenueCat) {
                  messenger.showSnackBar(const SnackBar(
                    content: Text(
                      'Restore is only for App Store/Google Play purchases. '
                      'If you purchased via Stripe (web/desktop), use “Refresh status”.',
                    ),
                  ));
                  return;
                }

                messenger.showSnackBar(SnackBar(content: Text(inProgress)));

                if (isAndroid) {
                  await RevenueCatService.instance.sync();
                } else {
                  await RevenueCatService.instance.restore();
                }

                final refreshed =
                    await RevenueCatService.instance.refreshCustomerInfo();
                final hasPremium = (refreshed.entitlements
                        .all[RevenueCatService.entitlementId]?.isActive ??
                    false);

                if (!context.mounted) return;

                if (hasPremium) {
                  messenger.showSnackBar(
                      const SnackBar(content: Text('Purchases restored.')));
                  nav.maybePop(true);
                } else {
                  messenger.showSnackBar(const SnackBar(
                      content: Text('No previous purchases found.')));
                }
              } on PlatformException catch (e) {
                if (!context.mounted) return;
                final code = PurchasesErrorHelper.getErrorCode(e);
                if (code == PurchasesErrorCode.purchaseCancelledError) return;
                final messenger = ScaffoldMessenger.of(context);
                messenger.showSnackBar(
                  SnackBar(
                      content:
                          Text('Restore failed: ${e.message ?? code.name}')),
                );
              } catch (e) {
                if (!context.mounted) return;
                final messenger = ScaffoldMessenger.of(context);
                messenger
                    .showSnackBar(SnackBar(content: Text('Restore error: $e')));
              }
            },
            child: Text(restoreLabel),
          ),
          _SmallTextButton(
            label: 'Already upgraded? Refresh status',
            onPressed: () async {
              final messenger = snacks;
              try {
                final active = await refreshPremiumStatusUnified();
                messenger.show(SnackBar(
                  content: Text(
                    active
                        ? 'Premium active ✅'
                        : (supportsFirebaseFunctionsClient
                            ? 'No premium found'
                            : 'No premium found. If you purchased on Google Play/App Store, open the mobile app and use Restore.'),
                  ),
                ));
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

/// After RC purchase, ensure plan flips to Premium even if device was Pro-Offline.
/// Strategy: clear local Pro-Offline first, then refresh RC customer info.
/// (FeatureGate will mirror RC and land on Premium.)
Future<void> _afterSuccessfulPurchaseEnsurePremium(BuildContext context) async {
  await FeatureGate.instance
      .deactivateProOffline(); // clears local override if set
  await RevenueCatService.instance.refreshCustomerInfo();
  if (FeatureGate.instance.isPremium && context.mounted) {
    snacks.show(const SnackBar(
        content: Text('Thanks for upgrading! Premium is active.')));
    Navigator.of(context).maybePop(true);
  }
}

/// Unified refresh:
/// - Mobile/web/macOS: call callable Function to sync RC, then read Firestore mirror
/// - Windows/Linux: skip callable (unsupported); just read Firestore mirror
Future<bool> refreshPremiumStatusUnified() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) throw Exception('Not signed in');

  if (supportsFirebaseFunctionsClient) {
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('syncPremiumFromRC');
      await fn.call(<String, dynamic>{});
    } catch (e) {
      debugPrint('syncPremiumFromRC callable failed: $e');
    }
  }

  final snap = await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('premium')
      .doc('status')
      .get();

  final data = snap.data() ?? const {};
  final premiumActive = (data['active'] as bool?) ?? false;
  final proOfflineOwned = (data['proOffline'] as bool?) ?? false;

  FeatureGate.instance.applyBackendMirror(
    premiumActive: premiumActive,
    proOfflineOwned: proOfflineOwned,
  );

  return premiumActive;
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

// Try to find the Pro-Offline package from Offerings.
Package? _pickProOfflinePackage(Offerings offerings) {
  bool matches(Package p) {
    final id = p.identifier.toLowerCase();
    final spId = p.storeProduct.identifier.toLowerCase();
    final title = p.storeProduct.title.toLowerCase();
    return id.contains('pro') ||
        spId.contains('pro_offline') ||
        title.contains('pro-offline') ||
        title.contains('pro offline');
  }

  final current = offerings.current;
  if (current != null) {
    for (final p in current.availablePackages) {
      if (matches(p)) return p;
    }
  }

  final def = offerings.all['default'];
  if (def != null) {
    for (final p in def.availablePackages) {
      if (matches(p)) return p;
    }
  }

  for (final entry in offerings.all.values) {
    for (final p in entry.availablePackages) {
      if (matches(p)) return p;
    }
  }

  return null;
}

Future<void> _purchaseProOffline(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);

  try {
    final offerings = await RevenueCatService.instance.getOfferings();
    final pkg = _pickProOfflinePackage(offerings);

    if (pkg == null) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Pro-Offline product not available right now.')),
      );
      return;
    }

    await RevenueCatService.instance.purchasePackage(pkg);
    // After purchase, ensure FeatureGate gets the RC entitlement.
    await FeatureGate.instance
        .deactivateProOffline(); // clear any local override
    await RevenueCatService.instance.refreshCustomerInfo();

    if (!context.mounted) return;
    if (FeatureGate.instance.isProOffline || FeatureGate.instance.isPremium) {
      messenger
          .showSnackBar(const SnackBar(content: Text('Pro-Offline unlocked.')));
      Navigator.of(context).maybePop(true);
    } else {
      messenger.showSnackBar(
          const SnackBar(content: Text('Purchase complete, updating status…')));
    }
  } on PlatformException catch (e) {
    if (!context.mounted) return;
    final code = PurchasesErrorHelper.getErrorCode(e);
    if (code == PurchasesErrorCode.purchaseCancelledError) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('Purchase failed: ${e.message ?? code.name}')),
    );
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text('Purchase error: $e')));
  }
}

Future<void> _onUpgradeTap(
  BuildContext context,
  Future<void> Function() scrollToPlans,
) async {
  if (RevenueCatService.instance.isSupported) {
    try {
      final offerings = await RevenueCatService.instance.getOfferings();

      // ✅ Guard after the await
      if (!context.mounted) return;

      final pkgs = offerings.current?.availablePackages ?? const <Package>[];

      Package? annual = _firstByType(pkgs, PackageType.annual);
      Package? monthly = _firstByType(pkgs, PackageType.monthly);
      final target = annual ?? monthly ?? (pkgs.isNotEmpty ? pkgs.first : null);

      if (target == null) {
        if (!context.mounted) return;
        snacks.show(const SnackBar(
            content: Text('No Premium products available right now.')));
        return;
      }

      if (!context.mounted) return;
      await _purchase(context, target);
    } catch (e) {
      if (!context.mounted) return;
      snacks.show(SnackBar(content: Text('Couldn’t start purchase: $e')));
    }
    return;
  }

  // Stripe/web/desktop → scroll user to plans
  await scrollToPlans();
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
    final String cyclesLabel = cycles > 1
        ? ' for $cycles ${_pluralize(unit, cycles)}'
        : ' for 1 $unit';
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
  final messenger = ScaffoldMessenger.of(context);
  try {
    await RevenueCatService.instance.purchasePackage(pkg);
    if (!context.mounted) return;
    await _afterSuccessfulPurchaseEnsurePremium(context);
  } on PlatformException catch (e) {
    final code = PurchasesErrorHelper.getErrorCode(e);
    if (code == PurchasesErrorCode.purchaseCancelledError) return;
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Purchase failed: ${e.message ?? code.name}')),
    );
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text('Purchase error: $e')));
  }
}

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String msg,
  String confirmLabel = 'OK',
  String cancelLabel = 'Cancel',
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(msg),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel)),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel)),
      ],
    ),
  );
}

/* ============================
   UI bits
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
        style: Theme.of(context)
            .textTheme
            .titleLarge!
            .copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ignore: unused_element
class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      Divider(color: Theme.of(context).colorScheme.outlineVariant);
}

class _BenefitTile extends StatelessWidget {
  const _BenefitTile({required this.icon, required this.title});
  final IconData icon;
  final String title;

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
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
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
  final String price;
  final String? trialText;
  final String? billingNote;
  final String? badge;
  final VoidCallback onPressed;
  final bool enabled;
  final bool compact;
  final bool primary;

  // --- Helpers ---------------------------------------------------------------

  // Simple luminance delta check; higher means more contrast.
  static double _contrastDelta(Color a, Color b) =>
      (a.computeLuminance() - b.computeLuminance()).abs();

  // Pick the first (bg, fg) pair that contrasts well with the given surface.
  static (Color bg, Color fg) _pickHighContrastAgainst(
    Color surface, {
    required List<(Color bg, Color fg)> candidates,
    double minDelta = 0.28, // tweak threshold to taste
  }) {
    for (final pair in candidates) {
      if (_contrastDelta(pair.$1, surface) >= minDelta) return pair;
    }
    // Fallback: black/white based on surface brightness.
    final bool lightSurface =
        ThemeData.estimateBrightnessForColor(surface) == Brightness.light;
    return (
      lightSurface ? const Color(0xFF111111) : const Color(0xFFFFFFFF),
      lightSurface ? const Color(0xFFFFFFFF) : const Color(0xFF000000)
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bool emphasized = primary;

    // Card background
    final BoxDecoration deco = emphasized
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.primaryContainer,
                Color.alphaBlend(cs.primary.withOpacity(isDark ? .10 : .06),
                    cs.primaryContainer),
              ],
            ),
            border: Border.all(color: cs.primary, width: 1.25),
            boxShadow: [
              BoxShadow(
                blurRadius: 22,
                offset: const Offset(0, 10),
                color: Colors.black.withOpacity(isDark ? 0.40 : 0.10),
              ),
            ],
          )
        : BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant),
            boxShadow: [
              BoxShadow(
                blurRadius: 18,
                offset: const Offset(0, 8),
                color: Colors.black.withOpacity(isDark ? 0.35 : 0.06),
              ),
            ],
          );

    // Text on card
    final Color onBg = emphasized ? cs.onPrimaryContainer : cs.onSurface;

    final titleStyle = theme.textTheme.titleMedium!.copyWith(
      fontWeight: FontWeight.w800,
      color: onBg,
    );

    final priceStyle = theme.textTheme.headlineSmall!.copyWith(
      fontWeight: FontWeight.w900,
      color: onBg,
      height: 1.1,
    );

    final noteStyle = theme.textTheme.labelSmall!.copyWith(
      color: emphasized
          ? cs.onPrimaryContainer.withOpacity(.9)
          : cs.onSurfaceVariant,
    );

    final badgeTextColor = emphasized ? cs.onPrimaryContainer : cs.primary;
    final badgeBg = (emphasized ? cs.onPrimaryContainer : cs.primary)
        .withOpacity(isDark ? .18 : .12);

    // >>> Choose a non-blending CTA color for non-primary cards
    final Color cardSurface = emphasized ? cs.primaryContainer : cs.surface;
    final (Color normalCtaBg, Color normalCtaFg) = _pickHighContrastAgainst(
      cardSurface,
      candidates: <(Color, Color)>[
        (cs.secondary, cs.onSecondary),
        (cs.tertiary, cs.onTertiary),
        (cs.inverseSurface, cs.onInverseSurface),
        (cs.primary, cs.onPrimary),
        (cs.errorContainer, cs.onErrorContainer),
      ],
      // If your palette is very close-toned, bump to ~0.34
      minDelta: 0.30,
    );

    return Opacity(
      opacity: enabled ? 1.0 : 0.6,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Container(
          padding: EdgeInsets.all(compact ? 12 : 16),
          decoration: deco,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (badge != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: emphasized
                            ? cs.onPrimaryContainer.withOpacity(.24)
                            : cs.primary.withOpacity(.24),
                      ),
                    ),
                    child: Text(
                      badge!,
                      style: theme.textTheme.labelSmall!.copyWith(
                        color: badgeTextColor,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .2,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Text(title, style: titleStyle, textAlign: TextAlign.center),
              if (trialText != null) ...[
                const SizedBox(height: 2),
                Text(
                  trialText!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: emphasized ? cs.onPrimaryContainer : cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(price, style: priceStyle, textAlign: TextAlign.center),
              if (billingNote != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(billingNote!,
                      style: noteStyle, textAlign: TextAlign.center),
                ),
              const SizedBox(height: 10),

              // CTA: never blends with the card
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: emphasized ? cs.primary : normalCtaBg,
                    foregroundColor: emphasized ? cs.onPrimary : normalCtaFg,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: emphasized ? cs.primary : cs.outlineVariant,
                        width: emphasized ? 0.0 : 1.0,
                      ),
                    ),
                    elevation: emphasized ? 2 : 1,
                  ),
                  onPressed: onPressed,
                  child: Text(
                    'Continue',
                    style: theme.textTheme.labelLarge!.copyWith(
                      color: emphasized ? cs.onPrimary : normalCtaFg,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TonalButton extends StatelessWidget {
  const TonalButton({super.key, required this.label, required this.onPressed});
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
          style:
              theme.textTheme.bodySmall!.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          children: [
            TextButton(
              onPressed: () =>
                  launchUrl(Uri.parse('https://fermentacraft.com/terms.html')),
              child: const Text('Terms'),
            ),
            TextButton(
              onPressed: () => launchUrl(
                  Uri.parse('https://fermentacraft.com/privacy.html')),
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
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}
