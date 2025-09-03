// lib/widgets/fermentation_chart_simple.dart
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/measurement.dart';

/// --------- Internal helpers ----------

class _HourlyAggregator {
  int sgCount = 0;
  double sgSum = 0;
  int tCCount = 0;
  double tCSum = 0; // Temp averaged in °C

  void add(Measurement m) {
    if (m.gravity != null) {
      sgSum += m.gravity!;
      sgCount += 1;
    }
    if (m.temperature != null) {
      if (m.temperature! > -50.0 && m.temperature! < 100.0) {
        tCSum += m.temperature!;
        tCCount += 1;
      }
    }
  }

  double? get avgSg => sgCount > 0 ? sgSum / sgCount : null;
  double? get avgTempC => tCCount > 0 ? tCSum / tCCount : null;
}

/// Truncates to the nearest hour.
DateTime truncateHour(DateTime t) {
  final lt = t.toLocal();
  return DateTime(lt.year, lt.month, lt.day, lt.hour);
}

/// "Nice" ticks for a numeric domain.
List<double> _niceTicks({
  required double min,
  required double max,
  int desired = 6,
}) {
  if (min.isInfinite || max.isInfinite || min.isNaN || max.isNaN) return [0, 1];
  if (min == max) return [min];
  if (min > max) {
    final tmp = min; min = max; max = tmp;
  }

  final range = max - min;
  final rawStep = range / (desired - 1).toDouble();
  final magnitude = math.pow(10, (math.log(rawStep) / math.ln10).floorToDouble()).toDouble();
  final normalizedStep = rawStep / magnitude;

  double step;
  if (normalizedStep < 1.5) { // 1, 1.2, 1.4 -> 1
    step = 1.0 * magnitude;
  } else if (normalizedStep < 3.0) { // 1.5, 2.0, 2.5 -> 2
    step = 2.0 * magnitude;
  } else if (normalizedStep < 7.0) { // 3.0, 4.0, 5.0, 6.0 -> 5
    step = 5.0 * magnitude;
  } else { // 7.0, 8.0, 9.0 -> 10
    step = 10.0 * magnitude;
  }

  final start = (min / step).floorToDouble() * step;
  final end = (max / step).ceilToDouble() * step;

  final ticks = <double>[];
  for (double v = start; v <= end + 1e-9; v += step) {
    ticks.add(double.parse(v.toStringAsFixed(6)));
  }
  return ticks;
}

double _minOf(Iterable<double> xs, {double fallback = 0.0}) {
  if (xs.isEmpty) return fallback;
  return xs.reduce(math.min);
}

double _maxOf(Iterable<double> xs, {double fallback = 0.0}) {
  if (xs.isEmpty) return fallback;
  return xs.reduce(math.max);
}

/// --------- Enums ----------
enum _RightAxis { temperature, fsu }
enum YScaleMode { auto, fitOnce, locked }
enum ChartRange { h24, d3, d7, d30, sincePitch }

/// --------- Viewport scale snapshot ----------
class _ViewportScale {
  _ViewportScale({
    required this.sgMin,
    required this.sgMax,
    required this.rightType,
    required this.rightMin,
    required this.rightMax,
    required this.rightTicks,
  });

  final double sgMin, sgMax;
  final _RightAxis rightType;

  /// Right axis values (for labels): either Temperature range or FSU range depending on rightType.
  final double rightMin, rightMax;

  /// Precomputed right ticks for labels.
  final List<double> rightTicks;
}

/// --------- Simple chart (hourly-avg) ----------
class SimpleFermentationChart extends StatefulWidget {
  const SimpleFermentationChart({
    super.key,
    required this.measurements,
    this.useFahrenheit = false,
    this.maxBuckets = 200,
    this.showBottomTicks = true,
    this.visibleRangeStart,
    this.visibleRangeEnd,
  });

  final int maxBuckets;
  final List<Measurement> measurements;
  final bool showBottomTicks;
  final bool useFahrenheit;
  final DateTime? visibleRangeEnd;
  final DateTime? visibleRangeStart;

  @override
  State<SimpleFermentationChart> createState() => _SimpleFermentationChartState();
}

class _Series {
  _Series({
    required this.sgSpots,
    required this.labelTimes,
    required this.xToSg,
    required this.xToTemp,
    required this.xToFsuPtDay,
    required this.dataMinX,
    required this.dataMaxX,
  });

  final List<FlSpot> sgSpots;                 // left axis raw SG values
  final Map<double, DateTime> labelTimes;     // x -> time
  final Map<double, double> xToSg;            // x -> sg
  final Map<double, double> xToTemp;          // x -> temp (C or F)
  final Map<double, double> xToFsuPtDay;      // x -> FSU (pt/day)
  final double dataMinX;
  final double dataMaxX;

