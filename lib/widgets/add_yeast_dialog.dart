import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AddYeastDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final Function(Map<String, dynamic>) onAdd;
  final Function(Map<String, dynamic>)? onAddToInventory;

  const AddYeastDialog({
    super.key,
    this.existing,
    required this.onAdd,
    this.onAddToInventory,
  });

  @override
  State<AddYeastDialog> createState() => _AddYeastDialogState();
}

class _AddYeastDialogState extends State<AddYeastDialog> {
  final List<String> commonYeasts = [
    'Lalvin EC-1118',
    'Red Star Premier Blanc',
    'Safale US-05',
    'Wyeast 1056 American Ale',
    'Lalvin D-47',
    'Lalvin K1-V1116',
    'Nottingham Ale Yeast',
    'WLP001 California Ale',
    'Mangrove Jack’s M02 Cider',
    'Other (Custom)',
  ];

  String selectedYeast = 'Lalvin EC-1118';
  final TextEditingController customYeastController = TextEditingController();
  final TextEditingController amountController = TextEditingController();
  final TextEditingController costController = TextEditingController();
  DateTime purchaseDate = DateTime.now();
  DateTime? expirationDate; // State for expiration date
  String unit = 'packets';

@override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final yeast = widget.existing!;
      selectedYeast = commonYeasts.contains(yeast['name']) ? yeast['name'] : 'Other (Custom)';
      customYeastController.text = selectedYeast == 'Other (Custom)' ? yeast['name'] : '';
      amountController.text = yeast['amount']?.toString() ?? '';
      unit = yeast['unit'] ?? 'packets';
      costController.text = yeast['cost']?.toString() ?? '';

      // FIX: Safely handle dates that might be a String or a DateTime object
      final pDate = yeast['purchaseDate'];
      if (pDate is String) {
        purchaseDate = DateTime.tryParse(pDate) ?? DateTime.now();
      } else if (pDate is DateTime) {
        purchaseDate = pDate;
      } else {
        purchaseDate = DateTime.now();
      }

      final expDate = yeast['expirationDate'];
      if (expDate is String) {
        expirationDate = DateTime.tryParse(expDate);
      } else if (expDate is DateTime) {
        expirationDate = expDate;
      }
    }
  }

  Map<String, dynamic> buildYeastEntry() {
    final name = selectedYeast == 'Other (Custom)'
        ? customYeastController.text.trim()
        : selectedYeast;
    final amount = double.tryParse(amountController.text.trim()) ?? 0.0;
    final cost = double.tryParse(costController.text.trim()) ?? 0.0;

    return {
      'name': name,
      'amount': amount,
      'unit': unit,
      'cost': cost,
      'purchaseDate': purchaseDate,
      'expirationDate': expirationDate, // Include expiration date
    };
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditing = widget.existing != null;

    return AlertDialog(
      title: Text(isEditing ? "Edit Yeast" : "Add Yeast"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ... (Your existing Dropdowns and TextFormFields for name, amount, etc.)
            DropdownButtonFormField<String>(
              value: selectedYeast,
              items: commonYeasts
                  .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => selectedYeast = val);
                }
              },
              decoration: const InputDecoration(labelText: "Select Yeast"),
            ),
            if (selectedYeast == 'Other (Custom)')
              TextFormField(
                controller: customYeastController,
                decoration: const InputDecoration(labelText: "Custom Yeast Name"),
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: amountController,
              decoration: const InputDecoration(labelText: "Amount"),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
             DropdownButtonFormField<String>(
              value: unit,
              items: ['grams', 'packets']
                  .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => unit = val);
                }
              },
              decoration: const InputDecoration(labelText: "Unit"),
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
            // --- Expiration Date Picker ---
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
      actions: [
        // --- "Add to Inventory" Button ---
        // This button correctly calls the onAddToInventory callback, which saves to Hive.
        if (widget.onAddToInventory != null)
          TextButton(
            onPressed: () {
              final yeast = buildYeastEntry();
              widget.onAddToInventory!(yeast);
              Navigator.of(context).pop();
            },
            child: const Text("Add to Inventory"),
          ),
        
        // --- "Add to Recipe" Button ---
        // This button correctly calls the onAdd callback, which only updates the recipe screen.
        TextButton(
          onPressed: () {
            final yeast = buildYeastEntry();
            widget.onAdd(yeast);
            Navigator.of(context).pop();
          },
          child: Text(isEditing ? "Save Changes" : "Add"),
        ),
      ],
    );
  }
}
