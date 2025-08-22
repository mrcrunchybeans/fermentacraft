// lib/widgets/yeast_section.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:fermentacraft/controllers/recipe_builder_controller.dart';
import 'package:fermentacraft/services/presets_service.dart';

class YeastSection extends StatelessWidget {
  const YeastSection({super.key});

  @override
  Widget build(BuildContext context) {
    // Safe to call every build; returns immediately after first load.
    context.read<PresetsService>().ensureLoaded();

    return Selector<RecipeBuilderController, List<YeastLine>>(
      selector: (_, c) => List<YeastLine>.from(c.yeasts),
      builder: (ctx, yeasts, _) {
        final presets = context.watch<PresetsService>().allYeastPresets;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Yeast',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add yeast'),
                      onPressed: () => _openYeastSheet(context, presets: presets),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (yeasts.isEmpty)
                  Text(
                    'No yeast added yet.',
                    style: TextStyle(color: Colors.grey.shade600),
                  )
                else
                  ...yeasts.map(
                    (y) => _YeastRow(
                      y: y,
                      onEdit: () => _openYeastSheet(context, editing: y, presets: presets),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openYeastSheet(
    BuildContext context, {
    YeastLine? editing,
    required List<String> presets,
  }) async {
    final presetService = context.read<PresetsService>();

    final YeastLine? result = await showModalBottomSheet<YeastLine>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => _YeastEditorSheet(
        editing: editing,
        onSavePreset: presetService.maybeAddYeastPreset,
      ),
    );

    // Guard the same BuildContext after awaiting the sheet.
    if (!context.mounted) return;

    if (result != null) {
      final ctrl = context.read<RecipeBuilderController>();
      if (editing == null) {
        ctrl.addYeast(result);
      } else {
        ctrl.updateYeast(editing.id, result);
      }
    }
  }
}

class _YeastRow extends StatelessWidget {
  final YeastLine y;
  final VoidCallback onEdit;
  const _YeastRow({required this.y, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<RecipeBuilderController>();
    final qty = (y.quantity == null) ? '' : '${_fmt(y.quantity!)} ${y.unit.label}';

    return ListTile(
      dense: true,
      title: Text(y.name.isEmpty ? 'Unnamed yeast' : y.name),
      subtitle: Text('${y.form.label}${qty.isEmpty ? '' : '  •  $qty'}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => ctrl.removeYeast(y.id),
          ),
        ],
      ),
    );
  }

  String _fmt(double v) {
    final s = v.toStringAsFixed(3);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}

/// Dedicated bottom-sheet widget that *owns* its controllers,
/// preventing “controller used after dispose” issues.
class _YeastEditorSheet extends StatefulWidget {
  final YeastLine? editing;
  final Future<void> Function(String) onSavePreset;

  const _YeastEditorSheet({
    required this.editing,
    required this.onSavePreset,
  });

  @override
  State<_YeastEditorSheet> createState() => _YeastEditorSheetState();
}

class _YeastEditorSheetState extends State<_YeastEditorSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _notesCtrl;

  late YeastForm _form;
  late QtyUnit _unit;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _nameCtrl = TextEditingController(text: e?.name ?? '')
      ..addListener(() => setState(() {})); // toggle Save enabled state
    _qtyCtrl = TextEditingController(
      text: e?.quantity == null ? '' : _trim(e!.quantity!),
    );
    _notesCtrl = TextEditingController(text: e?.notes ?? '');

    _form = e?.form ?? YeastForm.dry;
    _unit = e?.unit ?? QtyUnit.packets;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final livePresets = context.watch<PresetsService>().allYeastPresets;
    final viewInsets = MediaQuery.of(context).viewInsets;
    final height = MediaQuery.of(context).size.height;
    final maxH = height * 0.9;
    final canSave = _nameCtrl.text.trim().isNotEmpty;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // grab handle
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),

              // Row 1: Name + Form
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Yeast name',
                        hintText: 'e.g., Lalvin EC-1118',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<YeastForm>(
                      value: _form,
                      items: YeastForm.values
                          .map((f) => DropdownMenuItem(value: f, child: Text(f.label)))
                          .toList(),
                      onChanged: (f) => setState(() => _form = f ?? _form),
                      decoration: const InputDecoration(
                        labelText: 'Form',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Row 2: Quantity + Unit
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Quantity',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 130,
                    child: DropdownButtonFormField<QtyUnit>(
                      value: _unit,
                      items: QtyUnit.values
                          .map((u) => DropdownMenuItem(value: u, child: Text(u.label)))
                          .toList(),
                      onChanged: (u) => setState(() => _unit = u ?? _unit),
                      decoration: const InputDecoration(
                        labelText: 'Unit',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Preset chips (built-ins + saved)
              // Preset chips (built-ins + saved)
Align(
  alignment: Alignment.centerLeft,
  child: Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final n in livePresets)
        GestureDetector(
          onLongPress: () => _onManagePresetLongPress(context, n),
          child: ActionChip(
            label: Text(n, overflow: TextOverflow.ellipsis),
            onPressed: () {
              _nameCtrl.text = n;                 // autofill
              FocusScope.of(context).nextFocus();  // move to qty
            },
          ),
        ),
    ],
  ),
),

              const SizedBox(height: 12),

              // Notes
              TextField(
                controller: _notesCtrl,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) async {
                  if (canSave) await _commit();
                },
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 2,
              ),

              const SizedBox(height: 12),

              // Actions
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: Text(widget.editing == null ? 'Add Yeast' : 'Save'),
                    onPressed: canSave ? _commit : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
Future<void> _onManagePresetLongPress(BuildContext context, String name) async {
  final svc = context.read<PresetsService>();

  if (svc.isBuiltInYeastName(name)) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Built-in preset—cannot edit'),
        duration: Duration(seconds: 2),
      ),
    );
    return;
  }

  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(leading: const Icon(Icons.edit), title: const Text('Rename'),
            onTap: () => Navigator.pop(sheetCtx, 'rename')),
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Delete'),
            onTap: () => Navigator.pop(sheetCtx, 'delete')),
        ],
      ),
    ),
  );