  bool get isEmpty => sgSpots.isEmpty;
}


class _SimpleFermentationChartState extends State<SimpleFermentationChart> {
  // --- Memoization / caching ---
  String? _seriesFingerprint;
  _Series? _series;
  _Series? _lastNonEmptySeries; // used to avoid spinner during brief reloads

  // --- Viewport (in X units = hourly bucket indexes) ---
  double? _viewMinX;
  double? _viewMaxX;

  // --- Y-scale mode + locked snapshot ---
  YScaleMode _scaleMode = YScaleMode.fitOnce;
  _ViewportScale? _lockedScale;

// Expand (never shrink) a locked scale to include the fresh window.
// Keeps right axis type stable; expands right min/max only if the type matches.
_ViewportScale _expandFitOnceIfNeeded(_ViewportScale locked, _ViewportScale fresh) {
  double sgMin = locked.sgMin, sgMax = locked.sgMax;
  if (fresh.sgMin < sgMin) sgMin = fresh.sgMin;
  if (fresh.sgMax > sgMax) sgMax = fresh.sgMax;

  double rightMin = locked.rightMin, rightMax = locked.rightMax;
  final rightType = locked.rightType;
  if (locked.rightType == fresh.rightType) {
    if (fresh.rightMin < rightMin) rightMin = fresh.rightMin;
    if (fresh.rightMax > rightMax) rightMax = fresh.rightMax;
  }

  return _ViewportScale(
    sgMin: sgMin,
    sgMax: sgMax,
    rightType: rightType,
    rightMin: rightMin,
    rightMax: rightMax,
    rightTicks: _niceTicks(min: rightMin, max: rightMax, desired: 6),
  );
}

// Map an arbitrary [vMin..vMax] range into the current left SG span.
double _mapValueRangeToLeft({
  required double value,
  required double vMin,
  required double vMax,
  required _ViewportScale vs,
}) {
  final span = (vMax - vMin).abs();
  final t = span < 1e-9 ? 0.0 : (value - vMin) / span; // 0..1
  return vs.sgMin + t * (vs.sgMax - vs.sgMin);
}

  // --- Interaction & layout helpers ---
  double _chartWidth = 1; // updated by LayoutBuilder
  bool _shiftDown = false; // desktop SHIFT + wheel for horizontal pan
  double _startMinX = 0, _startMaxX = 0, _startRange = 0, _xAtFocal = 0;

  // Utility
  double _clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

  // Fingerprint of inputs to decide whether to recompute hourly aggregates
  String _calcFingerprint() {
    final ms = widget.measurements;
    if (ms.isEmpty) {
      return 'len=0|F=${widget.useFahrenheit}|B=${widget.maxBuckets}';
    }
    DateTime minT = ms.first.timestamp;
    DateTime maxT = ms.first.timestamp;
    for (final m in ms) {
      final t = m.timestamp;
      if (t.isBefore(minT)) minT = t;
      if (t.isAfter(maxT)) maxT = t;
    }
    return 'len=${ms.length}|min=${minT.millisecondsSinceEpoch}|max=${maxT.millisecondsSinceEpoch}|F=${widget.useFahrenheit}|B=${widget.maxBuckets}';
  }

  @override
  void didUpdateWidget(covariant SimpleFermentationChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedRange =
        oldWidget.visibleRangeStart != widget.visibleRangeStart ||
        oldWidget.visibleRangeEnd != widget.visibleRangeEnd;
    if (changedRange) {
      _viewMinX = null;
      _viewMaxX = null;
      if (_scaleMode != YScaleMode.locked) _lockedScale = null;
    }
  }

