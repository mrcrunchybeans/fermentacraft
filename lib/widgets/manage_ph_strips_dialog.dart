// lib/widgets/manage_ph_strips_dialog.dart
import 'package:flutter/material.dart';
import '../stores/ph_strip_store.dart';
import '../acid_tools/strip_reader_tab.dart'; // PHStrip model

class ManagePHStripsDialog extends StatelessWidget {
  final PHStripStore store;
  final ValueChanged<PHStrip>? onSelect; // optional: tap row to select & close

  const ManagePHStripsDialog({super.key, required this.store, this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: Column(
          children: [
            AppBar(
              automaticallyImplyLeading: false,
              title: const Text('Custom pH strips'),
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('New'),
                  onPressed: () => _openEditor(context, store: store),
                ),
              ],
            ),
            Expanded(
              child: StreamBuilder<List<PHStrip>>(
                stream: store.stripsStream,
                builder: (ctx, snap) {
                  final items = snap.data ?? const [];
                  if (items.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No custom strips yet.\nTap “New” to save one.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final s = items[i];
                      return ListTile(
                        title: Text(s.name),
                        subtitle: Text(
                          'pH: ${s.phValues.map((e) => e.toStringAsFixed(1)).join(' • ')}'
                          '${s.brand == null ? '' : ' · ${s.brand}'}',
                        ),
                        onTap: onSelect == null
                            ? null
                            : () {
                                onSelect!(s);
                                Navigator.pop(context);
                              },
                        trailing: Wrap(
  spacing: 8,
  children: [
    // EDIT
    IconButton(
      tooltip: 'Edit',
      icon: const Icon(Icons.edit),
      onPressed: () => _openEditor(context, store: store, existing: s),
    ),

    // DELETE
    IconButton(
      tooltip: 'Delete',
      icon: const Icon(Icons.delete_outline),
      onPressed: () async {
        // PRE-CAPTURE navigator (not strictly needed here, but fine to keep)

        final ok = await showDialog<bool>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title: const Text('Delete strip?'),
            content: Text('Remove “${s.name}” permanently?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );

        if (ok == true) {
          await store.delete(s.id);
          // StreamBuilder will refresh automatically.
        }
      },
    ),
  ],
),


                            
                          
                        
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context, {
    required PHStripStore store,
    PHStrip? existing,
  }) async {
    await showDialog(
      context: context,
      builder: (_) => _PHStripEditor(store: store, existing: existing),
    );
  }
}

class _PHStripEditor extends StatefulWidget {
  final PHStripStore store;
  final PHStrip? existing;
  const _PHStripEditor({required this.store, this.existing});

  @override
  State<_PHStripEditor> createState() => _PHStripEditorState();
}

class _PHStripEditorState extends State<_PHStripEditor> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _phValues = TextEditingController();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _brand.text = e.brand ?? '';
      _phValues.text = e.phValues.map((v) => v.toStringAsFixed(1)).join(', ');
    }
  }

  @override
  void dispose() {
    // Properly dispose TextEditingControllers to prevent memory leaks
    _name.dispose();
    _brand.dispose();
    _phValues.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New custom strip' : 'Edit custom strip'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Display name'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _brand,
                decoration: const InputDecoration(labelText: 'Brand / notes (optional)'),
              ),
              TextFormField(
                controller: _phValues,
                decoration: const InputDecoration(
                  labelText: 'pH values (comma-separated, low→high)',
                  hintText: 'e.g. 2.8, 3.2, 3.6, 4.0, 4.4',
                ),
                validator: (v) {
                  final list = _parseDoubles(v);
                  if (list.isEmpty) return 'Enter at least one pH value';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
onPressed: () async {
  if (!_formKey.currentState!.validate()) return;

  // PRE-CAPTURE navigator before awaiting
  final nav = Navigator.of(context);

  final values = _parseDoubles(_phValues.text);
  if (widget.existing == null) {
    await widget.store.create(
      name: _name.text.trim(),
      phValues: values,
      brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
    );
  } else {
    final s = widget.existing!
      ..name = _name.text.trim()
      ..phValues = values
      ..brand = _brand.text.trim().isEmpty ? null : _brand.text.trim();
    await widget.store.update(s);
  }

  // Safe to use pre-captured navigator after await
  nav.pop();
},

          child: const Text('Save'),
        ),
      ],
    );
  }

  List<double> _parseDoubles(String? s) {
    if (s == null) return [];
    return s
        .split(',')
        .map((e) => double.tryParse(e.trim()))
        .whereType<double>()
        .toList()
      ..sort();
  }
}
