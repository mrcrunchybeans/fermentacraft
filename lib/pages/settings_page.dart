// lib/pages/settings_page.dart
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:fermentacraft/utils/snacks.dart';
import 'package:fermentacraft/services/feature_gate.dart';
import 'package:fermentacraft/services/local_mode_service.dart';
import 'package:fermentacraft/services/firestore_sync_service.dart';
import 'package:fermentacraft/widgets/show_paywall.dart';
import 'package:fermentacraft/widgets/devices_selection.dart';
import 'package:fermentacraft/widgets/sync_health_dashboard.dart';
import 'package:fermentacraft/widgets/performance_dashboard.dart';

import 'package:fermentacraft/models/settings_model.dart';
import 'package:fermentacraft/utils/boxes.dart';
import 'package:fermentacraft/utils/data_management.dart';

import 'login_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // ────────────────────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────────────────────

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

  void _upsell(BuildContext context, String reason) {
    // You can thread `reason` into your paywall if desired.
    showPaywall(context);
  }

  // Single, reusable section card with header + internal dividers
  Widget _settingsGroup({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon, color: theme.colorScheme.primary),
              title: Text(title, style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: 8),
            ..._withDividers(children),
          ],
        ),
      ),
    );
  }

  List<Widget> _withDividers(List<Widget> items) {
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      out.add(items[i]);
      if (i != items.length - 1) out.add(const Divider(height: 20));
    }
    return out;
  }

  // Currency helpers
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

  Widget _currencyPicker(SettingsModel settings) {
    const String kCustomCurrency = '__CUSTOM__';
    final items = <String>[r'$', '€', '£', '₹', '¥', '₩', 'R\$', '₱'];
    if (!items.contains(settings.currencySymbol)) items.insert(0, settings.currencySymbol);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: settings.currencySymbol,
          decoration: const InputDecoration(
            labelText: 'Currency symbol',
            border: OutlineInputBorder(),
          ),
          items: [
            ...items.map((s) => DropdownMenuItem(value: s, child: Text(s))),
            const DropdownMenuItem(value: kCustomCurrency, child: Text('Custom…')),
          ],
          onChanged: (selected) async {
            if (selected == null) return;
            if (selected == kCustomCurrency) {
              await _promptCustomCurrencySymbol(settings);
            } else {
              await settings.setCurrencySymbol(selected);
            }
          },
        ),
        const SizedBox(height: 8),
        Text('Example: ${settings.currencySymbol}12.34',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Sections (content placed inside _settingsGroup)
  // ────────────────────────────────────────────────────────────────────────────

  Widget _subscriptionSection({
    required FeatureGate fg,
    required bool isLocal,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isLocal) ...[
          // Polished Local Mode banner
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.dividerColor.withOpacity(.12)),
            ),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.cloud_off, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("You’re using Local Mode",
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        SizedBox(height: 6),
                        Text(
                          "Everything stays on this device. Link an account to enable cloud sync, backups, and device integrations.",
                        ),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.link),
                    label: const Text('Link account'),
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                      );
                      if (!mounted) return;
                      if (FirebaseAuth.instance.currentUser != null) {
                        await LocalModeService.instance.clearLocalOnly();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Account linked. Sync is now available.'),
                          ),
                        );
                        setState(() {});
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],

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
            FilledButton.icon(
              icon: const Icon(Icons.upgrade),
              label: Text(fg.isPremium ? 'Switch Plan' : 'Upgrade / Switch Plan'),
              onPressed: () async => showPaywall(context),
            ),
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
                  snacks.show(const SnackBar(
                    content: Text('Switched to Pro-Offline on this device.'),
                  ));
                  setState(() {});
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _cloudSyncSection({
    required FeatureGate fg,
    required FirestoreSyncService sync,
    required User? user,
  }) {
    final isLocal = LocalModeService.instance.isLocalOnly && user == null;
    final canToggleSync = fg.allowSync && user != null && !isLocal;
    final switchValue = canToggleSync ? sync.isEnabled : false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
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
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text("Enable Sync"),
          subtitle: const Text("Sync recipes, batches, inventory, shopping list, tags, and settings"),
          value: switchValue,
          onChanged: (v) async {
            if (!fg.allowSync) {
              _upsell(context, "Cloud Sync is a Premium feature");
              return;
            }
            if (LocalModeService.instance.isLocalOnly || user == null) {
              snacks.show(const SnackBar(
                content: Text("Link an account to enable cloud sync & backups."),
              ));
              return;
            }

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
                      } else if (LocalModeService.instance.isLocalOnly || user == null) {
                        snacks.show(const SnackBar(content: Text('Link an account to sync.')));
                      } else {
                        snacks.show(const SnackBar(content: Text('Enable Sync first.')));
                      }
                    },
            ),
            const Spacer(),
            if (user == null || isLocal)
              const Text("Tip: Link an account to enable syncing."),
          ],
        ),
      ],
    );
  }

