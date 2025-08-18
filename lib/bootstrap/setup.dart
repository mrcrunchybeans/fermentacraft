// lib/bootstrap/setup.dart
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../utils/data_management.dart';

import '../firebase_options.dart';
import '../utils/boxes.dart';
import 'package:fermentacraft/utils/tag_icons.dart';

// Adapters / models
import 'package:fermentacraft/models/unit_type.dart' as ut;
import 'package:fermentacraft/models/purchase_transaction.dart';
import 'package:fermentacraft/models/inventory_item.dart';
import 'package:fermentacraft/models/inventory_action.dart';
import 'package:fermentacraft/models/inventory_transaction_model.dart';
import 'package:fermentacraft/models/inventory_purchase.dart';
import 'package:fermentacraft/models/batch_extras.dart';
import 'package:fermentacraft/models/measurement.dart';
import 'package:fermentacraft/models/fermentation_stage.dart';
import 'package:fermentacraft/models/tag.dart';
import 'package:fermentacraft/models/batch_model.dart';
import 'package:fermentacraft/models/recipe_model.dart';
import 'package:fermentacraft/models/shopping_list_item.dart';

/// Call this once before runApp().
Future<void> setupAppServices() async {
  // --- Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  try {
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
  } catch (_) {
    // Already applied / not supported.
  }

  // --- Hive
  await Hive.initFlutter();
  _registerHiveAdapters();
  await _openHiveBoxes();


  // 🚨 IMPORTANT: re-key first so downstream migrations see canonical keys
  await DataManagementService.migrateHiveKeysToStableIds();

  // --- Migrations / sanitizers (idempotent via settings flags)
  final settings = Hive.box(Boxes.settings);

  // v2: fix Tag.iconKey + sanitize embedded tags in recipes
  if (settings.get('migrated.tags.v2') != true) {
    await _sanitizeTagBox();
    await _sanitizeRecipeEmbeddedTags();
    await settings.put('migrated.tags.v2', true);
  }

  // v4a: normalize Tag keys to string names and repoint recipes to canonical refs
  if (settings.get('migrated.tags.v4_fix_keys') != true) {
    await _normalizeTagKeysAndRepointRecipes();
    await settings.put('migrated.tags.v4_fix_keys', true);
  }

  // v4: migrate RecipeModel embedded tags -> HiveList<Tag> (noop if already repointed)
  if (settings.get('migrated.tags.v4_refs') != true) {
    await _migrateRecipeEmbeddedToRefs();
    await settings.put('migrated.tags.v4_refs', true);
  }

  // v3: sanitize embedded tags in batches (safe after v2/v4)
  if (settings.get('migrated.tags.v3') != true) {
    await _sanitizeBatchEmbeddedTags();
    await _lightRecheckRecipes();
    await settings.put('migrated.tags.v3', true);
  }
}

/* ----------------------------------------------------------------------------
 * Registration / Boxes
 * ---------------------------------------------------------------------------*/

void _registerHiveAdapters() {
  void reg<T>(TypeAdapter<T> a) {
    if (!Hive.isAdapterRegistered(a.typeId)) {
      Hive.registerAdapter<T>(a);
    }
  }

  // Adapters with no Tag dependency
  reg<ut.UnitType>(ut.UnitTypeAdapter());
  reg<PurchaseTransaction>(PurchaseTransactionAdapter());
  reg<InventoryItem>(InventoryItemAdapter());
  reg<InventoryAction>(InventoryActionAdapter());
  reg<InventoryTransaction>(InventoryTransactionAdapter());
  reg<InventoryPurchase>(InventoryPurchaseAdapter());
  reg<BatchExtras>(BatchExtrasAdapter());
  reg<Measurement>(MeasurementAdapter());
  reg<FermentationStage>(FermentationStageAdapter());
  reg<ShoppingListItem>(ShoppingListItemAdapter());

  // 👉 Tag FIRST (others embed Tag)
  reg<Tag>(TagAdapter());

  // Models that embed Tag (must come AFTER TagAdapter)
  reg<BatchModel>(BatchModelAdapter());
  reg<RecipeModel>(RecipeModelAdapter());
}

Future<void> _openHiveBoxes() async {
  // Open Tags BEFORE Recipes/Batches (since they embed/refer to Tag)
  await Hive.openBox<Tag>(Boxes.tags);

  await Future.wait([
    Hive.openBox<BatchModel>(Boxes.batches),
    Hive.openBox<InventoryItem>(Boxes.inventory),
    Hive.openBox<InventoryAction>(Boxes.inventoryActions),
    Hive.openBox<RecipeModel>(Boxes.recipes),
    Hive.openBox(Boxes.settings),
    Hive.openBox<ShoppingListItem>(Boxes.shoppingList),
    Hive.openBox(Boxes.syncMeta),
  ]);
}

/* ----------------------------------------------------------------------------
 * v2: Sanitize icon keys + embedded recipe tags
 * ---------------------------------------------------------------------------*/

