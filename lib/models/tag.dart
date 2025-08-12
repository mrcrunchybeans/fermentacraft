import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../utils/tag_icons.dart';

part 'tag.g.dart';

@HiveType(typeId: 9)
class Tag extends HiveObject {
  @HiveField(0)
  String name;

  // Legacy fields (kept so old boxes still open)
  @HiveField(1)
  int? iconCodePoint; // DEPRECATED
  @HiveField(2)
  String? iconFontFamily; // DEPRECATED

  /// NEW: stable key → const IconData mapping (tree-shake friendly)
  @HiveField(3)
  String? iconKey;

  Tag({
    required this.name,
    this.iconCodePoint,
    this.iconFontFamily,
    this.iconKey,
  });

  /// UI should always use this. Never construct IconData dynamically.
  IconData get icon => iconForTagKey(iconKey);

  // --- JSON (include new field, keep legacy for round trips) ---
  Map<String, dynamic> toJson() => {
        'name': name,
        'iconKey': iconKey,
        'iconCodePoint': iconCodePoint,
        'iconFontFamily': iconFontFamily,
      };

  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
        name: json['name'] as String,
        iconKey: json['iconKey'] as String?,
        iconCodePoint: json['iconCodePoint'] as int?,
        iconFontFamily: json['iconFontFamily'] as String?,
      );

  @override
  String toString() => name;
}
