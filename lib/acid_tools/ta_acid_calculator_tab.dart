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

    if (current == null || target == null || volume == null || volume <= 0) {
      setState(() => neededGrams = null);
      return;
    }

    final deltaTA = target - current;
    if (deltaTA <= 0) {
      setState(() => neededGrams = 0);
      return;
    }

    double volumeLiters = volume;
    if (selectedVolumeUnit == 'mL') volumeLiters /= 1000;
    if (selectedVolumeUnit == 'gal') volumeLiters *= 3.78541;

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
              Expanded(
                child: Text(
                  "TA Adjustment Tool",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.help_outline),
                tooltip: "How this works",
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text("How This Works"),
                    // UPDATED: Using RichText for better formatting
                    content: RichText(
                      text: TextSpan(
                        style: Theme.of(context).textTheme.bodyMedium,
                        children: const [
                          TextSpan(text: "This calculator estimates how much acid blend to add to increase "),
                          TextSpan(text: "titratable acidity (TA)", style: TextStyle(fontWeight: FontWeight.bold)),
                          TextSpan(text: ".\n\nTA is measured in grams per liter (g/L) as if it were all malic acid. Enter your current TA, your target, and the batch volume to get an estimate in grams."),
                        ],
                      ),
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
          const SizedBox(height: 16),
          _buildField(currentTA, "Current TA (g/L)"),
          _buildField(targetTA, "Target TA (g/L)"),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildField(batchVolume, "Batch Volume")),
              const SizedBox(width: 12),
              // Using a Padding to align the dropdown better with the text field
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: DropdownButton<String>(
                  value: selectedVolumeUnit,
                  underline: const SizedBox(), // Removes the default underline
                  borderRadius: BorderRadius.circular(10),
                  onChanged: (val) {
                    setState(() {
                      selectedVolumeUnit = val!;
                      _recalculate();
                    });
                  },
                  items: volumeUnits
                      .map((unit) => DropdownMenuItem(value: unit, child: Text(unit)))
                      .toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // UPDATED: Using the new InfoCard widget for the result
          if (neededGrams != null)
            InfoCard(
              icon: neededGrams! > 0 ? Icons.science_outlined : Icons.check_circle_outline,
              text: neededGrams == 0
                  ? "Your current TA is already at or above the target."
                  : "Add ${neededGrams!.toStringAsFixed(2)} grams of acid blend.",
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

// NEW: A reusable, theme-aware card for displaying information.
class InfoCard extends StatelessWidget {
  final String text;
  final IconData icon;

  const InfoCard({
    required this.text,
    this.icon = Icons.info_outline, // Default icon
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // Using theme colors instead of hardcoded grey
        color: colorScheme.primaryContainer.withValues(alpha: 0.4),
        border: Border.all(color: colorScheme.primaryContainer),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: colorScheme.primary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}