Future<void> _sanitizeTagBox() async {
  final tagBox = Hive.box<Tag>(Boxes.tags);
  for (final t in tagBox.values) {
    if (!kTagIconMap.containsKey(t.iconKey)) {
      t.iconKey = keyFromLegacy(t.iconCodePoint, t.iconFontFamily);
      await t.save();
    }
  }
}

Future<void> _sanitizeRecipeEmbeddedTags() async {
  final recipeBox = Hive.box<RecipeModel>(Boxes.recipes);
  for (final key in recipeBox.keys.toList()) {
    try {
      final r = recipeBox.get(key);
      if (r == null) continue;

      bool dirty = false;

      // Sanitize whichever embedded list exists
      final embedded = _getEmbeddedTags(r);
      for (final t in embedded) {
        if (!kTagIconMap.containsKey(t.iconKey)) {
          t.iconKey = keyFromLegacy(t.iconCodePoint, t.iconFontFamily);
          dirty = true;
        }
      }

      

      // Normalize any custom fields if your model supports it
      try {
        // ignore: invalid_use_of_visible_for_testing_member
        r.normalizeInPlace();
        dirty = true;
      } catch (_) {}

      if (dirty) await r.save();
    } catch (_) {
      // If unrecoverable, try strip tags; else delete row
      try {
        final r = recipeBox.get(key);
        if (r != null) {
          _setEmbeddedTags(r, const <Tag>[]);
          await r.save();
          continue;
        }
      } catch (_) {}
      await recipeBox.delete(key);
    }
  }
}

/* ----------------------------------------------------------------------------
 * v4a: Normalize Tags box keys to string names + repoint recipes
 * ---------------------------------------------------------------------------*/

Future<void> _normalizeTagKeysAndRepointRecipes() async {
  final tagBox = Hive.box<Tag>(Boxes.tags);
  final recipeBox = Hive.box<RecipeModel>(Boxes.recipes);

  // 1) Build canonical map and move any numeric/mismatched keys to string key = name
  final Map<String, Tag> canonByName = {};
  final List<dynamic> toDelete = [];

  for (final dynamic oldKey in tagBox.keys.toList()) {
    final Tag? t = tagBox.get(oldKey);
    if (t == null) continue;

    final nameKey = t.name.trim();                // preferred key
    final lower = nameKey.toLowerCase();
    final normalizedIcon = kTagIconMap.containsKey(t.iconKey)
        ? t.iconKey
        : keyFromLegacy(t.iconCodePoint, t.iconFontFamily);

    Tag? canon = tagBox.get(nameKey);
    if (canon == null) {
      if (oldKey == nameKey) {
        // Already at correct key
        if (t.iconKey != normalizedIcon) {
          t.iconKey = normalizedIcon;
          await t.save();
        }
        canon = t;
      } else {
        // 👇 Clone to a FRESH instance at the proper key (never reuse same instance under 2 keys)
        final fresh = Tag(name: t.name, iconKey: normalizedIcon);
        await tagBox.put(nameKey, fresh);
        canon = fresh;
        toDelete.add(oldKey);
      }
    } else {
      // Ensure canonical icon sane
      if (!kTagIconMap.containsKey(canon.iconKey) && kTagIconMap.containsKey(normalizedIcon)) {
        canon.iconKey = normalizedIcon;
        await canon.save();
      }
      if (oldKey != nameKey) toDelete.add(oldKey);
    }

    canonByName[lower] = canon;
  }

  // 2) Repoint every recipe to canonical Tag instances (HiveList<Tag> if available)
  for (final r in recipeBox.values) {
    try {
      final embedded = _getEmbeddedTags(r);
      if (embedded.isEmpty) {
        _setRefs(r, const <Tag>[]);
        await r.save();
        continue;
      }

      final seen = <String>{};
      final canonList = <Tag>[];
      for (final t in embedded) {
        final k = t.name.trim().toLowerCase();
        if (seen.add(k)) {
          final Tag? canon = canonByName[k] ?? tagBox.get(t.name.trim());
          if (canon != null) canonList.add(canon);
        }
      }

      _setRefs(r, canonList);       // safe no-op if model lacks tagRefs
      _setEmbeddedTags(r, canonList); // also try to write embedded list if supported
      await r.save();
    } catch (_) {
      // ignore broken rows
    }
  }

  // 3) Remove old numeric / duplicate entries AFTER repointing
  for (final k in toDelete) {
    if (tagBox.containsKey(k)) {
      await tagBox.delete(k);
    }
  }
}

/* ----------------------------------------------------------------------------
 * v4: Migrate embedded recipe tags to HiveList<Tag>
 * (Mostly a no-op after v4a, but kept for safety across model versions)
 * ---------------------------------------------------------------------------*/

