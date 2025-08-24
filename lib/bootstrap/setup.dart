// lib/bootstrap/setup.dart
// Initializes Firebase + Hive, registers adapters, opens boxes,
// scrubs unreadable legacy rows (web-safe), then runs idempotent migrations.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
// For HiveList
import 'package:hive_flutter/hive_flutter.dart';

import '../firebase_options.dart';
import '../utils/boxes.dart';
import '../utils/data_management.dart';
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
  // ---------------------------
  // Firebase
  // ---------------------------
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  try {
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
  } catch (_) {
    // Already set or not supported (e.g., web).
  }

  // ---------------------------
  // Hive
  // ---------------------------
  await Hive.initFlutter();
  _registerHiveAdapters();
  await _openHiveBoxes();

  // ---------------------------
  // Pre-scrub (web-safe, keeps native behavior)
  // Remove ONLY rows that cannot decode with current adapters.
  // Run BEFORE any typed reads or migrations.
  // ---------------------------
  await _scrubUnreadableTagRows();
  await _scrubUnreadableRecipeRows();
  await _scrubUnreadableBatchRows();
  await _scrubUnreadableInventoryRows();

  // ---------------------------
  // Stable ID re-key (after scrubs, before other migrations)
  // ---------------------------
  await DataManagementService.migrateHiveKeysToStableIds();

  // ---------------------------
  // Migrations / sanitizers (idempotent via settings flags)
  // ---------------------------
  final settings = Hive.box(Boxes.settings);

  // v2: fix Tag.iconKey + sanitize embedded recipe tags
  if (settings.get('migrated.tags.v2') != true) {
    await _sanitizeTagBox();
    await _sanitizeRecipeEmbeddedTags();
    await settings.put('migrated.tags.v2', true);
  }

  // v4a: normalize Tag keys to string names + repoint recipes to canonical refs
  if (settings.get('migrated.tags.v4_fix_keys') != true) {
    await _normalizeTagKeysAndRepointRecipes();
    await settings.put('migrated.tags.v4_fix_keys', true);
  }

  // v4: migrate embedded recipe tags -> HiveList<Tag> (noop if already repointed)
  if (settings.get('migrated.tags.v4_refs') != true) {
    await _migrateRecipeEmbeddedToRefs();
    await settings.put('migrated.tags.v4_refs', true);
  }

  // v3: sanitize embedded tags in batches + light recipe recheck
  if (settings.get('migrated.tags.v3') != true) {
    await _sanitizeBatchEmbeddedTags();
    await _lightRecheckRecipes();
    await settings.put('migrated.tags.v3', true);
  }
}

/* ============================================================================
 * Registration / Boxes
 * ==========================================================================*/

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

  // Tag FIRST (others embed Tag)
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

/* ============================================================================
 * Pre-scrub (web-safe): remove unreadable rows BEFORE any typed reads
 * ==========================================================================*/

/// Deletes only entries in `tags` that cannot decode with the current Tag adapter.
/// Opens the box untyped to avoid crashing during iteration.
Future<void> _scrubUnreadableTagRows() async {
  final box = Hive.box(Boxes.tags); // untyped
  final badKeys = <dynamic>[];

  for (final key in box.keys.toList()) {
    try {
      final v = box.get(key); // forces decode
      if (v is! Tag) badKeys.add(key);
    } catch (_) {
      badKeys.add(key);
    }
  }

  if (badKeys.isNotEmpty) {
    for (final k in badKeys) {
      try { await box.delete(k); } catch (_) {}
    }
    _log('[startup] Pruned ${badKeys.length} unreadable rows from "${Boxes.tags}".');
  }
}

/// Deletes only recipe rows that fail to decode; also strips any non-Tag entries
/// from embedded tag lists so downstream migrations never choke.
Future<void> _scrubUnreadableRecipeRows() async {
  final box = Hive.box(Boxes.recipes); // untyped
  final badKeys = <dynamic>[];
  int fixedEmbedded = 0;

  for (final key in box.keys.toList()) {
    try {
      final v = box.get(key); // force decode
      if (v is! RecipeModel) {
        badKeys.add(key);
        continue;
      }

      // Use dynamic list so type checks are meaningful
      final embeddedDyn = _getEmbeddedTagsDynamic(v);
      if (embeddedDyn.isNotEmpty && embeddedDyn.any((e) => e is! Tag)) {
        final cleaned = <Tag>[
          for (final e in embeddedDyn)
            if (e is Tag) e,
        ];
        _setEmbeddedTags(v, cleaned);
        try { await v.save(); } catch (_) {}
        fixedEmbedded++;
      }
    } catch (_) {
      badKeys.add(key);
    }
  }

  if (badKeys.isNotEmpty) {
    for (final k in badKeys) {
      try { await box.delete(k); } catch (_) {}
    }
    _log('[startup] Pruned ${badKeys.length} unreadable rows from "${Boxes.recipes}".');
  }
  if (fixedEmbedded > 0) {
    _log('[startup] Stripped invalid embedded tag entries in $fixedEmbedded recipe(s).');
  }
}

