// lib/services/hive_key_migration.dart
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../utils/boxes.dart';
import '../models/recipe_model.dart';
import '../models/batch_model.dart';
import '../models/inventory_item.dart';
import '../models/shopping_list_item.dart';
import '../models/tag.dart';

Future<void> migrateHiveKeysToStableIds() async {
  await _rekeyBox<RecipeModel>(Hive.box<RecipeModel>(Boxes.recipes),
      idOf: (m) => m.id, setId: (m, v) => m.id = v);
  await _rekeyBox<BatchModel>(Hive.box<BatchModel>(Boxes.batches),
      idOf: (m) => m.id, setId: (m, v) => m.id = v);
  await _rekeyBox<InventoryItem>(Hive.box<InventoryItem>(Boxes.inventory),
      idOf: (m) => m.id, setId: (m, v) => m.id = v);
  await _rekeyBox<ShoppingListItem>(Hive.box<ShoppingListItem>(Boxes.shoppingList),
      idOf: (m) => m.id, setId: (m, v) => m.id = v);
  await _rekeyTags(Hive.box<Tag>(Boxes.tags));
}

Future<void> _rekeyTags(Box<Tag> box) async {
  final keys = box.keys.toList(growable: false);
  for (final originalKey in keys) {
    final tag = box.get(originalKey);
    if (tag == null) continue;
    final name = tag.name.trim();
    if (name.isEmpty) continue;
    if (originalKey is String && originalKey == name) continue;
    if (box.containsKey(name)) { await box.delete(originalKey); continue; }
    await box.put(name, tag);
    await box.delete(originalKey);
  }
}

Future<void> _rekeyBox<T>(
  Box<T> box, {
  required String Function(T) idOf,
  required void Function(T, String) setId,
}) async {
  final uuid = const Uuid();
  final keys = box.keys.toList(growable: false);
  for (final originalKey in keys) {
    final value = box.get(originalKey);
    if (value == null) continue;

    var id = idOf(value).trim();
    if (id.isEmpty) { id = uuid.v4(); setId(value, id); }

    if (originalKey is String && originalKey == id) continue;
    if (box.containsKey(id)) {
      final newId = uuid.v4();
      setId(value, newId);
      id = newId;
    }
    await box.put(id, value);
    await box.delete(originalKey);
  }
}
