import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
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

  /// Stable key → const IconData mapping (tree-shake friendly)
  @HiveField(3)
  String? iconKey;

  Tag({
    required this.name,
    this.iconCodePoint,
    this.iconFontFamily,
    this.iconKey,
  });

  /// Use this to render icons. Avoid constructing IconData dynamically.
  IconData get icon => iconForCategoryKey(effectiveIconKey);

  /// If iconKey is missing/legacy, derive a sane key from legacy fields.
  String? get effectiveIconKey =>
      kTagIconMap.containsKey(iconKey) ? iconKey : keyFromLegacy(iconCodePoint, iconFontFamily);

  // --- JSON (canonical & backward-compatible) ---

  /// Firestore canonical form: id == name.
  Map<String, dynamic> toJson() => {
        'id': name,                  // 🔒 keep id == name
        'name': name,                // 🔒 keep id == name
        'iconKey': effectiveIconKey, // write normalized key when available
        'iconCodePoint': iconCodePoint,     // kept for legacy round-trips
        'iconFontFamily': iconFontFamily,   // kept for legacy round-trips
      };

  /// Accept either `name` or `id` and normalize icon data on read.
  factory Tag.fromJson(Map<String, dynamic> json) {
    final rawName = (json['name'] ?? json['id'] ?? '').toString().trim();

    final rawIconKey = json['iconKey'] as String?;
    final cp = _toInt(json['iconCodePoint']);
    final ff = json['iconFontFamily'] as String?;

    // Normalize iconKey: prefer valid key; else derive from legacy fields.
    final normalizedKey =
        kTagIconMap.containsKey(rawIconKey) ? rawIconKey : keyFromLegacy(cp, ff);

    return Tag(
      name: rawName,
      iconKey: normalizedKey,
      iconCodePoint: cp,
      iconFontFamily: ff,
    );
  }

  /// Optional helper if you want to harden existing instances in-place.
  void normalizeInPlace() {
    name = name.trim();
    if (!kTagIconMap.containsKey(iconKey)) {
      iconKey = keyFromLegacy(iconCodePoint, iconFontFamily);
    }
  }

  @override
  String toString() => name;

  // ---- helpers ----
  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}
