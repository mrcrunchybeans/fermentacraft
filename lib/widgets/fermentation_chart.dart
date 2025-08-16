import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/measurement.dart';
import '../models/fermentation_stage.dart';
import '../models/settings_model.dart';

class FermentationChartWidget extends StatefulWidget {
  final List<Measurement> measurements;
  final List<FermentationStage> stages;
  final void Function(Measurement)? onEditMeasurement;
  final void Function(Measurement)? onDeleteMeasurement;
  final VoidCallback? onManageStages;

  const FermentationChartWidget({
    super.key,
    required this.measurements,
    required this.stages,
    this.onEditMeasurement,
    this.onDeleteMeasurement,
    this.onManageStages,
  });

  @override
  State<FermentationChartWidget> createState() =>
      _FermentationChartWidgetState();
}

class _FermentationChartWidgetState extends State<FermentationChartWidget> {
  double? _touchedX;
  Offset? _touchPosition;
  final GlobalKey _chartAreaKey = GlobalKey();
  bool _showMeasurements = true;

  // --- Touch Handling Logic ---
  void _updateTouchPosition(Offset localPosition, double maxX) {
    if (!mounted || _chartAreaKey.currentContext == null) return;
    final RenderBox renderBox =
        _chartAreaKey.currentContext!.findRenderObject() as RenderBox;
    final chartWidth = renderBox.size.width;
    final touchedX = (localPosition.dx / chartWidth) * maxX;
    if (touchedX >= 0 && touchedX <= maxX) {
      setState(() {
        _touchedX = touchedX;
        _touchPosition = localPosition;
      });
    }
  }

  // Add this helper method inside your _FermentationChartWidgetState class
String _formatTemperature(double tempCelsius, String unitSetting) {
  final isFahrenheit = unitSetting.contains('F');
  final displayUnit = isFahrenheit ? 'F' : 'C';

  final tempValue = isFahrenheit
      ? (tempCelsius * 9 / 5) + 32  // Convert to F
      : tempCelsius;                // Already C

  return "${tempValue.toStringAsFixed(1)}°$displayUnit";
}

  void _handleTap(
      TapUpDetails details, List<Measurement> sortedMeasurements, double maxX) {
    if (widget.onEditMeasurement == null ||
        _chartAreaKey.currentContext == null) {
      return;
    }
    final RenderBox renderBox =
        _chartAreaKey.currentContext!.findRenderObject() as RenderBox;
    final chartWidth = renderBox.size.width;
    final tapX = (details.localPosition.dx / chartWidth) * maxX;
    Measurement? closestMeasurement;
    double closestDistance = double.infinity;
    final startDate = sortedMeasurements.first.timestamp;
    for (final m in sortedMeasurements) {
      final mX = m.timestamp.difference(startDate).inHours.toDouble();
      final distance = (mX - tapX).abs();
      if (distance < closestDistance) {
        closestDistance = distance;
        closestMeasurement = m;
      }
    }
    if (closestDistance < 12 && closestMeasurement != null) {
      widget.onEditMeasurement!(closestMeasurement);
    }
    _clearTouchPosition();
  }

  void _clearTouchPosition() {
    setState(() {
      _touchedX = null;
      _touchPosition = null;
    });
  }

  // --- Data Processing Helpers ---
  double _normalize(double value, double valueMin, double valueMax,
      double scaleMin, double scaleMax) {
    if ((valueMax - valueMin).abs() < 1e-9) return scaleMin;
    return scaleMin +
        ((value - valueMin) * (scaleMax - scaleMin) / (valueMax - valueMin));
  }

  double _deNormalize(double normalizedValue, double valueMin, double valueMax,
      double scaleMin, double scaleMax) {
    if ((scaleMax - scaleMin).abs() < 1e-9) return valueMin;
    return valueMin +
        ((normalizedValue - scaleMin) * (valueMax - valueMin) /
            (scaleMax - scaleMin));
  }

