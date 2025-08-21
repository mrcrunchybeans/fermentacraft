// lib/pages/so2_calculator_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fermentacraft/utils/snacks.dart';
import 'package:fermentacraft/services/feature_gate.dart';
import 'package:fermentacraft/widgets/soft_lock_overlay.dart';
import 'package:provider/provider.dart';

// adjust this import to wherever CiderUtils lives
import '../../utils/utils.dart'; // CiderUtils.recommendedFreeSO2ppm

class So2CalculatorPage extends StatelessWidget {
  const So2CalculatorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final fg = context.watch<FeatureGate>();
    return Scaffold(
      appBar: AppBar(title: const Text('SO₂ Estimator')),
      body: SoftLockOverlay(
        allow: fg.allowSO2,
        message: 'SO₂ Estimator is a Premium feature',
        child: const So2CalculatorBody(),
      ),
    );
  }
}

class So2CalculatorBody extends StatefulWidget {
  const So2CalculatorBody({super.key});

  @override
  State<So2CalculatorBody> createState() => _So2CalculatorBodyState();
}

class _So2CalculatorBodyState extends State<So2CalculatorBody> {
  // Input State
  double pH = 3.4;
  int customPPM = 50;
  bool useRecommendedPPM = true;
  double volume = 5.0;
  bool useGallons = true;
  bool isPerry = false;
  String selectedSource = 'Potassium Metabisulphite';

  // Result State
  String resultText = '';
  String sourceNote = '';
  String? warning;

