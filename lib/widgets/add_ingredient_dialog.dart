// lib/widgets/add_ingredient_dialog.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:fermentacraft/models/unit_type.dart';
import 'package:fermentacraft/models/settings_model.dart';

// Unified units helpers (same ones used by Inventory)
import 'package:fermentacraft/utils/units.dart';

import '../utils/utils.dart';

class AddIngredientDialog extends StatefulWidget {
  final Function(Map<String, dynamic>) onAddToRecipe;
  final Function(Map<String, dynamic>)? onAddToInventory;
  final Map<String, dynamic>? existing;
  final UnitType unitType; // keep and use it

  const AddIngredientDialog({
    super.key,
    required this.onAddToRecipe,
    this.onAddToInventory,
    this.existing,
    required this.unitType,
  });

  @override
  State<AddIngredientDialog> createState() => _AddIngredientDialogState();
}

class _AddIngredientDialogState extends State<AddIngredientDialog> {
  final _formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final amountController = TextEditingController();
  final ogController = TextEditingController();
  final phController = TextEditingController();
  final costController = TextEditingController();

  DateTime purchaseDate = DateTime.now();
  DateTime? expirationDate;

  // Use canonical units and sensible defaults by unitType
  String amountUnit = 'g';
  String type = 'Juice';

  @override
  void initState() {
    super.initState();

    // Default unit based on the requested unit type (if no existing)
    amountUnit = (widget.unitType == UnitType.mass) ? 'g' : 'ml';

    if (widget.existing != null) {
      final f = widget.existing!;

      nameController.text = f['name']?.toString() ?? '';
      amountController.text = f['amount']?.toString() ?? '';

      // Normalize any incoming unit to our canonical set
      final incomingUnit = f['unit']?.toString();
      final normalized = normalizeUnit(incomingUnit);
      if (kCanonicalUnits.contains(normalized)) {
        amountUnit = normalized;
      }

      type = f['type']?.toString() ?? 'Juice';
      ogController.text = f['og']?.toString() ?? '';
      phController.text = f['ph']?.toString() ?? '';
      costController.text = f['cost']?.toString() ?? '';

      // Existing dates could be DateTime or String
      final pd = f['purchaseDate'];
      if (pd is DateTime) {
        purchaseDate = pd;
      } else if (pd is String) {
        purchaseDate = DateTime.tryParse(pd) ?? DateTime.now();
      }

      final ed = f['expirationDate'];
      if (ed is DateTime) {
        expirationDate = ed;
      } else if (ed is String) {
        expirationDate = DateTime.tryParse(ed);
      }
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    amountController.dispose();
    ogController.dispose();
    phController.dispose();
    costController.dispose();
    super.dispose();
  }

  Map<String, dynamic> buildIngredientEntry() {
    final og = double.tryParse(ogController.text);
    final ph = double.tryParse(phController.text);
    final cost = double.tryParse(costController.text);

    return {
      'name': nameController.text.trim(),
      'amount': double.tryParse(amountController.text) ?? 0,
      'unit': amountUnit, // canonical unit
      'type': type,
      'og': og,
      'ph': ph,
      'cost': cost,
      'purchaseDate': purchaseDate,
      'expirationDate': expirationDate,
      'acidityClass': ph != null ? CiderUtils.classifyAcidity(ph) : null,
    };
  }

  InputDecoration _dec(
    String label, {
    String? prefixText,
    Widget? suffixIcon,
  }) =>
      InputDecoration(
        labelText: label,
        isDense: true,
        prefixText: prefixText,
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        filled: true,
      );

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;

    // 👇 Selected currency symbol from settings
    final symbol = context.watch<SettingsModel>().currencySymbol;

    // live unit-cost preview
    double? unitCost;
    final amt = double.tryParse(amountController.text);
    final total = double.tryParse(costController.text);
    if ((amt ?? 0) > 0 && (total ?? 0) > 0) {
      unitCost = (total! / amt!);
    }

    return AlertDialog(
      title: Text(isEditing ? "Edit Ingredient" : "Add Ingredient"),
      content: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(controller: nameController, decoration: _dec('Name')),
                const SizedBox(height: 8),

                // Amount + Unit (fixed-width unit dropdown to prevent overflow)
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: amountController,
                        decoration: _dec('Amount'),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}), // refresh unit-cost preview
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: DropdownButtonFormField<String>(
                        isDense: true,
                        isExpanded: true, // fits inside the constrained box
                        // Guard the value so it ALWAYS matches exactly one item
                        value: kCanonicalUnits.contains(amountUnit)
                            ? amountUnit
                            : (widget.unitType == UnitType.mass ? 'g' : 'ml'),
                        decoration: _dec('Unit'),
                        onChanged: (val) {
                          if (val == null) return;
                          setState(() => amountUnit = val);
                        },
                        items: kCanonicalUnits
                            .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                            .toList(growable: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                DropdownButtonFormField<String>(
                  value: type,
                  decoration: _dec('Type'),
                  isDense: true,
                  onChanged: (val) => setState(() => type = val ?? type),
                  items: const [
                    'Juice', 'Fruit', 'Sugar', 'Concentrate', 'Additive', 'Other'
                  ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                ),
                const SizedBox(height: 8),

                TextFormField(
                  controller: ogController,
                  decoration: _dec('Original Gravity (SG)'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 8),

                TextFormField(
                  controller: phController,
                  decoration: _dec('pH'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 10),

                const Divider(),
                const SizedBox(height: 10),

                // 💸 Currency-aware cost input
                TextFormField(
                  controller: costController,
                  decoration: _dec('Total Cost', prefixText: '$symbol '),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}), // refresh unit-cost preview
                ),
                if (unitCost != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '≈ $symbol${unitCost.toStringAsFixed(2)} per $amountUnit',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Purchase: ${DateFormat.yMMMd().format(purchaseDate)}",
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: purchaseDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) setState(() => purchaseDate = picked);
                      },
                      child: const Text("Change"),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        expirationDate == null
                            ? "Expiration: Not set"
                            : "Expires: ${DateFormat.yMMMd().format(expirationDate!)}",
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: expirationDate ??
                              DateTime.now().add(const Duration(days: 365)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2040),
                        );
                        if (picked != null) setState(() => expirationDate = picked);
                      },
                      child: const Text("Set"),
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
        if (widget.onAddToInventory != null && !isEditing)
          TextButton(
            onPressed: () {
              widget.onAddToInventory!(buildIngredientEntry());
              Navigator.of(context).pop();
            },
            child: const Text("Add to Inventory"),
          ),
        TextButton(
          onPressed: () {
            widget.onAddToRecipe(buildIngredientEntry());
            Navigator.of(context).pop();
          },
          child: Text(isEditing ? "Save Changes" : "Add to Recipe"),
        ),
      ],
    );
  }
}