/// Deletes undecodable batches and strips invalid embedded tags.
Future<void> _scrubUnreadableBatchRows() async {
  final box = Hive.box(Boxes.batches); // untyped
  final badKeys = <dynamic>[];
  int fixed = 0;

  for (final key in box.keys.toList()) {
    try {
      final v = box.get(key);
      if (v is! BatchModel) { badKeys.add(key); continue; }

      final tagsDyn = _getBatchEmbeddedTagsDynamic(v);
      if (tagsDyn.isNotEmpty && tagsDyn.any((e) => e is! Tag)) {
        final cleaned = <Tag>[
          for (final e in tagsDyn)
            if (e is Tag) e,
        ];
        _setBatchEmbeddedTags(v, cleaned);
        try { await v.save(); } catch (_) {}
        fixed++;
      }
    } catch (_) {
      badKeys.add(key);
    }
  }

  if (badKeys.isNotEmpty) {
    for (final k in badKeys) { try { await box.delete(k); } catch (_) {} }
    _log('[startup] Pruned ${badKeys.length} unreadable rows from "${Boxes.batches}".');
  }
  if (fixed > 0) {
    _log('[startup] Stripped invalid embedded tag entries in $fixed batch(es).');
  }
}

/// Deletes undecodable rows from inventory and inventory_actions.
Future<void> _scrubUnreadableInventoryRows() async {
  // Inventory items
  {
    final box = Hive.box(Boxes.inventory);
    final badKeys = <dynamic>[];
    for (final k in box.keys.toList()) {
      try {
        if (box.get(k) is! InventoryItem) badKeys.add(k);
      } catch (_) {
        badKeys.add(k);
      }
    }
    if (badKeys.isNotEmpty) {
      for (final k in badKeys) { try { await box.delete(k); } catch (_) {} }
      _log('[startup] Pruned ${badKeys.length} unreadable rows from "${Boxes.inventory}".');
    }
  }
  // Inventory actions
  {
    final box = Hive.box(Boxes.inventoryActions);
    final badKeys = <dynamic>[];
    for (final k in box.keys.toList()) {
      try {
        if (box.get(k) is! InventoryAction) badKeys.add(k);
      } catch (_) {
        badKeys.add(k);
      }
    }
    if (badKeys.isNotEmpty) {
      for (final k in badKeys) { try { await box.delete(k); } catch (_) {} }
      _log('[startup] Pruned ${badKeys.length} unreadable rows from "${Boxes.inventoryActions}".');
    }
  }
}

/* ============================================================================
 * v2: Sanitize Tag.iconKey + embedded recipe tags
 * ==========================================================================*/

