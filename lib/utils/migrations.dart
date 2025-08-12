import 'package:hive/hive.dart';
import '../models/tag.dart';
import '../utils/tag_icons.dart';
import '../models/recipe_model.dart';
import '../models/batch_model.dart';

/// Idempotent: safe to run every startup.
/// Migrates Tag.iconCodePoint/fontFamily → Tag.iconKey in a standalone 'tags' box.
Future<void> migrateTagIconsIfNeeded() async {
  if (!Hive.isBoxOpen('tags')) return;

  final box = Hive.box<Tag>('tags');
  for (final tag in box.values) {
    if (tag.iconKey == null && tag.iconCodePoint != null) {
      tag.iconKey = keyFromLegacy(tag.iconCodePoint!, tag.iconFontFamily);
      await tag.save();
    }
  }
}

/// If your Tags are embedded in other objects (e.g., recipes/batches), migrate those too.
Future<void> migrateEmbeddedTagsIfNeeded() async {
  // Recipes
  if (Hive.isBoxOpen('recipes')) {
    final recipes = Hive.box<RecipeModel>('recipes');
    for (final r in recipes.values) {
      bool changed = false;
      for (final t in r.tags) {
        if (t.iconKey == null && t.iconCodePoint != null) {
          t.iconKey = keyFromLegacy(t.iconCodePoint!, t.iconFontFamily);
          changed = true;
        }
      }
      if (changed) await r.save();
    }
  }

  // Batches
  if (Hive.isBoxOpen('batches')) {
    final batches = Hive.box<BatchModel>('batches');
    for (final b in batches.values) {
      bool changed = false;
      for (final t in b.tags) {
        if (t.iconKey == null && t.iconCodePoint != null) {
          t.iconKey = keyFromLegacy(t.iconCodePoint!, t.iconFontFamily);
          changed = true;
        }
      }
      if (changed) await b.save();
    }
  }
}
