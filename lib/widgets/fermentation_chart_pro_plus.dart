import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/measurement.dart';
import '../models/fermentation_stage.dart';
import 'package:flutter/foundation.dart';

enum BucketMode { none, avgHourly, avgDaily }
enum RightPane { temp, fsu }
enum ChartDataState { loading, loaded, empty }

// ---- small numeric helper (prevents num->double clamp warnings)
double _clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

// Define the missing padding constants
const double _padLeft = 46.0;
const double _padRight = 12.0;

class FermentationChartProPlus extends StatefulWidget {
  final List<Measurement> measurements;
  final List<FermentationStage> stages;

  final BucketMode bucket;
  final bool showGrid;
  final bool useFahrenheit;
  final RightPane rightPane;
  final bool showPaneSwitcher;

  final bool clipOutliers;
  final bool smooth;
  final bool showMidnightGuides;

  const FermentationChartProPlus({
    super.key,
    required this.measurements,
    required this.stages,
    this.bucket = BucketMode.none,
    this.showGrid = true,
    this.useFahrenheit = false,
    this.rightPane = RightPane.temp,
    this.showPaneSwitcher = true,
    this.clipOutliers = true,
    this.smooth = false,
    this.showMidnightGuides = true,
  });

  @override
  State<FermentationChartProPlus> createState() => _FermentationChartProPlusState();
}

class _FermentationChartProPlusState extends State<FermentationChartProPlus> with WidgetsBindingObserver {
  SeriesCache? _series;
  ChartDataState _dataState = ChartDataState.empty;
  final ValueNotifier<_Viewport> _view = ValueNotifier(const _Viewport(0, 0));

  late RightPane _pane;
  double? _hoverAbsMs;
  bool _smooth = false;

  bool _isZoomed = false;
  final ValueNotifier<List<FlSpot>> _hoverSpots = ValueNotifier([]);

  @override
  void initState() {
    super.initState();
    _pane = widget.rightPane;
    _smooth = widget.smooth;
    _rebuildIfNeeded(force: true);
  }

  @override
  void didUpdateWidget(covariant FermentationChartProPlus old) {
    super.didUpdateWidget(old);
    final inputsChanged = !identical(old.measurements, widget.measurements) ||
        old.measurements.length != widget.measurements.length ||
        (widget.measurements.isNotEmpty &&
            old.measurements.isNotEmpty &&
            old.measurements.last.timestamp != widget.measurements.last.timestamp) ||
        old.bucket != widget.bucket ||
        old.useFahrenheit != widget.useFahrenheit ||
        old.stages.length != widget.stages.length ||
        (widget.stages.isNotEmpty &&
            old.stages.isNotEmpty &&
            (old.stages.last.startDate != widget.stages.last.startDate ||
                old.stages.last.durationDays != widget.stages.last.durationDays)) ||
        old.smooth != widget.smooth;

    if (inputsChanged) {
      _rebuildIfNeeded(force: true);
    }
    if (old.rightPane != widget.rightPane) _pane = widget.rightPane;
  }

  void _rebuildIfNeeded({bool force = false}) async {
    if (widget.measurements.isEmpty) {
      setState(() {
        _series = null;
        _dataState = ChartDataState.empty;
      });
      return;
    }

    setState(() {
      _dataState = ChartDataState.loading;
    });

    final nextSeries = await compute(SeriesCache.build, {
      'measurements': widget.measurements,
      'stages': widget.stages,
      'bucket': widget.bucket,
      'useFahrenheit': widget.useFahrenheit,
      'clipOutliers': widget.clipOutliers,
      'smooth': _smooth,
    });

    if (force || !_seriesSame(_series, nextSeries)) {
      _series = nextSeries;
      final fullSpan = (_series!.t1.millisecondsSinceEpoch - _series!.t0.millisecondsSinceEpoch).toDouble();
      _view.value = _Viewport(0, fullSpan <= 0 ? 1 : fullSpan);
    } else {
      _series = nextSeries;
    }

    setState(() {
      _dataState = ChartDataState.loaded;
    });
  }

  bool _seriesSame(SeriesCache? a, SeriesCache? b) {
    if (a == null || b == null) return false;
    return a.hash == b.hash;
  }

