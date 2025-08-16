import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/planned_event.dart';
import 'package:fermentacraft/utils/snacks.dart';
class PlannedEventDialog extends StatefulWidget {
  final PlannedEvent? existingEvent;
  final void Function()? onDelete;

  const PlannedEventDialog({
    super.key,
    this.existingEvent,
    this.onDelete,
  });

  @override
  State<PlannedEventDialog> createState() => _PlannedEventDialogState();
}

class _PlannedEventDialogState extends State<PlannedEventDialog> {
  late TextEditingController titleController;
  late TextEditingController notesController;
  late DateTime selectedDate;

  @override
  void initState() {
    super.initState();
    final event = widget.existingEvent;
    titleController = TextEditingController(text: event?.title ?? '');
    notesController = TextEditingController(text: event?.notes ?? '');
    selectedDate = event?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    titleController.dispose();
    notesController.dispose();
    super.dispose();
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  void _submit() {
    final title = titleController.text.trim();
    final notes = notesController.text.trim();

    if (title.isEmpty) {
      snacks.show(
        const SnackBar(content: Text("Event title cannot be empty.")),
      );
      return;
    }

    Navigator.of(context).pop(
      PlannedEvent(
        title: title,
        date: selectedDate,
        notes: notes.isEmpty ? null : notes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formattedDate = DateFormat.yMMMd().format(selectedDate);

    return AlertDialog(
      title: Text(
        widget.existingEvent == null ? 'Add Planned Event' : 'Edit Planned Event',
        style: theme.textTheme.titleLarge,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Event Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Date:'),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today),
                  label: Text(
                    formattedDate,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (widget.onDelete != null)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onDelete?.call();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
