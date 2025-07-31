import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

class DataManagementService {
  // List of all your Hive box names
  static const List<String> _boxNames = [
    'recipes',
    'settings',
    'tags',
    'batches',
    'measurementLogs',
    'fermentationStages',
    'inventory',
    'inventoryTransactions',
  ];

  /// Exports all Hive data to a single JSON file and shares it.
  static Future<void> exportData(BuildContext context) async {
    try {
      final Map<String, dynamic> allData = {};

      for (final boxName in _boxNames) {
        final box = await Hive.openBox(boxName);
        // Convert box data to a list of maps for JSON serialization
        final boxData = box.toMap().entries.map((e) => e.value).toList();
        allData[boxName] = boxData;
      }

      final jsonString = jsonEncode(allData);
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/cidercraft_backup.json';
      final file = File(filePath);
      await file.writeAsString(jsonString);

      // Use share_plus to open the native share dialog
      await Share.shareXFiles([XFile(filePath)], text: 'CiderCraft Backup');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data backup created successfully!')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting data: $e')),
        );
      }
    }
  }

  /// Imports data from a JSON file and overwrites existing Hive data.
  static Future<void> importData(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.single.path == null) {
        return; // User canceled the picker
      }

      final file = File(result.files.single.path!);
      final jsonString = await file.readAsString();
      final allData = jsonDecode(jsonString) as Map<String, dynamic>;

      if (context.mounted) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Confirm Import"),
            content: const Text(
                "This will overwrite all existing data. This action cannot be undone. Are you sure you want to continue?"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
              ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Import")),
            ],
          ),
        );

        if (confirmed != true) return;
      }

      for (final boxName in _boxNames) {
        if (allData.containsKey(boxName)) {
          final box = await Hive.openBox(boxName);
          await box.clear();
          final boxData = allData[boxName] as List;
          for (var item in boxData) {
            // HiveObjects need to be added, not put with a key
            if (item is HiveObject) {
               await box.add(item);
            } else {
               // For simple boxes like 'settings'
               await box.putAll(Map<String, dynamic>.from(item));
            }
          }
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data imported successfully! Please restart the app.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error importing data: $e')),
        );
      }
    }
  }
}