  void _postViewport(_Viewport v) {
    final s = _series!;
    final fullSpan = (s.t1.millisecondsSinceEpoch - s.t0.millisecondsSinceEpoch).toDouble();
    _isZoomed = v.minX != 0 || (v.maxX - v.minX).round() != fullSpan.round();
    _view.value = v;
  }

  @override
  Widget build(BuildContext context) {
    final s = _series;
    if (_dataState == ChartDataState.empty) {
      return const _EmptyState(text: 'No measurements yet.\nAdd SG or temperature to see the chart.');
    }
    if (_dataState == ChartDataState.loading || s == null) {
      return const _LoadingState();
    }

    final theme = Theme.of(context);

    double bottomIntervalMs(_Viewport v) {
      final days = Duration(milliseconds: (v.maxX - v.minX).toInt()).inDays.clamp(1, 365);
      if (days <= 2) return const Duration(hours: 12).inMilliseconds.toDouble();
      if (days <= 7) return const Duration(days: 1).inMilliseconds.toDouble();
      if (days <= 21) return const Duration(days: 2).inMilliseconds.toDouble();
      return const Duration(days: 3).inMilliseconds.toDouble();
    }

    Widget bottomTick(double vRel, TitleMeta _) {
      final t = DateTime.fromMillisecondsSinceEpoch(s.t0.millisecondsSinceEpoch + vRel.toInt());
      final dayN = t.difference(s.t0).inDays + 1;
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('Day $dayN\n${t.month}/${t.day}', textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final chartW = math.max(1.0, width - _padLeft - _padRight);

      Widget gestureLayer() {
        double pxToTime(double px, _Viewport v) {
          final span = (v.maxX - v.minX);
          if (span <= 0) return v.minX;
          final frac = _clampD((px - _padLeft) / chartW, 0.0, 1.0);
          return v.minX + frac * span;
        }

        double clampStart(double start, double span, double fullMax) {
          return _clampD(start, 0.0, fullMax - span);
        }

        return ValueListenableBuilder<_Viewport>(
          valueListenable: _view,
          builder: (_, view, __) {
            final fullMax = (s.t1.millisecondsSinceEpoch - s.t0.millisecondsSinceEpoch).toDouble();
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onDoubleTap: () => _postViewport(_Viewport(0, fullMax <= 0 ? 1 : fullMax)),
              onScaleStart: (_) {
                setState(() => _hoverAbsMs = null);
              },
              onScaleUpdate: (details) {
                final span = (view.maxX - view.minX);
                final focal = pxToTime(details.localFocalPoint.dx, view);

                // zoom
                final scale = details.scale;
                if (scale != 1.0) {
                  final ns = _clampD(span / scale, fullMax / 100, fullMax);
                  final frac = (span <= 0) ? 0.5 : _clampD((focal - view.minX) / span, 0.0, 1.0);
                  var newStart = focal - ns * frac;
                  newStart = clampStart(newStart, ns, fullMax);
                  _postViewport(_Viewport(newStart, newStart + ns));
                }

                // pan
                if (details.scale == 1.0 && details.focalPointDelta.dx != 0) {
                  final msPerPx = span / chartW;
                  final deltaMs = -details.focalPointDelta.dx * msPerPx;
                  var newStart = view.minX + deltaMs;
                  newStart = clampStart(newStart, span, fullMax);
                  _postViewport(_Viewport(newStart, newStart + span));
                }
              },
              onScaleEnd: (details) {
                // light kinetic fling
                final vx = details.velocity.pixelsPerSecond.dx;
                if (vx.abs() > 80) {
                  final span = (view.maxX - view.minX);
                  final msPerPx = span / chartW;
                  final delta = -vx * 0.25 * msPerPx;
                  final fullMax = (s.t1.millisecondsSinceEpoch - s.t0.millisecondsSinceEpoch).toDouble();
                  var start = _clampD(view.minX + delta, 0.0, fullMax - span);
                  _postViewport(_Viewport(start, start + span));
                }
              },
            );
          },
        );
      }

      Widget crosshairOverlayPx(_Viewport view) {
        if (_hoverAbsMs == null) return const SizedBox.shrink();
        final relMs = _hoverAbsMs! - _series!.t0.millisecondsSinceEpoch;
        final span = (view.maxX - view.minX);
        if (span <= 0) return const SizedBox.shrink();
        final frac = _clampD((relMs - view.minX) / span, 0.0, 1.0);
        final xPx = _padLeft + frac * chartW;
        return IgnorePointer(child: CustomPaint(painter: _CrosshairPainter(xPx: xPx), size: Size.infinite));
      }

      Widget quickRanges() {
        return ValueListenableBuilder<_Viewport>(
          valueListenable: _view,
          builder: (_, view, __) {
            final fullMax = (s.t1.millisecondsSinceEpoch - s.t0.millisecondsSinceEpoch).toDouble();
            void setLast(Duration d) {
              final span = d.inMilliseconds.toDouble();
              final start = _clampD(fullMax - span, 0.0, math.max(0.0, fullMax - span));
              _postViewport(_Viewport(start, start + span));
            }
            return Wrap(
              spacing: 6,
              children: [
                ActionChip(label: const Text('Last 24h'), onPressed: () => setLast(const Duration(hours: 24))),
                ActionChip(label: const Text('Last 3d'), onPressed: () => setLast(const Duration(days: 3))),
                ActionChip(label: const Text('Last 7d'), onPressed: () => setLast(const Duration(days: 7))),
                if (_isZoomed) TextButton(onPressed: () => _postViewport(_Viewport(0, fullMax)), child: const Text('Reset View')),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Smooth'),
                  selected: _smooth,
                  onSelected: (v) {
                    setState(() => _smooth = v);
                    _rebuildIfNeeded(force: true);
                  },
                ),
                if (widget.showPaneSwitcher) ...[
                  ChoiceChip(
                    label: const Text('Temp'), selected: _pane == RightPane.temp,
                    onSelected: (_) => setState(() => _pane = RightPane.temp),
                  ),
                  ChoiceChip(
                    label: const Text('FSU'), selected: _pane == RightPane.fsu,
                    onSelected: (_) => setState(() => _pane = RightPane.fsu),
                  ),
                ],
              ],
            );
          },
        );
      }

      return Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: -6,
                      children: [
                        const Chip(label: Text('SG')),
                        Chip(label: Text(_pane == RightPane.temp
                            ? (widget.useFahrenheit ? 'Temp (°F)' : 'Temp (°C)')
                            : 'FSU')),
                        Chip(label: Text(switch (widget.bucket) {
                          BucketMode.none => 'Raw',
                          BucketMode.avgHourly => 'Hourly',
                          BucketMode.avgDaily => 'Daily',
                        })),
                      ],
                    ),
                    const SizedBox(height: 6),
                    quickRanges(),
                  ],
                ),
              ),

              // TOP: SG
              RepaintBoundary(
                child: SizedBox(
                  height: 190,
                  child: ValueListenableBuilder<_Viewport>(
                    valueListenable: _view,
                    builder: (_, view, __) {
                      final visSg = s.slice(s.sg, view.minX, view.maxX);
                      final bands = s.visibleBands(view.minX, view.maxX, theme.colorScheme.primary.withOpacity(0.06));
                      final midnight = widget.showMidnightGuides
                          ? s.visibleMidnights(view.minX, view.maxX)
                          : const <VerticalRangeAnnotation>[];
                      return Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(_padLeft, 8, _padRight, 4),
                            child: LineChart(
                              LineChartData(
                                minX: view.minX, maxX: view.maxX,
                                minY: s.sgMin, maxY: s.sgMax,
                                rangeAnnotations: RangeAnnotations(
                                  verticalRangeAnnotations: [...bands, ...midnight],
                                ),
                                gridData: FlGridData(
                                  show: widget.showGrid,
                                  drawVerticalLine: false,
                                  horizontalInterval: _sgTickInterval(s.sgMin, s.sgMax),
                                ),
                                titlesData: FlTitlesData(
                                  leftTitles: AxisTitles(
                                    axisNameWidget: const Text('SG'),
                                    axisNameSize: 22,
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 46,
                                      interval: _sgTickInterval(s.sgMin, s.sgMax),
                                      getTitlesWidget: (v, _) =>
                                          Text(v.toStringAsFixed(3), style: theme.textTheme.bodySmall),
                                    ),
                                  ),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 30,
                                      interval: bottomIntervalMs(view),
                                      getTitlesWidget: bottomTick,
                                    ),
                                  ),
                                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                ),
                                lineTouchData: LineTouchData(
                                  handleBuiltInTouches: false,
                                  touchCallback: (evt, resp) {
                                    if (resp?.lineBarSpots?.isNotEmpty == true) {
                                      _hoverAbsMs = resp!.lineBarSpots!.first.x + s.t0.millisecondsSinceEpoch;
                                      _hoverSpots.value = resp.lineBarSpots!.map((spot) => spot.toFlSpot()).toList();
                                    } else {
                                      _hoverAbsMs = null;
                                      _hoverSpots.value = [];
                                    }
                                  },
                                ),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: visSg,
                                    isCurved: true,
                                    barWidth: 2,
                                    belowBarData: BarAreaData(
                                      show: true,
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [theme.colorScheme.primary.withOpacity(0.22), Colors.transparent],
                                      ),
                                    ),
                                    dotData: FlDotData(
                                      show: visSg.length <= 150,
                                      getDotPainter: (spot, _, __, ___) {
                                        final m = s.nearestMeasurementAtRel(spot.x);
                                        final isDevice = m?.fromDevice == true;
                                        return FlDotCirclePainter(
                                          radius: isDevice ? 2.5 : 3.5,
                                          strokeWidth: isDevice ? 0 : 1,
                                          color: theme.colorScheme.primary,
                                          strokeColor: theme.colorScheme.onSurface.withOpacity(0.6),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                                clipData: const FlClipData.all(),
                                borderData: FlBorderData(
                                  show: true,
                                  border: Border.all(color: theme.dividerColor.withOpacity(0.7), width: 1),
                                ),
                              ),
                              duration: const Duration(milliseconds: 120),
                              curve: Curves.easeOut,
                            ),
                          ),
                          crosshairOverlayPx(view),
                        ],
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // BOTTOM: Temp or FSU
              RepaintBoundary(
                child: SizedBox(
                  height: 170,
                  child: ValueListenableBuilder<_Viewport>(
                    valueListenable: _view,
                    builder: (_, view, __) {
                      final isTemp = _pane == RightPane.temp;
                      final visBottom = s.slice(isTemp ? s.temp : s.fsu, view.minX, view.maxX);

                      final bands = s.visibleBands(view.minX, view.maxX, theme.colorScheme.primary.withOpacity(0.06));
                      final midnight = widget.showMidnightGuides
                          ? s.visibleMidnights(view.minX, view.maxX)
                          : const <VerticalRangeAnnotation>[];
                      return Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(_padLeft, 4, _padRight, 8),
                            child: LineChart(
                              LineChartData(
                                minX: view.minX, maxX: view.maxX,
                                minY: isTemp ? s.tMin : s.fsuMin,
                                maxY: isTemp ? s.tMax : s.fsuMax,
                                rangeAnnotations: RangeAnnotations(
                                  verticalRangeAnnotations: [...bands, ...midnight],
                                ),
                                gridData: FlGridData(
                                  show: widget.showGrid,
                                  drawVerticalLine: false,
                                  horizontalInterval: isTemp
                                      ? _tempTickInterval(s.tMin, s.tMax, widget.useFahrenheit)
                                      : _fsuTickInterval(s.fsuMin, s.fsuMax),
                                ),
                                titlesData: FlTitlesData(
                                  leftTitles: AxisTitles(
                                    axisNameWidget:
                                        Text(isTemp ? (widget.useFahrenheit ? 'Temp (°F)' : 'Temp (°C)') : 'FSU'),
                                    axisNameSize: 22,
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 46,
                                      interval: isTemp
                                          ? _tempTickInterval(s.tMin, s.tMax, widget.useFahrenheit)
                                          : _fsuTickInterval(s.fsuMin, s.fsuMax),
                                      getTitlesWidget: (v, _) {
                                        if (isTemp) {
                                          final unit = widget.useFahrenheit ? '°F' : '°C';
                                          return Text('${v.toStringAsFixed(0)}$unit', style: theme.textTheme.bodySmall);
                                        } else {
                                          return Text(v.toStringAsFixed(0), style: theme.textTheme.bodySmall);
                                        }
                                      },
                                    ),
                                  ),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 30,
                                      interval: bottomIntervalMs(view),
                                      getTitlesWidget: bottomTick,
                                    ),
                                  ),
                                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                ),
                                lineTouchData: LineTouchData(
                                  handleBuiltInTouches: false,
                                  touchCallback: (evt, resp) {
                                    if (resp?.lineBarSpots?.isNotEmpty == true) {
                                      _hoverAbsMs = resp!.lineBarSpots!.first.x + s.t0.millisecondsSinceEpoch;
                                    } else {
                                      _hoverAbsMs = null;
                                    }
                                  },
                                ),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: visBottom,
                                    isCurved: true,
                                    barWidth: 2,
                                    belowBarData: BarAreaData(
                                      show: true,
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [theme.colorScheme.secondary.withOpacity(0.18), Colors.transparent],
                                      ),
                                    ),
                                    dotData: const FlDotData(show: false),
                                  ),
                                ],
                                clipData: const FlClipData.all(),
                                borderData: FlBorderData(
                                  show: true,
                                  border: Border.all(color: theme.dividerColor.withOpacity(0.7), width: 1),
                                ),
                              ),
                              duration: const Duration(milliseconds: 120),
                              curve: Curves.easeOut,
                            ),
                          ),
                          crosshairOverlayPx(view),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),

          // gestures overlay
          Positioned.fill(child: gestureLayer()),

          // Custom unified tooltip overlay
          if (_hoverAbsMs != null)
            Positioned.fill(
              child: IgnorePointer(
                child: ValueListenableBuilder<List<FlSpot>>(
                  valueListenable: _hoverSpots,
                  builder: (_, hoverSpots, __) {
                    // Check if the list is empty before trying to access elements
                    if (hoverSpots.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    // find nearest data points for both charts based on _hoverAbsMs
                    final sgDataPoint = s.sg.firstWhere(
                      (spot) => (spot.x - (_hoverAbsMs! - s.t0.millisecondsSinceEpoch)).abs() < 2,
                      orElse: () => const FlSpot(-1, -1),
                    );

                    final tempOrFsuDataPoint = (_pane == RightPane.temp ? s.temp : s.fsu).firstWhere(
                      (spot) => (spot.x - (_hoverAbsMs! - s.t0.millisecondsSinceEpoch)).abs() < 2,
                      orElse: () => const FlSpot(-1, -1),
                    );

                    // build display text
                    String displayText = '';
                    if (sgDataPoint.y != -1) {
                      final sgValue = sgDataPoint.y.toStringAsFixed(3);
                      displayText += 'SG: $sgValue';
                    }

                    if (tempOrFsuDataPoint.y != -1) {
                      final isTemp = _pane == RightPane.temp;
                      final bottomValue = tempOrFsuDataPoint.y.toStringAsFixed(isTemp ? 0 : 0);
                      final bottomLabel = isTemp
                          ? (widget.useFahrenheit ? 'Temp (°F)' : 'Temp (°C)')
                          : 'FSU';
                      if (displayText.isNotEmpty) {
                        displayText += '\n';
                      }
                      displayText += '$bottomLabel: $bottomValue';
                    }

                    // Position the tooltip at the top-center
                    return Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.5),
                              spreadRadius: 2,
                              blurRadius: 5,
                            ),
                          ],
                        ),
                        child: Text(
                          displayText,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      );
    });
  }

  // ticks
  double _sgTickInterval(double mn, double mx) {
    final span = (mx - mn).abs();
    if (span <= 0.004) return 0.001;
    if (span <= 0.010) return 0.002;
    if (span <= 0.020) return 0.005;
    return 0.01;
  }

  double _tempTickInterval(double mn, double mx, bool inF) {
    final span = (mx - mn).abs();
    if (inF) {
      if (span <= 6) return 2;
      if (span <= 15) return 5;
      return 10;
    } else {
      if (span <= 3) return 1;
      if (span <= 10) return 2;
      return 5;
    }
  }

  double _fsuTickInterval(double mn, double mx) {
    final span = (mx - mn).abs();
    if (span <= 100) return 25;
    if (span <= 250) return 50;
    return 100;
  }
}

