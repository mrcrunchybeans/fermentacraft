// lib/utils/data_management.dart
import 'dart:convert';
import 'package:fermentacraft/utils/sanitize.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:fermentacraft/utils/snacks.dart';
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

  /// Helper to OPEN a typed box when it's currently closed.
  static Future<Box> openTypedBox(String name) {
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
    // Re-key content boxes using a clone -> put(newKey) -> delete(oldKey) pattern.
    await _rekeyBox<RecipeModel>(
      boxName: Boxes.recipes,
      box: Hive.box<RecipeModel>(Boxes.recipes),
      idFrom: (m) => m.id,
    );
    await _rekeyBox<BatchModel>(
      boxName: Boxes.batches,
      box: Hive.box<BatchModel>(Boxes.batches),
      idFrom: (m) => m.id,
    );
    await _rekeyBox<InventoryItem>(
      boxName: Boxes.inventory,
      box: Hive.box<InventoryItem>(Boxes.inventory),
      idFrom: (m) => m.id,
    );
    await _rekeyBox<ShoppingListItem>(
      boxName: Boxes.shoppingList,
      box: Hive.box<ShoppingListItem>(Boxes.shoppingList),
      idFrom: (m) => m.id,
    );

    // Tags use name-as-key; also clone to avoid same-instance/two-keys error.
    await _rekeyTags(Hive.box<Tag>(Boxes.tags));
  }

  /// Clears all data from each box without causing "already open" errors.
  static Future<void> clearAllData() async {
    for (final boxName in _boxNames) {
      try {
        if (Hive.isBoxOpen(boxName)) {
          final box = getTypedBox(boxName);
          await box.clear();
        } else {
          final box = await openTypedBox(boxName);
          await box.clear();
          await box.close();
        }
      } catch (e) {
        debugPrint("Error clearing data for '$boxName': $e");
      }
    }
  }

 /// Exports all Hive data to a JSON file.
static Future<void> exportData(BuildContext context) async {
  try {
    final Map<String, dynamic> allData = {};

    for (final boxName in _boxNames) {
      // Open (or get) the correct typed box
      final wasOpen = Hive.isBoxOpen(boxName);
      final box = wasOpen ? getTypedBox(boxName) : await openTypedBox(boxName);

      try {
        if (boxName == Boxes.settings) {
          // Settings: single map -> wrap in a list for consistency
          // box.toMap() has dynamic keys; coerce to <String, dynamic>
          final raw = Map.from(box.toMap());
          final strKeyed = <String, dynamic>{
            for (final entry in raw.entries) entry.key.toString(): entry.value
          };
          allData[boxName] = [strKeyed];
        } else {
          // Other boxes: model -> toJson() -> deep sanitize so DateTime/Duration are safe
          final items = box.values.map((item) {
            final Map<String, dynamic> m =
                (item as dynamic).toJson() as Map<String, dynamic>;
            return sanitizeForJson(m);
          }).toList();
          allData[boxName] = items;
        }
      } finally {
        if (!wasOpen) {
          await box.close();
        }
      }
    }

    // Pretty JSON and save
    final jsonString = const JsonEncoder.withIndent('  ').convert(allData);
    final bytes = utf8.encode(jsonString);
    final timestamp =
        DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final fileName = 'fermentacraft_backup_$timestamp.json';

    final savedPath = await saveBytesToDevice(fileName, bytes);

    if (!kIsWeb && savedPath != null && context.mounted) {
      // ignore: deprecated_member_use
      await Share.shareXFiles([XFile(savedPath)],
          text: 'FermentaCraft Backup');
    }

    if (context.mounted) {
      snacks.show(const SnackBar(content: Text('Data backup successful!')));
    }
  } catch (e) {
    if (context.mounted) {
      snacks.show(SnackBar(content: Text('Export failed: $e')));
    }
  }
}

  /// Imports data from a user-selected JSON file.
  static Future<void> importData(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || !context.mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Confirm Import"),
          content: const Text(
              "This will overwrite all existing data. This action cannot be undone."),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Cancel")),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Import")),
          ],
        ),
      );

      if (confirmed != true) return;

      final bytes = result.files.single.bytes;
      if (bytes == null) throw Exception("No file data found.");

      final allData = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

      for (final boxName in _boxNames) {
        if (!allData.containsKey(boxName)) continue;

        final wasOpen = Hive.isBoxOpen(boxName);
        final box =
            wasOpen ? getTypedBox(boxName) : await openTypedBox(boxName);
        await box.clear();

        final items = allData[boxName] as List;
        for (var itemJson in items) {
          if (boxName == Boxes.settings) {
            await box.putAll(Map<String, dynamic>.from(itemJson));
            continue;
          }

          final item = _fromJsonConstructors[boxName]!(itemJson);
          final String key =
              (boxName == Boxes.tags) ? (item as Tag).name : (item as dynamic).id;
          if (key.trim().isNotEmpty) {
            await box.put(key.trim(), item);
          }
        }

        if (!wasOpen) await box.close();
      }

      if (context.mounted) {
        snacks.show(const SnackBar(
            content: Text('Data imported! Please restart the app.')));
      }
    } catch (e) {
      if (context.mounted) {
        snacks.show(SnackBar(content: Text('Import error: $e')));
      }
    }
  }
}

// --- ✅ PRIVATE HELPER FUNCTIONS FOR MIGRATION (MOVED OUTSIDE CLASS) ---

/// Helper to re-key tags from numeric IDs to string names.
Future<void> _rekeyTags(Box<Tag> box) async {
  final keys = box.keys.toList(growable: false);
  for (final originalKey in keys) {
    final tag = box.get(originalKey);
    if (tag == null) continue;

    final name = tag.name.trim();
    if (name.isEmpty) continue;

    if (originalKey is String && originalKey == name) continue;

    if (box.containsKey(name)) {
      await box.delete(originalKey);
      continue;
    }

    // Clone to avoid "same instance / two keys" error
    final cloned = Tag(
      name: tag.name,
      iconKey: tag.iconKey,
      iconCodePoint: tag.iconCodePoint,
      iconFontFamily: tag.iconFontFamily,
    );

    await box.put(name, cloned);
    await box.delete(originalKey);
  }
}

/// Generic rekey that clones objects, writes under the new ID, then deletes the old key.
Future<void> _rekeyBox<T>({
  required String boxName,
  required Box<T> box,
  required String Function(T) idFrom,
}) async {
  const uuid = Uuid();
  final keys = box.keys.toList(growable: false);
  final fromJson = DataManagementService.fromJsonFor(boxName);

  for (final originalKey in keys) {
    final value = box.get(originalKey);
    if (value == null) continue;

    var id = idFrom(value).trim();
    if (id.isEmpty) id = uuid.v4();
    if (originalKey is String && originalKey == id) continue;
    if (box.containsKey(id) && originalKey != id) id = uuid.v4();

    // Clone via JSON serialization
    final json = (value as dynamic).toJson() as Map<String, dynamic>;
    json['id'] = id; // Ensure the clone has the new ID

    final T cloned = fromJson(json) as T;

    await box.put(id, cloned);
    await box.delete(originalKey);
  }
}