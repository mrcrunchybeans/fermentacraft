// lib/pages/measurement_log_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/measurement.dart';
import '../utils/gravity_utils.dart';

enum LogPreset { today, yesterday, thisWeek, thisMonth, sincePitch, custom }
extension on LogPreset {
  String label() {
    switch (this) {
      case LogPreset.today:
        return 'Today';
      case LogPreset.yesterday:
        return 'Yesterday';
      case LogPreset.thisWeek:
        return 'This Week';
      case LogPreset.thisMonth:
        return 'This Month';
      case LogPreset.sincePitch:
        return 'Since Pitch';
      case LogPreset.custom:
        return 'Custom…';
    }
  }
}

enum BucketMode { none, keep15min, avgHourly, avgDaily }

class MeasurementLogPage extends StatefulWidget {
  const MeasurementLogPage({
    super.key,
    required this.batchId,
    required this.uid, // null => local-only
    required this.local,
    required this.deviceName,
    this.firstMeasurementDate,
    this.onEditLocal,
    this.onDeleteLocal,
    this.gravityOffset = 0.0,
    this.tempOffset = 0.0,
    this.pressureOffset = 0.0,
  });

  final String batchId;
  final String? uid;
  final String? deviceName;
  final List<Measurement> local;
  final DateTime? firstMeasurementDate;
  final void Function(Measurement)? onEditLocal;
  final void Function(Measurement)? onDeleteLocal;
  /// Offset added to every device gravity reading before display.
  final double gravityOffset;
  /// Offset added to every device temperature reading before display.
  final double tempOffset;
  /// Offset added to every Nautilis pressure reading before display (bar).
  final double pressureOffset;

  @override
  State<MeasurementLogPage> createState() => _MeasurementLogPageState();
}

class _MeasurementLogPageState extends State<MeasurementLogPage> {
  LogPreset _preset = LogPreset.thisWeek;
  DateTimeRange? _customRange;
  bool _showManual = true;
  bool _showDevice = true;
  BucketMode _bucketMode = BucketMode.keep15min;

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  DateTimeRange _rangeFor(LogPreset p, DateTime batchStart) {
    final now = DateTime.now();
    switch (p) {
      case LogPreset.today:
        return DateTimeRange(start: _startOfDay(now), end: _endOfDay(now));
      case LogPreset.yesterday:
        final y = now.subtract(const Duration(days: 1));
        return DateTimeRange(start: _startOfDay(y), end: _endOfDay(y));
      case LogPreset.thisWeek:
        final monday = now.subtract(Duration(days: (now.weekday - 1)));
        return DateTimeRange(start: _startOfDay(monday), end: _endOfDay(now));
      case LogPreset.thisMonth:
        final first = DateTime(now.year, now.month, 1);
        return DateTimeRange(start: first, end: _endOfDay(now));
      case LogPreset.sincePitch:
        return DateTimeRange(start: _startOfDay(batchStart), end: _endOfDay(now));
      case LogPreset.custom:
        return _customRange ??
            DateTimeRange(start: _startOfDay(now), end: _endOfDay(now));
    }
  }

  Future<List<Measurement>> _fetchRemoteBounded(DateTimeRange range) async {
    if (widget.uid == null || widget.batchId.isEmpty) return const [];
    // use [start, end) to avoid off-by-one at 23:59:59.999
    final endExclusive = range.end.add(const Duration(milliseconds: 1));
    final qs = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .collection('batches')
          .doc(widget.batchId)
          .collection('measurements')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(range.start))
          .where('timestamp', isLessThan: Timestamp.fromDate(endExclusive))
          .orderBy('timestamp', descending: false)
          .limit(2000)
          .get();