extension on LineBarSpot {
  FlSpot toFlSpot() => FlSpot(x, y);
}

// ---------------- Data cache & helpers ----------------

class SeriesCache {
  SeriesCache._({
    required this.hash,
    required this.bucket,
    required this.useFahrenheit,
    required this.clipOutliers,
    required this.smooth,
    required this.t0,
    required this.t1,
    required this.sg,
    required this.temp,
    required this.fsu,
    required this.sgMin,
    required this.sgMax,
    required this.tMin,
    required this.tMax,
    required this.fsuMin,
    required this.fsuMax,
    required this.midnights,
    required List<_StageWin> stageWindows,
    required this.rawMeasurements,
  }) : _stageWindows = stageWindows;

  final int hash;
  final BucketMode bucket;
  final bool useFahrenheit;
  final bool clipOutliers;
  final bool smooth;

  final DateTime t0, t1;
  final List<FlSpot> sg, temp, fsu;
  final double sgMin, sgMax, tMin, tMax, fsuMin, fsuMax;

  final List<double> midnights; // rel ms
  final List<_StageWin> _stageWindows; // private: avoids exposing a private type publicly

  final List<Measurement> rawMeasurements;

  static SeriesCache build(Map<String, dynamic> args) {
    final measurements = args['measurements'] as List<Measurement>;
    final stages = args['stages'] as List<FermentationStage>;
    final bucket = args['bucket'] as BucketMode;
    final useFahrenheit = args['useFahrenheit'] as bool;
    final clipOutliers = args['clipOutliers'] as bool;
    final smooth = args['smooth'] as bool;

    final sorted = [...measurements]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final data = switch (bucket) {
      BucketMode.none => sorted,
      BucketMode.avgHourly => _bucket(sorted, const Duration(hours: 1)),
      BucketMode.avgDaily => _bucket(sorted, const Duration(days: 1)),
    };

    final now = DateTime.now();
    final t0 = data.isEmpty ? now : data.first.timestamp;
    final t1 = data.isEmpty ? now.add(const Duration(days: 1)) : data.last.timestamp.add(const Duration(hours: 6));

    double rel(DateTime d) => (d.millisecondsSinceEpoch - t0.millisecondsSinceEpoch).toDouble();

    // SG
    List<FlSpot> sgSpots = [];
    for (final m in data) {
      final sg = _sgOf(m);
      if (sg != null) sgSpots.add(FlSpot(rel(m.timestamp), sg));
    }

    // Temp (display units)
    List<FlSpot> tSpots = [];
    for (final m in data) {
      final vt = _toDispTemp(m.temperature, useFahrenheit);
      if (vt != null) tSpots.add(FlSpot(rel(m.timestamp), vt));
    }

    // FSU
    final fsuPts = _computeFsu(data);
    List<FlSpot> fsuSpots = [for (final p in fsuPts) FlSpot(rel(p.at), p.fsu)];

    // Bounds
    double sgMin = 0.998, sgMax = 1.060;
    if (sgSpots.isNotEmpty) {
      final mn = sgSpots.map((e) => e.y).reduce(math.min);
      final mx = sgSpots.map((e) => e.y).reduce(math.max);
      final pad = math.max((mx - mn).abs() * 0.10, 0.002);
      sgMin = mn - pad;
      sgMax = mx + pad;
    }

    double tMin = useFahrenheit ? 60 : 15, tMax = useFahrenheit ? 80 : 27;
    if (tSpots.isNotEmpty) {
      final mn = tSpots.map((e) => e.y).reduce(math.min);
      final mx = tSpots.map((e) => e.y).reduce(math.max);
      final pad = math.max((mx - mn).abs() * 0.10, useFahrenheit ? 1 : 0.5);
      tMin = mn - pad;
      tMax = mx + pad;
    }

    double fMin = 0, fMax = 400;
    if (fsuSpots.isNotEmpty) {
      final mn = fsuSpots.map((e) => e.y).reduce(math.min);
      final mx = fsuSpots.map((e) => e.y).reduce(math.max);
      final pad = math.max((mx - mn).abs() * 0.20, 25);
      fMin = mn - pad;
      fMax = mx + pad;
    }

    // Outliers + smoothing at series level
    if (clipOutliers) {
      sgSpots = _clipOutliers(sgSpots);
      tSpots = _clipOutliers(tSpots);
      fsuSpots = _clipOutliers(fsuSpots);
    }
    if (smooth) {
      sgSpots = _ema(sgSpots);
      tSpots = _ema(tSpots, alpha: 0.25);
      fsuSpots = _ema(fsuSpots, alpha: 0.25);
    }

    // Midnights & stages
    final midnights = <double>[];
    DateTime d = DateTime(t0.year, t0.month, t0.day).add(const Duration(days: 1));
    while (d.isBefore(t1)) {
      midnights.add(rel(d));
      d = d.add(const Duration(days: 1));
    }
    final stageWindows = <_StageWin>[
      for (final s in stages)
        _StageWin(
          startRel: rel(s.startDate ?? t0),
          endRel: rel((s.startDate ?? t0).add(Duration(days: s.durationDays))),
          name: s.name,
        )
    ];

    final hash = Object.hash(
      bucket,
      useFahrenheit,
      clipOutliers,
      smooth,
      data.length,
      data.isEmpty ? 0 : data.last.timestamp.millisecondsSinceEpoch,
      stages.length,
      stages.isEmpty ? 0 : (stages.last.startDate?.millisecondsSinceEpoch ?? 0) ^ stages.last.durationDays,
    );

    return SeriesCache._(
      hash: hash,
      bucket: bucket,
      useFahrenheit: useFahrenheit,
      clipOutliers: clipOutliers,
      smooth: smooth,
      t0: t0,
      t1: t1,
      sg: sgSpots,
      temp: tSpots,
      fsu: fsuSpots,
      sgMin: sgMin,
      sgMax: sgMax,
      tMin: tMin,
      tMax: tMax,
      fsuMin: fMin,
      fsuMax: fMax,
      midnights: midnights,
      stageWindows: stageWindows,
      rawMeasurements: data,
    );
  }

