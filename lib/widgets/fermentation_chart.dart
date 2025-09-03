// lib/widgets/fermentation_chart.dart
import 'dart:math';
// for FontFeature in _tooltip

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/measurement.dart';
import '../models/fermentation_stage.dart';
import '../models/settings_model.dart';

/// Resolution options for bucketing raw samples.
enum BucketMode { none, keep15m, avgHourly, avgDaily }

/// Fermentation line chart with zoom/pan, crosshair + tooltip, stage bands,
/// dual right axis (SG / FSU) normalized into the left-axis domain, and
/// bucketing controls.
class FermentationChartWidget extends StatefulWidget {
  final List<Measurement> measurements;
  final List<FermentationStage> stages;
  final void Function(Measurement)? onEditMeasurement;
  final void Function(Measurement)? onDeleteMeasurement;
  final VoidCallback? onManageStages;
  final BucketMode bucketMode;

  const FermentationChartWidget({
    super.key,
    required this.measurements,
    required this.stages,
    this.onEditMeasurement,
    this.onDeleteMeasurement,
    this.onManageStages,
    this.bucketMode = BucketMode.avgHourly,
  });

  @override
  State<FermentationChartWidget> createState() =>
      _FermentationChartWidgetState();
}

/// Paints translucent stage bands inside the plot box.
class _StageBandsPainter extends CustomPainter {
  _StageBandsPainter({
    required this.stages,
    required this.start,
    required this.minX,
    required this.maxX,
    required this.colors,
  });

  final List<FermentationStage> stages;
  final DateTime start;
  final double minX, maxX;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (maxX <= minX) return;
    final w = size.width, h = size.height;
    double mapX(double x) => ((x - minX) / (maxX - minX)).clamp(0.0, 1.0) * w;