  double _getDynamicXInterval(double maxX, double chartWidth) {
    if (chartWidth <= 0) return 168;
    final hoursPerPixel = maxX / chartWidth;
    if (hoursPerPixel < 0.5) return 24;
    if (hoursPerPixel < 1) return 48;
    if (hoursPerPixel < 2) return 7 * 24;
    if (hoursPerPixel < 8) return 14 * 24;
    return 30 * 24;
  }

  double? _getInterpolatedY(List<FlSpot> spots, double x) {
    if (spots.isEmpty || x < spots.first.x || x > spots.last.x) return null;
    for (int i = 0; i < spots.length - 1; i++) {
      if (spots[i].x <= x && spots[i + 1].x >= x) {
        final x1 = spots[i].x;
        final y1 = spots[i].y;
        final x2 = spots[i + 1].x;
        final y2 = spots[i + 1].y;
        final slope = (x2 - x1) == 0 ? 0 : (y2 - y1) / (x2 - x1);
        return y1 + slope * (x - x1);
      }
    }
    return spots.last.y;
  }

  @override
  Widget build(BuildContext context) {
    final sortedMeasurements = [...widget.measurements]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: 16),
        if (sortedMeasurements.length >= 2)
          _buildChart(sortedMeasurements)
        else
          SizedBox(
            height: 350,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Add another measurement to see the graph.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        _buildMeasurementToggle(),
        if (_showMeasurements)
          _buildMeasurementList(sortedMeasurements),
      ],
    );
  }

  // --- Widget Builder Helpers ---
  Widget _buildChart(List<Measurement> sortedMeasurements) {
    final settings = context.watch<SettingsModel>();
    final startDate = sortedMeasurements.first.timestamp;

    final temps = sortedMeasurements
        .map((m) => m.temperature)
        .whereType<double>()
        .map((t) => settings.unit == 'F' ? (t * 9 / 5) + 32 : t) // FIXED
        .toList();
        
    final sgs = sortedMeasurements
        .map((m) => m.sgCorrected ?? m.gravity)
        .whereType<double>()
        .toList();

    final fsus = sortedMeasurements
        .map((m) => m.fsuspeed)
        .whereType<double>()
        .toList();

    final minTemp = temps.isNotEmpty ? temps.reduce(min) : (settings.unit == 'F' ? 60 : 15);
    final maxTemp = temps.isNotEmpty ? temps.reduce(max) : (settings.unit == 'F' ? 80 : 27);
    final tempPadding = (maxTemp - minTemp).abs() < 1.0 ? 5.0 : (maxTemp - minTemp) * 0.1;
    final chartMinY = (minTemp - tempPadding).floorToDouble();
    final chartMaxY = (maxTemp + tempPadding).ceilToDouble();
    final chartMidY = chartMinY + (chartMaxY - chartMinY) / 2;

    final minSg = sgs.isNotEmpty ? sgs.reduce(min) : 1.000;
    final maxSg = sgs.isNotEmpty ? sgs.reduce(max) : 1.060;
    final minFsu = fsus.isNotEmpty ? fsus.reduce(min) : 0.0;
    final maxFsu = fsus.isNotEmpty ? fsus.reduce(max) : 100.0;

    final tempSpots = <FlSpot>[];
    final gravitySpots = <FlSpot>[];
    final fsuSpots = <FlSpot>[];

    for (final m in sortedMeasurements) {
      final x = m.timestamp.difference(startDate).inHours.toDouble();
      if (m.temperature != null) {
        final tempValue = settings.unit == 'F' ? (m.temperature! * 9 / 5) + 32 : m.temperature!; // FIXED
        tempSpots.add(FlSpot(x, tempValue));
      }
      final sgValue = m.sgCorrected ?? m.gravity;
      if (sgValue != null) {
        gravitySpots.add(
            FlSpot(x, _normalize(sgValue, minSg, maxSg, chartMinY, chartMidY)));
      }
      if (m.fsuspeed != null) {
        fsuSpots.add(FlSpot(
            x, _normalize(m.fsuspeed!, minFsu, maxFsu, chartMidY, chartMaxY)));
      }
    }

    final maxX = sortedMeasurements.last.timestamp.difference(startDate).inHours.toDouble();

    return Column(
      children: [
        SizedBox(
          height: 350,
          child: GestureDetector(
            onTapUp: (details) => _handleTap(details, sortedMeasurements, maxX),
            onPanDown: (details) => _updateTouchPosition(details.localPosition, maxX),
            onPanUpdate: (details) => _updateTouchPosition(details.localPosition, maxX),
            onPanEnd: (details) => _clearTouchPosition(),
            child: MouseRegion(
              onHover: (event) => _updateTouchPosition(event.localPosition, maxX),
              onExit: (event) => _clearTouchPosition(),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  LayoutBuilder(
                    key: _chartAreaKey,
                    builder: (context, constraints) {
                      const reservedSpaceForYLabels = 40.0 + 40.0;
                      final plotAreaWidth = constraints.maxWidth - reservedSpaceForYLabels;
                      final xInterval = _getDynamicXInterval(maxX, plotAreaWidth);

                      return LineChart(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.linear,
                        LineChartData(
                          minY: chartMinY, maxY: chartMaxY, minX: 0, maxX: maxX,
                          lineTouchData: const LineTouchData(enabled: false),
                          titlesData: _buildTitlesData(chartMinY, chartMaxY, chartMidY, minSg, maxSg, minFsu, maxFsu, startDate, xInterval),
                          gridData: _buildGridData(),
                          borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade400)),
                          rangeAnnotations: _buildStageAnnotations(widget.stages, startDate),
                          lineBarsData: [
                            _buildLineBarData(tempSpots, Colors.blueAccent),
                            _buildLineBarData(
                              gravitySpots,
                              Colors.green,
                              getDotPainter: (spot, percent, barData, index) {
                                if (sortedMeasurements[index].interventions!.isNotEmpty) {
                                  return FlDotCirclePainter(radius: 6, color: Colors.orange.shade700, strokeWidth: 2, strokeColor: Colors.white);
                                }
                                return FlDotCirclePainter(radius: 3, color: Colors.green, strokeWidth: 1.5, strokeColor: Colors.white);
                              },
                            ),
                            _buildLineBarData(fsuSpots, Colors.purple),
                          ],
                        ),
                      );
                    },
                  ),
                  if (_touchedX != null && _touchPosition != null)
                    Positioned(
                      left: _touchPosition!.dx, top: 0, bottom: 0,
                      child: Container(width: 1.5, color: Colors.redAccent.withAlpha(150)),
                    ),
                  if (_touchedX != null && _touchPosition != null)
                    Positioned(
                      left: _touchPosition!.dx > MediaQuery.of(context).size.width / 2 ? null : _touchPosition!.dx + 12,
                      right: _touchPosition!.dx > MediaQuery.of(context).size.width / 2 ? MediaQuery.of(context).size.width - _touchPosition!.dx + 12 : null,
                      top: _touchPosition!.dy - 20,
                      child: _buildCustomTooltip(startDate, _touchedX!, tempSpots, gravitySpots, fsuSpots, chartMinY, chartMaxY, chartMidY, minSg, maxSg, minFsu, maxFsu),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildLegend(),
      ],
    );
  }

  Widget _buildMeasurementList(List<Measurement> measurements) {
    if (measurements.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Center(
            child: Text("No measurements have been added yet.",
                style: TextStyle(color: Colors.grey.shade600))),
      );
    }

    final settings = context.watch<SettingsModel>();
    final dateFormat = DateFormat('M/d h:mm a');

    return Column(
      children: measurements.reversed.map((m) {
        final temp = m.temperature != null ? _formatTemperature(m.temperature!, settings.unit) : "—";
        final ta = m.ta?.toStringAsFixed(1) ?? "—";
        final sgRaw = m.gravity?.toStringAsFixed(3) ?? "—";
        final sgCorr = m.sgCorrected?.toStringAsFixed(3) ?? "—";

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      dateFormat.format(m.timestamp),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    SizedBox(
                      width: 40,
                      child: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (value) {
                          if (value == 'edit') {
                            widget.onEditMeasurement?.call(m);
                          } else if (value == 'delete') {
                            widget.onDeleteMeasurement?.call(m);
                          }
                        },
                        itemBuilder: (context) => const [
                           PopupMenuItem(value: 'edit', child: Text('Edit')),
                           PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _DataPoint(label: 'SG', value: sgRaw),
                    _DataPoint(label: 'SG Corr', value: sgCorr),
                    _DataPoint(label: 'Temp', value: temp),
                    _DataPoint(label: 'TA', value: ta),
                  ],
                ),
                if (m.interventions!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6.0,
                    runSpacing: 4.0,
                    children: m.interventions!.map((i) => Chip(label: Text(i))).toList(),
                  )
                ]
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Text("Fermentation Chart", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const Spacer(),
        if (widget.onManageStages != null)
          TextButton.icon(
            onPressed: widget.onManageStages,
            icon: const Icon(Icons.edit, size: 16),
            label: const Text("Manage Stages"),
          ),
      ],
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [
        const _LegendItem(color: Colors.blueAccent, label: "Temperature"),
        const _LegendItem(color: Colors.green, label: "Corrected SG"),
        const _LegendItem(color: Colors.purple, label: "FSU"),
        _LegendItem(color: Colors.orange.shade700, label: "Intervention"),
      ],
    );
  }

  // FIXED: Restored the tooltip implementation
  Widget _buildCustomTooltip(
    DateTime startDate, double touchedX, List<FlSpot> tempSpots, List<FlSpot> gravitySpots, List<FlSpot> fsuSpots,
    double chartMinY, double chartMaxY, double chartMidY, double minSg, double maxSg, double minFsu, double maxFsu,
  ) {
    final settings = context.read<SettingsModel>();
    final time = startDate.add(Duration(microseconds: (touchedX * Duration.microsecondsPerHour).round()));
    final timeLabel = "${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";

    final tempY = _getInterpolatedY(tempSpots, touchedX);
    final sgYNormalized = _getInterpolatedY(gravitySpots, touchedX);
    final fsuYNormalized = _getInterpolatedY(fsuSpots, touchedX);

    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.black.withAlpha(34),
            borderRadius: BorderRadius.circular(4)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(timeLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            if (tempY != null)
              Text(
                  "Temp: ${tempY.toStringAsFixed(1)}°${settings.unit.toUpperCase().replaceAll('°', '')}", // Safely remove any extra °
                  style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 12, fontWeight: FontWeight.w600)),
            if (sgYNormalized != null)
              Text(
                  "SG: ${_deNormalize(sgYNormalized, minSg, maxSg, chartMinY, chartMidY).toStringAsFixed(3)}",
                  style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 12, fontWeight: FontWeight.w600)),
            if (fsuYNormalized != null)
              Text(
                  "FSU: ${_deNormalize(fsuYNormalized, minFsu, maxFsu, chartMidY, chartMaxY).toStringAsFixed(1)}",
                  style: const TextStyle(color: Colors.purpleAccent, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildMeasurementToggle() {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => setState(() => _showMeasurements = !_showMeasurements),
        icon: Icon(_showMeasurements ? Icons.expand_less : Icons.expand_more),
        label: Text(_showMeasurements ? "Hide Measurements" : "Show Measurements"),
      ),
    );
  }

  // FIXED: Changed the type from the non-existent FlDotPainterCallback to the correct function signature
  LineChartBarData _buildLineBarData(List<FlSpot> spots, Color color, {FlDotPainter Function(FlSpot, double, LineChartBarData, int)? getDotPainter}) {
    return LineChartBarData(
      spots: spots.where((spot) => spot.y.isFinite).toList(),
      isCurved: true,
      barWidth: 2.5,
      color: color,
      dotData: FlDotData(
        show: true,
        getDotPainter: getDotPainter ?? (spot, percent, barData, index) => FlDotCirclePainter(
            radius: 3,
            color: color,
            strokeWidth: 1.5,
            strokeColor: Colors.white),
      ),
    );
  }

RangeAnnotations _buildStageAnnotations(
      List<FermentationStage> stages, DateTime startDate) {
    final List<Color> stageColors = [
      Colors.orange, Colors.blue, Colors.green, Colors.purple,
      Colors.pink, Colors.teal, Colors.yellow
    ];
    return RangeAnnotations(
      verticalRangeAnnotations: stages.asMap().entries.map((entry) {
        final index = entry.key;
        final stage = entry.value;
        if (stage.startDate == null) return null;
        final from = stage.startDate!.difference(startDate).inHours.toDouble();
        final to = from + (stage.durationDays * 24);
        final color = stageColors[index % stageColors.length];
        return VerticalRangeAnnotation(
            x1: from, x2: to, color: color.withAlpha(34));
      }).whereType<VerticalRangeAnnotation>().toList(),
    );
  }
  
  FlGridData _buildGridData() {
    return FlGridData(
        show: true,
        drawVerticalLine: true,
        getDrawingHorizontalLine: (value) =>
            FlLine(color: Colors.grey.withAlpha(50), strokeWidth: 1),
        getDrawingVerticalLine: (value) =>
            FlLine(color: Colors.grey.withAlpha(50), strokeWidth: 1));
  }
  
  FlTitlesData _buildTitlesData(
    double chartMinY, double chartMaxY, double chartMidY, double minSg, double maxSg,
    double minFsu, double maxFsu, DateTime startDate, double xInterval,
  ) {
    final settings = context.read<SettingsModel>();
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        axisNameWidget:
            const Text("Fermentation Timeline", style: TextStyle(fontSize: 10)),
        axisNameSize: 20,
        sideTitles: SideTitles(
          showTitles: true,
          interval: xInterval,
          getTitlesWidget: (value, meta) {
            if (value < 0) return const SizedBox.shrink();
            final days = value / 24;
            if (days < 7) {
              return Text("Day ${days.round() + 1}",
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.bold));
            } else {
              final date = startDate.add(Duration(hours: value.toInt()));
              return Text("${date.month}/${date.day}",
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.bold));
            }
          },
        ),
      ),
      leftTitles: AxisTitles(
        axisNameWidget:
            Text("Temp (${settings.unit.toUpperCase()})", style: const TextStyle(fontSize: 12)),
        axisNameSize: 24,
        sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: (chartMaxY - chartMinY) / 4),
      ),
      rightTitles: AxisTitles(
        axisNameWidget:
            const Text("SG / FSU", style: TextStyle(fontSize: 12)),
        axisNameSize: 24,
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          interval: (chartMaxY - chartMinY) / 8,
          getTitlesWidget: (value, meta) {
            if (value <= chartMinY || value >= chartMaxY) {
              return const SizedBox.shrink();
            }
            if (value < chartMidY) {
              final deNormalizedSg =
                  _deNormalize(value, minSg, maxSg, chartMinY, chartMidY);
              return Text(deNormalizedSg.toStringAsFixed(3),
                  style:
                      const TextStyle(color: Colors.green, fontSize: 10));
            } else {
              final deNormalizedFsu =
                  _deNormalize(value, minFsu, maxFsu, chartMidY, chartMaxY);
              return Text(deNormalizedFsu.toStringAsFixed(0),
                  style:
                      const TextStyle(color: Colors.purple, fontSize: 10));
            }
          },
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 12, height: 12, color: color),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 12))
    ]);
  }
}

class _DataPoint extends StatelessWidget {
  final String label;
  final String value;
  const _DataPoint({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}