  List<FlSpot> slice(List<FlSpot> src, double minX, double maxX) {
    if (src.isEmpty) return const <FlSpot>[];
    final vis = <FlSpot>[];
    for (final p in src) {
      final x = p.x;
      if (x >= minX && x <= maxX) vis.add(p);
    }
    return _lttb(vis, 900);
  }

  List<VerticalRangeAnnotation> visibleBands(double minX, double maxX, Color color) {
    if (_stageWindows.isEmpty) return const <VerticalRangeAnnotation>[];
    final out = <VerticalRangeAnnotation>[];
    for (final w in _stageWindows) {
      final x1 = math.max(minX, w.startRel);
      final x2 = math.min(maxX, w.endRel);
      if (x2 > x1) out.add(VerticalRangeAnnotation(x1: x1, x2: x2, color: color));
    }
    return out;
  }

  List<VerticalRangeAnnotation> visibleMidnights(double minX, double maxX) {
    if (midnights.isEmpty) return const <VerticalRangeAnnotation>[];
    final out = <VerticalRangeAnnotation>[];
    for (final x in midnights) {
      if (x >= minX && x <= maxX) {
        out.add(VerticalRangeAnnotation(x1: x, x2: x + 1, color: const Color(0x1A000000)));
      }
    }
    return out;
  }