Future<void> _migrateRecipeEmbeddedToRefs() async {
  final tagBox = Hive.box<Tag>(Boxes.tags);
  final recipeBox = Hive.box<RecipeModel>(Boxes.recipes);

  for (final r in recipeBox.values) {
    try {
      final refs = _getRefs(r);
      final embedded = _getEmbeddedTags(r);

      // Already migrated?
      if (refs != null && (refs.isNotEmpty || embedded.isEmpty)) continue;

      if (embedded.isEmpty) {
        _setRefs(r, const <Tag>[]);
        await r.save();
        continue;
      }

      // Canonicalize by name (dedupe) and ensure each Tag exists under proper string key
      final byName = <String, Tag>{};
      for (final t in embedded) {
        final nameKey = t.name.trim();
        var canon = tagBox.get(nameKey);
        if (canon == null) {
          final icon = kTagIconMap.containsKey(t.iconKey)
              ? t.iconKey
              : keyFromLegacy(t.iconCodePoint, t.iconFontFamily);
          canon = Tag(name: t.name, iconKey: icon);
          // IMPORTANT: write a FRESH object; never reuse an instance at a second key
          await tagBox.put(nameKey, canon);
        }
        byName[nameKey.toLowerCase()] = canon;
      }

      final canonList = byName.values.toList();
      _setRefs(r, canonList);
      _setEmbeddedTags(r, canonList); // harmless no-op if fields are final/missing
      await r.save();
    } catch (_) {
      // ignore and let previous sanitizers handle
    }
  }
}

/* ----------------------------------------------------------------------------
 * v3: Sanitize batches + light recheck of recipes
 * ---------------------------------------------------------------------------*/

Future<void> _sanitizeBatchEmbeddedTags() async {
  final batchBox = Hive.box<BatchModel>(Boxes.batches);
  for (final key in batchBox.keys.toList()) {
    try {
      final b = batchBox.get(key);
      if (b == null) continue;

      final tags = _getBatchEmbeddedTags(b);
      if (tags.isEmpty) continue;

      bool dirty = false;
      for (final t in tags) {
        if (!kTagIconMap.containsKey(t.iconKey)) {
          t.iconKey = keyFromLegacy(t.iconCodePoint, t.iconFontFamily);
          dirty = true;
        }
      }
      if (dirty) {
        _setBatchEmbeddedTags(b, tags); // write back to whichever field exists
        await b.save();
      }
    } catch (_) {
      // skip deleting batches by default
    }
  }
}

Future<void> _lightRecheckRecipes() async {
  final recipeBox = Hive.box<RecipeModel>(Boxes.recipes);
  for (final key in recipeBox.keys.toList()) {
    try {
      final r = recipeBox.get(key);
      if (r == null) continue;

      bool dirty = false;
      for (final t in _getEmbeddedTags(r)) {
        if (!kTagIconMap.containsKey(t.iconKey)) {
          t.iconKey = keyFromLegacy(t.iconCodePoint, t.iconFontFamily);
          dirty = true;
        }
      }
      if (dirty) await r.save();
    } catch (_) {
      // ignore
    }
  }
}


/* ----------------------------------------------------------------------------
 * Small cross-version helpers (never assume fields exist / are mutable)
 * ---------------------------------------------------------------------------*/

List<Tag> _getEmbeddedTags(RecipeModel r) {
  // Prefer explicit legacy list if present; else current embedded list; else empty.
  try {
    final legacy = (r as dynamic).tagsLegacy as List<Tag>?;
    if (legacy != null) return legacy;
  } catch (_) {}
  try {
    final current = (r as dynamic).tags as List<Tag>?;
    if (current != null) return current;
  } catch (_) {}
  return const <Tag>[];
}

void _setEmbeddedTags(RecipeModel r, List<Tag> tags) {
  // Try to write both; ignore if field is final or absent.
  try { (r as dynamic).tagsLegacy = tags; } catch (_) {}
  try { (r as dynamic).tags = tags; } catch (_) {}
}

HiveList<Tag>? _getRefs(RecipeModel r) {
  try { return (r as dynamic).tagRefs as HiveList<Tag>?; } catch (_) { return null; }
}

void _setRefs(RecipeModel r, List<Tag> canon) {
  try {
    final tagBox = Hive.box<Tag>(Boxes.tags);
    (r as dynamic).tagRefs = HiveList<Tag>(tagBox, objects: canon);
  } catch (_) {
    // ignore on models without tagRefs
  }
}

// ---- Batch tag helpers (cross-version safe) ----
List<Tag> _getBatchEmbeddedTags(BatchModel b) {
  // Prefer legacy field if present; else current field; else empty.
  try {
    final legacy = (b as dynamic).tagsLegacy as List<Tag>?;
    if (legacy != null) return legacy;
  } catch (_) {}
  try {
    final current = (b as dynamic).tags as List<Tag>?;
    if (current != null) return current;
  } catch (_) {}
  return const <Tag>[];
}

void _setBatchEmbeddedTags(BatchModel b, List<Tag> tags) {
  // Try to write both; ignore if field is absent or final on this version.
  try { (b as dynamic).tagsLegacy = tags; } catch (_) {}
  try { (b as dynamic).tags = tags; } catch (_) {}
}
