// lib/pages/paywall_page.dart
import 'package:flutter/material.dart';
import '../services/feature_gate.dart';

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
                      // Consistent H1
                      Text(
                        'Unlock FermentaCraft Premium',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Everything you need to ferment smarter.',
                        style: theme.textTheme.bodyMedium?.copyWith(
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
                    // Consistent H2
                    Text(
                      'Remove Free Version Limitations',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _BenefitTile(
                      icon: Icons.all_inclusive,
                      title: 'Unlimited recipes, batches & inventory',
                      subtitle:
                          'Move past caps on recipes, active batches, and your inventory. Grow without limits.',
                    ),
                    _BenefitTile(
                      icon: Icons.lock_open,
                      title: 'Unlock all soft-locked tools',
                      subtitle:
                          'Gain full access to advanced calculators and tools when you need them most.',
                    ),

                    const SizedBox(height: 16),
                    Divider(color: cs.outlineVariant),
                    const SizedBox(height: 16),

                    // Consistent H2
                    Text(
                      'What You Get with Premium',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const _FeatureBullet(
                        text:
                            'Unlimited recipes, batches, inventory, and archives'),
                    const _FeatureBullet(
                        text:
                            'Advanced tools: Gravity & ABV, pH, acid, SO₂, and strip readers'),
                    const _FeatureBullet(
                        text: 'Cloud sync across devices & full data export'),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Plan Cards
                Row(
                  children: [
                    // Annual Plan Card
                    Expanded(
                      child: _PlanOptionCard(
                        title: 'Yearly',
                        price: '\$30',
                        subtitle: 'Best Value',
                        savings: 'Save 17%',
                        onPressed: () {
                          // Logic for annual purchase
                          FeatureGate.instance.isPro = true;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Annual plan simulated.'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                          Navigator.pop(context, true);
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Monthly Plan Card
                    Expanded(
                      child: _PlanOptionCard(
                        title: 'Monthly',
                        price: '\$3',
                        subtitle: 'Flexible',
                        onPressed: () {
                          // Logic for monthly purchase
                          FeatureGate.instance.isPro = true;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Monthly plan simulated.'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                          Navigator.pop(context, true);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    // Logic for restoring purchases goes here
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Restoring purchases...'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  child: const Text('Restore Purchases'),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // Dialog mode: body only; parent provides Material + width.
    if (asDialog) return content;

    // Full-screen page mode
    return Scaffold(
      appBar: AppBar(title: const Text('Go Premium')),
      body: content,
    );
  }
}

// Reusable widget for highlighting benefits with an icon and text
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

// New widget to create a simple, clear bullet point list
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

// New widget to represent a plan option as a card
class _PlanOptionCard extends StatelessWidget {
  const _PlanOptionCard({
    required this.title,
    required this.price,
    required this.subtitle,
    required this.onPressed,
    this.savings,
  });

  final String title;
  final String price;
  final String subtitle;
  final String? savings;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isBestValue = savings != null;

    return Semantics(
      container: true,
      label: '$title plan',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isBestValue ? cs.primaryContainer.withValues(alpha:0.2) : cs.surface,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'BEST VALUE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$price / ${title.toLowerCase()}',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (savings != null)
              Text(
                savings!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: isBestValue ? cs.primary : cs.surfaceContainerHigh,
                  foregroundColor: isBestValue ? cs.onPrimary : cs.onSurface,
                ),
                child: Text(isBestValue ? 'Go Yearly' : 'Go Monthly'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Removes the overscroll glow for a cleaner modal feel.
class _NoGlow extends ScrollBehavior {
  const _NoGlow();
  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}