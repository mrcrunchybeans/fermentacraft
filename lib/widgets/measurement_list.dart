// lib/widgets/measurement_list.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/measurement.dart';
import '../models/settings_model.dart';
import 'add_measurement_dialog.dart';
import '../utils/gravity_utils.dart';
import '../utils/temp_display.dart'; // for TemperatureUtils.toDisplay()

class MeasurementList extends StatelessWidget {
  final List<Measurement> measurements;
  final void Function(Measurement) onEdit;
  final void Function(Measurement) onDelete;

  const MeasurementList({
    super.key,
    required this.measurements,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (measurements.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('No measurements logged yet.'),
      );
    }

    // Newest first
    final sorted = measurements.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Read preferred unit (default to °C if model not found)
    final settings = context.read<SettingsModel?>();
    final useCelsius = settings?.useCelsius ?? true;
    final unitStr = useCelsius ? 'c' : 'f';

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final m = sorted[index];

        final sgText   = (m.gravity != null) ? formatGravity(m.gravity!) : '—';
        final brixText = (m.brix != null)    ? formatBrix(m.brix!)       : '—';

        // Temperature is stored in Celsius canonically; display per settings
        final tempText = (m.temperature != null)
            ? m.temperature!.toDisplay(targetUnit: unitStr)
            : '—';

        final fsuText  = (m.fsuspeed != null) ? m.fsuspeed!.toStringAsFixed(1) : '—';
        final dateText = m.timestamp.toLocal().toString().split(' ')[0];

        // trailing: note affordance for device points + your existing menu
        final trailing = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (m.fromDevice == true)
              IconButton(
                tooltip: (m.notes == null || m.notes!.trim().isEmpty) ? 'Add note' : 'Edit note',
                icon: Icon((m.notes == null || m.notes!.trim().isEmpty) ? Icons.note_add : Icons.edit_note),
onPressed: () async {
  // Capture before any awaits
  final messenger = ScaffoldMessenger.of(context);

  final newNote = await showDialog<String?>(
    context: context,
    builder: (_) => _NoteOnlyDialog(
      initial: m.notes ?? '',
      title: 'Device measurement note',
    ),
  );
  if (newNote == null) return; // cancelled

  final trimmed = newNote.trim();
  final updated = m.copyWith(notes: trimmed.isEmpty ? null : trimmed);
  onEdit(updated); // delegate persistence

  // Safe to use the captured messenger after await
  messenger.showSnackBar(const SnackBar(content: Text('Note saved')));
},

                
              ),
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'edit') {
                  await showDialog(
                    context: context,
                    builder: (_) => AddMeasurementDialog(
                      existingMeasurement: m,
                      onSave: (updated) => onEdit(updated),
                    ),
                  );
                } else if (value == 'delete') {
                  onDelete(m);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit',   child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        );

        return ListTile(
          title: Text('Date: $dateText'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SG: $sgText | Brix: $brixText'),
              Text('Temp: $tempText | FSU: $fsuText'),
              if ((m.notes ?? '').trim().isNotEmpty)
                Text('Note: ${m.notes!.trim()}',
                    style: const TextStyle(fontStyle: FontStyle.italic)),
            ],
          ),
          trailing: trailing,
        );
      },
    );
  }
}

/// Lightweight note-only dialog used by the device note affordance.
/// Does not allow editing SG/Temp — just comment text.
class _NoteOnlyDialog extends StatefulWidget {
  final String initial;
  final String title;
  const _NoteOnlyDialog({required this.initial, required this.title});

  @override
  State<_NoteOnlyDialog> createState() => _NoteOnlyDialogState();
}

class _NoteOnlyDialogState extends State<_NoteOnlyDialog> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextFormField(
        controller: _c,
        maxLines: 5,
        decoration: const InputDecoration(
          labelText: 'Note',
          hintText: 'Add your observation, action taken, aroma, etc.',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _c.text), child: const Text('Save')),
      ],
    );
  }
}
