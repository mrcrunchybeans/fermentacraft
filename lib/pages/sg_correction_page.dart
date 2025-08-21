import 'package:flutter/material.dart';
import '../widgets/utils.dart'; // Must contain correctedSgJolicoeur(sg, tempF)

class SgCorrectionPage extends StatefulWidget {
  const SgCorrectionPage({super.key});

  @override
  State<SgCorrectionPage> createState() => _SgCorrectionPageState();
}

class _SgCorrectionPageState extends State<SgCorrectionPage> {
  final TextEditingController _measuredSGController = TextEditingController();
  final TextEditingController _tempController = TextEditingController();

  double? correctedSG;
  String selectedUnit = '°F';

  @override
  void initState() {
    super.initState();
    _measuredSGController.addListener(_calculateCorrectedSG);
    _tempController.addListener(_calculateCorrectedSG);
  }

  @override
  void dispose() {
    _measuredSGController.dispose();
    _tempController.dispose();
    super.dispose();
  }

  void _calculateCorrectedSG() {
    final sg = double.tryParse(_measuredSGController.text);
    final temp = double.tryParse(_tempController.text);

    if (sg != null && temp != null) {
      final tempInF = selectedUnit == '°F' ? temp : (temp * 9 / 5) + 32;
      final corrected = CiderUtils.correctedSgJolicoeur(sg, tempInF);
      setState(() => correctedSG = corrected);
    } else {
      setState(() => correctedSG = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("SG Correction")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            const Text(
              "Hydrometers are calibrated at 60°F. This tool adjusts your SG for the actual sample temperature.",
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 20),

            // Measured SG
            TextField(
              controller: _measuredSGController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: "Measured SG",
                hintText: "e.g. 1.062",
                helperText: "Enter the SG reading from your hydrometer",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Temperature and Unit
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tempController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: "Temperature",
                      hintText: "e.g. 74",
                      helperText: "Sample temperature when SG was measured",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: selectedUnit,
                  onChanged: (value) {
                    setState(() => selectedUnit = value!);
                    _calculateCorrectedSG(); // recalculate immediately on unit change
                  },
                  items: ['°F', '°C'].map((unit) {
                    return DropdownMenuItem<String>(
                      value: unit,
                      child: Text(unit),
                    );
                  }).toList(),
                ),
              ],
            ),

            const SizedBox(height: 20),

            if (correctedSG != null)
              Card(
                color: Colors.green.shade50,
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    "Corrected SG: ${correctedSG!.toStringAsFixed(3)}",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 30),

            const Text(
              "How is this calculated?",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              "This correction is based on Jean-Jacques Jolicoeur’s polynomial formula:\n\n"
              "SGcorr = SGmeasured - (0.000135 × (T - 60)) - (0.00000225 × (T - 60)²)\n\n"
              "Where:\n"
              "• T is the temperature in °F\n"
              "• SGcorr is the corrected SG at 60°F\n\n"
              "This model provides highly accurate hydrometer correction values for cider and wine making.",
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