  // ---- Data preparation (hourly aggregate) ----
  _Series _buildSeries() {
    final ms = widget.measurements;

    if (ms.isEmpty && _lastNonEmptySeries != null) return _lastNonEmptySeries!;
    if (ms.isEmpty) {
      return _Series(
        sgSpots: const [],
        labelTimes: const {},
        xToSg: const {},
        xToTemp: const {},
        xToFsuPtDay: const {},
        dataMinX: 0.0,
        dataMaxX: 0.0,
      );
    }

    final sorted = [...ms]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final byHour = <DateTime, _HourlyAggregator>{};
    for (final m in sorted) {
      final k = truncateHour(m.timestamp);
      (byHour[k] ??= _HourlyAggregator()).add(m);
    }
    final keys = byHour.keys.toList()..sort();

    final stride = keys.length > widget.maxBuckets
        ? (keys.length / widget.maxBuckets).ceil()
        : 1;

    final sgSpots = <FlSpot>[];
    final labelTimes = <double, DateTime>{};
    final xToSg = <double, double>{};
    final xToTemp = <double, double>{};
    final xToFsu = <double, double>{};

    double x = 0.0;
    for (var i = 0; i < keys.length; i += stride) {
      final aggr = byHour[keys[i]]!;
      final sg = aggr.avgSg;
      final tempC = aggr.avgTempC;

      if (sg != null) {
        sgSpots.add(FlSpot(x, sg));
        xToSg[x] = sg;
      }
      if (tempC != null) {
        xToTemp[x] = widget.useFahrenheit ? (tempC * 9.0 / 5.0 + 32.0) : tempC;
      }

      labelTimes[x] = keys[i];
      x += 1.0;
    }

    if (xToSg.isNotEmpty) {
      final n = sgSpots.length;
      for (var i = 0; i < n; i++) {
        final iPrev = (i == 0) ? i : i - 1;
        final iNext = (i == n - 1) ? i : i + 1;

        final tPrev = labelTimes[iPrev.toDouble()]!;
        final tNext = labelTimes[iNext.toDouble()]!;
        final dtHours = (tNext.difference(tPrev).inMinutes.toDouble() / 60.0).abs();
        if (dtHours <= 0) continue;

        final sgPrev = xToSg[iPrev.toDouble()];
        final sgNext = xToSg[iNext.toDouble()];
        if (sgPrev == null || sgNext == null) continue;

        final dSgPerHour = (sgNext - sgPrev) / dtHours;
        final fsuPtDay = (-dSgPerHour * 1000.0) * 24.0;
        xToFsu[i.toDouble()] = math.max(0.0, fsuPtDay);
      }
    }

    final dataMinX = labelTimes.isEmpty ? 0.0 : _minOf(labelTimes.keys, fallback: 0.0).toDouble();
    final dataMaxX = labelTimes.isEmpty ? 0.0 : _maxOf(labelTimes.keys, fallback: 0.0).toDouble();

    final series = _Series(
      sgSpots: sgSpots,
      labelTimes: labelTimes,
      xToSg: xToSg,
      xToTemp: xToTemp,
      xToFsuPtDay: xToFsu,
      dataMinX: dataMinX,
      dataMaxX: dataMaxX,
    );

    if (!series.isEmpty) _lastNonEmptySeries = series;
    return series;
  }

  void _ensureSeries() {
    final fp = _calcFingerprint();
    if (_seriesFingerprint != fp || _series == null) {
      _seriesFingerprint = fp;
      _series = _buildSeries();
      if (_scaleMode != YScaleMode.locked) _lockedScale = null;
    }
  }

  // 5-point moving average smoothing
  double _smoothedFsuAt(_Series s, double xi) {
    double sum = 0;
    int c = 0;
    for (final dx in const [-2.0, -1.0, 0.0, 1.0, 2.0]) {
      final v = s.xToFsuPtDay[xi + dx];
      if (v != null) { sum += v; c++; }
    }
    if (c == 0) return 0.0;
    final avg = sum / c;
    return avg.isFinite ? avg : 0.0;
  }

  /// Build viewport from props when needed and keep it stable otherwise.
  void _ensureViewportInitialized(_Series s) {
    if (_viewMinX != null && _viewMaxX != null) return;

    double initialMinX = s.dataMinX;
    double initialMaxX = s.dataMaxX;

    if (widget.visibleRangeStart != null && s.labelTimes.isNotEmpty) {
      final start = widget.visibleRangeStart!;
      DateTime best = s.labelTimes.values.first;
      for (final t in s.labelTimes.values) {
        if (!t.isBefore(start)) { best = t; break; }
      }
      initialMinX = s.labelTimes.entries
          .firstWhere((e) => e.value == best, orElse: () => s.labelTimes.entries.first)
          .key;
    }

    if (widget.visibleRangeEnd != null && s.labelTimes.isNotEmpty) {
      final end = widget.visibleRangeEnd!;
      DateTime best = s.labelTimes.values.last;
      for (final t in s.labelTimes.values.toList().reversed) {
        if (!t.isAfter(end)) { best = t; break; }
      }
      initialMaxX = s.labelTimes.entries
          .firstWhere((e) => e.value == best, orElse: () => s.labelTimes.entries.last)
          .key;
    }

    if (initialMaxX < initialMinX) {
      final tmp = initialMinX; initialMinX = initialMaxX; initialMaxX = tmp;
    }
if (initialMaxX - initialMinX < 1) {
  // before: initialMaxX = (initialMinX + 1).clamp(s.dataMinX, s.dataMaxX);
  initialMaxX = _clamp(initialMinX + 1, s.dataMinX, s.dataMaxX);
}

    _viewMinX = _clamp(initialMinX, s.dataMinX, s.dataMaxX);
    _viewMaxX = _clamp(initialMaxX, s.dataMinX, s.dataMaxX);
  }

