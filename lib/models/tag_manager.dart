import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:fermentacraft/utils/boxes.dart';
import 'tag.dart';

class TagManager extends ChangeNotifier {
  Box<Tag> get _tagBox => Hive.box<Tag>(Boxes.tags);

  /// Provides a simple, reactive list of all tags from the database.
  List<Tag> get tags {
    if (!Hive.isBoxOpen(Boxes.tags)) return const <Tag>[];
    return _tagBox.values.toList();
  }

  /// Adds a new tag if a tag with the same name doesn't already exist.
  /// The check is case-insensitive.
  Future<void> addTag(String name) async {
    if (!Hive.isBoxOpen(Boxes.tags)) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final exists = _tagBox.values.any((t) => t.name.toLowerCase() == trimmed.toLowerCase());
    if (!exists) {
      await _tagBox.add(Tag(name: trimmed));
      notifyListeners();
    }
  }

  /// Deletes a given tag from the database.
  Future<void> deleteTag(Tag tag) async {
    if (!Hive.isBoxOpen(Boxes.tags)) return;
    await tag.delete();
    notifyListeners();
  }

  /// Edits the name of an existing tag.
  Future<void> editTag(Tag oldTag, String newName) async {
    if (!Hive.isBoxOpen(Boxes.tags)) return;
    oldTag.name = newName.trim();
    await oldTag.save();
    notifyListeners();
  }
}
