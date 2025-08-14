// lib/utils/data_management.dart
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';

import '../utils/boxes.dart';

// Hive model imports
import '../models/recipe_model.dart';
import '../models/batch_model.dart';
import '../models/inventory_item.dart';
import '../models/tag.dart';
import '../models/shopping_list_item.dart';

// Cross-platform save helper (IO on device, download on web)
import '../utils/file_saver.dart';

class DataManagementService {
  // Use your canonical box names from Boxes.* to avoid typos.
  static const List<String> _boxNames = [
    Boxes.recipes,
    Boxes.settings,
    Boxes.tags,
    Boxes.batches,
    Boxes.inventory,
    Boxes.shoppingList,
  ];

  static final Map<String, Function> _fromJsonConstructors = {
    Boxes.recipes: (json) => RecipeModel.fromJson(json),
    Boxes.batches: (json) => BatchModel.fromJson(json),
    Boxes.inventory: (json) => InventoryItem.fromJson(json),
    Boxes.tags: (json) => Tag.fromJson(json),
    Boxes.shoppingList: (json) => ShoppingListItem.fromJson(json),
  };

  static Function fromJsonFor(String boxName) {
    final ctor = _fromJsonConstructors[boxName];
    if (ctor == null) {
      throw ArgumentError('No fromJson constructor for box: $boxName');
    }
    return ctor;
  }

  // Helper to get a typed Hive box that is ALREADY OPEN.
  static Box getTypedBox(String name) {
    switch (name) {
      case Boxes.recipes:
        return Hive.box<RecipeModel>(Boxes.recipes);
      case Boxes.batches:
        return Hive.box<BatchModel>(Boxes.batches);
      case Boxes.inventory:
        return Hive.box<InventoryItem>(Boxes.inventory);
      case Boxes.tags:
        return Hive.box<Tag>(Boxes.tags);
      case Boxes.settings:
        return Hive.box(Boxes.settings);
      case Boxes.shoppingList:
        return Hive.box<ShoppingListItem>(Boxes.shoppingList);
      default:
        throw Exception('Unknown box name: $name');
    }
  }

  // Helper to OPEN a typed box when it's currently closed.
  static Future<Box> _openTypedBox(String name) {
    switch (name) {
      case Boxes.recipes:
        return Hive.openBox<RecipeModel>(Boxes.recipes);
      case Boxes.batches:
        return Hive.openBox<BatchModel>(Boxes.batches);
      case Boxes.inventory:
        return Hive.openBox<InventoryItem>(Boxes.inventory);
      case Boxes.tags:
        return Hive.openBox<Tag>(Boxes.tags);
      case Boxes.settings:
        return Hive.openBox(Boxes.settings);
      case Boxes.shoppingList:
        return Hive.openBox<ShoppingListItem>(Boxes.shoppingList);
      default:
        throw Exception('Unknown box name: $name');
    }
  }

  /// --- One-time (idempotent) migration to re-key items by stable string ids/name.
  static Future<void> migrateHiveKeysToStableIds() async {
    final uuid = const Uuid();

    Future<void> rekeyBox<T>(
      Box<T> box, {
      required String Function(T) idOf,
      required void Function(T, String) setId,
    }) async {
      final keys = box.keys.toList(growable: false);
      for (final originalKey in keys) {
        final value = box.get(originalKey);
        if (value == null) continue;

        var id = idOf(value).trim();
        if (id.isEmpty) {
          id = uuid.v4();
          setId(value, id);
        }

        if (originalKey is String && originalKey == id) continue;
        if (box.containsKey(id)) {
          // extremely rare: collision → mint a new id
          final newId = uuid.v4();
          setId(value, newId);
          id = newId;
        }
        await box.put(id, value);
        await box.delete(originalKey);
      }
    }

    // Re-key core boxes to key == model.id
    await rekeyBox<RecipeModel>(
      Hive.box<RecipeModel>(Boxes.recipes),
      idOf: (m) => m.id,
      setId: (m, v) => m.id = v,
    );
    await rekeyBox<BatchModel>(
      Hive.box<BatchModel>(Boxes.batches),
      idOf: (m) => m.id,
      setId: (m, v) => m.id = v,
    );
    await rekeyBox<InventoryItem>(
      Hive.box<InventoryItem>(Boxes.inventory),
      idOf: (m) => m.id,
      setId: (m, v) => m.id = v,
    );
    await rekeyBox<ShoppingListItem>(
      Hive.box<ShoppingListItem>(Boxes.shoppingList),
      idOf: (m) => m.id,
      setId: (m, v) => m.id = v,
    );

    // Tags: use name as the key
    final tagBox = Hive.box<Tag>(Boxes.tags);
    final tagKeys = tagBox.keys.toList(growable: false);
    for (final originalKey in tagKeys) {
      final tag = tagBox.get(originalKey);
      if (tag == null) continue;
      final k = tag.name.trim();
      if (k.isEmpty) continue;
      if (originalKey is String && originalKey == k) continue;
      if (tagBox.containsKey(k)) {
        // prefer existing canonical key; drop duplicate
        await tagBox.delete(originalKey);
        continue;
      }
      await tagBox.put(k, tag);
      await tagBox.delete(originalKey);
    }
  }