  Measurement? nearestMeasurementAtRel(double relX) {
    if (rawMeasurements.isEmpty) return null;
    final targetAbs = t0.millisecondsSinceEpoch + relX.toInt();
    Measurement? best;
    var bestDelta = 1 << 30;
    for (final m in rawMeasurements) {
      final d = (m.timestamp.millisecondsSinceEpoch - targetAbs).abs();
      if (d < bestDelta) {
        bestDelta = d;
        best = m;
      }
    }
    return best;
  }
}

class _Viewport {
  final double minX;
  final double maxX;
  const _Viewport(this.minX, this.maxX);
}

class _StageWin {
  final double startRel, endRel;
  final String name;
  const _StageWin({required this.startRel, required this.endRel, required this.name});
}

// ---------------- Painters ----------------

class _CrosshairPainter extends CustomPainter {
  final double xPx;
  _CrosshairPainter({required this.xPx});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF888888).withOpacity(0.35)
      ..strokeWidth = 1;
    final x = xPx.clamp(0.0, size.width);
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter old) => old.xPx != xPx;
}

// ---------------- Utils (pure) ----------------

double? _sgOf(Measurement m) {
  if (m.sgCorrected != null) return m.sgCorrected;
  if (m.gravity != null) return m.gravity;
  if (m.brix != null) {
    final b = m.brix!;
    return 1 + (b / (258.6 - ((b / 258.2) * 227.1)));
  }
  return null;
}