if (!context.mounted) return;    
if (action == null) return;

  if (action == 'rename') {
    final newName = await _promptText(
      context, title: 'Rename preset', label: 'New name', initial: name,
    );
    if (!context.mounted) return;               // <<< add this
    if (newName == null) return;

    final ok = await svc.renameYeastPreset(from: name, to: newName);
    if (!mounted || !context.mounted) return;               // <<< add this
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name exists or invalid'), duration: Duration(seconds: 2)),
      );
    } else {
      setState(() {});                  // refresh chips
    }
  } else if (action == 'delete') {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete preset?'),
        content: Text('Remove "$name" from your yeast presets?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (!mounted) return;               // <<< add this
    if (yes == true) {
      await svc.removeYeastPreset(name);
      if (!mounted) return;             // <<< add this
      setState(() {});                  // refresh chips
    }
  }
}

Future<String?> _promptText(
  BuildContext ctx, {
  required String title,
  required String label,
  String? initial,
}) async {
  final ctrl = TextEditingController(text: initial ?? '');
// in _promptText
return showDialog<String?>(
  context: ctx,
  builder: (dialogCtx) => AlertDialog(
    title: Text(title),
    content: TextField(
      controller: ctrl,
      autofocus: true,
      decoration: InputDecoration(labelText: label),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(dialogCtx, null), child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          final v = ctrl.text.trim();
          Navigator.pop(dialogCtx, v.isEmpty ? null : v);
        },
        child: const Text('Save'),
      ),
    ],
  ),
);

}

  Future<void> _commit() async {
    final name = _nameCtrl.text.trim();
    final qty = double.tryParse(_qtyCtrl.text.trim());
    final notes = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    // Persist custom names for future chips
    await widget.onSavePreset(name);

    // Guard State.context right after the await
    if (!mounted) return;

    final line = YeastLine(
      id: widget.editing?.id ?? '',
      name: name,
      form: _form,
      quantity: qty,
      unit: _unit,
      notes: notes,
    );

    Navigator.of(context).pop(line);
  }

  String _trim(double v) {
    final s = v.toStringAsFixed(3);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}