    for (var i = 0; i < stages.length; i++) {
      final s = stages[i];
      if (s.startDate == null) continue;

      final fromH = s.startDate!.difference(start).inHours.toDouble();
      final toH = fromH + s.durationDays * 24.0;

      final x1 = mapX(fromH);
      final x2 = mapX(toH);
      if (x2 <= 0 || x1 >= w) continue;

      final paint = Paint()..color = colors[i % colors.length].withOpacity(.18);
      canvas.drawRect(Rect.fromLTRB(x1, 0, x2, h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StageBandsPainter old) =>
      old.stages != stages || old.minX != minX || old.maxX != maxX;
}

class _FermentationChartWidgetState extends State<FermentationChartWidget> {
  // Outer padding for the plot area (inside the widget).
  static const double leftPad = 8; // tiny; label width is reserved in titles
  static const double rightPad = 8;
  static const double topPad = 8;
  static const double bottomPad = 30;

  final FocusNode _focusNode = FocusNode();
  bool _shiftDown = false;
  bool _bootstrapped = false;

  // Always-visible Manage Stages button below the header
  Widget _manageStagesButton() {
    if (widget.onManageStages == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: widget.onManageStages,
        icon: const Icon(Icons.edit, size: 16),
        label: const Text('Manage Stages'),
      ),
    );
  }

  double _initialSpanFor(double totalH) {
    if (totalH >= 24 * 7) return 24 * 7;
    if (totalH >= 24) return 24;
    if (totalH >= 6) return 6;
    if (totalH >= 1) return totalH;
    return 1;
  }

  // UI state
  late BucketMode mode;
  double? touchedX;
  Offset? touchPos;

  bool _showTemp = true;
  bool _showSG = true;
  bool _showFSU = true;

  // time domain
  DateTime domainStart = DateTime.now(); // default; real value set when data >= 2
  double totalHours = 1;

  // view window
  double viewStartH = 0;
  double viewSpanH = 24 * 7;

  @override
  void initState() {
    super.initState();
    mode = widget.bucketMode;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  // --------------- Utilities ----------------

  double _measureTextWidth(BuildContext context, String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    return tp.width;
  }

  String _fmtLeftTemp(num v) => v.toStringAsFixed(0);

  int bucketMinutes(BucketMode m) {
    switch (m) {
      case BucketMode.keep15m:
        return 15;
      case BucketMode.avgHourly:
        return 60;
      case BucketMode.avgDaily:
        return 60 * 24;
      case BucketMode.none:
        return 0;
    }
  }

  List<Measurement> bucketize(List<Measurement> items) {
    final m = mode;
    if (m == BucketMode.none || items.length < 3) return items;

    final stepMin = bucketMinutes(m);
    if (stepMin <= 0) return items;

    final Map<int, List<Measurement>> groups = {};
    final stepMs = stepMin * 60 * 1000;

    // Align buckets to *local* wall-clock boundaries (not UTC).
    final tzOffsetMs = items.isNotEmpty
        ? items.first.timestamp.timeZoneOffset.inMilliseconds
        : DateTime.now().timeZoneOffset.inMilliseconds;

    int bucketStartMs(int ms) =>
        ((ms + tzOffsetMs) ~/ stepMs) * stepMs - tzOffsetMs;

    for (final meas in items) {
      final ms = meas.timestamp.millisecondsSinceEpoch;
      final k = bucketStartMs(ms);
      (groups[k] ??= <Measurement>[]).add(meas);
    }

    final keys = groups.keys.toList()..sort();
    final out = <Measurement>[];

    for (final k in keys) {
      final g = groups[k]!;
      if (m == BucketMode.keep15m) {
        g.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        final pick =
            g.firstWhere((x) => x.fromDevice != true, orElse: () => g.first);
        out.add(pick);
      } else {
        double? avg(num? Function(Measurement) sel) {
          final vals =
              g.map(sel).whereType<num>().map((e) => e.toDouble()).toList();
          if (vals.isEmpty) return null;
          return vals.reduce((a, b) => a + b) / vals.length;
        }

        final mid = k + stepMs ~/ 2; // midpoint of the *local-aligned* bucket
        out.add(Measurement(
          id: null,
          timestamp: DateTime.fromMillisecondsSinceEpoch(mid),
          gravity: avg((m) => m.sgCorrected ?? m.gravity),
          brix: avg((m) => m.brix),
          temperature: avg((m) => m.temperature),
          fsuspeed: avg((m) => m.fsuspeed),
          fromDevice: g.every((x) => x.fromDevice == true),
          notes: null,
        ));
      }
    }
    return out;
  }

  ({double min, double max, double step}) niceAxis({
    required double rawMin,
    required double rawMax,
    required int targetTickCount,
    double? clampMin,
    double? clampMax,
  }) {
    final range = niceNum((rawMax - rawMin).abs(), round: false);
    double step = niceNum(range / (targetTickCount - 1), round: true);
    double minV = (rawMin / step).floor() * step;
    double maxV = (rawMax / step).ceil() * step;
    if (clampMin != null && minV < clampMin) minV = clampMin;
    if (clampMax != null && maxV > clampMax) maxV = clampMax;
    return (min: minV, max: maxV, step: step);
  }

  double niceNum(double x, {required bool round}) {
    if (x == 0) return 0;
    final exponent = (log(x) / ln10).floor();
    final fraction = x / pow(10.0, exponent);
    double nf;
    if (round) {
      if (fraction < 1.5) {
        nf = 1;
      } else if (fraction < 3) {
        nf = 2;
      } else if (fraction < 7) {
        nf = 5;
      } else {
        nf = 10;
      }
    } else {
      if (fraction <= 1) {
        nf = 1;
      } else if (fraction <= 2) {
        nf = 2;
      } else if (fraction <= 5) {
        nf = 5;
      } else {
        nf = 10;
      }
    }
    return nf * pow(10.0, exponent);
  }

  double normalize(double v, double vMin, double vMax, double sMin, double sMax) {
    if ((vMax - vMin).abs() < 1e-9) return sMin;
    return sMin + ((v - vMin) * (sMax - sMin) / (vMax - vMin));
  }

  double denormalize(
      double nv, double vMin, double vMax, double sMin, double sMax) {
    if ((sMax - sMin).abs() < 1e-9) return vMin;
    return vMin + ((nv - sMin) * (vMax - vMin) / (sMax - sMin));
  }

  double? interp(List<FlSpot> spots, double x) {
    if (spots.isEmpty || x < spots.first.x || x > spots.last.x) return null;
    for (int i = 0; i < spots.length - 1; i++) {
      final a = spots[i];
      final b = spots[i + 1];
      if (a.x <= x && b.x >= x) {
        final t = (x - a.x) / max(1e-9, (b.x - a.x));
        return a.y + (b.y - a.y) * t;
      }
    }
    return spots.last.y;
  }

  /// Monotone Hermite sampling -> polyline.
  List<FlSpot> monotonePolyline(
    List<FlSpot> src, {
    double samplesPerHour = 2.0,
    int maxPoints = 1200,
  }) {
    if (src.length <= 2) return src;
    final spots = [...src]..sort((a, b) => a.x.compareTo(b.x));
    final n = spots.length;
    final out = <FlSpot>[];
    final xs = List<double>.generate(n, (i) => spots[i].x);
    final ys = List<double>.generate(n, (i) => spots[i].y);
    final delta = List<double>.filled(n - 1, 0);
    final m = List<double>.filled(n, 0);

    for (int i = 0; i < n - 1; i++) {
      final dx = xs[i + 1] - xs[i];
      delta[i] = dx == 0 ? 0 : (ys[i + 1] - ys[i]) / dx;
    }
    m[0] = delta[0];
    for (int i = 1; i < n - 1; i++) {
      m[i] = (delta[i - 1] + delta[i]) / 2;
    }
    m[n - 1] = delta[n - 2];
    for (int i = 0; i < n - 1; i++) {
      if (delta[i] == 0) {
        m[i] = 0;
        m[i + 1] = 0;
      } else {
        final a = m[i] / delta[i];
        final b = m[i + 1] / delta[i];
        final s = a * a + b * b;
        if (s > 9) {
          final t = 3 / sqrt(s);
          m[i] = t * a * delta[i];
          m[i + 1] = t * b * delta[i];
        }
      }
    }

    double estimateTotalSamples() {
      double total = 0;
      for (int i = 0; i < n - 1; i++) {
        total += (xs[i + 1] - xs[i]).abs() * samplesPerHour;
      }
      return total;
    }

    double spH = samplesPerHour;
    while (estimateTotalSamples() > maxPoints && spH > 0.5) {
      spH *= 0.75;
    }

    for (int i = 0; i < n - 1; i++) {
      final x0 = xs[i], x1 = xs[i + 1];
      final y0 = ys[i], y1 = ys[i + 1];
      final dx = x1 - x0;
      final t0 = m[i];
      final t1 = m[i + 1];

      if ((y0 - y1).abs() < 1e-9) {
        if (out.isEmpty || out.last.x != x0) out.add(FlSpot(x0, y0));
        out.add(FlSpot(x1, y1));
      } else {
        final steps = max(2, (dx.abs() * spH).round());
        for (int k = 0; k < steps; k++) {
          final t = k / (steps - 1);
          final h00 = (2 * t * t * t) - (3 * t * t) + 1;
          final h10 = (t * t * t) - (2 * t * t) + t;
          final h01 = (-2 * t * t * t) + (3 * t * t);
          final h11 = (t * t * t) - (t * t);

          final x = x0 + t * dx;
          final y = h00 * y0 + h10 * dx * t0 + h01 * y1 + h11 * dx * t1;

          if (!(k == 0 && i > 0)) out.add(FlSpot(x, y));
        }
      }
    }
    return out;
  }

  // ---------- View helpers ----------
  void clampView() {
    if (viewSpanH < 1) viewSpanH = 1;
    if (viewSpanH > totalHours) viewSpanH = totalHours;
    if (viewStartH < 0) viewStartH = 0;
    if (viewStartH + viewSpanH > totalHours) {
      viewStartH = max(0, totalHours - viewSpanH);
    }
  }

  void zoomAroundCursor({
    required double dy,
    required double cursorDx,
    required double plotWidth,
  }) {
    if (plotWidth <= 0 || totalHours <= 0) return;
    final rel = ((cursorDx - leftPad) / plotWidth).clamp(0.0, 1.0);
    final focusH = viewStartH + rel * viewSpanH;

    final factor = pow(1.0 + 0.12, -dy.sign);
    final newSpan = (viewSpanH * factor).clamp(1.0, totalHours);
    viewStartH =
        (focusH - rel * newSpan).clamp(0.0, max(0.0, totalHours - newSpan));
    viewSpanH = newSpan;
    clampView();
    setState(() {});
  }

  void panByPixels(double dx, double plotWidth) {
    if (plotWidth <= 0 || totalHours <= 0) return;
    final hoursPerPixel = viewSpanH / plotWidth;
    viewStartH -= dx * hoursPerPixel;
    clampView();
    setState(() {});
  }

  /// Smarter x-interval: choose the smallest “nice” step >= target step.
  /// Prevents 1h labels at 24h span on small plots (uses 3h/4h/etc instead).
  double xIntervalFor(double spanHours, double plotWidth) {
    final approxLabels = max(6.0, (plotWidth / 100).floorToDouble());
    final targetStep = spanHours / approxLabels; // hours per label
    const allowed = <double>[1, 2, 3, 4, 6, 8, 12, 24, 48, 72, 96];
    for (final s in allowed) {
      if (s >= targetStep) return s;
    }
    return allowed.last;
  }

  String hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String md(DateTime d) => '${d.month}/${d.day}';

  // ---------------- Build ----------------
  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.measurements]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final data = bucketize(sorted);

    if (data.length < 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _headerBar(),
          const SizedBox(height: 6),
          _manageStagesButton(),
          const SizedBox(height: 12),
          SizedBox(
            height: 350,
            child: Center(
              child: Text(
                'Add another measurement to see the graph.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          ),
        ],
      );
    }

    domainStart = data.first.timestamp;
    totalHours =
        max(1.0, data.last.timestamp.difference(domainStart).inHours.toDouble());

    if (!_bootstrapped) {
      viewSpanH = _initialSpanFor(totalHours).clamp(1.0, totalHours);
      viewStartH = max(0, totalHours - viewSpanH);
      _bootstrapped = true;
    } else {
      if (viewSpanH > totalHours) {
        viewSpanH = totalHours;
        viewStartH = 0;
      }
    }

    clampView();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _headerBar(),
        const SizedBox(height: 6),
        _manageStagesButton(),
        const SizedBox(height: 12),
        _chartArea(data),
      ],
    );
  }

  Widget _headerBar() {
    // Only show the date range once we actually have a range
    final hasRange = widget.measurements.length >= 2;

    DateTime? visibleStart, visibleEnd;
    if (hasRange) {
      visibleStart = domainStart.add(Duration(hours: viewStartH.round()));
      visibleEnd =
          domainStart.add(Duration(hours: (viewStartH + viewSpanH).round()));
    }

    Widget trailingControls() {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ToggleButtons(
            isSelected: [
              viewSpanH == 1,
              viewSpanH == 6,
              viewSpanH == 24,
              viewSpanH == 24 * 7,
              viewSpanH == 24 * 30,
            ],
            borderRadius: BorderRadius.circular(10),
            constraints: const BoxConstraints(minHeight: 34, minWidth: 56),
            onPressed: (i) {
              final preset = <double>[1, 6, 24, 24 * 7, 24 * 30][i];
              setState(() {
                viewSpanH = preset.clamp(1.0, totalHours);
                viewStartH = max(0, totalHours - viewSpanH);
              });
            },
            children: const [Text('1h'), Text('6h'), Text('24h'), Text('7d'), Text('30d')],
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Fit to data',
            icon: const Icon(Icons.fullscreen_exit),
            onPressed: () => setState(() {
              viewStartH = 0;
              viewSpanH = totalHours;
            }),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<BucketMode>(
            tooltip: 'Resolution',
            onSelected: (v) => setState(() => mode = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: BucketMode.keep15m, child: Text('Keep 15m')),
              PopupMenuItem(value: BucketMode.avgHourly, child: Text('Avg hourly')),
              PopupMenuItem(value: BucketMode.avgDaily, child: Text('Avg daily')),
              PopupMenuItem(value: BucketMode.none, child: Text('Raw')),
            ],
            child: Row(
              children: [
                const Icon(Icons.tune, size: 18),
                const SizedBox(width: 6),
                Text(
                  switch (mode) {
                    BucketMode.keep15m => 'Keep 15m',
                    BucketMode.avgHourly => 'Avg hourly',
                    BucketMode.avgDaily => 'Avg daily',
                    BucketMode.none => 'Raw',
                  },
                  style: const TextStyle(fontSize: 13),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(builder: (context, cons) {
      final isNarrow = cons.maxWidth < 560;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isNarrow)
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Fermentation Chart',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: trailingControls(),
                  ),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Fermentation Chart',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: trailingControls(),
                ),
              ],
            ),
          const SizedBox(height: 8),
          if (hasRange)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${md(visibleStart!)} ${hhmm(visibleStart)}  →  ${md(visibleEnd!)} ${hhmm(visibleEnd)} · span ${viewSpanH.round()}h',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ),
        ],
      );
    });
  }

  Widget _chartArea(List<Measurement> points) {
    final settings = context.watch<SettingsModel>();
    final isF = settings.unit.contains('F');

    // Collect raw stats
    final temps = <double>[];
    final sgVals = <double>[];
    final fsuVals = <double>[];
    for (final m in points) {
      final t = m.temperature;
      if (t != null) temps.add(isF ? (t * 9 / 5) + 32 : t);
      final sg = m.sgCorrected ?? m.gravity;
      if (sg != null) sgVals.add(sg);
      final f = m.fsuspeed;
      if (f != null) fsuVals.add(f);
    }

    // Left (Temp) nice axis (we’ll override to interval = 2 later)
    final tNice = niceAxis(
      rawMin: temps.isEmpty ? (isF ? 60.0 : 15.0) : temps.reduce(min),
      rawMax: temps.isEmpty ? (isF ? 80.0 : 27.0) : temps.reduce(max),
      targetTickCount: 5,
    );

    // Right SG range
    final sgMin = sgVals.isEmpty ? 1.000 : sgVals.reduce(min);
    final sgMax = sgVals.isEmpty ? 1.060 : sgVals.reduce(max);
    const sgStep = 0.002; // for dense tick mode
    final sgMinNice = (sgMin / sgStep).floor() * sgStep;
    final sgMaxNice = (sgMax / sgStep).ceil() * sgStep;

    // Right FSU nice
    final fNice = niceAxis(
      rawMin: fsuVals.isEmpty ? 0.0 : fsuVals.reduce(min),
      rawMax: fsuVals.isEmpty ? 100.0 : fsuVals.reduce(max),
      targetTickCount: 5,
    );

    final yMin = tNice.min;
    final yMax = tNice.max;
    final yMid = yMin + (yMax - yMin) / 2;

    // Build domain spots (x in hours from domainStart)
    final tempSpots = <FlSpot>[];
    final gravSpotsRaw = <FlSpot>[];
    final fsuSpotsRaw = <FlSpot>[];
    final gravMs = <Measurement>[];

    for (final m in points) {
      final x = m.timestamp.difference(domainStart).inHours.toDouble();
      final t = m.temperature;
      if (t != null) tempSpots.add(FlSpot(x, isF ? (t * 9 / 5) + 32 : t));
      final sg = m.sgCorrected ?? m.gravity;
      if (sg != null) {
        gravSpotsRaw
            .add(FlSpot(x, normalize(sg, sgMinNice, sgMaxNice, yMin, yMid)));
        gravMs.add(m);
      }
      final f = m.fsuspeed;
      if (f != null) {
        fsuSpotsRaw.add(FlSpot(x, normalize(f, fNice.min, fNice.max, yMid, yMax)));
      }
    }

    // Smooth series (monotone) but draw as polylines
    final tempSpotsMono = monotonePolyline(tempSpots, samplesPerHour: 1.2);
    final gravSpots = monotonePolyline(gravSpotsRaw, samplesPerHour: 2.0);
    final fsuSpots = monotonePolyline(fsuSpotsRaw, samplesPerHour: 2.0);

    // Dynamic reserved sizes (tight gutters)
    final textStyle =
        Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 12);

    // Left examples based on current range (~2-digit temps)
    final exampleLefts = [_fmtLeftTemp(yMin), _fmtLeftTemp(yMax)];
    final maxLeftW = exampleLefts
        .map((s) => _measureTextWidth(context, s, textStyle))
        .fold<double>(0, (a, b) => a > b ? a : b);
    final leftReserved = max(34.0, maxLeftW + 14);

    // Right examples (SG & FSU)
    final exampleRights = ['1.010', '1.024', '150'];
    final maxRightW = exampleRights
        .map((s) => _measureTextWidth(context, s, textStyle))
        .fold<double>(0, (a, b) => a > b ? a : b);
    final rightReserved = max(42.0, maxRightW + 16);

    final List<LineChartBarData> seriesData = [];
    if (_showTemp) {
      seriesData.add(_series(
        tempSpotsMono,
        Colors.blueAccent,
        curved: false,
        dots: (viewSpanH <= 72) ? null : const FlDotData(show: false),
      ));
    }
    if (_showSG) {
      seriesData.add(_series(
        gravSpots,
        Colors.green,
        curved: false,
        dots:
            (viewSpanH <= 72) ? _gravityDots(gravSpotsRaw, gravMs) : const FlDotData(show: false),
      ));
    }
    if (_showFSU) {
      seriesData.add(_series(
        fsuSpots,
        Colors.purple,
        curved: false,
        dots: (viewSpanH <= 72) ? null : const FlDotData(show: false),
      ));
    }

    return Column(
      children: [
        SizedBox(
          height: 380,
          child: LayoutBuilder(builder: (context, cons) {
            final plotWidth = cons.maxWidth - leftPad - rightPad;
            final minX = viewStartH;
            final maxX = (viewStartH + viewSpanH).clamp(minX + 1, totalHours);
            final xInt = xIntervalFor(viewSpanH, plotWidth);

            return RawKeyboardListener(
              focusNode: _focusNode,
              onKey: (e) {
                final isDown = e is RawKeyDownEvent;
                if (e.logicalKey == LogicalKeyboardKey.shiftLeft ||
                    e.logicalKey == LogicalKeyboardKey.shiftRight) {
                  _shiftDown = isDown;
                }
                if (isDown && e.logicalKey == LogicalKeyboardKey.home) {
                  setState(() => viewStartH = 0);
                }
                if (isDown && e.logicalKey == LogicalKeyboardKey.end) {
                  setState(() => viewStartH = max(0, totalHours - viewSpanH));
                }
              },
              child: Listener(
                onPointerSignal: (PointerSignalEvent e) {
                  if (e is PointerScrollEvent) {
                    if (_shiftDown) {
                      panByPixels(e.scrollDelta.dy * 8, plotWidth);
                    } else {
                      zoomAroundCursor(
                        dy: e.scrollDelta.dy,
                        cursorDx: e.localPosition.dx,
                        plotWidth: plotWidth,
                      );
                    }
                  }
                },
                onPointerHover: (e) =>
                    _setCrosshairDx(e.localPosition.dx, plotWidth, minX, maxX),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: (d) => panByPixels(d.delta.dx, plotWidth),
                  onDoubleTapDown: (d) {
                    final rel =
                        ((d.localPosition.dx - leftPad) / plotWidth).clamp(0.0, 1.0);
                    final focusH = viewStartH + rel * viewSpanH;
                    setState(() {
                      viewSpanH = max(1.0, viewSpanH / 2);
                      viewStartH = (focusH - rel * viewSpanH)
                          .clamp(0.0, max(0.0, totalHours - viewSpanH));
                    });
                  },
                  onLongPressStart: (d) =>
                      _setCrosshairDx(d.localPosition.dx, plotWidth, minX, maxX),
                  onLongPressMoveUpdate: (d) =>
                      _setCrosshairDx(d.localPosition.dx, plotWidth, minX, maxX),
                  onLongPressEnd: (_) => _clearCrosshair(),
                  onTapUp: (d) {
                    if (widget.onEditMeasurement == null) return;
                    final rel =
                        ((d.localPosition.dx - leftPad).clamp(0, plotWidth)) / plotWidth;
                    final tapX = minX + rel * (maxX - minX);
                    Measurement? closest;
                    double best = double.infinity;
                    for (final m in points) {
                      final mx = m.timestamp.difference(domainStart).inHours.toDouble();
                      final dist = (mx - tapX).abs();
                      if (dist < best) {
                        best = dist;
                        closest = m;
                      }
                    }
                    if (best < 12 && closest != null) {
                      widget.onEditMeasurement!(closest);
                    }
                    _clearCrosshair();
                  },
                  child: Stack(
                    children: [
                      // Stage bands inside plot box
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                              leftPad, topPad, rightPad, bottomPad),
                          child: ClipRect(
                            child: CustomPaint(
                              painter: _StageBandsPainter(
                                stages: widget.stages,
                                start: domainStart,
                                minX: minX,
                                maxX: maxX,
                                colors: const [
                                  Colors.orange,
                                  Colors.blue,
                                  Colors.green,
                                  Colors.purple,
                                  Colors.pink,
                                  Colors.teal,
                                  Colors.yellow,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Chart
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                              leftPad, topPad, rightPad, bottomPad),
                          child: LineChart(
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.linear,
                            LineChartData(
                              minX: minX,
                              maxX: maxX,
                              minY: yMin,
                              maxY: yMax,
                              clipData: const FlClipData.all(),
                              lineTouchData: const LineTouchData(enabled: false),
                              gridData: FlGridData(
                                show: true,
                                drawVerticalLine: true,
                                getDrawingHorizontalLine: (_) =>
                                    FlLine(color: Colors.grey.withAlpha(50), strokeWidth: 1),
                                getDrawingVerticalLine: (_) =>
                                    FlLine(color: Colors.grey.withAlpha(50), strokeWidth: 1),
                              ),
                              borderData: FlBorderData(
                                show: true,
                                border: Border.all(color: Colors.grey.shade400),
                              ),
                              titlesData: _titles(
                                context: context,
                                start: domainStart,
                                leftMin: yMin,
                                leftMax: yMax,
                                midY: yMid,
                                sgMin: sgMinNice,
                                sgMax: sgMaxNice,
                                fsuMin: fNice.min,
                                fsuMax: fNice.max,
                                xIntervalHours: xInt,
                                spanHours: viewSpanH,
                                leftReserved: leftReserved.toDouble(),
                                rightReserved: rightReserved.toDouble(),
                                tempTickEvery: 2,
                                showSgTicks: _showSG,
                                showFsuTicks: !_showSG && _showFSU,
                                xMinHours: minX,
                                xMaxHours: maxX,
                              ),
                              lineBarsData: seriesData,
                            ),
                          ),
                        ),
                      ),
                      // Stage labels + crosshair/tooltip overlays
                      _stageLabels(
                        stages: widget.stages,
                        start: domainStart,
                        minX: minX,
                        maxX: maxX,
                        plotWidth: plotWidth,
                      ),
                      IgnorePointer(
                        child: Stack(
                          children: [
                            if (touchedX != null && touchPos != null)
                              Positioned(
                                left: touchPos!.dx.clamp(leftPad, leftPad + plotWidth),
                                top: 0,
                                bottom: bottomPad,
                                child: Container(
                                  width: 1.5,
                                  color: Colors.redAccent.withAlpha(160),
                                ),
                              ),
                            if (touchedX != null && touchPos != null)
                              Positioned(
                                left: (touchPos!.dx > (leftPad + plotWidth / 2))
                                    ? null
                                    : (touchPos!.dx + 10),
                                right: (touchPos!.dx > (leftPad + plotWidth / 2))
                                    ? (leftPad + plotWidth - touchPos!.dx + 10)
                                    : null,
                                top: 8,
                                child: _tooltip(
                                  start: domainStart,
                                  xHour: touchedX!,
                                  tempSpots: tempSpotsMono,
                                  gravSpots: gravSpots,
                                  fsuSpots: fsuSpots,
                                  leftMin: yMin,
                                  leftMax: yMax,
                                  midY: yMid,
                                  sgMin: sgMinNice,
                                  sgMax: sgMaxNice,
                                  fsuMin: fNice.min,
                                  fsuMax: fNice.max,
                                  isF: isF,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _legend(
            isF: isF,
            hasTemp: temps.isNotEmpty,
            hasSG: sgVals.isNotEmpty,
            hasFSU: fsuVals.isNotEmpty,
          ),
        ),
      ],
    );
  }

  // crosshair helpers
  void _setCrosshairDx(
      double localDx, double plotWidth, double minX, double maxX) {
    final dx = localDx.clamp(leftPad, leftPad + plotWidth).toDouble();
    final rel = (dx - leftPad) / plotWidth;
    setState(() {
      touchPos = Offset(dx, 0);
      touchedX = minX + rel * (maxX - minX);
    });
  }

  void _clearCrosshair() {
    setState(() {
      touchedX = null;
      touchPos = null;
    });
  }

  // ---------------- Series & dots ----------------
  LineChartBarData _series(
    List<FlSpot> spots,
    Color color, {
    required bool curved,
    FlDotData? dots,
  }) {
    return LineChartBarData(
      spots: spots.where((s) => s.y.isFinite).toList(),
      isCurved: curved,
      barWidth: 2.5,
      color: color,
      dotData: dots ??
          FlDotData(
            show: true,
            getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
              radius: 3,
              color: color,
              strokeWidth: 1.5,
              strokeColor: Colors.white,
            ),
          ),
    );
  }

  FlDotData _gravityDots(List<FlSpot> rawGravSpots, List<Measurement> ms) {
    return FlDotData(
      show: true,
      checkToShowDot: (spot, barData) {
        const eps = 1e-6;
        final isRaw = rawGravSpots.any((p) => (p.x - spot.x).abs() < eps);
        if (!isRaw) return false;
        final idx =
            rawGravSpots.indexWhere((p) => (p.x - spot.x).abs() < eps);
        if (idx < 0 || idx >= ms.length) return true;
        final m = ms[idx];
        final hasInterventions =
            (m.interventions != null && m.interventions!.isNotEmpty);
        return (m.fromDevice != true) || hasInterventions;
      },
      getDotPainter: (spot, _, __, ___) {
        const eps = 1e-6;
        final idx =
            rawGravSpots.indexWhere((p) => (p.x - spot.x).abs() < eps);
        if (idx < 0 || idx >= ms.length) {
          return FlDotCirclePainter(
              radius: 3,
              color: Colors.green,
              strokeWidth: 1.5,
              strokeColor: Colors.white);
        }
        final m = ms[idx];
        final hasInterventions =
            (m.interventions != null && m.interventions!.isNotEmpty);
        if (m.fromDevice == true) {
          return FlDotCirclePainter(
              radius: 2,
              color: Colors.green.shade900,
              strokeWidth: 0,
              strokeColor: Colors.transparent);
        }
        if (hasInterventions) {
          return FlDotCirclePainter(
              radius: 6,
              color: Colors.orange.shade700,
              strokeWidth: 2,
              strokeColor: Colors.white);
        }
        return FlDotCirclePainter(
            radius: 3,
            color: Colors.green,
            strokeWidth: 1.5,
            strokeColor: Colors.white);
      },
    );
  }

  FlTitlesData _titles({
    required BuildContext context,
    required DateTime start,
    required double leftMin,
    required double leftMax,
    required double midY,
    required double sgMin,
    required double sgMax,
    required double fsuMin,
    required double fsuMax,
    required double xIntervalHours,
    required double spanHours,
    required double leftReserved,
    required double rightReserved,
    required int tempTickEvery,
    required bool showSgTicks,
    required bool showFsuTicks,
    required double xMinHours, // viewStartH
    required double xMaxHours, // viewStartH + viewSpanH
  }) {
    final labelStyle =
        Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 12);

    // ---------- BOTTOM (time) ----------
    bool alignedToStep(double value, double step, double origin,
        [double eps = 1e-3]) {
      final r = (value - origin) / step;
      return (r - r.round()).abs() <= eps;
    }

    String fmtTimeTick(DateTime dt, double span) {
      // <= 8h → "HH:mm"
      if (span <= 8) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      // <= 36h → midnight gets "M/D\nHH", others just "HH"
      if (span <= 36) {
        final hh = dt.hour.toString().padLeft(2, '0');
        if (dt.hour == 0) {
          return '${dt.month}/${dt.day}\n$hh';
        }
        return hh;
      }
      // > 36h → "M/D"
      return '${dt.month}/${dt.day}';
    }

    Widget bottomBuilder(double value, TitleMeta meta) {
      const double xEps = 1e-3;
      if (!alignedToStep(value, xIntervalHours, xMinHours, xEps)) {
        return const SizedBox.shrink();
      }
      final dt = start.add(Duration(hours: value.round()));
      return SideTitleWidget(
        meta: meta,                // <-- change this line
        space: 8,
        child: Text(
          fmtTimeTick(dt, spanHours),
          style: labelStyle,
          textAlign: TextAlign.center,
        ),
      );
    }

    // ---------- LEFT (Temp) ----------
    final double leftInterval = tempTickEvery.toDouble(); // e.g., 2°

    // ---------- RIGHT (SG / FSU) ----------
    Widget rightBuilder(double value, TitleMeta meta) {
      bool near(double a, double b, [double eps = 1e-6]) => (a - b).abs() < eps;
      final wideSpan = spanHours >= 24;

      if (showSgTicks) {
        // Only in [leftMin..midY]
        if (value < leftMin - 1e-6 || value > midY + 1e-6) {
          return const SizedBox.shrink();
        }

        if (wideSpan) {
          if (!(near(value, leftMin) || near(value, midY))) {
            return const SizedBox.shrink();
          }
        } else {
          // Snap to ~3 ticks in SG half
          final step = (midY - leftMin) / 3.0;
          final snapped = leftMin + ((value - leftMin) / step).round() * step;
          if (!near(value, snapped, step * 0.06)) {
            return const SizedBox.shrink();
          }
        }

        final sgVal = denormalize(value, sgMin, sgMax, leftMin, midY);
        return SideTitleWidget(
            meta: meta,
            child: Text(sgVal.toStringAsFixed(3), style: labelStyle));
      }

      if (showFsuTicks) {
        if (value < midY - 1e-6 || value > leftMax + 1e-6) {
          return const SizedBox.shrink();
        }
        // ~3 ticks in FSU half
        final step = (leftMax - midY) / 3.0;
        final snapped = midY + ((value - midY) / step).round() * step;
        if (!near(value, snapped, step * 0.06)) return const SizedBox.shrink();

        final fsuVal = denormalize(value, fsuMin, fsuMax, midY, leftMax);
        return SideTitleWidget(
            meta: meta,
            child: Text(fsuVal.toStringAsFixed(0), style: labelStyle));
      }

      return const SizedBox.shrink();
    }

    return FlTitlesData(
      show: true,
      topTitles: const AxisTitles(
        sideTitles: SideTitles(showTitles: false),
      ),
      bottomTitles: AxisTitles(
        axisNameSize: 0,
        sideTitles: SideTitles(
          showTitles: true,
          // extra room for the "M/D\nHH" midnight label in the 24–36h range
          reservedSize: spanHours <= 8 ? 24 : (spanHours <= 36 ? 34 : 24),
          interval: xIntervalHours,
          getTitlesWidget: bottomBuilder,
        ),
      ),
      leftTitles: AxisTitles(
        axisNameSize: 0,
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: leftReserved,
          interval: leftInterval, // fixed temp tick interval
          getTitlesWidget: (v, meta) => SideTitleWidget(
            meta: meta,
            child: Text(v.toStringAsFixed(0), style: labelStyle),
          ),
        ),
      ),
      rightTitles: AxisTitles(
        axisNameSize: 0,
        sideTitles: SideTitles(
          showTitles: showSgTicks || showFsuTicks,
          reservedSize: rightReserved,
          // Coarse ask; the builder will accept only the ticks we want.
          interval: (leftMax - leftMin) / 2.0,
          getTitlesWidget: rightBuilder,
        ),
      ),
    );
  }

  Widget _stageLabels({
    required List<FermentationStage> stages,
    required DateTime start,
    required double minX,
    required double maxX,
    required double plotWidth,
  }) {
    final children = <Widget>[];
    for (final s in stages) {
      if (s.startDate == null) continue;
      final startH = s.startDate!.difference(start).inHours.toDouble();
      if (startH < minX || startH > maxX) continue;
      final rel = (startH - minX) / (maxX - minX);
      final dx = leftPad + rel * plotWidth;
      children.add(
        Positioned(
          left: (dx - 2).clamp(leftPad + 2, leftPad + plotWidth - 2),
          top: topPad + 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(.25),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              (s.name).trim().isEmpty ? 'Stage' : s.name,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      );
    }
    return Stack(children: children);
  }

  // Legend
  static const _chipStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w600);

  Widget _legend({
    required bool isF,
    required bool hasTemp,
    required bool hasSG,
    required bool hasFSU,
  }) {
    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            if (hasTemp)
              _pill(
                color: Colors.blueAccent,
                label: 'Temp',
                isToggled: _showTemp,
                onTap: () => setState(() => _showTemp = !_showTemp),
              ),
            if (hasSG)
              _pill(
                color: Colors.green,
                label: 'SG',
                isToggled: _showSG,
                onTap: () => setState(() => _showSG = !_showSG),
              ),
            if (hasFSU)
              _pill(
                color: Colors.purple,
                label: 'FSU',
                isToggled: _showFSU,
                onTap: () => setState(() => _showFSU = !_showFSU),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Temp (°${isF ? 'F' : 'C'}) · SG / FSU',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }

  Widget _pill({
    required Color color,
    required String label,
    required bool isToggled,
    required VoidCallback onTap,
  }) {
    final opacity = isToggled ? 1.0 : 0.4;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: opacity,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withOpacity(.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(label, style: _chipStyle),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tooltip({
    required DateTime start,
    required double xHour,
    required List<FlSpot> tempSpots,
    required List<FlSpot> gravSpots,
    required List<FlSpot> fsuSpots,
    required double leftMin,
    required double leftMax,
    required double midY,
    required double sgMin,
    required double sgMax,
    required double fsuMin,
    required double fsuMax,
    required bool isF,
  }) {
    final t = start
        .add(Duration(microseconds: (xHour * Duration.microsecondsPerHour).round()));
    final ts =
        '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    final tempY = interp(tempSpots, xHour);
    final sgN = interp(gravSpots, xHour);
    final fsuN = interp(fsuSpots, xHour);

    const tsStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 12);
    const valueStyle = TextStyle(
      fontFeatures: [FontFeature.tabularFigures()],
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.35),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 12, color: Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ts, style: tsStyle),
            const SizedBox(height: 4),
            if (tempY != null && _showTemp)
              Text(
                'Temp: ${tempY.toStringAsFixed(1)}°${isF ? 'F' : 'C'}',
                style: valueStyle.copyWith(color: Colors.lightBlueAccent),
              ),
            if (sgN != null && _showSG)
              Text(
                'SG: ${denormalize(sgN, sgMin, sgMax, leftMin, midY).toStringAsFixed(3)}',
                style: valueStyle.copyWith(color: Colors.lightGreenAccent),
              ),
            if (fsuN != null && _showFSU)
              Text(
                'FSU: ${denormalize(fsuN, fsuMin, fsuMax, midY, leftMax).round()}',
                style: valueStyle.copyWith(color: Colors.purpleAccent),
              ),
          ],
        ),
      ),
    );
  }
}