  /// Compute autoscaled SG + right axis for the current visible X window.
  _ViewportScale _viewportScale(_Series s, double minX, double maxX) {
    final sgVis = s.sgSpots
        .where((p) => p.x >= minX && p.x <= maxX)
        .map((p) => p.y)
        .toList();

    const sgMinClamp = 0.98;
    const sgMaxClamp = 1.5;

    double sgMin = sgVis.isEmpty ? 0.99 : _minOf(sgVis);
    double sgMax = sgVis.isEmpty ? 1.08 : _maxOf(sgVis);

    const sgPad = 0.0015;
    sgMin = (sgMin - sgPad).clamp(sgMinClamp, sgMaxClamp);
    sgMax = (sgMax + sgPad).clamp(sgMinClamp, sgMaxClamp);

    if (sgMax - sgMin < 0.005) {
      final mid = (sgMax + sgMin) / 2.0;
      sgMin = (mid - 0.003).clamp(sgMinClamp, sgMaxClamp);
      sgMax = (mid + 0.003).clamp(sgMinClamp, sgMaxClamp);
    }

    final tempVis = s.xToTemp.entries
        .where((e) => e.key >= minX && e.key <= maxX)
        .map((e) => e.value)
        .toList();
    final fsuVis = s.xToFsuPtDay.entries
        .where((e) => e.key >= minX && e.key <= maxX)
        .map((e) => e.value)
        .toList();

    final bool hasTempVis = tempVis.isNotEmpty;
    final _RightAxis rightType = hasTempVis ? _RightAxis.temperature : _RightAxis.fsu;

    double rightMin, rightMax;
    List<double> rightTicks;

    if (rightType == _RightAxis.temperature) {
      var tMin = tempVis.isEmpty ? (widget.useFahrenheit ? 64.0 : 18.0) : _minOf(tempVis);
      var tMax = tempVis.isEmpty ? (widget.useFahrenheit ? 75.0 : 24.0) : _maxOf(tempVis);

      final minTempSpan = widget.useFahrenheit ? 1.0 : 0.6;
      if (tMax - tMin < minTempSpan) {
        final mid = (tMax + tMin) / 2.0;
        tMin = mid - minTempSpan / 2.0;
        tMax = mid + minTempSpan / 2.0;
      }

      if (!tMin.isFinite || !tMax.isFinite) {
        tMin = widget.useFahrenheit ? 60.0 : 15.0;
        tMax = widget.useFahrenheit ? 80.0 : 27.0;
      }

      rightMin = tMin;
      rightMax = tMax;
      rightTicks = _niceTicks(min: rightMin, max: rightMax, desired: 6);
    } else {
final fMax = fsuVis.isEmpty ? 10.0 : _maxOf(fsuVis);
// before: rightMax = fMax.clamp(1.0, 1000.0);
rightMax = _clamp(fMax, 1.0, 1000.0);
      rightMin = 0.0;
      rightMax = _clamp(fMax, 1.0, 1000.0);
      rightTicks = _niceTicks(min: rightMin, max: rightMax, desired: 6);
    }

    return _ViewportScale(
      sgMin: sgMin,
      sgMax: sgMax,
      rightType: rightType,
      rightMin: rightMin,
      rightMax: rightMax,
      rightTicks: rightTicks,
    );
  }

  // Map right-axis value to left SG space
  double _mapRightToLeft(_ViewportScale vs, double yRight) {
    final denom = (vs.rightMax - vs.rightMin).abs();
    final safeDenom = denom < 1e-9 ? 1.0 : denom;
    return vs.sgMin + (vs.sgMax - vs.sgMin) * ((yRight - vs.rightMin) / safeDenom);
  }

  // Apply horizontal pan (deltaX in X units)
  void _applyPan(_Series s, double deltaX) {
    final span = (_viewMaxX! - _viewMinX!);
    var newMin = _viewMinX! + deltaX;
    var newMax = _viewMaxX! + deltaX;

    if (newMin < s.dataMinX) {
      newMin = s.dataMinX;
      newMax = newMin + span;
    }
    if (newMax > s.dataMaxX) {
      newMax = s.dataMaxX;
      newMin = newMax - span;
    }
    setState(() {
      _viewMinX = newMin;
      _viewMaxX = newMax;
    });
  }