Future<void> _sanitizeTagBox() async {
  final tagBox = Hive.box<Tag>(Boxes.tags);
  for (final key in tagBox.keys.toList()) {
    try {
      final t = tagBox.get(key);
      if (t == null) continue;
      if (!kTagIconMap.containsKey(t.iconKey)) {
        t.iconKey = keyFromLegacy(t.iconCodePoint, t.iconFontFamily);
        await t.save();
      }
    } catch (_) {
      try { await tagBox.delete(key); } catch (_) {}
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

      final embedded = _getEmbeddedTags(r);
      for (final t in embedded) {
        if (!kTagIconMap.containsKey(t.iconKey)) {
          t.iconKey = keyFromLegacy(t.iconCodePoint, t.iconFontFamily);
          dirty = true;
        }
      }

      // Optional normalization if available on your model
      try {
        // ignore: invalid_use_of_visible_for_testing_member
        r.normalizeInPlace();
        dirty = true;
      } catch (_) {}

      if (dirty) await r.save();
    } catch (_) {
      // Best-effort salvage: strip tags; else delete row
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

/* ============================================================================
 * v4a: Normalize Tag keys to string names + repoint recipes to canonical refs
 * ==========================================================================*/

Future<void> _normalizeTagKeysAndRepointRecipes() async {
  final tagBox = Hive.box<Tag>(Boxes.tags);
  final recipeBox = Hive.box<RecipeModel>(Boxes.recipes);

  // 1) Build canonical map (keyed by lowercased name) and move entries to name keys
  final Map<String, Tag> canonByLowerName = {};
  final List<dynamic> toDelete = [];

  for (final dynamic oldKey in tagBox.keys.toList()) {
    final Tag? t = tagBox.get(oldKey);
    if (t == null) continue;

    final nameKey = t.name.trim();
    final lower = nameKey.toLowerCase();

    final normalizedIcon = kTagIconMap.containsKey(t.iconKey)
        ? t.iconKey
        : keyFromLegacy(t.iconCodePoint, t.iconFontFamily);

    Tag? canon = tagBox.get(nameKey);
    if (canon == null) {
      if (oldKey == nameKey) {
        if (t.iconKey != normalizedIcon) {
          t.iconKey = normalizedIcon;
          await t.save();
        }
        canon = t;
      } else {
        // Write a fresh instance at the proper key (never reuse the same object under 2 keys)
        final fresh = Tag(name: t.name, iconKey: normalizedIcon);
        await tagBox.put(nameKey, fresh);
        canon = fresh;
        toDelete.add(oldKey);
      }
    } else {
      if (!kTagIconMap.containsKey(canon.iconKey) && kTagIconMap.containsKey(normalizedIcon)) {
        canon.iconKey = normalizedIcon;
        await canon.save();
      }
      if (oldKey != nameKey) toDelete.add(oldKey);
    }

    canonByLowerName[lower] = canon;
  }

  // 2) Repoint recipes to canonical Tag instances
  for (final key in recipeBox.keys.toList()) {
    try {
      final r = recipeBox.get(key);
      if (r == null) continue;

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
          final Tag? canon = canonByLowerName[k] ?? tagBox.get(t.name.trim());
          if (canon != null) canonList.add(canon);
        }
      }

      _setRefs(r, canonList);         // safe no-op if tagRefs not present
      _setEmbeddedTags(r, canonList); // try to write embedded list if supported
      await r.save();
    } catch (_) {
      // ignore broken rows
    }
  }

  // 3) Remove obsolete numeric/duplicate keys AFTER repointing
  for (final k in toDelete) {
    if (tagBox.containsKey(k)) {
      await tagBox.delete(k);
    }
  }
}

/* ============================================================================
 * v4: Migrate embedded recipe tags to HiveList<Tag>
 * ==========================================================================*/

Future<void> _migrateRecipeEmbeddedToRefs() async {
  final tagBox = Hive.box<Tag>(Boxes.tags);
  final recipeBox = Hive.box<RecipeModel>(Boxes.recipes);

  for (final key in recipeBox.keys.toList()) {
    try {
      final r = recipeBox.get(key);
      if (r == null) continue;

      final refs = _getRefs(r);
      final embedded = _getEmbeddedTags(r);

      // Already migrated?
      if (refs != null && (refs.isNotEmpty || embedded.isEmpty)) continue;

      if (embedded.isEmpty) {
        _setRefs(r, const <Tag>[]);
        await r.save();
        continue;
      }

      // Canonicalize by name (dedupe) and ensure each Tag exists under string key
      final byLower = <String, Tag>{};
      for (final t in embedded) {
        final nameKey = t.name.trim();
        var canon = tagBox.get(nameKey);
        if (canon == null) {
          final icon = kTagIconMap.containsKey(t.iconKey)
              ? t.iconKey
              : keyFromLegacy(t.iconCodePoint, t.iconFontFamily);
          canon = Tag(name: t.name, iconKey: icon);
          await tagBox.put(nameKey, canon); // fresh object at proper key
        }
        byLower[nameKey.toLowerCase()] = canon;
      }

      final canonList = byLower.values.toList();
      _setRefs(r, canonList);
      _setEmbeddedTags(r, canonList); // harmless if fields are final/missing
      await r.save();
    } catch (_) {
      // ignore; earlier sanitizers handle edge cases
    }
  }
}

/* ============================================================================
 * v3: Sanitize batches + light recheck of recipes
 * ==========================================================================*/

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
        _setBatchEmbeddedTags(b, tags);
        await b.save();
      }
    } catch (_) {
      // don't delete batches by default
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

/* ============================================================================
 * Cross-version helpers (typed) — for normal operations/migrations
 * ==========================================================================*/

List<Tag> _getEmbeddedTags(RecipeModel r) {
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
    // models without tagRefs
  }
}

// ---- Batch helpers (typed) ----
List<Tag> _getBatchEmbeddedTags(BatchModel b) {
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
  try { (b as dynamic).tagsLegacy = tags; } catch (_) {}
  try { (b as dynamic).tags = tags; } catch (_) {}
}

/* ============================================================================
 * Dynamic helpers — used ONLY during pre-scrub to avoid static type assumptions
 * ==========================================================================*/

List<dynamic> _getEmbeddedTagsDynamic(RecipeModel r) {
  try {
    final legacy = (r as dynamic).tagsLegacy as List<dynamic>?;
    if (legacy != null) return legacy;
  } catch (_) {}
  try {
    final current = (r as dynamic).tags as List<dynamic>?;
    if (current != null) return current;
  } catch (_) {}
  return const <dynamic>[];
}

List<dynamic> _getBatchEmbeddedTagsDynamic(BatchModel b) {
  try {
    final legacy = (b as dynamic).tagsLegacy as List<dynamic>?;
    if (legacy != null) return legacy;
  } catch (_) {}
  try {
    final current = (b as dynamic).tags as List<dynamic>?;
    if (current != null) return current;
  } catch (_) {}
  return const <dynamic>[];
}

/* ============================================================================
 * Logging
 * ==========================================================================*/

void _log(String msg) {
  // ignore: avoid_print
  print(msg);
}
