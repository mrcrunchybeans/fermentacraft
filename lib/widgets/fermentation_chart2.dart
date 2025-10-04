// lib/widgets/fermentation_chart2.dart
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/measurement.dart';
import '../models/fermentation_stage.dart';

enum BucketMode { none, avgHourly, avgDaily }
enum RightAxis { temp, fsu, off }

class FermentationChart2 extends StatefulWidget {
  /// Pass your native models directly.
  final List<Measurement> measurements;
  final List<FermentationStage> stages;

  /// Controls
  final BucketMode bucket;
  final RightAxis rightAxis;
  final bool showPoints;
  final bool showGrid;
  final bool tightBounds;

  /// If true, show temperatures in °F; otherwise °C.
  final bool tempInF;

  /// Optional: edit/delete hooks from a tap on a point (local-only)
  final void Function(Measurement)? onEditMeasurement;
  final void Function(Measurement)? onDeleteMeasurement;

  const FermentationChart2({
    super.key,
    required this.measurements,
    required this.stages,
    this.bucket = BucketMode.none,
    this.rightAxis = RightAxis.temp,
    this.showPoints = false,
    this.showGrid = true,
    this.tightBounds = false,
    required this.tempInF,
    this.onEditMeasurement,
    this.onDeleteMeasurement,
  });

  @override
  State<FermentationChart2> createState() => _FermentationChart2State();
}

class _FermentationChart2State extends State<FermentationChart2> {
  late List<Measurement> _data;        // sorted + bucketed
  late List<_FsuPoint> _fsu;           // derived
  late DateTime _t0, _t1;

  double? _yMinLeft, _yMaxLeft;        // SG
  double? _yMinRight, _yMaxRight;      // Temp or FSU

  @override
  void initState() {
    super.initState();
    _rebuildSeries();
  }

