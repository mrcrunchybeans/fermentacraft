// lib/pages/settings_page.dart
import 'package:fermentacraft/widgets/show_paywall.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:fermentacraft/services/feature_gate.dart';
// adjust if your PaywallPage is elsewhere

import '../utils/data_management.dart';
import '../models/settings_model.dart';
import '../services/firestore_sync_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Widget _sectionTitle(String title, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }

  void _upsell(BuildContext context, String reason) {
showPaywall(context);

  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    final sync = FirestoreSyncService.instance;
    final user = FirebaseAuth.instance.currentUser;
    final fg = FeatureGate.instance;

    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // --- CLOUD SYNC (visible, Pro-only functionality) ---
          _sectionTitle("Cloud Sync", context),
          Card(
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

                  // Soft-lock: switch remains visible; Free shows upsell
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Enable Sync"),
                    subtitle: const Text(
                      "Sync recipes, batches, inventory, shopping list, tags, and settings",
                    ),
                    value: fg.allowSync ? sync.isEnabled : false, // force OFF if free
                    onChanged: (v) async {
                      if (!fg.allowSync) {
                        _upsell(context, "Cloud Sync is a Pro feature");
                        return;
                      }
                      if (v && user == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Please sign in to enable sync.")),
                        );
                        return;
                      }

                      setState(() {
                        sync.isEnabled = v;
                      });

                      if (v) {
                        final messenger = ScaffoldMessenger.of(context);
                        await sync.forceSync();
                        if (!mounted) return;
                        messenger.showSnackBar(
                          const SnackBar(content: Text("Sync enabled. Merging changes…")),
                        );
                      }
                    },
                  ),

                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: (fg.allowSync && user != null && sync.isEnabled)
                            ? () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Sync queued…')),
                                );
                                sync.forceSync();
                              }
                            : () {
                                if (!fg.allowSync) {
                                  _upsell(context, "Cloud Sync is a Premium feature");
                                } else if (user == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please sign in to sync.')),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Enable Sync first.')),
                                  );
                                }
                              },
                        icon: const Icon(Icons.sync),
                        label: const Text("Sync now"),
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
          ),

          // --- UNITS ---
          _sectionTitle("Units", context),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Text("Temperature Unit"),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text("Celsius (°C)")),
                    // ignore: prefer_const_constructors
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
          ),

          // --- APPEARANCE ---
          _sectionTitle("Appearance", context),
          Card(
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
          ),

          // --- DATA MANAGEMENT ---
          _sectionTitle("Data Management", context),
          Card(
            child: Column(
              children: [
                // Export is Pro-only (soft-locked)
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: const Text("Export Data"),
                  subtitle: const Text("Save a backup of all your recipes and inventory."),
                  onTap: () {
                    if (!fg.allowDataExport) {
                      _upsell(context, "Export is a Pro feature");
                      return;
                    }
                    DataManagementService.exportData(context);
                  },
                ),
                // Import is allowed for Free (your choice; you can gate it too)
                ListTile(
                  leading: const Icon(Icons.download_for_offline),
                  title: const Text("Import Data"),
                  subtitle: const Text("Restore from a backup file."),
                  onTap: () {
                    // If you want to lock import too, uncomment:
                    // if (!fg.allowDataExport) { _upsell(context, "Import from backup is a Pro feature"); return; }
                    DataManagementService.importData(context);
                  },
                ),
              ],
            ),
          ),

          // --- DANGER ZONE ---
          _sectionTitle("Danger Zone", context),
          Card(
            color: Colors.red[50],
            child: ListTile(
              leading: const Icon(Icons.warning_amber_rounded, color: Colors.red),
              title: const Text("Clear All Data", style: TextStyle(color: Colors.red)),
              subtitle: const Text("Deletes all recipes, batches, and inventory."),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Are you sure?"),
                    content: const Text("This action is irreversible and will delete all of your data."),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Cancel"),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () async {
                          final navigator = Navigator.of(context);
                          final messenger = ScaffoldMessenger.of(context);
                          await DataManagementService.clearAllData();
                          if (!mounted) return;
                          navigator.pop();
                          messenger.showSnackBar(
                            const SnackBar(content: Text("All data has been cleared.")),
                          );
                        },
                        child: const Text("Delete Everything"),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
