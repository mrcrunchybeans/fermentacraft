import 'package:flutter/material.dart';

class TaAcidCalculatorTab extends StatefulWidget {
  const TaAcidCalculatorTab({super.key});

  @override
  State<TaAcidCalculatorTab> createState() => _TaAcidCalculatorTabState();
}

class _TaAcidCalculatorTabState extends State<TaAcidCalculatorTab> {
  final currentTA = TextEditingController();
  final targetTA = TextEditingController();
  final batchVolume = TextEditingController();
  String selectedVolumeUnit = 'gal';

  final List<String> volumeUnits = ['mL', 'L', 'gal'];
  double? neededGrams;

  @override
  void initState() {
    super.initState();
    for (var controller in [currentTA, targetTA, batchVolume]) {
      controller.addListener(_recalculate);
    }
  }

  @override
  void dispose() {
    for (var controller in [currentTA, targetTA, batchVolume]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _recalculate() {
    final current = double.tryParse(currentTA.text);
    final target = double.tryParse(targetTA.text);
    final volume = double.tryParse(batchVolume.text);

    if (current == null || target == null || volume == null) {
      setState(() => neededGrams = null);
      return;
    }

    final deltaTA = target - current;
    if (deltaTA <= 0) {
      setState(() => neededGrams = 0);
      return;
    }

    // Convert volume to liters
    double volumeLiters = volume;
    if (selectedVolumeUnit == 'mL') volumeLiters /= 1000;
    if (selectedVolumeUnit == 'gal') volumeLiters *= 3.78541;

    // TA is in g/L as malic acid. So g = deltaTA * L
    final gramsNeeded = deltaTA * volumeLiters;

    setState(() => neededGrams = gramsNeeded);
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
                  "TA Adjustment Tool",
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
                      "This calculator estimates how much acid blend (in grams) to add in order to increase titratable acidity (TA).\n\n"
                      "Enter your current TA, your target TA, and the volume of your batch. TA is measured in g/L as malic acid.\n\n"
                      "This is a linear approximation commonly used for acid blend additions.",
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
          _buildField(currentTA, "Current TA (g/L)"),
          _buildField(targetTA, "Target TA (g/L)"),

          const SizedBox(height: 20),
          const Text("Batch Volume:",
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

         if (neededGrams != null)
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
            neededGrams == 0
                ? "Your current TA is already at or above the target."
                : "Add ${neededGrams!.toStringAsFixed(2)} grams of acid blend.",
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ),
      const SizedBox(width: 8),
      const Tooltip(
        message: "Formula:\n"
            "grams = (Target TA - Current TA) × Volume\n\n"
            "• TA in g/L (as malic acid)\n"
            "• Volume is converted to liters\n"
            "• Assumes 1 g acid blend raises TA by 1 g/L per L",
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