double? _toDispTemp(double? t, bool useFahrenheit) {
  if (t == null) return null;
  final c = (t > 60) ? (t - 32) * 5 / 9 : t; // heuristic
  return useFahrenheit ? (c * 9 / 5 + 32) : c;
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
        temperature: tempC,
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
      sgSum = 0;
      sgN = 0;
      tSum = 0;
      tN = 0;
    }
    final sg = _sgOf(m);
    if (sg != null) {
      sgSum += sg;
      sgN += 1;
    }
    final c =
        (m.temperature == null) ? null : ((m.temperature! > 60) ? (m.temperature! - 32) * 5 / 9 : m.temperature!);
    if (c != null) {
      tSum += c;
      tN += 1;
    }
  }
  out.add(mk(wndStart.add(win ~/ 2), sgN > 0 ? sgSum / sgN : null, tN > 0 ? tSum / tN : null));
  return out.where((m) => m.gravity != null || m.temperature != null).toList();
}

DateTime _floorTo(DateTime t, Duration d) {
  final ms = d.inMilliseconds;
  final q = (t.millisecondsSinceEpoch ~/ ms) * ms;
  return DateTime.fromMillisecondsSinceEpoch(q);
}

class _FsuPoint {
  final DateTime at;
  final double fsu;
  _FsuPoint(this.at, this.fsu);
}

