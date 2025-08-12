import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

// Hive model imports
import '../models/recipe_model.dart';
import '../models/batch_model.dart';
import '../models/inventory_item.dart';
import '../models/tag.dart';
import '../models/shopping_list_item.dart';

// Cross-platform save helper (IO on device, download on web)
import '../utils/file_saver.dart';

class DataManagementService {
  static const List<String> _boxNames = [
    'recipes',
    'settings',
    'tags',
    'batches',
    'inventory',
    'shopping_list',
  ];

  static final Map<String, Function> _fromJsonConstructors = {
    'recipes': (json) => RecipeModel.fromJson(json),
    'batches': (json) => BatchModel.fromJson(json),
    'inventory': (json) => InventoryItem.fromJson(json),
    'tags': (json) => Tag.fromJson(json),
    'shopping_list': (json) => ShoppingListItem.fromJson(json),
  };

  static Function fromJsonFor(String boxName) {
    final ctor = _fromJsonConstructors[boxName];
    if (ctor == null) {
      throw ArgumentError('No fromJson constructor for box: $boxName');
    }
    return ctor;
  }

  // Helper to get a typed Hive box
  static Box getTypedBox(String name) {
    switch (name) {
      case 'recipes':
        return Hive.box<RecipeModel>('recipes');
      case 'batches':
        return Hive.box<BatchModel>('batches');
      case 'inventory':
        return Hive.box<InventoryItem>('inventory');
      case 'tags':
        return Hive.box<Tag>('tags');
      case 'settings':
        return Hive.box('settings');
      case 'shopping_list':
        return Hive.box<ShoppingListItem>('shopping_list');
      default:
        throw Exception('Unknown box name: $name');
    }
  }

  /// Deletes all data from all Hive boxes and reopens them with correct types.
  static Future<void> clearAllData() async {
    try {
      for (final boxName in _boxNames) {
        await Hive.deleteBoxFromDisk(boxName);
        switch (boxName) {
          case 'recipes':
            await Hive.openBox<RecipeModel>(boxName);
            break;
          case 'batches':
            await Hive.openBox<BatchModel>(boxName);
            break;
          case 'inventory':
            await Hive.openBox<InventoryItem>(boxName);
            break;
          case 'tags':
            await Hive.openBox<Tag>(boxName);
            break;
          case 'shopping_list':
            await Hive.openBox<ShoppingListItem>(boxName);
            break;
          case 'settings':
            await Hive.openBox(boxName);
            break;
        }
      }
    } catch (e) {
      debugPrint("Error clearing all data: $e");
    }
  }

  /// Exports all Hive data to a JSON file (download on web, save/share on device).
  static Future<void> exportData(BuildContext context) async {
    try {
      final Map<String, dynamic> allData = {};

      for (final boxName in _boxNames) {
        final box = getTypedBox(boxName);

        if (boxName == 'settings') {
          final settingsMap = box.toMap();
          final typedSettingsMap = Map<String, dynamic>.from(settingsMap);
          allData[boxName] = [typedSettingsMap];
          continue;
        }

        final List<Map<String, dynamic>> boxData = [];
        for (var i = 0; i < box.length; i++) {
          final item = box.getAt(i);
          if (item == null) continue;
          try {
            final Map<String, dynamic> jsonItem = item.toJson();
            boxData.add(jsonItem);
          } catch (e) {
            throw Exception(
              "Failed to serialize item in box '$boxName'. "
              "Check the debug console for details.",
            );
          }
        }
        allData[boxName] = boxData;
      }

      final jsonString = const JsonEncoder.withIndent('  ').convert(allData);
      final bytes = utf8.encode(jsonString);

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[:.]'), '-');
      final fileName = 'fermentacraft_backup_$timestamp.json';

      final savedPath = await saveBytesToDevice(fileName, bytes);

      // Optional: share the file on device platforms when we have a path.
      if (!kIsWeb && savedPath != null) {
        final params = ShareParams(
          text: 'FermentaCraft Backup',
          files: [XFile(savedPath)],
        );
        await SharePlus.instance.share(params);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data backup created successfully!')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  /// Imports data from a user-selected JSON file.
  static Future<void> importData(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        // Always request bytes so we don't need dart:io File on any platform.
        withData: true,
      );
      if (result == null) return;

      if (context.mounted) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Confirm Import"),
            content: const Text(
              "This will overwrite all existing data. "
              "This action cannot be undone. Are you sure?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Import"),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }

      final fileBytes = result.files.single.bytes;
      if (fileBytes == null) throw Exception("No file data provided.");
      final jsonString = utf8.decode(fileBytes);

      final allData = jsonDecode(jsonString) as Map<String, dynamic>;

      for (final boxName in _boxNames) {
        if (!allData.containsKey(boxName)) continue;

        final box = getTypedBox(boxName);
        await box.clear();
        final boxData = allData[boxName] as List;

        for (var itemJson in boxData) {
          if (_fromJsonConstructors.containsKey(boxName)) {
            final item = _fromJsonConstructors[boxName]!(itemJson);
            await box.add(item);
          } else if (boxName == 'settings') {
            await box.putAll(Map<String, dynamic>.from(itemJson));
          }
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Data imported successfully! Please restart the app.'),
          ),
        );
      }
    } catch (e) {
      debugPrint("IMPORT FAILED WITH ERROR: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error importing data: $e')),
        );
      }
    }
  }
}