      return qs.docs
          .map((d) => _fromRemoteDoc(d.data(), docId: d.id))
          .where((m) =>
              (m.gravity != null) ||
              (m.brix != null) ||
              (m.temperature != null))
          .toList();

  }

  // --- Bucketing helpers ---
  List<Measurement> _applyBucketing(List<Measurement> items) {
    if (items.isEmpty) return items;
    final sorted = [...items]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    switch (_bucketMode) {
      case BucketMode.none:
        return sorted;
      case BucketMode.keep15min:
        return _collapseWithin(sorted, const Duration(minutes: 15));
      case BucketMode.avgHourly:
        return _averageBy(sorted, (d) => DateTime(d.year, d.month, d.day, d.hour));
      case BucketMode.avgDaily:
        return _averageBy(sorted, (d) => DateTime(d.year, d.month, d.day));
    }
  }

  List<Measurement> _collapseWithin(List<Measurement> items, Duration window) {
    final out = <Measurement>[];
    Measurement? last;
    for (final m in items) {
      if (last == null) {
        out.add(m);
        last = m;
        continue;
      }
      if (m.timestamp.difference(last.timestamp).abs() <= window) {
        if (last.fromDevice == true && m.fromDevice != true) {
          out[out.length - 1] = m;
          last = m;
        }
      } else {
        out.add(m);
        last = m;
      }
    }
    return out;
  }

  List<Measurement> _averageBy(
    List<Measurement> items,
    DateTime Function(DateTime) bucketFn,
  ) {
    final groups = <DateTime, List<Measurement>>{};
    for (final m in items) {
      final k = bucketFn(m.timestamp.toLocal());
      (groups[k] ??= []).add(m);
    }
    final averaged = <Measurement>[];
    groups.forEach((key, list) {
      final sg = list.map((m) => m.gravity).whereType<double>().toList();
      final bx = list.map((m) => m.brix).whereType<double>().toList();
      final tc = list.map((m) => m.temperature).whereType<double>().toList();

      double? avg(List<double> xs) =>
          xs.isEmpty ? null : xs.reduce((a, b) => a + b) / xs.length;

      averaged.add(Measurement(
        timestamp: key,
        gravity: avg(sg),
        brix: avg(bx),
        temperature: avg(tc),
        fromDevice: list.any((m) => m.fromDevice == true),
      ));
    });
    averaged.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return averaged;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final batchStart =
        widget.firstMeasurementDate ?? DateTime.now().subtract(const Duration(days: 7));
    final range = _rangeFor(_preset, batchStart);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Measurement Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          )
        ],
      ),
    body: FutureBuilder<List<Measurement>>(
      key: ValueKey(
        '${widget.uid ?? "local"}|${widget.batchId}|'
        '${range.start.millisecondsSinceEpoch}-${range.end.millisecondsSinceEpoch}|'
        'M$_showManual-D$_showDevice-B${_bucketMode.index}',
      ),
      future: _fetchRemoteBounded(range),
        builder: (context, snap) {
          final isLoading = snap.connectionState == ConnectionState.waiting;

          final remote = snap.data ?? const <Measurement>[];
          final local = widget.local;

          // Filter sources
          var merged = <Measurement>[
            if (_showManual) ...local,
            if (_showDevice) ...remote,
          ];

          // Time range already enforced by Firestore fetch; local-only view still needs it:
          if (widget.uid == null) {
            final endExclusive = range.end.add(const Duration(milliseconds: 1));
            merged = merged
                .where((m) => !m.timestamp.isBefore(range.start) && m.timestamp.isBefore(endExclusive))
                .toList();
          }

          // Apply bucketing
          final processed = _applyBucketing(merged);

          // Group by day
          final byDay = <DateTime, List<Measurement>>{};
          for (final m in processed) {
            final t = m.timestamp.toLocal();
            final k = DateTime(t.year, t.month, t.day);
            (byDay[k] ??= []).add(m);
          }
          final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

          return Column(
            children: [
              // --- Filter bar ---
              Material(
                color: theme.colorScheme.surfaceVariant.withOpacity(.5),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final p in LogPreset.values)
                            ChoiceChip(
                              label: Text(p.label()),
                              selected: _preset == p,
                              onSelected: (sel) async {
                                if (!sel) return;
                                if (p == LogPreset.custom) {
                                  final picked = await showDateRangePicker(
                                    context: context,
                                    initialDateRange: _rangeFor(_preset, batchStart),
                                    firstDate: batchStart,
                                    lastDate: DateTime.now().add(const Duration(days: 1)),
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      _preset = LogPreset.custom;
                                      _customRange = picked;
                                    });
                                  }
                                } else {
                                  setState(() {
                                    _preset = p;
                                  });
                                }
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          FilterChip(
                            label: const Text('Manual'),
                            selected: _showManual,
                            onSelected: (v) => setState(() => _showManual = v),
                          ),
                          const SizedBox(width: 8),
                          FilterChip(
                            label: const Text('Device'),
                            selected: _showDevice,
                            onSelected: (v) => setState(() => _showDevice = v),
                          ),
                          const Spacer(),
                          DropdownButton<BucketMode>(
                            value: _bucketMode,
                            underline: const SizedBox.shrink(),
                            items: const [
                              DropdownMenuItem(
                                  value: BucketMode.none,
                                  child: Text('No bucket')),
                              DropdownMenuItem(
                                  value: BucketMode.keep15min,
                                  child: Text('~15m collapse')),
                              DropdownMenuItem(
                                  value: BucketMode.avgHourly,
                                  child: Text('Avg hourly')),
                              DropdownMenuItem(
                                  value: BucketMode.avgDaily,
                                  child: Text('Avg daily')),
                            ],
                            onChanged: (d) => setState(() => _bucketMode = d ?? BucketMode.none),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${DateFormat.yMMMd().format(range.start)} → ${DateFormat.yMMMd().format(range.end)}'
                        '${isLoading ? " · loading…" : ""}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),

              // --- Content ---
              Expanded(
                child: processed.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.hourglass_empty, size: 48, color: Colors.grey),
                            const SizedBox(height: 12),
                            Text(
                              'No measurements in this range',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(color: Colors.grey),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () =>
                                  setState(() => _preset = LogPreset.thisWeek),
                              child: const Text('Reset Filters'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: days.length,
                        itemBuilder: (_, i) {
                          final day = days[i];
                          final items = byDay[day]!;
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Text(DateFormat.yMMMMd().format(day),
                                          style: theme.textTheme.titleSmall),
                                      const SizedBox(width: 8),
                                      const Expanded(child: Divider()),
                                    ],
                                  ),
                                   ...items.map((m) => ListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(m.fromDevice == true
                                            ? Icons.sensors
                                            : Icons.edit_note),
                                        title: Text(
                                          () {
                                            // Apply per-device offsets for device readings; leave manual as-is.
                                            final isDevice = m.fromDevice == true;
                                            final rawSg = m.gravity ?? (m.brix != null ? brixToSg(m.brix!) : null);
                                            final displaySg = rawSg != null
                                                ? (isDevice ? rawSg + widget.gravityOffset : rawSg)
                                                : null;
                                            final rawTemp = m.temperature;
                                            final displayTemp = rawTemp != null
                                                ? (isDevice ? rawTemp + widget.tempOffset : rawTemp)
                                                : null;
                                            // Show 4 decimal places for gravity (instead of 3) so users can
                                            // see the true reading and fine-tune the offset accordingly.
                                            final sgStr = displaySg?.toStringAsFixed(4) ?? '—';
                                            final tempStr = displayTemp != null
                                                ? '${displayTemp.toStringAsFixed(1)}°C'
                                                : '—';
                                            final fsuStr = m.fsuspeed != null
                                                ? ' · FSU ${m.fsuspeed!.toStringAsFixed(0)}'
                                                : '';
                                            // Pressure from Nautilis iPressure/iRelay+P
                                            // is encoded as 'P: X.XXX bar' in the notes field.
                                            // Apply pressureOffset before display.
                                            String pressureStr = '';
                                            if (m.fromDevice == true &&
                                                m.notes != null &&
                                                m.notes!.startsWith('P:')) {
                                              // Parse the raw bar value out of e.g. 'P: 1.234 bar'
                                              final rawPStr = m.notes!
                                                  .replaceFirst('P:', '')
                                                  .replaceAll('bar', '')
                                                  .trim();
                                              final rawP = double.tryParse(rawPStr);
                                              if (rawP != null) {
                                                final displayP = rawP + widget.pressureOffset;
                                                pressureStr = ' · P: ${displayP.toStringAsFixed(3)} bar';
                                              } else {
                                                pressureStr = ' · ${m.notes}';
                                              }
                                            }
                                            return '${DateFormat.Md().add_jm().format(m.timestamp.toLocal())} · '
                                                'SG $sgStr · $tempStr$fsuStr$pressureStr';
                                          }(),
                                        ),
                                        trailing: (m.fromDevice == true)
                                            ? const SizedBox.shrink()
                                            : Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                      icon: const Icon(Icons.edit),
                                                      onPressed: () => widget.onEditLocal?.call(m)),
                                                  IconButton(
                                                      icon: const Icon(
                                                          Icons.delete_outline),
                                                      onPressed: () =>
                                                          widget.onDeleteLocal
                                                              ?.call(m)),
                                                ],
                                              ),
                                      )),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- Firestore doc → Measurement ---
  // NOTE: offsets are NOT applied here; they are applied at display time so
  // the raw values remain pristine for averaging/bucketing calculations.
  Measurement _fromRemoteDoc(Map<String, dynamic> m, {String? docId}) {
    final ts = (m['timestamp'] is Timestamp)
        ? (m['timestamp'] as Timestamp).toDate()
        : DateTime.tryParse(m['timestamp']?.toString() ?? '') ?? DateTime.now();

    double? sg = (m['sg'] as num?)?.toDouble() ??
        (m['corrSG'] as num?)?.toDouble() ??
        (m['corr_gravity'] as num?)?.toDouble() ??
        (m['corr-gravity'] as num?)?.toDouble();

    double? brix = (m['brix'] as num?)?.toDouble();
    if (sg == null && m['gravity'] != null) {
      final gVal = (m['gravity'] as num).toDouble();
      final gUnit = (m['gravity_unit'] ??
              m['gravity-unit'] ??
              m['gravityUnit'])
          ?.toString()
          .toLowerCase();
      if (gUnit == 'brix' || gUnit == '°brix' || gUnit == 'bx') {
        brix = gVal;
        sg = brixToSg(gVal);
      } else {
        sg = gVal;
      }
    }
    sg ??= (brix != null) ? brixToSg(brix) : null;

    double? tempC;
    if (m['tempC'] is num) {
      tempC = (m['tempC'] as num).toDouble();
    } else if (m['temperature'] is num) {
      final t = (m['temperature'] as num).toDouble();
      final u = (m['tempUnit'] ??
              m['temp_unit'] ??
              m['temperature_unit'] ??
              m['temperatureUnit'])
          ?.toString()
          .toLowerCase();
      if (u == 'f' || u == 'fahrenheit') {
        tempC = (t - 32) * 5.0 / 9.0;
      } else {
        tempC = t;
      }
    }

    // Pressure (Nautilis iPressure / iRelay+P) — stored in Firestore as pressureBar.
    // Since Measurement has no pressure field (no Hive schema change), we encode it
    // into notes so it can be displayed in the full log without touching local storage.
    final pressureBar = (m['pressureBar'] as num?)?.toDouble();
    String? notes = ((m['notes'] ?? m['note']) as String?)?.trim();
    if (pressureBar != null) {
      final pStr = 'P: ${pressureBar.toStringAsFixed(2)} bar';
      notes = notes != null && notes.isNotEmpty ? '$notes · $pStr' : pStr;
    }

    return Measurement(
      id: docId,
      timestamp: ts,
      gravity: sg,
      brix: brix,
      temperature: tempC,
      fromDevice: true,
      notes: notes,
    );
  }
}