Widget _devicesSection(FeatureGate fg) {
  final user = FirebaseAuth.instance.currentUser;
  final isAnon = user?.isAnonymous ?? false;
  final hasAccount = user != null && !isAnon; // real/linked account

  final baseTile = ListTile(
    leading: const Icon(Icons.sensors),
    title: const Text('Devices'),
    subtitle: Text(
      hasAccount
          ? 'Link, unlink, and view device ingest details.'
          : 'Create/link an account to enable device ingestion.',
    ),
    onTap: () {
      if (hasAccount && fg.allowDevices) {
        DevicesSelection.openWithCurrentUser(context);
      }
    },
  );

  final tileSurface = Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Theme.of(context).dividerColor.withOpacity(.15)),
    ),
    child: baseTile,
  );

  // Block if no real account OR plan doesn’t allow devices
  final needsOverlay = !hasAccount || !fg.allowDevices;
  if (!needsOverlay) return tileSurface;

  final overlayLabel = hasAccount
      ? 'Premium only'
      : 'Premium only';

  return ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: _DimGateOverlay(
      label: overlayLabel,
      onTap: () async {
        if (hasAccount) {
          showPaywall(context);
        } else {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LoginPage()),
          );
          if (!mounted) return;
          setState(() {}); // refresh if auth state changed
        }
      },
      child: tileSurface,
    ),
  );
}



  Widget _debugSection(FeatureGate fg) {
    if (!kDebugMode) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        const SizedBox(height: 12),
        // Debug tools section
        Text(
          'Debug Tools',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const SyncHealthDashboard(),
                  ),
                );
              },
              icon: const Icon(Icons.sync),
              label: const Text('Sync Health'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const PerformanceDashboard(),
                  ),
                );
              },
              icon: const Icon(Icons.speed),
              label: const Text('Performance'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Note: Debug actions affect only this device. For real Premium, purchase via Paywall.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
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

  // ────────────────────────────────────────────────────────────────────────────
  // Build
  // ────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    final sync = FirestoreSyncService.instance;
    final user = FirebaseAuth.instance.currentUser;
    final fg = context.watch<FeatureGate>();
    final isLocal = LocalModeService.instance.isLocalOnly && user == null;

    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Account & Sync
          _settingsGroup(
            icon: Icons.account_circle_outlined,
            title: "Account & Sync",
            children: [
              _subscriptionSection(fg: fg, isLocal: isLocal),
              _cloudSyncSection(fg: fg, sync: sync, user: user),
              _devicesSection(fg),
            ],
          ),

          // Personalization
          _settingsGroup(
            icon: Icons.tune,
            title: "Personalization",
            children: [
              // Units
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text("Temperature Unit"),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text("Celsius (°C)")),
                      ButtonSegment(value: false, label: Text("Fahrenheit (°F)")),
                    ],
                    selected: {settings.useCelsius},
                    onSelectionChanged: (s) => settings.setUnit(isCelsius: s.first),
                  ),
                ],
              ),

              // Currency
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text("Currency"),
                  const SizedBox(height: 8),
                  _currencyPicker(settings),
                ],
              ),

              // Appearance
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    onSelectionChanged: (s) => settings.changeTheme(s.first),
                  ),
                ],
              ),
            ],
          ),

          // Data & Backup
          _settingsGroup(
            icon: Icons.folder_open,
            title: "Data & Backup",
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

          if (kDebugMode)
            _settingsGroup(
              icon: Icons.bug_report,
              title: "Developer / Debug",
              children: [
                _debugSection(fg),
                ListTile(
                  leading: const Icon(Icons.monitor_heart),
                  title: const Text('Sync Health Dashboard'),
                  subtitle: const Text('Monitor sync operations and test error handling'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SyncHealthDashboard()),
                  ),
                ),
              ],
            ),

          // Keep Danger Zone visually distinct
          _dangerZoneCard(),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Top-level helpers (not nested) used by Devices row
// ──────────────────────────────────────────────────────────────────────────────

class _DimGateOverlay extends StatelessWidget {
  const _DimGateOverlay({
    required this.child,
    required this.onTap,
    this.label = 'Premium only',
  });

  final Widget child;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        child,
        Positioned.fill(
          child: Material(
            color: Colors.black.withOpacity(isDark ? 0.12 : 0.07),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: theme.dividerColor.withOpacity(.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline, size: 18),
                      const SizedBox(width: 8),
                      Text(label),
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