  // Controllers
  final pHController = TextEditingController();
  final volumeController = TextEditingController();
  final ppmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    pHController.text = pH.toStringAsFixed(2);
    volumeController.text = volume.toStringAsFixed(1);
    ppmController.text = customPPM.toString();
    _updateCalculations();
  }

  @override
  void dispose() {
    pHController.dispose();
    volumeController.dispose();
    ppmController.dispose();
    super.dispose();
  }

  void _updateCalculations() {
    final recommendedPPM = CiderUtils.recommendedFreeSO2ppm(pH);
    final basePPM = useRecommendedPPM ? recommendedPPM : customPPM.toDouble();
    final actualPPM = isPerry ? basePPM + 50 : basePPM;
    final liters = useGallons ? volume * 3.78541 : volume;

    String calculatedResult = '';
    String calculatedSourceNote = '';

    switch (selectedSource) {
      case 'Potassium Metabisulphite':
        final grams = (actualPPM * liters) / 1000 / 0.50;
        calculatedResult = "${grams.toStringAsFixed(2)} grams of K-Meta";
        calculatedSourceNote = "Using 50% SO₂ yield from Potassium Metabisulphite.";
        break;
      case 'Sodium Metabisulphite':
        final gramsLow = (actualPPM * liters) / 1000 / 0.60;
        final gramsHigh = (actualPPM * liters) / 1000 / 0.55;
        calculatedResult = "${gramsLow.toStringAsFixed(2)}–${gramsHigh.toStringAsFixed(2)} grams of Na-Meta";
        calculatedSourceNote = "Using 55–60% SO₂ yield from Sodium Metabisulphite.";
        break;
      case 'Campden Tablets':
        final tablets = (actualPPM * liters) / (50 * 4.546);
        calculatedResult = "${tablets.toStringAsFixed(1)} Campden tablets";
        calculatedSourceNote = "1 tablet = 50 ppm SO₂ in 1 imperial gallon (4.546 L).";
        break;
      case '5% Stock Solution':
        final mL = actualPPM * liters / 50;
        calculatedResult = "${mL.toStringAsFixed(2)} mL of 5% SO₂ stock solution";
        calculatedSourceNote = "Mix 10g K-Meta with 100mL water (SG ~1.0275). 1mL/L ≈ 50 ppm.";
        break;
    }

    setState(() {
      resultText = calculatedResult;
      sourceNote = calculatedSourceNote;
      warning = actualPPM > 200
          ? "⚠️ Warning: SO₂ level above 200 ppm may be unsafe for consumption."
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final recommendedPPM = CiderUtils.recommendedFreeSO2ppm(pH);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text("SO₂ Dosage Calculator", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text("Must pH"),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: pH,
                min: 2.8,
                max: 4.2,
                divisions: 140,
                label: pH.toStringAsFixed(2),
                onChanged: (val) {
                  setState(() {
                    pH = val;
                    pHController.text = val.toStringAsFixed(2);
                  });
                  _updateCalculations();
                },
              ),
            ),
            SizedBox(
              width: 70,
              child: TextField(
                controller: pHController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (val) {
                  final parsed = double.tryParse(val);
                  if (parsed != null && parsed >= 2.8 && parsed <= 4.2) {
                    setState(() => pH = parsed);
                    _updateCalculations();
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text("Recommended Free SO₂: ${recommendedPPM.toStringAsFixed(0)} ppm", style: const TextStyle(color: Colors.teal)),
        if (warning != null) ...[
          const SizedBox(height: 4),
          Text(warning!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 8),
        if (pH <= 3.0)
          const Text("Note: pH ≤ 3.0 is generally protective; sulfite addition may not be necessary.", style: TextStyle(fontSize: 13)),
        if (pH >= 3.8)
          const Text("Note: pH ≥ 3.8 — consider blending with more acidic juice to increase protection.", style: TextStyle(fontSize: 13)),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text("Use recommended PPM from pH"),
          value: useRecommendedPPM,
          onChanged: (val) {
            setState(() {
              useRecommendedPPM = val;
              if (!val) {
                final currentRecommended = CiderUtils.recommendedFreeSO2ppm(pH).round();
                customPPM = currentRecommended;
                ppmController.text = currentRecommended.toString();
              }
            });
            _updateCalculations();
          },
        ),
        if (!useRecommendedPPM)
          TextField(
            controller: ppmController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: "Target Free SO₂ (ppm)"),
            onChanged: (val) {
              final parsed = int.tryParse(val);
              if (parsed != null) {
                setState(() => customPPM = parsed);
                _updateCalculations();
              }
            },
          ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text("Perry (add 50 ppm)"),
          value: isPerry,
          onChanged: (val) {
            setState(() => isPerry = val);
            _updateCalculations();
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text("Batch Volume:"),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: volumeController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(suffixText: "Volume"),
                onChanged: (val) {
                  final parsed = double.tryParse(val);
                  if (parsed != null) {
                    setState(() => volume = parsed);
                    _updateCalculations();
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<bool>(
              value: useGallons,
              onChanged: (val) {
                if (val != null) {
                  setState(() => useGallons = val);
                  _updateCalculations();
                }
              },
              items: const [
                DropdownMenuItem(value: true, child: Text("Gallons")),
                DropdownMenuItem(value: false, child: Text("Liters")),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildSourceButton(Icons.science, 'Potassium Metabisulphite'),
              _buildSourceButton(Icons.science_outlined, 'Sodium Metabisulphite'),
              _buildSourceButton(Icons.tablet, 'Campden Tablets'),
              _buildSourceButton(Icons.water_drop, '5% Stock Solution'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                "Use: $resultText",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: "Copy to clipboard",
              onPressed: () {
                Clipboard.setData(ClipboardData(text: resultText));
                snacks.show(
                  SnackBar(content: Text("Copied: $resultText")),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(sourceNote, style: const TextStyle(fontSize: 13, color: Colors.teal)),
        const Divider(thickness: 5),
        const SizedBox(height: 24),
        const Text("Recommended Free SO₂ (ppm) vs pH", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        SizedBox(
          height: 300,
          child: LineChart(
            LineChartData(
              minX: 3.0,
              maxX: 3.9,
              minY: 0,
              maxY: 240,
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                    return LineTooltipItem(
                      'pH: ${spot.x.toStringAsFixed(2)}\nppm: ${spot.y.toStringAsFixed(0)}',
                      const TextStyle(color: Colors.white),
                    );
                  }).toList(),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  isCurved: true,
                  spots: List.generate(
                    91,
                    (i) {
                      final phVal = 3.0 + i * 0.01;
                      final ppm = CiderUtils.recommendedFreeSO2ppm(phVal);
                      return FlSpot(phVal, ppm.toDouble());
                    },
                  ),
                  barWidth: 3,
                  gradient: LinearGradient(
                    colors: [Colors.teal.shade900, Colors.teal.shade300],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  dotData: const FlDotData(show: false),
                ),
              ],
              extraLinesData: ExtraLinesData(
                verticalLines: [
                  VerticalLine(
                    x: pH,
                    color: Colors.redAccent,
                    strokeWidth: 2,
                    dashArray: [4, 4],
                    label: VerticalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      labelResolver: (line) => "pH ${pH.toStringAsFixed(2)}\n${CiderUtils.recommendedFreeSO2ppm(pH).round()} ppm",
                    ),
                  ),
                ],
              ),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 40, interval: 40),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 0.40,
                    reservedSize: 40,
                    getTitlesWidget: (value, _) => Text(value.toStringAsFixed(1)),
                  ),
                ),
              ),
              borderData: FlBorderData(show: true),
              gridData: const FlGridData(show: true),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSourceButton(IconData icon, String label) {
    final isSelected = selectedSource == label;
    return GestureDetector(
      onTap: () {
        setState(() => selectedSource = label);
        _updateCalculations();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            backgroundColor: isSelected ? Colors.teal : Colors.grey.shade300,
            child: Icon(icon, color: isSelected ? Colors.white : Colors.black),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
