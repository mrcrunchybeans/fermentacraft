// lib/services/hive_key_migration.dart
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../utils/boxes.dart';
import '../utils/data_management.dart'; // <- to clone via fromJsonFor

import '../models/recipe_model.dart';
import '../models/batch_model.dart';
import '../models/inventory_item.dart';
import '../models/shopping_list_item.dart';
import '../models/tag.dart';

/// Re-keys content boxes using a clone -> put(newKey) -> delete(oldKey) pattern.
/// Never reuses the same HiveObject instance under two keys.
Future<void> migrateHiveKeysToStableIds() async {
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

/// Helper to re-key tags from numeric IDs to string names.
Future<void> _rekeyTags(Box<Tag> box) async {
  final keys = box.keys.toList(growable: false);
  for (final originalKey in keys) {
    final tag = box.get(originalKey);
    if (tag == null) continue;

    final name = tag.name.trim();
    if (name.isEmpty) continue;

    // Already correct?
    if (originalKey is String && originalKey == name) continue;

    // If a canonical entry already exists, just drop the old one.
    if (box.containsKey(name)) {
      await box.delete(originalKey);
      continue;
    }

    // ✅ CLONE to avoid "same instance / two keys" error
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

/// Generic rekey that CLONES the object (via your DataManagementService),
/// writes it under the new id, then deletes the old key. Never reuses the same
/// HiveObject instance under two keys.
Future<void> _rekeyBox<T>({
  required String boxName,
  required Box<T> box,
  required String Function(T) idFrom,
}) async {
  final uuid = const Uuid();
  final keys = box.keys.toList(growable: false);

  final fromJson = DataManagementService.fromJsonFor(boxName);

  for (final originalKey in keys) {
    final value = box.get(originalKey);
    if (value == null) continue;

    // Read current id from the model
    var id = idFrom(value).trim();

    // Ensure a non-empty id
    if (id.isEmpty) {
      id = uuid.v4();
    }

    // If already under the correct key, skip
    if (originalKey is String && originalKey == id) continue;

    // Avoid collisions (rare, but safe)
    if (box.containsKey(id) && originalKey != id) {
      id = uuid.v4();
    }

    // ✅ Clone using JSON -> fromJson factory, set id inside JSON before cloning
    final json = (value as dynamic).toJson() as Map<String, dynamic>;
    json['id'] = id; // ensure the cloned object has the new id

    final T cloned = fromJson(json) as T;

    // Put the clone under the new key, then delete the old key
    await box.put(id, cloned);
    await box.delete(originalKey);
  }
}