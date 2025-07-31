import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive/hive.dart';

import '../models/settings_model.dart';
import '../utils/temp_display.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

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
    final settings = Provider.of<SettingsModel>(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
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
                      ButtonSegment(value: false, label: Text("Fahrenheit (°F)")),
                    ],
                    selected: {settings.useCelsius},
                    onSelectionChanged: (Set<bool> newSelection) async {
                      settings.toggleUnit();
                      await Hive.box('settings').put('useCelsius', newSelection.first);
                      TempDisplay.setUseFahrenheit(!newSelection.first);
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
                      ButtonSegment(value: ThemeMode.light, label: Text("Light"), icon: Icon(Icons.wb_sunny)),
                      ButtonSegment(value: ThemeMode.dark, label: Text("Dark"), icon: Icon(Icons.nightlight_round)),
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

          // --- DATA MANAGEMENT SECTION ---
          _sectionTitle("Data Management", context),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: const Text("Export Data"),
                  subtitle: const Text("Save a backup of all your recipes and inventory."),
                  onTap: () {
                    // Placeholder for export logic
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Export feature coming soon!")),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.download_for_offline),
                  title: const Text("Import Data"),
                  subtitle: const Text("Restore from a backup file."),
                  onTap: () {
                    // Placeholder for import logic
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Import feature coming soon!")),
                    );
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
                        onPressed: () {
                          // Placeholder for clearing all Hive boxes
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
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
