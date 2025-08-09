import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/data_management.dart';
import '../models/settings_model.dart';
import '../services/firestore_sync_service.dart';

// FIX: Convert to a StatefulWidget
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Helper for creating section titles
  Widget _sectionTitle(String title, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    final sync = FirestoreSyncService.instance;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // --- CLOUD SYNC (Firebase + Firestore) ---
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
                    title: Text(user == null
                        ? "Signed in as: Not signed in"
                        : "Signed in as: ${user.email ?? "Signed in"}"),
                    subtitle: Text(
                      user == null
                          ? "Sign in to enable online sync across devices."
                          : "",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Enable Sync"),
                    subtitle: const Text(
                        "Sync recipes, batches, inventory, shopping list, tags, and settings"),
                    value: sync.isEnabled,
                    onChanged: (v) async {
  setState(() {
    sync.isEnabled = v;
  });

  if (v && user != null) {
    // Capture the messenger BEFORE the async gap.
    final messenger = ScaffoldMessenger.of(context);
    
    await sync.forceSync();
    
    if (!mounted) return;
    
    // Use the captured messenger instance AFTER the gap.
    messenger.showSnackBar(
      const SnackBar(
          content:
              Text("Sync enabled. Merging changes…")),
    );
  }
},
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: (user != null && sync.isEnabled)
                            ? () {
                                // instant feedback
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Sync queued…')),
                                );
                                // fire and forget
                                sync.forceSync();
                              }
                            : null,
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

          // --- UNITS SECTION ---
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
                      ButtonSegment(
                          value: false, label: Text("Fahrenheit (°F)")),
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

          // --- APPEARANCE SECTION ---
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
                      ButtonSegment(
                          value: ThemeMode.light,
                          label: Text("Light"),
                          icon: Icon(Icons.wb_sunny)),
                      ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text("Dark"),
                          icon: Icon(Icons.nightlight_round)),
                      ButtonSegment(
                          value: ThemeMode.system,
                          label: Text("System"),
                          icon: Icon(Icons.settings_suggest)),
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

          // --- DATA MANAGEMENT SECTION ---
          _sectionTitle("Data Management", context),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: const Text("Export Data"),
                  subtitle: const Text(
                      "Save a backup of all your recipes and inventory."),
                  onTap: () {
                    DataManagementService.exportData(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.download_for_offline),
                  title: const Text("Import Data"),
                  subtitle: const Text("Restore from a backup file."),
                  onTap: () {
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
              leading:
                  const Icon(Icons.warning_amber_rounded, color: Colors.red),
              title:
                  const Text("Clear All Data", style: TextStyle(color: Colors.red)),
              subtitle:
                  const Text("Deletes all recipes, batches, and inventory."),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Are you sure?"),
                    content: const Text(
                        "This action is irreversible and will delete all of your data."),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Cancel"),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red),
                        onPressed: () async {
  // Capture the navigator and messenger BEFORE the async gap.
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  await DataManagementService.clearAllData();

  if (!mounted) return;
  
  // Use the captured instances AFTER the gap.
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