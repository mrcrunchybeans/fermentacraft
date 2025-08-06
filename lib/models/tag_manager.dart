import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'tag.dart';

class TagManager extends ChangeNotifier {
  final Box<Tag> _tagBox = Hive.box<Tag>('tags');

  /// Provides a simple, reactive list of all tags from the database.
  List<Tag> get tags => _tagBox.values.toList();

  /// Adds a new tag if a tag with the same name doesn't already exist.
  /// The check is case-insensitive.
  void addTag(String name) {
    if (!_tagBox.values.any((tag) => tag.name.toLowerCase() == name.toLowerCase().trim())) {
      _tagBox.add(Tag(name: name.trim()));
      notifyListeners(); // Notify UI to rebuild
    }
  }

  /// Deletes a given tag from the database.
  void deleteTag(Tag tag) {
    // HiveObjects can be deleted directly, which is very efficient.
    tag.delete();
    notifyListeners();
  }

  /// Edits the name of an existing tag.
  void editTag(Tag oldTag, String newName) {
    oldTag.name = newName.trim();
    oldTag.save(); // Save the changes back to the database
    notifyListeners();
  }
}