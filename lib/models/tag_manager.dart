import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'tag.dart'; // Import the correct Tag model

class TagManager extends ChangeNotifier {
  final Box<Tag> _tagBox = Hive.box<Tag>('tags');

  // Use a listenable for reactive UI updates
  ValueNotifier<List<Tag>> get tagsNotifier => ValueNotifier(_tagBox.values.toList());
  
  List<Tag> get tags => _tagBox.values.toList();

  void addTag(String name) {
    // Ensure the tag doesn't already exist (case-insensitive check)
    if (!_tagBox.values.any((tag) => tag.name.toLowerCase() == name.toLowerCase().trim())) {
      _tagBox.add(Tag(name: name.trim()));
      notifyListeners();
    }
  }

  void deleteTag(Tag tag) {
    // Use the object's key to delete it directly. This is much more efficient.
    tag.delete();
    notifyListeners();
  }

  void editTag(Tag oldTag, String newName) {
    // Modify the existing object and save it.
    oldTag.name = newName.trim();
    oldTag.save();
    notifyListeners();
  }
}