  // Zoom at pixel focal, wheelNotches: negative = zoom in, positive = zoom out
  void _applyZoomAt(_Series s, double focalPx, double wheelNotches) {
    const notchFactor = 0.1;
    final scaleNum = math.pow(1.0 + notchFactor, wheelNotches).toDouble();

    final fullSpan = math.max(1.0, s.dataMaxX - s.dataMinX);
    final oldSpan = _viewMaxX! - _viewMinX!;
    final targetSpan = (oldSpan * scaleNum).clamp(1.0, fullSpan);

    final rel = (_chartWidth <= 0) ? 0.5 : (_clamp(focalPx, 0.0, _chartWidth) / _chartWidth);
    final xAtFocal = _viewMinX! + rel * oldSpan;

    var newMin = xAtFocal - rel * targetSpan;
    var newMax = newMin + targetSpan;

    if (newMin < s.dataMinX) {
      newMin = s.dataMinX;
      newMax = newMin + targetSpan;
    }
    if (newMax > s.dataMaxX) {
      newMax = s.dataMaxX;
      newMin = newMax - targetSpan;
    }
    if (newMax - newMin < 1) {
      final mid = (newMin + newMax) / 2;
      newMin = mid - 0.5;
      newMax = mid + 0.5;
    }
    setState(() {
      _viewMinX = newMin;
      _viewMaxX = newMax;
    });
  }

