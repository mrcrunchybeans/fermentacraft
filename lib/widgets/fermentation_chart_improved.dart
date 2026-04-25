// Copyright 2024 Brian Henson
// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:fermentacraft/models/measurement.dart';
import 'dart:math' as math;

/// Improved fermentation chart with better UX:
/// - Larger, clearer legend
/// - Simplified controls (auto-fit by default)
/// - Prominent range selector at top
/// - Info button for FSU explanation
/// - Better data point visibility
/// - Clearer tooltips
/// - Empty state message

enum ChartRange {
  h24('24 hours'),
  d3('3 days'),
  d7('7 days'),
  d30('30 days'),
  sincePitch('Since pitching');

  const ChartRange(this.label);
  final String label;

  Duration? get duration {
    switch (this) {
      case ChartRange.h24:
        return const Duration(hours: 24);
      case ChartRange.d3:
        return const Duration(days: 3);
      case ChartRange.d7:
        return const Duration(days: 7);
      case ChartRange.d30:
        return const Duration(days: 30);
      case ChartRange.sincePitch:
        return null; // entire dataset
    }
  }
}

/// Aggregates measurements into time buckets
class _HourlyAggregator {
  static const int defaultMaxBuckets = 100; // Reduced for better performance

  /// Aggregate measurements into time buckets (adaptive based on data density)
  static List<Measurement> aggregate(
    List<Measurement> measurements, {
    int maxBuckets = defaultMaxBuckets,
  }) {
    if (measurements.isEmpty) return [];

    measurements.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // If already within limit, return as-is
    if (measurements.length <= maxBuckets) {
      return measurements;
    }

    final first = measurements.first.timestamp;
    final last = measurements.last.timestamp;
    final spanMinutes = last.difference(first).inMinutes;

    if (spanMinutes <= 0) return measurements;

    // Calculate bucket size in minutes to achieve target bucket count
    final bucketMinutes = math.max(1, (spanMinutes / maxBuckets).ceil());
    final Map<int, List<Measurement>> buckets = {};

    for (final m in measurements) {
      final minutesSinceFirst = m.timestamp.difference(first).inMinutes;
      final bucketIndex = minutesSinceFirst ~/ bucketMinutes;
      buckets.putIfAbsent(bucketIndex, () => []).add(m);
    }

    final result = <Measurement>[];
    for (final bucket in buckets.values) {
      result.add(_averageMeasurements(bucket));
    }

    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  static Measurement _averageMeasurements(List<Measurement> ms) {
    if (ms.length == 1) return ms.first;

    double? avgGravity;
    double? avgTemp;
    double? avgBrix;

    final gravities = ms.where((m) => m.gravity != null).map((m) => m.gravity!).toList();
    final temps = ms.where((m) => m.temperature != null).map((m) => m.temperature!).toList();
    final brixes = ms.where((m) => m.brix != null).map((m) => m.brix!).toList();

    if (gravities.isNotEmpty) {
      avgGravity = gravities.reduce((a, b) => a + b) / gravities.length;
    }
    if (temps.isNotEmpty) {
      avgTemp = temps.reduce((a, b) => a + b) / temps.length;
    }
    if (brixes.isNotEmpty) {
      avgBrix = brixes.reduce((a, b) => a + b) / brixes.length;
    }

    return Measurement(
      timestamp: ms.first.timestamp,
      gravity: avgGravity,
      temperature: avgTemp,
      brix: avgBrix,
      notes: null,
      fromDevice: ms.first.fromDevice,
    );
  }
}

/// Main chart panel with integrated range selector
class ImprovedFermentationChartPanel extends StatefulWidget {
  const ImprovedFermentationChartPanel({
    super.key,
    required this.measurements,
    required this.useFahrenheit,
    this.sincePitchingAt,
    this.initialRange = ChartRange.d7,
    this.onRangeChanged,
  });

  final List<Measurement> measurements;
  final bool useFahrenheit;
  final DateTime? sincePitchingAt;
  final ChartRange initialRange;
  final ValueChanged<ChartRange>? onRangeChanged;

  @override
  State<ImprovedFermentationChartPanel> createState() => _ImprovedFermentationChartPanelState();
}

class _ImprovedFermentationChartPanelState extends State<ImprovedFermentationChartPanel> {
  late ChartRange _range;

  @override
  void initState() {
    super.initState();
    _range = widget.initialRange;
  }