List<_FsuPoint> _computeFsu(List<Measurement> data) {
  final pts = <_FsuPoint>[];
  double? sgOf(Measurement m) => _sgOf(m);
  final sgOnly = data.where((m) => sgOf(m) != null).toList();
  for (var i = 1; i < sgOnly.length; i++) {
    final a = sgOnly[i - 1], b = sgOnly[i];
    final sgA = sgOf(a)!, sgB = sgOf(b)!;
    final days = b.timestamp.difference(a.timestamp).inMinutes / (60 * 24);
    if (days <= 0) continue;
    final fsu = 100000 * (sgA - sgB) / days;
    pts.add(_FsuPoint(b.timestamp, fsu));
  }
  return pts;
}

List<FlSpot> _clipOutliers(List<FlSpot> s, {double sigma = 3}) {
  if (s.length < 8) return s;
  final ys = s.map((e) => e.y).toList()..sort();
  final median = ys[ys.length ~/ 2];
  final mad = ys.map((y) => (y - median).abs()).reduce(math.max) / 0.6745;
  if (mad == 0 || mad.isNaN) return s;
  return s.where((p) => ((p.y - median).abs() / mad) <= sigma).toList();
}

List<FlSpot> _ema(List<FlSpot> s, {double alpha = 0.25}) {
  if (s.isEmpty) return s;
  final out = <FlSpot>[];
  double acc = s.first.y;
  for (final p in s) {
    acc = alpha * p.y + (1 - alpha) * acc;
    out.add(FlSpot(p.x, acc));
  }
  return out;
}