  @override
  void didUpdateWidget(covariant FermentationChart2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.measurements != widget.measurements ||
        oldWidget.stages != widget.stages ||
        oldWidget.bucket != widget.bucket ||
        oldWidget.rightAxis != widget.rightAxis ||
        oldWidget.tempInF != widget.tempInF) {
      _rebuildSeries();
    }
  }

  void _rebuildSeries() {
    final sorted = [...widget.measurements]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    _data = switch (widget.bucket) {
      BucketMode.none => sorted,
      BucketMode.avgHourly => _bucket(sorted, const Duration(hours: 1)),
      BucketMode.avgDaily => _bucket(sorted, const Duration(days: 1)),
    };

    if (_data.isEmpty) {
      final now = DateTime.now();
      _t0 = now;
      _t1 = now.add(const Duration(days: 1));
      _fsu = const [];
      _yMinLeft = 0.98;
      _yMaxLeft = 1.04;
      _yMinRight = 0;
      _yMaxRight = 100;
      return;
    }

    _t0 = _data.first.timestamp;
    _t1 = _data.last.timestamp.add(const Duration(hours: 6));

    _fsu = _computeFsu(_data);

    final sgVals = _data
        .map((m) => _chooseSg(m))
        .whereType<double>()
        .toList();

    if (sgVals.isEmpty) {
      _yMinLeft = 0.98;
      _yMaxLeft = 1.04;
    } else {
      final mn = sgVals.reduce(math.min);
      final mx = sgVals.reduce(math.max);
      final pad = (mx - mn).clamp(0.002, 0.01);
      _yMinLeft = widget.tightBounds ? mn - pad : (mn - 0.002);
      _yMaxLeft = widget.tightBounds ? mx + pad : (mx + 0.002);
    }

    switch (widget.rightAxis) {
      case RightAxis.temp:
        final temps = _data
            .map((m) => _toC(m.temperature))
            .whereType<double>()
            .map((c) => widget.tempInF ? (c * 9 / 5 + 32) : c)
            .toList();
        if (temps.isEmpty) {
          _yMinRight = widget.tempInF ? 50 : 10;
          _yMaxRight = widget.tempInF ? 90 : 32;
        } else {
          final mn = temps.reduce(math.min);
          final mx = temps.reduce(math.max);
          final pad = (mx - mn).clamp(1, 3);
          _yMinRight = (mn - pad);
          _yMaxRight = (mx + pad);
        }
        break;
      case RightAxis.fsu:
        final fsuVals = _fsu.map((e) => e.fsu).toList();
        if (fsuVals.isEmpty) {
          _yMinRight = 0;
          _yMaxRight = 400;
        } else {
          final mn = math.min(0, fsuVals.reduce(math.min));
          final mx = math.max(50, fsuVals.reduce(math.max));
          final pad = (mx - mn).clamp(25, 75);
          _yMinRight = (mn - pad * 0.1);
          _yMaxRight = (mx + pad * 0.2);
        }
        break;
      case RightAxis.off:
        _yMinRight = 0;
        _yMaxRight = 1;
        break;
    }
  }

  // Prefer corrected SG if present; else raw gravity; else convert Brix if given.
  double? _chooseSg(Measurement m) {
    if (m.sgCorrected != null) return m.sgCorrected;
    if (m.gravity != null) return m.gravity;
    if (m.brix != null) {
      // Simple Brix -> SG (Balling) approximation; adjust if you have a utility.
      final b = m.brix!;
      return 1 + (b / (258.6 - ((b / 258.2) * 227.1)));
    }
    return null;
  }

  // If measurement.temperature is °C when user uses Celsius, else °F; convert to °C for normalization.
  double? _toC(double? tempReading) {
    if (tempReading == null) return null;
    // We don't know how it was entered historically; assume batch detail entries follow user setting at time.
    // The chart caller tells us whether to *display* °F or °C; here we normalize to °C for scaling.
    // If the app is currently set to Celsius display, we treat stored values as °C; otherwise °F.
    // The caller can't tell us the historical setting per point, but this is consistent with current UX.
    // We will treat values > 60 very likely as °F to avoid nonsense.
    if (tempReading > 60) {
      // probably °F
      return (tempReading - 32) * 5 / 9;
    } else {
      return tempReading; // °C
    }
  }

  List<Measurement> _bucket(List<Measurement> src, Duration win) {
    if (src.isEmpty) return const [];
    final out = <Measurement>[];

    DateTime wndStart = _floorTo(src.first.timestamp, win);
    DateTime wndEnd = wndStart.add(win);

    double sgSum = 0, sgN = 0;
    double tSum = 0, tN = 0;

    Measurement mk(DateTime at, double? sg, double? tempC) => Measurement(
          id: 'bucket_${at.millisecondsSinceEpoch}',
          timestamp: at,
          gravity: sg,
          temperature: tempC, // stored as "°C-ish"; display transforms later
          notes: null,
          gravityUnit: 'SG',
          interventions: const [],
          ta: null,
          brix: null,
          sgCorrected: null,
          fsuspeed: null,
          fromDevice: false,
        );

    for (final m in src) {
      if (m.timestamp.isAfter(wndEnd)) {
        out.add(mk(wndStart.add(win ~/ 2), sgN > 0 ? sgSum / sgN : null, tN > 0 ? tSum / tN : null));
        while (m.timestamp.isAfter(wndEnd)) {
          wndStart = wndEnd;
          wndEnd = wndStart.add(win);
        }
        sgSum = 0; sgN = 0;
        tSum = 0; tN = 0;
      }
      final sg = _chooseSg(m);
      if (sg != null) { sgSum += sg; sgN += 1; }
      final c = _toC(m.temperature);
      if (c != null) { tSum += c; tN += 1; }
    }
    out.add(mk(wndStart.add(win ~/ 2), sgN > 0 ? sgSum / sgN : null, tN > 0 ? tSum / tN : null));

    return out.where((m) => m.gravity != null || m.temperature != null).toList();
  }

  DateTime _floorTo(DateTime t, Duration d) {
    final ms = d.inMilliseconds;
    final q = (t.millisecondsSinceEpoch ~/ ms) * ms;
    return DateTime.fromMillisecondsSinceEpoch(q);
  }

  @override
  Widget build(BuildContext context) {
    if (_data.isEmpty) {
      return const _EmptyChartState(
        hint: 'No measurements yet.\nAdd SG or temperature to see the chart.',
      );
    }

    final theme = Theme.of(context);
    final x0 = _t0.millisecondsSinceEpoch.toDouble();
    double x(DateTime t) => t.millisecondsSinceEpoch.toDouble();

    final sgSpots = <FlSpot>[];
    for (final m in _data) {
      final sg = _chooseSg(m);
      if (sg != null) {
        sgSpots.add(FlSpot(x(m.timestamp) - x0, sg));
      }
    }

    final rightIsTemp = widget.rightAxis == RightAxis.temp;
    final rightIsFsu  = widget.rightAxis == RightAxis.fsu;

    final tempSpots = <FlSpot>[];
    if (rightIsTemp) {
      for (final m in _data) {
        final c = _toC(m.temperature);
        if (c != null) {
          final disp = widget.tempInF ? (c * 9 / 5 + 32) : c;
          tempSpots.add(FlSpot(x(m.timestamp) - x0, _mapRightToLeft(disp)));
        }
      }
    }

    final fsuSpots = <FlSpot>[];
    if (rightIsFsu) {
      for (final p in _fsu) {
        fsuSpots.add(FlSpot(x(p.at) - x0, _mapRightToLeft(p.fsu)));
      }
    }

    // Stage bands
    final bands = <VerticalRangeAnnotation>[];
    for (final s in widget.stages) {
      final start = s.startDate ?? _t0;
      final end = (s.startDate ?? _t0).add(Duration(days: s.durationDays));
      final x1 = math.max(0.0, x(start) - x0);
      final x2 = x(end) - x0;
      bands.add(VerticalRangeAnnotation(
        x1: x1,
        x2: x2,
        color: theme.colorScheme.primary.withOpacity(0.06),
      ));
    }

    String fmtTs(double relX) {
      final t = DateTime.fromMillisecondsSinceEpoch(relX.toInt() + x0.toInt());
      final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
      final mm = t.minute.toString().padLeft(2, '0');
      final ap = t.hour < 12 ? 'AM' : 'PM';
      return "${t.month}/${t.day} $h:$mm $ap";
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChartHeader(
          rightAxis: widget.rightAxis,
          tempInF: widget.tempInF,
          bucket: widget.bucket,
        ),
        SizedBox(
          height: 260,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (_t1.millisecondsSinceEpoch - _t0.millisecondsSinceEpoch).toDouble(),
                minY: _yMinLeft,
                maxY: _yMaxLeft,
                gridData: FlGridData(
                  show: widget.showGrid,
                  drawVerticalLine: false,
                  horizontalInterval: 0.002,
                ),
                rangeAnnotations: RangeAnnotations(verticalRangeAnnotations: bands),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    axisNameWidget: const Text('SG'),
                    axisNameSize: 24,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      interval: 0.002,
                      getTitlesWidget: (v, _) => Text(v.toStringAsFixed(3),
                        style: theme.textTheme.bodySmall),
                    ),
                  ),
                  rightTitles: AxisTitles(
                    axisNameWidget: Text(switch (widget.rightAxis) {
                      RightAxis.temp => widget.tempInF ? 'Temp (°F)' : 'Temp (°C)',
                      RightAxis.fsu  => 'FSU',
                      RightAxis.off  => '',
                    }),
                    axisNameSize: 24,
                    sideTitles: SideTitles(
                      showTitles: widget.rightAxis != RightAxis.off,
                      reservedSize: 44,
                      interval: _rightTickInterval(),
                      getTitlesWidget: (v, _) {
                        final val = _mapLeftToRight(v);
                        if (widget.rightAxis == RightAxis.temp) {
                          final unit = widget.tempInF ? '°F' : '°C';
                          return Text('${val.toStringAsFixed(0)}$unit', style: theme.textTheme.bodySmall);
                        } else if (widget.rightAxis == RightAxis.fsu) {
                          return Text(val.toStringAsFixed(0), style: theme.textTheme.bodySmall);
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      interval: _bottomInterval(),
                      getTitlesWidget: (v, _) {
                        final t = DateTime.fromMillisecondsSinceEpoch(v.toInt() + _t0.millisecondsSinceEpoch);
                        final dayN = t.difference(_t0).inDays + 1;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Day $dayN\n${t.month}/${t.day}',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchSpotThreshold: 18,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) {
                      if (spots.isEmpty) return const [];
                      final xRel = spots.first.x;
                      final rows = <String>[fmtTs(xRel)];
                      for (final s in spots) {
                        final isSg = s.barIndex == 0;
                        if (isSg) {
                          rows.add('SG ${s.y.toStringAsFixed(3)}');
                        } else if (widget.rightAxis == RightAxis.temp) {
                          rows.add('${_mapLeftToRight(s.y).round()}${widget.tempInF ? '°F' : '°C'}');
                        } else if (widget.rightAxis == RightAxis.fsu) {
                          rows.add('FSU ${_mapLeftToRight(s.y).toStringAsFixed(0)}');
                        }
                      }
                      return [LineTooltipItem(rows.join('\n'),
                        theme.textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w600))];
                    },
                  ),
                ),
                lineBarsData: [
                  // SG
                  LineChartBarData(
                    spots: sgSpots,
                    isCurved: true,
                    barWidth: 2,
                    dotData: FlDotData(show: widget.showPoints),
                  ),
                  // Right axis mapped onto left scale
                  if (tempSpots.isNotEmpty)
                    LineChartBarData(
                      spots: tempSpots,
                      isCurved: true,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                    ),
                  if (fsuSpots.isNotEmpty)
                    LineChartBarData(
                      spots: fsuSpots,
                      isCurved: false,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                    ),
                ],
                clipData: const FlClipData.all(),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(
                    color: theme.dividerColor.withOpacity(0.7),
                    width: 1,
                  ),
                ),
              ),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            ),
          ),
        ),
      ],
    );
  }

  double _bottomInterval() {
    final days = _t1.difference(_t0).inDays.clamp(1, 365);
    if (days <= 2) return const Duration(hours: 12).inMilliseconds.toDouble();
    if (days <= 7) return const Duration(days: 1).inMilliseconds.toDouble();
    if (days <= 21) return const Duration(days: 2).inMilliseconds.toDouble();
    return const Duration(days: 3).inMilliseconds.toDouble();
  }

  double _rightTickInterval() {
    switch (widget.rightAxis) {
      case RightAxis.temp:
        return _mapRightToLeft(widget.tempInF ? 5 : 2);
      case RightAxis.fsu:
        return _mapRightToLeft(50);
      case RightAxis.off:
        return 1;
    }
  }

  double _mapRightToLeft(double valRight) {
    final leftMin = _yMinLeft ?? 1.0;
    final leftMax = _yMaxLeft ?? 1.1;
    final rightMin = _yMinRight ?? 0.0;
    final rightMax = _yMaxRight ?? 1.0;
    if (rightMax - rightMin == 0) return leftMin;
    final t = (valRight - rightMin) / (rightMax - rightMin);
    return leftMin + t * (leftMax - leftMin);
  }

  double _mapLeftToRight(double valLeft) {
    final leftMin = _yMinLeft ?? 1.0;
    final leftMax = _yMaxLeft ?? 1.1;
    final rightMin = _yMinRight ?? 0.0;
    final rightMax = _yMaxRight ?? 1.0;
    if (leftMax - leftMin == 0) return rightMin;
    final t = (valLeft - leftMin) / (leftMax - leftMin);
    return rightMin + t * (rightMax - rightMin);
  }
}

