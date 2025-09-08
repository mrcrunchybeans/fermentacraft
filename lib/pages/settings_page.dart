// lib/pages/settings_page.dart
// ignore_for_file: deprecated_member_use

import 'package:fermentacraft/widgets/show_paywall.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fermentacraft/utils/snacks.dart';
import 'package:fermentacraft/services/feature_gate.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../utils/boxes.dart';
import '../../utils/data_management.dart';
import '../../models/settings_model.dart';
import 'package:fermentacraft/services/firestore_sync_service.dart';
import 'package:fermentacraft/widgets/devices_selection.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // --- helpers ---------------------------------------------------------------
Future<bool?> _confirm({
  required String title,
  required String message,
  String confirmLabel = 'OK',
  String cancelLabel = 'Cancel',
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancelLabel)),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirmLabel)),
      ],
    ),
  );
}

Widget _manageSubscriptionCard(FeatureGate fg) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;

  // Change the URL to your customer portal / help page
  return Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              fg.isPremium ? Icons.verified : (fg.isProOffline ? Icons.cloud_off : Icons.star_border),
              color: cs.primary,
            ),
            title: const Text('Subscription & Premium'),
            subtitle: Text(
              fg.isPremium
                  ? 'Premium is active (cloud + sync).'
                  : (fg.isProOffline
                      ? 'Pro-Offline is active (all offline premium features).'
                      : 'Free plan.'),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              // Open your paywall to upgrade/downgrade
              FilledButton.icon(
                icon: const Icon(Icons.upgrade),
                label: Text(fg.isPremium ? 'Switch Plan' : 'Upgrade / Switch Plan'),
                onPressed: () async {
                  await showPaywall(context);
                },
              ),

              // External manage link (App Store / Play / Stripe portal, or FAQ)
              

              if (fg.isPremium)
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.cloud_off),
                  label: const Text('Switch to Pro-Offline'),
                  onPressed: () async {
                    final ok = await _confirm(
                      title: 'Switch to Pro-Offline?',
                      message:
                          'This disables cloud sync/backup and live device streaming in the app. '
                          'If you have an active subscription, cancel it in your store/Stripe to stop future charges.\n\nProceed?',
                      confirmLabel: 'Switch',
                    );
                    if (ok != true) return;
                    await FeatureGate.instance.activateProOffline();
                    if (!mounted) return;
                    snacks.show(const SnackBar(content: Text('Switched to Pro-Offline on this device.')));
                    setState(() {});
                  },
                ),

                
            ],
          ),
        ],
      ),
    ),
  );
}

Widget _debugPlanCard(FeatureGate fg) {
  if (!kDebugMode) return const SizedBox.shrink();

  return Card(
    color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(.4),
    child: Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.bug_report),
            title: Text('Developer / Debug'),
            subtitle: Text('Quickly test plan gates on this device.'),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () async {
                  await FeatureGate.instance.deactivateProOffline();
                  FeatureGate.instance.setFromBackend(false); // Free
                  if (!mounted) return;
                  snacks.show(const SnackBar(content: Text('Plan set to Free (debug).')));
                  setState(() {});
                },
                child: const Text('Set Free'),
              ),
              FilledButton.tonal(
                onPressed: () async {
                  await FeatureGate.instance.activateProOffline();
                  if (!mounted) return;
                  snacks.show(const SnackBar(content: Text('Plan set to Pro-Offline (debug).')));
                  setState(() {});
                },
                child: const Text('Set Pro-Offline'),
              ),
              FilledButton.tonal(
                onPressed: () async {
                  // Premium: clear Pro-Offline override, then mirror backend/RC as Premium.
                  await FeatureGate.instance.deactivateProOffline();
                  FeatureGate.instance.setFromBackend(true); // Pretend backend says Premium
                  if (!mounted) return;
                  snacks.show(const SnackBar(content: Text('Plan set to Premium (debug).')));
                  setState(() {});
                },
                child: const Text('Set Premium'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Note: Debug actions affect only this device. For real Premium, purchase via Paywall.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}


  Widget _sectionTitle(String title, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }

  void _upsell(BuildContext context, String reason) {
    // You can also pass the reason into your paywall if you want.
    showPaywall(context);
  }

  // Popular currency symbols. Use a sentinel for the "Custom…" item.
  static const String _kCustomCurrency = '__CUSTOM__';
  static final List<String> _kCommonCurrencies = <String>[
    r'$',
    '€',
    '£',
    '₹',
    '¥',
    '₩',
    'R\$',
    '₱',
  ];

  Widget _devicesCard(FeatureGate fg) {
  final baseCard = Card(
    child: Column(
      children: [
        ListTile(
          leading: const Icon(Icons.sensors),
          title: const Text('Devices'),
          subtitle: const Text('Link, unlink, and view device ingest details.'),
          onTap: () {
            // Will be wrapped by gate; here it’s the real action when Premium
            DevicesSelection.openWithCurrentUser(context);
          },
        ),
      ],
    ),
  );

  if (fg.allowDevices) return baseCard;

  // Free tier → dim + paywall on tap
  return _PremiumGate(
    child: baseCard,
    onTap: () => showPaywall(context),
  );
}


  // Prompts user for a custom currency symbol (1–4 visible chars is reasonable).
  Future<void> _promptCustomCurrencySymbol(SettingsModel settings) async {
    final controller = TextEditingController(text: settings.currencySymbol);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Custom currency'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter a symbol (e.g. kr, CHF, ₪)',
          ),
          maxLength: 4,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await settings.setCurrencySymbol(result);
    }
  }

  // --- cards -----------------------------------------------------------------

