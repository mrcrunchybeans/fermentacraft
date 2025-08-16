import 'package:flutter/material.dart';

/// Single fallback used everywhere (safe for all platforms).
const IconData kDefaultTagIcon = Icons.sell_outlined;

/// Use ONLY const Icons.* so web tree-shaking can work.
const Map<String, IconData> kTagIconMap = {
  'ingredient': Icons.liquor_outlined,
  'yeast': Icons.bubble_chart,
  'additive': Icons.science,
  'event': Icons.event_note,
  'default': kDefaultTagIcon,
};

/// Never throws. Unknown / null -> fallback icon.
IconData iconForTagKey(String? key) {
  if (key == null) return kDefaultTagIcon;
  return kTagIconMap[key] ?? kDefaultTagIcon;
}

/// (Optional) list of allowed keys if you want to validate inputs/migrations.
const Set<String> kKnownTagKeys = {
  'ingredient', 'yeast', 'additive', 'event', 'default',
};

/// Legacy Material codePoints -> stable keys.
/// Extend with any other icons you previously serialized.
String keyFromLegacy(int? codePoint, String? family) {
  switch (codePoint) {
    case 0xe566: // Icons.liquor_outlined
      return 'ingredient';
    case 0xe3df: // Icons.bubble_chart
      return 'yeast';
    case 0xea4a: // Icons.science
      return 'additive';
    case 0xe178: // Icons.event_note
      return 'event';
    default:
      return 'default';
  }
}
