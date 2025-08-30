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
            return ListTile(
              dense: true,
              title: Text(ts?.toLocal().toString() ?? '—'),
              subtitle: Text([
                if (sg != null) 'SG ${sg.toStringAsFixed(3)}',
                if (tempC != null) '${tempC.toStringAsFixed(1)} °C',
                if (d['source'] == 'device') 'device',
              ].join(' · ')),
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