Widget _cloudSyncCard({
  required FeatureGate fg,
  required FirestoreSyncService sync,
  required User? user,
}) {
  final canToggleSync = fg.allowSync && user != null; // Premium + signed in
  final switchValue = canToggleSync ? sync.isEnabled : false;

  return Card(
    child: Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.all(12.0),
            leading: const Icon(Icons.person_outline),
            title: Text(
              user == null
                  ? "Signed in as: Not signed in"
                  : "Signed in as: ${user.email ?? "Signed in"}",
            ),
            subtitle: Text(
              user == null ? "Sign in to enable online sync across devices." : "",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 4),

          // Use computed value + keep handler defensive
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text("Enable Sync"),
            subtitle: const Text(
              "Sync recipes, batches, inventory, shopping list, tags, and settings",
            ),
            value: switchValue,
            onChanged: (v) async {
              // Guardrails (also serve as messages for disabled state)
              if (!fg.allowSync) {
                _upsell(context, "Cloud Sync is a Premium feature");
                return;
              }
              if (user == null) {
                snacks.show(const SnackBar(content: Text("Please sign in to enable sync.")));
                return;
              }

              // Persist + apply
              Hive.box(Boxes.settings).put('syncEnabled', v);
              setState(() => sync.isEnabled = v);

              if (v) {
                await sync.init();
                await sync.forceSync();
                if (!mounted) return;
                snacks.show(const SnackBar(content: Text("Sync enabled. Merging changes…")));
              } else {
                snacks.show(const SnackBar(content: Text("Sync disabled.")));
              }
            },
          ),

          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.sync),
                label: const Text("Sync now"),
                onPressed: (canToggleSync && sync.isEnabled)
                    ? () {
                        snacks.show(const SnackBar(content: Text('Sync queued…')));
                        sync.forceSync();
                      }
                    : () {
                        if (!fg.allowSync) {
                          _upsell(context, "Cloud Sync is a Premium feature");
                        } else if (user == null) {
                          snacks.show(const SnackBar(content: Text('Please sign in to sync.')));
                        } else {
                          snacks.show(const SnackBar(content: Text('Enable Sync first.')));
                        }
                      },
              ),
              const SizedBox(width: 12),
              if (user == null)
                const Expanded(
                  child: Text(
                    "Tip: Sign in to enable syncing.",
                    textAlign: TextAlign.right,
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}


  Widget _unitsCard(SettingsModel settings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text("Temperature Unit"),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text("Celsius (°C)")),
                ButtonSegment(value: false, label: Text("Fahrenheit (°F)")),
              ],
              selected: {settings.useCelsius},
              onSelectionChanged: (Set<bool> newSelection) {
                settings.setUnit(isCelsius: newSelection.first);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _currencyCard(SettingsModel settings) {
    // Build item list: ensure current symbol is present even if custom.
    final List<String> items = [..._kCommonCurrencies];
    if (!items.contains(settings.currencySymbol)) {
      items.insert(0, settings.currencySymbol);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Currency"),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: settings.currencySymbol,
              decoration: const InputDecoration(
                labelText: 'Currency symbol',
                border: OutlineInputBorder(),
              ),
              items: [
                ...items.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                const DropdownMenuItem(
                  value: _kCustomCurrency,
                  child: Text('Custom…'),
                ),
              ],
              onChanged: (selected) async {
                if (selected == null) return;
                if (selected == _kCustomCurrency) {
                  await _promptCustomCurrencySymbol(settings);
                } else {
                  await settings.setCurrencySymbol(selected);
                }
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Example: ${settings.currencySymbol}12.34',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _appearanceCard(SettingsModel settings) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text("Theme"),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light,  label: Text("Light"),  icon: Icon(Icons.wb_sunny)),
                ButtonSegment(value: ThemeMode.dark,   label: Text("Dark"),   icon: Icon(Icons.nightlight_round)),
                ButtonSegment(value: ThemeMode.system, label: Text("System"), icon: Icon(Icons.settings_suggest)),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (Set<ThemeMode> newSelection) {
                settings.changeTheme(newSelection.first);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _dataManagementCard(FeatureGate fg) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text("Export Data"),
            subtitle: const Text("Save a backup of all your recipes and inventory."),
            onTap: () {
              if (!fg.allowDataExport) {
                _upsell(context, "Export is a Premium feature");
                return;
              }
              DataManagementService.exportData(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.download_for_offline),
            title: const Text("Import Data"),
            subtitle: const Text("Restore from a backup file."),
            onTap: () => DataManagementService.importData(context),
          ),
        ],
      ),
    );
  }

  Widget _dangerZoneCard() {
  final theme = Theme.of(context);
  final container = theme.colorScheme.errorContainer;
  final onContainer = theme.colorScheme.onErrorContainer;

  return Card(
    color: container,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: theme.colorScheme.error.withOpacity(0.35)),
    ),
    child: ListTile(
      leading: Icon(Icons.warning_amber_rounded, color: onContainer),
      title: Text(
        "Clear All Data",
        style: theme.textTheme.titleMedium?.copyWith(color: onContainer),
      ),
      subtitle: Text(
        "Deletes all recipes, batches, inventory, tags, and settings.",
        style: theme.textTheme.bodySmall?.copyWith(
          color: onContainer.withOpacity(0.9),
        ),
      ),
      onTap: () {
        showDialog(
          context: context,
          builder: (context) {
            final t = Theme.of(context);
            return AlertDialog(
              title: const Text("Are you sure?"),
              content: const Text(
                "This action is irreversible and will delete all of your data.",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                // delete button moved to use themed error colors
                ElevatedButton.icon(
                  icon: const Icon(Icons.delete_forever),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.colorScheme.error,
                    foregroundColor: t.colorScheme.onError,
                  ),
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final messenger = snacks;
                    await DataManagementService.clearAllData();
                    if (!mounted) return;
                    navigator.pop();
                    messenger.show(
                      const SnackBar(content: Text("All data has been cleared.")),
                    );
                  },
                  label: const Text("Delete Everything"),
                ),
              ],
            );
          },
        );
      },
    ),
  );
}


  // --- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    final sync = FirestoreSyncService.instance;
    final user = FirebaseAuth.instance.currentUser;
    final fg = context.watch<FeatureGate>();

    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionTitle("Cloud Sync", context),
          _cloudSyncCard(fg: fg, sync: sync, user: user),

          _sectionTitle("Account & Subscription", context),
          _manageSubscriptionCard(fg),

          _sectionTitle("Devices", context),
          _devicesCard(fg),

          _sectionTitle("Units", context),
          _unitsCard(settings),

          _sectionTitle("Currency", context),
          _currencyCard(settings),

          _sectionTitle("Appearance", context),
          _appearanceCard(settings),

          _sectionTitle("Data Management", context),
          _dataManagementCard(fg),

          if (kDebugMode) _sectionTitle("Developer / Debug", context),
          if (kDebugMode) _debugPlanCard(fg),

          _sectionTitle("Danger Zone", context),
          _dangerZoneCard(),
        ],
      ),
    );
  }
}
class _PremiumGate extends StatelessWidget {
  const _PremiumGate({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        Opacity(opacity: 0.45, child: child),
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: theme.dividerColor.withOpacity(.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.lock_outline, size: 18),
                      SizedBox(width: 8),
                      Text('Premium only – Tap to upgrade'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
