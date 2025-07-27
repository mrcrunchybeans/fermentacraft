import 'package:flutter/material.dart';
import '../utils/utils.dart';

class AddAdditiveDialog extends StatefulWidget {
  final double mustPH;
  final double volume; // in gallons
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

  String name = "Potassium Metabisulphite";
  String unit = "grams";
  double amount = 0.0;

  final amountController = TextEditingController();
  final customNameController = TextEditingController();

  final List<String> additiveOptions = [
    "Acid Blend",
    "Pectic Enzyme",
    "Potassium Metabisulphite",
    "Potassium Sorbate",
    "Tannin",
    "Yeast Nutrient",
    "Custom"
  ];

  final List<String> unitOptions = ["grams", "Campden Tablets", "tsp", "mL"];

  bool isCustom = false;

  @override
  void initState() {
    super.initState();

    if (widget.existing != null) {
      name = widget.existing!['name'] ?? "Custom";
      amount = widget.existing!['amount'] ?? 0.0;
      unit = widget.existing!['unit'] ?? "grams";

      if (!additiveOptions.contains(name)) {
        isCustom = true;
        name = "Custom";
        customNameController.text = widget.existing!['name'];
      } else {
        isCustom = name == "Custom";
        if (isCustom) {
          customNameController.text = widget.existing!['name'];
        }
      }

      amountController.text = amount.toString();
    } else {
      _autoCalculateAmount();
    }
  }

  void _autoCalculateAmount() {
    if (name == "Potassium Metabisulphite") {
      final liters = CiderUtils.gallonsToLiters(widget.volume);
      final ppm = CiderUtils.recommendedFreeSO2ppm(widget.mustPH);
      final grams = CiderUtils.sulfiteGramsForVolume(liters, ppm);
      amount = CiderUtils.round2(grams);
      amountController.text = amount.toString();
    }
  }

  void _onNameChanged(String? selected) {
    if (selected == null) return;
    setState(() {
      name = selected;
      isCustom = name == "Custom";

      if (name == "Potassium Metabisulphite") {
        unit = "grams";
        _autoCalculateAmount();
      } else {
        amount = 0.0;
        amountController.clear();
        customNameController.clear();
      }
    });
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final finalName = isCustom ? customNameController.text.trim() : name;
      widget.onAdd({
        "name": finalName,
        "amount": double.tryParse(amountController.text) ?? 0.0,
        "unit": unit,
      });
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    amountController.dispose();
    customNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing != null ? "Edit Additive" : "Add Additive"),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: name,
              items: additiveOptions
                  .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                  .toList(),
              onChanged: _onNameChanged,
              decoration: const InputDecoration(labelText: "Additive"),
            ),
            if (isCustom)
              TextFormField(
                controller: customNameController,
                decoration: const InputDecoration(labelText: "Custom Name"),
                validator: (val) =>
                    val == null || val.trim().isEmpty ? "Enter a custom name" : null,
              ),
            TextFormField(
              controller: amountController,
              decoration: const InputDecoration(labelText: "Amount"),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (val) =>
                  val == null || val.isEmpty ? "Enter amount" : null,
            ),
            DropdownButtonFormField<String>(
              value: unit,
              items: unitOptions
                  .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                  .toList(),
              onChanged: (val) => setState(() => unit = val ?? "grams"),
              decoration: const InputDecoration(labelText: "Unit"),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        ElevatedButton(
            onPressed: _submit,
            child: Text(widget.existing != null ? "Update" : "Add")),
      ],
    );
  }
}