  void _setRange(ChartRange r) {
    setState(() => _range = r);
    widget.onRangeChanged?.call(r);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title with info button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Fermentation Progress',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _showChartInfo(context),
                  tooltip: 'Chart help',
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Range selector chips
            _RangeSelector(
              currentRange: _range,
              onRangeChanged: _setRange,
              sincePitchingAvailable: widget.sincePitchingAt != null,
            ),
            const SizedBox(height: 12),
            
            // The chart itself
            ImprovedFermentationChart(
              measurements: widget.measurements,
              useFahrenheit: widget.useFahrenheit,
              range: _range,
              sincePitchingAt: widget.sincePitchingAt,
            ),
          ],
        ),
      ),
    );
  }

  void _showChartInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chart Information'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Lines:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text('• Blue = Specific Gravity (SG)'),
              Text('• Red = Temperature'),
              Text('• Green = Fermentation Speed (FSU)'),
              SizedBox(height: 12),
              Text('FSU (Fermentation Speed Units):', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text('Measures how fast gravity is dropping. Calculated as points per day (1 pt = 0.001 SG).'),
              SizedBox(height: 8),
              Text('Higher FSU = More active fermentation\nLower FSU = Slowing down or finished'),
              SizedBox(height: 12),
              Text('Interactions:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text('• Tap data points to see values'),
              Text('• Pinch to zoom in/out'),
              Text('• Drag to pan left/right'),
              Text('• Double-tap to reset zoom'),
              SizedBox(height: 12),
              Text('Data Display:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 4),
              Text('With many measurements (iSpindel, Nautilis, or other device), data is automatically grouped for clarity. Dots show when zoomed in.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

/// Range selector with chips
class _RangeSelector extends StatelessWidget {
  const _RangeSelector({
    required this.currentRange,
    required this.onRangeChanged,
    required this.sincePitchingAvailable,
  });

  final ChartRange currentRange;
  final ValueChanged<ChartRange> onRangeChanged;
  final bool sincePitchingAvailable;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [
        for (final range in ChartRange.values)
          if (range != ChartRange.sincePitch || sincePitchingAvailable)
            ChoiceChip(
              label: Text(range.label),
              selected: currentRange == range,
              onSelected: (selected) {
                if (selected) onRangeChanged(range);
              },
              selectedColor: Theme.of(context).colorScheme.primaryContainer,
              labelStyle: TextStyle(
                fontSize: 12,
                color: currentRange == range
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : null,
              ),
            ),
      ],
    );
  }
}

/// The main chart widget
class ImprovedFermentationChart extends StatefulWidget {
  const ImprovedFermentationChart({
    super.key,
    required this.measurements,
    required this.useFahrenheit,
    required this.range,
    this.sincePitchingAt,
  });

  final List<Measurement> measurements;
  final bool useFahrenheit;
  final ChartRange range;
  final DateTime? sincePitchingAt;

  @override
  State<ImprovedFermentationChart> createState() => _ImprovedFermentationChartState();
}

class _ImprovedFermentationChartState extends State<ImprovedFermentationChart> {
  double? _viewMinX;
  double? _viewMaxX;
  double? _zoomScale; // null = fit to data

  @override
  Widget build(BuildContext context) {
    final filtered = _filterByRange(widget.measurements, widget.range, widget.sincePitchingAt);
    
    // Debug output
    debugPrint('ImprovedChart: Total measurements: ${widget.measurements.length}, Filtered: ${filtered.length}, Range: ${widget.range.label}');
    
    if (filtered.isEmpty) {
      return _buildEmptyState();
    }

    final aggregated = _HourlyAggregator.aggregate(filtered, maxBuckets: 150);
    final chartData = _ChartData.fromMeasurements(aggregated, widget.useFahrenheit);

    // Initialize viewport
    _viewMinX ??= chartData.dataMinX;
    _viewMaxX ??= chartData.dataMaxX;
    
    // Adaptive dots: hide if too many points visible in viewport
    final visiblePoints = chartData.sgSpots.where((s) => s.x >= _viewMinX! && s.x <= _viewMaxX!).length;
    final showDots = visiblePoints < 50; // Only show dots if less than 50 points visible

    final viewData = _ViewportData.compute(
      chartData: chartData,
      viewMinX: _viewMinX!,
      viewMaxX: _viewMaxX!,
      zoomScale: _zoomScale,
    );

    return Column(
      children: [
        // Chart
        GestureDetector(
          onScaleStart: (_) {
            _zoomScale ??= (_viewMaxX! - _viewMinX!) / (chartData.dataMaxX - chartData.dataMinX);
          },
          onScaleUpdate: (details) {
            if (chartData.dataMaxX - chartData.dataMinX < 0.01) return;

            setState(() {
              // Zoom
              final oldSpan = _viewMaxX! - _viewMinX!;
              final newSpan = oldSpan / details.scale;
              final targetSpan = math.max(
                newSpan,
                (chartData.dataMaxX - chartData.dataMinX) * 0.05,
              ).clamp(
                (chartData.dataMaxX - chartData.dataMinX) * 0.05,
                chartData.dataMaxX - chartData.dataMinX,
              );

              final center = (_viewMinX! + _viewMaxX!) / 2;
              var newMin = center - targetSpan / 2;
              var newMax = center + targetSpan / 2;

              // Pan
              if ((details.scale - 1.0).abs() < 0.001) {
                final dx = -details.focalPointDelta.dx * targetSpan / 300;
                newMin += dx;
                newMax += dx;
              }

              // Clamp to data bounds
              if (newMin < chartData.dataMinX) {
                newMin = chartData.dataMinX;
                newMax = newMin + targetSpan;
              }
              if (newMax > chartData.dataMaxX) {
                newMax = chartData.dataMaxX;
                newMin = newMax - targetSpan;
              }

              _viewMinX = newMin;
              _viewMaxX = newMax;
              _zoomScale = targetSpan / (chartData.dataMaxX - chartData.dataMinX);
            });
          },
          onDoubleTap: () {
            setState(() {
              _viewMinX = chartData.dataMinX;
              _viewMaxX = chartData.dataMaxX;
              _zoomScale = null;
            });
          },
          child: SizedBox(
            height: 320,
            child: LineChart(
              LineChartData(
                minX: _viewMinX!,
                maxX: _viewMaxX!,
                minY: viewData.sgMin,
                maxY: viewData.sgMax,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: math.max(0.001, viewData.sgInterval),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) {
                        final dt = chartData.labelTimes[value.roundToDouble()];
                        if (dt == null) return const SizedBox.shrink();
                        
                        // Calculate proper interval to show 4-6 labels max
                        final span = _viewMaxX! - _viewMinX!;
                        final targetTicks = span < 10 ? 3 : (span < 30 ? 4 : 5);
                        final tickInterval = span / targetTicks;
                        
                        // Find nearest tick position
                        var minDist = double.infinity;
                        for (var i = 0; i <= targetTicks; i++) {
                          final tickPos = _viewMinX! + i * tickInterval;
                          final dist = (tickPos - value).abs();
                          if (dist < minDist) {
                            minDist = dist;
                          }
                        }
                        
                        // Only show if we're very close to a tick position
                        if (minDist > tickInterval * 0.3) {
                          return const SizedBox.shrink();
                        }
                        
                        return Transform.rotate(
                          angle: -0.5,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              _formatTimeLabel(dt, span.round()),
                              style: const TextStyle(fontSize: 9),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    axisNameWidget: const Padding(
                      padding: EdgeInsets.only(bottom: 4.0),
                      child: Text(
                        'Specific Gravity',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                    axisNameSize: 22,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      interval: math.max(0.001, viewData.sgInterval),
                      getTitlesWidget: (value, meta) {
                        if ((value - meta.min).abs() < 1e-6 || (meta.max - value).abs() < 1e-6) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          value.toStringAsFixed(3),
                          style: const TextStyle(fontSize: 11),
                        );
                      },
                    ),
                  ),
                  rightTitles: AxisTitles(
                    axisNameWidget: Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Text(
                        viewData.showTemp
                            ? (widget.useFahrenheit ? 'Temp (°F)' : 'Temp (°C)')
                            : 'FSU (pt/day)',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                    axisNameSize: 22,
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 52,
                      interval: math.max(0.01, (viewData.sgMax - viewData.sgMin) / 5),
                      getTitlesWidget: (leftCoord, meta) {
                        if ((leftCoord - meta.min).abs() < 1e-6 || (meta.max - leftCoord).abs() < 1e-6) {
                          return const SizedBox.shrink();
                        }
                        
                        final rightVal = viewData.rightMin +
                            (viewData.rightMax - viewData.rightMin) *
                                ((leftCoord - viewData.sgMin) / (viewData.sgMax - viewData.sgMin));

                        if (viewData.showTemp) {
                          return Text(
                            widget.useFahrenheit
                                ? '${rightVal.toStringAsFixed(0)}°F'
                                : '${rightVal.toStringAsFixed(1)}°C',
                            style: const TextStyle(fontSize: 11),
                          );
                        } else {
                          return Text(
                            '${rightVal.toStringAsFixed(0)} pt/d',
                            style: const TextStyle(fontSize: 11),
                          );
                        }
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(color: Colors.grey.shade300),
                ),
                lineBarsData: [
                  // SG line
                  LineChartBarData(
                    spots: chartData.sgSpots,
                    isCurved: false,
                    barWidth: 2.5,
                    color: Colors.blue,
                    dotData: FlDotData(
                      show: showDots,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 3,
                          color: Colors.blue,
                          strokeWidth: 1,
                          strokeColor: Colors.white,
                        );
                      },
                    ),
                  ),
                  // Temperature line
                  if (viewData.tempSpotsScaled.isNotEmpty)
                    LineChartBarData(
                      spots: viewData.tempSpotsScaled,
                      isCurved: false,
                      barWidth: 2.5,
                      color: Colors.red.shade600,
                      dotData: FlDotData(
                        show: showDots,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 3,
                            color: Colors.red.shade600,
                            strokeWidth: 1,
                            strokeColor: Colors.white,
                          );
                        },
                      ),
                    ),
                  // FSU line
                  if (viewData.fsuSpotsScaled.isNotEmpty)
                    LineChartBarData(
                      spots: viewData.fsuSpotsScaled,
                      isCurved: false,
                      barWidth: 2.5,
                      color: Colors.green.shade700,
                      dotData: const FlDotData(show: false), // FSU is smoothed, don't show dots
                    ),
                ],
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    // Changed from tooltipBgColor to getTooltipColor
                    getTooltipColor: (spot) => Colors.blueGrey.shade800,
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItems: (spots) {
                      if (spots.isEmpty) return [];
                      
                      final xVal = spots.first.x;
                      final sg = chartData.xToSg[xVal];
                      final temp = chartData.xToTemp[xVal];
                      final fsu = chartData.xToFsu[xVal];

                      final items = <LineTooltipItem>[];
                      
                      // Always show SG if available
                      if (sg != null) {
                        items.add(LineTooltipItem(
                          'SG: ${sg.toStringAsFixed(3)}\n',
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ));
                      }
                      
                      // Show temp if available
                      if (temp != null) {
                        items.add(LineTooltipItem(
                          widget.useFahrenheit
                              ? 'Temp: ${temp.toStringAsFixed(1)}°F\n'
                              : 'Temp: ${temp.toStringAsFixed(1)}°C\n',
                          const TextStyle(color: Colors.white),
                        ));
                      }
                      
                      // Show FSU if calculated
                      if (fsu != null && fsu > 0) {
                        items.add(LineTooltipItem(
                          'FSU: ${fsu.toStringAsFixed(1)} pt/day',
                          const TextStyle(color: Colors.white),
                        ));
                      }

                      // Pad to match spots length
                      while (items.length < spots.length) {
                        items.add(const LineTooltipItem('', TextStyle()));
                      }
                      
                      return items;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Legend - larger and clearer
        _LegendRow(
          useFahrenheit: widget.useFahrenheit,
          hasTempData: chartData.xToTemp.isNotEmpty,
          hasFsuData: chartData.xToFsu.isNotEmpty,
        ),
        
        const SizedBox(height: 12),
        
        // Reset zoom button (only show if zoomed)
        if (_zoomScale != null && _zoomScale! < 0.99)
          TextButton.icon(
            onPressed: () {
              setState(() {
                _viewMinX = chartData.dataMinX;
                _viewMaxX = chartData.dataMaxX;
                _zoomScale = null;
              });
            },
            icon: const Icon(Icons.zoom_out_map, size: 16),
            label: const Text('Reset Zoom'),
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      height: 320,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey.shade50,
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.show_chart, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'No measurements yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Add measurements to see fermentation progress',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  List<Measurement> _filterByRange(
    List<Measurement> measurements,
    ChartRange range,
    DateTime? sincePitchingAt,
  ) {
    if (measurements.isEmpty) return [];

    final duration = range.duration;
    if (duration == null) {
      // "Since pitching" - show all
      return measurements;
    }

    final cutoff = DateTime.now().subtract(duration);
    return measurements.where((m) => m.timestamp.isAfter(cutoff)).toList();
  }

  String _formatTimeLabel(DateTime dt, int dataSpan) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    // Format based on how much data is visible
    if (dataSpan < 5) {
      // Very zoomed in - show time with minutes
      return '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (dataSpan < 20) {
      // Moderately zoomed - show hour
      return '${dt.hour}:00';
    } else if (diff.inDays > 5) {
      // Zoomed out far - show date
      return '${dt.month}/${dt.day}';
    } else if (diff.inDays > 1) {
      // Multiple days - show day and hour
      return '${dt.day}d ${dt.hour}h';
    } else {
      // Within a day - show hour
      return '${dt.hour}:00';
    }
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.useFahrenheit,
    required this.hasTempData,
    required this.hasFsuData,
  });

  final bool useFahrenheit;
  final bool hasTempData;
  final bool hasFsuData;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        const _LegendItem(color: Colors.blue, label: 'Specific Gravity (SG)'),
        if (hasTempData)
          _LegendItem(
            color: Colors.red.shade600,
            label: useFahrenheit ? 'Temperature (°F)' : 'Temperature (°C)',
          ),
        if (hasFsuData)
          _LegendItem(color: Colors.green.shade700, label: 'Fermentation Speed (FSU)'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

/// Data structure for chart calculations
class _ChartData {
  final List<FlSpot> sgSpots;
  final Map<double, double> xToSg;
  final Map<double, double> xToTemp;
  final Map<double, double> xToFsu;
  final Map<double, DateTime> labelTimes;
  final double dataMinX;
  final double dataMaxX;

  _ChartData({
    required this.sgSpots,
    required this.xToSg,
    required this.xToTemp,
    required this.xToFsu,
    required this.labelTimes,
    required this.dataMinX,
    required this.dataMaxX,
  });

  factory _ChartData.fromMeasurements(List<Measurement> measurements, bool useFahrenheit) {
    if (measurements.isEmpty) {
      return _ChartData(
        sgSpots: [],
        xToSg: {},
        xToTemp: {},
        xToFsu: {},
        labelTimes: {},
        dataMinX: 0,
        dataMaxX: 1,
      );
    }

    final sgSpots = <FlSpot>[];
    final xToSg = <double, double>{};
    final xToTemp = <double, double>{};
    final xToFsu = <double, double>{};
    final labelTimes = <double, DateTime>{};

    for (var i = 0; i < measurements.length; i++) {
      final m = measurements[i];
      final x = i.toDouble();
      labelTimes[x] = m.timestamp;

      // SG
      final sg = m.gravity ?? (m.brix != null ? _brixToSg(m.brix!) : null);
      if (sg != null) {
        sgSpots.add(FlSpot(x, sg));
        xToSg[x] = sg;
      }

      // Temperature
      if (m.temperature != null) {
        final temp = useFahrenheit ? _celsiusToFahrenheit(m.temperature!) : m.temperature!;
        xToTemp[x] = temp;
      }

      // FSU (Fermentation Speed Units) - calculate from SG slope
      if (i > 0 && sg != null) {
        final prevSg = xToSg[x - 1];
        if (prevSg != null) {
          final dt = m.timestamp.difference(measurements[i - 1].timestamp);
          if (dt.inMinutes > 0) {
            final sgDrop = prevSg - sg; // positive if dropping
            final pointsPerDay = (sgDrop * 1000) / dt.inMinutes * 1440;
            xToFsu[x] = pointsPerDay.clamp(0, 100); // FSU can't be negative or unreasonably high
          }
        }
      }
    }

    return _ChartData(
      sgSpots: sgSpots,
      xToSg: xToSg,
      xToTemp: xToTemp,
      xToFsu: xToFsu,
      labelTimes: labelTimes,
      dataMinX: 0,
      dataMaxX: (measurements.length - 1).toDouble(),
    );
  }

  static double _brixToSg(double brix) {
    return 1.0 + (brix / (258.6 - (brix / 258.2) * 227.1));
  }

  static double _celsiusToFahrenheit(double c) {
    return c * 9.0 / 5.0 + 32.0;
  }
}

/// Viewport scaling calculations
class _ViewportData {
  final double sgMin;
  final double sgMax;
  final double sgInterval;
  final double rightMin;
  final double rightMax;
  final bool showTemp;
  final List<FlSpot> tempSpotsScaled;
  final List<FlSpot> fsuSpotsScaled;

  _ViewportData({
    required this.sgMin,
    required this.sgMax,
    required this.sgInterval,
    required this.rightMin,
    required this.rightMax,
    required this.showTemp,
    required this.tempSpotsScaled,
    required this.fsuSpotsScaled,
  });

  factory _ViewportData.compute({
    required _ChartData chartData,
    required double viewMinX,
    required double viewMaxX,
    double? zoomScale,
  }) {
    // Get SG values in viewport
    final sgInView = chartData.sgSpots
        .where((s) => s.x >= viewMinX && s.x <= viewMaxX)
        .map((s) => s.y)
        .toList();

    double sgMin, sgMax;
    if (sgInView.isEmpty) {
      sgMin = 0.990;
      sgMax = 1.100;
    } else {
      sgMin = sgInView.reduce(math.min);
      sgMax = sgInView.reduce(math.max);
      
      // Ensure minimum range to prevent zero intervals
      if ((sgMax - sgMin).abs() < 0.001) {
        final center = (sgMin + sgMax) / 2;
        sgMin = center - 0.005;
        sgMax = center + 0.005;
      } else {
        final padding = (sgMax - sgMin) * 0.1;
        sgMin -= padding;
        sgMax += padding;
      }
    }

    // Nice interval for SG axis (ensure never zero)
    final rawInterval = (sgMax - sgMin) / 5;
    final sgInterval = _niceInterval(rawInterval);
    
    // Final safety check
    final safeInterval = sgInterval > 0 ? sgInterval : 0.01;

    // Decide: show temperature or FSU on right axis?
    final tempInView = chartData.xToTemp.entries
        .where((e) => e.key >= viewMinX && e.key <= viewMaxX)
        .map((e) => e.value)
        .toList();
    final fsuInView = chartData.xToFsu.entries
        .where((e) => e.key >= viewMinX && e.key <= viewMaxX)
        .map((e) => e.value)
        .toList();

    final showTemp = tempInView.isNotEmpty;
    
    double rightMin, rightMax;
    if (showTemp && tempInView.isNotEmpty) {
      rightMin = tempInView.reduce(math.min);
      rightMax = tempInView.reduce(math.max);
      final padding = (rightMax - rightMin) * 0.1;
      rightMin -= padding;
      rightMax += padding;
    } else if (fsuInView.isNotEmpty) {
      rightMin = 0;
      rightMax = fsuInView.reduce(math.max) * 1.2;
    } else {
      rightMin = 0;
      rightMax = 10;
    }

    // Scale temperature spots to SG space
    final tempSpotsScaled = <FlSpot>[];
    if (showTemp) {
      for (final entry in chartData.xToTemp.entries) {
        final sgY = _mapToSgSpace(entry.value, rightMin, rightMax, sgMin, sgMax);
        tempSpotsScaled.add(FlSpot(entry.key, sgY));
      }
    }

    // Scale FSU spots to SG space
    final fsuSpotsScaled = <FlSpot>[];
    if (!showTemp && fsuInView.isNotEmpty) {
      for (final entry in chartData.xToFsu.entries) {
        final sgY = _mapToSgSpace(entry.value, rightMin, rightMax, sgMin, sgMax);
        fsuSpotsScaled.add(FlSpot(entry.key, sgY));
      }
    }

    return _ViewportData(
      sgMin: sgMin,
      sgMax: sgMax,
      sgInterval: safeInterval,
      rightMin: rightMin,
      rightMax: rightMax,
      showTemp: showTemp,
      tempSpotsScaled: tempSpotsScaled,
      fsuSpotsScaled: fsuSpotsScaled,
    );
  }

  static double _mapToSgSpace(double val, double rMin, double rMax, double sgMin, double sgMax) {
    final rSpan = rMax - rMin;
    if (rSpan.abs() < 1e-9) return sgMin;
    return sgMin + (val - rMin) / rSpan * (sgMax - sgMin);
  }

  static double _niceInterval(double rawInterval) {
    if (rawInterval <= 0) return 0.01;
    final exp = (math.log(rawInterval) / math.ln10).floor();
    final f = rawInterval / math.pow(10, exp);
    double niceFraction;
    if (f <= 1.5) {
      niceFraction = 1.0;
    } else if (f <= 3.5) {
      niceFraction = 2.0;
    } else if (f <= 7.5) {
      niceFraction = 5.0;
    } else {
      niceFraction = 10.0;
    }
    return niceFraction * math.pow(10, exp);
  }
}