// LTTB downsampling (no casts)
List<FlSpot> _lttb(List<FlSpot> data, int threshold) {
  if (data.length <= threshold) return data;
  final out = <FlSpot>[];
  final bucketSize = (data.length - 2) / (threshold - 2);
  var a = 0;
  out.add(data[a]);
  for (var i = 0; i < threshold - 2; i++) {
    final start = (1 + (i * bucketSize)).floor();
    final endCandidate = (1 + ((i + 1) * bucketSize)).floor();
    final e = endCandidate < start + 1 ? start + 1 : (endCandidate > data.length ? data.length : endCandidate);
    final bucket = data.sublist(start, e);
    final avgX = bucket.fold<double>(0, (s, p) => s + p.x) / bucket.length;
    final avgY = bucket.fold<double>(0, (s, p) => s + p.y) / bucket.length;
    double maxArea = -1;
    var nextA = start;
    for (var j = start; j < e; j++) {
      final area = (data[a].x - avgX) * (data[j].y - data[a].y) -
          (data[a].x - data[j].x) * (avgY - data[a].y);
      final absArea = area.abs();
      if (absArea > maxArea) {
        maxArea = absArea;
        nextA = j;
      }
    }
    a = nextA;
    out.add(data[a]);
  }
  out.add(data.last);
  return out;
}

class _EmptyState extends StatelessWidget {
  final String text;
  const _EmptyState({required this.text});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 320,
      margin: const EdgeInsets.all(12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, textAlign: TextAlign.center),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 320,
      margin: const EdgeInsets.all(12),
      alignment: Alignment.center,
      child: const CircularProgressIndicator(),
    );
  }
}