import 'package:flutter/material.dart';

class PhAcidCalculatorTab extends StatefulWidget {
  const PhAcidCalculatorTab({super.key});

  @override
  State<PhAcidCalculatorTab> createState() => _PhAcidCalculatorTabState();
}

class _PhAcidCalculatorTabState extends State<PhAcidCalculatorTab> {
  final originalPH = TextEditingController();
  final currentPH = TextEditingController();
  final targetPH = TextEditingController();
  final testVolume = TextEditingController(); // optional
  final testAcid = TextEditingController();   // amount of acid used in test
  final batchVolume = TextEditingController();

  double? calculatedResult;
  String selectedVolumeUnit = 'gal';
  final List<String> volumeUnits = ['mL', 'L', 'gal'];

  @override
  void initState() {
    super.initState();
    for (var controller in [
      originalPH,
      currentPH,
      targetPH,
      testVolume,
      testAcid,
      batchVolume
    ]) {
      controller.addListener(_recalculate);
    }
  }

  @override
  void dispose() {
    for (var controller in [
      originalPH,
      currentPH,
      targetPH,
      testVolume,
      testAcid,
      batchVolume
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _recalculate() {
    final oPH = double.tryParse(originalPH.text);
    final cPH = double.tryParse(currentPH.text);
    final tPH = double.tryParse(targetPH.text);
    final testV = double.tryParse(testVolume.text);
    final testA = double.tryParse(testAcid.text);
    final batchV = double.tryParse(batchVolume.text);

    if ([oPH, cPH, tPH, testA, batchV].contains(null)) {
      setState(() => calculatedResult = null);
      return;
    }

    final effectiveTestVol = testV ?? 100.0; // mL
    final pHChange = cPH! - oPH!;
    final targetDelta = tPH! - cPH;

    if (pHChange == 0 || effectiveTestVol == 0) {
      setState(() => calculatedResult = null);
      return;
    }

    final acidPerPHUnitPerML = testA! / pHChange / effectiveTestVol;

    // Convert batch volume to mL
    double batchVolumeML = batchV!;
    if (selectedVolumeUnit == 'gal') batchVolumeML *= 3785.41;
    if (selectedVolumeUnit == 'L') batchVolumeML *= 1000;

    final neededAcid = acidPerPHUnitPerML * targetDelta * batchVolumeML;

    setState(() => calculatedResult = neededAcid);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  "pH Adjustment Tool",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.help_outline),
                tooltip: "How this works",
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text("How this works"),
                    content: const Text(
                        "This tool helps you estimate how much acid blend to add to your full batch "
                        "to reach a target pH — based on real-world testing.\n\n"
                        "pH is not linear, and the effect of acid depends on many factors including buffering, "
                        "acid type, and liquid composition. So this tool uses a small-scale test to calculate the actual effect.\n\n"
                        "👉 Steps:\n"
                        "1. Measure the original pH of a small test batch.\n"
                        "2. Add a known amount of acid and measure the new pH.\n"
                        "3. Enter those values here, plus your target pH and total batch volume.\n\n"
                        "If no test volume is entered, we assume 100 mL.\n\n"
                        "💡 Why this works: It uses the pH shift in your test batch to estimate how much acid would "
                        "create a similar shift in the full batch, taking into account your specific ingredients.",
                      ),

                    actions: [
                      TextButton(
                        child: const Text("Got it"),
                        onPressed: () => Navigator.of(context).pop(),
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildField(originalPH, "Original pH (before acid added)"),
          _buildField(currentPH, "Current pH (after test acid added)"),
          _buildField(targetPH, "Target pH (desired)"),

          const SizedBox(height: 16),
          const Text("Optional Test Details:",
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            "To improve accuracy, enter how much acid you added during your test and the size of that test batch (in mL). If no test volume is entered, 100 mL is assumed.",
            style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 8),
          _buildField(testAcid, "Acid added in test (grams)"),
          _buildField(testVolume, "Test batch volume (mL, optional)"),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),

          const Text("Full Batch Details:",
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: _buildField(batchVolume, "Batch volume")),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: selectedVolumeUnit,
                borderRadius: BorderRadius.circular(10),
                onChanged: (val) {
                  setState(() {
                    selectedVolumeUnit = val!;
                    _recalculate();
                  });
                },
                items: volumeUnits
                    .map((unit) =>
                        DropdownMenuItem(value: unit, child: Text(unit)))
                    .toList(),
              ),
            ],
          ),
          const SizedBox(height: 24),

          if (calculatedResult != null)
  Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            "Add ${calculatedResult!.toStringAsFixed(2)} grams of acid blend to your full batch.",
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ),
      const SizedBox(width: 8),
      const Tooltip(
        message:
          "Formula:\n"
          "Acid needed = (Acid in test / ΔpH in test / test volume) × ΔpH to target × full batch volume\n\n"
          "All volumes are converted to mL.",
        child: Icon(Icons.info_outline),
      ),
    ],
  ),

        ],
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        onTap: () => controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.text.length,
        ),
      ),
    );
  }
}
