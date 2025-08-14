// lib/services/migrations/tag_icon_migrations.dart

import 'package:hive_flutter/hive_flutter.dart';

import '../../models/tag.dart';
import '../../models/recipe_model.dart';
import '../../models/batch_model.dart';
import '../../utils/tag_icons.dart';
import '../../utils/boxes.dart';

/// Run after Hive boxes are opened. Safe to call multiple times.
Future<void> runTagIconMigrations() async {
  await Future.wait([
    _migrateStandaloneTags(),
    _migrateRecipeTags(),
    _migrateBatchTags(),
  ]);
}

/// Returns a new iconKey for [t] if it still needs migration, otherwise null.
String? _maybeNewIconKey(Tag t) {
  // Already migrated?
  final current = t.iconKey;
  if (current != null && current.isNotEmpty) return null;

  // No legacy data to migrate?
  final cp = t.iconCodePoint;
  if (cp == null) return null;

  final k = keyFromLegacy(cp, t.iconFontFamily);
  return (k.isNotEmpty) ? k : null;
}

Future<void> _migrateStandaloneTags() async {
  if (!Hive.isBoxOpen(Boxes.tags)) return;

  final box = Hive.box<Tag>(Boxes.tags);
  for (final tag in box.values) {
    final k = _maybeNewIconKey(tag);
    if (k != null) {
      tag.iconKey = k;
      await tag.save();
    }
  }
}

Future<void> _migrateRecipeTags() async {
  if (!Hive.isBoxOpen(Boxes.recipes)) return;

  final recipes = Hive.box<RecipeModel>(Boxes.recipes);
  for (final r in recipes.values) {
    var changed = false;
    for (final t in r.tags) {
      final k = _maybeNewIconKey(t);
      if (k != null) {
        t.iconKey = k;
        changed = true;
      }
    }
    if (changed) await r.save();
  }
}

Future<void> _migrateBatchTags() async {
  if (!Hive.isBoxOpen(Boxes.batches)) return;

  final batches = Hive.box<BatchModel>(Boxes.batches);
  for (final b in batches.values) {
    var changed = false;
    for (final t in b.tags) {
      final k = _maybeNewIconKey(t);
      if (k != null) {
        t.iconKey = k;
        changed = true;
      }
    }
    if (changed) await b.save();
  }
}
