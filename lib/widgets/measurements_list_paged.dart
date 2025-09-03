// lib/widgets/measurement_list_paged.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/firestore_paths.dart';

class MeasurementListPaged extends StatefulWidget {
  final String uid;
  final String batchId;
  final int pageSize;
  const MeasurementListPaged({super.key, required this.uid, required this.batchId, this.pageSize = 50});

  @override
  State<MeasurementListPaged> createState() => _MeasurementListPagedState();
}

class _MeasurementListPagedState extends State<MeasurementListPaged> {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  bool _loading = false;
  bool _end = false;
  DocumentSnapshot? _cursor;

  Future<void> _loadMore() async {
    if (_loading || _end) return;
    setState(() => _loading = true);
    Query<Map<String, dynamic>> q = FirestorePaths
        .batchMeasurements(widget.uid, widget.batchId)
        .orderBy('timestamp', descending: true)
        .limit(widget.pageSize);

    if (_cursor != null) q = q.startAfterDocument(_cursor!);

    final snap = await q.get();
    if (snap.docs.isEmpty) {
      setState(() { _end = true; _loading = false; });
      return;
    }
    setState(() {
      _docs.addAll(snap.docs);
      _cursor = snap.docs.last;
      _loading = false;
      if (snap.docs.length < widget.pageSize) _end = true;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    if (_docs.isEmpty && _loading) {
      return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
    }
    if (_docs.isEmpty && !_loading) {
      return const Text('No device measurements yet.');
    }
    return Column(
      children: [
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final d = _docs[i].data();
            final ts = (d['timestamp'] as Timestamp?)?.toDate();
            final sg = d['sg'] as num?;
            final tempC = d['tempC'] as num?;
             final docId = _docs[i].id;
             final note = (d['notes'] as String?)?.trim();
             final isDevice = (d['source'] == 'device');
             return ListTile(
               dense: true,
               title: Text(ts?.toLocal().toString() ?? '—'),
               subtitle: Text([
                 if (sg != null) 'SG ${sg.toStringAsFixed(3)}',
                 if (tempC != null) '${tempC.toStringAsFixed(1)} °C',
                 if (isDevice) 'device',
                 if ((note ?? '').isNotEmpty) '📝 note',
               ].join(' · ')),
               trailing: isDevice
                   ? Row(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         IconButton(
                           tooltip: (note == null || note.isEmpty) ? 'Add note' : 'Edit note',
                           icon: Icon((note == null || note.isEmpty) ? Icons.note_add : Icons.edit_note),
                          onPressed: () async {
  // Capture things we need before any awaits
  final messenger = ScaffoldMessenger.of(context);

  final newNote = await showDialog<String?>(
    context: context,
    builder: (_) => const _NoteOnlyDialog(
      title: 'Device measurement note',
    ),
  );
  if (newNote == null) return;

  final trimmed = newNote.trim();
  await FirestorePaths
      .batchMeasurements(widget.uid, widget.batchId)
      .doc(docId)
      .set({'notes': trimmed.isEmpty ? null : trimmed}, SetOptions(merge: true));

  if (!mounted) return;        // guard setState & UI work
  setState(() {});             // refresh this item
  messenger.showSnackBar(      // use captured messenger
    const SnackBar(content: Text('Note saved')),
  );
},

                   )],
                     )
                   : null,
             );
          },
        ),
        const SizedBox(height: 8),
        if (!_end)
          OutlinedButton.icon(
            onPressed: _loadMore,
            icon: const Icon(Icons.expand_more),
            label: const Text('Show more'),
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }
}
class _NoteOnlyDialog extends StatefulWidget {
  final String title;
  const _NoteOnlyDialog({required this.title});

  @override
  State<_NoteOnlyDialog> createState() => _NoteOnlyDialogState();
}

class _NoteOnlyDialogState extends State<_NoteOnlyDialog> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController();
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
