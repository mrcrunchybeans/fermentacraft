import 'package:flutter/material.dart';
import '../utils/utils.dart';

class ABVCalculatorPage extends StatefulWidget {
  const ABVCalculatorPage({super.key});

  @override
  State<ABVCalculatorPage> createState() => _ABVCalculatorPageState();
}

class _ABVCalculatorPageState extends State<ABVCalculatorPage> {
  double fg = 1.000;
  double og = 1.050;
  bool useBetterFormula = true;

  late TextEditingController _ogController;
  late TextEditingController _fgController;

  @override
  void initState() {
    super.initState();
    _ogController = TextEditingController(text: og.toStringAsFixed(3));
    _fgController = TextEditingController(text: fg.toStringAsFixed(3));
  }

  @override
  void dispose() {
    _ogController.dispose();
    _fgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final abvSimple = CiderUtils.calculateABV(og, fg);
    final abvBetter = CiderUtils.calculateABVBetter(og, fg);
    final abv = useBetterFormula ? abvBetter : abvSimple;

    return Scaffold(
      appBar: AppBar(
        title: const Text("ABV Calculator"),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const _FormulaHelpDialog(),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _GravityInputRow(
              label: "Original Gravity (OG)",
              controller: _ogController,
              onChanged: (val) {
                setState(() {
                  og = val;
                });
              },
            ),
            _GravityInputRow(
              label: "Final Gravity (FG)",
              controller: _fgController,
              onChanged: (val) {
                setState(() {
                  fg = val;
                });
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.swap_vert),
                  label: const Text("Swap OG/FG"),
                  onPressed: () {
                    setState(() {
                      final temp = og;
                      og = fg;
                      fg = temp;
                      _ogController.text = og.toStringAsFixed(3);
                      _fgController.text = fg.toStringAsFixed(3);
                    });
                  },
                ),
              ],
            ),
            SwitchListTile(
              title: const Text("Use Better Formula (More Accurate)"),
              value: useBetterFormula,
              onChanged: (val) => setState(() => useBetterFormula = val),
            ),
            const SizedBox(height: 12),
            Text(
              "Estimated ABV: ${abv.toStringAsFixed(2)}%",
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              "(Simple: ${abvSimple.toStringAsFixed(2)}% | Better: ${abvBetter.toStringAsFixed(2)}%)",
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 16),
            _ABVCategoryChart(abv: abv),
          ],
        ),
      ),
    );
  }
}

class _GravityInputRow extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final void Function(double) onChanged;

  const _GravityInputRow({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (val) {
          final parsed = double.tryParse(val);
          if (parsed != null && parsed >= 0.990 && parsed <= 1.150) {
            onChanged(parsed);
          }
        },
      ),
    );
  }
}

class _FormulaHelpDialog extends StatelessWidget {
  const _FormulaHelpDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Which ABV Formula Should I Use?"),
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("There are two formulas for Alcohol by Volume (ABV):"),
            SizedBox(height: 12),
            Text(
              "🔹 Simple Formula:\n  (OG - FG) × 131.25",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text("Quick and close enough for most cider, wine, or mead batches."),
            SizedBox(height: 8),
            Text(
              "🔹 Better Formula:\n  [(76.08 × (OG - FG)) / (1.775 - OG)] × (FG / 0.794)",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text("More accurate for higher-alcohol fermentations or labeling."),
            SizedBox(height: 12),
            Text(
              "💡 Tip:\nUse the better formula if you're entering contests, bottling commercially, or just want precision.",
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: const Text("Got it!"),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

class _ABVCategoryChart extends StatelessWidget {
  final double abv;

  const _ABVCategoryChart({required this.abv});

  @override
  Widget build(BuildContext context) {
    String category;
    if (abv < 3.5) {
      category = "Low ABV (session cider)";
    } else if (abv < 6.5) {
      category = "Typical Cider";
    } else if (abv < 9.0) {
      category = "Strong Cider or Table Wine";
    } else if (abv < 14.0) {
      category = "Standard Wine / Traditional Mead";
    } else {
      category = "High ABV (fortified or dessert styles)";
    }

    return Column(
      children: [
        const Divider(),
        Text(
          category,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          "Typical Ranges:\n• Cider: 4.5–6.5%  • Wine: 9–14%  • Mead: 8–14%",
          style: TextStyle(fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
