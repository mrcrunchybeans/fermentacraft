import 'package:flutter/material.dart';
import 'package:fermentacraft/models/unit_type.dart';
import 'package:intl/intl.dart';
import '../utils/utils.dart';

class AddIngredientDialog extends StatefulWidget {
  final Function(Map<String, dynamic>) onAddToRecipe;
  final Function(Map<String, dynamic>)? onAddToInventory;
  final Map<String, dynamic>? existing;

  const AddIngredientDialog({
    super.key,
    required this.onAddToRecipe,
    this.onAddToInventory,
    this.existing, required UnitType unitType,
  });

  @override
  State<AddIngredientDialog> createState() => _AddIngredientDialogState();
}

class _AddIngredientDialogState extends State<AddIngredientDialog> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController nameController = TextEditingController();
  final TextEditingController amountController = TextEditingController();
  final TextEditingController ogController = TextEditingController();
  final TextEditingController phController = TextEditingController();
  final TextEditingController costController = TextEditingController();
  DateTime purchaseDate = DateTime.now();
  DateTime? expirationDate; // <-- ADDED: State for expiration date

  String amountUnit = 'gal';
  String type = 'Juice';

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final f = widget.existing!;
      nameController.text = f['name']?.toString() ?? '';
      amountController.text = f['amount']?.toString() ?? '';
      amountUnit = f['unit']?.toString() ?? 'gal';
      type = f['type']?.toString() ?? 'Juice';
      ogController.text = f['og']?.toString() ?? '';
      phController.text = f['ph']?.toString() ?? '';
      costController.text = f['cost']?.toString() ?? '';
      purchaseDate = f['purchaseDate'] ?? DateTime.now();
      expirationDate = f['expirationDate']; // <-- ADDED: Initialize expiration date
    }
  }

  Map<String, dynamic> buildIngredientEntry() {
    final double? og = double.tryParse(ogController.text);
    final double? ph = double.tryParse(phController.text);
    final double? cost = double.tryParse(costController.text);

    return {
      'name': nameController.text.trim(),
      'amount': double.tryParse(amountController.text) ?? 0,
      'unit': amountUnit,
      'type': type,
      'og': og,
      'ph': ph,
      'cost': cost,
      'purchaseDate': purchaseDate,
      'expirationDate': expirationDate, // <-- ADDED: Include expiration date
      'acidityClass': ph != null ? CiderUtils.classifyAcidity(ph) : null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditing = widget.existing != null;

    return AlertDialog(
      title: Text(isEditing ? "Edit Ingredient" : "Add Ingredient"),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              // ... (Other form fields for amount, type, OG, pH)
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: amountController,
                      decoration: const InputDecoration(labelText: 'Amount'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: amountUnit,
                    onChanged: (val) => setState(() => amountUnit = val!),
                    items: ['oz', 'g', 'lb', 'ml', 'l', 'gal', 'tsp', 'tbsp', 'package']
                        .map((unit) => DropdownMenuItem(value: unit, child: Text(unit)))
                        .toList(),
                  ),
                ],
              ),
              DropdownButtonFormField<String>(
                value: type,
                onChanged: (val) => setState(() => type = val!),
                items: ['Juice', 'Fruit', 'Sugar', 'Concentrate', 'Additive', 'Other']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: ogController,
                decoration: const InputDecoration(labelText: 'Original Gravity (SG)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: phController,
                decoration: const InputDecoration(labelText: 'pH'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const Divider(),
              TextFormField(
                controller: costController,
                decoration: const InputDecoration(labelText: 'Total Cost (\$)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text("Purchase Date: ${DateFormat.yMMMd().format(purchaseDate)}"),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: purchaseDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => purchaseDate = picked);
                      }
                    },
                    child: const Text("Change"),
                  ),
                ],
              ),
              // --- ADDED: Expiration Date Picker ---
              Row(
                children: [
                  Text(expirationDate == null
                      ? "Expiration: Not set"
                      : "Expires: ${DateFormat.yMMMd().format(expirationDate!)}"),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: expirationDate ?? DateTime.now().add(const Duration(days: 365)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2040),
                      );
                      if (picked != null) {
                        setState(() => expirationDate = picked);
                      }
                    },
                    child: const Text("Set"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        // --- CLEANED UP: Button Logic ---
        if (widget.onAddToInventory != null && !isEditing)
          TextButton(
            onPressed: () {
              final ingredient = buildIngredientEntry();
              widget.onAddToInventory!(ingredient);
              Navigator.of(context).pop();
            },
            child: const Text("Add to Inventory"),
          ),
        TextButton(
          onPressed: () {
            final ingredient = buildIngredientEntry();
            widget.onAddToRecipe(ingredient);
            Navigator.of(context).pop();
          },
          child: Text(isEditing ? "Save Changes" : "Add to Recipe"),
        ),
      ],
    );
  }
}