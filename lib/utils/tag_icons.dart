import 'package:flutter/material.dart';

/// Use ONLY const Icons.* so the web icon tree-shaker can see them.
const Map<String, IconData> kTagIconMap = {
  'ingredient': Icons.liquor_outlined,
  'yeast': Icons.bubble_chart,
  'additive': Icons.science,
  'event': Icons.event_note,
  'default': Icons.label_outline,
};

IconData iconForTagKey(String? key) {
  return kTagIconMap[key] ?? kTagIconMap['default']!;
}

/// Optional: map your legacy Material codePoints → the keys above.
/// Add cases for any other icons you previously used.
String keyFromLegacy(int codePoint, String? family) {
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
