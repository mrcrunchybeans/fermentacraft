import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

part 'tag.g.dart';

@HiveType(typeId: 9)
class Tag extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  int? iconCodePoint; // Stores the Material icon code point
  @HiveField(2)
  String? iconFontFamily; // Usually 'MaterialIcons'

  Tag({
    required this.name,
    this.iconCodePoint,
    this.iconFontFamily,
  });

  /// Returns an IconData if icon info exists, otherwise null
  IconData? get icon => iconCodePoint != null
      ? IconData(iconCodePoint!, fontFamily: iconFontFamily ?? 'MaterialIcons')
      : null;

  // --- ADDED for data export/import ---
  Map<String, dynamic> toJson() => {
        'name': name,
        'iconCodePoint': iconCodePoint,
        'iconFontFamily': iconFontFamily,
      };

  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
        name: json['name'],
        iconCodePoint: json['iconCodePoint'],
        iconFontFamily: json['iconFontFamily'],
      );
  // --- END of added code ---

  @override
  String toString() => name;
}