  /// Clears all data from each box without causing "already open" errors.
  /// - If a box is open: clears it in-place (does not close or re-open).
  /// - If a box is closed: opens, clears, then closes it again.
  static Future<void> clearAllData() async {
    for (final boxName in _boxNames) {
      try {
        if (Hive.isBoxOpen(boxName)) {
          // Use the already-open instance; do NOT open it again.
          final box = getTypedBox(boxName);
          await box.clear();
        } else {
          // Open the typed box, clear, then close since it wasn't open originally.
          final box = await _openTypedBox(boxName);
          await box.clear();
          await box.close();
        }
      } catch (e) {
        debugPrint("Error clearing data for '$boxName': $e");
      }
    }
  }

  /// Exports all Hive data to a JSON file (download on web, save/share on device).
  static Future<void> exportData(BuildContext context) async {
    try {
      final Map<String, dynamic> allData = {};

      for (final boxName in _boxNames) {
        final box = Hive.isBoxOpen(boxName)
            ? getTypedBox(boxName)
            : await _openTypedBox(boxName);

        try {
          if (boxName == Boxes.settings) {
            final settingsMap = box.toMap();
            final typedSettingsMap = Map<String, dynamic>.from(settingsMap);
            allData[boxName] = [typedSettingsMap];
          } else {
            final List<Map<String, dynamic>> boxData = [];
            for (var i = 0; i < box.length; i++) {
              final item = box.getAt(i);
              if (item == null) continue;
              final Map<String, dynamic> jsonItem = (item as dynamic).toJson();
              boxData.add(jsonItem);
            }
            allData[boxName] = boxData;
          }
        } finally {
          // If we opened it for export, close it again.
          if (!Hive.isBoxOpen(boxName)) {
            await box.close();
          }
        }
      }

      final jsonString = const JsonEncoder.withIndent('  ').convert(allData);
      final bytes = utf8.encode(jsonString);

      final timestamp =
          DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
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
  /// NOTE: uses stable keys (id or tag.name) instead of auto-increment add().
  static Future<void> importData(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
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

        // Use an existing open box or open/close around the import.
        final wasOpen = Hive.isBoxOpen(boxName);
        final box = wasOpen ? getTypedBox(boxName) : await _openTypedBox(boxName);

        await box.clear();
        final boxData = allData[boxName] as List;

        for (var itemJson in boxData) {
          if (boxName == Boxes.settings) {
            await box.putAll(Map<String, dynamic>.from(itemJson));
            continue;
          }

          if (_fromJsonConstructors.containsKey(boxName)) {
            final item = _fromJsonConstructors[boxName]!(itemJson);

            // Write by stable key (id for most; name for tags)
            try {
              if (boxName == Boxes.tags) {
                final name = (item as Tag).name.trim();
                if (name.isNotEmpty) {
                  await box.put(name, item);
                } else {
                  await box.add(item);
                }
              } else {
                final id = (item as dynamic).id as String?;
                if (id != null && id.trim().isNotEmpty) {
                  await box.put(id.trim(), item);
                } else {
                  await box.add(item);
                }
              }
            } catch (_) {
              await box.add(item);
            }
          }
        }

        if (!wasOpen) {
          await box.close();
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data imported successfully! Please restart the app.'),
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
