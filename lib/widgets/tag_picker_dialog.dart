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
  late List<Tag> selectedTags;
  final TextEditingController _newTagController = TextEditingController();
  late Box<Tag> _tagBox;
  final List<String> defaultTags = ['cider', 'wine', 'mead', 'soda', 'sake', 'kefir', 'kombucha'];

  @override
  void initState() {
    super.initState();
    selectedTags = List<Tag>.from(widget.initialTags);
    _tagBox = Hive.box<Tag>('tags');
    _ensureDefaultTags();
  }

  void _ensureDefaultTags() async {
    for (var tag in defaultTags) {
      if (!_tagBox.values.any((t) => t.name.toLowerCase() == tag.toLowerCase())) {
      await _tagBox.add(Tag(name: tag));
      }
    }
    setState(() {});
  }

  void _addTag(String name) async {
    name = name.trim();
    if (name.isEmpty) return;

    final exists = _tagBox.values.any((tag) => tag.name.toLowerCase() == name.toLowerCase());
    if (!exists) {
    final newTag = Tag(name: name);
      await _tagBox.add(newTag);
      setState(() {
        selectedTags.add(newTag);
      });
    } else {
      final existingTag = _tagBox.values.firstWhere((tag) => tag.name.toLowerCase() == name.toLowerCase());
      if (!selectedTags.contains(existingTag)) {
        setState(() {
          selectedTags.add(existingTag);
        });
      }
    }

    _newTagController.clear();
  }

  Icon _iconForTag(String tagName) {
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
    final tags = _tagBox.values.toList();

    return AlertDialog(
      title: const Text('Select Tags'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              children: tags.map((tag) {
                final isSelected = selectedTags.contains(tag);
                return FilterChip(
                  avatar: _iconForTag(tag.name),
                  label: Text(tag.name),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() {
                      isSelected ? selectedTags.remove(tag) : selectedTags.add(tag);
                    });
                  },
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
          onPressed: () => Navigator.pop(context, selectedTags),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

Future<List<Tag>?> showTagPickerDialog(BuildContext context, List<Tag> initialTags) {
  return showDialog<List<Tag>>(
    context: context,
    builder: (context) => TagPickerDialog(initialTags: initialTags),
  );
}
