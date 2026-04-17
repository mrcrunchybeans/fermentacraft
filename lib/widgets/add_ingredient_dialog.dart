// lib/widgets/add_ingredient_dialog.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:fermentacraft/models/unit_type.dart';
import 'package:fermentacraft/models/settings_model.dart';
import 'package:fermentacraft/models/enums.dart'; // FermentableType + .label
import 'package:fermentacraft/utils/units.dart'; // kCanonicalUnits, normalizeUnit
import '../utils/utils.dart'; // CiderUtils.classifyAcidity

class AddIngredientDialog extends StatefulWidget {
  final Function(Map<String, dynamic>) onAddToRecipe;
  final Function(Map<String, dynamic>)? onAddToInventory;
  final Map<String, dynamic>? existing;
  final UnitType unitType;

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

  // Controllers
  final nameController = TextEditingController();
  final amountController = TextEditingController();
  final ogController = TextEditingController();
  final phController = TextEditingController();
  final costController = TextEditingController();

  // Dates
  DateTime purchaseDate = DateTime.now();
  DateTime? expirationDate;

  // Selections
  late final List<String> _typeOptions; // enum-driven labels
  String type = 'Juice';                // label string, for data compatibility
  String amountUnit = 'g';              // canonical unit

  @override
  void initState() {
    super.initState();

    // Build labels from the enum so Batch stays in sync with Recipe Builder.
    _typeOptions = FermentableType.values.map((t) => t.label).toList();

    // Default unit based on requested unit type (unless editing)
    amountUnit = (widget.unitType == UnitType.mass) ? 'g' : 'ml';

    // Seed defaults / load existing
    if (widget.existing != null) {
      final f = widget.existing!;

      nameController.text = f['name']?.toString() ?? '';
      amountController.text = f['amount']?.toString() ?? '';

      final incomingUnit = f['unit']?.toString();
      final normalized = normalizeUnit(incomingUnit);
      if (kCanonicalUnits.contains(normalized)) {
        amountUnit = normalized;
      }

      final incomingType = (f['type']?.toString() ?? 'Juice');
      // Keep any legacy/custom labels even if not in enum
      type = incomingType;

      ogController.text = f['og']?.toString() ?? '';
      phController.text = f['ph']?.toString() ?? '';
      costController.text = f['cost']?.toString() ?? '';

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
    } else {
      // New entry: choose a sensible default type and unit
      // Default to Juice (volume), but respect widget.unitType
      type = 'Juice';
      amountUnit = (widget.unitType == UnitType.mass) ? 'g' : 'ml';
      _nudgeUnitForType(type); // sets ml for Juice/Water, etc.
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

  // Small helper: nudge default unit per type (without overriding a user’s explicit choice later)
  void _nudgeUnitForType(String t) {
    // Only nudge if we’re on a default-ish unit; otherwise, don’t fight the user
    // (We consider 'g' and 'ml' as our starting defaults.)
    switch (t) {
      case 'Water':
      case 'Juice':
        // Volume is common for liquids
        if (amountUnit != 'ml' && amountUnit != 'g') return;
        setState(() => amountUnit = 'ml');
        break;
      case 'Honey':
        // Many track honey by weight; keep weight if already mass default, else ml is ok
        if (amountUnit == 'g' || amountUnit == 'ml') return;
        break;
      default:
        // Leave as-is
        break;
    }
  }

  Map<String, dynamic> buildIngredientEntry() {
    final og = double.tryParse(ogController.text);
    final ph = double.tryParse(phController.text);
    final cost = double.tryParse(costController.text);

    return {
      'name': nameController.text.trim(),
      'amount': double.tryParse(amountController.text) ?? 0,
      'unit': amountUnit, // canonical unit
      'type': type,       // label string (keeps compatibility with existing data)
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
  }) {
    return InputDecoration(
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
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;

    // Currency symbol from settings
    final symbol = context.watch<SettingsModel>().currencySymbol;

    // Unit-cost live preview
    double? unitCost;
    final amt = double.tryParse(amountController.text);
    final total = double.tryParse(costController.text);
    if ((amt ?? 0) > 0 && (total ?? 0) > 0) {
      unitCost = (total! / amt!);
    }

    return AlertDialog(
      title: Text(isEditing ? 'Edit Ingredient' : 'Add Ingredient'),
      content: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: _dec('Name'),
                ),
                const SizedBox(height: 8),

                // Amount + Unit
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: amountController,
                        decoration: _dec('Amount'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}), // refresh unit-cost
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: DropdownButtonFormField<String>(
                        isDense: true,
                        isExpanded: true,
                        value: kCanonicalUnits.contains(amountUnit)
                            ? amountUnit
                            : (widget.unitType == UnitType.mass ? 'g' : 'ml'),
                        decoration: _dec('Unit'),
                        onChanged: (val) {
                          if (val == null) return;
                          setState(() => amountUnit = val);
                        },
                        items: kCanonicalUnits
                            .map((u) =>
                                DropdownMenuItem(value: u, child: Text(u)))
                            .toList(growable: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Type (enum-driven list, includes Honey + Water)
                DropdownButtonFormField<String>(
                  value: _typeOptions.contains(type) ? type : 'Juice',
                  decoration: _dec('Type'),
                  isDense: true,
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() => type = val);
                    _nudgeUnitForType(val);
                  },
                  items: _typeOptions
                      .map((e) =>
                          DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                ),
                const SizedBox(height: 8),

                TextFormField(
                  controller: ogController,
                  decoration: _dec('Original Gravity (SG)'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 8),

                TextFormField(
                  controller: phController,
                  decoration: _dec('pH'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 10),

                const Divider(),
                const SizedBox(height: 10),

                // Cost (currency-aware)
                TextFormField(
                  controller: costController,
                  decoration: _dec('Total Cost', prefixText: '$symbol '),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
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

                // Purchase date
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Purchase: ${DateFormat.yMMMd().format(purchaseDate)}',
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
                        if (picked != null) {
                          setState(() => purchaseDate = picked);
                        }
                      },
                      child: const Text('Change'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Expiration date
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        expirationDate == null
                            ? 'Expiration: Not set'
                            : 'Expires: ${DateFormat.yMMMd().format(expirationDate!)}',
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
                        if (picked != null) {
                          setState(() => expirationDate = picked);
                        }
                      },
                      child: const Text('Set'),
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
            child: const Text('Add to Inventory'),
          ),
        TextButton(
          onPressed: () {
            widget.onAddToRecipe(buildIngredientEntry());
            Navigator.of(context).pop();
          },
          child: Text(isEditing ? 'Save Changes' : 'Add to Recipe'),
        ),
      ],
    );
  }
}
