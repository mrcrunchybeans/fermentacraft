// lib/widgets/tag_picker_dialog.dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/tag.dart';

class TagPickerDialog extends StatefulWidget {
  final List<Tag> initialTags;

  const TagPickerDialog({super.key, required this.initialTags});

  @override
  State<TagPickerDialog> createState() => _TagPickerDialogState();
}

class _TagPickerDialogState extends State<TagPickerDialog> {
  late Box<Tag> _tagBox;

  // Track selection by lowercase name (stable across objects)
  late Set<String> _selectedLower;

  final TextEditingController _newTagController = TextEditingController();

  final List<String> defaultTags = const [
    'cider', 'wine', 'mead', 'soda', 'sake', 'kefir', 'kombucha'
  ];

  @override
  void initState() {
    super.initState();
    _tagBox = Hive.box<Tag>('tags');

    _selectedLower = widget.initialTags
        .map((t) => t.name.trim().toLowerCase())
        .toSet();

    _ensureDefaultTags();
  }

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  Future<void> _ensureDefaultTags() async {
    // Only insert if a case-insensitive match doesn't exist
    final existingLower = _tagBox.values
        .map((t) => t.name.trim().toLowerCase())
        .toSet();

    for (final tag in defaultTags) {
      final key = tag.trim().toLowerCase();
      if (!existingLower.contains(key)) {
        await _tagBox.add(Tag(name: tag));
      }
    }
    if (mounted) setState(() {});
  }

  void _toggleSelection(String name) {
    final key = name.trim().toLowerCase();
    setState(() {
      if (_selectedLower.contains(key)) {
        _selectedLower.remove(key);
      } else {
        _selectedLower.add(key);
      }
    });
  }

  Future<void> _addTag(String name) async {
    name = name.trim();
    if (name.isEmpty) return;

    final key = name.toLowerCase();

    // If it already exists (case-insensitive), just select it
    final existing = _tagBox.values.firstWhere(
      (t) => t.name.trim().toLowerCase() == key,
      orElse: () => Tag(name: ''),
    );

    if (existing.name.isNotEmpty) {
      setState(() {
        _selectedLower.add(key);
        _newTagController.clear();
      });
      return;
    }

    // Otherwise create once and select it
    await _tagBox.add(Tag(name: name));
    setState(() {
      _selectedLower.add(key);
      _newTagController.clear();
    });
  }

  Icon _iconForCategory(String tagName) {
    switch (tagName.toLowerCase()) {
      case 'cider':
        return const Icon(Icons.local_drink);
      case 'wine':
        return const Icon(Icons.wine_bar);
      case 'mead':
        return const Icon(Icons.emoji_nature);
      case 'soda':
        return const Icon(Icons.local_cafe);
      case 'sake':
        return const Icon(Icons.rice_bowl);
      case 'kefir':
        return const Icon(Icons.icecream);
      case 'kombucha':
        return const Icon(Icons.eco);
      default:
        return const Icon(Icons.label);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<Tag>>(
      valueListenable: _tagBox.listenable(),
      builder: (context, box, _) {
        // Build a de-duplicated, sorted list of tags by lowercased name
        final Map<String, Tag> byLower = {};
        for (final t in box.values) {
          final key = t.name.trim().toLowerCase();
          byLower.putIfAbsent(key, () => t);
        }
        final tags = byLower.values.toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

        return AlertDialog(
          title: const Text('Select Tags'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: tags.map((tag) {
                    final key = tag.name.trim().toLowerCase();
                    final isSelected = _selectedLower.contains(key);
                    return FilterChip(
                      avatar: _iconForCategory(tag.name),
                      label: Text(tag.name),
                      selected: isSelected,
                      onSelected: (_) => _toggleSelection(tag.name),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _newTagController,
                  decoration: InputDecoration(
                    labelText: 'Add new tag',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () => _addTag(_newTagController.text),
                    ),
                  ),
                  onSubmitted: _addTag,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                // Convert selection back to Tag objects using the map
                final mapLowerToTag = {
                  for (final t in tags) t.name.trim().toLowerCase(): t
                };
                final result = _selectedLower
                    .map((k) => mapLowerToTag[k])
                    .whereType<Tag>()
                    .toList()
                  ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                Navigator.pop(context, result);
              },
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }
}

Future<List<Tag>?> showTagPickerDialog(
  BuildContext context,
  List<Tag> initialTags,
) {
  return showDialog<List<Tag>>(
    context: context,
    builder: (context) => TagPickerDialog(initialTags: initialTags),
  );
}