// ---------- UI bits ----------

class _ChartHeader extends StatelessWidget {
  final RightAxis rightAxis;
  final bool tempInF;
  final BucketMode bucket;
  const _ChartHeader({
    required this.rightAxis,
    required this.tempInF,
    required this.bucket,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <String>[
      'SG',
      if (rightAxis == RightAxis.temp) tempInF ? 'Temp °F' : 'Temp °C',
      if (rightAxis == RightAxis.fsu) 'FSU',
      switch (bucket) {
        BucketMode.none => 'Raw',
        BucketMode.avgHourly => 'Hourly',
        BucketMode.avgDaily => 'Daily',
      },
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: -6,
        children: chips.map((c) => Chip(label: Text(c))).toList(),
      ),
    );
  }
}

class _EmptyChartState extends StatelessWidget {
  final String hint;
  const _EmptyChartState({required this.hint});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 220,
      alignment: Alignment.center,
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(hint, textAlign: TextAlign.center),
    );
  }
}

// ---------- FSU computation ----------

class _FsuPoint {
  final DateTime at;
  final double fsu;
  _FsuPoint(this.at, this.fsu);
}

/// FSU = 100,000 * (SG1 - SG2) / days_between
List<_FsuPoint> _computeFsu(List<Measurement> data) {
  final pts = <_FsuPoint>[];
  final sgOnly = data.where((m) => m.gravity != null || m.sgCorrected != null || m.brix != null).toList();
  double? sgOf(Measurement m) => m.sgCorrected ?? m.gravity ?? (m.brix == null ? null : 1 + (m.brix! / (258.6 - ((m.brix! / 258.2) * 227.1))));
  for (var i = 1; i < sgOnly.length; i++) {
    final a = sgOnly[i - 1];
    final b = sgOnly[i];
    final sgA = sgOf(a);
    final sgB = sgOf(b);
    if (sgA == null || sgB == null) continue;
    final days = b.timestamp.difference(a.timestamp).inMinutes / (60 * 24);
    if (days <= 0) continue;
    final fsu = 100000 * (sgA - sgB) / days;
    pts.add(_FsuPoint(b.timestamp, fsu));
  }
  return pts;
}
