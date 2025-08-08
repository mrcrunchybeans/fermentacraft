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
    this.existing,
    required UnitType unitType,
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
      expirationDate = f['expirationDate'];
    }
  }

  Map<String, dynamic> buildIngredientEntry() {
    final og = double.tryParse(ogController.text);
    final ph = double.tryParse(phController.text);
    final cost = double.tryParse(costController.text);

    return {
      'name': nameController.text.trim(),
      'amount': double.tryParse(amountController.text) ?? 0,
      'unit': amountUnit,
      'type': type,
      'og': og,
      'ph': ph,
      'cost': cost,
      'purchaseDate': purchaseDate,
      'expirationDate': expirationDate,
      'acidityClass': ph != null ? CiderUtils.classifyAcidity(ph) : null,
    };
  }

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

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;

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
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 96),
                      child: DropdownButtonFormField<String>(
                        isDense: true,
                        isExpanded: true, // fits inside the 96px box
                        value: amountUnit,
                        decoration: _dec('Unit'),
                        onChanged: (val) => setState(() => amountUnit = val!),
                        items: const [
                          'oz','g','lb','ml','l','gal','tsp','tbsp','package'
                        ].map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                DropdownButtonFormField<String>(
                  value: type,
                  decoration: _dec('Type'),
                  isDense: true,
                  onChanged: (val) => setState(() => type = val!),
                  items: const [
                    'Juice','Fruit','Sugar','Concentrate','Additive','Other'
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

                TextFormField(
                  controller: costController,
                  decoration: _dec('Total Cost (\$)'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
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
