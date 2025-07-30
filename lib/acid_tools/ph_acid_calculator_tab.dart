import 'package:flutter/material.dart';

class PhAcidCalculatorTab extends StatefulWidget {
  const PhAcidCalculatorTab({super.key});

  @override
  State<PhAcidCalculatorTab> createState() => _PhAcidCalculatorTabState();
}

class _PhAcidCalculatorTabState extends State<PhAcidCalculatorTab> {
  // Controllers
  final originalPH = TextEditingController(text: "3.8");
  final currentPH = TextEditingController();
  final targetPH = TextEditingController(text: "3.4");
  final testVolume = TextEditingController();
  final testAcid = TextEditingController();
  final batchVolume = TextEditingController();
  late final List<TextEditingController> _controllers;

  // State
  int _currentStep = 0;
  double? calculatedResult;
  String selectedVolumeUnit = 'gal';
  final List<String> volumeUnits = ['mL', 'L', 'gal'];

  void _resetForm() {
    setState(() {
      _currentStep = 0;
      calculatedResult = null;

      // Clear all controllers
      for (final controller in _controllers) {
        controller.clear();
      }

      // Optionally restore default values
      originalPH.text = "3.8";
      targetPH.text = "3.4";
    });
  }

  @override
  void initState() {
    super.initState();
    _controllers = [originalPH, currentPH, targetPH, testVolume, testAcid, batchVolume];
    for (final controller in _controllers) {
      controller.addListener(_recalculate);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.removeListener(_recalculate);
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

    final effectiveTestVol = testV ?? 100.0;
    final pHChangeInTest = (oPH! - cPH!).abs();
    final targetDelta = cPH - tPH!;

    if (pHChangeInTest == 0 || effectiveTestVol == 0 || targetDelta <= 0) {
      setState(() => calculatedResult = null);
      return;
    }

    final acidPerPHUnitPerML = testA! / pHChangeInTest / effectiveTestVol;
    double batchVolumeML = batchV!;
    if (selectedVolumeUnit == 'gal') batchVolumeML *= 3785.41;
    if (selectedVolumeUnit == 'L') batchVolumeML *= 1000;
    final neededAcid = acidPerPHUnitPerML * targetDelta * batchVolumeML;
    setState(() => calculatedResult = neededAcid);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Row(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text("pH Adjustment Tool", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: "How this works",
              onPressed: () => _showHelpDialog(context),
            ),
          ],
        ),
        Stepper(
          physics: const ClampingScrollPhysics(),
          currentStep: _currentStep,
          onStepTapped: (step) => setState(() => _currentStep = step),
          // REMOVE onStepContinue and onStepCancel
          // ADD controlsBuilder instead
          controlsBuilder: (context, details) {
            // On the last step (index 1), show a Reset button
            if (details.stepIndex == 1) {
              return Container(
                margin: const EdgeInsets.only(top: 24),
                child: Row(
                  children: [
                    ElevatedButton(
                      onPressed: _resetForm,
                      child: const Text('Start Over'),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: details.onStepCancel, // Still use the cancel callback
                      child: const Text('Back'),
                    ),
                  ],
                ),
              );
            }

            // On all other steps, show the default Continue and Back buttons
            return Container(
              margin: const EdgeInsets.only(top: 24),
              child: Row(
                children: <Widget>[
                  ElevatedButton(
                    onPressed: details.onStepContinue,
                    child: const Text('Continue'),
                  ),
                  const SizedBox(width: 12),
                  // Disable the 'Back' button on the first step
                  if (_currentStep > 0)
                    TextButton(
                      onPressed: details.onStepCancel,
                      child: const Text('Back'),
                    ),
                ],
              ),
            );
          },
          // This onStepContinue is now handled by the controlsBuilder
          onStepContinue: () {
            if (_currentStep < 1) {
              setState(() => _currentStep += 1);
            }
          },
          onStepCancel: () {
            if (_currentStep > 0) {
              setState(() => _currentStep -= 1);
            }
          },
          steps: _buildSteps(),
        ),
        if (calculatedResult != null) _buildResultCard(),
      ],
    );
  }

  List<Step> _buildSteps() {
    return [
      Step(
        title: const Text('Calibrate with Test Sample'),
        isActive: _currentStep >= 0,
        state: _currentStep > 0 ? StepState.complete : StepState.indexed,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Perform a small-scale test to find your must\'s buffering capacity.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            _buildStepRow('Original pH', originalPH),
            _buildStepRow('Acid Added', testAcid, unit: 'grams'),
            _buildStepRow('Test Volume', testVolume, unit: 'mL', optional: true),
            _buildStepRow('Resulting pH', currentPH),
          ],
        ),
      ),
      Step(
        title: const Text('Calculate for Full Batch'),
        isActive: _currentStep >= 1,
        state: _currentStep > 1 ? StepState.complete : StepState.indexed,
        content: Column(
          children: [
            _buildStepRow('Target pH', targetPH),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Expanded(child: Text("Batch Volume", style: TextStyle(fontSize: 16))),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: batchVolume,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: selectedVolumeUnit,
                    items: volumeUnits.map((unit) => DropdownMenuItem(value: unit, child: Text(unit))).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => selectedVolumeUnit = val);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildStepRow(String label, TextEditingController controller, {String? unit, bool optional = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(label, style: const TextStyle(fontSize: 16)),
                if (optional) const Text(" (optional)", style: TextStyle(color: Colors.grey, fontSize: 14)),
              ],
            ),
          ),
          SizedBox(
            width: 120,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                isDense: true,
                suffixText: unit,
                hintText: "0.0",
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    return Card(
      color: Colors.teal.shade50,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.science_outlined, color: Colors.teal, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 18),
                  children: [
                    const TextSpan(text: "Add "),
                    TextSpan(
                      text: "${calculatedResult!.toStringAsFixed(2)} grams",
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                    ),
                    const TextSpan(text: " of acid blend."),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("How this works"),
        content: const Text(
          "This tool helps you estimate how much acid blend to add to your full batch "
          "to reach a target pH — based on real-world testing.\n\n"
          "pH is not linear, and the effect of acid depends on many factors including buffering, "
          "acid type, and liquid composition. So this tool uses a small-scale test to calculate the actual effect.\n\n"
          "Step 1 finds this 'buffering capacity'. Step 2 applies it to your full batch.",
        ),
        actions: [
          TextButton(
            child: const Text("Got it"),
            onPressed: () => Navigator.of(context).pop(),
          )
        ],
      ),
    );
  }
}