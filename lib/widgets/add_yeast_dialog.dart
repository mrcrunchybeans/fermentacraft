import 'package:flutter/material.dart';

class AddYeastDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final Function(Map<String, dynamic>) onAdd;

  const AddYeastDialog({
    super.key,
    this.existing,
    required this.onAdd,
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
  String unit = 'packets';

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final yeast = widget.existing!;
      selectedYeast = commonYeasts.contains(yeast['name']) ? yeast['name'] : 'Other (Custom)';
      customYeastController.text = selectedYeast == 'Other (Custom)' ? yeast['name'] : '';
      amountController.text = yeast['amount']?.toString() ?? '';
      unit = yeast['unit'] ?? 'grams';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Add Yeast"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            final name = selectedYeast == 'Other (Custom)'
                ? customYeastController.text.trim()
                : selectedYeast;
            final amount = double.tryParse(amountController.text.trim()) ?? 0.0;

            widget.onAdd({
              'name': name,
              'amount': amount,
              'unit': unit,
            });

            Navigator.of(context).pop();
          },
          child: const Text("Save"),
        ),
      ],
    );
  }
}