  @override
  Widget build(BuildContext context) {
    _ensureSeries();
    final s = _series!;

    if (s.sgSpots.isEmpty) {
      return const SizedBox(height: 300, child: Center(child: Text('No measurements yet')));
    }

    _ensureViewportInitialized(s);

// Compute scale for current view
final freshScale = _viewportScale(s, _viewMinX!, _viewMaxX!);

// Fit-once/Locked behavior: keep a captured scale
_ViewportScale vs;
if (_scaleMode == YScaleMode.auto) {
  vs = freshScale;
  _lockedScale = null;
} else {
  _lockedScale ??= freshScale; // capture first fit
  if (_scaleMode == YScaleMode.fitOnce) {
    // Expand only if the new window exceeds the locked range
    _lockedScale = _expandFitOnceIfNeeded(_lockedScale!, freshScale);
  }
  // YScaleMode.locked leaves _lockedScale unchanged
  vs = _lockedScale!;
}


final tempSpotsL = s.xToTemp.entries
    .where((e) => e.key >= _viewMinX! && e.key <= _viewMaxX!)
    .map((e) {
      final y = _mapRightToLeft(vs, e.value);
      return FlSpot(e.key, _clamp(y, vs.sgMin, vs.sgMax));
    })
    .toList();

List<FlSpot> fsuSpotsL = const [];
if (s.xToFsuPtDay.isNotEmpty) {
  final fsuVis = s.xToFsuPtDay.entries
      .where((e) => e.key >= _viewMinX! && e.key <= _viewMaxX!)
      .map((e) => e.value)
      .toList();

  double fMin = fsuVis.isEmpty ? 0.0 : _minOf(fsuVis);
  double fMax = fsuVis.isEmpty ? 1.0 : _maxOf(fsuVis);
  if ((fMax - fMin).abs() < 1e-6) fMax = fMin + 1.0;

  fsuSpotsL = s.xToSg.keys
      .where((xi) => xi >= _viewMinX! && xi <= _viewMaxX!)
      .map((xi) {
        final v = _smoothedFsuAt(s, xi);
        double y = _mapValueRangeToLeft(value: v, vMin: fMin, vMax: fMax, vs: vs);
        y = y.isFinite ? y.clamp(vs.sgMin, vs.sgMax) : vs.sgMin;
        return FlSpot(xi, y);
      })
      .toList();
}

    final xRange = math.max(1.0, _viewMaxX! - _viewMinX!);

    List<double> bottomTickXsForWidth(double chartWidth) {
      if (!widget.showBottomTicks) return const [];
      const minSpacingPx = 56.0;
      final maxTicks = math.max(2, (chartWidth / minSpacingPx).floor());
      final desired = math.min(8, maxTicks);
      if (desired <= 1) return [_viewMinX!, _viewMaxX!];

      final interval = math.max(1.0, xRange / (desired - 1));
final xs = <double>[];
for (double v = _viewMinX!; v <= _viewMaxX! + 0.001; v += interval) {
  // before: xs.add(v.roundToDouble().clamp(_viewMinX!, _viewMaxX!));
  xs.add(_clamp(v.roundToDouble(), _viewMinX!, _viewMaxX!));
}
      final dedup = <double>[];
      for (final v in xs) {
        if (dedup.isEmpty || (v - dedup.last).abs() > 0.01) dedup.add(v);
      }
      return dedup;
    }

    String formatTimeLabel(DateTime t) {
      final spanHours = (s.labelTimes[_viewMaxX!] ?? t)
          .difference(s.labelTimes[_viewMinX!] ?? t)
          .inHours
          .abs();
      if (spanHours <= 36) {
        final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
        final ap = t.hour < 12 ? 'a' : 'p';
        return "$h$ap";
      } else {
        return "${t.month}/${t.day}";
      }
    }

    final visiblePoints =
        s.sgSpots.where((p) => p.x >= _viewMinX! && p.x <= _viewMaxX!).length;
    final showDots = visiblePoints <= 2;
    final dotData = FlDotData(show: showDots);

    // ---- Left-axis tick fix: compute nice ticks and sync grid ----
    final leftTicks = _niceTicks(min: vs.sgMin, max: vs.sgMax, desired: 6);
    final leftInterval =
        leftTicks.length > 1 ? (leftTicks[1] - leftTicks[0]).abs() : 0.010;

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            _chartWidth = constraints.maxWidth > 0 ? constraints.maxWidth : 1;
            final bottomTicks = bottomTickXsForWidth(_chartWidth);

            return Focus(
              autofocus: true,
              onKeyEvent: (node, evt) {
                if (evt.logicalKey == LogicalKeyboardKey.shiftLeft ||
                    evt.logicalKey == LogicalKeyboardKey.shiftRight) {
                  setState(() => _shiftDown = evt is KeyDownEvent);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Listener(
                onPointerSignal: (signal) {
                  if (signal is PointerScrollEvent) {
                    final dy = signal.scrollDelta.dy;
                    final dx = signal.scrollDelta.dx;

                    if (_shiftDown) {
                      final span = (_viewMaxX! - _viewMinX!);
                      final px = (dx.abs() > 0.0001 ? dx : dy);
                      final panDelta = px * (span / _chartWidth) * 0.5;
                      _applyPan(s, panDelta);
                    } else {
                      final notches = dy / 120.0;
                      _applyZoomAt(s, signal.position.dx, notches);
                    }
                  }
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) {
                    final span = (_viewMaxX! - _viewMinX!);
                    final dxX = details.delta.dx * (span / _chartWidth);
                    _applyPan(s, -dxX);
                  },
                  onScaleStart: (details) {
                    _startMinX = _viewMinX!;
                    _startMaxX = _viewMaxX!;
                    _startRange = _startMaxX - _startMinX;
                    final focalPx = details.focalPoint.dx.clamp(0.0, _chartWidth);
                    _xAtFocal = _startMinX + (focalPx / _chartWidth) * _startRange;
                  },
                  onScaleUpdate: (details) {
                    if (details.scale == 1.0) return;
                    final zoomFactor = details.scale;

                    final maxSpan = math.max(1.0, s.dataMaxX - s.dataMinX);
                    final targetRange = _clamp(_startRange / zoomFactor, 1.0, maxSpan);
                    final focalRel = (_xAtFocal - _startMinX) / _startRange;
                    var newMin = _xAtFocal - focalRel * targetRange;
                    var newMax = newMin + targetRange;

                    if (newMin < s.dataMinX) {
                      newMin = s.dataMinX;
                      newMax = newMin + targetRange;
                    }
                    if (newMax > s.dataMaxX) {
                      newMax = s.dataMaxX;
                      newMin = newMax - targetRange;
                    }
                    setState(() {
                      _viewMinX = newMin;
                      _viewMaxX = newMax;
                    });
                  },
                  onDoubleTap: () {
                    setState(() {
                      _lockedScale = _viewportScale(s, _viewMinX!, _viewMaxX!);
                    });
                  },
                  child: SizedBox(
                    height: 300,
                    child: LineChart(
                      LineChartData(
                        clipData: const FlClipData.all(),
                        minX: _viewMinX!,
                        maxX: _viewMaxX!,
                        minY: vs.sgMin,
                        maxY: vs.sgMax,
                        gridData: FlGridData(
                          show: true,
                          horizontalInterval: leftInterval, // sync grid with ticks
                          drawVerticalLine: false,
                        ),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: widget.showBottomTicks,
                              interval: 1,
                              reservedSize: 22,
                              getTitlesWidget: (value, meta) {
                                final near = bottomTicks.any((x) => (x - value).abs() < 0.5);
                                if (!near) return const SizedBox.shrink();
                                final dt = s.labelTimes[value.roundToDouble()];
                                if (dt == null) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    formatTimeLabel(dt),
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            axisNameWidget: const Text(
                              'Specific Gravity',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                            axisNameSize: 20,
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 46,
                              interval: leftInterval, // <- nice interval
                              getTitlesWidget: (value, meta) {
                                // Only draw when we're near one of our computed nice ticks
                                final near = leftTicks.any(
                                  (t) => (t - value).abs() < leftInterval / 5,
                                );
                                // Hide exact min/max to prevent double/clipped labels
                                final isEdge = (value - meta.min).abs() < 1e-6 ||
                                               (meta.max - value).abs() < 1e-6;
                                if (!near || isEdge) return const SizedBox.shrink();
                                return Text(
                                  value.toStringAsFixed(3),
                                  style: const TextStyle(fontSize: 10),
                                );
                              },
                            ),
                          ),
                          rightTitles: AxisTitles(
                            axisNameWidget: Text(
                              vs.rightType == _RightAxis.temperature
                                  ? (widget.useFahrenheit ? 'Temp (°F)' : 'Temp (°C)')
                                  : 'FSU (pt/day)',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                            axisNameSize: 20,
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 48,
                              // positions still expressed in left-space
                              interval: (vs.sgMax - vs.sgMin) / 5.0,
                              getTitlesWidget: (leftCoord, meta) {
                                final leftSpan = (vs.sgMax - vs.sgMin).abs();
                                final safeLeftSpan = leftSpan < 1e-9 ? 1.0 : leftSpan;
                                final rightVal = vs.rightMin +
                                    (vs.rightMax - vs.rightMin) *
                                        ((leftCoord - vs.sgMin) / safeLeftSpan);

                                final threshold = (vs.rightMax - vs.rightMin).abs() / 50.0;
                                final near = vs.rightTicks.any(
                                  (t) => (t - rightVal).abs() < threshold,
                                );
                                final isEdge = (leftCoord - meta.min).abs() < 1e-6 ||
                                               (meta.max - leftCoord).abs() < 1e-6;
                                if (!near || isEdge) return const SizedBox.shrink();

                                if (vs.rightType == _RightAxis.temperature) {
                                  return Text(
                                    widget.useFahrenheit
                                        ? "${rightVal.toStringAsFixed(0)}°F"
                                        : "${rightVal.toStringAsFixed(1)}°C",
                                    style: const TextStyle(fontSize: 10),
                                  );
                                } else {
                                  return Text(
                                    "${rightVal.toStringAsFixed(0)} pt/d",
                                    style: const TextStyle(fontSize: 10),
                                  );
                                }
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: true),
                        lineBarsData: [
                          LineChartBarData(
                            spots: s.sgSpots,
                            isCurved: false,
                            barWidth: 2,
                            color: Colors.blue,
                            dotData: dotData,
                          ),
                          if (tempSpotsL.isNotEmpty)
                            LineChartBarData(
                              spots: tempSpotsL,
                              isCurved: false,
                              barWidth: 2,
                              color: Colors.red,
                              dotData: dotData,
                            ),
                          if (fsuSpotsL.isNotEmpty)
                            LineChartBarData(
                              spots: fsuSpotsL,
                              isCurved: false,
                              barWidth: 2,
                              color: Colors.green,
                              dotData: const FlDotData(show: false),
                            ),
                        ],
                        lineTouchData: LineTouchData(
                          handleBuiltInTouches: true,
                          touchTooltipData: LineTouchTooltipData(
                            fitInsideHorizontally: true,
                            fitInsideVertically: true,
                            tooltipPadding: const EdgeInsets.all(8),
                            getTooltipItems: (spots) {
                              if (spots.isEmpty) return const <LineTooltipItem>[];
                              final xVal = spots.first.x;
                              final sg = s.xToSg[xVal];
                              final tmp = s.xToTemp[xVal];
                              final fsu = _smoothedFsuAt(s, xVal);

                              final buf = StringBuffer();
                              if (sg != null) buf.writeln('SG: ${sg.toStringAsFixed(3)}');
                              if (tmp != null) {
                                buf.writeln(
                                  widget.useFahrenheit
                                      ? 'Temp: ${tmp.toStringAsFixed(1)} °F'
                                      : 'Temp: ${tmp.toStringAsFixed(1)} °C',
                                );
                              }
                              buf.write('FSU: ${fsu.toStringAsFixed(1)} pt/day');

                              return [
                                LineTooltipItem(buf.toString(), const TextStyle(fontSize: 12)),
                                ...List.generate(spots.length - 1, (_) => const LineTooltipItem('', TextStyle())),
                              ];
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        _LegendRow(
          useFahrenheit: widget.useFahrenheit,
          hasTempData: _series?.xToTemp.isNotEmpty ?? false,
          hasFsuData: _series?.xToFsuPtDay.isNotEmpty ?? false,
        ),
        const SizedBox(height: 4),
        // Scale controls: Lock toggle + Fit button + mode menu
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: _scaleMode == YScaleMode.locked ? 'Unlock Y-scale' : 'Lock Y-scale',
              icon: Icon(_scaleMode == YScaleMode.locked ? Icons.lock : Icons.lock_open),
              onPressed: () {
                setState(() {
                  if (_scaleMode == YScaleMode.locked) {
                    _scaleMode = YScaleMode.fitOnce;
                  } else {
                    _lockedScale ??= _viewportScale(_series!, _viewMinX!, _viewMaxX!);
                    _scaleMode = YScaleMode.locked;
                  }
                });
              },
            ),
            IconButton(
              tooltip: 'Fit Y to current view',
              icon: const Icon(Icons.auto_graph),
              onPressed: () {
                setState(() {
                  _lockedScale = _viewportScale(_series!, _viewMinX!, _viewMaxX!);
                  if (_scaleMode == YScaleMode.auto) {
                    _scaleMode = YScaleMode.fitOnce;
                  }
                });
              },
            ),
            PopupMenuButton<YScaleMode>(
              tooltip: 'Y-axis scale mode',
              onSelected: (mode) {
                setState(() {
                  _scaleMode = mode;
                  if (mode == YScaleMode.auto) {
                    _lockedScale = null;
                  } else {
                    _lockedScale ??= _viewportScale(_series!, _viewMinX!, _viewMaxX!);
                  }
                });
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: YScaleMode.auto, child: Text('Auto (dynamic)')),
                PopupMenuItem(value: YScaleMode.fitOnce, child: Text('Fit once (stable)')),
                PopupMenuItem(value: YScaleMode.locked, child: Text('Locked')),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                child: Icon(Icons.tune),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.useFahrenheit,
    required this.hasTempData,
    required this.hasFsuData,
  });

  final bool hasFsuData;
  final bool hasTempData;
  final bool useFahrenheit;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        const _LegendDot(color: Colors.blue, label: 'SG'),
        if (hasTempData)
          _LegendDot(color: Colors.red, label: useFahrenheit ? 'Temp (°F)' : 'Temp (°C)'),
        if (hasFsuData)
          const _LegendDot(color: Colors.green, label: 'FSU (pt/day)'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

/// --------- Range + Chart Panel ----------
class SimpleFermentationChartPanel extends StatefulWidget {
  const SimpleFermentationChartPanel({
    super.key,
    required this.measurements,
    required this.useFahrenheit,
    this.sincePitchingAt,
    this.initialRange = ChartRange.d7,
    this.onRangeChanged,
  });

  final ChartRange initialRange;
  final List<Measurement> measurements;
  final ValueChanged<ChartRange>? onRangeChanged;
  final DateTime? sincePitchingAt; // optional
  final bool useFahrenheit;

  @override
  State<SimpleFermentationChartPanel> createState() => _SFCPanelState();
}

class _SFCPanelState extends State<SimpleFermentationChartPanel> {
  late ChartRange _range;

  @override
  void initState() {
    super.initState();
    _range = widget.initialRange;
  }

  void _setChartRange(ChartRange r) {
    if (_range == r) return;
    setState(() => _range = r);
    widget.onRangeChanged?.call(r);
  }

  _VisibleRange _calculateVisibleRange() {
    if (widget.measurements.isEmpty) return _VisibleRange(null, null);

    final now = DateTime.now();
    late final DateTime start;
    late final DateTime end;

    switch (_range) {
      case ChartRange.h24:
        start = now.subtract(const Duration(hours: 24));
        end = now;
        break;
      case ChartRange.d3:
        start = now.subtract(const Duration(days: 3));
        end = now;
        break;
      case ChartRange.d7:
        start = now.subtract(const Duration(days: 7));
        end = now;
        break;
      case ChartRange.d30:
        start = now.subtract(const Duration(days: 30));
        end = now;
        break;
      case ChartRange.sincePitch:
        start = widget.sincePitchingAt ??
            widget.measurements.map((m) => m.timestamp).reduce((a, b) => a.isBefore(b) ? a : b);
        end = now;
        break;
    }
    return _VisibleRange(start, end);
  }

  Widget _chip(ChartRange r, String label) {
    final selected = _range == r;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _setChartRange(r),
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleRange = _calculateVisibleRange();

    // Animated switch on range change
    final switcherKey = ValueKey<String>(
      'range=${_range.name}|start=${visibleRange.start?.millisecondsSinceEpoch}|end=${visibleRange.end?.millisecondsSinceEpoch}|F=${widget.useFahrenheit}|len=${widget.measurements.length}',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            _chip(ChartRange.h24, '24h'),
            _chip(ChartRange.d3, '3d'),
            _chip(ChartRange.d7, '7d'),
            _chip(ChartRange.d30, '30d'),
            if (widget.measurements.isNotEmpty || widget.sincePitchingAt != null)
              _chip(ChartRange.sincePitch, 'Since pitching'),
          ],
        ),
        const SizedBox(height: 8),

        // ---------- AnimatedSwitcher ----------
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0.02, 0), end: Offset.zero).animate(anim),
              child: child,
            ),
          ),
          child: SimpleFermentationChart(
            key: switcherKey,
            measurements: widget.measurements,
            useFahrenheit: widget.useFahrenheit,
            showBottomTicks: true,
            visibleRangeStart: visibleRange.start,
            visibleRangeEnd: visibleRange.end,
          ),
        ),
      ],
    );
  }
}

class _VisibleRange {
  _VisibleRange(this.start, this.end);
  final DateTime? start;
  final DateTime? end;
}
