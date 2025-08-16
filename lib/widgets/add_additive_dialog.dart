import 'package:flutter/material.dart';
import '../utils/utils.dart';

class AddAdditiveDialog extends StatefulWidget {
  final double mustPH;
  final double volume; // gallons
  final void Function(Map<String, dynamic>) onAdd;
  final Map<String, dynamic>? existing;

  const AddAdditiveDialog({
    super.key,
    required this.mustPH,
    required this.volume,
    required this.onAdd,
    this.existing,
  });

  @override
  State<AddAdditiveDialog> createState() => _AddAdditiveDialogState();
}

class _AddAdditiveDialogState extends State<AddAdditiveDialog> {
  final _formKey = GlobalKey<FormState>();

  final amountController = TextEditingController();
  final customNameController = TextEditingController();

  String name = 'Potassium Metabisulphite';
  String unit = 'grams';
  bool isCustom = false;

  final List<String> additiveOptions = const [
    'Acid Blend',
    'Pectic Enzyme',
    'Potassium Metabisulphite',
    'Potassium Sorbate',
    'Tannin',
    'Yeast Nutrient',
    'Custom',
  ];

  final List<String> unitOptions = const ['grams', 'Campden Tablets', 'tsp', 'mL'];

  @override
  void initState() {
    super.initState();

    if (widget.existing != null) {
      final m = widget.existing!;
      name = (m['name'] as String?) ?? 'Custom';
      unit = (m['unit'] as String?) ?? 'grams';
      final amt = (m['amount'] as num?)?.toDouble();

      // Decide if this is a "custom" tag based on whether it appears in list
      if (!additiveOptions.contains(name)) {
        isCustom = true;
        customNameController.text = name;
        name = 'Custom';
      } else {
        isCustom = name == 'Custom';
        if (isCustom) {
          customNameController.text = (m['name'] as String?) ?? '';
        }
      }
      if (amt != null) amountController.text = amt.toString();
    } else {
      _autoCalculateForKMBS(); // prefill for default selection
    }
  }

  @override
  void dispose() {
    amountController.dispose();
    customNameController.dispose();
    super.dispose();
  }

  // --- UI helpers ------------------------------------------------------------

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        filled: true,
      );

  // --- Behavior --------------------------------------------------------------

  void _autoCalculateForKMBS() {
    // Auto-calc grams of KMBS to hit recommended free SO2 for the given pH
    final liters = CiderUtils.gallonsToLiters(widget.volume);
    final ppm = CiderUtils.recommendedFreeSO2ppm(widget.mustPH);
    final grams = CiderUtils.sulfiteGramsForVolume(liters, ppm);
    amountController.text = CiderUtils.round2(grams).toString();
  }

  void _onNameChanged(String? selected) {
    if (selected == null) return;
    setState(() {
      name = selected;
      isCustom = name == 'Custom';

      if (name == 'Potassium Metabisulphite') {
        unit = 'grams';
        _autoCalculateForKMBS();
      } else {
        // Don’t nuke the user's custom name if they were editing it
        if (!isCustom) customNameController.clear();
        // Only clear amount if we’re switching away from KMBS auto-calc
        if (amountController.text.isEmpty || name != 'Potassium Metabisulphite') {
          amountController.clear();
        }
      }
    });
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final parsedAmount = double.tryParse(amountController.text) ?? 0.0;
    final finalName = isCustom ? customNameController.text.trim() : name;

    widget.onAdd({
      'name': finalName,
      'amount': parsedAmount,
      'unit': unit,
    });
    Navigator.of(context).pop();
  }

  // --- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Additive' : 'Add Additive'),
      content: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: name,
                  decoration: _dec('Additive'),
                  isDense: true,
                  onChanged: _onNameChanged,
                  items: additiveOptions
                      .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                      .toList(),
                ),
                if (isCustom) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: customNameController,
                    decoration: _dec('Custom Name'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Enter a custom name' : null,
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: amountController,
                        decoration: _dec('Amount'),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Enter amount' : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: DropdownButtonFormField<String>(
                        initialValue: unit,
                        decoration: _dec('Unit'),
                        isDense: true,
                        isExpanded: true,
                        onChanged: (val) => setState(() => unit = val ?? 'grams'),
                        items: unitOptions
                            .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(isEditing ? 'Update' : 'Add'),
        ),
      ],
    );
  }
}
